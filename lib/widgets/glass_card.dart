import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// A real frosted-glass container using BackdropFilter — genuine
/// iOS-style glassmorphism, not a static image trick. Layers a blur, a
/// soft diagonal glass highlight, and a bright top edge the way
/// UIVisualEffectView cards read as "glass" rather than just "translucent".
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blur;

  /// Optional brand tint (e.g. a selected profile's color) mixed into the
  /// glass fill and border — leave null for the neutral look.
  final Color? tint;
  final bool selected;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.blur = 22,
    this.tint,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final tintColor = tint ?? Colors.white;
    final fillOpacity = selected ? 0.14 : (tint != null ? 0.10 : 0.06);
    final borderColor = selected
        ? tintColor.withOpacity(0.65)
        : (tint != null ? tintColor.withOpacity(0.35) : SnazyTheme.glassBorder);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: AnimatedContainer(
          duration: SnazyTheme.fast,
          curve: SnazyTheme.springOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: selected ? 1.4 : 1),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tintColor.withOpacity(fillOpacity + 0.04),
                tintColor.withOpacity(fillOpacity * 0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              if (selected)
                BoxShadow(
                  color: tintColor.withOpacity(0.25),
                  blurRadius: 20,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: Stack(
            children: [
              // Glossy top-edge highlight — the detail that reads as "glass".
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.55),
                        Colors.white.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}
