import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

/// A shimmer loading placeholder that replaces [CircularProgressIndicator]
/// for full-page / section loading states.
///
/// Usage: `loading ? const ShimmerLoading() : content`
class ShimmerLoading extends StatelessWidget {
  /// Number of shimmer lines / card placeholders to show.
  final int itemCount;

  const ShimmerLoading({super.key, this.itemCount = 4});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Shimmer.fromColors(
      baseColor: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
          : Colors.grey.shade300,
      highlightColor: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.8)
          : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(itemCount, (index) {
            if (index == 0) {
              // Title placeholder
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Container(
                  height: 24,
                  width: 180,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusDefault),
                  ),
                ),
              );
            }
            // Card placeholder
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// A shimmer circle placeholder ideal for profile avatars.
class ShimmerCircle extends StatelessWidget {
  final double size;

  const ShimmerCircle({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Shimmer.fromColors(
      baseColor: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
          : Colors.grey.shade300,
      highlightColor: isDark
          ? cs.surfaceContainerHighest.withValues(alpha: 0.8)
          : Colors.grey.shade100,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
