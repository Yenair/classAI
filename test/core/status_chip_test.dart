import 'package:classai/core/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'scheme status chips share the pending / approved / rejected / draft '
    'mapping with icon + text',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                schemeStatusChip('pending'),
                schemeStatusChip('approved'),
                schemeStatusChip('rejected'),
                schemeStatusChip('draft'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Pending'), findsOneWidget);
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);
      expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
    },
  );

  testWidgets(
    'every status chip pairs an icon with a label — never color-only',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                examRowStatusChip(unlocked: false),
                examRowStatusChip(unlocked: true),
                lessonRowStatusChip(completed: true, unlocked: true, generated: false),
                lessonRowStatusChip(completed: false, unlocked: false, generated: true),
                lessonStatusChipFor('generated'),
                schemeStatusChip('none', fallbackLabel: 'No Scheme'),
                schemeLinkedChip(),
              ],
            ),
          ),
        ),
      );

      final chips = tester.widgetList<StatusChip>(find.byType(StatusChip));
      expect(chips, hasLength(7));
      for (final chip in chips) {
        expect(chip.label, isNotEmpty);
        expect(chip.icon, isNotNull);
      }
      expect(find.text('Draft'), findsOneWidget);
      expect(find.text('Unlocked'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Generated'), findsWidgets);
      expect(find.text('No Scheme'), findsOneWidget);
      expect(find.text('Linked'), findsOneWidget);
    },
  );
}
