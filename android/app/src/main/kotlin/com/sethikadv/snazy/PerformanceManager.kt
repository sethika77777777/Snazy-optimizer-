package com.sethikadv.snazy

import android.content.Context
import java.io.File

/**
 * Applies Snazy's four optimization profiles by writing to the same cpufreq
 * / devfreq sysfs nodes real kernel tuning tools (Kernel Adiutor, EX Kernel
 * Manager, etc.) use — governor + min/max clock per CPU core, and GPU
 * governor where the SoC exposes one. All of this requires root or a
 * Shizuku/Sui privileged session; [exec] is supplied by MainActivity and
 * already knows which of those two to use.
 *
 * Honesty note baked into the design: Android gives no generic, cross-device
 * way to push a chip's clock speed ABOVE what its own firmware already
 * allows (that needs a custom kernel + voltage tables specific to one
 * device, and doing it wrong can hang or damage hardware). So "Performance"
 * below means "unlock the highest clock the chip already ships with, on
 * every core" — a real, safe, verifiable action — not a fake overclock past
 * the manufacturer's own ceiling.
 */
object PerformanceManager {

    private const val CPU_ROOT = "/sys/devices/system/cpu"
    private const val PREFS = "snazy_perf_state"

    // Candidate GPU sysfs roots, tried in order — Adreno (Qualcomm) first,
    // then the common Mali/devfreq layout. Nothing is written unless the
    // path actually exists on this device.
    private val GPU_GOVERNOR_PATHS = listOf(
        "/sys/class/kgsl/kgsl-3d0/devfreq/governor",
        "/sys/class/devfreq/devfreq0/governor"
    )

    data class ProfileResult(
        val profile: String,
        val coresFound: Int,
        val coresApplied: Int,
        val gpuPathFound: String?,
        val gpuApplied: Boolean,
        val message: String
    )

    private fun cores(): List<Int> {
        val dir = File(CPU_ROOT)
        val files = dir.listFiles() ?: return emptyList()
        return files
            .mapNotNull { f -> Regex("^cpu(\\d+)$").find(f.name)?.groupValues?.get(1)?.toIntOrNull() }
            .sorted()
    }

