import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/constants/curriculum_types.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/widgets/status_chip.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

final selectedSchemeTeacherSelection = ValueNotifier<int?>(null);

final schemeOfWeeksProvider = FutureProvider.family<List<SchemeOfWorkData>, int>(
  (ref, schoolId) async {
    final db = ref.read(databaseProvider);
    return db.schemeOfWorkDao.getBySchool(schoolId);
  },
);

class SchemeOfWorkScreen extends ConsumerStatefulWidget {
  const SchemeOfWorkScreen({super.key});

  @override
  ConsumerState<SchemeOfWorkScreen> createState() => _SchemeOfWorkScreenState();
}

class _SchemeOfWorkScreenState extends ConsumerState<SchemeOfWorkScreen> {
  bool _isAdmin = false;
  int? _schoolId;
  int? _selectedTeacherId;

  final Map<int, String> _teacherNamesById = {};
  final Map<int, String> _subjectNamesById = {};
  List<Teacher> _teachers = [];

  // Admin filters ('' / null = "All")
  int? _adminFilterTeacher; // null = All Teachers
  String _adminFilterSubject = '';
  String _adminFilterClass = '';
  String _adminFilterTopic = '';
  String _adminFilterTerm = '';

  Map<int, TextEditingController> _adminEditControllers = {};
  List<SchemeOfWorkData> _existingSowRecords = [];
  final Map<String, List<Lesson>> _linkedLessonsBySchemeId = {};

  final List<String> _terms = ['First', 'Second', 'Third'];
  final Set<String> _expandedAdminGroups = {};

  /// Wide layout: the teacher panel can be collapsed to a slim rail so the
  /// scheme list gets the full width.
  bool _teachersPanelCollapsed = false;

  final List<String> _classLevels = [
    'JSS 1', 'JSS 2', 'JSS 3',
    'SSS 1', 'SSS 2', 'SSS 3',
    'Primary 1', 'Primary 2', 'Primary 3',
    'Primary 4', 'Primary 5', 'Primary 6',
  ];

  String _friendlyTerm(String t) {
    switch (t.trim().toLowerCase()) {
      case 'first':
      case '1st':
        return 'First Term';
      case 'second':
      case '2nd':
        return 'Second Term';
      case 'third':
      case '3rd':
        return 'Third Term';
      default:
        return t;
    }
  }

