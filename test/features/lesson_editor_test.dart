import 'dart:convert';
// These matchers are needed from flutter_test (for example, expect(..., isNull));
// Drift's column-expression helpers of the same names would be ambiguous.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

Map<String, dynamic> _generatedLessonContent() {
  return {
    'objectives': ['Learn X'],
    'vocabulary': ['Term1'],
    'materials': ['Book'],
    'presentation': {'step1': 'Intro'},
    'assessment': 'Quiz',
    'homework': 'Worksheet',
    'questions': {
      'mcqs': [
        {
          'question': 'What is 2 + 2?',
          'options': {'A': '3', 'B': '4', 'C': '5', 'D': '6'},
          'correct': 'B',
        },
      ],
      'theory': [
        {
          'question': 'Explain algebraic expressions.',
          'modelAnswer': 'An algebraic expression combines numbers and variables.',
        },
      ],
      'subjective': <Map<String, dynamic>>[],
    },
    'references': [
      {'text': 'Original reference', 'origin': 'ai'},
    ],
    'diagrams': [
      {'description': 'A classroom diagram'},
    ],
  };
}

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

Future<int> _insertLessonFixture(
  AppDatabase db, {
  required String topic,
  String subject = 'Mathematics',
  String classLevel = 'JSS 1',
  int week = 1,
  String status = 'draft',
  bool isUnlocked = false,
  Map<String, dynamic>? content,
}) {
  return db.lessonsDao.insertLesson(
    LessonsCompanion.insert(
      subject: subject,
      classLevel: classLevel,
      week: week,
      topic: topic,
      difficulty: 'medium',
      bloomsVerbs: 'Remember,Understand',
      curriculum: 'NERDC',
      content: jsonEncode(content ?? <String, dynamic>{}),
      status: Value(status),
      isUnlocked: Value(isUnlocked),
      teacherServerId:
          const Value('00000000-0000-0000-0000-000000000001'),
      schoolServerId:
          const Value('00000000-0000-0000-0000-000000000010'),
    ),
  );
}

