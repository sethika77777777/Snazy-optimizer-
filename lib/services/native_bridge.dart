import 'package:flutter/services.dart';

/// Everything here calls into real Android code (MainActivity.kt) because
/// Dart alone cannot: detect root, run su commands, or read system-wide
/// CPU/RAM without going through the Android APIs / proc filesystem.
/// There is no simulated data in this file — every method either returns
/// a real value from the device or throws/returns a clear failure.
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('snazy/native');

  /// Detects an existing su binary / Magisk. Cannot install root — Android
  /// does not allow any app to root a device from inside itself.
  static Future<bool> isRooted() async {
    try {
      return (await _channel.invokeMethod<bool>('isRooted')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Runs a single shell command as root (e.g. "pm disable-user --user 0 pkg").
  /// Triggers the Magisk/SuperSU grant popup the first time it's called.
  static Future<bool> runRootCommand(String cmd) async {
    try {
      return (await _channel
              .invokeMethod<bool>('runRootCommand', {'cmd': cmd})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Real device-wide RAM info from ActivityManager.MemoryInfo.
  static Future<Map<String, dynamic>> getRamInfo() async {
    final result = await _channel.invokeMethod('getRamInfo');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Real aggregate CPU usage % sampled from /proc/stat over ~350ms.
  /// Returns -1 if the device/OEM blocks /proc/stat for apps (some do,
  /// especially Android 12+ with tightened SELinux policies) — the UI
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
}
