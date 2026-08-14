# Sync Full-Table Reconciliation — Phase 1 Investigation & Design

**Date:** 2026-08-13 (revised 2026-08-13 — design review fixes 1–6 applied)
**Status:** PHASE 1 COMPLETE — read-only investigation + design review. No implementation code written yet.
**Scope:** `subjects`, `lessons`, `exams`, `scheme_of_work`, `progress_logs`.
**Rule:** No code changes were made. No commit, no deploy. Plan file to be deleted after Phase 2 is confirmed.

---

## 0. Executive summary

The subject self-heal (`_reconcileLocalSubjects` in `lib/core/services/sync_service.dart`, wired in the uncommitted working tree) proves the pattern: sync-pull returns a full, cursor-independent, school-scoped **catalog**; the client reconciles local rows against it; rows missing server-side get a clean INSERT re-queued; rows the server already has adopt the server id; soft-deleted rows are never re-created.

That mechanism currently exists **only for `subjects`**. Lessons, exams, scheme_of_work, and progress_logs still have no such reconciliation, so the rows belonging to the repaired Igbo / Basic Science / English Studies subjects never reach the server.

This plan generalizes the exact subject pattern to all five tables. New server work: extending **sync-pull** to return small identity catalogs (like `subject_catalog`), plus **check-before-insert guards in sync-push** and **partial unique indexes** for scheme_of_work, lessons, exams, **and subjects** (Fix 5, §1.5; deploy order in §1.8). New local work: a small **reconcile-state table** in Drift (Fix 1 + Fix 6, §C.5) and a **debug dump for flagged rows** (Fix 7, §1.7). Everything else reuses the existing INSERT/FK-resolution path.

---

## 1. Design review — fixes applied (2026-08-13)

Six problems were raised against the original design; each is resolved below. Evidence for Fix 2 was gathered live from the server on 2026-08-13 via `run_supabase_query.ps1` (read-only).

### 1.1 Fix 1 — progress_logs: one-shot re-queue (chosen: local one-shot flag, not a match window)

**Decision: option (b) — a local marker so a progress_logs row is never auto-requeued more than once.** After reconciliation re-queues an INSERT for a progress_logs row, a record in the new `sync_reconcile_state` table (see §C.5) marks it; every later cycle treats that row as **needs manual review** and never re-queues it again.

