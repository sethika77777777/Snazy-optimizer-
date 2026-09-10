import 'package:flutter/services.dart';

/// Everything here calls into real Android code (MainActivity.kt /
/// ShizukuManager.kt / PerformanceManager.kt) because Dart alone cannot:
/// detect root, run su/Shizuku commands, or read system-wide CPU/RAM
/// without going through the Android APIs / proc filesystem. There is no
/// simulated data in this file — every method either returns a real value
/// from the device or throws/returns a clear failure.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('snazy/native');

  // ---------------- Root ----------------

  /// Detects an existing su binary / Magisk. Cannot install root — Android
  /// does not allow any app to root a device from inside itself.
  static Future<bool> isRooted() async {
    try {
      return (await _channel.invokeMethod<bool>('isRooted')) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Shizuku (root-equivalent access without rooting) ----------------

  /// Real, live snapshot of what privilege Snazy currently has:
  /// { rooted, shizukuInstalled, shizukuBinderAlive, shizukuGranted,
  ///   shizukuUid, mode: "root"|"shizuku"|"none" }
  static Future<Map<String, dynamic>> getPrivilegeState() async {
    try {
      final result = await _channel.invokeMethod('getPrivilegeState');
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return {
        'rooted': false,
        'shizukuInstalled': false,
        'shizukuBinderAlive': false,
        'shizukuGranted': false,
        'shizukuUid': -1,
        'mode': 'none',
      };
    }
  }

  /// Shows the real Shizuku permission dialog. Only meaningful once the
  /// user has installed and started Shizuku — returns false otherwise.
  static Future<bool> requestShizukuPermission() async {
    try {
      return (await _channel.invokeMethod<bool>('requestShizukuPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the installed Shizuku app so the user can tap "Start".
  static Future<bool> openShizukuApp() async {
    try {
      return (await _channel.invokeMethod<bool>('openShizukuApp')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Shizuku's real Play Store listing for users who don't have it yet.
  static Future<void> openShizukuPlayStore() async {
    try {
      await _channel.invokeMethod('openShizukuPlayStore');
    } catch (_) {}
  }

  // ---------------- Device stats ----------------

  /// Real device-wide RAM info from ActivityManager.MemoryInfo.
  static Future<Map<String, dynamic>> getRamInfo() async {
    final result = await _channel.invokeMethod('getRamInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Real aggregate CPU usage % sampled from /proc/stat over ~350ms.
  /// Returns -1 if the device/OEM blocks /proc/stat for apps — the UI
  /// must handle that case rather than fake a number.
  static Future<double> getCpuUsage() async {
    return (await _channel.invokeMethod<double>('getCpuUsage')) ?? -1.0;
  }

  /// Real battery level + charging state from BatteryManager.
  static Future<Map<String, dynamic>> getBatteryInfo() async {
    final result = await _channel.invokeMethod('getBatteryInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Opens the real Android "Ignore battery optimizations" settings screen
  /// for a given package — the only legitimate non-root way to ask the OS
  /// to stop throttling an app in the background.
  static Future<void> openBatteryOptimizationSettings(String pkg) async {
    await _channel.invokeMethod('openBatteryOptSettings', {'pkg': pkg});
  }

  /// Reads back the current CPU governor (e.g. "schedutil", "performance")
  /// directly from sysfs — no privilege needed to read it.
  static Future<String> currentGovernor() async {
    try {
      return (await _channel.invokeMethod<String>('currentGovernor')) ?? '--';
    } catch (_) {
      return '--';
    }
  }

  // ---------------- Profiles ----------------

  /// Applies one of the four profiles. Returns the real, verified result —
  /// PerformanceManager reads every value back after writing it, so
  /// `success` reflects what actually changed on the device, not a guess.
  static Future<Map<String, dynamic>> applyProfile(String profileId) async {
    try {
      final result =
          await _channel.invokeMethod('applyProfile', {'profileId': profileId});
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      return {
        'profile': profileId,
        'success': false,
        'message': 'Could not reach the device — try again.',
      };
    }
  }

  // ---------------- Background freeze (force-stop, never disable) ----------------

  /// One immediate sweep of [pkgs] — used at Boost time. Returns
  /// { mode: "privileged"|"basic", stopped: int }.
  static Future<Map<String, dynamic>> runFreezeSweep(List<String> pkgs) async {
    try {
      final result =
          await _channel.invokeMethod('runFreezeSweep', {'pkgs': pkgs});
      return Map<String, dynamic>.from(result as Map);
    } catch (_) {
      return {'mode': 'basic', 'stopped': 0};
    }
  }

  /// Starts the detached, privileged polling loop that keeps [pkgs]
  /// stopped in the background until [stopFreezeLoop] is called. Requires
  /// root or a granted Shizuku session — returns false otherwise.
  static Future<bool> startFreezeLoop(List<String> pkgs) async {
    try {
      return (await _channel
              .invokeMethod<bool>('startFreezeLoop', {'pkgs': pkgs})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Removes the freeze flag file — every app Snazy stopped is free to run
  /// normally again immediately. Nothing was ever disabled, so there is
  /// nothing to "re-enable".
  static Future<bool> stopFreezeLoop() async {
    try {
      return (await _channel.invokeMethod<bool>('stopFreezeLoop')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Non-root, non-Shizuku fallback: ActivityManager#killBackgroundProcesses
  /// per package. Real API, weaker effect — Android limits what it's
  /// allowed to reap without privilege.
  static Future<int> killBackgroundProcesses(List<String> pkgs) async {
    try {
      return (await _channel
              .invokeMethod<int>('killBackgroundProcesses', {'pkgs': pkgs})) ??
          0;
    } catch (_) {
      return 0;
    }
  }

  // ---------------- Game boost: real FPS-targeting actions ----------------
  //
  // Separate from applyProfile: governor/clock unlocking stops the chip
  // being artificially slow, this actually raises the frame ceiling by
  // cutting compositor overhead and pinning the game's threads onto the
  // fast cores with elevated scheduling priority. Root or Shizuku only.

  /// Zeroes animation scales, forces GPU rendering, and starts the
  /// detached loop that keeps pinning [gamePkg]'s process + threads into
  /// the top-app cpuset with raised scheduling priority. Returns false
  /// (no-op) without root/Shizuku — there is no public API for either
  /// action, so Snazy doesn't pretend to apply it.
  static Future<bool> applyGameBoost(String gamePkg) async {
    try {
      return (await _channel
              .invokeMethod<bool>('applyGameBoost', {'pkg': gamePkg})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Stops the thread-priority loop and restores animation/GPU render
  /// settings to exactly what was captured before boosting.
  static Future<bool> stopGameBoost() async {
    try {
      return (await _channel.invokeMethod<bool>('stopGameBoost')) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---------------- Touch response optimization ----------------
  //
  // Shortens real tap/long-press recognition timeouts (Settings.Secure) and
  // sweeps known vendor touch-boost sysfs nodes best-effort. Root or
  // Shizuku only — WRITE_SECURE_SETTINGS isn't grantable to a normal app.

  static Future<bool> applyTouchOptimization(int sensitivity) async {
    try {
      return (await _channel.invokeMethod<bool>(
              'applyTouchOptimization', {'sensitivity': sensitivity})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> stopTouchOptimization() async {
    try {
      return (await _channel.invokeMethod<bool>('stopTouchOptimization')) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Runs one arbitrary command through root-or-Shizuku, whichever is
  /// available. Used sparingly — most flows have a dedicated method above.
  static Future<bool> runPrivilegedCommand(String cmd) async {
    try {
      return (await _channel
              .invokeMethod<bool>('runPrivilegedCommand', {'cmd': cmd})) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
