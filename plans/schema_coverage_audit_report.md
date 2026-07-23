# Schema Coverage Audit Report

**Date:** 2026-07-22  
**Scope:** Every hardcoded table/column allowlist, default-value map, and column assumption in the codebase vs. live production schema  
**Method:** `information_schema` queries against live Supabase database (project ref: `zbqhxqnkoggckxoyoqox`)

---

## Table of Contents

1. [Category Legend](#1-category-legend)
2. [Table-Level Discrepancies](#2-table-level-discrepancies)
3. [Column-Level Discrepancies in Sync Pipeline](#3-column-level-discrepancies-in-sync-pipeline)
4. [Column-Level Discrepancies in Auth Functions](#4-column-level-discrepancies-in-auth-functions)
5. [Column-Level Discrepancies in Payment Functions](#5-column-level-discrepancies-in-payment-functions)
6. [KEY_MAP / PayloadCompressor Cross-Reference](#6-key_map--payloadcompressor-cross-reference)
7. [LESSON_DEFAULTS vs. Lessons Schema](#7-lesson_defaults-vs-lessons-schema)
8. [EXAM_DEFAULTS vs. Exams Schema](#8-exam_defaults-vs-exams-schema)
9. [VAULT_ITEMS_DEFAULTS vs. Vault Items Schema](#9-vault_items_defaults-vs-vault-items-schema)
10. [SCHEME_OF_WORK_DEFAULTS vs. Scheme of Work Schema](#10-scheme_of_work_defaults-vs-scheme-of-work-schema)
11. [FK Resolution Assumptions](#11-fk-resolution-assumptions)
12. [Summary: Confirmed Gaps Requiring Action](#12-summary-confirmed-gaps-requiring-action)
13. [Summary: Stale/Harmless Mismatches](#13-summary-staleharmless-mismatches)
14. [Summary: Uncertain / Needs Decision](#14-summary-uncertain--needs-decision)

---

## 1. Category Legend

| Category | Meaning |
|----------|---------|
| **🔴 CONFIRMED GAP** | Column/table referenced in code does NOT exist on server. Causes runtime error or silent data loss. |
| **🟡 STALE / HARMLESS** | Column/table doesn't exist server-side but code handles the absence gracefully (null default, fallback, etc.) |
| **🔵 UNCERTAIN / NEEDS DECISION** | May or may not be a problem; requires business-logic or design decision. |

---

## 2. Table-Level Discrepancies

### 2a. `_syncableTables` (Dart client, [`sync_service.dart:247-257`](lib/core/services/sync_service.dart:247))

List sent by client to sync-pull endpoint: `subjects, lessons, exams, progress_logs, vault_items, scheme_of_work, teachers, schools, payment_events`

**Server tables all exist** ✅ — All 9 tables are present in the live database.

### 2b. `SYNCABLE_TABLES` (sync-push, [`index.ts:656-662`](supabase/functions/sync-push/index.ts:656))

`lessons, exams, progress_logs, subjects, teachers, schools, scheme_of_work, vault_items, payment_events, credit_spend`

| Discrepancy | Status |
|---|---|
| `credit_spend` table does NOT exist on server | **🔴 CONFIRMED GAP** — No table with "credit" in the name exists in `public` schema |

### 2c. `adminTables` (sync-push, [`index.ts:680-689`](supabase/functions/sync-push/index.ts:680))

`teachers, schools, subjects, payment_events, app_config, pending_activations, activation_codes, admin_recovery_otps, verification_codes, recovery_codes`

| Discrepancy | Status |
|---|---|
| All 10 tables exist on server | ✅ All confirmed present |

### 2d. `scopedTables` (sync-pull, [`index.ts:97-107`](supabase/functions/sync-pull/index.ts:97))

`teachers, lessons, exams, subjects, scheme_of_work, vault_items, progress_logs, payment_events, schools`

| Discrepancy | Status |
|---|---|
| All 9 tables exist on server | ✅ All confirmed present |

### 2e. `audit_logs` referenced as syncable (Drift migration 13)

`audit_logs` table is defined in Drift local schema (migration 13) but does NOT exist on server.

| Discrepancy | Status |
|---|---|
| `audit_logs` used locally, not on server | **🟡 STALE / HARMLESS** — Already confirmed as local-only table. Not in any syncable list. |

---

## 3. Column-Level Discrepancies in Sync Pipeline

### 3a. `_upsertTeacherFromSync` ([`sync_service.dart:1536-1699`](lib/core/services/sync_service.dart:1536))

Columns read from remote `merged` map vs. actual `teachers` table schema:

| Code reads from `merged` | Server has column? | Status |
|---|---|---|
| `server_id` / `id` | ✅ `id` (UUID), `server_id` (text, nullable) | ✅ |
| `email` | ✅ `email` (text, not null) | ✅ |
| `teacher_name` | ✅ `teacher_name` (text, not null) | ✅ |
| `role` | ✅ `role` (text, not null) | ✅ |
| `school_id` | ✅ `school_id` (uuid, not null) | ✅ |
| `is_active` | ✅ `is_active` (boolean, not null) | ✅ |
| `force_password_reset` | ✅ `force_password_reset` (boolean) — **NOT in server schema!** | **🟡 STALE / HARMLESS** — Defaults to `false` |
| `password_hash_version` | ✅ `password_hash_version` (integer) — **NOT in server schema!** | **🟡 STALE / HARMLESS** — Defaults to `1` |
| `temp_password` | ✅ `temp_password` (text, nullable) | ✅ |
| `school_key_wrapped` / `school_master_key_wrapped` | ✅ server has `school_key_wrapped` (text, nullable) | **🟡 STALE / HARMLESS** — `school_key_wrapped` exists, `school_master_key_wrapped` used as fallback |
| `salt` | ✅ `salt` (text, nullable) | ✅ |
| `current_device_id` | ❌ **NO `current_device_id` on server** | **🟡 STALE / HARMLESS** — Server doesn't store this; defaults to `null` locally |
| `is_deleted` | ❌ **NO `is_deleted` on server `teachers`** | **🟡 STALE / HARMLESS** — Defaults to `false`; the server DELETE handler uses `deleted_at` instead |
| `created_at` | ✅ `created_at` (timestamptz, not null) | ✅ |
| `updated_at` | ✅ `updated_at` (timestamptz, not null) | ✅ |
| `last_modified_by` | ✅ `last_modified_by` (uuid, nullable) | ✅ |

### 3b. `_upsertSchoolFromSync` ([`sync_service.dart:1712-1769`](lib/core/services/sync_service.dart:1712))

| Code reads from `merged` | Server has column? | Status |
|---|---|---|
| `server_id` / `id` | ✅ | ✅ |
| `school_name` | ✅ | ✅ |
| `short_code` | ✅ | ✅ |
| `subscription_tier` | ✅ | ✅ |
| `active_curriculum` | ✅ | ✅ |
| `active_curriculum_version` | ✅ | ✅ |
| `total_seats` | ✅ | ✅ |
| `school_master_key_wrapped` / `school_key_wrapped` | ✅ `school_master_key_wrapped` exists. `school_key_wrapped` does NOT. | **🟡 STALE / HARMLESS** — Fallback works |
| `admin_recovery_email` | ✅ | ✅ |
| `admin_recovery_email_verified` | ✅ | ✅ |
| `expiry_date` | ✅ | ✅ |
| `activation_code` | ✅ | ✅ |
| `logo_url` | ✅ | ✅ |
| `deleted_at` | ✅ | ✅ |
| `update_counter` | ✅ | ✅ |

**All school columns checked match.** ✅

### 3c. sync-push DELETE handler ([`index.ts:857-860`](supabase/functions/sync-push/index.ts:857))

```ts
.update({ is_deleted: true }).eq("id", serverId)
```

This sets `is_deleted = true` on every syncable table during DELETE. However:

| Table | Has `is_deleted`? | Status |
|---|---|---|
| `lessons` | ✅ | |
| `exams` | ✅ | |
| `subjects` | ❌ **NO `is_deleted` column** | **🔴 CONFIRMED GAP** — Subjects table uses `deleted_at` (timestamptz), not `is_deleted` boolean |
| `teachers` | ❌ **NO `is_deleted` column** | **🔴 CONFIRMED GAP** — Uses `deleted_at` instead |
| `schools` | ❌ **NO `is_deleted` column** | **🔴 CONFIRMED GAP** — Uses `deleted_at` instead |
| `scheme_of_work` | ❌ **NO `is_deleted` column** | **🔴 CONFIRMED GAP** — Uses `deleted_at` instead |
| `progress_logs` | ✅ has `is_deleted` | ✅ |
| `vault_items` | ❌ **NO `is_deleted` column (on server)** | **🔴 CONFIRMED GAP** — vault_items server has no `is_deleted` column (though VAULT_ITEMS_DEFAULTS adds one) |
| `payment_events` | ❌ **NO `is_deleted` column** | **🔴 CONFIRMED GAP** — Uses `deleted_at` instead |

**This is a significant bug.** The DELETE handler calls `.update({ is_deleted: true })` on tables that don't have an `is_deleted` column, which will throw a PostgreSQL error.

**Tables that DO have `is_deleted`:** `lessons`, `exams`, `progress_logs`  
**Tables that DON'T have `is_deleted` but have `deleted_at`:** `subjects`, `teachers`, `schools`, `scheme_of_work`, `vault_items`, `payment_events`

### 3d. sync-pull `is_deleted` filtering ([`index.ts:158-176`](supabase/functions/sync-pull/index.ts:158))

Comment at line 162: "teachers table has no is_deleted column" — the code handles this by just fetching `.select("id")` from teachers. This is correct for teachers. However, the same pattern applies generically.

**🟡 STALE / HARMLESS** — The pull endpoint doesn't filter on `is_deleted` for any table; it just fetches `updated_at > lastSyncTimestamp`.

---

## 4. Column-Level Discrepancies in Auth Functions

### 4a. `signup/index.ts` teachers insert ([`signup/index.ts:108-123`](supabase/functions/signup/index.ts:108))

Inserts: `email, teacher_name, role, school_id, password_hash, salt, password_hash_version, force_password_reset, is_active, email_verified`

| Column | Server has? | Status |
|---|---|---|
| `email` | ✅ | |
| `teacher_name` | ✅ | |
| `role` | ✅ | |
| `school_id` | ✅ | |
| `password_hash` | ✅ (text) | ✅ |
| `salt` | ✅ (text, nullable) | ✅ |
| `password_hash_version` | ✅ (integer, NOT in earlier schema dump) | **🟡 STALE / HARMLESS** — exists on server now |
| `force_password_reset` | ✅ (boolean, NOT in earlier schema dump) | **🟡 STALE / HARMLESS** — exists on server now |
| `is_active` | ✅ | |
| `email_verified` | ✅ | |

**All columns match.** ✅

### 4b. `signup/index.ts` schools insert ([`signup/index.ts:89-100`](supabase/functions/signup/index.ts:89))

Inserts: `school_name, short_code, subscription_tier, total_seats, admin_recovery_email, admin_recovery_email_verified`

All match server schema. ✅

### 4c. `login/index.ts` query ([`login/index.ts`](supabase/functions/login/index.ts))

Selects from `teachers` with `*, schools(...)`. Uses `current_device_id`, `last_credit_refill_date`, `theme_mode`, `token_version`.

| Column | Server has? | Status |
|---|---|---|
| `current_device_id` | ❌ **NO `current_device_id` on server `teachers`** | **🟡 STALE / HARMLESS** — Not written server-side; just read and returned |
| `last_credit_refill_date` | ✅ (timestamptz) | ✅ |
| `theme_mode` | ✅ (text) | ✅ |
| `token_version` | ✅ (integer) | ✅ |

### 4d. `add-teacher/index.ts` insert ([`add-teacher/index.ts`](supabase/functions/add-teacher/index.ts))

Inserts: `email, teacher_name, role, school_id, password_hash, salt, password_hash_version, force_password_reset, is_active, temp_password`

All match server schema. ✅

### 4e. `change-password/index.ts` update ([`change-password/index.ts`](supabase/functions/change-password/index.ts))

Updates: `password_hash, password_hash_version, force_password_reset, temp_password`

All match server schema. ✅

### 4f. `admin-recovery-request/index.ts` ([`admin-recovery-request/index.ts`](supabase/functions/admin-recovery-request/index.ts))

Uses `teachers`, `admin_recovery_otps`, `schools`. All columns match. ✅

### 4g. `admin-recovery-verify-otp/index.ts` ([`admin-recovery-verify-otp/index.ts`](supabase/functions/admin-recovery-verify-otp/index.ts))

Uses `teachers`, `admin_recovery_otps`. All columns match. ✅

### 4h. `request-upgrade/index.ts` ([`request-upgrade/index.ts`](supabase/functions/request-upgrade/index.ts))

Uses `upgrade_requests`, `teachers`, `schools`. All columns match. ✅

---

## 5. Column-Level Discrepancies in Payment Functions

### 5a. `confirm-payment/index.ts` ([`confirm-payment/index.ts`](supabase/functions/confirm-payment/index.ts))

Uses `activation_codes` (updates `used`, `school_id`, `redeemed_at`), `schools` (updates `subscription_tier`, `expiry_date`, `activation_code`, `updated_at`). All columns match. ✅

### 5b. `paystack-webhook/index.ts` ([`paystack-webhook/index.ts`](supabase/functions/paystack-webhook/index.ts))

Same table usage as confirm-payment. All columns match. ✅

### 5c. `redeem-activation/index.ts` ([`redeem-activation/index.ts`](supabase/functions/redeem-activation/index.ts))

Uses `activation_codes`, `schools`. All columns match. ✅

---

## 6. KEY_MAP / PayloadCompressor Cross-Reference

### 6a. Server-side KEY_MAP ([`sync-push/index.ts:13-85`](supabase/functions/sync-push/index.ts:13))

Maps short keys → full column names for decompression on server push.

Full-column-name targets that do NOT exist on any server table:

| Short Key | Maps To | Exists on any server table? | Status |
|---|---|---|---|
| `skw` | `school_key_wrapped` | ❌ — Server has `school_master_key_wrapped` (schools). No `school_key_wrapped` anywhere. | **🟡 STALE / HARMLESS** — `resolveForeignKeys` maps `school_key_wrapped` → no-op; schools insert doesn't use it directly |
| `cdid` (in Dart compressor) | `current_device_id` | ❌ — No `current_device_id` on server `teachers` | **🟡 STALE / HARMLESS** — Not sent by server; only used client-side |
| `fpr` (in Dart compressor) | `force_password_reset` | ✅ — Actually present on server now | **🟡 STALE / HARMLESS** — was in earlier schema dump, now migrated |
| `tp` (in Dart compressor) | `temp_password` | ✅ | ✅ |

All other KEY_MAP entries map to columns that exist on their respective tables. ✅

### 6b. Dart-side PayloadCompressor `_keyMap` ([`payload_compressor.dart:104-154`](lib/core/utils/payload_compressor.dart:104))

Same analysis as above — all short keys map to valid Drift-model fields locally. The compressor is used client-side only; the server KEY_MAP in sync-push mirrors it for decompression.

**Risk:** `end_date` is mapped to `ed` in Dart compressor, but `ed` is also used for `expiry_date` in the server-side KEY_MAP. This means:
- Dart client compresses `end_date` → `ed`
- Server decompresses `ed` → `expiry_date` (not `end_date`)

**🔴 CONFIRMED GAP — KEY COLLISION**: The short key `ed` maps to TWO different full keys: `expiry_date` (server KEY_MAP) and `end_date` (Dart compressor). If a payload contains `end_date`, it will be decompressed server-side as `expiry_date`.

---

## 7. LESSON_DEFAULTS vs. Lessons Schema ([`sync-push/index.ts:113-125`](supabase/functions/sync-push/index.ts:113))

| Default Field | Server `lessons` has column? | Status |
|---|---|---|
| `topic` | ✅ (not null, default `''`) | ✅ |
| `difficulty` | ✅ (not null) | ✅ |
| `blooms_verbs` | ✅ (not null) | ✅ |
| `title` | ✅ (not null) | ✅ |
| `credits_spent` | ✅ (not null, default `1`) | **🟡 STALE / HARMLESS** — Default is `1` not `0`; the code overwrites with `0` |
| `objectives` | ✅ (not null) | ✅ |
| `vocabulary` | ✅ (not null) | ✅ |
| `materials` | ✅ (not null) | ✅ |
| `presentation` | ✅ (not null) | ✅ |
| `assessment` | ✅ (not null) | ✅ |
| `homework` | ✅ (not null) | ✅ |

**All match.** ✅ (Minor: `credits_spent` server default is `1`, code defaults to `0` — but code explicitly sets it so server default is irrelevant.)

---

## 8. EXAM_DEFAULTS vs. Exams Schema ([`sync-push/index.ts:127-134`](supabase/functions/sync-push/index.ts:127))

| Default Field | Server `exams` has column? | Status |
|---|---|---|
| `difficulty` | ✅ (not null) | ✅ |
| `title` | ✅ (not null) | ✅ |
| `credits_spent` | ✅ (not null, default `0`) | ✅ |
| `questions` | ✅ (not null) | ✅ |
| `theory_questions` | ✅ (not null) | ✅ |
| `marking_scheme` | ✅ (not null) | ✅ |

**All match.** ✅

---

## 9. VAULT_ITEMS_DEFAULTS vs. Vault Items Schema ([`sync-push/index.ts:140-146`](supabase/functions/sync-push/index.ts:140))

| Default Field | Server `vault_items` has column? | Status |
|---|---|---|
| `min_tier` | ✅ (not null, default `'free'`) | ✅ |
| `credit_cost` | ❌ **NO `credit_cost` column on server** | **🔴 CONFIRMED GAP** — Server has `credits_spent` (integer, not null, default `0`), not `credit_cost` |
| `needs_approval` | ❌ **NO `needs_approval` column on server** | **🔴 CONFIRMED GAP** |
| `approval_status` | ✅ (not null, default `'pending'`) | ✅ |
| `is_deleted` | ❌ **NO `is_deleted` column on server `vault_items`** | **🔴 CONFIRMED GAP** — Server has no soft-delete column at all |

**Significant gaps:** VAULT_ITEMS_DEFAULTS assumes columns (`credit_cost`, `needs_approval`, `is_deleted`) that don't exist server-side. When the client pushes a vault_item with these defaults, the INSERT/UPDATE will fail.

---

## 10. SCHEME_OF_WORK_DEFAULTS vs. Scheme of Work Schema ([`sync-push/index.ts:136-138`](supabase/functions/sync-push/index.ts:136))

| Default Field | Server `scheme_of_work` has column? | Status |
|---|---|---|
| `status` | ❌ **NO `status` column on server `scheme_of_work`** | **🔴 CONFIRMED GAP** |

**This will cause INSERT failures** when pushing new scheme_of_work entries, since the code applies `status: "draft"` as a default and the column doesn't exist.

---

## 11. FK Resolution Assumptions

### 11a. `resolveForeignKeys` for lessons/exams ([`sync-push/index.ts:174-274`](supabase/functions/sync-push/index.ts:174))

All column references checked:
- `school_id` — ✅ on both `lessons` and `exams`
- `school_server_id` — ✅ on both (text, nullable)
- `teacher_server_id` — ✅ on both (text, nullable)
- `teacher_id` — ✅ on both (uuid, not null)
- `subject` — ✅ on both (text, nullable)
- `subject_id` — ✅ on both (uuid, not null)
- `class_level` — ✅ on both (text, nullable)
- `week_number` — ✅ on lessons (integer, not null), ✅ on exams (integer, nullable)
- `title` — ✅ on both (text, not null)
- `topic` — ✅ on both (text, not null — exams has default `''`)
- `content` — ✅ on both (text, not null — default `''`)

### 11b. `resolveForeignKeys` for progress_logs ([`sync-push/index.ts:276-318`](supabase/functions/sync-push/index.ts:276))

- `school_id` — ✅ (uuid, not null)
- `teacher_id` — ✅ (uuid, not null)
- `lesson_id` — ✅ (uuid, nullable)
- `local_id` — ✅ (lessons table has `local_id` integer)

### 11c. `resolveForeignKeys` for scheme_of_work ([`sync-push/index.ts:323-351`](supabase/functions/sync-push/index.ts:323))

- `teacher_server_id` → `teacher_id` — ❌ **Server `scheme_of_work` has NO `teacher_id` UUID column** | **🔴 CONFIRMED GAP**
- `school_server_id` → `school_id` — ✅
- `subject_id` — ✅
- `local_id` — removed ✅ (local-only)

### 11d. `resolveForeignKeys` for vault_items ([`sync-push/index.ts:356-389`](supabase/functions/sync-push/index.ts:356))

- `teacher_server_id` → `teacher_id` — ❌ **Server `vault_items` has NO `teacher_id` UUID column** | **🔴 CONFIRMED GAP**
- `school_server_id` → `school_id` — ✅
- `subject_id` — ✅
- `author_name` — ❌ **Server `vault_items` has NO `author_name` column** | **🔴 CONFIRMED GAP**
- `local_id` — removed ✅
- `encrypted` — removed ❓ Server `vault_items` has no `encrypted` column, but it's being deleted anyway (local-only field)

---

## 12. Summary: Confirmed Gaps Requiring Action

These will cause runtime errors (INSERT/UPDATE failures, 500 errors) in the current production code:

| # | Location | Issue | Impact |
|---|----------|-------|--------|
| 1 | [`sync-push/index.ts:857-860`](supabase/functions/sync-push/index.ts:857) | DELETE handler sets `is_deleted: true` on tables without `is_deleted` column: `subjects`, `teachers`, `schools`, `scheme_of_work`, `payment_events` | **HIGH** — DELETE operations on these tables throw 500 errors |
| 2 | [`sync-push/index.ts:857-860`](supabase/functions/sync-push/index.ts:857) | DELETE handler sets `is_deleted: true` on `vault_items` which has no `is_deleted` column on server | **HIGH** — Same as above |
| 3 | [`sync-push/index.ts:656-662`](supabase/functions/sync-push/index.ts:656) | `credit_spend` in `SYNCABLE_TABLES` — table doesn't exist | **LOW** — Client never sends this table name; it's just in the allowlist set. Won't cause errors unless explicitly triggered. |
| 4 | [`payload_compressor.dart:152-153`](lib/core/utils/payload_compressor.dart:152) vs [`sync-push/index.ts:48`](supabase/functions/sync-push/index.ts:48) | KEY COLLISION: short key `ed` maps to `end_date` (Dart) AND `expiry_date` (server) | **MEDIUM** — If a payload contains `end_date`, server decompresses it as `expiry_date` |
| 5 | [`sync-push/index.ts:140-146`](supabase/functions/sync-push/index.ts:140) | `VAULT_ITEMS_DEFAULTS` has `credit_cost`, `needs_approval`, `is_deleted` — none exist on server `vault_items` | **HIGH** — Pushing vault_items will fail |
| 6 | [`sync-push/index.ts:136-138`](supabase/functions/sync-push/index.ts:136) | `SCHEME_OF_WORK_DEFAULTS` has `status: "draft"` — no `status` column on server `scheme_of_work` | **HIGH** — Pushing scheme_of_work will fail |
| 7 | [`sync-push/index.ts:325-327`](supabase/functions/sync-push/index.ts:325) | `resolveForeignKeys` maps `teacher_server_id` → `teacher_id` for scheme_of_work, but server `scheme_of_work` has no `teacher_id` column | **MEDIUM** — Silent data loss; teacher reference is lost |
| 8 | [`sync-push/index.ts:359`](supabase/functions/sync-push/index.ts:359) | `resolveForeignKeys` maps `teacher_server_id` → `teacher_id` for vault_items, but server `vault_items` has no `teacher_id` column | **MEDIUM** — Silent data loss |
| 9 | [`sync-push/index.ts:377 (comment)`](supabase/functions/sync-push/index.ts:377) | Comment mentions `author_name` but server `vault_items` has no such column | **MEDIUM** — Column name referenced in code but doesn't exist |

---

## 13. Summary: Stale/Harmless Mismatches

These are references to columns that don't exist server-side but are handled safely:

| # | Location | Issue | Why Harmless |
|---|----------|-------|-------------|
| 1 | [`sync_service.dart:1573-1574`](lib/core/services/sync_service.dart:1573) | `_upsertTeacherFromSync` reads `current_device_id` and `is_deleted` from remote — these don't exist on server `teachers` | Values default to `null`/`false`; no crash |
| 2 | [`sync_service.dart:1570-1571`](lib/core/services/sync_service.dart:1570) | Falls back from `school_key_wrapped` to `school_master_key_wrapped` | Fallback chain works |
| 3 | [`sync_service.dart:1729-1730`](lib/core/services/sync_service.dart:1729) | Same fallback for schools | Works correctly |
| 4 | [`sync-pull/index.ts:162`](supabase/functions/sync-pull/index.ts:162) | Comment says "teachers table has no is_deleted column" | Code handles correctly; just fetches `.select("id")` |
| 5 | Various auth functions reading `current_device_id` | Column doesn't exist on server | Just read from `select(*)` response — returns `null` |
| 6 | `force_password_reset` in KEY_MAP | Was missing from earlier schema but now migrated | Exists now after migration |

---

## 14. Summary: Uncertain / Needs Decision

| # | Location | Issue | Question |
|---|----------|-------|----------|
| 1 | [`sync-push/index.ts:359`](supabase/functions/sync-push/index.ts:359) | vault_items has no `teacher_id` — should it? | Should vault_items track which teacher published them? If so, add column. If not, remove FK resolution. |
| 2 | [`sync-push/index.ts:325-327`](supabase/functions/sync-push/index.ts:325) | scheme_of_work has no `teacher_id` — should it? | Should scheme_of_work entries track which teacher created/modified them? Currently `last_modified_by` exists but no direct `teacher_id`. |
| 3 | [`sync-push/index.ts:140-146`](supabase/functions/sync-push/index.ts:140) | vault_items missing `needs_approval`, `credit_cost` — should these columns be added to server? | These appear to be design-intent columns that were never migrated to the server |
| 4 | DELETE handler [`sync-push/index.ts:857-860`](supabase/functions/sync-push/index.ts:857) | Should tables without `is_deleted` use `deleted_at` instead? | Need to decide: add `is_deleted` to all tables OR use `deleted_at` approach for the DELETE handler |
| 5 | `credit_spend` table in `SYNCABLE_TABLES` | Was this table planned but never created? | Should it be created or removed from the allowlist? |

---

## Appendix A: Server Schema Reference

### Tables confirmed present (24 total)
`activation_codes`, `admin_recovery_otps`, `app_config`, `conflicts`, `exams`, `lessons`, `payment_events`, `pending_activations`, `progress_logs`, `realtime_events`, `recovery_codes`, `scheme_generation_queue`, `scheme_of_work`, `schools`, `subjects`, `sync_queue`, `sync_queue_snapshot`, `teacher_devices`, `teachers`, `upgrade_requests`, `vault_items`, `verification_codes`, `version_hashes`

### Tables referenced in code but NOT on server
- `audit_logs` — local-only Drift table
- `credit_spend` — referenced in `SYNCABLE_TABLES` only

### Column patterns by table

| Table | soft-delete method |
|---|---|
| `lessons` | `is_deleted` (boolean) |
| `exams` | `is_deleted` (boolean) |
| `progress_logs` | `is_deleted` (boolean) + `deleted_at` (timestamptz) |
| `subjects` | `deleted_at` (timestamptz) only |
| `teachers` | `deleted_at` (timestamptz) only |
| `schools` | `deleted_at` (timestamptz) only |
| `scheme_of_work` | `deleted_at` (timestamptz) only |
| `vault_items` | `deleted_at` (timestamptz) only |
| `payment_events` | `deleted_at` (timestamptz) only |
