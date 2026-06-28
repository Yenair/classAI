import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' show ClientException;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/auth_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/features/settings/providers/theme_provider.dart';
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

  /// Form data stored temporarily during verify-before-create signup flow.
  /// Populated after [AuthNotifier.initiateSignup] succeeds and cleared
  /// after [AuthNotifier._finalizeSignup] completes.
  final Map<String, String>? pendingSignupData;

  /// True when [AuthState.emailVerificationRequired] is for a signup flow
  /// (as opposed to a login flow where the teacher already exists).
  /// Used by [LoginScreen] to skip showing its own email verification dialog.
  final bool isSignupFlow;

  /// The device_id that triggered a "new device" verification flow.
  /// Set during login when [AuthResult.newDevice] is true, used by
  /// [AuthNotifier._verifyEmailCodeExisting] to register the device
  /// after successful verification.
  final String? pendingDeviceId;

  const AuthStateData({
    required this.state,
    this.currentTeacher,
    this.currentSchool,
    this.errorMessage,
    this.offlineLoginAttempts = 0,
    this.pendingSignupData,
    this.isSignupFlow = false,
    this.pendingDeviceId,
  });

  AuthStateData copyWith({
    AuthState? state,
    Teacher? currentTeacher,
    School? currentSchool,
    String? errorMessage,
    int? offlineLoginAttempts,
    Map<String, String>? pendingSignupData,
    bool? isSignupFlow,
    String? pendingDeviceId,
    bool clearError = false,
    bool clearTeacher = false,
    bool clearSchool = false,
    bool clearPendingSignup = false,
    bool clearPendingDeviceId = false,
  }) {
    return AuthStateData(
      state: state ?? this.state,
      currentTeacher:
          clearTeacher ? null : (currentTeacher ?? this.currentTeacher),
      currentSchool: clearSchool ? null : (currentSchool ?? this.currentSchool),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      offlineLoginAttempts: offlineLoginAttempts ?? this.offlineLoginAttempts,
      pendingSignupData: clearPendingSignup
          ? null
          : (pendingSignupData ?? this.pendingSignupData),
      isSignupFlow: isSignupFlow ?? this.isSignupFlow,
      pendingDeviceId: clearPendingDeviceId
          ? null
          : (pendingDeviceId ?? this.pendingDeviceId),
    );
  }
}

/// Notifier implementing the Auth State Machine defined in phase_03_auth.md.
class AuthNotifier extends Notifier<AuthStateData> {
  static const int maxOfflineAttempts = 3;
  static const _sessionCheckInterval = Duration(seconds: 30);
  bool _isResending = false;
  Timer? _sessionTimer;

  @override
  AuthStateData build() {
    ref.onDispose(() {
      _sessionTimer?.cancel();
      _sessionTimer = null;
    });
    return const AuthStateData(state: AuthState.uninitialized);
  }

  AppDatabase get _db => ref.read(databaseProvider);
  AuthService get _authService => ref.read(authServiceProvider);
  SecurityService get _securityService => ref.read(securityServiceProvider);
  EmergencyFlushService get _emergencyFlushService =>
      ref.read(emergencyFlushServiceProvider);

  /// Calls the server-time edge function and returns the server timestamp.
  /// Returns null if the call fails (network error, etc.).
  Future<DateTime?> _fetchServerTime() async {
    try {
      final client = supabase_pkg.Supabase.instance.client;
      final response = await client.functions
          .invoke('server-time')
          .timeout(const Duration(seconds: 10));
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return null;
      final timeStr = data['server_time'] as String?;
      if (timeStr == null) return null;
      return DateTime.tryParse(timeStr);
    } catch (_) {
      // Silently ignore — the next sync cycle or session timer will re-check.
      return null;
    }
  }