Future<void> _unlockGeneratedLesson(WidgetTester tester) async {
  final unlockButton = find.textContaining('Unlock').first;
  await tester.ensureVisible(unlockButton);
  await tester.pumpAndSettle();
  await tester.tap(unlockButton);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 1));
  final closeButton = find.text('Close');
  if (closeButton.evaluate().isNotEmpty) {
    await tester.tap(closeButton.first);
    await tester.pumpAndSettle();
  }
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
  final generateButton = find.text('Generate with AI');
  await tester.ensureVisible(generateButton);
  await tester.pumpAndSettle();
  await tester.tap(generateButton);
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

  Widget buildRoutedApp({
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
    int? lessonId,
  }) {
    final router = GoRouter(
      initialLocation: '/editor',
      routes: [
        GoRoute(
          path: '/editor',
          builder: (context, state) => LessonEditorScreen(
            generateCallback: generateCallback,
            lessonId: lessonId,
          ),
        ),
        GoRoute(
          path: '/lessons',
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('Lessons list route')),
          ),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_eliteAuthState()),
        ),
        configServiceProvider.overrideWithValue(
          ConfigService(client: mockSupabase),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(0.65),
          ),
          child: widget!,
        ),
      ),
    );
  }

  group('LessonEditorScreen', () {
    testWidgets('renders entry screen with Generate with AI button', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // The blank-lesson entry screen: a large topic input and the single
      // primary create action. No Subject/Class/Week dropdowns.
      expect(find.text('Lesson topic'), findsOneWidget);
      expect(find.text('Generate with AI'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);
      // No context line or lesson details sheet.
      expect(find.textContaining('·'), findsNothing);
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

    testWidgets('can select Bloom\'s verbs chips', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // After generation, the Advanced Settings card is visible but collapsed
      // by default. Expand it to access Bloom chips.
      expect(find.text('Advanced Settings'), findsOneWidget);
      expect(find.text('Remember'), findsNothing);

      // Expand Advanced Settings.
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
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
      // tab) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — 10 previews left');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tap the Assessment tab to see the tier-gated content.
      await tester.tap(find.text('Assessment'));
      await tester.pumpAndSettle();

      // Basic tier: the Assessment tab shows the upgrade blocker, not
      // the question cards.
      expect(find.text('Assessment questions'), findsOneWidget);
      expect(find.text('Upgrade Plan'), findsOneWidget);
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

    testWidgets('floating action area appears after generation', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // After generation, the floating action area is visible with
      // the expected controls.
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Visible Sections'), findsOneWidget);
    });

    testWidgets(
        'visible sections sheet reveals hidden sections and Suggested Images opens',
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

      // Unlock the lesson so the Diagrams tab is available, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tap the Diagrams tab to see Suggested Images.
      await tester.tap(find.text('Diagrams'));
      await tester.pumpAndSettle();

      // Suggested Images is expanded by default after it becomes visible.
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
      // button in the Assessment tab) is rendered, then dismiss the unlock toast.
      final unlockButton = find.text('Unlock — Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tap the Assessment tab to see homework controls.
      await tester.tap(find.text('Assessment'));
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

    testWidgets('generate card switches from Generate with AI to Regenerate after generation', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      expect(find.text('Generate with AI'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);

      await _tapGenerate(tester);

      // After generation, only the regeneration primary action remains.
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Generate with AI'), findsNothing);
      expect(find.text('Preview Generated Content'), findsOneWidget);
    });

    testWidgets('Advanced Settings only contains Difficulty and Bloom after tab move', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // After generation, Advanced Settings card is visible (collapsed).
      expect(find.text('Advanced Settings'), findsOneWidget);

      // Expand Advanced Settings — only Difficulty and Bloom remain.
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Difficulty'), findsOneWidget);
      expect(find.text("Cognitive Objectives (Bloom's)"), findsOneWidget);
      // Assessment format, question counts, and auto-image are NOT here.
      expect(find.text('Assessment Format'), findsNothing);
      expect(find.text('Question Counts'), findsNothing);
      expect(find.text('Auto-generate first image'), findsNothing);
    });

    testWidgets('unlocked preview shows tab chips not flat sections', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock the lesson.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tab chips are visible.
      expect(find.text('Lesson Note'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);

      // Lesson Note tab is active: objectives are visible on tab 0.
      expect(find.text('Objectives'), findsWidgets);
    });

    testWidgets(
        'draft lesson with partial content shows unlocked Generate with AI',
        (tester) async {
      final id = await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Algebraic Expressions',
          difficulty: 'medium',
          bloomsVerbs: 'Remember,Understand',
          curriculum: 'NERDC',
          content: jsonEncode({
            'objectives': ['Partially saved objective'],
            'vocabulary': <String>[],
            'materials': <String>[],
            'presentation': <String, dynamic>{},
            'assessment': '',
            'homework': '',
          }),
          status: const Value('draft'),
          isUnlocked: const Value(false),
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

      expect(find.text('Generate with AI'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);
      expect(find.text('Locked — Preview only'), findsNothing);
      expect(find.text('Preview Generated Content'), findsNothing);
    });

    testWidgets('existing lesson loading still works', (tester) async {
      final id = await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Algebraic Expressions',
          difficulty: 'medium',
          bloomsVerbs: 'Remember,Understand',
          curriculum: 'NERDC',
          content: jsonEncode({
            'objectives': ['Learn algebraic expressions'],
            'vocabulary': ['Variable', 'Constant'],
            'materials': ['Textbook'],
            'presentation': {'step1': 'Introduction'},
            'assessment': 'Quiz on expressions',
            'homework': 'Practice problems',
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
      // restored objectives text.
      expect(find.textContaining('Learn algebraic expressions'), findsOneWidget);
      expect(find.text('Preview Generated Content'), findsOneWidget);
    });

    testWidgets(
        'after generation, topic field is disabled and requires double-tap to edit',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The topic field in the Generate card is read-only after generation.
      final topicField = find.byType(TextField).first;
      final textField = tester.widget<TextField>(topicField);
      expect(textField.readOnly, isTrue);

      // Double-tap shows the confirmation dialog.
      await tester.tap(topicField, warnIfMissed: false);
      await tester.pump();
      await tester.tap(topicField, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Edit Topic?'), findsOneWidget);
      expect(find.text('Proceed to Edit'), findsOneWidget);

      // Cancel keeps the field read-only.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(topicField).readOnly, isTrue);

      // Double-tap again and confirm to enable editing.
      await tester.tap(topicField, warnIfMissed: false);
      await tester.pump();
      await tester.tap(topicField, warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proceed to Edit'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(topicField).readOnly, isFalse);
    });

    testWidgets(
        'tool header subtitle is removed',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The tool header subtitle should not be present.
      expect(
        find.text('Configure parameters to generate high-quality, localized educational content.'),
        findsNothing,
      );
      // But the main title should still be present.
      expect(find.text('Lesson Editor'), findsOneWidget);
    });

    testWidgets(
        'single completion control in floating action area after unlock',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock the lesson so the floating action area shows completion control.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // There should be exactly one 'Mark Completed' button (in the floating
      // action area), not duplicated in the preview footer.
      expect(find.text('Mark Completed'), findsOneWidget);
      // The old 'Mark Lesson as Completed' button should not exist.
      expect(find.text('Mark Lesson as Completed'), findsNothing);
    });

    testWidgets(
        'curated reference appears when AI returns a real textbook title',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      // Return a lesson with a curated textbook reference.
      final curatedResult = {
        'raw': {
          'objectives': ['Learn fractions'],
          'vocabulary': ['Numerator'],
          'materials': ['Textbook'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Quiz',
          'homework': 'Worksheet',
          'references': [
            {'title': 'New General Mathematics for Junior Secondary Schools'},
          ],
        },
      };

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) {
            return curatedResult;
          }
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Verify the reference was saved in the lesson content.
      final lessons = await db.select(db.lessons).get();
      expect(lessons.length, equals(1));
      final content = jsonDecode(lessons.first.content) as Map<String, dynamic>;
      final refs = content['references'] as List<dynamic>;
      expect(refs.length, equals(1));
      expect(refs[0]['text'],
          equals('New General Mathematics for Junior Secondary Schools'));
      expect(refs[0]['origin'], equals('curated'));
    });

    testWidgets(
        'empty references show empty state in References sheet',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // 'View References' is shown in the locked preview (before unlock).
      final refsButton = find.text('View References');
      await tester.ensureVisible(refsButton);
      await tester.pumpAndSettle();
      await tester.tap(refsButton);
      await tester.pumpAndSettle();

      // dispatchCallback returns no references, so the empty state
      // message should be shown.
      expect(find.text('No source references provided.'), findsOneWidget);
    });

    testWidgets(
        'no fabricated page or chapter in curated references',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      // Return a reference with a curated title but no page/chapter.
      final result = {
        'raw': {
          'objectives': ['Learn algebra'],
          'vocabulary': ['Variable'],
          'materials': ['Textbook'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Quiz',
          'homework': 'Worksheet',
          'references': [
            {
              'title':
                  'New General Mathematics for Junior Secondary Schools',
            },
          ],
        },
      };

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) return result;
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The saved reference should contain only the title — no page,
      // chapter, or author fields.
      final lessons = await db.select(db.lessons).get();
      final content = jsonDecode(lessons.first.content) as Map<String, dynamic>;
      final refs = content['references'] as List<dynamic>;
      expect(refs.length, equals(1));
      final ref = refs[0] as Map<String, dynamic>;
      expect(ref.containsKey('page'), isFalse);
      expect(ref.containsKey('chapter'), isFalse);
      expect(ref.containsKey('author'), isFalse);
      expect(ref['text'],
          equals('New General Mathematics for Junior Secondary Schools'));
    });

    testWidgets('four tabs appear after unlock in correct order', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock the lesson.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // All four tabs are visible in order (References hidden by default).
      expect(find.text('Lesson Note'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);
      // References not visible (default toggle is off).
      expect(find.text('References'), findsNothing);

      // Tap Assessment, then Diagrams to verify they work.
      await tester.tap(find.text('Assessment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagrams'));
      await tester.pumpAndSettle();
    });

    testWidgets('References tab hidden unless visible toggle is enabled', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      // Enable the references visible toggle.
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      });

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // With toggle enabled, References tab appears as fourth tab.
      expect(find.text('Lesson Note'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);
      expect(find.text('References'), findsOneWidget);
    });

    testWidgets('Homework appears in Assessment tab not Lesson Note', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Homework should NOT appear on the Lesson Note tab (tab 0).
      // It should appear on the Assessment tab (tab 1).
      // First check that Lesson Note tab does NOT show Homework header.
      // The PageView starts on tab 0, so Homework shouldn't be rendered.
      expect(find.text('Homework'), findsNothing);

      // Tap Assessment tab.
      await tester.tap(find.text('Assessment'));
      await tester.pumpAndSettle();

      // Now Homework should appear.
      expect(find.text('Homework'), findsOneWidget);
    });

    testWidgets('format selector and question counts appear in Assessment tab', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Tap Assessment tab.
      await tester.tap(find.text('Assessment'));
      await tester.pumpAndSettle();

      // Format selector and question counts are visible.
      expect(find.text('Assessment Format'), findsOneWidget);
      expect(find.text('Question Counts'), findsOneWidget);
      expect(find.text('Objective'), findsOneWidget);
    });

    testWidgets('include diagram toggle appears in Advanced Settings', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Expand Advanced Settings to reveal the toggle.
      await tester.ensureVisible(find.text('Advanced Settings'));
      await tester.tap(find.text('Advanced Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Include diagram generation'), findsOneWidget);
    });

    testWidgets('topic context line shows Subject Class Week on Lesson Note tab', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Lesson Note tab shows the context line with subject, class, week.
      expect(find.textContaining('\u00b7'), findsOneWidget);
    });

    testWidgets('keyboard arrow switching is ignored while a text field has focus', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Unlock.
      final unlockButton = find.text('Unlock \u2014 Unlimited previews');
      await tester.ensureVisible(unlockButton);
      await tester.pumpAndSettle();
      await tester.tap(unlockButton);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Focus the objectives text field on the Lesson Note tab.
      // Tap into the Objectives section to get a TextFormField focused.
      final objectivesField = find.byType(TextFormField).first;
      await tester.ensureVisible(objectivesField);
      await tester.tap(objectivesField);
      await tester.pumpAndSettle();

      // Send right arrow key — should NOT switch tabs because a field is focused.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Still on Lesson Note tab (Objectives visible, Assessment tab content not visible).
      expect(find.text('Objectives'), findsWidgets);
      expect(find.text('Assessment Format'), findsNothing);
    });

    testWidgets(
        'draft topic selector filters by class and subject and routes new topics',
        (tester) async {
      final currentId = await _insertLessonFixture(
        db,
        topic: 'Current draft',
        week: 1,
      );
      await _insertLessonFixture(
        db,
        topic: 'Matching draft',
        week: 4,
      );
      await _insertLessonFixture(
        db,
        topic: 'Wrong class draft',
        classLevel: 'JSS 2',
      );
      await _insertLessonFixture(
        db,
        topic: 'Wrong subject draft',
        subject: 'English Studies',
      );
      await _insertLessonFixture(
        db,
        topic: 'Generated lesson',
        status: 'generated',
      );

      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildRoutedApp(lessonId: currentId));
      await tester.pumpAndSettle();

      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.text('LESSON TOPIC'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField).first);
      await tester.pumpAndSettle();
      expect(find.text('Current draft'), findsOneWidget);
      expect(find.text('Matching draft'), findsOneWidget);
      expect(find.text('Wrong class draft'), findsNothing);
      expect(find.text('Wrong subject draft'), findsNothing);
      expect(find.text('Generated lesson'), findsNothing);
      expect(find.text('Create new topic'), findsOneWidget);

      await tester.tap(find.text('Create new topic'));
      await tester.pumpAndSettle();
      expect(find.text('Lessons list route'), findsOneWidget);
    });

    testWidgets('draft topic selector shows a safe empty state', (tester) async {
      final id = await _insertLessonFixture(
        db,
        topic: 'Already unlocked draft',
        isUnlocked: true,
      );

      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      expect(
        find.text('No draft topics are available for this class and subject.'),
        findsOneWidget,
      );
      await tester.tap(find.byType(DropdownButtonFormField).first);
      await tester.pumpAndSettle();
      expect(find.text('Create new topic'), findsOneWidget);
    });

    testWidgets('switching draft topics saves generation to the selected lesson',
        (tester) async {
      _mockConnectivityChannel(isOnline: true);
      final firstId = await _insertLessonFixture(
        db,
        topic: 'First draft',
        week: 1,
      );
      final secondId = await _insertLessonFixture(
        db,
        topic: 'Second draft',
        week: 6,
      );

      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(buildApp(
        lessonId: firstId,
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();

      expect(find.text('Second draft'), findsOneWidget);
      await tester.tap(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final first = await db.lessonsDao.getById(firstId);
      final second = await db.lessonsDao.getById(secondId);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(first!.status, equals('draft'));
      expect(first.topic, equals('First draft'));
      expect(second!.status, equals('generated'));
      expect(second.topic, equals('Second draft'));
      expect(second.content, contains('Learn X'));
    });

    testWidgets('generated deck starts on Lesson Note and clamps hidden References',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      });

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      expect(find.text('Card 1 of 4'), findsOneWidget);
      expect(find.text('Lesson Note'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Go to References'));
      await tester.pumpAndSettle();
      expect(find.text('Card 4 of 4'), findsOneWidget);

      await _unlockGeneratedLesson(tester);
      expect(find.byTooltip('Lesson actions'), findsOneWidget);

      await tester.tap(find.byTooltip('Visible sections').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SwitchListTile, 'References'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();

      expect(find.text('References'), findsNothing);
      expect(find.text('Card 3 of 3'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);
    });

    testWidgets('unlocked FAB exposes the existing lesson actions', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);
      await _unlockGeneratedLesson(tester);

      expect(find.byTooltip('Lesson actions'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();

      expect(find.text('Regenerate'), findsNWidgets(2));
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Visible Sections'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('assessment regeneration preserves non-assessment lesson data',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      var questionCallCount = 0;
      final Map<String, dynamic> lessonResult = {
        'raw': {
          'objectives': ['Learn X'],
          'vocabulary': ['Term1'],
          'materials': ['Book'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Original assessment',
          'homework': 'Original homework',
          'references': [
            {'text': 'Original reference'},
          ],
          'diagrams': [
            {'description': 'Original diagram'},
          ],
        },
      };
      final Map<String, dynamic> replacementQuestions = {
        'raw': {
          'mcq': [
            {
              'question': 'Replacement question',
              'options': {'A': 'One', 'B': 'Two', 'C': 'Three', 'D': 'Four'},
              'correct': 'B',
            },
          ],
          'theory': <Map<String, dynamic>>[],
          'subjective': <Map<String, dynamic>>[],
        },
      };

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) return lessonResult;
          questionCallCount++;
          return questionCallCount == 1
              ? _defaultQuestionsResult
              : replacementQuestions;
        },
      ));
      await tester.pumpAndSettle();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);
      await _unlockGeneratedLesson(tester);

      await tester.tap(find.text('Assessment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      expect(find.text('Feedback for regeneration'), findsOneWidget);
      expect(find.text('Replacement question'), findsNothing);

      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final lesson = (await db.select(db.lessons).get()).single;
      final content = jsonDecode(lesson.content) as Map<String, dynamic>;
      final questions = content['questions'] as Map<String, dynamic>;
      expect((questions['mcqs'] as List).single['question'],
          equals('Replacement question'));
      expect(content['objectives'], equals('Learn X'));
      expect(content['homework'], equals('Original homework'));
      expect((content['references'] as List).single['text'],
          equals('Original reference'));
      expect((content['diagrams'] as List).single['description'],
          equals('Original diagram'));
    });

    testWidgets('References regeneration preserves other lesson data',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      });
      var questionCallCount = 0;
      final Map<String, dynamic> lessonResult = {
        'raw': {
          'objectives': ['Learn X'],
          'vocabulary': ['Term1'],
          'materials': ['Book'],
          'presentation': {'step1': 'Intro'},
          'assessment': 'Original assessment',
          'homework': 'Original homework',
          'references': [
            {'text': 'Original reference'},
          ],
          'diagrams': [
            {'description': 'Original diagram'},
          ],
        },
      };

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          if (prompt.contains('## Learning Objectives')) return lessonResult;
          questionCallCount++;
          if (questionCallCount == 1) return _defaultQuestionsResult;
          return {
            'raw': {
              'objectives': ['Do not replace this objective'],
              'references': [
                {'text': 'Replacement reference'},
              ],
            },
          };
        },
      ));
      await tester.pumpAndSettle();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);
      await _unlockGeneratedLesson(tester);

      await tester.tap(find.text('References'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      expect(find.text('Feedback for regeneration'), findsOneWidget);

      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final lesson = (await db.select(db.lessons).get()).single;
      final content = jsonDecode(lesson.content) as Map<String, dynamic>;
      expect((content['references'] as List).single['text'],
          equals('Replacement reference'));
      expect(content['objectives'], equals('Learn X'));
      expect(content['assessment'], equals('Original assessment'));
      expect(content['homework'], equals('Original homework'));
      expect((content['diagrams'] as List).single['description'],
          equals('Original diagram'));
    });

    testWidgets('Lesson Editor sidebar omits Admin and stays safe at target sizes',
        (tester) async {
      for (final size in const [
        Size(1600, 1000),
        Size(800, 1000),
        Size(390, 844),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(createTestApp());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(find.text('Admin'), findsNothing);
      expect(find.text('Lessons'), findsOneWidget);
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('draft deck shows Generate first and hides the FAB', (tester) async {
      final id = await _insertLessonFixture(
        db,
        topic: 'Draft topic',
        content: _generatedLessonContent(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Go to Generate'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to Lesson Note'), findsOneWidget);
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.text('Card 1 of 3'), findsNothing);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Go to Lesson Note'));
      await tester.pumpAndSettle();
      expect(find.text('Card 1 of 3'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Go to Generate'));
      await tester.pumpAndSettle();
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);
    });

    testWidgets('unsaved draft switching asks before changing the lesson ID',
        (tester) async {
      _mockConnectivityChannel(isOnline: true);
      final firstId = await _insertLessonFixture(
        db,
        topic: 'First draft',
        week: 1,
        content: {
          'objectives': ['Original objective'],
          'presentation': {'step1': 'Original presentation'},
        },
      );
      final secondId = await _insertLessonFixture(
        db,
        topic: 'Second draft',
        week: 6,
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(
        lessonId: firstId,
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Go to Lesson Note'));
      await tester.pumpAndSettle();
      final objectivesField = find.byType(TextFormField).first;
      await tester.ensureVisible(objectivesField);
      await tester.enterText(objectivesField, 'Unsaved objective');
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Go to Generate'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Switch topic'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsNothing);
      expect(find.text('First draft'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch topic'));
      await tester.pumpAndSettle();

      expect(find.text('Second draft'), findsOneWidget);
      await tester.tap(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      final first = await db.lessonsDao.getById(firstId);
      final second = await db.lessonsDao.getById(secondId);
      expect(first!.status, equals('draft'));
      expect(first.content, contains('Original objective'));
      expect(second!.status, equals('generated'));
      expect(second.topic, equals('Second draft'));
    });

    testWidgets('generated tabs expose order, counters, dots, arrows, and keys',
        (tester) async {
      final id = await _insertLessonFixture(
        db,
        topic: 'Generated lesson',
        status: 'generated',
        isUnlocked: true,
        content: _generatedLessonContent(),
      );
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      expect(find.text('Lesson Note'), findsOneWidget);
      expect(find.text('Assessment'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);
      expect(find.text('References'), findsOneWidget);
      expect(find.text('Card 1 of 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to Lesson Note'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to Assessment'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to Diagrams'), findsOneWidget);
      expect(find.bySemanticsLabel('Go to References'), findsOneWidget);
      expect(find.byTooltip('Previous lesson section'), findsOneWidget);
      expect(find.byTooltip('Next lesson section'), findsOneWidget);
      expect(
        tester.widget<IconButton>(
          find.byTooltip('Previous lesson section'),
        ).onPressed,
        isNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Card 2 of 4'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Card 3 of 4'), findsOneWidget);

      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 4 of 4'), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byTooltip('Next lesson section')).onPressed,
        isNull,
      );

      await tester.tap(find.bySemanticsLabel('Go to Assessment'));
      await tester.pumpAndSettle();
      expect(find.text('Card 2 of 4'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 1 of 4'), findsOneWidget);
    });

    testWidgets('locked generated cards hide actions until unlocked', (tester) async {
      _mockConnectivityChannel(isOnline: true);
      final id = await _insertLessonFixture(
        db,
        topic: 'Locked lesson',
        status: 'generated',
        content: _generatedLessonContent(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();
      expect(find.text('Locked \u2014 Preview only'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);
      expect(find.textContaining('Unlock'), findsWidgets);

      await _unlockGeneratedLesson(tester);
      expect(find.byTooltip('Lesson actions'), findsOneWidget);
    });

    testWidgets('assessment access follows Free, Basic, Standard, and Elite tiers',
        (tester) async {
      final lessonsByTier = <String, int>{};
      for (final tier in const ['free', 'basic', 'standard', 'elite']) {
        lessonsByTier[tier] = await _insertLessonFixture(
          db,
          topic: '$tier lesson',
          status: 'generated',
          isUnlocked: true,
          content: _generatedLessonContent(),
        );
      }
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final entry in lessonsByTier.entries) {
        await tester.pumpWidget(buildApp(
          lessonId: entry.value,
          authState: _authState(entry.key),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Assessment'));
        await tester.pumpAndSettle();

        if (entry.key == 'standard' || entry.key == 'elite') {
          expect(find.text('What is 2 + 2?'), findsOneWidget);
          expect(find.text('Upgrade Plan'), findsNothing);
        } else {
          expect(find.text('Upgrade Plan'), findsOneWidget);
          expect(find.text('What is 2 + 2?'), findsNothing);
        }
      }
    });

    testWidgets('FAB regeneration opens review before invoking generation',
        (tester) async {
      var callbackCount = 0;
      final id = await _insertLessonFixture(
        db,
        topic: 'Review lesson',
        status: 'generated',
        isUnlocked: true,
        content: _generatedLessonContent(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(
        lessonId: id,
        generateCallback: (prompt) async {
          callbackCount++;
          return _defaultLessonResult;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      expect(find.text('Feedback for regeneration'), findsOneWidget);
      expect(callbackCount, equals(0));

      await tester.tap(find.text('Regenerate').last);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(callbackCount, equals(1));
    });

    testWidgets('diagram action exposes its callback loading state', (tester) async {
      final id = await _insertLessonFixture(
        db,
        topic: 'Diagram lesson',
        status: 'generated',
        isUnlocked: true,
        content: _generatedLessonContent(),
      );
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_suggested_images': true,
      });
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(
        lessonId: id,
        authState: _eliteAuthState(),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagrams'));
      await tester.pumpAndSettle();

      final generateImage = find.text('Generate Image 1');
      expect(generateImage, findsOneWidget);
      await tester.ensureVisible(generateImage);
      await tester.tap(generateImage);
      await tester.pump();
      expect(find.text('Generating Image 1...'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.textContaining('Generate Image 1'), findsOneWidget);
    });

    testWidgets('FAB exposes and executes all visible actions', (tester) async {
      _mockConnectivityChannel(isOnline: true);
      final id = await _insertLessonFixture(
        db,
        topic: 'Action lesson',
        status: 'generated',
        isUnlocked: true,
        content: _generatedLessonContent(),
      );
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      expect(find.text('Regenerate'), findsNWidgets(2));
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Visible Sections'), findsOneWidget);

      await tester.tap(find.text('Visible Sections'));
      await tester.pumpAndSettle();
      expect(find.text('Visible sections'), findsOneWidget);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark Completed'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect((await db.lessonsDao.getById(id))!.status, equals('completed'));
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close').first);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byTooltip('Lesson actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export PDF'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('lesson editor has no layout exceptions at desktop tablet phone sizes',
        (tester) async {
      final id = await _insertLessonFixture(
        db,
        topic: 'Responsive lesson',
        status: 'generated',
        isUnlocked: true,
        content: _generatedLessonContent(),
      );
      for (final size in const [
        Size(1600, 1000),
        Size(800, 1000),
        Size(390, 844),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(buildApp(lessonId: id));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Assessment'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Diagrams'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
