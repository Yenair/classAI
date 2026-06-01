import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/widgets/animated_pressable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Stitch‑designed lesson note editor with AI generation.
///
/// Form fields: Subject dropdown, Class dropdown, Week spinbox,
/// Topic textfield, Difficulty segmented control, Bloom's verbs multi‑select chips,
/// Assessment format segmented control.
/// "Generate with AI" builds a prompt, calls the provided [generateCallback],
/// then populates preview cards with editable text fields per section.
/// "Save to Vault" inserts into `lessons` table.
/// Registers with [EmergencyFlushService] on init.
class LessonEditorScreen extends ConsumerStatefulWidget {
  /// Callback invoked with the generated prompt; returns parsed JSON map.
  /// In production this wraps [AiService.generate]; in tests a mock is used.
  final Future<Map<String, dynamic>> Function(String prompt)? generateCallback;

  /// If provided, pre-fills the form from an existing lesson.
  final int? lessonId;

  const LessonEditorScreen({super.key, this.generateCallback, this.lessonId});

  @override
  ConsumerState<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _LessonEditorScreenState extends ConsumerState<LessonEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  int? _lessonId;
  String _lessonStatus = 'draft';
  int _week = 1;
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  String _assessmentFormat = 'Both';
  final Set<String> _selectedBlooms = {};
  bool _isGenerating = false;
  bool _hasGenerated = false;
  bool _isUnlocked = false;
  bool _editorSidebarOpen = true;
  int _creditBalance = 0;
  String? _encryptedContent;
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

  // Generated content (editable after generation)
  String _objectivesText = '';
  String _vocabularyText = '';
  String _materialsText = '';
  String _presentationText = '';
  String _assessmentText = '';
  String _homeworkText = '';

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

  final List<String> _bloomVerbs = [
    'Remember',
    'Understand',
    'Apply',
    'Analyze',
    'Evaluate',
    'Create',
  ];

