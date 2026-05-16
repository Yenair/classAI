
```markdown
`phase_03_auth.md`
# Phase 3: Auth Flow + Online Core (Self-Contained)

**Goal**: Complete login/logout, admin activation, teacher recovery, admin recovery flows. All server-interacting code works against a mock Supabase client. Deep links configured.

## State Machine: Authentication

```
AuthState:
  uninitialized → [appStart] → checkingLocalAuth
  checkingLocalAuth → [hasLocalHashes] → offlineLoginAttempt
  checkingLocalAuth → [noLocalHashes] → onlineLoginRequired
  offlineLoginAttempt → [passwordMatch && versionMatch] → authenticated
  offlineLoginAttempt → [versionMismatch] → emergencySave → onlineLoginRequired
  offlineLoginAttempt → [passwordMismatch] → [incrementAttempt] → offlineLoginAttempt (if <3)
  offlineLoginAttempt → [passwordMismatch && attempts>=3] → onlineLoginRequired
  onlineLoginRequired → [userProvidesCredentials] → serverLogin
  serverLogin → [success] → authenticated
  serverLogin → [deactivated] → accountDeactivated
  serverLogin → [passwordWrong] → [delay(5/30s)] → onlineLoginRequired
  authenticated → [forceLogout] → emergencySave → uninitialized
  authenticated → [manualLogout] → uninitialized
  emergencySave → [flushComplete] → uninitialized
```

## Architecture Decisions (This Phase Only)

- **Activation**: First activation code MUST be `role: 'admin'`. During admin activation: recovery email REQUIRED, verified via OTP.
- **Admin recovery**: OTP to recovery email → admin enters OTP + new password → server re-wraps school key.
- **Teacher recovery**: Admin generates recovery code online. Code expires 24h. 3 attempts/hour/teacher.
- **Forced logout**: Auto-save via centralized `EmergencyFlushService` (NOT Riverpod dispose). Iterates registered form states from a registry, saves each atomically.
- **Salt storage**: Pulled from server on first login, cached in `teachers` table (`salt` column to add). If offline and no cached salt: block login.
- **Deep links**: `classai://reset-password?token=xxx`, `classai://activate?code=xxx`, `classai://admin-recovery?token=xxx`.

## Agent Playbook — Phase 3 File Creation Order

### Step 3.1: Add `salt` column to Teachers table

Modify `lib/core/database/tables/teachers.dart` — add:
```dart
TextColumn get salt => text().nullable()(); // cached Argon2id salt from server (base64)
```

### Step 3.2: Emergency Flush Service

`lib/core/services/emergency_flush_service.dart`:

```dart
/// Centralized emergency save mechanism.
/// Replaces Riverpod onDispose for forced logout auto-save.
/// Every form provider REGISTERS its save callback at creation time.
/// On forced logout, this service calls all registered callbacks atomically.

typedef SaveCallback = Future<void> Function();

class EmergencyFlushService {
  final List<SaveCallback> _callbacks = [];

  void register(SaveCallback callback) {
    _callbacks.add(callback);
  }

  void unregister(SaveCallback callback) {
    _callbacks.remove(callback);
  }

  Future<void> flushAll() async {
    final results = <bool>[];
    for (final callback in List.from(_callbacks)) {
      try {
        await callback();
        results.add(true);
      } catch (e) {
        results.add(false);
        // Log failure but continue flushing others
      }
    }
    // If any failed, log to Sentry
    if (results.any((r) => !r)) {
      // Sentry.captureMessage('Emergency flush incomplete');
    }
    _callbacks.clear();
  }
}
```

### Step 3.3: Auth Service (stub against mock Supabase)

`lib/core/services/auth_service.dart`:

Define the interface:
```dart
abstract class AuthService {
  Future<AuthResult> login(String email, String password, String deviceId);
  Future<AuthResult> activate(String code, String email, String password, String deviceId, {required bool isAdmin, String? recoveryEmail});
  Future<void> logout();
  Future<AdminRecoveryResult> requestAdminOtp(String email);
  Future<AuthResult> verifyAdminOtp(String email, String otp, String newPassword);
  Future<String> generateTeacherRecoveryCode(String teacherId, String adminId);
  Future<AuthResult> recoverTeacherPassword(String email, String recoveryCode, String newPassword);
}

// Models
class AuthResult {
  final Teacher teacher;
  final School school;
  final String? wrappedSchoolKey; // base64
  final int passwordHashVersion;
  final int offlineCredits;
  final DateTime lastCreditRefillServerTime;

  AuthResult({required this.teacher, required this.school, this.wrappedSchoolKey, required this.passwordHashVersion, required this.offlineCredits, required this.lastCreditRefillServerTime});
}

class AdminRecoveryResult {
  final bool otpSent;
  final DateTime otpExpiry;
}
```

Implementation: Mock supabase initially. Real implementation uses `SupabaseClient` after Phase 4.

### Step 3.4: Auth State Machine Provider

`lib/features/auth/providers/auth_provider.dart`:

```dart
enum AuthState {
  uninitialized,
  checkingLocalAuth,
  offlineLoginAttempt,
  onlineLoginRequired,
  authenticated,
  accountDeactivated,
  emergencySaving,
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.uninitialized);
  // ... state machine transitions
}
```

### Step 3.5: Login Screen

`lib/features/auth/screens/login_screen.dart` — Material Design login with:
- Email field
- Password field
- "Forgot Password?" link (separate flow for teacher vs admin)
- "Activate Account" link
- Error states: "Invalid credentials" / "Account deactivated" / "Network error"
- Loading state during server call
```
```