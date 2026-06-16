import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

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
  int _week = 1;
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  bool _isGenerating = false;
  bool _hasGenerated = false;
  bool _isUnlocked = false;
  int? _examId;
  bool _editorSidebarOpen = true;
  int _creditBalance = 3;
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
  List<Lesson> _teacherLessons = [];
  int? _selectedLessonId;
  bool _isManualTopicEntry = true;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithEmergencyFlush();
      _loadCreditBalance();
      _loadAuthInfo();
      _loadSubjects();
      _loadSchemesForContext();
      _loadTeacherLessons();
    });
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
        await db.subjectsDao.insert(name: result);
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
          _loadedSubjects = subjects.map((s) => s.name).toList();
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
        final schemes = await db.schemeOfWorkDao.getApprovedBySubject(subjectId);
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

  void _onSchemeOfWorkSelected(SchemeOfWorkData? scheme) {
    if (scheme == null) {
      setState(() {
        _schemeOfWorkLocalId = null;
        _isFromSchemeOfWork = false;
        _week = 1;
        _selectedLessonId = null;
        _isManualTopicEntry = true;
      });
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
    });
  }

  void _onLessonSelected(Lesson? lesson) {
    if (lesson == null) {
      setState(() {
        _selectedLessonId = null;
        _isManualTopicEntry = true;
      });
      return;
    }
    setState(() {
      _selectedLessonId = lesson.id;
      _topicController.text = lesson.topic;
      _week = lesson.weekNumber ?? lesson.week;
      _isManualTopicEntry = false;
    });
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
    } catch (_) {}
  }

  Future<void> _loadCreditBalance() async {
    try {
      final db = ref.read(databaseProvider);
      final config = await db.securityConfigDao.get();
      if (mounted) {
        setState(() => _creditBalance = config.offlineCredits);
      }
    } catch (_) {}
  }

  Future<void> _handleGenerate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isGenerating = true);

    try {
      final db = ref.read(databaseProvider);
      final aiService = AiService(db: db);
      final topic = _topicController.text.trim();
      final generateMcq = _selectedQuestionTypes.contains('MCQ');
      final generateTheory = _selectedQuestionTypes.contains('Theory');
      final generateSubjective = _selectedQuestionTypes.contains('Subjective');

      // Check daily generation limit before generating
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

      // Check daily preview limit
      final previewAllowed = await db.securityConfigDao
          .checkAndIncrementDailyPreviews(tier: _subscriptionTier);
      if (!previewAllowed) {
        if (mounted) {
          setState(() => _isGenerating = false);
          showErrorToast(
            context: context,
            message: 'Daily preview limit reached (10/day). Try again tomorrow.',
          );
        }
        return;
      }

      // Generate questions
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      _mcqs = [];
      _theoryQuestions = [];
      _subjectiveQuestions = [];

      if (generateMcq) {
        final mcqPrompt = PromptTemplates.mcqs(
          _subject,
          _classLevel,
          topic,
          _difficulty,
          teacherName: _teacherName,
          schoolName: _schoolName,
        );
        Map<String, dynamic> mcqResult = {};
        if (widget.generateCallback != null) {
          mcqResult = await widget.generateCallback!(mcqPrompt);
        } else {
          mcqResult = await aiService.generate(mcqPrompt);
        }
        final mcqRaw = mcqResult['raw'] as Map<String, dynamic>? ?? mcqResult;
        final mcqList = mcqRaw['questions'] as List<dynamic>? ?? [];
        _mcqs =
            mcqList.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      }

      if (generateTheory) {
        final theoryPrompt = PromptTemplates.theoryQuestions(
          _subject,
          _classLevel,
          topic,
          teacherName: _teacherName,
          schoolName: _schoolName,
        );
        Map<String, dynamic> theoryResult = {};
        if (widget.generateCallback != null) {
          theoryResult = await widget.generateCallback!(theoryPrompt);
        } else {
          theoryResult = await aiService.generate(theoryPrompt);
        }
        final theoryRaw =
            theoryResult['raw'] as Map<String, dynamic>? ?? theoryResult;
        final theoryList = theoryRaw['questions'] as List<dynamic>? ?? [];
        _theoryQuestions =
            theoryList.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      }

      if (generateSubjective) {
        final subjectivePrompt = PromptTemplates.subjectiveQuestions(
          _subject,
          _classLevel,
          topic,
          teacherName: _teacherName,
          schoolName: _schoolName,
        );
        Map<String, dynamic> subjectiveResult = {};
        if (widget.generateCallback != null) {
          subjectiveResult = await widget.generateCallback!(subjectivePrompt);
        } else {
          subjectiveResult = await aiService.generate(subjectivePrompt);
        }
        final subjectiveRaw =
            subjectiveResult['raw'] as Map<String, dynamic>? ?? subjectiveResult;
        final subjectiveList = subjectiveRaw['questions'] as List<dynamic>? ?? [];
        _subjectiveQuestions =
            subjectiveList.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      }

      // Audit log the generation
      await aiService.logGeneration(
        teacherId: _teacherId,
        schoolId: _schoolId,
        topic: topic,
      );

      setState(() {
        _hasGenerated = true;
        _isUnlocked = false;
        _isGenerating = false;
      });

      await _saveExam(notify: false);

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final parts = <String>[];
          if (_mcqs.isNotEmpty) parts.add('${_mcqs.length} MCQs');
          if (_theoryQuestions.isNotEmpty) parts.add('${_theoryQuestions.length} theory');
          if (_subjectiveQuestions.isNotEmpty) parts.add('${_subjectiveQuestions.length} subjective');
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
    if (_creditBalance < 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        AppToast.instance.showToast(
          context: context,
          message: 'Out of credits. Connect to internet and sync to refill.',
          icon: Icons.warning,
        );
        _showSyncBottomSheet();
      });
      return;
    }

    try {
      final creditService = CreditService(ref.read(databaseProvider));
      final topicId = _topicController.text.trim();
      await creditService.spendCredits(
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
        _creditBalance = _creditBalance - 1;
      });

      ref.read(creditStateProvider.notifier).refresh();

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
            Text('Sync Credits', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Tap below to sync with the server and refill your credits.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // Refresh credit state
                final db = ref.read(databaseProvider);
                db.securityConfigDao.get().then((config) {
                  if (mounted) {
                    setState(() => _creditBalance = config.offlineCredits);
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
        weekNumber: _isFromSchemeOfWork && _schemeOfWorkLocalId != null
            ? const Value.absent()
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      // Check for existing exam (dedup)
      final existingId = _examId ?? widget.examId;
      final existingExam = existingId != null
          ? await db.examsDao.getById(existingId)
          : await db.examsDao.findByTopicSubjectTeacher(
              topic: topic,
              subject: _subject,
              teacherServerId: _teacherId ?? '',
            );

      int localId;
      String operation;
      if (existingExam != null) {
        // Update existing
        await db.examsDao.updateExam(existingExam.id, companion);
        localId = existingExam.id;
        operation = 'UPDATE';
      } else {
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
          weekNumber: _isFromSchemeOfWork && _schemeOfWorkLocalId != null
              ? Value(_schemeOfWorkLocalId)
              : const Value.absent(),
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
        'classLevel': _classLevel,
        'topic': topic,
        'difficulty': _difficulty,
        'curriculum': 'NERDC',
        'teacher_server_id': _teacherId,
        'school_server_id': _schoolId,
      };
      if (schemeOfWorkIdStr != null) {
        payload['scheme_of_work_id'] = schemeOfWorkIdStr;
      }
      if (_isFromSchemeOfWork && _schemeOfWorkLocalId != null) {
        payload['week_number'] = _schemeOfWorkLocalId;
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
    });
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  // ── Nav items ──────────────────────────────────────────────────────
  static const _navItems = [
    _NavDef('Home', Icons.home_rounded, false),
    _NavDef('Lessons', Icons.menu_book_rounded, false),
    _NavDef('Exams', Icons.quiz_rounded, true),
    _NavDef('Vault', Icons.inventory_2_rounded, false),
    _NavDef('Admin', Icons.admin_panel_settings_rounded, false),
  ];

  static const _bottomNavItems = [
    _BottomDef('Home', Icons.home_rounded, false),
    _BottomDef('Lessons', Icons.menu_book_rounded, false),
    _BottomDef('Exams', Icons.quiz_rounded, true),
    _BottomDef('More', Icons.more_horiz_rounded, false),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final totalQuestions = _mcqs.length + _theoryQuestions.length + _subjectiveQuestions.length;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer (tablet+) ──────────────────────────
          _NavDrawer(
            cs: cs,
            theme: theme,
            isOpen: _editorSidebarOpen,
          ),

          // ── Main Content ─────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Top AppBar ──────────────────────────────────────
                _TopBar(
                  cs: cs,
                  theme: theme,
                  creditBalance: _creditBalance,
                  onToggleSidebar: () => setState(
                      () => _editorSidebarOpen = !_editorSidebarOpen),
                  sidebarOpen: _editorSidebarOpen,
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
                        child: Form(
                          key: _formKey,
                          child: isWide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 380,
                                      child: _ConfigPanel(
                                          cs: cs,
                                          theme: theme,
                                          subject: _subject,
                                          classLevel: _classLevel,
                                          week: _week,
                                          topicController: _topicController,
                                          selectedQuestionTypes:
                                              _selectedQuestionTypes,
                                          questionCounts: _questionCounts,
                                          difficulty: _difficulty,
                                          isGenerating: _isGenerating,
                                          creditBalance: _creditBalance,
                                          subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                          classLevels: _classLevels,
                                          difficulties: _difficulties,
                                          onSubjectChanged: (v) => setState(() {
                                            _subject = v;
                                            _selectedLessonId = null;
                                            _isManualTopicEntry = true;
                                            _loadSchemesForContext();
                                          }),
                                          onClassChanged: (v) => setState(() {
                                              _classLevel = v;
                                              _selectedLessonId = null;
                                              _isManualTopicEntry = true;
                                            }),
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
                                          teacherLessons: _teacherLessons,
                                          schemes: _schemes,
                                          schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                          isFromSchemeOfWork: _isFromSchemeOfWork,
                                          isManualTopicEntry: _isManualTopicEntry,
                                          selectedLessonId: _selectedLessonId,
                                          onWeekChanged: (v) => setState(() => _week = v),
                                          onLessonSelected: _onLessonSelected,
                                          onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                          onManualTopicSelected: () => _onLessonSelected(null),
                                        ),
                                    ),
                                    const SizedBox(width: 24),
                                    Expanded(
                                      child: _PreviewPanel(
                                        cs: cs,
                                        theme: theme,
                                        hasGenerated: _hasGenerated,
                                        isUnlocked: _isUnlocked,
                                        mcqs: _mcqs,
                                        theoryQuestions: _theoryQuestions,
                                        subjectiveQuestions: _subjectiveQuestions,
                                        totalQuestions: totalQuestions,
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
                                    _ConfigPanel(
                                      cs: cs,
                                      theme: theme,
                                      subject: _subject,
                                      classLevel: _classLevel,
                                      week: _week,
                                      topicController: _topicController,
                                      selectedQuestionTypes:
                                          _selectedQuestionTypes,
                                      questionCounts: _questionCounts,
                                      difficulty: _difficulty,
                                      isGenerating: _isGenerating,
                                      creditBalance: _creditBalance,
                                      subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                      classLevels: _classLevels,
                                      difficulties: _difficulties,
                                      onSubjectChanged: (v) => setState(() {
                                          _subject = v;
                                          _selectedLessonId = null;
                                          _isManualTopicEntry = true;
                                          _loadSchemesForContext();
                                        }),
                                      onClassChanged: (v) => setState(() {
                                        _classLevel = v;
                                        _selectedLessonId = null;
                                        _isManualTopicEntry = true;
                                      }),
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
                                      teacherLessons: _teacherLessons,
                                      schemes: _schemes,
                                      schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                      isFromSchemeOfWork: _isFromSchemeOfWork,
                                      isManualTopicEntry: _isManualTopicEntry,
                                      selectedLessonId: _selectedLessonId,
                                      onWeekChanged: (v) => setState(() => _week = v),
                                      onLessonSelected: _onLessonSelected,
                                      onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                      onManualTopicSelected: () => _onLessonSelected(null),
                                    ),
                                    const SizedBox(height: 24),
                                    _PreviewPanel(
                                      cs: cs,
                                      theme: theme,
                                      hasGenerated: _hasGenerated,
                                      isUnlocked: _isUnlocked,
                                      mcqs: _mcqs,
                                      theoryQuestions: _theoryQuestions,
                                      subjectiveQuestions: _subjectiveQuestions,
                                      totalQuestions: totalQuestions,
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
  const _NavDrawer({
    required this.cs,
    required this.theme,
    required this.isOpen,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 768) return const SizedBox.shrink();
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
              // Logo area
              if (isOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ClassAI',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                          Text(
                            'Nigerian Academic Partner',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
                      Icons.person_rounded,
                      size: 24,
                      color: cs.onSurface.withValues(alpha: 0.54),
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
      case 'Vault':
        context.go('/vault');
        break;
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
  final int creditBalance;
  final VoidCallback? onToggleSidebar;
  final bool sidebarOpen;
  const _TopBar({
    required this.cs,
    required this.theme,
    required this.creditBalance,
    this.onToggleSidebar,
    required this.sidebarOpen,
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
          // Sidebar toggle (tablet+)
          if (onToggleSidebar != null)
            IconButton(
              onPressed: onToggleSidebar,
              icon: Icon(sidebarOpen
                  ? Icons.menu_open_rounded
                  : Icons.menu_rounded),
              tooltip: sidebarOpen ? 'Close sidebar' : 'Open sidebar',
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
          Text(
            'Exam Editor',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const Spacer(),
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
                    '$creditBalance',
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
  final int creditBalance;
  final List<String> subjects;
  final List<String> classLevels;
  final List<String> difficulties;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onDifficultyChanged;
  final ValueChanged<String> onTypeToggled;
  final void Function(String, int) onCountChanged;
  final VoidCallback onGenerate;
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
    required this.creditBalance,
    required this.subjects,
    required this.classLevels,
    required this.difficulties,
    required this.onSubjectChanged,
    required this.onClassChanged,
    required this.onDifficultyChanged,
    required this.onTypeToggled,
    required this.onCountChanged,
    required this.onGenerate,
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
  });

  @override
  Widget build(BuildContext context) {
    final filteredLessons = teacherLessons
        .where((lesson) => lesson.subject == subject)
        .where((lesson) => lesson.classLevel == classLevel)
        .toList();
    final selectedLesson = selectedLessonId != null
        ? filteredLessons.where((lesson) => lesson.id == selectedLessonId).firstOrNull
        : null;
    return Column(
      children: [
        // ── Exam Configuration Card ────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exam Configuration',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              const SizedBox(height: 8),
              // Lesson topics dropdown
              _FieldLabel(theme: theme, cs: cs, label: 'Topics'),
              const SizedBox(height: 4),
              if (teacherLessons.isEmpty)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => context.go('/lesson-editor'),
                    child: const Text('No lessons yet. Generate a lesson first.'),
                  ),
                )
              else
                SizedBox(
                  height: AppTheme.touchTarget,
                  child: DropdownButtonFormField<String>(
                    initialValue: isManualTopicEntry
                        ? '__manual__'
                        : selectedLesson?.id.toString(),
                    isExpanded: true,
                    decoration: InputDecoration(
                      hintText: filteredLessons.isEmpty
                          ? 'No matching lessons'
                          : 'Select a lesson topic...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      filled: true,
                      fillColor: cs.surface,
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '__manual__',
                        child: Text('✏️ Write a new topic'),
                      ),
                      ...filteredLessons.map((lesson) {
                        final lessonWeek = lesson.weekNumber ?? lesson.week;
                        return DropdownMenuItem<String>(
                          value: lesson.id.toString(),
                          child: Text('Week $lessonWeek: ${lesson.topic}'),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      if (value == null || value == '__manual__') {
                        onManualTopicSelected();
                        return;
                      }
                      final lesson = filteredLessons
                          .where((item) => item.id.toString() == value)
                          .firstOrNull;
                      if (lesson == null) {
                        onManualTopicSelected();
                        return;
                      }
                      onLessonSelected(lesson);
                    },
                  ),
                ),
              const SizedBox(height: 16),
              _FieldLabel(theme: theme, cs: cs, label: 'Topic'),
              const SizedBox(height: 4),
              SizedBox(
                height: AppTheme.touchTarget,
                child: TextFormField(
                  controller: topicController,
                  readOnly: !isManualTopicEntry,
                  decoration: InputDecoration(
                    hintText: 'e.g. Advanced Mathematics: Calculus',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    filled: true,
                    fillColor: cs.surface,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 16),
              _FieldLabel(theme: theme, cs: cs, label: 'Week'),
              const SizedBox(height: 4),
              SizedBox(
                height: AppTheme.touchTarget,
                width: 120,
                child: TextFormField(
                  key: ValueKey(week),
                  initialValue: week.toString(),
                  readOnly: !isManualTopicEntry,
                  keyboardType: TextInputType.number,
                  onChanged: isManualTopicEntry
                      ? (value) {
                          final parsed = int.tryParse(value);
                          if (parsed != null) {
                            onWeekChanged(parsed);
                          }
                        }
                      : null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    filled: true,
                    fillColor: cs.surface,
                  ),
                ),
              ),
              // Grade Level + Duration row
              Row(
                children: [
                  Expanded(
                    child: _SimpleDropdown(
                      cs: cs,
                      theme: theme,
                      label: 'Grade Level',
                      value: classLevel,
                      items: classLevels,
                      onChanged: onClassChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _FieldLabel(
                      theme: theme,
                      cs: cs,
                      label: 'Duration (Mins)',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Subject dropdown
              _SimpleDropdown(
                cs: cs,
                theme: theme,
                label: 'Subject',
                onAddNewSubject: onAddNewSubject,
                value: subject,
                items: subjects,
                onChanged: onSubjectChanged,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

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
  final List<Map<String, dynamic>> mcqs;
  final List<Map<String, dynamic>> theoryQuestions;
  final List<Map<String, dynamic>> subjectiveQuestions;
  final int totalQuestions;
  final VoidCallback onUnlock;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final void Function(int, String, String) onUpdateMcq;
  final void Function(int, String, String) onUpdateMcqOption;
  final void Function(int, String, String) onUpdateTheory;

  const _PreviewPanel({
    required this.cs,
    required this.theme,
    required this.hasGenerated,
    required this.isUnlocked,
    required this.mcqs,
    required this.theoryQuestions,
    required this.subjectiveQuestions,
    required this.totalQuestions,
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
                    Text(
                      'Unlocked — You can edit and save this exam',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Locked overlay
          if (hasGenerated && !isUnlocked) ...[
            RepaintBoundary(
              child: Padding(
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
                          label: const Text('Unlock for 1 Credit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // MCQ Section
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
                    (i) => _buildMcqCard(i, theme, cs)),
                ),
            ),
          ],

          // Theory Section
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
                    theoryQuestions.length, (i) => _buildTheoryCard(i, theme, cs)),
              ),
            ),
          ],

          // Subjective Questions Section
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
                    subjectiveQuestions.length, (i) => _buildTheoryCard(i, theme, cs)),
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
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
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
                  const SizedBox(width: 12),
                  SizedBox(
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
                      label: const Text('Save to Vault'),
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
            Text(
              '$totalQuestions Questions Total',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMcqCard(int index, ThemeData theme, ColorScheme cs) {
    final mcq = mcqs[index];
    final question = mcq['question'] as String? ?? '';
    final options = mcq['options'] as Map<String, dynamic>? ?? {};
    final correct = mcq['correct'] as String? ?? 'A';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question number
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    AppTheme.radiusFull,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: question,
                  maxLines: 2,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  onChanged: (v) => onUpdateMcq(index, 'question', v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Options grid
          ...['A', 'B', 'C', 'D'].map((key) {
            final optVal = options[key] as String? ?? '';
            final isCorrect = correct == key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => onUpdateMcq(index, 'correct', key),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCorrect
                            ? cs.secondaryContainer
                            : Colors.transparent,
                        border: Border.all(
                          color: isCorrect
                              ? cs.secondary
                              : cs.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: isCorrect
                          ? Icon(Icons.check_rounded,
                              size: 14, color: cs.onSecondaryContainer)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$key.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextFormField(
                      initialValue: optVal,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      onChanged: (v) =>
                          onUpdateMcqOption(index, key, v),
                    ),
                  ),
                  if (isCorrect)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'CORRECT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.secondary,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTheoryCard(int index, ThemeData theme, ColorScheme cs) {
    final theory = theoryQuestions[index];
    final question = theory['question'] as String? ?? '';
    final modelAnswer = theory['modelAnswer'] as String? ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    AppTheme.radiusFull,
                  ),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: question,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Question',
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onChanged: (v) => onUpdateTheory(index, 'question', v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: modelAnswer,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Marking Guide / Expected Elements',
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  style: BorderStyle.solid,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  style: BorderStyle.solid,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
              fillColor: cs.surfaceContainerLow,
              filled: true,
            ),
            onChanged: (v) => onUpdateTheory(index, 'modelAnswer', v),
          ),
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
        if (constraints.maxWidth >= 768) return const SizedBox.shrink();
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
        context.go('/settings');
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
