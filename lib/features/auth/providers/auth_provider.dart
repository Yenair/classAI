import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' show ClientException;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/main.dart' show databaseProvider, navigatorKey;

// ---------------------------------------------------------------------------
// Dependency providers (to be overridden with real implementations later)
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  // Default production implementation. Override in tests with a mock
  // via ProviderContainer overrides.
  return SupabaseAuthService();
});

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});

// ---------------------------------------------------------------------------
// Auth state machine
// ---------------------------------------------------------------------------

/// Possible states of the authentication state machine.
enum AuthState {
  /// App just launched, no auth checks performed yet.
  uninitialized,

  /// Checking if a stored password hash exists locally (for offline login).
  checkingLocalAuth,

  /// Password hash found locally, attempting offline login.
  offlineLoginAttempt,

  /// No local credentials or offline login failed — user must go online.
  onlineLoginRequired,

  /// Successfully authenticated.
  authenticated,

  /// Server reported account as deactivated.
  accountDeactivated,

  /// Emergency save in progress before forced logout.
  emergencySaving,

  /// Server requires the user to change their password before proceeding.
  /// The UI should show a password-change screen.
  forcePasswordResetRequired,

  /// Login/signup succeeded but the teacher's email is not yet verified.
  /// The UI should show a non-dismissible email verification popup.
  emailVerificationRequired,
}

/// Holds the current [AuthState] plus any associated data from transitions.
class AuthStateData {
  final AuthState state;
  final Teacher? currentTeacher;
  final School? currentSchool;
  final String? errorMessage;
  final int offlineLoginAttempts;

  const AuthStateData({
    required this.state,
    this.currentTeacher,
    this.currentSchool,
    this.errorMessage,
    this.offlineLoginAttempts = 0,
  });

  AuthStateData copyWith({
    AuthState? state,
    Teacher? currentTeacher,
    School? currentSchool,
    String? errorMessage,
    int? offlineLoginAttempts,
    bool clearError = false,
    bool clearTeacher = false,
    bool clearSchool = false,
  }) {
    return AuthStateData(
      state: state ?? this.state,
      currentTeacher:
          clearTeacher ? null : (currentTeacher ?? this.currentTeacher),
      currentSchool: clearSchool ? null : (currentSchool ?? this.currentSchool),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      offlineLoginAttempts: offlineLoginAttempts ?? this.offlineLoginAttempts,
    );
  }
}

/// Notifier implementing the Auth State Machine defined in phase_03_auth.md.
class AuthNotifier extends Notifier<AuthStateData> {
  static const int maxOfflineAttempts = 3;
  bool _isResending = false;

  @override
  AuthStateData build() {
    return const AuthStateData(state: AuthState.uninitialized);
  }

  AppDatabase get _db => ref.read(databaseProvider);
  AuthService get _authService => ref.read(authServiceProvider);
  SecurityService get _securityService => ref.read(securityServiceProvider);
  EmergencyFlushService get _emergencyFlushService =>
      ref.read(emergencyFlushServiceProvider);

  // -----------------------------------------------------------------------
  // State machine transitions
  // -----------------------------------------------------------------------

