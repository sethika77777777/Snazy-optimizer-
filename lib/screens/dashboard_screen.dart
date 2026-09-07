import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import '../services/native_bridge.dart';
import '../services/optimizer_service.dart';
import '../theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/stat_box.dart';
import 'game_select_screen.dart';
import 'safe_apps_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool isRooted;
  const DashboardScreen({super.key, required this.isRooted});

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
  GraphicsBackend _backend = GraphicsBackend.openGLES;

  bool _boosting = false;
  String _boostMessage = '';
  int _lastFrozenCount = 0;

  late final AnimationController _boostAnim;

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
    setState(() {
      _safeList = safe;
      _selectedGamePkg = game;
      _backend = backend;
    });
  }

  Future<void> _pollStats() async {
    try {
      final ram = await NativeBridge.getRamInfo();
      final cpu = await NativeBridge.getCpuUsage();
      final total = (ram['totalMem'] ?? 1) as int;
      final avail = (ram['availMem'] ?? 0) as int;
      final usedPct = total > 0
          ? (((total - avail) / total) * 100).round()
          : 0;

      int batteryLevel = 0;
      bool charging = false;
      try {
        final b = await NativeBridge.getBatteryInfo();
        batteryLevel = (b['level'] ?? 0) as int;
        charging = (b['charging'] ?? false) as bool;
      } catch (_) {
        // Fallback to battery_plus if the platform channel path fails.
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
      setState(() {
        _selectedGamePkg = pkg;
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

    if (widget.isRooted && _freezeEnabled) {
      final frozen = await OptimizerService.rootBoost(
        gamePkg: _selectedGamePkg!,
        safeList: _safeList,
      );
      setState(() => _lastFrozenCount = frozen.length);
      setState(() => _boostMessage = 'Optimizing CPU scheduler...');
    } else {
      setState(() => _boostMessage = 'Whitelisting game from battery limits...');
      await OptimizerService.nonRootBoost(gamePkg: _selectedGamePkg!);
    }

    await Future.delayed(const Duration(milliseconds: 900));
    setState(() => _boostMessage = 'Launching game...');
    await Future.delayed(const Duration(milliseconds: 600));

    _boostAnim.stop();
    if (!mounted) return;
    setState(() => _boosting = false);
  }

  Future<void> _restore() async {
    if (!widget.isRooted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Restore re-enables apps frozen by root boost — nothing to restore in non-root mode.')),
      );
      return;
    }
    final n = await OptimizerService.restoreFrozenApps();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored $n app(s) to normal')),
    );
    setState(() => _lastFrozenCount = 0);
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: widget.isRooted
                                ? SnazyTheme.success.withOpacity(0.2)
                                : Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.isRooted ? 'ROOT' : 'STANDARD',
                            style: TextStyle(
                              fontSize: 11,
                              color: widget.isRooted
                                  ? SnazyTheme.success
                                  : Colors.white70,
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
                        Row(
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
                        const SizedBox(height: 16),

                        // ---- Game select ----
                        GlassCard(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.videogame_asset,
                                color: SnazyTheme.accentCyan),
                            title: Text(
                              _selectedGameName ?? _selectedGamePkg ?? 'No game selected',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: const Text('Tap to choose a game to optimize',
                                style: TextStyle(color: Colors.white38)),
                            trailing: const Icon(Icons.chevron_right,
                                color: Colors.white38),
                            onTap: _pickGame,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Freeze toggle ----
                        GlassCard(
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _freezeEnabled,
                                activeColor: SnazyTheme.accentCyan,
                                onChanged: widget.isRooted
                                    ? (v) => setState(() => _freezeEnabled = v)
                                    : null,
                                title: const Text('Background Freeze',
                                    style: TextStyle(color: Colors.white)),
                                subtitle: Text(
                                  widget.isRooted
                                      ? 'Disables other apps at OS level while your game runs'
                                      : 'Requires root — non-root mode whitelists the game instead',
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
                                subtitle: Text('${_safeList.length} app(s) excluded from freeze',
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12)),
                                trailing: const Icon(Icons.chevron_right,
                                    color: Colors.white38),
                                onTap: _pickSafeApps,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ---- Graphics backend ----
                        GlassCard(
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
                        const SizedBox(height: 12),

                        if (_lastFrozenCount > 0)
                          GlassCard(
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline,
                                    color: SnazyTheme.accentPurple, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$_lastFrozenCount app(s) currently frozen',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 100),
                      ]),
                    ),
                  ),
                ],
              ),

              // ---- Bottom action bar ----
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restore,
                          icon: const Icon(Icons.restore,
                              color: Colors.white70),
                          label: const Text('Restore',
                              style: TextStyle(color: Colors.white70)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _boosting ? null : _runBoost,
                          icon: const Icon(Icons.bolt),
                          label: Text(_boosting ? 'Boosting...' : 'BOOST'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SnazyTheme.accentCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
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
                          Text(_boostMessage,
                              style: const TextStyle(color: Colors.white)),
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
    return GestureDetector(
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
