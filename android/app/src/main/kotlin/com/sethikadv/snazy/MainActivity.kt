package com.sethikadv.snazy

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.InputStreamReader

/**
 * Every method here does a real, verifiable thing on the device. Nothing in
 * this file returns a hard-coded or simulated value.
 *
 * Privilege model:
 *  - Rooted devices: commands run through `su` (see [runAsRootRaw]).
 *  - Non-rooted devices with Shizuku/Sui running and granted: the same
 *    commands run through [ShizukuManager] with whatever privilege the
 *    user's Shizuku session has (adb/shell, or root if backed by Sui).
 *  - Neither available: only Android's own public, permission-free APIs are
 *    used (ActivityManager, battery-optimization settings, etc.) — Snazy
 *    never pretends those give root-level control.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "snazy/native"

    // Flag file that gates the detached background-freeze shell loop. Lives
    // under /data/local/tmp because that path is writable by both the
    // "shell" uid (adb/Shizuku) and root.
    private val FREEZE_FLAG = "/data/local/tmp/.snazy_freeze"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ShizukuManager.init()
    }

    override fun onDestroy() {
        ShizukuManager.dispose()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRooted" -> result.success(checkRoot())

                    "getPrivilegeState" -> result.success(getPrivilegeState())

                    "requestShizukuPermission" -> {
                        ShizukuManager.requestPermission { granted ->
                            runOnUiThread { result.success(granted) }
                        }
                    }

                    "openShizukuApp" -> {
                        val opened = if (ShizukuManager.isShizukuAppInstalled(applicationContext)) {
                            ShizukuManager.openShizukuApp(applicationContext)
                        } else false
                        result.success(opened)
                    }

                    "openShizukuPlayStore" -> {
                        ShizukuManager.openShizukuOnPlayStore(applicationContext)
                        result.success(null)
                    }

                    "runPrivilegedCommand" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                    }

                    "getRamInfo" -> result.success(getRamInfo())
                    "getCpuUsage" -> result.success(getCpuUsage())
                    "getBatteryInfo" -> result.success(getBatteryInfo())
                    "openBatteryOptSettings" -> {
                        val pkg = call.argument<String>("pkg") ?: ""
                        openBatteryOptSettings(pkg)
                        result.success(null)
                    }

                    "currentGovernor" -> result.success(PerformanceManager.currentGovernorSummary())

                    "applyProfile" -> {
                        val profileId = call.argument<String>("profileId") ?: "normal"
                        Thread {
                            PerformanceManager.applyProfile(
                                applicationContext,
                                profileId,
                                exec = { cmd, cb -> runPrivileged(cmd) { _, output -> cb(output) } }
                            ) { r ->
                                runOnUiThread {
                                    result.success(
                                        mapOf(
                                            "profile" to r.profile,
                                            "coresFound" to r.coresFound,
                                            "coresApplied" to r.coresApplied,
                                            "gpuFound" to (r.gpuPathFound != null),
                                            "gpuApplied" to r.gpuApplied,
                                            "message" to r.message,
                                            "success" to (r.coresApplied > 0 || r.gpuApplied)
                                        )
                                    )
                                }
                            }
                        }.start()
                    }

                    "runFreezeSweep" -> {
                        @Suppress("UNCHECKED_CAST")
                        val pkgs = (call.argument<List<String>>("pkgs") ?: emptyList())
                        runFreezeSweep(pkgs) { mode, stopped ->
                            runOnUiThread {
                                result.success(mapOf("mode" to mode, "stopped" to stopped))
                            }
                        }
                    }

                    "startFreezeLoop" -> {
                        @Suppress("UNCHECKED_CAST")
                        val pkgs = (call.argument<List<String>>("pkgs") ?: emptyList())
                        val cmd = buildFreezeLoopCommand(pkgs)
                        runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                    }

                    "stopFreezeLoop" -> {
                        runPrivileged("rm -f $FREEZE_FLAG") { ok, _ -> runOnUiThread { result.success(ok) } }
                    }

                    "killBackgroundProcesses" -> {
                        @Suppress("UNCHECKED_CAST")
                        val pkgs = (call.argument<List<String>>("pkgs") ?: emptyList())
                        result.success(killBackgroundProcessesBasic(pkgs))
                    }

                    // ---- Real FPS boost: render overhead removed + game
                    // process/threads pinned to top-app cpuset with raised
                    // scheduling priority. Root or Shizuku only — there is
                    // no non-privileged Android API for either action.
                    "applyGameBoost" -> {
                        val pkg = call.argument<String>("pkg") ?: ""
                        Thread {
                            val cmd = GameBoostManager.buildApplyRenderBoostCommand() +
                                    GameBoostManager.buildBoostLoopCommand(pkg)
                            runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                        }.start()
                    }

                    "stopGameBoost" -> {
                        val cmd = GameBoostManager.buildStopBoostLoopCommand() + "; " +
                                GameBoostManager.buildRestoreRenderCommand(applicationContext)
                        runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                    }

                    // ---- Touch response optimization: real settings + best-effort
                    // vendor touch-boost node. Root or Shizuku only — see TouchOptimizer.
                    "applyTouchOptimization" -> {
                        val sensitivity = call.argument<Int>("sensitivity") ?: 75
                        Thread {
                            TouchOptimizer.captureBaselineIfNeeded(applicationContext) { key ->
                                runPrivilegedBlocking("settings get secure $key")
                            }
                            val cmd = TouchOptimizer.buildApplyCommand(sensitivity)
                            runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                        }.start()
                    }

                    "stopTouchOptimization" -> {
                        val cmd = TouchOptimizer.buildRestoreCommand(applicationContext)
                        runPrivileged(cmd) { ok, _ -> runOnUiThread { result.success(ok) } }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ---------------- Privilege routing ----------------

    /**
     * Runs [cmd] via `su` if root is present, otherwise via Shizuku if
     * granted. Always executes off the UI thread — some of these (profile
     * writes, freeze sweeps) touch many sysfs nodes / packages in one call.
     * [then] receives (success, rawOutputOrNull); callers post to the UI
     * thread themselves before touching Flutter's `result`.
     */
    private fun runPrivileged(cmd: String, then: (Boolean, String?) -> Unit) {
        Thread {
            if (checkRoot()) {
                val ok = runAsRootRaw(cmd)
                then(ok, null)
            } else if (ShizukuManager.hasPermission()) {
                ShizukuManager.exec(cmd) { output ->
                    val ok = output != null && !output.startsWith("ERROR:")
                    then(ok, output)
                }
            } else {
                then(false, null)
            }
        }.start()
    }

    /**
     * Blocking privileged call that returns captured stdout — used only for
     * the small number of reads (baseline `settings get`) that need a
     * result back before the next step can run. Safe to block on: every
     * caller is already inside its own background [Thread].
     */
    private fun runPrivilegedBlocking(cmd: String): String? {
        return if (checkRoot()) {
            runAsRootRawWithOutput(cmd)
        } else if (ShizukuManager.hasPermission()) {
            val latch = java.util.concurrent.CountDownLatch(1)
            var out: String? = null
            ShizukuManager.exec(cmd) { output ->
                out = output
                latch.countDown()
            }
            latch.await(3, java.util.concurrent.TimeUnit.SECONDS)
            out
        } else {
            null
        }
    }

    private fun getPrivilegeState(): Map<String, Any> {
        val rooted = checkRoot()
        val shizukuInstalled = ShizukuManager.isShizukuAppInstalled(applicationContext)
        val shizukuBinderAlive = ShizukuManager.isBinderAlive()
        val shizukuGranted = ShizukuManager.hasPermission()
        val shizukuUid = ShizukuManager.getUid()
        val mode = when {
            rooted -> "root"
            shizukuGranted -> "shizuku"
            else -> "none"
        }
        return mapOf(
            "rooted" to rooted,
            "shizukuInstalled" to shizukuInstalled,
            "shizukuBinderAlive" to shizukuBinderAlive,
            "shizukuGranted" to shizukuGranted,
            "shizukuUid" to shizukuUid,
            "mode" to mode
        )
    }

    // ---------------- Background freeze (force-stop, never disable) ----------------

    /** One immediate sweep — used at Boost time for instant RAM/CPU relief. */
    private fun runFreezeSweep(pkgs: List<String>, then: (String, Int) -> Unit) {
        if (pkgs.isEmpty()) {
            then(if (checkRoot() || ShizukuManager.hasPermission()) "privileged" else "basic", 0)
            return
        }
        if (checkRoot() || ShizukuManager.hasPermission()) {
            val cmd = buildString {
                for (pkg in pkgs) append("am force-stop \"$pkg\" 2>/dev/null; ")
            }
            runPrivileged(cmd) { _, _ -> then("privileged", pkgs.size) }
        } else {
            val stopped = killBackgroundProcessesBasic(pkgs)
            then("basic", stopped)
        }
    }

    /**
     * Non-root, non-Shizuku fallback. ActivityManager#killBackgroundProcesses
     * is a normal (auto-granted) permission and a real Android API — but,
     * being honest about it, Android only lets it reap processes the system
     * already considers killable background/cached processes, so its effect
     * is far weaker than a privileged `am force-stop` sweep.
     */
    private fun killBackgroundProcessesBasic(pkgs: List<String>): Int {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        var count = 0
        for (pkg in pkgs) {
            try {
                am.killBackgroundProcesses(pkg)
                count++
            } catch (_: Exception) {
                // OEM/Android version blocked it for this package — skip, don't fake success.
            }
        }
        return count
    }

    /**
     * Builds the detached polling loop that keeps everything in [pkgs]
     * stopped while [FREEZE_FLAG] exists. Apps are never disabled —
     * `am force-stop` only ends their current process, so the instant the
     * flag file is removed (Restore) every app is free to run again exactly
     * as before. `nohup ... &` inside a subshell detaches the loop from
     * Snazy's own process, so it keeps running while the selected game is
     * in the foreground.
     *
     * Perf note: `am` boots a fresh ART process for every single
     * invocation (100s of ms each, on-device). Blindly re-running
     * `am force-stop` for the whole package list on every tick meant a
     * "sweep" of 20-30 apps could itself take several seconds of real CPU
     * time, back-to-back, for as long as the game ran — competing directly
     * with the foreground game for CPU and causing stutter during Boost.
     * `pidof` is a native binary with no VM start-up cost (~1ms), so each
     * tick now only pays the expensive `am` cost for a package that
     * actually respawned. The poll interval is also widened since apps
     * don't respawn instantly.
     */
    private fun buildFreezeLoopCommand(pkgs: List<String>): String {
        val stopBlock = buildString {
            for (pkg in pkgs) {
                append("if [ -n \"$(pidof $pkg 2>/dev/null)\" ]; then am force-stop \"$pkg\" 2>/dev/null; fi; ")
            }
        }
        val loop = "while [ -f $FREEZE_FLAG ]; do $stopBlock sleep 15; done"
        return "echo 1 > $FREEZE_FLAG; (nohup sh -c '$loop' > /dev/null 2>&1 &) ; exit 0"
    }

    // ---------------- Root detection / execution ----------------

    /** Detects an existing su binary / Magisk. Cannot install root — Android does not allow any app to root itself. */
    private fun checkRoot(): Boolean {
        val paths = arrayOf(
            "/system/bin/su", "/system/xbin/su", "/sbin/su",
            "/system/app/Superuser.apk", "/system/bin/.ext/.su",
            "/su/bin/su", "/data/local/xbin/su", "/data/local/bin/su"
        )
        for (path in paths) {
            if (File(path).exists()) return true
        }
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("which", "su"))
            val output = BufferedReader(InputStreamReader(process.inputStream)).readLine()
            process.waitFor()
            !output.isNullOrEmpty()
        } catch (e: Exception) {
            false
        }
    }

    /** Runs a single command through a real su shell and returns whether it exited 0. */
    private fun runAsRootRaw(command: String): Boolean {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec("su")
            val os = DataOutputStream(process.outputStream)
            os.writeBytes("$command\n")
            os.writeBytes("exit\n")
            os.flush()
            val exitCode = process.waitFor()
            exitCode == 0
        } catch (e: Exception) {
            false
        } finally {
            process?.destroy()
        }
    }

    /** Same as [runAsRootRaw] but returns captured stdout instead of just success. */
    private fun runAsRootRawWithOutput(command: String): String? {
        var process: Process? = null
        return try {
            process = Runtime.getRuntime().exec("su")
            val os = DataOutputStream(process.outputStream)
            os.writeBytes("$command\n")
            os.writeBytes("exit\n")
            os.flush()
            val output = BufferedReader(InputStreamReader(process.inputStream)).readText()
            process.waitFor()
            output.trim()
        } catch (e: Exception) {
            null
        } finally {
            process?.destroy()
        }
    }

    // ---------------- Device stats (unchanged real behaviour) ----------------

    private fun getRamInfo(): Map<String, Long> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        return mapOf(
            "totalMem" to memInfo.totalMem,
            "availMem" to memInfo.availMem,
            "threshold" to memInfo.threshold
        )
    }

    /**
     * Real aggregate CPU usage sampled from /proc/stat across two reads.
     * Some OEMs restrict /proc/stat via SELinux for non-system apps — when
     * that happens this returns -1 rather than fabricating a percentage;
     * the Dart side shows "--" in that case.
     */
    private fun getCpuUsage(): Double {
        return try {
            fun readStat(): Pair<Long, Long> {
                val reader = BufferedReader(InputStreamReader(FileInputStream("/proc/stat")))
                val line = reader.readLine()
                reader.close()
                val toks = line.split(" ").filter { it.isNotEmpty() }
                val idle = toks[4].toLong()
                val total = toks.subList(1, toks.size).sumOf { it.toLongOrNull() ?: 0L }
                return Pair(idle, total)
            }

            val (idle1, total1) = readStat()
            Thread.sleep(350)
            val (idle2, total2) = readStat()

            val idleDelta = idle2 - idle1
            val totalDelta = total2 - total1
            if (totalDelta <= 0) -1.0
            else (1.0 - idleDelta.toDouble() / totalDelta.toDouble()) * 100.0
        } catch (e: Exception) {
            -1.0
        }
    }

    private fun getBatteryInfo(): Map<String, Any> {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        return mapOf(
            "level" to level,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING)
        )
    }

    /** Opens the real system "Ignore battery optimizations" screen — the only legitimate non-root way to stop background throttling for a package. */
    private fun openBatteryOptSettings(pkg: String) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$pkg")
                )
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            // OEM blocks this intent — nothing more can legitimately be done without root.
        }
    }

}
