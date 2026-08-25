import 'dart:convert';
import 'dart:math' show min;
import 'package:drift/drift.dart' hide Column;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/services/exam_generation_service.dart';
import 'package:classai/core/services/question_validation.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/widgets/question_cards.dart';
import 'package:classai/core/widgets/upgrade_request_dialog.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show examsListProvider;
import 'package:classai/main.dart' show databaseProvider;
import 'package:shared_preferences/shared_preferences.dart';

/// Stitch‑designed exam editor with AI generation.
///
/// Generates MCQ, Theory, and/or Subjective questions. Preview as editable list of question cards.
/// Save inserts into `exams` table.

class ExamEditorScreen extends ConsumerStatefulWidget {
  /// Callback invoked with the generated prompt; returns parsed JSON map.
  final Future<Map<String, dynamic>> Function(String prompt)? generateCallback;

  /// The local ID of an existing exam to edit, or null for new exam.
  final int? examId;

  const ExamEditorScreen({super.key, this.generateCallback, this.examId});

  @override
  ConsumerState<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends ConsumerState<ExamEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _reviewController = TextEditingController();
  final _undoController = UndoHistoryController();
  int _week = 1;
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  bool _isGenerating = false;
  bool _isRegenerating = false;
  bool _hasGenerated = false;
  bool _configExpanded = false;
  bool _isUnlocked = false;
  bool _isOnline = true;
  int? _examId;
  bool _editorSidebarOpen = false;
  bool _sidebarInitialized = false;
  int _offlineCreditBalance = 3;
  int _remainingDailyPreviews = 10;
  String? _teacherId;
  String? _schoolId;
  String _subscriptionTier = 'free';
  String _teacherName = 'Teacher';
  String _schoolName = 'School';

  /// Loaded from subjectsDao, falls back to [_subjects] if empty.
  List<String> _loadedSubjects = [];

  /// Scheme of Work state
  List<SchemeOfWorkData> _schemes = [];
  int? _schemeOfWorkLocalId;
  bool _isFromSchemeOfWork = false;
  bool _sourceMissing = false;
  List<Lesson> _teacherLessons = [];
  int? _selectedLessonId;
  bool _isManualTopicEntry = true;

  // Phase 3 hybrid: reuse the selected week's saved lesson questions when
  // available; AI fills only the remaining counts.
  bool _useSavedLessonQuestions = true;
  SavedLessonQuestions? _savedLessonQuestions;
  bool _routeDefaultsApplied = false;

  /// When non-null, the editor opens in combined-exam mode ('termExam' or
  /// 'caTest') instead of the single-topic form. Set from the
  /// `compilationType` query parameter (the only way this mode is reached).
  String? _compilationMode;

  /// Term label for the combined-exam flow ('1st Term' etc.), set from the
  /// `term` query parameter when provided.
  String _termLabel = '1st Term';

  // Multi-select question types and their counts
  final Set<String> _selectedQuestionTypes = {'MCQ', 'Theory'};
  final Map<String, int> _questionCounts = {
    'MCQ': 5,
    'Theory': 5,
    'Subjective': 5,
  };
  static const _defaultQuestionTypes = {'MCQ', 'Theory'};
  static const Map<String, int> _defaultQuestionCounts = {
    'MCQ': 5,
    'Theory': 5,
    'Subjective': 5,
  };

  // Generated MCQ data
  List<Map<String, dynamic>> _mcqs = [];

  // Generated theory questions
  List<Map<String, dynamic>> _theoryQuestions = [];

  // Generated subjective questions
  List<Map<String, dynamic>> _subjectiveQuestions = [];
  int _previewRevision = 0;

  final List<String> _subjects = [
    'Mathematics',
    'English',
    'Science',
    'Social Studies',
    'Civic Education',
    'Christian Religious Studies',
    'Agricultural Science',
    'Home Economics',
    'Physical Education',
  ];

  final List<String> _classLevels = [
    'JSS 1',
    'JSS 2',
    'JSS 3',
    'SSS 1',
    'SSS 2',
    'SSS 3',
    'Primary 1',
    'Primary 2',
    'Primary 3',
    'Primary 4',
    'Primary 5',
    'Primary 6',
  ];

  final List<String> _difficulties = ['easy', 'medium', 'hard'];

