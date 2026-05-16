import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/theme/app_theme.dart';

double luminance(Color c) {
  // WCAG relative luminance calculation
  double r = c.r, g = c.g, b = c.b;
  r = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4).toDouble();
  g = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4).toDouble();
  b = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

void main() {
  test('WCAG AAA contrast ratios', () {
    expect(contrastRatio(AppTheme.primary, AppTheme.onPrimary), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppTheme.surface, AppTheme.onSurface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(AppTheme.error, AppTheme.surface), greaterThanOrEqualTo(4.5));
  });
}
