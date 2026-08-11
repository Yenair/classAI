# Scheme of Work UX Redesign — Full Implementation Summary (for AI handoff)

Everything from the SoW UX redesign proposal through the implemented "Plan My Term"
feature, with the code that landed. Written so another AI (or you) can pick up the
work without re-discovering the codebase.

---

## 1. The problem

The old flow forced teachers to open a dedicated Scheme of Work screen, create a
scheme (subject/class/term/week/topic), then separately link lessons to it in the
lesson editor. For low-literacy users this was far too many screens, taps, and
decisions, and it silently produced unlinked ("orphaned") lessons. The audit
counted ~9–13 taps across 4 screens, with 5 confusion points (approval vocabulary,
misleading "No approved scheme" hint, silent unlinked saves, etc.).

## 2. The approved design (Design A + curated NERDC list)

1. **Curated NERDC topics are the primary source of topic titles.** A static Dart
   file maps subject → class → term → 13 weeks of topics+objectives. If a combo is
   covered, **no AI call is made at all** (instant, offline, deterministic).
   Missing combos fall back to the existing AI `PromptTemplates.schemeOfWork` path.
2. **"Plan My Term" button on the Lessons list** (teachers only) creates the whole
   scheme + 13 linked draft lessons (+ linked draft exams) in one action. The
   dedicated SoW screen is **admin-only** now (approval workflow preserved).
3. **Silent draft seeding (`_bootstrapSchemeDrafts`) removed** — no more invisible
   duplicate drafts; plan creation is explicit only.
4. **Atomic recreate:** when the teacher confirms "Create Again", the old plan is
   deleted *inside the same DB transaction* that writes the new one — no window
   where the old plan is gone and the new one failed to save.

## 3. Files

| File | Status | Role |
|---|---|---|
| `lib/core/data/nerdc_curriculum.dart` | **new** (598 ln) | Curated topics + `getNerdcTopics()` |
| `lib/core/services/scheme_of_work_service.dart` | **new** (462 ln) | Shared save/delete transaction + `parseSchemeWeeks` |
| `lib/core/database/daos/scheme_of_work_dao.dart` | +12 ln | Added `hardDelete(int id)` |
| `lib/features/lesson/screens/lessons_list_screen.dart` | edited | "Plan My Term" button/dialog/flow; seeding removed |
| `lib/features/scheme_of_work/screens/scheme_of_work_screen.dart` | edited | `_saveScheme` → thin wrapper over the service |
| `lib/router/app_router.dart` | edited | `/scheme-of-work` admin-only |
| `lib/features/dashboard/screens/dashboard_screen.dart` | edited | SoW nav hidden for teachers (both layouts) |

## 4. Key code (as landed)

### 4.1 Curated data + helper — `lib/core/data/nerdc_curriculum.dart`

```dart
class NerdcWeekTopic {
  final String topic;
  final List<String> objectives;
  const NerdcWeekTopic(this.topic, this.objectives);
}

// subject (lowercase) → class ('jss 1'..'sss 3') → term ('1st'|'2nd'|'3rd') → 13 weeks
const Map<String, Map<String, Map<String, List<NerdcWeekTopic>>>> nerdcCurriculum = {
  'mathematics': {
    'jss 1': {
      '1st': [
        NerdcWeekTopic('Whole Numbers: Counting and Writing Numbers in Words',
            ['Count and write numbers in words up to millions',
             'Identify place values of digits in large numbers']),
        // ... 13 weeks for Math / English Studies / Biology, JSS1–SSS3, 1st term
      ],
    },
  },
};

/// Returns curated topics, or null → caller falls back to AI generation.
List<NerdcWeekTopic>? getNerdcTopics(String subject, String classLevel, String term) {
  final subjectKey = subject.trim().toLowerCase();
  final classKey = _normalizeClassKey(classLevel); // 'JSS1'/'Jss 1' → 'jss 1'
  final termKey = _normalizeTermKey(term);         // 'First'/'1st term' → '1st'
  return nerdcCurriculum[subjectKey]?[classKey]?[termKey];
}
```

### 4.2 The shared transaction — `lib/core/services/scheme_of_work_service.dart`

Everything runs in **one Drift transaction**. `deleteExistingFirst` performs the
recreate safely: delete old rows + linked drafts, then write the new plan, all
atomically.

