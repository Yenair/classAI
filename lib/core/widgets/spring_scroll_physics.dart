import 'package:flutter/widgets.dart';

/// Scroll physics that provides a spring-like overscroll effect.
///
/// Uses [BouncingScrollPhysics] as a base, which gives a natural springy
/// feel on overscroll — similar to iOS native scrolling. Apply to any
/// scrollable widget via `physics: const SpringScrollPhysics()`.
///
/// This replaces the default [ClampingScrollPhysics] (Android) with a
/// bouncy overscroll that visually indicates the scroll boundary.
///
/// Example:
/// ```dart
/// SingleChildScrollView(
///   physics: const SpringScrollPhysics(),
///   child: ...
/// )
/// ```
class SpringScrollPhysics extends BouncingScrollPhysics {
  const SpringScrollPhysics({super.parent});

  @override
  SpringScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return SpringScrollPhysics(parent: buildParent(ancestor));
  }
}
