import 'package:flutter/material.dart';
import '../services/native_bridge.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _status = 'Starting Snazy...';
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: SnazyTheme.slow);
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: SnazyTheme.springOut),
    );
    _logoFade = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
    _checkAndProceed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkAndProceed() async {
    setState(() => _status = 'Checking device access...');
    final state = await NativeBridge.getPrivilegeState();
    final mode = state['mode'] as String? ?? 'none';
    setState(() {
      _status = switch (mode) {
        'root' => 'Root detected — unlocking full mode',
        'shizuku' => 'Shizuku ready — unlocking full mode',
        _ => 'Preparing standard mode',
      };
    });
    await Future.delayed(const Duration(milliseconds: 750));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: SnazyTheme.pageGradient,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: FadeTransition(
                  opacity: _logoFade,
                  child: Column(
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: SnazyTheme.brandGradient,
                          boxShadow: [
                            BoxShadow(
                              color: SnazyTheme.accentCyan.withOpacity(0.35),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.bolt_rounded,
                            color: Colors.black, size: 44),
                      ),
                      const SizedBox(height: 20),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [SnazyTheme.accentCyan, SnazyTheme.accentPurple],
                        ).createShader(bounds),
                        child: const Text('SNAZY',
                            style: TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 6)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: SnazyTheme.accentCyan),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: SnazyTheme.medium,
                child: Text(
                  _status,
                  key: ValueKey(_status),
                  style: const TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