  @override
  void initState() {
    super.initState();
    // A brand-new (blank) exam opens with the config form expanded so the
    // fields are immediately visible/interactive; a reopened existing exam
    // stays collapsed. Post-generation, the generate handler sets this back
    // to false to auto-collapse after a successful generation.
    _configExpanded = widget.examId == null;
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final online = await PlatformHelper.isOnline();
    if (mounted) setState(() => _isOnline = online);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithEmergencyFlush();
      _loadOfflineCreditBalance();
      _loadDailyPreviewData();
      _loadAuthInfo();
      _loadSubjects();
      _loadSchemesForContext();
      _loadTeacherLessons();
      if (widget.examId != null) {
        _loadExistingExam(widget.examId!);
      } else {
        _restoreLastQuestionCounts();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sidebarInitialized) {
      _sidebarInitialized = true;
      // Synchronous — renders correctly on the very first frame, no flash
      _editorSidebarOpen = MediaQuery.of(context).size.shortestSide >= 600;
      // Async override only triggers setState if SharedPreferences has a saved override
      PlatformHelper.isEditorMode(context).then((isEditor) {
        if (mounted && isEditor != _editorSidebarOpen) {
          setState(() => _editorSidebarOpen = isEditor);
        }
      });
    }
    if (_routeDefaultsApplied || widget.examId != null) {
      return;
    }
    _routeDefaultsApplied = true;

    final query = GoRouterState.of(context).uri.queryParameters;
    final subject = query['subject']?.trim();
    final classLevel = query['classLevel']?.trim();
    final compilationType = query['compilationType']?.trim();
    final term = query['term']?.trim();

    if (subject != null && subject.isNotEmpty) {
      _subject = subject;
    }
    if (classLevel != null && classLevel.isNotEmpty) {
      _classLevel = classLevel;
    }
    if (compilationType == 'termExam' || compilationType == 'caTest') {
      _compilationMode = compilationType;
    }
    if (term != null && term.isNotEmpty) {
      _termLabel = _normalizeTermLabel(term);
    }
    if (subject != null && subject.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadSchemesForContext();
        }
      });
    }
  }

  Future<void> _showAddSubjectDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Subject'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Subject Name',
            hintText: 'e.g., Physics',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      try {
        final db = ref.read(databaseProvider);
        // Check for existing subject scoped to this school before inserting.
        final existingSubject = _schoolId != null
            ? await db.subjectsDao.getByNameAndSchool(result, _schoolId!)
            : null;
        final int newSubjectId;
        if (existingSubject != null) {
          newSubjectId = existingSubject.id;
        } else {
          newSubjectId = await db.subjectsDao.insert(
            name: result,
            schoolId: _schoolId,
          );
          await db.syncQueueDao.insertEntry(
            queueTable: 'subjects',
            recordLocalId: newSubjectId,
            operation: 'INSERT',
            payload: {
              'name': result,
              'school_id': _schoolId,
            },
          );
        }
        await _loadSubjects();
        setState(() => _subject = result);
      } catch (_) {
        await _loadSubjects();
      }
    }
  }

  Future<void> _loadSubjects() async {
    try {
      final db = ref.read(databaseProvider);
      final subjects = await db.subjectsDao.getAll();
      if (mounted) {
        setState(() {
          // Deduplicate: subjects table has no unique constraint on name,
          // so the same name may appear in multiple rows. .toSet() preserves
          // the sortOrder ordering from the query while removing duplicates.
          _loadedSubjects = subjects.map((s) => s.name).toSet().toList();
        });
      }
    } catch (_) {
      // Fall back to hardcoded _subjects
    }
  }

  Future<void> _loadSchemesForContext() async {
    try {
      final db = ref.read(databaseProvider);
      final subjectRow = await db.subjectsDao.getByName(_subject);
      final subjectId = subjectRow?.id;
      if (subjectId != null) {
        final schemes = await db.schemeOfWorkDao.getSavedBySubject(subjectId);
        if (mounted) {
          setState(() => _schemes = schemes);
        }
      }
    } catch (_) {
      // Silently fail
    }
  }

  Future<void> _loadTeacherLessons() async {
    try {
      final db = ref.read(databaseProvider);
      if (_teacherId == null) {
        if (mounted) {
          setState(() => _teacherLessons = []);
        }
        return;
      }
      final lessons = await db.lessonsDao.getAll();
      if (mounted) {
        setState(() {
          _teacherLessons = lessons.where((lesson) => lesson.teacherServerId == _teacherId).toList();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _teacherLessons = []);
      }
    }
  }

  /// Refreshes how many of the configured questions this week's saved lesson
  /// can cover (subject/class/week/term based). Cheap: one in-memory filter
  /// over the school's non-deleted lessons.
  Future<void> _refreshSavedLessonAvailability() async {
    if (_teacherId == null || _schoolId == null) return;
    final db = ref.read(databaseProvider);
    final termLabel = await _resolveTermLabel(db) ?? '';
    final saved = await ExamGenerationService(db).loadSavedLessonQuestions(
      teacherServerId: _teacherId!,
      schoolServerId: _schoolId!,
      subject: _subject,
      classLevel: _classLevel,
      termLabel: termLabel,
      weekNumbers: [_week],
    );
    if (!mounted) return;
    setState(() {
      _savedLessonQuestions = saved;
      // Nothing usable → the checkbox is replaced by the calm note and
      // generation must be the pure-AI path (decision §12.6).
      if (saved.total == 0) _useSavedLessonQuestions = false;
    });
  }

  /// X of the requested questions this week's saved lesson can cover (capped
  /// per enabled type). Computed in build so typing a count updates the label
  /// with no extra DB read.
  int get _savedCoverage {
    final saved = _savedLessonQuestions;
    if (saved == null) return 0;
    final requestedMcq =
        _selectedQuestionTypes.contains('MCQ') ? (_questionCounts['MCQ'] ?? 0) : 0;
    final requestedTheory = _selectedQuestionTypes.contains('Theory')
        ? (_questionCounts['Theory'] ?? 0)
        : 0;
    final requestedSubjective = _selectedQuestionTypes.contains('Subjective')
        ? (_questionCounts['Subjective'] ?? 0)
        : 0;
    return min(saved.mcqs.length, requestedMcq).toInt() +
        min(saved.theory.length, requestedTheory).toInt() +
        min(saved.subjective.length, requestedSubjective).toInt();
  }

  /// Total requested questions across the enabled types (Y of the label).
  int get _neededQuestions {
    var needed = 0;
    for (final type in _selectedQuestionTypes) {
      needed += _questionCounts[type] ?? 0;
    }
    return needed;
  }

  Future<void> _refreshSourceMissing() async {
    if (_schemeOfWorkLocalId == null) {
      return;
    }
    try {
      final db = ref.read(databaseProvider);
      final exists = await db.schemeOfWorkDao.getById(_schemeOfWorkLocalId!) != null;
      if (mounted) {
        setState(() {
          _sourceMissing = !exists;
          // Prevention: release the dead scheme link in-memory so the exam
          // becomes fully editable (topic field) and the error banner clears.
          // No DB row is modified until the user explicitly saves.
          if (!exists) {
            _schemeOfWorkLocalId = null;
            _isFromSchemeOfWork = false;
            _isManualTopicEntry = true;
          }
        });
      }
    } catch (_) {}
  }

  /// Change 4: Restore last used question counts from SharedPreferences.
  Future<void> _restoreLastQuestionCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mcq = prefs.getInt('exam_last_mcq_count');
      final theory = prefs.getInt('exam_last_theory_count');
      final subjective = prefs.getInt('exam_last_subjective_count');
      final selectedTypes = prefs.getStringList('exam_last_selected_types');
      if (mcq != null || theory != null || subjective != null) {
        setState(() {
          _questionCounts['MCQ'] = mcq ?? _defaultQuestionCounts['MCQ']!;
          _questionCounts['Theory'] = theory ?? _defaultQuestionCounts['Theory']!;
          _questionCounts['Subjective'] = subjective ?? _defaultQuestionCounts['Subjective']!;
          if (selectedTypes != null && selectedTypes.isNotEmpty) {
            _selectedQuestionTypes
              ..clear()
              ..addAll(selectedTypes);
          }
        });
      }
    } catch (_) {
      // Silently fall back to defaults
    }
  }

  Future<String?> _resolveTermLabel(AppDatabase db) async {
    try {
      final schoolLocalId =
          ref.read(authProvider).currentSchool?.localId ??
              (await db.schoolsDao.get())?.localId;
      if (schoolLocalId == null) return null;

      if (_schemeOfWorkLocalId != null) {
        final scheme = await db.schemeOfWorkDao.getById(_schemeOfWorkLocalId!);
        final schemeTerm = scheme?.term.trim();
        if (schemeTerm != null && schemeTerm.isNotEmpty) {
          return _normalizeTermLabel(schemeTerm);
        }
      }

      final currentTerm =
          await db.termsDao.getCurrent(schoolLocalId) ??
              await db.termsDao.getTermForDate(
                schoolLocalId,
                DateTime.now(),
              );
      final termName = currentTerm?.name.trim();
      if (termName == null || termName.isEmpty) return null;
      return _normalizeTermLabel(termName);
    } catch (_) {
      return null;
    }
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

  Future<void> _loadExistingExam(int examId) async {
    try {
      final db = ref.read(databaseProvider);
      final exam = await db.examsDao.getById(examId);
      if (exam == null || !mounted) {
        return;
      }

      final content =
          jsonDecode(exam.content) as Map<String, dynamic>? ?? <String, dynamic>{};
      final mcqs = content['mcqs'] as List<dynamic>? ?? const [];
      final theory = content['theory'] as List<dynamic>? ?? const [];
      final subjective = content['subjective'] as List<dynamic>? ?? const [];

      setState(() {
        _examId = exam.id;
        _topicController.text = exam.topic;
        _week = exam.weekNumber ?? 1;
        _subject = exam.subject;
        _classLevel = exam.classLevel;
        _difficulty = exam.difficulty;
        _isUnlocked = exam.isUnlocked;
        _hasGenerated = mcqs.isNotEmpty || theory.isNotEmpty || subjective.isNotEmpty;
        _mcqs = mcqs
            .map((q) => Map<String, dynamic>.from(q as Map))
            .toList();
        _theoryQuestions = theory
            .map((q) => Map<String, dynamic>.from(q as Map))
            .toList();
        _subjectiveQuestions = subjective
            .map((q) => normalizeWrittenQuestion(
                Map<String, dynamic>.from(q as Map)))
            .toList();
        _selectedQuestionTypes
          ..clear()
          ..addAll([
            if (_mcqs.isNotEmpty) 'MCQ',
            if (_theoryQuestions.isNotEmpty) 'Theory',
            if (_subjectiveQuestions.isNotEmpty) 'Subjective',
          ]);
        _questionCounts
          ..clear()
          ..addAll({
            'MCQ': _mcqs.length,
            'Theory': _theoryQuestions.length,
            'Subjective': _subjectiveQuestions.length,
          });
        _schemeOfWorkLocalId = exam.schemeOfWorkId == null
            ? null
            : int.tryParse(exam.schemeOfWorkId!);
        _isFromSchemeOfWork = _schemeOfWorkLocalId != null;
        _isManualTopicEntry = _schemeOfWorkLocalId == null;
        _sourceMissing = false;
        _previewRevision++;
      });

      await _loadSchemesForContext();
      await _refreshSourceMissing();
      await _refreshSavedLessonAvailability();
    } catch (_) {}
  }

  void _onSchemeOfWorkSelected(SchemeOfWorkData? scheme) {
    if (scheme == null) {
      setState(() {
        _schemeOfWorkLocalId = null;
        _isFromSchemeOfWork = false;
        _week = 1;
        _selectedLessonId = null;
        _isManualTopicEntry = true;
        _sourceMissing = false;
      });
      _refreshSavedLessonAvailability();
      return;
    }
    final displayTopic = scheme.adminEditedTopic ?? scheme.topic;
    setState(() {
      _schemeOfWorkLocalId = scheme.id;
      _isFromSchemeOfWork = true;
      _topicController.text = displayTopic;
      _week = scheme.weekNumber;
      _selectedLessonId = null;
      _isManualTopicEntry = false;
      _sourceMissing = false;
    });
    _refreshSavedLessonAvailability();
  }

  void _onLessonSelected(Lesson? lesson) {
    if (lesson == null) {
      setState(() {
        _selectedLessonId = null;
        _isManualTopicEntry = true;
      });
      _refreshSavedLessonAvailability();
      return;
    }
    setState(() {
      _selectedLessonId = lesson.id;
      _topicController.text = lesson.topic;
      _week = lesson.weekNumber ?? lesson.week;
      _isManualTopicEntry = false;
      _sourceMissing = false;
    });
    _refreshSavedLessonAvailability();
  }

  void _registerWithEmergencyFlush() {
    final flushService = ref.read(emergencyFlushServiceProvider);
    flushService.register(() async {
      if (_hasGenerated && _isUnlocked && _formKey.currentState!.validate()) {
        await _saveExam(notify: false);
      }
    });
  }

  Future<void> _loadAuthInfo() async {
    try {
      final authData = ref.read(authProvider);
      if (authData.currentTeacher?.serverId != null) {
        _teacherId = authData.currentTeacher!.serverId;
        _teacherName = authData.currentTeacher!.teacherName;
      }
      if (authData.currentSchool != null) {
        _schoolId = authData.currentSchool!.serverId;
        _subscriptionTier = authData.currentSchool!.subscriptionTier;
        _schoolName = authData.currentSchool!.schoolName;
      }
      // Fallback: read from DB if auth provider has null data
      if (_teacherId == null || _schoolId == null) {
        final db = ref.read(databaseProvider);
        final school = await db.schoolsDao.get();
        if (school != null) {
          _schoolId ??= school.serverId;
          _subscriptionTier = school.subscriptionTier;
          _schoolName = school.schoolName;
        }
        final teachers = await db.teachersDao.getAll();
        if (teachers.isNotEmpty) {
          _teacherName = teachers.first.teacherName;
        }
      }
      if (mounted) setState(() {});
      await _loadTeacherLessons();
      await _refreshSourceMissing();
      await _refreshSavedLessonAvailability();
    } catch (_) {}
  }

  Future<void> _loadDailyPreviewData() async {
    try {
      final db = ref.read(databaseProvider);
      final config = await db.securityConfigDao.get();
      final today = DateTime.now().toIso8601String().split('T').first;
      final currentCount = config.dailyPreviewCount;
      final currentDate = config.dailyPreviewDate ?? '';
      // Reset counter if date changed
      int count = currentCount;
      if (currentDate != today) {
        count = 0;
      }
      // Calculate remaining previews based on tier
      const limits = {'free': 10, 'basic': 10, 'standard': 10, 'elite': -1};
      final limit = limits[_subscriptionTier] ?? 10;
      final remaining = limit < 0 ? -1 : (limit - count).clamp(0, limit);
      if (mounted) {
        setState(() => _remainingDailyPreviews = remaining);
      }
    } catch (_) {}
  }

  Future<void> _loadOfflineCreditBalance() async {
    try {
      await ref.read(offlineCreditStateProvider.notifier).refresh();
      if (mounted) {
        setState(() => _offlineCreditBalance =
            ref.read(offlineCreditStateProvider).currentOfflineCredits);
      }
    } catch (_) {}
  }

  Future<void> _showUpgradeRequiredDialog() async {
    if (!mounted) return;
    final role = ref.read(authProvider).currentTeacher?.role;
    if (role == 'admin') {
      // Admin navigates directly to payment
      if (mounted) {
        context.push('/payment');
      }
      return;
    }
    // Teacher sees the upgrade-request dialog
    await showUpgradeRequestDialog(context, ref, requestedTier: 'elite');
  }

  int _defaultStorageLimit(String tier) {
    switch (tier) {
      case 'free':
        return 100;
      case 'basic':
        return 200;
      case 'standard':
        return 500;
      case 'elite':
        return -1;
      default:
        return 100;
    }
  }

  Future<void> _handleGenerate() async {
    if (!_formKey.currentState!.validate()) return;

    // Change 1: Check if at least one question type has a count > 0
    final hasAnyTypeWithCount = _selectedQuestionTypes.any(
      (type) => (_questionCounts[type] ?? 0) > 0,
    );
    if (!hasAnyTypeWithCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showErrorToast(
          context: context,
          message: 'Please select at least one question type (MCQ, Theory, or Subjective).',
        );
      });
      return;
    }

    // Change 4: Check if total questions is 0
    final totalCount = _questionCounts.values.fold(0, (sum, c) => sum + c);
    if (totalCount == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showErrorToast(
          context: context,
          message: 'Please set the number of questions to generate.',
        );
      });
      return;
    }

    final authTier =
        ref.read(authProvider).currentSchool?.subscriptionTier.toLowerCase() ?? _subscriptionTier;
    final config = ref.read(configServiceProvider);
    final allowedTiers = config.examGenerationAllowedTiers;
    if (!allowedTiers.contains(authTier)) {
      await _showUpgradeRequiredDialog();
      return;
    }

    // Phase 3 hybrid: reuse this week's saved lesson questions, ask AI only
    // for the remaining counts. Requested = the on-screen per-type counts
    // (the prompts below are told the exact remaining count).
    final db = ref.read(databaseProvider);
    final topic = _topicController.text.trim();
    final generateMcq = _selectedQuestionTypes.contains('MCQ');
    final generateTheory = _selectedQuestionTypes.contains('Theory');
    final generateSubjective = _selectedQuestionTypes.contains('Subjective');
    List<Map<String, dynamic>> mcqs = [];
    List<Map<String, dynamic>> theoryQuestions = [];
    List<Map<String, dynamic>> subjectiveQuestions = [];

    final saved = _useSavedLessonQuestions
        ? await ExamGenerationService(db).loadSavedLessonQuestions(
            teacherServerId: _teacherId ?? '',
            schoolServerId: _schoolId ?? '',
            subject: _subject,
            classLevel: _classLevel,
            termLabel: await _resolveTermLabel(db) ?? '',
            weekNumbers: [_week],
          )
        : const SavedLessonQuestions.empty();
    final requestedMcq = _questionCounts['MCQ'] ?? 0;
    final requestedTheory = _questionCounts['Theory'] ?? 0;
    final requestedSubjective = _questionCounts['Subjective'] ?? 0;
    final usedMcq = generateMcq ? min(saved.mcqs.length, requestedMcq) : 0;
    final usedTheory =
        generateTheory ? min(saved.theory.length, requestedTheory) : 0;
    final usedSubjective =
        generateSubjective ? min(saved.subjective.length, requestedSubjective) : 0;
    final remainingMcq = requestedMcq - usedMcq;
    final remainingTheory = requestedTheory - usedTheory;
    final remainingSubjective = requestedSubjective - usedSubjective;
    // When every requested question is covered by saved lessons, skip the AI
    // call entirely (no credits / daily-limit spend; works offline).
    final needsAi = remainingMcq + remainingTheory + remainingSubjective > 0;

    if (needsAi && !await PlatformHelper.isOnline()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showErrorToast(
          context: context,
          message: 'Generation requires internet — try again when connected.',
        );
      });
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final aiService = AiService(db: db);

      // Check daily generation limit before generating (only when AI is
      // actually needed — a fully saved-question exam spends no limit).
      if (needsAi) {
        try {
          await aiService.checkDailyLimit(_subscriptionTier);
        } on AiGenerationException catch (e) {
          if (mounted) {
            setState(() => _isGenerating = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showErrorToast(context: context, message: e.message);
            });
          }
          return;
        }
      }

      // Generate questions
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      if (generateMcq && remainingMcq > 0) {
        final mcqPrompt = PromptTemplates.mcqs(
          _subject,
          _classLevel,
          topic,
          _difficulty,
          count: remainingMcq,
          teacherName: _teacherName,
          schoolName: _schoolName,
        ) +
            PromptTemplates.doNotRepeatInstruction(
              'MCQ',
              [
                for (final q in saved.mcqs.take(usedMcq))
                  q['question'].toString(),
              ],
            );
        mcqs = await _generateValidatedQuestions(
          prompt: mcqPrompt,
          aiService: aiService,
          validator: validateMcqs,
        );
      }

      if (generateTheory && remainingTheory > 0) {
        final theoryPrompt = PromptTemplates.theoryQuestions(
          _subject,
          _classLevel,
          topic,
          count: remainingTheory,
          teacherName: _teacherName,
          schoolName: _schoolName,
        ) +
            PromptTemplates.doNotRepeatInstruction(
              'Theory',
              [
                for (final q in saved.theory.take(usedTheory))
                  q['question'].toString(),
              ],
            );
        theoryQuestions = await _generateValidatedQuestions(
          prompt: theoryPrompt,
          aiService: aiService,
          validator: validateWrittenQuestions,
        );
      }

      if (generateSubjective && remainingSubjective > 0) {
        final subjectivePrompt = PromptTemplates.subjectiveQuestions(
          _subject,
          _classLevel,
          topic,
          count: remainingSubjective,
          teacherName: _teacherName,
          schoolName: _schoolName,
        ) +
            PromptTemplates.doNotRepeatInstruction(
              'Subjective',
              [
                for (final q in saved.subjective.take(usedSubjective))
                  q['question'].toString(),
              ],
            );
        subjectiveQuestions = await _generateValidatedQuestions(
          prompt: subjectivePrompt,
          aiService: aiService,
          validator: validateWrittenQuestions,
        );
      }

      // Increment preview counter only after successful generation
      await db.securityConfigDao
          .checkAndIncrementDailyPreviews(tier: _subscriptionTier);

      // Audit log the generation
      await aiService.logGeneration(
        teacherId: _teacherId,
        schoolId: _schoolId,
        topic: topic,
      );

      // Change 4: Save question counts to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('exam_last_mcq_count', _questionCounts['MCQ'] ?? 0);
      await prefs.setInt('exam_last_theory_count', _questionCounts['Theory'] ?? 0);
      await prefs.setInt('exam_last_subjective_count', _questionCounts['Subjective'] ?? 0);
      await prefs.setStringList(
        'exam_last_selected_types',
        _selectedQuestionTypes.toList(),
      );

      // Merge saved first, then AI — the requested totals are a contract. The
      // AI may return more than the remainder it was asked for, so cap each
      // type to the exact remaining count BEFORE merging (the final exam must
      // never exceed the requested totals; the fill check below only catches
      // shortfall). If the AI under-filled, abort BEFORE _saveExam so the
      // draft keeps its previous content and nothing partial is written.
      if (_useSavedLessonQuestions) {
        mcqs = mcqs.take(remainingMcq).toList();
        theoryQuestions = theoryQuestions.take(remainingTheory).toList();
        subjectiveQuestions =
            subjectiveQuestions.take(remainingSubjective).toList();

        mcqs = [...saved.mcqs.take(usedMcq), ...mcqs];
        theoryQuestions = [...saved.theory.take(usedTheory), ...theoryQuestions];
        subjectiveQuestions = [
          ...saved.subjective.take(usedSubjective),
          ...subjectiveQuestions,
        ];
        if ((generateMcq && mcqs.length < requestedMcq) ||
            (generateTheory && theoryQuestions.length < requestedTheory) ||
            (generateSubjective &&
                subjectiveQuestions.length < requestedSubjective)) {
          if (mounted) {
            setState(() => _isGenerating = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              showErrorToast(
                context: context,
                message: 'AI could not complete the exam — nothing was saved. '
                    'Try again.',
              );
            });
          }
          return; // no _saveExam → the draft keeps its previous content
        }
      }

      setState(() {
        _mcqs = mcqs;
        _theoryQuestions = theoryQuestions;
        _subjectiveQuestions = subjectiveQuestions;
        _hasGenerated = true;
        _configExpanded = false;
        _isUnlocked = false;
        _isGenerating = false;
        _previewRevision++;
      });

      await _saveExam(notify: false);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final parts = <String>[];
          if (_mcqs.isNotEmpty) parts.add('${_mcqs.length} MCQs');
          if (_theoryQuestions.isNotEmpty) parts.add('${_theoryQuestions.length} theory');
          if (_subjectiveQuestions.isNotEmpty) parts.add('${_subjectiveQuestions.length} subjective');
          if (_useSavedLessonQuestions &&
              usedMcq + usedTheory + usedSubjective > 0) {
            parts.add('${usedMcq + usedTheory + usedSubjective} from saved '
                'lessons');
          }
          showInfoToast(
            context: context,
            message: 'Generated ${parts.join(', ')}',
          );
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorToast(context: context, message: 'Generation failed: $e');
        });
      }
    }
  }

  Future<void> _handleUnlock() async {
    final isOnline = await PlatformHelper.isOnline();

    if (!isOnline && _offlineCreditBalance < 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.instance.showToast(
          context: context,
          message:
              'Out of offline credits. Connect to internet and sync to refill.',
          icon: Icons.warning,
        );
        _showSyncBottomSheet();
      });
      return;
    }

    try {
      final offlineCreditService =
          OfflineCreditService(ref.read(databaseProvider));
      final topicId = _topicController.text.trim();
      await offlineCreditService.spendOfflineCredits(
        amount: 1,
        contentIds: ['exam_$_subject\$$topicId'],
      );

      // Audit log the unlock
      await ref.read(databaseProvider).auditLogsDao.insert(
        AuditLogsCompanion.insert(
          id: Value(const Uuid().v4()),
          teacherId: Value(_teacherId),
          schoolId: Value(_schoolId),
          action: Value('unlock'),
          metadata: Value(jsonEncode({
            'type': 'exam',
            'subject': _subject,
            'topic': topicId,
            'timestamp': DateTime.now().toIso8601String(),
          })),
        ),
      );

      setState(() {
        _isUnlocked = true;
        if (!isOnline) {
          _offlineCreditBalance = _offlineCreditBalance - 1;
        }
      });

      // Persist the unlock so it survives navigation away and back.
      await _saveExam(notify: false);

      // Refresh the cached exam list so the "Unlocked" filter reflects the
      // newly unlocked state immediately.
      ref.invalidate(examsListProvider);

      ref.read(offlineCreditStateProvider.notifier).refresh();

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showInfoToast(context: context, message: 'Exam unlocked!');
        });
      }
    } catch (e) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorToast(context: context, message: 'Failed to unlock: $e');
        });
      }
    }
  }

  void _showSyncBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Sync Offline Credits',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
                'Tap below to sync with the server and refill your offline credits.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // Refresh offline credit state
                final db = ref.read(databaseProvider);
                db.securityConfigDao.get().then((config) {
                  if (mounted) {
                    setState(() =>
                        _offlineCreditBalance = config.offlineCredits);
                  }
                });
              },
              child: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleRegenerate() async {
    setState(() => _isRegenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final aiService = AiService(db: db);
      final topic = _topicController.text.trim();
      final review = _reviewController.text.trim();
      List<Map<String, dynamic>> mcqs = _mcqs;
      List<Map<String, dynamic>> theoryQuestions = _theoryQuestions;
      List<Map<String, dynamic>> subjectiveQuestions = _subjectiveQuestions;

      // Regenerate MCQ
      if (_mcqs.isNotEmpty) {
        final mcqPrompt = _buildRegenerationPrompt(
          PromptTemplates.mcqs(
            _subject,
            _classLevel,
            topic,
            _difficulty,
            teacherName: _teacherName,
            schoolName: _schoolName,
          ),
          review,
        );
        mcqs = await _generateValidatedQuestions(
          prompt: mcqPrompt,
          aiService: aiService,
          validator: validateMcqs,
        );
      }

      // Regenerate Theory
      if (_theoryQuestions.isNotEmpty) {
        final theoryPrompt = _buildRegenerationPrompt(
          PromptTemplates.theoryQuestions(
            _subject,
            _classLevel,
            topic,
            teacherName: _teacherName,
            schoolName: _schoolName,
          ),
          review,
        );
        theoryQuestions = await _generateValidatedQuestions(
          prompt: theoryPrompt,
          aiService: aiService,
          validator: validateWrittenQuestions,
        );
      }

      // Regenerate Subjective
      if (_subjectiveQuestions.isNotEmpty) {
        final subjectivePrompt = _buildRegenerationPrompt(
          PromptTemplates.subjectiveQuestions(
            _subject,
            _classLevel,
            topic,
            teacherName: _teacherName,
            schoolName: _schoolName,
          ),
          review,
        );
        subjectiveQuestions = await _generateValidatedQuestions(
          prompt: subjectivePrompt,
          aiService: aiService,
          validator: validateWrittenQuestions,
        );
      }

      setState(() {
        _mcqs = mcqs;
        _theoryQuestions = theoryQuestions;
        _subjectiveQuestions = subjectiveQuestions;
        _previewRevision++;
      });

      await _saveExam(notify: false);

      if (mounted) {
        setState(() => _isRegenerating = false);
        _reviewController.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showInfoToast(context: context, message: 'Questions regenerated successfully');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorToast(context: context, message: 'Regeneration failed: $e');
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchQuestionList(
    String prompt,
    AiService aiService,
  ) async {
    final result = widget.generateCallback != null
        ? await widget.generateCallback!(prompt)
        : await aiService.generate(prompt);
    final raw = result['raw'] as Map<String, dynamic>? ?? result;
    final list = raw['questions'] as List<dynamic>? ?? const [];
    final questions = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is Map) {
        questions.add(Map<String, dynamic>.from(item));
      }
    }
    return questions;
  }

  Future<List<Map<String, dynamic>>> _generateValidatedQuestions({
    required String prompt,
    required AiService aiService,
    required QuestionValidationResult Function(List<Map<String, dynamic>>)
        validator,
  }) async {
    final initialQuestions = await _fetchQuestionList(prompt, aiService);
    final initialValidation = validator(initialQuestions);
    final cleanedQuestions =
        List<Map<String, dynamic>>.from(initialValidation.validQuestions);

    if (initialValidation.invalidLabels.isEmpty) {
      return cleanedQuestions;
    }

    final followUpPrompt = '$prompt\n\n'
        'The following questions were invalid or missing: '
        '${initialValidation.invalidLabels.join(', ')}. '
        'Please generate correct replacements for them in the same JSON format.';
    final replacementQuestions =
        await _fetchQuestionList(followUpPrompt, aiService);
    final replacementValidation = validator(replacementQuestions);
    cleanedQuestions.addAll(replacementValidation.validQuestions);

    return cleanedQuestions.take(initialQuestions.length).toList();
  }

  String _buildRegenerationPrompt(String basePrompt, String review) {
    if (review.isEmpty) {
      return basePrompt;
    }
    return '$basePrompt\n\nTeacher feedback: $review';
  }

  void _updateMcq(int index, String field, String value) {
    setState(() {
      _mcqs[index][field] = value;
    });
  }

  void _updateMcqOption(int index, String optionKey, String value) {
    setState(() {
      final options = Map<String, String>.from(_mcqs[index]['options'] as Map);
      options[optionKey] = value;
      _mcqs[index]['options'] = options;
    });
  }

  void _updateTheory(int index, String field, String value) {
    setState(() {
      _theoryQuestions[index][field] = value;
    });
  }

  Future<void> _saveExam({bool notify = true}) async {
    try {
      final content = {
        'mcqs': _mcqs,
        'theory': _theoryQuestions,
        'subjective': _subjectiveQuestions,
      };

      final db = ref.read(databaseProvider);
      final topic = _topicController.text.trim();
      final schemeOfWorkIdStr = _isFromSchemeOfWork && _schemeOfWorkLocalId != null
          ? _schemeOfWorkLocalId.toString()
          : null;

      // Resolve the term label for this exam
      final termLabel = await _resolveTermLabel(db);

      // Build companion
      final companion = ExamsCompanion(
        subject: Value(_subject),
        classLevel: Value(_classLevel),
        topic: Value(topic),
        difficulty: Value(_difficulty),
        curriculum: const Value('NERDC'),
        content: Value(jsonEncode(content)),
        teacherServerId: Value(_teacherId),
        schoolServerId: Value(_schoolId),
        isUnlocked: Value(_isUnlocked),
        schemeOfWorkId: schemeOfWorkIdStr != null
            ? Value(schemeOfWorkIdStr)
            : const Value.absent(),
        weekNumber: Value(_week),
        term: termLabel != null ? Value(termLabel) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      // Check for existing exam (dedup)
      final existingId = _examId ?? widget.examId;
      final existingExam = existingId != null
          ? await db.examsDao.getById(existingId)
          : (_teacherId != null && _schoolId != null)
              ? await db.examsDao.findByTopicSubjectTeacher(
                  topic: topic,
                  subject: _subject,
                  teacherServerId: _teacherId!,
                  schoolServerId: _schoolId!,
                )
              : null;

      int localId;
      String operation;
      if (existingExam != null) {
        // Update existing
        await db.examsDao.updateExam(existingExam.id, companion);
        localId = existingExam.id;
        operation = 'UPDATE';
      } else {
        // Check storage limit before inserting new exam
        final configService = ref.read(configServiceProvider);
        final storageLimits = configService.lessonStorageLimits;
        final limit = storageLimits[_subscriptionTier] as int? ?? _defaultStorageLimit(_subscriptionTier);
        if (limit >= 0) {
          final currentCount = await db.examsDao.countNonDeletedBySchool(_schoolId ?? '');
          if (currentCount >= limit) {
            if (notify && mounted) {
              showInfoToast(context: context, message: 'Storage limit reached');
            }
            return;
          }
        }

        // Insert new
        final insertCompanion = ExamsCompanion(
          subject: Value(_subject),
          classLevel: Value(_classLevel),
          topic: Value(topic),
          difficulty: Value(_difficulty),
          curriculum: const Value('NERDC'),
          content: Value(jsonEncode(content)),
          teacherServerId: Value(_teacherId),
          schoolServerId: Value(_schoolId),
          isUnlocked: Value(_isUnlocked),
          schemeOfWorkId: schemeOfWorkIdStr != null
              ? Value(schemeOfWorkIdStr)
              : const Value.absent(),
          weekNumber: Value(_week),
          term: termLabel != null ? Value(termLabel) : const Value.absent(),
          createdAt: Value(DateTime.now()),
          isDeleted: const Value(false),
        );
        localId = await db.examsDao.insertExam(insertCompanion);
        operation = 'INSERT';
      }

      // Update local state with the saved exam ID
      _examId = localId;

      // Queue sync entry
      final payload = <String, dynamic>{
        'subject': _subject,
        'class_level': _classLevel,
        'topic': topic,
        'difficulty': _difficulty,
        'curriculum': 'NERDC',
        'teacher_server_id': _teacherId,
        'school_server_id': _schoolId,
        'content': jsonEncode(content),
        'is_unlocked': _isUnlocked,
      };
      if (schemeOfWorkIdStr != null) {
        payload['scheme_of_work_id'] = schemeOfWorkIdStr;
      }
      payload['week_number'] = _week;
      if (termLabel != null) {
        payload['term'] = termLabel;
      }

      await db.syncQueueDao.insertEntry(
        queueTable: 'exams',
        recordLocalId: localId,
        operation: operation,
        payload: payload,
      );

      if (notify && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showInfoToast(context: context, message: 'Exam saved (id=$localId)');
        });
      }
    } catch (e) {
      if (notify && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showErrorToast(context: context, message: 'Save failed: $e');
        });
      }
    }
  }

  void _discard() {
    setState(() {
      _topicController.clear();
      _subject = 'Mathematics';
      _classLevel = 'JSS 1';
      _week = 1;
      _difficulty = 'medium';
      _mcqs = [];
      _theoryQuestions = [];
      _subjectiveQuestions = [];
      _selectedQuestionTypes
        ..clear()
        ..addAll(_defaultQuestionTypes);
      _questionCounts
        ..clear()
        ..addAll(_defaultQuestionCounts);
      _hasGenerated = false;
      _schemeOfWorkLocalId = null;
      _isFromSchemeOfWork = false;
      _selectedLessonId = null;
      _isManualTopicEntry = true;
      _previewRevision++;
    });
  }

  Widget _buildConfigArea({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasSelection = _subject.isNotEmpty && _classLevel.isNotEmpty;
    final summaryItems = <String>[];
    if (_subject.isNotEmpty) summaryItems.add(_subject);
    if (_classLevel.isNotEmpty) summaryItems.add(_classLevel);
    if (_week > 0) summaryItems.add('Week $_week');
    final summary = summaryItems.join(' · ');
    final icon = _configExpanded
        ? Icons.keyboard_arrow_up_rounded
        : Icons.keyboard_arrow_down_rounded;
    return Column(
      children: [
        // Collapsible header
        InkWell(
          onTap: () => setState(() => _configExpanded = !_configExpanded),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exam Configuration',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: cs.onSurface,
                        ),
                      ),
                      if (!_configExpanded && summary.isNotEmpty && hasSelection)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(summary, style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(icon, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
        // Collapsible body
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _configExpanded
              ? Padding(padding: const EdgeInsets.only(top: 24), child: child)
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _topicController.dispose();
    _reviewController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  // ── Nav items ──────────────────────────────────────────────────────
  static const _navItems = [
    _NavDef('Home', Icons.home_rounded, false),
    _NavDef('Lessons', Icons.menu_book_rounded, false),
    _NavDef('Exams', Icons.fact_check_rounded, true),
    // _NavDef('Vault', Icons.inventory_2_rounded, false), // Vault feature disabled
  ];

  static const _bottomNavItems = [
    _BottomDef('Home', Icons.home_rounded, false),
    _BottomDef('Lessons', Icons.menu_book_rounded, false),
    _BottomDef('Exams', Icons.fact_check_rounded, true),
    _BottomDef('More', Icons.more_horiz_rounded, false),
  ];

  @override
  Widget build(BuildContext context) {
    // Combined-exam mode (Term Exam / CA Test) renders a dedicated flow
    // instead of the single-topic editor form. It is only reached via the
    // `compilationType` query parameter.
    if (_compilationMode != null) {
      return _CombinedExamPanel(
        initialMode: _compilationMode!,
        initialSubject: _subject,
        initialClassLevel: _classLevel,
        initialTerm: _termLabel,
        subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
        classLevels: _classLevels,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final totalQuestions = _mcqs.length + _theoryQuestions.length + _subjectiveQuestions.length;
    // True when there are no generated questions to regenerate. Guards the
    // "Regenerate with AI" button so it is disabled for title-only exams.
    final examBodyEmpty = totalQuestions == 0;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _undoController.redo,
      },
      child: Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer (tablet+; never on Android) ─────────
          if (PlatformHelper.shouldShowSidebar(context))
            _NavDrawer(
              cs: cs,
              theme: theme,
              isOpen: _editorSidebarOpen,
              onToggleSidebar: () => setState(
                  () => _editorSidebarOpen = !_editorSidebarOpen),
            ),

          // ── Main Content ─────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Top AppBar ──────────────────────────────────────
                _TopBar(
                  cs: cs,
                  theme: theme,
                  offlineCreditBalance: _offlineCreditBalance,
                  onToggleSidebar: () => setState(
                      () => _editorSidebarOpen = !_editorSidebarOpen),
                  sidebarOpen: _editorSidebarOpen,
                  undoController: _undoController,
                ),

                // ── Editor Workspace ────────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1024;
                      return SingleChildScrollView(
                        physics: (Platform.isAndroid || Platform.isIOS)
                            ? const BouncingScrollPhysics()
                            : null,
                        padding: EdgeInsets.all(
                          isWide
                              ? AppTheme.spacingMarginTablet
                              : AppTheme.spacingMarginMobile,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_sourceMissing)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'The source scheme for this exam no longer exists. '
                                    'You can still edit the exam, but the original scheme link is missing.',
                                    style: TextStyle(color: cs.onErrorContainer),
                                  ),
                                ),
                              ),
                            if (!_sourceMissing && _schemeOfWorkLocalId != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _ExamSchemeContextBanner(
                                  schemeId: _schemeOfWorkLocalId!,
                                  classLevel: _classLevel,
                                  cs: cs,
                                  theme: theme,
                                ),
                              ),
                            Form(
                              key: _formKey,
                              child: isWide
                                  ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 380,
                                      child: _buildConfigArea(
                                        child: _ConfigPanel(
                                          cs: cs,
                                          theme: theme,
                                          subject: _subject,
                                          classLevel: _classLevel,
                                          week: _week,
                                          topicController: _topicController,
                                          undoController: _undoController,
                                          selectedQuestionTypes:
                                              _selectedQuestionTypes,
                                          questionCounts: _questionCounts,
                                          difficulty: _difficulty,
                                          isGenerating: _isGenerating,
                                          isRegenerating: _isRegenerating,
                                          examBodyEmpty: examBodyEmpty,
                                          onRegenerate: _isUnlocked ? _handleRegenerate : null,
                                          reviewController: _reviewController,
                                          offlineCreditBalance: _offlineCreditBalance,
                                          subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                          classLevels: _classLevels,
                                          difficulties: _difficulties,
                                          onSubjectChanged: (v) {
                                            setState(() {
                                              _subject = v;
                                              _selectedLessonId = null;
                                              _isManualTopicEntry = true;
                                              _loadSchemesForContext();
                                            });
                                            _refreshSavedLessonAvailability();
                                          },
                                          onClassChanged: (v) {
                                            setState(() {
                                              _classLevel = v;
                                              _selectedLessonId = null;
                                              _isManualTopicEntry = true;
                                            });
                                            _refreshSavedLessonAvailability();
                                          },
                                          onDifficultyChanged: (v) => setState(
                                              () => _difficulty = v),
                                          onTypeToggled: (type) => setState(() {
                                            if (_selectedQuestionTypes.contains(type)) {
                                              _selectedQuestionTypes.remove(type);
                                            } else {
                                              _selectedQuestionTypes.add(type);
                                            }
                                          }),
                                          onCountChanged: (type, count) => setState(() {
                                            _questionCounts[type] = count;
                                          }),
                                          onGenerate: _handleGenerate,
                                          onAddNewSubject: _showAddSubjectDialog,
                                          savedCoverage: _savedCoverage,
                                          neededQuestions: _neededQuestions,
                                          useSavedLessonQuestions:
                                              _useSavedLessonQuestions,
                                          onSavedToggle: () => setState(
                                            () => _useSavedLessonQuestions =
                                                !_useSavedLessonQuestions,
                                          ),
                                          teacherLessons: _teacherLessons,
                                          schemes: _schemes,
                                          schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                          isFromSchemeOfWork: _isFromSchemeOfWork,
                                          isManualTopicEntry: _isManualTopicEntry,
                                          selectedLessonId: _selectedLessonId,
                                          onWeekChanged: (v) {
                                            setState(() => _week = v);
                                            _refreshSavedLessonAvailability();
                                          },
                                          onLessonSelected: _onLessonSelected,
                                          onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                          onManualTopicSelected: () => _onLessonSelected(null),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: _PreviewPanel(
                                          key: ValueKey(_previewRevision),
                                          cs: cs,
                                          theme: theme,
                                          hasGenerated: _hasGenerated,
                                          isUnlocked: _isUnlocked,
                                          isOnline: _isOnline,
                                          subscriptionTier: _subscriptionTier,
                                          remainingDailyPreviews: _remainingDailyPreviews,
                                          mcqs: _mcqs,
                                          theoryQuestions: _theoryQuestions,
                                          subjectiveQuestions: _subjectiveQuestions,
                                          totalQuestions: totalQuestions,
                                          undoController: _undoController,
                                          onUnlock: _handleUnlock,
                                          onSave: () => _saveExam(),
                                          onDiscard: _discard,
                                          onUpdateMcq: _updateMcq,
                                          onUpdateMcqOption: _updateMcqOption,
                                          onUpdateTheory: _updateTheory,
                                        ),
                                    ),
                                  ],
                                )
                                  : Column(
                                  children: [
                                    _buildConfigArea(
                                      child: _ConfigPanel(
                                        cs: cs,
                                        theme: theme,
                                        subject: _subject,
                                        classLevel: _classLevel,
                                        week: _week,
                                        topicController: _topicController,
                                        undoController: _undoController,
                                        selectedQuestionTypes:
                                            _selectedQuestionTypes,
                                        questionCounts: _questionCounts,
                                        difficulty: _difficulty,
                                        isGenerating: _isGenerating,
                                        isRegenerating: _isRegenerating,
                                        examBodyEmpty: examBodyEmpty,
                                        onRegenerate: _isUnlocked ? _handleRegenerate : null,
                                        reviewController: _reviewController,
                                        offlineCreditBalance: _offlineCreditBalance,
                                        subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                        classLevels: _classLevels,
                                        difficulties: _difficulties,
                                        onSubjectChanged: (v) {
                                          setState(() {
                                            _subject = v;
                                            _selectedLessonId = null;
                                            _isManualTopicEntry = true;
                                            _loadSchemesForContext();
                                          });
                                          _refreshSavedLessonAvailability();
                                        },
                                        onClassChanged: (v) {
                                          setState(() {
                                            _classLevel = v;
                                            _selectedLessonId = null;
                                            _isManualTopicEntry = true;
                                          });
                                          _refreshSavedLessonAvailability();
                                        },
                                        onDifficultyChanged: (v) => setState(
                                            () => _difficulty = v),
                                        onTypeToggled: (type) => setState(() {
                                          if (_selectedQuestionTypes.contains(type)) {
                                            _selectedQuestionTypes.remove(type);
                                          } else {
                                            _selectedQuestionTypes.add(type);
                                          }
                                        }),
                                        onCountChanged: (type, count) => setState(() {
                                          _questionCounts[type] = count;
                                        }),
                                        onGenerate: _handleGenerate,
                                        onAddNewSubject: _showAddSubjectDialog,
                                        savedCoverage: _savedCoverage,
                                        neededQuestions: _neededQuestions,
                                        useSavedLessonQuestions:
                                            _useSavedLessonQuestions,
                                        onSavedToggle: () => setState(
                                          () => _useSavedLessonQuestions =
                                              !_useSavedLessonQuestions,
                                        ),
                                        teacherLessons: _teacherLessons,
                                        schemes: _schemes,
                                        schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                        isFromSchemeOfWork: _isFromSchemeOfWork,
                                        isManualTopicEntry: _isManualTopicEntry,
                                        selectedLessonId: _selectedLessonId,
                                        onWeekChanged: (v) {
                                            setState(() => _week = v);
                                            _refreshSavedLessonAvailability();
                                          },
                                        onLessonSelected: _onLessonSelected,
                                        onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                        onManualTopicSelected: () => _onLessonSelected(null),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    _PreviewPanel(
                                      key: ValueKey(_previewRevision),
                                      cs: cs,
                                      theme: theme,
                                      hasGenerated: _hasGenerated,
                                      isUnlocked: _isUnlocked,
                                      isOnline: _isOnline,
                                      subscriptionTier: _subscriptionTier,
                                      remainingDailyPreviews: _remainingDailyPreviews,
                                      mcqs: _mcqs,
                                      theoryQuestions: _theoryQuestions,
                                      subjectiveQuestions: _subjectiveQuestions,
                                      totalQuestions: totalQuestions,
                                      undoController: _undoController,
                                      onUnlock: _handleUnlock,
                                      onSave: () => _saveExam(),
                                      onDiscard: _discard,
                                      onUpdateMcq: _updateMcq,
                                      onUpdateMcqOption: _updateMcqOption,
                                      onUpdateTheory: _updateTheory,
                                    ),
                                  ],
                                ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Bottom Navigation (mobile) ──────────────────────
                _BottomBar(cs: cs, theme: theme),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════
class _NavDef {
  final String label;
  final IconData icon;
  final bool isActive;
  const _NavDef(this.label, this.icon, this.isActive);
}

class _BottomDef {
  final String label;
  final IconData icon;
  final bool isActive;
  const _BottomDef(this.label, this.icon, this.isActive);
}

// ═══════════════════════════════════════════════════════════════════════
// Navigation Drawer
// ═══════════════════════════════════════════════════════════════════════
class _NavDrawer extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool isOpen;
  final VoidCallback? onToggleSidebar;
  const _NavDrawer({
    required this.cs,
    required this.theme,
    required this.isOpen,
    this.onToggleSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 768 || Platform.isAndroid) return const SizedBox.shrink();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: isOpen ? 288 : 72,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(height: isOpen ? 32 : 16),
              // Logo area — tapping toggles sidebar
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                onTap: onToggleSidebar,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isOpen ? 24 : 12,
                  ),
                  child: isOpen
                      ? Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull,
                                ),
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 24,
                                color: cs.onSurface.withValues(alpha: 0.54),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ClassAI',
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: cs.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Nigerian Academic Partner',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull,
                              ),
                            ),
                            child: Icon(
                              Icons.menu_rounded,
                              size: 24,
                              color: cs.onSurface.withValues(alpha: 0.54),
                            ),
                          ),
                        ),
                ),
              ),
              SizedBox(height: isOpen ? 32 : 16),
              Expanded(
                child: Column(
                  children: _ExamEditorScreenState._navItems.map((item) {
                    return Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isOpen ? 12 : 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: item.isActive
                            ? cs.secondaryFixed
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusFull,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        onTap: () => _navigateTo(context, item.label),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isOpen ? 16 : 8,
                            vertical: 12,
                          ),
                          child: isOpen
                              ? Row(
                                  children: [
                                    Icon(
                                      item.icon,
                                      size: 22,
                                      color: item.isActive
                                          ? cs.onSecondaryFixed
                                          : cs.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        item.label,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: item.isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: item.isActive
                                              ? cs.onSecondaryFixed
                                              : cs.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Icon(
                                    item.icon,
                                    size: 22,
                                    color: item.isActive
                                        ? cs.onSecondaryFixed
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateTo(BuildContext context, String label) {
    switch (label) {
      case 'Home':
        context.go('/');
        break;
      case 'Lessons':
        context.go('/lessons');
        break;
      case 'Exams':
        context.go('/exams');
        break;
      // case 'Vault':
      //   context.go('/vault');
      //   break;
      case 'Admin':
        context.go('/admin');
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Top Bar
// ═══════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final int offlineCreditBalance;
  final VoidCallback? onToggleSidebar;
  final bool sidebarOpen;
  final UndoHistoryController undoController;
  const _TopBar({
    required this.cs,
    required this.theme,
    required this.offlineCreditBalance,
    this.onToggleSidebar,
    required this.sidebarOpen,
    required this.undoController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMarginMobile,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.surfaceContainer,
          ),
        ),
      ),
      child: Row(
        children: [
          // Back button (when navigable)
          if (Navigator.of(context).canPop())
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
              style: IconButton.styleFrom(
                foregroundColor: cs.onSurfaceVariant,
              ),
            ),
          // Mobile avatar (hidden on desktop)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 768) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: cs.onSurface.withValues(alpha: 0.54),
                  ),
                ),
              );
            },
          ),
          Flexible(
            child: Text(
              'Exam Editor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
          // Undo / Redo buttons
          ValueListenableBuilder<UndoHistoryValue>(
            valueListenable: undoController,
            builder: (context, value, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: value.canUndo ? () => undoController.undo() : null,
                    icon: const Icon(Icons.undo_rounded),
                    tooltip: 'Undo (Ctrl+Z)',
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: value.canRedo ? () => undoController.redo() : null,
                    icon: const Icon(Icons.redo_rounded),
                    tooltip: 'Redo (Ctrl+Shift+Z)',
                    style: IconButton.styleFrom(
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          // Credit chip
          RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stars_rounded, size: 20, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$offlineCreditBalance',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Configuration Panel (left column)
// ═══════════════════════════════════════════════════════════════════════
class _ConfigPanel extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String subject;
  final String classLevel;
  final int week;
  final TextEditingController topicController;
  final Set<String> selectedQuestionTypes;
  final Map<String, int> questionCounts;
  final String difficulty;
  final bool isGenerating;
  final bool isRegenerating;
  final bool examBodyEmpty;
  final int offlineCreditBalance;
  final List<String> subjects;
  final List<String> classLevels;
  final List<String> difficulties;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onDifficultyChanged;
  final ValueChanged<String> onTypeToggled;
  final void Function(String, int) onCountChanged;
  final VoidCallback onGenerate;
  final VoidCallback? onRegenerate;
  final TextEditingController? reviewController;
  final UndoHistoryController undoController;
  final VoidCallback? onAddNewSubject;
  final List<Lesson> teacherLessons;
  final List<SchemeOfWorkData> schemes;
  final int? schemeOfWorkLocalId;
  final bool isFromSchemeOfWork;
  final bool isManualTopicEntry;
  final int? selectedLessonId;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<Lesson?> onLessonSelected;
  final ValueChanged<SchemeOfWorkData?> onSchemeOfWorkSelected;
  final VoidCallback onManualTopicSelected;
  final int savedCoverage;
  final int neededQuestions;
  final bool useSavedLessonQuestions;
  final VoidCallback? onSavedToggle;

  const _ConfigPanel({
    required this.cs,
    required this.theme,
    required this.subject,
    required this.classLevel,
    required this.week,
    required this.topicController,
    required this.selectedQuestionTypes,
    required this.questionCounts,
    required this.difficulty,
    required this.isGenerating,
    this.isRegenerating = false,
    this.examBodyEmpty = false,
    required this.offlineCreditBalance,
    required this.subjects,
    required this.classLevels,
    required this.difficulties,
    required this.onSubjectChanged,
    required this.onClassChanged,
    required this.onDifficultyChanged,
    required this.onTypeToggled,
    required this.onCountChanged,
    required this.onGenerate,
    this.onRegenerate,
    this.reviewController,
    required this.undoController,
    this.onAddNewSubject,
    required this.teacherLessons,
    required this.schemes,
    required this.schemeOfWorkLocalId,
    required this.isFromSchemeOfWork,
    required this.isManualTopicEntry,
    required this.selectedLessonId,
    required this.onWeekChanged,
    required this.onLessonSelected,
    required this.onSchemeOfWorkSelected,
    required this.onManualTopicSelected,
    this.savedCoverage = 0,
    this.neededQuestions = 0,
    this.useSavedLessonQuestions = true,
    this.onSavedToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Generation Engine Card ─────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded,
                      color: cs.onPrimaryContainer, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Generation Engine',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Question Types
              _FieldLabel(
                theme: theme,
                cs: cs,
                label: 'Question Types',
                color: cs.onSurface.withValues(alpha: 0.70),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: ['MCQ', 'Theory', 'Subjective'].map((type) {
                  final isSelected = selectedQuestionTypes.contains(type);
                  return FilterChip(
                    label: Text(
                      type,
                      style: TextStyle(
                        color: isSelected
                            ? cs.onSecondaryFixed
                            : cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) => onTypeToggled(type),
                    selectedColor: cs.secondary,
                    checkmarkColor: cs.onSecondaryFixed,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.10),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              // Quantity fields for selected types
              ...['MCQ', 'Theory', 'Subjective']
                  .where((t) => selectedQuestionTypes.contains(t))
                  .map((type) {
                final count = questionCounts[type] ?? 5;
                final labels = {
                  'MCQ': 'Multiple Choice (MCQ)',
                  'Theory': 'Theory / Essay',
                  'Subjective': 'Subjective / Practical',
                };
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel(
                        theme: theme,
                        cs: cs,
                        label: labels[type] ?? type,
                        color: cs.onSurface.withValues(alpha: 0.70),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: AppTheme.touchTarget,
                        child: TextFormField(
                          initialValue: count.toString(),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(AppTheme.radiusLg),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.15),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: cs.onPrimaryContainer),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null && parsed >= 1 && parsed <= 100) {
                              onCountChanged(type, parsed);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              // ── Question Plan Summary ──────────────────────────────
              if (selectedQuestionTypes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question Plan',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Total
                      Row(
                        children: [
                          Icon(Icons.quiz_rounded, size: 16, color: cs.onPrimaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            'Total: ${selectedQuestionTypes.fold<int>(0, (sum, t) => sum + (questionCounts[t] ?? 5))} questions',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Breakdown by type
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: selectedQuestionTypes.map((type) {
                          final count = questionCounts[type] ?? 5;
                          return Text(
                            '$type: $count',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 4),
                      // Difficulty
                      Row(
                        children: [
                          Icon(Icons.tune_rounded, size: 16, color: cs.onPrimaryContainer),
                          const SizedBox(width: 6),
                          Text(
                            'Difficulty: $difficulty',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Phase 3: saved-lesson checkbox (or the calm note when
              // nothing is available). The checkbox IS the warning — no
              // extra popup.
              if (onSavedToggle != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: savedCoverage == 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          ),
                          child: Row(children: [
                            Icon(Icons.info_outline_rounded,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No saved lessons yet — using AI for all questions.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ]),
                        )
                      : InkWell(
                          onTap: onSavedToggle,
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                              border: Border.all(
                                color: cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(children: [
                              Checkbox(
                                value: useSavedLessonQuestions,
                                onChanged: (_) => onSavedToggle?.call(),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Use my saved lesson questions '
                                  '($savedCoverage/$neededQuestions available)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Icon(Icons.auto_awesome_rounded,
                                  size: 18, color: cs.primary),
                            ]),
                          ),
                        ),
                ),
              ],
              // Generate button
              SizedBox(
                width: double.infinity,
                height: AppTheme.touchTarget,
                child: FilledButton.icon(
                  onPressed: isGenerating ? null : onGenerate,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondary,
                    foregroundColor: cs.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    ),
                  ),
                  icon: isGenerating
                      ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.onPrimary,
                            ),
                          )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(
                    isGenerating
                        ? 'Generating...'
                        : 'Generate with AI',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              // ── Review & Regenerate (visible after generation + unlock) ──
              if (onRegenerate != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.onPrimaryContainer.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    border: Border.all(
                      color: cs.secondary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.refresh_rounded, size: 18, color: cs.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Text(
                            'Review & Regenerate',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Difficulty
                      _FieldLabel(
                        theme: theme,
                        cs: cs,
                        label: 'Difficulty',
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: AppTheme.touchTarget,
                        child: DropdownButtonFormField<String>(
                          initialValue: difficulty,
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: cs.onSurface.withValues(alpha: 0.15),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          items: difficulties.map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d[0].toUpperCase() + d.substring(1),
                              style: TextStyle(color: cs.onPrimaryContainer)),
                          )).toList(),
                          onChanged: (v) {
                            if (v != null) onDifficultyChanged(v);
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Review field
                      _FieldLabel(
                        theme: theme,
                        cs: cs,
                        label: 'Suggestions or Corrections',
                        color: cs.onPrimaryContainer.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: reviewController,
                        undoController: undoController,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(
                          hintText: 'Type feedback to guide regeneration...',
                          hintStyle: TextStyle(
                            color: cs.onPrimaryContainer.withValues(alpha: 0.5),
                            fontSize: 13,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: cs.surface.withValues(alpha: 0.5),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                        style: TextStyle(color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: AppTheme.touchTarget,
                        child: FilledButton.icon(
                          onPressed: isRegenerating || examBodyEmpty
                              ? null
                              : onRegenerate,
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.secondary,
                            foregroundColor: cs.onSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            ),
                          ),
                          icon: isRegenerating
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: cs.onSecondary,
                                  ),
                                )
                              : const Icon(Icons.refresh_rounded, size: 20),
                          label: Text(
                            isRegenerating ? 'Regenerating...' : 'Regenerate with AI',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Preview Panel (right column)
// ═══════════════════════════════════════════════════════════════════════
class _PreviewPanel extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool hasGenerated;
  final bool isUnlocked;
  final bool isOnline;
  final String subscriptionTier;
  final int remainingDailyPreviews;
  final List<Map<String, dynamic>> mcqs;
  final List<Map<String, dynamic>> theoryQuestions;
  final List<Map<String, dynamic>> subjectiveQuestions;
  final int totalQuestions;
  final UndoHistoryController undoController;
  final VoidCallback onUnlock;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final void Function(int, String, String) onUpdateMcq;
  final void Function(int, String, String) onUpdateMcqOption;
  final void Function(int, String, String) onUpdateTheory;

  const _PreviewPanel({
    super.key,
    required this.cs,
    required this.theme,
    required this.hasGenerated,
    required this.isUnlocked,
    required this.isOnline,
    required this.subscriptionTier,
    this.remainingDailyPreviews = 10,
    required this.mcqs,
    required this.theoryQuestions,
    required this.subjectiveQuestions,
    required this.totalQuestions,
    required this.undoController,
    required this.onUnlock,
    required this.onSave,
    required this.onDiscard,
    required this.onUpdateMcq,
    required this.onUpdateMcqOption,
    required this.onUpdateTheory,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasGenerated) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            _previewHeader(null),
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.quiz_outlined,
                        size: 48, color: cs.outlineVariant),
                    const SizedBox(height: 12),
                    Text(
                      'Configure and generate\nyour exam to see preview',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview header
          _previewHeader(totalQuestions),

          // Unlocked banner
          if (hasGenerated && isUnlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unlocked — You can edit and save this exam',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: SizedBox(
                        height: 32,
                        child: FilledButton.icon(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                            ),
                          ),
                          icon: const Icon(Icons.save_rounded, size: 16),
                          label: const Text('Save', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Locked overlay
          if (hasGenerated && !isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  border: Border.all(
                    color: cs.tertiary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock_rounded,
                            color: cs.tertiary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Locked — Preview only',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.tertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _buildSummaryText(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: AppTheme.touchTarget,
                      child: FilledButton.icon(
                        onPressed: onUnlock,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiary,
                          foregroundColor: cs.onTertiary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusXl),
                          ),
                        ),
                        icon: const Icon(Icons.lock_open_rounded),
                        label: Text(_buildUnlockLabel()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // ── Locked preview: MCQ (first 2) ─────────────────────
          if (hasGenerated && mcqs.isNotEmpty && !isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _SectionHeader(
                label: 'Section A',
                subtitle: 'Multiple Choice',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  ...List.generate(
                    mcqs.length > 2 ? 2 : mcqs.length,
                    (i) => McqQuestionCard(
                      index: i,
                      mcq: mcqs[i],
                      cs: cs,
                      theme: theme,
                      readOnly: true,
                    ),
                  ),
                  if (mcqs.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '... and ${mcqs.length - 2} more MCQ questions',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // ── Locked preview: Theory (first 2) ──────────────────
          if (hasGenerated && theoryQuestions.isNotEmpty && !isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _SectionHeader(
                label: 'Section B',
                subtitle: 'Theory / Essay',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  ...List.generate(
                    theoryQuestions.length > 2 ? 2 : theoryQuestions.length,
                    (i) => TheoryQuestionCard(
                      index: i,
                      question: theoryQuestions[i],
                      cs: cs,
                      theme: theme,
                      readOnly: true,
                    ),
                  ),
                  if (theoryQuestions.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '... and ${theoryQuestions.length - 2} more theory questions',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // ── Locked preview: Subjective (first 2) ──────────────
          if (hasGenerated && subjectiveQuestions.isNotEmpty && !isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _SectionHeader(
                label: 'Section C',
                subtitle: 'Subjective / Practical',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: [
                  ...List.generate(
                    subjectiveQuestions.length > 2 ? 2 : subjectiveQuestions.length,
                    (i) => TheoryQuestionCard(
                      index: i,
                      question: subjectiveQuestions[i],
                      cs: cs,
                      theme: theme,
                      readOnly: true,
                    ),
                  ),
                  if (subjectiveQuestions.length > 2)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '... and ${subjectiveQuestions.length - 2} more subjective questions',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          // MCQ Section (unlocked — full)
          if (hasGenerated && mcqs.isNotEmpty && isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _SectionHeader(
                label: 'Section A',
                subtitle: 'Multiple Choice',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: List.generate(mcqs.length,
                    (i) => McqQuestionCard(
                      index: i,
                      mcq: mcqs[i],
                      cs: cs,
                      theme: theme,
                      undoController: undoController,
                      onUpdateMcq: onUpdateMcq,
                      onUpdateMcqOption: onUpdateMcqOption,
                    )),
                ),
            ),
          ],

          // Theory Section (unlocked — full)
          if (hasGenerated && theoryQuestions.isNotEmpty && isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _SectionHeader(
                label: 'Section B',
                subtitle: 'Theory / Essay',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: List.generate(
                    theoryQuestions.length, (i) => TheoryQuestionCard(
                      index: i,
                      question: theoryQuestions[i],
                      cs: cs,
                      theme: theme,
                      undoController: undoController,
                      onUpdateTheory: onUpdateTheory,
                    )),
              ),
            ),
          ],

          // Subjective Questions Section (unlocked — full)
          if (hasGenerated && subjectiveQuestions.isNotEmpty && isUnlocked) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _SectionHeader(
                label: 'Section C',
                subtitle: 'Subjective / Practical',
                cs: cs,
                theme: theme,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                children: List.generate(
                    subjectiveQuestions.length, (i) => TheoryQuestionCard(
                      index: i,
                      question: subjectiveQuestions[i],
                      cs: cs,
                      theme: theme,
                      undoController: undoController,
                      onUpdateTheory: onUpdateTheory,
                    )),
              ),
            ),
          ],

          // Action footer
          if (hasGenerated)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SizedBox(
                      height: AppTheme.touchTarget,
                      child: OutlinedButton(
                        onPressed: onDiscard,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusXl),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                        ),
                        child: const Text('Discard'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    fit: FlexFit.loose,
                    child: SizedBox(
                      height: AppTheme.touchTarget,
                      child: FilledButton.icon(
                        onPressed: onSave,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusXl),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                        ),
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _buildSummaryText() {
    final parts = <String>[];
    if (mcqs.isNotEmpty) parts.add('${mcqs.length} MCQs');
    if (theoryQuestions.isNotEmpty) parts.add('${theoryQuestions.length} theory');
    if (subjectiveQuestions.isNotEmpty) parts.add('${subjectiveQuestions.length} subjective');
    return 'Generated ${parts.join(', ')} questions';
  }

  String _buildUnlockLabel() {
    if (!isOnline) return 'Unlock Offline';
    if (subscriptionTier.toLowerCase() == 'elite') return 'Unlock \u2014 Unlimited previews';
    if (remainingDailyPreviews > 0) {
      return 'Unlock \u2014 $remainingDailyPreviews previews left';
    }
    return 'Unlock for 1 Offline Credit';
  }

  Widget _previewHeader(int? totalQuestions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Preview Draft',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
          if (totalQuestions != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$totalQuestions Questions Total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════
// Bottom Navigation Bar (mobile)
// ═══════════════════════════════════════════════════════════════════════
class _BottomBar extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  const _BottomBar({required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!Platform.isAndroid && constraints.maxWidth >= 768) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusFull),
            ),
            child: BottomNavigationBar(
              backgroundColor: cs.surfaceContainerLow,
              elevation: 0,
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 0,
              unselectedFontSize: 0,
              currentIndex: 2,
              onTap: (index) {
                final label = _ExamEditorScreenState._bottomNavItems[index].label;
                _navigateTo(context, label);
              },
              items: _ExamEditorScreenState._bottomNavItems.map((item) {
                return BottomNavigationBarItem(
                  icon: item.isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusFull,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                item.icon,
                                size: 22,
                                color: cs.onSecondaryContainer,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                item.label,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSecondaryContainer,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Icon(
                          item.icon,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                  label: '',
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _navigateTo(BuildContext context, String label) {
    switch (label) {
      case 'Home':
        context.go('/');
        break;
      case 'Lessons':
        context.go('/lessons');
        break;
      case 'Exams':
        context.go('/exams');
        break;
      case 'More':
        context.push('/settings');
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Reusable Widgets
// ═══════════════════════════════════════════════════════════════════════

class _FieldLabel extends StatelessWidget {
  final ThemeData theme;
  final ColorScheme cs;
  final String label;
  final Color? color;
  const _FieldLabel({
    required this.theme,
    required this.cs,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: color ?? cs.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SimpleDropdown extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAddNewSubject;

  const _SimpleDropdown({
    required this.cs,
    required this.theme,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.onAddNewSubject,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(theme: theme, cs: cs, label: label),
        const SizedBox(height: 4),
        Container(
          height: AppTheme.touchTarget,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surface,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.arrow_drop_down_rounded),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
              ),
              items: [
                ...items.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text(
                      item,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  );
                }),
                const DropdownMenuItem<String>(
                  value: '__add_new__',
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Add new subject…'),
                    ],
                  ),
                ),
              ],
              onChanged: (v) {
                if (v != null) {
                  if (v == '__add_new__') {
                    onAddNewSubject?.call();
                  } else {
                    onChanged(v);
                  }
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String subtitle;
  final ColorScheme cs;
  final ThemeData theme;
  const _SectionHeader({
    required this.label,
    required this.subtitle,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: cs.onSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.surface,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            subtitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              overflow: TextOverflow.clip,
            ),
          ),
        ),
      ],
    );
  }
  
}

// ---------------------------------------------------------------------------
// Exam Scheme Context Banner
// ---------------------------------------------------------------------------
/// Shows a contextual banner when the exam is linked to a scheme of work.
class _ExamSchemeContextBanner extends ConsumerWidget {
  const _ExamSchemeContextBanner({
    required this.schemeId,
    required this.classLevel,
    required this.cs,
    required this.theme,
  });

  final int schemeId;
  final String classLevel;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<SchemeOfWorkData?>(
      future: ref.read(databaseProvider).schemeOfWorkDao.getById(schemeId),
      builder: (context, snapshot) {
        final scheme = snapshot.data;
        if (scheme == null) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.primary.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Linked to Scheme of Work',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Class: $classLevel • Week ${scheme.weekNumber} • Topic: ${scheme.topic}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Combined Exam flow (Term Exam / CA Test)
// ═══════════════════════════════════════════════════════════════════════

/// Dedicated flow shown inside the exam editor when it is opened with a
/// `compilationType` query parameter ('termExam' or 'caTest'). Replaces the
/// old standalone Full-Term Exam screen:
///
/// - The exam type is chosen on the `/exams` choice screen; this setup panel
///   locks to that mode: **Term Exam** (all term topics, pre-selected with
///   per-topic question counts) or **CA Test** (tick only the topics taught
///   so far).
/// - Subject / Class / Term pickers.
/// - ONE combined exam generated via the multi-topic
///   [PromptTemplates.examQuestions] prompt and saved as a single exam row.
class _CombinedExamPanel extends ConsumerStatefulWidget {
  const _CombinedExamPanel({
    required this.initialMode,
    required this.initialSubject,
    required this.initialClassLevel,
    required this.initialTerm,
    required this.subjects,
    required this.classLevels,
  });

  /// 'termExam' or 'caTest' — the initial selection of the mode cards.
  final String initialMode;
  final String initialSubject;
  final String initialClassLevel;
  final String initialTerm;
  final List<String> subjects;
  final List<String> classLevels;

  @override
  ConsumerState<_CombinedExamPanel> createState() => _CombinedExamPanelState();
}

class _CombinedExamPanelState extends ConsumerState<_CombinedExamPanel> {
  static const _terms = ['1st Term', '2nd Term', '3rd Term'];
  static const _defaultQuestionsPerTopic = 5;

  late String _mode;
  late String _subject;
  late String _classLevel;
  late String _term;

  List<TermTopic> _topics = [];
  List<int> _questionCounts = [];
  Set<int> _selectedIndexes = {};
  bool _isLoadingTopics = true;
  String? _topicsError;
  bool _isGenerating = false;
  final _totalQuestionsController = TextEditingController(text: '30');

  // Phase 3 hybrid: reuse saved lesson questions when available; AI fills
  // only the remaining counts.
  bool _useSavedLessonQuestions = true;
  SavedLessonQuestions? _savedLessonQuestions;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode == 'caTest' ? 'caTest' : 'termExam';
    _subject = widget.initialSubject;
    _classLevel = widget.initialClassLevel;
    _term = _terms.contains(widget.initialTerm) ? widget.initialTerm : _terms.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTopics());
  }

  @override
  void dispose() {
    _totalQuestionsController.dispose();
    super.dispose();
  }

  /// AI fallback used only when no matching scheme rows or curated NERDC
  /// topics exist for the selected subject/class/term.
  Future<Map<String, dynamic>> _aiGenerate(String prompt) async {
    if (!await PlatformHelper.isOnline()) {
      throw const ExamTopicsUnavailableException();
    }
    final db = ref.read(databaseProvider);
    return AiService(db: db).generate(prompt);
  }

  Future<void> _loadTopics() async {
    setState(() {
      _isLoadingTopics = true;
      _topicsError = null;
    });
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      final teacherServerId = authState.currentTeacher?.serverId;
      if (school == null || teacherServerId == null) {
        if (!mounted) return;
        setState(() {
          _topicsError = 'Teacher or school data not available.';
          _isLoadingTopics = false;
        });
        return;
      }
      final teacher = await db.teachersDao.findByServerId(teacherServerId);
      if (teacher == null) {
        if (!mounted) return;
        setState(() {
          _topicsError = 'Teacher account not ready yet.';
          _isLoadingTopics = false;
        });
        return;
      }

      final service = ExamGenerationService(db);
      final topics = await service.loadTermTopics(
        schoolId: school.localId,
        teacherId: teacher.localId,
        subject: _subject,
        classLevel: _classLevel,
        termLabel: _term,
        aiGenerate: _aiGenerate,
      );
      if (!mounted) return;
      setState(() {
        if (topics == null || topics.isEmpty) {
          _topicsError = 'No topics found for $_subject, $_classLevel, '
              '$_term. Try a different combination or check your internet '
              'connection.';
        } else {
          _topics = topics;
          _questionCounts = List.filled(topics.length, _defaultQuestionsPerTopic);
          // Term Exam pre-selects every topic; CA Test starts empty.
          _selectedIndexes = _mode == 'caTest'
              ? <int>{}
              : {for (var i = 0; i < topics.length; i++) i};
        }
        _isLoadingTopics = false;
      });
      _refreshSavedLessonQuestions();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _topicsError = 'Failed to load topics: $e';
        _isLoadingTopics = false;
      });
    }
  }

  /// Selected topics with their requested per-topic counts — Term Exam:
  /// every topic with count > 0; CA Test: the ticked topics at the default
  /// count. Shared by `_generate`, the saved-coverage label and the refresh.
  List<(TermTopic, int)> _selectedTopicsWithCounts() {
    final result = <(TermTopic, int)>[];
    if (_mode == 'termExam') {
      for (var i = 0; i < _topics.length; i++) {
        if (_questionCounts[i] > 0) {
          result.add((_topics[i], _questionCounts[i]));
        }
      }
    } else {
      final indexes = _selectedIndexes.toList()..sort();
      for (final index in indexes) {
        result.add((_topics[index], _defaultQuestionsPerTopic));
      }
    }
    return result;
  }

  /// Refreshes the saved lesson questions for the current selection
  /// (subject/class/term/weeks). Cheap: one in-memory filter over the
  /// school's non-deleted lessons. Runs on topic load, mode switch and CA
  /// Test tick changes.
  Future<void> _refreshSavedLessonQuestions() async {
    final selected = _selectedTopicsWithCounts();
    if (selected.isEmpty) {
      if (mounted) setState(() => _savedLessonQuestions = null);
      return;
    }
    final db = ref.read(databaseProvider);
    final authState = ref.read(authProvider);
    final school = authState.currentSchool ?? await db.schoolsDao.get();
    final teacherServerId = authState.currentTeacher?.serverId;
    if (school == null || teacherServerId == null) return;
    final saved = await ExamGenerationService(db).loadSavedLessonQuestions(
      teacherServerId: teacherServerId,
      schoolServerId: school.serverId ?? '',
      subject: _subject,
      classLevel: _classLevel,
      termLabel: _term,
      weekNumbers: [for (final (t, _) in selected) t.weekNumber],
    );
    if (!mounted) return;
    setState(() {
      _savedLessonQuestions = saved;
      // Nothing usable → the calm note replaces the checkbox and generation
      // is the pure-AI path (decision §12.6).
      if (saved.total == 0) _useSavedLessonQuestions = false;
    });
  }

  /// Phase 3 label: X/Y — how many of the requested questions the saved
  /// lesson questions can cover (exact same distribution the service uses).
  (int, int) _savedCoverage() {
    if (_savedLessonQuestions == null) return (0, 0);
    final saved = _savedLessonQuestions!;
    var needed = 0, covered = 0, mcqNeeded = 0, theoryNeeded = 0, subjNeeded = 0;
    for (final (_, count) in _selectedTopicsWithCounts()) {
      final (m, t, s) = ExamGenerationService.distributePerTopicCount(count);
      needed += count;
      mcqNeeded += m;
      theoryNeeded += t;
      subjNeeded += s;
    }
    covered = min(saved.mcqs.length, mcqNeeded).toInt() +
        min(saved.theory.length, theoryNeeded).toInt() +
        min(saved.subjective.length, subjNeeded).toInt();
    return (covered, needed);
  }

  /// The saved-lesson row shown directly above the Generate button: the
  /// tappable checkbox when questions are available, the calm note otherwise.
  Widget _buildSavedLessonRow(ColorScheme cs, ThemeData theme) {
    final (covered, needed) = _savedCoverage();
    if (covered == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No saved lessons yet — using AI for all questions.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ]),
      );
    }
    return InkWell(
      onTap: () => setState(
        () => _useSavedLessonQuestions = !_useSavedLessonQuestions,
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(children: [
          Checkbox(
            value: _useSavedLessonQuestions,
            onChanged: (_) => setState(
              () => _useSavedLessonQuestions = !_useSavedLessonQuestions,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Use my saved lesson questions '
              '($covered/$needed available)',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.auto_awesome_rounded, size: 18, color: cs.primary),
        ]),
      ),
    );
  }

  void _autoDistribute() {
    final totalText = _totalQuestionsController.text.trim();
    final total = int.tryParse(totalText);
    if (total == null || total <= 0) {
      showErrorToast(context: context, message: 'Enter a valid total question count.');
      return;
    }
    if (_topics.isEmpty) return;

    final base = total ~/ _topics.length;
    var remainder = total % _topics.length;
    setState(() {
      for (var i = 0; i < _topics.length; i++) {
        _questionCounts[i] = base + (i < remainder ? 1 : 0);
      }
    });
    showInfoToast(
      context: context,
      message: 'Distributed $total questions across ${_topics.length} topics.',
    );
  }

  Future<void> _showUpgradeRequired() async {
    if (!mounted) return;
    final role = ref.read(authProvider).currentTeacher?.role;
    if (role == 'admin') {
      if (mounted) context.push('/payment');
      return;
    }
    await showUpgradeRequestDialog(context, ref, requestedTier: 'elite');
  }

  Future<void> _generate() async {
    // Build the selected topic list (Term Exam: every topic with a count > 0;
    // CA Test: only the ticked topics).
    final selected = _selectedTopicsWithCounts();
    if (selected.isEmpty) {
      showErrorToast(
        context: context,
        message: 'Select at least one topic to generate.',
      );
      return;
    }
    final selectedTopics = [for (final (t, _) in selected) t];
    final selectedCounts = [for (final (_, c) in selected) c];

    // Tier gate — same as the single-topic editor.
    final authTier =
        ref.read(authProvider).currentSchool?.subscriptionTier.toLowerCase() ??
            '';
    final config = ref.read(configServiceProvider);
    if (!config.examGenerationAllowedTiers.contains(authTier)) {
      await _showUpgradeRequired();
      return;
    }

    // Skip the online requirement when saved lessons cover everything — the
    // service never calls AI in that case (no credits, works offline).
    final (covered, needed) = _savedCoverage();
    final needsAi = !_useSavedLessonQuestions || needed > covered;
    if (needsAi && !await PlatformHelper.isOnline()) {
      showErrorToast(
        context: context,
        message: 'Generation requires internet — try again when connected.',
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final teacher = authState.currentTeacher;
      final school = authState.currentSchool;
      if (teacher == null || school == null || teacher.serverId == null) {
        showErrorToast(
          context: context,
          message: 'Authentication data not available.',
        );
        setState(() => _isGenerating = false);
        return;
      }

      final service = ExamGenerationService(db);
      final topicTitle = _mode == 'termExam'
          ? 'Term Exam (${selectedTopics.length} topics)'
          : 'CA Test (${selectedTopics.length} topics)';
      final examId = await service.generateCombinedExam(
        subject: _subject,
        classLevel: _classLevel,
        termLabel: _term,
        teacherServerId: teacher.serverId!,
        schoolServerId: school.serverId,
        subscriptionTier: school.subscriptionTier.toLowerCase(),
        examGenerationAllowedTiers: config.examGenerationAllowedTiers,
        lessonStorageLimits:
            ref.read(configServiceProvider).lessonStorageLimits,
        difficulty: 'medium',
        topics: selectedTopics,
        questionCounts: selectedCounts,
        topicTitle: topicTitle,
        aiGenerate: _aiGenerate,
        useSavedLessonQuestions: _useSavedLessonQuestions,
        teacherName: teacher.teacherName,
        schoolName: school.schoolName,
      );

      if (!mounted) return;
      setState(() => _isGenerating = false);
      // Big success confirmation. The setup screen is the final review, so
      // generation jumps straight into the new exam with a green banner —
      // there is no extra confirmation dialog before Generate.
      AppToast.instance.showToast(
        context: context,
        message: _mode == 'termExam'
            ? 'Term exam created as draft!'
            : 'CA Test created as draft!',
        icon: Icons.check_circle_rounded,
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
      );
      context.pushReplacement('/exams/$examId');
    } on ExamStorageLimitExceededException {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      showInfoToast(
        context: context,
        message: 'Exam storage limit reached. Upgrade your school plan to '
            'create more exams.',
      );
    } on ExamGenerationNotAllowedException {
      // Defense-in-depth: the pre-check above normally catches this, but the
      // remote config may change between the check and the call.
      if (!mounted) return;
      setState(() => _isGenerating = false);
      await _showUpgradeRequired();
    } on ExamIncompleteGenerationException {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      showErrorToast(
        context: context,
        message: 'AI could not complete the exam — no exam was created. '
            'Try again.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      final collected = _useSavedLessonQuestions &&
          (_savedLessonQuestions?.total ?? 0) > 0;
      showErrorToast(
        context: context,
        message: collected
            ? 'Saved questions were found, but AI could not finish the exam — '
                'no exam was created. Try again.'
            : 'Failed to generate exam: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final hasSelection = _mode == 'caTest'
        ? _selectedIndexes.isNotEmpty
        : _questionCounts.any((c) => c > 0);
    final canGenerate = !_isLoadingTopics &&
        _topicsError == null &&
        !_isGenerating &&
        hasSelection;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        // The setup screen always has a visible back affordance returning to
        // the `/exams` choice screen (or wherever this screen was pushed
        // from, e.g. the list zero state). History-preserving: pop when this
        // screen was pushed, and fall back to the /exams choice screen when
        // it was reached with no history (e.g. a deep link) — never Home.
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/exams');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to exams',
        ),
        title: Text(
          _mode == 'termExam' ? 'Term Exam Setup' : 'CA Test Setup',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
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
        surfaceTintColor: cs.surface,
      ),
      body: Column(
        children: [
          // ── Subject / Class / Term pickers ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _subject,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Subject',
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    // Always include the current value — the pre-filled
                    // subject (e.g. from the Exams list filter) may not be in
                    // the loaded list on the very first frame.
                    items: [
                      ...widget.subjects
                          .map((s) => DropdownMenuItem(value: s, child: Text(s))),
                      if (!widget.subjects.contains(_subject))
                        DropdownMenuItem(value: _subject, child: Text(_subject)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _subject = v);
                      _loadTopics();
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _classLevel,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Class Level',
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    // Always include the current value (a filter class like
                    // 'JSS3' without a space must not crash the dropdown).
                    items: [
                      ...widget.classLevels
                          .map((c) => DropdownMenuItem(value: c, child: Text(c))),
                      if (!widget.classLevels.contains(_classLevel))
                        DropdownMenuItem(
                          value: _classLevel,
                          child: Text(_classLevel),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _classLevel = v);
                      _loadTopics();
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _term,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Term',
                      filled: true,
                      fillColor: cs.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    items: _terms
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _term = v);
                      _loadTopics();
                    },
                  ),
                ),
              ],
            ),
          ),
          // ── Topic list ──────────────────────────────────────────────
          Expanded(child: _buildTopics(cs, theme)),
          // ── Bottom action bar ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_mode == 'termExam') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _totalQuestionsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Total Questions',
                              filled: true,
                              fillColor: cs.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(color: cs.outlineVariant),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _autoDistribute,
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          label: const Text('Auto-Distribute'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Phase 3: saved-lesson checkbox (or the calm note when
                  // nothing is available) — directly above the Generate
                  // button.
                  if (!_isLoadingTopics &&
                      _topicsError == null &&
                      hasSelection) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSavedLessonRow(cs, theme),
                    ),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canGenerate ? _generate : null,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome_rounded),
                      label: Text(
                        _isGenerating
                            ? 'Generating...'
                            : _mode == 'termExam'
                                ? 'Generate Term Exam'
                                : 'Generate CA Test',
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopics(ColorScheme cs, ThemeData theme) {
    if (_isLoadingTopics) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_topicsError != null) {
      return Center(
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
                _topicsError!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadTopics,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_topics.isEmpty) {
      return const Center(child: Text('No topics found.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: _topics.length,
      itemBuilder: (context, index) {
        final topic = _topics[index];
        if (_mode == 'caTest') {
          final selected = _selectedIndexes.contains(index);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selectedIndexes.remove(index);
                  } else {
                    _selectedIndexes.add(index);
                  }
                });
                _refreshSavedLessonQuestions();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.6)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: selected,
                      onChanged: (_) {
                        setState(() {
                          if (selected) {
                            _selectedIndexes.remove(index);
                          } else {
                            _selectedIndexes.add(index);
                          }
                        });
                        _refreshSavedLessonQuestions();
                      },
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      ),
                      child: Center(
                        child: Text(
                          'W${topic.weekNumber}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        topic.topic,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _CombinedTopicCard(
            weekNumber: topic.weekNumber,
            topicName: topic.topic,
            questionCount: _questionCounts[index],
            onQuestionCountChanged: (value) {
              setState(() => _questionCounts[index] = value);
            },
            cs: cs,
            theme: theme,
          ),
        );
      },
    );
  }
}

/// Topic row for Term Exam mode: week badge + topic + per-topic question count.
class _CombinedTopicCard extends StatefulWidget {
  const _CombinedTopicCard({
    required this.weekNumber,
    required this.topicName,
    required this.questionCount,
    required this.onQuestionCountChanged,
    required this.cs,
    required this.theme,
  });

  final int weekNumber;
  final String topicName;
  final int questionCount;
  final ValueChanged<int> onQuestionCountChanged;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  State<_CombinedTopicCard> createState() => _CombinedTopicCardState();
}

class _CombinedTopicCardState extends State<_CombinedTopicCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.questionCount.toString());
  }

  @override
  void didUpdateWidget(_CombinedTopicCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reflect external changes (e.g. Auto-Distribute) unless the teacher is
    // actively typing in this field.
    if (widget.questionCount != oldWidget.questionCount &&
        _controller.text != widget.questionCount.toString()) {
      _controller.text = widget.questionCount.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final theme = widget.theme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Center(
              child: Text(
                'W${widget.weekNumber}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.topicName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainer,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                isDense: true,
                labelText: 'Q',
                labelStyle: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              onChanged: (value) {
                final count = int.tryParse(value);
                if (count != null && count >= 0) {
                  widget.onQuestionCountChanged(count);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
