import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import '../models/profile.dart';
import '../services/apps_service.dart';
import '../services/native_bridge.dart';
import '../services/optimizer_service.dart';
import '../theme.dart';
import '../widgets/animated_press.dart';
import '../widgets/footer_credit.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_box.dart';
import 'game_select_screen.dart';
import 'profiles_screen.dart';
import 'safe_apps_screen.dart';
import 'shizuku_setup_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  Timer? _statsTimer;
  double _cpu = -1;
  int _ramUsedPct = 0;
  int _battery = 0;
  bool _charging = false;

  String? _selectedGamePkg;
  String? _selectedGameName;
  Set<String> _safeList = {};
  bool _freezeEnabled = true;
  bool _freezeActive = false;
  bool _touchOptEnabled = true;
  int _touchSensitivity = 75;
  bool _touchOptActive = false;
  GraphicsBackend _backend = GraphicsBackend.openGLES;
  SnazyProfile _profile = SnazyProfile.normal;
  Map<String, dynamic> _privilege = const {'mode': 'none'};

  bool _boosting = false;
  String _boostMessage = '';
  int _lastFrozenCount = 0;
  bool _gameBoostActive = false;

  late final AnimationController _boostAnim;

  bool get _privileged => _privilege['mode'] != 'none';

  @override
  void initState() {
    super.initState();
    _boostAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _loadPrefs();
    _pollStats();
    _statsTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => _pollStats());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _boostAnim.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final safe = await OptimizerService.getSafeList();
    final game = await OptimizerService.getSelectedGame();
    final backend = await OptimizerService.getGraphicsBackend();
    final profile = await OptimizerService.getSelectedProfile();
    final freeze = await OptimizerService.getFreezeEnabled();
    final touchOptEnabled = await OptimizerService.getTouchOptEnabled();
    final touchSensitivity = await OptimizerService.getTouchSensitivity();
    final privilege = await NativeBridge.getPrivilegeState();
    String? gameName;
    if (game != null) gameName = await _lookupAppName(game);
    if (!mounted) return;
    setState(() {
      _safeList = safe;
      _selectedGamePkg = game;
      _selectedGameName = gameName;
      _backend = backend;
      _profile = profile;
      _freezeEnabled = freeze;
      _touchOptEnabled = touchOptEnabled;
      _touchSensitivity = touchSensitivity;
      _privilege = privilege;
    });
  }

  Future<String?> _lookupAppName(String pkg) async {
    try {
      final apps = await AppsService.getInstalledApps();
      for (final a in apps) {
        if (a.packageName == pkg) return a.name;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pollStats() async {
    try {
      final ram = await NativeBridge.getRamInfo();
      final cpu = await NativeBridge.getCpuUsage();
      final total = (ram['totalMem'] ?? 1) as int;
      final avail = (ram['availMem'] ?? 0) as int;
      final usedPct =
          total > 0 ? (((total - avail) / total) * 100).round() : 0;

      int batteryLevel = 0;
      bool charging = false;
      try {
        final b = await NativeBridge.getBatteryInfo();
        batteryLevel = (b['level'] ?? 0) as int;
        charging = (b['charging'] ?? false) as bool;
      } catch (_) {
        final battery = Battery();
        batteryLevel = await battery.batteryLevel;
        charging = (await battery.batteryState) == BatteryState.charging;
      }

      if (!mounted) return;
      setState(() {
        _cpu = cpu;
        _ramUsedPct = usedPct;
        _battery = batteryLevel;
        _charging = charging;
      });
    } catch (_) {
      // Stats genuinely unavailable on this device/OEM — surfaced as "--"
      // in the UI rather than a made-up number.
    }
  }

  Future<void> _pickGame() async {
    final pkg = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => GameSelectScreen(currentSelection: _selectedGamePkg)),
    );
    if (pkg != null) {
      await OptimizerService.setSelectedGame(pkg);
      final name = await _lookupAppName(pkg);
      if (!mounted) return;
      setState(() {
        _selectedGamePkg = pkg;
        _selectedGameName = name;
      });
    }
  }

  Future<void> _pickSafeApps() async {
    final result = await Navigator.push<Set<String>>(
      context,
      MaterialPageRoute(
          builder: (_) => SafeAppsScreen(initialSafeList: _safeList)),
    );
    if (result != null) {
      await OptimizerService.setSafeList(result);
      setState(() => _safeList = result);
    }
  }

  Future<void> _openProfiles() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    final profile = await OptimizerService.getSelectedProfile();
    final privilege = await NativeBridge.getPrivilegeState();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _privilege = privilege;
    });
  }

  Future<void> _runBoost() async {
    if (_selectedGamePkg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a game first')),
      );
      return;
    }

    setState(() {
      _boosting = true;
      _boostMessage = 'Cleaning RAM...';
    });
    _boostAnim.repeat();

    final gamePkg = _selectedGamePkg!;
    final targets = await OptimizerService.freezeTargets(
      gamePkg: gamePkg,
      safeList: _safeList,
    );

    if (_privileged) {
      final sweep = await OptimizerService.freezeSweep(targets);
      setState(() {
        _lastFrozenCount = (sweep['stopped'] as int?) ?? 0;
        _boostMessage = 'Applying ${_profile.label} profile...';
      });

      await OptimizerService.applyProfile(_profile);

      setState(() => _boostMessage = 'Boosting game thread priority...');
      final boosted = await OptimizerService.applyGameBoost(gamePkg);
      setState(() => _gameBoostActive = boosted);

      if (_touchOptEnabled) {
        setState(() => _boostMessage = 'Sharpening touch response...');
        final touchOk =
            await OptimizerService.applyTouchOptimization(_touchSensitivity);
        setState(() => _touchOptActive = touchOk);
      }

      if (_freezeEnabled) {
        setState(() => _boostMessage = 'Keeping background apps stopped...');
        final started = await OptimizerService.startFreezeLoop(targets);
        setState(() => _freezeActive = started);
      }
    } else {
      setState(() => _boostMessage = 'Whitelisting game from battery limits...');
      final killed =
          await OptimizerService.basicBoost(gamePkg: gamePkg, targets: targets);
      setState(() => _lastFrozenCount = killed);
    }

    setState(() => _boostMessage = 'Launching game...');
    await OptimizerService.launchGame(gamePkg);
    await Future.delayed(const Duration(milliseconds: 400));

    _boostAnim.stop();
    if (!mounted) return;
    setState(() => _boosting = false);
  }

  Future<void> _restore() async {
    if (!_freezeActive && !_gameBoostActive && !_touchOptActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nothing is frozen right now — Boost first.')),
      );
      return;
    }
    final freezeOk = _freezeActive ? await OptimizerService.restore() : true;
    final boostOk =
        _gameBoostActive ? await OptimizerService.stopGameBoost() : true;
    final touchOk = _touchOptActive
        ? await OptimizerService.stopTouchOptimization()
        : true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text((freezeOk && boostOk && touchOk)
            ? 'Restored — everything is back to normal.'
            : 'Could not confirm restore — check root/Shizuku access.'),
      ),
    );
    setState(() {
      _freezeActive = false;
      _gameBoostActive = false;
      _touchOptActive = false;
      _lastFrozenCount = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: SnazyTheme.pageGradient,
        child: SafeArea(
          child: Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Row(
                      children: [
                        const Text('SNAZY',
                            style: TextStyle(
                                fontWeight: FontWeight.w900, letterSpacing: 2)),
                        const SizedBox(width: 8),
                        AnimatedPress(
                          onTap: () async {
                            if (!_privileged) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const ShizukuSetupScreen()),
                              );
                              // Re-check root/Shizuku state on return — without
                              // this, granting Shizuku permission in the setup
                              // screen never reaches the dashboard, so Freeze/
                              // Touch/Boost keep silently running the
                              // non-privileged fallback until the app restarts.
                              final privilege =
                                  await NativeBridge.getPrivilegeState();
                              if (!mounted) return;
                              setState(() => _privilege = privilege);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _privileged
                                  ? SnazyTheme.success.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _privilege['mode'] == 'root'
                                  ? 'ROOT'
                                  : (_privilege['mode'] == 'shizuku'
                                      ? 'SHIZUKU'
                                      : 'STANDARD'),
                              style: TextStyle(
                                fontSize: 11,
                                color: _privileged
                                    ? SnazyTheme.success
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        // ---- Stats dashboard ----
                        FadeInUp(
                          child: Row(
                            children: [
                              Expanded(
                                child: StatBox(
                                  label: 'CPU',
                                  value: _cpu >= 0
                                      ? '${_cpu.toStringAsFixed(0)}%'
                                      : '--',
                                  icon: Icons.memory,
                                  color: SnazyTheme.accentCyan,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatBox(
                                  label: 'RAM used',
                                  value: '$_ramUsedPct%',
                                  icon: Icons.developer_board,
                                  color: SnazyTheme.accentPurple,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: StatBox(
                                  label: _charging ? 'Battery (chg)' : 'Battery',
                                  value: '$_battery%',
                                  icon: _charging
                                      ? Icons.battery_charging_full
                                      : Icons.battery_std,
                                  color: SnazyTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ---- Profile summary ----
                        FadeInUp(
                          delay: const Duration(milliseconds: 40),
                          child: AnimatedPress(
                            onTap: _openProfiles,
                            child: GlassCard(
                              tint: _profile.color,
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _profile.color.withOpacity(0.16),
                                    ),
                                    child: Icon(_profile.icon,
                                        color: _profile.color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('${_profile.label} profile',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(_profile.tagline,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right,
                                      color: Colors.white38),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Game select ----
                        FadeInUp(
                          delay: const Duration(milliseconds: 80),
                          child: AnimatedPress(
                            onTap: _pickGame,
                            child: GlassCard(
                              child: Row(
                                children: [
                                  const Icon(Icons.videogame_asset,
                                      color: SnazyTheme.accentCyan),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedGameName ??
                                              _selectedGamePkg ??
                                              'No game selected',
                                          style: const TextStyle(
                                              color: Colors.white),
                                        ),
                                        const Text(
                                            'Tap to choose a game to optimize',
                                            style: TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right,
                                      color: Colors.white38),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Touch response optimization ----
                        FadeInUp(
                          delay: const Duration(milliseconds: 100),
                          child: GlassCard(
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _touchOptEnabled,
                                  activeColor: SnazyTheme.accentCyan,
                                  onChanged: !_privileged
                                      ? null
                                      : (v) async {
                                          setState(() => _touchOptEnabled = v);
                                          await OptimizerService
                                              .setTouchOptEnabled(v);
                                          if (!v && _touchOptActive) {
                                            await OptimizerService
                                                .stopTouchOptimization();
                                            setState(
                                                () => _touchOptActive = false);
                                          }
                                        },
                                  title: const Text('Touch Response Boost',
                                      style: TextStyle(color: Colors.white)),
                                  subtitle: Text(
                                    _privileged
                                        ? 'Shortens tap/long-press recognition delay for smoother, snappier touches while boosted'
                                        : 'Requires root or Shizuku — Android gives no other way to change touch timing',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                  ),
                                ),
                                if (_privileged) ...[
                                  const Divider(color: Colors.white12, height: 1),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.touch_app_outlined,
                                            color: Colors.white54, size: 18),
                                        const SizedBox(width: 8),
                                        const Text('Sensitivity',
                                            style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12)),
                                        Expanded(
                                          child: Slider(
                                            value: _touchSensitivity
                                                .toDouble(),
                                            min: 0,
                                            max: 100,
                                            divisions: 20,
                                            activeColor:
                                                SnazyTheme.accentCyan,
                                            label: '$_touchSensitivity',
                                            onChanged: !_touchOptEnabled
                                                ? null
                                                : (v) => setState(() =>
                                                    _touchSensitivity =
                                                        v.round()),
                                            // Saved on release, not every
                                            // frame of the drag — but every
                                            // edit is always persisted.
                                            onChangeEnd: (v) async {
                                              await OptimizerService
                                                  .setTouchSensitivity(
                                                      v.round());
                                              if (_touchOptActive) {
                                                await OptimizerService
                                                    .applyTouchOptimization(
                                                        v.round());
                                              }
                                            },
                                          ),
                                        ),
                                        Text('$_touchSensitivity',
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Freeze toggle ----
                        FadeInUp(
                          delay: const Duration(milliseconds: 120),
                          child: GlassCard(
                            child: Column(
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _freezeEnabled,
                                  activeColor: SnazyTheme.accentCyan,
                                  onChanged: (v) async {
                                    setState(() => _freezeEnabled = v);
                                    await OptimizerService.setFreezeEnabled(v);
                                  },
                                  title: const Text('Background Freeze',
                                      style: TextStyle(color: Colors.white)),
                                  subtitle: Text(
                                    _privileged
                                        ? 'Stops other apps\' background processes while your game runs — nothing is disabled, Restore instantly frees them again'
                                        : 'Requires root or Shizuku — non-root mode whitelists the game instead',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12),
                                  ),
                                ),
                                const Divider(color: Colors.white12, height: 1),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.shield_outlined,
                                      color: Colors.white54),
                                  title: const Text('Apps kept alive',
                                      style: TextStyle(color: Colors.white)),
                                  subtitle: Text(
                                      '${_safeList.length} app(s) excluded from freeze',
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 12)),
                                  trailing: const Icon(Icons.chevron_right,
                                      color: Colors.white38),
                                  onTap: _pickSafeApps,
                                ),
                                if (!_privileged) ...[
                                  const Divider(color: Colors.white12, height: 1),
                                  AnimatedPress(
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ShizukuSetupScreen()),
                                      );
                                      // Same fix as the SHIZUKU/STANDARD badge
                                      // above — refresh so this card's "Requires
                                      // root or Shizuku" state and the Boost
                                      // button both see the grant immediately.
                                      final privilege =
                                          await NativeBridge.getPrivilegeState();
                                      if (!mounted) return;
                                      setState(() => _privilege = privilege);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.bolt_outlined,
                                              color: SnazyTheme.accentCyan,
                                              size: 18),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'Can\'t freeze in the background yet? Set up Shizuku to unlock it — no root needed',
                                              style: TextStyle(
                                                  color: SnazyTheme.accentCyan,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right,
                                              color: SnazyTheme.accentCyan,
                                              size: 18),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Graphics backend ----
                        FadeInUp(
                          delay: const Duration(milliseconds: 160),
                          child: GlassCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Graphics rendering backend',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                const Text(
                                  'Android only supports OpenGL ES and Vulkan — '
                                  'DirectX does not exist on this OS.',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 11),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _backendChip(
                                          'OpenGL ES', GraphicsBackend.openGLES),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _backendChip(
                                          'Vulkan', GraphicsBackend.vulkan),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'This sets a preference Snazy passes along; the game '
                                  'itself must support the chosen API to honor it.',
                                  style: TextStyle(
                                      color: Colors.white24, fontSize: 10),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (_lastFrozenCount > 0)
                          FadeInUp(
                            child: GlassCard(
                              child: Row(
                                children: [
                                  const Icon(Icons.info_outline,
                                      color: SnazyTheme.accentPurple, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _freezeActive
                                          ? '$_lastFrozenCount app(s) currently kept stopped'
                                          : '$_lastFrozenCount app(s) stopped at last boost',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        const FooterCredit(),
                        const SizedBox(height: 90),
                      ]),
                    ),
                  ),
                ],
              ),

              // ---- Bottom action bar ----
              // Wrapped in a MediaQuery override that pins text scaling to
              // 1.0 for just this bar. Without it, a device's system font
              // size setting scales the Text/Icon inside these buttons, and
              // since their height is driven purely by content padding (not
              // a fixed size), a large system font size balloons them into
              // giant, near-fullscreen buttons instead of the normal pill
              // shape shown in the design.
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.0)),
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedPress(
                            onTap: _restore,
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.restore,
                                      color: Colors.white70, size: 18),
                                  SizedBox(width: 6),
                                  Text('Restore',
                                      style: TextStyle(color: Colors.white70)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: AnimatedPress(
                            onTap: _boosting ? null : _runBoost,
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: SnazyTheme.brandGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        SnazyTheme.accentCyan.withOpacity(0.35),
                                    blurRadius: 22,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt, color: Colors.black),
                                  const SizedBox(width: 6),
                                  Text(_boosting ? 'Boosting...' : 'BOOST',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- Boost overlay animation ----
              if (_boosting)
                Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(
                    child: GlassCard(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          RotationTransition(
                            turns: _boostAnim,
                            child: const Icon(Icons.bolt,
                                color: SnazyTheme.accentCyan, size: 48),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: SnazyTheme.fast,
                            child: Text(
                              _boostMessage,
                              key: ValueKey(_boostMessage),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendChip(String label, GraphicsBackend value) {
    final selected = _backend == value;
    return AnimatedPress(
      onTap: () async {
        await OptimizerService.setGraphicsBackend(value);
        setState(() => _backend = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? SnazyTheme.accentCyan.withOpacity(0.2)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? SnazyTheme.accentCyan : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? SnazyTheme.accentCyan : Colors.white54,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
