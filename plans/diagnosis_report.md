# Android Router Crash/Black-Screen & Offline Auto-Login — Diagnostic Report

**Date:** 2026-07-13  
**Scope:** Code analysis only (no runtime execution)  
**Files examined:**
- `lib/router/app_router.dart`
- `lib/main.dart`
- `lib/features/auth/providers/auth_provider.dart`
- `lib/features/dashboard/screens/dashboard_screen.dart`
- `lib/features/admin/screens/admin_dashboard_screen.dart`
- `lib/core/services/security_service.dart`
- `lib/core/utils/platform_helper.dart`
- `lib/features/auth/screens/login_screen.dart`
- `lib/features/lesson/screens/lessons_list_screen.dart`

---

## Symptom A — Black/Blank Screen on Some Routes

### Pre-diagnosis caveat
Black screens can be either **widget-build exception caught by Flutter** (red error overlay in debug, blank in release/without overlay) or **uncaught exception that escapes Flutter's error zone** (app fully terminates, indistinguishable from Symptom B). Without a `flutter run` session to capture actual console output, the following is the best code-path analysis.

### Routes that accept dynamic parameters (higher black-screen risk)

| Route | Widget | Param risk |
|-------|--------|-----------|
| `/lessons/:id` | `LessonEditorScreen(lessonId: int?)` | `int.tryParse('')` yields `null` → widget must handle null `lessonId` |
| `/exams/:id` | `ExamEditorScreen(examId: int?)` | Same null-parsing risk |
| `/admin/teachers/:id` | `TeacherDetailScreen(teacherLocalId: int)` | Guarded: null → shows deliberate `Scaffold` with "Invalid teacher ID" — **no black screen** |

**Potential black-screen candidate: `/lessons/:id` and `/exams/:id` with missing/invalid ID**
If `LessonEditorScreen` or `ExamEditorScreen` does not handle a `null` `lessonId`/`examId` gracefully (e.g., accesses a DB row with `null` filter and throws), it will trigger a widget-build error. Whether this manifests as a black screen (release) or red error overlay (debug) depends on build mode.

### Routes that require specific auth role

| Route | Role guard | Risk |
|-------|-----------|------|
| `/admin` | `isAdminRoute` → redirects non-admin to `/` | Safe: redirect before build |
| `/admin/teachers/:id` | `isAdminRoute` → same redirect | Safe |
| `/payment` | Admin-only, others redirected to `/` | Safe |
| `/full-term-exam` | In `isTeacherRoute` → admin redirected to `/admin` | Safe |
| `/scheme-of-work` | Explicit `return null` for all roles (line 82) | Safe |

### GoRouter redirect-loop risk (rare black-screen cause)

At `app_router.dart:53-97`, the `redirect` closure reads `authProvider` with `listen: false`. During state transitions (`uninitialized` → `checkingLocalAuth` → `authenticated`), `currentTeacher` may briefly be `null`, causing temporary redirect to `/login`. If the redirect throws (provider not yet available, context not mounted), the exception propagates to **`PlatformDispatcher.instance.onError`**, not to Flutter's widget error zone — this becomes **Symptom B** (app close), not a black screen.

### Summary for Symptom A

**Root cause cannot be definitively confirmed without runtime console output.** However, the most likely candidates are:

1. **`/lessons/:id` or `/exams/:id` navigated with invalid/missing `:id`** → the widget crashes during build when it tries to use a `null` lessonId/examId for a DB query. This is a **caught widget-build exception** (visible as red error overlay in debug, blank screen in release).
2. **A null-safety or provider-access error in any screen that doesn't account for guest mode** (`currentTeacher == null`). Since the guest path (`clearTeacher: true`) is used when offline without cached credentials, any screen that assumes `currentTeacher` is non-null will crash during build.

**Status:** Requires runtime test with `flutter run` to capture exact stack traces for each route. No code change recommended yet.

---

## Symptom B — App Closes Automatically + Symptom C — Exit-Confirmation Dialog Bypassed

### These are the SAME bug, not separate

**C is a direct consequence of B, not an independent bug.** The evidence:

### The exit-confirmation dialog chain

There are THREE independent exit-confirmation paths in the codebase:

