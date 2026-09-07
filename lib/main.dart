import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'theme.dart';

void main() {
  runApp(const SnazyApp());
}

class SnazyApp extends StatelessWidget {
  const SnazyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Snazy',
      debugShowCheckedModeBanner: false,
      theme: SnazyTheme.theme,
      home: const SplashScreen(),
    );
  }
}
