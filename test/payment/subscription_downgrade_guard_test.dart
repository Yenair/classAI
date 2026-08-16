// Regression tests for the subscription downgrade guard in the CLIENT-side
// automatic payment-resume path (`_resumePendingPayments` on DashboardScreen).
//
// Why Dart and not server-side JS/Deno tests:
//  - supabase/functions/ has no test infrastructure and the repo has no Deno
//    setup (no deno.json, no `deno test` runner, Deno not installed).
//  - the Edge Functions are Deno-only (remote imports, `Deno.env`, `serve`),
//    and confirm-payment's downgrade guard runs only AFTER a live Paystack
//    verification call that cannot be stubbed from outside the Deno runtime.
// So the guard is covered on the client side instead, mirroring the exact
// tier rank table the server uses (free=0, basic=1, standard=2, elite=3).

import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// A connectivity platform stub so `PlatformHelper.isOnline()` is
/// deterministic in the widget tests.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

/// AuthNotifier that returns a fixed authenticated state, and records whether
/// [refreshSchoolFromDb] was invoked after a payment was confirmed.
class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);

  final AuthStateData fixedState;

  bool refreshSchoolFromDbCalled = false;

  @override
  AuthStateData build() => fixedState;

  @override
  Future<void> refreshSchoolFromDb() async {
    refreshSchoolFromDbCalled = true;
  }
}

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

/// Every HTTP request observed by the in-test Supabase backend, e.g.
/// `POST /functions/v1/verify-payment`. Reset per test.
final List<String> recordedRequests = [];

