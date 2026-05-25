# ClassAI Roadmap Compliance Audit — `roadmap_gaps.md`

> **Audit Date**: 2026-05-20  
> **Scope**: All roadmap files under [`ClassAI MarkDown Files/`](ClassAI%20MarkDown%20Files/) (Phase 0–8, including `Done/` subfolder) vs. current codebase at [`c:/Users/Yene/classai`](.)  
> **Methodology**: File existence, class/method/UI presence, stub/placeholder detection, architectural comparison  
> **Total Gaps Found**: **10**  

---

## Phase 0 (Done) — Database Foundation

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 1 | *None* — Database foundation fully implemented. Schema at version 12 (evolved beyond Phase 0's initial v1). pubspec.yaml, environment specs, backend contract all present. | [`lib/core/database/database.dart`](lib/core/database/database.dart) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 1 (Done) — Database Tables + Directory Structure

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| — | *None* — All core tables (Schools, Teachers, Subjects, Lessons, Exams, SecurityConfig, ProgressLogs) exist. Directory structure matches spec (core/constants, core/theme, core/database/tables, core/utils, features/, models/, router/). AppConstants, CurriculumTypes, AppTheme all present. | [`lib/core/database/tables/`](lib/core/database/tables/) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 1B (Done) — Extended Tables

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| — | *None* — VersionHashes, SyncQueue, Conflicts, PaymentEvents, RecoveryCodes, PendingRecoveryRequests, TeacherDevices tables all exist. FTS5 search implemented. Extras beyond spec: PdfCache, TeacherSubjects, Terms, VaultItems, SchemeGenerationQueue, SchemeOfWork, SyncQueueSnapshot. | [`lib/core/database/tables/`](lib/core/database/tables/) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 1C (Done) — Bootstrapper + Tests

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| — | *None* — [`main.dart`](lib/main.dart) is fully implemented with Supabase init, Sentry, deep link handling, Riverpod, GoRouter, DatabaseBootstrapper. Test directory exists with all specified test files. | [`lib/main.dart`](lib/main.dart) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 2 — Encryption

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 1 | **AES-KWP replaced with AES-GCM for key wrapping**: The roadmap specified `wrapKey`/`unwrapKey` sync methods using AES-KWP that throw `UnsupportedError`. The actual implementation uses `wrapKeyAesGcm`/`unwrapKeyAesGcm` (async, AES-GCM-based, fully working). This is functionally *better* but diverges from the roadmap spec. | [`lib/core/utils/encryption_utils.dart`](lib/core/utils/encryption_utils.dart:100) | Low |
| 2 | **`SecurityService.authenticateWithBiometric` formatting issue**: Method body has an extra blank line at the start (minor code style). | [`lib/core/services/security_service.dart`](lib/core/services/security_service.dart:27) | Low |

**Status**: ⚠️ **2 gaps** — Low severity; functional equivalent or better

---

## Phase 3 — Auth Flow

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 3 | **Auth state machine states not verified in provider**: The roadmap specifies `AuthState` enum with 7 states (`uninitialized`, `checkingLocalAuth`, `offlineLoginAttempt`, `onlineLoginRequired`, `authenticated`, `accountDeactivated`, `emergencySaving`). The provider file exists at [`lib/features/auth/providers/auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) but the exact state transitions were not verified against the roadmap's flow diagram. | [`lib/features/auth/providers/auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) | Medium |

**Status**: ⚠️ **1 gap** — Medium severity; likely matches but needs verification

---

## Phase 4 — Sync

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| — | *None* — SyncService (885 lines), MergeEngine (195 lines), merge strategies, topological push, conflict detection, emergency queue all fully implemented. Test files present. | [`lib/core/services/sync_service.dart`](lib/core/services/sync_service.dart) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 5 — AI Service

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 4 | **AiService uses Supabase Edge Functions instead of direct Dio calls**: The roadmap specifies direct HTTP calls to DeepSeek/Gemini APIs via `dio` with certificate pinning (`dio_interceptor_certificate_pinning`). The actual [`AiService`](lib/core/services/ai_service.dart:8) uses `SupabaseClient.functions.invoke('deepseek-proxy')` / `'gemini-proxy'` instead. No Dio dependency, no certificate pinning, no retry interceptor. | [`lib/core/services/ai_service.dart`](lib/core/services/ai_service.dart:36) | **High** |
| 5 | **No `dio_interceptor_certificate_pinning` dependency**: The roadmap specifies this package for certificate pinning. The actual `pubspec.yaml` does not include it (since Dio is not used). | [`pubspec.yaml`](pubspec.yaml) | Medium |
| 6 | **AiService `_encrypt` method signature differs**: Roadmap spec shows `_encrypt` as sync returning `{'encrypted': true, 'content_hash': ..., 'raw': parsed}` with a fallback. Actual code is properly async and truly encrypts via `EncryptionUtils.encryptAesGcm`. Better implementation, but diverges from spec. | [`lib/core/services/ai_service.dart`](lib/core/services/ai_service.dart:62) | Low |

**Status**: 🔴 **3 gaps** — 1 High severity (architecture divergence)

---

## Phase 6 — UI

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| — | *None* — PlatformHelper, SyncIndicator, CreditCounter, ConflictBanner, DashboardScreen (EditorLayout + ReaderLayout), ConflictResolutionScreen, AppRouter (GoRouter with all routes), dashboard providers all fully implemented. | [`lib/features/dashboard/screens/dashboard_screen.dart`](lib/features/dashboard/screens/dashboard_screen.dart) | ✅ Complete |

**Status**: ✅ **Complete** — No gaps

---

## Phase 7 — Admin + Payments

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 7 | **Paystack secret key placeholder**: [`payment_service.dart`](lib/core/services/payment_service.dart) contains `sk_REPLACE_WITH_SECRET_KEY` as the Paystack secret key — a placeholder, not a real key. Payment integration will fail in production. | [`lib/core/services/payment_service.dart`](lib/core/services/payment_service.dart) | **Critical** |
| 8 | **Vault tier-gating is concept-only**: The vault publisher screen conditionally enables publishing for Standard+ tiers, but since no payment integration is connected (see #7), tier-gated access is effectively non-functional. | [`lib/features/vault/screens/vault_publisher_screen.dart`](lib/features/vault/screens/vault_publisher_screen.dart) | Medium |

**Status**: 🔴 **2 gaps** — 1 Critical, 1 Medium

---

## Phase 8 — Polish, Performance, Nigerian Adaptation

| # | Gap Description | File / Location | Severity |
|---|----------------|-----------------|----------|
| 9 | **SMS OTP service is completely stubbed**: [`sms_otp_service.dart`](lib/core/services/sms_otp_service.dart) exists but **all methods return placeholder values** (`sent: false`, `false`). The Termii/BulkSMS Nigeria integration is not implemented. The UI screen at [`sms_otp_screen.dart`](lib/features/auth/screens/sms_otp_screen.dart) exists but calling the service will always fail. | [`lib/core/services/sms_otp_service.dart`](lib/core/services/sms_otp_service.dart) | **Critical** |
| 10 | **USSD recovery is concept-only**: [`ussd_recovery_service.dart`](lib/core/services/ussd_recovery_service.dart) implements the full menu flow (reset password, get activation code, account status) and local code generation/verification, but no actual telco/USSD gateway integration. The Supabase Edge Function at [`supabase/functions/ussd-recovery/index.ts`](supabase/functions/ussd-recovery/index.ts) exists but requires telco agreement to be useful. | [`lib/core/services/ussd_recovery_service.dart`](lib/core/services/ussd_recovery_service.dart) | Medium |

**Status**: 🔴 **2 gaps** — 1 Critical, 1 Medium

---

## Summary

### Gap Count by Phase

| Phase | Gaps | Critical | High | Medium | Low | Status |
|-------|------|----------|------|--------|-----|--------|
| 0 — Database Foundation | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 1 — Database Tables | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 1B — Extended Tables | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 1C — Bootstrapper | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 2 — Encryption | 2 | 0 | 0 | 0 | 2 | ⚠️ Minor divergence |
| 3 — Auth Flow | 1 | 0 | 0 | 1 | 0 | ⚠️ Needs verification |
| 4 — Sync | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 5 — AI Service | 3 | 0 | **1** | 1 | 1 | 🔴 Architecture change |
| 6 — UI | 0 | 0 | 0 | 0 | 0 | ✅ Complete |
| 7 — Admin + Payments | 2 | **1** | 0 | 1 | 0 | 🔴 Missing real key |
| 8 — Polish/Nigerian | 2 | **1** | 0 | 1 | 0 | 🔴 SMS OTP stubbed |
| **Total** | **10** | **2** | **1** | **4** | **3** | |

### Most Critical Missing Features

1. **🔴 SMS OTP Service — Completely Stubbed** ([`lib/core/services/sms_otp_service.dart`](lib/core/services/sms_otp_service.dart))  
   The roadmap (Phase 8) requires SMS OTP via Termii/BulkSMS Nigeria as an alternative to email OTP for activation and recovery. The entire service returns placeholder values. The UI screen exists but is non-functional. This blocks a key Nigerian-market requirement.

2. **🔴 Paystack Secret Key — Placeholder** ([`lib/core/services/payment_service.dart`](lib/core/services/payment_service.dart))  
   The roadmap (Phase 7) requires Paystack payment integration for subscription plans (Basic/Standard/Elite at ₦49,999/₦99,999/₦249,999). The integration code is structurally complete, but the `sk_REPLACE_WITH_SECRET_KEY` placeholder means no real payment can be processed. This blocks monetization.

3. **🟡 AI Service Architecture Divergence** ([`lib/core/services/ai_service.dart`](lib/core/services/ai_service.dart))  
   The roadmap (Phase 5) specifies direct DeepSeek/Gemini API calls via `dio` with certificate pinning. The actual implementation routes through Supabase Edge Function proxies. This changes the deployment model (requires Supabase-managed API keys instead of client-side keys) and removes the retry interceptor and certificate pinning that the roadmap required for security.

### Recommendations by Priority

1. **Implement SMS OTP** — Integrate Termii or BulkSMS Nigeria API in [`sms_otp_service.dart`](lib/core/services/sms_otp_service.dart)
2. **Replace Paystack placeholder** — Set the real `sk_live_...` key in [`payment_service.dart`](lib/core/services/payment_service.dart) (or use environment variable injection)
3. **Verify auth state machine** — Confirm [`auth_provider.dart`](lib/features/auth/providers/auth_provider.dart) implements all 7 states from the roadmap flow diagram
4. **Evaluate AI architecture** — Decide whether to keep Supabase Edge Function proxies (more secure, server-managed keys) or switch to direct Dio calls as per roadmap (simpler, fewer moving parts)

---

*Audit generated by comparing [`c:/Users/Yene/classai/ClassAI MarkDown Files/`](ClassAI%20MarkDown%20Files/) (15 roadmap files) against actual source code in [`c:/Users/Yene/classai/`](.). All file links are relative to the project root.*
