# Database Column Migration Audit Report

**Date:** 2026-05-31
**Scope:** All 22 Drift table definitions cross-referenced against the 15 migration blocks (schema v1→v16), raw SQL in services, DAO methods, and Supabase Edge Functions.

---

## Summary

**Total issues found: 8**
- **Critical (app crash):** 1
- **High (likely app crash):** 4
- **Medium (conditional crash):** 2
- **Low (server-side, no local crash):** 1

### Top 3 Most Critical

1. **Conflicts table missing `local_value` and `remote_value`** — Migration 2 explicitly adds columns to `conflicts` but omits these two. Any Drift query accessing `localValue`/`remoteValue` on an upgraded database crashes with `no such column: local_value` or `no such column: remote_value`.
2. **Lessons table missing `teacher_server_id`, `school_server_id`, `is_unlocked`** — These sync/feature columns have no migration. If added to the Drift definition after schema v1, upgraded databases crash on any query touching them.
3. **Exams table missing `teacher_server_id`, `school_server_id`, `is_unlocked`** — Same pattern as Lessons. Migrations add `server_id`, `update_counter`, `is_deleted`, `last_modified_by` but not these three.

---

## Full Issue Table

| # | Severity | File | Line | Issue | Current Code | Expected Column |
|---|----------|------|------|-------|-------------|-----------------|
| 1 | **Critical** | [`lib/core/database/database.dart`](lib/core/database/database.dart:149) | 149–169 | Migration v2 adds 7 columns to `conflicts` but omits `local_value` and `remote_value` defined in the Drift table. Upgraded DBs (v1→v2+) crash when Drift queries these columns. | `ALTER TABLE conflicts ADD COLUMN record_type TEXT …` (7x ALTER TABLE) | `ALTER TABLE conflicts ADD COLUMN local_value TEXT NULL` + `ALTER TABLE conflicts ADD COLUMN remote_value TEXT NULL` |
| 2 | **High** | [`lib/core/database/database.dart`](lib/core/database/database.dart:142) | 142–528 | `teachers.last_credit_refill_date`, `teachers.salt`, `teachers.last_modified_by` exist in Drift definition [`teachers.dart:21,26,28`](lib/core/database/tables/teachers.dart:21) but no migration adds them. If added after v1, upgraded DBs lack them. | No `ALTER TABLE teachers ADD COLUMN` for these 3 columns anywhere in v2–v16 | 3x `ALTER TABLE teachers ADD COLUMN last_credit_refill_date / salt / last_modified_by` |
| 3 | **High** | [`lib/core/database/database.dart`](lib/core/database/database.dart:142) | 142–528 | `schools.last_modified_by` exists in Drift definition [`schools.dart:22`](lib/core/database/tables/schools.dart:22) but no migration adds it. | No `ALTER TABLE schools ADD COLUMN last_modified_by` anywhere in v2–v16 | `ALTER TABLE schools ADD COLUMN last_modified_by TEXT NULL` |
| 4 | **High** | [`lib/core/database/database.dart`](lib/core/database/database.dart:311) | 311–334 | Migration v12 adds sync columns to `lessons` (`server_id`, `update_counter`, `is_deleted`, `last_modified_by`) but omits `teacher_server_id`, `school_server_id`, `is_unlocked` defined in [`lessons.dart:20-22`](lib/core/database/tables/lessons.dart:20). | `ALTER TABLE lessons ADD COLUMN server_id …` (4x ALTER TABLE for lessons) | `ALTER TABLE lessons ADD COLUMN teacher_server_id TEXT NULL` + `school_server_id` + `is_unlocked` |
| 5 | **High** | [`lib/core/database/database.dart`](lib/core/database/database.dart:311) | 324–334 | Same as #4 for `exams`. Migration v12 adds `server_id`, `update_counter`, `is_deleted`, `last_modified_by` but omits `teacher_server_id`, `school_server_id`, `is_unlocked` defined in [`exams.dart:17-19`](lib/core/database/tables/exams.dart:17). | `ALTER TABLE exams ADD COLUMN server_id …` (4x ALTER TABLE for exams) | `ALTER TABLE exams ADD COLUMN teacher_server_id TEXT NULL` + `school_server_id` + `is_unlocked` |
| 6 | **Medium** | [`lib/core/database/database.dart`](lib/core/database/database.dart:298) | 298–303 | Migration v10 is empty. Comment says `email` and `attempted_at` on `pending_recovery_requests` were added in v4 but missing from Drift definition. This acknowledges the schema version bump. No column change needed — informational only. | Empty block with comment | N/A (documentation only) |
| 7 | **Medium** | [`supabase/functions/sync-push/index.ts`](supabase/functions/sync-push/index.ts:171) | 171 | Soft-delete UPDATE references `deleted_at` column on the Supabase table. If the Supabase `lessons`/`exams`/etc. tables don't have a `deleted_at` column, the push fails server-side (no local SqliteException but sync breaks). | `.update({ deleted_at: new Date().toISOString(), is_deleted: true })` | Add `deleted_at` column to Supabase tables, OR change to use existing `is_deleted` + `updated_at` |
| 8 | **Low** | [`supabase/functions/ussd-recovery/index.ts`](supabase/functions/ussd-recovery/index.ts:231) | 231 | Queries `schools` table with `.select("name, subscription_tier")` but the Supabase `schools` table uses `school_name` (confirmed by login, signup, validate-session Edge Functions). This causes a Postgres error. | `.from("schools").select("name, subscription_tier")` | `.select("school_name, subscription_tier")` |

