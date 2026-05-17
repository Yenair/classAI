import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/main.dart' show databaseProvider;

// ---------------------------------------------------------------------------
// Dependency providers (to be overridden with real implementations later)
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  throw UnimplementedError(
    'authServiceProvider must be overridden in main() before use',
  );
});

final securityServiceProvider = Provider<SecurityService>((ref) {
  return SecurityService();
});

final emergencyFlushServiceProvider = Provider<EmergencyFlushService>((ref) {
  return EmergencyFlushService();
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
      currentSchool:
          clearSchool ? null : (currentSchool ?? this.currentSchool),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      offlineLoginAttempts:
          offlineLoginAttempts ?? this.offlineLoginAttempts,
    );
  }
}

/// Notifier implementing the Auth State Machine defined in phase_03_auth.md.
class AuthNotifier extends Notifier<AuthStateData> {
  static const int maxOfflineAttempts = 3;

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
      final storedHash = await _securityService.getPasswordHash();
      if (storedHash != null && storedHash.isNotEmpty) {
        state = state.copyWith(state: AuthState.offlineLoginAttempt);
      } else {
        state = state.copyWith(state: AuthState.onlineLoginRequired);
      }
    } catch (e) {
      state = state.copyWith(state: AuthState.onlineLoginRequired);
    }
  }

  /// Attempt offline login using stored password hash.
  /// Returns true if login succeeded.
  Future<bool> attemptOfflineLogin(String password) async {
    if (state.state != AuthState.offlineLoginAttempt) {
      return false;
    }

    try {
      final storedHash = await _securityService.getPasswordHash();
      if (storedHash == null) {
        state = state.copyWith(
          state: AuthState.onlineLoginRequired,
          errorMessage: 'No stored credentials. Please login online.',
        );
        return false;
      }

      final passwordMatch = await _verifyPasswordLocally(password, storedHash);

      if (passwordMatch) {
        // Before authenticating, check for password hash version mismatch.
        // If the server has re-wrapped keys (admin recovery, force reset),
        // the version will differ and we must emergency-save then go online.
        final versionMismatch = await _checkPasswordHashVersionMismatch();
        if (versionMismatch) {
          state = state.copyWith(state: AuthState.emergencySaving);
          try {
            await _emergencyFlushService.flushAll();
          } catch (_) {
            // Flush errors are logged inside flushAll; continue with logout
          }
          state = state.copyWith(
            state: AuthState.onlineLoginRequired,
            errorMessage:
                'Your account credentials have been updated by an administrator. '
                'Please login online to sync.',
            offlineLoginAttempts: 0,
          );
          return false;
        }

        state = state.copyWith(state: AuthState.authenticated);
        return true;
      }

      final attempts = state.offlineLoginAttempts + 1;

      if (attempts >= maxOfflineAttempts) {
        state = state.copyWith(
          state: AuthState.onlineLoginRequired,
          errorMessage:
              'Too many failed attempts. Login online to continue.',
          offlineLoginAttempts: attempts,
        );
      } else {
        state = state.copyWith(
          state: AuthState.offlineLoginAttempt,
          errorMessage:
              'Invalid password. ${maxOfflineAttempts - attempts} attempt(s) remaining.',
          offlineLoginAttempts: attempts,
        );
      }

      return false;
    } catch (e) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Offline login error. Please login online.',
      );
      return false;
    }
  }

  /// Checks whether the cached teacher's [passwordHashVersion] differs from
  /// the [lastKnownPasswordHashVersion] stored in the security config.
  ///
  /// Returns `true` if there is a mismatch (meaning keys have been re-wrapped
  /// server-side and a fresh online login is required).
  Future<bool> _checkPasswordHashVersionMismatch() async {
    try {
      final config = await _db.securityConfigDao.get();
      final storedVersion = config.lastKnownPasswordHashVersion;

      // Read the first (oldest / highest-privilege) cached teacher record
      final teachers = await (_db.select(_db.teachers)
            ..where((t) => t.isActive.equals(true))
            ..limit(1))
          .get();

      if (teachers.isEmpty) return false;
      final cachedVersion = teachers.first.passwordHashVersion;

      return cachedVersion != storedVersion;
    } catch (_) {
      // If we cannot read the config or teachers table, assume no mismatch
      // and allow offline login to proceed.
      return false;
    }
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

    try {
      final result = await _authService.login(email, password, deviceId);

      // Store password hash locally for future offline login
      await _securityService.storePasswordHash(password);

      // Update local database with server state
      await _saveAuthResultToLocalDb(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
        offlineLoginAttempts: 0,
      );
    } on AuthException catch (e) {
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
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'Network error. Please check your connection and try again.',
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
    await _performLogout(isForced: false);
  }

  /// Perform a forced logout (triggers emergency save).
  Future<void> forceLogout() async {
    await _performLogout(isForced: true);
  }

  Future<void> _performLogout({required bool isForced}) async {
    if (isForced) {
      state = state.copyWith(state: AuthState.emergencySaving);

      try {
        await _emergencyFlushService.flushAll();
      } catch (_) {
        // Flush errors are logged inside flushAll; continue with logout
      }
    }

    try {
      await _authService.logout();
    } catch (_) {
      // Server logout failure is non-blocking
    }

    await _securityService.clearAll();

    state = const AuthStateData(state: AuthState.uninitialized);
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
      final result =
          await _authService.verifyAdminOtp(email, otp, newPassword);

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

  /// Clear any displayed error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  Future<void> _saveAuthResultToLocalDb(AuthResult result) async {
    // Upsert teacher record
    if (result.teacher.serverId != null) {
      final existingTeachers = await (_db.select(_db.teachers)
            ..where(
                (t) => t.serverId.equals(result.teacher.serverId!)))
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
            isActive: Value(result.teacher.isActive),
            forcePasswordReset: Value(result.teacher.forcePasswordReset),
            passwordHashVersion: Value(result.passwordHashVersion),
            schoolKeyWrapped: Value(result.wrappedSchoolKey),
            lastCreditRefillDate: Value(result.lastCreditRefillServerTime),
            updatedAt: Value(DateTime.now()),
            updateCounter: Value(existing.updateCounter + 1),
          ),
        );
        return;
      }
    }

    // Insert new teacher
    await (_db.into(_db.teachers)).insert(
      TeachersCompanion.insert(
        serverId: Value(result.teacher.serverId),
        email: result.teacher.email,
        teacherName: result.teacher.teacherName,
        role: Value(result.teacher.role),
        schoolLocalId: result.teacher.schoolLocalId,
        schoolServerId: Value(result.teacher.schoolServerId),
        isActive: Value(result.teacher.isActive),
        forcePasswordReset: Value(result.teacher.forcePasswordReset),
        passwordHashVersion: Value(result.passwordHashVersion),
        schoolKeyWrapped: Value(result.wrappedSchoolKey),
        lastCreditRefillDate: Value(result.lastCreditRefillServerTime),
      ),
    );

    // Upsert school record
    if (result.school.serverId != null) {
      final existingSchools = await (_db.select(_db.schools)
            ..where(
                (s) => s.serverId.equals(result.school.serverId!)))
          .get();

      if (existingSchools.isNotEmpty) {
        final existing = existingSchools.first;
        await (_db.update(_db.schools)
              ..where((s) => s.localId.equals(existing.localId)))
            .write(
          SchoolsCompanion(
            schoolName: Value(result.school.schoolName),
            shortCode: Value(result.school.shortCode),
            subscriptionTier: Value(result.school.subscriptionTier),
            activeCurriculum: Value(result.school.activeCurriculum),
            activeCurriculumVersion:
                Value(result.school.activeCurriculumVersion),
            totalSeats: Value(result.school.totalSeats),
            schoolMasterKeyWrapped:
                Value(result.school.schoolMasterKeyWrapped),
            adminRecoveryEmail: Value(result.school.adminRecoveryEmail),
            adminRecoveryEmailVerified:
                Value(result.school.adminRecoveryEmailVerified),
            updatedAt: Value(DateTime.now()),
            updateCounter: Value(existing.updateCounter + 1),
          ),
        );
        return;
      }
    }

    // Insert new school
    await (_db.into(_db.schools)).insert(
      SchoolsCompanion.insert(
        serverId: Value(result.school.serverId),
        schoolName: result.school.schoolName,
        shortCode: result.school.shortCode,
        subscriptionTier: Value(result.school.subscriptionTier),
        activeCurriculum: Value(result.school.activeCurriculum),
        activeCurriculumVersion:
            Value(result.school.activeCurriculumVersion),
        totalSeats: Value(result.school.totalSeats),
        schoolMasterKeyWrapped:
            Value(result.school.schoolMasterKeyWrapped),
        adminRecoveryEmail: Value(result.school.adminRecoveryEmail),
        adminRecoveryEmailVerified:
            Value(result.school.adminRecoveryEmailVerified),
      ),
    );

    // Update security config with server credit state
    await _db.securityConfigDao.updateConfig(
      offlineCredits: result.offlineCredits,
      lastCreditRefillServerTime: result.lastCreditRefillServerTime,
      lastKnownPasswordHashVersion: result.passwordHashVersion,
    );
  }

  /// Verifies a password against the stored hash using SHA-256.
  ///
  /// Used for offline login where the stored password hash (from a previous
  /// online login) is compared against the user-supplied password.
  /// Replace with Argon2id verification once the crypto package is wired.
  Future<bool> _verifyPasswordLocally(
      String password, String storedHash) async {
    // Hash the provided password and compare to the stored hash.
    // This is a placeholder until Argon2id verification is integrated.
    final hash = sha256.convert(utf8.encode(password)).toString();
    return hash == storedHash;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final authProvider =
    NotifierProvider<AuthNotifier, AuthStateData>(AuthNotifier.new);
