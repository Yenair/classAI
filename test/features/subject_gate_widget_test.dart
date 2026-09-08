// Phase 5 (items 3 & 4) — widget tests for the per-tier subject gate.
//
// Verifies that LessonEditorScreen and ExamEditorScreen block generation with
// the "Upgrade Required" dialog when the current subject is not allowed for
// the subscription tier (topic_restrictions_by_tier), that no AI call is
// made, and that the daily generation counter is not consumed.
//
// Harness copied from test/features/lesson_editor_test.dart: the ConfigService
// override is seeded through the SharedPreferences disk cache (`get-config`
// fails fast on an offline mock, so `refresh()` falls back to the disk cache,
// mirroring an offline device).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/exam/screens/exam_editor_screen.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart';
import 'package:classai/main.dart' show databaseProvider;

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

/// Builds a mock Supabase client whose `get-config` function fails fast so
/// [ConfigService.refresh] throws with no network I/O.
MockSupabaseClient buildMockSupabase() {
  final supabase = MockSupabaseClient();
  final functions = MockFunctionsClient();
  when(() => functions.invoke('get-config')).thenThrow(
    FunctionException(status: 500),
  );
  when(() => supabase.functions).thenReturn(functions);
  return supabase;
}

/// Offline HTTP backend for the Supabase client the ExamEditorScreen
/// constructs internally (AiService reads Supabase.instance). Nothing in
/// these tests performs an actual request — the generateCallback replaces
/// the network call — so a catch-all 404 is sufficient.
/// (Pattern from test/payment/subscription_downgrade_guard_test.dart.)
http.Client buildMockHttpClient() {
  return MockClient((request) async => http.Response(jsonEncode({}), 404));
}

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

/// An authenticated teacher (not an admin, so the gate shows the upgrade
/// dialog instead of navigating to /payment) at a school on [tier].
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

/// Default structured-questions AI result. `_fetchQuestionList` in the exam
/// editor reads `raw['questions']`.
final Map<String, dynamic> _defaultQuestionsResult = {
  'raw': {
    'questions': [
      {
        'question': 'What is 2 + 2?',
        'options': {'A': '3', 'B': '4', 'C': '5', 'D': '6'},
        'correct': 'B',
      },
    ],
  },
};

/// Mocks the connectivity_plus method channel so PlatformHelper.isOnline()
/// returns the given value.
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