```dart
Future<Map<int, int>> saveScheme({
  required int schoolId,
  required int teacherId,
  required String subject,
  required String classLevel,
  required String term,
  required List<Map<String, dynamic>> weeks, // {'week', 'topic', 'objectives'}
  Map<int, int> existingWeekRecordIds = const {},
  bool deleteExistingFirst = false,
}) {
  return db.transaction(() async {
    if (deleteExistingFirst) {
      await _deleteExistingPlan(
        schoolId: schoolId, teacherId: teacherId, subject: subject,
        classLevel: classLevel, term: term);
    }
    var subjectId = await _resolveOrInsertSubjectId(schoolId, subject);
    // ... per week: upsert scheme row (update if existingId != null, else insert),
    // queue sync entries, then auto-create linked draft lesson + exam
    // (duplicate-guarded by schemeOfWorkId + subject/class/term/week match).
    return weekRecordIds; // weekNumber → scheme row id
  });
}
```

The recreate delete (inside the same transaction):

```dart
Future<void> _deleteExistingPlan({
  required int schoolId, required int teacherId,
  required String subject, required String classLevel, required String term,
}) async {
  final rows = await findSchemes(schoolId: schoolId, teacherId: teacherId,
      subject: subject, classLevel: classLevel, term: term);
  for (final row in rows) {
    // Linked draft lessons/exams: soft-delete via existing DAO + queue DELETE
    // when the row has a server id (mirrors _confirmDeleteLesson pattern).
    await db.lessonsDao.deleteLesson(lesson.id);
    // ... exams likewise ...
    if (row.serverId != null && row.serverId!.isNotEmpty) {
      await db.syncQueueDao.insertEntry(queueTable: 'scheme_of_work',
          recordLocalId: row.id, operation: 'DELETE',
          payload: {'id': row.id, 'server_id': row.serverId});
    }
    await db.schemeOfWorkDao.hardDelete(row.id); // added DAO method
  }
}
```

### 4.3 The teacher flow — `lessons_list_screen.dart`

Button (AppBar, teachers only, disabled while running):

```dart
if (ref.read(authProvider).currentTeacher?.role != 'admin') ...[
  FilledButton.tonalIcon(
    onPressed: _autoGenerating ? null : _openAutoGenerateDialog,
    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
    label: const Text('Plan My Term'),
    ...
  ),
  const SizedBox(width: 8),
],
```

Generation pipeline (curated → AI fallback → recreate warning → atomic save):

```dart
List<Map<String, dynamic>> weeks;
final curated = getNerdcTopics(selection.subject, selection.classLevel, selection.termLabel);
if (curated != null) {
  weeks = [ for (var i = 0; i < curated.length; i++)
    { 'week': i + 1, 'topic': curated[i].topic,
      'objectives': curated[i].objectives.join('\n') } ];
} else {
  if (!await PlatformHelper.isOnline()) { /* "No internet connection" SnackBar; return */ }
  final aiService = AiService(db: db);
  await aiService.checkDailyLimit(school.subscriptionTier.isEmpty ? 'free' : school.subscriptionTier);
  final result = await aiService.generate(
      PromptTemplates.schemeOfWork(selection.subject, selection.classLevel, selection.termLabel));
  weeks = parseSchemeWeeks(result);   // shared parser in the service file
  if (weeks.isEmpty) throw Exception('AI returned no weeks');
}

final existing = await service.findSchemes(...);   // same subject/class/term?
if (existing.isNotEmpty) {
  final recreate = await showDialog<bool>(...);     // "Replace your plan?" confirm
  if (recreate != true || !mounted) return;
}

await service.saveScheme(
  schoolId: school.localId, teacherId: teacher.localId,
  subject: selection.subject, classLevel: selection.classLevel,
  term: _termForStorage(selection.termLabel), // '1st Term' → 'First' (matches legacy rows)
  weeks: weeks,
  deleteExistingFirst: existing.isNotEmpty,     // ← atomic fix
);
ref.invalidate(lessonsListProvider);
```

Confirmation dialog copy (per spec):

```
'This will create a complete scheme of work for $_subject, $_classLevel, $_term
with 13 weekly topics and linked draft lessons. Ready?'
```

Silent seeding replaced with a display-only lookup (labels still work; no inserts):

```dart
Future<void> _loadSchemesForDisplay() async {
  // loads saved schemes into _schemesById (with setState) so lesson-card
  // term labels resolve — does NOT create lessons.
}
```

### 4.4 Admin screen wrapper — `scheme_of_work_screen.dart`

`_saveScheme` (was ~275 lines) is now a thin call into the same service — the two
paths can never drift apart:

