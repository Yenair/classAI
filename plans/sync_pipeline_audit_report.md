# ClassAI Sync Pipeline — Comprehensive Audit Report

**Date:** 2026-07-10  
**Auditor:** Architectural Review  
**Scope:** Offline → Online sync pipeline for all local tables  
**Rule:** No changes made. Audit only.

---

## 1. Tables That Must Sync

The app writes data locally to **21 Drift tables**. Of these, the sync pipeline is relevant for the **12 core data tables** listed below. The remaining 9 are utility tables (`sync_queue`, `version_hashes`, `teacher_devices`, `teacher_subjects`, `terms`, `recovery_codes`, `scheme_generation_queue`, `pdf_cache`, `pending_recovery_requests`).

| # | Table | Sync Queue Entry? | Push EF Handles? | Pull EF Handles? | UpdateLocalServerId? | Merge Strategy? |
|---|-------|:-:|:-:|:-:|:-:|:-:|
| 1 | `lessons` | ✅ INSERT/UPDATE/DELETE | ✅ | ✅ | ✅ | ✅ (5 fields) |
| 2 | `exams` | ✅ INSERT/UPDATE/DELETE | ✅ | ✅ | ✅ | ✅ (4 fields) |
| 3 | `progress_logs` | ✅ INSERT only | ✅ | ✅ | ❌ Missing | ❌ Default |
| 4 | `scheme_of_work` | ❌ **MISSING** | ❌ **MISSING** | ✅ | ✅ | ✅ (5 fields) |
| 5 | `vault_items` | ✅ INSERT only | ❌ **MISSING** | ✅ | ✅ | ❌ Default |
| 6 | `teachers` | ❌ **MISSING** | ❌ **MISSING** | ✅ | ❌ Missing | ❌ Default |
| 7 | `schools` | ❌ **MISSING** | ❌ **MISSING** | ❌ **MISSING** | ❌ Missing | ❌ Default |
| 8 | `subjects` | ❌ **MISSING** | ❌ **MISSING** | ✅ | ❌ Missing | ❌ Default |
| 9 | `security_config` | ❌ **MISSING** | ❌ **MISSING** | ❌ **MISSING** | ❌ Missing | ❌ Default |
| 10 | `audit_logs` | ❌ **MISSING** | ❌ **MISSING** | ❌ **MISSING** | ❌ Missing | ❌ Default |
| 11 | `payment_events` | ❌ **MISSING** | ❌ **MISSING** | ❌ **MISSING** | ❌ Missing | ❌ Default |
| 12 | `credit_spend` | ✅ SPEND_CREDITS | ✅ (returns "skipped") | N/A — not a DB table | N/A | N/A |

---

## 2. Push Path Audit (Local → Supabase)

### 2.1 Lessons

**Payload in sync queue** (from [`lesson_editor_screen.dart:881-899, 934-952`](lib/features/lesson/screens/lesson_editor_screen.dart)):
- `subject`, `classLevel`, `week`, `topic`, `difficulty`, `bloomsVerbs`, `curriculum`
- `teacher_server_id`, `school_server_id`, `scheme_of_work_id`, `week_number`, `term`

**⚠️ ISSUE: `content` field NOT included in sync payload**
- The actual lesson content (objectives, vocabulary, materials, presentation, assessment, homework) is stored in the local `content` column but is **never added to the sync queue payload**.
- The `sync-push` Edge Function tries to extract sub-fields from `content` JSON, but since content is never sent, all sub-fields remain empty defaults.
- **Result:** When a lesson is pushed to the server, the `content` column on Supabase is always empty or default (`''`). Pulling the lesson back would lose the content.

**⚠️ ISSUE: `status`, `is_unlocked`, `content_hash` not included**
- These fields exist in both local Drift schema and Supabase schema, but are not in the sync payload.
- `is_unlocked` defaults to `false` on push; `status` defaults to `'draft'`.

**FK Resolution** (from [`sync-push/index.ts:142-221`](supabase/functions/sync-push/index.ts)):
- `school_server_id` → `school_id` ✅ (same UUID value)
- `teacher_server_id` → `teacher_id` ✅ (same UUID value)
- `subject` (text name) → `subject_id` (UUID lookup) ✅
- Derives `title` from `topic` ✅
- Defaults applied for NOT NULL columns via `LESSON_DEFAULTS` ✅

### 2.2 Exams

