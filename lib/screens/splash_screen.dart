import 'package:flutter/material.dart';
import '../services/native_bridge.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'Starting Snazy...';

  @override
  void initState() {
    super.initState();
    _checkRootAndProceed();
  }

  Future<void> _checkRootAndProceed() async {
    setState(() => _status = 'Checking root access...');
    final rooted = await NativeBridge.isRooted();
    setState(() =>
        _status = rooted ? 'Root detected — unlocking full mode' : 'Preparing standard mode');
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DashboardScreen(isRooted: rooted)),
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
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: SnazyTheme.accentCyan),
              const SizedBox(height: 16),
              Text(_status, style: const TextStyle(color: Colors.white60)),
            ],
          ),
        ),
      ),
    );
  }
}
