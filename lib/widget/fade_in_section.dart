import 'package:flutter/material.dart';

/// Apparition progressive d'une section de l'accueil (Foodie 9.2).
///
/// Fades + slides its child up when it first appears.
///
/// Used on home-screen sections so reactively-loaded content (banners,
/// stories, offers) glides in smoothly instead of popping, and the initial
/// page build feels staged rather than laggy. Animates once per mount —
/// rebuilds of the same section keep their state and don't re-animate.
class FadeInSection extends StatefulWidget {
  final Widget child;

  /// Delay before the animation starts — stagger sections with 60-200ms steps.
  final int delayMs;

  const FadeInSection({super.key, required this.child, this.delayMs = 0});

  @override
  State<FadeInSection> createState() => _FadeInSectionState();
}

class _FadeInSectionState extends State<FadeInSection> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.delayMs <= 0) {
      _controller.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Reglage systeme « supprimer les animations » : affichage direct.
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