**Payload in sync queue** (from [`exam_editor_screen.dart:1223-1239`](lib/features/exam/screens/exam_editor_screen.dart)):
- `subject`, `classLevel`, `topic`, `difficulty`, `curriculum`
- `teacher_server_id`, `school_server_id`, `scheme_of_work_id`, `week_number`, `term`

**⚠️ ISSUE: `content` field NOT included in sync payload**
- Same as lessons — the content (MCQs, theory questions) is never sent to the server.
- `is_unlocked` is also missing from the payload.

**FK Resolution** ✅ Same as lessons.

### 2.3 Progress Logs

**Payload in sync queue** (from [`lesson_editor_screen.dart:983-993, 1021-1031`](lib/features/lesson/screens/lesson_editor_screen.dart)):
- `event_type`, `lesson_id`, `teacher_id`, `school_id`

**FK Resolution** (from [`sync-push/index.ts:223-264`](supabase/functions/sync-push/index.ts)):
- `school_id` defaults to zero-UUID if missing ⚠️
- `teacher_id` defaults to zero-UUID if missing ⚠️
- `lesson_id` resolved from `local_id` on `lessons` table ✅

**⚠️ ISSUE: progress_logs payload uses `_teacherId` and `_schoolId` which are the server UUID strings** (from auth state), **but these are stored as raw TEXT UUIDs in the progress_logs table. The server-side `school_id` and `teacher_id` columns are `uuid` type FK references.** The client sends the server UUID directly, which works if the referenced row exists. However, if the teacher or school hasn't been synced yet, the FK will fail with a silent error.

### 2.4 Vault Items

**Payload in sync queue** (from [`vault_publisher_screen.dart:212-222`](lib/features/vault/screens/vault_publisher_screen.dart)):
- `title`, `encrypted`, `teacher_server_id`, `school_server_id`

**⚠️ ISSUE: Minimal payload — missing many fields**
- Missing: `description`, `subject`, `class_level`, `curriculum`, `content`, `author_name`, `credit_cost`, `needs_approval`, `thumbnail_url`
- The sync-push Edge Function has **NO handling for `vault_items`** table — it will try `INSERT` without any FK resolution or column defaults.

**⚠️ ISSUE: sync-push does not handle `vault_items` at all**
- See [`sync-push/index.ts:142-265`](supabase/functions/sync-push/index.ts) — `resolveForeignKeys` only handles `lessons`, `exams`, and `progress_logs`.
- The generic INSERT at line 360-363 will fail if Supabase has any NOT NULL columns without defaults, FK constraints, or column type mismatches.

### 2.5 Scheme of Work

**⚠️ ISSUE: No sync queue entries ever created**

I searched the entire [`scheme_of_work_screen.dart`](lib/features/scheme_of_work/screens/scheme_of_work_screen.dart) (1594 lines) — **zero references** to `syncQueue` or `insertEntry`. The `SchemeOfWorkDao` (95 lines) also has no sync queue logic. Any SoW created or modified locally is **never pushed to the server**.

Even though the `sync-pull` Edge Function and `_updateLocalServerId` support `scheme_of_work`, the **push path is completely broken** — nothing ever queues a SoW change.

### 2.6 Teachers

**⚠️ ISSUE: No sync queue entries ever created**

The [`teachers_dao.dart`](lib/core/database/daos/teachers_dao.dart) has pure CRUD with no sync queue logic. Teachers are added during school registration or admin operations, but those changes are **never pushed**.

### 2.7 Schools

**⚠️ ISSUE: No sync queue entries ever created**

The [`schools_dao.dart`](lib/core/database/daos/schools_dao.dart) has `upsertByServerId` but no sync queue entry creation. School registration/updates are **never pushed**.

### 2.8 Subjects

**⚠️ ISSUE: No sync queue entries ever created**

No subjects data is ever queued for sync. The sync-pull handles subjects (returns all rows), but the push path is dead.

### 2.9 Security Config, Audit Logs, Payment Events

**⚠️ ISSUE: No sync queue entries ever created** for any of these tables.

- [`audit_logs_dao.dart`](lib/core/database/daos/audit_logs_dao.dart): Pure insert, no sync
- [`payment_events_dao.dart`](lib/core/database/daos/payment_events_dao.dart): Pure insert, no sync
- [`security_config_dao.dart`](lib/core/database/daos/security_config_dao.dart): CRUD, no sync

---

## 3. Pull Path Audit (Supabase → Local)

### 3.1 `_syncableTables` definition

