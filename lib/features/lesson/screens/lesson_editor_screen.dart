import 'dart:convert';
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
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/widgets/upgrade_request_dialog.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show lessonsListProvider;
import 'package:classai/features/lesson/screens/lessons_list_screen.dart'
    show exportLessonPdf;
import 'package:classai/core/services/diagram_service.dart'
    show DiagramService, DiagramRequest, DiagramImage;
import 'package:classai/main.dart' show databaseProvider;

/// Stitch‑designed lesson note editor with AI generation.
///
/// Form fields: Subject dropdown, Class dropdown, Week spinbox,
/// Topic textfield, Difficulty segmented control, Bloom's verbs multi‑select chips,
/// Assessment format segmented control.
/// "Generate with AI" builds a prompt, calls the provided [generateCallback],
/// then populates preview cards with editable text fields per section.
/// "Save" inserts into `lessons` table.
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
  final _undoController = UndoHistoryController();
  final _objectivesController = TextEditingController();
  final _vocabularyController = TextEditingController();
  final _materialsController = TextEditingController();
  final _presentationController = TextEditingController();
  final _assessmentController = TextEditingController();
  final _homeworkController = TextEditingController();
  int? _lessonId;
  String _lessonStatus = 'draft';
  int _week = 1;
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  String _assessmentFormat = 'Both';
  final Set<String> _selectedBlooms = {};
  bool _includeDiagrams = false;
  List<Map<String, dynamic>> _diagramResults = [];
  bool _isGeneratingDiagrams = false;
  bool _isGenerating = false;
  bool _isRegenerating = false;
  bool _hasGenerated = false;
  bool _configExpanded = false;
  int _previewRevision = 0;
  final _reviewController = TextEditingController();
  bool _isUnlocked = false;
  bool _isOnline = true;
  bool _isExporting = false;
  bool _editorSidebarOpen = false;
  bool _sidebarInitialized = false;
  int _creditBalance = 0;
  int _remainingDailyPreviews = 10;
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
  bool _isManualTopicEntry = true;
  bool _sourceMissing = false;

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
    _checkConnectivity();
    // Sync preview controllers → state variables so onChanged behavior is preserved
    _objectivesController.addListener(() {
      setState(() => _objectivesText = _objectivesController.text);
    });
    _vocabularyController.addListener(() {
      setState(() => _vocabularyText = _vocabularyController.text);
    });
    _materialsController.addListener(() {
      setState(() => _materialsText = _materialsController.text);
    });
    _presentationController.addListener(() {
      setState(() => _presentationText = _presentationController.text);
    });
    _assessmentController.addListener(() {
      setState(() => _assessmentText = _assessmentController.text);
    });
    _homeworkController.addListener(() {
      setState(() => _homeworkText = _homeworkController.text);
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
  }

  Future<void> _checkConnectivity() async {
    final online = await PlatformHelper.isOnline();
    if (mounted) setState(() => _isOnline = online);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithEmergencyFlush();
      _loadCreditBalance();
      _loadDailyPreviewData();
      _loadAuthInfo();
      _loadSubjects();
      _loadSchemesForContext();
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

  Future<void> _loadLesson(int id) async {
    try {
      final db = ref.read(databaseProvider);
      final lesson = await db.lessonsDao.getById(id);
      if (lesson != null && mounted) {
        bool sourceMissing = false;
        if (lesson.schemeOfWorkId != null) {
          final schemeId = int.tryParse(lesson.schemeOfWorkId!);
          if (schemeId != null) {
            sourceMissing = await db.schemeOfWorkDao.getById(schemeId) == null;
          } else {
            sourceMissing = true;
          }
        }
        final rawContent = lesson.content;
        Map<String, dynamic>? parsedContent;
        try {
          final decoded = jsonDecode(rawContent);
          if (decoded is Map<String, dynamic>) {
            parsedContent = decoded;
          }
        } catch (_) {
          // Keep the saved content as-is if it is encrypted or not JSON.
        }
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
          _sourceMissing = sourceMissing;
          _isUnlocked = lesson.isUnlocked;
          _encryptedContent = rawContent;
          if (parsedContent != null) {
            _objectivesText = _formatList(parsedContent['objectives']);
            _objectivesController.text = _objectivesText;
            _vocabularyText = _formatList(parsedContent['vocabulary']);
            _vocabularyController.text = _vocabularyText;
            _materialsText = _formatList(parsedContent['materials']);
            _materialsController.text = _materialsText;
            _presentationText = _formatJson(parsedContent['presentation']);
            _presentationController.text = _presentationText;
            _assessmentText = parsedContent['assessment'] as String? ?? '';
            _assessmentController.text = _assessmentText;
            _homeworkText = parsedContent['homework'] as String? ?? '';
            _homeworkController.text = _homeworkText;
            _hasGenerated = true;
            // Restore diagram results if present in stored content
            final storedDiagrams = parsedContent['diagrams'] as List<dynamic>?;
            if (storedDiagrams != null && storedDiagrams.isNotEmpty) {
              _diagramResults = storedDiagrams
                  .map((d) => d as Map<String, dynamic>)
                  .toList();
            }
          }
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
      await _refreshSourceMissing();
    } catch (_) {}
  }

  Future<void> _loadDailyPreviewData() async {
    try {
      final db = ref.read(databaseProvider);
      final config = await db.securityConfigDao.get();
      final today = DateTime.now().toIso8601String().split('T').first;
      final currentCount = config.dailyPreviewCount;
      final currentDate = config.dailyPreviewDate ?? '';
      int count = currentCount;
      if (currentDate != today) {
        count = 0;
      }
      const limits = {'free': 10, 'basic': 10, 'standard': 10, 'elite': -1};
      final limit = limits[_subscriptionTier] ?? 10;
      final remaining = limit < 0 ? -1 : (limit - count).clamp(0, limit);
      if (mounted) {
        setState(() => _remainingDailyPreviews = remaining);
      }
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

  Future<String?> _resolveGenerationTermLabel(AppDatabase db) async {
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

  Future<String?> _resolveLessonTermLabel(
    AppDatabase db,
    Lesson lesson,
    int schoolLocalId,
  ) async {
    try {
      final schemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
      if (schemeId != null) {
        final scheme = await db.schemeOfWorkDao.getById(schemeId);
        final schemeTerm = scheme?.term.trim();
        if (schemeTerm != null && schemeTerm.isNotEmpty) {
          return _normalizeTermLabel(schemeTerm);
        }
      }

      final lessonTerm = await db.termsDao.getTermForDate(
        schoolLocalId,
        lesson.createdAt,
      );
      final termName = lessonTerm?.name.trim();
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

  Future<bool> _hasDuplicateLessonForGeneration(AppDatabase db) async {
    try {
      final teacherServerId = _teacherId;
      if (teacherServerId == null || teacherServerId.isEmpty) return false;

      final schoolLocalId =
          ref.read(authProvider).currentSchool?.localId ??
              (await db.schoolsDao.get())?.localId;
      if (schoolLocalId == null) return false;

      final targetTerm = await _resolveGenerationTermLabel(db);
      if (targetTerm == null || targetTerm.isEmpty) return false;

      final lessons = await db.lessonsDao.getAll();
      for (final lesson in lessons) {
        if (_lessonId != null && lesson.id == _lessonId) continue;
        if (lesson.teacherServerId != teacherServerId) continue;
        if (lesson.subject != _subject || lesson.week != _week) continue;

        final lessonTerm =
            await _resolveLessonTermLabel(db, lesson, schoolLocalId);
        if (lessonTerm == null || lessonTerm.isEmpty) continue;
        if (_normalizeTermLabel(lessonTerm) == targetTerm) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _showCenteredToast({
    required BuildContext context,
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.tertiary.withValues(alpha: 0.4),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.onSurface.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: tt.bodyMedium?.copyWith(
                color: cs.onTertiaryContainer,
                fontWeight: FontWeight.w500,
              ) ?? const TextStyle(),
              child: Text(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () {
      entry.remove();
    });
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
        return 10;
      case 'basic':
        return 20;
      case 'standard':
        return 50;
      case 'elite':
        return -1;
      default:
        return 10;
    }
  }

  Future<void> _handleGenerate() async {
    if (!_formKey.currentState!.validate()) return;

    final topic = _topicController.text.trim();
    if (_isManualTopicEntry && topic.isEmpty) {
      showErrorToast(
        context: context,
        message: 'Please enter a topic before generating.',
      );
      return;
    }

    final authTier =
        (ref.read(authProvider).currentSchool?.subscriptionTier ?? _subscriptionTier).toLowerCase();
    if (authTier == 'free') {
      await _showUpgradeRequiredDialog();
      return;
    }

    if (!await PlatformHelper.isOnline()) {
      showErrorToast(
        context: context,
        message: 'Generation requires internet — try again when connected.',
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final db = ref.read(databaseProvider);

      // Build prompt with teacher/school attribution
      final bloomsStr =
          _selectedBlooms.isEmpty ? 'All levels' : _selectedBlooms.join(', ');
      final prompt = PromptTemplates.lessonNote(
        _subject,
        'NERDC',
        _classLevel,
        _week,
        topic,
        _difficulty,
        bloomsStr,
        teacherName: _teacherName,
        schoolName: _schoolName,
      );

      if (await _hasDuplicateLessonForGeneration(db)) {
        if (mounted) {
          _showCenteredToast(
            context: context,
            message:
                'A lesson already exists for this week. Edit the existing one instead.',
          );
        }
        return;
      }

      // Generate via callback or fallback to AiService
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      Map<String, dynamic> result;
      if (widget.generateCallback != null) {
        // Test / external callback path – skip AiService setup
        result = await widget.generateCallback!(prompt);
        // Increment preview counter only after successful test generation
        await db.securityConfigDao
            .checkAndIncrementDailyPreviews(tier: _subscriptionTier);
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

        // Increment preview counter only after successful generation
        await db.securityConfigDao
            .checkAndIncrementDailyPreviews(tier: _subscriptionTier);

        // Audit log the generation
        await aiService.logGeneration(
          teacherId: _teacherId,
          schoolId: _schoolId,
          topic: topic,
        );
      }

      // Parse the generated JSON — defer setState to its own event loop
      // iteration to avoid layout/paint assertion errors during the
      // warm-up frame that Flutter schedules when setState is called
      // from an async continuation.
      final parsedRaw = result['raw'] as Map<String, dynamic>? ?? result;
      final parsedEncrypted = result['encryptedContent'] as String?;

      await _saveLesson(notify: false);

      // ── Generate diagrams (Elite only) ──────────────────────────
      List<Map<String, dynamic>> generatedDiagrams = [];
      if (_includeDiagrams && _subscriptionTier.toLowerCase() == 'elite') {
        final diagramsRaw = parsedRaw['diagrams'] as List<dynamic>?;
        if (diagramsRaw != null && diagramsRaw.isNotEmpty) {
          final requests = diagramsRaw
              .map((d) => DiagramRequest(
                    description: (d as Map<String, dynamic>)['description']
                            as String? ??
                        'Diagram',
                  ))
              .toList();
          try {
            final diagramService = DiagramService();
            final lessonIdStr = _lessonId?.toString();
            final results = await diagramService.generateDiagrams(
              requests,
              lessonId: lessonIdStr ?? 'new_${DateTime.now().millisecondsSinceEpoch}',
            );
            generatedDiagrams = results
                .map((r) => <String, dynamic>{
                      'index': r.index,
                      'description': r.description,
                      'imageUrl': r.imageUrl,
                      'error': r.error,
                    })
                .toList();
          } catch (e) {
            debugPrint('[LessonEditor] Diagram generation failed: $e');
          }
        }
      }

      if (mounted) {
        // Schedule a normal vsync frame instead of calling setState directly.
        // Calling setState from an async continuation triggers
        // scheduleWarmUpFrame(), which uses Timer.run internally. On desktop,
        // this Timer can fire during the engine's onBeginFrame where
        // _debugDuringDeviceUpdate is still true, causing the mouse_tracker
        // assertion error. By scheduling a real vsync frame and deferring all
        // state changes to the post-frame callback, no setState runs from an
        // async continuation and no warm-up frame is triggered.
        WidgetsBinding.instance.scheduleFrame();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _encryptedContent = parsedEncrypted;
            _objectivesText = _formatList(parsedRaw['objectives']);
            _objectivesController.text = _objectivesText;
            _vocabularyText = _formatList(parsedRaw['vocabulary']);
            _vocabularyController.text = _vocabularyText;
            _materialsText = _formatList(parsedRaw['materials']);
            _materialsController.text = _materialsText;
            _presentationText = _formatJson(parsedRaw['presentation']);
            _presentationController.text = _presentationText;
            _assessmentText = parsedRaw['assessment'] as String? ?? '';
            _assessmentController.text = _assessmentText;
            _homeworkText = parsedRaw['homework'] as String? ?? '';
            _homeworkController.text = _homeworkText;
            _diagramResults = generatedDiagrams;
            _hasGenerated = true;
            _configExpanded = false;
            _isUnlocked = false;
            _isGenerating = false;
            _previewRevision++;
          });
          if (mounted) {
            showInfoToast(
                context: context, message: 'Lesson generated successfully!');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        showErrorToast(context: context, message: 'Generation failed: $e');
      }
    }
  }

  Future<void> _handleRegenerateDiagram(int diagramIndex) async {
    final currentTier = (ref.read(authProvider).currentSchool?.subscriptionTier ?? _subscriptionTier).toLowerCase();
    if (currentTier != 'elite') {
      if (mounted) {
        showErrorToast(context: context, message: 'Diagram generation requires Elite subscription');
      }
      return;
    }
    setState(() => _isGeneratingDiagrams = true);
    try {
      // Find the diagram description from current results
      final diagram = _diagramResults.length > diagramIndex ? _diagramResults[diagramIndex] : null;
      if (diagram == null) return;
      final description = diagram['description'] as String? ?? 'Diagram';
      final oldUrl = diagram['imageUrl'] as String?;
      final requests = [DiagramRequest(description: description)];
      final diagramService = DiagramService();
      final lessonIdStr = _lessonId?.toString();
      final results = await diagramService.generateDiagrams(
        requests,
        lessonId: lessonIdStr ?? 'regenerate_${DateTime.now().millisecondsSinceEpoch}',
        oldUrl: oldUrl,
      );
      if (results.isNotEmpty && mounted) {
        setState(() {
          _diagramResults[diagramIndex] = <String, dynamic>{
            'index': results[0].index,
            'description': results[0].description,
            'imageUrl': results[0].imageUrl,
            'error': results[0].error,
          };
          _isGeneratingDiagrams = false;
        });
      }
    } catch (e) {
      debugPrint('[LessonEditor] Diagram regeneration failed: $e');
      if (mounted) {
        setState(() => _isGeneratingDiagrams = false);
      }
    }
  }

  Future<void> _handleRegenerate() async {
    setState(() => _isRegenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final aiService = AiService(db: db);
      final topic = _topicController.text.trim();
      final review = _reviewController.text.trim();

      // Build the original lesson prompt
      final bloomsStr =
          _selectedBlooms.isEmpty ? 'All levels' : _selectedBlooms.join(', ');
      final basePrompt = PromptTemplates.lessonNote(
        _subject,
        'NERDC',
        _classLevel,
        _week,
        topic,
        _difficulty,
        bloomsStr,
        teacherName: _teacherName,
        schoolName: _schoolName,
      );

      // Append teacher review feedback
      final regeneratedPrompt = review.isEmpty
          ? basePrompt
          : '$basePrompt\n\nTeacher feedback: $review';

      // Generate via callback or fallback to AiService
      Map<String, dynamic> result;
      if (widget.generateCallback != null) {
        result = await widget.generateCallback!(regeneratedPrompt);
      } else {
        result = await aiService.generate(regeneratedPrompt);
      }

      // Parse the generated JSON
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      // Defer ALL setState to a normal vsync frame to avoid scheduleWarmUpFrame
      // and the mouse_tracker assertion during device update.
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _encryptedContent = result['encryptedContent'] as String?;
        _objectivesText = _formatList(raw['objectives']);
        _objectivesController.text = _objectivesText;
        _vocabularyText = _formatList(raw['vocabulary']);
        _vocabularyController.text = _vocabularyText;
        _materialsText = _formatList(raw['materials']);
        _materialsController.text = _materialsText;
        _presentationText = _formatJson(raw['presentation']);
        _presentationController.text = _presentationText;
        _assessmentText = raw['assessment'] as String? ?? '';
        _assessmentController.text = _assessmentText;
        _homeworkText = raw['homework'] as String? ?? '';
        _homeworkController.text = _homeworkText;
        _hasGenerated = true;
        _configExpanded = false;
        _isRegenerating = false;
        _previewRevision++;
      });
      });

      await _saveLesson(notify: false);
      _reviewController.clear();

      if (mounted) {
        showInfoToast(
            context: context, message: 'Lesson regenerated successfully!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        showErrorToast(context: context, message: 'Regeneration failed: $e');
      }
    }
  }

  Future<void> _handleUnlock() async {
    final isOnline = await PlatformHelper.isOnline();

    if (!isOnline && _creditBalance < 1) {
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
        if (!isOnline) {
          _creditBalance = _creditBalance - 1;
        }
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
        if (_diagramResults.isNotEmpty) 'diagrams': _diagramResults,
      };
      final topic = _topicController.text.trim();

      final db = ref.read(databaseProvider);

      // Resolve the term label for this lesson
      final termLabel = await _resolveGenerationTermLabel(db);

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
        weekNumber: Value(_week),
        term: termLabel != null ? Value(termLabel) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      int id;

      // Dedup: check for existing lesson with same topic/subject/week/teacher/school
      if (_teacherId != null && _schoolId != null) {
        final existing = await db.lessonsDao.findByTopicSubjectWeekTeacher(
          topic: topic,
          subject: _subject,
          week: _week,
          teacherServerId: _teacherId!,
          schoolServerId: _schoolId!,
        );
        if (existing != null) {
          // Update existing lesson
          id = existing.id;
          await db.lessonsDao.updateLesson(id, companion);

          // Queue UPDATE sync entry
          final lessonContent = _encryptedContent ?? jsonEncode(content);
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
              'content': lessonContent,
              'is_unlocked': _isUnlocked,
              'status': _lessonStatus,
              if (schemeOfWorkIdStr != null) 'scheme_of_work_id': schemeOfWorkIdStr,
              'week_number': _week,
              if (termLabel != null) 'term': termLabel,
            },
          );

          if (notify && mounted) {
            ref.invalidate(lessonsListProvider);
            showInfoToast(context: context, message: 'Lesson updated (id=$id)');
          }
          return;
        }
      }

      // Check storage limit before inserting new lesson
      final configService = ref.read(configServiceProvider);
      final storageLimits = configService.lessonStorageLimits;
      final limit = storageLimits[_subscriptionTier] as int? ?? _defaultStorageLimit(_subscriptionTier);
      if (limit >= 0) {
        final currentCount = await db.lessonsDao.countNonDeletedBySchool(_schoolId ?? '');
        if (currentCount >= limit) {
          if (notify && mounted) {
            _showCenteredToast(context: context, message: 'Storage limit reached');
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
          weekNumber: Value(_week),
          term: termLabel != null ? Value(termLabel) : const Value.absent(),
        ),
      );

      // Queue sync entry
      final lessonContent = _encryptedContent ?? jsonEncode(content);
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
          'content': lessonContent,
          'content_hash': lessonContent.hashCode.toString(),
          'is_unlocked': _isUnlocked,
          'status': _lessonStatus,
          if (schemeOfWorkIdStr != null) 'scheme_of_work_id': schemeOfWorkIdStr,
          'week_number': _week,
          if (termLabel != null) 'term': termLabel,
        },
      );

      ref.invalidate(lessonsListProvider);
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
      // _schoolId is guaranteed non-null by the guard above, and holds the
      // authenticated account's school serverId — use it to look up the
      // correct school row (not schoolsDao.get(), which uses limit(1) with no
      // serverId filter and may return the wrong school).
      final school = await db.schoolsDao.getByServerId(_schoolId!);
      // Resolve teacher's localId from the String serverId
      final teacher = await db.teachersDao.findByServerId(_teacherId!);
      final teacherLocalId = teacher?.localId ?? 0;
      final logId = await db.progressLogsDao.insert(
        ProgressLogsCompanion.insert(
          eventType: newStatus == 'completed' ? 'lesson_completed' : 'lesson_reopened',
          lessonId: Value(_lessonId!),
          teacherId: Value(teacherLocalId),
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

  Future<void> _handleMarkCompleted() async {
    if (_lessonId == null || _schoolId == null || _teacherId == null) return;
    try {
      final db = ref.read(databaseProvider);
      await db.lessonsDao.updateStatus(_lessonId!, 'completed');
      // _schoolId is guaranteed non-null by the guard, holds the serverId.
      final school = await db.schoolsDao.getByServerId(_schoolId!);
      final teacher = await db.teachersDao.findByServerId(_teacherId!);
      final teacherLocalId = teacher?.localId ?? 0;
      final logId = await db.progressLogsDao.insert(
        ProgressLogsCompanion.insert(
          eventType: 'lesson_completed',
          lessonId: Value(_lessonId!),
          teacherId: Value(teacherLocalId),
          schoolId: Value(school?.localId ?? 0),
        ),
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': 'lesson_completed',
          'lesson_id': _lessonId,
          'teacher_id': _teacherId,
          'school_id': _schoolId,
        },
      );
      setState(() => _lessonStatus = 'completed');
      await _saveLesson(notify: false);
      if (mounted) {
        _showCenteredToast(context: context, message: 'Lesson marked as completed.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Failed to mark lesson as completed: $e');
      }
    }
  }

  Future<void> _handleExportPdf() async {
    if (_lessonId == null) {
      if (mounted) {
        showErrorToast(context: context, message: 'Save the lesson before exporting.');
      }
      return;
    }

    setState(() => _isExporting = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school =
          authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) {
        if (mounted) {
          showErrorToast(context: context, message: 'School data not available.');
        }
        return;
      }

      // Load the saved lesson from the database
      final lesson = await db.lessonsDao.getById(_lessonId!);
      if (lesson == null) {
        if (mounted) {
          showErrorToast(context: context, message: 'Lesson not found in database.');
        }
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
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _onSchemeOfWorkSelected(SchemeOfWorkData? scheme) {
    if (scheme == null) {
      setState(() {
        _schemeOfWorkLocalId = null;
        _isFromSchemeOfWork = false;
        _isManualTopicEntry = true;
      });
      return;
    }
    final displayTopic = scheme.adminEditedTopic ?? scheme.topic;
    setState(() {
      _schemeOfWorkLocalId = scheme.id;
      _isFromSchemeOfWork = true;
      _isManualTopicEntry = false;
      _sourceMissing = false;
      _week = scheme.weekNumber;
      _topicController.text = displayTopic;
    });
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

  Future<void> _refreshSourceMissing() async {
    if (_schemeOfWorkLocalId == null) return;
    try {
      final db = ref.read(databaseProvider);
      final exists = await db.schemeOfWorkDao.getById(_schemeOfWorkLocalId!) != null;
      if (mounted) {
        setState(() => _sourceMissing = !exists);
      }
    } catch (_) {}
  }

  void _onManualTopicSelected() {
    setState(() {
      _isManualTopicEntry = true;
      _isFromSchemeOfWork = false;
      _schemeOfWorkLocalId = null;
      _sourceMissing = false;
    });
  }

  void _discard() {
    setState(() {
      _topicController.clear();
      _reviewController.clear();
      _objectivesController.clear();
      _vocabularyController.clear();
      _materialsController.clear();
      _presentationController.clear();
      _assessmentController.clear();
      _homeworkController.clear();
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
      _isManualTopicEntry = true;
    });
  }

  Widget _buildConfigArea({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final summary = '$_subject · $_classLevel · Week $_week';
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
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Generation Parameters',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      if (!_configExpanded && summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
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
              ? Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: child,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _topicController.dispose();
    _reviewController.dispose();
    _objectivesController.dispose();
    _vocabularyController.dispose();
    _materialsController.dispose();
    _presentationController.dispose();
    _assessmentController.dispose();
    _homeworkController.dispose();
    _undoController.dispose();
    super.dispose();
  }

  // ── Nav item data class ──────────────────────────────────────────────
  static const _navItems = [
    _NavItem('Home', Icons.home_rounded, false),
    _NavItem('Lessons', Icons.menu_book_rounded, true),
    _NavItem('Exams', Icons.quiz_rounded, false),
    // _NavItem('Vault', Icons.inventory_2_rounded, false), // Vault feature disabled
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
          // ── Navigation Drawer (tablet+) ─────────────────────────
          _NavigationDrawer(
            cs: cs,
            theme: theme,
            isOpen: _editorSidebarOpen,
            onToggleSidebar: () => setState(
                () => _editorSidebarOpen = !_editorSidebarOpen),
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
                  undoController: _undoController,
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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Tool Header Area ────────────────────
                            _ToolHeader(
                              cs: cs,
                              theme: theme,
                              onToggleSidebar: () => setState(
                                  () => _editorSidebarOpen = !_editorSidebarOpen),
                              sidebarOpen: _editorSidebarOpen,
                              undoController: _undoController,
                            ),
                            if (_schemeOfWorkLocalId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                                child: _LinkedSchemeBanner(
                                  schemeId: _schemeOfWorkLocalId!,
                                  classLevel: _classLevel,
                                  isSourceMissing: _sourceMissing,
                                  cs: cs,
                                  theme: theme,
                                ),
                              ),

                            // ── Two-column layout ───────────────────
                            if (_sourceMissing)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: cs.errorContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'The source scheme for this lesson no longer exists. '
                                    'You can still edit the lesson, but the original scheme link is missing.',
                                    style: TextStyle(color: cs.onErrorContainer),
                                  ),
                                ),
                              ),
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
                                            child: _buildConfigArea(
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
                                                      _loadSchemesForContext();
                                                    },
                                                    onClassChanged: (v) {
                                                      setState(() => _classLevel = v);
                                                      _loadSchemesForContext();
                                                    },
                                                    onWeekChanged: (v) => setState(() => _week = v),
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
                                                    isManualTopicEntry: _isManualTopicEntry,
                                                    onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                                    onManualTopicSelected: _onManualTopicSelected,
                                                    subscriptionTier: _subscriptionTier,
                                                    includeDiagrams: _includeDiagrams,
                                                    onIncludeDiagramsChanged: (v) => setState(() => _includeDiagrams = v),
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          // Right column: preview
                                          Expanded(
                                            child: _PreviewColumn(
                                              key: ValueKey(_previewRevision),
                                              cs: cs,
                                              theme: theme,
                                              hasGenerated: _hasGenerated,
                                              isUnlocked: _isUnlocked,
                                              isOnline: _isOnline,
                                              subscriptionTier: _subscriptionTier,
                                              remainingDailyPreviews: _remainingDailyPreviews,
                                              isRegenerating: _isRegenerating,
                                              diagramResults: _diagramResults,
                                              isGeneratingDiagrams: _isGeneratingDiagrams,
                                              onRegenerateDiagram: _handleRegenerateDiagram,
                                              objectivesController: _objectivesController,
                                              vocabularyController: _vocabularyController,
                                              materialsController: _materialsController,
                                              presentationController: _presentationController,
                                              assessmentController: _assessmentController,
                                              homeworkController: _homeworkController,
                                              reviewController: _reviewController,
                                              undoController: _undoController,
                                              onUnlock: _handleUnlock,
                                              onSave: _saveLesson,
                                              onDiscard: _discard,
                                              onRegenerate: _isUnlocked ? _handleRegenerate : null,
                                              lessonStatus: _lessonStatus,
                                              onMarkCompleted: _isUnlocked ? _handleMarkCompleted : null,
                                              onToggleComplete: _isUnlocked ? _handleToggleComplete : null,
                                              onExportPdf: _hasGenerated ? _handleExportPdf : null,
                                              isExporting: _isExporting,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          _buildConfigArea(
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
                                                _loadSchemesForContext();
                                              },
                                              onClassChanged: (v) {
                                                setState(() => _classLevel = v);
                                                _loadSchemesForContext();
                                              },
                                              onWeekChanged: (v) => setState(() => _week = v),
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
                                              isManualTopicEntry: _isManualTopicEntry,
                                              onSchemeOfWorkSelected: _onSchemeOfWorkSelected,
                                              onManualTopicSelected: _onManualTopicSelected,
                                              subscriptionTier: _subscriptionTier,
                                              includeDiagrams: _includeDiagrams,
                                              onIncludeDiagramsChanged: (v) => setState(() => _includeDiagrams = v),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          _PreviewColumn(
                                            key: ValueKey(_previewRevision),
                                            cs: cs,
                                            theme: theme,
                                            hasGenerated: _hasGenerated,
                                            isUnlocked: _isUnlocked,
                                            isOnline: _isOnline,
                                            subscriptionTier: _subscriptionTier,
                                            remainingDailyPreviews: _remainingDailyPreviews,
                                            isRegenerating: _isRegenerating,
                                            diagramResults: _diagramResults,
                                            isGeneratingDiagrams: _isGeneratingDiagrams,
                                            onRegenerateDiagram: _handleRegenerateDiagram,
                                            objectivesController: _objectivesController,
                                            vocabularyController: _vocabularyController,
                                            materialsController: _materialsController,
                                            presentationController: _presentationController,
                                            assessmentController: _assessmentController,
                                            homeworkController: _homeworkController,
                                            reviewController: _reviewController,
                                            undoController: _undoController,
                                            onUnlock: _handleUnlock,
                                            onSave: _saveLesson,
                                            onDiscard: _discard,
                                            onRegenerate: _isUnlocked ? _handleRegenerate : null,
                                            lessonStatus: _lessonStatus,
                                            onMarkCompleted: _isUnlocked ? _handleMarkCompleted : null,
                                            onExportPdf: _hasGenerated ? _handleExportPdf : null,
                                            isExporting: _isExporting,
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
  final VoidCallback? onToggleSidebar;
  const _NavigationDrawer({
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
              SizedBox(height: isOpen ? 24 : 16),
              // Logo area — tapping toggles sidebar
              InkWell(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                onTap: onToggleSidebar,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isOpen ? 24 : 12,
                  ),
                  child: isOpen
                      ? Column(
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
                        )
                      : Center(
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
                              Icons.menu_rounded,
                              color: cs.onPrimaryContainer,
                              size: 22,
                            ),
                          ),
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
        _goToLessonsDeferred(context);
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

  void _goToLessonsDeferred(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      context.go('/lessons');
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mobile Header
// ═══════════════════════════════════════════════════════════════════════
class _MobileHeader extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final int creditBalance;
  final UndoHistoryController undoController;
  const _MobileHeader({
    required this.cs,
    required this.theme,
    required this.creditBalance,
    required this.undoController,
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
              if (Navigator.of(context).canPop())
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  style: IconButton.styleFrom(
                    foregroundColor: cs.onSurfaceVariant,
                  ),
                ),
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
              const SizedBox(width: 4),
              RepaintBoundary(
                child: Text(
                  '$creditBalance',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
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
  final UndoHistoryController undoController;
  const _ToolHeader({
    required this.cs,
    required this.theme,
    this.onToggleSidebar,
    required this.sidebarOpen,
    required this.undoController,
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
              // Back button (when navigable)
              if (Navigator.of(context).canPop())
                InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back_rounded,
                          size: 20,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
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

/// Data holder for a loaded scheme together with its resolved subject name.
class _SchemeDisplayData {
  final String subjectName;
  final SchemeOfWorkData scheme;
  const _SchemeDisplayData({required this.subjectName, required this.scheme});
}

class _LinkedSchemeBanner extends ConsumerWidget {
  const _LinkedSchemeBanner({
    required this.schemeId,
    required this.classLevel,
    required this.isSourceMissing,
    required this.cs,
    required this.theme,
  });

  final int schemeId;
  final String classLevel;
  final bool isSourceMissing;
  final ColorScheme cs;
  final ThemeData theme;

  Future<_SchemeDisplayData?> _loadScheme(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final scheme = await db.schemeOfWorkDao.getById(schemeId);
    if (scheme == null) return null;

    // Resolve subject name from the subjects table
    final allSubjects = await db.subjectsDao.getAll();
    final subject = allSubjects.where((s) => s.id == scheme.subjectId).firstOrNull;
    final subjectName = subject?.name ?? 'Subject ${scheme.subjectId}';
    return _SchemeDisplayData(subjectName: subjectName, scheme: scheme);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<_SchemeDisplayData?>(
      future: _loadScheme(ref),
      builder: (context, snapshot) {
        final display = snapshot.data;
        if (display == null) {
          if (!isSourceMissing) return const SizedBox.shrink();
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'The linked scheme of work is no longer available. You can still edit this lesson.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          );
        }

        final scheme = display.scheme;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
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
                'Subject: ${display.subjectName} • Class: $classLevel • Week ${scheme.weekNumber} • Topic: ${scheme.topic}',
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
  final String subscriptionTier;
  final bool includeDiagrams;
  final ValueChanged<bool>? onIncludeDiagramsChanged;
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
  final bool isManualTopicEntry;
  final ValueChanged<SchemeOfWorkData?> onSchemeOfWorkSelected;
  final VoidCallback onManualTopicSelected;

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
    required this.isManualTopicEntry,
    required this.onSchemeOfWorkSelected,
    required this.onManualTopicSelected,
    required this.subscriptionTier,
    required this.includeDiagrams,
    this.onIncludeDiagramsChanged,
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
              // Topics dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Topics',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: AppTheme.touchTarget,
                    child: DropdownButtonFormField<String>(
                      initialValue: isManualTopicEntry
                          ? '__manual__'
                          : schemeOfWorkLocalId?.toString(),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      hint: Text(
                        schemes.isEmpty ? 'No approved scheme of work' : 'Select topic…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.outlineVariant,
                        ),
                      ),
                      isExpanded: true,
                      items: [
                        DropdownMenuItem<String>(
                          value: '__manual__',
                          child: Text(
                            '✏️ Write a new topic',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        ...schemes.map((s) {
                          final displayTopic = s.adminEditedTopic ?? s.topic;
                          return DropdownMenuItem<String>(
                            value: s.id.toString(),
                            child: Text(
                              'Week ${s.weekNumber}: $displayTopic',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }),
                        if (schemes.isEmpty)
                          DropdownMenuItem<String>(
                            value: '__empty__',
                            enabled: false,
                            child: Text(
                              'No approved scheme of work',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.outlineVariant,
                              ),
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null || id == '__manual__' || id == '__empty__') {
                          onManualTopicSelected();
                          return;
                        }
                        final scheme = schemes.where((s) => s.id.toString() == id).firstOrNull;
                        if (scheme != null) {
                          onSchemeOfWorkSelected(scheme);
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
                      readOnly: !isManualTopicEntry,
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 80,
                    child: _WeekControl(
                      cs: cs,
                      theme: theme,
                      week: week,
                      onChanged: isManualTopicEntry ? onWeekChanged : (_) {},
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
              // ── Include Diagrams (Elite only) ────────────────
              if (subscriptionTier.toLowerCase() == 'elite') ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    'Include diagrams',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Generate AI illustrations for this lesson',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  value: includeDiagrams,
                  onChanged: (v) {
                    if (v != null && onIncludeDiagramsChanged != null) {
                      onIncludeDiagramsChanged!(v);
                    }
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
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
                ? SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: cs.onPrimary,
                    ),
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
  final bool isOnline;
  final String subscriptionTier;
  final int remainingDailyPreviews;
  final bool isRegenerating;
  final List<Map<String, dynamic>> diagramResults;
  final bool isGeneratingDiagrams;
  final ValueChanged<int>? onRegenerateDiagram;
  final TextEditingController objectivesController;
  final TextEditingController vocabularyController;
  final TextEditingController materialsController;
  final TextEditingController presentationController;
  final TextEditingController assessmentController;
  final TextEditingController homeworkController;
  final TextEditingController? reviewController;
  final UndoHistoryController undoController;
  final VoidCallback onUnlock;
  final VoidCallback onSave;
  final VoidCallback? onMarkCompleted;
  final VoidCallback onDiscard;
  final VoidCallback? onRegenerate;
  final String lessonStatus;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onExportPdf;
  final bool isExporting;

  const _PreviewColumn({
    super.key,
    required this.cs,
    required this.theme,
    required this.hasGenerated,
    required this.isUnlocked,
    required this.isOnline,
    required this.subscriptionTier,
    this.remainingDailyPreviews = 10,
    this.isRegenerating = false,
    this.diagramResults = const [],
    this.isGeneratingDiagrams = false,
    this.onRegenerateDiagram,
    required this.objectivesController,
    required this.vocabularyController,
    required this.materialsController,
    required this.presentationController,
    required this.assessmentController,
    required this.homeworkController,
    this.reviewController,
    required this.undoController,
    required this.onUnlock,
    required this.onSave,
    this.onMarkCompleted,
    required this.onDiscard,
    this.onRegenerate,
    this.lessonStatus = 'draft',
    this.onToggleComplete,
    this.onExportPdf,
    this.isExporting = false,
  });

  @override
  Widget build(BuildContext context) {
    // Empty state (before generation)
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            // Empty body
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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

    // Generated state (after generation, with ValueKey forcing clean mount)
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
          // ── Locked overlay (generated but not yet unlocked) ─────
          if (hasGenerated && !isUnlocked)
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
                      'Review the generated lesson content below. '
                      'Unlock to edit, save, or regenerate.',
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

          // ── Locked preview (brief draft preview) ───────────────
          if (hasGenerated && !isUnlocked)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLockedPreviewCard('Objectives', objectivesController.text),
                  const SizedBox(height: 12),
                  _buildLockedPreviewCard('Presentation', presentationController.text),
                ],
              ),
            ),

          // ── Unlocked banner ─────────────────────────────────────
          if (hasGenerated && isUnlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unlocked — You can edit and save this lesson',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Preview Cards (unlocked only) ─────────────────────
          if (hasGenerated && isUnlocked)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPreviewCard('Objectives', objectivesController,
                    readOnly: !isUnlocked,
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard('Vocabulary', vocabularyController,
                    readOnly: !isUnlocked,
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard('Materials', materialsController,
                    readOnly: !isUnlocked,
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard('Presentation', presentationController,
                    readOnly: !isUnlocked,
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard('Assessment', assessmentController,
                    readOnly: !isUnlocked,
                  ),
                  const SizedBox(height: 12),
                  _buildPreviewCard('Homework', homeworkController,
                    readOnly: !isUnlocked,
                  ),

                  // ── Diagram Previews ─────────────────────────────
                  if (diagramResults.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Diagrams',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    ...diagramResults.asMap().entries.map((entry) {
                      final index = entry.key;
                      final diagram = entry.value;
                      final desc = diagram['description'] as String? ?? '';
                      final imageUrl = diagram['imageUrl'] as String?;
                      final error = diagram['error'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                            side: BorderSide(
                              color: cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          color: cs.surfaceBright,
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                child: Text(
                                  'Diagram ${index + 1}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (desc.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                  child: Text(
                                    desc,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              if (imageUrl != null)
                                DiagramImage(url: imageUrl)
                              else if (error != null)
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.error_outline,
                                            size: 40, color: cs.error),
                                        const SizedBox(height: 8),
                                        Text(
                                          error,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: cs.error),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // Regenerate button for this diagram
                              if (onRegenerateDiagram != null) ...[
                                const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: SizedBox(
                                    height: 32,
                                    child: TextButton.icon(
                                      onPressed: isGeneratingDiagrams
                                          ? null
                                          : () => onRegenerateDiagram!(index),
                                      icon: Icon(Icons.refresh_rounded,
                                          size: 16, color: cs.primary),
                                      label: Text(
                                        isGeneratingDiagrams ? 'Regenerating...' : 'Regenerate',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: cs.primary),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  // ── Review & Regenerate ────────────────────────
                  if (onRegenerate != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            cs.onPrimaryContainer.withValues(alpha: 0.10),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusXl),
                        border: Border.all(
                          color: cs.secondary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.refresh_rounded,
                                  size: 18, color: cs.onPrimaryContainer),
                              const SizedBox(width: 8),
                              Text(
                                'Review & Regenerate',
                                style:
                                    theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: cs.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: reviewController,
                            maxLines: 3,
                            minLines: 2,
                            decoration: InputDecoration(
                              hintText:
                                  'Type feedback to guide regeneration...',
                              hintStyle: TextStyle(
                                color: cs.onPrimaryContainer
                                    .withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusLg),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor:
                                  cs.surface.withValues(alpha: 0.5),
                              contentPadding:
                                  const EdgeInsets.all(12),
                            ),
                            style:
                                TextStyle(color: cs.onPrimaryContainer),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: AppTheme.touchTarget,
                            child: FilledButton.icon(
                              onPressed:
                                  isRegenerating ? null : onRegenerate,
                              style: FilledButton.styleFrom(
                                backgroundColor: cs.secondary,
                                foregroundColor: cs.onSecondary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppTheme.radiusLg),
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
                                  : const Icon(Icons.refresh_rounded,
                                      size: 20),
                              label: Text(
                                isRegenerating
                                    ? 'Regenerating...'
                                    : 'Regenerate with AI',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14),
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

          // Divider + Action footer — always visible after generation
          if (hasGenerated)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, thickness: 1),
            ),
          if (hasGenerated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: onDiscard,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 24),
                      minimumSize:
                          const Size(100, AppTheme.touchTarget),
                    ),
                    child: const Text('Discard'),
                  ),
                  if (onExportPdf != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: isExporting ? null : onExportPdf,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.tertiary,
                        side: BorderSide(color: cs.tertiary.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusXl),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        minimumSize:
                            const Size(120, AppTheme.touchTarget),
                      ),
                      icon: isExporting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.tertiary,
                              ),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 20),
                      label: Text(isExporting ? 'Exporting...' : 'Export PDF'),
                    ),
                  ],
                  if (onToggleComplete != null) ...[
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: onToggleComplete,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppTheme.radiusXl),
                        ),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        minimumSize:
                            const Size(120, AppTheme.touchTarget),
                      ),
                      icon: Icon(lessonStatus == 'completed'
                          ? Icons.refresh
                          : Icons.check_circle),
                      label: Text(
                          lessonStatus == 'completed'
                              ? 'Mark Draft'
                              : 'Mark Completed'),
                    ),
                  ],
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: lessonStatus == 'completed'
                        ? null
                        : (isUnlocked && lessonStatus == 'draft'
                            ? onMarkCompleted ?? onSave
                            : onSave),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 32),
                      minimumSize:
                          const Size(100, AppTheme.touchTarget),
                    ),
                    child: Text(lessonStatus == 'completed'
                        ? 'Completed'
                        : (isUnlocked && lessonStatus == 'draft'
                            ? 'Mark Lesson as Completed'
                            : 'Save')),
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
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildLockedPreviewCard(String title, String content) {
    // Show first 2 sentences with maxLines:5 ellipsis
    final sentences = content
        .split(RegExp(r'(?<=[.!?])\s+'))
        .take(2)
        .join(' ');
    final displayText = sentences.isNotEmpty ? sentences : content;
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: cs.surfaceBright,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              displayText,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.lock_rounded, size: 14, color: cs.tertiary),
                const SizedBox(width: 4),
                Text(
                  'Full content visible after unlock',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.tertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(
    String title,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: cs.surfaceBright,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
        ),
        subtitle: readOnly
            ? _renderMarkdownContent(controller.text)
            : TextFormField(
                controller: controller,
                undoController: undoController,
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
              ),
      ),
    );
  }

  String _buildUnlockLabel() {
    if (!isOnline) return 'Unlock Offline';
    if (subscriptionTier.toLowerCase() == 'elite') return 'Unlock \u2014 Unlimited previews';
    if (remainingDailyPreviews > 0) {
      return 'Unlock \u2014 $remainingDailyPreviews previews left';
    }
    return 'Unlock for 1 Credit';
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
  final bool readOnly;

  const _StyledTextField({
    required this.cs,
    required this.theme,
    required this.label,
    this.controller,
    this.initialValue,
    this.readOnly = false,
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
            readOnly: readOnly,
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