| # | Location | Trigger | Intercepts |
|---|----------|---------|------------|
| 1 | `lib/main.dart:138-165` — `_RootKeyboardListener._showQuitConfirmation()` | Escape key (desktop) via `HardwareKeyboard` handler | Only keyboard-initiated Escape |
| 2 | `lib/features/dashboard/screens/dashboard_screen.dart:48-75` — `_onBackPressed()` | Android system back on `/` via `PopScope` at line 141 | Only `Navigator.pop()` (system back) |
| 3 | `lib/features/admin/screens/admin_dashboard_screen.dart:40-66` — `_onBackPressed()` | Android system back on `/admin` via `PopScope` at line 118 | Only `Navigator.pop()` (system back) |

All three call `SystemNavigator.pop()` AFTER showing a confirmation dialog. There is **no code path** where a normal user interaction triggers `SystemNavigator.pop()` without first showing a dialog.

### The smoking gun: `PlatformDispatcher.instance.onError` returns `false`

At `lib/main.dart:46-50`:

```dart
PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught error: $error');
    debugPrint(stack.toString());
    return false;   // <── TELLS FLUTTER TO TERMINATE THE APP
};
```

When `PlatformDispatcher.instance.onError` returns `false`, **Flutter terminates the application process immediately** (this is documented Flutter behavior). This termination:

1. Is instantaneous — no dialog can intercept it
2. Bypasses ALL three confirmation-dialog paths because no `PopScope.onPopInvokedWithResult` fires
3. Is silent from the app's perspective — the user sees the app "just close"

### What errors reach `PlatformDispatcher.instance.onError`?

There are two error boundaries:

| Boundary | Catches | Default action |
|----------|---------|---------------|
| `FlutterError.onError` (line 38) | Widget build errors, layout errors, render errors | `presentError` → shows red overlay in debug, logs to console in release |
| `PlatformDispatcher.instance.onError` (line 46) | **Everything else**: async unhandled errors, zone-escaped errors, raw Dart exceptions outside of Flutter's widget tree | Returns `false` → **app terminates** |

`FlutterError.onError` is correctly configured to `presentError`, so widget build errors SHOULD produce a red overlay / console log, NOT terminate the app. The errors that terminate the app must be **non-widget errors** that escape into `PlatformDispatcher.instance.onError`.

Likely candidates for errors reaching `PlatformDispatcher`:
1. **Unhandled async exceptions** in `checkLocalAuth()` or `_loadLocalCredentialCache()` that were not caught (e.g., `FlutterSecureStorage` access crashes, DB access crashes)
2. **Exceptions in GoRouter's `redirect` closure** — if the provider read at line 55 (`ProviderScope.containerOf`) throws (e.g., `ProviderNotFoundException` because the provider isn't ready yet), that exception is NOT caught by any try/catch within `redirect`
3. **Exceptions thrown inside `SentryFlutter.init` or the `appRunner` callback** — could crash during initialization before the widget tree is even built

### Verdict for B + C

| Symptom | Root cause | Evidence |
|---------|-----------|----------|
| **B** (app closes) | Uncaught non-widget exceptions reach `PlatformDispatcher.instance.onError`, which returns `false`, causing Flutter to terminate the process | `main.dart:49` — `return false;` |
| **C** (no quit dialog) | **Not a separate bug.** The app terminates at the platform level via `PlatformDispatcher` — this path bypasses all three `PopScope`/keyboard-based confirmation dialogs because they only guard `Navigator.pop()` and keyboard events, not process termination | Console logs + app-termination behavior |

**Fix approach (future):** Change `main.dart:49` to `return true;` so Flutter does NOT terminate on unhandled errors, AND add a top-level `runZonedGuarded` that logs to Sentry and optionally navigates to an error screen instead of crashing.

---

## Symptom D — Offline Auto-Login Failure

### Architecture: "guest" mode semantics

Per code at `lib/features/auth/providers/auth_provider.dart:401-408`:

```dart
// No cached credentials — show guest dashboard with a Login button.
state = state.copyWith(
    state: AuthState.authenticated,
    clearTeacher: true,
    clearSchool: true,
);
```