In [`lib/core/services/sync_service.dart:242-250`](lib/core/services/sync_service.dart):
```dart
['subjects', 'lessons', 'exams', 'progress_logs', 'vault_items', 'scheme_of_work', 'teachers']
```

**⚠️ ISSUE: Missing tables from pull list**
- `schools` — ❌ Not pulled
- `security_config` — ❌ Not pulled
- `audit_logs` — ❌ Not pulled
- `payment_events` — ❌ Not pulled

### 3.2 Column coverage

The [`sync-pull/index.ts`](supabase/functions/sync-pull/index.ts) uses `.select("*")` for all tables, which means all columns are returned. ✅

However, for tables that `SyncService._pullChanges()` processes, the data is upserted into Drift. The Drift table schemas may have additional columns not present on Supabase (e.g., `salt` on `teachers`, `temp_password` on `teachers`).

### 3.3 `_mergeRemoteChange()` handling

From [`sync_service.dart:1214-1261`](lib/core/services/sync_service.dart):
- Only `teachers` changes get upserted into the actual Drift `teachers` table (via `_upsertTeacherFromSync`).
- All other table changes are only saved to `version_hashes` for conflict detection.
- The actual upsert into Drift tables is implied via the remote API's return processing (in `_pullChanges`), but the merge logic only applies to `teachers`.

### 3.4 Teacher pull — `temp_password` and `force_password_reset`

The pull function returns `pendingTeachers` with `force_password_reset=true` scoped to school. ✅

The `_upsertTeacherFromSync` method (lines 1265-1401) handles `tempPassword` and `forcePasswordReset` fields. ✅

---

## 4. Logic Gaps and Failure Points

### 4.1 Critical Gaps

| # | Gap | Impact | Location |
|---|-----|--------|----------|
| 1 | **`content` never pushed for lessons/exams** | Content is empty on server; pull returns empty content | [`lesson_editor_screen.dart:881-899, 934-952`](lib/features/lesson/screens/lesson_editor_screen.dart) |
| 2 | **`scheme_of_work` never queued** | SoW changes stay local only | [`scheme_of_work_screen.dart`](lib/features/scheme_of_work/screens/scheme_of_work_screen.dart) |
| 3 | **vault_items not handled in sync-push** | Any vault item push silently fails or errors | [`sync-push/index.ts`](supabase/functions/sync-push/index.ts) |
| 4 | **`teachers`, `schools`, `security_config`, `audit_logs`, `payment_events` never queued** | These tables are local-only; never sync | Multiple DAOs |
| 5 | **`_updateLocalServerId` missing for `teachers`, `schools`, `progress_logs`, `subjects`** | Server IDs not stored locally after push; future updates may fail | [`sync_service.dart:1085-1128`](lib/core/services/sync_service.dart) |

### 4.2 `SPEND_CREDITS` handling

- Client: `CreditService.spendCredits()` creates queue entry with `SPEND_CREDITS` operation ✅
- Server: sync-push returns `{ status: "skipped", retryable: false }` ✅
- Client: `_pushChanges()` treats `"skipped"` as success ✅
- **Result: Correctly handled.** No stuck entries.

### 4.3 Merge Strategies

From [`merge_strategies.dart`](lib/core/database/daos/scheme_of_work_dao.dart):
- Only `lessons`, `exams`, `scheme_of_work` have explicit merge strategies (5, 4, and 5 fields respectively)
- All other tables fall back to `lwwByUpdateCounter` (last-writer-wins by update counter) — this is acceptable but not optimal for tables where field-level merging matters (e.g., `vault_items` with approval workflows)

### 4.4 Push result with `ServerId: null` and `Status: updated`

The sync-push handler returns `server_id` = the existing server UUID for UPDATE operations. For `Status: created`, it returns the generated UUID. For errors, `server_id: null` is returned with `retryable: true`.

In `_pushChanges()` (line 1038-1081), entries with `status: "error"` and `retryable: true` get their `attempts` incremented. After 5 attempts, they're left in the queue as stuck entries.

### 4.5 `_tablePriority()` coverage

From [`sync_service.dart:1509-1528`](lib/core/services/sync_service.dart):
- Defined for: `schools`(0), `subjects`(1), `lessons`(2), `exams`(3), `progress_logs`(4), `scheme_of_work`(5), `vault_items`(6)
- Everything else → priority 99
- `teachers` → priority 99 (likely too low — teachers should be pushed before their dependent data)

---

## 5. Audit Report Table

