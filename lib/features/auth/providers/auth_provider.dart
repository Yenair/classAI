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
  bool _isLoggingIn = false;
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

  /// Error codes returned by the server that indicate the current session
  /// has been invalidated (token version mismatch, expired JWT, teacher deleted).
  static const _sessionMismatchCodes = <String>{
    'token_version_mismatch',
    'invalid_jwt',
    'teacher_not_found',
  };

  /// Checks whether [error] indicates a server-side session invalidation
  /// (e.g. token_version_mismatch) that should force a logout.
  ///
  /// Prefers the structured `code` field from `FunctionException.details`
  /// over brittle string matching on error messages.
  bool _isSessionMismatchError(Object error) {
    // ── Helper: extract the server "code" from a FunctionException ────────
    String? _extractCode(supabase_pkg.FunctionException ex) {
      final details = ex.details;
      if (details is Map<String, dynamic>) {
        final code = details['code'];
        if (code is String && code.isNotEmpty) return code;
      }
      return null;
    }

    // ── Helper: fallback text-based check for known session mismatch
    //    keywords. This catches edge cases where the error is not wrapped
    //    in a FunctionException (e.g. raw DioException on the client side).
    bool _matchesText(String text) {
      final normalized = text.toLowerCase();
      return normalized.contains('token_version_mismatch') ||
          normalized.contains('token version mismatch') ||
          normalized.contains('session expired');
    }

    // ── Check AuthException (wraps server errors from login/signup) ───────
    if (error is AuthException) {
      // Only proceed if the code suggests a session/credentials issue.
      if (error.code != AuthErrorCode.invalidCredentials) return false;

      final original = error.originalError;
      if (original is supabase_pkg.FunctionException) {
        final serverCode = _extractCode(original);
        if (serverCode != null) {
          return _sessionMismatchCodes.contains(serverCode);
        }
      }

      // Fallback: check the message text.
      return _matchesText(error.message);
    }

    // ── Raw FunctionException (sync calls etc.) ───────────────────────────
    if (error is supabase_pkg.FunctionException) {
      final serverCode = _extractCode(error);
      if (serverCode != null) {
        return _sessionMismatchCodes.contains(serverCode);
      }
      final details = error.details;
      if (details is Map<String, dynamic>) {
        return _matchesText(details.toString());
      }
      if (details is String) {
        return _matchesText(details);
      }
      return false;
    }

    // ── Fallback: check error.toString() for keywords ─────────────────────
    return _matchesText(error.toString());
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
  /// 1. First checks device connectivity.
  /// 2. If **offline**, reads the local credential cache directly:
  ///    - cached credentials found → [AuthState.authenticated]
  ///    - no cached credentials → [AuthState.onlineLoginRequired] with a message
  /// 3. If **online**, tries JWT validation first, then falls back to the local
  ///    credential cache, and finally shows the login screen.
  Future<void> checkLocalAuth() async {
    state = state.copyWith(
      state: AuthState.checkingLocalAuth,
      clearError: true,
    );

    // --- Offline-first: skip network calls when there is no connectivity ---
    if (!await PlatformHelper.isOnline()) {
      String? cachedPassword;
      try {
        cachedPassword = await _securityService.getPasswordHash();
      } catch (e) {
        if (await _logoutIfSessionMismatch(e)) {
          return;
        }
        state = state.copyWith(
          state: AuthState.onlineLoginRequired,
          clearTeacher: true,
          clearSchool: true,
          errorMessage:
              'Saved offline account data could not be read. Please connect to the internet and sign in again.',
        );
        return;
      }
      if (cachedPassword == null || cachedPassword.isEmpty) {
        state = state.copyWith(
          state: AuthState.authenticated,
          clearTeacher: true,
          clearSchool: true,
          clearError: true,
        );
        return;
      }

      final cachedAuth = await _loadLocalCredentialCache(
        cachedPassword: cachedPassword,
      );
      if (cachedAuth != null) {
        await _persistLastLoggedInTeacher(cachedAuth.teacher);
        state = state.copyWith(
          state: AuthState.authenticated,
          currentTeacher: cachedAuth.teacher,
          currentSchool: cachedAuth.school,
          clearError: true,
        );
        await _applyThemeFromTeacher(
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

      // Offline credentials exist, but the cached teacher identity no longer
      // resolves to a local row. Fail clearly instead of guessing.
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        clearTeacher: true,
        clearSchool: true,
        errorMessage:
            'Saved offline account data is missing for the last signed-in teacher. Please connect to the internet and sign in again.',
      );
      return;
    }

    // --- Online flow ---
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
          await _applyThemeFromTeacher(result);
          await _persistLastLoggedInTeacher(result.teacher);
          state = state.copyWith(
            state: AuthState.authenticated,
            currentTeacher: result.teacher,
            currentSchool: result.school,
            clearError: true,
          );
          _startSessionTimer();
          // Check subscription expiry using server time (fire-and-forget)
          unawaited(_checkSubscriptionExpiry());
          // Check min app version (fire-and-forget, shows update dialog if outdated)
          unawaited(_checkMinAppVersion());

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
          debugPrint(
            '[AUTH] Auto-login session validation failed; clearing JWT from '
            'secure storage and memory. error=$e',
          );
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

    final cachedPassword = await _readCachedPasswordHash();
    final cachedAuth = await _loadLocalCredentialCache(
      cachedPassword: cachedPassword,
    );
    if (cachedAuth != null) {
      await _persistLastLoggedInTeacher(cachedAuth.teacher);
      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: cachedAuth.teacher,
        currentSchool: cachedAuth.school,
        clearError: true,
      );
      await _applyThemeFromTeacher(
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

    if (cachedPassword != null && cachedPassword.isNotEmpty) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        clearTeacher: true,
        clearSchool: true,
        errorMessage:
            'Saved offline account data is missing for the last signed-in teacher. Please connect to the internet and sign in again.',
      );
      return;
    }

    // No valid stored session or local cache — show guest dashboard.
    state = state.copyWith(
      state: AuthState.authenticated,
      clearTeacher: true,
      clearSchool: true,
      clearError: true,
    );
  }

  /// Attempt offline login using stored password hash.
  /// Returns true if login succeeded.
  Future<bool> attemptOfflineLogin(String password) async {
    final cachedPassword = await _readCachedPasswordHash();
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

    final cachedAuth = await _loadLocalCredentialCache(
      cachedPassword: cachedPassword,
    );
    if (cachedAuth == null) {
      state = state.copyWith(
        state: AuthState.onlineLoginRequired,
        errorMessage:
            'Saved offline account data is missing for the last signed-in teacher. Connect to the internet and sign in again.',
        offlineLoginAttempts: 0,
      );
      return false;
    }

    await _persistLastLoggedInTeacher(cachedAuth.teacher);
    state = state.copyWith(
      state: AuthState.authenticated,
      currentTeacher: cachedAuth.teacher,
      currentSchool: cachedAuth.school,
      offlineLoginAttempts: 0,
      clearError: true,
    );
    await _applyThemeFromTeacher(
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
    // Check min app version (fire-and-forget, shows update dialog if outdated)
    unawaited(_checkMinAppVersion());
    return true;
  }

  /// Perform server-side login with email, password, and device ID.
  Future<void> loginOnline({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    // ── Concurrent-login guard ──────────────────────────────────────────
    // Prevent duplicate loginOnline() calls that can occur when the widget
    // tree swaps (MaterialApp ↔ MaterialApp.router) during the email
    // verification flow, creating a second LoginScreen that triggers a
    // redundant login. Each login bumps token_version server-side, which
    // invalidates the JWT used by the ongoing verification session and
    // causes the 30-second session timer to detect a false mismatch.
    if (_isLoggingIn ||
        state.state == AuthState.emailVerificationRequired ||
        state.state == AuthState.checkingLocalAuth) {
      debugPrint(
        '[AuthNotifier.loginOnline] ⚠️ concurrent login blocked '
        '(_isLoggingIn=$_isLoggingIn, state=${state.state})',
      );
      return;
    }
    _isLoggingIn = true;
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
      await _applyThemeFromTeacher(result);

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
      await _persistLastLoggedInTeacher(result.teacher);
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
    } finally {
      _isLoggingIn = false;
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
      await _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      await _persistLastLoggedInTeacher(result.teacher);
      _startSessionTimer();
      // Check min app version (fire-and-forget, shows update dialog if outdated)
      unawaited(_checkMinAppVersion());
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
  /// Transitions to the login screen after cleanup.
  Future<void> manualLogout() async {
    debugPrint('[AUTH] manualLogout() called; clearing JWT and secure storage.');
    await _performLogout(
        isForced: false, targetState: AuthState.onlineLoginRequired);
  }

  /// Perform a forced logout (triggers emergency save).
  Future<void> forceLogout() async {
    debugPrint('[AUTH] forceLogout() called; clearing JWT and secure storage.');
    await _performLogout(isForced: true);
  }

  /// Scope-delete the outgoing teacher's local data from Drift tables.
  ///
  /// *Category A tables (lessons, exams, vault_items, scheme_of_work):*
  ///   Hard-delete only confirmed-synced rows (WHERE serverId IS NOT NULL),
  ///   leaving unsynced (pending) rows untouched — **Option (b)**.
  ///
  /// *Re-downloadable tables (teacher_devices, teacher_subjects, audit_logs,
  ///  recovery_codes, pending_recovery_requests):*
  ///   Hard-delete unconditionally; they will be re-fetched on next login.
  ///
  /// *Tables explicitly skipped:*
  ///   - `progress_logs` — has serverId now, but remains excluded from
  ///     teacher-local cleanup because it is low-value sync history
  ///   - `teachers` — must remain for re-auth; the current row is kept
  ///   - `sync_queue` — no teacher-scoping column; pending ops remain safe
  ///   - `payment_events` — billing records must be preserved
  Future<void> _clearTeacherLocalData() async {
    final teacher = state.currentTeacher;
    if (teacher == null) {
      return; // nothing to clean
    }

    final serverId = teacher.serverId;
    final localId = teacher.localId;

    // serverId is nullable; if missing there is nothing to scope-clean
    if (serverId == null) {
      return;
    }

    // ── Category A: confirmed-synced only ────────────────────────────
    try {
      await _db.lessonsDao.deleteSyncedRowsByTeacher(serverId);
    } catch (_) {}

    try {
      await _db.examsDao.deleteSyncedRowsByTeacher(serverId);
    } catch (_) {}

    try {
      await _db.vaultItemsDao.deleteSyncedRowsByAuthor(serverId);
    } catch (_) {}

    try {
      await _db.schemeOfWorkDao.deleteSyncedRowsByTeacher(localId);
    } catch (_) {}

    // ── Re-downloadable tables (always delete) ───────────────────────
    try {
      await _db.teacherDevicesDao.deleteAllByTeacher(localId);
    } catch (_) {}

    try {
      await _db.teacherSubjectsDao.deleteAllForTeacher(localId);
    } catch (_) {}

    try {
      await _db.auditLogsDao.deleteByTeacher(serverId);
    } catch (_) {}

    try {
      await _db.pendingRecoveryRequestsDao.deleteByTeacher(localId);
    } catch (_) {}

    // RecoveryCodes has no dedicated DAO; use raw SQL.
    try {
      await _db.customUpdate(
        'DELETE FROM recovery_codes WHERE teacher_local_id = ?',
        variables: [Variable<int>(localId)],
      );
    } catch (_) {}
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

    // Clear auth credentials (JWT, session, password hash, last-login marker)
    // but PRESERVE the SQLCipher database encryption passphrase. The encrypted
    // classai.db file is intentionally kept (unsynced local rows are preserved
    // by _clearTeacherLocalData below), so the passphrase must remain stable to
    // avoid a key-mismatch on the next launch. Clearing it here would cause the
    // next launch to generate a new passphrase and fail to decrypt the old file.
    await _securityService.clearAuthCredentials();

    // Scope-delete the outgoing teacher's local data *after* clearing
    // secure storage but *before* resetting state (so currentTeacher is
    // still available).
    await _clearTeacherLocalData();

    _stopSessionTimer();
    state = AuthStateData(state: targetState);
  }

  /// Starts a periodic timer that calls [validateSession] every 30 seconds
  /// while the user is authenticated. If the server returns 401 with a
  /// token_version_mismatch, the user is forcibly logged out.
  void _startSessionTimer() {
    _stopSessionTimer(); // cancel any existing timer first
    _sessionTimer = Timer.periodic(_sessionCheckInterval, (_) async {
      if (!await PlatformHelper.isOnline()) {
        return; // skip validation when offline
      }
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
      await _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      await _persistLastLoggedInTeacher(result.teacher);
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
      await _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
      );
      await _persistLastLoggedInTeacher(result.teacher);
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
      await _applyThemeFromTeacher(result);

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
      await _persistLastLoggedInTeacher(result.teacher);
      _startSessionTimer();
      // Check min app version (fire-and-forget, shows update dialog if outdated)
      unawaited(_checkMinAppVersion());
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
        // Persist JWT to secure storage — _verifyEmailCodeExisting reuses the
        // JWT from login() but never stores it, so sync/pull can't find it.
        final jwt = _authService.currentJwt;
        if (jwt != null && jwt.isNotEmpty) {
          await _securityService.storeJwt(jwt);
        }

        state = state.copyWith(
          state: AuthState.authenticated,
          clearError: true,
          clearPendingDeviceId: true,
        );
        final currentTeacher = state.currentTeacher;
        if (currentTeacher != null) {
          await _persistLastLoggedInTeacher(currentTeacher);
        }
        _startSessionTimer();

        // Navigate GoRouter to the correct route — otherwise the tree swap
        // leaves GoRouter stuck at /login (its initial location) with no
        // navigation trigger.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            final isAdmin = state.currentTeacher?.role == 'admin';
            GoRouter.of(ctx).go(isAdmin ? '/admin' : '/');
          }
        });
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
      await _applyThemeFromTeacher(result);

      state = state.copyWith(
        state: AuthState.authenticated,
        currentTeacher: result.teacher,
        currentSchool: result.school,
        clearPendingSignup: true,
        isSignupFlow: false,
        clearError: true,
      );
      await _persistLastLoggedInTeacher(result.teacher);
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
      final currentTeacher = state.currentTeacher;
      if (currentTeacher != null) {
        await _persistLastLoggedInTeacher(currentTeacher);
      }
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
      // Use the known serverId from the current state if available, so we
      // re-fetch the *same* school row rather than whatever row happens to
      // be first in the schools table (the bug that schoolsDao.get()
      // exhibits when multiple school records exist locally).
      final knownServerId = state.currentSchool?.serverId;
      final activeSchool = knownServerId != null
          ? await _db.schoolsDao.getByServerId(knownServerId)
          : await _db.schoolsDao.get();
      if (activeSchool != null) {
        state = state.copyWith(currentSchool: activeSchool);
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

  /// Applies the stored theme mode for the signed-in teacher or admin.
  Future<void> _applyThemeFromTeacher(AuthResult result) {
    return ref.read(themeProvider.notifier).applyTeacherThemeMode(
          result.teacher.themeMode,
        );
  }

  Future<void> _persistLastLoggedInTeacher(Teacher teacher) async {
    final serverId = teacher.serverId;
    if (serverId != null && serverId.isNotEmpty) {
      await _securityService.storeLastLoggedInTeacherIdentifier(
        'server:$serverId',
      );
      return;
    }

    if (teacher.localId > 0) {
      await _securityService.storeLastLoggedInTeacherIdentifier(
        'local:${teacher.localId}',
      );
    }
  }

  Future<String?> _readCachedPasswordHash() async {
    try {
      return await _securityService.getPasswordHash();
    } catch (_) {
      return null;
    }
  }

  Future<Teacher?> _resolveTeacherFromLastLoginMarker(String marker) async {
    final normalized = marker.trim();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('server:')) {
      final serverId = normalized.substring('server:'.length);
      if (serverId.isEmpty) {
        return null;
      }
      return _db.teachersDao.findByServerId(serverId);
    }

    if (normalized.startsWith('local:')) {
      final localId = int.tryParse(normalized.substring('local:'.length));
      if (localId == null) {
        return null;
      }
      return _db.teachersDao.getById(localId);
    }

    final directServerMatch = await _db.teachersDao.findByServerId(normalized);
    if (directServerMatch != null) {
      return directServerMatch;
    }

    final directLocalId = int.tryParse(normalized);
    if (directLocalId != null) {
      return _db.teachersDao.getById(directLocalId);
    }

    return null;
  }

  Future<({Teacher teacher, School school})?> _loadLocalCredentialCache({
    required String? cachedPassword,
  }) async {
    try {
      if (cachedPassword == null || cachedPassword.isEmpty) {
        return null;
      }
      final lastLoggedInTeacherIdentifier =
          await _securityService.getLastLoggedInTeacherIdentifier();
      if (lastLoggedInTeacherIdentifier == null ||
          lastLoggedInTeacherIdentifier.isEmpty) {
        return null;
      }

      final teacher = await _resolveTeacherFromLastLoginMarker(
        lastLoggedInTeacherIdentifier,
      );
      if (teacher == null || teacher.isDeleted) {
        return null;
      }

      final school = await _db.schoolsDao.getByLocalId(teacher.schoolLocalId);
      if (school == null || school.isDeleted) {
        return null;
      }

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

    // Auth hydration no longer queues a schools update.
    if ((schoolRow.serverId?.isEmpty ?? true) &&
        (schoolRow.serverId?.isNotEmpty ?? false)) {
      try {
        await _db.syncQueueDao.insertEntry(
          queueTable: '__disabled_schools__',
          recordLocalId: schoolRow.localId,
          operation: 'UPDATE',
          payload: {
            'server_id': schoolRow.serverId,
            'school_name': schoolRow.schoolName,
            'short_code': schoolRow.shortCode,
            'subscription_tier': schoolRow.subscriptionTier,
            'active_curriculum': schoolRow.activeCurriculum,
            'total_seats': schoolRow.totalSeats,
          },
        );
      } catch (_) {
        // Non-critical — school sync failure shouldn't block auth
      }
    }

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

        // Queue teacher update for sync — only admins may push to the
        // teachers table (server-side admin guard).  Non-admin teachers
        // would get "Admin access required for this table" with
        // retryable=false on every attempt, and if the local_id echo
        // is missing (bug) these entries retry indefinitely, jamming the
        // sync queue and blocking real work (lessons, exams, etc.).
        if (result.teacher.serverId != null &&
            result.teacher.role == 'admin') {
          try {
            await _db.syncQueueDao.insertEntry(
              queueTable: 'teachers',
              recordLocalId: existing.localId,
              operation: 'UPDATE',
              payload: {
                'server_id': result.teacher.serverId,
                'email': result.teacher.email,
                'teacher_name': result.teacher.teacherName,
                'role': result.teacher.role,
                'school_server_id': result.teacher.schoolServerId,
                'is_active': result.teacher.isActive,
              },
            );
          } catch (_) {
            // Non-critical
          }
        }
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

    // Get the local ID of the newly inserted teacher
    final insertedTeacherLocalId = await (_db.select(_db.teachers)
          ..where((t) => t.serverId.equals(result.teacher.serverId!))
          ..limit(1))
        .getSingleOrNull()
        .then((t) => t?.localId);

    // Queue teacher insert for sync — only admins may push to the
    // teachers table (server-side admin guard).  Non-admin teachers
    // would be rejected on every attempt, and if the local_id echo
    // is missing (bug) these entries retry indefinitely.
    if (insertedTeacherLocalId != null &&
        result.teacher.serverId != null &&
        result.teacher.role == 'admin') {
      try {
        await _db.syncQueueDao.insertEntry(
          queueTable: 'teachers',
          recordLocalId: insertedTeacherLocalId,
          operation: 'INSERT',
          payload: {
            'server_id': result.teacher.serverId,
            'email': result.teacher.email,
            'teacher_name': result.teacher.teacherName,
            'role': result.teacher.role,
            'school_server_id': result.teacher.schoolServerId,
            'is_active': result.teacher.isActive,
          },
        );
      } catch (_) {
        // Non-critical
      }
    }

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
