import 'package:flutter/material.dart';

/// Snazy dark "glass" theme — deep background so frosted cards pop, plus
/// the shared motion tokens every screen's entrance/press animations use.
class SnazyTheme {
  static const Color bg = Color(0xFF08090D);
  static const Color bgElevated = Color(0xFF14171F);
  static const Color glassBorder = Color(0x33FFFFFF);
  static const Color glassBorderBright = Color(0x59FFFFFF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color accentPurple = Color(0xFF7C4DFF);
  static const Color accentPink = Color(0xFFFF4FA3);
  static const Color danger = Color(0xFFFF5252);
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB300);

  /// Shared "iOS-style" easing — snappy start, soft settle.
  static const Curve springOut = Curves.easeOutCubic;
  static const Curve springInOut = Curves.easeInOutCubic;
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 560);

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: accentCyan,
          secondary: accentPurple,
          surface: bgElevated,
          error: danger,
        ),
        splashFactory: InkSparkle.splashFactory,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
          },
        ),
      );

  static BoxDecoration get pageGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B0D14), Color(0xFF171B2C), Color(0xFF08090D)],
        ),
      );

  static LinearGradient get brandGradient => const LinearGradient(
        colors: [accentCyan, accentPurple],
      );

  static LinearGradient get dangerGradient => const LinearGradient(
        colors: [accentPink, danger],
      );
}

/// A light custom PageTransitionsBuilder that fades + gently scales instead
/// of Android's default abrupt slide — the closest Material equivalent to
/// iOS's soft cross-fade between screens, without pulling in a new package.
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: SnazyTheme.springOut);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}