| Table | Push? | Pull? | Issue Found | Suggested Fix |
|-------|:-----:|:-----:|-------------|---------------|
| `lessons` | ⚠️ | ✅ | Content field NOT included in sync payload — lessons push with empty content | Add `content` and `content_hash` to the sync payload in `lesson_editor_screen.dart` |
| `exams` | ⚠️ | ✅ | Content field NOT included in sync payload — exams push with empty content | Add `content` and `is_unlocked` to the sync payload in `exam_editor_screen.dart` |
| `progress_logs` | ⚠️ | ✅ | Uses server UUID strings for `teacher_id`/`school_id` directly — FK may fail if parent not synced | Resolve teacher/school server IDs to actual Supabase UUIDs before insert, or provide fallback |
| `scheme_of_work` | ❌ | ✅ | No sync queue entry created for SoW saves — all SoW data is local-only | Add `syncQueueDao.insertEntry` in `scheme_of_work_screen.dart` save/update methods |
| `vault_items` | ❌ | ✅ | sync-push has NO handler for `vault_items` — INSERT will fail on FK/column constraints | Add `vault_items` handling in `resolveForeignKeys()` with defaults and FK mapping |
| `teachers` | ❌ | ✅ | No sync queue entry created for teacher CRUD — teacher data is local-only | Add sync queue entry creation in the teacher creation/update flow |
| `schools` | ❌ | ❌ | Not in `_syncableTables`, no sync queue entry, not in pull list | Add `schools` to `_syncableTables` and implement push/pull for school records |
| `subjects` | ❌ | ✅ | No sync queue entry created — subjects never push | Add sync queue entry in subject creation/update flow |
| `security_config` | ❌ | ❌ | Not in sync pipeline at all — credits and config are local-only | Add `security_config` to `_syncableTables` and implement push/pull |
| `audit_logs` | ❌ | ❌ | Not in sync pipeline at all — audit trail is local-only | Consider if audit logs need to sync; if so, add to sync pipeline |
| `payment_events` | ❌ | ❌ | Not in sync pipeline at all — payment records are local-only | Consider if payment events need to sync; if so, add to sync pipeline |
| `credit_spend` | ✅ | N/A | Correctly handled with SPEND_CREDITS operation and "skipped" status | No fix needed |

---

## 6. Summary

### Total Issues Found: 10

### Top 3 Most Critical

1. **🔴 Content never pushed for lessons/exams** — The `content` column (which holds the actual lesson plan / exam questions) is excluded from the sync queue payload. This means:
   - Content is empty on Supabase
   - Pulling lessons on a new device returns empty content
   - Data loss risk if the device is wiped
   - **Fix requires:** Add `content` (and `content_hash`) to the sync payload in both `lesson_editor_screen.dart` and `exam_editor_screen.dart`

2. **🔴 Scheme of Work never pushes** — The SoW screen creates/edits/deletes SoW records locally but never creates sync queue entries. Combined with the push Edge Function also not handling `scheme_of_work`, the entire push path is missing.
   - **Fix requires:** Both Flutter code (add sync queue entry) AND Edge Function code (add handler and FK resolution for `scheme_of_work`)

3. **🔴 Vault items push path broken** — The sync queue entry is created with a minimal 4-field payload, but the Edge Function has no handler for `vault_items`. The generic INSERT will likely fail due to missing FK resolution and NOT NULL columns.
   - **Fix requires:** Edge Function changes to add `vault_items` handling in `resolveForeignKeys()` and column defaults

### Changes Required By Layer

| Layer | Changes Needed |
|-------|---------------|
| **🟢 Database Schema** | None — all required columns already exist on both sides |
| **🔵 Edge Functions** | Add handlers for `scheme_of_work`, `vault_items` in `sync-push/index.ts`; add FK resolution and defaults |
| **🟠 Flutter Code** | Add `content`/`content_hash` to lesson/exam payloads; add sync queue entries for SoW; add missing tables to `_syncableTables`; add `_updateLocalServerId` for `teachers`, `schools`, `progress_logs`, `subjects` |

### Git Commit Commands

After implementing fixes, to commit the project:

```bash
git add -A
git commit -m "fix(sync): add content to lesson/exam payloads, add SoW sync queue entries, vault_items EF handler"
git push
```

### Next Steps

1. Prioritize and implement the fixes — starting with content payload (most impactful) and SoW (most broken)
2. After fixes, run `dart analyze lib/` on changed files to verify no regressions
3. Test push/pull with real data — create a lesson, mark it completed, verify both appear on Supabase
4. Test pull on a fresh device — verify all data appears correctly