/// A scripted Supabase backend: `verify-payment` succeeds, `confirm-payment`
/// returns a Standard activation, and the `schools` row is returned so
/// [PaymentService.confirmPayment] can update the local school record.
http.Client buildMockHttpClient() {
  return MockClient((request) async {
    recordedRequests.add('${request.method} ${request.url.path}');
    final path = request.url.path;
    if (path.endsWith('/functions/v1/verify-payment')) {
      return http.Response(
        jsonEncode({'status': 'success'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/functions/v1/confirm-payment')) {
      return http.Response(
        jsonEncode({
          'activation_code': 'CLA-TEST-TEST-TEST',
          'subscription_tier': 'standard',
          'expiry_date':
              DateTime.now().add(const Duration(days: 365)).toIso8601String(),
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/rest/v1/schools')) {
      return http.Response(
        jsonEncode({
          'id': 'school-1',
          'school_name': 'Test School',
          'short_code': 'TS01',
          'active_curriculum': 'nerdc',
          'total_seats': 20,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    // Unknown endpoints (e.g. a stray server-time probe) — generic JSON so
    // nothing 4xx-crashes the flow under test.
    return http.Response(
      '{}',
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

class _AuthFixture {
  _AuthFixture({
    required this.schoolId,
    required this.teacherId,
    required this.school,
    required this.teacher,
  });

  final int schoolId;
  final int teacherId;
  final School school;
  final Teacher teacher;
}

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
        SecurityConfigCompanion.insert(
          currentDeviceId: 'downgrade-guard-test-device',
          lastRealtimeEventId: Value(0),
        ),
      );
}

Future<_AuthFixture> _seedAuth(AppDatabase db, {String tier = 'free'}) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('school-1'),
          schoolName: 'Test School',
          shortCode: 'TS01',
          subscriptionTier: Value(tier),
        ),
      );
  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('teacher-1'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value('admin'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('school-1'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );
  final school = await db.schoolsDao.getByLocalId(schoolId);
  final teacher = await db.teachersDao.getById(teacherId);
  if (school == null || teacher == null) {
    throw StateError('Failed to seed auth fixture');
  }
  return _AuthFixture(
    schoolId: schoolId,
    teacherId: teacherId,
    school: school,
    teacher: teacher,
  );
}

AuthStateData _authState(_AuthFixture fixture) {
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: fixture.teacher,
    currentSchool: fixture.school,
  );
}

/// Pumps the real DashboardScreen. On the test host (non-mobile) it renders
/// the editor layout, whose `initState` post-frame callback runs
/// `_resumePendingPayments` (fire-and-forget). We pump repeatedly so the
/// async DB + (for the upgrade test) scripted Supabase work settles.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  required AppDatabase db,
  required FixedAuthNotifier notifier,
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final mockSupabase = buildMockSupabase();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => notifier),
        configServiceProvider.overrideWithValue(
          ConfigService(client: mockSupabase),
        ),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ),
  );

  // First frame builds the screen and schedules the post-frame callback;
  // subsequent pumps let the async resume work complete.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FixedAuthNotifier notifier;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });
    // PaymentService._requireAdminJwt needs a non-empty JWT before it will
    // invoke the verify/confirm Edge Functions.
    SupabaseAuthService().setJwt('test-jwt');
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-anon-key',
      httpClient: buildMockHttpClient(),
    );
  });

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });
    recordedRequests.clear();
    notifier = FixedAuthNotifier(
      const AuthStateData(state: AuthState.authenticated),
    );
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  testWidgets(
    'Elite school: _resumePendingPayments skips a pending Basic payment',
    (tester) async {
      final fixture = await _seedAuth(db, tier: 'elite');
      notifier = FixedAuthNotifier(_authState(fixture));
      await db.paymentEventsDao.insert(
        transactionReference: 'ref-basic',
        confirmedByWebhook: false,
        amount: 100,
        plan: 'basic',
        createdAt: DateTime.now(),
      );

      await _pumpDashboard(
        tester,
        db: db,
        notifier: notifier,
      );

      // The pending Basic payment is left untouched — no verify/confirm call,
      // no confirmation, no school refresh.
      final unconfirmed = await db.paymentEventsDao.getUnconfirmed();
      expect(unconfirmed, hasLength(1),
          reason: 'a pending Basic payment must stay unconfirmed on Elite');
      expect(unconfirmed.single.plan, 'basic');
      expect(unconfirmed.single.confirmedByWebhook, isFalse);
      expect(recordedRequests, isEmpty,
          reason: 'a skipped payment must never hit the network');
      expect(notifier.refreshSchoolFromDbCalled, isFalse);
    },
  );

  testWidgets(
    'Standard school: same-tier pending Standard payment is skipped '
    'in automatic resume',
    (tester) async {
      final fixture = await _seedAuth(db, tier: 'standard');
      notifier = FixedAuthNotifier(_authState(fixture));
      await db.paymentEventsDao.insert(
        transactionReference: 'ref-standard-same-tier',
        confirmedByWebhook: false,
        amount: 200,
        plan: 'standard',
        createdAt: DateTime.now(),
      );

      await _pumpDashboard(
        tester,
        db: db,
        notifier: notifier,
      );

      // Same-tier renewals are user-triggered, never auto-resumed.
      final unconfirmed = await db.paymentEventsDao.getUnconfirmed();
      expect(unconfirmed, hasLength(1),
          reason: 'same-tier payment must be skipped in automatic resume');
      expect(unconfirmed.single.plan, 'standard');
      expect(recordedRequests, isEmpty,
          reason: 'a same-tier payment must never hit the network');
      expect(notifier.refreshSchoolFromDbCalled, isFalse);
    },
  );

  testWidgets(
    'Basic school: _resumePendingPayments processes a pending Standard upgrade',
    (tester) async {
      final fixture = await _seedAuth(db, tier: 'basic');
      notifier = FixedAuthNotifier(_authState(fixture));
      await db.paymentEventsDao.insert(
        transactionReference: 'ref-standard-upgrade',
        confirmedByWebhook: false,
        amount: 200,
        plan: 'standard',
        createdAt: DateTime.now(),
      );

      await _pumpDashboard(
        tester,
        db: db,
        notifier: notifier,
      );

      // Genuine upgrades are verified and confirmed against the backend.
      expect(recordedRequests, contains('/functions/v1/verify-payment'),
          reason: 'upgrade payment must be verified');
      expect(recordedRequests, contains('/functions/v1/confirm-payment'),
          reason: 'upgrade payment must be confirmed');
      expect(recordedRequests, contains('/rest/v1/schools'),
          reason: 'school record must be re-fetched after confirming');

      // The payment row is marked confirmed and the local school is upgraded.
      expect(await db.paymentEventsDao.getUnconfirmed(), isEmpty,
          reason: 'upgrade payment must be marked confirmed locally');
      final school = await db.schoolsDao.get();
      expect(school, isNotNull);
      expect(school!.subscriptionTier, 'standard');
      expect(notifier.refreshSchoolFromDbCalled, isTrue,
          reason: 'the dashboard must refresh the school after an upgrade');
    },
  );
}
