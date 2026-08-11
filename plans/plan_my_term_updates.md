# Plan My Term — Follow-up Updates (sync push, JSS Biology rename, Option-3 UI)

Status: **APPLIED (2026-08-11) — code changes in the working tree, Edge Function NOT deployed, NOT committed.**

Implementation notes:
- Task 1: client fix applied to `lib/core/services/sync_service.dart` (`_pushChanges` —
  injects `server_id` for UPDATE/DELETE entries lacking it); server fix applied to
  `supabase/functions/sync-push/index.ts` (bumps `updated_at` on UPDATE and soft-delete).
  NOT deployed — deploy requires separate approval.
- Task 2: `'basic science'` key added (jss 1–3) in `lib/core/data/nerdc_curriculum.dart`;
  `'biology'` retains sss 1–3. Braces verified balanced; `getNerdcTopics` needs no change.
- Task 3: all hunks applied to `lib/features/lesson/screens/lessons_list_screen.dart`.
- Validation: `flutter analyze` on the three changed lib files → 1 warning only
  (pre-existing, `sync_service.dart:2784` in `_upsertSubjectFromSync`, from commit `f9e51df`,
  untouched by this work). `flutter test` on lesson_editor/reader_layout/dashboard_layout →
  14/14 passed. `deno check` NOT run (deno not installed; supabase CLI present but needs
  Docker for `functions serve`) — sync-push edits are small and reviewed inline.

Scope: ClassAI Flutter + Supabase app. Investigation is read-only (one live-DB
`information_schema` SELECT was run via the Management API; no writes).

---

## Task 1 — Scheme-of-work sync push (highest priority)

### 1.1 Investigation — sync-push (`supabase/functions/sync-push/index.ts`)

**Finding: the premise that "the Edge Function has no handler for `scheme_of_work`" is
stale. A complete handler already exists in the committed tree** (added over several
commits: `621b0ca`, `d45073b`, `e1a6b72`, `e855d48`, `d5f6735`). Evidence below.

**1.1.1 `scheme_of_work` is in the syncable allowlist** (`SYNCABLE_TABLES`, lines 703–711):

```ts
const SYNCABLE_TABLES = new Set([
  "lessons", "exams", "progress_logs",
  "subjects", "teachers", "schools",
  "scheme_of_work", "vault_items",
  "payment_events",
  "credit_spend",
]);
```

**1.1.2 `resolveForeignKeys` has a dedicated `scheme_of_work` block** (lines 325–390)
which is exactly what the task asked for — school/teacher scoping from the JWT (never
client-supplied), UUID validation of `subject_id`, admin gating, defaults, and stripping
of local-only fields:

```ts
  if (table === "scheme_of_work") {
    // ── 1. School: Override from JWT — never trust client-supplied values ─
    const jwtSchoolId = jwtClaims["school_id"] as string | undefined;
    if (!jwtSchoolId) { ... return `Foreign key could not be resolved ...`; }
    rowData["school_id"] = jwtSchoolId;
    rowData["school_server_id"] = jwtSchoolId;

    // ── 2. Teacher: Override from JWT — same pattern as school_id ─────
    const jwtTeacherId = jwtClaims["teacher_id"] as string | undefined;
    if (!jwtTeacherId) { ... return `...`; }
    rowData["teacher_id"] = jwtTeacherId;
    rowData["teacher_server_id"] = jwtTeacherId;

    // ── 3. Subject_id: validate UUID format ─────────────────────────
    if (rowData["subject_id"]) {
      const subId = rowData["subject_id"] as string;
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(subId)) {
        delete rowData["subject_id"];
      }
    }

    // ── 4. Admin-gated fields: only admins may set status to
    //    'approved'/'rejected', or write admin_edited_topic/admin_comment ──
    const isAdmin = jwtClaims.is_admin === true;
    ... (skips entry with `Admin access required` when violated) ...

    // ── 5. Apply defaults ────────────────────────────────────────────
    for (const [col, defaultVal] of Object.entries(SCHEME_OF_WORK_DEFAULTS)) { ... }

    // ── 6. Remove local-only fields ──────────────────────────────────
    delete rowData["teacher_server_id"];
    delete rowData["school_server_id"];
    delete rowData["local_id"];
  }
```