---

## Detailed Analysis

### Issue 1 — Conflicts: `local_value` / `remote_value` (CRITICAL)

**File:** [`lib/core/database/database.dart`](lib/core/database/database.dart:149) lines 149–169

**Drift table definition** ([`conflicts.dart`](lib/core/database/tables/conflicts.dart)):
```
IntColumn get id → id
TextColumn get recordType → record_type
IntColumn get recordLocalId → record_local_id
TextColumn get conflictingFields → conflicting_fields
TextColumn get localValue → local_value        ← NOT in migration
TextColumn get remoteValue → remote_value      ← NOT in migration
TextColumn get resolution → resolution
BoolColumn get notified → notified
DateTimeColumn get createdAt → created_at
DateTimeColumn get updatedAt → updated_at
```

**Migration v2 adds:**
- `record_type`, `record_local_id`, `conflicting_fields`, `resolution`, `notified`, `created_at`, `updated_at`

**Missing:**
- `local_value` and `remote_value`

**Impact:** Any Drift-generated query accessing `local_value` or `remote_value` on an upgraded database will throw:
```
SqliteException(1): no such column: conflicts.local_value
```

**Confidence:** **100%** — Migration v2 explicitly adds columns to `conflicts` but intentionally or accidentally skips these two. The columns are nullable (`text().nullable()()`) so they can be added safely with no default value concern.

---

### Issues 2–3 — Teachers & Schools: Missing sync/lifecycle columns (HIGH)

**Teachers** ([`teachers.dart`](lib/core/database/tables/teachers.dart:21,26,28)):
- `last_credit_refill_date` — `DateTimeColumn get lastCreditRefillDate => dateTime().nullable()()`
- `salt` — `TextColumn get salt => text().nullable()()`
- `last_modified_by` — `TextColumn get lastModifiedBy => text().nullable()()`

**Schools** ([`schools.dart`](lib/core/database/tables/schools.dart:22)):
- `last_modified_by` — `TextColumn get lastModifiedBy => text().nullable()()`

**No migration adds any of these.** If these columns were part of the original v1 table definition (created by `createAll()`), they exist in all databases. If they were added to the Drift definition after v1, upgraded databases lack them.

