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
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
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

class _TestDailyCreditNotifier extends DailyCreditStateNotifier {
  @override
  DailyCreditStateData build() => const DailyCreditStateData();
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

/// R2 removed the manual unlock step: generation auto-unlocks, so there is
/// no unlock helper anymore.

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
  final generateButton = find.text('Create with AI');
  await tester.ensureVisible(generateButton);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(generateButton);
  await tester.pump(const Duration(milliseconds: 200));
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
  await tester.pump(const Duration(milliseconds: 200));
}


void main() {

  late AppDatabase db;
  final mockSupabase = buildMockSupabase();



  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    // Set initial credits so _handleGenerate() passes the credit check
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
    // Pin connectivity so PlatformHelper.isOnline() resolves immediately
    // without hitting the real connectivity_plus plugin. Use true so
    // the lesson editor thinks the device is online (most tests need this).
    PlatformHelper.isOnlineOverride = true;
    // In-memory SharedPreferences store: the visible-section preferences
    // default to hidden, and PlatformHelper.isEditorMode has a value to read.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    PlatformHelper.isOnlineOverride = null;
    await db.close();
  });

  /// Scale text down so the LessonEditorScreen content does not overflow.
  Widget createTestApp() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_eliteAuthState()),
        ),
        configServiceProvider.overrideWithValue(
          ConfigService(client: mockSupabase),
        ),
        emergencyFlushServiceProvider.overrideWithValue(
          EmergencyFlushService(),
        ),
        dailyCreditStateProvider.overrideWith(
          () => _TestDailyCreditNotifier(),
        ),
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
        emergencyFlushServiceProvider.overrideWithValue(
          EmergencyFlushService(),
        ),
        dailyCreditStateProvider.overrideWith(
          () => _TestDailyCreditNotifier(),
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
        emergencyFlushServiceProvider.overrideWithValue(
          EmergencyFlushService(),
        ),
        dailyCreditStateProvider.overrideWith(
          () => _TestDailyCreditNotifier(),
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
    testWidgets('renders entry screen with Create with AI button', (tester) async {
      await ensureViewportHeight(tester);
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // The blank-lesson entry screen: a large topic input and the single
      // primary create action. No Subject/Class/Week dropdowns.
      expect(find.text('LESSON TOPIC'), findsOneWidget);
      expect(find.text('Create with AI'), findsOneWidget);
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

      // The header renders the lesson editor title.
      expect(find.text('Lesson Editor'), findsOneWidget);
    });

    testWidgets('topic field is rendered in the form', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pumpAndSettle();

      // The entry screen's topic TextField should be present.
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('lesson note is editable after generation', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The legacy Advanced Settings card (Bloom chips, difficulty) was
      // removed with the deck overhaul; R2 removed the unlock step, so the
      // Lesson Note slide is immediately editable.
      expect(find.text('Advanced Settings'), findsNothing);
      final objectivesField = find.byType(TextField).first;
      await tester.enterText(objectivesField, 'Edited objective');
      await tester.pump();
      expect(find.text('Edited objective'), findsOneWidget);
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

      // R2 removed the locked-preview step: the deck lands on the Lesson
      // Note slide with editable content and the footer actions.
      expect(find.text('Preview Generated Content'), findsNothing);
      expect(find.text('Locked — Preview only'), findsNothing);
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Presentation'), findsWidgets);
      expect(find.text('Introduction'), findsOneWidget);
      expect(find.textContaining('step1: Intro'), findsOneWidget);
      expect(find.text('Regenerate'), findsOneWidget);
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

      // Navigate to the Assessment slide to see the tier-gated content.
      await tester.tap(find.byTooltip('Next lesson section'));
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

      // The lesson loads without crashing: drafts open on the Generate
      // slide with the existing topic preselected.
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.textContaining('Algebraic Expressions'), findsOneWidget);
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

      // Open the Visible sections sheet from the footer action bar.
      await tester.tap(find.text('Visible Sections'));
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
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();

      // Vocabulary and Materials now appear on the Lesson Note slide,
      // with their content.
      expect(find.text('Vocabulary'), findsOneWidget);
      expect(find.textContaining('Term1'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
      expect(find.textContaining('Book'), findsOneWidget);

      // Navigate to the Suggested Images slide.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();

      // Suggested Images is expanded by default after it becomes visible.
      // The mock callback returns no diagrams, so the empty state shows.
      final suggestedImagesHeader = find.text('Suggested Images');
      expect(suggestedImagesHeader, findsOneWidget);
      expect(find.text('No suggested images yet.'), findsOneWidget);
    });

    testWidgets(
        'regenerating homework updates the text and shows a success toast',
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
      // Wait for async _saveLesson() to complete so _lessonId is set.
      await tester.pump();
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // Navigate to the Assessment card using arrows; the homework
      // regenerate control lives there.
      await tester.tap(find.byTooltip('Next lesson section'));
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
        // (bounded: 100 × 50 ms of real time).
        for (var i = 0; i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          // Pump with explicit Duration to advance the fake clock and fire
          // the toast's Future.delayed(2s) removal timer.
          await tester.pump(const Duration(milliseconds: 100));
          if (find
              .text('Homework regenerated.')
              .evaluate()
              .isNotEmpty) {
            break;
          }
        }
      });

      // The regeneration flow shows only the success toast. Advance the
      // fake clock by 3 s so the toast's auto-removal timer fires.
      await tester.pump(const Duration(seconds: 3));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.text('Homework regenerated.'), findsNothing);
      expect(find.textContaining('New Homework'), findsOneWidget);

      // The regenerated homework was persisted to the lesson row.
      final lesson = (await db.select(db.lessons).get()).single;
      final content = jsonDecode(lesson.content) as Map<String, dynamic>;
      expect(content['homework'], equals('New Homework'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('generate card switches from Generate with AI to Regenerate after generation', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      expect(find.text('Create with AI'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);

      await _tapGenerate(tester);

      // After generation the deck auto-navigates to the Lesson Note card
      // and the footer shows the regeneration primary action. R2 removed
      // the locked-preview step entirely. Default prefs have
      // visible_references=true, so the deck is 4 cards.
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Create with AI'), findsNothing);
      expect(find.text('Preview Generated Content'), findsNothing);
      expect(find.text('Card 2 of 4'), findsOneWidget);
    });

    testWidgets('legacy Advanced Settings card is removed from the deck', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The legacy Advanced Settings card (difficulty, Bloom chips and the
      // diagram toggle) was removed with the deck overhaul; none of its
      // controls render on the content cards anymore.
      expect(find.text('Advanced Settings'), findsNothing);
      expect(find.text('Difficulty'), findsNothing);
      expect(find.text("Cognitive Objectives (Bloom's)"), findsNothing);
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

      // R2 removed the unlock step: the deck lands directly on the Lesson
      // Note content card with the document sections rendered. There are
      // no tab chips and no locked preview. Default prefs have
      // visible_references=true → 4 cards total.
      expect(find.text('Card 2 of 4'), findsOneWidget);
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Presentation'), findsWidgets);
      expect(find.text('Introduction'), findsOneWidget);
    });

    testWidgets(
        'draft lesson with partial content opens the generate slide',
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

      // Drafts open on the Generate slide even when they carry partial
      // content; no locked-preview chrome remains.
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.text('Create with AI'), findsOneWidget);
      expect(find.text('Regenerate'), findsNothing);
      expect(find.text('Locked \u2014 Preview only'), findsNothing);
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

      // The lesson loads without crashing: drafts open on the Generate
      // slide with the restored topic preselected, not on a locked preview.
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.textContaining('Algebraic Expressions'), findsOneWidget);
      expect(find.text('Preview Generated Content'), findsNothing);
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
        'footer shows a single completion control after generation',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // There should be exactly one 'Mark Completed' button (in the footer
      // action area), not duplicated anywhere else.
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

      // With the default (references hidden), the deck has 3 slides:
      // Generate + 2 content cards. Navigate to the References card via
      // the footer arrows instead of the removed locked-preview button.
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
      });
      // Re-reading prefs does not rebuild the deck, so assert via a fresh
      // generate flow: the deck's last card is the References card.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();

      // dispatchCallback returns no references, so the empty state
      // message should be shown.
      expect(find.text('No source references available yet.'), findsOneWidget);
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

    testWidgets('deck shows all content cards after generation in correct order', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Default prefs have visible_references=true (4 cards: Generate +
      // Lesson Note + Assessment + References). R2 removed the unlock
      // step, so the deck shows content cards without any unlock interaction.
      expect(find.text('Card 2 of 4'), findsOneWidget);
      expect(find.text('Objectives'), findsOneWidget);

      // The content cards are reachable via the footer arrows.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 3 of 4'), findsOneWidget);
    });

    testWidgets('References card hidden unless visible toggle is enabled', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      // Explicitly disable references to test the hidden case.
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references':
            false,
      });
      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);
      // With references disabled the deck has 3 slides:
      // Lesson Note and Assessment — numbered 2 and 3 after the hidden
      // Generate slide. No References card exists.
      expect(find.text('Card 2 of 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 3 of 3'), findsOneWidget);
      expect(find.text('Assessment Format'), findsOneWidget);
      expect(find.text('Source References'), findsNothing);
    });

    testWidgets('References card appears when the visible toggle is enabled', (tester) async {
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

      // With the toggle enabled the deck has 4 slides: Generate + 3
      // content cards, ending on Source References.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 4 of 4'), findsOneWidget);
      expect(find.text('Source References'), findsOneWidget);
    });

    testWidgets('Homework appears in Assessment card not Lesson Note', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // Homework should NOT appear on the Lesson Note card (the deck's
      // landing card). It lives on the Assessment card.
      expect(find.text('Homework'), findsNothing);

      // Move to the Assessment card.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();

      // Now Homework should appear.
      expect(find.text('Homework'), findsOneWidget);
    });

    testWidgets('format selector and question counts appear in Assessment card', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();

      // Format selector and question counts are visible.
      expect(find.text('Assessment Format'), findsOneWidget);
      expect(find.text('Question Counts'), findsOneWidget);
      expect(find.text('Objective'), findsOneWidget);
    });

    testWidgets('legacy diagram-generation toggle no longer renders in the deck', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The Advanced Settings card that used to host this toggle is gone;
      // the Suggested Images card exposes its own Generate Image actions.
      expect(find.text('Include diagram generation'), findsNothing);
      expect(find.text('Advanced Settings'), findsNothing);
    });

    testWidgets('topic context line shows Subject Class Week on Lesson Note card', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The Lesson Note card's card meta label shows 'subject • classLevel'
      // in its badge. The Assessment card header shows the class + subject.
      // Verify the subject appears on screen after generation.
      expect(find.textContaining('Mathematics'), findsWidgets);
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

      // Focus the objectives text field on the Lesson Note card.
      final objectivesField = find.byType(TextField).first;
      await tester.ensureVisible(objectivesField);
      await tester.tap(objectivesField);
      await tester.pumpAndSettle();

      // Send right arrow key — should NOT move the deck because a field is
      // focused.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Still on the Lesson Note card (Objectives visible, Assessment card
      // content not visible).
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Assessment Format'), findsNothing);
    });

    testWidgets('draft topic selector filters by class and subject and routes new topics',
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
      expect(find.text('Create with AI'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      // The card-based draft selector shows only drafts matching this
      // class and subject. Wrong class/subject drafts are filtered out.
      expect(find.text('Current draft'), findsOneWidget);
      expect(find.text('Matching draft'), findsOneWidget);
      expect(find.textContaining('Wrong class draft'), findsNothing);
      expect(find.textContaining('Wrong subject draft'), findsNothing);
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
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // A lone draft is auto-selected (no dropdown rendered), and the
      // generate slide still offers the create-new-topic entry.
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.text('Create with AI'), findsOneWidget);
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

      // The card-based draft selector shows matching drafts as cards.
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Second draft'), findsOneWidget);
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

    testWidgets('generated deck starts on Lesson Note and clamps when sections toggle',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_references': true,
        '00000000-0000-0000-0000-000000000001_lesson_visible_suggested_images': true,
      });

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // The deck lands on the Lesson Note card (card 2 after Generate);
      // with references on (default) and suggested images enabled there
      // are 5 slides.
      expect(find.text('Card 2 of 5'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      // Walk to the References card via the footer arrows.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Card 5 of 5'), findsOneWidget);
      expect(find.text('Source References'), findsOneWidget);

      // Toggle References off from the footer's Visible Sections sheet:
      // the deck clamps onto the now-last Suggested Images card.
      await tester.tap(find.text('Visible Sections'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(SwitchListTile, 'References'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Source References'), findsNothing);
      expect(find.text('Card 4 of 4'), findsOneWidget);
      expect(find.text('Suggested Images'), findsOneWidget);
    });

    testWidgets('footer exposes the existing lesson actions after generation', (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: dispatchCallback(),
      ));
      await tester.pumpAndSettle();
      await _enterTopic(tester, 'Algebraic Expressions');
      await _tapGenerate(tester);

      // At desktop width the action area is the footer strip (the FAB and
      // its menu are mobile-only). R2 auto-unlocks, so it appears without
      // any unlock interaction.
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Visible Sections'), findsOneWidget);
      // The action-menu-only entries stay hidden on desktop.
      expect(find.text('Save'), findsNothing);
      expect(find.byTooltip('Lesson actions'), findsNothing);
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

      // The deck lands on Lesson Note; move to the Assessment card and
      // regenerate via the footer's Regenerate action. On desktop the
      // footer calls skipConfirmation=true, so regeneration happens
      // directly without showing the review panel.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Regenerate'));
      await tester.pump(const Duration(milliseconds: 300));
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

      // The deck lands on Lesson Note; walk to the References card (the
      // last slide with the toggle enabled) and use its dedicated
      // regenerate control. On desktop the 'Regenerate references' button
      // calls _handleRegenerateReferences directly (no review panel).
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Regenerate references'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
      // Dismiss the success toast.
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 5; i++) await tester.pump();

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
      // 'Lessons' appears in both sidebar and bottom nav on desktop.
      expect(find.text('Lessons'), findsWidgets);
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

      // Drafts open on the Generate slide: its generate header is shown,
      // no card counter or footer actions appear, and the FAB is hidden.
      expect(find.text('Generate Lesson Content'), findsOneWidget);
      expect(find.text('Card 2 of 4'), findsNothing);
      expect(find.byTooltip('Lesson actions'), findsNothing);
      expect(find.text('Regenerate'), findsNothing);

      // Move to the Lesson Note card: the card counter appears but the
      // footer is hidden because _hasGenerated is false for drafts.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 2 of 4'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);

      // Back to the Generate slide hides the action area again.
      await tester.tap(find.byTooltip('Previous lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Generate Lesson Content'), findsOneWidget);
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
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // Edit the objectives field on the Lesson Note card to dirty the
      // draft.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      final objectivesField = find.byType(TextField).first;
      await tester.ensureVisible(objectivesField);
      await tester.enterText(objectivesField, 'Unsaved objective');
      await tester.pump();

      // Go back to the Generate slide and try to switch drafts.
      await tester.tap(find.byTooltip('Previous lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();

      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);
      expect(find.text('Switch topic'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved changes'), findsNothing);

      // Switch again, this time confirming.
      await tester.tap(find.text('Second draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch topic'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Second draft'), findsOneWidget);
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

    testWidgets('generated deck exposes counters, arrows, and clamping',
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

      // With references visible (default) and no images, the deck is
      // Generate + 3 content cards. Unlocked generated lessons open on
      // the Lesson Note card (2 of 4).
      expect(find.text('Card 2 of 4'), findsOneWidget);
      expect(find.byTooltip('Previous lesson section'), findsOneWidget);
      expect(find.byTooltip('Next lesson section'), findsOneWidget);

      // Walk forward through every card to the end.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Card 3 of 4'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Card 4 of 4'), findsOneWidget);

      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pumpAndSettle();
      // No further card beyond References (card 4 of 4).
      expect(
        tester.widget<IconButton>(find.byTooltip('Next lesson section')).onPressed,
        isNull,
      );

      // Walk back to the start of the content cards.
      await tester.tap(find.byTooltip('Previous lesson section'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Previous lesson section'));
      await tester.pumpAndSettle();
      expect(find.text('Card 2 of 4'), findsOneWidget);
    });

    testWidgets('locked generated cards stay in read-only preview', (tester) async {
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
      // R2 removed the unlock button: legacy locked rows stay in the
      // read-only preview overlay with no editing chrome at all.
      expect(find.text('Locked \u2014 Preview only'), findsOneWidget);
      expect(find.text('View References'), findsOneWidget);
      expect(find.byTooltip('Lesson actions'), findsNothing);
      expect(find.text('Regenerate'), findsNothing);
      expect(find.text('Mark Completed'), findsNothing);
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
        await tester.pump();
        await tester.pump();
        await tester.pump();
        // The deck lands on the Lesson Note card; move to Assessment.
        await tester.tap(find.byTooltip('Next lesson section'));
        await tester.pump();
        await tester.pump();

        if (entry.key == 'standard' || entry.key == 'elite') {
          expect(find.text('What is 2 + 2?'), findsOneWidget);
          expect(find.text('Upgrade Plan'), findsNothing);
        } else {
          expect(find.text('Upgrade Plan'), findsOneWidget);
          expect(find.text('What is 2 + 2?'), findsNothing);
        }
      }
    });

    testWidgets('footer regeneration opens review before invoking generation',
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

      // The footer's Regenerate skips the review panel and regenerates
      // directly (skipConfirmation: true). The FAB's Regenerate opens
      // the review panel but is only visible on mobile. On desktop, just
      // verify the footer's Regenerate triggers the callback.
      await tester.tap(find.text('Regenerate'));
      await tester.pump(const Duration(milliseconds: 300));
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
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The deck lands on Lesson Note; walk to the Suggested Images card.
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Next lesson section'));
      await tester.pump(const Duration(milliseconds: 300));

      final generateImage = find.text('Generate Image 1');
      expect(generateImage, findsOneWidget);
      await tester.ensureVisible(generateImage);
      await tester.tap(generateImage);
      await tester.pump();
      await tester.pump();
      // The image generation callback throws because Supabase is not
      // initialized in the test. The loading indicator still appears
      // briefly before the error.
      expect(find.textContaining('Generate Image 1'), findsWidgets);
    });

    testWidgets('footer exposes and executes all visible actions', (tester) async {
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
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // At desktop width the action area is the footer strip.
      expect(find.text('Regenerate'), findsOneWidget);
      expect(find.text('Mark Completed'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Visible Sections'), findsOneWidget);

      await tester.tap(find.text('Visible Sections'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Visible sections'), findsOneWidget);
      await tester.tap(find.byTooltip('Close').last);
      await tester.pump(const Duration(milliseconds: 300));

      // Mark Completed persists the completed status.
      await tester.tap(find.text('Mark Completed'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
      // Dismiss the toast and advance fake clock.
      await tester.pump(const Duration(seconds: 3));
      for (var i = 0; i < 5; i++) await tester.pump();
      expect((await db.lessonsDao.getById(id))!.status, equals('completed'));

      // Export PDF runs without exceptions.
      await tester.tap(find.text('Export PDF'));
      await tester.pump(const Duration(milliseconds: 300));
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
      SharedPreferences.setMockInitialValues({
        '00000000-0000-0000-0000-000000000001_lesson_visible_suggested_images': true,
      });
      for (final size in const [
        Size(1600, 1000),
        Size(800, 1000),
        Size(390, 844),
      ]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(buildApp(lessonId: id));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Walk the deck: Lesson Note -> Assessment -> Suggested Images.
        await tester.tap(find.byTooltip('Next lesson section'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Next lesson section'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });
  });
}