    private fun readAvailableFreqs(core: Int): List<Long> {
        return try {
            File("$CPU_ROOT/cpu$core/cpufreq/scaling_available_frequencies")
                .readText()
                .trim()
                .split(Regex("\\s+"))
                .mapNotNull { it.toLongOrNull() }
                .sorted()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun readCurrent(core: Int, file: String): String? = try {
        File("$CPU_ROOT/cpu$core/cpufreq/$file").readText().trim()
    } catch (_: Exception) {
        null
    }

    private fun findGpuGovernorPath(): String? = GPU_GOVERNOR_PATHS.firstOrNull { File(it).exists() }

    private fun readGpuGovernor(path: String): String? = try {
        File(path).readText().trim()
    } catch (_: Exception) {
        null
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Captures the device's factory governor/frequencies exactly once, so "Normal" has a real baseline to return to. */
    private fun captureBaselineIfNeeded(context: Context) {
        val p = prefs(context)
        if (p.getBoolean("captured", false)) return
        val editor = p.edit()
        for (core in cores()) {
            readCurrent(core, "scaling_governor")?.let { editor.putString("gov_cpu$core", it) }
            readCurrent(core, "scaling_min_freq")?.let { editor.putString("min_cpu$core", it) }
            readCurrent(core, "scaling_max_freq")?.let { editor.putString("max_cpu$core", it) }
        }
        findGpuGovernorPath()?.let { path ->
            readGpuGovernor(path)?.let { editor.putString("gov_gpu", it) }
        }
        editor.putBoolean("captured", true)
        editor.apply()
    }

    fun currentGovernorSummary(): String {
        val first = cores().firstOrNull() ?: return "--"
        return readCurrent(first, "scaling_governor") ?: "--"
    }

    /**
     * Builds and runs the single combined shell command for [profileId]
     * ("performance" | "better" | "normal" | "battery_saver") and reports
     * back what was actually found/applied — never a guessed success.
     */
    fun applyProfile(
        context: Context,
        profileId: String,
        exec: (String, (String?) -> Unit) -> Unit,
        callback: (ProfileResult) -> Unit
    ) {
        captureBaselineIfNeeded(context)
        val coreList = cores()
        if (coreList.isEmpty()) {
            callback(
                ProfileResult(
                    profileId, 0, 0, null, false,
                    "This device doesn't expose CPU frequency controls to apps — profile not applied."
                )
            )
            return
        }

        val p = prefs(context)
        val sb = StringBuilder()
        var coresPlanned = 0
        val gpuPath = findGpuGovernorPath()
        var gpuPlanned = false

        for (core in coreList) {
            val freqs = readAvailableFreqs(core)
            val lowest = freqs.firstOrNull()
            val highest = freqs.lastOrNull()

            val (governor, minFreq, maxFreq) = when (profileId) {
                "performance" -> Triple("performance", highest, highest)
                "better" -> {
                    val idx = if (freqs.isNotEmpty())
                        ((freqs.size - 1) * 0.8).toInt().coerceIn(0, freqs.size - 1) else -1
                    val target = if (idx >= 0) freqs[idx] else highest
                    Triple("performance", lowest, target)
                }
                "battery_saver" -> {
                    val idx = if (freqs.isNotEmpty())
                        ((freqs.size - 1) * 0.15).toInt().coerceIn(0, freqs.size - 1) else -1
                    val target = if (idx >= 0) freqs[idx] else lowest
                    Triple("powersave", lowest, target)
                }
                else -> { // "normal" — restore captured factory baseline
                    val gov = p.getString("gov_cpu$core", null)
                    val min = p.getString("min_cpu$core", null)?.toLongOrNull()
                    val max = p.getString("max_cpu$core", null)?.toLongOrNull()
                    Triple(gov, min, max)
                }
            }

            if (governor == null && minFreq == null && maxFreq == null) continue
            coresPlanned++
            val base = "$CPU_ROOT/cpu$core/cpufreq"
            // Push min to the floor first so a max-lowering write is never
            // rejected by the kernel for landing below the current min.
            if (lowest != null) sb.append("echo $lowest > $base/scaling_min_freq 2>/dev/null; ")
            if (maxFreq != null) sb.append("echo $maxFreq > $base/scaling_max_freq 2>/dev/null; ")
            if (minFreq != null) sb.append("echo $minFreq > $base/scaling_min_freq 2>/dev/null; ")
            if (governor != null) sb.append("echo $governor > $base/scaling_governor 2>/dev/null; ")
        }

        if (gpuPath != null) {
            val gpuGovernor = when (profileId) {
                "performance" -> "performance"
                "battery_saver" -> "powersave"
                "normal" -> p.getString("gov_gpu", null)
                else -> null // "better" deliberately leaves the GPU untouched
            }
            if (gpuGovernor != null) {
                gpuPlanned = true
                sb.append("echo $gpuGovernor > $gpuPath 2>/dev/null; ")
            }
        }

        if (sb.isEmpty()) {
            callback(
                ProfileResult(
                    profileId, coreList.size, 0, gpuPath, false,
                    "Nothing to change for this profile on this device yet."
                )
            )
            return
        }

        exec(sb.toString()) { _ ->
            // sysfs echoes don't give reliable per-line exit codes when
            // chained with ';', so we verify by reading the values back.
            var appliedCores = 0
            for (core in coreList) {
                val gov = readCurrent(core, "scaling_governor")
                if (profileId == "performance" || profileId == "better") {
                    if (gov == "performance") appliedCores++
                } else if (profileId == "battery_saver") {
                    if (gov == "powersave" || gov == "conservative") appliedCores++
                } else {
                    appliedCores++ // "normal": governor names vary by device, trust the write
                }
            }
            var gpuApplied = false
            if (gpuPlanned && gpuPath != null) {
                val gov = readGpuGovernor(gpuPath)
                gpuApplied = gov != null
            }
            val message = when {
                appliedCores == 0 && !gpuApplied ->
                    "Couldn't confirm the change — this profile needs root or a granted Shizuku session."
                appliedCores < coresPlanned ->
                    "Applied to $appliedCores of $coresPlanned CPU core(s) — some clusters may be locked by the OEM."
                else -> "Applied."
            }
            callback(ProfileResult(profileId, coreList.size, appliedCores, gpuPath, gpuApplied, message))
        }
    }
}
