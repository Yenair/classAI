# Full Audit: teachers/Auth Consistency and Login Failure Root Cause

**Date:** 2026-07-13  
**Target Admin Email:** `umohyeneabasi@gmail.com`  
**Type:** Read-only investigation — no modifications made

---

## Step 1: Login Failure Root Cause Analysis

### How "Invalid email or password" Is Produced

The [`login/index.ts`](supabase/functions/login/index.ts) function has exactly **two code paths** that produce "Invalid credentials" (the server-side error that appears as "Invalid email or password" on the client):

**Path A — Account not found (line 42-44):**
```typescript
const { data: teacher, error: teacherError } = await supabase
  .from("teachers")
  .select("*, schools(...)")
  .eq("email", email)
  .maybeSingle();

if (teacherError || !teacher) {
  return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
}
```

**Path B — Password mismatch (line 54-57):**
```typescript
const valid = await bcrypt.compare(password + pepper, teacher.password_hash);
if (!valid) {
  return new Response(JSON.stringify({ error: "Invalid credentials" }), { status: 401 });
}
```

These produce the **exact same error string** — the client cannot distinguish them.

### What We Know About the Admin Account

From the prior report's confirmed DB state:
- ✅ `teachers` row EXISTS for `umohyeneabasi@gmail.com`
- ✅ `is_active: true`
- ✅ `email_verified: true`

**Conclusion:** The account is found in the `teachers` table (Path A is ruled out). The "Invalid credentials" error must come from **Path B — password comparison failing**.

### Why Password Comparison Fails

The hash formula is:

```
password_hash = bcrypt(plaintext_password + PASSWORD_PEPPER, rounds=10)
```

The comparison is:

```
valid = bcrypt.compare(input_password + PASSWORD_PEPPER, stored_password_hash)
```

#### Possible Cause #1: Wrong password (user error)
The user is entering a password that doesn't match the one used to create the hash.

#### Possible Cause #2: PASSWORD_PEPPER has changed
If `PASSWORD_PEPPER` environment variable has been **changed or rotated** since this account's hash was created, then `bcrypt.compare("correct_password" + new_pepper, old_hash)` will fail — for EVERY account, not just this one.

This is the most dangerous scenario because it's **systemic**: if the pepper changed, **no one can log in**.

#### Possible Cause #3: Account was created via `signup` flow without a confirmable password
If the admin account was created via the web signup ([`signup/index.ts`](supabase/functions/signup/index.ts)), the signup function does set `password_hash` correctly (line 108-123). However, the signup was originally followed by an `activate` step that also creates a new hash (line 107 of activate/index.ts). If the activation was done with a **different password** than signup, and the user is trying to login with the signup password, it would fail.

#### What Does NOT Affect Login

| Factor | Effect | Evidence |
|--------|--------|----------|
| `force_password_reset = true` | ❌ Does NOT block login | [`login/index.ts`](supabase/functions/login/index.ts) lines 82-83: issues short-lived JWT with flag, still allows login |
| `is_active` | ❌ Login does NOT check it | No check in login function at all |
| Missing Supabase Auth user | ❌ Login does NOT use Auth | Login queries only `teachers` table |
| `token_version` mismatch | ❌ Different error message | Returns 401 "Session expired" / "token_version_mismatch" from [`validate_token.ts`](supabase/functions/_shared/validate_token.ts), not "Invalid credentials" |

### Password Recovery Flow (Separate Issue)

The "Auth user not found" error comes from a **different function** — [`admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts) (lines 109-114) and [`recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts) (lines 98-103). These functions:
1. Look up the teacher in `teachers` table ✅ (succeeds)
2. Look up the matching Auth user by email via `supabase.auth.admin.listUsers()` ❌ FAILS if no Auth user exists
3. Return `"Auth user not found"` (404)

This confirms that the admin account has a `teachers` row but NO corresponding `auth.users` row — which is expected for accounts created via `signup` or `add-teacher` (neither creates Auth users).

### Recommendation for Step 1

Before proceeding to fixes, run this query in Supabase SQL Editor to confirm the systemic pepper status:

```sql
-- Test if pepper rotation is the cause: compare hash of known passwords
-- For ANY single account whose password you know, check if login succeeds
```

A simpler test: try logging in with any **other** account whose password you know. If ALL accounts fail with "Invalid credentials", the pepper has been rotated. If only `umohyeneabasi@gmail.com` fails, it's an isolated password issue.

---

## Step 2: System-Wide teachers/Auth Consistency Enumeration

I cannot run the database query directly from this environment. Please run the following SQL in your Supabase SQL Editor:

```sql
SELECT t.id, t.email, t.role, t.is_active, t.email_verified,
       (au.id IS NOT NULL) AS has_auth_user,
       CASE
         WHEN t.role = 'admin' AND t.email_verified = false THEN 'signup-only (needs activation)'
         WHEN t.role = 'admin' THEN 'signup or activated'
         ELSE 'added by admin'
       END AS likely_creation_path
FROM teachers t
LEFT JOIN auth.users au ON au.email = t.email
ORDER BY t.role, t.email;
```

### Expected Pattern (from code analysis):

| Creation Path | teachers row? | Auth user? | Recovery works? |
|---------------|---------------|------------|-----------------|
| [`signup`](supabase/functions/signup/index.ts) alone | ✅ Yes | ❌ No | ❌ Fails "Auth user not found" |
| [`signup`](supabase/functions/signup/index.ts) + [`activate`](supabase/functions/activate/index.ts) | ✅ Yes | ✅ Yes | ✅ Works |
| [`add-teacher`](supabase/functions/add-teacher/index.ts) | ✅ Yes | ❌ No | ❌ Fails "Auth user not found" |
| [`activate`](supabase/functions/activate/index.ts) (teacher) | ✅ Yes | ✅ Yes | ✅ Works |