Why not option (a) (widen the match window to a few seconds):
- Window matching is **probabilistic**. A drifted `event_date` outside the window still fails to match and duplicates; and a *genuine second event* inside the window is silently swallowed as "already matched" — progress logs are append-only, and two `lesson_completed` events for different lessons within seconds are legitimate (the server's `lesson_id` is almost always NULL, so lesson_id cannot disambiguate). Any window size is wrong in one direction or the other.
- The one-shot rule is **deterministic and auditable**: at most one reconciliation push per row ever, then a human decides. Progress logs are low-stakes append-only events; a duplicated event corrupts teacher analytics, while a missing one is cheap for a human to check. That is the right risk posture.
- It composes with Fix 6: both use the same `sync_reconcile_state` table (progress_logs threshold = 1 attempt, other tables = 3).

The marker only matters when the row has no `server_id` and no pending queue entry; a normal push sets `server_id` (Tier 1) and never hits it. See §C.4.

### 1.2 Fix 2 — duplicates: verified none exist — no cleanup step needed

Live check on 2026-08-13 (school `9ae4dd4d-…`, the three repaired subjects and whole-school):
- Lessons grouped by `(subject_id, topic, week, term)` for Igbo / Basic Science / English Studies → **0 groups with >1 row**.
- Same grouping whole-school, plus a **normalized** variant `(subject_id, LOWER(BTRIM(topic)), week, LOWER(term))` → **0 groups** (exact keys can hide case/whitespace twins).
- Lessons grouped by the migration-20260730 dedup key `(subject_id, teacher_id, class_level, week, term)` for the three subjects → **0 groups**.
- Exams grouped by `(subject_id, topic, week_number, term)` and `(subject_id, teacher_id, class_level, week_number, term)` for the three subjects, and normalized whole-school → **0 groups**.
- scheme_of_work grouped by `(school_id, subject_id, term, week_number)` and `(school_id, subject_id, teacher_id, term, week_number)` → **0 groups** (6 rows, all unique; `subject_id`/`teacher_id` always populated; `server_id` always NULL).

**Conclusion: no one-time cleanup is required before enabling ongoing reconciliation for exams/lessons.** The plan therefore needs no dedup migration. As a defensive rule anyway, Tier 2 treats a natural key with **two or more active catalog rows as `ambiguous`** — it adopts neither, re-queues nothing, and flags the row for review (§C.2 step 3). Phase 2 verification re-runs the grouping queries to confirm reconciliation created no new duplicates.

### 1.3 Fix 3 — Tier 2 (natural-key match): safe adoption rule

Chosen: a concrete, auditable rule (option b) rather than blanket "never auto-overwrite". Blanket never-overwrite would flag the exact production bug this plan exists to fix — lessons/exams with **stale cross-table `server_id`s** (the same old collision that hit subjects) would be sent to manual review instead of healed. The rule below overwrites an existing `server_id` in **exactly one provable case**, and never silently:

1. `server_id` **null** + natural-key match → **fill** it. (No existing binding to contradict.)
2. `server_id` non-null + **present in the catalog at all** (active or inactive) → the id references a *real row of this table*; **never rebind**, even when the natural key diverges. Active → Tier 1 match (content edits flow through the normal UPDATE push). Inactive-only → warn + leave.
3. `server_id` non-null + **absent from the entire catalog** (not active, not inactive — provably not a row of this table in this school; e.g. the cross-table-collision id or a foreign-school id) + single natural-key match → **adopt with an explicit WARN log**: `server_id X is not a row of table T in this school's catalog; adopting Y via natural key`. This is the only auto-overwrite case.
4. Natural key is `ambiguous` (2+ active matches) → **never adopt, never re-queue**; flag for review.
5. `server_id` non-null + absent from catalog + **no** natural-key match → treat as missing: clear the stale `server_id`, queue a clean INSERT (subject to the Fix 6 stop-limit).

Every adoption/overwrite is logged at WARN level with old id → new id and the reason, so nothing is ever reassigned silently.

### 1.4 Fix 4 — school scoping: strict explicit match (no null pass-through)

**Rule: a local row is reconciled only if its school **explicitly** resolves to the active session school; a null/unresolvable school column is NEVER treated as "this school".**

- lessons/exams: `schoolServerId == effectiveSchoolId` (exact, non-null string).
- scheme_of_work / progress_logs: local int `schoolId` must resolve (via `schoolsDao`) to the school whose server uuid == `effectiveSchoolId`.
- subjects: `_reconcileLocalSubjects` is tightened the same way — the existing `schoolId == effectiveSchoolId || schoolId == null` predicate drops the `|| null` (one-line change + test update; this is a deliberate deviation from "left untouched").
- If `effectiveSchoolId` is null (no active school session) → skip all reconciliation with one log line.

Rows skipped for scope are counted as `unscoped` in the per-table summary so a human can see them. Verified that rows created by current app versions persist their school: lessons/exams store `schoolServerId` at insert (`lesson_editor_screen.dart:1093-1094,1179-1180`), scheme_of_work stores int `schoolId` (`scheme_of_work_service.dart:42-43,549-550`), progress_logs stores int `schoolId` (`lesson_editor_screen.dart:742-743,983`) — so strict scoping does not skip the production rows that need healing.

### 1.5 Fix 5 — duplicate protection for lessons/exams (decision: extend the guard + indexes NOW), and the verified client push-result path

**Decision (a) — extend the check-before-insert guard and a unique index to lessons and exams in this phase**, so scheme_of_work, lessons, and exams share identical protection. The lessons natural key is the *most* certain of all tables: migration `20260730_002556` deduped lessons on `(subject_id, teacher_id, class_level, week, COALESCE(term,''))` (verified — it soft-deleted newer dups, it did not add a constraint), and the app's `findByTopicSubjectWeekTeacher` uses the same key. Exams use the app's `findByTopicSubjectTeacher` key. Cost is negligible (one SELECT per first-time INSERT on tiny tables). "Optional deferred hardening" is rejected because reconciliation *increases* how often these tables' INSERTs are pushed, so the retry hole is more likely to be exercised after Phase 2, not less.

**progress_logs is deliberately NOT given the guard or an index (written reason):** the one-shot rule (Fix 1) means reconciliation physically cannot push the same progress_logs row twice, so the reconciliation path cannot create a duplicate; and `event_date` is a high-cardinality client timestamp where a unique index could reject rare-but-legitimate same-timestamp events. Its only residual exposure is the pre-existing network-retry hole, out of scope and never observed (1 progress_log row server-side).

**subjects IS included — deliberate decision (revised from "subjects untouched"):** the original scope excluded subjects, but on review that was not justified. Subjects has the *identical* first-time-INSERT retry hole — no unique index on `server_id`, and its sync-push handler (`sync-push/index.ts:566-600`) maps `name`→`subject_name`, fills defaults, and inserts plainly with no dedup — and the subject self-heal actively re-queues subject INSERTs, so the hole is exercised by this project's own mechanism. Verified live: no duplicate subject names per school today (6 rows; `class_level` is `''` for client-created subjects like Igbo/Basic Science/English Studies and non-empty for provisioned ones, e.g. `Mathematics`/`JSS 1`), so the index is safe to create. Natural key mirrors the `lookupSubjectId` chain: **(school_id, normalized subject_name, class_level)** — class_level must be in the key because per-class provisioning is legitimate (same name, different classes); the check-before-insert lookup reproduces the name+class → empty-class → any-name fallback so a retried INSERT lands on the same row the app would have resolved anyway. Partial predicate: `WHERE is_active = true AND deleted_at IS NULL` (subjects has no `is_deleted` column).

**What already stops two reconciliation runs from creating two rows for the same natural key:**
1. **Pending-entry guard** — a re-queued INSERT stays pending until the server confirms **and** the local `server_id` is written; `_pushChanges` writes `server_id` (`_updateLocalServerId`) **before** `removeQueueEntry` (verified `sync_service.dart:1710→1725`), so a crash in between leaves a pending stale INSERT that the next push converts to an UPDATE (`_getServerIdForQueueEntry` → `payload['server_id']` → op UPDATE → server `.update().eq('id', serverId)`) — no duplicate.
2. **Catalog freshness** — Supabase is a single Postgres instance: a catalog read after the server commit always sees the row, so the next pull's Tier 1/Tier 2 match stops any re-queue.

**The remaining hole:** a first-time INSERT (no `server_id`) re-pushed after the server committed but the client lost the response — the normal retry path re-sends it as a plain `.insert()`. `sync-push/index.ts` comments that "the UNIQUE constraint on server_id is the last-line defence", but that is **false for scheme_of_work — it has no unique index on `server_id`** (live `pg_indexes` check: only `scheme_of_work_pkey`, `idx_scheme_school`, `idx_scheme_subject`), and the partial unique `server_id` indexes on lessons/exams do not help first-time INSERTs (server_id is NULL).

**Guard (belt and suspenders), applied to scheme_of_work, lessons, and exams:**
1. **Primary — check-before-insert in sync-push:** before a first-time INSERT, `SELECT` the active row by the table's natural key; if one exists, `UPDATE` it with the payload and return its id as `status: "updated"` instead of inserting. Natural keys (mirroring C.2): SoW `(school_id, subject_id, term, week_number)`; lessons `(school_id, teacher_id, subject_id, class_level, week, COALESCE(term,''))`; exams `(school_id, teacher_id, subject_id, class_level, week_number, COALESCE(term,''), COALESCE(topic,''))`. Lookups filter `is_deleted = false`. Makes first-time INSERTs idempotent at the natural-key level for reconciliation re-queues **and** network retries alike (same pattern as `lookupSubjectId`).
2. **Defense-in-depth — PARTIAL unique indexes** (one SQL migration), all `WHERE is_deleted = false`:
   - `scheme_of_work (school_id, subject_id, term, week_number)` — verified unique (6 rows, all active).
   - `lessons (school_id, teacher_id, subject_id, class_level, week, COALESCE(term,''))` — **must be partial**: verified live that one historical soft-deleted dup (teacher `b9e5f991-…`, week 1, JSS 1) collides with the kept row, so a full index would fail to create. Active rows are unique.
   - `exams (school_id, teacher_id, subject_id, class_level, week_number, COALESCE(term,''), COALESCE(topic,''))` — verified unique including soft-deleted rows; partial for consistency.
   - The index is the atomic backstop against two devices pushing the same row concurrently; sync-push catches the duplicate-key error and converts to UPDATE so it never retries forever. Index and check-before-insert ship together.

**Verified client handling of a check-before-insert result — no client change needed:** `_pushChanges` treats `status: "updated"` exactly like a successful insert: success set at `sync_service.dart:1688-1691`; the success branch (`:1701-1725`) calls `_updateLocalServerId` when `serverId` is non-empty (`:1710-1713`), then `saveSyncedRecord`, then `removeQueueEntry` (`:1725`); `SyncPushResult.fromJson` maps the server's `server_id` field into `result.serverId` (`:158-161`); and `_updateLocalServerId` has a `case 'scheme_of_work'` (`:1814-1819`, with `lessons`/`exams` cases above it) that writes `serverId` + `updatedAt`. So a check-before-insert returning `status: "updated"` with the existing row's id sets the local `server_id` and removes the queue entry — identical to a `created` result.

### 1.6 Fix 6 — stop-limit: 3 consecutive failed matches → manual review

The `sync_reconcile_state` table (§C.5) records, per (table, localId), how many pull cycles the row has been in the "missing" state. **At the threshold (3 for lessons/exams/scheme_of_work, 1 for progress_logs), reconciliation stops re-queueing the row**, logs `needs manual review (no server match after K cycles)`, and counts it as `flagged` in the summary line. The counter resets (state row deleted) when the row eventually matches at Tier 1 or Tier 2 — e.g. when another device pushes it — and only increments in the "missing → about to re-queue" path. Restart-safe: the state lives in Drift.

### 1.8 Deploy order (server pieces) — SQL migration first, then functions, same maintenance window; app last

1. **SQL migration (the unique indexes) FIRST.** Backward compatible with the current sync-push: its plain INSERTs only violate a new index when a genuine duplicate is attempted — the exact race that would otherwise create a dup. In the brief window before the new function deploys, such a violation returns a retryable error; the pending entry retries, and once the new sync-push is live the same retry is caught by the check-before-insert and converted to an UPDATE. The window is transient and self-correcting.
2. **Deploy sync-pull + sync-push together, next** (the two functions are independent of each other; ship in one deploy unit). Deploying the guard *before* the index would leave a window where the non-atomic SELECT-then-INSERT race can slip a permanent duplicate through (only surfaced later by reconciliation's `ambiguous` rule) — strictly worse than migration-first.
3. **Release the app build last** (Drift `sync_reconcile_state` migration + client reconciliation). The client degrades gracefully: an absent `catalogs` key skips reconciliation entirely, so an app released before the server is safe. The Drift migration is device-side and has no server dependency.

### 1.7 Fix 7 — flagged/manual-review rows must reach a person

Reconcile-state rows must not sit invisible in Drift. Three mechanisms, no new UI:

1. **Per-cycle WARN detail lines (primary):** each cycle, in addition to the per-table summary line, reconciliation emits one WARN line per `flagged` row with enough identity to act — `[SYNC-HEAL] <table> localId=<n> needs manual review — no server match after <attempts> cycle(s) (<identity>: subject/topic/class/week…)` — plus one WARN line per `ambiguous` and per `unscoped` row. These appear in the same app-log stream the operator already watches for `[SYNC-SUBJECT-HEAL]`.
2. **`debugDumpReconcileIssues()` on SyncService:** a public method that (a) lists every `sync_reconcile_state` row at/over its threshold — table, localId, attempts, lastAttemptedAt, and the row's identity fields — and (b) prints per-table `unscoped` / `ambiguous` counts from the most recent reconciliation pass (kept in memory for the cycle). Runs automatically at the end of each successful pull (so issues are in the log even when nobody checks) and is callable manually from tests or dev builds. No UI.
3. **Test:** `full_table_reconciliation_test.dart` asserts the dump lists exactly the over-threshold rows with expected identity and counts.

**Documented check:** filter the `flutter run` console (or `adb logcat` on Android) on `SYNC-HEAL`; every flagged row is visible each cycle with localId + identity, and the owning teacher can be looked up from the identity fields.

---

## Task A — Enumerate the syncable tables and their server-side identity

Live schema was queried via `run_supabase_query.ps1` (read-only, Management API) on 2026-08-13. Row counts (this school): lessons 36, exams 33, scheme_of_work 6, progress_logs 1, subjects 6 — catalogs are trivially small.

### A.1 subjects

**Local entity** — `Subjects` (`lib/core/database/tables/subjects.dart`), DAO `SubjectsDao`.
Local columns: `id` (PK), `serverId` (text, nullable), `name`, `alias`, `schoolId` (server school uuid, nullable), `sortOrder`, `createdAt`, `updatedAt`.

**Server columns** (live):
```
id (uuid PK), school_id (uuid NN), subject_name (text NN), curriculum (text NN),
class_level (text NN), is_active (bool NN default true), created_at, updated_at,
update_counter, deleted_at (ts NULL), last_modified_by (uuid)
```
There is **no `server_id` column on the server** — the server row's `id` UUID *is* the local `server_id`. Indexes: only `subjects_pkey` + `idx_subjects_school`.

**Natural identity key:** `school_id` + normalized `subject_name` (trim, collapse whitespace, lowercase). `class_level` is a secondary discriminator; the current self-heal matches on name only (server rows for client-created subjects have `class_level = ''`).

**Current code paths:**
- **Inserted locally:** `SubjectsDao.insert()` from the lesson editor "Add subject" dialog (`lesson_editor_screen.dart:247`), the exam editor dialog (`exam_editor_screen.dart:246`), and `_resolveOrInsertSubjectId` in `scheme_of_work_service.dart:480`.
- **Queued for sync:** every insert site queues `subjects` INSERT with `{'name': ..., 'school_id': <server uuid>}` immediately. Plus the self-heal re-queues missing ones.
- **Server id assigned:** only via push result (`_updateLocalServerId` case `subjects`), or the self-heal adopting an id from the catalog. Sync-pull also writes rows into the local table via `_upsertSubjectFromSync`.
- **Pending/terminal detection:** `store.loadPendingQueue()` (`sync_queue_dao.pendingEntries()`, `isTerminal = false`); the self-heal dedups by localId and by normalized name. Terminal (`isTerminal = true`) entries are preserved but excluded from `pendingEntries()`.

### A.2 lessons

**Local entity** — `Lessons` (`lib/core/database/tables/lessons.dart`), DAO `LessonsDao`.
Local columns mapping to server: `serverId`, `subject` (text name), `classLevel`, `week`, `topic`, `difficulty`, `bloomsVerbs`, `curriculum`, `content` (encrypted JSON), `contentHash`, `schemeOfWorkId`, `weekNumber`, `teacherServerId` (server uuid), `schoolServerId` (server uuid), `isUnlocked`, `status`, `term`, `isDeleted`, `updateCounter`, `lastModifiedBy`, `createdAt`, `updatedAt`.

**Server columns** (live, abbreviated to what matters):
```
id (uuid PK), school_id (uuid NN), subject_id (uuid NN), teacher_id (uuid NN),
title (text NN), topic (text NN), week_number (int NN), week (int NN default 0),
difficulty (text NN), blooms_verbs (text NN), objectives/vocabulary/materials/
presentation/assessment/homework (text NN, derived from content), content (text NN),
content_hash (text NULL), class_level (text NULL), curriculum (text NULL),
subject (text NULL — backfilled by migration 20260730_002556, only lessons),
term (text NULL), status (text NN default 'draft'), is_unlocked (bool),
scheme_of_work_id (text NULL), teacher_server_id (text), school_server_id (text),
server_id (text NULL — effectively unused; 1/36 rows populated, an E2E artifact),
is_deleted (bool NN default false), deleted_at (ts NULL), local_id (int NULL — never
populated: sync-push strips local_id from INSERTs), credits_spent, updated_at, ...
```
Indexes: `idx_lessons_server_id` (UNIQUE partial on non-null server_id), `idx_lessons_local_id`, `idx_lessons_school`, `idx_lessons_subject`, `idx_lessons_teacher`.

**Natural identity key:** the server row's `id` UUID (stored locally as `server_id`). When that is stale/missing, fall back to the app-level dedup key — the same key the server migration `20260730_002556` used to dedupe: **(school_id, teacher_id, subject_id, class_level, week, COALESCE(term,''))**, with normalized `topic` as a strong additional discriminator (the app's own `findByTopicSubjectWeekTeacher` dedups on topic+subject+week+teacher+school). `subject_id` is resolved client-side to text via the local subjects table (serverIds are correct after the subject self-heal).

**Current code paths:**
- **Inserted locally:** `lessonsDao.insertLesson()` from `lesson_editor_screen.dart:1166`, SoW auto-created drafts (`scheme_of_work_service.dart:110` and `scheme_of_work_screen.dart:601`).
- **Queued for sync:** every site queues `lessons` INSERT/UPDATE immediately with the full payload (subject, classLevel, week, topic, difficulty, bloomsVerbs, curriculum, teacher_server_id, school_server_id, content, content_hash, is_unlocked, status, scheme_of_work_id, week_number, term). DELETE is queued from `lessons_list_screen.dart:1139` (only when serverId exists).
- **Server id assigned:** push result → `_updateLocalServerId` case `lessons` (sets local `serverId`, `updatedAt`). Stale-INSERT recovery in `_pushChanges` converts INSERT→UPDATE when a local serverId exists. Pull upserts via `_upsertLessonFromSync` (matches by server_id/`id`, keeps lowest localId on duplicates).
- **Pending/terminal:** same queue semantics as subjects. `_getServerIdForQueueEntry` reads the local row's serverId for stale-INSERT recovery.

### A.3 exams

**Local entity** — `Exams` (`lib/core/database/tables/exams.dart`), DAO `ExamsDao`. Same local column set as lessons (no `contentHash`, no `week`; has `weekNumber`).

**Server columns** (live): same shape as lessons with `subject` **always NULL** (the backfill migration only covered lessons), plus `questions`, `theory_questions`, `marking_scheme` (NOT NULL, derived from content defaults), `content_hash` (NULL), no `week` column. Indexes: `idx_exams_server_id` (UNIQUE partial), `idx_exams_local_id`, `idx_exams_school`, `idx_exams_subject`, `idx_exams_teacher`.

**Natural identity key:** server `id` UUID; fallback = app dedup key from `findByTopicSubjectTeacher` = **(school_id, teacher_id, subject_id, topic)** — plus class_level/week_number/term as extra discriminators (migration 20260730 only deduped lessons; for exams use the same subject/teacher/class/week/term shape minus the server `week` column).

**Current code paths:** mirror lessons — `exam_editor_screen.dart:1294` (INSERT/UPDATE with subject, classLevel, topic, difficulty, curriculum, teacher_server_id, school_server_id, content, is_unlocked, week_number, term, scheme_of_work_id), SoW auto-created drafts (`scheme_of_work_service.dart:220`, `scheme_of_work_screen.dart:686`), `full_term_exam_screen.dart:285` (INSERT), DELETE from `exams_list_screen.dart:447`. Server id assignment, stale-INSERT recovery, pull upsert, pending/terminal detection — identical to lessons.

### A.4 scheme_of_work

**Local entity** — `SchemeOfWork` (`lib/core/database/tables/scheme_of_work.dart`), DAO `SchemeOfWorkDao`. Note the local FK columns are **local integer ids**, not server uuids: `schoolId` (int), `teacherId` (int), `subjectId` (int), plus `term`, `weekNumber`, `topic`, `objectives`, `status`, `adminEditedTopic`, `adminComment`, `classLevel`, `isDeleted`, `serverId` (text uuid), `updateCounter`.

**Server columns** (live):
```
id (uuid PK), school_id (uuid NN), subject_id (uuid NN), term (text NN),
week_number (int NN), topic (text NN), objectives (text NN), created_at,
updated_at, update_counter, deleted_at (ts NULL), last_modified_by (uuid),
server_id (text NULL — never populated, no unique index on it),
teacher_id (uuid NULL), status (text NN default 'draft' + CHECK in
draft/pending/approved/rejected), admin_edited_topic (text NULL),
admin_comment (text NULL), class_level (text NN default ''), is_deleted (bool NN)
```
Indexes: only `scheme_of_work_pkey`, `idx_scheme_school`, `idx_scheme_subject` — **no unique index on server_id**.

**Natural identity key:** server `id` UUID; fallback = **(school_id, subject_id, term, week_number)** — one SoW row per plan week, **teacher is NOT part of identity**: the SoW is a school-shared document per subject/week and the app's own lookup (`getSavedBySubject`, `scheme_of_work_dao.dart:38`) keys by subject only (verified live: `teacher_id` is populated but rows are unique on school+subject+term+week). `topic` is a field, not identity (admin edits change it). Term values are lowercase on both sides ('first'/'second'/'third'); compare case-insensitively. Note: **no unique index exists on `server_id` or the natural key server-side** — see Fix 5 (§1.5).

**Current code paths:**
- **Inserted locally:** `_insertWeekRow` (`scheme_of_work_service.dart:500`) and the SoW screen save flow.
- **Queued for sync:** `_insertWeekRow` always queues INSERT (`scheme_of_work_service.dart:524`) with `teacher_server_id`, `school_server_id`, `subject_id` (may be null), `subject_name` (name fallback for sync-push), `term`, `week_number`, `topic`, `objectives`, `status`, `admin_edited_topic`, `admin_comment`, `class_level`. UPDATEs from `_submitForApproval` / `_adminApprove` (`scheme_of_work_screen.dart:485,561,644,707`) and from `saveScheme` re-saves (`scheme_of_work_service.dart:80`). DELETE queued only when the row has a serverId.
- **Server id assigned:** `_updateLocalServerId` case `scheme_of_work`; pull upsert via `_upsertSchemeOfWorkFromSync` (resolves local school/teacher/subject ints from server uuids).
- **Pending/terminal:** same queue semantics.

### A.5 progress_logs

**Local entity** — `ProgressLogs` (`lib/core/database/tables/progress_logs.dart`), DAO `ProgressLogsDao`. Local columns: `id`, `serverId`, `eventType`, `lessonId` (local int), `teacherId` (local int FK), `schoolId` (local int FK), `eventDate`, `isDeleted`, `updateCounter`, `createdAt`, `updatedAt`.

**Server columns** (live):
```
id (uuid PK), school_id (uuid NN), teacher_id (uuid NN), lesson_id (uuid NULL),
exam_id (uuid NULL), event_type (text NN), notes (text NULL),
event_date (timestamptz NN), created_at, updated_at, update_counter,
deleted_at (ts NULL), last_modified_by (uuid), server_id (text NULL),
is_deleted (bool NN default false)
```
Indexes: `idx_progress_logs_server_id` (UNIQUE partial), `idx_progress_school`, `idx_progress_teacher`.

**Natural identity key:** server `id` UUID; fallback = **(school_id, teacher_id, event_type, event_date, lesson_id)** (append-only logs; `event_date` is the client timestamp with sub-second precision, so collisions are possible but rare — the report in Task C.3 calls this out). Note: server `lesson_id` is almost always NULL because sync-push resolves `lesson_id` from `lessons.local_id`, which is never populated server-side (sync-push strips it) — a pre-existing limitation, out of scope to fix here.

**Current code paths:**
- **Inserted locally:** `progressLogsDao.insert()` from `_handleToggleComplete` / `_handleMarkCompleted` (`lesson_editor_screen.dart:1035,1197`).
- **Queued for sync:** INSERT immediately after insert with `event_type`, `event_date` (UTC ISO), `lesson_id` (local int), `teacher_id` (server uuid), `school_id` (server uuid). INSERT-only — no UPDATE/DELETE paths.
- **Server id assigned:** `_updateLocalServerId` case `progress_logs`; the `event_date` push-time injection (`_pushChanges`) heals legacy queue entries lacking `event_date` (NOT NULL violation).
- **Pending/terminal:** same queue semantics. Pull does **not** create local progress_logs rows (`_mergeRemoteChange` has no `progress_logs` write-back branch — rows go only to `version_hashes`), so no local duplicates from pull.

---

## Task B — Every way a row can be missing from the server

For each table, conditions producing a local row with no server row despite no pending queue entry:

| Condition | subjects | lessons | exams | scheme_of_work | progress_logs |
|---|---|---|---|---|---|
| **Stale/wrong server_id from the old cross-table local_id collision** (serverId = another table's uuid; queue entry was dropped as "updated" against the wrong uuid) | ✅ fixed by self-heal | ✅ possible | ✅ possible | ✅ possible | ✅ possible |
| **Queue entry incorrectly removed as success** (crash between `_updateLocalServerId` and `removeQueueEntry`, or `skipped` result from `pushSkipResult` — e.g. "no subject found for name") | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Queue entry terminal** (`isTerminal = true` — old 5-attempt cap, NOT NULL violation pre-fix, admin-blocked op) — excluded from `pendingEntries()` forever | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Insert never queued** (older app versions before queue entry existed; e.g. SoW rows created before commit `09e4829`; rows created by code paths that forgot to queue) | ✅ | ✅ | ✅ | ✅ (historic — all SoW from before `09e4829` was local-only) | ✅ |
| **Server-side soft-deleted** (`is_deleted = true` / `deleted_at` set / `is_active = false`) — local copy survives, server row intentionally gone | ✅ (is_active/deleted_at) | ✅ | ✅ | ✅ | ✅ |
| **Missing required column / FK resolution failure** — INSERT rejected with retryable error and eventually terminal, or `skipped` non-retryable (e.g. lesson/exam without `week_number`, SoW whose subject doesn't exist yet, progress_logs without `event_date` pre-fix) | ✅ (subject INSERTs before curriculum/class_level defaults existed) | ✅ | ✅ | ✅ | ✅ |
| **Lesson/exam subject resolved to a subject that was never created server-side** (subject self-heal only heals subjects; the child rows were never pushed because `lookupSubjectId` found nothing and the entry was `skipped` terminal) | n/a | ✅ | ✅ | ✅ | n/a |

Common thread: for the 4 non-subject tables there is **no mechanism that looks at the local table itself and re-queues**; the queue is the only driver, and every "dropped/terminal/never-queued" path is permanent.

---

## Task C — Generalized full-table reconciliation design

### C.1 Server-provided catalogs — decision

**Decision: extend `sync-pull` to return a `catalogs` object** (one minimal-column array per table), exactly like the existing `subject_catalog`, instead of a separate reconciliation endpoint.

Rationale:
- Reuses the existing auth/session/`email_verified` validation and the single request path — zero extra round trips, no second endpoint to secure.
- Volume is tiny for small schools (this school: 82 rows total; projected catalogs ≈ 13 columns × ≤50 rows ≈ a few KB). `subject_catalog` already sets the precedent of returning full school catalogs on every page.
- The client already opts in via the request body (`tables` array); we add a `catalogs` array (`['lessons','exams','scheme_of_work','progress_logs']`) so a client can skip it and a future large-school optimization (cursor/watermark-based catalogs) can be added without changing the contract.
- A separate endpoint would double network cost and add a second place where token validation must stay in sync.

sync-pull catalog column projections (identity + active-state only):
- `lessons`: `id, school_id, teacher_id, subject_id, subject, class_level, week, week_number, term, topic, is_deleted, deleted_at, updated_at`
- `exams`: `id, school_id, teacher_id, subject_id, subject, class_level, week_number, term, topic, is_deleted, deleted_at, updated_at`
- `scheme_of_work`: `id, school_id, teacher_id, subject_id, term, week_number, topic, class_level, status, is_deleted, deleted_at, updated_at`
- `progress_logs`: `id, school_id, teacher_id, lesson_id, exam_id, event_type, event_date, notes, is_deleted, deleted_at, updated_at`

`subject_catalog` stays as-is for backward compatibility with the existing subject self-heal. Catalogs are returned on **every page** (like subject_catalog) and the client captures the last page's value.

### C.2 Client reconciliation algorithm (generalized from `_reconcileLocalSubjects`)

Runs at the end of every successful pull, **after** `_reconcileLocalSubjects` (so local subjects already carry correct serverIds, enabling subject_id→name resolution for lessons/exams matching). Skipped entirely when the pull failed (catalog map null), mirroring the subject guard.

For each table `T ∈ {lessons, exams, scheme_of_work, progress_logs}` with a non-null catalog:

0. **School-scope gate (Fix 4):** if `effectiveSchoolId` is null (no active school session) → skip all reconciliation, log one line. Otherwise only local rows whose school **explicitly** resolves to the active school are candidates: `schoolServerId == effectiveSchoolId` (lessons/exams, exact non-null string); local int `schoolId` resolves via `schoolsDao` to the school whose server uuid == `effectiveSchoolId` (scheme_of_work, progress_logs). Null / unresolvable / different school → skip and count as `unscoped` — a null school is never treated as "this school".

1. **Build index maps from the catalog (school-scoped already server-side):**
   - `activeById`: rows where `is_deleted != true` and `deleted_at` is null/empty, keyed by server `id`.
   - `activeByKey`: active rows keyed by the table's natural key (below), normalized. **If two or more active rows share a natural key, the key maps to `ambiguous` — treated as no match and flagged for review (Fix 2 defensive rule).**
   - `inactiveKeys`: natural keys that exist only as soft-deleted/inactive rows.

2. **Load state once:** `store.loadPendingQueue()` (`pendingForLocalId` any op + `pendingInsertsForLocalId` per table, plus the normalized natural-key of pending INSERT payloads where derivable — dedup by localId first, then natural key) and the `sync_reconcile_state` table (§C.5): `attemptsForLocalId` and which rows are already over their stop threshold.

3. **For each candidate local row:**
   - **Skip** rows that are locally soft-deleted (`isDeleted == true`) — re-pushing would resurrect a deliberately deleted row. Also skip empty/blank rows with no usable identity (e.g. blank topic).
   - **Tier 1 — server_id match:** if `serverId` is non-null and `activeById[serverId]` exists → row is on the server; keep `serverId`, drop any pending **INSERT** entries for this localId (a stale INSERT must not re-create it), clear this (table, localId)'s reconcile-state row, `continue`.
   - **Tier 2 — natural-key match (Fix 3 rule):**
     - `serverId` **null** and `activeByKey[key]` is a single active row → **adopt**: write the server `id` into `server_id`, drop pending INSERT entries for this localId, clear reconcile-state, `continue`.
     - `serverId` non-null and present in the catalog at all (active or inactive) → the id references a real row of this table; **never rebind**. Active → Tier 1 already handled it. Inactive-only → warn + `continue` (below).
     - `serverId` non-null and **absent from the entire catalog** (provably not a row of this table in this school — the cross-table-collision id or a foreign-school id) and `activeByKey[key]` is a single active row → **adopt with an explicit WARN**: `server_id X is not a row of table T in this school's catalog; adopting Y via natural key`; write `server_id = Y`, drop stale pending INSERTs, clear reconcile-state, `continue`. This is the only auto-overwrite case.
     - `activeByKey[key]` is `ambiguous` → WARN + count as `flagged`, `continue` (adopt nothing, re-queue nothing).
   - **Inactive check:** if the natural key exists only in `inactiveKeys` (or the existing `server_id` resolves to an inactive catalog row) → log a warning (`[SYNC-HEAL] … soft-deleted/inactive on server — leaving local row unchanged`), `continue` (never re-create a deliberately removed row).
   - **Missing → repair (stop-limit first, Fix 6):** consult `sync_reconcile_state` for this (table, localId). If `attempts >= maxAttempts(table)` (3 for lessons/exams/scheme_of_work, **1 for progress_logs** — one-shot, Fix 1) → do **not** re-queue; WARN `needs manual review (no server match after K cycles)`, count as `flagged`, `continue`. Otherwise: clear a stale `server_id` (write `server_id = NULL`), delete any pre-existing **terminal** INSERT entry for the same (table, localId) so the queue never holds a dead twin, **queue a clean INSERT** built from the full local row **unless** an INSERT is already pending for this localId (or the same natural key), then upsert `sync_reconcile_state` with `attempts + 1` and `lastAttemptedAt = now`.
4. **One summary log line per table:** `[SYNC-HEAL] lessons: X repaired, Y adopted, Z inactive, W unscoped, V flagged` (repaired = re-queued; adopted = server id filled/adopted; inactive = soft-deleted server match; unscoped = no explicit school match; flagged = over stop-limit / ambiguous / needs manual review).

**Natural keys (normalized, case/whitespace-insensitive):**
- lessons: `(schoolId, teacherId, subjectId, classLevel, week, term)` where `subjectId` is resolved client-side from local subject text via local subjects' `serverId` (fallback: match `subject` text against the catalog's `subject` text, which is backfilled for lessons); topic used as a tiebreaker when multiple matches.
- exams: `(schoolId, teacherId, subjectId, classLevel, weekNumber, term, topic)`; `subject_id` resolved via local subjects (exams' server `subject` text is always NULL).
- scheme_of_work: `(schoolId, subjectId, term, weekNumber)` — **teacher excluded** (Fix 5 / §A.4: one school-shared row per subject+week; `topic` is a mutable field, so it is a tiebreaker only).
- progress_logs: `(schoolId, teacherId, eventType, eventDate)` with `lessonId` as an optional tiebreaker (used only when both sides have it; the server's `lesson_id` is almost always NULL) — the one-shot rule (§C.4) bounds the damage when the key cannot disambiguate.

### C.3 Safety properties (per the task requirements)

- **Idempotent:** after healing, the next pull's catalog contains the row, so Tier 1 matches by server id and makes no further changes (subjects test proves the pattern).
- **School-scoped (strict — Fix 4):** catalogs are school-scoped server-side; local rows are reconciled **only** when their school explicitly resolves to the active session school (`schoolServerId == effectiveSchoolId` for lessons/exams; local int `schoolId` → `schoolsDao` → server uuid == `effectiveSchoolId` for scheme_of_work/progress_logs; the same tightening applied to `_reconcileLocalSubjects`). Null / unresolvable / other-school rows are skipped and counted `unscoped`. If `effectiveSchoolId` is null, reconciliation is skipped entirely.
- **Teacher-safe:** only touches the local data table (server_id clears/adopts), the reconcile-state table, and the local sync_queue; never deletes local data; never modifies rows that already exist server-side; never re-creates server-soft-deleted rows. Non-admin teachers can push INSERTs to all five tables (only `subjects` **DELETE** and admin-only SoW fields are admin-gated; reconciliation only ever queues INSERTs and only sends admin fields when the local row has them — a deliberate non-admin re-push of a locally-approved SoW row is a known edge case logged in Phase 2).
- **Stop-limited (Fix 6):** a row in the "missing" state is re-queued at most `maxAttempts(table)` times (3; 1 for progress_logs — Fix 1), then flagged for manual review. No infinite requeue loop.
- **Restart-safe:** state lives only in Drift (server_id column, queue rows, `sync_reconcile_state`), so a crash mid-heal is recovered on the next cycle; the stale-INSERT recovery in `_pushChanges` already converts any INSERT whose local row gained a serverId into an upsert.
- **Automatic:** runs at the end of every successful `_pullChanges`, with no manual scripts. No disposable tools created.

### C.4 progress_logs — handled separately (one-shot re-queue, Fix 1)

- **One-shot (Fix 1, §1.1):** progress_logs uses `sync_reconcile_state` with `maxAttempts = 1`. The first time reconciliation finds a progress_logs row missing from the server with no pending entry, it re-queues a clean INSERT and records one attempt. Every subsequent cycle treats that row as **needs manual review** — it is never auto-requeued again. This makes duplication impossible from the reconciliation path regardless of `event_date` drift, clock skew, or rounding.
- The natural-key match (`school + teacher + event_type + event_date`, `lesson_id` optional) is still used to *adopt* a server id when a match exists (Tier 2) — the one-shot only governs the re-queue path.
- **No check-before-insert / unique index for progress_logs (written decision, §1.5):** the one-shot makes reconciliation-duplicates impossible; a unique index on `(school_id, teacher_id, event_type, event_date)` could reject legitimate same-timestamp events; the only residual exposure is the pre-existing network-retry hole (shared with subjects), never observed.
- Reuse the existing `event_date` push-time injection as a safety net, but the reconciliation INSERT payload **always includes `event_date`** (local `eventDate` → UTC ISO), so the re-queued entry cannot hit the NOT NULL violation.
- Payload: `event_type`, `event_date`, `lesson_id` (local int — same as current behavior; the server resolves to NULL lesson_id as today), `teacher_id` (server uuid resolved from local int via `teachersDao.getById`), `school_id` (server uuid via `schoolsDao.getByLocalId`). If the teacher/school server uuid cannot be resolved, log and skip (do not push zero-uuid rows).

### C.5 Reconcile-state table (Fix 1 + Fix 6)

One new Drift table, `sync_reconcile_state` — additive migration, safe on-device:
- Columns: `id` (PK auto), `tableName` (text), `localId` (int), `attempts` (int, default 0), `lastAttemptedAt` (timestamp, nullable), `updatedAt` (timestamp). UNIQUE on `(tableName, localId)`.
- Semantics: upserted (attempts+1, `lastAttemptedAt = now`) only in the **missing → re-queue** path (C.2 step 3). Deleted when the row matches at Tier 1/Tier 2. Threshold `maxAttempts(table)`: 3 for lessons/exams/scheme_of_work, 1 for progress_logs. Over-threshold rows are skipped and logged `needs manual review`.
- Rationale for a dedicated table over columns on each entity: one entity + one DAO + one migration serves both fixes, the state is about reconciliation rather than row data, and it is trivially testable/auditable.

### C.6 Duplicate verification (Fix 2)

Live evidence from 2026-08-13 (see §1.2): **no duplicate lessons, exams, or scheme_of_work rows exist** on the server — exact and normalized keys, whole school. No one-time cleanup step is required. Tier 2 still treats multi-match natural keys as `ambiguous` and flags them, so future duplicates are surfaced rather than silently adopted.

### C.7 Duplicate protection across re-queueable tables (Fix 5, decision (a))

See §1.5. Applied to **scheme_of_work, lessons, and exams**: (1) **sync-push check-before-insert** — natural-key SELECT (active rows only) before a first-time INSERT; if found, UPDATE and return its id (`status: "updated"`) — first-time INSERTs become idempotent at the natural-key level for reconciliation re-queues and network retries; (2) **partial UNIQUE indexes** `WHERE is_deleted = false` on each table's natural key (one SQL migration; the lessons index must be partial — one historical soft-deleted dup verified live). sync-push converts a duplicate-key race into an UPDATE. **progress_logs deliberately has neither** (the one-shot already prevents reconciliation duplicates; an `event_date` unique index could reject legitimate same-timestamp events — §1.5). **No client change needed** for the `status: "updated"` result path (verified end-to-end in §1.5).

---

## Task D — Report before coding

### D.1 Server schema and identity key per table

| Table | Server identity column | Local `server_id` | Natural key (when server_id stale/missing) |
|---|---|---|---|
| subjects | `id` (uuid) | `serverId` | school_id + normalized subject_name |
| lessons | `id` (uuid) | `serverId` | school + teacher + subject(+class) + week + term (+ topic tiebreaker) |
| exams | `id` (uuid) | `serverId` | school + teacher + subject(+class) + week_number + term (+ topic) |
| scheme_of_work | `id` (uuid) | `serverId` | school + subject + term + week_number (teacher is NOT identity — Fix 5) |
| progress_logs | `id` (uuid) | `serverId` | school + teacher + event_type + event_date (+ lesson_id) |

### D.2 Every local-creation / queue / server_id-assignment path

Covered in full in Task A. Key files:
- Queue inserts: `lesson_editor_screen.dart` (subjects:247, lessons:1123/1193/1252, progress_logs:1035/1197), `exam_editor_screen.dart` (subjects:246, exams:1309), `lessons_list_screen.dart:1139` (DELETE), `exams_list_screen.dart:447` (DELETE), `scheme_of_work_screen.dart:485/561/644/707`, `scheme_of_work_service.dart:80/167/238/405/414/471/524/565/624/638/647/690/711`, `full_term_exam_screen.dart:285`, `auth_provider.dart:1915/1970/2023`, `credit_service.dart:49`, `vault_publisher_screen.dart:214`.
- Server-id assignment: `_updateLocalServerId` (`sync_service.dart:1782`), stale-INSERT recovery + `_getServerIdForQueueEntry` (`sync_service.dart:1556,3540`), pull upserts `_upsertLessonFromSync`/`_upsertExamFromSync`/`_upsertSchemeOfWorkFromSync`/`_upsertSubjectFromSync`.
- Pending/terminal detection: `sync_queue_dao.dart` (`pendingEntries`, `pendingCount`, `markTerminalFailure`, `recoverRetryableTerminalRows`).

### D.3 Proposed design

Extended sync-pull `catalogs` + client-side `_reconcileMissingLocalRows` (C.1–C.5) + reconcile-state table (C.5) + the scheme_of_work check-before-insert guard in sync-push and its unique index (C.7, Fix 5). No new endpoint.

### D.4 Exact files and intended diffs for Phase 2

**Server (deploy required):**
1. `supabase/functions/sync-pull/index.ts` — add `catalogs` request parameter; for each requested table run a school-scoped minimal-column SELECT (columns listed in C.1); add `catalogs` to the JSON response alongside `subject_catalog`. ~40 lines. Backward compatible (absent param → `catalogs: {}`).
2. `supabase/functions/sync-push/index.ts` — **check-before-insert (Fix 5) for scheme_of_work, lessons, exams, and subjects:** in the INSERT branch, before a first-time insert, SELECT the active row by the table's natural key (§1.5 — subjects uses the `lookupSubjectId` name+class → empty-class → any-name chain); if one exists, UPDATE it with the payload and return its id as `status: "updated"`; on a duplicate-key error (race), convert to the same UPDATE instead of retrying forever. ~80 lines. progress_logs untouched.
3. New server SQL migration — **four partial unique indexes** (Fix 5 defense-in-depth; verified against live data):
   - `scheme_of_work (school_id, subject_id, term, week_number)` `WHERE is_deleted = false` — verified unique (6 rows).
   - `lessons (school_id, teacher_id, subject_id, class_level, week, COALESCE(term,''))` `WHERE is_deleted = false` — partial is **mandatory**: one historical soft-deleted dup verified live (teacher `b9e5f991-…`, week 1, JSS 1).
   - `exams (school_id, teacher_id, subject_id, class_level, week_number, COALESCE(term,''), COALESCE(topic,''))` `WHERE is_deleted = false` — verified unique incl. soft-deleted.
   - `subjects (school_id, LOWER(BTRIM(subject_name)), class_level)` `WHERE is_active = true AND deleted_at IS NULL` — verified unique; class_level in the key because per-class provisioning is legitimate.

**Flutter client (one additive Drift migration; no new deps):**
4. New Drift table `sync_reconcile_state` + DAO (C.5) with an additive schema migration (Fix 1 + Fix 6).
5. `lib/core/services/sync_service.dart`:
   - `SyncPullPage`: add `Map<String, List<Map<String, dynamic>>>? tableCatalogs` (+ parse `catalogs` in `fromJson`).
   - `SupabaseSyncRemoteApi.pullChanges`: add `'catalogs': ['lessons','exams','scheme_of_work','progress_logs']` to the request body.
   - `_pullChanges`: capture `page.tableCatalogs` from the last page; after `_reconcileLocalSubjects`, call `_reconcileMissingLocalRows(catalogs, effectiveSchoolId)`.
   - New `_reconcileMissingLocalRows` dispatcher + four per-table reconciles (`_reconcileLocalLessons`, `_reconcileLocalExams`, `_reconcileLocalSchemeOfWork`, `_reconcileLocalProgressLogs`) implementing C.2 exactly: strict school-scope gate (Fix 4), tiered adoption rule (Fix 3), multi-match `ambiguous` handling (Fix 2), stop-limit + one-shot via `sync_reconcile_state` (Fix 1 + Fix 6), **per-row WARN detail lines for flagged/ambiguous/unscoped (Fix 7)**, each ending with one `[SYNC-HEAL]` summary line (`X repaired, Y adopted, Z inactive, W unscoped, V flagged`).
   - New `debugDumpReconcileIssues()` (Fix 7): lists over-threshold `sync_reconcile_state` rows with identity + per-table unscoped/ambiguous counts; called at the end of each successful pull and available manually.
   - New payload builders (`_buildLessonInsertPayload`, `_buildExamInsertPayload`, `_buildSchemeOfWorkInsertPayload`, `_buildProgressLogInsertPayload`) that reproduce the same payloads the current queue sites produce (A.2–A.5), so the re-pushed INSERT is byte-identical to a fresh one and flows through the existing `resolveForeignKeys` — the only sync-push edits are the check-before-insert guards in #2 (lessons/exams/SoW); progress_logs and subjects flow through unchanged.
   - `_reconcileLocalSubjects`: **one-line tightening only** — drop the `|| schoolId == null` pass-through (Fix 4) + update its test. Otherwise untouched.
6. New `test/sync/full_table_reconciliation_test.dart` mirroring `subject_self_heal_test.dart`, covering: missing row → stale server_id cleared + clean INSERT queued + pushed next cycle + second cycle no-op; active match → adopt server id + drop pending INSERT; inactive/soft-deleted match → no-op + warning; already-pending INSERT → no duplicate; locally-deleted rows never re-pushed; progress_logs payload contains `event_date`; **progress_logs one-shot (no second re-queue — Fix 1)**; **stop-limit: 3rd consecutive missing cycle flags for review without re-queueing (Fix 6)**; **multi-school scoping: null/other-school rows skipped as `unscoped` (Fix 4)**; **ambiguous multi-match natural key → flag, never adopt (Fix 2)**; **adoption-with-reason WARN path when the existing server_id is provably absent from the catalog (Fix 3)**; **debugDumpReconcileIssues lists exactly the over-threshold rows + unscoped/ambiguous counts (Fix 7)**; subject test updated for strict school scope.

**No changes:** Drift schema for the five data tables, any screen/DAO, `sync-pull` schema logic beyond the catalogs addition.

### D.5 New server endpoint/function changes required?

Yes, three server-side changes (all small, all deployable together):
1. **sync-pull** gains a `catalogs` response (backward compatible).
2. **sync-push** gains the check-before-insert guard for **scheme_of_work, lessons, exams, and subjects** (Fix 5) — the only sync-push edits; progress_logs re-queued INSERTs reuse the existing handler, FK resolution, and defaults unchanged.
3. One **SQL migration** with **four partial unique indexes** (SoW/lessons/exams `WHERE is_deleted = false`; subjects `WHERE is_active = true AND deleted_at IS NULL`; Fix 5 backstop; each verified against live data — the lessons index must be partial, see §1.5).
4. **Deploy order** (see §1.8): SQL migration first, then sync-pull + sync-push together, then the app release.

On-device: one **additive Drift migration** creating `sync_reconcile_state` (Fix 1 + Fix 6). No other database changes.

---

## Verification after Phase 2 (future)

1. Show full `git diff`.
2. Run (per AGENTS.md — on changed files only):
   ```
   flutter analyze --no-pub
   flutter test test/sync/full_table_reconciliation_test.dart
   flutter test test/sync/subject_self_heal_test.dart
   ```
3. Manually verify one sync cycle against the live school: the previously-missing Igbo/Basic Science/English Studies lessons, exams, and SoW rows appear server-side after a pull, the log shows `[SYNC-HEAL]` summary lines for each table, and `debugDumpReconcileIssues()` (Fix 7) prints the expected `sync_reconcile_state` rows / unscoped / ambiguous counts.
4. Re-run the Fix 2 grouping queries (§1.2) **and the Fix 5 index-key queries** (§1.5) after Phase 2 to confirm reconciliation created **no new duplicates** in lessons/exams/scheme_of_work.
5. Delete `plans/sync_full_table_reconciliation.md` after user confirms.
6. Do NOT commit; do NOT deploy without explicit approval.
