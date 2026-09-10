package com.sethikadv.snazy

import android.content.Context

/**
 * Real touch-response tuning — root or Shizuku only, same privilege model
 * as GameBoostManager. Two things actually change on the device:
 *
 *  1. `long_press_timeout` / `multi_press_timeout` (Settings.Secure) — the
 *     real framework values Android's own input pipeline (ViewConfiguration)
 *     reads to decide how long a finger has to stay down before a touch is
 *     recognised as a long-press instead of a tap, and how long between taps
 *     still counts as one gesture. Lower values make every tap register
 *     sooner. These require WRITE_SECURE_SETTINGS, which normal apps never
 *     get — exactly what root/Shizuku shell access provides.
 *  2. A best-effort sweep of the handful of publicly-known vendor sysfs
 *     "game mode" / touch-sampling-boost nodes that OEM Game Turbo tools
 *     use (MediaTek/Xiaomi/OnePlus-style touch panels). Written only if the
 *     node actually exists on this device — silently skipped otherwise.
 *     Snazy never claims this changes anything on a device that doesn't
 *     expose one of these nodes.
 *
 * There is no public, non-privileged Android API for either action, so —
 * same as everywhere else in this app — there is no non-root/non-Shizuku
 * fallback for touch optimization; the UI is honest about that.
 */
object TouchOptimizer {

    private const val PREFS = "snazy_touch_state"

    // Real, publicly documented vendor "game mode" touch nodes used by
    // various OEM Game Turbo/GameSpace tools. Only ever written if present.
    private val VENDOR_GAME_NODES = listOf(
        "/proc/touchpanel/game_switch_enable",
        "/sys/kernel/touchpanel/game_switch_enable",
        "/sys/class/touch/touch_dev/game_mode",
        "/sys/devices/virtual/touch/tp_dev/game_mode",
        "/proc/touchpanel/oplus_tp_direction"
    )

    private val SETTINGS_KEYS = listOf("long_press_timeout", "multi_press_timeout")

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Captures the device's real current values once, so Restore has a true baseline. */
    fun captureBaselineIfNeeded(context: Context, readSecureSetting: (String) -> String?) {
        val p = prefs(context)
        if (p.getBoolean("captured", false)) return
        val editor = p.edit()
        for (key in SETTINGS_KEYS) {
            val value = readSecureSetting(key)?.trim()
            val fallback = if (key == "long_press_timeout") "500" else "300"
            editor.putString("orig_$key", if (value.isNullOrEmpty() || value == "null") fallback else value)
        }
        editor.putBoolean("captured", true)
        editor.apply()
    }

    /**
     * Maps [sensitivity] (0-100, higher = snappier) onto real millisecond
     * timeouts. Clamped to a range that keeps long-press/double-tap gesture
     * detection actually usable — going lower doesn't make Android faster,
     * it just breaks gesture recognition, so Snazy doesn't offer that.
     */
    private fun longPressMs(sensitivity: Int): Int {
        val s = sensitivity.coerceIn(0, 100)
        return (500 - (s / 100.0 * 350)).toInt().coerceIn(150, 500) // 500ms..150ms
    }

    private fun multiPressMs(sensitivity: Int): Int {
        val s = sensitivity.coerceIn(0, 100)
        return (300 - (s / 100.0 * 200)).toInt().coerceIn(100, 300) // 300ms..100ms
    }

    /** Shortens tap/long-press recognition delay and enables any real vendor touch-boost node found. */
    fun buildApplyCommand(sensitivity: Int): String {
        val sb = StringBuilder()
        sb.append("settings put secure long_press_timeout ${longPressMs(sensitivity)} 2>/dev/null; ")
        sb.append("settings put secure multi_press_timeout ${multiPressMs(sensitivity)} 2>/dev/null; ")
        for (node in VENDOR_GAME_NODES) {
            sb.append("[ -f $node ] && echo 1 > $node 2>/dev/null; ")
        }
        return sb.toString()
    }

    /** Restores exactly what was captured, and turns off any vendor node this device has. */
    fun buildRestoreCommand(context: Context): String {
        val p = prefs(context)
        val sb = StringBuilder()
        for (key in SETTINGS_KEYS) {
            val fallback = if (key == "long_press_timeout") "500" else "300"
            val orig = p.getString("orig_$key", fallback)
            sb.append("settings put secure $key $orig 2>/dev/null; ")
        }
        for (node in VENDOR_GAME_NODES) {
            sb.append("[ -f $node ] && echo 0 > $node 2>/dev/null; ")
        }
        return sb.toString()
    }
}
