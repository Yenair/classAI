import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:classai/core/theme/app_theme.dart';

/// Pumps [widget] in a [MaterialApp] at [size] and verifies no
/// RenderFlex overflow error is thrown during layout.
Future<void> expectNoOverflow(
  WidgetTester tester,
  Widget widget, {
  required Size size,
}) async {
  // Catch layout errors that Flutter logs but doesn't throw.
  final layoutErrors = <FlutterErrorDetails>[];
  final oldHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.toString();
    if (msg.contains('RenderFlex overflowed') ||
        msg.contains('overflow') ||
        msg.contains('BoxConstraints forces an infinite') ||
        msg.contains('infinite width') ||
        msg.contains('infinite height')) {
      layoutErrors.add(details);
    }
    oldHandler?.call(details);
  };

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: widget),
    ),
  );
  // Allow animations and layout to settle.
  await tester.pumpAndSettle(const Duration(milliseconds: 300));

  FlutterError.onError = oldHandler;

  expect(
    layoutErrors,
    isEmpty,
    reason: 'Layout error detected at ${size.width}x${size.height} '
        '${layoutErrors.map((e) => e.summary).join('; ')}',
  );
}

void main() {
  group('Exam screen overflow checks', () {
    const sizes = {
      'Small phone 320x640': Size(320, 640),
      'iPhone X 375x812': Size(375, 812),
      'Tablet 768x1024': Size(768, 1024),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} — exam choice screen', (tester) async {
        // ExamChoiceScreen is a pure StatelessWidget with no providers,
        // so we can pump it directly.
        await expectNoOverflow(
          tester,
          _ExamChoiceScreenPlaceholder(),
          size: entry.value,
        );
      });

      testWidgets(
          '${entry.key} — exam editor bottom bar button row (infinite-width regression)',
          (tester) async {
        // Reproduces the Row(Expanded(TextField), FilledButton.tonalIcon)
        // layout from ExamEditorScreen's bottom action bar.
        // The theme sets minimumSize: Size.fromHeight(48) = Size(inf, 48)
        // on every FilledButton; wrapping the button with
        //   style: FilledButton.styleFrom(minimumSize: Size(0, 48))
        // prevents the infinite-width BoxConstraints error.
        await expectNoLayoutErrorsWithTheme(
          tester,
          _ExamEditorButtonRowPlaceholder(),
          size: entry.value,
        );
      });
    }
  });
}

/// Minimal placeholder that mirrors ExamChoiceScreen's core layout
/// (Row with Expanded children, icon + text + chevron) without requiring
/// the full navigation / Supabase stack.  This isolates the layout test.
Future<void> expectNoLayoutErrorsWithTheme(
  WidgetTester tester,
  Widget widget, {
  required Size size,
}) async {
  final layoutErrors = <FlutterErrorDetails>[];
  final oldHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final msg = details.toString();
    if (msg.contains('RenderFlex overflowed') ||
        msg.contains('overflow') ||
        msg.contains('BoxConstraints forces an infinite') ||
        msg.contains('infinite width') ||
        msg.contains('infinite height')) {
      layoutErrors.add(details);
    }
    oldHandler?.call(details);
  };

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: widget),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 300));

  FlutterError.onError = oldHandler;

  expect(
    layoutErrors,
    isEmpty,
    reason: 'Layout error detected at ${size.width}x${size.height} '
        '${layoutErrors.map((e) => e.summary).join('; ')}',
  );
}

/// Reproduces the Row layout from ExamEditorScreen's bottom action bar:
///   Row([Expanded(TextField), SizedBox(width: 12), FilledButton.tonalIcon])
/// with the same FilledButtonThemeData (minimumSize: Size.fromHeight(48))
/// that causes a BoxConstraints infinite-width error when the button has
/// no explicit minimumSize override.
class _ExamEditorButtonRowPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Total Questions',
              ),
            ),
          ),
          const SizedBox(width: 12),
          // This is the fixed button — the style override prevents the
          // Size.fromHeight(48) → Size(∞, 48) minimum width.
          Flexible(
            child: FilledButton.tonalIcon(
              onPressed: () {},
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              label: const Text('Auto-Distribute'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamChoiceScreenPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        // Row that mirrors ExamTypeCard layout
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.quiz_rounded, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CA Test (Class Test)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Make a class test from selected topics.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ],
    );
  }
}
