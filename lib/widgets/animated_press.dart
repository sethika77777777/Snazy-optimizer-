import 'package:flutter/material.dart';
import '../theme.dart';

/// Wraps any tappable widget with the small iOS-style "press down" scale +
/// opacity dip. Cheap, dependency-free, and used everywhere in Snazy that
/// isn't already a Material ripple (cards, chips, the boost button).
class AnimatedPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const AnimatedPress({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
  });

  @override
  State<AnimatedPress> createState() => _AnimatedPressState();
}

class _AnimatedPressState extends State<AnimatedPress> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: SnazyTheme.fast,
        curve: SnazyTheme.springOut,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: SnazyTheme.fast,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades + rises a child in on first build — used for staggered entrance
/// animations down the dashboard's list of cards.
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
  });

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: SnazyTheme.slow);
    final curved = CurvedAnimation(parent: _controller, curve: SnazyTheme.springOut);
    _fade = curved;
    _slide = Tween<Offset>(
      begin: Offset(0, widget.offset / 100),
      end: Offset.zero,
    ).animate(curved);
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