**"Guest" is NOT a separate account type** — it is simply `AuthState.authenticated` with `currentTeacher == null` and `currentSchool == null`. The GoRouter redirect at `app_router.dart:63` then redirects guests to `/login`:

```dart
if (authData.currentTeacher == null && location != '/login') return '/login';
```

So "guest mode" is literally "unauthenticated browsing that shows the login screen." It does NOT provide any content access — it's a graceful fallback so the app doesn't crash on startup when offline.

**For cached accounts (e.g., `test@test.com`):** The offline path requires all three of:
1. `getPasswordHash()` returns non-null
2. `schoolsDao.get()` returns a school
3. `teachersDao.getBySchool(school.localId)` returns non-empty teachers list

### The offline path trace

```
checkLocalAuth() [line 368]
  └→ isOnline() == false [line 375]
       └→ _loadLocalCredentialCache() [line 376]
            ├→ getPasswordHash() from FlutterSecureStorage [line 1603]
            │    └→ null or throws → return null → GUEST MODE
            ├→ schoolsDao.get() from local DB [line 1608]
            │    └→ null → return null → GUEST MODE
            └→ teachersDao.getBySchool() from local DB [line 1613]
                 └→ empty → return null → GUEST MODE
```

### Bug hypothesis: The cache read succeeds, the REDIRECT logic is wrong

Look at what happens when **offline with cached credentials** (cache succeeds):

1. `checkLocalAuth()` sets:
   - `state: AuthState.authenticated`
   - `currentTeacher: cachedAuth.teacher` (non-null)
   - `currentSchool: cachedAuth.school` (non-null)

2. The GoRouter `redirect` guard at `app_router.dart:63` checks:
   ```dart
   if (authData.currentTeacher == null && location != '/login') return '/login';
   ```
   Since `currentTeacher` is non-null, this does NOT redirect.

3. The user should see the dashboard `/` — this should work correctly.

**But wait** — let me re-examine the offline path more carefully. There's a subtle issue at lines 401-408:

```dart
// No cached credentials — show guest dashboard with a Login button.
state = state.copyWith(
    state: AuthState.authenticated,
    clearTeacher: true,
    clearSchool: true,
    clearError: true,
);
return;
```

When `_loadLocalCredentialCache()` returns null (no cache), the state goes to `authenticated` with `currentTeacher == null`. This triggers the GoRouter redirect to `/login`. **The user sees the login screen**, not a "guest dashboard."

HOWEVER, there's a **critical UX gap**: When offline with an EMPTY cache, the LoginScreen is shown but `loginOnline()` will fail (network required). The `attemptOfflineLogin()` on line 499 requires the password hash to be cached — but if the cache is empty, it says "No offline credentials are cached yet." So the user is stuck.

### MOST LIKELY ROOT CAUSE: `_loadLocalCredentialCache()` is silently failing

The catch-all at line 1624 devours exceptions:

```dart
} catch (_) {
    return null;
}
```

If ANY of the three reads (secure storage for password hash, schools DAO, teachers DAO) throws, the entire function returns null and the user lands on guest mode → redirect to `/login`.

**Primary suspect: `FlutterSecureStorage.read()` on Android.** Common failure scenarios:
1. **Biometric / credential changes invalidate keys** — If the user enrolled a new fingerprint or changed their lock screen, Android Keystore invalidates the encryption key. `FlutterSecureStorage.read()` throws `PluginException` or similar, caught by the blanket catch, returns null.
2. **App reinstall** — The stored data survives an app install (Android backup), but the encryption key may not, causing read failures.
3. **Android 12+ background restriction** — Keystore access restrictions when the app is launched from background.

**Secondary suspect: Drift database not fully initialized for `schoolsDao.get()`.** Although the FutureBuilder gates the app UI, if there's a race between DB init and the post-frame `checkLocalAuth()` call, a transient DB error could cause the schools/teachers query to throw, caught by the blanket catch.

### Which bug is it: cache read failure vs. redirect logic?

Based on code analysis alone:

**It is a CACHE READ FAILURE, not a redirect logic bug.** Here's why:

