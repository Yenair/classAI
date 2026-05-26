import 'package:flutter/material.dart';

/// A wrapper widget that provides press-down feedback via a smooth scale
/// animation. When pressed, the child scales to [scaleEnd] (default 0.97);
/// when released it springs back to 1.0.
///
/// Use this to wrap any tappable widget for a tactile "sinking" feel.
///
/// Example:
/// ```dart
/// AnimatedPressable(
///   onPressed: () => print('tapped'),
///   child: FilledButton(
///     onPressed: null, // handled by AnimatedPressable
///     child: const Text('Press Me'),
///   ),
/// )
/// ```
class AnimatedPressable extends StatefulWidget {
  const AnimatedPressable({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.scaleEnd = 0.97,
  });

  /// The widget to wrap with press animation.
  final Widget child;

  /// Called when the user taps.
  final VoidCallback? onPressed;

  /// Called when the user long-presses.
  final VoidCallback? onLongPress;

  /// The scale to animate to when pressed (default 0.97).
  final double scaleEnd;

  @override
  State<AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<AnimatedPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleEnd).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
        reverseCurve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _controller.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _controller.reverse();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _onTapDown : null,
      onTapUp: widget.onPressed != null ? _onTapUp : null,
      onTapCancel: widget.onPressed != null ? _onTapCancel : null,
      onLongPressStart: widget.onLongPress != null ? _onLongPressStart : null,
      onLongPressEnd: widget.onLongPress != null ? _onLongPressEnd : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
