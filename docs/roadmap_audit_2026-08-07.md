# ClassAI Roadmap Audit

Date: 2026-08-07

Scope: repo planning docs, roadmap files, spec notes, and the current codebase. I checked `README.md`, `ClassAI MarkDown Files/`, `plans/`, `_previous_audits/`, and planning notes in code comments. I did not find a pre-existing `PROJECT.md`, `ROADMAP.md`, `CHANGELOG.md`, or a populated `docs/` planning folder before writing this report.

## 1. Roadmap vs. reality

The main roadmap lives in `ClassAI MarkDown Files/`. The repo also has a set of supporting plans and audits under `plans/` and `_previous_audits/`. `README.md` is still the default Flutter starter text and does not add product-specific planning detail.

| Planned phase / doc | Status | Evidence in code | What is missing or different |
|---|---|---|---|
| Phase 0 - Build contract / foundation (`ClassAI MarkDown Files/Done/phase_00_contract.md`) | Implemented | `lib/main.dart`, `lib/core/constants/app_constants.dart`, `pubspec.yaml`, `lib/core/database/database.dart` | The repo has the expected foundation pieces and platform setup. |
| Phase 1 - Project skeleton + database core (`ClassAI MarkDown Files/Done/phase_01_contract.md`) | Implemented | `lib/core/database/tables/schools.dart`, `teachers.dart`, `subjects.dart`, `lessons.dart`, `exams.dart`, `security_config.dart`, generated `lib/core/database/database.g.dart` | Core schema and database wiring are present. |
| Phase 1B - Extended tables (`ClassAI MarkDown Files/Done/phase_01B_contract .md`) | Implemented | `lib/core/database/tables/version_hashes.dart`, `sync_queue.dart`, `conflicts.dart`, `payment_events.dart`, `recovery_codes.dart`, `pending_recovery_requests.dart`, `teacher_devices.dart`, `vault_items.dart`, `scheme_of_work.dart`, `sync_queue_snapshot.dart`, `field_conflict_history.dart` | Extended local tables exist. |
| Phase 1C - Bootstrapper + tests (`ClassAI MarkDown Files/Done/phase_01C_contract.md`) | Implemented | `lib/main.dart`, `test/database/schema_test.dart`, `test/database/db_encryption_bootstrap_test.dart`, `lib/core/database/database_encryption_bootstrap.dart` | Bootstrap and test coverage are present. |
| Phase 2 - Encryption + credit core (`ClassAI MarkDown Files/phase_02_encryption.md`, plus `phase_02B_encryption.md`, `phase_02C_encryption.md`, `phase_02D_encryption.md`) | Partially implemented | `lib/core/utils/encryption_utils.dart`, `lib/core/services/security_service.dart`, `lib/core/services/credit_service.dart`, `lib/core/database/daos/security_config_dao.dart` | Encryption and credit logic exist, but the roadmap's exact crypto shape is not what the code uses. The audit in `_previous_audits/roadmap_gaps.md` notes that `wrapKey`/`unwrapKey` were replaced by AES-GCM-based wrapping, which is different from the original spec. |
| Phase 3 - Auth flow + online core (`ClassAI MarkDown Files/phase_03_auth.md`, `phase_03B_auth.md`) | Partially implemented | `lib/core/services/auth_service.dart`, `lib/features/auth/providers/auth_provider.dart`, `lib/features/auth/screens/login_screen.dart`, `signup_screen.dart`, `admin_recovery_screen.dart`, `teacher_recovery_dialog.dart` | The auth stack exists, but I did not verify the exact seven-state flow from the roadmap. SMS OTP fallback is still stubbed in `lib/core/services/sms_otp_service.dart`, so the full recovery path is not finished. |
| Phase 4 - Sync engine (`ClassAI MarkDown Files/phase_04_sync.md`, `phase_04B_sync.md`) | Implemented | `lib/core/services/sync_service.dart`, `lib/core/services/merge_engine.dart`, `supabase/functions/sync-pull/index.ts`, `supabase/functions/sync-push/index.ts`, `test/sync/sync_fakes.dart` | No material gap found in the evidence I checked. |
| Phase 5 - AI service + lesson/exam generation (`ClassAI MarkDown Files/phase_05_ai.md`) | Partially implemented | `lib/core/services/ai_service.dart`, `lib/features/lesson/screens/lesson_editor_screen.dart`, `lib/features/exam/screens/exam_editor_screen.dart`, `lib/core/services/diagram_service.dart` | The generation path exists, but the roadmap asked for direct `dio` calls with certificate pinning. Current code routes AI requests through Supabase Edge Functions instead. |
| Phase 6 - UI dashboard + reader mode (`ClassAI MarkDown Files/phase_06_ui.md`) | Implemented | `lib/features/dashboard/screens/dashboard_screen.dart`, `lib/core/widgets/sync_indicator.dart`, `lib/core/widgets/credit_counter.dart`, `lib/core/widgets/conflict_banner.dart`, `lib/router/app_router.dart`, `lib/features/settings/screens/conflict_resolution_screen.dart` | Layout and navigation pieces are in place. |
| Phase 7 - Admin portal + vault + payments + export (`ClassAI MarkDown Files/phase_07_admin.md`, `phase_07B_admin.md`, `phase_07C_admin.md`) | Partially implemented | `lib/features/admin/screens/admin_dashboard_screen.dart`, `lib/features/vault/screens/vault_publisher_screen.dart`, `lib/features/payment/screens/payment_screen.dart`, `lib/core/services/payment_service.dart`, `supabase/functions/init-payment/index.ts` | The feature set exists, but production payment setup is not complete. `lib/main.dart` still contains a Paystack live-key TODO. |
| Phase 8 - Polish, performance, Nigerian adaptation, launch prep (`ClassAI MarkDown Files/phase_08_polish.md`) | Partially implemented | `lib/core/services/sms_otp_service.dart`, `lib/core/services/ussd_recovery_service.dart`, `lib/core/services/academic_calendar_service.dart`, `lib/core/database/tables/terms.dart`, `lib/core/services/vacuum_service.dart`, `lib/core/services/config_service.dart` | SMS OTP is explicitly stubbed. Some other Phase 8 items exist as real code, but several are still concept-level or support-level rather than a finished end-user flow. |
| Credit + preview/unlock plan (`plans/credit_preview_unlock_system.md`) | Partially implemented | `lib/features/lesson/screens/lesson_editor_screen.dart`, `lib/features/exam/screens/exam_editor_screen.dart`, `lib/core/services/credit_service.dart`, `lib/core/database/daos/security_config_dao.dart` | The preview/unlock path exists, but I did not verify every rule from the plan as fully enforced. |