**1.1.3 Operation paths (all generic, apply to `scheme_of_work`):**

- **INSERT** (lines ~566–616): if the payload carries `server_id` it does
  `upsert({ onConflict: "server_id" })` (stale-INSERT crash recovery); otherwise a plain
  `.insert()`. Server generates the UUID and echoes it back as `server_id`.
- **UPDATE** (lines ~644–682): requires `server_id` in the payload; writes exactly the
  fields the client sent after `resolveForeignKeys`.
- **DELETE** (lines ~684–757): **soft-delete** — `.update({ is_deleted: true }).eq("id", serverIdStr)`,
  with an idempotent short-circuit when the id is not a UUID.

**1.1.4 sync-pull (`supabase/functions/sync-pull/index.ts`) — `scheme_of_work` is already
pulled and school-scoped** (lines 97–108):

```ts
const scopedTables = new Set([
  "teachers", "lessons", "exams", "subjects",
  "scheme_of_work", "vault_items", "progress_logs",
  "payment_events", "schools",
]);
```

The client requests it too: `SupabaseSyncRemoteApi._syncableTables`
(`lib/core/services/sync_service.dart` line 252) includes `'scheme_of_work'`, and the
client merge pipeline is fully wired: `_mergeRemoteChange` (`sync_service.dart` ~1890),
`_upsertSchemeOfWorkFromSync` (~2799, resolves school/teacher/subject server UUIDs to
local integer FKs), and `schemeOfWorkMergeStrategies` (`merge_strategies.dart` line 30).

### 1.2 Server schema vs client payload (read-only query, run against live DB)

Query run (via `run_supabase_query.ps1`, Management API, SELECT only):
`SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_name = 'scheme_of_work' ORDER BY ordinal_position;`

Live `scheme_of_work` columns (project `zbqhxqnkoggckxoyoqox`):

| column | type | nullable | default |
|---|---|---|---|
| id | uuid | NO | gen_random_uuid() |
| school_id | uuid | NO | — |
| subject_id | uuid | NO | — |
| term | text | NO | — |
| week_number | integer | NO | — |
| topic | text | NO | — |
| objectives | text | NO | — |
| created_at | timestamptz | NO | now() |
| updated_at | timestamptz | NO | now() |
| update_counter | integer | NO | 0 |
| deleted_at | timestamptz | YES | — |
| last_modified_by | uuid | YES | — |
| server_id | text | YES | — |
| teacher_id | uuid | YES | — |
| status | text | NO | 'draft' |
| admin_edited_topic | text | YES | — |
| admin_comment | text | YES | — |
| class_level | text | NO | '' |
| is_deleted | boolean | NO | false |

**Client INSERT payload** (`SchemeOfWorkService._insertWeekRow`, `scheme_of_work_service.dart`):
`teacher_server_id, school_server_id, subject_id (subject's server UUID), term, week_number,
topic, objectives, status, admin_edited_topic, admin_comment, class_level`.

**Match verdict: every required NOT NULL column is covered** — `school_id`/`teacher_id` come
from the JWT override, `subject_id` passes through as a validated UUID, and
`created_at/updated_at/update_counter/is_deleted/status/class_level` are defaulted server-side.
**Subject-resolution approach picked: pass-through of the client's `subject_server_id`**
(the client already resolves `subject_id` to the subject's server UUID before queueing, and
the server validates UUID format). No server-side local-id→UUID lookup is needed, matching
the task's "or assume the payload includes a subject_server_id" option.

### 1.3 The real gaps (both currently break cross-device sync of plans)

