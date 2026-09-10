import 'package:flutter/material.dart';
import '../theme.dart';

/// The four optimization profiles. The `id` is the exact string sent over
/// the platform channel to PerformanceManager.kt — keep them in sync.
enum SnazyProfile { performance, better, normal, batterySaver }

extension SnazyProfileData on SnazyProfile {
  String get id {
    switch (this) {
      case SnazyProfile.performance:
        return 'performance';
      case SnazyProfile.better:
        return 'better';
      case SnazyProfile.normal:
        return 'normal';
      case SnazyProfile.batterySaver:
        return 'battery_saver';
    }
  }

  String get label {
    switch (this) {
      case SnazyProfile.performance:
        return 'Performance';
      case SnazyProfile.better:
        return 'Better';
      case SnazyProfile.normal:
        return 'Normal';
      case SnazyProfile.batterySaver:
        return 'Ultra Battery Saver';
    }
  }

  String get tagline {
    switch (this) {
      case SnazyProfile.performance:
        return 'Unlocks every CPU core and the GPU to their highest available clock speed.';
      case SnazyProfile.better:
        return 'Max performance without pushing every clock to its ceiling — cooler and more sustained.';
      case SnazyProfile.normal:
        return 'Stock behavior. Restores the CPU/GPU to how they were before Snazy touched anything.';
      case SnazyProfile.batterySaver:
        return 'Caps clocks low across the board for maximum battery life during long sessions.';
    }
  }

  /// Longer, honest explanation shown on the profile picker — this app
  /// doesn't claim to overclock past what the chip's own firmware allows.
  String get detail {
    switch (this) {
      case SnazyProfile.performance:
        return 'Root or Shizuku required. Sets every CPU core\'s governor to '
            '"performance" and pins it to its own maximum stock frequency, '
            'plus the GPU governor where the chip exposes one. This is the '
            'highest clock speed your hardware already supports — Android '
            'gives no safe, generic way to push a chip past its own '
            'manufacturer limits, so that\'s never attempted here.';
      case SnazyProfile.better:
        return 'Root or Shizuku required. CPU governor set to "performance" '
            'but capped below the absolute ceiling, so the chip runs fast '
            'without sitting at max clock (and max heat) the whole time. '
            'The GPU is left untouched in this profile.';
      case SnazyProfile.normal:
        return 'Restores the exact governor and frequency values Snazy '
            'found the very first time it ran on this device — the real '
            'factory baseline, not a guess.';
      case SnazyProfile.batterySaver:
        return 'Root or Shizuku required. Governor set to "powersave" with '
            'both CPU and GPU clocks pinned low. Without root/Shizuku, '
            'Snazy instead opens Android\'s own Battery Saver settings.';
    }
  }

  IconData get icon {
    switch (this) {
      case SnazyProfile.performance:
        return Icons.bolt_rounded;
      case SnazyProfile.better:
        return Icons.speed_rounded;
      case SnazyProfile.normal:
        return Icons.balance_rounded;
      case SnazyProfile.batterySaver:
        return Icons.battery_saver_rounded;
    }
  }

  Color get color {
    switch (this) {
      case SnazyProfile.performance:
        return SnazyTheme.accentCyan;
      case SnazyProfile.better:
        return SnazyTheme.accentPurple;
      case SnazyProfile.normal:
        return const Color(0xFF9AA5B1);
      case SnazyProfile.batterySaver:
        return SnazyTheme.success;
    }
  }

  bool get requiresPrivilege => this != SnazyProfile.normal;

  static SnazyProfile fromId(String id) {
    return SnazyProfile.values.firstWhere(
      (p) => p.id == id,
      orElse: () => SnazyProfile.normal,
    );
  }
}
