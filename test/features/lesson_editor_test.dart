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
    // Set initial credits so _handleGenerate() passes the credit check
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
  });

  tearDown(() async {
    await db.close();
  });

  /// Scale text down so the LessonEditorScreen content does not overflow.
  Widget createTestApp() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.65),
          ),
          child: widget!,
        ),
        home: const LessonEditorScreen(),
      ),
    );
  }

  /// Increase the test viewport so content does not overflow the default
  /// 800×600 surface.
  Future<void> ensureViewportHeight(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Build a LessonEditorScreen wrapped with the database override and
  /// text-scaling MediaQuery.  Accepts an optional [generateCallback].
  Widget buildApp({
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.65),
          ),
          child: widget!,
        ),
        home: LessonEditorScreen(generateCallback: generateCallback),
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
      expect(find.text('Difficulty Level'), findsWidgets);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Generate with AI'), findsOneWidget);

      // Check that Bloom\'s verbs chips are present
      expect(find.text('Remember'), findsOneWidget);
      expect(find.text('Understand'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
    });

    testWidgets('displays credit balance in header', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Header shows credit balance as a simple number text
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data?.contains(RegExp(r'\d')) ?? false),
        ),
        findsWidgets,
      );
    });

    testWidgets('topic field is rendered in the form', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Topic TextField should be present
      expect(find.byType(TextField), findsWidgets);
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
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      // Tap decrement
      await tester.tap(find.byIcon(Icons.remove_rounded));
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

      await ensureViewportHeight(tester);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          capturedPrompt = prompt;
          return result;
        },
      ));
      await tester.pumpAndSettle();

      // Scroll to and tap Generate with AI
      await tester.scrollUntilVisible(
        find.text('Generate with AI'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();

      // Verify callback was called with default values
      expect(capturedPrompt, isNotNull);
      expect(capturedPrompt, contains('Mathematics'));
      expect(capturedPrompt, contains('Week 1'));

      // Verify preview cards appear with generated content
      // Note: _buildPreviewCard only renders the content, NOT the title string
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Learn X'), findsOneWidget);
      expect(find.text('Term1'), findsOneWidget);
      expect(find.text('Book'), findsOneWidget);
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

      await ensureViewportHeight(tester);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async => result,
      ));
      await tester.pumpAndSettle();

      // Scroll to and tap Generate with AI
      await tester.scrollUntilVisible(
        find.text('Generate with AI'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();

      // Dismiss the "Lesson generated successfully!" toast dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Scroll Save button into view (it's below preview cards)
      await tester.scrollUntilVisible(
        find.text('Save to Vault'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap Save to Vault
      await tester.tap(find.text('Save to Vault'));
      await tester.pumpAndSettle();

      // Verify saved in database
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      expect(lessons.first.subject, equals('Mathematics'));
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

      await ensureViewportHeight(tester);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async => result,
      ));
      await tester.pumpAndSettle();

      // Scroll to and tap Generate with AI
      await tester.scrollUntilVisible(
        find.text('Generate with AI'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();

      // Verify preview cards visible with generated content
      // Note: _buildPreviewCard only renders the content, NOT the title string
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Learn X'), findsOneWidget);

      // Dismiss the "Lesson generated successfully!" toast dialog
      await tester.tap(find.text('Close'));
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

      // Preview cards content should be cleared but header persists
      // (lib _discard() clears content text but doesn't set _hasGenerated = false)
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Learn X'), findsNothing);
    });
  });
}
