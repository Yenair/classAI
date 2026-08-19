import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
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
    show lessonsListProvider;
import 'package:classai/features/lesson/screens/lessons_list_screen.dart'
    show exportLessonPdf;
import 'package:classai/core/services/diagram_service.dart'
    show DiagramService, DiagramRequest, DiagramImage;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:classai/main.dart' show databaseProvider;

enum _LessonEditorCardKey {
  generate,
  lessonNotes,
  assessment,
  diagrams,
  references,
}

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
  // Presentation sub-section controllers.
  final _introController = TextEditingController();
  final _devController = TextEditingController();
  final _conclusionController = TextEditingController();
  int? _lessonId;
  // Phase 1: stable target for the draft generation tab.
  int? _selectedDraftLessonId;
  List<_DraftTopicOption> _draftTopicOptions = [];
  _DraftTopicOption? _selectedDraftTopic;
  bool _isLoadingDraftTopics = false;
  String? _draftLoadedSnapshot;
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
  int? _generatingDiagramIndex;
  int? _activeDiagramIndex;
  bool _isGenerating = false;
  bool _isRegenerating = false;
  bool _hasGenerated = false;
  bool _isLoadingLesson = false;
  // Phase 1/6: card-specific regeneration state.
  int _activeDeckIndex = 0;
  _LessonEditorCardKey _activeCardKey = _LessonEditorCardKey.generate;
  bool _isRegeneratingReferences = false;
  String? _referencesRegenerationError;
  int _previewRevision = 0;
  final _reviewController = TextEditingController();
  bool _isUnlocked = false;
  bool _isOnline = true;
  bool _isExporting = false;
  bool _editorSidebarOpen = false;
  bool _sidebarInitialized = false;
  int _offlineCreditBalance = 0;
  int _remainingDailyPreviews = 10;
  String? _teacherId;
  String? _schoolId;
  String _subscriptionTier = 'free';
  String _teacherName = 'Teacher';
  String _schoolName = 'School';

  // Stage 4: per-teacher visible-section preferences (persisted locally via
  // SharedPreferences, never stored in the lesson content JSON).
  bool _visibleVocabulary = false;
  bool _visibleMaterials = false;
  bool _visibleSuggestedImages = false;

  // Stage 1: legacy-settings fallback note.
  String? _legacySettingsNote;

  // Stage 1: regeneration undo snapshot path.
  String? _regenerationSnapshotPath;

  // Stage 1: persistent undo banner after regeneration.
  bool _showRegenerationBanner = false;
  // Stage 2: homework regeneration.
  bool _isRegeneratingHomework = false;
  String? _homeworkSnapshotPath;
  // Stage 2: in-memory snapshot of the pre-regeneration homework. Serves as
  // a reliable fallback for Undo when the snapshot file write fails.
  String? _homeworkBeforeRegeneration;
  // Stage 2: persistent undo banner after homework regeneration.
  bool _showHomeworkRegenerationBanner = false;

  // After generation, topic field must be double-tap confirmed before editing.
  // Starts true (editable) for new lessons; set false after generation;
  // set true for loaded existing lessons.
  bool _topicEditable = true;
  bool _topicConfirmShown = false;
  DateTime? _lastTopicTap;

  // Advanced Settings card collapsible state (default closed).
  bool _advancedSettingsOpen = false;

  // Stage 4: references visibility toggle (opt-in via Visible Sections sheet).
  bool _visibleReferences = false;

  // Floating action area: Review & Regenerate expandable state.
  bool _showReviewSection = false;
  _LessonEditorCardKey? _regenerationCardKey;
  int? _regenerationDiagramIndex;

  // Question count controls for generation.
  int _mcqCount = 5;
  int _theoryCount = 5;

  /// Scheme of Work state
  List<SchemeOfWorkData> _schemes = [];
  int? _schemeOfWorkLocalId;
  bool _isManualTopicEntry = true;
  bool _sourceMissing = false;

  // Generated content (editable after generation)
  String _objectivesText = '';
  String _vocabularyText = '';
  String _materialsText = '';
  String _presentationText = '';
  String _assessmentText = '';
  String _homeworkText = '';

  // Structured assessment questions (Phase 2) — same shape as exam content.
  List<Map<String, dynamic>> _mcqs = [];
  List<Map<String, dynamic>> _theoryQuestions = [];
  List<Map<String, dynamic>> _subjectiveQuestions = [];

  // Stage 3: number of invalid questions dropped at the last generation.
  int _droppedQuestionCount = 0;

  // Stage 3: source references persisted inside the lesson content JSON.
  // Each entry is {text, origin} where origin is 'ai' or 'teacher'.
  List<Map<String, dynamic>> _references = [];

  // Stage 3: debounced autosave timer for question edits/deletions.
  Timer? _questionAutosaveTimer;

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
    _selectedDraftLessonId = widget.lessonId;
    _isLoadingLesson = widget.lessonId != null;
    // A brand-new (blank) lesson opens with the config form expanded so the
    // fields are immediately visible/interactive; a reopened existing lesson
    // stays collapsed. Post-generation, _handleGenerate sets this back to
    // false to auto-collapse after a successful generation.
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
    _introController.addListener(_combinePresentation);
    _devController.addListener(_combinePresentation);
    _conclusionController.addListener(_combinePresentation);
  }

  List<_LessonEditorCardKey> get _visibleDeckCardKeys => [
        if (!_hasGenerated) _LessonEditorCardKey.generate,
        _LessonEditorCardKey.lessonNotes,
        _LessonEditorCardKey.assessment,
        _LessonEditorCardKey.diagrams,
        if (_visibleReferences) _LessonEditorCardKey.references,
      ];

  void _clampActiveDeckState() {
    final keys = _visibleDeckCardKeys;
    if (keys.isEmpty) return;

    final currentIndex = keys.indexOf(_activeCardKey);
    if (currentIndex >= 0) {
      _activeDeckIndex = currentIndex;
      return;
    }

    final clampedIndex = _activeDeckIndex < 0
        ? 0
        : (_activeDeckIndex >= keys.length ? keys.length - 1 : _activeDeckIndex);
    _activeDeckIndex = clampedIndex;
    _activeCardKey = keys[clampedIndex];
  }

  void _setGeneratedDeckState() {
    _hasGenerated = true;
    _activeCardKey = _LessonEditorCardKey.lessonNotes;
    _activeDeckIndex = 0;
  }

  void _onPreviewCardChanged(_LessonEditorCardKey cardKey) {
    final index = _visibleDeckCardKeys.indexOf(cardKey);
    if (index < 0 || !mounted) return;
    setState(() {
      _activeCardKey = cardKey;
      _activeDeckIndex = index;
    });
  }

  void _openReviewSectionForCard(
    _LessonEditorCardKey cardKey, {
    int? diagramIndex,
  }) {
    if (cardKey == _LessonEditorCardKey.generate) {
      return;
    }
    setState(() {
      _regenerationCardKey = cardKey;
      _regenerationDiagramIndex =
          cardKey == _LessonEditorCardKey.diagrams ? diagramIndex : null;
      _showReviewSection = true;
    });
  }

  void _toggleReviewSectionForActiveCard() {
    if (_showReviewSection) {
      setState(() => _showReviewSection = false);
      return;
    }
    _openReviewSectionForCard(
      _activeCardKey,
      diagramIndex: _activeDiagramIndex,
    );
  }

  Future<void> _handleDiagramAction(
    int index, {
    bool fromReview = false,
  }) async {
    if (index < 0 || index >= _diagramResults.length) return;

    final imageUrl = _diagramResults[index]['imageUrl'] as String?;
    setState(() {
      _activeDiagramIndex = index;
      _regenerationCardKey = _LessonEditorCardKey.diagrams;
      _regenerationDiagramIndex = index;
    });
    if (!fromReview && imageUrl != null && imageUrl.isNotEmpty) {
      _openReviewSectionForCard(
        _LessonEditorCardKey.diagrams,
        diagramIndex: index,
      );
      return;
    }
    await _snapshotForUndo();
    await _generateSuggestedImage(index);
    if (fromReview && mounted) {
      _reviewController.clear();
      setState(() {
        _showReviewSection = false;
        _showRegenerationBanner = true;
      });
      showInfoToast(context: context, message: 'Image ${index + 1} regenerated.');
    }
  }

  Future<void> _regenerateCurrentCard({
    required _LessonEditorCardKey cardKey,
    int? diagramIndex,
  }) async {
    switch (cardKey) {
      case _LessonEditorCardKey.lessonNotes:
        await _regenerateLessonNotesOnly();
        return;
      case _LessonEditorCardKey.assessment:
        await _regenerateAssessmentOnly();
        return;
      case _LessonEditorCardKey.diagrams:
        final selectedIndex = diagramIndex ?? _activeDiagramIndex;
        if (selectedIndex == null) {
          if (mounted) {
            showInfoToast(
              context: context,
              message: 'Select an image before regenerating it.',
            );
          }
          return;
        }
        await _handleDiagramAction(selectedIndex, fromReview: true);
        return;
      case _LessonEditorCardKey.generate:
        // Generate is not a generated card.
        return;
      case _LessonEditorCardKey.references:
        await _handleRegenerateReferences();
        return;
    }
  }

  String _editorSnapshot() {
    return jsonEncode({
      'topic': _topicController.text,
      'subject': _subject,
      'classLevel': _classLevel,
      'week': _week,
      'difficulty': _difficulty,
      'blooms': _selectedBlooms.toList()..sort(),
      'assessmentFormat': _assessmentFormat,
      'includeDiagrams': _includeDiagrams,
      'objectives': _objectivesController.text,
      'vocabulary': _vocabularyController.text,
      'materials': _materialsController.text,
      'presentation': _presentationController.text,
      'assessment': _assessmentController.text,
      'homework': _homeworkController.text,
    });
  }

  bool get _hasUnsavedDraftChanges =>
      _draftLoadedSnapshot != null && _draftLoadedSnapshot != _editorSnapshot();

  Future<void> _loadDraftTopicOptions() async {
    final teacherId = _teacherId;
    final schoolId = _schoolId;
    if (teacherId == null || schoolId == null) return;

    if (mounted) setState(() => _isLoadingDraftTopics = true);
    try {
      final db = ref.read(databaseProvider);
      final lessons = await db.lessonsDao.getAllForTeacher(teacherId, schoolId);
      final options = lessons
          .where(
            (lesson) =>
                lesson.status == 'draft' &&
                !lesson.isUnlocked &&
                lesson.subject == _subject &&
                lesson.classLevel == _classLevel,
          )
          .map(_DraftTopicOption.fromLesson)
          .toList();
      if (!mounted) return;
      setState(() {
        _draftTopicOptions = options;
        _selectedDraftTopic = options
            .where((option) => option.lessonId == _selectedDraftLessonId)
            .firstOrNull;
        _isLoadingDraftTopics = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _draftTopicOptions = [];
          _selectedDraftTopic = null;
          _isLoadingDraftTopics = false;
        });
      }
    }
  }

  Future<bool> _confirmDraftSwitch(String topic) async {
    final switchTopic = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'Keep editing this lesson or switch to "$topic"? '
          'Your unsaved changes will be discarded when you switch.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Switch topic'),
          ),
        ],
      ),
    );
    return switchTopic == true;
  }

  Future<void> _handleDraftTopicChanged(_DraftTopicOption? option) async {
    if (option == null) return;

    if (option.isCreateNew) {
      if (_hasUnsavedDraftChanges &&
          !await _confirmDraftSwitch('a new topic')) {
        return;
      }
      if (mounted) context.go('/lessons');
      return;
    }

    final lessonId = option.lessonId;
    if (lessonId == null) return;
    if (lessonId == _selectedDraftLessonId) {
      setState(() => _selectedDraftTopic = option);
      return;
    }

    if (_hasUnsavedDraftChanges && !await _confirmDraftSwitch(option.topic)) {
      return;
    }

    _clearDraftEditorForSwitch();
    setState(() {
      _selectedDraftTopic = option;
      _selectedDraftLessonId = lessonId;
      _lessonId = lessonId;
      _isLoadingLesson = true;
      _draftLoadedSnapshot = null;
    });
    await _loadLesson(lessonId);
  }

  void _clearDraftEditorForSwitch() {
    _topicController.clear();
    _objectivesController.clear();
    _vocabularyController.clear();
    _materialsController.clear();
    _presentationController.clear();
    _assessmentController.clear();
    _homeworkController.clear();
    _introController.clear();
    _devController.clear();
    _conclusionController.clear();
    setState(() {
      _objectivesText = '';
      _vocabularyText = '';
      _materialsText = '';
      _presentationText = '';
      _assessmentText = '';
      _homeworkText = '';
      _mcqs = [];
      _theoryQuestions = [];
      _subjectiveQuestions = [];
      _references = [];
      _diagramResults = [];
      _activeDiagramIndex = null;
      _lessonStatus = 'draft';
      _isUnlocked = true;
      _topicEditable = true;
    });
  }

  void _handleDraftGenerate() {
    final selected = _selectedDraftTopic;
    if (selected == null || selected.isCreateNew || selected.lessonId == null) {
      return;
    }
    setState(() {
      _topicController.text = selected.topic;
      _week = selected.week;
      _selectedDraftLessonId = selected.lessonId;
      _lessonId = selected.lessonId;
    });
    _handleGenerate();
  }

  void _handleCreateNewTopic() {
    _handleDraftTopicChanged(const _DraftTopicOption.createNew());
  }

  /// Combine the three presentation sub-sections back into the single
  /// [_presentationController] text so the content model stays intact.
  void _combinePresentation() {
    final parts = <String>[];
    if (_introController.text.trim().isNotEmpty) {
      parts.add('Introduction\n${_introController.text}');
    }
    if (_devController.text.trim().isNotEmpty) {
      parts.add('Development\n${_devController.text}');
    }
    if (_conclusionController.text.trim().isNotEmpty) {
      parts.add('Conclusion\n${_conclusionController.text}');
    }
    final combined = parts.join('\n\n');
    if (_presentationController.text != combined) {
      _presentationController.text = combined;
    }
  }

  /// Parse the raw presentation text into three labeled sub-sections.
  void _parsePresentationSubSections() {
    final text = _presentationText;

    // Try structured parse: look for labeled lines.
    final lines = text.split('\n');
    String? currentSection;
    final buffer = StringBuffer();
    final Map<String, String> sections = {};

    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();
      if (lower == 'introduction' || lower.startsWith('introduction:')) {
        if (currentSection != null && buffer.isNotEmpty) {
          sections[currentSection] = buffer.toString().trim();
        }
        buffer.clear();
        currentSection = 'intro';
        if (lower.startsWith('introduction:') && trimmed.length > 14) {
          buffer.writeln(trimmed.substring(14).trim());
        }
      } else if (lower == 'development' || lower.startsWith('development:')) {
        if (currentSection != null && buffer.isNotEmpty) {
          sections[currentSection] = buffer.toString().trim();
        }
        buffer.clear();
        currentSection = 'dev';
        if (lower.startsWith('development:') && trimmed.length > 12) {
          buffer.writeln(trimmed.substring(12).trim());
        }
      } else if (lower == 'conclusion' || lower.startsWith('conclusion:')) {
        if (currentSection != null && buffer.isNotEmpty) {
          sections[currentSection] = buffer.toString().trim();
        }
        buffer.clear();
        currentSection = 'conclusion';
        if (lower.startsWith('conclusion:') && trimmed.length > 11) {
          buffer.writeln(trimmed.substring(11).trim());
        }
      } else if (currentSection != null) {
        buffer.writeln(line);
      }
    }
    if (currentSection != null && buffer.isNotEmpty) {
      sections[currentSection] = buffer.toString().trim();
    }

    // If no sections were parsed, fall back: put everything in intro.
    if (sections.isEmpty && text.trim().isNotEmpty) {
      _introController.text = text;
      _devController.text = '';
      _conclusionController.text = '';
    } else {
      _introController.text = sections['intro'] ?? '';
      _devController.text = sections['dev'] ?? '';
      _conclusionController.text = sections['conclusion'] ?? '';
    }
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
      _loadOfflineCreditBalance();
      _loadDailyPreviewData();
      _loadAuthInfo();
      _loadSchemesForContext();
      _loadVisibleSectionPrefs();
      if (_lessonId != null) {
        _loadLesson(_lessonId!);
      }
    });
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
        // Detect legacy lessons missing settings for fallback defaults.
        final bool legacyDifficulty = lesson.difficulty.isEmpty;
        final bool legacyBlooms = lesson.bloomsVerbs.trim().isEmpty;
        final bool legacyAssessmentFormat = parsedContent != null &&
            parsedContent['assessmentFormat'] == null &&
            parsedContent['objectives'] != null;
        final bool needsLegacyFallback =
            legacyDifficulty || legacyBlooms || legacyAssessmentFormat;
        setState(() {
          _lessonId = lesson.id;
          _selectedDraftLessonId = lesson.id;
          _topicController.text = lesson.topic;
          _lessonStatus = lesson.status;
          _week = lesson.week;
          _subject = lesson.subject;
          _classLevel = lesson.classLevel;
          _difficulty = legacyDifficulty ? 'medium' : lesson.difficulty;
          _selectedBlooms.clear();
          if (legacyBlooms) {
            _selectedBlooms.addAll(_bloomVerbs);
          } else {
            _selectedBlooms.addAll(
              lesson.bloomsVerbs
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty),
            );
          }
          _schemeOfWorkLocalId = lesson.schemeOfWorkId != null
              ? int.tryParse(lesson.schemeOfWorkId!)
              : null;
          if (lesson.weekNumber != null) {
            _week = lesson.weekNumber!;
          }
          _sourceMissing = sourceMissing;
          if (parsedContent != null) {
            _objectivesText = _formatList(parsedContent['objectives']);
            _objectivesController.text = _objectivesText;
            _vocabularyText = _formatList(parsedContent['vocabulary']);
            _vocabularyController.text = _vocabularyText;
            _materialsText = _formatList(parsedContent['materials']);
            _materialsController.text = _materialsText;
            _presentationText = _formatJson(parsedContent['presentation']);
            _presentationController.text = _presentationText;
            _parsePresentationSubSections();
            _assessmentText = parsedContent['assessment'] as String? ?? '';
            _assessmentController.text = _assessmentText;
            _homeworkText = parsedContent['homework'] as String? ?? '';
            _homeworkController.text = _homeworkText;
            final hasStoredGeneratedContent = [
              _objectivesText,
              _vocabularyText,
              _materialsText,
              _presentationText,
              _assessmentText,
              _homeworkText,
            ].any((section) => section.trim().isNotEmpty);
            // Drafts are editable generation inputs, even if an autosave or
            // interrupted generation left partial content in the JSON column.
            _hasGenerated = lesson.status != 'draft' && hasStoredGeneratedContent;
            _activeCardKey = _hasGenerated
                ? _LessonEditorCardKey.lessonNotes
                : _LessonEditorCardKey.generate;
            _activeDeckIndex = 0;
            _isUnlocked = lesson.status == 'draft' ||
                (lesson.isUnlocked && _hasGenerated);
            _topicEditable = true;
            _assessmentFormat =
                parsedContent['assessmentFormat'] as String? ?? 'Both';
            // Restore structured questions if present in stored content.
            // Older lessons without the `questions` key load normally.
            final storedQuestions =
                parsedContent['questions'] as Map<String, dynamic>?;
            if (storedQuestions != null) {
              _mcqs = _castQuestionList(storedQuestions['mcqs']);
              _theoryQuestions = _castQuestionList(storedQuestions['theory']);
              _subjectiveQuestions =
                  _castQuestionList(storedQuestions['subjective']);
            }
            // Restore source references (Stage 3). Missing or malformed
            // values fall back to an empty list.
            _references = _parseReferences(parsedContent['references']);
            // Restore diagram results if present in stored content
            final storedDiagrams = parsedContent['diagrams'] as List<dynamic>?;
            if (storedDiagrams != null && storedDiagrams.isNotEmpty) {
              _diagramResults = storedDiagrams
                  .map((d) => d as Map<String, dynamic>)
                  .toList();
            }
          }
        });
        if (needsLegacyFallback && mounted) {
          setState(() {
            _legacySettingsNote =
                'Some lesson settings were missing and restored to defaults.';
          });
        }
        if (mounted) {
          _draftLoadedSnapshot = _editorSnapshot();
          await _loadDraftTopicOptions();
        }
      }
    } catch (_) {
      // Lesson not found — continue with empty form
    } finally {
      if (mounted) {
        setState(() => _isLoadingLesson = false);
      }
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
      await _loadDraftTopicOptions();
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

  Future<void> _loadOfflineCreditBalance() async {
    try {
      await ref.read(offlineCreditStateProvider.notifier).refresh();
      if (mounted) {
        setState(() => _offlineCreditBalance =
            ref.read(offlineCreditStateProvider).currentOfflineCredits);
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

  /// Returns true when the stored lesson content is an empty placeholder
  /// (no populated objectives/vocabulary/materials/presentation/assessment/
  /// homework), such as the rows auto-created from a scheme of work.
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
      // If it is not valid JSON, treat it as content that should be
      // preserved and therefore block generation (conservative).
      return false;
    }
  }

  /// Returns the first duplicate lesson found, or null if none.
  Future<Lesson?> _findDuplicateLesson(AppDatabase db) async {
    try {
      final teacherServerId = _teacherId;
      if (teacherServerId == null || teacherServerId.isEmpty) return null;

      final schoolLocalId =
          ref.read(authProvider).currentSchool?.localId ??
              (await db.schoolsDao.get())?.localId;
      if (schoolLocalId == null) return null;

      final targetTerm = await _resolveGenerationTermLabel(db);
      if (targetTerm == null || targetTerm.isEmpty) return null;

      final allLessons = await db.lessonsDao.getAll();
      for (final lesson in allLessons) {
        if (_lessonId != null && lesson.id == _lessonId) continue;
        if (lesson.teacherServerId != teacherServerId) continue;
        if (lesson.subject != _subject || lesson.week != _week) continue;

        final lessonTerm =
            await _resolveLessonTermLabel(db, lesson, schoolLocalId);
        if (lessonTerm == null || lessonTerm.isEmpty) continue;
        if (_normalizeTermLabel(lessonTerm) == targetTerm) {
          if (_isLessonContentEmpty(lesson.content)) continue;
          return lesson;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _isEmptyListOrBlank(dynamic value) {
    if (value == null) return true;
    if (value is List) return value.isEmpty;
    if (value is String) return value.trim().isEmpty;
    return false;
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
    // The blank-lesson entry screen does not render a Form, so its
    // FormState is null. Only validate when a Form is actually mounted
    // (the existing/generated editor path); the entry screen's
    // "Create lesson" must not crash on a null check.
    if (_formKey.currentState != null &&
        !_formKey.currentState!.validate()) {
      return;
    }

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

      // Duplicate detection — show a dialog with Open / Continue.
      final duplicate = await _findDuplicateLesson(db);
      if (duplicate != null && mounted) {
        setState(() => _isGenerating = false);
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Duplicate Lesson'),
            content: Text(
              'You already have a lesson for ${duplicate.topic} in '
              '${duplicate.subject} \u00b7 ${duplicate.classLevel} '
              '\u00b7 Week ${duplicate.week}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('open'),
                child: const Text('Open existing lesson'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop('continue'),
                child: const Text('Continue anyway'),
              ),
            ],
          ),
        );
        if (action == 'open') {
          if (mounted) context.push('/lessons/${duplicate.id}');
          return;
        }
        // 'continue' — fall through to generation.
        setState(() => _isGenerating = true);
      }

      // ── Structured assessment questions (Phase 2) ────────────────
      // The agreed tier gate (assessment_generation_allowed_tiers, default
      // ["standard","elite"]) gates ONLY the questions call — lower tiers
      // still generate lessons exactly as before.
      final config = ref.read(configServiceProvider);
      final questionsEnabled =
          config.assessmentGenerationAllowedTiers.contains(authTier);
      final questionsPrompt = questionsEnabled
          ? PromptTemplates.lessonQuestions(
              _subject,
              _classLevel,
              topic,
              _difficulty,
              bloomsStr,
              _questionCountsForFormat(_assessmentFormat),
              teacherName: _teacherName,
              schoolName: _schoolName,
            )
          : null;

      // Generate via callback or fallback to AiService
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      Map<String, dynamic> result;
      Map<String, dynamic>? questionsResult;
      if (widget.generateCallback != null) {
        // Test / external callback path – skip AiService setup
        result = await widget.generateCallback!(prompt);
        if (questionsPrompt != null) {
          try {
            questionsResult = await widget.generateCallback!(questionsPrompt);
          } catch (_) {
            // Questions failed — the lesson still saves without them.
            questionsResult = null;
          }
        }
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

        // Fire the lesson and questions calls concurrently. The lesson call
        // is authoritative: if IT fails, the whole action fails and nothing
        // is saved (no partial data). A questions failure only means the
        // lesson saves without structured questions.
        final lessonFuture = aiService.generate(prompt);
        final questionsFuture = questionsPrompt != null
            ? aiService
                  .generate(questionsPrompt)
                  .then<Map<String, dynamic>?>((r) => r)
                  .catchError((Object _) => null)
            : Future<Map<String, dynamic>?>.value(null);

        result = await lessonFuture;
        questionsResult = await questionsFuture;

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

      // Parse + validate the structured questions (best-effort). Invalid
      // items are dropped; a failed/empty questions result never blocks the
      // lesson from saving.
      Map<String, List<Map<String, dynamic>>>? parsedQuestions;
      var droppedQuestionCount = 0;
      if (questionsResult != null) {
        try {
          final questionsRaw =
              questionsResult['raw'] as Map<String, dynamic>? ??
                  questionsResult;
          final rawMcqs =
              (questionsRaw['mcq'] ?? questionsRaw['mcqs']) as List<dynamic>? ??
                  const [];
          final rawTheory = questionsRaw['theory'] as List<dynamic>? ?? const [];
          final rawSubjective =
              questionsRaw['subjective'] as List<dynamic>? ?? const [];
          parsedQuestions = parseLessonQuestions(questionsRaw);
          final validCount = parsedQuestions['mcqs']!.length +
              parsedQuestions['theory']!.length +
              parsedQuestions['subjective']!.length;
          droppedQuestionCount =
              rawMcqs.length + rawTheory.length + rawSubjective.length -
                  validCount;
        } catch (_) {
          parsedQuestions = null;
        }
      }
      final questionsFailed = questionsResult == null || parsedQuestions == null;

      List<Map<String, dynamic>> generatedDiagrams = [];
      final diagramsRaw = parsedRaw['diagrams'] as List<dynamic>?;
      if (diagramsRaw != null && diagramsRaw.isNotEmpty) {
        generatedDiagrams = diagramsRaw.take(3).map((entry) {
          final diagram = entry is Map<String, dynamic>
              ? entry
              : <String, dynamic>{};
          return <String, dynamic>{
            'description': diagram['description'] as String? ?? 'Suggested image',
            'imageUrl': diagram['imageUrl'] as String?,
            'error': diagram['error'] as String?,
          };
        }).toList();
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
            _objectivesText = _formatList(parsedRaw['objectives']);
            _objectivesController.text = _objectivesText;
            _vocabularyText = _formatList(parsedRaw['vocabulary']);
            _vocabularyController.text = _vocabularyText;
            _materialsText = _formatList(parsedRaw['materials']);
            _materialsController.text = _materialsText;
            _presentationText = _formatJson(parsedRaw['presentation']);
            _presentationController.text = _presentationText;
            _parsePresentationSubSections();
            _assessmentText = _formatList(parsedRaw['assessment']);
            _assessmentController.text = _assessmentText;
            _homeworkText = _formatList(parsedRaw['homework']);
            _homeworkController.text = _homeworkText;
            _mcqs = parsedQuestions?['mcqs'] ?? const [];
            _theoryQuestions = parsedQuestions?['theory'] ?? const [];
            _subjectiveQuestions = parsedQuestions?['subjective'] ?? const [];
            _droppedQuestionCount = droppedQuestionCount;
            _references =
                _parseReferences(parsedRaw['references'], forceAiOrigin: true);
            _diagramResults = generatedDiagrams;
            _setGeneratedDeckState();
            _topicEditable = false;
            _topicConfirmShown = false;
            if (_lessonStatus == 'draft') _lessonStatus = 'generated';
            _isUnlocked = false;
            _isGenerating = false;
            _previewRevision++;
          });
          _saveLesson(notify: false);
          if (mounted) {
            if (!questionsEnabled) {
              showInfoToast(
                context: context,
                message: 'Assessment questions require Standard or Elite — '
                    'upgrade to include them.',
              );
            } else if (questionsFailed) {
              showInfoToast(
                context: context,
                message: 'Lesson saved — assessment questions could not be '
                    'generated.',
              );
            } else if (droppedQuestionCount > 0) {
              showInfoToast(
                context: context,
                message: 'Lesson saved — $droppedQuestionCount question(s) '
                    'were invalid and skipped.',
              );
            } else {
              showInfoToast(
                  context: context, message: 'Lesson generated successfully!');
            }
            if (_includeDiagrams &&
                _subscriptionTier.toLowerCase() == 'elite' &&
                _diagramResults.isNotEmpty) {
              _generateSuggestedImage(0);
            }
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

  Future<void> _generateSuggestedImage(int diagramIndex) async {
    final currentTier = (ref.read(authProvider).currentSchool?.subscriptionTier ?? _subscriptionTier).toLowerCase();
    if (currentTier != 'elite') {
      if (mounted) {
        await _showUpgradeRequiredDialog();
      }
      return;
    }
    if (diagramIndex < 0 || diagramIndex >= _diagramResults.length) {
      return;
    }

    setState(() {
      _isGeneratingDiagrams = true;
      _generatingDiagramIndex = diagramIndex;
    });

    try {
      // Find the diagram description from current results
      final diagram = _diagramResults[diagramIndex];
      final description = diagram['description'] as String? ?? 'Suggested image';
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
          _generatingDiagramIndex = null;
        });
        await _saveLesson(notify: false);
      }
    } catch (e) {
      debugPrint('[LessonEditor] Suggested image generation failed: $e');
      if (mounted) {
        setState(() {
          _isGeneratingDiagrams = false;
          _generatingDiagramIndex = null;
        });
      }
    }
  }

  Future<void> _regenerateLessonNotesOnly() async {
    await _snapshotForUndo();
    if (!mounted) return;
    setState(() {
      _isRegenerating = true;
      _showRegenerationBanner = false;
    });

    try {
      final db = ref.read(databaseProvider);
      final topic = _topicController.text.trim();
      final review = _reviewController.text.trim();
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
      final prompt = review.isEmpty
          ? basePrompt
          : '$basePrompt\n\nTeacher feedback: $review';
      final result = widget.generateCallback != null
          ? await widget.generateCallback!(prompt)
          : await AiService(db: db).generate(prompt);
      final raw = result['raw'] as Map<String, dynamic>? ?? result;

      if (!mounted) return;
      setState(() {
        _objectivesText = _formatList(raw['objectives']);
        _objectivesController.text = _objectivesText;
        _vocabularyText = _formatList(raw['vocabulary']);
        _vocabularyController.text = _vocabularyText;
        _materialsText = _formatList(raw['materials']);
        _materialsController.text = _materialsText;
        _presentationText = _formatJson(raw['presentation']);
        _presentationController.text = _presentationText;
        _parsePresentationSubSections();
        _isRegenerating = false;
        _previewRevision++;
      });
      await _saveLesson(notify: false);
      _reviewController.clear();
      if (mounted) {
        setState(() {
          _showReviewSection = false;
          _showRegenerationBanner = true;
        });
        showInfoToast(context: context, message: 'Lesson notes regenerated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        showErrorToast(context: context, message: 'Regeneration failed: $e');
      }
    }
  }

  Future<void> _regenerateAssessmentOnly() async {
    final authTier =
        (ref.read(authProvider).currentSchool?.subscriptionTier ??
                _subscriptionTier)
            .toLowerCase();
    final questionsEnabled = ref
        .read(configServiceProvider)
        .assessmentGenerationAllowedTiers
        .contains(authTier);
    if (!questionsEnabled) {
      if (mounted) await _showUpgradeRequiredDialog();
      return;
    }

    await _snapshotForUndo();
    if (!mounted) return;
    setState(() {
      _isRegenerating = true;
      _showRegenerationBanner = false;
    });

    try {
      final db = ref.read(databaseProvider);
      final topic = _topicController.text.trim();
      final review = _reviewController.text.trim();
      final bloomsStr =
          _selectedBlooms.isEmpty ? 'All levels' : _selectedBlooms.join(', ');
      final basePrompt = PromptTemplates.lessonQuestions(
        _subject,
        _classLevel,
        topic,
        _difficulty,
        bloomsStr,
        _questionCountsForFormat(_assessmentFormat),
        teacherName: _teacherName,
        schoolName: _schoolName,
      );
      final prompt = review.isEmpty
          ? basePrompt
          : '$basePrompt\n\nTeacher feedback: $review';
      final result = widget.generateCallback != null
          ? await widget.generateCallback!(prompt)
          : await AiService(db: db).generate(prompt);
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      final rawMcqs =
          (raw['mcq'] ?? raw['mcqs']) as List<dynamic>? ?? const [];
      final rawTheory = raw['theory'] as List<dynamic>? ?? const [];
      final rawSubjective = raw['subjective'] as List<dynamic>? ?? const [];
      final parsedQuestions = parseLessonQuestions(raw);
      final validCount = parsedQuestions['mcqs']!.length +
          parsedQuestions['theory']!.length +
          parsedQuestions['subjective']!.length;
      final droppedQuestionCount =
          rawMcqs.length + rawTheory.length + rawSubjective.length - validCount;

      if (!mounted) return;
      setState(() {
        _mcqs = parsedQuestions['mcqs']!;
        _theoryQuestions = parsedQuestions['theory']!;
        _subjectiveQuestions = parsedQuestions['subjective']!;
        _droppedQuestionCount = droppedQuestionCount;
        _isRegenerating = false;
        _previewRevision++;
      });
      await _saveLesson(notify: false);
      _reviewController.clear();
      if (mounted) {
        setState(() {
          _showReviewSection = false;
          _showRegenerationBanner = true;
        });
        showInfoToast(context: context, message: 'Assessment regenerated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        showErrorToast(
          context: context,
          message: 'Assessment regeneration failed: $e',
        );
      }
    }
  }

  Future<void> _handleRegenerateReferences() async {
    if (!_isUnlocked || _lessonId == null || _isRegeneratingReferences) return;

    setState(() {
      _isRegeneratingReferences = true;
      _referencesRegenerationError = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final topic = _topicController.text.trim();
      final review = _reviewController.text.trim();
      final basePrompt = PromptTemplates.referencesOnly(
        _subject,
        _classLevel,
        _week,
        topic,
        teacherName: _teacherName,
        schoolName: _schoolName,
      );
      final prompt = review.isEmpty
          ? basePrompt
          : '$basePrompt\n\nTeacher feedback: $review';
      final result = widget.generateCallback != null
          ? await widget.generateCallback!(prompt)
          : await AiService(db: db).generate(prompt);
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      final references =
          _parseReferences(raw['references'], forceAiOrigin: true);

      if (!mounted) return;
      setState(() {
        _references = references;
        _isRegeneratingReferences = false;
        _referencesRegenerationError = null;
      });
      await _saveLesson(notify: false);
      _reviewController.clear();
      if (mounted) {
        setState(() => _showReviewSection = false);
        showInfoToast(context: context, message: 'References regenerated.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRegeneratingReferences = false;
          _referencesRegenerationError = 'References regeneration failed: $e';
        });
        showErrorToast(
          context: context,
          message: 'References regeneration failed: $e',
        );
      }
    }
  }

  Future<void> _handleRegenerate({
    bool skipConfirmation = false,
    _LessonEditorCardKey? cardKey,
    int? diagramIndex,
  }) async {
    final targetCard = cardKey ?? _regenerationCardKey ?? _activeCardKey;
    if (!mounted) return;
    if (!skipConfirmation) {
      _openReviewSectionForCard(
        targetCard,
        diagramIndex: diagramIndex ?? _activeDiagramIndex,
      );
      return;
    }
    if (targetCard != _LessonEditorCardKey.generate) {
      await _regenerateCurrentCard(
        cardKey: targetCard,
        diagramIndex: diagramIndex ?? _regenerationDiagramIndex,
      );
      return;
    }
    // Snapshot current content for undo before overwriting.
    await _snapshotForUndo();

    setState(() {
      _isRegenerating = true;
      _showRegenerationBanner = false;
    });
    try {
      final db = ref.read(databaseProvider);
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

      // Structured assessment questions (Phase 2) — same tier gate as
      // generation; the feedback suffix applies to both prompts.
      final authTier =
          (ref.read(authProvider).currentSchool?.subscriptionTier ??
                  _subscriptionTier)
              .toLowerCase();
      final questionsEnabled =
          ref
              .read(configServiceProvider)
              .assessmentGenerationAllowedTiers
              .contains(authTier);
      final baseQuestionsPrompt = questionsEnabled
          ? PromptTemplates.lessonQuestions(
              _subject,
              _classLevel,
              topic,
              _difficulty,
              bloomsStr,
              _questionCountsForFormat(_assessmentFormat),
              teacherName: _teacherName,
              schoolName: _schoolName,
            )
          : null;
      final questionsPrompt =
          (baseQuestionsPrompt == null || review.isEmpty)
              ? baseQuestionsPrompt
              : '$baseQuestionsPrompt\n\nTeacher feedback: $review';

      // Generate via callback or fallback to AiService
      Map<String, dynamic> result;
      Map<String, dynamic>? questionsResult;
      if (widget.generateCallback != null) {
        result = await widget.generateCallback!(regeneratedPrompt);
        if (questionsPrompt != null) {
          try {
            questionsResult = await widget.generateCallback!(questionsPrompt);
          } catch (_) {
            questionsResult = null;
          }
        }
      } else {
        // Production path: construct AiService only here so widget tests
        // providing a generateCallback never touch Supabase.
        final aiService = AiService(db: db);
        final lessonFuture = aiService.generate(regeneratedPrompt);
        final questionsFuture = questionsPrompt != null
            ? aiService
                  .generate(questionsPrompt)
                  .then<Map<String, dynamic>?>((r) => r)
                  .catchError((Object _) => null)
            : Future<Map<String, dynamic>?>.value(null);
        result = await lessonFuture;
        questionsResult = await questionsFuture;
      }

      // Parse the generated JSON
      final raw = result['raw'] as Map<String, dynamic>? ?? result;

      // Parse + validate the structured questions (best-effort).
      Map<String, List<Map<String, dynamic>>>? parsedQuestions;
      var droppedQuestionCount = 0;
      if (questionsResult != null) {
        try {
          final questionsRaw =
              questionsResult['raw'] as Map<String, dynamic>? ??
                  questionsResult;
          final rawMcqs =
              (questionsRaw['mcq'] ?? questionsRaw['mcqs']) as List<dynamic>? ??
                  const [];
          final rawTheory = questionsRaw['theory'] as List<dynamic>? ?? const [];
          final rawSubjective =
              questionsRaw['subjective'] as List<dynamic>? ?? const [];
          parsedQuestions = parseLessonQuestions(questionsRaw);
          final validCount = parsedQuestions['mcqs']!.length +
              parsedQuestions['theory']!.length +
              parsedQuestions['subjective']!.length;
          droppedQuestionCount =
              rawMcqs.length + rawTheory.length + rawSubjective.length -
                  validCount;
        } catch (_) {
          parsedQuestions = null;
        }
      }
      final questionsFailed = questionsResult == null || parsedQuestions == null;
      // Defer ALL setState to a normal vsync frame to avoid scheduleWarmUpFrame
      // and the mouse_tracker assertion during device update.
      WidgetsBinding.instance.scheduleFrame();
      WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _objectivesText = _formatList(raw['objectives']);
        _objectivesController.text = _objectivesText;
        _vocabularyText = _formatList(raw['vocabulary']);
        _vocabularyController.text = _vocabularyText;
        _materialsText = _formatList(raw['materials']);
        _materialsController.text = _materialsText;
        _presentationText = _formatJson(raw['presentation']);
        _presentationController.text = _presentationText;
        _parsePresentationSubSections();
        _assessmentText = raw['assessment'] as String? ?? '';
        _assessmentController.text = _assessmentText;
        _homeworkText = raw['homework'] as String? ?? '';
        _homeworkController.text = _homeworkText;
        _mcqs = parsedQuestions?['mcqs'] ?? const [];
        _theoryQuestions = parsedQuestions?['theory'] ?? const [];
        _subjectiveQuestions = parsedQuestions?['subjective'] ?? const [];
        _droppedQuestionCount = droppedQuestionCount;
        _references =
            _parseReferences(raw['references'], forceAiOrigin: true);
        _setGeneratedDeckState();
        if (_lessonStatus == 'draft') _lessonStatus = 'generated';
        _isRegenerating = false;
        _previewRevision++;
      });
      });

      await _saveLesson(notify: false);
      _reviewController.clear();
      if (mounted) {
        setState(() => _showReviewSection = false);
        // Show persistent undo banner after regeneration.
        setState(() => _showRegenerationBanner = true);
        if (!questionsEnabled) {
          showInfoToast(
            context: context,
            message: 'Assessment questions require Standard or Elite — '
                'upgrade to include them.',
          );
        } else if (questionsFailed) {
          showInfoToast(
            context: context,
            message: 'Lesson saved — assessment questions could not be '
                'generated.',
          );
        } else if (droppedQuestionCount > 0) {
          showInfoToast(
            context: context,
            message: 'Lesson saved — $droppedQuestionCount question(s) '
                'were invalid and skipped.',
          );
        }
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

    if (!isOnline && _offlineCreditBalance < 1) {
      // Show persistent toast with sync option
      AppToast.instance.showToast(
        context: context,
        message:
            'Out of offline credits. Connect to internet and sync to refill.',
        icon: Icons.warning,
      );
      _showSyncBottomSheet();
      return;
    }

    try {
      final offlineCreditService =
          OfflineCreditService(ref.read(databaseProvider));
      await offlineCreditService.spendOfflineCredits(
          amount: 1, contentIds: ['lesson_draft']);

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
          _offlineCreditBalance = _offlineCreditBalance - 1;
        }
      });

      // Persist the unlock so it survives navigation away and back.
      await _saveLesson(notify: false);

      // Refresh the cached lesson list so the "Unlocked" filter reflects the
      // newly unlocked state immediately.
      ref.invalidate(lessonsListProvider);

      ref.read(offlineCreditStateProvider.notifier).refresh();

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
            Text('Sync Offline Credits',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
                'Tap below to sync with the server and refill your offline credits.'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // Trigger sync
                ref.read(offlineCreditStateProvider.notifier).refresh();
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

  /// Maps the existing Assessment Format dropdown (MCQ / Theory / Both) to
  /// per-type question counts — giving the control a real effect.
  Map<String, int> _questionCountsForFormat(String format) {
    switch (format) {
      case 'MCQ':
        return {'MCQ': _mcqCount, 'Theory': 0, 'Subjective': 0};
      case 'Theory':
        return {'MCQ': 0, 'Theory': _theoryCount, 'Subjective': 0};
      case 'Subjective':
        return {'MCQ': 0, 'Theory': 0, 'Subjective': _mcqCount};
      default: // 'Both'
        return {'MCQ': _mcqCount, 'Theory': _theoryCount, 'Subjective': 0};
    }
  }

  /// Casts a stored questions list (from lesson content) to a list of maps,
  /// tolerating null/malformed entries so older lessons load safely.
  List<Map<String, dynamic>> _castQuestionList(dynamic list) {
    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// Safely parses a `references` value (from the AI response or stored
  /// lesson content) into a list of {text, origin} maps. Malformed or
  /// missing input never throws and defaults to an empty list.
  ///
  /// When [forceAiOrigin] is true (AI response), every entry is labeled
  /// 'ai' or 'curated' (when the title matches a known textbook) so
  /// generated references are never presented without a label.
  /// When false (stored content), stored origins are preserved and
  /// sanitized to 'teacher', 'ai', or 'curated'.
  List<Map<String, dynamic>> _parseReferences(
    dynamic raw, {
    bool forceAiOrigin = false,
  }) {
    if (raw is! List) return const [];
    final result = <Map<String, dynamic>>[];
    try {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final text =
            (map['text'] ?? map['title'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        var origin = map['origin']?.toString().trim().toLowerCase();
        if (origin != 'teacher' && origin != 'ai' && origin != 'curated') {
          origin = 'ai';
        }
        // Auto-detect curated references from AI responses: if the title
        // matches a known textbook in the curated list, upgrade the label.
        if (forceAiOrigin && origin == 'ai') {
          final isCurated = PromptTemplates.curatedTextbookTitles.any(
            (t) => t.toLowerCase() == text.toLowerCase(),
          );
          if (isCurated) origin = 'curated';
        }
        result.add({
          'text': text,
          'origin': origin,
        });
      }
    } catch (_) {
      return const [];
    }
    return result;
  }

  // ── Stage 3: Question editing / deletion ────────────────────────

  /// Schedules a debounced autosave (500ms) after a question edit or
  /// deletion. Only fires while the lesson is unlocked and has a persisted
  /// row; repeated edits cancel the previous pending save so the final
  /// save always reflects the current in-memory state.
  void _scheduleQuestionAutosave() {
    if (!_isUnlocked || _lessonId == null || !_hasGenerated) return;
    _questionAutosaveTimer?.cancel();
    _questionAutosaveTimer = Timer(const Duration(milliseconds: 500), () {
      _questionAutosaveTimer = null;
      if (!mounted) return;
      _saveLesson(notify: false);
    });
  }

  void _updateMcq(int index, String field, String value) {
    if (index < 0 || index >= _mcqs.length) return;
    setState(() {
      _mcqs[index][field] = value;
    });
    _scheduleQuestionAutosave();
  }

  void _updateMcqOption(int index, String optionKey, String value) {
    if (index < 0 || index >= _mcqs.length) return;
    setState(() {
      final options = Map<String, String>.from(
          _mcqs[index]['options'] as Map? ?? {});
      options[optionKey] = value;
      _mcqs[index]['options'] = options;
    });
    _scheduleQuestionAutosave();
  }

  void _updateTheory(int index, String field, String value) {
    if (index < 0 || index >= _theoryQuestions.length) return;
    setState(() {
      _theoryQuestions[index][field] = value;
    });
    _scheduleQuestionAutosave();
  }

  /// Subjective questions store the answer under both `answer` (legacy)
  /// and `modelAnswer` (normalized) — keep them in sync when the shared
  /// card edits `modelAnswer`.
  void _updateSubjective(int index, String field, String value) {
    if (index < 0 || index >= _subjectiveQuestions.length) return;
    setState(() {
      _subjectiveQuestions[index][field] = value;
      if (field == 'modelAnswer') {
        _subjectiveQuestions[index]['answer'] = value;
      }
    });
    _scheduleQuestionAutosave();
  }

  /// Removes a question from the in-memory list; the saved lesson content
  /// is updated on the next save.
  void _deleteMcq(int index) {
    if (index < 0 || index >= _mcqs.length) return;
    setState(() {
      _mcqs.removeAt(index);
    });
    _scheduleQuestionAutosave();
  }

  void _deleteTheory(int index) {
    if (index < 0 || index >= _theoryQuestions.length) return;
    setState(() {
      _theoryQuestions.removeAt(index);
    });
    _scheduleQuestionAutosave();
  }

  void _deleteSubjective(int index) {
    if (index < 0 || index >= _subjectiveQuestions.length) return;
    setState(() {
      _subjectiveQuestions.removeAt(index);
    });
    _scheduleQuestionAutosave();
  }

  // ── Stage 3: References panel ───────────────────────────────────

  /// Builds the "linked scheme-of-work name and week" reference text, or
  /// null when the lesson is not linked to a scheme.
  String? _buildSchemeReference() {
    final schemeId = _schemeOfWorkLocalId;
    if (schemeId == null) return null;
    final scheme = _schemes.where((s) => s.id == schemeId).firstOrNull;
    final topic = scheme?.adminEditedTopic ?? scheme?.topic;
    final base = '$_subject Scheme of Work — Week $_week';
    if (topic != null && topic.trim().isNotEmpty) {
      return '$base: ${topic.trim()}';
    }
    return base;
  }

  /// Shows the References bottom sheet. While the lesson is still locked
  /// the sheet opens in read-only mode: references can be viewed but not
  /// added or removed.
  void _showReferencesSheet() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final readOnly = !_isUnlocked;
    // Priority order: (1) linked scheme, (2) source topic when manually
    // entered, then (3) stored AI / teacher references.
    final schemeReference = _buildSchemeReference();
    final String? topicReference = null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _ReferencesSheet(
        cs: cs,
        theme: theme,
        schemeReference: schemeReference,
        topicReference: topicReference,
        references: List<Map<String, dynamic>>.from(_references),
        readOnly: readOnly,
        onAddReference: (text) {
          setState(() {
            _references.add({'text': text, 'origin': 'teacher'});
          });
        },
        onRemoveReference: (index) {
          setState(() {
            if (index >= 0 && index < _references.length) {
              _references.removeAt(index);
            }
          });
        },
      ),
    );
  }

  // ── Stage 4: Visible sections preferences ───────────────────────

  /// Returns the SharedPreferences key for a visible-section toggle, scoped
  /// per teacher (`<teacherId>_lesson_visible_...`). Falls back to the
  /// unscoped key when no teacher ID is known yet, which is a safe default
  /// (one shared preference set for anonymous / not-yet-loaded sessions).
  String _visibleSectionPrefKey(String baseKey) {
    final teacherId = _teacherId;
    return (teacherId == null || teacherId.isEmpty)
        ? baseKey
        : '${teacherId}_$baseKey';
  }

  /// Loads the per-teacher visible-section preferences. Defaults are all
  /// OFF (sections hidden) when nothing has been saved yet.
  Future<void> _loadVisibleSectionPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _visibleVocabulary =
            prefs.getBool(_visibleSectionPrefKey('lesson_visible_vocabulary')) ??
                false;
        _visibleMaterials =
            prefs.getBool(_visibleSectionPrefKey('lesson_visible_materials')) ??
                false;
        _visibleSuggestedImages =
            prefs.getBool(
                  _visibleSectionPrefKey('lesson_visible_suggested_images'),
                ) ??
                false;
        _visibleReferences =
            prefs.getBool(
                  _visibleSectionPrefKey('lesson_visible_references'),
                ) ??
                false;
        _clampActiveDeckState();
      });
    } catch (_) {
      // Preferences unavailable — keep the defaults (sections hidden).
    }
  }

  /// Persists a single visible-section toggle. Never touches the lesson
  /// content JSON.
  Future<void> _persistVisibleSection(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Non-fatal: the toggle still applies for this session.
    }
  }

  /// Opens the bottom sheet where the teacher picks which optional sections
  /// (Vocabulary, Materials, Suggested Images / Diagrams) appear in the
  /// lesson document.
  void _showVisibleSectionsSheet() {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _VisibleSectionsSheet(
        cs: cs,
        theme: theme,
        visibleVocabulary: _visibleVocabulary,
        visibleMaterials: _visibleMaterials,
        visibleSuggestedImages: _visibleSuggestedImages,
        onVocabularyChanged: (v) {
          setState(() => _visibleVocabulary = v);
          _persistVisibleSection(
              _visibleSectionPrefKey('lesson_visible_vocabulary'), v);
        },
        onMaterialsChanged: (v) {
          setState(() => _visibleMaterials = v);
          _persistVisibleSection(
              _visibleSectionPrefKey('lesson_visible_materials'), v);
        },
        onSuggestedImagesChanged: (v) {
          setState(() => _visibleSuggestedImages = v);
          _persistVisibleSection(
              _visibleSectionPrefKey('lesson_visible_suggested_images'), v);
        },
        visibleReferences: _visibleReferences,
        onReferencesChanged: (v) {
          setState(() {
            _visibleReferences = v;
            _clampActiveDeckState();
          });
          _persistVisibleSection(
              _visibleSectionPrefKey('lesson_visible_references'), v);
        },
      ),
    );
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
        if (_mcqs.isNotEmpty ||
            _theoryQuestions.isNotEmpty ||
            _subjectiveQuestions.isNotEmpty)
          'questions': {
            'mcqs': _mcqs,
            'theory': _theoryQuestions,
            'subjective': _subjectiveQuestions,
          },
        if (_references.isNotEmpty) 'references': _references,
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
        content: Value(jsonEncode(content)),
        teacherServerId: Value(_teacherId),
        schoolServerId: Value(_schoolId),
        isUnlocked: Value(_isUnlocked),
        status: Value(_lessonStatus),
        schemeOfWorkId: schemeOfWorkIdStr != null
            ? Value(schemeOfWorkIdStr)
            : const Value.absent(),
        weekNumber: Value(_week),
        term: termLabel != null ? Value(termLabel) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      );

      int id;

      // Dedup: check for existing lesson with same topic/subject/week/teacher/school
      Lesson? existing;
      final selectedDraft = _selectedDraftLessonId == null
          ? null
          : await db.lessonsDao.getById(_selectedDraftLessonId!);
      if (selectedDraft != null &&
          !selectedDraft.isDeleted &&
          selectedDraft.topic == topic &&
          selectedDraft.subject == _subject &&
          selectedDraft.classLevel == _classLevel &&
          selectedDraft.week == _week) {
        existing = selectedDraft;
      } else if (_teacherId != null && _schoolId != null) {
        existing = await db.lessonsDao.findByTopicSubjectWeekTeacher(
          topic: topic,
          subject: _subject,
          week: _week,
          teacherServerId: _teacherId!,
          schoolServerId: _schoolId!,
        );
      }
      if (existing != null) {
        // Update existing lesson
        id = existing.id;
        _selectedDraftLessonId = id;
        await db.lessonsDao.updateLesson(id, companion);

        // Queue UPDATE sync entry
        final lessonContent = jsonEncode(content);
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
          content: jsonEncode(content),
          teacherServerId: Value(_teacherId),
          schoolServerId: Value(_schoolId),
          isUnlocked: Value(_isUnlocked),
          status: Value(_lessonStatus),
          schemeOfWorkId: schemeOfWorkIdStr != null
              ? Value(schemeOfWorkIdStr)
              : const Value.absent(),
          weekNumber: Value(_week),
          term: termLabel != null ? Value(termLabel) : const Value.absent(),
        ),
      );
      // Remember the new lesson ID so undo and subsequent saves work.
      _lessonId = id;
      _selectedDraftLessonId = id;

      // Queue sync entry
      final lessonContent = jsonEncode(content);
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
    final newStatus = _lessonStatus == 'completed' ? 'generated' : 'completed';
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
      final now = DateTime.now();
      final logId = await db.progressLogsDao.insert(
        ProgressLogsCompanion.insert(
          eventType: newStatus == 'completed' ? 'lesson_completed' : 'lesson_reopened',
          lessonId: Value(_lessonId!),
          teacherId: Value(teacherLocalId),
          schoolId: Value(school?.localId ?? 0),
          eventDate: Value(now),
        ),
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': newStatus == 'completed' ? 'lesson_completed' : 'lesson_reopened',
          'event_date': now.toUtc().toIso8601String(),
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
      final now = DateTime.now();
      final logId = await db.progressLogsDao.insert(
        ProgressLogsCompanion.insert(
          eventType: 'lesson_completed',
          lessonId: Value(_lessonId!),
          teacherId: Value(teacherLocalId),
          schoolId: Value(school?.localId ?? 0),
          eventDate: Value(now),
        ),
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': 'lesson_completed',
          'event_date': now.toUtc().toIso8601String(),
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
        setState(() {
          _sourceMissing = !exists;
          // Prevention: release the dead scheme link in-memory so the lesson
          // becomes fully editable (topic field) and the error banner clears.
          // No DB row is modified until the user explicitly saves.
          if (!exists) {
            _schemeOfWorkLocalId = null;
            _isManualTopicEntry = true;
          }
        });
      }
    } catch (_) {}
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
      _mcqs = [];
      _theoryQuestions = [];
      _subjectiveQuestions = [];
      _droppedQuestionCount = 0;
      _references = [];
      _hasGenerated = false;
      _activeDiagramIndex = null;
      _activeCardKey = _LessonEditorCardKey.generate;
      _activeDeckIndex = 0;
      _topicEditable = true;
      _topicConfirmShown = false;
      _schemeOfWorkLocalId = null;
      _isManualTopicEntry = true;
    });
  }

  // ── Regeneration undo snapshot ──────────────────────────────────

  /// Snapshot all six content sections + questions + diagrams to a local
  /// JSON file so the teacher can undo a regeneration.
  Future<void> _snapshotForUndo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lesson_undo_${_lessonId}.json');
      final snapshot = <String, dynamic>{
        'objectives': _objectivesText,
        'vocabulary': _vocabularyText,
        'materials': _materialsText,
        'presentation': _presentationText,
        'assessment': _assessmentText,
        'homework': _homeworkText,
        'questions': {
          'mcqs': _mcqs,
          'theory': _theoryQuestions,
          'subjective': _subjectiveQuestions,
        },
        'diagrams': _diagramResults,
        'assessmentFormat': _assessmentFormat,
        'difficulty': _difficulty,
        'bloomsVerbs': _selectedBlooms.join(', '),
      };
      await file.writeAsString(jsonEncode(snapshot));
      _regenerationSnapshotPath = file.path;
    } catch (_) {
      // Snapshot failure is non-fatal — regeneration proceeds without undo.
    }
  }

  /// Restore the content from the undo snapshot, save the lesson, then
  /// delete the snapshot file.
  Future<void> _restoreFromUndo() async {
    if (_regenerationSnapshotPath == null) return;
    try {
      final file = File(_regenerationSnapshotPath!);
      if (!await file.exists()) return;
      final snapshot =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      setState(() {
        _objectivesText = snapshot['objectives'] as String? ?? '';
        _objectivesController.text = _objectivesText;
        _vocabularyText = snapshot['vocabulary'] as String? ?? '';
        _vocabularyController.text = _vocabularyText;
        _materialsText = snapshot['materials'] as String? ?? '';
        _materialsController.text = _materialsText;
        _presentationText = snapshot['presentation'] as String? ?? '';
        _presentationController.text = _presentationText;
        _parsePresentationSubSections();
        _assessmentText = snapshot['assessment'] as String? ?? '';
        _assessmentController.text = _assessmentText;
        _homeworkText = snapshot['homework'] as String? ?? '';
        _homeworkController.text = _homeworkText;
        _mcqs = _castQuestionList(
            (snapshot['questions'] as Map<String, dynamic>?)?['mcqs']);
        _theoryQuestions = _castQuestionList(
            (snapshot['questions'] as Map<String, dynamic>?)?['theory']);
        _subjectiveQuestions = _castQuestionList(
            (snapshot['questions'] as Map<String, dynamic>?)?['subjective']);
        _diagramResults = (snapshot['diagrams'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        _showRegenerationBanner = false;
        _previewRevision++;
      });
      await _saveLesson(notify: false);
      try {
        await file.delete();
      } catch (_) {}
      _regenerationSnapshotPath = null;
      if (mounted) {
        showInfoToast(context: context, message: 'Lesson restored from undo.');
      }
    } catch (_) {
      if (mounted) {
        showErrorToast(context: context, message: 'Undo failed.');
      }
    }
  }

  // ── Topic edit confirmation dialog ──────────────────────────
  Future<void> _showTopicEditDialog() async {
    if (_topicConfirmShown) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Topic?'),
        content: const Text(
          'This topic is used to generate the lesson. '
          'Editing it may affect the generated content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed to Edit'),
          ),
        ],
      ),
    );
    if (proceed == true) {
      setState(() {
        _topicEditable = true;
        _topicConfirmShown = true;
      });
    }
  }

  // ── Stage 2: Homework regeneration ──────────────────────────

  Future<void> _snapshotHomework() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/lesson_hw_undo_${_lessonId}.json');
      await file.writeAsString(jsonEncode({'homework': _homeworkText}));
      _homeworkSnapshotPath = file.path;
    } catch (_) {}
  }

  Future<void> _handleRegenerateHomework() async {
    if (_lessonId == null) return;
    setState(() => _isRegeneratingHomework = true);
    try {
      // Snapshot the current homework in memory before overwriting it. This
      // is the authoritative source for Undo; the file snapshot below is
      // only a persistence fallback.
      _homeworkBeforeRegeneration = _homeworkText;
      await _snapshotHomework();
      final db = ref.read(databaseProvider);
      final topic = _topicController.text.trim();
      final prompt = 'Regenerate only the Homework section for a lesson on '
          '"$topic" in $_subject, $_classLevel, Week $_week. '
          'Return a JSON object with a "homework" key containing the homework text.';
      final result = widget.generateCallback != null
          ? await widget.generateCallback!(prompt)
          : await AiService(db: db).generate(prompt);
      final raw = result['raw'] as Map<String, dynamic>? ?? result;
      final newHomework = raw['homework'] as String? ?? '';
      if (newHomework.isNotEmpty && mounted) {
        setState(() {
          _homeworkText = newHomework;
          _homeworkController.text = _homeworkText;
          _previewRevision++;
        });
        await _saveLesson(notify: false);
        // Show the persistent undo banner only after the regenerated
        // homework has actually been saved.
        if (mounted) {
          setState(() => _showHomeworkRegenerationBanner = true);
        }
      }
      if (mounted) {
        showInfoToast(context: context, message: 'Homework regenerated.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Homework regeneration failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isRegeneratingHomework = false);
    }
  }

  /// Restore the previous homework, save the lesson, then delete the
  /// snapshot. The in-memory snapshot ([_homeworkBeforeRegeneration]) is the
  /// authoritative source; the snapshot file is a secondary fallback. Called
  /// from the persistent undo banner.
  Future<void> _restoreHomeworkUndo() async {
    // Always hide the banner immediately, even when there is nothing to
    // restore.
    if (mounted) setState(() => _showHomeworkRegenerationBanner = false);

    // Restore from the in-memory snapshot first; fall back to the file.
    String? oldHomework = _homeworkBeforeRegeneration;
    if (oldHomework == null && _homeworkSnapshotPath != null) {
      try {
        final file = File(_homeworkSnapshotPath!);
        if (await file.exists()) {
          final snapshot =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          oldHomework = snapshot['homework'] as String? ?? '';
        }
      } catch (_) {
        oldHomework = null;
      }
    }

    if (oldHomework != null) {
      // Bind to a non-null local so the value is promoted inside the
      // setState closure (oldHomework is written in the catch block above,
      // which defeats flow analysis promotion for captured variables).
      final restoredText = oldHomework;
      if (mounted) {
        setState(() {
          _homeworkText = restoredText;
          _homeworkController.text = restoredText;
        });
        await _saveLesson(notify: false);
      }
      if (mounted) {
        showInfoToast(
            context: context, message: 'Homework restored from undo.');
      }
    } else if (mounted) {
      showInfoToast(context: context, message: 'Nothing to undo.');
    }

    // Delete the snapshot file (if any) and clear both snapshot sources.
    if (_homeworkSnapshotPath != null) {
      try {
        final file = File(_homeworkSnapshotPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
    _homeworkSnapshotPath = null;
    _homeworkBeforeRegeneration = null;
  }

  /// Deletes the homework undo snapshot file and clears the stored path.
  /// Called when the banner is dismissed; also covered by
  /// [_cleanupUndoSnapshot] on dispose / back navigation.
  void _deleteHomeworkSnapshot() {
    if (_homeworkSnapshotPath == null) return;
    try {
      final file = File(_homeworkSnapshotPath!);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
    _homeworkSnapshotPath = null;
  }


  // ── Entry screen skeleton for new blank lessons ──────────────

  Widget _buildEntryScreenSkeleton(ColorScheme cs, ThemeData theme) {
    final topicEmpty = _topicController.text.trim().isEmpty;
    final canCreate = !topicEmpty && _isOnline && !_isGenerating;
    String? disabledReason;
    if (topicEmpty) {
      disabledReason = null; // no reason text, just disabled
    } else if (!_isOnline) {
      disabledReason =
          "You\u2019re offline \u2014 connect to the internet to generate a lesson.";
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Text(
          'Lesson topic',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _topicController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'e.g., Introduction to Fractions',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            filled: true,
            fillColor: cs.surfaceBright,
          ),
          style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        // Create button
        SizedBox(
          width: double.infinity,
          height: AppTheme.touchTarget,
          child: FilledButton.icon(
            onPressed: canCreate ? _handleGenerate : null,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusXl),
              ),
            ),
            icon: _isGenerating
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
              _isGenerating ? 'Generating...' : 'Generate with AI',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              disabledReason,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
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
    _introController.dispose();
    _devController.dispose();
    _conclusionController.dispose();
    _undoController.dispose();
    _questionAutosaveTimer?.cancel();
    // Clean up undo snapshot file and banner on navigation away.
    _cleanupUndoSnapshot();
    // Also clear the in-memory homework undo snapshot.
    _homeworkBeforeRegeneration = null;
    super.dispose();
  }

  /// Delete the undo snapshot file if it exists and clear the banner.
  void _cleanupUndoSnapshot() {
    _showRegenerationBanner = false;
    if (_regenerationSnapshotPath != null) {
      try {
        final file = File(_regenerationSnapshotPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
      _regenerationSnapshotPath = null;
    }
    // Also clean up homework snapshot.
    if (_homeworkSnapshotPath != null) {
      try {
        final file = File(_homeworkSnapshotPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
      _homeworkSnapshotPath = null;
    }
    // Also clear the in-memory homework snapshot.
    _homeworkBeforeRegeneration = null;
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
    if (_isLoadingLesson) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final showDraftGenerateTab =
        widget.lessonId != null && _lessonStatus == 'draft' && !_hasGenerated;
    final showEntryScreen =
        widget.lessonId == null && !_hasGenerated && !_isGenerating;

    // Read-only summary of the stored structured assessment questions.
    final questionSummary =
        (_mcqs.isNotEmpty ||
                _theoryQuestions.isNotEmpty ||
                _subjectiveQuestions.isNotEmpty)
            ? '${_mcqs.length} MCQ · ${_theoryQuestions.length} '
                'Theory · ${_subjectiveQuestions.length} Subjective'
            : null;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _undoController.redo,
      },
      child: PopScope(
        canPop: true,
        // Clean up the undo snapshot file + banner whenever the route pops
        // (back button, system back, or explicit Navigator.pop). dispose()
        // cleanup alone is not enough — the banner state must be cleared
        // before the route is removed.
        onPopInvokedWithResult: (didPop, result) {
          _cleanupUndoSnapshot();
        },
        child: Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer (tablet+; never on Android) ────────
          if (PlatformHelper.shouldShowSidebar(context))
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
                  offlineCreditBalance: _offlineCreditBalance,
                  undoController: _undoController,
                ),

                // ── Tool Header (static, above scrollable) ─────────
                _ToolHeader(
                  cs: cs,
                  theme: theme,
                  onToggleSidebar: () => setState(
                      () => _editorSidebarOpen = !_editorSidebarOpen),
                  sidebarOpen: _editorSidebarOpen,
                  undoController: _undoController,
                ),

                // ── Scrollable content ─────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1024;
                      if (showDraftGenerateTab) {
                        return Padding(
                          padding: EdgeInsets.all(
                            isWide
                                ? AppTheme.spacingMarginTablet
                                : AppTheme.spacingMarginMobile,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _DraftGenerateTab(
                              cs: cs,
                              theme: theme,
                              options: _draftTopicOptions,
                              selectedOption: _selectedDraftTopic,
                              isLoadingOptions: _isLoadingDraftTopics,
                              isGenerating: _isGenerating,
                              isOnline: _isOnline,
                              onChanged: _handleDraftTopicChanged,
                              onGenerate: _handleDraftGenerate,
                              onCreateNewTopic: _handleCreateNewTopic,
                            ),
                          ),
                        );
                      }
                      return SingleChildScrollView(

                        physics: (Platform.isAndroid || Platform.isIOS)
                            ? const BouncingScrollPhysics()
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Entry screen for new blank lessons ──
                            // ── Legacy settings note ──────────────
                            if (showEntryScreen)
                              Padding(
                                padding: EdgeInsets.all(
                                  isWide
                                      ? AppTheme.spacingMarginTablet
                                      : AppTheme.spacingMarginMobile,
                                ),
                                child: _buildEntryScreenSkeleton(cs, theme),
                              ),
                            if (_legacySettingsNote != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: MaterialBanner(
                                  content: Text(_legacySettingsNote!),
                                  leading: Icon(Icons.info_outline,
                                      color: cs.primary, size: 20),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _legacySettingsNote = null),
                                      child: const Text('Dismiss'),
                                    ),
                                  ],
                                ),
                              ),
                            // ── Regeneration undo banner ──────────
                            if (_showRegenerationBanner && _lessonId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: MaterialBanner(
                                  content: const Text('Lesson regenerated.'),
                                  leading: Icon(Icons.check_circle_outline,
                                      color: cs.primary, size: 20),
                                  actions: [
                                    TextButton(
                                      onPressed: _restoreFromUndo,
                                      child: const Text('Undo'),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(
                                          () => _showRegenerationBanner = false),
                                      child: const Text('Dismiss'),
                                    ),
                                  ],
                                ),
                              ),
                            // ── Homework regeneration undo banner ──
                            if (_showHomeworkRegenerationBanner &&
                                _lessonId != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                                child: MaterialBanner(
                                  content: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Homework regenerated.'),
                                      const SizedBox(height: 4),
                                      Text(
                                        'New Homework: ${_homeworkText.length > 100 ? '${_homeworkText.substring(0, 100)}...' : _homeworkText}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  leading: Icon(Icons.check_circle_outline,
                                      color: cs.primary, size: 20),
                                  actions: [
                                    TextButton(
                                      onPressed: _restoreHomeworkUndo,
                                      child: const Text('Undo'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _showHomeworkRegenerationBanner =
                                              false;
                                        });
                                        // Dismissing also discards the
                                        // undo snapshot.
                                        _deleteHomeworkSnapshot();
                                      },
                                      child: const Text('Dismiss'),
                                    ),
                                  ],
                                ),
                              ),
                            if (!showEntryScreen && _schemeOfWorkLocalId != null)
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
                            if (!showEntryScreen && _sourceMissing)
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
                            if (!showEntryScreen)
                            Padding(
                              padding: EdgeInsets.all(
                                isWide
                                    ? AppTheme.spacingMarginTablet
                                    : AppTheme.spacingMarginMobile,
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // 1. Generate card
                                      _StitchCard(
                                        cs: cs,
                                        theme: theme,
                                        title: 'Generate',
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            GestureDetector(
                                              behavior: HitTestBehavior.translucent,
                                              onTap: _topicEditable ? null : () {
                                                  if (_topicConfirmShown) return;
                                                  final now = DateTime.now();
                                                  if (_lastTopicTap != null && now.difference(_lastTopicTap!) < const Duration(milliseconds: 400)) {
                                                    _lastTopicTap = null;
                                                    _showTopicEditDialog();
                                                  } else {
                                                    _lastTopicTap = now;
                                                  }
                                                },
                                              child: IgnorePointer(
                                                ignoring: !_topicEditable,
                                                child: TextField(
                                                  controller: _topicController,
                                                  readOnly: !_topicEditable,
                                                  textCapitalization: TextCapitalization.sentences,
                                                  decoration: InputDecoration(
                                                    hintText: 'e.g., Introduction to Fractions',
                                                    border: OutlineInputBorder(
                                                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                                                    ),
                                                    filled: true,
                                                    fillColor: cs.surfaceBright,
                                                    suffixIcon: _topicEditable
                                                        ? null
                                                        : const Icon(Icons.lock_outline, size: 18),
                                                  ),
                                                  style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface),
                                                  onChanged: (_) => setState(() {}),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            SizedBox(
                                              width: double.infinity,
                                              height: AppTheme.touchTarget,
                                              child: FilledButton.icon(
                                                onPressed: _isGenerating
                                                    ? null
                                                    : (_hasGenerated ? _handleRegenerate : _handleGenerate),
                                                style: FilledButton.styleFrom(
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                                                  ),
                                                ),
                                                icon: _isGenerating
                                                    ? SizedBox(
                                                        height: 22,
                                                        width: 22,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2.5,
                                                          color: cs.onPrimary,
                                                        ),
                                                      )
                                                    : Icon(_hasGenerated ? Icons.refresh_rounded : Icons.auto_awesome_rounded),
                                                label: Text(
                                                  _isGenerating
                                                      ? 'Generating...'
                                                      : (_hasGenerated ? 'Regenerate' : 'Generate with AI'),
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      // 2. Advanced Settings card (collapsible, default closed)
                                      Container(
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
                                            InkWell(
                                              onTap: () => setState(() =>
                                                  _advancedSettingsOpen = !_advancedSettingsOpen),
                                              borderRadius: BorderRadius.circular(8),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Advanced Settings',
                                                      style: theme.textTheme.titleMedium?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: cs.onSurface,
                                                      ),
                                                    ),
                                                  ),
                                                  Icon(
                                                    _advancedSettingsOpen
                                                        ? Icons.expand_less_rounded
                                                        : Icons.expand_more_rounded,
                                                    color: cs.onSurfaceVariant,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(vertical: 12),
                                              child: Divider(height: 1),
                                            ),
                                            AnimatedSize(
                                              duration: const Duration(milliseconds: 200),
                                              curve: Curves.easeInOut,
                                              alignment: Alignment.topCenter,
                                              clipBehavior: Clip.hardEdge,
                                              child: _advancedSettingsOpen
                                                  ? Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        CheckboxListTile(
                                                          dense: true,
                                                          contentPadding: EdgeInsets.zero,
                                                          visualDensity: VisualDensity.compact,
                                                          title: Text(
                                                            'Include diagram generation',
                                                            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                                                          ),
                                                          subtitle: Text(
                                                            _subscriptionTier.toLowerCase() == 'elite'
                                                                ? 'Automatically create the first suggested image after lesson generation'
                                                                : 'Upgrade to Elite to auto-generate diagrams',
                                                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                                          ),
                                                          value: _includeDiagrams,
                                                          onChanged: (value) => setState(() => _includeDiagrams = value ?? false),
                                                          controlAffinity: ListTileControlAffinity.leading,
                                                        ),
                                                        const SizedBox(height: 12),
                                                        _SegmentedControl(
                                                          cs: cs,
                                                          theme: theme,
                                                          label: 'Difficulty',
                                                          options: const ['Easy', 'Medium', 'Hard'],
                                                          value: _difficulty[0].toUpperCase() + _difficulty.substring(1),
                                                          onChanged: (v) => setState(() => _difficulty = v.toLowerCase()),
                                                        ),
                                                        const SizedBox(height: 20),
                                                        _BloomChipsSection(
                                                          cs: cs,
                                                          theme: theme,
                                                          bloomVerbs: _bloomVerbs,
                                                          selectedBlooms: _selectedBlooms,
                                                          onToggle: (verb) {
                                                            setState(() {
                                                              if (_selectedBlooms.contains(verb)) {
                                                                _selectedBlooms.remove(verb);
                                                              } else {
                                                                _selectedBlooms.add(verb);
                                                              }
                                                            });
                                                          },
                                                        ),
                                                      ],
                                                    )
                                                  : const SizedBox.shrink(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (_hasGenerated) ...[
                                        const SizedBox(height: 24),
                                        // 3. Preview Generated Content
                                        SizedBox(
                                          height: _hasGenerated && constraints.maxHeight.isFinite
                                              ? constraints.maxHeight
                                              : null,
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
                                            generatingDiagramIndex: _generatingDiagramIndex,
                                            onRegenerateDiagram: _handleDiagramAction,
                                            onActiveCardChanged: _onPreviewCardChanged,
                                            objectivesController: _objectivesController,
                                            vocabularyController: _vocabularyController,
                                            materialsController: _materialsController,
                                            presentationController: _presentationController,
                                            introController: _introController,
                                            devController: _devController,
                                            conclusionController: _conclusionController,
                                            assessmentController: _assessmentController,
                                            homeworkController: _homeworkController,
                                            questionSummary: questionSummary,
                                            reviewController: _reviewController,
                                            undoController: _undoController,
                                            onUnlock: _handleUnlock,
                                            onSave: _saveLesson,
                                            onDiscard: _discard,
                                            onRegenerate: _isUnlocked ? _handleRegenerate : null,
                                            onRegenerateReferences:
                                                _isUnlocked && _lessonId != null
                                                    ? _handleRegenerateReferences
                                                    : null,
                                            isRegeneratingReferences:
                                                _isRegeneratingReferences,
                                            referencesRegenerationError:
                                                _referencesRegenerationError,
                                            lessonStatus: _lessonStatus,
                                            onMarkCompleted: _isUnlocked ? _handleMarkCompleted : null,
                                            onToggleComplete: _isUnlocked ? _handleToggleComplete : null,
                                            onExportPdf: _hasGenerated ? _handleExportPdf : null,
                                            isExporting: _isExporting,
                                            assessmentFormat: _assessmentFormat,
                                            onAssessmentFormatChanged: (v) => setState(() => _assessmentFormat = v),
                                            mcqs: _mcqs,
                                            theoryQuestions: _theoryQuestions,
                                            subjectiveQuestions: _subjectiveQuestions,
                                            droppedQuestionCount: _droppedQuestionCount,
                                            onUpdateMcq: _updateMcq,
                                            onUpdateMcqOption: _updateMcqOption,
                                            onUpdateTheory: _updateTheory,
                                            onUpdateSubjective: _updateSubjective,
                                            onDeleteMcq: _deleteMcq,
                                            onDeleteTheory: _deleteTheory,
                                            onDeleteSubjective: _deleteSubjective,
                                            onShowUpgradeRequired: _showUpgradeRequiredDialog,
                                            onShowReferences: _showReferencesSheet,
                                            onRegenerateHomework: _handleRegenerateHomework,
                                            isRegeneratingHomework: _isRegeneratingHomework,
                                            visibleVocabulary: _visibleVocabulary,
                                            visibleMaterials: _visibleMaterials,
                                            visibleSuggestedImages: _visibleSuggestedImages,
                                            onShowVisibleSections: _showVisibleSectionsSheet,
                                            topicText: _topicController.text,
                                            subject: _subject,
                                            classLevel: _classLevel,
                                            week: _week,
                                            visibleReferences: _visibleReferences,
                                            references: _references,
                                            schemeReference: _buildSchemeReference(),
                                            onAddReference: (text) {
                                              setState(() {
                                                _references.add({'text': text, 'origin': 'teacher'});
                                              });
                                            },
                                            onRemoveReference: (index) {
                                              setState(() {
                                                if (index >= 0 && index < _references.length) {
                                                  _references.removeAt(index);
                                                }
                                              });
                                            },
                                            mcqCount: _mcqCount,
                                            theoryCount: _theoryCount,
                                            onMcqCountChanged: (v) => setState(() => _mcqCount = v),
                                            onTheoryCountChanged: (v) => setState(() => _theoryCount = v),
                                            includeDiagrams: _includeDiagrams,
                                            onIncludeDiagramsChanged: (v) => setState(() => _includeDiagrams = v),
                                          ),
                                        ),
                                     ],
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

                // ── Floating Action Area ───────────────────────────
                if (_hasGenerated)
                  _FloatingActionArea(
                    cs: cs,
                    theme: theme,
                    showReviewSection: _showReviewSection,
                    onToggleReview: _toggleReviewSectionForActiveCard,
                    reviewController: _reviewController,
                    isRegenerating: _isRegenerating,
                    onRegenerate: _isUnlocked &&
                            (_activeCardKey == _LessonEditorCardKey.lessonNotes ||
                                _activeCardKey == _LessonEditorCardKey.assessment ||
                                _activeCardKey == _LessonEditorCardKey.references ||
                                (_activeCardKey == _LessonEditorCardKey.diagrams &&
                                    _activeDiagramIndex != null))
                        ? () => _handleRegenerate(
                              skipConfirmation: true,
                              cardKey: _regenerationCardKey ?? _activeCardKey,
                              diagramIndex: _regenerationDiagramIndex ??
                                  _activeDiagramIndex,
                            )
                        : null,
                    lessonStatus: _lessonStatus,
                    onMarkCompleted: _isUnlocked && _lessonStatus != 'completed'
                        ? _handleMarkCompleted
                        : null,
                    onExportPdf: _handleExportPdf,
                    isExporting: _isExporting,
                    onShowVisibleSections: _showVisibleSectionsSheet,
                  ),

                // ── Bottom Navigation (mobile) ─────────────────────
                _BottomNavBar(cs: cs, theme: theme),
              ],
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════
// Data classes
// ═══════════════════════════════════════════════════════════════════════
class _DraftTopicOption {
  final int? lessonId;
  final String topic;
  final String subject;
  final String classLevel;
  final int week;
  final bool isCreateNew;

  const _DraftTopicOption({
    required this.lessonId,
    required this.topic,
    required this.subject,
    required this.classLevel,
    required this.week,
    this.isCreateNew = false,
  });

  const _DraftTopicOption.createNew()
      : lessonId = null,
        topic = '',
        subject = '',
        classLevel = '',
        week = 1,
        isCreateNew = true;

  factory _DraftTopicOption.fromLesson(Lesson lesson) {
    return _DraftTopicOption(
      lessonId: lesson.id,
      topic: lesson.topic,
      subject: lesson.subject,
      classLevel: lesson.classLevel,
      week: lesson.week,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _DraftTopicOption &&
        other.lessonId == lessonId &&
        other.isCreateNew == isCreateNew;
  }

  @override
  int get hashCode => Object.hash(lessonId, isCreateNew);
}

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
  final int offlineCreditBalance;
  final UndoHistoryController undoController;
  const _MobileHeader({
    required this.cs,
    required this.theme,
    required this.offlineCreditBalance,
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
                  '$offlineCreditBalance',
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
class _DraftGenerateTab extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final List<_DraftTopicOption> options;
  final _DraftTopicOption? selectedOption;
  final bool isLoadingOptions;
  final bool isGenerating;
  final bool isOnline;
  final ValueChanged<_DraftTopicOption?> onChanged;
  final VoidCallback onGenerate;
  final VoidCallback onCreateNewTopic;

  const _DraftGenerateTab({
    required this.cs,
    required this.theme,
    required this.options,
    required this.selectedOption,
    required this.isLoadingOptions,
    required this.isGenerating,
    required this.isOnline,
    required this.onChanged,
    required this.onGenerate,
    required this.onCreateNewTopic,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight.isFinite &&
            constraints.maxHeight < 560;
        final selected = options.contains(selectedOption) ? selectedOption : null;
        final items = [
          ...options.map(
            (option) => DropdownMenuItem<_DraftTopicOption>(
              value: option,
              child: Text(option.topic, overflow: TextOverflow.ellipsis),
            ),
          ),
          const DropdownMenuItem<_DraftTopicOption>(
            value: _DraftTopicOption.createNew(),
            child: Text('Create new topic'),
          ),
        ];
        final canGenerate = selected != null &&
            !selected.isCreateNew &&
            isOnline &&
            !isGenerating;

        return Container(
          constraints: const BoxConstraints(maxWidth: 760),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 32,
              vertical: compact ? 20 : 32,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: compact ? 30 : 40,
                  backgroundColor: cs.primary.withValues(alpha: 0.10),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: cs.primary,
                    size: compact ? 36 : 48,
                  ),
                ),
                SizedBox(height: compact ? 16 : 24),
                Text(
                  'Generate Lesson Content',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a draft topic and let AI create the lesson content for your students.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: compact ? 16 : 24),
                DropdownButtonFormField<_DraftTopicOption>(
                  value: selected,
                  items: items,
                  onChanged: isLoadingOptions
                      ? null
                      : (value) {
                          if (value?.isCreateNew == true) {
                            onCreateNewTopic();
                          } else {
                            onChanged(value);
                          }
                        },
                  decoration: InputDecoration(
                    labelText: 'LESSON TOPIC',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    ),
                    filled: true,
                    fillColor: cs.surfaceBright,
                  ),
                ),
                if (!isLoadingOptions && options.isEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No draft topics are available for this class and subject.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 16 : 24),
                SizedBox(
                  width: double.infinity,
                  height: AppTheme.touchTarget,
                  child: FilledButton.icon(
                    onPressed: canGenerate ? onGenerate : null,
                    icon: isGenerating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(isGenerating ? 'Generating...' : 'Create with AI'),
                  ),
                ),
                if (!isOnline) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Generation requires an internet connection.',
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// Preview Column (right side)
// ═══════════════════════════════════════════════════════════════════════
class _PreviewColumn extends StatefulWidget {
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
  final int? generatingDiagramIndex;
  final ValueChanged<int>? onRegenerateDiagram;
  final Future<void> Function()? onRegenerateReferences;
  final bool isRegeneratingReferences;
  final String? referencesRegenerationError;
  final ValueChanged<_LessonEditorCardKey>? onActiveCardChanged;
  final TextEditingController objectivesController;
  final TextEditingController vocabularyController;
  final TextEditingController materialsController;
  final TextEditingController presentationController;
  final TextEditingController introController;
  final TextEditingController devController;
  final TextEditingController conclusionController;
  final TextEditingController assessmentController;
  final TextEditingController homeworkController;
  final String? questionSummary;
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
  // Stage 2: Assessment
  final String assessmentFormat;
  final ValueChanged<String>? onAssessmentFormatChanged;
  final List<Map<String, dynamic>> mcqs;
  final List<Map<String, dynamic>> theoryQuestions;
  final List<Map<String, dynamic>> subjectiveQuestions;
  // Stage 3: question editing / deletion callbacks + dropped-count note
  final void Function(int index, String field, String value)? onUpdateMcq;
  final void Function(int index, String optionKey, String value)?
      onUpdateMcqOption;
  final void Function(int index, String field, String value)? onUpdateTheory;
  final void Function(int index, String field, String value)?
      onUpdateSubjective;
  final ValueChanged<int>? onDeleteMcq;
  final ValueChanged<int>? onDeleteTheory;
  final ValueChanged<int>? onDeleteSubjective;
  final int droppedQuestionCount;
  final VoidCallback? onShowUpgradeRequired;
  // Stage 3: References (opens the references bottom sheet; read-only
  // while the lesson is still locked)
  final VoidCallback? onShowReferences;
  // Stage 2: Homework
  final VoidCallback? onRegenerateHomework;
  final bool isRegeneratingHomework;
  // Stage 4: visible-section preferences + settings sheet opener
  final bool visibleVocabulary;
  final bool visibleMaterials;
  final bool visibleSuggestedImages;
  final VoidCallback? onShowVisibleSections;
  // 4-panel tab: context line data
  final String topicText;
  final String subject;
  final String classLevel;
  final int week;
  // 4-panel tab: references tab data
  final bool visibleReferences;
  final List<Map<String, dynamic>> references;
  final String? schemeReference;
  final ValueChanged<String>? onAddReference;
  final ValueChanged<int>? onRemoveReference;
  // 4-panel tab: assessment controls moved from Advanced Settings
  final int mcqCount;
  final int theoryCount;
  final ValueChanged<int>? onMcqCountChanged;
  final ValueChanged<int>? onTheoryCountChanged;
  // 4-panel tab: include diagram toggle moved from Advanced Settings
  final bool includeDiagrams;
  final ValueChanged<bool>? onIncludeDiagramsChanged;

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
    this.generatingDiagramIndex,
    this.onRegenerateDiagram,
    this.onRegenerateReferences,
    this.isRegeneratingReferences = false,
    this.referencesRegenerationError,
    this.onActiveCardChanged,
    required this.objectivesController,
    required this.vocabularyController,
    required this.materialsController,
    required this.presentationController,
    required this.introController,
    required this.devController,
    required this.conclusionController,
    required this.assessmentController,
    required this.homeworkController,
    this.questionSummary,
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
    // Stage 2: Assessment
    this.assessmentFormat = 'Both',
    this.onAssessmentFormatChanged,
    this.mcqs = const [],
    this.theoryQuestions = const [],
    this.subjectiveQuestions = const [],
    // Stage 3: question editing / deletion callbacks + dropped-count note
    this.onUpdateMcq,
    this.onUpdateMcqOption,
    this.onUpdateTheory,
    this.onUpdateSubjective,
    this.onDeleteMcq,
    this.onDeleteTheory,
    this.onDeleteSubjective,
    this.droppedQuestionCount = 0,
    this.onShowUpgradeRequired,
    // Stage 3: References
    this.onShowReferences,
    // Stage 2: Homework
    this.onRegenerateHomework,
    this.isRegeneratingHomework = false,
    // Stage 4: visible-section preferences + settings sheet opener
    this.visibleVocabulary = false,
    this.visibleMaterials = false,
    this.visibleSuggestedImages = false,
    this.onShowVisibleSections,
    // 4-panel tab: context line
    this.topicText = '',
    this.subject = '',
    this.classLevel = '',
    this.week = 1,
    // 4-panel tab: references
    this.visibleReferences = false,
    this.references = const [],
    this.schemeReference,
    this.onAddReference,
    this.onRemoveReference,
    // 4-panel tab: assessment controls
    this.mcqCount = 5,
    this.theoryCount = 5,
    this.onMcqCountChanged,
    this.onTheoryCountChanged,
    // 4-panel tab: diagram toggle
    this.includeDiagrams = false,
    this.onIncludeDiagramsChanged,
  });

  @override
  State<_PreviewColumn> createState() => _PreviewColumnState();
}

class _PreviewColumnState extends State<_PreviewColumn> {
  late PageController _deckController;
  final FocusNode _tabFocusNode = FocusNode();
  int _activeDeckIndex = 0;
  _LessonEditorCardKey _activeCardKey = _LessonEditorCardKey.lessonNotes;
  bool _tabAutoFocused = false;

  // Shorthand getters for ColorScheme and ThemeData from widget.
  ColorScheme get cs => widget.cs;
  ThemeData get theme => widget.theme;
  bool get visibleReferences => widget.visibleReferences;

  @override
  void initState() {
    super.initState();
    _deckController = PageController();
  }

  @override
  void didUpdateWidget(covariant _PreviewColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _deckController.dispose();
      _deckController = PageController();
      _activeDeckIndex = 0;
      _activeCardKey = _LessonEditorCardKey.lessonNotes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onActiveCardChanged?.call(_activeCardKey);
      });
      return;
    }

    final oldKeys = _cardKeys(oldWidget.visibleReferences);
    final newKeys = _cardKeys(widget.visibleReferences);
    final oldIndex = _activeDeckIndex < 0
        ? 0
        : (_activeDeckIndex >= oldKeys.length
            ? oldKeys.length - 1
            : _activeDeckIndex);
    final oldCardKey = oldKeys[oldIndex];
    final newIndex = newKeys.indexOf(oldCardKey);
    final clampedIndex = newIndex < 0
        ? (_activeDeckIndex >= newKeys.length ? newKeys.length - 1 : _activeDeckIndex)
        : newIndex;
    if (clampedIndex != _activeDeckIndex) {
      _activeDeckIndex = clampedIndex;
      _activeCardKey = newKeys[clampedIndex];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_deckController.hasClients) return;
        _deckController.jumpToPage(clampedIndex);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onActiveCardChanged?.call(_activeCardKey);
      });
    }
  }

  @override
  void dispose() {
    _deckController.dispose();
    _tabFocusNode.dispose();
    super.dispose();
  }

  bool _isTextFocused() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;
    final ctx = focus.context;
    if (ctx == null) return false;
    // Check if the focused element itself is an EditableText.
    if (ctx.widget is EditableText) return true;
    // Walk up the widget tree to check if an ancestor is an EditableText.
    bool found = false;
    ctx.visitAncestorElements((element) {
      if (element.widget is EditableText) {
        found = true;
        return false; // stop visiting
      }
      return true; // continue visiting
    });
    return found;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isTextFocused()) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_activeDeckIndex > 0) {
        _goToDeckSlide(_activeDeckIndex - 1);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_activeDeckIndex < _cardKeys(widget.visibleReferences).length - 1) {
        _goToDeckSlide(_activeDeckIndex + 1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  List<_LessonEditorCardKey> _cardKeys(bool includeReferences) => [
        _LessonEditorCardKey.lessonNotes,
        _LessonEditorCardKey.assessment,
        _LessonEditorCardKey.diagrams,
        if (includeReferences) _LessonEditorCardKey.references,
      ];

  List<String> get _tabLabels {
    return _cardKeys(widget.visibleReferences)
        .map((key) {
          switch (key) {
            case _LessonEditorCardKey.lessonNotes:
              return 'Lesson Note';
            case _LessonEditorCardKey.assessment:
              return 'Assessment';
            case _LessonEditorCardKey.diagrams:
              return 'Diagrams';
            case _LessonEditorCardKey.references:
              return 'References';
            case _LessonEditorCardKey.generate:
              return 'Generate';
          }
        })
        .toList();
  }

  void _goToDeckSlide(int index) {
    final keys = _cardKeys(widget.visibleReferences);
    if (index < 0 || index >= keys.length) return;
    setState(() {
      _activeDeckIndex = index;
      _activeCardKey = keys[index];
    });
    widget.onActiveCardChanged?.call(_activeCardKey);
    if (_deckController.hasClients) {
      _deckController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onTabTapped(int index) {
    _goToDeckSlide(index);
  }

  Widget _buildDeckArrow({required bool isPrevious}) {
    final keys = _cardKeys(widget.visibleReferences);
    final canMove = isPrevious
        ? _activeDeckIndex > 0
        : _activeDeckIndex < keys.length - 1;
    final label = isPrevious
        ? 'Previous lesson section'
        : 'Next lesson section';
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        tooltip: label,
        onPressed: canMove
            ? () => _goToDeckSlide(
                  isPrevious ? _activeDeckIndex - 1 : _activeDeckIndex + 1,
                )
            : null,
        icon: Icon(
          isPrevious ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        ),
        style: IconButton.styleFrom(
          minimumSize: const Size(AppTheme.touchTarget, AppTheme.touchTarget),
          foregroundColor: cs.onSurface,
          backgroundColor: cs.surfaceContainerLow,
        ),
      ),
    );
  }

  Widget _buildDeckIndicator() {
    final keys = _cardKeys(widget.visibleReferences);
    final total = keys.length;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Card ${_activeDeckIndex + 1} of $total',
          style: theme.textTheme.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(total, (index) {
            final selected = index == _activeDeckIndex;
            return Semantics(
              button: true,
              label: 'Go to ${_tabLabels[index]}',
              selected: selected,
              child: InkWell(
                onTap: () => _onTabTapped(index),
                borderRadius: BorderRadius.circular(24),
                child: SizedBox(
                  width: AppTheme.touchTarget,
                  height: AppTheme.touchTarget,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: selected ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: selected ? cs.primary : cs.outlineVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // Shorthand getters for field access in helper methods
  bool get hasGenerated => widget.hasGenerated;
  bool get isUnlocked => widget.isUnlocked;
  bool get isOnline => widget.isOnline;
  String get subscriptionTier => widget.subscriptionTier;
  int get remainingDailyPreviews => widget.remainingDailyPreviews;
  bool get isRegenerating => widget.isRegenerating;
  List<Map<String, dynamic>> get diagramResults => widget.diagramResults;
  bool get isGeneratingDiagrams => widget.isGeneratingDiagrams;
  int? get generatingDiagramIndex => widget.generatingDiagramIndex;
  ValueChanged<int>? get onRegenerateDiagram => widget.onRegenerateDiagram;
  Future<void> Function()? get onRegenerateReferences =>
      widget.onRegenerateReferences;
  bool get isRegeneratingReferences => widget.isRegeneratingReferences;
  String? get referencesRegenerationError =>
      widget.referencesRegenerationError;
  TextEditingController get objectivesController => widget.objectivesController;
  TextEditingController get vocabularyController => widget.vocabularyController;
  TextEditingController get materialsController => widget.materialsController;
  TextEditingController get presentationController => widget.presentationController;
  TextEditingController get introController => widget.introController;
  TextEditingController get devController => widget.devController;
  TextEditingController get conclusionController => widget.conclusionController;
  TextEditingController get assessmentController => widget.assessmentController;
  TextEditingController get homeworkController => widget.homeworkController;
  String? get questionSummary => widget.questionSummary;
  TextEditingController? get reviewController => widget.reviewController;
  UndoHistoryController get undoController => widget.undoController;
  VoidCallback get onUnlock => widget.onUnlock;
  VoidCallback get onSave => widget.onSave;
  VoidCallback? get onMarkCompleted => widget.onMarkCompleted;
  VoidCallback? get onRegenerate => widget.onRegenerate;
  String get lessonStatus => widget.lessonStatus;
  VoidCallback? get onToggleComplete => widget.onToggleComplete;
  VoidCallback? get onExportPdf => widget.onExportPdf;
  bool get isExporting => widget.isExporting;
  String get assessmentFormat => widget.assessmentFormat;
  ValueChanged<String>? get onAssessmentFormatChanged => widget.onAssessmentFormatChanged;
  List<Map<String, dynamic>> get mcqs => widget.mcqs;
  List<Map<String, dynamic>> get theoryQuestions => widget.theoryQuestions;
  List<Map<String, dynamic>> get subjectiveQuestions => widget.subjectiveQuestions;
  void Function(int, String, String)? get onUpdateMcq => widget.onUpdateMcq;
  void Function(int, String, String)? get onUpdateMcqOption => widget.onUpdateMcqOption;
  void Function(int, String, String)? get onUpdateTheory => widget.onUpdateTheory;
  void Function(int, String, String)? get onUpdateSubjective => widget.onUpdateSubjective;
  ValueChanged<int>? get onDeleteMcq => widget.onDeleteMcq;
  ValueChanged<int>? get onDeleteTheory => widget.onDeleteTheory;
  ValueChanged<int>? get onDeleteSubjective => widget.onDeleteSubjective;
  int get droppedQuestionCount => widget.droppedQuestionCount;
  VoidCallback? get onShowUpgradeRequired => widget.onShowUpgradeRequired;
  VoidCallback? get onShowReferences => widget.onShowReferences;
  VoidCallback? get onRegenerateHomework => widget.onRegenerateHomework;
  bool get isRegeneratingHomework => widget.isRegeneratingHomework;
  bool get visibleVocabulary => widget.visibleVocabulary;
  bool get visibleMaterials => widget.visibleMaterials;
  bool get visibleSuggestedImages => widget.visibleSuggestedImages;
  VoidCallback? get onShowVisibleSections => widget.onShowVisibleSections;

  @override
  Widget build(BuildContext context) {
    // Empty state (before generation)
    if (!widget.hasGenerated) {
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
                // Stage 4: choose which optional sections appear.
                if (onShowVisibleSections != null)
                  IconButton(
                    onPressed: onShowVisibleSections,
                    icon: const Icon(Icons.settings_rounded, size: 20),
                    color: cs.onSurfaceVariant,
                    tooltip: 'Visible sections',
                    visualDensity: VisualDensity.compact,
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
                    const SizedBox(height: 12),
                    if (onShowReferences != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: onShowReferences,
                          icon: const Icon(
                              Icons.menu_book_outlined, size: 16),
                          label: const Text('View References'),
                          style: TextButton.styleFrom(
                            foregroundColor: cs.tertiary,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
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

          // ── Numbered content tabs ─────────────────────────────
          if (hasGenerated)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Tab chips
                  Focus(
                    focusNode: _tabFocusNode,
                    onKeyEvent: _handleKeyEvent,
                    child: Builder(
                      builder: (ctx) {
                        if (!_tabAutoFocused) {
                          _tabAutoFocused = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) Focus.of(ctx).requestFocus();
                          });
                        }
                        return GestureDetector(
                          onTap: () => Focus.of(ctx).requestFocus(),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(_tabLabels.length, (i) {
                                final selected = _activeDeckIndex == i;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(_tabLabels[i]),
                                    selected: selected,
                                    onSelected: (_) => _onTabTapped(i),
                                    selectedColor: cs.primaryContainer,
                                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                      color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDeckIndicator(),
                  const SizedBox(height: 8),
                  // The viewport is bounded by the parent SizedBox. Each
                  // card keeps its own vertical scroll for long content.
                  Expanded(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 52),
                          child: PageView.builder(
                            controller: _deckController,
                            itemCount: _cardKeys(visibleReferences).length,
                            onPageChanged: (i) {
                              final keys = _cardKeys(visibleReferences);
                              if (i < 0 || i >= keys.length) return;
                              setState(() {
                                _activeDeckIndex = i;
                                _activeCardKey = keys[i];
                              });
                              widget.onActiveCardChanged?.call(_activeCardKey);
                            },
                            itemBuilder: (context, index) {
                              switch (_cardKeys(visibleReferences)[index]) {
                                case _LessonEditorCardKey.lessonNotes:
                                  return _buildLessonNoteTab(readOnly: !isUnlocked);
                                case _LessonEditorCardKey.assessment:
                                  return _buildAssessmentTab(readOnly: !isUnlocked);
                                case _LessonEditorCardKey.diagrams:
                                  return _buildDiagramsTab(readOnly: !isUnlocked);
                                case _LessonEditorCardKey.references:
                                  return _buildReferencesTab();
                                case _LessonEditorCardKey.generate:
                                  return const SizedBox.shrink();
                              }
                            },
                          ),
                        ),
                        // Equal insets and centered alignment keep both
                        // assessment arrows at the same vertical position.
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _buildDeckArrow(isPrevious: true),
                          ),
                        ),
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _buildDeckArrow(isPrevious: false),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),          // Save footer
          if (hasGenerated)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: onSave,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    minimumSize: const Size(100, AppTheme.touchTarget),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Open a fullscreen dialog with the diagram so the user can pinch-zoom
  /// and inspect it closely.
  void _openDiagramViewer(
    BuildContext context,
    String url, {
    String desc = '',
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with close button + description.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: Colors.black.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                    if (desc.isNotEmpty)
                      Expanded(
                        child: Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // The image, pinch-zoomable.
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 6.0,
                  boundaryMargin: const EdgeInsets.all(32),
                  child: Center(
                    child: DiagramImage(url: url),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders list-style content (Objectives, Vocabulary, Materials) as a
  /// bulleted list — each line prefixed with a bullet. Display-only: the
  /// stored text is never modified.
  Widget _renderBulletedList(String content) {
    final lines = content
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
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
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '\u2022 $line',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurface,
                height: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  /// Render markdown content using flutter_markdown_plus for proper
  /// headings, bold, italic, and list rendering.
  Widget _renderMarkdownContent(String content) {
    if (content.trim().isEmpty) {
      return Text(
        'No content yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurface,
          height: 1.5,
        ),
        h1: theme.textTheme.headlineSmall?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
        h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
        h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
        blockSpacing: 8,
        listBullet: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurface,
        ),
        listIndent: 24,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4-panel tab content builders
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLessonNoteTab({required bool readOnly}) {
    final cs = widget.cs;
    final theme = widget.theme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Topic / context summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.topicText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.subject} \u00b7 ${widget.classLevel} \u00b7 Week ${widget.week}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Objectives
          _buildCollapsibleSection(
            title: 'Objectives',
            controller: widget.objectivesController,
            readOnly: readOnly,
            undoController: readOnly ? null : widget.undoController,
          ),
          // Vocabulary (if visible)
          if (widget.visibleVocabulary)
            _buildCollapsibleSection(
              title: 'Vocabulary',
              controller: widget.vocabularyController,
              readOnly: readOnly,
              undoController: readOnly ? null : widget.undoController,
            ),
          // Materials (if visible)
          if (widget.visibleMaterials)
            _buildCollapsibleSection(
              title: 'Materials',
              controller: widget.materialsController,
              readOnly: readOnly,
              undoController: readOnly ? null : widget.undoController,
            ),
          // Presentation
          _buildPresentationSection(readOnly: readOnly),
        ],
      ),
    );
  }

  Widget _buildAssessmentTab({required bool readOnly}) {
    final cs = widget.cs;
    final theme = widget.theme;
    final tierBlocked = widget.subscriptionTier.toLowerCase() != 'standard' &&
        widget.subscriptionTier.toLowerCase() != 'elite';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tierBlocked) ...[
            // Tier-locked state
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lock_rounded, size: 18, color: cs.tertiary),
                      const SizedBox(width: 8),
                      Text(
                        'Assessment questions',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\u2022 Objective (MCQ) question generation',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u2022 Theory question generation',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u2022 Subjective question generation',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (widget.onShowUpgradeRequired != null)
                    SizedBox(
                      width: double.infinity,
                      height: AppTheme.touchTarget,
                      child: FilledButton.icon(
                        onPressed: widget.onShowUpgradeRequired,
                        icon: const Icon(Icons.upgrade_rounded, size: 18),
                        label: const Text('Upgrade Plan'),
                      ),
                    ),
                ],
              ),
            ),
          ] else if (readOnly) ...[
            _buildLockedPreviewSection(
              'Assessment',
              widget.assessmentController.text,
            ),
            _buildLockedPreviewSection(
              'Homework',
              widget.homeworkController.text,
            ),
          ] else ...[
            // Unlocked assessment controls
            // Format selector
            _SegmentedControl(
              cs: cs,
              theme: theme,
              label: 'Assessment Format',
              options: const ['MCQ', 'Theory', 'Both', 'Subjective'],
              value: widget.assessmentFormat,
              onChanged: widget.onAssessmentFormatChanged ?? (v) {},
            ),
            const SizedBox(height: 16),
            // Question counts
            Text(
              'Question Counts',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _NumberControl(
                    cs: cs,
                    theme: theme,
                    label: 'Objective',
                    value: widget.mcqCount,
                    onChanged: widget.onMcqCountChanged ?? (v) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberControl(
                    cs: cs,
                    theme: theme,
                    label: 'Theory',
                    value: widget.theoryCount,
                    onChanged: widget.onTheoryCountChanged ?? (v) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Dropped question note
            if (widget.droppedQuestionCount > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Some generated questions didn't meet quality checks and were skipped.",
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            // Assessment summary
            if (widget.questionSummary != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  widget.questionSummary!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            // Question cards
            ..._buildQuestionCards(),
            const SizedBox(height: 16),
            // Homework section
            _buildHomeworkSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagramsTab({required bool readOnly}) {
    return SingleChildScrollView(
      child: _buildSuggestedImagesSection(context, readOnly: readOnly),
    );
  }

  Widget _buildReferencesTab() {
    final cs = widget.cs;
    final theme = widget.theme;
    final readOnly = !widget.isUnlocked;
    // Build priority-ordered list
    final displayItems = <({String text, String origin, bool removable, int? storedIndex})>[];
    final schemeRef = widget.schemeReference?.trim() ?? '';
    if (schemeRef.isNotEmpty) {
      displayItems.add((text: schemeRef, origin: 'scheme', removable: false, storedIndex: null));
    }
    var storedIdx = 0;
    for (final item in widget.references) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final origin = (item['origin'] ?? 'ai').toString();
      displayItems.add((text: text, origin: origin, removable: !readOnly, storedIndex: storedIdx));
      storedIdx++;
    }
    String originLabel(String origin) {
      switch (origin) {
        case 'scheme': return 'From scheme of work';
        case 'teacher': return 'Teacher entered';
        case 'curated': return 'Curated';
        default: return 'AI-generated';
      }
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Source references used for this lesson.',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (!readOnly && onRegenerateReferences != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: isRegeneratingReferences
                    ? null
                    : () => onRegenerateReferences!.call(),
                icon: isRegeneratingReferences
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  isRegeneratingReferences
                      ? 'Regenerating...'
                      : 'Regenerate references',
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.touchTarget),
                ),
              ),
            ),
          ],
          if (referencesRegenerationError != null) ...[
            const SizedBox(height: 8),
            Text(
              referencesRegenerationError!,
              style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
            ),
          ],
          const SizedBox(height: 12),
          if (displayItems.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No source references available yet.',
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            )
          else
            ...displayItems.map((item) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.book_outlined, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.text, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              originLabel(item.origin),
                              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.removable)
                      IconButton(
                        onPressed: () {
                          if (item.storedIndex != null) widget.onRemoveReference?.call(item.storedIndex!);
                        },
                        icon: const Icon(Icons.close_rounded, size: 16),
                        color: cs.onSurfaceVariant,
                        tooltip: 'Remove reference',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              );
            }),
          if (!readOnly && widget.onAddReference != null) ...[
            const SizedBox(height: 12),
            _ReferencesAddField(
              cs: cs,
              theme: theme,
              onAdd: widget.onAddReference!,
            ),
          ],
        ],
      ),
    );
  }

  /// Presentation section with Introduction / Development / Conclusion
  /// rendered as labeled document sub-headings below the section header.
  Widget _buildPresentationSection({
    required bool readOnly,
  }) {
    final sections = [
      ('Introduction', introController),
      ('Development', devController),
      ('Conclusion', conclusionController),
    ];
    return _DocumentSection(
      title: 'Presentation',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sections.map((entry) {
          final (label, controller) = entry;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                if (readOnly)
                  _renderMarkdownContent(controller.text)
                else
                  _buildDocumentTextField(
                    controller,
                    undoController: undoController,
                    minLines: 3,
                    hintText: '$label content...',
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildQuestionCards() {
    final widgets = <Widget>[];
    // MCQs
    for (int i = 0; i < mcqs.length; i++) {
      widgets.add(McqQuestionCard(
        index: i,
        mcq: mcqs[i],
        cs: cs,
        theme: theme,
        undoController: undoController,
        onUpdateMcq: onUpdateMcq,
        onUpdateMcqOption: onUpdateMcqOption,
        onDelete: onDeleteMcq != null ? () => onDeleteMcq!(i) : null,
      ));
    }
    // Theory
    for (int i = 0; i < theoryQuestions.length; i++) {
      widgets.add(TheoryQuestionCard(
        index: i,
        question: theoryQuestions[i],
        cs: cs,
        theme: theme,
        undoController: undoController,
        onUpdateTheory: onUpdateTheory,
        onDelete: onDeleteTheory != null ? () => onDeleteTheory!(i) : null,
      ));
    }
    // Subjective
    for (int i = 0; i < subjectiveQuestions.length; i++) {
      widgets.add(TheoryQuestionCard(
        index: i,
        question: subjectiveQuestions[i],
        cs: cs,
        theme: theme,
        undoController: undoController,
        onUpdateTheory: onUpdateSubjective,
        onDelete: onDeleteSubjective != null
            ? () => onDeleteSubjective!(i)
            : null,
      ));
    }
    if (mcqs.isEmpty && theoryQuestions.isEmpty && subjectiveQuestions.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No questions generated yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  // ── Stage 2: Homework section ────────────────────────────────

  Widget _buildHomeworkSection() {
    return _DocumentSection(
      title: 'Homework',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (!isUnlocked)
          _renderMarkdownContent(homeworkController.text)
        else ...[
          _buildDocumentTextField(
            homeworkController,
            undoController: undoController,
            minLines: 4,
          ),
          const SizedBox(height: 8),
          if (onRegenerateHomework != null)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: isRegeneratingHomework ? null : onRegenerateHomework,
                icon: isRegeneratingHomework
                    ? SizedBox(
                        height: 16, width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                      )
                    : Icon(Icons.refresh_rounded, size: 16, color: cs.primary),
                label: Text(
                  isRegeneratingHomework ? 'Regenerating...' : 'Regenerate homework only',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
  }

  /// Suggested Images as a collapsible document section. Closed by default
  /// and only rendered when the teacher enabled the section in the "Visible
  /// sections" sheet. Shows an empty state when no images were generated.
  /// When [readOnly] is true (locked preview) the Generate Image action is
  /// hidden and the section is purely informational.
  Widget _buildSuggestedImagesSection(
    BuildContext context, {
    bool readOnly = false,
  }) {
    return _DocumentSection(
      title: 'Suggested Images',
      icon: Icons.image_outlined,
      initiallyExpanded: true,
      child: diagramResults.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No images generated yet.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...diagramResults.asMap().entries.map((entry) {
                  final index = entry.key;
                  final suggestion = entry.value;
                  final desc = suggestion['description'] as String? ?? '';
                  final imageUrl = suggestion['imageUrl'] as String?;
                  final error = suggestion['error'] as String?;
                  final isElite = subscriptionTier.toLowerCase() == 'elite';
                  final isGeneratingThisItem = generatingDiagramIndex == index;
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
                              'Suggestion ${index + 1}',
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
                            GestureDetector(
                              onTap: () => _openDiagramViewer(
                                context,
                                imageUrl,
                                desc: desc,
                              ),
                              child: DiagramImage(url: imageUrl),
                            )
                          else if (error != null)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline,
                                      size: 40, color: cs.error),
                                  const SizedBox(height: 8),
                                  Text(
                                    error,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: cs.error),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          // Generate button for this suggestion (hidden in
                          // the read-only locked preview).
                          if (!readOnly && onRegenerateDiagram != null) ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              child: SizedBox(
                                width: double.infinity,
                                height: 40,
                                child: isElite
                                    ? FilledButton.icon(
                                        onPressed: !isGeneratingDiagrams &&
                                                !isGeneratingThisItem
                                            ? () => onRegenerateDiagram!(index)
                                            : null,
                                        icon: isGeneratingThisItem
                                            ? SizedBox(
                                                height: 16,
                                                width: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: cs.onPrimary,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.auto_awesome_rounded,
                                                size: 16,
                                              ),
                                        label: Text(
                                          isGeneratingThisItem
                                              ? 'Generating Image ${index + 1}...'
                                              : imageUrl == null
                                                  ? 'Generate Image ${index + 1}'
                                                  : 'Regenerate Image ${index + 1}',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    : Tooltip(
                                        message:
                                            'Upgrade to Elite to generate images',
                                        child: FilledButton.icon(
                                          onPressed: null,
                                          icon: const Icon(
                                            Icons.lock_rounded,
                                            size: 16,
                                          ),
                                          label: Text(
                                            'Generate Image ${index + 1}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
    );
  }

  /// Collapsible section for the continuous document skeleton.
  Widget _buildCollapsibleSection({
    required String title,
    required TextEditingController controller,
    required bool readOnly,
    UndoHistoryController? undoController,
  }) {
    return _DocumentSection(
      title: title,
      child: readOnly
          ? (title == 'Objectives' ||
                    title == 'Vocabulary' ||
                    title == 'Materials'
                ? _renderBulletedList(controller.text)
                : _renderMarkdownContent(controller.text))
          : _buildDocumentTextField(
              controller,
              undoController: undoController,
              minLines: 4,
            ),
    );
  }

  /// Editable body field shared by the continuous document sections.
  Widget _buildDocumentTextField(
    TextEditingController controller, {
    UndoHistoryController? undoController,
    int minLines = 4,
    String? hintText,
  }) {
    return TextFormField(
      controller: controller,
      undoController: undoController,
      maxLines: null,
      minLines: minLines,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: cs.onSurface,
        height: 1.5,
      ),
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          borderSide: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        contentPadding: const EdgeInsets.all(12),
        hintText: hintText ?? 'No content yet.',
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  /// Full-content locked preview section (no truncation) styled like the
  /// continuous document. When [introController], [devController],
  /// [conclusionController] are provided for Presentation, the labeled
  /// sub-sections are rendered as document sub-headings.
  Widget _buildLockedPreviewSection(
    String title,
    String content, {
    TextEditingController? introController,
    TextEditingController? devController,
    TextEditingController? conclusionController,
  }) {
    // For Presentation, render labeled sub-sections.
    if (title == 'Presentation' &&
        introController != null &&
        devController != null &&
        conclusionController != null) {
      final subs = [
        ('Introduction', introController.text),
        ('Development', devController.text),
        ('Conclusion', conclusionController.text),
      ];
      final hasAny = subs.any((s) => s.$2.trim().isNotEmpty);
      if (!hasAny) return const SizedBox.shrink();
      return _DocumentSection(
        title: title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: subs.where((s) => s.$2.trim().isNotEmpty).map((entry) {
            final (label, text) = entry;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _renderMarkdownContent(text),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return _DocumentSection(
      title: title,
      child: (title == 'Objectives' ||
              title == 'Vocabulary' ||
              title == 'Materials')
          ? _renderBulletedList(content)
          : _renderMarkdownContent(content),
    );
  }

  String _buildUnlockLabel() {
    if (!isOnline) return 'Unlock Offline';
    if (subscriptionTier.toLowerCase() == 'elite') return 'Unlock \u2014 Unlimited previews';
    if (remainingDailyPreviews > 0) {
      return 'Unlock \u2014 $remainingDailyPreviews previews left';
    }
    return 'Unlock for 1 Offline Credit';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Collapsible document section (continuous lesson document)
// ═══════════════════════════════════════════════════════════════════════
/// A collapsible section header used to make the generated lesson read as
/// one continuous document instead of a stack of boxed cards: a tappable
/// header row (title + chevron) with plain body content below and only a
/// subtle horizontal divider separating it from the next section. Collapse
/// is animated with [AnimatedSize] — the body always keeps its intrinsic
/// height so it stays safe inside a scroll view.
class _DocumentSection extends StatefulWidget {
  final String title;
  final IconData? icon;
  final Widget child;
  final bool initiallyExpanded;

  const _DocumentSection({
    required this.title,
    this.icon,
    required this.child,
    this.initiallyExpanded = true,
  });

  @override
  State<_DocumentSection> createState() => _DocumentSectionState();
}

class _DocumentSectionState extends State<_DocumentSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tappable header — plain row, no border, no filled background.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // Collapsible body — animated but always finite intrinsic height.
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? widget.child
                : const SizedBox(width: double.infinity),
          ),
        ),
        // Subtle divider between document sections.
        const SizedBox(height: 12),
        Divider(
          height: 1,
          color: cs.outlineVariant.withValues(alpha: 0.4),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Visible sections bottom sheet (Stage 4)
// ═══════════════════════════════════════════════════════════════════════
/// Bottom sheet listing the optional lesson sections (Vocabulary, Materials,
/// Suggested Images / Diagrams) with per-section toggles. Choices are
/// persisted per teacher via SharedPreferences by the parent screen.
class _VisibleSectionsSheet extends StatefulWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool visibleVocabulary;
  final bool visibleMaterials;
  final bool visibleSuggestedImages;
  final ValueChanged<bool> onVocabularyChanged;
  final ValueChanged<bool> onMaterialsChanged;
  final ValueChanged<bool> onSuggestedImagesChanged;
  final bool visibleReferences;
  final ValueChanged<bool> onReferencesChanged;

  const _VisibleSectionsSheet({
    required this.cs,
    required this.theme,
    required this.visibleVocabulary,
    required this.visibleMaterials,
    required this.visibleSuggestedImages,
    required this.onVocabularyChanged,
    required this.onMaterialsChanged,
    required this.onSuggestedImagesChanged,
    this.visibleReferences = false,
    required this.onReferencesChanged,
  });

  @override
  State<_VisibleSectionsSheet> createState() => _VisibleSectionsSheetState();
}

class _VisibleSectionsSheetState extends State<_VisibleSectionsSheet> {
  late bool _vocabulary;
  late bool _materials;
  late bool _suggestedImages;
  late bool _references;

  @override
  void initState() {
    super.initState();
    _vocabulary = widget.visibleVocabulary;
    _materials = widget.visibleMaterials;
    _suggestedImages = widget.visibleSuggestedImages;
    _references = widget.visibleReferences;
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: widget.cs.onSurfaceVariant),
      title: Text(
        title,
        style: widget.theme.textTheme.bodyMedium?.copyWith(
          color: widget.cs.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final theme = widget.theme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Visible sections',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
                color: cs.onSurfaceVariant,
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Choose which sections appear in the lesson document.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _toggleTile(
            icon: Icons.menu_book_outlined,
            title: 'Vocabulary',
            value: _vocabulary,
            onChanged: (v) {
              setState(() => _vocabulary = v);
              widget.onVocabularyChanged(v);
            },
          ),
          _toggleTile(
            icon: Icons.inventory_2_outlined,
            title: 'Materials',
            value: _materials,
            onChanged: (v) {
              setState(() => _materials = v);
              widget.onMaterialsChanged(v);
            },
          ),
          _toggleTile(
            icon: Icons.image_outlined,
            title: 'Suggested Images / Diagrams',
            value: _suggestedImages,
            onChanged: (v) {
              setState(() => _suggestedImages = v);
              widget.onSuggestedImagesChanged(v);
            },
          ),
          _toggleTile(
            icon: Icons.menu_book_outlined,
            title: 'References',
            value: _references,
            onChanged: (v) {
              setState(() => _references = v);
              widget.onReferencesChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// References bottom sheet (Stage 3)
// ═══════════════════════════════════════════════════════════════════════
/// Bottom sheet listing the source references for a generated lesson, in
/// priority order: (1) linked scheme-of-work name + week, (2) the source
/// topic, (3) stored curated / AI-generated / teacher-entered references.
/// Every item carries an origin label ("From scheme of work" /
/// "Teacher entered" / "Curated" / "AI-generated"); references are
/// never shown unlabeled.
class _ReferencesSheet extends StatefulWidget {
  final ColorScheme cs;
  final ThemeData theme;

  /// Priority 1 — linked scheme-of-work name and week, or null.
  final String? schemeReference;

  /// Priority 2 — the source topic (manual entry), or null.
  final String? topicReference;

  /// Stored references ({text, origin}); origin is 'ai' or 'teacher'.
  final List<Map<String, dynamic>> references;

  /// When true (locked lesson), references can be viewed but not added or
  /// removed: the remove buttons and the add-reference input are hidden.
  final bool readOnly;

  final ValueChanged<String> onAddReference;
  final ValueChanged<int> onRemoveReference;

  const _ReferencesSheet({
    required this.cs,
    required this.theme,
    this.schemeReference,
    this.topicReference,
    required this.references,
    this.readOnly = false,
    required this.onAddReference,
    required this.onRemoveReference,
  });

  @override
  State<_ReferencesSheet> createState() => _ReferencesSheetState();
}

class _ReferencesSheetState extends State<_ReferencesSheet> {
  final _controller = TextEditingController();
  late final List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List<Map<String, dynamic>>.from(widget.references);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _originLabel(String origin) {
    switch (origin) {
      case 'scheme':
        return 'From scheme of work';
      case 'teacher':
        return 'Teacher entered';
      case 'curated':
        return 'Curated';
      default:
        return 'AI-generated';
    }
  }

  void _addReference() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onAddReference(text);
    setState(() {
      _items.add({'text': text, 'origin': 'teacher'});
      _controller.clear();
    });
  }

  void _removeReference(int storedIndex) {
    if (storedIndex < 0 || storedIndex >= _items.length) return;
    widget.onRemoveReference(storedIndex);
    setState(() {
      _items.removeAt(storedIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.cs;
    final theme = widget.theme;

    // Build the display list in priority order. Only stored items
    // (AI-generated / teacher-entered) are removable.
    final displayItems =
        <({String text, String origin, bool removable, int? storedIndex})>[];
    final schemeRef = widget.schemeReference?.trim() ?? '';
    final topicRef = widget.topicReference?.trim() ?? '';
    if (schemeRef.isNotEmpty) {
      displayItems.add(
          (text: schemeRef, origin: 'scheme', removable: false, storedIndex: null));
    }
    if (topicRef.isNotEmpty) {
      displayItems.add(
          (text: topicRef, origin: 'teacher', removable: false, storedIndex: null));
    }
    var storedIndex = 0;
    for (final item in _items) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final origin = (item['origin'] ?? 'ai').toString();
      displayItems.add((
        text: text,
        origin: origin,
        removable: !widget.readOnly,
        storedIndex: storedIndex,
      ));
      storedIndex++;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'References',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                  color: cs.onSurfaceVariant,
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Source references used for this lesson.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (displayItems.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Text(
                  'No source references provided.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...displayItems.map((item) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.book_outlined,
                          size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer
                                    .withValues(alpha: 0.6),
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusFull),
                              ),
                              child: Text(
                                _originLabel(item.origin),
                                style:
                                    theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onSecondaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (item.removable)
                        IconButton(
                          onPressed: () =>
                              _removeReference(item.storedIndex ?? -1),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          color: cs.onSurfaceVariant,
                          tooltip: 'Remove reference',
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                );
              }),
            if (!widget.readOnly) ...[
              const SizedBox(height: 12),
              // Add a teacher-entered reference
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Add a reference (e.g. textbook, source)…',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLg),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => _addReference(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _addReference,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'Add reference',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Inline references add field for the References tab
// ═══════════════════════════════════════════════════════════════════════
class _ReferencesAddField extends StatefulWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final ValueChanged<String> onAdd;
  const _ReferencesAddField({
    required this.cs,
    required this.theme,
    required this.onAdd,
  });

  @override
  State<_ReferencesAddField> createState() => _ReferencesAddFieldState();
}

class _ReferencesAddFieldState extends State<_ReferencesAddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Add a reference (e.g. textbook, source)...',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: widget.cs.outlineVariant),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onSubmitted: (value) {
              final text = value.trim();
              if (text.isNotEmpty) widget.onAdd(text);
              _controller.clear();
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: () {
            final text = _controller.text.trim();
            if (text.isNotEmpty) widget.onAdd(text);
            _controller.clear();
          },
          icon: const Icon(Icons.add_rounded),
          tooltip: 'Add reference',
        ),
      ],
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
                              Flexible(
                                child: Text(
                                  item.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSecondaryContainer,
                                    fontSize: 11,
                                  ),
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
// Floating Action Area (fixed at bottom)
// ═══════════════════════════════════════════════════════════════════════
class _FloatingActionArea extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool showReviewSection;
  final VoidCallback onToggleReview;
  final TextEditingController reviewController;
  final bool isRegenerating;
  final VoidCallback? onRegenerate;
  final VoidCallback? onMarkCompleted;
  final String lessonStatus;
  final VoidCallback? onExportPdf;
  final bool isExporting;
  final VoidCallback? onShowVisibleSections;

  const _FloatingActionArea({
    required this.cs,
    required this.theme,
    required this.showReviewSection,
    required this.onToggleReview,
    required this.reviewController,
    required this.isRegenerating,
    this.onRegenerate,
    this.onMarkCompleted,
    required this.lessonStatus,
    this.onExportPdf,
    this.isExporting = false,
    this.onShowVisibleSections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: cs.onSurface.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Expandable Review & Regenerate section
            if (showReviewSection)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
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
                        Expanded(
                          child: Text(
                            'Feedback for regeneration',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: onToggleReview,
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: 'Close feedback',
                          visualDensity: VisualDensity.compact,
                          color: cs.onPrimaryContainer,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reviewController,
                      maxLines: 2,
                      minLines: 1,
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
                        contentPadding: const EdgeInsets.all(10),
                        isDense: true,
                      ),
                      style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: FilledButton.icon(
                        onPressed: isRegenerating ? null : onRegenerate,
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.secondary,
                          foregroundColor: cs.onSecondary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                          ),
                        ),
                        icon: isRegenerating
                            ? SizedBox(
                                height: 18, width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: cs.onSecondary,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(
                          isRegenerating ? 'Regenerating...' : 'Regenerate',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Action buttons row
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                // Regenerate (opens review section)
                if (!showReviewSection && onRegenerate != null)
                  FilledButton.tonalIcon(
                    onPressed: onToggleReview,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Regenerate'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, AppTheme.touchTarget),
                    ),
                  ),
                // Mark Completed
                if (onMarkCompleted != null)
                  FilledButton.tonalIcon(
                    onPressed: onMarkCompleted,
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(lessonStatus == 'completed' ? 'Completed' : 'Mark Completed'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, AppTheme.touchTarget),
                    ),
                  ),
                // Export PDF
                if (onExportPdf != null)
                  OutlinedButton.icon(
                    onPressed: isExporting ? null : onExportPdf,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.tertiary,
                      side: BorderSide(color: cs.tertiary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, AppTheme.touchTarget),
                    ),
                    icon: isExporting
                        ? SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: cs.tertiary,
                            ),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: Text(isExporting ? 'Exporting...' : 'Export PDF'),
                  ),
                // Visible Sections
                if (onShowVisibleSections != null)
                  OutlinedButton.icon(
                    onPressed: onShowVisibleSections,
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('Visible Sections'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(0, AppTheme.touchTarget),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Number Control (for question counts)
// ═══════════════════════════════════════════════════════════════════════
class _NumberControl extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _NumberControl({
    required this.cs,
    required this.theme,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
          child: Row(
            children: [
              IconButton(
                onPressed: value > 1 ? () => onChanged(value - 1) : null,
                icon: const Icon(Icons.remove_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                onPressed: value < 20 ? () => onChanged(value + 1) : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(
                  foregroundColor: cs.onSurfaceVariant,
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
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Cognitive Objectives (Bloom\'s)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
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
