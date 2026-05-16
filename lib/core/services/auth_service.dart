import 'package:classai/core/database/database.dart';

/// Result of a login, activation, or password recovery operation.
class AuthResult {
  final Teacher teacher;
  final School school;
  final String? wrappedSchoolKey; // base64
  final int passwordHashVersion;
  final int offlineCredits;
  final DateTime lastCreditRefillServerTime;

  AuthResult({
    required this.teacher,
    required this.school,
    this.wrappedSchoolKey,
    required this.passwordHashVersion,
    required this.offlineCredits,
    required this.lastCreditRefillServerTime,
  });
}

/// Result of an admin OTP request.
class AdminRecoveryResult {
  final bool otpSent;
  final DateTime otpExpiry;

  AdminRecoveryResult({required this.otpSent, required this.otpExpiry});
}

/// Abstract interface for authentication operations.
///
/// All server-interacting methods work against a mock Supabase client
/// until Phase 4, when the real SupabaseClient is wired in.
abstract class AuthService {
  /// Authenticate a teacher with email + password + deviceId.
  Future<AuthResult> login(
    String email,
    String password,
    String deviceId,
  );

  /// Activate a new account (admin or teacher) using an activation code.
  ///
  /// For admin activation ([isAdmin]==true), [recoveryEmail] is REQUIRED
  /// and will be verified via OTP before activation completes.
  Future<AuthResult> activate(
    String code,
    String email,
    String password,
    String deviceId, {
    required bool isAdmin,
    String? recoveryEmail,
  });

  /// Log the current session out.
  Future<void> logout();

  /// Request an OTP sent to the admin's recovery email.
  Future<AdminRecoveryResult> requestAdminOtp(String email);

  /// Verify the admin's OTP and set a new password (re-wraps school key).
  Future<AuthResult> verifyAdminOtp(
    String email,
    String otp,
    String newPassword,
  );

  /// Generate a temporary recovery code for a teacher (admin-only action).
  /// Code expires in 24 hours.
  Future<String> generateTeacherRecoveryCode(
    String teacherId,
    String adminId,
  );

  /// Reset a teacher's password using a recovery code.
  Future<AuthResult> recoverTeacherPassword(
    String email,
    String recoveryCode,
    String newPassword,
  );
}

