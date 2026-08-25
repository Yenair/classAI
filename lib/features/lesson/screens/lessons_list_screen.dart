import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:classai/core/database/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:classai/core/constants/curriculum_types.dart' show nerdcSubjects;
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/data/nerdc_curriculum.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/providers/pdf_service_provider.dart';
import 'package:classai/core/services/pdf_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/core/widgets/status_chip.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show lessonsListProvider;
import 'package:classai/main.dart' show databaseProvider;
import 'package:file_selector/file_selector.dart'
    show getSaveLocation, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;

/// lessonsListProvider is defined in
/// lib/features/dashboard/providers/dashboard_data_providers.dart.

/// One reversible delete performed on this screen. Holds the lesson snapshot
/// taken before the soft-delete, the id of the DELETE sync entry created by
/// this delete (null when the lesson has no server row), the ids of any
/// DELETE entries that were already pending for the lesson before this
/// delete, and the timer that performs the delayed remote diagram cleanup
/// once the Undo window elapses.
class _LessonDeleteRecord {
  _LessonDeleteRecord({
    required this.lesson,
    required this.queueEntryId,
    required this.pendingDeleteEntryIds,
    this.diagramCleanupTimer,
  });

  final Lesson lesson;

  /// Id of the DELETE sync entry created by this delete. Replaced on redo
  /// (the undo that preceded it removed the previous entry).
  int? queueEntryId;

  final List<int> pendingDeleteEntryIds;

  /// Timer for the delayed remote diagram deletion; cancelled by Undo and
  /// re-created by redo.
  Timer? diagramCleanupTimer;
}

/// Displays a list of lessons from the local database.
class LessonsListScreen extends ConsumerStatefulWidget {
  const LessonsListScreen({super.key});

  @override
  ConsumerState<LessonsListScreen> createState() => _LessonsListScreenState();
}

class _LessonsListScreenState extends ConsumerState<LessonsListScreen> {

  /// How long the Undo SnackBar stays visible. The DELETE sync entry created
  /// by a delete is held (`next_retry_at` in the future) and the remote
  /// diagram deletion is delayed for exactly this window, so neither can run
  /// before Undo is possible.
  static const _undoWindow = Duration(seconds: 4);

  /// Flow-local reversible command stack for deletes on this screen. Undo
  /// (SnackBar action or Ctrl+Z) restores the row, drops the held DELETE
  /// entry, and cancels the delayed diagram cleanup; redo (Ctrl+Y) re-applies
  /// the delete and re-queues both.
  final List<_LessonDeleteRecord> _undoStack = [];
  final List<_LessonDeleteRecord> _redoStack = [];

  /// Release timers for held DELETE entries, keyed by queue entry id. Each
  /// fires at the end of the Undo window and clears `next_retry_at` so the
  /// sync engine pushes the delete normally. Cancelled by Undo (the entry is
  /// removed anyway) and on dispose (the timestamp itself still auto-releases
  /// the entry).
  final Map<int, Timer> _heldDeleteTimers = {};

  @override
  void dispose() {
    for (final timer in _heldDeleteTimers.values) {
      timer.cancel();
    }
    _heldDeleteTimers.clear();
    super.dispose();
  }

  static const _termFilters = ['All', '1st Term', '2nd Term', '3rd Term'];
  static const _statusFilters = [
    _StatusFilterItem('All', Icons.layers_rounded),
    _StatusFilterItem('Draft', Icons.edit_note_rounded),
    _StatusFilterItem('Completed', Icons.check_circle_rounded),
    _StatusFilterItem('Unlocked', Icons.lock_open_rounded),
    _StatusFilterItem('Generated', Icons.auto_awesome_rounded),
  ];

  String _selectedStatusFilter = 'All';
  String _selectedTermFilter = 'All';
  String _selectedClassFilter = 'All';
  String _selectedSubjectFilter = 'All';
  bool _filtersExpanded = true;
  bool _hasPlanForFilters = false;
  bool _isExportingPdf = false;
  final Map<int, SchemeOfWorkData> _schemesById = {};

  /// Cache of lesson id → "content is an empty placeholder" computed once per
  /// loaded list (see [_rebuildContentEmptyCache]). Predicates read from this
  /// instead of parsing every lesson's content JSON on each filter render.
  Map<int, bool> _lessonContentEmptyById = {};

  static const _prefPrefix = 'lessons_filter_';

