import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockAuthService extends Mock implements AuthService {}

class MockSecurityService extends Mock implements SecurityService {}

/// Sets up a mock for the connectivity_plus method channel so that
/// [PlatformHelper.isOnline] returns `false` (offline) in tests.
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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a [ProviderScope] with the auth provider wired to mocked services.
Future<ProviderContainer> createContainer({
  required AppDatabase db,
  required AuthService authService,
  required SecurityService securityService,
  EmergencyFlushService? emergencyFlushService,
}) async {
  final flushService = emergencyFlushService ?? EmergencyFlushService();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      authServiceProvider.overrideWithValue(authService),
      securityServiceProvider.overrideWithValue(securityService),
      emergencyFlushServiceProvider.overrideWithValue(flushService),
    ],
  );

  // Ensure AuthNotifier is initialised
  container.read(authProvider);
  addTearDown(container.dispose);

  return container;
}

Future<void> seedLocalAuthCache(AppDatabase db) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000010'),
          schoolName: 'Test School',
          shortCode: 'TST',
          subscriptionTier: const Value('free'),
          activeCurriculum: const Value('nerdc'),
          activeCurriculumVersion: const Value('2024'),
          totalSeats: const Value(5),
          schoolMasterKeyWrapped: const Value(
            'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          ),
        ),
      );

  await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000001'),
          email: 'teacher@test.com',
          teacherName: 'Test Teacher',
          role: const Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value(
            '00000000-0000-0000-0000-000000000010',
          ),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          schoolKeyWrapped: const Value(
            'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
          ),
          lastCreditRefillDate: Value(DateTime.now()),
          themeMode: const Value('system'),
        ),
      );
}

Future<void> seedMarkerSelectionCache(AppDatabase db) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000020'),
          schoolName: 'Marker Test School',
          shortCode: 'MKR',
          subscriptionTier: const Value('free'),
          activeCurriculum: const Value('nerdc'),
          activeCurriculumVersion: const Value('2024'),
          totalSeats: const Value(5),
          schoolMasterKeyWrapped: const Value(
            'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          ),
        ),
      );

  await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000021'),
          email: 'alpha@test.com',
          teacherName: 'Alpha Teacher',
          role: const Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value(
            '00000000-0000-0000-0000-000000000020',
          ),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          schoolKeyWrapped: const Value(
            'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
          ),
          lastCreditRefillDate: Value(DateTime.now()),
          themeMode: const Value('system'),
        ),
      );

  await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000022'),
          email: 'zeta@test.com',
          teacherName: 'Zeta Teacher',
          role: const Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value(
            '00000000-0000-0000-0000-000000000020',
          ),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          schoolKeyWrapped: const Value(
            'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
          ),
          lastCreditRefillDate: Value(DateTime.now()),
          themeMode: const Value('system'),
        ),
      );
}

