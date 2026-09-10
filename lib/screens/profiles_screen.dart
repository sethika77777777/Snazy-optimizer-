import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/native_bridge.dart';
import '../services/optimizer_service.dart';
import '../theme.dart';
import '../widgets/animated_press.dart';
import '../widgets/glass_card.dart';
import 'shizuku_setup_screen.dart';

/// Full-screen profile picker: Performance / Better / Normal / Ultra
/// Battery Saver. Applying a profile calls straight into
/// PerformanceManager.kt and shows back the verified result — never an
/// optimistic "done!" the device didn't actually confirm.
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  SnazyProfile _selected = SnazyProfile.normal;
  Map<String, dynamic> _privilege = const {'mode': 'none'};
  bool _applying = false;
  String? _lastMessage;
  String _governor = '--';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await OptimizerService.getSelectedProfile();
    final privilege = await NativeBridge.getPrivilegeState();
    final governor = await NativeBridge.currentGovernor();
    if (!mounted) return;
    setState(() {
      _selected = profile;
      _privilege = privilege;
      _governor = governor;
    });
  }

  bool get _hasPrivilege => _privilege['mode'] != 'none';

  Future<void> _apply(SnazyProfile profile) async {
    if (profile.requiresPrivilege && !_hasPrivilege) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ShizukuSetupScreen()),
      );
      return;
    }
    setState(() {
      _applying = true;
      _selected = profile;
      _lastMessage = null;
    });
    await OptimizerService.setSelectedProfile(profile);
    final result = await OptimizerService.applyProfile(profile);
    final governor = await NativeBridge.currentGovernor();
    if (!mounted) return;
    setState(() {
      _applying = false;
      _lastMessage = result['message'] as String? ??
          (result['success'] == true ? 'Applied.' : 'Could not apply this profile.');
      _governor = governor;
    });
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
                title: const Text('Profiles'),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GlassCard(
                  child: Row(
                    children: [
                      Icon(
                        _hasPrivilege ? Icons.shield_rounded : Icons.shield_outlined,
                        color: _hasPrivilege ? SnazyTheme.success : SnazyTheme.warning,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _hasPrivilege
                              ? '${_privilege['mode'] == 'root' ? 'Root' : 'Shizuku'} access active · governor: $_governor'
                              : 'No root or Shizuku — only Normal is available',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                      if (!_hasPrivilege)
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const ShizukuSetupScreen()),
                          ),
                          child: const Text('Set up',
                              style: TextStyle(color: SnazyTheme.accentCyan)),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    for (final profile in SnazyProfile.values) ...[
                      FadeInUp(
                        delay: Duration(
                            milliseconds: 60 * SnazyProfile.values.indexOf(profile)),
                        child: _ProfileCard(
                          profile: profile,
                          selected: _selected == profile,
                          locked: profile.requiresPrivilege && !_hasPrivilege,
                          applying: _applying && _selected == profile,
                          onTap: () => _apply(profile),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_lastMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _lastMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ),
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

class _ProfileCard extends StatelessWidget {
  final SnazyProfile profile;
  final bool selected;
  final bool locked;
  final bool applying;
  final VoidCallback onTap;

  const _ProfileCard({
    required this.profile,
    required this.selected,
    required this.locked,
    required this.applying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPress(
      onTap: onTap,
      child: GlassCard(
        tint: profile.color,
        selected: selected,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: profile.color.withOpacity(0.16),
              ),
              child: applying
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: profile.color),
                    )
                  : Icon(profile.icon, color: profile.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(profile.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline,
                            size: 13, color: Colors.white38),
                      ],
                      if (selected) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: profile.color),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(profile.tagline,
                      style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  const SizedBox(height: 6),
                  Text(profile.detail,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
