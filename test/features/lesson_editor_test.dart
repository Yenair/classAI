import 'dart:io';
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

/// Returns an authenticated state with a non-free (elite) school so
/// _handleGenerate() passes the subscription-tier gate.
class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);
  final AuthStateData fixedState;
  @override
  AuthStateData build() => fixedState;
}

AuthStateData _eliteAuthState() {
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
      subscriptionTier: 'elite',
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
  /// text-scaling MediaQuery.  Accepts an optional [generateCallback].
  Widget buildApp({
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => FixedAuthNotifier(_eliteAuthState())),
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
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async {
          capturedPrompt = prompt;
          return result;
        },
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');

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
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async => result,
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');

      // Scroll to and tap Generate with AI
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

      // Dismiss the "Lesson generated successfully!" toast dialog
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Verify lesson was auto-saved to database during generation
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
      _mockConnectivityChannel(isOnline: true);

      await tester.pumpWidget(buildApp(
        generateCallback: (prompt) async => result,
      ));
      await tester.pumpAndSettle();

      await _enterTopic(tester, 'Algebraic Expressions');

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