**Gap A — UPDATE entries never reach the server (root cause of "plans created on one
device won't appear on others" for edits/approvals).** Every `scheme_of_work` UPDATE
payload — `scheme_of_work_service.dart:83`, `scheme_of_work_screen.dart:488` (submit
for approval) and `:564` (admin approve) — **omits `server_id`**. The server's UPDATE
branch requires it:

```ts
const serverId = getValue(fullRowData, "server_id", "serverId", "id");
if (!serverId) {
  results.push({ local_id: localId, server_id: null, status: "error", retryable: true });
  continue;
}
```

The client only injects `server_id` for **stale INSERTs** (`sync_service.dart` `_pushChanges`
lines 1307–1318: `if (effectiveOperation == 'INSERT')` → `_getServerIdForQueueEntry`).
So an admin approval, "Submit for approval", or admin topic edit queues an UPDATE with no
`server_id` → server rejects → retryable error → **stuck in the queue forever; the status
change never syncs to other devices.** (Lessons/exams UPDATE payloads have the same
omission — see `lesson_editor_screen.dart:1076` — so this is a generic engine bug, fixed
once.)

**Gap B — server writes don't bump `updated_at`, so even successful writes don't
propagate.** `sync-pull` returns rows with `updated_at > lastSyncTimestamp` only
(`sync-pull/index.ts` line 113). Client payloads never include `updated_at` (verified:
no `'updated_at':` in any DAO/service queue payload), and no DB trigger touches it
(the only `scheme_of_work` trigger is the realtime-events recorder from
`20260518_add_realtime_events.sql`, which does not modify `updated_at`). Therefore:
- **UPDATE** (after Gap A is fixed): row fields change but `updated_at` stays at INSERT
  time → peers never re-fetch it.
- **DELETE** (soft-delete): `is_deleted=true` but `updated_at` unchanged → peers never
  learn the plan was deleted; it lingers on their devices indefinitely.

**INSERT is fine** — `created_at`/`updated_at` default to `now()`.

### 1.4 Proposed fixes (NOT applied — for review)

**Fix 1 — client, generic (root cause of Gap A).** In `lib/core/services/sync_service.dart`
`_pushChanges`, inject `server_id` from the local record for UPDATE/DELETE entries that
lack it, same mechanism already used for stale INSERTs:

```diff
       String effectiveOperation = entry.operation;
       if (effectiveOperation == 'INSERT') {
         final serverId = await _getServerIdForQueueEntry(db, entry);
         if (serverId != null && serverId.isNotEmpty) {
           debugPrint(
             '[PUSH-DIAG] Stale INSERT detected for ${entry.queueTable} '
             'localId=${entry.recordLocalId}, serverId=$serverId — '
             'injecting server_id, converting to upsert',
           );
           payload['server_id'] = serverId;
           effectiveOperation = 'UPDATE';
         }
       }
+      // ── Inject server_id for UPDATE/DELETE entries that lack it ──────
+      // DAO-crafted UPDATE payloads (scheme_of_work, lessons, exams) never
+      // include server_id, so the server's UPDATE branch rejects them with
+      // "missing server_id" and they retry forever — status changes (admin
+      // approval, submit-for-approval) and edits never reach other devices.
+      if (payload['server_id'] == null &&
+          (effectiveOperation == 'UPDATE' || effectiveOperation == 'DELETE')) {
+        final serverId = await _getServerIdForQueueEntry(db, entry);
+        if (serverId != null && serverId.isNotEmpty) {
+          payload['server_id'] = serverId;
+        }
+      }
       // ───────────────────────────────────────────────────────────────────
```

(`_getServerIdForQueueEntry` already resolves `scheme_of_work` — `sync_service.dart` line 3236.)

**Fix 2 — server, generic (Gap B).** In `supabase/functions/sync-push/index.ts`, bump
`updated_at` on UPDATE and on soft-delete so `sync-pull` picks the row up on peers:

```diff
           const updateSkipReason = await resolveForeignKeys(supabase, table, updateData, jwtClaims);
           if (updateSkipReason) { ... }
+          // Bump updated_at server-side: client payloads never include it and
+          // sync-pull only returns rows with updated_at > lastSyncTimestamp.
+          // Without this, an UPDATE (e.g. admin approval changing status)
+          // never propagates to other devices.
+          if (updateData["updated_at"] === undefined) {
+            updateData["updated_at"] = new Date().toISOString();
+          }
           const { error } = await supabase
             .from(table)
             .update(updateData)
             .eq("id", serverId);
```

```diff
-          const { error } = await supabase
-            .from(table)
-            .update({ is_deleted: true })
-            .eq("id", serverIdStr);
+          const { error } = await supabase
+            .from(table)
+            .update({
+              is_deleted: true,
+              // Bump updated_at so the soft-delete propagates to peers
+              // (sync-pull filters by updated_at > lastSyncTimestamp).
+              updated_at: new Date().toISOString(),
+            })
+            .eq("id", serverIdStr);
```

(Also sets `updated_at = now()` for DELETE exactly as the task spec requested. The
`deleted_at` column exists but is not written anywhere; not required for propagation —
noted as optional follow-up.)

**sync-pull: no change needed** — `scheme_of_work` is already pulled, school-scoped, and
`select("*")` returns every column the client's `_upsertSchemeOfWorkFromSync` reads.

---

## Task 2 — Rename JSS "Biology" → "Basic Science" in the curated list

### 2.1 Findings

- `lib/core/data/nerdc_curriculum.dart` lines 387–570: a single `'biology'` key holds
  `jss 1` (390–418), `jss 2` (420–448), `jss 3` (450–478), `sss 1` (480–508),
  `sss 2` (510–538), `sss 3` (540–568).
- The app already calls the JSS subject **"Basic Science"** everywhere else:
  `nerdcSubjects` and `defaultSubjects` in `lib/core/constants/curriculum_types.dart`
  (lines 42–60) contain `'Basic Science'`, never `'Biology'`. The admin Scheme of Work
  screen's subject dropdown and the Plan My Term dialog both use `nerdcSubjects`.
- **Consequence today:** picking "Basic Science" in the dialog calls
  `getNerdcTopics('Basic Science', …)` → key `'basic science'` → **misses the curated
  JSS topics and silently falls back to AI** even though curated JSS biology content exists.
- `getNerdcTopics` normalizes with `subject.trim().toLowerCase()`, so `'Basic Science'`
  → `'basic science'` already — **no helper change needed.**
- No tests reference `biology`/`basic science`/`getNerdcTopics` (grep of `test/` empty).

### 2.2 Proposed diff — `lib/core/data/nerdc_curriculum.dart` (NOT applied)

The jss/sss blocks are byte-identical; only the key structure and two comments move.
Three hunks:

```diff
-  // ─────────────────────────── BIOLOGY ───────────────────────────
-  // Note: at JSS level this is the biology strand of Basic Science.
-  'biology': {
-    'jss 1': {
+  // ─────────────────────────── BASIC SCIENCE ───────────────────────────
+  // Basic Science is the JSS-level subject in the Nigerian curriculum.
+  // (The SSS-level Biology strand lives under 'biology' below.)
+  'basic science': {
+    'jss 1': {
       [unchanged JSS 1 weeks]
     },
-    'jss 2': {
+    'jss 2': {
       [unchanged JSS 2 weeks]
     },
-    'jss 3': {
+    'jss 3': {
       [unchanged JSS 3 weeks]
     },
+  },
+
+  // ─────────────────────────── BIOLOGY ───────────────────────────
+  'biology': {
     'sss 1': {
       [unchanged SSS 1 weeks]
     },
     'sss 2': {
       [unchanged SSS 2 weeks]
     },
     'sss 3': {
       [unchanged SSS 3 weeks]
     },
   },
```

Effect: `'basic science'` now contains jss 1–3; `'biology'` contains only sss 1–3.
`getNerdcTopics('Basic Science', 'JSS 1', …)` now hits the curated list instead of
falling back to AI. No other file references the `'biology'` curriculum key.

---

## Task 3 — Option-3 UI: two-button dialog + Refresh Plan

All changes are in `lib/features/lesson/screens/lessons_list_screen.dart`
(`_AutoGenerateDialog`, `_AutoGenerateSelection`, `_openAutoGenerateDialog`,
`_runAutoGenerate`, the AppBar button, and a small button-state helper).
`SchemeOfWorkService.saveScheme` needs **no signature change** — `forceAI` is handled in
the screen's generation method, as the task allows.

### 3.1 Design (per spec)

- Dialog gains a second choice; the selection result carries a `useAI` flag.
- "Use Built-in Topics" (FilledButton, primary) → curated if available, else AI fallback
  (today's logic). "Get New Topics Online" (OutlinedButton) → forces AI; if offline,
  SnackBar "This option needs an internet connection." and no-op.
- When a plan exists for the current subject/class/term filters, the AppBar button shows
  "Refresh Plan" (`Icons.refresh_rounded`); otherwise "Plan My Term"
  (`Icons.auto_awesome_rounded`).
- Refresh flow: dialog (same two buttons) → confirmation dialog with the exact warning
  copy → `_runAutoGenerate(deleteExistingFirst: true, forceAI: <choice>)` — atomic
  replace inside `saveScheme`'s single transaction via the existing
  `_deleteExistingPlan`.
- The existing "Replace your plan?" prompt inside `_runAutoGenerate` stays as a safety
  net for the create path only (when the user changes the combo in the dialog); in
  refresh mode the caller has already confirmed.

### 3.2 Proposed diff — `lib/features/lesson/screens/lessons_list_screen.dart` (NOT applied)

**Hunk 1 — state field + button-state helper** (near `_loadSchemesForDisplay`, lines 60–101):

```diff
   bool _filtersExpanded = true;
   bool _autoGenerating = false;
+  bool _hasPlanForFilters = false;
   final Map<int, SchemeOfWorkData> _schemesById = {};
```

```diff
   Future<void> _loadSchemesForDisplay() async {
     try {
       final db = ref.read(databaseProvider);
       ...
       if (mounted) {
         setState(() {
           _schemesById
             ..clear()
             ..addAll(schemeMap);
         });
       } else {
         _schemesById
           ..clear()
           ..addAll(schemeMap);
       }
+      await _refreshPlanButtonState();
     } catch (_) {
       // Display-only; failure is not worth interrupting the screen.
     }
   }
+
+  /// Recomputes whether a saved plan exists for the currently selected
+  /// subject/class/term filters — drives the "Plan My Term" ↔ "Refresh Plan"
+  /// button label. 'All' filters mean no specific plan can be targeted, so
+  /// the button stays on "Plan My Term".
+  Future<void> _refreshPlanButtonState() async {
+    try {
+      final db = ref.read(databaseProvider);
+      final authState = ref.read(authProvider);
+      final school = authState.currentSchool ?? await db.schoolsDao.get();
+      final teacherServerId = authState.currentTeacher?.serverId;
+      final teacher = teacherServerId != null
+          ? await db.teachersDao.findByServerId(teacherServerId)
+          : null;
+      final hasPlan = school != null &&
+          teacher != null &&
+          _selectedSubjectFilter != 'All' &&
+          _selectedClassFilter != 'All' &&
+          _selectedTermFilter != 'All' &&
+          (await SchemeOfWorkService(db).findSchemes(
+                schoolId: school.localId,
+                teacherId: teacher.localId,
+                subject: _selectedSubjectFilter,
+                classLevel: _selectedClassFilter,
+                term: _selectedTermFilter,
+              ))
+              .isNotEmpty;
+      if (mounted && hasPlan != _hasPlanForFilters) {
+        setState(() => _hasPlanForFilters = hasPlan);
+      }
+    } catch (_) {
+      // Display-only — failure leaves the button on "Plan My Term".
+    }
+  }
```

**Hunk 2 — filter setters refresh the button state** (lines 392–406):

```diff
   void _setTermFilter(String filter) {
     setState(() => _selectedTermFilter = filter);
+    _refreshPlanButtonState();
     SharedPreferences.getInstance().then((prefs) {
       prefs.setString('${_prefPrefix}term', filter);
     });
   }

   void _setClassFilter(String filter) {
     setState(() => _selectedClassFilter = filter);
+    _refreshPlanButtonState();
     SharedPreferences.getInstance().then((prefs) {
       prefs.setString('${_prefPrefix}class', filter);
     });
   }

   void _setSubjectFilter(String filter) {
     setState(() => _selectedSubjectFilter = filter);
+    _refreshPlanButtonState();
     SharedPreferences.getInstance().then((prefs) {
       prefs.setString('${_prefPrefix}subject', filter);
     });
   }
```

**Hunk 3 — `_openAutoGenerateDialog`** (lines 134–172): detect existing plan, pass
`isRefresh`, enforce offline for the online option, show the refresh confirmation, and
pass `forceAI`/`deleteExistingFirst`:

```diff
   Future<void> _openAutoGenerateDialog() async {
     final prefs = await SharedPreferences.getInstance();
     final savedSubject = prefs.getString(_prefAutoGenerateSubject) ?? 'Mathematics';
     final savedClass = prefs.getString(_prefAutoGenerateClass) ?? 'JSS 1';
     final savedTerm = prefs.getString(_prefAutoGenerateTerm) ?? '1st Term';

     final subject =
         _selectedSubjectFilter != 'All' ? _selectedSubjectFilter : savedSubject;
     final classLevel =
         _selectedClassFilter != 'All' ? _selectedClassFilter : savedClass;
     final termLabel =
         _selectedTermFilter != 'All' ? _selectedTermFilter : savedTerm;

     final filterSubjects = _selectedSubjectFilter != 'All'
         ? [_selectedSubjectFilter]
         : const <String>[];
     final subjectOptions =
         <String>[...filterSubjects, ...nerdcSubjects].toSet().toList();

+    // Detect an existing plan for the effective subject/class/term so the
+    // dialog and button switch to "Refresh Plan" mode.
+    final db = ref.read(databaseProvider);
+    final authState = ref.read(authProvider);
+    final school = authState.currentSchool ?? await db.schoolsDao.get();
+    final teacherServerId = authState.currentTeacher?.serverId;
+    final teacher = teacherServerId != null
+        ? await db.teachersDao.findByServerId(teacherServerId)
+        : null;
+    final existingPlan = (school != null && teacher != null)
+        ? await SchemeOfWorkService(db).findSchemes(
+            schoolId: school.localId,
+            teacherId: teacher.localId,
+            subject: subject,
+            classLevel: classLevel,
+            term: termLabel,
+          )
+        : const <SchemeOfWorkData>[];
+    final isRefresh = existingPlan.isNotEmpty;

     final selection = await showDialog<_AutoGenerateSelection>(
       context: context,
       builder: (ctx) => _AutoGenerateDialog(
         subjectOptions: subjectOptions,
         initialSubject: subject,
         initialClassLevel: classLevel,
         initialTerm: termLabel,
+        isRefresh: isRefresh,
       ),
     );
     if (selection == null || !mounted) return;

+    // "Get New Topics Online" requires internet — check before doing anything.
+    if (selection.useAI && !await PlatformHelper.isOnline()) {
+      ScaffoldMessenger.of(context).showSnackBar(
+        const SnackBar(
+          content: Text('This option needs an internet connection.'),
+        ),
+      );
+      return;
+    }
+
     await prefs.setString(_prefAutoGenerateSubject, selection.subject);
     await prefs.setString(_prefAutoGenerateClass, selection.classLevel);
     await prefs.setString(_prefAutoGenerateTerm, selection.termLabel);

-    await _runAutoGenerate(selection);
+    // Refresh mode: confirm before atomically replacing the existing plan.
+    if (isRefresh && mounted) {
+      final proceed = await showDialog<bool>(
+        context: context,
+        builder: (ctx) => AlertDialog(
+          title: const Text('Refresh your plan?'),
+          content: Text(
+            'This will replace your existing plan for $subject, $classLevel, '
+            '$termLabel with fresh topics. Your previously generated lesson '
+            'content will be kept, but topic titles may change. Continue?',
+          ),
+          actions: [
+            TextButton(
+              onPressed: () => Navigator.of(ctx).pop(false),
+              child: const Text('Cancel'),
+            ),
+            FilledButton(
+              onPressed: () => Navigator.of(ctx).pop(true),
+              child: const Text('Refresh Plan'),
+            ),
+          ],
+        ),
+      );
+      if (proceed != true || !mounted) return;
+    }
+
+    await _runAutoGenerate(
+      selection,
+      forceAI: selection.useAI,
+      deleteExistingFirst: isRefresh,
+    );
   }
```

**Hunk 4 — `_runAutoGenerate`** (lines 174–306): accept `forceAI` + `deleteExistingFirst`,
skip the curated check when forcing AI, keep the create-path safety confirm, and pass the
effective delete flag:

```diff
-  Future<void> _runAutoGenerate(_AutoGenerateSelection selection) async {
+  Future<void> _runAutoGenerate(
+    _AutoGenerateSelection selection, {
+    bool forceAI = false,
+    bool deleteExistingFirst = false,
+  }) async {
     if (mounted) setState(() => _autoGenerating = true);
     try {
       ...
-      // ── 1. Build the 13-week topic list (curated first, AI fallback) ──
+      // ── 1. Build the 13-week topic list ─────────────────────────────
+      // forceAI skips the curated list entirely so the teacher can
+      // intentionally regenerate topics from the AI ("Get New Topics Online").
       List<Map<String, dynamic>> weeks;
-      final curated = getNerdcTopics(
-        selection.subject, selection.classLevel, selection.termLabel);
+      final curated = forceAI
+          ? null
+          : getNerdcTopics(
+              selection.subject, selection.classLevel, selection.termLabel);
       if (curated != null) {
       ...
       // ── 3. Already have a plan? Warn before deleting + recreating ──
       final existing = await service.findSchemes(
         schoolId: school.localId,
         teacherId: teacher.localId,
         subject: selection.subject,
         classLevel: selection.classLevel,
         term: selection.termLabel,
       );
-      if (existing.isNotEmpty) {
+      // In refresh mode the caller already confirmed; only re-prompt when the
+      // create dialog picked a combo that matches an existing plan.
+      if (existing.isNotEmpty && !deleteExistingFirst) {
         if (!mounted) return;
         final recreate = await showDialog<bool>( ... );   // unchanged
         if (recreate != true || !mounted) return;
       }

       // ── 4. Write (and if needed replace) everything in one transaction ──
       await service.saveScheme(
         schoolId: school.localId,
         teacherId: teacher.localId,
         subject: selection.subject,
         classLevel: selection.classLevel,
         term: _termForStorage(selection.termLabel),
         weeks: weeks,
-        deleteExistingFirst: existing.isNotEmpty,
+        deleteExistingFirst: deleteExistingFirst || existing.isNotEmpty,
       );
```

**Hunk 5 — AppBar button** (lines 516–525): label + icon driven by `_hasPlanForFilters`:

```diff
               if (ref.read(authProvider).currentTeacher?.role != 'admin') ...[
                 FilledButton.tonalIcon(
                   onPressed: _autoGenerating ? null : _openAutoGenerateDialog,
-                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
-                  label: const Text('Plan My Term'),
+                  icon: Icon(
+                    _hasPlanForFilters
+                        ? Icons.refresh_rounded
+                        : Icons.auto_awesome_rounded,
+                    size: 18,
+                  ),
+                  label: Text(
+                    _hasPlanForFilters ? 'Refresh Plan' : 'Plan My Term',
+                  ),
                   style: FilledButton.styleFrom(
                     padding: const EdgeInsets.symmetric(horizontal: 14),
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(14),
```

**Hunk 6 — `_AutoGenerateSelection`** (lines 1534–1540): add `useAI`:

```diff
 class _AutoGenerateSelection {
   final String subject;
   final String classLevel;
   final String termLabel;
+  final bool useAI;
 
-  const _AutoGenerateSelection(this.subject, this.classLevel, this.termLabel);
+  const _AutoGenerateSelection(
+    this.subject,
+    this.classLevel,
+    this.termLabel, {
+    this.useAI = false,
+  });
 }
```

**Hunk 7 — `_AutoGenerateDialog`** (lines 1542–1635): `isRefresh` field, refresh-aware
title/copy, and the two action buttons:

```diff
 class _AutoGenerateDialog extends StatefulWidget {
   const _AutoGenerateDialog({
     required this.subjectOptions,
     required this.initialSubject,
     required this.initialClassLevel,
     required this.initialTerm,
+    required this.isRefresh,
   });
 
   final List<String> subjectOptions;
   final String initialSubject;
   final String initialClassLevel;
   final String initialTerm;
+  final bool isRefresh;
   ...
   @override
   Widget build(BuildContext context) {
     return AlertDialog(
-      title: const Text('Plan My Term'),
+      title: Text(widget.isRefresh ? 'Refresh Plan' : 'Plan My Term'),
       content: Column(
         mainAxisSize: MainAxisSize.min,
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text(
-            'This will create a complete scheme of work for '
-            '$_subject, $_classLevel, $_term with 13 weekly topics and '
-            'linked draft lessons. Ready?',
+            widget.isRefresh
+                ? 'Replace the existing scheme of work for '
+                    '$_subject, $_classLevel, $_term with 13 fresh weekly '
+                    'topics and linked draft lessons.'
+                : 'Create a complete scheme of work for '
+                    '$_subject, $_classLevel, $_term with 13 weekly topics '
+                    'and linked draft lessons.',
             style: Theme.of(context).textTheme.bodyMedium,
           ),
           ... (dropdowns unchanged) ...
         ],
       ),
       actions: [
         TextButton(
           onPressed: () => Navigator.of(context).pop(),
           child: const Text('Cancel'),
         ),
-        FilledButton(
+        OutlinedButton(
           onPressed: () => Navigator.of(context).pop(
-            _AutoGenerateSelection(_subject, _classLevel, _term),
+            _AutoGenerateSelection(_subject, _classLevel, _term, useAI: true),
           ),
-          child: const Text('Create'),
+          child: const Text('Get New Topics Online'),
+        ),
+        FilledButton(
+          onPressed: () => Navigator.of(context).pop(
+            _AutoGenerateSelection(_subject, _classLevel, _term),
+          ),
+          child: const Text('Use Built-in Topics'),
         ),
       ],
     );
   }
 }
```

### 3.3 Notes

- Offline handling for the forced-AI path lives in `_openAutoGenerateDialog` (exact
  SnackBar copy from spec); the pre-existing curated-miss fallback offline check inside
  `_runAutoGenerate` remains for the "built-in topics" path when a combo is uncovered.
- `deleteExistingFirst: true` reuses `SchemeOfWorkService._deleteExistingPlan` (hard-delete
  scheme rows, soft-delete linked draft lessons/exams, queue DELETE entries) **inside the
  same transaction** as the new insert — atomic replace as designed.
- After a successful save, `_loadSchemesForDisplay()` (already called) now also refreshes
  `_hasPlanForFilters`, so the button flips back to "Plan My Term".
- `_termForStorage('1st Term')` → `'First'` and `findSchemes`'s `_normalizeTermKey` handle
  the storage-label mapping for refresh detection. ✓

---

## Validation plan (after approval, before commit)

1. `flutter analyze --no-pub` on the two changed lib files.
2. `flutter test` on lessons-list-related widget tests (`test/features/lesson_editor_test.dart`
   and any `lessons_list` tests).
3. Deno `deno check supabase/functions/sync-push/index.ts` (or `supabase functions serve`)
   to typecheck the Edge Function changes.
4. Manual two-device check: create plan on A → B pulls it; admin approves on B → A sees
   `approved`; delete plan on A → B no longer lists it.

## Open questions for review

1. **Fix 1 is generic (lessons/exams too).** The lesson-editor UPDATE payload has the same
   missing-`server_id` flaw; fixing it engine-side heals all three tables at once. OK, or
   scope the injection to `scheme_of_work` only?
2. **Fix 2's UPDATE bump:** safe today because clients never send `updated_at`; the
   `=== undefined` guard keeps it that way if they ever do. OK?
3. Should the DELETE path also write `deleted_at = now()` (column exists, unused)?
4. Confirm deploy of sync-push after approval — I will not deploy.