  @override
  void initState() {
    super.initState();
    _loadFilterPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(offlineCreditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
      _loadSchemesForDisplay();
    });
  }

  void _rebuildContentEmptyCache(List<Lesson> lessons) {
    final cache = <int, bool>{};
    for (final lesson in lessons) {
      cache[lesson.id] = _isLessonContentEmpty(lesson.content);
    }
    _lessonContentEmptyById = cache;
  }

  /// True when [content] is an empty placeholder (no populated sections), e.g.
  /// the rows auto-created from a scheme of work. Same logic as the lesson
  /// editor's helper, kept here so filter predicates can classify legacy rows.
  bool _isLessonContentEmpty(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return true;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) return true;
      final objectives = decoded['objectives'];
      final vocabulary = decoded['vocabulary'];
      final materials = decoded['materials'];
      final presentation = decoded['presentation'];
      final assessment = decoded['assessment'];
      final homework = decoded['homework'];
      return _isEmptyListOrBlank(objectives) &&
          _isEmptyListOrBlank(vocabulary) &&
          _isEmptyListOrBlank(materials) &&
          _isEmptyListOrBlank(presentation) &&
          _isEmptyListOrBlank(assessment) &&
          _isEmptyListOrBlank(homework);
    } catch (_) {
      // Non-JSON (e.g. encrypted) content counts as real content.
      return false;
    }
  }

  bool _isEmptyListOrBlank(dynamic value) {
    if (value == null) return true;
    if (value is List) return value.isEmpty;
    if (value is String) return value.trim().isEmpty;
    return false;
  }

  Future<void> _loadFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedStatusFilter = prefs.getString('${_prefPrefix}status') ?? 'All';
      _selectedTermFilter = prefs.getString('${_prefPrefix}term') ?? 'All';
      _selectedClassFilter = prefs.getString('${_prefPrefix}class') ?? 'All';
      _selectedSubjectFilter = prefs.getString('${_prefPrefix}subject') ?? 'All';
      _filtersExpanded = prefs.getBool('lessons_filters_expanded') ?? true;
    });
  }

  Future<void> _toggleFiltersExpanded() async {
    setState(() => _filtersExpanded = !_filtersExpanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('lessons_filters_expanded', _filtersExpanded);
  }

  /// Populates the scheme lookup used to display term labels on lesson
  /// cards. Does NOT create lessons — plan creation is now exclusively the
  /// explicit "Plan My Term" flow (silent draft seeding was removed).
  Future<void> _loadSchemesForDisplay() async {
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) return;

      final schemes = (await db.schemeOfWorkDao.getSaved())
          .where((scheme) => scheme.schoolId == school.localId)
          .toList();
      final schemeMap = <int, SchemeOfWorkData>{
        for (final scheme in schemes) scheme.id: scheme,
      };
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
      await _refreshPlanButtonState();
    } catch (_) {
      // Display-only; failure is not worth interrupting the screen.
    }
  }

  /// Recomputes whether a saved plan exists for the currently selected
  /// subject/class/term filters — drives the "Plan My Term" ↔ "Refresh Plan"
  /// button label. 'All' filters mean no specific plan can be targeted, so
  /// the button stays on "Plan My Term".
  Future<void> _refreshPlanButtonState() async {
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      final teacherServerId = authState.currentTeacher?.serverId;
      final teacher = teacherServerId != null
          ? await db.teachersDao.findByServerId(teacherServerId)
          : null;
      final hasPlan = school != null &&
          teacher != null &&
          _selectedSubjectFilter != 'All' &&
          _selectedClassFilter != 'All' &&
          _selectedTermFilter != 'All' &&
          (await SchemeOfWorkService(db).findSchemes(
                schoolId: school.localId,
                teacherId: teacher.localId,
                subject: _selectedSubjectFilter,
                classLevel: _selectedClassFilter,
                term: _selectedTermFilter,
              ))
              .isNotEmpty;
      if (mounted && hasPlan != _hasPlanForFilters) {
        setState(() => _hasPlanForFilters = hasPlan);
      }
    } catch (_) {
      // Display-only — failure leaves the button on "Plan My Term".
    }
  }

  static const _prefAutoGenerateSubject = 'auto_generate_subject';
  static const _prefAutoGenerateClass = 'auto_generate_class';
  static const _prefAutoGenerateTerm = 'auto_generate_term';

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

    // Subject options = any subject the teacher filters on + the curated
    // subjects, so a filter like "French" stays selected instead of silently
    // falling back to Mathematics.
    final filterSubjects = _selectedSubjectFilter != 'All'
        ? [_selectedSubjectFilter]
        : const <String>[];
    final subjectOptions =
        <String>[...filterSubjects, ...nerdcSubjects].toSet().toList();

    // Detect an existing plan for the pre-filled combo so the dialog can
    // hint at refresh mode. This only drives the dialog title — the teacher
    // may change subject/class/term inside the dialog, so the actual
    // "Refresh your plan?" confirmation is decided from the FINAL selection
    // below (and only fires when a plan exists for that exact combo).
    final db = ref.read(databaseProvider);
    final authState = ref.read(authProvider);
    final school = authState.currentSchool ?? await db.schoolsDao.get();
    final teacherServerId = authState.currentTeacher?.serverId;
    final teacher = teacherServerId != null
        ? await db.teachersDao.findByServerId(teacherServerId)
        : null;
    final existingPlan = (school != null && teacher != null)
        ? await SchemeOfWorkService(db).findSchemes(
            schoolId: school.localId,
            teacherId: teacher.localId,
            subject: subject,
            classLevel: classLevel,
            term: termLabel,
          )
        : const <SchemeOfWorkData>[];

    final selection = await showDialog<_AutoGenerateSelection>(
      context: context,
      builder: (ctx) => _AutoGenerateDialog(
        subjectOptions: subjectOptions,
        initialSubject: subject,
        initialClassLevel: classLevel,
        initialTerm: termLabel,
        isRefresh: existingPlan.isNotEmpty,
      ),
    );
    if (selection == null || !mounted) return;

    // "Get New Topics Online" requires internet — check before doing anything.
    if (selection.useAI && !await PlatformHelper.isOnline()) {
      _showToast('This option needs an internet connection.');
      return;
    }

    await prefs.setString(_prefAutoGenerateSubject, selection.subject);
    await prefs.setString(_prefAutoGenerateClass, selection.classLevel);
    await prefs.setString(_prefAutoGenerateTerm, selection.termLabel);

    // Refresh mode: confirm before atomically replacing the existing plan.
    // The confirmation must ONLY appear when a plan actually exists for the
    // subject/class/term the teacher finally selected in the dialog (they may
    // have changed it from the pre-filled values) — a fresh subject/class/
    // term goes straight to generation with no popup.
    final hasExistingPlan = (school != null && teacher != null)
        ? await SchemeOfWorkService(db).findSchemes(
            schoolId: school.localId,
            teacherId: teacher.localId,
            subject: selection.subject,
            classLevel: selection.classLevel,
            term: selection.termLabel,
          )
        : const <SchemeOfWorkData>[];
    if (hasExistingPlan.isNotEmpty && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Refresh your plan?'),
          content: Text(
            'This will replace your existing plan for '
            '${selection.subject}, ${selection.classLevel}, '
            '${selection.termLabel} with fresh topics. Your previously '
            'generated lesson content will be kept, but topic titles may '
            'change. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Refresh Plan'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    await _runAutoGenerate(
      selection,
      forceAI: selection.useAI,
      deleteExistingFirst: hasExistingPlan.isNotEmpty,
    );
  }

  Future<void> _runAutoGenerate(
    _AutoGenerateSelection selection, {
    bool forceAI = false,
    bool deleteExistingFirst = false,
  }) async {
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) throw Exception('School data not available');

      // ── 1. Build the 13-week topic list ─────────────────────────────
      // forceAI skips the curated list entirely so the teacher can
      // intentionally regenerate topics from the AI ("Get New Topics Online").
      List<Map<String, dynamic>> weeks;
      final curated = forceAI
          ? null
          : getNerdcTopics(
              selection.subject, selection.classLevel, selection.termLabel);
      if (curated != null) {
        weeks = [
          for (var i = 0; i < curated.length; i++)
            {
              'week': i + 1,
              'topic': curated[i].topic,
              'objectives': curated[i].objectives.join('\n'),
            },
        ];
      } else {
        // AI fallback — requires internet.
        if (!await PlatformHelper.isOnline()) {
          _showToast(
            'No internet connection. This subject is not in the built-in '
            'list yet — connect to the internet to generate it.',
          );
          return;
        }
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(width: 20),
                    Expanded(child: Text('Creating your plan…')),
                  ],
                ),
              ),
            ),
          );
        }
        final aiService = AiService(db: db);
        await aiService.checkDailyLimit(
          school.subscriptionTier.isEmpty ? 'free' : school.subscriptionTier);
        final prompt = PromptTemplates.schemeOfWork(
          selection.subject, selection.classLevel, selection.termLabel);
        final result = await aiService.generate(prompt);
        weeks = parseSchemeWeeks(result);
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        await aiService.logGeneration(
          teacherId: authState.currentTeacher?.localId.toString(),
          schoolId: school.localId.toString(),
          topic: 'SoW: ${selection.subject} ${selection.termLabel}',
        );
        if (weeks.isEmpty) {
          // The model returned something we could not turn into a weeks list
          // (error object, plain prose, or a malformed structure). Show a
          // friendly message instead of the cryptic "AI returned no weeks".
          if (mounted) {
            _showToast(
              "The AI didn't return a valid scheme of work for "
              '${selection.subject}, ${selection.classLevel}, '
              '${selection.termLabel}. Please try again.',
            );
          }
          return;
        }
      }

      // ── 2. Resolve teacher local id ──
      final teacherServerId = authState.currentTeacher?.serverId;
      final teacher = teacherServerId != null
          ? await db.teachersDao.findByServerId(teacherServerId)
          : null;
      if (teacher == null) throw Exception('Teacher account not ready yet');

      final service = SchemeOfWorkService(db);

      // ── 3. Already have a plan? Warn before deleting + recreating ──
      final existing = await service.findSchemes(
        schoolId: school.localId,
        teacherId: teacher.localId,
        subject: selection.subject,
        classLevel: selection.classLevel,
        term: selection.termLabel,
      );
      // In refresh mode the caller already confirmed; only re-prompt when the
      // create dialog picked a combo that matches an existing plan.
      if (existing.isNotEmpty && !deleteExistingFirst) {
        if (!mounted) return;
        final recreate = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace your plan?'),
            content: const Text(
              'You already have a plan for this class and subject. '
              'Creating again will delete your existing plan and its draft '
              'lessons, then build a fresh one.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                child: const Text('Create Again'),
              ),
            ],
          ),
        );
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
        deleteExistingFirst: deleteExistingFirst || existing.isNotEmpty,
      );

      ref.invalidate(lessonsListProvider);
      await _loadSchemesForDisplay();
      _showToast('Your plan is ready! Tap a week to start writing.');
    } catch (e) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        // Dismiss any loading dialog that is still open on failure.
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showToast('Could not create plan: $e');
    }
  }

  /// Maps the dialog's '1st Term' labels to the storage form ('First') used
  /// by existing scheme rows.
  String _termForStorage(String termLabel) {
    switch (termLabel) {
      case '2nd Term':
        return 'Second';
      case '3rd Term':
        return 'Third';
      default:
        return 'First';
    }
  }

  List<Lesson> _applyFilters(List<Lesson> lessons) {
    return lessons.where((lesson) {
      if (!_matchesStatusFilter(lesson)) return false;
      if (!_matchesTermFilter(lesson)) return false;
      if (!_matchesClassFilter(lesson)) return false;
      if (!_matchesSubjectFilter(lesson)) return false;
      return true;
    }).toList();
  }

  bool _matchesStatusFilter(Lesson lesson) {
    final contentEmpty = _lessonContentEmptyById[lesson.id] ??
        _isLessonContentEmpty(lesson.content);
    switch (_selectedStatusFilter) {
      case 'Draft':
        return lesson.status == 'draft' && !lesson.isUnlocked;
      case 'Generated':
        // New persisted status, plus legacy fallbacks: unlocking always
        // follows generation, and any lesson with real content counts too.
        return lesson.status == 'generated' ||
            lesson.isUnlocked ||
            !contentEmpty;
      case 'Completed':
        return lesson.status == 'completed';
      case 'Unlocked':
        return lesson.isUnlocked;
      default:
        return true;
    }
  }

  bool _matchesTermFilter(Lesson lesson) {
    if (_selectedTermFilter == 'All') return true;
    final termLabel = _termLabelForLesson(lesson);
    return termLabel == _selectedTermFilter;
  }

  bool _matchesClassFilter(Lesson lesson) {
    if (_selectedClassFilter == 'All') return true;
    // Compare normalized labels so a 'JSS3' filter matches lessons stored as
    // 'JSS 3' (and vice versa) — otherwise freshly generated lessons can
    // disappear from the list under the class filter that produced them.
    return _normalizeClassLabel(lesson.classLevel) ==
        _normalizeClassLabel(_selectedClassFilter);
  }

  bool _matchesSubjectFilter(Lesson lesson) {
    if (_selectedSubjectFilter == 'All') return true;
    return lesson.subject == _selectedSubjectFilter;
  }

  void _setStatusFilter(String filter) {
    setState(() => _selectedStatusFilter = filter);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}status', filter);
    });
  }

  void _setTermFilter(String filter) {
    setState(() => _selectedTermFilter = filter);
    _refreshPlanButtonState();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}term', filter);
    });
  }

  void _setClassFilter(String filter) {
    setState(() => _selectedClassFilter = filter);
    _refreshPlanButtonState();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}class', filter);
    });
  }

  void _setSubjectFilter(String filter) {
    setState(() => _selectedSubjectFilter = filter);
    _refreshPlanButtonState();
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}subject', filter);
    });
  }

  List<String> _buildFilterOptions(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...items];
  }

  String? _termLabelForLesson(Lesson lesson) {
    // Use the real term column first
    if (lesson.term != null && lesson.term!.trim().isNotEmpty) {
      final normalized = _normalizeTermLabel(lesson.term!);
      if (normalized.isNotEmpty) return normalized;
    }

    // Fall back to linked scheme of work
    final schemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
    if (schemeId == null) return null;
    final scheme = _schemesById[schemeId];
    if (scheme == null) return null;
    return _normalizeTermLabel(scheme.term);
  }

  String _classLevelLabelForLesson(Lesson lesson) {
    final termLabel = _termLabelForLesson(lesson);
    final weekLabel = lesson.weekNumber != null ? ' - Week ${lesson.weekNumber}' : '';
    if (termLabel == null || termLabel.isEmpty) {
      return '${lesson.classLevel}$weekLabel';
    }
    return '${lesson.classLevel} ($termLabel)$weekLabel';
  }

  String _normalizeTermLabel(String term) {
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

  String _createLessonLocation({
    required String subject,
    required String classLevel,
    required String term,
  }) {
    final queryParameters = <String, String>{};
    if (subject.isNotEmpty) queryParameters['subject'] = subject;
    if (classLevel.isNotEmpty) queryParameters['classLevel'] = classLevel;
    if (term.isNotEmpty) queryParameters['term'] = term;
    return Uri(
      path: '/lesson-editor',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  void _openNewLesson() {
    final subject = _selectedSubjectFilter == 'All' ? '' : _selectedSubjectFilter;
    final classLevel =
        _selectedClassFilter == 'All' ? '' : _selectedClassFilter;
    final term = _selectedTermFilter == 'All' ? '' : _selectedTermFilter;
    context.push(
      _createLessonLocation(
        subject: subject,
        classLevel: classLevel,
        term: term,
      ),
    );
  }

  /// Handles the single "Create" flyout. [option] selects which action runs.
  Future<void> _handleCreateOption(String option) async {
    switch (option) {
      case 'single':
        _openNewLesson();
        break;
      case 'offline':
        // Bulk generate — opens the plan dialog so the teacher can choose
        // between curated offline topics and AI online generation. The
        // existing internet check and curated-data check are preserved.
        await _openAutoGenerateDialog();
        break;
      case 'refresh':
        // Refresh re-runs generation against the existing plan selection.
        // (Only offered when a plan exists for the current filters; the
        // confirmation still gates on the combo finally chosen in the dialog.)
        await _openAutoGenerateDialog();
        break;
    }
  }

  /// Shows a readable toast (dark background, white text) on this screen.
  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF323232),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the content-empty cache whenever the list reloads/refreshes so
    // the filter predicates never parse content JSON per row per frame.
    ref.listen(lessonsListProvider, (prev, next) {
      next.whenData(_rebuildContentEmptyCache);
    });

    final lessonsAsync = ref.watch(lessonsListProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);


    // CallbackShortcuts must sit ABOVE the autofocused node so key events
    // bubbling up from it reach the bindings (Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        // Ctrl+Shift+Z is the conventional redo shortcut on Windows/Linux.
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ):
            _redo,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && mounted) {
              context.go('/');
            }
          },
          child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back to Home',
          ),
          title: Text(
            'Lessons',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.12,
            ),
          ),
          elevation: 0,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          surfaceTintColor: cs.surface,
          actions: [
            const SyncIndicator(),
            const SizedBox(width: 4),
            OfflineCreditCounter(
              visible: ref.watch(isOfflineProvider),
            ),
            PopupMenuButton<String>(
              onSelected: (option) => _handleCreateOption(option),
              tooltip: 'Create',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'single',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.add_rounded),
                    title: Text('✏️  Add Single Lesson'),
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'offline',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_rounded),
                    title: const Text('📋  Bulk Generate'),
                    dense: true,
                  ),
                ),
                if (_hasPlanForFilters)
                  PopupMenuItem(
                    value: 'refresh',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.refresh_rounded),
                      title: const Text('🔄  Refresh Plan'),
                      dense: true,
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.add_circle_rounded, color: cs.primary),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            const ConflictBanner(),
            Expanded(
              child: lessonsAsync.when(
                loading: () => ListView(
                  physics: (Platform.isAndroid || Platform.isIOS)
                      ? const BouncingScrollPhysics()
                      : null,
                  padding: const EdgeInsets.all(16),
                  children: List.generate(
                    4,
                    (i) => _LessonCardSkeleton(cs: cs),
                  ),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(
                            Icons.error_outline,
                            size: 34,
                            color: cs.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load lessons',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$error',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => ref.invalidate(lessonsListProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (lessons) {
                  final filteredLessons = _applyFilters(lessons);
                  filteredLessons.sort((a, b) => (a.weekNumber ?? 0).compareTo(b.weekNumber ?? 0));
                  final termOptions = _termFilters;
                  final classOptions = _buildFilterOptions(
                    lessons.map((lesson) => lesson.classLevel),
                  );
                  final subjectOptions = _buildFilterOptions(
                    lessons.map((lesson) => lesson.subject),
                  );

                  final filterPanel = Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _LessonFiltersPanel(
                      cs: cs,
                      theme: theme,
                      expanded: _filtersExpanded,
                      onToggleExpanded: _toggleFiltersExpanded,
                      selectedStatusFilter: _selectedStatusFilter,
                      selectedTermFilter: _selectedTermFilter,
                      selectedClassFilter: _selectedClassFilter,
                      selectedSubjectFilter: _selectedSubjectFilter,
                      statusFilters: _statusFilters,
                      termFilters: termOptions,
                      classFilters: classOptions,
                      subjectFilters: subjectOptions,
                      onStatusChanged: _setStatusFilter,
                      onTermChanged: _setTermFilter,
                      onClassChanged: _setClassFilter,
                      onSubjectChanged: _setSubjectFilter,
                      headerTrailing: null,
                    ),
                  );

                  if (lessons.isEmpty) {
                    return Column(
                      children: [
                        filterPanel,
                        Expanded(
                          child: ListView(
                            physics: (Platform.isAndroid || Platform.isIOS)
                                ? const BouncingScrollPhysics()
                                : null,
                            padding: const EdgeInsets.all(32),
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainer,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        Icons.book_rounded,
                                        size: 38,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'No lessons yet',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap "Create" to add a single lesson or '
                                      'build your whole term at once.',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  if (filteredLessons.isEmpty) {
                    return Column(
                      children: [
                        filterPanel,
                        Expanded(
                          child: ListView(
                            physics: (Platform.isAndroid || Platform.isIOS)
                                ? const BouncingScrollPhysics()
                                : null,
                            padding: const EdgeInsets.all(32),
                            children: [
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainer,
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Icon(
                                        Icons.filter_alt_off_rounded,
                                        size: 38,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'No lessons match the selected filters',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try a different filter or clear it to see all lessons.',
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      filterPanel,
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => ref.invalidate(lessonsListProvider),
                          child: ListView.builder(
                            physics: (Platform.isAndroid || Platform.isIOS)
                                ? const BouncingScrollPhysics()
                                : null,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filteredLessons.length,
                            itemBuilder: (context, index) {
                              final lesson = filteredLessons[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _LessonCard(
                                  lesson: lesson,
                                  position: index + 1,
                                  classLevelLabel: _classLevelLabelForLesson(lesson),
                                  onTap: () => context.push('/lessons/${lesson.id}'),
                                  onEdit: () => context.push('/lessons/${lesson.id}'),
                                  onDelete: () => _confirmDeleteLesson(lesson),
                                  isExportingPdf: _isExportingPdf,
                                  onExport: _isExportingPdf ? null : () => _exportLesson(lesson),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  /// Extracts diagram URLs from the lesson content at delete time and
  /// schedules the remote `delete-diagram` Edge Function calls for after the
  /// Undo window elapses, so the remote diagrams are never deleted before the
  /// user can Undo. Returns null when there is nothing to clean up (offline,
  /// no diagrams, no JWT, or Supabase unavailable) so Undo has no timer to
  /// cancel. Best-effort only — failure never blocks lesson deletion.
  Future<Timer?> _scheduleDelayedDiagramCleanup(Lesson lesson) async {
    try {
      if (!await PlatformHelper.isOnline()) return null;

      final contentRaw = lesson.content;
      if (contentRaw.isEmpty) return null;

      final parsed = json.decode(contentRaw) as Map<String, dynamic>?;
      if (parsed == null) return null;
      final diagrams = parsed['diagrams'] as List<dynamic>?;
      if (diagrams == null || diagrams.isEmpty) return null;

      final jwt = ref.read(authServiceProvider).currentJwt;
      if (jwt == null || jwt.isEmpty) return null;

      final urls = <String>[];
      for (final entry in diagrams) {
        if (entry is! Map<String, dynamic>) continue;
        final url = entry['imageUrl'] as String?;
        if (url != null && url.isNotEmpty) urls.add(url);
      }
      if (urls.isEmpty) return null;

      final client = supabase_pkg.Supabase.instance.client;
      return Timer(_undoWindow, () async {
        for (final url in urls) {
          try {
            await client.functions.invoke(
              'delete-diagram',
              headers: {'x-classai-jwt': jwt},
              body: {'url': url},
            );
          } catch (_) {
            // Best-effort only — never surface diagram cleanup failures.
          }
        }
      });
    } catch (_) {
      // Entire cleanup is best-effort; never block deletion.
      return null;
    }
  }

  Future<void> _confirmDeleteLesson(Lesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lesson'),
        content: Text('Are you sure you want to delete "${lesson.topic}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _deleteLesson(lesson);
    }
  }

  /// Applies a delete as a reversible command:
  ///  1. captures DELETE entries already pending for the lesson,
  ///  2. soft-deletes the local row FIRST — remote side effects never run
  ///     before the local row is gone,
  ///  3. queues the remote DELETE but holds it (`next_retry_at` in the
  ///     future) so the sync engine cannot push it before the Undo window
  ///     elapses,
  ///  4. schedules the remote diagram deletion for after the Undo window,
  ///  5. pushes the operation onto the flow-local undo stack.
  Future<void> _deleteLesson(Lesson lesson) async {
    try {
      final db = ref.read(databaseProvider);
      // Capture pending DELETE queue entries before deleting so Undo can drop
      // them — otherwise the queued DELETE would still remove the server row
      // after the local row is restored.
      final pendingDeleteEntries = (await db.syncQueueDao.pendingEntries())
          .where((e) =>
              e.queueTable == 'lessons' &&
              e.recordLocalId == lesson.id &&
              e.operation == 'DELETE')
          .map((e) => e.id)
          .toList();

      await db.lessonsDao.deleteLesson(lesson.id);

      // Only queue a remote DELETE when the lesson has a server UUID.
      // Lessons whose original INSERT was skipped server-side have no server
      // row; queueing a DELETE with only the local id caused the server to
      // fail `.eq("id", <localInt>)` forever.
      int? newQueueEntryId;
      if (lesson.serverId != null && lesson.serverId!.isNotEmpty) {
        newQueueEntryId = await _queueHeldDelete(
          db,
          table: 'lessons',
          localId: lesson.id,
          serverId: lesson.serverId!,
        );
      }

      // Delay the remote diagram deletion until the Undo window elapses;
      // Undo cancels it, and after the window it proceeds automatically.
      final diagramCleanupTimer =
          await _scheduleDelayedDiagramCleanup(lesson);

      // Any new delete invalidates the redo history — the stack only covers
      // the current delete flow.
      _redoStack.clear();
      _undoStack.add(_LessonDeleteRecord(
        lesson: lesson,
        queueEntryId: newQueueEntryId,
        pendingDeleteEntryIds: pendingDeleteEntries,
        diagramCleanupTimer: diagramCleanupTimer,
      ));
      ref.invalidate(lessonsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: _undoWindow,
            content: const Text('Lesson deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: _undo),
          ),
        );
      }
    } catch (e) {
      _showToast('Failed to delete: $e');
    }
  }

  /// Inserts a DELETE sync entry for [localId] and immediately holds it by
  /// setting `next_retry_at` past the Undo window, so a sync cycle cannot
  /// push the delete before the user's Undo opportunity elapses. A release
  /// timer clears `next_retry_at` once the window passes, making the entry
  /// due for a normal push; Undo cancels the timer and removes the entry.
  Future<int> _queueHeldDelete(
    AppDatabase db, {
    required String table,
    required int localId,
    required String serverId,
  }) async {
    final entryId = await db.into(db.syncQueue).insert(
          SyncQueueCompanion.insert(
            queueTable: table,
            recordLocalId: localId,
            operation: 'DELETE',
            payload: jsonEncode({'id': localId, 'server_id': serverId}),
          ),
        );
    // `where` on a drift statement returns void, so the write must be chained
    // through a parenthesized cascade (same pattern as the DAOs).
    await (db.update(db.syncQueue)..where((t) => t.id.equals(entryId))).write(
          SyncQueueCompanion(
            nextRetryAt: Value(DateTime.now().add(_undoWindow)),
          ),
        );
    final releaseTimer = Timer(_undoWindow, () {
      _heldDeleteTimers.remove(entryId);
      (db.update(db.syncQueue)..where((t) => t.id.equals(entryId)))
          .write(const SyncQueueCompanion(nextRetryAt: Value(null)));
    });
    _heldDeleteTimers[entryId] = releaseTimer;
    return entryId;
  }

  /// Undo the most recent delete — shared by the SnackBar action and the
  /// Ctrl+Z shortcut, so both operate on the same flow-local stack.
  void _undo() {
    if (_undoStack.isEmpty) return;
    final record = _undoStack.removeLast();
    _redoStack.add(record);
    unawaited(_applyUndo(record));
  }

  /// Restores a soft-deleted lesson, cancels the delayed remote diagram
  /// deletion, and drops the DELETE entries created by the delete plus any
  /// that were pending before it, so the server row is left untouched.
  Future<void> _applyUndo(_LessonDeleteRecord record) async {
    // Cancel the queued remote diagram deletion so the diagrams stay put,
    // and stop the DELETE entry's release timer — the entry is removed below.
    record.diagramCleanupTimer?.cancel();
    final newEntryId = record.queueEntryId;
    if (newEntryId != null) {
      _heldDeleteTimers.remove(newEntryId)?.cancel();
    }
    try {
      final db = ref.read(databaseProvider);
      await db.lessonsDao.updateLesson(
        record.lesson.id,
        LessonsCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (newEntryId != null) {
        await db.syncQueueDao.deleteById(newEntryId);
      }
      for (final entryId in record.pendingDeleteEntryIds) {
        await db.syncQueueDao.deleteById(entryId);
      }
      ref.invalidate(lessonsListProvider);
    } catch (_) {
      // Undo is best-effort; the lesson remains deleted if it fails.
    }
  }

  /// Re-applies the most recently undone delete (Ctrl+Y).
  void _redo() {
    if (_redoStack.isEmpty) return;
    final record = _redoStack.removeLast();
    _undoStack.add(record);
    unawaited(_applyRedo(record));
  }

  /// Re-applies a delete: soft-deletes the row again, re-queues a held
  /// DELETE entry, and re-schedules the delayed diagram cleanup. The record's
  /// [queueEntryId] is refreshed so a subsequent Undo removes the new entry.
  Future<void> _applyRedo(_LessonDeleteRecord record) async {
    try {
      final db = ref.read(databaseProvider);
      await db.lessonsDao.deleteLesson(record.lesson.id);
      int? newQueueEntryId;
      if (record.lesson.serverId != null &&
          record.lesson.serverId!.isNotEmpty) {
        newQueueEntryId = await _queueHeldDelete(
          db,
          table: 'lessons',
          localId: record.lesson.id,
          serverId: record.lesson.serverId!,
        );
      }
      final diagramCleanupTimer =
          await _scheduleDelayedDiagramCleanup(record.lesson);
      record.queueEntryId = newQueueEntryId;
      record.diagramCleanupTimer = diagramCleanupTimer;
      ref.invalidate(lessonsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: _undoWindow,
            content: const Text('Lesson deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: _undo),
          ),
        );
      }
    } catch (_) {
      // Best-effort — the row stays deleted even if re-queueing failed.
    }
  }

  Future<void> _exportLesson(Lesson lesson) async {
    if (_isExportingPdf) return;
    setState(() => _isExportingPdf = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) {
        _showToast('School data not available');
        return;
      }
      final teacherId = authState.currentTeacher?.serverId;
      final teacherEmail = authState.currentTeacher?.email;
      await exportLessonPdf(
        context,
        ref,
        lesson,
        school,
        teacherId,
        teacherEmail,
      );
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }
}

class _LessonFiltersPanel extends StatelessWidget {
  const _LessonFiltersPanel({
    required this.cs,
    required this.theme,
    required this.expanded,
    required this.onToggleExpanded,
    required this.selectedStatusFilter,
    required this.selectedTermFilter,
    required this.selectedClassFilter,
    required this.selectedSubjectFilter,
    required this.statusFilters,
    required this.termFilters,
    required this.classFilters,
    required this.subjectFilters,
    required this.onStatusChanged,
    required this.onTermChanged,
    required this.onClassChanged,
    required this.onSubjectChanged,
    this.headerTrailing,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final String selectedStatusFilter;
  final String selectedTermFilter;
  final String selectedClassFilter;
  final String selectedSubjectFilter;
  final List<_StatusFilterItem> statusFilters;
  final List<String> termFilters;
  final List<String> classFilters;
  final List<String> subjectFilters;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onTermChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onSubjectChanged;

  /// Compact status widgets (sync + offline credits) shown at the right of the
  /// "Filters" header, before the expand chevron.
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Filters',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (headerTrailing != null) ...[
                    headerTrailing!,
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: statusFilters.map((item) {
                final selected = item.label == selectedStatusFilter;
                final accent = _statusFilterAccent(item.label, cs);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(
                      item.icon,
                      size: 18,
                      color: selected ? accent : cs.onSurfaceVariant,
                    ),
                    label: Text(item.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => onStatusChanged(item.label),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? accent : cs.onSurfaceVariant,
                    ),
                    backgroundColor: cs.surfaceContainerLow,
                    selectedColor: accent.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: selected
                          ? accent.withValues(alpha: 0.4)
                          : cs.outlineVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: _FilterDropdownField(
                    cs: cs,
                    label: 'Term',
                    value: selectedTermFilter,
                    items: termFilters,
                    onChanged: onTermChanged,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _FilterDropdownField(
                    cs: cs,
                    label: 'Class Level',
                    value: selectedClassFilter,
                    items: classFilters,
                    onChanged: onClassChanged,
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _FilterDropdownField(
                    cs: cs,
                    label: 'Subject',
                    value: selectedSubjectFilter,
                    items: subjectFilters,
                    onChanged: onSubjectChanged,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Maps each status filter label to its accent color for the FilterChip
/// selected state.
Color _statusFilterAccent(String label, ColorScheme cs) => switch (label) {
      'Draft' => kStatusDraftColor,
      'Completed' => kStatusCompletedColor,
      'Unlocked' => kStatusUnlockedColor,
      'Generated' => kStatusGeneratedColor,
      _ => cs.primary, // 'All'
    };

class _FilterDropdownField extends StatelessWidget {
  const _FilterDropdownField({
    required this.cs,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final ColorScheme cs;
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : 'All',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _StatusFilterItem {
  const _StatusFilterItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Shared helper: export a lesson as PDF and invoke the system share sheet.
/// Can be called from any widget that has access to [Lesson], [School],
/// and teacher info.
///
/// Handles daily limit enforcement and upgrade prompts consistently.
Future<void> exportLessonPdf(
  BuildContext context,
  WidgetRef ref,
  Lesson lesson,
  School school,
  String? teacherId,
  String? teacherEmail,
) async {
  final pdfService = ref.read(pdfServiceProvider);
  try {
    final pdfBytes = await pdfService.generateLessonPdf(
      lesson,
      school,
      teacherId: teacherId,
      teacherEmail: teacherEmail,
    );

    // Write to temp file for sharing
    final dir = await getTemporaryDirectory();
    final safeName = lesson.topic.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File(
      '${dir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(pdfBytes);

    // Check context is still mounted after async work before any UI interaction
    if (!context.mounted) return;

    if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
      // Share via system share sheet
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'Lesson: ${lesson.topic}',
        ),
      );
    } else {
      // Desktop (Windows/macOS/Linux): native "Save As" dialog so the user
      // picks a location and gets a real .pdf on disk.
      final saveLocation = await getSaveLocation(
        suggestedName:
            '${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PDF', extensions: ['pdf']),
        ],
      );
      // User cancellation (null location) is normal; no error SnackBar needed.
      if (saveLocation != null) {
        await File(saveLocation.path).writeAsBytes(pdfBytes);
      }
    }
    // User cancellation is normal; no error SnackBar needed.
  } on PdfExportException catch (e) {
    // ── Unified daily limit handling ──
    if (e.remainingCount != null && e.remainingCount! <= 0) {
      // Remaining count is 0 (or negative for already-over-limit)
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Daily Export Limit Reached'),
            content: const Text(
              'You have reached your daily PDF export limit. '
              'Upgrade to Elite for unlimited exports.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // Navigate to payment or show upgrade request
                  context.push('/payment');
                },
                child: const Text('Upgrade'),
              ),
            ],
          ),
        );
      }
    } else {
      // Export succeeded within quota — informational notice only
      if (context.mounted && e.remainingCount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF323232),
            content: Text(
              'PDF exported. ${e.remainingCount} export(s) remaining today.',
              style: const TextStyle(color: Colors.white),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF323232),
          content: Text(
            'Failed to export PDF: $e',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }
}

/// Lesson row status chips (Completed / Unlocked / Draft) plus the brown
/// "Linked" marker come from the shared status language in
/// core/widgets/status_chip.dart, keeping the exams and lessons lists
/// consistent.

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final int position;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isExportingPdf;
  final VoidCallback? onExport;

  const _LessonCard({
    required this.lesson,
    required this.position,
    required this.classLevelLabel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.isExportingPdf = false,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // Primary status color for the left accent strip.
    final Color accentColor = switch (lesson.status) {
      'completed' => kStatusCompletedColor,
      'generated' when lesson.isUnlocked => kStatusUnlockedColor,
      'generated' => kStatusGeneratedColor,
      _ => lesson.isUnlocked ? kStatusUnlockedColor : kStatusDraftColor,
    };

    // Status chips — stacked vertically: primary first, Needs Sync below.
    final chipsColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        lessonRowStatusChip(
          completed: lesson.status == 'completed',
          unlocked: lesson.isUnlocked,
          generated: lesson.status == 'generated',
        ),
        if (lesson.serverId == null || lesson.serverId!.isEmpty) ...[
          const SizedBox(height: 4),
          const StatusChip(
            label: 'Needs Sync',
            icon: Icons.sync_rounded,
            color: kStatusNeedsSyncColor,
            dense: true,
          ),
        ],
      ],
    );

    // Position + icon + text + actions — the shared main row body used by
    // both the desktop (chips inline) and narrow (chips stacked) layouts.
    final mainRowChildren = <Widget>[
      const SizedBox(width: 10),
      SizedBox(
        width: 18,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const SizedBox(width: 10),
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          Icons.menu_book_rounded,
          color: cs.primary,
          size: 22,
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              lesson.topic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            // Flexible + ellipsis keeps the subject badge from
            // overflowing the text column on narrow cards.
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lesson.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              classLevelLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 8),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatDate(lesson.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isExportingPdf)
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (onExport != null)
                IconButton(
                  icon: Icon(Icons.picture_as_pdf_rounded, size: 20, color: cs.tertiary),
                  onPressed: onExport,
                  tooltip: 'Export PDF',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              IconButton(
                icon: Icon(Icons.edit_rounded, size: 20, color: cs.primary),
                onPressed: onEdit,
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: cs.error,
                ),
                onPressed: onDelete,
                tooltip: 'Delete',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.only(left: 0, right: 16, top: 14, bottom: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.onSurface.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 4px left accent strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Content area
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 440) {
                    return Row(
                      children: [
                        chipsColumn,
                        const SizedBox(width: 10),
                        ...mainRowChildren,
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chipsColumn,
                      const SizedBox(height: 8),
                      Row(children: mainRowChildren),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonCardSkeleton extends StatelessWidget {
  const _LessonCardSkeleton({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 160,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Flexible placeholders shrink with the text column so
                  // the skeleton never overflows at 320dp.
                  Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 3,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  height: 14,
                  width: 48,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// 'JSS3' / 'jss3' / 'JSS 3' → 'JSS 3' (likewise SSS). Keeps class values
/// stored without a space (legacy/synced data) matching the canonical dialog
/// and filter labels.
String _normalizeClassLabel(String value) {
  final compact = value.trim().toLowerCase().replaceAll(' ', '');
  final match = RegExp(r'^(jss|sss)(\d)$').firstMatch(compact);
  if (match != null) {
    return '${match.group(1)!.toUpperCase()} ${match.group(2)}';
  }
  return value;
}

class _AutoGenerateSelection {
  final String subject;
  final String classLevel;
  final String termLabel;
  final bool useAI;

  const _AutoGenerateSelection(
    this.subject,
    this.classLevel,
    this.termLabel, {
    this.useAI = false,
  });
}

class _AutoGenerateDialog extends StatefulWidget {
  const _AutoGenerateDialog({
    required this.subjectOptions,
    required this.initialSubject,
    required this.initialClassLevel,
    required this.initialTerm,
    required this.isRefresh,
  });

  final List<String> subjectOptions;
  final String initialSubject;
  final String initialClassLevel;
  final String initialTerm;
  final bool isRefresh;

  @override
  State<_AutoGenerateDialog> createState() => _AutoGenerateDialogState();
}

class _AutoGenerateDialogState extends State<_AutoGenerateDialog> {
  static const _classes = ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];
  static const _terms = ['1st Term', '2nd Term', '3rd Term'];

  late String _subject;
  late String _classLevel;
  late String _term;

  @override
  void initState() {
    super.initState();
    _subject = widget.subjectOptions.contains(widget.initialSubject)
        ? widget.initialSubject
        : widget.subjectOptions.first;
    // Normalize so a filter value like 'JSS3' (no space) maps to the
    // canonical 'JSS 3' instead of silently falling back to 'JSS 1' — which
    // would generate the whole plan under the wrong class.
    final normalizedClass = _normalizeClassLabel(widget.initialClassLevel);
    _classLevel = _classes.contains(normalizedClass)
        ? normalizedClass
        : _classes.first;
    _term = _terms.contains(widget.initialTerm) ? widget.initialTerm : _terms.first;
  }

  @override
  Widget build(BuildContext context) {
    // Whether curated NERDC topics exist for the current subject/class/term.
    // When missing, "Use Built-in Topics" is disabled with a tooltip.
    final hasOffline = getNerdcTopics(_subject, _classLevel, _term) != null;

    final offlineButton = hasOffline
        ? FilledButton(
            onPressed: () => Navigator.of(context).pop(
              _AutoGenerateSelection(_subject, _classLevel, _term),
            ),
            child: const Text('📋  Bulk Offline Generate'),
          )
        : const Tooltip(
            message: 'No offline topics available for this term.',
            child: FilledButton(
              onPressed: null,
              child: Text('📋  Bulk Offline Generate'),
            ),
          );

    return AlertDialog(
      title: Text(widget.isRefresh ? 'Refresh Plan' : 'Plan My Term'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isRefresh
                ? 'Replace the existing scheme of work for '
                    '$_subject, $_classLevel, $_term with 13 fresh weekly '
                    'topics and linked draft lessons.'
                : 'Create a complete scheme of work for '
                    '$_subject, $_classLevel, $_term with 13 weekly topics '
                    'and linked draft lessons.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: widget.subjectOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v ?? _subject),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _classLevel,
            decoration: const InputDecoration(labelText: 'Class Level'),
            items: _classes
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _classLevel = v ?? _classLevel),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _term,
            decoration: const InputDecoration(labelText: 'Term'),
            items: _terms
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _term = v ?? _term),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(
            _AutoGenerateSelection(_subject, _classLevel, _term, useAI: true),
          ),
          child: const Text('🌐  Bulk Online Generate'),
        ),
        offlineButton,
      ],
    );
  }
}
