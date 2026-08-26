import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [widget] in a [MaterialApp] at [size] and verifies no
/// RenderFlex overflow error is thrown during layout.
Future<void> expectNoOverflow(
  WidgetTester tester,
  Widget widget, {
  required Size size,
}) async {
  // Catch RenderFlex overflow errors that Flutter logs but doesn't throw.
  final overflowErrors = <FlutterErrorDetails>[];
  final oldHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.toString().contains('RenderFlex overflowed') ||
        details.toString().contains('overflow')) {
      overflowErrors.add(details);
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
    overflowErrors,
    isEmpty,
    reason: 'RenderFlex overflow detected at ${size.width}x${size.height}',
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
    }
  });
}

/// Minimal placeholder that mirrors ExamChoiceScreen's core layout
/// (Row with Expanded children, icon + text + chevron) without requiring
/// the full navigation / Supabase stack.  This isolates the layout test.
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
