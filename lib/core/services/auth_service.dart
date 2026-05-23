import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:classai/core/constants/app_constants.dart';
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
  final bool emailVerified;

  AuthResult({
    required this.teacher,
    required this.school,
    this.wrappedSchoolKey,
    required this.passwordHashVersion,
    required this.offlineCredits,
    required this.lastCreditRefillServerTime,
    this.forcePasswordReset,
    this.emailVerified = false,
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
  supabase_pkg.GoTrueClient get _auth =>
      supabase_pkg.Supabase.instance.client.auth;

  @override
  Future<AuthResult> login(
    String email,
    String password,
    String deviceId,
  ) async {
    // Uses the custom JWT auth Edge Function, not Supabase Auth's
    // built-in provider. Passwords are validated server-side with bcrypt+pepper.
    final client = supabase_pkg.Supabase.instance.client;
    final url = '${AppConstants.supabaseUrl}/functions/v1/login';
    debugPrint('[DEBUG] login() — Full Edge Function URL: $url');
    debugPrint(
        '[DEBUG] login() — Request body: email=$email, device_id=$deviceId');
    try {
      final response = await client.functions.invoke(
        'login',
        body: {
          'email': email,
          'password': password,
          'device_id': deviceId,
        },
      );

      // Debug: print response status and data
      debugPrint('[DEBUG] login() — Response status: ${response.status}');
      debugPrint('[DEBUG] login() — Response data: ${response.data}');

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['error'] != null) {
        debugPrint(
            '[DEBUG] login() — Error in response data: ${data?['error']}');
        throw AuthException(
          code: AuthErrorCode.networkError,
          message: (data?['error'] as String?) ??
              'Login failed. Please check your credentials.',
        );
      }

      return _parseAuthResult(data);
    } on AuthException {
      rethrow;
    } on supabase_pkg.FunctionException catch (e) {
      debugPrint(
          '[DEBUG] login() — FunctionException caught: status=${e.status}, details=${e.details}');

      // Try to parse the response body and extract the error field
      final serverError = _extractErrorFromResponse(e.details);

      if (serverError != null) {
        // Server returned a JSON body with an "error" field
        throw AuthException(
          code: AuthErrorCode.invalidCredentials,
          message: serverError,
          originalError: e,
        );
      }

      // Body could not be parsed or has no "error" field
      throw AuthException(
        code: AuthErrorCode.invalidCredentials,
        message: 'Server error (status: ${e.status})',
        originalError: e,
      );
    } catch (e) {
      debugPrint('[DEBUG] login() — RAW EXCEPTION TYPE: ${e.runtimeType}');
      debugPrint('[DEBUG] login() — RAW EXCEPTION MESSAGE: $e');
      debugPrint('[DEBUG] login() — EXCEPTION CAUGHT: ${e.runtimeType}: $e');
      // Detect connectivity-related exceptions and return a user-friendly message
      if (_isConnectivityException(e)) {
        throw AuthException(
          code: AuthErrorCode.networkError,
          message:
              'No internet connection. Please check your connection and try again.',
          originalError: e,
        );
      }
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: '${e.runtimeType}: $e',
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
    } on AuthException {
      rethrow;
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.invalidActivationCode,
        message: serverError ?? 'Activation failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.notFound,
        message: serverError ?? 'Request failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.invalidOtp,
        message:
            serverError ?? 'Verification failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: serverError ??
            'Recovery code generation failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.invalidRecoveryCode,
        message: serverError ??
            'Password recovery failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    final url = '${AppConstants.supabaseUrl}/functions/v1/signup';
    debugPrint('[DEBUG] signup() — Full Edge Function URL: $url');
    debugPrint(
        '[DEBUG] signup() — Request body: school_name=$schoolName, admin_email=$adminEmail');
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

      debugPrint('[DEBUG] signup() — Response status: ${response.status}');
      debugPrint('[DEBUG] signup() — Response data: ${response.data}');

      final data = response.data as Map<String, dynamic>;
      final errorResponse = data['error'] as String?;
      if (errorResponse != null) {
        debugPrint('[DEBUG] signup() — Error in response data: $errorResponse');
        throw AuthException(
          code: AuthErrorCode.validationError,
          message: errorResponse,
        );
      }
      return _parseAuthResult(data);
    } on AuthException {
      rethrow;
    } on supabase_pkg.FunctionException catch (e) {
      debugPrint(
          '[DEBUG] signup() — FunctionException caught: status=${e.status}, details=${e.details}');
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: serverError ?? 'Signup failed (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      debugPrint('[DEBUG] signup() — RAW EXCEPTION TYPE: ${e.runtimeType}');
      debugPrint('[DEBUG] signup() — RAW EXCEPTION MESSAGE: $e');
      debugPrint('[DEBUG] signup() — EXCEPTION CAUGHT: ${e.runtimeType}: $e');
      // Only network-level errors reach here
      await Sentry.captureException(e);
      // Detect connectivity-related exceptions and return a user-friendly message
      if (_isConnectivityException(e)) {
        throw AuthException(
          code: AuthErrorCode.networkError,
          message:
              'No internet connection. Please check your connection and try again.',
          originalError: e,
        );
      }
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.validationError,
        message:
            serverError ?? 'Failed to add teacher (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
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
    } on supabase_pkg.FunctionException catch (e) {
      final serverError =
          (e.details is Map && (e.details as Map)['error'] != null)
              ? (e.details as Map)['error'] as String
              : null;
      throw AuthException(
        code: AuthErrorCode.validationError,
        message: serverError ??
            'Failed to change password (server error ${e.status}).',
        originalError: e,
      );
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Network error. Please check your connection and try again.',
        originalError: e,
      );
    }
  }

  /// Attempts to extract an `error` field from a [FunctionException.details].
  ///
  /// [details] can be a parsed JSON [Map] (when Content-Type was
  /// `application/json`) or a raw [String] (for other content types).
  /// Returns the error message string, or `null` if extraction fails.
  String? _extractErrorFromResponse(dynamic details) {
    try {
      if (details is Map) {
        return details['error'] as String?;
      }
      if (details is String) {
        final body = jsonDecode(details) as Map<String, dynamic>;
        return body['error'] as String?;
      }
    } catch (_) {
      // Response body is not valid JSON or has unexpected structure
    }
    return null;
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

    // Fallback: if the school object lacks an 'id', use the teacher's
    // school_id (which the login edge function always includes).
    final schoolId =
        schoolMap['id'] as String? ?? teacherMap['school_id'] as String?;

    final school = School(
      localId: 0,
      serverId: schoolId,
      schoolName: schoolMap['name'] as String? ??
          schoolMap['school_name'] as String? ??
          '',
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
      teacherName: teacherMap['name'] as String? ??
          teacherMap['teacher_name'] as String? ??
          '',
      role: teacherMap['role'] as String? ?? 'teacher',
      schoolLocalId: 0,
      schoolServerId: schoolId,
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
      emailVerified: data['email_verified'] as bool? ?? false,
    );
  }

  /// Returns `true` if [e] is a connectivity-related exception.
  ///
  /// Checks for [SocketException], [DioException] with connection error types,
  /// and generic exceptions whose message contains "Failed host lookup" or
  /// "Connection refused".
  bool _isConnectivityException(Object e) {
    if (e is SocketException) return true;
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          // unknown may include DNS resolution failures; check message too
          final msg = e.message?.toLowerCase() ?? '';
          if (msg.contains('failed host lookup') ||
              msg.contains('connection refused') ||
              msg.contains('socketexception') ||
              msg.contains('network is unreachable')) {
            return true;
          }
          return false;
        default:
          return false;
      }
    }
    final msg = e.toString().toLowerCase();
    return msg.contains('failed host lookup') ||
        msg.contains('connection refused');
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