  /// Called on app start. Checks for stored password hash to attempt offline login.
  Future<void> checkLocalAuth() async {
    state = state.copyWith(
      state: AuthState.checkingLocalAuth,
      clearError: true,
    );

    try {
      // Offline login is disabled: the server uses bcrypt+pepper for
      // password verification while the client only stored a SHA-256 hash
      // that will never match. In both cases the user must log in online.
      // Transition silently — no error banner should appear just because
      // the app started.
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        clearError: true,
      );
    }
  }

  /// Attempt offline login using stored password hash.
  /// Returns true if login succeeded.
  Future<bool> attemptOfflineLogin(String password) async {
    // Offline login is disabled — the server uses bcrypt+pepper for
    // password verification while the client stored a SHA-256 hash that
    // will never match. Only surface the "connect to the internet" message
    // when the device is actually offline; otherwise silently return false
    // so the caller can proceed to online login without a scary banner.
    final isOnline = await PlatformHelper.isOnline();
    if (!isOnline) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'Offline login unavailable — connect to the internet to sign in.',
        offlineLoginAttempts: 0,
      );
    } else {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        clearError: true,
        offlineLoginAttempts: 0,
      );
    }
    return false;
  }

  /// Perform server-side login with email, password, and device ID.
  Future<void> loginOnline({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    // Check connectivity before making the API call
    final isOnline = await PlatformHelper.isOnline();
    if (!isOnline) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'No internet connection. Please check your connection and try again.',
      );
      return;
    }

    try {
      final result = await _authService.login(email, password, deviceId);

      // Store password hash locally for future offline login
      await _securityService.storePasswordHash(password);

      // Update local database with server state
      await _saveAuthResultToLocalDb(result);

      if (result.forcePasswordReset == true) {
        // Server flagged this account for forced password reset.
        // Transition to a dedicated state so the UI shows the change-password screen.
        state = state.copyWith(
          state: AuthState.forcePasswordResetRequired,
          currentTeacher: result.teacher,
          currentSchool: result.school,
          offlineLoginAttempts: 0,
        );
        return;
      }

      if (!result.emailVerified) {
        // Email not yet verified — show the verification popup.
        state = state.copyWith(
          state: AuthState.emailVerificationRequired,
          currentTeacher: result.teacher,
          currentSchool: result.school,
          offlineLoginAttempts: 0,
        );
        return;
      }

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
        offlineLoginAttempts: 0,
      );

      // Navigate based on role — admin goes to /admin, teachers go to /
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          final isAdmin = result.teacher.role == 'admin';
          GoRouter.of(ctx).go(isAdmin ? '/admin' : '/');
        }
      });
    } on AuthException catch (e) {
      debugPrint(
          '[DEBUG] loginOnline() — AUTH EXCEPTION: code=${e.code}, message=${e.message}');
      switch (e.code) {
        case AuthErrorCode.accountDeactivated:
          state = state.copyWith(
            state: AuthState.accountDeactivated,
            errorMessage: e.message,
          );
          break;
        case AuthErrorCode.invalidCredentials:
          state = state.copyWith(
            state: AuthState.onlineLoginRequired,
            errorMessage: 'Invalid email or password. Please try again.',
          );
          break;
        default:
          state = state.copyWith(
            state: AuthState.onlineLoginRequired,
            errorMessage: e.message,
          );
      }
    } catch (e) {
      debugPrint(
          '[DEBUG] loginOnline() — UNEXPECTED EXCEPTION TYPE: ${e.runtimeType}');
      debugPrint('[DEBUG] loginOnline() — UNEXPECTED EXCEPTION MESSAGE: $e');
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'No internet connection. Please check your connection and try again.',
      );
    }
  }

  /// Activate a new account using an activation code.
  Future<void> activateAccount({
    required String code,
    required String email,
    required String password,
    required String deviceId,
    required bool isAdmin,
    String? recoveryEmail,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    try {
      final result = await _authService.activate(
        code,
        email,
        password,
        deviceId,
        isAdmin: isAdmin,
        recoveryEmail: recoveryEmail,
      );

      await _securityService.storePasswordHash(password);
      await _saveAuthResultToLocalDb(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Activation failed. Please try again.',
      );
    }
  }

  /// Perform a manual logout (clean).
  Future<void> manualLogout() async {
    await _performLogout(
        isForced: false, targetState: AuthState.onlineLoginRequired);
  }

  /// Perform a forced logout (triggers emergency save).
  Future<void> forceLogout() async {
    await _performLogout(isForced: true);
  }

  Future<void> _performLogout(
      {required bool isForced,
      AuthState targetState = AuthState.uninitialized}) async {
    if (isForced) {
      state = state.copyWith(state: AuthState.emergencySaving);

      try {
        await _emergencyFlushService.flushAll();
      } catch (e) {
        // Flush errors are logged inside flushAll; continue with logout
        await Sentry.captureException(
          e,
          hint: null,
        );
      }
    }

    try {
      await _authService.logout();
    } catch (e) {
      // Server logout failure is non-blocking
      await Sentry.captureException(
        e,
        hint: null,
      );
    }

    await _securityService.clearAll();

    state = AuthStateData(state: targetState);
  }

  /// Request OTP for admin password recovery.
  Future<AdminRecoveryResult> requestAdminOtp(String email) async {
    return await _authService.requestAdminOtp(email);
  }

  /// Verify admin OTP and set new password.
  Future<void> verifyAdminOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    try {
      final result = await _authService.verifyAdminOtp(email, otp, newPassword);

      await _securityService.storePasswordHash(newPassword);
      await _saveAuthResultToLocalDb(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Verification failed. Please try again.',
      );
    }
  }

  /// Generate a teacher recovery code (admin only).
  /// The returned 16-character alphanumeric code expires after 24 hours.
  /// This is called by the [TeacherDetailScreen] in the admin dashboard.
  Future<String> generateTeacherRecoveryCode(
    String teacherId,
    String adminId,
  ) async {
    return await _authService.generateTeacherRecoveryCode(teacherId, adminId);
  }

  /// Recover a teacher's password using a recovery code.
  Future<void> recoverTeacherPassword({
    required String email,
    required String recoveryCode,
    required String newPassword,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    try {
      final result = await _authService.recoverTeacherPassword(
        email,
        recoveryCode,
        newPassword,
      );

      await _securityService.storePasswordHash(newPassword);
      await _saveAuthResultToLocalDb(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Password recovery failed. Please try again.',
      );
    }
  }

  /// Register a new school and admin account via the signup edge function.
  ///
  /// On success, stores the password hash locally, upserts the school/teacher
  /// records in the local DB, and transitions to [AuthState.authenticated].
  Future<void> signup({
    required String schoolName,
    required String adminEmail,
    required String adminPassword,
    String? recoveryEmail,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    // Check connectivity before making the API call
    final isOnline = await PlatformHelper.isOnline();
    if (!isOnline) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'No internet connection. Please check your connection and try again.',
      );
      return;
    }

    try {
      final result = await _authService.signup(
        schoolName,
        adminEmail,
        adminPassword,
        recoveryEmail,
      );

      await _securityService.storePasswordHash(adminPassword);
      await _saveAuthResultToLocalDb(result);

      if (!result.emailVerified) {
        state = state.copyWith(
          state: AuthState.emailVerificationRequired,
          currentTeacher: result.teacher,
          currentSchool: result.school,
        );
        return;
      }

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      // Log to Sentry and surface the actual error for debugging
      await Sentry.captureException(e);
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'No internet connection. Please check your connection and try again.',
      );
    }
  }

  /// Verify the 6-digit email verification code by calling the verify-code
  /// edge function with the current JWT.
  ///
  /// On success, transitions to [AuthState.authenticated].
  Future<void> verifyEmailCode(String code) async {
    final jwt = _authService.currentJwt;

    try {
      if (jwt == null || jwt.isEmpty) {
        // No JWT available — show an error
        state = state.copyWith(
          errorMessage: 'No active session. Please login again.',
          clearError: false,
        );
        return;
      }

      final client = supabase_pkg.Supabase.instance.client;
      final response = await client.functions.invoke(
        'verify-code',
        headers: {'Authorization': 'Bearer $jwt'},
        body: {'code': code},
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        state = state.copyWith(
          state: AuthState.authenticated,
          clearError: true,
        );
      } else {
        final error = data['error'] as String? ?? 'Verification failed.';
        state = state.copyWith(errorMessage: error, clearError: false);
      }
    } on supabase_pkg.FunctionException catch (e) {
      // Server returned an error response – extract the actual message
      final details = e.details;
      String errorMessage;
      if (details is Map<String, dynamic>) {
        errorMessage = details['error'] as String? ??
            details['message'] as String? ??
            'Verification failed.';
      } else if (details is String) {
        errorMessage = details;
      } else {
        errorMessage = 'Verification failed.';
      }
      state = state.copyWith(errorMessage: errorMessage, clearError: false);
    } catch (e) {
      debugPrint('[AuthNotifier] verifyEmailCode error: $e');
      state = state.copyWith(
        errorMessage: 'Failed to verify code. Please try again.',
        clearError: false,
      );
    }
  }

  /// Resend the email verification code by calling the send-verification-code
  /// edge function.
  ///
  /// Remains in [AuthState.emailVerificationRequired].
  Future<void> resendVerificationCode() async {
    if (_isResending) {
      return;
    }

    final jwt = _authService.currentJwt;
    final email = state.currentTeacher?.email;
    if (email == null || email.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No email associated with this account.',
        clearError: false,
      );
      return;
    }

    // The send-verification-code edge function requires a valid JWT.
    // If there's no active session, show an error instead of calling the function.
    if (jwt == null || jwt.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No active session. Please login again.',
        clearError: false,
      );
      return;
    }

    final Map<String, dynamic> body = {'email': email};

    _isResending = true;
    try {
      final client = supabase_pkg.Supabase.instance.client;

      // Add 15-second timeout to prevent UI hanging
      final response = await client.functions
          .invoke(
            'send-verification-code',
            headers: {'Authorization': 'Bearer $jwt'},
            body: body,
          )
          .timeout(
            const Duration(seconds: 15),
          );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        state = state.copyWith(
          clearError: true,
          errorMessage: null,
        );
      } else {
        debugPrint(
          '[AuthNotifier] resendVerificationCode response body: ${response.data}',
        );
        final error = data['error'] as String? ?? 'Failed to resend code.';
        final step = data['step'] as String?;
        final stack = data['stack'] as String?;
        final detailedError = step == null ? error : '$error (step: $step)';
        debugPrint(
          '[AuthNotifier] resendVerificationCode server error: $detailedError',
        );
        if (stack != null && stack.isNotEmpty) {
          debugPrint('[AuthNotifier] resendVerificationCode stack:\n$stack');
        }
        state = state.copyWith(
          errorMessage: detailedError,
          clearError: false,
        );
      }
    } on TimeoutException {
      state = state.copyWith(
        errorMessage:
            'The verification email is taking too long to send. Please try again in a moment.',
        clearError: false,
      );
    } on ClientException {
      state = state.copyWith(
        errorMessage:
            'Could not reach the verification service. Please check your connection and try again.',
        clearError: false,
      );
    } on supabase_pkg.FunctionException catch (e) {
      // Server returned an error response – extract the actual message
      final details = e.details;
      debugPrint(
        '[AuthNotifier] resendVerificationCode FunctionException: status=${e.status}, details=$details',
      );
      String errorMessage;
      if (details is Map<String, dynamic>) {
        errorMessage = details['error'] as String? ??
            details['message'] as String? ??
            'Failed to resend code.';
        final step = details['step'] as String?;
        if (step != null && step.isNotEmpty) {
          errorMessage = '$errorMessage (step: $step)';
        }
        final stack = details['stack'] as String?;
        if (stack != null && stack.isNotEmpty) {
          debugPrint('[AuthNotifier] resendVerificationCode stack:\n$stack');
        }
      } else if (details is String) {
        errorMessage = details;
      } else {
        errorMessage = 'Failed to resend code.';
      }
      state = state.copyWith(errorMessage: errorMessage, clearError: false);
    } catch (e) {
      debugPrint('[AuthNotifier] resendVerificationCode error: $e');
      debugPrint(
        '[AuthNotifier] resendVerificationCode raw exception type: ${e.runtimeType}',
      );
      // Check if this is actually a connectivity issue
      final isOnline = await PlatformHelper.isOnline();
      if (!isOnline) {
        state = state.copyWith(
          errorMessage:
              'No internet connection. Please check your connection and try again.',
          clearError: false,
        );
      } else {
        state = state.copyWith(
          errorMessage:
              'Verification email could not be sent. Please try again later.',
          clearError: false,
        );
      }
    } finally {
      _isResending = false;
    }
  }

  /// Change the current user's password via the change-password edge function.
  ///
  /// On success the password hash in local storage is updated and the state
  /// transitions to [AuthState.authenticated]. If the user was in
  /// [AuthState.forcePasswordResetRequired], this resolves the forced reset.
  Future<void> changePassword(String newPassword) async {
    try {
      await _authService.changePassword(newPassword);

      // Update the locally stored password hash for future offline login
      await _securityService.storePasswordHash(newPassword);

      // Transition to authenticated state
      state = state.copyWith(
        state: AuthState.authenticated,
        clearError: true,
      );
    } on AuthException catch (e) {
      state = state.copyWith(
        state:
            state.state, // keep current state (e.g. forcePasswordResetRequired)
        errorMessage: e.message,
      );
    } catch (e) {
      state = state.copyWith(
        state: state.state,
        errorMessage: 'Failed to change password. Please try again.',
      );
    }
  }

  /// Add a teacher to the school (admin-only action).
  ///
  /// Delegates to [AuthService.addTeacher] and returns a success indicator.
  /// Does not change the auth state.
  Future<void> addTeacher({
    required String email,
    required String teacherName,
    required String role,
  }) async {
    try {
      await _authService.addTeacher(email, teacherName, role);
    } on AuthException {
      // Let AuthException propagate so the UI can catch and display it
      rethrow;
    } catch (e) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to add teacher. Please try again.',
        originalError: e,
      );
    }
  }

  /// Set an error message on the current auth state without changing
  /// the current state machine phase.
  ///
  /// Used by the [LoginScreen] as a last-resort fallback when an
  /// unexpected exception escapes the normal error-handling flow.
  void setErrorMessage(String message) {
    state = state.copyWith(
      errorMessage: message,
      clearError: false,
    );
  }

  /// Clear any displayed error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  Future<void> _saveAuthResultToLocalDb(AuthResult result) async {
    // Guaranteed to return a School row with a valid non-zero localId.
    // `upsertByServerId` SELECTs by serverId, UPDATEs the existing row, or
    // INSERTs a new one — in all cases the returned School has the correct
    // persistent localId that can safely be used as the teacher's foreign key.
    final schoolRow = await _db.schoolsDao.upsertByServerId(
      serverId: result.school.serverId!,
      schoolName: result.school.schoolName,
      shortCode: result.school.shortCode,
      subscriptionTier: result.school.subscriptionTier,
      activeCurriculum: result.school.activeCurriculum,
      activeCurriculumVersion: result.school.activeCurriculumVersion,
      totalSeats: result.school.totalSeats,
      schoolMasterKeyWrapped: result.school.schoolMasterKeyWrapped,
      adminRecoveryEmail: result.school.adminRecoveryEmail,
      adminRecoveryEmailVerified: result.school.adminRecoveryEmailVerified,
    );
    final schoolLocalIdToUse = schoolRow.localId;

    // Upsert teacher record - schoolLocalIdToUse is guaranteed non-zero
    if (result.teacher.serverId != null) {
      final existingTeachers = await (_db.select(_db.teachers)
            ..where((t) => t.serverId.equals(result.teacher.serverId!)))
          .get();

      if (existingTeachers.isNotEmpty) {
        final existing = existingTeachers.first;

        await (_db.update(_db.teachers)
              ..where((t) => t.localId.equals(existing.localId)))
            .write(
          TeachersCompanion(
            email: Value(result.teacher.email),
            teacherName: Value(result.teacher.teacherName),
            role: Value(result.teacher.role),
            schoolServerId: Value(result.teacher.schoolServerId),
            schoolLocalId: Value(schoolLocalIdToUse),
            isActive: Value(result.teacher.isActive),
            forcePasswordReset: Value(result.teacher.forcePasswordReset),
            passwordHashVersion: Value(result.passwordHashVersion),
            schoolKeyWrapped: Value(result.wrappedSchoolKey),
            lastCreditRefillDate: Value(result.lastCreditRefillServerTime),
            updatedAt: Value(DateTime.now()),
            updateCounter: Value(existing.updateCounter + 1),
          ),
        );
      }
    }

    // Insert new teacher with valid school localId
    await (_db.into(_db.teachers)).insert(
      TeachersCompanion.insert(
        serverId: Value(result.teacher.serverId),
        email: result.teacher.email,
        teacherName: result.teacher.teacherName,
        role: Value(result.teacher.role),
        schoolLocalId: schoolLocalIdToUse,
        schoolServerId: Value(result.teacher.schoolServerId),
        isActive: Value(result.teacher.isActive),
        forcePasswordReset: Value(result.teacher.forcePasswordReset),
        passwordHashVersion: Value(result.passwordHashVersion),
        schoolKeyWrapped: Value(result.wrappedSchoolKey),
        lastCreditRefillDate: Value(result.lastCreditRefillServerTime),
      ),
    );

    // Update security config with server credit state
    await _db.securityConfigDao.updateConfig(
      offlineCredits: result.offlineCredits,
      lastCreditRefillServerTime: result.lastCreditRefillServerTime,
      lastKnownPasswordHashVersion: result.passwordHashVersion,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final authProvider =
    NotifierProvider<AuthNotifier, AuthStateData>(AuthNotifier.new);
