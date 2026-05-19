import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  Widget createTestApp() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: const MaterialApp(
        home: LessonEditorScreen(),
      ),
    );
  }

  group('LessonEditorScreen', () {
    testWidgets('renders all form fields', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Check that key form elements exist
      expect(find.text('Subject'), findsWidgets);
      expect(find.text('Mathematics'), findsAtLeast(1));
      expect(find.text('Class'), findsWidgets);
      expect(find.text('Topic'), findsWidgets);
      expect(find.text('Difficulty'), findsWidgets);
      expect(find.text('Week:'), findsOneWidget);
      expect(find.text('Generate'), findsOneWidget);

      // Check that Bloom\'s verbs chips are present
      expect(find.text('Remember'), findsOneWidget);
      expect(find.text('Understand'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('displays credit balance in app bar', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // AppBar shows credit balance as a lock-icon pill with a number
      final lockPill = find.byWidgetPredicate((w) {
        if (w is! Row) return false;
        final children = w.children.toList();
        return children
                .any((c) => c is Icon && (c.icon == Icons.lock_rounded)) &&
            children.any(
                (c) => c is Text && (c.data?.contains(RegExp(r'\d')) ?? false));
      });
      expect(lockPill, findsOneWidget);
    });

    testWidgets('topic validation requires input', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Scroll to and tap Generate without filling topic
      await tester.scrollUntilVisible(
        find.text('Generate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      // Should show validation error
      expect(find.text('Topic is required'), findsOneWidget);
    });

    testWidgets('can select different subject', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap subject dropdown
      await tester.tap(find.text('Mathematics').last);
      await tester.pumpAndSettle();

      // Select English
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
    });

    testWidgets('can select Bloom\'s verbs chips', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Tap a chip
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();

      // Tap another
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
    });

    testWidgets('week spinbox increments and decrements', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Initial week is 1
      expect(find.text('1'), findsWidgets);

      // Tap increment
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      // Tap decrement
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('generate callback is invoked with valid prompt',
        (tester) async {
      String? capturedPrompt;
      final result = {
        'raw': {
          'objectives': ['Learn X'],
          'vocabulary': ['Term1'],
          'materials': ['Book'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Quiz',
          'homework': 'Worksheet',
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            home: LessonEditorScreen(
              generateCallback: (prompt) async {
                capturedPrompt = prompt;
                return result;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill topic
      await tester.enterText(find.byType(TextFormField).first, 'Algebra');
      await tester.pumpAndSettle();

      // Scroll to and tap Generate
      await tester.scrollUntilVisible(
        find.text('Generate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      // Verify callback was called
      expect(capturedPrompt, isNotNull);
      expect(capturedPrompt, contains('Algebra'));
      expect(capturedPrompt, contains('Mathematics'));
      expect(capturedPrompt, contains('Week 1'));

      // Verify preview cards appear (after generation)
      expect(find.text('Learning Objectives'), findsOneWidget);
      expect(find.text('Key Vocabulary'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
    });

    testWidgets('save button persists to database', (tester) async {
      final result = {
        'raw': {
          'objectives': ['Learn X'],
          'vocabulary': ['Term1'],
          'materials': ['Book'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Quiz',
          'homework': 'Worksheet',
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            home: LessonEditorScreen(
              generateCallback: (prompt) async => result,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill topic and generate
      await tester.enterText(find.byType(TextFormField).first, 'Algebra');
      await tester.scrollUntilVisible(
        find.text('Generate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      // Wait for the Lesson generated successfully! SnackBar to auto-dismiss
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Scroll Save button into view (it's below preview cards)
      await tester.scrollUntilVisible(
        find.text('Save'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify saved in database
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      expect(lessons.first.subject, equals('Mathematics'));
      expect(lessons.first.topic, equals('Algebra'));
    });

    testWidgets('discard clears form fields', (tester) async {
      final result = {
        'raw': {
          'objectives': ['Learn X'],
          'vocabulary': ['Term1'],
          'materials': ['Book'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Quiz',
          'homework': 'Worksheet',
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            home: LessonEditorScreen(
              generateCallback: (prompt) async => result,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Fill topic and generate
      await tester.enterText(find.byType(TextFormField).first, 'Algebra');
      await tester.scrollUntilVisible(
        find.text('Generate'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();

      // Verify preview cards visible
      expect(find.text('Learning Objectives'), findsOneWidget);

      // Wait for the "Lesson generated successfully!" SnackBar to auto-dismiss
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Scroll Discard button into view (it's below preview cards)
      await tester.scrollUntilVisible(
        find.text('Discard'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap Discard
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Preview cards should be gone
      expect(find.text('Learning Objectives'), findsNothing);
      // Topic should be cleared
      expect(find.text('Algebra'), findsNothing);
    });
  });
}
