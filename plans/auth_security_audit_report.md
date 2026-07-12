# ClassAI Authentication & Session Logic — Security Audit Report

**Date:** 2026-07-12  
**Auditor:** Roo (Architect Mode)  
**Scope:** Static code analysis of Dart client and TypeScript Edge Functions; RLS policy review; dynamic testing predictions  
**Constraint:** No code was modified. All findings are observational.

---

## Table of Contents

1. [Static Code Analysis](#1-static-code-analysis)
   - 1.1 [JWT Storage & Retrieval](#11-jwt-storage--retrieval)
   - 1.2 [Auto-Login / Offline Login](#12-auto-login--offline-login)
   - 1.3 [Token Versioning & Concurrent Session Blocking](#13-token-versioning--concurrent-session-blocking)
   - 1.4 [Email Verification & Password Reset](#14-email-verification--password-reset)
   - 1.5 [Role-Based Routing](#15-role-based-routing)
   - 1.6 [Logout & Session Cleanup](#16-logout--session-cleanup)
2. [Dynamic Testing Predictions](#2-dynamic-testing-predictions)
   - 2.1 [Offline-First Launch](#21-offline-first-launch)
   - 2.2 [Online → Offline Transition](#22-online--offline-transition)
   - 2.3 [Concurrent Session Blocking](#23-concurrent-session-blocking)
   - 2.4 [Token Expiry Recovery](#24-token-expiry-recovery)
   - 2.5 [Role Escalation Attempts](#25-role-escalation-attempts)
   - 2.6 [Email Verification Bypass Attempts](#26-email-verification-bypass-attempts)
3. [RLS & Server-Side Checks](#3-rls--server-side-checks)
4. [Executive Report](#4-executive-report)
   - 4.1 [Summary](#41-summary)
   - 4.2 [Vulnerability Table](#42-vulnerability-table)
   - 4.3 [Edge Cases & Logic Gaps](#43-edge-cases--logic-gaps)
   - 4.4 [Overall Verdict](#44-overall-verdict)

---

## 1. Static Code Analysis

### 1.1 JWT Storage & Retrieval

#### Architecture
- Custom HS256 JWT (via `djwt` library), **not** Supabase built-in auth.
- JWT is stored in platform secure storage via [`flutter_secure_storage`](lib/core/services/security_service.dart:37) using key `auth_token`.
- The JWT is retrieved from secure storage and sent as a **custom HTTP header** `x-classai-jwt` rather than the standard `Authorization: Bearer` header.

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F1** | **Custom header `x-classai-jwt` lacks standard bearer semantics** | 🟡 Medium | All edge functions that require auth read `x-classai-jwt` from headers. The [`validate-session`](supabase/functions/validate-session/index.ts:24), [`sync-push`](supabase/functions/sync-push/index.ts:561), [`sync-pull`](supabase/functions/sync-pull/index.ts:16), [`sync-realtime-events`](supabase/functions/sync-realtime-events/index.ts:25) functions all use `x-classai-jwt`. However, [`change-password`](supabase/functions/change-password/index.ts:12) and [`redeem-activation`](supabase/functions/redeem-activation/index.ts:21) use `Authorization: Bearer`. This **inconsistency** means the JWT authentication pathway is not standardized across all functions. |
| **F2** | **`_currentJwt` is a static field — not instance-safe** | 🟡 Medium | In [`SupabaseAuthService`](lib/core/services/auth_service.dart:172), `_currentJwt` is a static `String?`. If multiple auth service instances existed (unlikely in production but possible in tests), they would share the same JWT reference. This could cause cross-instance contamination. |
| **F3** | **Debug print statements leak JWT and response data** | 🟠 High | In [`auth_service.dart:188-265`](lib/core/services/auth_service.dart:188), the `login()` method prints the JWT URL, the raw response, and raw exceptions to the debug console. This could leak tokens, teacher data, and school data in logs. |
| **F4** | **Empty certificate fingerprint list = pass-through** | 🟠 High | In [`http_client.dart:37-50`](lib/core/services/http_client.dart:37), the certificate pinning list is populated via `_getCertFingerprints()` which currently returns an **empty list**. With an empty list, certificate pinning is effectively **disabled** — all certificates are trusted. |
| **F5** | **No JWT generated after account activation** | 🟠 High | The [`activate/index.ts`](supabase/functions/activate/index.ts) edge function creates a Supabase Auth user, creates school + teacher, but **does not sign a JWT**. The response includes no `jwt` field. The client's `_currentJwt` remains `null` after activation, meaning the user cannot make authenticated API calls without going through the login flow. |
| **F6** | **No JWT generated after recovery flows** | 🟠 High | Both [`recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts:87-142) and [`admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts:95-153) update passwords successfully but **do not sign or return a JWT**. The client receives no `jwt` in the response. The user must log in again after password recovery. **This is likely intentional** (force re-login after recovery is a security best practice), but the client code expects a `jwt` field in `AuthResult` — its absence could cause a null state. |
| **F7** | **`signup/index.ts` JWT is missing `token_version` claim** | 🟡 Medium | The [`signup/index.ts`](supabase/functions/signup/index.ts:215-232) function signs a JWT with claims `sub`, `teacher_id`, `school_id`, `is_admin`, `exp` — but **not** `token_version`. All other functions that validate JWT via [`validateTokenVersion`](supabase/functions/_shared/validate_token.ts:22) expect `token_version` in the claims. The first `validateSession()` call after signup will compare `claims.token_version` against `teacher.token_version` (default = 1). If `claims.token_version` is `undefined`, the comparison `undefined !== 1` is `true`, causing a **false-positive session expiry**. |

---

### 1.2 Auto-Login / Offline Login

#### Architecture
The [`checkLocalAuth()`](lib/features/auth/providers/auth_provider.dart:345) method implements the startup authentication flow:
1. Load local credential cache (secure storage → password hash)
2. If online: validate JWT via `validateSession()`
3. If online but JWT invalid: try login with cached password hash
4. If offline: rely solely on local credential cache
5. Fallback: show guest dashboard with Login button

The [`attemptOfflineLogin()`](lib/features/auth/providers/auth_provider.dart:476) compares provided password against stored hash from secure storage.

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F8** | **Offline login bypasses all server-side checks** | 🟠 High | The offline login at [`auth_provider.dart:493-497`](lib/features/auth/providers/auth_provider.dart:493) merely compares bcrypt hash from secure storage against the provided password. It does **not** validate: token_version, account deactivation status, email verification, whether the account still exists on the server, or subscription expiry. This is mitigated by the fact that the password hash is stored in platform secure storage (hard to extract), but **if the device is compromised, offline access is completely unconstrained**. |
| **F9** | **JWT expiration is not checked for offline login** | 🟡 Medium | Even if the cached JWT has expired (24-hour expiry), `attemptOfflineLogin` still proceeds based on the password hash comparison alone. The code at [`auth_provider.dart:543-550`](lib/features/auth/providers/auth_provider.dart:543) only attempts online re-auth via `_authService.login()` but falls back to offline mode on any exception. |
| **F10** | **`checkLocalAuth()` falls back to local cache even on JWT validation failure** | 🟢 Low | In [`auth_provider.dart:395-397`](lib/features/auth/providers/auth_provider.dart:395), if `validateSession()` throws, the code catches the exception and falls back to local cache. This is **by design** (offline-first), but means a revoked JWT won't be detected until the user attempts an online operation. The 30-second periodic timer mitigates this. |
| **F11** | **`_isSessionMismatchError()` has narrow detection** | 🟡 Medium | The method at [`auth_provider.dart:275`](lib/features/auth/providers/auth_provider.dart:275) only processes `AuthErrorCode.invalidCredentials` from the `_sessionMismatchCodes` check (line 287). Other auth-related errors (e.g., `AuthErrorCode.unknown`, network errors) are **not treated as session mismatches**, so a user with a genuinely invalid session might remain in an "authenticated" state without being logged out. |

---

### 1.3 Token Versioning & Concurrent Session Blocking

#### Architecture
- **`token_version`** column on `teachers` table (default = 1), incremented on every [`login`](supabase/functions/login/index.ts:86-90).
- JWT payload includes `token_version` claim at time of login.
- [`validateTokenVersion`](supabase/functions/_shared/validate_token.ts:56) compares JWT's `token_version` against the DB value. Mismatch → `token_version_mismatch` error.
- **`current_device_id`** column on `teachers` table. Login checks if `device_id` matches `current_device_id`. If different → concurrent session blocked.
- **`teacher_devices`** table tracks known devices per teacher.

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F12** | **Concurrent session blocking at login (device check) is well-implemented** | 🟢 Low (Good) | In [`login/index.ts:61-66`](supabase/functions/login/index.ts:61), if the incoming `device_id` differs from `teacher.current_device_id`, the login is rejected with 403. This **prevents a second device from logging in** while the first is active. However, see F13. |
| **F13** | **`current_device_id` is updated to new device WITHOUT checking old device is still active** | 🟡 Medium | In [`login/index.ts:93-95`](supabase/functions/login/index.ts:93), the `current_device_id` is set to the new device unconditionally (as long as it's in `teacher_devices`). This means **Device B can forcibly take over from Device A** simply by registering first (which happens automatically on first login attempt from that device). The old device's JWT will be invalidated on next `validateSession()` due to `token_version` increment, but the old device is never notified. |
| **F14** | **`token_version` is incremented on EVERY login — even for the same device** | 🟢 Low (Informational) | Every call to [`login/index.ts:86-90`](supabase/functions/login/index.ts:86) increments `token_version`. This means **every app restart** on the same device (which triggers `checkLocalAuth()` → JWT validation fails for ephemeral reason → `loginOnline()`) increments the version. All other logged-in devices are invalidated on each re-login. This could cause excessive session invalidations for multi-device teachers. |
| **F15** | **Client-side session mismatch detection uses error message string matching** | 🟡 Medium | In [`_isSessionMismatchError()`](lib/features/auth/providers/auth_provider.dart:275), the detection converts the error to a string and checks for substrings: `"token_version_mismatch"`, `"session expired"`, `"401"`, `"unauthorized"`. This is **brittle** — if the server changes error message formatting, the client won't detect session mismatches. A structured error code would be more robust. |
| **F16** | **`_logoutIfSessionMismatch()` checks `!state.isOnline`** | 🟡 Medium | At [`auth_provider.dart:305`](lib/features/auth/providers/auth_provider.dart:305), the method checks `!state.isOnline`. If the device is offline when the session mismatch is detected (e.g., by the periodic timer), it **won't trigger logout**. The user remains in an "authenticated" offline state with an invalid session. When they go back online, the timer fires again and should catch it. |
| **F17** | **`signup` function does NOT set `current_device_id`** | 🟡 Medium | After [`signup/index.ts`](supabase/functions/signup/index.ts) creates the teacher, it does not set `current_device_id` on the new teacher record. The teacher's `current_device_id` remains `null`. The first login will work (no device check for null), but this means the signup JWT (which is missing `token_version` per F7) cannot be properly validated. |

---

### 1.4 Email Verification & Password Reset

#### Architecture
- **Signup flow:** `initiateSignup()` → verify email (6-digit OTP) → `_finalizeSignup()` creates account. This is **verify-before-create**.
- **Login flow:** Regular login → if `email_verified == false` after JWT issued → show email verification dialog.
- **Verification codes:** 6-digit OTP, 15-minute expiry, max 3 attempts, sent via Gmail SMTP.
- **Password reset (teacher):** `recovery-generate-code` → `recovery-reset-password` (no JWT required).
- **Password reset (admin):** `admin-recovery-request` → `admin-recovery-verify-otp` (no JWT required).

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F18** | **Verify-before-create signup is well-designed** | 🟢 Low (Good) | The signup flow in [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart:842-938) requires email verification **before** the account is created. The server [`verify-code/index.ts`](supabase/functions/verify-code/index.ts) in signup mode requires only the email (no JWT) and validates the code before account creation proceeds. This prevents creating orphan accounts with unverified emails. |
| **F19** | **`send-verification-code` in signup mode has no rate limiting on the email field** | 🟡 Medium | The [`send-verification-code/index.ts`](supabase/functions/send-verification-code/index.ts) for signup mode requires only email from the body (no JWT). An attacker could **flood an email address with OTP codes** by calling this function repeatedly, since the rate limiting is implicit (expiring old codes) rather than explicit (cooldown period). |
| **F20** | **`recovery-reset-password` is completely open (no JWT)** | 🟠 High | The [`recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts) function validates only against `recovery_codes` table — code match, `used=false`, `expires_at` check, max 3 attempts. If an attacker obtains a valid recovery code (e.g., via SMS interception or social engineering), they can reset the password without any authentication. **This is inherent to the password recovery model** and not a bug per se, but the protection relies entirely on the security of the recovery code delivery channel (SMS) and the `recovery_codes` table integrity. |
| **F21** | **`admin-recovery-request` returns `debug_otp` in dev mode** | 🟡 Medium | At [`admin-recovery-request/index.ts:123`](supabase/functions/admin-recovery-request/index.ts:123), the response includes `debug_otp` if `DENO_REGION` is `"local"`. In development environments, this means anyone who can make HTTP requests can see the plaintext OTP. If this were accidentally deployed with `DENO_REGION` = unset/local, it would leak OTPs. |
| **F22** | **`verify-email/index.ts` generates a verification token but doesn't validate JWT** | 🟠 High | The [`verify-email/index.ts`](supabase/functions/verify-email/index.ts) function takes an `email` parameter, looks up the teacher, generates a verification token, stores it on the teacher record, and returns a verification URL. **There is no JWT validation** — anyone who knows an email address can trigger a verification email for that teacher. The `config.toml` file doesn't exist for this function, but it uses no auth header. |
| **F23** | **`verify-email` token is stored on the teacher record without expiry enforcement** | 🟡 Medium | The token `email_verification_token` has a 24-hour expiry, but the verification endpoint that consumes this token exists client-side only (deep link handler). If the deep link handler is not properly implemented, the token could remain valid indefinitely. |
| **F24** | **`forgot_password_dialog.dart` relies on server-side function but does not enforce rate limiting** | 🟢 Low | The [`forgot_password_dialog.dart`](lib/features/auth/screens/forgot_password_dialog.dart:76) sends a recovery request. The server-side `recovery-generate-code` function handles rate limiting implicitly. No additional client-side rate limiting is imposed. |

---

### 1.5 Role-Based Routing

#### Architecture
- GoRouter in [`app_router.dart`](lib/router/app_router.dart:53-97) with redirect logic:
  - If `currentTeacher == null` and not `/login` → redirect to `/login`
  - If role is `admin` on teacher route → redirect to `/admin`
  - If role is not `admin` on admin route → redirect to `/`
  - `/scheme-of-work` is accessible by both roles (explicitly excluded)

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F25** | **Missing redirect for `currentTeacher != null && role == null`** | 🟡 Medium | In [`app_router.dart:53-97`](lib/router/app_router.dart:53), the redirect logic checks `if (currentTeacher == null)` but does **not** check the case where `currentTeacher != null` but `role` is `null`. This could happen if a teacher record is loaded without the role field. In this state, the user would pass the null teacher check, but neither admin nor teacher route checks would match — they could end up on the root route `/` with no navigation guard. This is an **unhandled edge case**. |
| **F26** | **Role-based routing relies on client-side `currentTeacher.role`** | 🟡 Medium | The role check at [`app_router.dart:68-73`](lib/router/app_router.dart:68) reads `currentTeacher.role` from the Riverpod state. The `role` field originates from the server during login and is stored in the local Drift database. If a teacher's role is changed on the server (admin demoted to teacher), the **client will not know until the next sync-pull** (which syncs the `teachers` table). During the gap, the demoted admin retains access to admin routes. |
| **F27** | **`/payment` route is admin-only but billing webhook is server-validated** | 🟢 Low (Informational) | The `/payment` route at [`app_router.dart:89-91`](lib/router/app_router.dart:89) is restricted to admin only. The server-side [`paystack-webhook`](supabase/functions/paystack-webhook/index.ts) handles actual payment processing. Even if a teacher accesses `/payment` through direct navigation, Paystack's webhook validation prevents unauthorized billing actions. |

---

### 1.6 Logout & Session Cleanup

#### Architecture
- [`_performLogout()`](lib/features/auth/providers/auth_provider.dart:1004) in AuthNotifier:
  1. Sets `logoutInProgress = true`
  2. Clears secure storage (JWT, password hash, session key)
  3. Calls `_authService.logout()` (sets `_currentJwt = null`, calls `supabase.auth.signOut()`)
  4. Resets state to `AuthState.onlineLoginRequired`
  5. Navigates to login screen

#### Findings

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F28** | **Logout does NOT increment `token_version` on the server** | 🟡 Medium | When a user logs out, the `token_version` stays the same on the server. This means if the JWT hasn't expired yet and someone steals it (e.g., from logs per F3), it remains valid until the 24-hour expiry. A logout-triggered `token_version` increment would immediately invalidate all tokens for that user. |
| **F29** | **`_performLogout()` clears `_sessionTimer` but does not cancel pending operations** | 🟢 Low | At [`auth_provider.dart:1004-1037`](lib/features/auth/providers/auth_provider.dart:1004), the logout method clears the timer at line 1027 with `_sessionTimer?.cancel()`. However, if a `validateSession()` call is **in-flight** when logout is triggered, the response handling could attempt to modify state after logout, potentially causing a state inconsistency. The `mounted` check mitigates this but isn't guaranteed with async gaps. |
| **F30** | **`_performLogout()` clears secure storage before server logout** | 🟢 Low (Informational) | The order at [`auth_provider.dart:1008-1012`](lib/features/auth/providers/auth_provider.dart:1008) is: clear secure storage → call server logout. If the server logout call fails (network error), the local credentials are already gone. The user is logged out locally but the server still considers the session active. The `token_version` remains unchanged, so the server won't revoke the session. |
| **F31** | **`supabase.auth.signOut()` is called but app uses custom JWT** | 🟢 Low (Informational) | At [`auth_service.dart:342`](lib/features/auth/service.dart:342), `_auth.signOut()` calls Supabase Auth's sign-out. Since the app uses **custom JWT auth** (not Supabase Auth session), this call may be a no-op. The actual session cleanup is the `_currentJwt = null` and secure storage clearing. |

---

## 2. Dynamic Testing Predictions

### 2.1 Offline-First Launch

**Scenario:** User launches app with no network connectivity. Account exists with cached credentials.

**Predicted behavior:**
1. Auth state goes to `checkingLocalAuth`
2. [`_loadLocalCredentialCache()`](lib/features/auth/providers/auth_provider.dart:1578) reads password hash from secure storage
3. JWT validation skip (`state.isOnline == false`)
4. Returns cached teacher + school from local DB
5. State transitions to `authenticated` with `isOnline: false`

**Expected result:** User sees dashboard with limited offline functionality (3 credits). Sync button disabled. "You're offline" indicator shown.

**Risk assessment:** ✅ **Works as designed.** The offline fallback correctly preserves access for offline scenarios. Risk F8 applies: no server-side checks are performed.

### 2.2 Online → Offline Transition

**Scenario:** User is authenticated online, then loses network. They continue using the app, then go back online.

**Predicted behavior:**
1. During online period: 30-second timer calls `validateSession()` successfully
2. Network drops: timer fires → `validateSession()` throws (network error)
3. `_isSessionMismatchError()` returns false for network errors (not in the error code list)
4. Error is caught at [`auth_provider.dart:395-397`](lib/features/auth/providers/auth_provider.dart:395) — falls through without state change
5. Timer continues firing, retrying validation every 30 seconds
6. When network returns: next timer tick → successful `validateSession()` → normal operation resumes

**Expected result:** ✅ **Graceful transition.** The system does not log out the user during transient network issues. The 30-second retry ensures automatic recovery.

**Risk assessment:** Low risk, but consider F11 — if the server returns a structured error during the offline gap that's not in the recognized error codes, the user could remain authenticated with an invalid session until the next successful validation.

### 2.3 Concurrent Session Blocking

**Scenario:** Same teacher account logged in on two devices (Phone A and Phone B).

**Step-by-step prediction:**

1. **Phone A login:**
   - `token_version` incremented to N (was N-1)
   - `current_device_id` set to Device-A-ID
   - Phone A JWT has `token_version: N`

2. **Phone B login attempt:**
   - Sends device_id = Device-B-ID
   - Server checks: `teacher.current_device_id` (Device-A-ID) !== Device-B-ID → **blocked with 403**
   - Response: `{ error: "Concurrent session detected...", code: "concurrent_session", requires_new_device: true }`

3. **Phone B user clicks "Continue anyway" (in `loginOnline` handling):**
   - Calls `_authService.login()` again with `forceDeviceRegistration: true`
   - Server registers Device-B-ID in `teacher_devices`, updates `current_device_id` to Device-B-ID, increments `token_version` to N+1
   - Phone B logs in successfully with JWT `token_version: N+1`

4. **Phone A timer fires next:**
   - `validateSession()` sends JWT with `token_version: N`
   - Server compares: JWT `token_version` (N) !== DB `token_version` (N+1) → `token_version_mismatch`
   - Phone A's `_isSessionMismatchError()` detects mismatch
   - Phone A is logged out with "Session expired" message

**Expected result:** ✅ **Concurrent session blocked as designed.** Phone B forcibly takes over from Phone A with user consent. Phone A is silently logged out within 30 seconds.

**Risk assessment:** ✅ **Well-implemented.** The flow is secure. Minor concern: F14 mentions every login increments `token_version`, meaning even the same device could trigger this flow on re-login.

### 2.4 Token Expiry Recovery

**Scenario:** User's 24-hour JWT expires while they are actively using the app.

**Step-by-step prediction:**

1. JWT expires server-side (via `exp` claim in edge function)
2. Next user action that triggers an API call (sync, lesson generation, etc.):
   - The HTTP request includes `x-classai-jwt` with expired token
   - Edge function `validateTokenVersion()` throws JWT verification error
   - Error propagates to the calling Dart code
3. However, most operations use the **30-second timer** `validateSession()`:
   - If the timer is running, within 30 seconds of expiry:
     - `_authService.validateSession()` calls edge function
     - Edge function fails JWT verification
     - `_isSessionMismatchError()` checks error string for `"401"` or `"unauthorized"`
     - If matched → `_logoutIfSessionMismatch()` → logout
     - If NOT matched → error suppressed, user remains "authenticated"

**Predicted issue:** The [`_isSessionMismatchError()`](lib/features/auth/providers/auth_provider.dart:275) method may **not correctly detect all JWT expiry scenarios**. The `djwt` library's JWT verification error message may not contain `"401"` or `"unauthorized"` — it might say `"JWT expired"` or `"Signature verification failed"`.

**Expected result:** ⚠️ **Potentially inconsistent.** If the JWT validation error message from the edge function doesn't match the expected substrings, the user won't be logged out and will remain in an "authenticated" state with an expired token. The next successful re-auth attempt (e.g., background re-login) would restore access.

**Risk assessment:** 🟠 High | This is a **real gap** — the error detection relies on fragile string matching without a structured error protocol for JWT expiry.

### 2.5 Role Escalation Attempts

**Scenario:** Teacher user attempts to access admin-only features.

**Step-by-step prediction:**

1. **Client-side routing protection:**
   - Teacher navigates to `/admin` or `/payment`
   - GoRouter redirect logic checks `currentTeacher.role`
   - Role is `teacher` → redirected to `/`
   - **Client-side check is robust**

2. **Direct API calls to admin functions:**
   - Teacher's JWT contains `is_admin: false` claim (set during login)
   - Admin-only edge functions (e.g., `redeem-activation`, `request-upgrade`):
     - [`redeem-activation/index.ts:50-64`](supabase/functions/redeem-activation/index.ts:50): checks `teacher.role !== "admin"` from DB → 403
     - `request-upgrade`: checks role from JWT claims or DB lookup
   - **Server-side check is also robust**

3. **Sync-push / sync-pull as admin workaround:**
   - Even if a teacher's sync-push payload includes admin fields (e.g., modifying `schools` table), the edge function processes the change — but it uses `service_role` key, so **it could succeed** if the payload includes valid school data.

**Predicted result:** ✅ **Role escalation is prevented** at both client and server layers.

**Risk area:** ⚠️ **The sync-push function uses service_role key** with `verify_jwt = false` in config.toml but validates JWT manually via `validateTokenVersion()`. The JWT claims are used only for identity, not authorization scoping. If a teacher with `is_admin: false` sends a sync-push that modifies school-level data, the function **processes it because it uses service_role client** — the authorization is at the data access layer (DB RLS). Since the function uses service_role (bypasses RLS), the only protection is the function's own logic. Currently, the function does not check `is_admin` before processing updates to school-level tables.

**Risk assessment:** 🟡 Medium | Sync-push could be a vector for unauthorized school-level modifications if a payload is crafted to target `schools` or other admin tables. The function currently trusts all changes from any authenticated teacher.

### 2.6 Email Verification Bypass Attempts

**Scenario:** Attacker attempts to bypass email verification to access the app with an unverified account.

**Step-by-step prediction:**

1. **Login with unverified email:**
   - Login proceeds normally (server issues JWT even if `email_verified = false`)
   - Server response includes `email_verified: false`
   - Client state enters `emailVerificationRequired`
   - Email verification dialog is shown (non-dismissible via `PopScope(canPop: false)`)
   - User cannot proceed without verifying

2. **Direct API access with unverified status:**
   - JWT contains no explicit `email_verified` claim (checking JWT payload structure in login/index.ts)
   - Edge functions don't check `email_verified` on the DB side for data operations
   - Sync-push, sync-pull, and other functions rely only on `validateTokenVersion()` which checks `token_version` only
   - **A determined attacker could use the JWT (even with unverified email) to call sync functions**

3. **Verification code brute force:**
   - 6-digit code = 1,000,000 possibilities
   - Max 3 attempts per code (server-enforced in `verify-code/index.ts`)
   - 15-minute code expiry
   - After 3 failed attempts: code is marked used, need to request new code
   - Rate limiting is adequate for 6-digit codes

**Predicted result:** ⚠️ **Email verification is enforced at the client (dialog), but not at the server level** for all API operations. A technically skilled user could extract the JWT from secure storage and use it to call sync functions without email verification.

**Risk assessment:** 🟠 High | The email verification is a **client-enforced gate**, not a server-enforced permission. The JWT is issued regardless of verification status. The sync and data operations don't check `email_verified` before processing requests.

---

## 3. RLS & Server-Side Checks

### Migration SQL Analysis

| Table | RLS Enabled | Policy | Effect |
|-------|------------|--------|--------|
| [`pending_activations`](supabase/migrations/20260517_add_auth_tables.sql:69) | Yes | `service_role_all` — ALL TO service_role USING(true) WITH CHECK(true) | Only service_role (edge functions) can access. End-user never touches this table directly. ✅ |
| [`admin_recovery_otps`](supabase/migrations/20260517_add_auth_tables.sql:70) | Yes | `service_role_all` — same pattern | Same as above. ✅ |
| [`verification_codes`](supabase/migrations/20260520_add_email_verification.sql:39-42) | Yes | `auth.role() = 'service_role'` | Same pattern using auth.role() instead of TO. ✅ |
| `teachers` (not explicitly defined in migrations read) | Assumed enabled | — | Edge functions use `service_role` client, bypassing RLS entirely. |
| `schools` (not explicitly defined) | Assumed enabled | — | Same pattern. |

### Key Finding

**All edge functions use `service_role` Supabase client** (created with `SUPABASE_SERVICE_ROLE_KEY`). This means **RLS is completely bypassed** for all edge function operations. Authorization is performed **programmatically within each function** rather than through RLS policies.

| # | Observation | Risk | Details |
|---|------------|------|---------|
| **F32** | **No RLS on `teachers` or `schools` for end-user access** | 🟡 Medium | If an end-user somehow manages to query these tables directly (e.g., via Supabase client SDK with anon key and a leaked API endpoint), there may be no RLS policy restricting access. However, the app does not expose direct table queries from the client — all access is through edge functions. |
| **F33** | **`service_role` pattern means all functions are all-powerful** | 🟢 Low (Informational) | Every edge function has full CRUD access to all tables. The security posture relies entirely on the **correctness of each function's authorization logic**. A bug in any single function could expose all data. This is a deliberate architectural choice but carries inherent risk. |
| **F34** | **`verify_jwt = false` in config.toml for most auth functions** | 🟡 Medium | Functions with `verify_jwt = false`: [`sync-push`](supabase/functions/sync-push/config.toml:2), [`sync-pull`](supabase/functions/sync-pull/config.toml:2), [`sync-realtime-events`](supabase/functions/sync-realtime-events/config.toml:2), [`verify-code`](supabase/functions/verify-code/config.toml:2), [`send-verification-code`](supabase/functions/send-verification-code/config.toml:2), [`validate-session`](supabase/functions/validate-session/config.toml:2), [`change-password`](supabase/functions/change-password/index.ts:12) (uses Bearer instead). These functions **manually validate** the JWT via `validateTokenVersion()` rather than relying on Supabase's gateway JWT verification. This means the Supabase gateway does NOT reject unauthenticated requests — the function itself must do it. If `validateTokenVersion()` has a bug, the function could be called without auth. |
| **F35** | **`redeem-activation` has `verify_jwt = true` at gateway level but ALSO validates manually** | 🟢 Low (Good) | [`redeem-activation/config.toml`](supabase/functions/redeem-activation/config.toml:2) has `verify_jwt = true`. The gateway rejects unauthenticated requests before the function runs. The function then additionally checks `teacher.role === "admin"` from the DB. This is **defense-in-depth** and correctly implemented. |

### Summary of `verify_jwt` Settings

| Function | `verify_jwt` | Manual Validation | Protection |
|----------|-------------|-------------------|------------|
| `redeem-activation` | `true` | Yes (validateTokenVersion + role check) | ✅ Gateway + function |
| `request-upgrade` | `true` | Yes (validateTokenVersion) | ✅ Gateway + function |
| `verify-payment` | `true` | Unknown | ✅ Gateway |
| `sync-push` | `false` | Yes (validateTokenVersion) | ⚠️ Function only |
| `sync-pull` | `false` | Yes (validateTokenVersion) | ⚠️ Function only |
| `sync-realtime-events` | `false` | Yes (validateTokenVersion) | ⚠️ Function only |
| `validate-session` | `false` | Yes (validateTokenVersion) | ⚠️ Function only |
| `verify-code` | `false` | Conditional (normal mode only) | ⚠️ Partially |
| `send-verification-code` | `false` | Conditional (normal mode only) | ⚠️ Partially |
| `change-password` | N/A (no config.toml) | Yes (uses Bearer + validateTokenVersion) | ⚠️ Function only |
| `signup` | N/A | No JWT (open for account creation) | 🟢 Intentionally open |
| `activate` | N/A | No JWT (activation code only) | 🟢 Intentionally open |
| `login` | N/A | No (password-based auth) | 🟢 Intentionally open |
| `recovery-reset-password` | N/A | No (recovery code only) | 🟢 Intentionally open |
| `admin-recovery-request` | N/A | No (email only) | 🟢 Intentionally open |
| `admin-recovery-verify-otp` | N/A | No (OTP only) | 🟢 Intentionally open |
| `verify-email` | N/A | No (email only, no config.toml) | ⚠️ Open endpoint |

---

## 4. Executive Report

### 4.1 Summary

The ClassAI authentication system implements a **custom JWT-based auth architecture** with well-designed security features including:
- **Token versioning** for session invalidation (server-incremented on each login)
- **Concurrent session blocking** via device ID tracking
- **Verify-before-create** signup flow
- **Offline-first** with secure credential caching
- **Non-dismissible email verification** dialog at the client

The system shows **strong architectural choices** (custom JWT, token versioning, device registration) that demonstrate deliberate security design. However, several issues were identified in the implementation details:

1. **Critical:** No JWT generated after [`activate`](supabase/functions/activate/index.ts) and [`recovery-reset-password`](supabase/functions/recovery-reset-password/index.ts) flows
2. **Critical:** [`signup/index.ts`](supabase/functions/signup/index.ts) JWT missing `token_version` claim — causes false-positive session expiry
3. **High:** [Email verification is client-enforced only](lib/features/auth/providers/auth_provider.dart:717-720) — server does not gate data operations on `email_verified`
4. **High:** [Certificate pinning is disabled](lib/core/services/http_client.dart:37-50) — empty fingerprint list
5. **High:** [Debug log leakage](lib/core/services/auth_service.dart:188-265) of JWT and response data
6. **High:** [Error detection uses fragile string matching](lib/features/auth/providers/auth_provider.dart:275) instead of structured error codes
7. **Medium:** [No `token_version` increment on logout](lib/features/auth/providers/auth_provider.dart:1004)
8. **Medium:** [sync-push doesn't check admin role](supabase/functions/sync-push/index.ts) — any authenticated teacher can push data to any table via service_role client

### 4.2 Vulnerability Table

| ID | Severity | Title | File(s) | Fix Recommendation |
|----|----------|-------|---------|-------------------|
| F5 | 🔴 Critical | No JWT after account activation | [`activate/index.ts`](supabase/functions/activate/index.ts) | Sign a JWT in the activate function and return it in the response |
| F6 | 🔴 Critical | No JWT after password recovery | [`recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts), [`admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts) | Sign a JWT after password update and return it, OR update client to handle null JWT gracefully |
| F7 | 🔴 Critical | Signup JWT missing `token_version` | [`signup/index.ts`](supabase/functions/signup/index.ts:215-232) | Add `token_version` (teacher.token_version or 1) to JWT claims at signup |
| F3 | 🟠 High | Debug log leaks JWT and responses | [`auth_service.dart`](lib/core/services/auth_service.dart:188-265) | Remove or gate debug print statements behind a verbose flag |
| F4 | 🟠 High | Certificate pinning disabled | [`http_client.dart`](lib/core/services/http_client.dart:37-50) | Deploy valid certificate fingerprints for production |
| F11 | 🟠 High | Fragile session mismatch detection | [`auth_provider.dart:275`](lib/features/auth/providers/auth_provider.dart:275) | Use structured error codes (e.g., `AuthErrorCode`) instead of string matching |
| F22 | 🟠 High | `verify-email` endpoint is open | [`verify-email/index.ts`](supabase/functions/verify-email/index.ts) | Add JWT validation for non-signup flows, or rate-limit by email |
| F1 | 🟡 Medium | Inconsistent auth header standard | Multiple edge functions | Standardize all functions to use `Authorization: Bearer` or all use `x-classai-jwt` |
| F2 | 🟡 Medium | Static `_currentJwt` | [`auth_service.dart:172`](lib/core/services/auth_service.dart:172) | Make `_currentJwt` an instance field, or ensure singleton usage |
| F8 | 🟡 Medium | Offline login bypasses server checks | [`auth_provider.dart:493-497`](lib/features/auth/providers/auth_provider.dart:493) | Acceptable by design (offline-first), but document the risk |
| F13 | 🟡 Medium | Device takeover without notification | [`login/index.ts:93-95`](supabase/functions/login/index.ts:93) | Notify old device via push/email when device takeover occurs |
| F14 | 🟡 Medium | Every login increments `token_version` | [`login/index.ts:86-90`](supabase/functions/login/index.ts:86) | Only increment `token_version` when a NEW device logs in, not same-device re-login |
| F16 | 🟡 Medium | Offline session mismatch not processed | [`auth_provider.dart:305`](lib/features/auth/providers/auth_provider.dart:305) | Queue session mismatch for processing when connectivity returns |
| F19 | 🟡 Medium | No rate limiting on OTP sending | [`send-verification-code/index.ts`](supabase/functions/send-verification-code/index.ts) | Add explicit rate limiting (cooldown period per email) |
| F21 | 🟡 Medium | `debug_otp` in admin recovery | [`admin-recovery-request/index.ts:123`](supabase/functions/admin-recovery-request/index.ts:123) | Remove `debug_otp` or gate behind stricter env check |
| F25 | 🟡 Medium | Missing null role edge case in router | [`app_router.dart:53-97`](lib/router/app_router.dart:53) | Add explicit check for `currentTeacher != null && role == null` |
| F26 | 🟡 Medium | Role change not reflected until next sync | [`app_router.dart:68-73`](lib/router/app_router.dart:68) | Validate role from `validateSession()` response on each check |
| F27 | 🟡 Medium | `verify_jwt = false` on auth functions | Various config.toml files | Set `verify_jwt = true` where possible, or document why manual validation is used |
| F34 | 🟡 Medium | Service_role in all edge functions | All edge functions | Consider implementing function-level scoping or per-table RLS for defense-in-depth |

### 4.3 Edge Cases & Logic Gaps

| # | Gap | Details | Impact |
|---|-----|---------|--------|
| E1 | **Login race condition** | User logs in on Device A → `token_version` incremented. Simultaneous request from Device A using old JWT → `validateSession()` fails with `token_version_mismatch` → Device A logged out of its own session. | User might see "Session expired" immediately after login if a timer fires before the new JWT propagates. The 30-second timer interval mitigates this: the login response gives the client the new JWT, so the next timer tick (up to 30s later) uses the new JWT. Low risk. |
| E2 | **`checkLocalAuth()` race with `loginOnline()`** | If `checkLocalAuth()` is still running (JWT validation in flight) when the user taps Login, two auth flows could run concurrently. | State machine design prevents this — `checkLocalAuth()` runs on startup, Login button only appears after all checks complete. Low risk. |
| E3 | **`_finalizeSignup()` called after `initiateSignup()` already saved to local DB** | [`_saveAuthResultToLocalDb`](lib/features/auth/providers/auth_provider.dart:1606) is called at the end of `initiateSignup()` (line 926) and again at the end of `_finalizeSignup()` (line 988). | Double-write to local DB: the second call upserts the school and teacher that were already inserted. The upsert logic uses `serverId` matching, so it should be idempotent. Low risk due to upsert semantics. |
| E4 | **Admin recovery OTP has no code expiry enforcement** | The OTP has `expires_at` stored, but the [verify function](supabase/functions/admin-recovery-verify-otp/index.ts:66) only checks `!expires_at || expires_at < now`. If `expires_at` is null (DB default?), the null check passes and the OTP never expires. | Depends on migration having NOT NULL constraint. The migration [`20260517_add_auth_tables.sql`](supabase/migrations/20260517_add_auth_tables.sql:25) has `expires_at TIMESTAMPTZ NOT NULL`. Low risk. |
| E5 | **Device ID mismatch during validate-session** | The [`validate-session/index.ts`](supabase/functions/validate-session/index.ts:64-72) optionally checks `device_id` against `teacher_devices`. If device_id provided and not found, the session is **still valid** (just logged). | This means a stolen JWT from an unknown device can still be used to call `validate-session`. The device check is informational only. Medium risk. |
| E6 | **Supabase Auth user creation in activate may fail silently** | [`activate/index.ts`](supabase/functions/activate/index.ts:145) calls `supabase.auth.admin.createUser()` then proceeds to create teacher/school records. If the Auth user creation succeeds but the subsequent DB inserts fail, the Auth user is orphaned (no corresponding teacher record). | The code structure should handle this transactionally, but Supabase Edge Functions don't have cross-service transactions. Medium risk. |

### 4.4 Overall Verdict

```
VERDICT: CONDITIONALLY SECURE — 3 Critical, 4 High, 10 Medium, 4 Low findings
```

The ClassAI authentication system demonstrates a **well-architected custom auth model** with thoughtful security features:
- Token versioning with server-side validation
- Concurrent session blocking via device registration  
- Offline-first with secure credential caching
- Verify-before-create signup flow

**Strengths:**
- The token versioning mechanism (`validateTokenVersion`) is correctly implemented and used consistently across all auth-protected edge functions
- The signup flow (verify-before-create) prevents account creation with unverified emails
- The offline-first design with graceful fallback is well-implemented
- Concurrent session blocking at login time is robust
- Non-dismissible email verification dialog prevents UI bypass

**Critical Issues (must fix before production):**
1. **No JWT after activation** (F5) — users cannot proceed after account activation without a separate login
2. **No JWT after recovery** (F6) — users cannot proceed after password reset without a separate login  
3. **Signup JWT missing `token_version`** (F7) — first server interaction after signup will trigger false session expiry

**Significant Concerns:**
1. Email verification is **client-enforced only** — no server-side gate on data operations
2. Certificate pinning is **disabled** — MITM attack surface
3. Debug log leakage of JWT tokens in client-side code
4. Session mismatch detection uses **brittle string matching** instead of structured error codes

**Recommendations:**
1. Fix the three Critical issues (F5, F6, F7) — these are server-side edge function fixes
2. Implement server-side `email_verified` check in sync-push/pull functions
3. Deploy valid certificate fingerprints
4. Strip debug prints from production builds
5. Standardize error handling to use structured error codes
6. Add rate limiting to OTP sending endpoints
7. Configure `verify_jwt = true` for all non-anonymous edge functions where possible

The system is **foundationally secure but has implementation gaps** that should be addressed before production deployment. The custom JWT architecture is sound and the token versioning mechanism is particularly well-executed.
