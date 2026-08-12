import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:classai/core/database/database.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;

/// lessonsListProvider is defined in
/// lib/features/dashboard/providers/dashboard_data_providers.dart.

/// Displays a list of lessons from the local database.
class LessonsListScreen extends ConsumerStatefulWidget {
  const LessonsListScreen({super.key});

  @override
  ConsumerState<LessonsListScreen> createState() => _LessonsListScreenState();
}

class _LessonsListScreenState extends ConsumerState<LessonsListScreen> {

  static const _termFilters = ['All', '1st Term', '2nd Term', '3rd Term'];
  static const _statusFilters = [
    _StatusFilterItem('All', Icons.layers_rounded),
    _StatusFilterItem('Draft', Icons.edit_note_rounded),
    _StatusFilterItem('Completed', Icons.check_circle_rounded),
    _StatusFilterItem('Unlocked', Icons.lock_open_rounded),
    _StatusFilterItem('Generated', Icons.auto_awesome_rounded),
    _StatusFilterItem('Needs Sync', Icons.sync_rounded),
  ];

  String _selectedStatusFilter = 'All';
  String _selectedTermFilter = 'All';
  String _selectedClassFilter = 'All';
  String _selectedSubjectFilter = 'All';
  bool _filtersExpanded = true;
  bool _hasPlanForFilters = false;
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
    // Rebuild the content-empty cache whenever the list reloads/refreshes so
    // the filter predicates never parse content JSON per row per frame.
    ref.listen(lessonsListProvider, (prev, next) {
      next.whenData(_rebuildContentEmptyCache);
    });
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
        // Never generated: still 'draft', not unlocked, and content is an
        // empty placeholder. Unlocked legacy rows and lessons with content
        // are excluded from Draft.
        return lesson.status == 'draft' &&
            !lesson.isUnlocked &&
            contentEmpty;
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
      case 'Needs Sync':
        return lesson.serverId == null;
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
    final lessonsAsync = ref.watch(lessonsListProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);


    return PopScope(
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
        ),
        body: Column(
          children: [
            const ConflictBanner(),
            // Primary action — full width, directly under the banner so it no
            // longer competes with the AppBar title. Same flyout as before.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: PopupMenuButton<String>(
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
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 20, color: cs.onPrimary),
                      const SizedBox(width: 6),
                      Text(
                        'Create',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: cs.onPrimary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                      headerTrailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SyncIndicator(),
                          const SizedBox(width: 4),
                          OfflineCreditCounter(
                            visible: ref.watch(isOfflineProvider),
                          ),
                        ],
                      ),
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
                                  onExport: () => _exportLesson(lesson),
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
    );
  }

  /// Parse diagram URLs from lesson.content and attempt to delete each one
  /// via the `delete-diagram` Edge Function as a best-effort optimization.
  ///
  /// This runs BEFORE the local soft-delete so the lesson content is intact.
  /// Failure is logged but never blocks lesson deletion — section 2's
  /// sync-push cleanup is the authoritative path.
  Future<void> _cleanupDiagramsIfOnline(Lesson lesson) async {
    try {
      if (!await PlatformHelper.isOnline()) return;

      final contentRaw = lesson.content;
      if (contentRaw.isEmpty) return;

      final parsed = json.decode(contentRaw) as Map<String, dynamic>?;
      if (parsed == null) return;
      final diagrams = parsed['diagrams'] as List<dynamic>?;
      if (diagrams == null || diagrams.isEmpty) return;

      final jwt = ref.read(authServiceProvider).currentJwt;
      if (jwt == null || jwt.isEmpty) return;

      final client = supabase_pkg.Supabase.instance.client;

      for (final entry in diagrams) {
        if (entry is! Map<String, dynamic>) continue;
        final url = entry['imageUrl'] as String?;
        if (url == null || url.isEmpty) continue;

        try {
          await client.functions.invoke(
            'delete-diagram',
            headers: {'x-classai-jwt': jwt},
            body: {'url': url},
          );
        } catch (_) {
          // Best-effort only — sync-push will clean up via section 2.
        }
      }
    } catch (_) {
      // Entire cleanup is best-effort; never block deletion.
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
      try {
        // Best-effort diagram cleanup (online optimization only)
        await _cleanupDiagramsIfOnline(lesson);

        final db = ref.read(databaseProvider);
        await db.lessonsDao.deleteLesson(lesson.id);
        // Only queue a remote DELETE when the lesson has a server UUID.
        // Lessons whose original INSERT was skipped server-side have no
        // server row; queueing a DELETE with only the local id caused the
        // server to fail `.eq("id", <localInt>)` forever.
        if (lesson.serverId != null && lesson.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'lessons',
            recordLocalId: lesson.id,
            operation: 'DELETE',
            payload: {
              'id': lesson.id,
              'server_id': lesson.serverId,
            },
          );
        }
        ref.invalidate(lessonsListProvider);
        _showToast('Lesson deleted');
      } catch (e) {
        _showToast('Failed to delete: $e');
      }
    }
  }

  Future<void> _exportLesson(Lesson lesson) async {
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
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(
                      item.icon,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    label: Text(item.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => onStatusChanged(item.label),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    backgroundColor: cs.surfaceContainerLow,
                    selectedColor: cs.primaryContainer.withValues(alpha: 0.45),
                    side: BorderSide(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.25)
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

/// Status-circle colors shared with the exams list so the mapping stays
/// consistent across both screens: Draft → grey, Unlocked → blue,
/// Completed → green, linked to a scheme → orange border.
const _draftCircleColor = Color(0xFF9E9E9E);
const _unlockedCircleColor = Color(0xFF2196F3);
const _completedCircleColor = Color(0xFF4CAF50);
const _schemeLinkedCircleColor = Color(0xFFFF9800);

/// Lesson → circle color: Completed → green, Unlocked → blue, Draft → grey.
Color _lessonStatusCircleColor(Lesson lesson) {
  if (lesson.status == 'completed') return _completedCircleColor;
  if (lesson.isUnlocked) return _unlockedCircleColor;
  return _draftCircleColor;
}

/// Small colored circle showing an item's state. An orange border is drawn
/// when the item is linked to a scheme of work. Identical implementation on
/// the exams list so the two screens stay consistent.
class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.color, required this.linked});

  final Color color;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: linked
            ? Border.all(color: _schemeLinkedCircleColor, width: 2)
            : null,
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final int position;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _LessonCard({
    required this.lesson,
    required this.position,
    required this.classLevelLabel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          children: [
            _StatusCircle(
              color: _lessonStatusCircleColor(lesson),
              linked: lesson.schemeOfWorkId != null,
            ),
            const SizedBox(width: 6),
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
                  Row(
                    children: [
                      Container(
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
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.3,
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
                    if (onExport != null)
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
                  Row(
                    children: [
                      Container(
                        height: 20,
                        width: 64,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 20,
                        width: 92,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
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
