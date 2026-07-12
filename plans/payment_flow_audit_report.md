# ClassAI Payment Flow Security Audit Report

**Date:** 2026-07-12  
**Auditor:** Roo (Security Architect)  
**Scope:** Full subscription upgrade lifecycle (teacher request + admin payment)  

---

## Payment Lifecycle Trace

### Flow A — Teacher "Request Upgrade"

```
[Teacher UI] → showUpgradeRequestDialog()
            → UpgradeRequestService.sendUpgradeRequest(accessToken, requestedTier)
            → Edge Function: request-upgrade (POST, verify_jwt=true)
                → validateTokenVersion() → extracts teacher_id, school_id
                → INSERT into upgrade_requests (UNIQUE teacher_id + request_date)
                → If duplicate: returns { already_requested: true }
                → Query school admins → send Gmail via nodemailer
                → Returns { success: true }
```

### Flow B — Admin Payment

```
[Admin UI] → PaymentScreen → _initializePayment()
           → PaymentService.initializePayment(email, amount, plan, schoolId)
               → INSERT into local payment_events (confirmedByWebhook: false)
               → POST https://api.paystack.co/transaction/initialize (USING SECRET KEY ON CLIENT)
               → Opens Paystack checkout URL
           → _pollForPayment() [10 tries × 30s = 5 min]
               → PaymentService.verifyPayment(reference)
                   → GET https://api.paystack.co/transaction/verify (USING SECRET KEY ON CLIENT)
               → If confirmed:
                   → PaymentService.confirmPayment(reference, plan, schoolId)
                       → Edge Function: confirm-payment (POST, NO JWT VERIFICATION)
                           → Server-to-server Paystack verify
                           → CREATE activation_codes row (used: false)
                           → UPDATE schools SET subscription_tier, expiry_date, activation_code
                           → UPDATE activation_codes SET used=true (where code=... AND used=false)
                           → Send activation email (best-effort)
                       → Client: INSERT/REPLACE into local schools table
                       → refreshSchoolFromDb() → authProvider state updated
```

### Flow C — Admin Redeem Activation Code

```
[Admin UI] → _RedeemCodeDialog → _handleSubmit()
           → Edge Function: redeem-activation (POST, verify_jwt=false, NO AUTH CHECK)
               → Validates code format
               → SELECT from activation_codes WHERE code=... AND used=false
               → Verifies school_name match
               → Verifies caller email matches an admin at the school
               → UPDATE schools SET subscription_tier, expiry_date, activation_code
               → UPDATE activation_codes SET used=true
           → Client: updateSubscriptionFields() locally
           → refreshSchoolFromDb()
```

---

## Findings

### Critical (payment will silently fail, data loss, or security breach)

