import 'package:flutter/material.dart';

/// Small, unobtrusive developer credit shown at the bottom of the
/// dashboard — fades gently in after the rest of the screen has settled.
class FooterCredit extends StatefulWidget {
  const FooterCredit({super.key});

  @override
  State<FooterCredit> createState() => _FooterCreditState();
}

class _FooterCreditState extends State<FooterCredit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future.delayed(const Duration(milliseconds: 400), () {
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
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeIn),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          'Developed by sethikaDV',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.28),
            fontSize: 11,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}
