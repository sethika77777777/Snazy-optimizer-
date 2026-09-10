import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';
import 'apps_service.dart';
import 'native_bridge.dart';

enum GraphicsBackend { openGLES, vulkan }

class OptimizerService {
  static const _kSafeList = 'safe_list';
  static const _kSelectedGame = 'selected_game';
  static const _kGraphicsBackend = 'graphics_backend';
  static const _kSelectedProfile = 'selected_profile';
  static const _kFreezeEnabled = 'freeze_enabled';
  static const _kTouchOptEnabled = 'touch_opt_enabled';
  static const _kTouchSensitivity = 'touch_sensitivity';

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

  static Future<SnazyProfile> getSelectedProfile() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kSelectedProfile);
    if (v == null) return SnazyProfile.normal;
    return SnazyProfileData.fromId(v);
  }

  static Future<void> setSelectedProfile(SnazyProfile profile) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSelectedProfile, profile.id);
  }

  static Future<bool> getFreezeEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kFreezeEnabled) ?? true;
  }

  static Future<void> setFreezeEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kFreezeEnabled, v);
  }

  static Future<bool> getTouchOptEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kTouchOptEnabled) ?? true;
  }

  static Future<void> setTouchOptEnabled(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kTouchOptEnabled, v);
  }

  /// 0-100, higher = shorter tap/long-press recognition delay. Persisted
  /// immediately on every edit so the value survives app restarts.
  static Future<int> getTouchSensitivity() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getInt(_kTouchSensitivity) ?? 75;
  }

  static Future<void> setTouchSensitivity(int v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_kTouchSensitivity, v);
  }

  // ---------- Profiles ----------

  /// Applies [profile]'s real CPU/GPU governor + frequency settings via
  /// PerformanceManager.kt. Returns the verified native result map.
  static Future<Map<String, dynamic>> applyProfile(SnazyProfile profile) {
    return NativeBridge.applyProfile(profile.id);
  }

  // ---------- Boost: real, privileged force-stop sweep ----------
  //
  // "Freeze" never disables an app — it only force-stops the CURRENT
  // process of everything except the selected game and the safe list. Since
  // nothing is disabled, every app is immediately usable again the moment
  // Restore is tapped; there's nothing to "re-enable".

  /// Every installed, non-safe-listed, non-core-system package except the
  /// game itself — the exact set Background Freeze is allowed to touch.
  static Future<List<String>> freezeTargets({
    required String gamePkg,
    required Set<String> safeList,
  }) async {
    final apps = await AppsService.getInstalledApps();
    final targets = <String>[];
    for (final app in apps) {
      final pkg = app.packageName ?? '';
      if (pkg.isEmpty) continue;
      if (pkg == gamePkg) continue;
      if (safeList.contains(pkg)) continue;
      if (pkg.startsWith('com.android.') ||
          pkg.startsWith('com.google.android.gms') ||
          pkg == 'android' ||
          pkg == 'com.sethikadv.snazy') {
        continue; // never touch core OS / Play services / itself
      }
      targets.add(pkg);
    }
    return targets;
  }

  /// One immediate sweep for instant RAM/CPU relief at Boost time.
  static Future<Map<String, dynamic>> freezeSweep(List<String> targets) {
    return NativeBridge.runFreezeSweep(targets);
  }

  /// Starts the detached loop that keeps [targets] stopped while the game
  /// runs. Only takes effect with root or granted Shizuku — the caller
  /// should check privilege state first.
  static Future<bool> startFreezeLoop(List<String> targets) {
    return NativeBridge.startFreezeLoop(targets);
  }

  static Future<void> launchGame(String gamePkg) {
    return AppsService.launchApp(gamePkg);
  }

  // ---------- Game Boost: the actual FPS lever, not just anti-lag ----------
  //
  // applyProfile()/freeze above stop the chip being artificially slow and
  // stop other apps stealing cycles — that fixes stutter, not the frame
  // ceiling. This is the piece that targets FPS directly: it cuts
  // SurfaceFlinger/animation overhead system-wide and keeps the game's own
  // process + every render/worker thread inside it pinned to the top-app
  // cpuset with a real-time scheduling priority for as long as it runs —
  // the same mechanism OEM "Game Turbo" tools use. Root or Shizuku only.

  static Future<bool> applyGameBoost(String gamePkg) {
    return NativeBridge.applyGameBoost(gamePkg);
  }

  /// Restores animation/GPU render settings and stops the thread-priority
  /// loop. Safe to call even if boost was never started.
  static Future<bool> stopGameBoost() {
    return NativeBridge.stopGameBoost();
  }

  // ---------- Touch response optimization: real settings + best-effort ----------
  // vendor touch-boost node, root/Shizuku only. See TouchOptimizer.kt.

  static Future<bool> applyTouchOptimization(int sensitivity) =>
      NativeBridge.applyTouchOptimization(sensitivity);

  static Future<bool> stopTouchOptimization() =>
      NativeBridge.stopTouchOptimization();

  /// Ends the freeze loop. Nothing needs "restoring" beyond that — apps
  /// were force-stopped, never disabled — so this is instant.
  static Future<bool> restore() {
    return NativeBridge.stopFreezeLoop();
  }

  // ---------- Non-root, non-Shizuku boost: only real, permission-legal actions ----------
  //
  // With no privileged access at all, Android gives no API to stop other
  // apps' processes from a normal app. This path is honest about that: it
  // whitelists the selected game from battery optimization via the real
  // system settings screen, makes a best-effort (weaker) background kill
  // pass via ActivityManager, then launches the game.

  static Future<int> basicBoost({
    required String gamePkg,
    required List<String> targets,
  }) async {
    await NativeBridge.openBatteryOptimizationSettings(gamePkg);
    final killed = await NativeBridge.killBackgroundProcesses(targets);
    return killed;
  }
}
