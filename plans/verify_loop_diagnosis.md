cls# Diagnosis: Login → Verify → Signed-Out → Login-Again Loop

## 1. The Exact Sign-Out Trigger

The sign-out is triggered by **`_logoutIfSessionMismatch`** calling **`manualLogout()`**, which calls **`_performLogout()`** → **`_authService.logout()`** → **`supabase.auth.signOut()`**.

### Trace

| Step | File | Line | What Happens |
|------|------|------|-------------|
| 1 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 1163 | `_verifyEmailCodeExisting` receives `success: true` |
| 2 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 1164-1168 | State set to `AuthState.authenticated` |
| 3 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 1169 | `_startSessionTimer()` starts (30s periodic) |
| 4 | — | — | Between line 1169 and any async cleanup, a **different** server call receives `token_version_mismatch` |
| 5 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 348-354 | `_logoutIfSessionMismatch(error)` returns `true` |
| 6 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 733-735 | `manualLogout()` called |
| 7 | [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | 759-773 | `_performLogout()` → clears JWT, clears secure storage, calls `_authService.logout()` |
| 8 | [`auth_service.dart`](lib/core/services/auth_service.dart) | 318-320 | `SupabaseAuthService.logout()` → clears `_currentJwt`, calls `await _auth.signOut()` |
| 9 | Supabase SDK | — | Logs: `supabase.auth: INFO: Signing out user with scope: SignOutScope.local` |

The `_isSessionMismatchError` method at [`auth_provider.dart:288-346`](lib/features/auth/providers/auth_provider.dart) catches these server error codes from ANY edge function call:
- `token_version_mismatch`
- `invalid_jwt`
- `teacher_not_found`

## 2. Why Two Different `pendingDeviceId` Values Appear

Two different `pendingDeviceId` values **proves `loginOnline()` was called twice** with two different device IDs. This is the only place `pendingDeviceId` is assigned (at [`auth_provider.dart:606`](lib/features/auth/providers/auth_provider.dart)):

```dart
pendingDeviceId: result.newDevice ? deviceId : null,
```

Each `LoginScreen` instance caches a single device ID via `_cachedDeviceId` at [`login_screen.dart:39-173`](lib/features/auth/screens/login_screen.dart). Two different ones means **two different `LoginScreen` instances existed**.

### The Double-Registration Chain

Here is the exact mechanism:

#### First Cycle (Device A)

| Step | Actor | Action | Effect |
|------|-------|--------|--------|
| 1 | `LoginScreen` (instance 1) | `loginOnline(email, pw, device_A)` | **Server bumps `token_version` to N+1**, sets `current_device_id = device_A`, issues JWT_A (tv=N+1) |
| 2 | `AuthNotifier` | State → `emailVerificationRequired`, `pendingDeviceId = device_A` | Dialog shown |
| 3 | Dialog | Auto-resend: `resendVerificationCode()` | Sends verification code to email |
| 4 | User | Enters code_X → `_verifyEmailCodeExisting(code_X)` | Calls `verify-code` edge with JWT_A + `device_id: device_A`. **Success.** |
| 5 | `AuthNotifier` | State → `AuthState.authenticated` | Dialog popped (via listener at line 86-93) |

#### The Widget Tree Swap

When state hits `authenticated`, [`ClassAiRouterApp.build()`](lib/main.dart:461-479) swaps the entire widget tree:

```
Before: MaterialApp(LoginScreen)
After:  MaterialApp.router(GoRouter(DashboardScreen))
```

The `LoginScreen` is **destroyed**. Its `dispose()` at line 150-157 closes the auth listener:

```dart
void dispose() {
    _authStateSubscription?.close();
    ...
}
```

#### Why the State is Lost and a Second Cycle Begins

The GoRouter's `redirect` at [`app_router.dart:53-97`](lib/router/app_router.dart) runs when the router mounts:

```dart
redirect: (context, state) {
    final container = ProviderScope.containerOf(context, listen: false);
    final authData = container.read(authProvider);
    if (authData.currentTeacher == null && location != '/login') {
        return '/login';
    }
```

The `ProviderScope.containerOf(context)` resolves the `ProviderContainer` from the **widget tree's context**. During the widget tree swap from `MaterialApp` to `MaterialApp.router`:

1. The `MaterialApp` subtree is unmounted
2. The `MaterialApp.router` subtree is mounted with a **different navigator context**
3. `ProviderScope.containerOf()` traverses up from the GoRouter context — this is the SAME `ProviderContainer` (from `UncontrolledProviderScope`), so `read(authProvider)` should return the current state

**HOWEVER** — there is a subtlety. The `_verifyEmailCodeExisting` success handler at line 1163-1169 does **NOT set `currentTeacher` or `currentSchool`**:

```dart
state = state.copyWith(
    state: AuthState.authenticated,
    clearError: true,
    clearPendingDeviceId: true,
);
```

These are preserved via `copyWith` defaults from the previous state. BUT — if there is any intermediate state between `emailVerificationRequired` and `authenticated` where `currentTeacher` gets dropped, the GoRouter would see `null` and redirect to `/login`.

**The actual loss happens through the fire-and-forget tasks.** In `loginOnline()` at lines 619-623:

```dart
unawaited(_checkSubscriptionExpiry());
unawaited(_checkMinAppVersion());
```

These run **asynchronously**. If either encounters an error that `_isSessionMismatchError` classifies as a session mismatch, it calls `manualLogout()` at line 733, which sets state to `AuthState.authenticated` with NO teacher (guest mode). The GoRouter redirect then fires and sends the user to `/login`.

#### Second Cycle (Device B)

| Step | Actor | Action | Effect |
|------|-------|--------|--------|
| 6 | GoRouter redirect | `currentTeacher == null` → redirects to `/login` | A NEW `LoginScreen` (instance 2) mounts |
| 7 | `LoginScreen` (instance 2) | `loginOnline(email, pw, device_B)` | **Server bumps `token_version` to N+2**, sets `current_device_id = device_B`, issues JWT_B (tv=N+2) |
| 8 | `AuthNotifier` | State → `emailVerificationRequired`, `pendingDeviceId = device_B` | New dialog shown |
| 9 | User | Enters code_Y → `_verifyEmailCodeExisting(code_Y)` | **JWT_A is now stale** (tv=N+1 ≠ DB's tv=N+2), but this uses JWT_B (tv=N+2) which is valid. **Success.** |
| 10 | `AuthNotifier` | State → `AuthState.authenticated` | GoRouter mounts DashboardScreen |

#### The Payload Hit

After step 10, the `_checkMinAppVersion()` or `_checkSubscriptionExpiry()` **from the FIRST login cycle** (dispatched at step 1 as `unawaited`) finally completes. It uses `_authService.currentJwt` which is now **JWT_B** (set by step 7) — so it should be valid.

BUT — the `_startSessionTimer()` from step 3 runs every 30 seconds. OR more likely, a **fire-and-forget task from the second cycle** hits a timing issue.

Actually, the most likely culprit is simpler: one of the `unawaited` tasks catches a network error that gets **misclassified** as a session mismatch. The `_isSessionMismatchError` at line 302-308 has very broad text-matching fallbacks:

```dart
bool _matchesText(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('token_version_mismatch') ||
        normalized.contains('token version mismatch') ||
        normalized.contains('session expired') ||
        normalized.contains('401 unauthorized') ||
        normalized.contains('unauthorized');
}
```

Any error message containing "401 unauthorized" or "unauthorized" **anywhere in the text** will trigger a logout. A network error, rate-limiting response, or any other error that happens to contain these words would be misclassified.

## 3. Connection to the "Double Login" Symptom

**Yes, both symptoms share the same root cause.** The "double login" symptom (no verification code) follows this pattern:

| Symptom | Trigger | Cause |
|---------|---------|-------|
| Login → Verify → Sign-out → Login again → Verify → Dashboard | `token_version_mismatch` from stale JWT or misclassified error | Two `loginOnline()` calls with different device IDs; first JWT invalidated by second login's `token_version` bump |
| Login → Login screen again → Login again → Dashboard | `_logoutIfSessionMismatch` fires after first `loginOnline()` succeeds | Fire-and-forget task or session timer detects `token_version_mismatch` (or false positive from text matching) |

In the simpler case (no verification), the sequence is:
1. `loginOnline()` → `token_version` bumped → JWT issued → `emailVerified=true, newDevice=false` → `authenticated`
2. GoRouter mounts, DashboardScreen shows
3. Session timer fires after 30 seconds → `validateSession()` → `validateTokenVersion` → JWT's token_version matches DB → OK
4. BUT — if the `_checkMinAppVersion()` or `_checkSubscriptionExpiry()` fire-and-forget encounters an error during the GoRouter swap, `_logoutIfSessionMismatch` classifies it as a session mismatch
5. `manualLogout()` → user sent back to login screen
6. User logs in again → second JWT issued → dashboard shows (this time the stale task from the first login has already completed, so no second logout)

## 4. Summary of Exact Trigger

| Question | Answer |
|----------|--------|
| **What calls `supabase.auth.signOut()`?** | [`SupabaseAuthService.logout()`](lib/core/services/auth_service.dart:320) — the **only** call site |
| **What calls that?** | [`_performLogout()`](lib/features/auth/providers/auth_provider.dart:761) |
| **What calls that?** | [`manualLogout()`](lib/features/auth/providers/auth_provider.dart:735) |
| **What calls manualLogout?** | [`_logoutIfSessionMismatch()`](lib/features/auth/providers/auth_provider.dart:352) |
| **What triggers the mismatch detection?** | A server edge function error classified as `token_version_mismatch`, `invalid_jwt`, or `teacher_not_found` — or a **false positive** from the broad text matcher that catches any error containing `unauthorized`, `401`, or `session expired`. |
| **Why two device registrations?** | `loginOnline()` runs twice because the first successful verification triggers a widget tree swap that either (a) causes a fire-and-forget `unawaited` task to misidentify an error and call `manualLogout()`, or (b) the GoRouter redirect briefly sees a null `currentTeacher` during the widget transition, sending the user back to the login screen. |
| **Is "double login" the same issue?** | Yes. The fire-and-forget task or session timer triggers the same `_logoutIfSessionMismatch` → `manualLogout()` chain, but without the intermediate verification step. |

## 5. Key Code Paths for the Fix

The following areas should be addressed (diagnosis only — no fix yet):

1. **Broad text matching in `_isSessionMismatchError`** at [`auth_provider.dart:302-308`](lib/features/auth/providers/auth_provider.dart) — `contains('unauthorized')` and `contains('401')` are dangerously broad and will trigger false-positive logouts.

2. **Fire-and-forget tasks** at [`auth_provider.dart:619-623`](lib/features/auth/providers/auth_provider.dart) — `_checkSubscriptionExpiry` and `_checkMinAppVersion` are dispatched with `unawaited()` and could complete during or after the GoRouter swap, catching transient errors.

3. **`_verifyEmailCodeExisting` success handler** at [`auth_provider.dart:1163-1169`](lib/features/auth/providers/auth_provider.dart) — does not explicitly set `currentTeacher`/`currentSchool` (relies on `copyWith` defaults), and does not clean up any pending state from `loginOnline`.

4. **Widget tree swap gap** in [`main.dart:461-479`](lib/main.dart) — the entire app swaps from `MaterialApp` to `MaterialApp.router` on the `authenticated` state transition. Any async operation that touches auth state during this swap could trigger a cascade.