/// Mock implementation of [AuthService] that simulates Supabase responses.
///
/// Replace with a real Supabase-backed implementation in Phase 4.
class MockAuthService implements AuthService {
  @override
  Future<AuthResult> login(
    String email,
    String password,
    String deviceId,
  ) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Mock: always succeed for test accounts
    if (email == 'admin@test.com' || email == 'teacher@test.com') {
      final now = DateTime.now();
      return AuthResult(
        teacher: Teacher(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000001',
          email: email,
          teacherName: email == 'admin@test.com' ? 'Admin User' : 'Teacher User',
          role: email == 'admin@test.com' ? 'admin' : 'teacher',
          schoolLocalId: 1,
          schoolServerId: '00000000-0000-0000-0000-000000000010',
          isActive: true,
          forcePasswordReset: false,
          passwordHashVersion: 1,
          schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=', // base64
          lastCreditRefillDate: now,
          createdAt: now.subtract(const Duration(days: 30)),
          updatedAt: now,
          updateCounter: 0,
          isDeleted: false,
          lastModifiedBy: null,
        ),
        school: School(
          localId: 1,
          serverId: '00000000-0000-0000-0000-000000000010',
          schoolName: 'Mock School',
          shortCode: 'MOCK',
          logoUrl: null,
          subscriptionTier: 'free',
          activeCurriculum: 'nerdc',
          activeCurriculumVersion: '2024',
          totalSeats: 5,
          schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
          adminRecoveryEmail: email == 'admin@test.com' ? 'admin-recovery@test.com' : null,
          adminRecoveryEmailVerified: email == 'admin@test.com',
          createdAt: now.subtract(const Duration(days: 30)),
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
    }

    // Simulate deactivated account
    if (email == 'deactivated@test.com') {
      throw AuthException(
        code: AuthErrorCode.accountDeactivated,
        message: 'This account has been deactivated. Contact your administrator.',
      );
    }

    // Simulate invalid credentials
    throw AuthException(
      code: AuthErrorCode.invalidCredentials,
      message: 'Invalid email or password.',
    );
  }

  @override
  Future<AuthResult> activate(
    String code,
    String email,
    String password,
    String deviceId, {
    required bool isAdmin,
    String? recoveryEmail,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    // Validate admin activation requirements
    if (isAdmin && (recoveryEmail == null || recoveryEmail.isEmpty)) {
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: 'Recovery email is required for admin activation.',
      );
    }

    // Mock: valid activation codes are 8-character alphanumeric
    if (code.length != 8) {
      throw AuthException(
        code: AuthErrorCode.invalidActivationCode,
        message: 'Invalid or expired activation code.',
      );
    }

    final now = DateTime.now();
    return AuthResult(
      teacher: Teacher(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000002',
        email: email,
        teacherName: isAdmin ? 'Admin User' : 'Teacher User',
        role: isAdmin ? 'admin' : 'teacher',
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
      ),
      school: School(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000010',
        schoolName: 'New Mock School',
        shortCode: 'NEW',
        logoUrl: null,
        subscriptionTier: 'free',
        activeCurriculum: 'nerdc',
        activeCurriculumVersion: '2024',
        totalSeats: 5,
        schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
        adminRecoveryEmail: isAdmin ? recoveryEmail : null,
        adminRecoveryEmailVerified: isAdmin,
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
  }

  @override
  Future<void> logout() async {
    await Future.delayed(const Duration(milliseconds: 200));
    // In mock mode, nothing to flush server-side
  }

  @override
  Future<AdminRecoveryResult> requestAdminOtp(String email) async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (email != 'admin@test.com') {
      throw AuthException(
        code: AuthErrorCode.notFound,
        message: 'No admin account found with this email.',
      );
    }

    return AdminRecoveryResult(
      otpSent: true,
      otpExpiry: DateTime.now().add(const Duration(minutes: 10)),
    );
  }

  @override
  Future<AuthResult> verifyAdminOtp(
    String email,
    String otp,
    String newPassword,
  ) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (otp != '123456') {
      throw AuthException(
        code: AuthErrorCode.invalidOtp,
        message: 'Invalid or expired OTP.',
      );
    }

    final now = DateTime.now();
    return AuthResult(
      teacher: Teacher(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000001',
        email: email,
        teacherName: 'Admin User',
        role: 'admin',
        schoolLocalId: 1,
        schoolServerId: '00000000-0000-0000-0000-000000000010',
        isActive: true,
        forcePasswordReset: false,
        passwordHashVersion: 2,
        schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXlfdjI=',
        lastCreditRefillDate: now,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now,
        updateCounter: 1,
        isDeleted: false,
        lastModifiedBy: null,
      ),
      school: School(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000010',
        schoolName: 'Mock School',
        shortCode: 'MOCK',
        logoUrl: null,
        subscriptionTier: 'free',
        activeCurriculum: 'nerdc',
        activeCurriculumVersion: '2024',
        totalSeats: 5,
        schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
        adminRecoveryEmail: 'admin-recovery@test.com',
        adminRecoveryEmailVerified: true,
        createdAt: now.subtract(const Duration(days: 30)),
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
  }

  @override
  Future<String> generateTeacherRecoveryCode(
    String teacherId,
    String adminId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Mock: return a 12-character alphanumeric code
    return 'RCV-' + DateTime.now().millisecondsSinceEpoch.toString().substring(0, 8);
  }

  @override
  Future<AuthResult> recoverTeacherPassword(
    String email,
    String recoveryCode,
    String newPassword,
  ) async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (!recoveryCode.startsWith('RCV-')) {
      throw AuthException(
        code: AuthErrorCode.invalidRecoveryCode,
        message: 'Invalid or expired recovery code.',
      );
    }

    final now = DateTime.now();
    return AuthResult(
      teacher: Teacher(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000003',
        email: email,
        teacherName: 'Recovered Teacher',
        role: 'teacher',
        schoolLocalId: 1,
        schoolServerId: '00000000-0000-0000-0000-000000000010',
        isActive: true,
        forcePasswordReset: false,
        passwordHashVersion: 1,
        schoolKeyWrapped: 'bW9ja193cmFwcGVkX3NjaG9vbF9rZXk=',
        lastCreditRefillDate: now,
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now,
        updateCounter: 1,
        isDeleted: false,
        lastModifiedBy: null,
      ),
      school: School(
        localId: 1,
        serverId: '00000000-0000-0000-0000-000000000010',
        schoolName: 'Mock School',
        shortCode: 'MOCK',
        logoUrl: null,
        subscriptionTier: 'free',
        activeCurriculum: 'nerdc',
        activeCurriculumVersion: '2024',
        totalSeats: 5,
        schoolMasterKeyWrapped: 'bW9ja193cmFwcGVkX21hc3Rlcl9rZXk=',
        adminRecoveryEmail: null,
        adminRecoveryEmailVerified: false,
        createdAt: now.subtract(const Duration(days: 30)),
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
  }
}

/// Error codes returned by [AuthService] operations.
enum AuthErrorCode {
  invalidCredentials,
  accountDeactivated,
  invalidActivationCode,
  invalidOtp,
  invalidRecoveryCode,
  notFound,
  validationError,
  networkError,
}

/// Exception thrown when an auth operation fails.
class AuthException implements Exception {
  final AuthErrorCode code;
  final String message;
  final dynamic originalError;

  AuthException({
    required this.code,
    required this.message,
    this.originalError,
  });

  @override
  String toString() => 'AuthException($code): $message';
}