  /// Checks if the school's subscription has expired by comparing the server
  /// time against [School.expiryDate]. If expired, downgrades the local school
  /// record to 'free' and updates the notifier state.
  ///
  /// Uses the server-provided timestamp — NEVER [DateTime.now].
  Future<void> _checkSubscriptionExpiry() async {
    final serverTime = await _fetchServerTime();
    if (serverTime == null) return; // offline or error — defer check

    final school = state.currentSchool;
    if (school == null) return;

    final expiry = school.expiryDate;
    if (expiry == null) return; // no expiry set (free tier) — no action needed.

    if (expiry.isBefore(serverTime)) {
      // Subscription expired — downgrade to free
      debugPrint(
        '[AuthNotifier] Subscription expired: expiry=$expiry, serverTime=$serverTime',
      );
      if (school.serverId != null) {
        await _db.schoolsDao.updateSubscriptionFields(
          serverId: school.serverId!,
          subscriptionTier: 'free',
          expiryDate: null,
          activationCode: null,
        );
      }
      // Reload school from local DB and update state
      await refreshSchoolFromDb();
    }
  }

  /// Checks the remote [minAppVersion] against the installed app version and
  /// shows a non‑dismissible update dialog if the app is outdated.
  Future<void> _checkMinAppVersion() async {
    try {
      final configService = ref.read(configServiceProvider);
      await configService.refresh();
      final required = configService.minAppVersion;
      if (required.isEmpty) return;

      final info = await PackageInfo.fromPlatform();
      final installed = info.version;

      if (_isVersionLessThan(installed, required)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx == null || !ctx.mounted) return;
          showDialog<void>(
            context: ctx,
            barrierDismissible: false,
            builder: (dialogCtx) => AlertDialog(
              backgroundColor: Theme.of(dialogCtx).colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: const Text('Update Required'),
              content: Text(
                'Your app version ($installed) is outdated. '
                'Please update to version $required or later to continue.',
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    // Open app store — for now just close the dialog.
                    Navigator.of(dialogCtx).pop();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('[AuthNotifier] _checkMinAppVersion failed: $e');
    }
  }

  /// Compares two semantic version strings (e.g. "1.2.3").
  /// Returns true if [a] is strictly less than [b].
  bool _isVersionLessThan(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < maxLen; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal < bVal) return true;
      if (aVal > bVal) return false;
    }
    return false;
  }

  bool _isSessionMismatchError(Object error) {
    bool matchesText(String text) {
      final normalized = text.toLowerCase();
      return normalized.contains('token_version_mismatch') ||
          normalized.contains('token version mismatch') ||
          normalized.contains('session expired') ||
          normalized.contains('401 unauthorized') ||
          normalized.contains('unauthorized');
    }

    if (error is AuthException) {
      if (error.code != AuthErrorCode.invalidCredentials) {
        return false;
      }
      if (matchesText(error.message)) {
        return true;
      }
      final original = error.originalError;
      if (original is supabase_pkg.FunctionException) {
        // Only check the details content for session-related keywords.
        // Do NOT blindly treat every 401 as session mismatch — the login
        // edge function also returns 401 for invalid credentials, and that
        // must surface as an error message, not a force-logout.
        final details = original.details;
        if (details is Map<String, dynamic>) {
          return matchesText(details.toString());
        }
        if (details is String) {
          return matchesText(details);
        }
      }
      return false;
    }

    if (error is supabase_pkg.FunctionException) {
      // Do NOT blindly treat every 401 as session mismatch — the login
      // edge function also returns 401 for invalid credentials.
      final details = error.details;
      if (details is Map<String, dynamic>) {
        return matchesText(details.toString());
      }
      if (details is String) {
        return matchesText(details);
      }
      return false;
    }

    return matchesText(error.toString());
  }

  Future<bool> _logoutIfSessionMismatch(Object error) async {
    if (!_isSessionMismatchError(error)) {
      return false;
    }
    await manualLogout();
    return true;
  }

  // -----------------------------------------------------------------------
  // State machine transitions
  // -----------------------------------------------------------------------

  /// Called on app start. Tries silent auto-login from stored JWT.
  ///
  /// 1. Reads stored JWT from flutter_secure_storage (via SecurityService).
  /// 2. If found, calls validate-session edge function.
  /// 3. If valid, transitions to [AuthState.authenticated] and navigates.
  /// 4. If invalid/expired/offline, falls back to the local credential cache.
  Future<void> checkLocalAuth() async {
    state = state.copyWith(
      state: AuthState.checkingLocalAuth,
      clearError: true,
    );

    try {
      // Try auto-login from stored JWT
      final storedJwt = await _securityService.getStoredJwt();
      if (storedJwt != null && storedJwt.isNotEmpty) {
        // Set the JWT on the auth service so validateSession can use it
        _authService.setJwt(storedJwt);

        try {
          final result = await _authService.validateSession();

          // Session is valid — save to local DB and transition to authenticated
          await _saveAuthResultToLocalDb(result);
          _applyThemeFromTeacher(result);
          state = state.copyWith(
            state: AuthState.authenticated,
            currentTeacher: result.teacher,
            currentSchool: result.school,
            clearError: true,
          );
          _startSessionTimer();
          // Check subscription expiry using server time (fire-and-forget)
          unawaited(_checkSubscriptionExpiry());

          // Navigate based on role
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = navigatorKey.currentContext;
            if (ctx != null) {
              final isAdmin = result.teacher.role == 'admin';
              GoRouter.of(ctx).go(isAdmin ? '/admin' : '/');
            }
          });
          return; // Successful auto-login
        } catch (e) {
          if (await _logoutIfSessionMismatch(e)) {
            return;
          }
          // Session validation failed (expired, token_version_mismatch, offline)
          // Clear the stored JWT and fall through to the local credential cache.
          await _securityService.clearJwt();
          _authService.clearJwt();
        }
      }
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      // Secure storage read failed — fall through to local cache.
    }

