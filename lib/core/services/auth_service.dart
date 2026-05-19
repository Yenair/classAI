import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:classai/core/database/database.dart';

/// Result of a login, activation, signup or password recovery operation.
class AuthResult {
  final Teacher teacher;
  final School school;
  final String? wrappedSchoolKey; // base64
  final int passwordHashVersion;
  final int offlineCredits;
  final DateTime lastCreditRefillServerTime;
  final bool? forcePasswordReset;

  AuthResult({
    required this.teacher,
    required this.school,
    this.wrappedSchoolKey,
    required this.passwordHashVersion,
    required this.offlineCredits,
    required this.lastCreditRefillServerTime,
    this.forcePasswordReset,
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
/// All server-interacting methods work against a real Supabase client.
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

  /// Send an SMS OTP to a phone number for passwordless login fallback.
  /// Uses Termii (primary) or BulkSMS Nigeria (fallback).
  Future<void> sendSmsOtp(String phoneNumber);

  /// Verify an OTP code sent via SMS.
  /// Returns true if the code is valid.
  Future<bool> verifySmsOtp(String phoneNumber, String code);

  /// Register a new school and admin account.
  ///
  /// Calls POST /functions/v1/signup with school_name, admin_email,
  /// admin_password and optional recovery_email.
  Future<AuthResult> signup(
    String schoolName,
    String adminEmail,
    String adminPassword,
    String? recoveryEmail,
  );

  /// Add a teacher to the school (admin-only).
  ///
  /// Calls POST /functions/v1/add-teacher with email, teacher_name, role
  /// and the admin's JWT in the Authorization header.
  Future<void> addTeacher(
    String email,
    String teacherName,
    String role,
  );

  /// Change the current user's password.
  ///
  /// Calls POST /functions/v1/change-password with new_password
  /// and the JWT in the Authorization header.
  Future<void> changePassword(String newPassword);
}

/// Real implementation of [AuthService] backed by Supabase.
///
/// Uses [Supabase.instance.client] for authentication and calls Supabase Edge
/// Functions for activation, admin recovery, and teacher recovery flows.
class SupabaseAuthService implements AuthService {
  supabase_pkg.GoTrueClient get _auth => supabase_pkg.Supabase.instance.client.auth;

  @override
  Future<AuthResult> login(
    String email,
    String password,
    String deviceId,
  ) async {
    final response = await _auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw AuthException(
        code: AuthErrorCode.invalidCredentials,
        message: 'Invalid email or password.',
      );
    }

    // Fetch teacher profile and school from the database
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final teacherData = await client
          .from('teachers')
          .select('*, schools(*)')
          .eq('id', user.id)
          .single();

      final schoolData = teacherData['schools'] as Map<String, dynamic>;

      final school = School(
        localId: 0,
        serverId: schoolData['id'] as String?,
        schoolName: schoolData['school_name'] as String,
        shortCode: schoolData['short_code'] as String? ?? '',
        logoUrl: schoolData['logo_url'] as String?,
        subscriptionTier:
            schoolData['subscription_tier'] as String? ?? 'free',
        activeCurriculum:
            schoolData['active_curriculum'] as String? ?? 'nerdc',
        activeCurriculumVersion:
            schoolData['active_curriculum_version'] as String?,
        totalSeats: schoolData['total_seats'] as int? ?? 5,
        schoolMasterKeyWrapped:
            schoolData['school_master_key_wrapped'] as String?,
        adminRecoveryEmail: schoolData['admin_recovery_email'] as String?,
        adminRecoveryEmailVerified:
            schoolData['admin_recovery_email_verified'] as bool? ?? false,
        createdAt: DateTime.parse(schoolData['created_at'] as String),
        updatedAt: DateTime.parse(schoolData['updated_at'] as String),
        updateCounter: schoolData['update_counter'] as int? ?? 0,
        isDeleted: schoolData['is_deleted'] as bool? ?? false,
        lastModifiedBy: schoolData['last_modified_by'] as String?,
      );

      final teacher = Teacher(
        localId: 0,
        serverId: teacherData['id'] as String?,
        email: teacherData['email'] as String,
        teacherName: teacherData['teacher_name'] as String,
        role: teacherData['role'] as String? ?? 'teacher',
        schoolLocalId: 0,
        schoolServerId: schoolData['id'] as String?,
        isActive: teacherData['is_active'] as bool? ?? true,
        forcePasswordReset:
            teacherData['force_password_reset'] as bool? ?? false,
        passwordHashVersion:
            teacherData['password_hash_version'] as int? ?? 1,
        schoolKeyWrapped: teacherData['school_key_wrapped'] as String?,
        lastCreditRefillDate: teacherData['last_credit_refill_date'] != null
            ? DateTime.parse(
                teacherData['last_credit_refill_date'] as String)
            : null,
        createdAt: DateTime.parse(teacherData['created_at'] as String),
        updatedAt: DateTime.parse(teacherData['updated_at'] as String),
        updateCounter: teacherData['update_counter'] as int? ?? 0,
        isDeleted: teacherData['is_deleted'] as bool? ?? false,
        salt: teacherData['salt'] as String?,
        lastModifiedBy: teacherData['last_modified_by'] as String?,
      );

      final forcePwdReset =
          teacherData['force_password_reset'] as bool? ?? false;

      return AuthResult(
        teacher: teacher,
        school: school,
        wrappedSchoolKey:
            schoolData['school_master_key_wrapped'] as String?,
        passwordHashVersion:
            teacherData['password_hash_version'] as int? ?? 1,
        offlineCredits: 3, // placeholder
        lastCreditRefillServerTime:
            teacherData['last_credit_refill_date'] != null
                ? DateTime.parse(
                    teacherData['last_credit_refill_date'] as String)
                : DateTime.now(),
        forcePasswordReset: forcePwdReset,
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to fetch teacher profile.',
        originalError: e,
      );
    }
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
    if (isAdmin && (recoveryEmail == null || recoveryEmail.isEmpty)) {
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: 'Recovery email is required for admin activation.',
      );
    }

    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'activate',
        body: {
          'activationCode': code,
          'email': email,
          'password': password,
          'deviceId': deviceId,
          'isAdmin': isAdmin,
          'recoveryEmail': recoveryEmail,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.invalidActivationCode,
          message: errorResponse,
        );
      }
      return _parseAuthResult(data);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Activation failed. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<void> logout() async {
    await _auth.signOut();
  }

  @override
  Future<AdminRecoveryResult> requestAdminOtp(String email) async {
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'admin-recovery-request',
        body: {'email': email},
      );
      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.notFound,
          message: errorResponse,
        );
      }
      return AdminRecoveryResult(
        otpSent: data['otp_sent'] as bool? ?? true,
        otpExpiry: DateTime.parse(data['otp_expiry'] as String),
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<AuthResult> verifyAdminOtp(
    String email,
    String otp,
    String newPassword,
  ) async {
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'admin-recovery-verify-otp',
        body: {
          'email': email,
          'otp': otp,
          'newPassword': newPassword,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.invalidOtp,
          message: errorResponse,
        );
      }
      return _parseAuthResult(data);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Verification failed. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<String> generateTeacherRecoveryCode(
    String teacherId,
    String adminId,
  ) async {
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'recovery-generate-code',
        body: {
          'teacherId': teacherId,
          'adminId': adminId,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.networkError,
          message: errorResponse,
        );
      }
      if (data['recovery_code'] is String) {
        return data['recovery_code'] as String;
      }
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Unexpected response from server.',
      );
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<AuthResult> recoverTeacherPassword(
    String email,
    String recoveryCode,
    String newPassword,
  ) async {
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'recovery-reset-password',
        body: {
          'email': email,
          'recoveryCode': recoveryCode,
          'newPassword': newPassword,
        },
      );
      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.invalidRecoveryCode,
          message: errorResponse,
        );
      }
      return _parseAuthResult(data);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Password recovery failed. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<void> sendSmsOtp(String phoneNumber) async {
    throw UnimplementedError('SMS OTP is currently unavailable');
  }

  @override
  Future<bool> verifySmsOtp(String phoneNumber, String code) async {
    throw UnimplementedError('SMS OTP is currently unavailable');
  }

  @override
  Future<AuthResult> signup(
    String schoolName,
    String adminEmail,
    String adminPassword,
    String? recoveryEmail,
  ) async {
    final client = supabase_pkg.Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'signup',
        body: {
          'school_name': schoolName,
          'admin_email': adminEmail,
          'admin_password': adminPassword,
          'recovery_email': recoveryEmail,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.validationError,
          message: errorResponse,
        );
      }
      return _parseAuthResult(data);
    } on AuthException {
      rethrow;
    } catch (e) {
      // Capture full error details in Sentry for diagnosis
      await Sentry.captureException(e);
      final detail = e.toString();
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Signup failed. $detail',
        originalError: e,
      );
    }
  }

  @override
  Future<void> addTeacher(
    String email,
    String teacherName,
    String role,
  ) async {
    final client = supabase_pkg.Supabase.instance.client;
    final session = client.auth.currentSession;
    final jwt = session?.accessToken;
    if (jwt == null || jwt.isEmpty) {
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: 'No active session. Please login again.',
      );
    }

    try {
      final response = await client.functions.invoke(
        'add-teacher',
        headers: {'Authorization': 'Bearer $jwt'},
        body: {
          'email': email,
          'teacher_name': teacherName,
          'role': role,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.validationError,
          message: errorResponse,
        );
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to add teacher. Please try again.',
        originalError: e,
      );
    }
  }

  @override
  Future<void> changePassword(String newPassword) async {
    final client = supabase_pkg.Supabase.instance.client;
    final session = client.auth.currentSession;
    final jwt = session?.accessToken;
    if (jwt == null || jwt.isEmpty) {
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: 'No active session. Please login again.',
      );
    }

    try {
      final response = await client.functions.invoke(
        'change-password',
        headers: {'Authorization': 'Bearer $jwt'},
        body: {
          'new_password': newPassword,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        throw AuthException(
          code: AuthErrorCode.validationError,
          message: errorResponse,
        );
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to change password. Please try again.',
        originalError: e,
      );
    }
  }

  /// Parses the edge function response map into an [AuthResult].
  ///
  /// Expected keys:
  /// - `teacher` (Map with id, email, name, role, school_id)
  /// - `school` (Map with id, name, subscription_tier)
  /// - `wrapped_school_key` (String? base64)
  /// - `password_hash_version` (int)
  /// - `offline_credits` (int)
  /// - `last_credit_refill_server_time` (String ISO date)
  AuthResult _parseAuthResult(Map<String, dynamic> data) {
    final teacherMap = data['teacher'] as Map<String, dynamic>?;
    final schoolMap = data['school'] as Map<String, dynamic>?;

    if (teacherMap == null || schoolMap == null) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Invalid server response: missing teacher or school data.',
      );
    }

    final school = School(
      localId: 0,
      serverId: schoolMap['id'] as String?,
      schoolName: schoolMap['name'] as String? ?? schoolMap['school_name'] as String? ?? '',
      shortCode: '',
      logoUrl: null,
      subscriptionTier: schoolMap['subscription_tier'] as String? ?? 'free',
      activeCurriculum: 'nerdc',
      activeCurriculumVersion: null,
      totalSeats: 5,
      schoolMasterKeyWrapped: data['wrapped_school_key'] as String?,
      adminRecoveryEmail: null,
      adminRecoveryEmailVerified: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      updateCounter: 0,
      isDeleted: false,
      lastModifiedBy: null,
    );

    final teacher = Teacher(
      localId: 0,
      serverId: teacherMap['id'] as String?,
      email: teacherMap['email'] as String? ?? '',
      teacherName: teacherMap['name'] as String? ?? teacherMap['teacher_name'] as String? ?? '',
      role: teacherMap['role'] as String? ?? 'teacher',
      schoolLocalId: 0,
      schoolServerId: schoolMap['id'] as String?,
      isActive: true,
      forcePasswordReset: false,
      passwordHashVersion: data['password_hash_version'] as int? ?? 1,
      schoolKeyWrapped: data['wrapped_school_key'] as String?,
      lastCreditRefillDate: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      updateCounter: 0,
      isDeleted: false,
      salt: null,
      lastModifiedBy: null,
    );

    final serverTimeStr = data['last_credit_refill_server_time'] as String?;
    final serverTime = serverTimeStr != null
        ? DateTime.tryParse(serverTimeStr) ?? DateTime.now()
        : DateTime.now();

    return AuthResult(
      teacher: teacher,
      school: school,
      wrappedSchoolKey: data['wrapped_school_key'] as String?,
      passwordHashVersion: data['password_hash_version'] as int? ?? 1,
      offlineCredits: data['offline_credits'] as int? ?? 3,
      lastCreditRefillServerTime: serverTime,
      forcePasswordReset: data['force_password_reset'] as bool?,
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
