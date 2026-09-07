import 'package:flutter/material.dart';

/// Snazy dark "glass" theme — deep background so frosted cards pop.
class SnazyTheme {
  static const Color bg = Color(0xFF0B0D12);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentPurple = Color(0xFF7C4DFF);
  static const Color danger = Color(0xFFFF5252);
  static const Color success = Color(0xFF00E676);

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: accentCyan,
          secondary: accentPurple,
          surface: Color(0xFF14171F),
        ),
        useMaterial3: true,
      );

  static BoxDecoration get pageGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0D12), Color(0xFF141826), Color(0xFF0B0D12)],
        ),
      );
}