/// A ConfigService whose `get-config` fails fast (offline mock) and whose
/// disk cache holds [restrictions] for `topic_restrictions_by_tier`.
/// Must be awaited before pumping the app so the gate reads seeded values.
Future<ConfigService> _seededConfigService(
  Map<String, dynamic> restrictions,
) async {
  SharedPreferences.setMockInitialValues({
    'config_topic_restrictions_by_tier': jsonEncode(restrictions),
  });
  final config = ConfigService(client: buildMockSupabase());
  await config.refresh(); // fails fast → falls back to the disk cache
  return config;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUpAll(() async {
    // The ExamEditorScreen constructs AiService(db: db) after its gates, and
    // AiService reads Supabase.instance — initialize it against an offline
    // mock HTTP client (pattern from subscription_downgrade_guard_test.dart).
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-anon-key',
      httpClient: buildMockHttpClient(),
    );
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    // Set initial credits so _handleGenerate() passes the credit check.
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await db.close();
  });

  /// The stored daily generation counter — must stay at 0 when the subject
  /// gate blocks, and advance when generation is allowed through.
  Future<int> generationCount() async =>
      (await db.select(db.securityConfig).getSingle()).dailyGenerations;

  Widget buildLessonApp({
    required ConfigService config,
    required String tier,
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
  }) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_authState(tier)),
        ),
        configServiceProvider.overrideWithValue(config),
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
        home: LessonEditorScreen(generateCallback: generateCallback),
      ),
    );
  }

  /// The exam editor reads GoRouter query parameters in
  /// didChangeDependencies, so it must be hosted under a router.
  Widget buildExamApp({
    required ConfigService config,
    required String tier,
    Future<Map<String, dynamic>> Function(String prompt)? generateCallback,
  }) {
    final router = GoRouter(
      initialLocation: '/exam',
      routes: [
        GoRoute(
          path: '/exam',
          builder: (context, state) =>
              ExamEditorScreen(generateCallback: generateCallback),
        ),
        GoRoute(
          path: '/payment',
          builder: (context, state) =>
              const Scaffold(body: Text('Payment route')),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_authState(tier)),
        ),
        configServiceProvider.overrideWithValue(config),
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

  Future<void> ensureViewportHeight(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  /// Dismisses a route-based toast whose message is the only SelectableText
  /// in the tree (pattern from lesson_editor_test.dart).
  Future<void> dismissToastIfShowing(WidgetTester tester) async {
    final toastMessage = find.byType(SelectableText);
    if (toastMessage.evaluate().isNotEmpty) {
      Navigator.of(tester.element(toastMessage.first)).pop();
    }
    await tester.pumpAndSettle();
  }

  group('LessonEditorScreen subject gate', () {
    testWidgets(
        'blocks generation with the upgrade dialog when the subject is not allowed for the tier',
        (tester) async {
      await ensureViewportHeight(tester);
      // Offline on purpose: the subject gate must fire BEFORE the online
      // check, so no connectivity mock value can be responsible for the block.
      _mockConnectivityChannel(isOnline: false);
      final config = await _seededConfigService({
        'basic': ['English', 'Social Studies'],
      });

      var generateCalls = 0;
      await tester.pumpWidget(buildLessonApp(
        config: config,
        tier: 'basic',
        generateCallback: (prompt) async {
          generateCalls++;
          return _defaultLessonResult;
        },
      ));
      await tester.pumpAndSettle();

      // Entry screen: a topic is required before the button is enabled.
      await tester.enterText(find.byType(TextField).first, 'Algebraic Expressions');
      await tester.pump();
      await tester.ensureVisible(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create with AI'));
      await tester.pumpAndSettle();

      // The subject gate fires: the teacher sees the upgrade dialog…
      expect(find.text('Upgrade Required'), findsOneWidget);
      // …no AI call was made…
      expect(generateCalls, 0);
      // …and the daily generation counter was not consumed.
      expect(await generationCount(), 0);
    });

    testWidgets('allows generation when the subject is permitted (control)',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      final config = await _seededConfigService({
        'basic': ['Mathematics'],
      });

      var generateCalls = 0;
      await tester.pumpWidget(buildLessonApp(
        config: config,
        tier: 'basic',
        generateCallback: (prompt) async {
          generateCalls++;
          return _defaultLessonResult;
        },
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Algebraic Expressions');
      await tester.pump();
      await tester.ensureVisible(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create with AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      // Same tier, allowed subject: no dialog, generation ran.
      expect(find.text('Upgrade Required'), findsNothing);
      expect(generateCalls, greaterThan(0));

      await dismissToastIfShowing(tester);
    });
  });

  group('ExamEditorScreen subject gate', () {
    testWidgets(
        'blocks generation with the upgrade dialog when the subject is not allowed for the tier',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      // 'standard' is inside the default exam_generation_allowed_tiers, so
      // the earlier tier gate passes and the SUBJECT gate is what blocks.
      final config = await _seededConfigService({
        'standard': ['English', 'Social Studies'],
      });

      var generateCalls = 0;
      await tester.pumpWidget(buildExamApp(
        config: config,
        tier: 'standard',
        generateCallback: (prompt) async {
          generateCalls++;
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Generate with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();

      expect(find.text('Upgrade Required'), findsOneWidget);
      expect(generateCalls, 0);
      expect(await generationCount(), 0);
    });

    testWidgets('reaches generation when the subject is permitted (control)',
        (tester) async {
      await ensureViewportHeight(tester);
      _mockConnectivityChannel(isOnline: true);
      final config = await _seededConfigService({
        'standard': ['Mathematics'],
      });

      var generateCalls = 0;
      await tester.pumpWidget(buildExamApp(
        config: config,
        tier: 'standard',
        generateCallback: (prompt) async {
          generateCalls++;
          return _defaultQuestionsResult;
        },
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Generate with AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate with AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      // The daily-limit check runs right after the subject gate and
      // consumes one generation — proof the gate let the request through.
      expect(find.text('Upgrade Required'), findsNothing);
      expect(generateCalls, greaterThan(0));
      expect(await generationCount(), 1);

      await dismissToastIfShowing(tester);
    });
  });
}