**Likelihood:** Given that migration v12 adds `last_modified_by` to `lessons` and `exams` as a sync column, it's likely `teachers.last_modified_by` and `schools.last_modified_by` were also added post-v1 and need migrations.

---

### Issues 4–5 — Lessons & Exams: Missing sync columns (HIGH)

**Lessons** ([`lessons.dart`](lib/core/database/tables/lessons.dart:20-22)):
- `teacher_server_id` — `TextColumn get teacherServerId => text().nullable()()`
- `school_server_id` — `TextColumn get schoolServerId => text().nullable()()`
- `is_unlocked` — `BoolColumn get isUnlocked => boolean().withDefault(const Constant(false))()`

**Exams** ([`exams.dart`](lib/core/database/tables/exams.dart:17-19)):
- `teacher_server_id`, `school_server_id`, `is_unlocked` — same types

**Migration v12** adds `server_id`, `update_counter`, `is_deleted`, `last_modified_by` to both tables, but NOT `teacher_server_id`, `school_server_id`, or `is_unlocked`.

**Likelihood:** These sync/feature columns were likely added to the Drift definition at the same time as the v12 sync columns. The migration was simply incomplete.

---

### Issue 6 — Migration v10 empty (MEDIUM, informational)

**File:** [`lib/core/database/database.dart`](lib/core/database/database.dart:298) lines 298–303

The comment explains this is intentional — `email` and `attempted_at` on `pending_recovery_requests` were added in migration v4 but were missing from the Drift table definition. Once the Drift definition was updated to include them, this empty migration acknowledges the version bump so Drift's schema version matches. No action needed.

---

### Issue 7 — `deleted_at` column in sync-push Edge Function (MEDIUM)

**File:** [`supabase/functions/sync-push/index.ts`](supabase/functions/sync-push/index.ts:171)

```typescript
.update({ deleted_at: new Date().toISOString(), is_deleted: true })
```

This references a `deleted_at` column on Supabase tables. If the Supabase schema doesn't have `deleted_at` on the synced tables, the UPDATE fails server-side. The sync push will return an error, and the local sync queue will retry indefinitely.

**Fix:** Either add `deleted_at TIMESTAMPTZ` to all syncable Supabase tables, or change the push to only set `is_deleted: true` and `updated_at: new Date().toISOString()`.

---

### Issue 8 — Wrong column name `name` in ussd-recovery Edge Function (LOW)

**File:** [`supabase/functions/ussd-recovery/index.ts`](supabase/functions/ussd-recovery/index.ts:231)

```typescript
const { data: school } = await supabase
  .from("schools")
  .select("name, subscription_tier")  // ← BUG: should be "school_name"
  .eq("id", teacher.school_id)
  .maybeSingle();
```

All other Edge Functions (`login`, `signup`, `validate-session`, `confirm-payment`) use `school_name`. This causes a Postgres error on the server but does not affect the local SQLite database.

---

## Methodology

1. **Read all 22 Drift table definitions** in [`lib/core/database/tables/`](lib/core/database/tables/) to establish the complete column set per table.
2. **Read the full migration** in [`lib/core/database/database.dart`](lib/core/database/database.dart:142) lines 142–528 (schema versions 2–16) and cross-referenced each `ALTER TABLE` / `CREATE TABLE` against the current Drift definitions.
3. **Searched for all raw SQL** usage (`customStatement`, `customSelect`, `customInsert`, `customUpdate`) across [`lib/`](lib/) — found 39 results, primarily in `database.dart` (migrations), [`ussd_recovery_service.dart`](lib/core/services/ussd_recovery_service.dart), and [`vacuum_service.dart`](lib/core/services/vacuum_service.dart).
4. **Read all 8 Supabase Edge Functions** that interact with database tables and verified column name consistency.
5. **Reviewed DAO files** for column access patterns — all use Drift type-safe queries, so column mismatches stem from migration gaps, not DAO code.