void main() {
  SharedPreferences.setMockInitialValues({});

  late AppDatabase db;
  late MockAuthService mockAuth;
  late MockSecurityService mockSecurity;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockConnectivityChannel(isOnline: false);
    db = AppDatabase.forTesting();
    await db.initialize();
    mockAuth = MockAuthService();
    mockSecurity = MockSecurityService();

    when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
    when(() => mockSecurity.getLastLoggedInTeacherIdentifier())
        .thenAnswer((_) async => 'server:00000000-0000-0000-0000-000000000001');
    when(() => mockSecurity.storeLastLoggedInTeacherIdentifier(any()))
        .thenAnswer((_) async {});
  });

  tearDown(() async {
    await db.close();
  });

  group('initial state', () {
    test('starts in uninitialized state', () async {
      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      final state = container.read(authProvider).state;
      expect(state, equals(AuthState.uninitialized));
    });
  });

  group('checkLocalAuth', () {
    test('transitions to authenticated when local cache exists', () async {
      when(() => mockSecurity.getPasswordHash())
          .thenAnswer((_) async => 'stored_hash');
      when(() => mockSecurity.getLastLoggedInTeacherIdentifier())
          .thenAnswer((_) async => 'server:00000000-0000-0000-0000-000000000001');
      await seedLocalAuthCache(db);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNotNull);
      expect(state.currentSchool, isNotNull);
      expect(state.errorMessage, isNull);
      verify(() => mockSecurity.storeLastLoggedInTeacherIdentifier(
            'server:00000000-0000-0000-0000-000000000001',
          )).called(1);
      container.dispose();
    });

    test('uses the stored teacher marker instead of the first local teacher',
        () async {
      when(() => mockSecurity.getPasswordHash())
          .thenAnswer((_) async => 'stored_hash');
      when(() => mockSecurity.getLastLoggedInTeacherIdentifier())
          .thenAnswer((_) async => 'server:00000000-0000-0000-0000-000000000022');
      await seedMarkerSelectionCache(db);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNotNull);
      expect(state.currentTeacher!.email, equals('zeta@test.com'));
      expect(state.currentSchool, isNotNull);
      expect(state.currentSchool!.schoolName, equals('Marker Test School'));
      verify(() => mockSecurity.storeLastLoggedInTeacherIdentifier(
            'server:00000000-0000-0000-0000-000000000022',
          )).called(1);
      container.dispose();
    });

    test('transitions to onlineLoginRequired when no stored hash', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNull);
      expect(state.currentSchool, isNull);
    });

    test(
        'routes to manual login when the stored marker no longer matches a local teacher',
        () async {
      when(() => mockSecurity.getPasswordHash())
          .thenAnswer((_) async => 'stored_hash');
      when(() => mockSecurity.getLastLoggedInTeacherIdentifier())
          .thenAnswer((_) async => 'server:00000000-0000-0000-0000-000000009999');
      await seedLocalAuthCache(db);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(
        state.errorMessage,
        contains('Saved offline account data is missing'),
      );
      container.dispose();
    });

    test('transitions to onlineLoginRequired when security service throws',
        () async {
      when(() => mockSecurity.getPasswordHash())
          .thenThrow(Exception('Storage error'));

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNull);
      expect(state.currentSchool, isNull);
    });
  });

  group('offline login attempts', () {
    test('returns true and authenticates when cached password matches',
        () async {
      when(() => mockSecurity.getPasswordHash())
          .thenAnswer((_) async => 'password123');
      await seedLocalAuthCache(db);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).checkLocalAuth();

      final success =
          await container.read(authProvider.notifier).attemptOfflineLogin(
                'password123',
              );
      expect(success, isTrue);
      expect(container.read(authProvider).state, equals(AuthState.authenticated));
      verify(() => mockSecurity.storeLastLoggedInTeacherIdentifier(
            'server:00000000-0000-0000-0000-000000000001',
          )).called(2);
      container.dispose();
    });

    test('returns false when cached password does not match', () async {
      when(() => mockSecurity.getPasswordHash())
          .thenAnswer((_) async => 'password123');
      await seedLocalAuthCache(db);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      final success =
          await container.read(authProvider.notifier).attemptOfflineLogin(
                'wrong-password',
              );

      expect(success, isFalse);
      expect(container.read(authProvider).state, equals(AuthState.onlineLoginRequired));
      expect(container.read(authProvider).errorMessage,
          contains('Invalid offline credentials'));
    });
  });

  group('loginOnline', () {
    setUp(() async {
      // Override connectivity to online so loginOnline() can proceed
      // past the PlatformHelper.isOnline() check.
      _mockConnectivityChannel(isOnline: true);

      // Insert a school record so teacher foreign key references work
      await db.into(db.schools).insert(
            SchoolsCompanion.insert(
              serverId: Value('00000000-0000-0000-0000-000000000010'),
              schoolName: 'Test School',
              shortCode: 'TST',
              subscriptionTier: Value('free'),
              activeCurriculum: Value('nerdc'),
              activeCurriculumVersion: Value('2024'),
              totalSeats: Value(5),
              schoolMasterKeyWrapped: Value('bW9ja193cmFwcGVkX21hc3Rlcl9rZXk='),
            ),
          );
    });

    test('transitions to authenticated on success', () async {
      final now = DateTime.now();
      final authResult = AuthResult(
        teacher: Teacher(
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
          schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
          lastCreditRefillDate: now,
          createdAt: now,
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
          themeMode: 'system',
        ),
        school: School(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000010',
          schoolName: 'Test School',
          shortCode: 'TST',
          logoUrl: null,
          subscriptionTier: 'free',
          activeCurriculum: 'nerdc',
          activeCurriculumVersion: '2024',
          totalSeats: 5,
          schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          adminRecoveryEmail: null,
          adminRecoveryEmailVerified: false,
          createdAt: now,
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
        ),
        wrappedSchoolKey: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
        passwordHashVersion: 1,
        offlineCredits: 50,
        lastCreditRefillServerTime: now,
        emailVerified: true,  // Required to reach authenticated state
      );

      when(() => mockAuth.login(any(), any(), any()))
          .thenAnswer((_) async => authResult);
      when(() => mockSecurity.storePasswordHash(any()))
          .thenAnswer((_) async => {});
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).loginOnline(
            email: 'teacher@test.com',
            password: 'password123',
            deviceId: 'device-001',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNotNull);
      expect(state.currentTeacher!.email, equals('teacher@test.com'));
      expect(state.currentSchool, isNotNull);
      expect(state.currentSchool!.schoolName, equals('Test School'));
      verify(() => mockSecurity.storeLastLoggedInTeacherIdentifier(
            'server:00000000-0000-0000-0000-000000000001',
          )).called(1);
      container.dispose();
    });

    test('transitions to accountDeactivated on deactivated error', () async {
      when(() => mockAuth.login(any(), any(), any())).thenThrow(
        AuthException(
          code: AuthErrorCode.accountDeactivated,
          message: 'Account deactivated',
        ),
      );
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).loginOnline(
            email: 'deactivated@test.com',
            password: 'password',
            deviceId: 'device-001',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.accountDeactivated));
      expect(state.errorMessage, isNotNull);
    });

    test('shows error on invalid credentials and stays in onlineLoginRequired',
        () async {
      when(() => mockAuth.login(any(), any(), any())).thenThrow(
        AuthException(
          code: AuthErrorCode.invalidCredentials,
          message: 'Invalid email or password',
        ),
      );
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).loginOnline(
            email: 'wrong@test.com',
            password: 'wrong',
            deviceId: 'device-001',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(state.errorMessage, contains('Invalid email or password'));
    });

    test('shows error on network error and stays in onlineLoginRequired',
        () async {
      when(() => mockAuth.login(any(), any(), any()))
          .thenThrow(Exception('Network error'));
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).loginOnline(
            email: 'teacher@test.com',
            password: 'password',
            deviceId: 'device-001',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(state.errorMessage,
          contains('An unexpected error occurred. Please try again.'));
    });
  });

  group('manualLogout', () {
    test('resets to onlineLoginRequired state (skips local auth check)',
        () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
      when(() => mockAuth.logout()).thenAnswer((_) async => {});
      when(() => mockSecurity.clearAll()).thenAnswer((_) async => {});

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).manualLogout();

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(state.currentTeacher, isNull);
      expect(state.currentSchool, isNull);
    });
  });

  group('forceLogout', () {
    test('triggers emergency save and resets to uninitialized', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
      when(() => mockAuth.logout()).thenAnswer((_) async => {});
      when(() => mockSecurity.clearAll()).thenAnswer((_) async => {});

      bool flushCalled = false;
      final flushService = EmergencyFlushService();
      flushService.register(() async {
        flushCalled = true;
      });

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
        emergencyFlushService: flushService,
      );

      await container.read(authProvider.notifier).forceLogout();

      expect(flushCalled, isTrue);
      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.uninitialized));
    });
  });

  group('clearError', () {
    test('clears error message', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      // Set an error first
      when(() => mockAuth.login(any(), any(), any())).thenThrow(
        AuthException(
          code: AuthErrorCode.invalidCredentials,
          message: 'Some error',
        ),
      );

      await container.read(authProvider.notifier).loginOnline(
            email: 'test@test.com',
            password: 'pass',
            deviceId: 'd1',
          );

      expect(container.read(authProvider).errorMessage, isNotNull);

      // Clear it
      container.read(authProvider.notifier).clearError();
      expect(container.read(authProvider).errorMessage, isNull);
    });
  });

  group('requestAdminOtp', () {
    test('delegates to auth service and returns AdminRecoveryResult', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final expiry = DateTime.now().add(const Duration(minutes: 10));
      when(() => mockAuth.requestAdminOtp('admin@test.com')).thenAnswer(
        (_) async => AdminRecoveryResult(otpSent: true, otpExpiry: expiry),
      );

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      final result = await container
          .read(authProvider.notifier)
          .requestAdminOtp('admin@test.com');

      expect(result.otpSent, isTrue);
      expect(result.otpExpiry, equals(expiry));
    });
  });

  group('verifyAdminOtp', () {
    setUp(() async {
      await db.into(db.schools).insert(
            SchoolsCompanion.insert(
              serverId: Value('00000000-0000-0000-0000-000000000010'),
              schoolName: 'Test School',
              shortCode: 'TST',
              subscriptionTier: Value('free'),
              activeCurriculum: Value('nerdc'),
              activeCurriculumVersion: Value('2024'),
              totalSeats: Value(5),
              schoolMasterKeyWrapped: Value('bW9ja193cmFwcGVkX21hc3Rlcl9rZXk='),
            ),
          );
    });

    test('transitions to authenticated on successful OTP verification',
        () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final now = DateTime.now();
      final authResult = AuthResult(
        teacher: Teacher(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000001',
          email: 'admin@test.com',
          teacherName: 'Admin User',
          role: 'admin',
          schoolLocalId: 1,
          schoolServerId: '00000000-0000-0000-0000-000000000010',
          isActive: true,
          forcePasswordReset: false,
          passwordHashVersion: 2,
          schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXlfdjI=',
          lastCreditRefillDate: now,
          createdAt: now,
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
          themeMode: 'system',
        ),
        school: School(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000010',
          schoolName: 'Test School',
          shortCode: 'TST',
          logoUrl: null,
          subscriptionTier: 'free',
          activeCurriculum: 'nerdc',
          activeCurriculumVersion: '2024',
          totalSeats: 5,
          schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          adminRecoveryEmail: 'admin-recovery@test.com',
          adminRecoveryEmailVerified: true,
          createdAt: now,
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
        ),
        wrappedSchoolKey: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXlfdjI=',
        passwordHashVersion: 2,
        offlineCredits: 50,
        lastCreditRefillServerTime: now,
      );

      when(() => mockAuth.verifyAdminOtp(any(), any(), any()))
          .thenAnswer((_) async => authResult);
      when(() => mockSecurity.storePasswordHash(any()))
          .thenAnswer((_) async => {});

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).verifyAdminOtp(
            email: 'admin@test.com',
            otp: '123456',
            newPassword: 'newPassword123',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNotNull);
      expect(state.currentTeacher!.role, equals('admin'));
      container.dispose();
    });

    test('stays in onlineLoginRequired on invalid OTP', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
      when(() => mockAuth.verifyAdminOtp(any(), any(), any())).thenThrow(
        AuthException(
          code: AuthErrorCode.invalidOtp,
          message: 'Invalid or expired OTP.',
        ),
      );

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).verifyAdminOtp(
            email: 'admin@test.com',
            otp: 'wrong',
            newPassword: 'newPassword123',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(state.errorMessage, contains('Invalid or expired OTP'));
    });
  });

  group('generateTeacherRecoveryCode', () {
    test('delegates to auth service and returns recovery code', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
      when(() => mockAuth.generateTeacherRecoveryCode(any(), any()))
          .thenAnswer((_) async => 'RCV-ABCD1234');

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      final code = await container
          .read(authProvider.notifier)
          .generateTeacherRecoveryCode('teacher-1', 'admin-1');

      expect(code, equals('RCV-ABCD1234'));
    });
  });

  group('recoverTeacherPassword', () {
    setUp(() async {
      await db.into(db.schools).insert(
            SchoolsCompanion.insert(
              serverId: Value('00000000-0000-0000-0000-000000000010'),
              schoolName: 'Test School',
              shortCode: 'TST',
              subscriptionTier: Value('free'),
              activeCurriculum: Value('nerdc'),
              activeCurriculumVersion: Value('2024'),
              totalSeats: Value(5),
              schoolMasterKeyWrapped: Value('bW9ja193cmFwcGVkX21hc3Rlcl9rZXk='),
            ),
          );
    });

    test('transitions to authenticated on successful recovery', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);

      final now = DateTime.now();
      final authResult = AuthResult(
        teacher: Teacher(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000003',
          email: 'teacher@test.com',
          teacherName: 'Recovered Teacher',
          role: 'teacher',
          schoolLocalId: 1,
          schoolServerId: '00000000-0000-0000-0000-000000000010',
          isActive: true,
          forcePasswordReset: false,
          passwordHashVersion: 1,
          schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
          lastCreditRefillDate: now,
          createdAt: now,
          updatedAt: now,
          updateCounter: 1,
          isDeleted: false,
          lastModifiedBy: null,
          themeMode: 'system',
        ),
        school: School(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000010',
          schoolName: 'Test School',
          shortCode: 'TST',
          logoUrl: null,
          subscriptionTier: 'free',
          activeCurriculum: 'nerdc',
          activeCurriculumVersion: '2024',
          totalSeats: 5,
          schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          adminRecoveryEmail: null,
          adminRecoveryEmailVerified: false,
          createdAt: now,
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
        ),
        wrappedSchoolKey: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
        passwordHashVersion: 1,
        offlineCredits: 50,
        lastCreditRefillServerTime: now,
      );

      when(() => mockAuth.recoverTeacherPassword(any(), any(), any()))
          .thenAnswer((_) async => authResult);
      when(() => mockSecurity.storePasswordHash(any()))
          .thenAnswer((_) async => {});

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).recoverTeacherPassword(
            email: 'teacher@test.com',
            recoveryCode: 'RCV-ABCD1234',
            newPassword: 'newPassword123',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.authenticated));
      expect(state.currentTeacher, isNotNull);
      expect(state.currentTeacher!.email, equals('teacher@test.com'));
      container.dispose();
    });

    test('stays in onlineLoginRequired on invalid recovery code', () async {
      when(() => mockSecurity.getPasswordHash()).thenAnswer((_) async => null);
      when(() => mockAuth.recoverTeacherPassword(any(), any(), any()))
          .thenThrow(
        AuthException(
          code: AuthErrorCode.invalidRecoveryCode,
          message: 'Invalid or expired recovery code.',
        ),
      );

      final container = await createContainer(
        db: db,
        authService: mockAuth,
        securityService: mockSecurity,
      );

      await container.read(authProvider.notifier).recoverTeacherPassword(
            email: 'teacher@test.com',
            recoveryCode: 'WRONG',
            newPassword: 'newPassword123',
          );

      final state = container.read(authProvider);
      expect(state.state, equals(AuthState.onlineLoginRequired));
      expect(state.errorMessage, contains('Invalid or expired recovery code'));
    });
  });
}