    final cachedAuth = await _loadLocalCredentialCache();
    if (cachedAuth != null) {
      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: cachedAuth.teacher,
        currentSchool: cachedAuth.school,
        clearError: true,
      );
      _applyThemeFromTeacher(
        AuthResult(
          teacher: cachedAuth.teacher,
          school: cachedAuth.school,
          wrappedSchoolKey: cachedAuth.teacher.schoolKeyWrapped,
          passwordHashVersion: cachedAuth.teacher.passwordHashVersion,
          offlineCredits: (await _db.securityConfigDao.get()).offlineCredits,
          lastCreditRefillServerTime:
              cachedAuth.teacher.lastCreditRefillDate ?? DateTime.now(),
          emailVerified: true,
          newDevice: false,
        ),
      );
      _startSessionTimer();
      return;
    }

    // No valid stored session or local cache — show login screen.
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );
  }

  /// Attempt offline login using stored password hash.
  /// Returns true if login succeeded.
  Future<bool> attemptOfflineLogin(String password) async {
    final cachedPassword = await _securityService.getPasswordHash();
    if (cachedPassword == null || cachedPassword.isEmpty) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'No offline credentials are cached yet. Connect to the internet to sign in.',
        offlineLoginAttempts: 0,
      );
      return false;
    }

    if (cachedPassword != password) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Invalid offline credentials. Please try again.',
        offlineLoginAttempts: state.offlineLoginAttempts + 1,
      );
      return false;
    }

    final cachedAuth = await _loadLocalCredentialCache();
    if (cachedAuth == null) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'Offline data is not ready yet. Connect to the internet once to finish setup.',
        offlineLoginAttempts: 0,
      );
      return false;
    }

    state = state.copyWith(
      state: AuthState.authenticated,
      currentTeacher: cachedAuth.teacher,
      currentSchool: cachedAuth.school,
      offlineLoginAttempts: 0,
      clearError: true,
    );
    _applyThemeFromTeacher(
      AuthResult(
        teacher: cachedAuth.teacher,
        school: cachedAuth.school,
        wrappedSchoolKey: cachedAuth.teacher.schoolKeyWrapped,
        passwordHashVersion: cachedAuth.teacher.passwordHashVersion,
        offlineCredits: (await _db.securityConfigDao.get()).offlineCredits,
        lastCreditRefillServerTime:
            cachedAuth.teacher.lastCreditRefillDate ?? DateTime.now(),
        emailVerified: true,
        newDevice: false,
      ),
    );
    _startSessionTimer();
    return true;
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

      // Store JWT in secure storage for auto-login on next startup
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      // Store password hash locally for future offline login
      await _securityService.storePasswordHash(password);

      // Update local database with server state
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

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

      if (!result.emailVerified || result.newDevice) {
        // Email not yet verified, OR this is a new device requiring
        // re-verification — show the verification popup.
        // Store the device_id so _verifyEmailCodeExisting can register
        // the device after successful verification.
        state = state.copyWith(
          state: AuthState.emailVerificationRequired,
          currentTeacher: result.teacher,
          currentSchool: result.school,
          offlineLoginAttempts: 0,
          pendingDeviceId: result.newDevice ? deviceId : null,
        );
        return;
      }

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
        offlineLoginAttempts: 0,
        clearPendingDeviceId: true,
      );
      _startSessionTimer();
      // Check subscription expiry using server time (fire-and-forget)
      unawaited(_checkSubscriptionExpiry());

      // Check min app version (fire-and-forget, shows an update dialog if outdated)
      unawaited(_checkMinAppVersion());

      // Navigate based on role — admin goes to /admin, teachers go to /
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          final isAdmin = result.teacher.role == 'admin';
          GoRouter.of(ctx).go(isAdmin ? '/admin' : '/');
        }
      });
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
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
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      await Sentry.captureException(e);
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'An unexpected error occurred. Please try again. (${e.runtimeType}: $e)',
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

      // Persist JWT for auto-login
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      await _securityService.storePasswordHash(password);
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      _startSessionTimer();
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
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

    _stopSessionTimer();
    state = AuthStateData(state: targetState);
  }

  /// Starts a periodic timer that calls [validateSession] every 30 seconds
  /// while the user is authenticated. If the server returns 401 with a
  /// token_version_mismatch, the user is forcibly logged out.
  void _startSessionTimer() {
    _stopSessionTimer(); // cancel any existing timer first
    _sessionTimer = Timer.periodic(_sessionCheckInterval, (_) async {
      try {
        await _authService.validateSession();
      } catch (e) {
        if (await _logoutIfSessionMismatch(e)) {
          return;
        }
      }
    });
  }

  /// Cancels the periodic session check timer.
  void _stopSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
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

      // Persist JWT for auto-login
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      await _securityService.storePasswordHash(newPassword);
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      _startSessionTimer();
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
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

      // Persist JWT for auto-login
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      await _securityService.storePasswordHash(newPassword);
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      _startSessionTimer();
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
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

    try {
      final result = await _authService.signup(
        schoolName,
        adminEmail,
        adminPassword,
        recoveryEmail,
      );

      // Persist JWT for auto-login
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      await _securityService.storePasswordHash(adminPassword);
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

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
      _startSessionTimer();
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      // Log to Sentry and surface the actual error for debugging
      await Sentry.captureException(e);
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'An unexpected error occurred. Please try again. (${e.runtimeType}: $e)',
      );
    }
  }

  /// Start the verify-before-create signup flow by sending a verification code
  /// to the admin email via the send-verification-code edge function with
  /// mode="signup" (no JWT required).
  ///
  /// Stores the form data in [AuthStateData.pendingSignupData] and transitions
  /// to [AuthState.emailVerificationRequired] with [AuthStateData.isSignupFlow]
  /// set to true. The actual school/teacher creation happens in [_finalizeSignup]
  /// after the user verifies their email.
  Future<void> initiateSignup({
    required String schoolName,
    required String adminEmail,
    required String adminPassword,
    String? recoveryEmail,
  }) async {
    state = state.copyWith(
      state: AuthState.onlineLoginRequired,
      clearError: true,
    );

    try {
      final client = supabase_pkg.Supabase.instance.client;
      await client.functions
          .invoke(
            'send-verification-code',
            body: {'email': adminEmail, 'mode': 'signup'},
          )
          .timeout(const Duration(seconds: 15));

      // Store pending data and transition to email verification
      state = state.copyWith(
        state: AuthState.emailVerificationRequired,
        isSignupFlow: true,
        clearError: true,
        pendingSignupData: {
          'schoolName': schoolName,
          'adminEmail': adminEmail,
          'adminPassword': adminPassword,
          if (recoveryEmail != null) 'recoveryEmail': recoveryEmail,
        },
      );
    } on TimeoutException {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'The verification email is taking too long. Please try again.',
      );
    } on supabase_pkg.FunctionException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      final details = e.details;
      String errorMessage;
      if (details is Map<String, dynamic>) {
        errorMessage = details['error'] as String? ??
            'Failed to send verification code.';
      } else {
        errorMessage = 'Failed to send verification code.';
      }
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: errorMessage,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      debugPrint('[AuthNotifier] initiateSignup error: $e');
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage: 'Failed to send verification code. Please try again.',
      );
    }
  }

  /// Verify the 6-digit email verification code by calling the verify-code
  /// edge function.
  ///
  /// If [AuthStateData.pendingSignupData] is present (signup flow), calls
  /// verify-code with mode="signup" (no JWT required) and on success
  /// calls [_finalizeSignup] to create the school and teacher.
  ///
  /// Otherwise uses the existing JWT-based flow (login email verification).
  ///
  /// On success, transitions to [AuthState.authenticated].
  Future<void> verifyEmailCode(String code) async {
    // Detect mode from state
    if (state.pendingSignupData != null) {
      await _verifyEmailCodeForSignup(code);
      return;
    }
    await _verifyEmailCodeExisting(code);
  }

  /// Signup-mode email verification — calls verify-code with mode="signup"
  /// (no JWT), then on success creates the school + teacher via [_finalizeSignup].
  Future<void> _verifyEmailCodeForSignup(String code) async {
    final email = state.pendingSignupData!['adminEmail']!;

    try {
      final client = supabase_pkg.Supabase.instance.client;
      final response = await client.functions.invoke(
        'verify-code',
        body: {'code': code, 'email': email, 'mode': 'signup'},
      );

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        // Code verified — now create the school and teacher
        await _finalizeSignup();
      } else {
        final error = data['error'] as String? ?? 'Verification failed.';
        state = state.copyWith(errorMessage: error, clearError: false);
      }
    } on supabase_pkg.FunctionException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
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
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      debugPrint('[AuthNotifier] _verifyEmailCodeForSignup error: $e');
      state = state.copyWith(
        errorMessage: 'Failed to verify code. Please try again.',
        clearError: false,
      );
    }
  }

  /// Original JWT-based email verification flow (used after login).
  Future<void> _verifyEmailCodeExisting(String code) async {
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
      // Include device_id and platform for new-device verification flow.
      // If pendingDeviceId is set, this is a "new device" verification
      // and the edge function will register the device after verifying.
      final body = <String, dynamic>{
        'code': code,
        if (state.pendingDeviceId != null) 'device_id': state.pendingDeviceId,
      };
      debugPrint('[AuthNotifier] _verifyEmailCodeExisting — JWT present: ${jwt.isNotEmpty}, pendingDeviceId: ${state.pendingDeviceId ?? "null"}');
      debugPrint('[AuthNotifier] _verifyEmailCodeExisting — body: $body');
      final response = await client.functions.invoke(
        'verify-code',
        headers: {'x-classai-jwt': jwt},
        body: body,
      );
      debugPrint('[AuthNotifier] _verifyEmailCodeExisting — response: ${response.data}');

      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        state = state.copyWith(
          state: AuthState.authenticated,
          clearError: true,
          clearPendingDeviceId: true,
        );
        _startSessionTimer();
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

  /// Called after email verification succeeds in signup mode.
  /// Calls the signup edge function with the stored pending data,
  /// stores the password hash and auth result locally, and transitions
  /// to [AuthState.authenticated].
  Future<void> _finalizeSignup() async {
    final data = state.pendingSignupData;
    if (data == null) {
      state = state.copyWith(
        errorMessage: 'Signup data lost. Please start over.',
        clearError: false,
      );
      return;
    }

    final schoolName = data['schoolName']!;
    final adminEmail = data['adminEmail']!;
    final adminPassword = data['adminPassword']!;
    final recoveryEmail = data['recoveryEmail'];

    try {
      final result = await _authService.signup(
        schoolName,
        adminEmail,
        adminPassword,
        recoveryEmail,
      );

      // Persist JWT for auto-login
      final jwt = _authService.currentJwt;
      if (jwt != null && jwt.isNotEmpty) {
        await _securityService.storeJwt(jwt);
      }

      await _securityService.storePasswordHash(adminPassword);
      await _saveAuthResultToLocalDb(result);
      _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
        clearPendingSignup: true,
        isSignupFlow: false,
        clearError: true,
      );
      _startSessionTimer();

      // Navigate to admin dashboard
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          final isAdmin = result.teacher.role == 'admin';
          GoRouter.of(ctx).go(isAdmin ? '/admin' : '/');
        }
      });
    } on AuthException catch (e) {
      // Stay in emailVerificationRequired so the user can retry
      state = state.copyWith(
        state: AuthState.emailVerificationRequired,
        errorMessage: e.message,
      );
    } catch (e) {
      await Sentry.captureException(e);
      state = state.copyWith(
        state: AuthState.emailVerificationRequired,
        errorMessage: 'Failed to create account. Please try again.',
      );
    }
  }

  /// Resend the email verification code by calling the send-verification-code
  /// edge function.
  ///
  /// If [AuthStateData.pendingSignupData] is present (signup flow), sends
  /// the code with mode="signup" (no JWT required).
  ///
  /// Remains in [AuthState.emailVerificationRequired].
  Future<void> resendVerificationCode() async {
    // Signup mode: use pending email without JWT
    if (state.pendingSignupData != null) {
      await _resendVerificationCodeForSignup();
      return;
    }
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
            headers: {'x-classai-jwt': jwt},
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

  /// Signup-mode resend — calls send-verification-code with mode="signup"
  /// (no JWT), using the email from [AuthStateData.pendingSignupData].
  Future<void> _resendVerificationCodeForSignup() async {
    final email = state.pendingSignupData?['adminEmail'];
    if (email == null || email.isEmpty) {
      state = state.copyWith(
        errorMessage: 'No email associated with this signup.',
        clearError: false,
      );
      return;
    }

    _isResending = true;
    try {
      final client = supabase_pkg.Supabase.instance.client;
      await client.functions
          .invoke(
            'send-verification-code',
            body: {'email': email, 'mode': 'signup'},
          )
          .timeout(const Duration(seconds: 15));

      state = state.copyWith(clearError: true, errorMessage: null);
    } on TimeoutException {
      state = state.copyWith(
        errorMessage:
            'The verification email is taking too long to send. Please try again in a moment.',
        clearError: false,
      );
    } on supabase_pkg.FunctionException catch (e) {
      final details = e.details;
      String errorMessage;
      if (details is Map<String, dynamic>) {
        errorMessage = details['error'] as String? ??
            details['message'] as String? ??
            'Failed to resend code.';
      } else if (details is String) {
        errorMessage = details;
      } else {
        errorMessage = 'Failed to resend code.';
      }
      state = state.copyWith(errorMessage: errorMessage, clearError: false);
    } catch (e) {
      debugPrint('[AuthNotifier] _resendVerificationCodeForSignup error: $e');
      state = state.copyWith(
        errorMessage: 'Failed to resend code. Please try again.',
        clearError: false,
      );
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
      _startSessionTimer();
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state:
            state.state, // keep current state (e.g. forcePasswordResetRequired)
        errorMessage: e.message,
      );
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return;
      }
      state = state.copyWith(
        state: state.state,
        errorMessage: 'Failed to change password. Please try again.',
      );
    }
  }

  /// Add a teacher to the school (admin-only action).
  ///
  /// Delegates to [AuthService.addTeacher] and returns the temporary password.
  /// Does not change the auth state.
  Future<String?> addTeacher({
    required String email,
    required String teacherName,
    required String role,
  }) async {
    try {
      return await _authService.addTeacher(email, teacherName, role);
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return null;
      }
      // Let AuthException propagate so the UI can catch and display it
      rethrow;
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return null;
      }
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to add teacher. Please try again.',
        originalError: e,
      );
    }
  }

  /// Resend the temporary password to a teacher who hasn't logged in yet.
  ///
  /// Delegates to [AuthService.resendTeacherPassword].
  /// Returns the new temporary password.
  Future<String?> resendTeacherPassword({
    required String email,
    required String teacherName,
    required String role,
  }) async {
    try {
      return await _authService.resendTeacherPassword(email, teacherName, role);
    } on AuthException catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return null;
      }
      rethrow;
    } catch (e) {
      if (await _logoutIfSessionMismatch(e)) {
        return null;
      }
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Failed to resend password. Please try again.',
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

  /// Re-reads the school record from the local database and updates the
  /// notifier state.  Called after a payment completes so that widgets
  /// watching [authProvider] (free-plan banner, credit dialog tier, etc.)
  /// react immediately without requiring an app restart.
  Future<void> refreshSchoolFromDb() async {
    try {
      final school = await _db.schoolsDao.get();
      if (school != null) {
        state = state.copyWith(currentSchool: school);
      }
    } catch (_) {
      // Silently ignore – the next sync cycle will pick up any changes.
    }
    // Check subscription expiry using server time (fire-and-forget)
    unawaited(_checkSubscriptionExpiry());
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  void _applyThemeFromTeacher(AuthResult result) {
    ref.read(themeProvider.notifier).applyTeacherThemeMode(
          result.teacher.themeMode,
        );
  }

  Future<({Teacher teacher, School school})?> _loadLocalCredentialCache() async {
    try {
      final cachedPassword = await _securityService.getPasswordHash();
      if (cachedPassword == null || cachedPassword.isEmpty) {
        return null;
      }

      final school = await _db.schoolsDao.get();
      if (school == null) {
        return null;
      }

      final teachers = await _db.teachersDao.getBySchool(school.localId);
      if (teachers.isEmpty) {
        return null;
      }

      final teacher = teachers.firstWhere(
        (t) => t.isActive,
        orElse: () => teachers.first,
      );

      return (teacher: teacher, school: school);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveAuthResultToLocalDb(AuthResult result) async {
    await _db.deduplicateAuthLoginRows();

    // Guaranteed to return a School row with a valid non-zero localId.
    // `upsertByServerId` SELECTs by serverId, UPDATEs the existing row, or
    // INSERTs a new one — in all cases the returned School has the correct
    // persistent localId that can safely be used as the teacher's foreign key.
    final schoolServerId = result.school.serverId;
    if (schoolServerId == null) {
      throw AuthException(
        code: AuthErrorCode.networkError,
        message: 'Invalid server response: missing school ID.',
      );
    }
    final schoolRow = await _db.schoolsDao.upsertByServerId(
      serverId: schoolServerId,
      schoolName: result.school.schoolName,
      shortCode: result.school.shortCode,
      subscriptionTier: result.school.subscriptionTier,
      activeCurriculum: result.school.activeCurriculum,
      activeCurriculumVersion: result.school.activeCurriculumVersion,
      totalSeats: result.school.totalSeats,
      schoolMasterKeyWrapped: result.school.schoolMasterKeyWrapped,
      adminRecoveryEmail: result.school.adminRecoveryEmail,
      adminRecoveryEmailVerified: result.school.adminRecoveryEmailVerified,
      expiryDate: result.school.expiryDate,
      activationCode: result.school.activationCode,
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
        return;
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