  @override
  void initState() {
    super.initState();
    _lessonId = widget.lessonId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithEmergencyFlush();
      _loadCreditBalance();
      _loadAuthInfo();
      _loadSubjects();
      _loadSchemes();
      if (_lessonId != null) {
        _loadLesson(_lessonId!);
      }
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
        // Subject may already exist
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

  Future<void> _loadSchemes() async {
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

  Future<void> _loadLesson(int id) async {
    try {
      final db = ref.read(databaseProvider);
      final lesson = await db.lessonsDao.getById(id);
      if (lesson != null && mounted) {
        setState(() {
          _topicController.text = lesson.topic;
          _lessonStatus = lesson.status;
          _week = lesson.week;
          _subject = lesson.subject;
          _classLevel = lesson.classLevel;
          _schemeOfWorkLocalId = lesson.schemeOfWorkId != null
              ? int.tryParse(lesson.schemeOfWorkId!)
              : null;
          if (lesson.weekNumber != null) {
            _week = lesson.weekNumber!;
          }
          _isFromSchemeOfWork = _schemeOfWorkLocalId != null;
        });
      }
    } catch (_) {
      // Lesson not found — continue with empty form
    }
  }

  void _registerWithEmergencyFlush() {
    final flushService = ref.read(emergencyFlushServiceProvider);
    flushService.register(() async {
      if (_hasGenerated && _isUnlocked && _formKey.currentState!.validate()) {
        await _saveLesson(notify: false);
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
        // Try to get teacher name from DB
        final teachers = await db.teachersDao.getAll();
        if (teachers.isNotEmpty) {
          final teacher = teachers.first;
          _teacherId ??= teacher.serverId;
          _teacherName = teacher.teacherName;
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadCreditBalance() async {
    try {
      await ref.read(creditStateProvider.notifier).refresh();
      if (mounted) {
        setState(() =>
            _creditBalance = ref.read(creditStateProvider).currentCredits);
      }
    } catch (_) {}
  }

  Future<void> _handleGenerate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isGenerating = true);

    try {
      final db = ref.read(databaseProvider);

      // Check daily preview limit before generating
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

      // Build prompt with teacher/school attribution
      final bloomsStr =
          _selectedBlooms.isEmpty ? 'All levels' : _selectedBlooms.join(', ');
      final prompt = PromptTemplates.lessonNote(
        _subject,
        'NERDC',
        _classLevel,
        _week,
        _topicController.text.trim(),
        _difficulty,
        bloomsStr,
        teacherName: _teacherName,
        schoolName: _schoolName,
      );

      // Generate via callback or fallback to AiService
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      Map<String, dynamic> result;
      if (widget.generateCallback != null) {
        // Test / external callback path – skip AiService setup
        result = await widget.generateCallback!(prompt);
      } else {
        // Production path: call the AI generation service directly
        final aiService = AiService(db: db);

        // Check daily generation limit before generating
        try {
          await aiService.checkDailyLimit(_subscriptionTier);
        } on AiGenerationException catch (e) {
          if (mounted) {
            setState(() => _isGenerating = false);
            showErrorToast(context: context, message: e.message);
          }
          return;
        }

        result = await aiService.generate(prompt);

        // Audit log the generation
        await aiService.logGeneration(
          teacherId: _teacherId,
          schoolId: _schoolId,
          topic: _topicController.text.trim(),
        );
      }

      // Parse the generated JSON
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      _encryptedContent = result['encryptedContent'] as String?;
      setState(() {
        _objectivesText = _formatList(raw['objectives']);
        _vocabularyText = _formatList(raw['vocabulary']);
        _materialsText = _formatList(raw['materials']);
        _presentationText = _formatJson(raw['presentation']);
        _assessmentText = raw['assessment'] as String? ?? '';
        _homeworkText = raw['homework'] as String? ?? '';
        _hasGenerated = true;
        _isUnlocked = false;
        _isGenerating = false;
      });

      await _saveLesson(notify: false);

      if (mounted) {
        showInfoToast(
            context: context, message: 'Lesson generated successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showErrorToast(context: context, message: 'Generation failed: $e');
      }
    }
  }

  Future<void> _handleUnlock() async {
    if (_creditBalance < 1) {
      // Show persistent toast with sync option
      AppToast.instance.showToast(
        context: context,
        message: 'Out of credits. Connect to internet and sync to refill.',
        icon: Icons.warning,
      );
      _showSyncBottomSheet();
      return;
    }

    try {
      final creditService = CreditService(ref.read(databaseProvider));
      await creditService.spendCredits(amount: 1, contentIds: ['lesson_draft']);

      // Audit log the unlock
      await ref.read(databaseProvider).auditLogsDao.insert(
        AuditLogsCompanion.insert(
          id: Value(const Uuid().v4()),
          teacherId: Value(_teacherId),
          schoolId: Value(_schoolId),
          action: Value('unlock'),
          metadata: Value(jsonEncode({
            'type': 'lesson',
            'topic': _topicController.text.trim(),
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
        showInfoToast(context: context, message: 'Lesson unlocked!');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Failed to unlock: $e');
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
                // Trigger sync
                ref.read(creditStateProvider.notifier).refresh();
              },
              child: const Text('Sync Now'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatList(dynamic items) {
    if (items == null) return '';
    if (items is List) {
      return items.map((e) => e is String ? e : e.toString()).join('\n');
    }
    return items.toString();
  }

  String _formatJson(dynamic obj) {
    if (obj == null) return '';
    if (obj is Map) {
      return obj.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    return obj.toString();
  }

  Future<void> _saveLesson({bool notify = true}) async {
    try {
      final content = {
        'objectives': _objectivesText,
        'vocabulary': _vocabularyText,
        'materials': _materialsText,
        'presentation': _presentationText,
        'assessment': _assessmentText,
        'homework': _homeworkText,
      };
      final topic = _topicController.text.trim();

      final db = ref.read(databaseProvider);

      // Build companion with common fields
      final schemeOfWorkIdStr = _schemeOfWorkLocalId?.toString();
      LessonsCompanion companion = LessonsCompanion(
        subject: Value(_subject),
        classLevel: Value(_classLevel),
        week: Value(_week),
        topic: Value(topic),
        difficulty: Value(_difficulty),
        bloomsVerbs: Value(_selectedBlooms.join(', ')),
        curriculum: Value('NERDC'),
        content: Value(_encryptedContent ?? jsonEncode(content)),
        teacherServerId: Value(_teacherId),
        schoolServerId: Value(_schoolId),
        isUnlocked: Value(_isUnlocked),
        schemeOfWorkId: schemeOfWorkIdStr != null
            ? Value(schemeOfWorkIdStr)
            : const Value.absent(),
        weekNumber: _isFromSchemeOfWork
            ? Value(_week)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      int id;

      // Dedup: check for existing lesson with same topic/subject/week/teacher
      if (_teacherId != null) {
        final existing = await db.lessonsDao.findByTopicSubjectWeekTeacher(
          topic: topic,
          subject: _subject,
          week: _week,
          teacherServerId: _teacherId!,
        );
        if (existing != null) {
          // Update existing lesson
          id = existing.id;
          await db.lessonsDao.updateLesson(id, companion);

          // Queue UPDATE sync entry
          await db.syncQueueDao.insertEntry(
            queueTable: 'lessons',
            recordLocalId: id,
            operation: 'UPDATE',
            payload: {
              'subject': _subject,
              'classLevel': _classLevel,
              'week': _week,
              'topic': topic,
              'difficulty': _difficulty,
              'bloomsVerbs': _selectedBlooms.join(', '),
              'curriculum': 'NERDC',
              'teacher_server_id': _teacherId,
              'school_server_id': _schoolId,
              if (schemeOfWorkIdStr != null) 'scheme_of_work_id': schemeOfWorkIdStr,
              if (_isFromSchemeOfWork) 'week_number': _week,
            },
          );

          if (notify && mounted) {
            showInfoToast(context: context, message: 'Lesson updated (id=$id)');
          }
          return;
        }
      }

      // No existing lesson found — insert new
      id = await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: _subject,
          classLevel: _classLevel,
          week: _week,
          topic: topic,
          difficulty: _difficulty,
          bloomsVerbs: _selectedBlooms.join(', '),
          curriculum: 'NERDC',
          content: _encryptedContent ?? jsonEncode(content),
          teacherServerId: Value(_teacherId),
          schoolServerId: Value(_schoolId),
          isUnlocked: Value(_isUnlocked),
          schemeOfWorkId: schemeOfWorkIdStr != null
              ? Value(schemeOfWorkIdStr)
              : const Value.absent(),
          weekNumber: _isFromSchemeOfWork
              ? Value(_week)
              : const Value.absent(),
        ),
      );

      // Queue sync entry
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: id,
        operation: 'INSERT',
        payload: {
          'subject': _subject,
          'classLevel': _classLevel,
          'week': _week,
          'topic': topic,
          'difficulty': _difficulty,
          'bloomsVerbs': _selectedBlooms.join(', '),
          'curriculum': 'NERDC',
          'teacher_server_id': _teacherId,
          'school_server_id': _schoolId,
          if (schemeOfWorkIdStr != null) 'scheme_of_work_id': schemeOfWorkIdStr,
          if (_isFromSchemeOfWork) 'week_number': _week,
        },
      );

      if (notify && mounted) {
        showInfoToast(context: context, message: 'Lesson saved (id=$id)');
      }
    } catch (e) {
      if (notify && mounted) {
        showErrorToast(context: context, message: 'Save failed: $e');
      }
    }
  }

  Future<void> _handleToggleComplete() async {
    if (_lessonId == null || _schoolId == null || _teacherId == null) return;
    final newStatus = _lessonStatus == 'completed' ? 'draft' : 'completed';
    try {
      final db = ref.read(databaseProvider);
      await db.lessonsDao.updateStatus(_lessonId!, newStatus);
      final school = await db.schoolsDao.get();
      final logId = await db.progressLogsDao.insert(
        ProgressLogsCompanion.insert(
          eventType: newStatus == 'completed' ? 'lesson_completed' : 'lesson_reopened',
          lessonId: Value(_lessonId!),
          teacherId: Value(int.tryParse(_teacherId ?? '0') ?? 0),
          schoolId: Value(school?.localId ?? 0),
        ),
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': newStatus == 'completed' ? 'lesson_completed' : 'lesson_reopened',
          'lesson_id': _lessonId,
          'teacher_id': _teacherId,
          'school_id': _schoolId,
        },
      );
      setState(() => _lessonStatus = newStatus);
      if (mounted) {
        showInfoToast(context: context, message: newStatus == 'completed' ? 'Lesson marked as completed!' : 'Lesson reopened');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Failed to update status: $e');
      }
    }
  }

  void _onSchemeOfWorkSelected(SchemeOfWorkData? scheme) {
    if (scheme == null) {
      setState(() {
        _schemeOfWorkLocalId = null;
        _isFromSchemeOfWork = false;
      });
      return;
    }
    final displayTopic = scheme.adminEditedTopic ?? scheme.topic;
    setState(() {
      _schemeOfWorkLocalId = scheme.id;
      _isFromSchemeOfWork = true;
      _week = scheme.weekNumber;
      _topicController.text = displayTopic;
    });
  }

  Future<void> _loadSchemesForSubject(String subject) async {
    try {
      final db = ref.read(databaseProvider);
      final subjectRow = await db.subjectsDao.getByName(subject);
      final subjectId = subjectRow?.id;
      if (subjectId != null) {
        final schemes = await db.schemeOfWorkDao.getApprovedBySubject(subjectId);
        if (mounted) {
          setState(() => _schemes = schemes);
        }
      } else {
        if (mounted) {
          setState(() => _schemes = []);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _schemes = []);
      }
    }
  }

  void _discard() {
    setState(() {
      _topicController.clear();
      _week = 1;
      _subject = 'Mathematics';
      _classLevel = 'JSS 1';
      _difficulty = 'medium';
      _selectedBlooms.clear();
      _objectivesText = '';
      _vocabularyText = '';
      _materialsText = '';
      _presentationText = '';
      _assessmentText = '';
      _homeworkText = '';
      _encryptedContent = null;
      _hasGenerated = false;
      _schemeOfWorkLocalId = null;
      _isFromSchemeOfWork = false;
    });
  }

  @override
  void dispose() {
    _topicController.dispose();
    super.dispose();
  }

  // ── Nav item data class ──────────────────────────────────────────────
  static const _navItems = [
    _NavItem('Home', Icons.home_rounded, false),
    _NavItem('Lessons', Icons.menu_book_rounded, true),
    _NavItem('Exams', Icons.quiz_rounded, false),
    _NavItem('Vault', Icons.inventory_2_rounded, false),
    _NavItem('Admin', Icons.admin_panel_settings_rounded, false),
  ];

  // ── Bottom nav items (mobile) ────────────────────────────────────────
  static const _bottomNavItems = [
    _BottomNavDef('Home', Icons.home_rounded, false),
    _BottomNavDef('Lessons', Icons.menu_book_rounded, true),
    _BottomNavDef('Exams', Icons.quiz_rounded, false),
    _BottomNavDef('More', Icons.more_horiz_rounded, false),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer (tablet+) ─────────────────────────
          _NavigationDrawer(
            cs: cs,
            theme: theme,
            isOpen: _editorSidebarOpen,
          ),

          // ── Main Content ────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Mobile Header ──────────────────────────────────
                _MobileHeader(
                  cs: cs,
                  theme: theme,
                  creditBalance: _creditBalance,
                ),

                // ── Scrollable content ─────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1024;
                      return SingleChildScrollView(

                        physics: (Platform.isAndroid || Platform.isIOS)
                            ? const BouncingScrollPhysics()
                            : null,
                        child: Column(
                          children: [
                            // ── Tool Header Area ────────────────────
                            _ToolHeader(
                              cs: cs,
                              theme: theme,
                              onToggleSidebar: () => setState(
                                  () => _editorSidebarOpen = !_editorSidebarOpen),
                              sidebarOpen: _editorSidebarOpen,
                            ),

                            // ── Two-column layout ───────────────────
                            Padding(
                              padding: EdgeInsets.all(
                                isWide
                                    ? AppTheme.spacingMarginTablet
                                    : AppTheme.spacingMarginMobile,
                              ),
                              child: Form(
                                key: _formKey,
                                child: isWide
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Left column: config
                                          SizedBox(
                                            width: 450,
                                            child: _ConfigColumn(
                                                  cs: cs,
                                                  theme: theme,
                                                  subject: _subject,
                                                  classLevel: _classLevel,
                                                  week: _week,
                                                  difficulty: _difficulty,
                                                  assessmentFormat:
                                                      _assessmentFormat,
                                                  selectedBlooms: _selectedBlooms,
                                                  isGenerating: _isGenerating,
                                                  hasGenerated: _hasGenerated,
                                                  subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                                  classLevels: _classLevels,
                                                  difficulties: _difficulties,
                                                  bloomVerbs: _bloomVerbs,
                                                  topicController: _topicController,
                                                  onSubjectChanged: (v) {
                                                    setState(() => _subject = v);
                                                    _loadSchemesForSubject(v);
                                                  },
                                                  onClassChanged: (v) =>
                                                      setState(() =>
                                                          _classLevel = v),
                                                  onWeekChanged: (v) =>
                                                      setState(() => _week = v),
                                                  onDifficultyChanged: (v) =>
                                                      setState(() =>
                                                          _difficulty = v),
                                                  onAssessmentFormatChanged: (v) =>
                                                      setState(() =>
                                                          _assessmentFormat = v),
                                                  onBloomToggled: (verb) {
                                                    setState(() {
                                                      if (_selectedBlooms
                                                          .contains(verb)) {
                                                        _selectedBlooms
                                                            .remove(verb);
                                                      } else {
                                                        _selectedBlooms.add(verb);
                                                      }
                                                    });
                                                  },
                                                  onGenerate: _handleGenerate,
                                                  schemes: _schemes,
                                                  schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                                  isFromSchemeOfWork: _isFromSchemeOfWork,
                                                  onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                                ),
                                          ),
                                          const SizedBox(width: 24),
                                          // Right column: preview
                                          Expanded(
                                            child: _PreviewColumn(
                                              cs: cs,
                                              theme: theme,
                                              hasGenerated: _hasGenerated,
                                              isUnlocked: _isUnlocked,
                                              objectivesText: _objectivesText,
                                              vocabularyText: _vocabularyText,
                                              materialsText: _materialsText,
                                              presentationText:
                                                  _presentationText,
                                              assessmentText: _assessmentText,
                                              homeworkText: _homeworkText,
                                              onObjectivesChanged: (v) =>
                                                  setState(() =>
                                                      _objectivesText = v),
                                              onVocabularyChanged: (v) =>
                                                  setState(() =>
                                                      _vocabularyText = v),
                                              onMaterialsChanged: (v) =>
                                                  setState(() =>
                                                      _materialsText = v),
                                              onPresentationChanged: (v) =>
                                                  setState(() =>
                                                      _presentationText = v),
                                              onAssessmentChanged: (v) =>
                                                  setState(() =>
                                                      _assessmentText = v),
                                              onHomeworkChanged: (v) =>
                                                  setState(() =>
                                                      _homeworkText = v),
                                              onUnlock: _handleUnlock,
                                              onSave: _saveLesson,
                                              onDiscard: _discard,
                                              lessonStatus: _lessonStatus,
                                              onToggleComplete: _isUnlocked ? _handleToggleComplete : null,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          _ConfigColumn(
                                            cs: cs,
                                            theme: theme,
                                            subject: _subject,
                                            classLevel: _classLevel,
                                            week: _week,
                                            difficulty: _difficulty,
                                            assessmentFormat:
                                                _assessmentFormat,
                                            selectedBlooms: _selectedBlooms,
                                            isGenerating: _isGenerating,
                                            hasGenerated: _hasGenerated,
                                            subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                            classLevels: _classLevels,
                                            difficulties: _difficulties,
                                            bloomVerbs: _bloomVerbs,
                                            topicController: _topicController,
                                            onSubjectChanged: (v) {
                                              setState(() => _subject = v);
                                              _loadSchemesForSubject(v);
                                            },
                                            onClassChanged: (v) => setState(
                                                () => _classLevel = v),
                                            onWeekChanged: (v) =>
                                                setState(() => _week = v),
                                            onDifficultyChanged: (v) =>
                                                setState(
                                                    () => _difficulty = v),
                                            onAssessmentFormatChanged: (v) =>
                                                setState(() =>
                                                    _assessmentFormat = v),
                                            onBloomToggled: (verb) {
                                              setState(() {
                                                if (_selectedBlooms
                                                    .contains(verb)) {
                                                  _selectedBlooms.remove(verb);
                                                } else {
                                                  _selectedBlooms.add(verb);
                                                }
                                              });
                                            },
                                            onGenerate: _handleGenerate,
                                            onAddNewSubject: _showAddSubjectDialog,
                                            schemes: _schemes,
                                            schemeOfWorkLocalId: _schemeOfWorkLocalId,
                                            isFromSchemeOfWork: _isFromSchemeOfWork,
                                            onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                          ),
                                          const SizedBox(height: 24),
                                          _PreviewColumn(
                                            cs: cs,
                                            theme: theme,
                                            hasGenerated: _hasGenerated,
                                            isUnlocked: _isUnlocked,
                                            objectivesText: _objectivesText,
                                            vocabularyText: _vocabularyText,
                                            materialsText: _materialsText,
                                            presentationText:
                                                _presentationText,
                                            assessmentText: _assessmentText,
                                            homeworkText: _homeworkText,
                                            onObjectivesChanged: (v) =>
                                                setState(() =>
                                                    _objectivesText = v),
                                            onVocabularyChanged: (v) =>
                                                setState(() =>
                                                    _vocabularyText = v),
                                            onMaterialsChanged: (v) =>
                                                setState(() =>
                                                    _materialsText = v),
                                            onPresentationChanged: (v) =>
                                                setState(() =>
                                                    _presentationText = v),
                                            onAssessmentChanged: (v) =>
                                                setState(() =>
                                                    _assessmentText = v),
                                            onHomeworkChanged: (v) =>
                                                setState(() =>
                                                    _homeworkText = v),
                                            onUnlock: _handleUnlock,
                                            onSave: _saveLesson,
                                            onDiscard: _discard,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // ── Bottom Navigation (mobile) ─────────────────────
                _BottomNavBar(cs: cs, theme: theme),
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
class _NavItem {
  final String label;
  final IconData icon;
  final bool isActive;
  const _NavItem(this.label, this.icon, this.isActive);
}

class _BottomNavDef {
  final String label;
  final IconData icon;
  final bool isActive;
  const _BottomNavDef(this.label, this.icon, this.isActive);
}

// ═══════════════════════════════════════════════════════════════════════
// Navigation Drawer (tablet+)
// ═══════════════════════════════════════════════════════════════════════
class _NavigationDrawer extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool isOpen;
  const _NavigationDrawer({
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
              SizedBox(height: isOpen ? 24 : 16),
              // Logo area
              if (isOpen)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusFull,
                              ),
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: cs.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'ClassAI',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 52),
                        child: Text(
                          'Nigerian Academic Partner',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusFull,
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      color: cs.onPrimaryContainer,
                      size: 22,
                    ),
                  ),
                ),
              SizedBox(height: isOpen ? 32 : 16),
              // Nav items
              Expanded(
                child: Column(
                  children: _LessonEditorScreenState._navItems.map((item) {
                    return Container(
                        margin: EdgeInsets.symmetric(
                          horizontal: isOpen ? 12 : 4,
                        vertical: 2,
                      ),
                      transform: item.isActive
                          ? Matrix4.translationValues(isOpen ? 4.0 : 0.0, 0.0, 0.0)
                          : Matrix4.identity(),
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
                                    Text(
                                      item.label,
                                      style: theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: item.isActive
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: item.isActive
                                            ? cs.onSecondaryFixed
                                            : cs.onSurfaceVariant,
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
// Mobile Header
// ═══════════════════════════════════════════════════════════════════════
class _MobileHeader extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final int creditBalance;
  const _MobileHeader({
    required this.cs,
    required this.theme,
    required this.creditBalance,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 768) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTheme.spacingMarginMobile,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(
                color: cs.surfaceContainer.withValues(alpha: 1.0),
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Icon(Icons.person_rounded, size: 18, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Text(
                'ClassAI',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                ),
              ),
              const Spacer(),
              Text(
                '$creditBalance',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: cs.onSurfaceVariant,
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
// Tool Header
// ═══════════════════════════════════════════════════════════════════════
class _ToolHeader extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback? onToggleSidebar;
  final bool sidebarOpen;
  const _ToolHeader({
    required this.cs,
    required this.theme,
    this.onToggleSidebar,
    required this.sidebarOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMarginMobile,
        vertical: 24,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back link + Toggle
          Row(
            children: [
              // Sidebar toggle (tablet+) - moved to left
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
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Back to Lessons',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Lesson Editor',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure parameters to generate high-quality, localized educational content.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Config Column (left side)
// ═══════════════════════════════════════════════════════════════════════
class _ConfigColumn extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String subject;
  final String classLevel;
  final int week;
  final String difficulty;
  final String assessmentFormat;
  final Set<String> selectedBlooms;
  final bool isGenerating;
  final bool hasGenerated;
  final List<String> subjects;
  final List<String> classLevels;
  final List<String> difficulties;
  final List<String> bloomVerbs;
  final TextEditingController topicController;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<String> onDifficultyChanged;
  final ValueChanged<String> onAssessmentFormatChanged;
  final ValueChanged<String> onBloomToggled;
  final VoidCallback onGenerate;
  final VoidCallback? onAddNewSubject;
  final List<SchemeOfWorkData> schemes;
  final int? schemeOfWorkLocalId;
  final bool isFromSchemeOfWork;
  final ValueChanged<SchemeOfWorkData?> onSchemeOfWorkSelected;

  const _ConfigColumn({
    required this.cs,
    required this.theme,
    required this.subject,
    required this.classLevel,
    required this.week,
    required this.difficulty,
    required this.assessmentFormat,
    required this.selectedBlooms,
    required this.isGenerating,
    required this.hasGenerated,
    required this.subjects,
    required this.classLevels,
    required this.difficulties,
    required this.bloomVerbs,
    required this.topicController,
    required this.onSubjectChanged,
    required this.onClassChanged,
    required this.onWeekChanged,
    required this.onDifficultyChanged,
    required this.onAssessmentFormatChanged,
    required this.onBloomToggled,
    required this.onGenerate,
    this.onAddNewSubject,
    required this.schemes,
    required this.schemeOfWorkLocalId,
    required this.isFromSchemeOfWork,
    required this.onSchemeOfWorkSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Curriculum Context Card ──────────────────────────────────
        _StitchCard(
          cs: cs,
          theme: theme,
          title: 'Curriculum Context',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Subject + Class row
              Row(
                children: [
                  Expanded(
                    child: _StyledDropdown<String>(
                      cs: cs,
                      theme: theme,
                      label: 'Subject',
                      onAddNewSubject: onAddNewSubject,
                      value: subject,
                      items: subjects,
                      onChanged: onSubjectChanged,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _StyledDropdown<String>(
                      cs: cs,
                      theme: theme,
                      label: 'Class',
                      value: classLevel,
                      items: classLevels,
                      onChanged: onClassChanged,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Scheme of Work dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scheme of Work',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: AppTheme.touchTarget,
                    child: DropdownButtonFormField<int>(
                      value: schemeOfWorkLocalId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      hint: Text(
                        'Select scheme…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.outlineVariant,
                        ),
                      ),
                      isExpanded: true,
                      items: [
                        ...schemes.map((s) {
                          final displayTopic = s.adminEditedTopic ?? s.topic;
                          return DropdownMenuItem<int>(
                            value: s.id,
                            child: Text(
                              displayTopic,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                      ],
                      onChanged: (id) {
                        if (id == null) {
                          onSchemeOfWorkSelected(null);
                        } else {
                          final scheme = schemes.where((s) => s.id == id).firstOrNull;
                          if (scheme != null) {
                            onSchemeOfWorkSelected(scheme);
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Topic + Week row
              Row(
                children: [
                  Expanded(
                    child: _StyledTextField(
                      cs: cs,
                      theme: theme,
                      label: 'Topic',
                      controller: topicController,
                      initialValue: null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 80,
                    child: _WeekControl(
                      cs: cs,
                      theme: theme,
                      week: week,
                      onChanged: onWeekChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Generation Parameters Card ───────────────────────────────
        _StitchCard(
          cs: cs,
          theme: theme,
          title: 'Generation Parameters',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Difficulty Segmented
              _SegmentedControl(
                cs: cs,
                theme: theme,
                label: 'Difficulty Level',
                options: ['Easy', 'Medium', 'Hard'],
                value: _capitalize(difficulty),
                onChanged: (v) => onDifficultyChanged(v.toLowerCase()),
              ),
              const SizedBox(height: 20),

              // Bloom's Taxonomy Chips
              _BloomChipsSection(
                cs: cs,
                theme: theme,
                bloomVerbs: bloomVerbs,
                selectedBlooms: selectedBlooms,
                onToggle: onBloomToggled,
              ),
              const SizedBox(height: 20),

              // Assessment Format Segmented
              _SegmentedControl(
                cs: cs,
                theme: theme,
                label: 'Assessment Format',
                options: ['MCQ', 'Theory', 'Both'],
                value: assessmentFormat,
                onChanged: onAssessmentFormatChanged,
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── Generate Button ──────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: AppTheme.touchTarget,
          child: FilledButton.icon(
            onPressed: isGenerating ? null : onGenerate,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
            ),
            icon: isGenerating
                ? AnimatedPressable(
                    onPressed: null,
                    child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.onPrimary,
                    ),
                  )
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              isGenerating ? 'Generating...' : 'Generate with AI',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Preview Column (right side)
// ═══════════════════════════════════════════════════════════════════════
class _PreviewColumn extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool hasGenerated;
  final bool isUnlocked;
  final String objectivesText;
  final String vocabularyText;
  final String materialsText;
  final String presentationText;
  final String assessmentText;
  final String homeworkText;
  final ValueChanged<String> onObjectivesChanged;
  final ValueChanged<String> onVocabularyChanged;
  final ValueChanged<String> onMaterialsChanged;
  final ValueChanged<String> onPresentationChanged;
  final ValueChanged<String> onAssessmentChanged;
  final ValueChanged<String> onHomeworkChanged;
  final VoidCallback onUnlock;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final String lessonStatus;
  final VoidCallback? onToggleComplete;

  const _PreviewColumn({
    required this.cs,
    required this.theme,
    required this.hasGenerated,
    required this.isUnlocked,
    required this.objectivesText,
    required this.vocabularyText,
    required this.materialsText,
    required this.presentationText,
    required this.assessmentText,
    required this.homeworkText,
    required this.onObjectivesChanged,
    required this.onVocabularyChanged,
    required this.onMaterialsChanged,
    required this.onPresentationChanged,
    required this.onAssessmentChanged,
    required this.onHomeworkChanged,
    required this.onUnlock,
    required this.onSave,
    required this.onDiscard,
    this.lessonStatus = 'draft',
    this.onToggleComplete,
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
            // Preview header
            Container(
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
                  Icon(Icons.visibility_rounded, color: cs.primary, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Preview Generated Content',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                        overflow: TextOverflow.clip,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Empty state
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 48,
                      color: cs.outlineVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Configure and generate\na lesson to see preview',
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility_rounded, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Preview Generated Content',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.secondaryFixed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Ready to Save',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.secondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Unlocked banner
          if (isUnlocked)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                    'Unlocked — You can edit and save this lesson',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          // Preview canvas
          if (!isUnlocked) ...[
            // Locked overlay
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
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
                      Icon(Icons.lock_rounded, color: cs.tertiary, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Locked — Preview only',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: cs.tertiary,
                            overflow: TextOverflow.clip,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Objectives: $objectivesText',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Presentation: $presentationText',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        ),
                      ),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Unlock for 1 Credit'),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Preview content cards
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                _buildPreviewCard(
                  'Learning Objectives',
                  objectivesText,
                  readOnly: !isUnlocked,
                  onChanged: onObjectivesChanged,
                ),
                const SizedBox(height: 12),
                _buildPreviewCard(
                  'Key Vocabulary',
                  vocabularyText,
                  readOnly: !isUnlocked,
                  onChanged: onVocabularyChanged,
                ),
                const SizedBox(height: 12),
                _buildPreviewCard(
                  'Materials',
                  materialsText,
                  readOnly: !isUnlocked,
                  onChanged: onMaterialsChanged,
                ),
                const SizedBox(height: 12),
                _buildPreviewCard(
                  'Lesson Presentation',
                  presentationText,
                  readOnly: !isUnlocked,
                  onChanged: onPresentationChanged,
                ),
                const SizedBox(height: 12),
                _buildPreviewCard(
                  'Assessment',
                  assessmentText,
                  readOnly: !isUnlocked,
                  onChanged: onAssessmentChanged,
                ),
                const SizedBox(height: 12),
                _buildPreviewCard(
                  'Homework',
                  homeworkText,
                  readOnly: !isUnlocked,
                  onChanged: onHomeworkChanged,
                ),
              ],
            ),
          ),

          // Action footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
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
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    child: const Text('Discard'),
                  ),
                ),
                if (onToggleComplete != null) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    height: AppTheme.touchTarget,
                    child: FilledButton.tonalIcon(
                      onPressed: onToggleComplete,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      icon: Icon(lessonStatus == 'completed' ? Icons.refresh : Icons.check_circle),
                      label: Text(lessonStatus == 'completed' ? 'Mark Draft' : 'Mark Completed'),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                SizedBox(
                  height: AppTheme.touchTarget,
                  child: FilledButton(
                    onPressed: onSave,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                    ),
                    child: const Text('Save to Vault'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Render markdown heading lines (starting with ##) as bold text.
  /// Other lines are rendered as normal body text with paragraph spacing.
  Widget _renderMarkdownContent(String content) {
    if (content.isEmpty) {
      return Text(
        'No content yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      );
    }

    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('## ')) {
        // Render heading as bold text
        final headingText = trimmed.substring(3).trim();
        widgets.add(Padding(
          padding: EdgeInsets.only(top: i > 0 ? 12.0 : 0, bottom: 4.0),
          child: Text(
            headingText,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ));
      } else if (trimmed.startsWith('#')) {
        // Single # heading
        final headingText = trimmed.substring(1).trim();
        widgets.add(Padding(
          padding: EdgeInsets.only(top: i > 0 ? 12.0 : 0, bottom: 4.0),
          child: Text(
            headingText,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ));
      } else if (trimmed.isEmpty) {
        // Blank line = paragraph break
        widgets.add(const SizedBox(height: 8));
      } else {
        // Normal body text
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 4.0),
          child: Text(
            line,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
            ),
          ),
        ));
      }
    }

    if (widgets.isEmpty) {
      return Text(
        'No content yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPreviewCard(
    String title,
    String content, {
    bool readOnly = false,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceBright,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (readOnly)
            _renderMarkdownContent(content)
          else
            TextFormField(
              initialValue: content,
              maxLines: 6,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                hintText: 'No content yet. Tap Generate first.',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Bottom Navigation Bar (mobile)
// ═══════════════════════════════════════════════════════════════════════
class _BottomNavBar extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  const _BottomNavBar({required this.cs, required this.theme});

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
              currentIndex: 1,
              onTap: (index) {
                final label = _LessonEditorScreenState._bottomNavItems[index].label;
                _navigateTo(context, label);
              },
              items: _LessonEditorScreenState._bottomNavItems.map((item) {
                return BottomNavigationBarItem(
                  icon: item.isActive
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
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

/// Stitch card with rounded-xl border and shadow
class _StitchCard extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String title;
  final Widget child;

  const _StitchCard({
    required this.cs,
    required this.theme,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          child,
        ],
      ),
    );
  }
}

/// Styled dropdown matching Stitch design
class _StyledDropdown<T> extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T> onChanged;
  final VoidCallback? onAddNewSubject;

  const _StyledDropdown({
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
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: AppTheme.touchTarget,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cs.outline),
            color: cs.surfaceBright,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
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
                      item.toString(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                  );
                }),
                DropdownMenuItem<T>(
                  value: '__add_new__' as T,
                  child: const Row(
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

/// Styled text field matching Stitch design
class _StyledTextField extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final TextEditingController? controller;
  final String? initialValue;

  const _StyledTextField({
    required this.cs,
    required this.theme,
    required this.label,
    this.controller,
    this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: AppTheme.touchTarget,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(color: cs.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(color: cs.outline),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: cs.outlineVariant,
              ),
              filled: false,
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Week increment/decrement control
class _WeekControl extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final int week;
  final ValueChanged<int> onChanged;

  const _WeekControl({
    required this.cs,
    required this.theme,
    required this.week,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Week',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: AppTheme.touchTarget,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cs.outline),
            color: cs.surfaceBright,
          ),
          child: Row(
            children: [
              InkWell(
                onTap: week > 1 ? () => onChanged(week - 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.remove_rounded,
                    size: 18,
                    color: week > 1
                        ? cs.onSurfaceVariant
                        : cs.outlineVariant,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    '$week',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: week < 52 ? () => onChanged(week + 1) : null,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: week < 52
                        ? cs.onSurfaceVariant
                        : cs.outlineVariant,
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

/// Segmented control matching Stitch style
class _SegmentedControl extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;

  const _SegmentedControl({
    required this.cs,
    required this.theme,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: AppTheme.touchTarget,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: cs.outline),
            color: cs.surfaceBright,
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: List.generate(options.length * 2 - 1, (index) {
              if (index.isOdd) {
                return Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                );
              }
              final i = index ~/ 2;
              final option = options[i];
              final isSelected = option == value;
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(option),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.secondaryContainer
                          : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLg - 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      option,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// Bloom's Taxonomy multi-select chips
class _BloomChipsSection extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final List<String> bloomVerbs;
  final Set<String> selectedBlooms;
  final ValueChanged<String> onToggle;

  const _BloomChipsSection({
    required this.cs,
    required this.theme,
    required this.bloomVerbs,
    required this.selectedBlooms,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Cognitive Objectives (Bloom\'s)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Text(
              'SELECT MULTIPLE',
              style: TextStyle(
                fontSize: 10,
                color: cs.outline,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: bloomVerbs.map((verb) {
            final selected = selectedBlooms.contains(verb);
            return InkWell(
              onTap: () => onToggle(verb),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(
                    color: selected ? cs.primary : cs.outline,
                  ),
                  color: selected
                      ? cs.primary.withValues(alpha: 0.05)
                      : cs.surfaceBright,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                      ),
                    Text(
                      verb,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