| # | File | Line(s) | Issue | Fix |
|---|------|---------|-------|-----|
| C1 | [`lib/core/constants/paystack_keys.dart`](lib/core/constants/paystack_keys.dart) | 2 | **Hardcoded Paystack secret key** — `sk_test_33ebcdf9b2ad8ed3b1bbe406a36d57a91e3e38dc` is a literal string in the Dart source. This key is bundled into the app binary, extractable via decompilation, and committed to Git. Anyone who obtains it can initiate/verify arbitrary Paystack transactions. | Remove the key from source. Store it server-side only (Edge Functions via `Deno.env.get("PAYSTACK_SECRET_KEY")`). The Flutter client must call a secure proxy endpoint instead of calling Paystack directly. |
| C2 | [`lib/core/services/payment_service.dart`](lib/core/services/payment_service.dart) | 36–39, 80–90 | **Client-side Paystack API calls with secret key** — Both [`initializePayment()`](lib/core/services/payment_service.dart:62) (line 80) and [`verifyPayment()`](lib/core/services/payment_service.dart:103) (line 104) call Paystack directly from the Flutter client using the hardcoded secret key via Dio. This exposes the secret key to anyone inspecting network traffic or decompiling the app. | Delegate all Paystack API calls to server-side Edge Functions. Initialize via a new `proxy-init-payment` function, verify via `confirm-payment` only. Never embed the secret key in the client. |
| C3 | [`supabase/functions/confirm-payment/`](supabase/functions/confirm-payment/) | (no config.toml) | **No config.toml + no JWT verification** — The [`confirm-payment`](supabase/functions/confirm-payment/index.ts) function has NO config.toml at all (defaults to `verify_jwt=false`). The code never validates the caller's JWT or role. **Any network actor** (authenticated teacher, unauthenticated attacker) who knows the function URL can call it with any `school_id` and upgrade any school. | Add `config.toml` with `verify_jwt=true`. Add server-side JWT validation + role check (admin-only) + school_id ownership verification. |
| C4 | [`supabase/functions/redeem-activation/config.toml`](supabase/functions/redeem-activation/config.toml) | 1–2 | **No JWT verification on redeem-activation** — `verify_jwt=false` means **no authentication required**. The function itself never checks the caller's identity or role. An attacker can call this endpoint with a brute-forced or leaked activation code and subscribe any school. | Set `verify_jwt = true`. Add server-side role check (admin-only). The Flutter client must pass the admin's JWT. |
| C5 | [`supabase/functions/confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts) | 80 | **`school_id` from request body, unverified** — The function reads `school_id` directly from the request body and operates on it without verifying the caller owns or belongs to that school. Combined with C3, an attacker can upgrade any school whose ID they know. | Extract `school_id` from validated JWT claims (as `request-upgrade` does). If the admin needs to act on a different school, verify cross-school authorization server-side. |
| C6 | [`supabase/functions/paystack-webhook/index.ts`](supabase/functions/paystack-webhook/index.ts) | 86–217 | **Webhook does NOT update the school record** — The [`paystack-webhook`](supabase/functions/paystack-webhook/index.ts) function cryptographically verifies the Paystack signature (good) and generates an activation code + sends an email, but **never updates** `schools.subscription_tier` or marks the activation code as `used: true`. The school is never upgraded via the webhook path; it relies entirely on the client calling `confirm-payment`. If the client crashes after checkout but before calling `confirm-payment`, the payment is permanently lost even though Paystack recorded it. | After verifying the webhook, the function should atomically create the activation code AND update the school's subscription tier. The activation code should also be marked as used immediately since the webhook is the authoritative payment confirmation. |
| C7 | [`supabase/functions/paystack-webhook/index.ts`](supabase/functions/paystack-webhook/index.ts) | 163–196 | **Activation code created but never marked as used by webhook** — The webhook inserts an activation code with `used: false` and never updates it. This creates orphaned, redeemable activation codes in the database for every Paystack payment. | Either mark the code as `used: true` in the webhook, or don't create a code at all — let the `confirm-payment` client call do it. The dual-path (webhook creates, client confirms) is inherently racy. |

### High (payment works but edge case is broken)

| # | File | Line(s) | Issue | Fix |
|---|------|---------|-------|-----|
| H1 | [`supabase/functions/confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts) | 166–234 | **No rollback for partial failure** — The function performs 3 sequential state mutations: (1) create activation code (line 168), (2) update school tier (line 203), (3) mark code as used (line 220). If step 2 or 3 fails, the activation code is orphaned (`used: false`), the school is NOT upgraded, but Paystack already confirmed the payment. No compensating transaction, dead-letter queue, or retry mechanism exists. | Wrap steps 1–3 in a database transaction (Supabase RPC with `BEGIN`/`COMMIT`). If that's not possible, implement a compensating action: on step 2 failure, delete the orphaned code. Better: use a single RPC that atomically creates the code and updates the school. |
| H2 | [`supabase/functions/confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts) | 218–225 | **Race condition on activation code** — The query at line 224 uses `WHERE code = ... AND used = false` to protect against double-redeem, but the code was just created a few lines earlier by this same request. In a concurrent scenario where `confirm-payment` is called twice for the same `school_id`, both requests could create separate codes, both update the school (the second overwrites the first), and both try to mark their code as used — both succeed. This could result in the school getting two "paid" upgrades for a single user action. | Use a unique constraint on `school_id` + `tier` for active subscriptions, or implement a distributed lock per `school_id`. Better: deduplicate by `reference` — check if a code was already generated for this Paystack reference before creating one. |
| H3 | [`lib/features/payment/screens/payment_screen.dart`](lib/features/payment/screens/payment_screen.dart) | 632–648 | **`_resumePendingPayments` only processes first successful payment** — When the payment screen loads, it iterates ALL unconfirmed payments but `break`s after the first confirmed one. If there are 2+ pending payments from separate sessions, the rest are silently ignored. They remain in `payment_events` with `confirmedByWebhook=false` forever. | Either process all pending confirmations, or add a cleanup mechanism for aged unconfirmed records. |
| H4 | [`supabase/functions/redeem-activation/index.ts`](supabase/functions/redeem-activation/index.ts) | 13–160 | **Race condition on activation code** — The [`redeem-activation`](supabase/functions/redeem-activation/index.ts) function selects a code with `used=false` (line 60), then later updates it to `used=true` (line 131). Between these two operations, another concurrent request could also select the same code. Both would pass the `used=false` check. The second update would succeed (SET used=true WHERE code=X AND used=false fails for the second, but the school update at line 112 already ran). | Use a pessimistic lock (`SELECT ... FOR UPDATE`) or implement the school-update and code-mark-used atomically in a single RPC. The `WHERE used=false` guard on the UPDATE (line 136) partially mitigates this, but the school was already updated at line 112 before checking if the code marking failed. Restructure: UPDATE code first (with WHERE used=false), check affected rows, then UPDATE school. |
| H5 | [`lib/features/admin/screens/admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart) | 1233–1258 | **`_RedeemCodeDialog` error handling extracts error text from exception string** — Lines 1283–1291 do `errorStr.contains('already used activation code')` which is fragile and locale-dependent. If the server error message changes, the UI will show a generic error instead of the specific one. | Parse the `FunctionException.details` map for structured error fields, or check the HTTP status code from the response. |
| H6 | [`supabase/functions/paystack-webhook/index.ts`](supabase/functions/paystack-webhook/index.ts) | 119–121 | **Webhook silently ignores non-charge.success events** — Returns `{ success: true }` for any non-charge.success event. This is correct Paystack webhook behavior, but there's no logging or monitoring. If Paystack starts sending `charge.failed` events after a prior `charge.success` (rare but possible with retries), the webhook would silently accept it without alerting. | Log all events at info level and alert on `charge.failed` for references that previously succeeded. |

