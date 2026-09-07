import 'package:shared_preferences/shared_preferences.dart';
import 'apps_service.dart';
import 'native_bridge.dart';

enum GraphicsBackend { openGLES, vulkan }

class OptimizerService {
  static const _kSafeList = 'safe_list';
  static const _kFrozenList = 'frozen_list';
  static const _kSelectedGame = 'selected_game';
  static const _kGraphicsBackend = 'graphics_backend';

  // ---------- Preferences ----------

  static Future<Set<String>> getSafeList() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kSafeList) ?? []).toSet();
  }

  static Future<void> setSafeList(Set<String> pkgs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kSafeList, pkgs.toList());
  }

  static Future<String?> getSelectedGame() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(_kSelectedGame);
  }

  static Future<void> setSelectedGame(String pkg) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSelectedGame, pkg);
  }

  static Future<GraphicsBackend> getGraphicsBackend() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kGraphicsBackend);
    return v == 'vulkan' ? GraphicsBackend.vulkan : GraphicsBackend.openGLES;
  }

  static Future<void> setGraphicsBackend(GraphicsBackend b) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kGraphicsBackend, b == GraphicsBackend.vulkan ? 'vulkan' : 'gles');
  }

  // ---------- Root boost: real freeze via pm disable-user ----------
  //
  // "Freeze" here means the OS-level package is disabled for the current
  // user (pm disable-user). A disabled app cannot run in the foreground
  // OR background until it's re-enabled — this is a real mechanism used
  // by tools like Package Disabler Pro. It is NOT a soft/fake kill.

  /// Freezes every installed, non-system-critical app except [gamePkg]
  /// and anything in the safe list. Returns the list of packages it
  /// actually froze (only those where the root command succeeded).
  static Future<List<String>> rootBoost({
    required String gamePkg,
    required Set<String> safeList,
  }) async {
    final apps = await AppsService.getInstalledApps();
    final frozen = <String>[];

    for (final app in apps) {
      final pkg = app.packageName ?? '';
      if (pkg.isEmpty) continue;
      if (pkg == gamePkg) continue;
      if (safeList.contains(pkg)) continue;
      if (pkg.startsWith('com.android.') ||
          pkg.startsWith('com.google.android.gms') ||
          pkg == 'android' ||
          pkg == 'com.sethikadv.snazy') {
        continue; // never freeze core OS / Play services / itself — bricking risk
      }
      final ok = await NativeBridge.runRootCommand(
          'pm disable-user --user 0 $pkg');
      if (ok) frozen.add(pkg);
    }

    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kFrozenList, frozen);
    await NativeBridge.runRootCommand('am force-stop $gamePkg');
    await AppsService.launchApp(gamePkg);
    return frozen;
  }

  /// Re-enables every app this session froze.
  static Future<int> restoreFrozenApps() async {
    final sp = await SharedPreferences.getInstance();
    final frozen = sp.getStringList(_kFrozenList) ?? [];
    var restored = 0;
    for (final pkg in frozen) {
      final ok = await NativeBridge.runRootCommand('pm enable $pkg');
      if (ok) restored++;
    }
    await sp.setStringList(_kFrozenList, []);
    return restored;
  }

  // ---------- Non-root boost: only real, permission-legal actions ----------
  //
  // Non-root Android gives no API to kill or freeze other apps' processes.
  // Being honest about that: this path (a) force-stops nothing — it can't —
  // (b) offers to whitelist the selected game from battery optimization via
  // the real system settings screen, and (c) launches the game fresh.
  // Any app claiming to "kill background apps for max FPS" without root is
  // not telling you the truth about what it actually did.

  static Future<void> nonRootBoost({required String gamePkg}) async {
    await NativeBridge.openBatteryOptimizationSettings(gamePkg);
    await AppsService.launchApp(gamePkg);
  }
}
