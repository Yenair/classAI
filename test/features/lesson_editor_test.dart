import 'dart:convert';
// `isNotNull` is needed from the flutter_test matchers (expect(..., isNotNull));
// drift's column-expression helper of the same name would be ambiguous.
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

/// Builds a mock Supabase client whose `get-config` function fails fast so
/// [ConfigService.refresh] throws synchronously with no network I/O.
MockSupabaseClient buildMockSupabase() {
  final supabase = MockSupabaseClient();
  final functions = MockFunctionsClient();
  when(() => functions.invoke('get-config')).thenThrow(
    FunctionException(status: 500),
  );
  when(() => supabase.functions).thenReturn(functions);
  return supabase;
}

/// Returns an authenticated state with a non-free school so
/// _handleGenerate() passes the subscription-tier gate.
class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);
  final AuthStateData fixedState;
  @override
  AuthStateData build() => fixedState;
}

AuthStateData _authState(String tier) {
  final now = DateTime.now();
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: Teacher(
      localId: 1,
      serverId: '00000000-0000-0000-0000-000000000001',
      email: 'teacher@test.com',
      teacherName: 'Test Teacher',
      role: 'teacher',
      schoolLocalId: 1,
      schoolServerId: '00000000-0000-0000-0000-000000000010',
      isActive: true,
      forcePasswordReset: false,
      passwordHashVersion: 1,
      schoolKeyWrapped: 'wrapped',
      lastCreditRefillDate: now,
      createdAt: now,
      updatedAt: now,
      updateCounter: 0,
      isDeleted: false,
      lastModifiedBy: null,
      themeMode: 'system',
    ),
    currentSchool: School(
      localId: 1,
      serverId: '00000000-0000-0000-0000-000000000010',
      schoolName: 'Test School',
      shortCode: 'TST',
      logoUrl: null,
      subscriptionTier: tier,
      activeCurriculum: 'nerdc',
      activeCurriculumVersion: '2024',
      totalSeats: 5,
      schoolMasterKeyWrapped: 'wrapped',
      adminRecoveryEmail: null,
      adminRecoveryEmailVerified: false,
      createdAt: now,
      updatedAt: now,
      updateCounter: 0,
      isDeleted: false,
      lastModifiedBy: null,
    ),
  );
}

AuthStateData _eliteAuthState() => _authState('elite');

/// Default lesson-note AI result (the `lessonNote` prompt contract).
final Map<String, dynamic> _defaultLessonResult = {
  'raw': {
    'objectives': ['Learn X'],
    'vocabulary': ['Term1'],
    'materials': ['Book'],
    'presentation': {'step1': 'Intro'},
    'assessment': 'Quiz',
    'homework': 'Worksheet',
  },
};

/// Default structured-questions AI result (the `lessonQuestions` prompt
/// contract — the same `{mcq, theory, subjective}` shape `examQuestions`
/// returns).
final Map<String, dynamic> _defaultQuestionsResult = {
  'raw': {
    'mcq': [
      {
        'question': 'What is 2 + 2?',
        'options': {'A': '3', 'B': '4', 'C': '5', 'D': '6'},
        'correct': 'B',
      },
    ],
    'theory': [
      {
        'question': 'Explain algebraic expressions.',
        'modelAnswer':
            'An algebraic expression combines numbers and variables with operations.',
      },
    ],
    'subjective': [
      {
        'question': 'Describe solving a linear equation.',
        'answer':
            'Isolate the variable by applying inverse operations to both sides of the equation.',
      },
    ],
  },
};

/// Returns a generateCallback that dispatches on prompt content: the lesson
/// prompt (which contains `## Learning Objectives`) returns the lesson shape;
/// any other prompt (the questions prompt) returns the questions shape.
Future<Map<String, dynamic>> Function(String prompt) dispatchCallback() {
  return (prompt) async {
    if (prompt.contains('## Learning Objectives')) {
      return _defaultLessonResult;
    }
    return _defaultQuestionsResult;
  };
}

/// Mocks the connectivity_plus method channel so PlatformHelper.isOnline()
/// returns the given value. Copied pattern from auth_state_machine_test.
void _mockConnectivityChannel({bool isOnline = false}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'check') {
        return isOnline ? <String>['wifi'] : <String>['none'];
      }
      return null;
    },
  );
}