### Medium (user experience / robustness)

| # | File | Line(s) | Issue | Fix |
|---|------|---------|-------|-----|
| M1 | [`lib/features/payment/screens/payment_screen.dart`](lib/features/payment/screens/payment_screen.dart) | 752–762 | **Polling timeout message offers no recovery** — "Your payment may still have processed. Please check your email for a receipt." After 5 minutes of polling, the user gets no way to retry. They must navigate away and come back (which triggers `_resumePendingPayments`). | Add a "Check Payment Status" button that manually retries `verifyPayment` + `confirmPayment`. Or auto-retry on next app open with better UX. |
| M2 | [`supabase/functions/confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts) | 249–257 | **Duplicate response fields** — Returns both `activation_code` and `code` (same value), `subscription_tier` and `tier`, `expiry_date` and `expiry`. This inconsistency makes client parsing ambiguous. | Pick one canonical key per field. Document the response schema. |
| M3 | [`lib/core/services/payment_service.dart`](supabase/functions/payment_service.dart) | 162–173 | **Local school insert uses placeholder values** — When the payment confirms, the client inserts/replaces the school row with `schoolName: ''` and `shortCode: ''`. These are placeholder values that will be overwritten by the next sync cycle, but in the meantime the UI shows an empty school name. | After confirming payment, sync-pull from the server to get the authoritative school record instead of inserting blanks. |
| M4 | [`supabase/functions/request-upgrade/index.ts`](supabase/functions/request-upgrade/index.ts) | 151–175 | **Admin email lookup failure silently degrades** — If the admin lookup query fails, the function logs the error but returns success as if the email was sent. The teacher sees "Request sent!" but no admin receives a notification. | Return a 207 Multi-Status or at minimum include a `warning` field in the response so the client can show "Request recorded but notification may not have been delivered." |
| M5 | [`supabase/functions/confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts) | 236–246 | **Activation email failure silently caught** — The empty `catch {}` block on line 245 silently discards email errors. Same pattern in `paystack-webhook` at line 200. While email is best-effort, the failure should be logged with sufficient context to debug. | Log the error details (to address, error message). Add a `warning` field to the response if email fails. |
| M6 | [`lib/core/services/payment_service.dart`](lib/core/services/payment_service.dart) | 141–149 | **`confirmPayment` passes no JWT to the Edge Function** — The call to `confirm-payment` at line 142 does not include any `Authorization` header or JWT. Even though the endpoint currently has no auth (C3), when auth is added the client must pass the admin's JWT. | Include `'Authorization': 'Bearer ${authService.currentJwt}'` in the headers. |
| M7 | [`lib/core/widgets/upgrade_request_dialog.dart`](lib/core/widgets/upgrade_request_dialog.dart) | 178–184 | **UI redirects admin to `/payment` but doesn't enforce role server-side** — The dialog checks `role == 'admin'` and redirects. This is a UI-only guard. The `request-upgrade` function itself doesn't enforce that only teachers can call it; it just processes any valid JWT. | Add a role check in the `request-upgrade` Edge Function: if the caller's role is `admin`, return a 403 error since admins should use the payment screen directly. |

---

## Overall Health Summary

The payment flow has a **critical security architecture flaw**: the Paystack secret key is hardcoded in the Flutter client source code and used to make direct Paystack API calls (`initialize` and `verify`) from the mobile app. Any extracted key allows fraudulent transaction initiation and verification. Both `confirm-payment` and `redeem-activation` Edge Functions lack JWT authentication entirely, meaning any network actor who discovers their URLs can arbitrarily upgrade school subscriptions or redeem codes. The `paystack-webhook` cryptographically verifies its Paystack signature (good) but fails to update the school's subscription record, making it purely a notification endpoint — the actual upgrade depends entirely on the client successfully calling `confirm-payment` after checkout, leaving a window where a payment succeeds on Paystack but never materializes in the app. The `redeem-activation` function has a race condition window between checking and marking an activation code, and none of the state-mutation sequences use database transactions, so partial failures can orphan activation codes. On the positive side, the `request-upgrade` flow is well-designed with JWT validation, token-version checking, and database-level deduplication. The client-side polling and `_resumePendingPayments` recovery mechanism provides reasonable crash resilience for normal use, and the local school record is updated immediately after confirmation.