Additional planning and investigation docs found:

| Document group | File paths | Reality |
|---|---|---|
| Security and sync audit reports | `plans/auth_security_audit_report.md`, `plans/payment_flow_audit_report.md`, `plans/sync_pipeline_audit_report.md`, `plans/schema_coverage_audit_report.md` | These are diagnostic documents, not product features. They map to real code areas, but they are reports rather than roadmap phases. |
| Test and integrity planning notes | `plans/data_integrity_audit_plan.md`, `plans/admin_auth_consistency_report.md`, `plans/diagnosis_report.md` | These are planning / validation docs. Some are backed by tests and services, but the docs themselves are not feature requirements. |
| Investigation notes | `plans/verify_loop_diagnosis.md`, `plans/updated_at_tiebreaker_investigation.md`, `plans/typing_undo_feasibility_report.md`, `_previous_audits/roadmap_gaps.md` | These are investigations and audits. They describe issues, not user-facing product scope. |

## 2. Skipped or abandoned work

| File path | What looks unfinished |
|---|---|
| `lib/core/services/sms_otp_service.dart` | The SMS OTP service is stubbed; every method returns placeholder values and the class says SMS OTP is currently disabled. |
| `lib/main.dart` | There is still a `TODO` to update the Paystack live key before launch. |
| `supabase/functions/init-payment/index.ts` | There is a `TODO` to replace test plan codes with production codes. |
| `lib/core/database/database.dart` | The migration comments still describe `sync_queue_snapshot`, `scheme_of_work`, and `scheme_generation_queue` as stub tables that were later expanded. |
| `lib/core/database/database_encryption_bootstrap.dart` | The plaintext-to-SQLCipher conversion path still contains `TEMP DEBUG` blocks marked for removal. |
| `lib/core/database/daos/pending_recovery_requests_dao.dart` | `teacherLocalId` is still written as a placeholder `0` until the teacher is known. |
| `supabase/functions/login/index.ts` | `offline_credits: 3` is still hard-coded as a placeholder and the comment says it should come from a credit table later. |
| `lib/features/settings/screens/conflict_resolution_screen.dart` | The merge path still has an "auto-union placeholder" comment, which suggests the merge UX is not fully finished. |
| `lib/core/database/tables/field_conflict_history.dart` | The table exists, but I found only schema creation/test references and no clear DAO/service usage. |

## 3. Features NOT in the roadmap but built anyway

| Feature | Where it lives | Relevance / 10 | Why |
|---|---|---:|---|
| Offline diagram generation and image caching | `lib/core/services/diagram_service.dart` | 7 | Useful for lesson content, but it is more of a teaching aid than a core school-management workflow. |
| One-time plaintext-to-SQLCipher database migration with backup retention | `lib/core/database/database_encryption_bootstrap.dart` | 8 | This is strong security hardening, but it is infrastructure rather than a teacher-facing feature. |
| Remote config cache for limits and feature flags | `lib/core/services/config_service.dart` | 6 | Helpful for rollout control and tier limits, but it sits behind the app rather than directly helping a teacher run class. |
| Custom API client with certificate-pinning support | `lib/core/services/http_client.dart` | 6 | Good security plumbing, but not a classroom workflow on its own. |
| Field conflict history table | `lib/core/database/tables/field_conflict_history.dart`, `lib/core/database/database.dart` | 5 | Useful for debugging sync problems, but I did not find evidence that teachers interact with it directly. |
| Legacy diagram storage compatibility methods | `lib/core/services/diagram_service.dart` | 3 | This is migration support for old data, not a new product capability. |

## 4. Suggestions - features Nigerian teachers might value

| Suggestion | Why it fits a Nigerian classroom |
|---|---|
| WAEC/NECO report-card templates | Many schools still need result formats that match local exam and reporting expectations, not generic export layouts. |
| Continuous assessment weight builder | Nigerian schools often use CA structures with school-specific weighting, so teachers need a quick way to configure those ratios. |
| SMS parent notices with low-data fallback | Some parents do not have reliable smartphones or steady data, so SMS is still practical for reminders and urgent updates. |
| Term-based timetable and calendar tools | The app already thinks in terms; teachers would benefit from a calendar that matches first, second, and third term workflows. |
| Offline attendance register with later sync | Internet can be unreliable, so attendance needs to work offline first and sync when connectivity returns. |
| Low-data sync mode | Compression and delayed background sync would reduce data cost, which matters in real day-to-day use. |
| Exam revision and past-question packs | WAEC, NECO, and other exam prep is a major classroom need, so built-in revision content would be highly relevant. |
| Bulk announcement lists for parents and guardians | Teacher communication often involves many parents at once, and a simple broadcast tool would save time. |