/// Types into the Topic TextField on the entry screen. It is the first (and
/// only) TextField in the tree on a fresh (non-generated) blank lesson, so
/// find.byType(TextField).first is reliable.
Future<void> _enterTopic(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

/// Generates a lesson through the new entry screen: ensures a topic is
/// entered (the Create button is disabled while the topic is empty), taps
/// "Create lesson", then pumps until the generation flow (both AI calls +
/// the auto-save) settles and dismisses the success toast.
Future<void> _tapGenerate(WidgetTester tester) async {
  final topicField = find.byType(TextField).first;
  final controller = tester.widget<TextField>(topicField).controller;
  if (controller == null || controller.text.trim().isEmpty) {
    await _enterTopic(tester, 'Algebraic Expressions');
  }
  final createButton = find.text('Create lesson');
  await tester.ensureVisible(createButton);
  await tester.pumpAndSettle();
  await tester.tap(createButton);
  await tester.pumpAndSettle();
  // Let the async _saveLesson inside the post-frame callback complete.
  await tester.pump(const Duration(seconds: 1));
  // Dismiss whatever success surface is showing. The generation toast is a
  // route-based dialog whose message (AppToast renders it as
  // SelectableText) is the only SelectableText in the tree on this screen,
  // so it safely anchors the dialog route: popping it dismisses the toast
  // without depending on a specific dismiss label/button. If no toast is
  // showing there is nothing to pop.
  final toastMessage = find.byType(SelectableText);
  if (toastMessage.evaluate().isNotEmpty) {
    Navigator.of(tester.element(toastMessage.first)).pop();
  }
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  final mockSupabase = buildMockSupabase();

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    // Set initial credits so _handleGenerate() passes the credit check
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
    // In-memory SharedPreferences store: the visible-section preferences
    // default to hidden, and PlatformHelper.isEditorMode has a value to read.
    SharedPreferences.setMockInitialValues({});
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
  /// text-scaling MediaQuery. Accepts an optional [generateCallback], an
  /// optional [authState] (defaults to elite), and an optional [lessonId]
  /// to edit an existing lesson.
  Widget buildApp({
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
    AuthStateData? authState,
    int? lessonId,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(authState ?? _eliteAuthState()),
        ),
        configServiceProvider.overrideWithValue(
          ConfigService(client: mockSupabase),
        ),
      ],
      child: MaterialApp(
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.65),
          ),
          child: widget!,
        ),
        home: LessonEditorScreen(
          generateCallback: generateCallback,
          lessonId: lessonId,
        ),
      ),
    );
  }

  group('LessonEditorScreen', () {
    testWidgets('renders all form fields', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // The new blank-lesson entry screen: a large topic input, a compact
      // context line, and the single primary create action.
      expect(find.text('Lesson topic'), findsOneWidget);
      expect(find.text('Mathematics · JSS 1 · Week 1'), findsOneWidget);
      expect(find.text('Create lesson'), findsOneWidget);

      // Tapping the context line opens the Lesson details bottom sheet.
      await tester.ensureVisible(find.text('Mathematics · JSS 1 · Week 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mathematics · JSS 1 · Week 1'));
      await tester.pumpAndSettle();

      // The sheet exposes Subject, Class, Week and the Scheme topic selector.
      expect(find.text('Lesson details'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Class'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);
      expect(find.text('Scheme topic'), findsOneWidget);
    });

    testWidgets('displays credit balance in header', (tester) async {
      _mockConnectivityChannel(isOnline: true);
      // Use a narrow viewport so the mobile header (which shows the credit
      // balance) is rendered instead of the desktop tool header.
      await tester.binding.setSurfaceSize(const Size(600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Header shows the seeded offline credit balance as a number.
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('topic field is rendered in the form', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // The entry screen's topic TextField should be present.
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('can select different subject', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Open the Lesson details sheet from the context line.
      await tester.tap(find.text('Mathematics · JSS 1 · Week 1'));
      await tester.pumpAndSettle();

      // Change the Subject inside the sheet.
      await tester.tap(find.text('Mathematics').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      // Close the sheet.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The context line reflects the new subject.
      expect(find.text('English · JSS 1 · Week 1'), findsOneWidget);
      expect(find.text('Mathematics · JSS 1 · Week 1'), findsNothing);
    });

    testWidgets('can select Bloom\'s verbs chips', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock the lesson so the editable document (which contains the
      // Advanced Settings panel) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Advanced Settings is collapsed by default: its Bloom chips are not
      // built yet.
      expect(find.text('Advanced Settings'), findsOneWidget);
      expect(find.text('Remember'), findsNothing);

      // Expand the panel.
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();

      // The Bloom's verbs chips are now visible.
      expect(find.text('Cognitive Objectives (Bloom\'s)'), findsOneWidget);
      expect(find.text('Remember'), findsOneWidget);

      // Tapping a chip selects it: a check icon appears inside its row.
      final rememberChip = find
          .ancestor(of: find.text('Remember'), matching: find.byType(Row))
          .first;
      await tester.ensureVisible(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: rememberChip,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Remember'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: rememberChip,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );

      // Multi-select: another chip can be selected too.
      await tester.ensureVisible(find.text('Analyze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find
              .ancestor(of: find.text('Analyze'), matching: find.byType(Row))
              .first,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('week spinbox increments and decrements', (tester) async {
      await ensureViewportHeight(tester);

      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // Open the Lesson details sheet to reach the Week stepper.
      await tester.tap(find.text('Mathematics · JSS 1 · Week 1'));
      await tester.pumpAndSettle();

      // Initial week is 1.
      expect(find.text('1'), findsWidgets);

      // Tap increment.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      // Close the sheet; the context line reflects the new week.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics · JSS 1 · Week 2'), findsOneWidget);

      // Reopen the sheet and decrement back to week 1.
      await tester.tap(find.text('Mathematics · JSS 1 · Week 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics · JSS 1 · Week 1'), findsOneWidget);
    });

    testWidgets('generate callback is invoked with valid prompts',
        (tester) async {
      String? lessonPrompt;
      String? questionsPrompt;
      final result = _defaultLessonResult;

      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      // Vocabulary and Materials are optional sections: enable them via the
      // persisted preferences so the locked preview shows them. The keys are
      // scoped per teacher (test teacher id + '_' + base key).
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_vocabulary':
            true,
        '00000000-0000-0000-0000-000000000001_lesson_visible_materials': true,
      });

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) {
            lessonPrompt = prompt;
            return result;
          }
          questionsPrompt = prompt;
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The lesson prompt was sent with the default values.
      expect(lessonPrompt, isNotNull);
      expect(lessonPrompt, contains('Mathematics'));
      expect(lessonPrompt, contains('Week 1'));

      // The structured-questions prompt was sent too (elite tier) and reuses
      // the combined question contract with Bloom's levels.
      expect(questionsPrompt, isNotNull);
      expect(questionsPrompt, contains('Generate 5 MCQ questions'));
      expect(questionsPrompt, contains('cognitive levels'));

      // After generation the preview is in the locked state: the header and a
      // locked overlay are shown, and the full generated document is rendered
      // read-only beneath them. Every section is shown in full — locked
      // content stays readable, not truncated. Vocabulary and Materials
      // render as bulleted lists in the locked state.
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Locked — Preview only'), findsOneWidget);
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.textContaining('Learn X'), findsOneWidget);
      expect(find.text('Vocabulary'), findsOneWidget);
      expect(find.textContaining('Term1'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.textContaining('Book'), findsOneWidget);
      expect(find.text('Presentation'), findsOneWidget);
      expect(find.text('Introduction'), findsOneWidget);
      expect(find.text('step1: Intro'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Quiz'), findsOneWidget);
      expect(find.text('Homework'), findsOneWidget);
      expect(find.text('Worksheet'), findsOneWidget);
    });

    testWidgets('save button persists to database', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Verify lesson was auto-saved to database during generation
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      expect(lessons.first.subject, equals('Mathematics'));
    });

    testWidgets('saves structured assessment questions inside content',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      final content = jsonDecode(lessons.first.content) as Map<String, dynamic>;
      final questions = content['questions'] as Map<String, dynamic>;
      expect((questions['mcqs'] as List).length, equals(1));
      expect((questions['theory'] as List).length, equals(1));
      expect((questions['subjective'] as List).length, equals(1));
      // Legacy free-text sections are preserved alongside the questions.
      expect(content['assessment'], equals('Quiz'));
      expect(content['homework'], equals('Worksheet'));
    });

    testWidgets('saves lesson without questions when question generation fails',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) {
            return _defaultLessonResult;
          }
          throw Exception('questions failed');
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The lesson still saved (no partial-data loss), without questions.
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      final content = jsonDecode(lessons.first.content) as Map<String, dynamic>;
      expect(content.containsKey('questions'), isFalse);
    });

    testWidgets('lesson generation failure creates no rows and no sync entry',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          throw Exception('lesson failed');
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // No partial data: no lesson row and no lessons sync entry.
      final lessons = await db.select(db.lessons).get();
      expect(lessons, isEmpty);
      final syncEntries = await db.select(db.syncQueue).get();
      expect(
        syncEntries.where((e) => e.queueTable == 'lessons'),
        isEmpty,
      );
    });

    testWidgets(
        'basic tier generates lesson without questions prompt or questions',
        (tester) async {
      var questionsPromptSeen = false;
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        authState: _authState('basic'),
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) {
            return _defaultLessonResult;
          }
          questionsPromptSeen = true;
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      expect(questionsPromptSeen, isFalse);
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      final content = jsonDecode(lessons.first.content) as Map<String, dynamic>;
      expect(content.containsKey('questions'), isFalse);

      // Unlock so the editable document (with the tier-gated Assessment
      // section) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — 10 previews left');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Basic tier: the Assessment section shows the upgrade blocker, not
      // the question cards.
      final blocker = find.text(
          'Upgrade to Standard or Elite to view assessment questions.');
      await tester.ensureVisible(blocker);
      await tester.pumpAndSettle();
      expect(blocker, findsOneWidget);
      expect(find.text('Request Upgrade'), findsOneWidget);
      expect(find.text('What is 2 + 2?'), findsNothing);
    });

    testWidgets('old lessons without questions load safely', (tester) async {
      final id = await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Algebraic Expressions',
          difficulty: 'medium',
          bloomsVerbs: '',
          curriculum: 'NERDC',
          content: jsonEncode({
            'objectives': ['Old objective'],
            'vocabulary': ['Term'],
            'materials': ['Book'],
            'presentation': {'step1': 'Intro'},
            'assessment': 'Legacy quiz text',
            'homework': 'Worksheet',
          }),
          teacherServerId:
              const Value('00000000-0000-0000-0000-000000000001'),
          schoolServerId:
              const Value('00000000-0000-0000-0000-000000000010'),
        ),
      );

      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      // The lesson loads without crashing; the locked preview shows the
      // restored objectives text as a bulleted list.
      expect(find.textContaining('Old objective'), findsOneWidget);
      expect(find.text('Preview Generated Content'), findsOneWidget);
    });

    testWidgets('discard clears form fields', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Generated content is visible in the locked preview.
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.textContaining('Learn X'), findsOneWidget);

      // Scroll the Discard action into view (it's below the document).
      await tester.scrollUntilVisible(
        find.text('Discard'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Tap Discard.
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      // Discard returns to the blank entry screen and clears the topic.
      expect(find.text('Lesson topic'), findsOneWidget);
      expect(find.text('Create lesson'), findsOneWidget);
      expect(find.text('Preview Generated Content'), findsNothing);
      final topicField = tester.widget<TextField>(find.byType(TextField).first);
      expect(topicField.controller!.text, isEmpty);
    });

    testWidgets(
        'visible sections sheet reveals hidden sections and Suggested Images collapses',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      // All optional sections default to hidden.
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Vocabulary, Materials and Suggested Images are hidden by default.
      expect(find.text('Vocabulary'), findsNothing);
      expect(find.text('Materials'), findsNothing);
      expect(find.text('Suggested Images'), findsNothing);

      // Open the Visible sections sheet from the document header.
      final settingsIcon = find.byIcon(Icons.settings_rounded);
      await tester.ensureVisible(settingsIcon);
      await tester.pumpAndSettle();
      await tester.tap(settingsIcon);
      await tester.pumpAndSettle();
      expect(find.text('Visible sections'), findsOneWidget);

      // Enable Vocabulary, Materials and Suggested Images.
      await tester.tap(find.widgetWithText(SwitchListTile, 'Vocabulary'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'Materials'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(
          SwitchListTile, 'Suggested Images / Diagrams'));
      await tester.pumpAndSettle();

      // Close the sheet.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      // Vocabulary and Materials now appear, with their content.
      expect(find.text('Vocabulary'), findsOneWidget);
      expect(find.textContaining('Term1'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.textContaining('Book'), findsOneWidget);

      // Unlock the lesson so the editable document (including the Suggested
      // Images section) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Suggested Images is a collapsible section that starts collapsed:
      // the header is visible but the body is not built.
      final suggestedImagesHeader = find.text('Suggested Images');
      expect(suggestedImagesHeader, findsOneWidget);
      expect(find.text('No images generated yet.'), findsNothing);

      // Expanding the section reveals the empty-state body.
      await tester.ensureVisible(suggestedImagesHeader);
      await tester.pumpAndSettle();
      await tester.tap(suggestedImagesHeader);
      await tester.pumpAndSettle();
      expect(find.text('No images generated yet.'), findsOneWidget);

      // Collapsing it again hides the body.
      await tester.tap(suggestedImagesHeader);
      await tester.pumpAndSettle();
      expect(find.text('No images generated yet.'), findsNothing);
    });

    testWidgets(
        'regenerating homework shows undo banner and Undo restores previous text',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      // Route getApplicationDocumentsDirectory() to a real, existing
      // directory so the homework undo snapshot is actually written by
      // _snapshotHomework(). '.dart_tool' exists after pub get and is
      // git-ignored, so a leftover snapshot never pollutes the repo.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async {
          if (call.method == 'getApplicationDocumentsPath') {
            return '.dart_tool';
          }
          return null;
        },
      );

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) {
            return _defaultLessonResult;
          }
          if (prompt.contains('Regenerate only the Homework')) {
            return {'raw': {'homework': 'New Homework'}};
          }
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock so the editable document (with the homework regenerate
      // button) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // The generated homework is on screen before regeneration.
      expect(find.textContaining('Worksheet'), findsOneWidget);

      // Trigger "Regenerate homework only". The flow writes a real undo
      // snapshot file, awaits the (mock) AI callback, and saves the lesson —
      // real asynchronous I/O that only completes inside tester.runAsync.
      await tester.ensureVisible(find.text('Regenerate homework only'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Regenerate homework only'));
        // Poll with real delays + pumps until the regeneration completes
        // (bounded: 100 × 20 ms of real time).
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find
              .text('Homework regenerated.')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });

      // Dismiss the success toast (if still showing) so the only remaining
      // "Homework regenerated." text is the persistent undo banner.
      await tester.pumpAndSettle();
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Homework regenerated.'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(find.textContaining('New Homework'), findsOneWidget);

      // Tapping Undo restores the previous homework text and dismisses the
      // banner. The restore path (_restoreHomeworkUndo) also deletes the
      // undo snapshot file. It reads and deletes a real file, so it also
      // runs inside runAsync. The banner sits at the top of the scroll
      // view, so bring it into view first. ensureVisible aligns the target
      // with the viewport's leading edge, so scrolling the Undo text itself
      // would park it only a few pixels from the very top of the screen.
      // Scroll the banner's message text instead so the Undo action sits
      // comfortably in view and is reliably hit-testable.
      await tester.ensureVisible(find.text('Homework regenerated.'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(TextButton, 'Undo'));
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
          if (find.text('Homework regenerated.').evaluate().isEmpty) {
            break;
          }
        }
        // Give the rest of the restore path (lesson save, snapshot file
        // deletion, undo toast) a moment to finish inside the real zone.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });

      await tester.pumpAndSettle();
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Homework regenerated.'), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Dismiss'), findsNothing);
      expect(find.textContaining('Worksheet'), findsOneWidget);
      expect(find.textContaining('New Homework'), findsNothing);
    });
  });
}