**Every account that went through `signup` (without activation) or `add-teacher` will fail password recovery.** This is not a data corruption issue — it's a design gap in the code.

---

## Step 3: Systemic Fix Recommendations

### Root Cause

The functions [`signup/index.ts`](supabase/functions/signup/index.ts) and [`add-teacher/index.ts`](supabase/functions/add-teacher/index.ts) create `teachers` rows but **never create Supabase Auth users**. The only function that creates Auth users is [`activate/index.ts`](supabase/functions/activate/index.ts) (line 83).

### Recommended Fix A: One-Time Backfill Script

Create a Supabase Auth user for every `teachers` row without a matching `auth.users` entry:

```sql
-- First: identify all affected accounts
SELECT t.id, t.email, t.role
FROM teachers t
LEFT JOIN auth.users au ON au.email = t.email
WHERE au.id IS NULL;
```

Then for each account, create an Auth user via the Supabase Management API or a one-time Edge Function:

```typescript
// Pseudocode for the backfill Edge Function
for each affected_teacher:
  // Create Auth user with random placeholder password
  // The password doesn't need to match — login uses teachers.password_hash
  const { data, error } = await supabase.auth.admin.createUser({
    email: teacher.email,
    password: crypto.randomUUID(),  // placeholder, never used for login
    email_confirm: true,
  });
```

**Why a placeholder password is safe:**
- The [`login/index.ts`](supabase/functions/login/index.ts) function does NOT use Supabase Auth — it uses `teachers.password_hash` with bcrypt+pepper
- The [`recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts) and [`admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts) functions call `updateUserById()` to **set** the password during recovery — they never need to verify the Auth user's password
- The [`verify-email/index.ts`](supabase/functions/verify-email/index.ts) function generates magic links via `generateLink()` which also doesn't need the password

The Auth user is only used as a **target for password updates** during recovery. A random placeholder password is perfectly safe.

### Recommended Fix B: Code Fix to Prevent Recurrence

Modify [`signup/index.ts`](supabase/functions/signup/index.ts) and [`add-teacher/index.ts`](supabase/functions/add-teacher/index.ts) to create Supabase Auth users at the same time they create `teachers` rows.

#### Fix for `signup/index.ts`

After line 130 (teacher insert succeeds), add:

```typescript
// Create Supabase Auth user for recovery flow compatibility
const { error: authCreateError } = await supabase.auth.admin.createUser({
  email: admin_email,
  password: crypto.randomUUID(), // placeholder — login uses bcrypt+pepper
  email_confirm: true,
});
// Non-fatal: log warning but don't block signup
if (authCreateError) {
  console.warn("[signup] Failed to create Auth user for", admin_email, authCreateError);
}
```

Also create an Auth user for the recovery admin teacher (after line 161).

#### Fix for `add-teacher/index.ts`

After line 195 (teacher insert succeeds), add:

```typescript
// Create Supabase Auth user for recovery flow compatibility
const { error: authCreateError } = await supabase.auth.admin.createUser({
  email,
  password: crypto.randomUUID(), // placeholder — login uses bcrypt+pepper
  email_confirm: true,
});
// Non-fatal: log warning but don't block teacher creation
if (authCreateError) {
  console.warn("[add-teacher] Failed to create Auth user for", email, authCreateError);
}
```

### Why Backfill Alone Is Not Enough

Without Fix B, every new account created via `signup` or `add-teacher` going forward will continue to have the same gap. The backfill fixes existing accounts; the code fix prevents recurrence.

---

## Summary Table

| Issue | Status | Fix |
|-------|--------|-----|
| `umohyeneabasi@gmail.com` login fails "Invalid credentials" | Password mismatch (Path B). Likely wrong password OR PASSWORD_PEPPER changed systemically. | Confirm pepper hasn't changed → reset password |
| `umohyeneabasi@gmail.com` recovery fails "Auth user not found" | ✅ Confirmed: no Auth user for this email | Backfill + code fix |
| All accounts from `signup` without activation | ❌ No Auth user (expected, code gap) | Backfill + code fix |
| All accounts from `add-teacher` | ❌ No Auth user (expected, code gap) | Backfill + code fix |
| All accounts from `activate` | ✅ Auth user exists | No fix needed |

### Files Referenced

| File | Relevance |
|------|-----------|
| [`supabase/functions/login/index.ts`](supabase/functions/login/index.ts) | Login function — bcrypt compare path |
| [`supabase/functions/signup/index.ts`](supabase/functions/signup/index.ts) | Signup — NO Auth user creation (fix needed) |
| [`supabase/functions/add-teacher/index.ts`](supabase/functions/add-teacher/index.ts) | Add teacher — NO Auth user creation (fix needed) |
| [`supabase/functions/activate/index.ts`](supabase/functions/activate/index.ts) | Activation — creates Auth user correctly |
| [`supabase/functions/admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts) | Recovery — "Auth user not found" at line 110 |
| [`supabase/functions/recovery-reset-password/index.ts`](supabase/functions/recovery-reset-password/index.ts) | Recovery — "Auth user not found" at line 99 |
| [`supabase/functions/_shared/validate_token.ts`](supabase/functions/_shared/validate_token.ts) | JWT/token_version validation |
| [`lib/core/services/auth_service.dart`](lib/core/services/auth_service.dart) | Client-side auth service |
