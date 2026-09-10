import 'package:flutter/material.dart';
import '../services/native_bridge.dart';
import '../theme.dart';
import '../widgets/animated_press.dart';
import '../widgets/glass_card.dart';

/// Walks a non-rooted user through installing and granting Shizuku, so
/// Snazy can reach the same root-level actions rooted users get — without
/// ever rooting the device. Every status shown here is a live read from
/// NativeBridge.getPrivilegeState(), not a script.
class ShizukuSetupScreen extends StatefulWidget {
  const ShizukuSetupScreen({super.key});

  @override
  State<ShizukuSetupScreen> createState() => _ShizukuSetupScreenState();
}

class _ShizukuSetupScreenState extends State<ShizukuSetupScreen> {
  Map<String, dynamic> _state = const {
    'rooted': false,
    'shizukuInstalled': false,
    'shizukuBinderAlive': false,
    'shizukuGranted': false,
    'shizukuUid': -1,
    'mode': 'none',
  };
  bool _loading = true;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final state = await NativeBridge.getPrivilegeState();
    if (!mounted) return;
    setState(() {
      _state = state;
      _loading = false;
    });
  }

  bool get _installed => _state['shizukuInstalled'] == true;
  bool get _running => _state['shizukuBinderAlive'] == true;
  bool get _granted => _state['shizukuGranted'] == true;
  bool get _rooted => _state['rooted'] == true;

  Future<void> _requestPermission() async {
    setState(() => _requesting = true);
    await NativeBridge.requestShizukuPermission();
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() => _requesting = false);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: SnazyTheme.pageGradient,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text('Set up Shizuku'),
                backgroundColor: Colors.transparent,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: SnazyTheme.accentCyan),
                          )
                        : const Icon(Icons.refresh, color: Colors.white70),
                    onPressed: _loading ? null : _refresh,
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    FadeInUp(
                      child: GlassCard(
                        tint: _rooted
                            ? SnazyTheme.success
                            : (_granted ? SnazyTheme.success : SnazyTheme.warning),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _rooted
                                      ? Icons.verified_rounded
                                      : (_granted
                                          ? Icons.check_circle_rounded
                                          : Icons.info_outline_rounded),
                                  color: _rooted || _granted
                                      ? SnazyTheme.success
                                      : SnazyTheme.warning,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _rooted
                                        ? 'Root detected — Shizuku not needed'
                                        : (_granted
                                            ? 'Shizuku is ready'
                                            : 'Shizuku isn\'t granted yet'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _rooted
                                  ? 'Your device already has root, so Snazy uses it directly for Performance/Better/Ultra Battery Saver and Background Freeze. You don\'t need Shizuku at all.'
                                  : 'Shizuku gives Snazy the same shell-level access adb has — no root required. Follow the steps below, then come back here.',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_rooted) ...[
                      FadeInUp(
                        delay: const Duration(milliseconds: 60),
                        child: _StepTile(
                          index: 1,
                          done: _installed,
                          title: 'Install Shizuku',
                          body:
                              'A small, open-source app by the Android tooling community. Free, no ads.',
                          action: _installed ? null : 'Open Play Store',
                          onAction: () => NativeBridge.openShizukuPlayStore(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FadeInUp(
                        delay: const Duration(milliseconds: 120),
                        child: _StepTile(
                          index: 2,
                          done: _running,
                          title: 'Start the Shizuku service',
                          body:
                              'Open Shizuku and tap Start. On Android 11+, use "Wireless debugging" (Settings → Developer options) and pair once. On older Android, start it once via a computer with adb. It needs restarting after a reboot unless your device stays rooted.',
                          action: _installed ? 'Open Shizuku' : null,
                          onAction: () => NativeBridge.openShizukuApp(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FadeInUp(
                        delay: const Duration(milliseconds: 180),
                        child: _StepTile(
                          index: 3,
                          done: _granted,
                          title: 'Grant Snazy permission',
                          body:
                              'One tap — Shizuku shows its own permission dialog, the same way a runtime permission works.',
                          action: _running
                              ? (_requesting ? 'Requesting...' : 'Grant permission')
                              : null,
                          onAction: _requesting ? null : _requestPermission,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeInUp(
                        delay: const Duration(milliseconds: 240),
                        child: GlassCard(
                          child: Row(
                            children: [
                              const Icon(Icons.developer_board,
                                  color: Colors.white38, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _state['shizukuUid'] == 0
                                      ? 'Shizuku is running with root privilege (via Sui).'
                                      : (_state['shizukuUid'] == 2000
                                          ? 'Shizuku is running with adb/shell privilege.'
                                          : 'Waiting for Shizuku to start...'),
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final bool done;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  const _StepTile({
    required this.index,
    required this.done,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      tint: done ? SnazyTheme.success : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? SnazyTheme.success.withOpacity(0.2)
                  : Colors.white.withOpacity(0.08),
              border: Border.all(
                  color: done ? SnazyTheme.success : Colors.white24),
            ),
            child: done
                ? const Icon(Icons.check, color: SnazyTheme.success, size: 16)
                : Text('$index',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12, height: 1.35)),
                if (action != null) ...[
                  const SizedBox(height: 10),
                  AnimatedPress(
                    onTap: onAction,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: SnazyTheme.brandGradient,
                      ),
                      child: Text(action!,
                          style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