  /// 'First' / '1st term' / 'first' → 'first' (likewise second/third) so
  /// internal term comparisons, admin filtering, and admin grouping stay
  /// stable regardless of casing. The DB stores the lowercase value after the
  /// v27 migration; the UI dropdown still shows the title-case labels.
  String _normalizeTermKey(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) {
      return 'first';
    }
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) {
      return 'second';
    }
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) {
      return 'third';
    }
    return lower;
  }

  /// Normalizes class level values like `JSS1`, `JSS 1` or `jss 1` to the
  /// canonical `JSS 1` form used by class filter comparisons, class options,
  /// grouping keys, and week label display.
  String _normalizeClassLevel(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.isEmpty) return compact;
    final upper = compact.toUpperCase();
    final jss = RegExp(r'^JSS\s*(\d+)$').firstMatch(upper);
    if (jss != null) return 'JSS ${jss.group(1)}';
    final sss = RegExp(r'^SSS\s*(\d+)$').firstMatch(upper);
    if (sss != null) return 'SSS ${sss.group(1)}';
    final primary = RegExp(r'^PRIMARY\s*(\d+)$').firstMatch(upper);
    if (primary != null) return 'Primary ${primary.group(1)}';
    return compact
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  int _classSortIndex(String classLevel) {
    final index = _classLevels.indexOf(classLevel);
    return index == -1 ? _classLevels.length : index;
  }

  /// The effective topic shown and edited by the admin: the admin-edited
  /// value when one exists, otherwise the teacher's original topic.
  String _effectiveTopic(SchemeOfWorkData record) {
    final edited = record.adminEditedTopic;
    if (edited != null && edited.isNotEmpty) return edited;
    return record.topic;
  }

  /// Expansion keys use the normalized subject and class values.
  String _adminGroupKey(String subject, String classLevel) =>
      '$subject\u0000$_normalizeClassLevel(classLevel)';

  /// Expands the single group uniquely identified by the current subject and
  /// class filters. Broad (or empty) filters leave groups collapsed.
  void _applyFilterExpansion() {
    if (_adminFilterSubject.isNotEmpty && _adminFilterClass.isNotEmpty) {
      _expandedAdminGroups
          .add(_adminGroupKey(_adminFilterSubject, _adminFilterClass));
    }
  }

  List<String> _classFilterOptions() {
    final options = <String>[..._classLevels];
    for (final record in _existingSowRecords) {
      final normalized = _normalizeClassLevel(record.classLevel);
      // An empty stored class level (sync can blank these) would duplicate the
      // "All Classes" item and trip DropdownButton's single-match assert.
      if (normalized.isEmpty) continue;
      if (!options.contains(normalized)) options.add(normalized);
    }
    return options;
  }

  List<String> _topicFilterOptions() {
    final options = <String>{};
    for (final record in _existingSowRecords) {
      final topic = _effectiveTopic(record).trim();
      if (topic.isNotEmpty) options.add(topic);
    }
    final sorted = options.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAuthInfo();
    });
  }

  Future<void> _loadAuthInfo() async {
    try {
      final authData = ref.read(authProvider);
      _isAdmin = authData.currentTeacher?.role == 'admin';
      final db = ref.read(databaseProvider);

      // Look up the school by serverId from auth state (not by schoolsDao.get())
      // to ensure we match the correct school record, since schoolsDao.get()
      // returns the first non-deleted school which may not match the admin's school.
      final schoolServerId = authData.currentSchool?.serverId;
      int? resolvedSchoolId;
      if (schoolServerId != null) {
        final schoolByServerId = await (db.select(db.schools)
              ..where((s) => s.serverId.equals(schoolServerId)))
            .getSingleOrNull();
        if (schoolByServerId != null) {
          resolvedSchoolId = schoolByServerId.localId;
        }
      }
      if (resolvedSchoolId == null) {
        final fallbackSchool = await db.schoolsDao.get();
        if (fallbackSchool != null) {
          resolvedSchoolId = fallbackSchool.localId;
        }
      }
      _schoolId = resolvedSchoolId;

      // Reconcile legacy teacher rows before querying, fixing stale schoolLocalId
      await db.reconcileLegacyTeachers();

      final teachers = _schoolId != null
          ? await db.teachersDao.getBySchool(_schoolId!)
          : await db.teachersDao.getAll();
      _teachers = teachers;
      if (teachers.isNotEmpty) {
        final preferredTeacherId = selectedSchemeTeacherSelection.value;
        final teacherIds = teachers.map((t) => t.localId).toSet();
        final selectedTeacher = preferredTeacherId != null &&
                teacherIds.contains(preferredTeacherId)
            ? teachers.firstWhere((t) => t.localId == preferredTeacherId)
            : teachers.first;
        _selectedTeacherId = selectedTeacher.localId;
      }
      for (final teacher in teachers) {
        _teacherNamesById[teacher.localId] = teacher.teacherName;
      }

      // Preload subject name map for admin filters
      final allSubjects = await db.subjectsDao.getAll();
      for (final subject in allSubjects) {
        _subjectNamesById[subject.id] = subject.name;
      }

      // Admin-only view: preload all school schemes so the filtered view works
      if (_isAdmin && _schoolId != null) {
        await _loadExistingSow();
        debugPrint('[SOW ADMIN] Loaded ${_existingSowRecords.length} total schemes for school $_schoolId');
      }
    } catch (_) {}
  }

  /// Single source of admin data and UI refresh:
  /// 1. Load scheme records.
  /// 2. Load linked lessons.
  /// 3. Rebuild lookup data.
  /// 4. Rebuild admin edit controllers safely.
  /// 5. Call setState once when mounted.
  Future<List<SchemeOfWorkData>?> _loadExistingSow() async {
    if (_schoolId == null) return null;
    final db = ref.read(databaseProvider);
    try {
      if (_isAdmin && _teachers.isNotEmpty) {
        // Admin view: schemes may have stale schoolId values, so query by
        // teacher IDs from the correctly-filtered school teacher list instead
        // of relying on scheme_of_work.schoolId. The dashboard also uses this
        // approach (queries by teacherId alone, see admin_provider.dart:252).
        final teacherIds = _teachers.map((t) => t.localId).toSet();
        final allSchoolSchemes = await db.schemeOfWorkDao.getAll();
        _existingSowRecords = allSchoolSchemes
            .where((s) => teacherIds.contains(s.teacherId) && !s.isDeleted)
            .toList();
      } else {
        _existingSowRecords = await db.schemeOfWorkDao.getBySchool(_schoolId!);
      }
      await _loadLinkedLessons(db);
      await _rebuildLookupData(db);
      _disposeAdminEditControllers();
      _hydrateAdminEditControllers(_existingSowRecords);
      debugPrint('[SOW ADMIN] _loadExistingSow returned ${_existingSowRecords.length} records for school $_schoolId');
      if (mounted) setState(() {});
      return _existingSowRecords;
    } on FormatException catch (e) {
      debugPrint('[SOW] Skipped corrupted scheme_of_work row: $e');
      await db.customStatement(
        "DELETE FROM scheme_of_work WHERE typeof(created_at) != 'integer' OR typeof(updated_at) != 'integer'",
      );
      _existingSowRecords = [];
      if (mounted) setState(() {});
      return null;
    }
  }

  /// Loads non-deleted lessons linked to the loaded scheme records by
  /// `lesson.schemeOfWorkId == record.id.toString()`.
  Future<void> _loadLinkedLessons(AppDatabase db) async {
    _linkedLessonsBySchemeId.clear();
    if (_existingSowRecords.isEmpty) return;
    final schemeIds = _existingSowRecords.map((r) => r.id.toString()).toSet();
    // getAll() only returns non-deleted lessons.
    final allLessons = await db.lessonsDao.getAll();
    for (final lesson in allLessons) {
      if (lesson.isDeleted) continue;
      final schemeId = lesson.schemeOfWorkId;
      if (schemeId == null || !schemeIds.contains(schemeId)) continue;
      _linkedLessonsBySchemeId.putIfAbsent(schemeId, () => []).add(lesson);
    }
  }

  Future<void> _rebuildLookupData(AppDatabase db) async {
    _teacherNamesById.clear();
    for (final teacher in _teachers) {
      _teacherNamesById[teacher.localId] = teacher.teacherName;
    }
    _subjectNamesById.clear();
    final allSubjects = await db.subjectsDao.getAll();
    for (final subject in allSubjects) {
      _subjectNamesById[subject.id] = subject.name;
    }
  }

  /// Recreates the admin topic controllers using the effective topic
  /// (adminEditedTopic when non-empty, otherwise topic). Empty values stay
  /// empty so the placeholder shows.
  void _hydrateAdminEditControllers(List<SchemeOfWorkData> records) {
    for (final record in records) {
      _adminEditControllers[record.id] =
          TextEditingController(text: _effectiveTopic(record));
    }
  }

  void _disposeAdminEditControllers() {
    for (final c in _adminEditControllers.values) {
      c.dispose();
    }
    _adminEditControllers = {};
  }

  Future<void> _adminApprove(int schemeWeekId) async {
    try {
      final db = ref.read(databaseProvider);
      if (await _hasLessonOrExamReferences(db, schemeWeekId)) {
        await _showReferencedSchemeWarning();
        return;
      }
      final adminEdit = _adminEditControllers[schemeWeekId]?.text.trim();
      if (adminEdit != null && adminEdit.isNotEmpty) {
        await db.schemeOfWorkDao.updateAdminEditedTopic(schemeWeekId, adminEdit);
      }
      await db.schemeOfWorkDao.updateStatus(schemeWeekId, 'approved');

      // Fetch the approved scheme week to get metadata for draft creation & sync
      final schemeWeek = await db.schemeOfWorkDao.getById(schemeWeekId);
      if (schemeWeek != null) {
        final teacher = await db.teachersDao.getById(schemeWeek.teacherId);
        final teacherServerId = teacher?.serverId;
        // _schoolId is the correct localId resolved in _loadAuthInfo — use
        // getByLocalId (not get()) to avoid returning the wrong school row.
        final school = await db.schoolsDao.getByLocalId(_schoolId!);
        final schoolServerId = school?.serverId;
        final termLabel = _normalizeTermLabelForDraft(schemeWeek.term);
        final classLevel = schemeWeek.classLevel;
        final subjectRow = await db.subjectsDao.getById(schemeWeek.subjectId);
        final subjectName = subjectRow?.name ?? '';
        final weekNumber = schemeWeek.weekNumber;
        final topic = adminEdit != null && adminEdit.isNotEmpty
            ? adminEdit
            : schemeWeek.topic;

        // Resolve subject server ID for sync payload
        final subjectServerId = subjectRow?.serverId;

        // Queue the status change for sync (only if subject has a server ID)
        if (subjectServerId != null) {
          try {
            await db.syncQueueDao.insertEntry(
              queueTable: 'scheme_of_work',
              recordLocalId: schemeWeekId,
              operation: 'UPDATE',
              payload: {
                'status': 'approved',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'subject_id': subjectServerId,
                'term': normalizeSowTermForServer(schemeWeek.term),
                'week_number': schemeWeek.weekNumber,
                'topic': schemeWeek.topic,
                'objectives': schemeWeek.objectives,
                'class_level': schemeWeek.classLevel,
                'admin_edited_topic': schemeWeek.adminEditedTopic,
                'admin_comment': schemeWeek.adminComment,
              },
            );
          } catch (_) {
            // Non-critical — sync failure shouldn't block approval
          }
        }

        if (teacherServerId != null &&
            termLabel.isNotEmpty &&
            subjectName.isNotEmpty &&
            classLevel.isNotEmpty) {
          // Check for and create draft lesson
          final existingLessons = await db.lessonsDao.getAll();
          final lessonExists = existingLessons.any((l) {
            if (l.isDeleted ||
                (l.status != 'draft' && l.status != 'generated')) {
              return false;
            }
            // Fallback: same scheme_of_work_id (resilient to subject being
            // wiped to '' by sync pull before the empty-remote guard fix).
            final existingSchemeId = int.tryParse(l.schemeOfWorkId ?? '');
            if (existingSchemeId == schemeWeekId) return true;
            if (l.teacherServerId == teacherServerId &&
                l.classLevel == classLevel &&
                (l.term ?? '') == termLabel &&
                (l.weekNumber ?? l.week) == weekNumber) {
              return true;
            }
            return false;
          });
          if (!lessonExists) {
            final lessonId = await db.lessonsDao.insertLesson(
              LessonsCompanion.insert(
                subject: subjectName,
                classLevel: classLevel,
                week: weekNumber,
                topic: topic,
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: jsonEncode({
                  'objectives': [],
                  'vocabulary': [],
                  'materials': [],
                  'presentation': [],
                  'assessment': '',
                  'homework': '',
                }),
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                schemeOfWorkId: Value(schemeWeekId.toString()),
                weekNumber: Value(weekNumber),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                term: Value(termLabel),
              ),
            );
            final lessonContent = jsonEncode({
              'objectives': [],
              'vocabulary': [],
              'materials': [],
              'presentation': [],
              'assessment': '',
              'homework': '',
            });
            await db.syncQueueDao.insertEntry(
              queueTable: 'lessons',
              recordLocalId: lessonId,
              operation: 'INSERT',
              payload: {
                'subject': subjectName,
                'class_level': classLevel,
                'week': weekNumber,
                'topic': topic,
                'difficulty': 'medium',
                'blooms_verbs': '',
                'curriculum': 'NERDC',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'content': lessonContent,
                'content_hash': lessonContent.hashCode.toString(),
                'is_unlocked': false,
                'scheme_of_work_id': schemeWeekId.toString(),
                'week_number': weekNumber,
                'term': termLabel,
              },
            );
          }
        }
      }

      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Approved!');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Approve failed: $e');
      }
    }
  }

  Future<void> _adminReject(int schemeWeekId) async {
    try {
      final db = ref.read(databaseProvider);
      if (await _hasLessonOrExamReferences(db, schemeWeekId)) {
        await _showReferencedSchemeWarning();
        return;
      }
      await db.schemeOfWorkDao.updateStatus(schemeWeekId, 'rejected',
          adminComment: 'Rejected by admin');
      await _loadExistingSow();
      if (mounted) {
        showInfoToast(context: context, message: 'Rejected.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Reject failed: $e');
      }
    }
  }

  Future<bool> _hasLessonOrExamReferences(AppDatabase db, int schemeId) async {
    final schemeIdStr = schemeId.toString();
    final lessonRefs = await (db.select(db.lessons)
          ..where((t) => t.schemeOfWorkId.equals(schemeIdStr))
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    if (lessonRefs.isNotEmpty) return true;

    final examRefs = await (db.select(db.exams)
          ..where((t) => t.schemeOfWorkId.equals(schemeIdStr))
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    return examRefs.isNotEmpty;
  }

  Future<void> _showReferencedSchemeWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scheme in Use'),
        content: const Text(
          'This approved scheme is already linked to lessons or exams. '
          'Please remove those references before editing or deleting it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _normalizeTermLabelForDraft(String term) {
    final cleaned = term.trim();
    if (cleaned.isEmpty) return '';
    final lower = cleaned.toLowerCase();
    if (lower.contains('1st') || lower.contains('first') || lower == '1') {
      return '1st Term';
    }
    if (lower.contains('2nd') || lower.contains('second') || lower == '2') {
      return '2nd Term';
    }
    if (lower.contains('3rd') || lower.contains('third') || lower == '3') {
      return '3rd Term';
    }
    return cleaned;
  }

  @override
  void dispose() {
    _disposeAdminEditControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 768;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scheme of Work',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Review and update teachers scheme of work',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Home',
          ),
        ],
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: SafeArea(
        child: isWide
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _teachersPanelCollapsed ? 64 : 320,
                      child: _buildTeacherSelectorPanel(theme, cs),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildAdminFilters(theme, cs),
                          const SizedBox(height: 16),
                          Expanded(
                            child: _buildAdminSchemeList(theme, cs),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildTeacherDropdown(theme, cs),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildAdminFilters(theme, cs),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: _buildAdminSchemeList(theme, cs),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTeacherSelectorPanel(ThemeData theme, ColorScheme cs) {
    if (_teachersPanelCollapsed) {
      // Collapsed: a slim rail that still shows the teacher count.
      return Card(
        color: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () =>
                    setState(() => _teachersPanelCollapsed = false),
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Show teachers',
              ),
              const SizedBox(height: 4),
              Icon(
                Icons.groups_rounded,
                size: 20,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                '${_teachers.length}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Teachers',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      setState(() => _teachersPanelCollapsed = true),
                  icon: const Icon(Icons.chevron_left_rounded),
                  tooltip: 'Collapse teachers',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // The tile list is bounded by the panel's height so a school with
            // many teachers scrolls instead of overflowing the card.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._teachers.map(
                      (teacher) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildTeacherSelectorTile(theme, cs, teacher),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherSelectorTile(
    ThemeData theme,
    ColorScheme cs,
    Teacher teacher,
  ) {
    final isSelected = teacher.localId == _selectedTeacherId;
    return Material(
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _selectTeacher(teacher.localId),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.35)
                  : cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: cs.primaryContainer,
                foregroundColor: cs.onPrimaryContainer,
                child: Text(
                  _getInitials(teacher.teacherName),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      teacher.teacherName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      teacher.email,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.chevron_right_rounded : Icons.chevron_right,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherDropdown(ThemeData theme, ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<int>(
          initialValue: _selectedTeacherId,
          decoration: const InputDecoration(
            labelText: 'Select teacher',
          ),
          items: _teachers
              .map(
                (teacher) => DropdownMenuItem<int>(
                  value: teacher.localId,
                  child: Text(teacher.teacherName),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              _selectTeacher(value);
            }
          },
        ),
      ),
    );
  }

  List<SchemeOfWorkData> _selectedTeacherSchemes() {
    final selectedTeacherId = _selectedTeacherId;
    if (selectedTeacherId == null) return [];
    final records = _existingSowRecords
        .where((r) => r.teacherId == selectedTeacherId && !r.isDeleted)
        .toList()
      ..sort((a, b) {
        final subjectCompare = a.subjectId.compareTo(b.subjectId);
        if (subjectCompare != 0) return subjectCompare;
        return a.weekNumber.compareTo(b.weekNumber);
      });
    return records;
  }

  Future<void> _selectTeacher(int teacherId) async {
    if (_selectedTeacherId == teacherId) return;
    setState(() {
      _selectedTeacherId = teacherId;
      // Sync the admin filter so the admin view is filtered by this teacher
      _adminFilterTeacher = teacherId;
    });
    selectedSchemeTeacherSelection.value = teacherId;
    await _loadExistingSow();
  }

  Future<void> _bulkApproveSelectedTeacher() async {
    final records = _selectedTeacherSchemes()
        .where((record) => record.status != 'approved')
        .toList();
    for (final record in records) {
      await _adminApprove(record.id);
    }
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Widget _buildAdminFilterDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    // DropdownButtonFormField asserts that exactly one item matches its value.
    // A filter value can go stale (record deleted, label blanked by a sync), so
    // fall back to the first entry ("All …") instead of asserting and taking
    // the whole screen down with a layout error.
    final int matchCount = items.where((item) => item.value == value).length;
    final T safeValue = matchCount == 1 || items.isEmpty
        ? value
        : items.first.value as T;
    return DropdownButtonFormField<T>(
      initialValue: safeValue,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildAdminFilters(ThemeData theme, ColorScheme cs) {
    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter schemes',
              style: theme.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 180,
                    child: _buildAdminFilterDropdown<int?>(
                      label: 'Filter by Teacher',
                      value: _adminFilterTeacher,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Teachers'),
                        ),
                        ..._teachers.map(
                          (teacher) => DropdownMenuItem<int?>(
                            value: teacher.localId,
                            child: Text(teacher.teacherName),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _adminFilterTeacher = v;
                        // Keep the teacher panel — and the Bulk Approve
                        // action, which is scoped to the selected teacher —
                        // on the teacher being reviewed.
                        if (v != null) _selectedTeacherId = v;
                        _applyFilterExpansion();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: _buildAdminFilterDropdown<String>(
                      label: 'Filter by Subject',
                      value: _adminFilterSubject,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Subjects'),
                        ),
                        ...nerdcSubjects.map(
                          (s) => DropdownMenuItem<String>(value: s, child: Text(s)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _adminFilterSubject = v ?? '';
                        _applyFilterExpansion();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: _buildAdminFilterDropdown<String>(
                      label: 'Filter by Class',
                      value: _adminFilterClass,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Classes'),
                        ),
                        ..._classFilterOptions().map(
                          (c) => DropdownMenuItem<String>(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _adminFilterClass = v ?? '';
                        _applyFilterExpansion();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: _buildAdminFilterDropdown<String>(
                      label: 'Filter by Topic',
                      value: _adminFilterTopic,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Topics'),
                        ),
                        ..._topicFilterOptions().map(
                          (t) => DropdownMenuItem<String>(value: t, child: Text(t)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _adminFilterTopic = v ?? '';
                        _applyFilterExpansion();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 180,
                    child: _buildAdminFilterDropdown<String>(
                      label: 'Filter by Term',
                      value: _adminFilterTerm,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Text('All Terms'),
                        ),
                        ..._terms.map(
                          (t) => DropdownMenuItem<String>(value: t, child: Text(t)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _adminFilterTerm = v ?? '';
                        _applyFilterExpansion();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _adminFilterTeacher = null;
                        _adminFilterSubject = '';
                        _adminFilterClass = '';
                        _adminFilterTopic = '';
                        _adminFilterTerm = '';
                        _expandedAdminGroups.clear();
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off),
                    label: const Text('Clear Filters'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminSchemeList(ThemeData theme, ColorScheme cs) {
    if (_existingSowRecords.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_rounded, size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text('No schemes submitted yet',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Ask teachers to generate a scheme of work.',
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final filtered = _existingSowRecords.where(_matchesAdminFilters).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('No schemes match the current filters.',
              style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
        ),
      );
    }

    // Group records by normalized subject -> normalized class. Term and week
    // subsections are rendered inside each subject/class group.
    final grouped = <String, List<SchemeOfWorkData>>{};
    for (final record in filtered) {
      final subject = _subjectNamesById[record.subjectId] ?? 'Unknown Subject';
      final classLevel = _normalizeClassLevel(record.classLevel);
      final key = _adminGroupKey(subject, classLevel);
      grouped.putIfAbsent(key, () => []).add(record);
    }

    final groupKeys = grouped.keys.toList()
      ..sort((a, b) => _compareAdminGroups(a, b, grouped));

    // Schemes of the teacher selected in the side panel that still need a
    // decision. The bulk action lives in the list header now that the old
    // review banner is gone.
    final pendingForTeacher = _selectedTeacherSchemes()
        .where((record) => record.status != 'approved')
        .toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'All Schemes (Admin)',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (pendingForTeacher.isNotEmpty)
              Tooltip(
                message:
                    'Approve ${pendingForTeacher.length} pending scheme${pendingForTeacher.length != 1 ? 's' : ''} for the selected teacher',
                child: FilledButton.icon(
                  onPressed: _bulkApproveSelectedTeacher,
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Bulk Approve'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final key in groupKeys) ...[
          _buildAdminGroupSection(theme, cs, key, grouped[key]!),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  bool _matchesAdminFilters(SchemeOfWorkData record) {
    // Teacher filter
    if (_adminFilterTeacher != null && record.teacherId != _adminFilterTeacher) {
      return false;
    }
    // Subject filter: compare by subjectId using the name map
    if (_adminFilterSubject.isNotEmpty) {
      final subjectName = _subjectNamesById[record.subjectId] ?? '';
      if (_adminFilterSubject != subjectName) return false;
    }
    // Class filter: compare using normalized class values
    if (_adminFilterClass.isNotEmpty &&
        _normalizeClassLevel(record.classLevel) != _adminFilterClass) {
      return false;
    }
    // Topic filter: compare using the effective topic text
    if (_adminFilterTopic.isNotEmpty &&
        _effectiveTopic(record) != _adminFilterTopic) {
      return false;
    }
    // Term filter
    if (_adminFilterTerm.isNotEmpty &&
        _normalizeTermKey(_adminFilterTerm) != _normalizeTermKey(record.term)) {
      return false;
    }
    return true;
  }

  /// Sort order: subject, then class, then (inside each group) term order and
  /// ascending week number.
  int _compareAdminGroups(
    String keyA,
    String keyB,
    Map<String, List<SchemeOfWorkData>> grouped,
  ) {
    final recordA = grouped[keyA]!.first;
    final recordB = grouped[keyB]!.first;
    final subjectA = (_subjectNamesById[recordA.subjectId] ?? '').toLowerCase();
    final subjectB = (_subjectNamesById[recordB.subjectId] ?? '').toLowerCase();
    final subjectCompare = subjectA.compareTo(subjectB);
    if (subjectCompare != 0) return subjectCompare;
    final classA = _normalizeClassLevel(recordA.classLevel);
    final classB = _normalizeClassLevel(recordB.classLevel);
    final classIndexCompare =
        _classSortIndex(classA).compareTo(_classSortIndex(classB));
    if (classIndexCompare != 0) return classIndexCompare;
    return classA.compareTo(classB);
  }

  Widget _buildAdminGroupSection(
    ThemeData theme,
    ColorScheme cs,
    String key,
    List<SchemeOfWorkData> records,
  ) {
    final subject = _subjectNamesById[records.first.subjectId] ?? 'Unknown Subject';
    final classLevel = _normalizeClassLevel(records.first.classLevel);
    final isExpanded = _expandedAdminGroups.contains(key);

    // Group records by normalized term key, then sort each term's weeks.
    final byTerm = <String, List<SchemeOfWorkData>>{};
    for (final record in records) {
      final termKey = _normalizeTermKey(record.term);
      byTerm.putIfAbsent(termKey, () => []).add(record);
    }
    for (final termRecords in byTerm.values) {
      termRecords.sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
    }

    return Card(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedAdminGroups.remove(key);
                } else {
                  _expandedAdminGroups.add(key);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$subject · $classLevel',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${records.length} week${records.length != 1 ? 's' : ''}',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final termLabel in _terms)
                    if (byTerm.containsKey(_normalizeTermKey(termLabel))) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Text(
                          _friendlyTerm(termLabel),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      for (final record in byTerm[_normalizeTermKey(termLabel)]!)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildAdminSchemeCard(theme, cs, record),
                        ),
                    ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAdminSchemeCard(ThemeData theme, ColorScheme cs, SchemeOfWorkData record) {
    final linkedLessons =
        _linkedLessonsBySchemeId[record.id.toString()] ?? const <Lesson>[];
    return Card(
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Week ${record.weekNumber} · ${_friendlyTerm(record.term)} · ${_normalizeClassLevel(record.classLevel)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                schemeStatusChip(record.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('Teacher: ${_teacherNamesById[record.teacherId] ?? 'Unknown Teacher'}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('Teacher Topic: ${record.topic}', style: theme.textTheme.bodyMedium),
            if (record.adminEditedTopic != null && record.adminEditedTopic!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Admin Edited: ${record.adminEditedTopic}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary)),
              ),
            const SizedBox(height: 4),
            Text(record.objectives, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Admin Edit Topic (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              controller: _adminEditControllers[record.id] ??= TextEditingController(),
            ),
            const SizedBox(height: 8),
            ..._buildLinkedLessonsSection(theme, cs, linkedLessons),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                if (record.status != 'approved')
                  TextButton.icon(
                    onPressed: () => _adminApprove(record.id),
                    icon: Icon(Icons.check_circle, color: cs.primary),
                    label: const Text('Approve'),
                  ),
                if (record.status != 'rejected')
                  TextButton.icon(
                    onPressed: () => _adminReject(record.id),
                    icon: Icon(Icons.cancel, color: cs.error),
                    label: const Text('Reject'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLinkedLessonsSection(
    ThemeData theme,
    ColorScheme cs,
    List<Lesson> lessons,
  ) {
    if (lessons.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'No linked lesson',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ];
    }
    return [
      for (final lesson in lessons)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  lessonStatusChipFor(lesson.status),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lesson.topic,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              // Read the notes in place instead of navigating away mid-review.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () => _showLessonNotesDialog(lesson),
                    icon: const Icon(Icons.article_outlined, size: 18),
                    label: const Text('View notes'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/lessons/${lesson.id}'),
                    child: const Text('Open lesson', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ),
        ),
    ];
  }

  /// Shows the lesson's notes and diagrams in a dialog, so an admin can review
  /// the content without leaving the scheme of work.
  Future<void> _showLessonNotesDialog(Lesson lesson) async {
    final sections = _parseLessonNoteSections(lesson.content);
    final diagrams = _parseLessonDiagrams(lesson.content);
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final media = MediaQuery.of(ctx);
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: media.size.height * 0.85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lesson.topic,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${lesson.subject} · ${lesson.classLevel} · '
                              'Week ${lesson.weekNumber ?? lesson.week}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Flexible(
                  child: sections.isEmpty && diagrams.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notes_rounded,
                                size: 40,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No lesson notes yet.',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final section in sections)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildLessonNoteTile(theme, cs, section),
                                ),
                              if (diagrams.isNotEmpty)
                                _buildLessonDiagramsTile(theme, cs, diagrams),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLessonNoteTile(
    ThemeData theme,
    ColorScheme cs,
    _LessonNoteSection section,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    section.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (section.paragraph.isNotEmpty)
              Text(
                section.paragraph,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            for (final bullet in section.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        bullet,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonDiagramsTile(
    ThemeData theme,
    ColorScheme cs,
    List<Map<String, String>> diagrams,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insert_photo_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Diagrams',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final diagram in diagrams)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if ((diagram['imageUrl'] ?? '').isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          diagram['imageUrl']!,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            height: 120,
                            color: cs.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    if ((diagram['description'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        diagram['description']!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Reads the lesson content JSON into the note sections an admin needs to
  /// review, in the same order the lesson editor presents them.
  List<_LessonNoteSection> _parseLessonNoteSections(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      // Legacy rows can hold plain text rather than JSON.
      return [
        _LessonNoteSection(
          label: 'Lesson notes',
          icon: Icons.notes_rounded,
          paragraph: trimmed,
        ),
      ];
    }
    if (decoded is! Map<String, dynamic>) {
      return [
        _LessonNoteSection(
          label: 'Lesson notes',
          icon: Icons.notes_rounded,
          paragraph: trimmed,
        ),
      ];
    }

    const specs = <({String key, String label, IconData icon})>[
      (key: 'objectives', label: 'Objectives', icon: Icons.flag_rounded),
      (key: 'vocabulary', label: 'Vocabulary', icon: Icons.translate_rounded),
      (key: 'materials', label: 'Materials', icon: Icons.inventory_2_rounded),
      (key: 'presentation', label: 'Presentation', icon: Icons.menu_book_rounded),
      (
        key: 'assessment',
        label: 'Assessment',
        icon: Icons.assignment_turned_in_rounded
      ),
      (key: 'homework', label: 'Homework', icon: Icons.home_work_rounded),
    ];

    final sections = <_LessonNoteSection>[];
    for (final spec in specs) {
      final value = decoded[spec.key];
      final bullets = <String>[];
      var paragraph = '';
      if (value is List) {
        for (final entry in value) {
          final text = _noteEntryText(entry);
          if (text.isNotEmpty) bullets.add(text);
        }
      } else if (value != null) {
        paragraph = _noteEntryText(value);
      }
      if (bullets.isEmpty && paragraph.isEmpty) continue;
      sections.add(
        _LessonNoteSection(
          label: spec.label,
          icon: spec.icon,
          bullets: bullets,
          paragraph: paragraph,
        ),
      );
    }
    return sections;
  }

  String _noteEntryText(dynamic entry) {
    if (entry == null) return '';
    if (entry is String) return entry.trim();
    if (entry is Map) {
      final title = (entry['title'] ?? entry['heading'] ?? '').toString().trim();
      final body = (entry['body'] ??
              entry['content'] ??
              entry['text'] ??
              '')
          .toString()
          .trim();
      if (title.isEmpty) return body;
      if (body.isEmpty) return title;
      return '$title: $body';
    }
    return entry.toString().trim();
  }

  List<Map<String, String>> _parseLessonDiagrams(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return const [];
      final raw = decoded['diagrams'];
      if (raw is! List) return const [];
      final diagrams = <Map<String, String>>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final description = (entry['description'] ?? '').toString().trim();
        final imageUrl = (entry['imageUrl'] ?? '').toString().trim();
        if (description.isEmpty && imageUrl.isEmpty) continue;
        diagrams.add({'description': description, 'imageUrl': imageUrl});
      }
      return diagrams;
    } catch (_) {
      return const [];
    }
  }
}

/// One read-only note section shown in the lesson notes dialog.
class _LessonNoteSection {
  const _LessonNoteSection({
    required this.label,
    required this.icon,
    this.bullets = const [],
    this.paragraph = '',
  });

  final String label;
  final IconData icon;
  final List<String> bullets;
  final String paragraph;
}