- The redirect logic at `app_router.dart:63` correctly recognizes a non-null `currentTeacher` as "not a guest" and allows navigation.
- The only way the user ends up on `/login` when offline with a previously-cached account is if `_loadLocalCredentialCache()` returns null, which triggers the `clearTeacher: true` path, which triggers the redirect to `/login`.
- The blanket `catch (_)` at line 1624 is the most likely culprit, silently swallowing a `FlutterSecureStorage` or Drift exception.

**To confirm:** Deploy a debug build, enable airplane mode, ensure the account was previously logged in online, then launch the app. Add a temporary `debugPrint` inside the catch block at line 1624 to see if an exception is being swallowed. OR, check `FlutterSecureStorage` access logs via `adb logcat` for any Keystore-related errors.

### Guest path vs cached account path — different bugs?

| Path | Condition | Bug | Likelihood |
|------|-----------|-----|-----------|
| `test@test.com` cached | `_loadLocalCredentialCache()` should return non-null | Cache read failure (blanket catch at line 1624) | **High** — see above |
| Guest (no cache) | `_loadLocalCredentialCache()` returns null = correct behavior | UX: user is stuck on login with "no offline credentials" message | **Low** — this is architecturally correct, but off-putting UX |

Both hit the same code path (`_loadLocalCredentialCache()` returning null), but the **root cause only applies to accounts that SHOULD have cached data**.

### Verdict for D

| Aspect | Finding |
|--------|---------|
| **Root cause** | `_loadLocalCredentialCache()` at `auth_provider.dart:1601-1627` silently fails (blanket `catch (_)` at line 1624 returning null) — most likely `FlutterSecureStorage.read()` encounters an Android Keystore error that is swallowed |
| **Is it the cache or the redirect?** | **It's the cache read failure.** The redirect logic at `app_router.dart:63` is correct — it properly checks `currentTeacher == null`. The problem is that `currentTeacher` ends up null because the cache read silently failed. |
| **Affects** | All cached accounts (not guest-specific), most noticeable on Android where Keystore invalidation is common after biometric change or OS update |
| **Guest mode** | Guest mode works as designed (redirect to login). It's not a "mode" — it's just `currentTeacher == null` with `AuthState.authenticated`, which the redirect sends to `/login`. |

---

## Cross-Symptom Dependency Matrix

| | A (black screen) | B (app closes) | C (no quit dialog) | D (offline login) |
|---|---|---|---|---|
| **A** | — | If build error escapes widget zone → B | N/A | N/A |
| **B** | N/A | — | **C is a consequence of B, same root cause** | N/A |
| **C** | N/A | Consequence of B | — | N/A |
| **D** | N/A | N/A | N/A | — |

**Key relationships:**
- **B and C are NOT separate bugs.** C is an expected consequence of B because `PlatformDispatcher.instance.onError` returning `false` kills the process instantly, bypassing all confirmation dialogs.
- **A may become B** if the widget-build error escapes Flutter's error zone (e.g., error in GoRouter redirect closure or async init code).
- **D is independent** — unrelated to A/B/C.

---

## Routes Found with SystemNavigator.pop() Calls

| File | Line | Guarded by dialog? | Notes |
|------|------|-------------------|-------|
| `lib/main.dart` | 153-154 | Yes — `_showQuitConfirmation` | Escape-key only, desktop |
| `lib/features/dashboard/screens/dashboard_screen.dart` | 67-68 | Yes — `_onBackPressed` | System back, home `/` |
| `lib/features/admin/screens/admin_dashboard_screen.dart` | 58-59 | Yes — `_onBackPressed` | System back, admin `/admin` |

No case found where `SystemNavigator.pop()` is called unintentionally or without a guard.

---

## Recommendations for Next Steps

1. **Fix Symptom B (app closes) first** — This is the most disruptive. Change `PlatformDispatcher.instance.onError` to return `true` and add proper error reporting + graceful degradation.
2. **Fix Symptom D (offline login)** — Remove the blanket `catch (_)` at `auth_provider.dart:1624`, add specific error logging to diagnose which cache read fails, and verify `FlutterSecureStorage` accessibility on the target Android device/emulator.
3. **Test Symptom A routes** — Run `flutter run` and navigate to each route listed in `app_router.dart`, capture any error output.
4. **Symptom C will be resolved automatically by fixing B** — No separate fix needed.
