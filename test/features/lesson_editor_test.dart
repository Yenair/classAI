import 'dart:convert';
import 'dart:io';
// `isNotNull` is needed from the flutter_test matchers (expect(..., isNotNull));
// drift's column-expression helper of the same name would be ambiguous.
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
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

/// Types into the Topic TextField. It is the first TextField in the tree on
/// a fresh (non-generated) form, so find.byType(TextField).first is reliable.
Future<void> _enterTopic(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

/// Scrolls to and taps "Generate with AI", then pumps until the generation
/// flow (both AI calls + the auto-save) settles.
Future<void> _tapGenerate(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Generate with AI'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Generate with AI'));
  await tester.pumpAndSettle();
  // Let the async _saveLesson inside the post-frame callback complete.
  await tester.pump(const Duration(seconds: 1));
  // Dismiss the toast dialog.
  await tester.tap(find.text('Close'));
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

      // Check that Bloom's verbs chips are present
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
      await ensureViewportHeight(tester);

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

    testWidgets('generate callback is invoked with valid prompts',
        (tester) async {
      String? lessonPrompt;
      String? questionsPrompt;
      final result = _defaultLessonResult;

      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);

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
      // locked overlay are shown, plus brief locked preview cards for
      // Objectives and Presentation. The full Vocabulary/Materials/etc. cards
      // are gated behind isUnlocked, so only the Objectives content is visible.
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Locked — Preview only'), findsOneWidget);
      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Learn X'), findsOneWidget);
      expect(find.text('Full content visible after unlock'), findsWidgets);
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
      await tester.pumpWidget(buildApp(lessonId: id));
      await tester.pumpAndSettle();

      // The lesson loads without crashing; the locked preview shows the
      // restored objectives text.
      expect(find.text('Old objective'), findsOneWidget);
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

      // Verify preview cards visible with generated content
      // Note: _buildPreviewCard only renders the content, NOT the title string
      expect(find.text('Preview Generated Content'), findsOneWidget);
      expect(find.text('Learn X'), findsOneWidget);

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