```dart
final service = SchemeOfWorkService(db);
final weeks = _weeks.map((week) {
  final weekNumber = (week['week'] as int?) ?? 0;
  return <String, dynamic>{
    'week': weekNumber,
    'topic': _topicControllers[weekNumber]?.text ?? week['topic']?.toString() ?? '',
    'objectives': _objectivesControllers[weekNumber]?.text ?? week['objectives']?.toString() ?? '',
  };
}).toList();
_weekRecordIds = await service.saveScheme(
  schoolId: _schoolId!, teacherId: _teacherId!,
  subject: _subject, classLevel: _classLevel, term: _term,
  weeks: weeks, existingWeekRecordIds: _weekRecordIds,
);
// _submitForApproval needs the resolved subject id afterwards:
_subjectId = await service.findSubjectId(schoolId: _schoolId!, subject: _subject);
```

### 4.5 Gating — router + dashboard

```dart
// app_router.dart — /scheme-of-work joined the admin-only routes
final isAdminRoute =
    location == '/admin' ||
    location.startsWith('/admin/teachers/') ||
    location == '/scheme-of-work';
// (the old "accessible by both roles" override was removed)
```

```dart
// dashboard_screen.dart — editor side-nav: admin-only SoW item
if (isAdmin)
  NavItem(icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),

// reader bottom-nav: spec-driven destinations; teachers get 4 tabs, admins 5
List<_ReaderNavSpec> get _navSpecs {
  final isAdmin = ref.read(authProvider).currentTeacher?.role == 'admin';
  final specs = <_ReaderNavSpec>[
    const _ReaderNavSpec(icon: Icons.home_rounded, label: 'Home', route: 'home'),
    const _ReaderNavSpec(icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons', isFilled: true),
    const _ReaderNavSpec(icon: Icons.quiz_rounded, label: 'Exams', route: 'exams'),
    if (isAdmin)
      const _ReaderNavSpec(icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
    const _ReaderNavSpec(icon: Icons.more_horiz_rounded, label: 'More', route: '/settings'),
  ];
  // index assigned = position in list (isActive uses it)
  return specs;
}
// _onNavDestination switches on the route string, not the index, so the
// index shift when the SoW tab is hidden can't misroute taps.
```

## 5. Behaviors & edge cases handled

- **Offline + curated combo** → works with no network at all (topics are local).
- **Offline + missing combo** → clear "No internet connection" message, aborts.
- **Duplicate plan** → warning dialog → only proceeds on explicit confirm.
- **Partial failure** → single `db.transaction` rolls everything back.
- **Malformed AI output** → shared `parseSchemeWeeks` throws → caught → error SnackBar.
- **Duplicate drafts** → lesson/exam creation is guarded by scheme id + subject/class/term/week match (same guard the old `_saveScheme` used).
- **Admin re-save** → `existingWeekRecordIds` triggers the UPDATE branch (no duplicate rows) and `_subjectId` is re-resolved for `_submitForApproval`.

## 6. Verification (per project AGENTS.md: `flutter analyze --no-pub`, changed files only)

```
flutter analyze --no-pub <7 changed files>
Analyzing 7 items...
No issues found! (ran in 39.4s)
```

Two warnings introduced mid-work were fixed: unused `drift` import (bootstrap
removed) and `currentTeacher?.localId?.toString()` (the second `?.` is illegal —
`Teacher.localId` is a non-nullable `int`).

## 7. Known issues / open items (important to tell the next AI)

1. **Pre-existing sync gap (unfixed):** `scheme_of_work` rows are queued locally
   but the server push path for schemes is broken. Regeneration queues local
   deletes/inserts; server-side rows may not reflect them until that sync path is
   fixed. Recommended before shipping.
2. **Data accuracy:** NERDC topics were drafted from public curriculum knowledge —
   recommend a subject-teacher review pass. 2nd/3rd terms + other subjects fall
   back to AI, so nothing breaks.
3. **JSS "Biology"** is really the biology strand of Basic Science (Biology is an
   SSS subject). The JSS entries exist; drop them if undesired.
4. **Scheme rows are hard-deleted on recreate** (no `isDeleted` filter exists on
   scheme queries, so soft-delete wouldn't hide them). Linked lessons/exams are
   soft-deleted. The plan is recreated immediately in the same transaction.

## 8. Working-tree hygiene

- **Nothing is committed.** The implementation is uncommitted in the working tree.
- Some edited files (e.g., `lessons_list_screen.dart`) also carry **pre-existing
  uncommitted user changes** (collapsible filter panel, back-button behavior,
  `flutter/services.dart` import removal) that predate this work — do not assume
  those are part of the feature, and do not discard them.
- New files are untracked: `lib/core/data/nerdc_curriculum.dart`,
  `lib/core/services/scheme_of_work_service.dart`.
- Per AGENTS.md: never `flutter clean` / `dart analyze`; use
  `flutter analyze --no-pub <changed files>`; no new dependencies were added.
