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
 * Every method here does a real, verifiable thing on the device.
 * Nothing in this file returns a hard-coded or simulated value.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "snazy/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRooted" -> result.success(checkRoot())
                    "runRootCommand" -> {
                        val cmd = call.argument<String>("cmd") ?: ""
                        result.success(runAsRoot(cmd))
                    }
                    "getRamInfo" -> result.success(getRamInfo())
                    "getCpuUsage" -> result.success(getCpuUsage())
                    "getBatteryInfo" -> result.success(getBatteryInfo())
                    "openBatteryOptSettings" -> {
                        val pkg = call.argument<String>("pkg") ?: ""
                        openBatteryOptSettings(pkg)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Checks for common su binary locations, then falls back to actually
     * invoking `which su`. This detects existing root; it can never grant
     * root — no app can do that on Android.
     */
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

    /**
     * Runs a single command through a real su shell. The first call on a
     * device triggers the actual Magisk/SuperSU grant dialog — this is not
     * simulated, and it will genuinely fail (return false) if the user
     * denies it or root isn't present.
     */
    private fun runAsRoot(command: String): Boolean {
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

    /** Real device-wide RAM figures from ActivityManager — no root needed. */
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
     * NOTE: some OEMs (particularly some Android 12+ builds) restrict
     * /proc/stat via SELinux for non-system apps. When that happens this
     * throws/returns -1 rather than fabricating a percentage — the Dart
     * side displays "--" in that case.
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

    /** Real battery level + charging state from BatteryManager. */
    private fun getBatteryInfo(): Map<String, Any> {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        val status = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_STATUS)
        return mapOf(
            "level" to level,
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING)
        )
    }

    /**
     * Opens the real system "Ignore battery optimizations" screen for a
     * package. This is the only legitimate non-root way to ask Android to
     * stop background-throttling an app.
     */
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
            // If the OEM blocks this intent, there is nothing more we can
            // legitimately do without root — fail silently rather than
            // pretend it worked.
        }
    }
}
