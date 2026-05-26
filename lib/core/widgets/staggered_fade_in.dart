import 'package:flutter/material.dart';

/// Animates a child widget with a fade-in + slide-up effect, staggered by
/// [index] so that items appear one after another (50ms delay per index).
///
/// This creates a cascading entrance animation for list items.
///
/// Example:
/// ```dart
/// ListView.builder(
///   itemCount: items.length,
///   itemBuilder: (context, index) => StaggeredFadeIn(
///     index: index,
///     child: MyListItem(...),
///   ),
/// )
/// ```
class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({
    super.key,
    required this.index,
    required this.child,
    this.offset = 16.0,
    this.staggerMs = 50,
  });

  /// The item's position in the list (0-based).
  final int index;

  /// The widget to animate in.
  final Widget child;

  /// Vertical offset (in px) the item slides up from (default 16).
  final double offset;

  /// Delay per index in milliseconds (default 50).
  final int staggerMs;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slide = Tween<Offset>(
      begin: Offset(0, widget.offset / 100),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Staggered start: each item begins its animation with [staggerMs] delay
    Future.delayed(Duration(milliseconds: widget.index * widget.staggerMs), () {
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(0, _slide.value.dy * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
