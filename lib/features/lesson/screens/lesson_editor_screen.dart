import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/settings/providers/text_scale_provider.dart';
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

ColorScheme _lessonEditorStitchColorScheme(ColorScheme base) {
  // Follow the app's active theme brightness so the editor switches between
  // a light and a dark palette instead of always rendering a fixed dark one.
  if (base.brightness == Brightness.light) {
    return base.copyWith(
      primary: const Color(0xFF4B53BA),
      onPrimary: const Color(0xFFFFFFFF),
      primaryContainer: const Color(0xFF8C94FF),
      onPrimaryContainer: const Color(0xFF1E258F),
      secondary: const Color(0xFF4B53BA),
      onSecondary: const Color(0xFFFFFFFF),
      secondaryContainer: const Color(0xFFE0E0FF),
      onSecondaryContainer: const Color(0xFF1E258F),
      tertiary: const Color(0xFF344EBF),
      onTertiary: const Color(0xFFFFFFFF),
      tertiaryContainer: const Color(0xFF5068D9),
      onTertiaryContainer: const Color(0xFFF8F6FF),
      error: const Color(0xFFBA1A1A),
      onError: const Color(0xFFFFFFFF),
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF93000A),
      surface: const Color(0xFFF8F9FF),
      onSurface: const Color(0xFF191C20),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF2F3F9),
      surfaceContainer: const Color(0xFFEDEDF3),
      surfaceContainerHigh: const Color(0xFFE7E8EE),
      surfaceContainerHighest: const Color(0xFFE1E2E8),
      surfaceBright: const Color(0xFFF8F9FF),
      surfaceDim: const Color(0xFFD9DAE0),

      onSurfaceVariant: const Color(0xFF414750),
      outline: const Color(0xFF727781),
      outlineVariant: const Color(0xFFC1C7D2),
      inverseSurface: const Color(0xFF2E3035),
      inversePrimary: const Color(0xFFA1C9FF),
      surfaceTint: const Color(0xFF4B53BA),
    );
  }
  return base.copyWith(
    primary: const Color(0xFFB8C3FF),
    onPrimary: const Color(0xFF0B267E),
    primaryContainer: const Color(0xFF8FA3FF),
    onPrimaryContainer: const Color(0xFF1E358B),
    secondary: const Color(0xFFD7BAFF),
    onSecondary: const Color(0xFF401578),
    secondaryContainer: const Color(0xFF5A3392),
    onSecondaryContainer: const Color(0xFFCBA8FF),
    tertiary: const Color(0xFF6BD2FF),
    onTertiary: const Color(0xFF003547),
    tertiaryContainer: const Color(0xFF00B6EA),
    onTertiaryContainer: const Color(0xFF004358),
    error: const Color(0xFFFFB4AB),
    onError: const Color(0xFF690005),
    errorContainer: const Color(0xFF93000A),
    onErrorContainer: const Color(0xFFFFDAD6),
    surface: const Color(0xFF131315),
    onSurface: const Color(0xFFE5E1E4),
    surfaceContainerLowest: const Color(0xFF0E0E10),
    surfaceContainerLow: const Color(0xFF1B1B1D),
    surfaceContainer: const Color(0xFF201F21),
    surfaceContainerHigh: const Color(0xFF2A2A2C),
    surfaceContainerHighest: const Color(0xFF353437),
    surfaceBright: const Color(0xFF39393B),
    surfaceDim: const Color(0xFF131315),
    onSurfaceVariant: const Color(0xFFC5C5D3),
    outline: const Color(0xFF8F909D),
    outlineVariant: const Color(0xFF454652),
    inverseSurface: const Color(0xFFE5E1E4),
    inversePrimary: const Color(0xFF4358AE),
    surfaceTint: const Color(0xFFB8C3FF),
  );
}

enum _LessonEditorCardKey {
  generate,
  lessonNotes,
  assessment,
  diagrams,
  references,
}

String _referenceStringValue(Map<String, dynamic> reference, String key) {
  final value = reference[key];
  if (value is String) return value.trim();
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .join(', ');
  }
  return value?.toString().trim() ?? '';
}

String _referenceMetadataText(Map<String, dynamic> reference) {
  final author = _referenceStringValue(reference, 'author').isNotEmpty
      ? _referenceStringValue(reference, 'author')
      : _referenceStringValue(reference, 'authors');
  final publisher = _referenceStringValue(reference, 'publisher');
  final edition = _referenceStringValue(reference, 'edition');
  final isbn = _referenceStringValue(reference, 'isbn');
  final searchQuery = _referenceStringValue(reference, 'searchQuery');
  final parts = <String>[];
  if (author.isNotEmpty) parts.add('Author: $author');
  if (publisher.isNotEmpty) parts.add('Publisher: $publisher');
  if (edition.isNotEmpty) parts.add(edition);
  if (isbn.isNotEmpty) parts.add('ISBN: $isbn');
  if (searchQuery.isNotEmpty) parts.add('Search: $searchQuery');
  return parts.join(' • ');
}

String _referenceRelatedTopicsText(Map<String, dynamic> reference) {
  final topics = _referenceStringValue(reference, 'relatedTopics');
  return topics.isEmpty ? '' : 'Related topics: $topics';
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

  // Stage 1: regeneration undo snapshot path.
  String? _regenerationSnapshotPath;

  // Stage 2: homework regeneration.
  bool _isRegeneratingHomework = false;
  String? _homeworkSnapshotPath;
  // Stage 2: in-memory snapshot of the pre-regeneration homework. Serves as
  // a reliable fallback for Undo when the snapshot file write fails.
  String? _homeworkBeforeRegeneration;

  bool _topicConfirmShown = false;

  // Stage 4: references visibility toggle (opt-in via Visible Sections sheet).
  bool _visibleReferences = true;

  // Font size is now a global setting via textScaleProvider.
  // The picker in the footer writes to the shared provider.

  // Floating action area: Review & Regenerate expandable state.
  bool _showReviewSection = false;
  bool _showLessonActions = false;
  _LessonEditorCardKey? _regenerationCardKey;
  int? _regenerationDiagramIndex;

  // Question count controls for generation.
  int _mcqCount = 5;
  int _theoryCount = 5;

  /// Scheme of Work state
  List<SchemeOfWorkData> _schemes = [];
  int? _schemeOfWorkLocalId;
  bool _isManualTopicEntry = true;

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
        if (_visibleSuggestedImages) _LessonEditorCardKey.diagrams,
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
    if (index < 0 || !mounted ||
        (_activeCardKey == cardKey && _activeDeckIndex == index)) {
      return;
    }
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
    if (_teacherId == null || _schoolId == null) {
      _ensureAuthInfoLoaded();
    }
    final teacherId = _teacherId;
    final schoolId = _schoolId;
    if (teacherId == null || schoolId == null) return;

    if (mounted) setState(() => _isLoadingDraftTopics = true);
    try {
      final db = ref.read(databaseProvider);
      final lessons = await db.lessonsDao.getAllForTeacher(teacherId, schoolId);
      final currentOption = lessons
          .where(
            (lesson) =>
                lesson.id == _lessonId &&
                lesson.subject == _subject &&
                lesson.classLevel == _classLevel,
          )
          .map(_DraftTopicOption.fromLesson)
          .firstOrNull;
      final options = lessons
          .where(
            (lesson) =>
                lesson.status == 'draft' &&
                !lesson.isUnlocked,
          )
          .map(_DraftTopicOption.fromLesson)
          .toList();
      if (currentOption != null &&
          !options.any((option) => option.lessonId == currentOption.lessonId)) {
        options.insert(0, currentOption);
      }
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
    });
  }

  void _handleDraftGenerate() {
    final selected = _selectedDraftTopic;
    if (selected != null && !selected.isCreateNew && selected.lessonId != null) {
      setState(() {
        _topicController.text = selected.topic;
        _week = selected.week;
        _selectedDraftLessonId = selected.lessonId;
        _lessonId = selected.lessonId;
      });
    } else if (widget.lessonId == null &&
        _topicController.text.trim().isEmpty) {
      return;
    }
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
      if (!mounted) return;
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
                message: 'Assessment questions are not included in your '
                    'current plan — upgrade to include them.',
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
        showInfoToast(
          context: context,
          message: 'References regenerated.',
          barrierDismissible: true,
          autoCloseDuration: const Duration(seconds: 2),
        );
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
        if (!questionsEnabled) {
          showInfoToast(
            context: context,
            message: 'Assessment questions are not included in your current '
                'plan — upgrade to include them.',
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

    if (!mounted) return;
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
        showSuccessToast(context: context, message: 'Lesson unlocked!');
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
        final parsedReference = <String, dynamic>{
          'text': text,
          'origin': origin,
        };
        for (final key in const [
          'author',
          'authors',
          'publisher',
          'edition',
          'isbn',
          'searchQuery',
        ]) {
          final value = map[key];
          if (value is String && value.trim().isNotEmpty || value is List) {
            parsedReference[key] = value;
          }
        }
        final relatedTopics = map['relatedTopics'];
        if (relatedTopics is List) {
          final topics = relatedTopics
              .map((topic) => topic.toString().trim())
              .where((topic) => topic.isNotEmpty)
              .toList();
          if (topics.isNotEmpty) parsedReference['relatedTopics'] = topics;
        }
        result.add(parsedReference);
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
    final cs = _lessonEditorStitchColorScheme(
      Theme.of(context).colorScheme,
    );
    final theme = ThemeData(
      colorScheme: cs,
      textTheme: GoogleFonts.workSansTextTheme(
        Theme.of(context).textTheme,
      ),
    );
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
                true;
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

  // ── Stage 5: Editor font size preference ────────────────────────
  // Now delegated to the global textScaleProvider.

  /// Ensures [_teacherId] and [_schoolId] are populated by reading
  /// [authProvider]. Called lazily by [_loadDraftTopicOptions] when
  /// auth info has not yet been loaded.
  void _ensureAuthInfoLoaded() {
    if (_teacherId != null && _schoolId != null) return;
    try {
      final authData = ref.read(authProvider);
      if (_teacherId == null &&
          authData.currentTeacher?.serverId != null) {
        _teacherId = authData.currentTeacher!.serverId;
      }
      if (_schoolId == null &&
          authData.currentSchool?.serverId != null) {
        _schoolId = authData.currentSchool!.serverId;
      }
    } catch (_) {
      // Ignore — will return early via null checks.
    }
  }

  void _showFontSizePicker() {
    final cs = _lessonEditorStitchColorScheme(
      Theme.of(context).colorScheme,
    );
    final theme = ThemeData(
      colorScheme: cs,
      textTheme: GoogleFonts.workSansTextTheme(
        Theme.of(context).textTheme,
      ),
    );
    // Map global text scale to the closest named size for the picker UI.
    final currentScale = ref.read(textScaleProvider);
    final currentSize = currentScale <= 0.875
        ? 'small'
        : currentScale >= 1.075
            ? 'large'
            : 'medium';
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _FontSizePickerSheet(
        cs: cs,
        theme: theme,
        currentSize: currentSize,
        onSelected: (size) {
          final double scale = switch (size) {
            'small' => 0.85,
            'large' => 1.15,
            _ => 1.0,
          };
          ref.read(textScaleProvider.notifier).setScale(scale);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  /// Opens the bottom sheet where the teacher picks which optional sections
  /// (Vocabulary, Materials, Suggested Images / Diagrams) appear in the
  /// lesson document.
  void _showVisibleSectionsSheet() {
    final cs = _lessonEditorStitchColorScheme(
      Theme.of(context).colorScheme,
    );
    final theme = ThemeData(
      colorScheme: cs,
      textTheme: GoogleFonts.workSansTextTheme(
        Theme.of(context).textTheme,
      ),
    );
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
          setState(() {
            _visibleSuggestedImages = v;
            _clampActiveDeckState();
          });
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
            'class_level': _classLevel,
            'week': _week,
            'topic': topic,
            'difficulty': _difficulty,
            'blooms_verbs': _selectedBlooms.join(', '),
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
          'class_level': _classLevel,
          'week': _week,
          'topic': topic,
          'difficulty': _difficulty,
          'blooms_verbs': _selectedBlooms.join(', '),
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
      if (mounted) {
        setState(() => _lessonStatus = newStatus);
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
      if (!mounted) return;
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

      if (!mounted) return;

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

      }
      if (mounted) {
        showSuccessToast(context: context, message: 'Homework regenerated.');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context: context, message: 'Homework regeneration failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isRegeneratingHomework = false);
    }
  }

  Widget _buildStitchLessonFab() {
    return Positioned(
      left: 0,
      right: 0,
      // The bottom navigation is outside this Stack, so adding a fixed
      // mobile offset here makes the menu float too high and worsens keyboard
      // and short-screen collisions.
      bottom: 0,
      child: Align(
        alignment: Alignment.bottomRight,
        child: _StitchLessonFab(
          cs: _lessonEditorStitchColorScheme(
            Theme.of(context).colorScheme,
          ),
          theme: ThemeData(
            colorScheme: _lessonEditorStitchColorScheme(
              Theme.of(context).colorScheme,
            ),
            textTheme: GoogleFonts.workSansTextTheme(
              Theme.of(context).textTheme,
            ),
          ),
          showReviewSection: _showReviewSection,
          showActionMenu: _showLessonActions,
          onToggleReview: _toggleReviewSectionForActiveCard,
          onToggleActions: () => setState(
            () => _showLessonActions = !_showLessonActions,
          ),
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
                    diagramIndex:
                        _regenerationDiagramIndex ?? _activeDiagramIndex,
                  )
              : null,
          lessonStatus: _lessonStatus,
          onMarkCompleted: _isUnlocked && _lessonStatus != 'completed'
              ? _handleMarkCompleted
              : null,
          onExportPdf: _handleExportPdf,
          isExporting: _isExporting,
          onShowVisibleSections: _showVisibleSectionsSheet,
          onShowFontSize: _showFontSizePicker,
          onSave: _saveLesson,
        ),
      ),
    );
  }

  Widget _buildPreviewColumn(
    ColorScheme cs,
    ThemeData theme,
    String? questionSummary, {
    required bool showGenerateSlide,
    required bool allowManualTopic,
  }) {
    return _PreviewColumn(
      key: ValueKey(_previewRevision),
      cs: cs,
      theme: theme,
      hasGenerated: _hasGenerated,
      showGenerateSlide: showGenerateSlide,
      isGenerating: _isGenerating,
      isUnlocked: _isUnlocked,
      isOnline: _isOnline,
      subscriptionTier: _subscriptionTier,
      remainingDailyPreviews: _remainingDailyPreviews,
      isRegenerating: _isRegenerating,
      assessmentAllowedTiers: ref
          .read(configServiceProvider)
          .assessmentGenerationAllowedTiers,
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
      onDiscard: _discard,
      onRegenerate: _isUnlocked ? _handleRegenerate : null,
      onRegenerateReferences:
          _isUnlocked && _lessonId != null ? _handleRegenerateReferences : null,
      isRegeneratingReferences: _isRegeneratingReferences,
      referencesRegenerationError: _referencesRegenerationError,
      lessonStatus: _lessonStatus,
      onMarkCompleted: _isUnlocked ? _handleMarkCompleted : null,
      onToggleComplete: _isUnlocked ? _handleToggleComplete : null,
      onExportPdf: _hasGenerated ? _handleExportPdf : null,
      isExporting: _isExporting,
      assessmentFormat: _assessmentFormat,
      onAssessmentFormatChanged: (v) =>
          setState(() => _assessmentFormat = v),
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
      onIncludeDiagramsChanged: (v) =>
          setState(() => _includeDiagrams = v),
      draftTopicOptions: _draftTopicOptions,
      selectedDraftTopic: _selectedDraftTopic,
      isLoadingDraftTopics: _isLoadingDraftTopics,
      onDraftTopicChanged: _handleDraftTopicChanged,
      onDraftGenerate: _handleDraftGenerate,
      onCreateNewTopic: _handleCreateNewTopic,
      allowManualTopic: allowManualTopic,
      topicController: _topicController,
      onTopicChanged: (_) => setState(() {}),
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
    final cs = _lessonEditorStitchColorScheme(
      Theme.of(context).colorScheme,
    );
    final theme = ThemeData(
      colorScheme: cs,
      textTheme: GoogleFonts.workSansTextTheme(
        Theme.of(context).textTheme,
      ),
    );
    // Every lesson without generated content starts in the deck's Generate
    // slide, including a brand-new lesson. Keeping this as the single entry
    // path avoids bringing back the legacy form while an AI request is active.
    final showDraftGenerateTab = !_hasGenerated;

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
          if (MediaQuery.sizeOf(context).width >= 768)
            _StitchLessonSidebar(
              cs: cs,
              theme: theme,
              teacherName: _teacherName,
              isOpen: _editorSidebarOpen,
              onToggle: () => setState(
                () => _editorSidebarOpen = !_editorSidebarOpen,
              ),
            ),

          // ── Main Content ────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Mobile Header ──────────────────────────────────
                _StitchLessonHeader(
                  cs: cs,
                  theme: theme,
                  undoController: _undoController,
                  contextLine: showDraftGenerateTab
                      ? [
                          _subject,
                          _classLevel,
                          'Week $_week',
                        ].where((value) => value.trim().isNotEmpty).join(' • ')
                      : null,
                  deckIndicatorTotal: _visibleDeckCardKeys.length,
                  deckIndicatorIndex: _activeDeckIndex,
                ),

                // ── Tool Header (static, above scrollable) ─────────
                // The responsive Stitch header above owns desktop and phone
                // header rendering.

                // ── Scrollable content ─────────────────────────────
                Expanded(
                  child: Stack(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1024;
                      if (showDraftGenerateTab) {
                        return Padding(
                          padding: EdgeInsets.all(
                            isWide
                                ? AppTheme.spacingMarginTablet
                                : AppTheme.spacingMarginMobile,
                          ),
                          child: SizedBox.expand(
                            child: _buildPreviewColumn(
                              cs,
                              theme,
                              questionSummary,
                              showGenerateSlide: true,
                              allowManualTopic: widget.lessonId == null,
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.all(
                          isWide
                              ? AppTheme.spacingMarginTablet
                              : AppTheme.spacingMarginMobile,
                        ),
                        child: SizedBox.expand(
                          child: _buildPreviewColumn(
                            cs,
                            theme,
                            questionSummary,
                            showGenerateSlide: false,
                            allowManualTopic: false,
                          ),
                        ),
                      );
                      /* Legacy editor layout retained below for reference
                         while the deck is the active generated-editor shell.
                      return Column(
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
                                        // 3. Generated lesson preview
                                        SizedBox(
                                          height: _hasGenerated && constraints.maxHeight.isFinite
                                              ? constraints.maxHeight
                                              : null,
                                          child: _buildPreviewColumn(
                                            cs,
                                            theme,
                                            questionSummary,
                                            showGenerateSlide: false,
                                          ),
                                        ),
                                     ],
                                    ],
                                  ),
                              ),
                            ),
                          ],
                        ); */
                          },
                        ),
                      // Scrim overlay when FAB popup is open (mobile only)
                      if (_hasGenerated &&
                          _isUnlocked &&
                          (_showLessonActions || _showReviewSection) &&
                          MediaQuery.sizeOf(context).width < 768)
                        GestureDetector(
                          onTap: () => setState(() {
                            _showLessonActions = false;
                            _showReviewSection = false;
                          }),
                          child: Container(color: Colors.black54),
                        ),
                      // FAB floats above everything
                      if (_hasGenerated &&
                          _isUnlocked &&
                          MediaQuery.sizeOf(context).width < 768 &&
                          _activeCardKey != _LessonEditorCardKey.generate)
                        _buildStitchLessonFab(),
                    ],
                  ),
                ),

                // ── Floating Action Area ───────────────────────────
                // ── Bottom Navigation (mobile) ─────────────────────
                if (_hasGenerated &&
                    _isUnlocked &&
                    MediaQuery.sizeOf(context).width >= 768 &&
                    _activeCardKey != _LessonEditorCardKey.generate)
                  _StitchLessonFooter(
                    cs: cs,
                    theme: theme,
                    onRegenerate: () => _handleRegenerate(
                      skipConfirmation: true,
                      cardKey: _regenerationCardKey ?? _activeCardKey,
                      diagramIndex:
                          _regenerationDiagramIndex ?? _activeDiagramIndex,
                    ),
                    onMarkCompleted: _lessonStatus != 'completed'
                        ? _handleMarkCompleted
                        : null,
                    lessonStatus: _lessonStatus,
                    onExportPdf: _handleExportPdf,
                    isExporting: _isExporting,
                    onShowVisibleSections: _showVisibleSectionsSheet,
                  ),
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
  final String term;
  final int week;
  final bool isCreateNew;

  const _DraftTopicOption({
    required this.lessonId,
    required this.topic,
    required this.subject,
    required this.classLevel,
    required this.term,
    required this.week,
  }) : isCreateNew = false;

  const _DraftTopicOption.createNew()
      : lessonId = null,
        topic = '',
        subject = '',
        classLevel = '',
        term = '',
        week = 1,
        isCreateNew = true;

  factory _DraftTopicOption.fromLesson(Lesson lesson) {
    return _DraftTopicOption(
      lessonId: lesson.id,
      topic: lesson.topic,
      subject: lesson.subject,
      classLevel: lesson.classLevel,
      term: lesson.term ?? '',
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
/// Fixed Stitch navigation rail used by the responsive Lesson Editor shell.
/// The older collapsible drawer remains available to other legacy callers,
/// but this screen uses the fixed rail so desktop and tablet share one layout.
class _StitchLessonSidebar extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String teacherName;
  final bool isOpen;
  final VoidCallback onToggle;

  const _StitchLessonSidebar({
    required this.cs,
    required this.theme,
    required this.teacherName,
    required this.isOpen,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 768) {
      return const SizedBox.shrink();
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: isOpen ? 256 : 72,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(right: BorderSide(color: cs.outlineVariant)),
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: EdgeInsets.fromLTRB(isOpen ? 24 : 12, 24, 12, 0),
                child: Row(
                  mainAxisAlignment: isOpen
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    Icon(Icons.school_rounded, color: cs.primary, size: 28),
                    if (isOpen) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ClassAI', style: theme.textTheme.titleLarge?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w700,
                            )),
                            Text('Nigerian Academic Partner', style: theme.textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            )),
                          ],
                        ),
                      ),
                    ],
                    Icon(
                      isOpen ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 48),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _LessonEditorScreenState._navItems.map((item) {
                  final foreground = item.isActive
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Semantics(
                      button: true,
                      selected: item.isActive,
                      label: item.label,
                      child: Tooltip(
                        message: item.label,
                        child: Material(
                          color: item.isActive
                              ? cs.secondaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _navigateTo(context, item.label),
                            borderRadius: BorderRadius.circular(16),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                minHeight: AppTheme.touchTarget,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(item.icon, size: 22, color: foreground),
                                    if (isOpen) ...[
                                      const SizedBox(width: 16),
                                      Text(
                                        item.label,
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: foreground,
                                          fontWeight: item.isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              height: 1,
              color: cs.outlineVariant,
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(isOpen ? 24 : 12, 20, isOpen ? 24 : 12, 24),
              child: isOpen
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: cs.surfaceContainerHigh,
                          child: Text(
                            _initials(teacherName),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            teacherName.trim().isEmpty ? 'Teacher' : teacherName,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: cs.surfaceContainerHigh,
                        child: Text(
                          _initials(teacherName),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final values = parts.take(2).map((part) => part[0].toUpperCase()).join();
    return values.isEmpty ? 'T' : values;
  }

  void _navigateTo(BuildContext context, String label) {
    switch (label) {
      case 'Home':
        context.go('/');
        break;
      case 'Lessons':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/lessons');
        });
        break;
      case 'Exams':
        context.go('/exams');
        break;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Mobile Header
// ═══════════════════════════════════════════════════════════════════════
class _StitchLessonHeader extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final UndoHistoryController undoController;
  final String? contextLine;
  final int? deckIndicatorIndex;
  final int? deckIndicatorTotal;

  const _StitchLessonHeader({
    required this.cs,
    required this.theme,
    required this.undoController,
    this.contextLine,
    this.deckIndicatorIndex,
    this.deckIndicatorTotal,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 768;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 32,
            compact ? 8 : 16,
            compact ? 12 : 32,
            compact ? 8 : 16,
          ),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Back',
                child: compact
                    ? IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: 'Back',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(
                            AppTheme.touchTarget,
                            AppTheme.touchTarget,
                          ),
                          foregroundColor: cs.onSurfaceVariant,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(
                            AppTheme.touchTarget,
                            AppTheme.touchTarget,
                          ),
                          foregroundColor: cs.onSurfaceVariant,
                        ),
                      ),
              ),
              SizedBox(width: compact ? 4 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lesson Editor',
                      overflow: TextOverflow.ellipsis,
                      style: (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineLarge)
                          ?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (contextLine != null && contextLine!.isNotEmpty)
                      Text(
                        contextLine!,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (!compact &&
                  deckIndicatorTotal != null &&
                  deckIndicatorTotal! > 0) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(deckIndicatorTotal!, (index) {
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == deckIndicatorIndex
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                ),
                const SizedBox(width: 20),
              ],
              if (!compact) _buildHistoryButtons(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryButtons() {
    return ValueListenableBuilder<UndoHistoryValue>(
      valueListenable: undoController,
      builder: (context, value, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: true,
              enabled: value.canUndo,
              label: 'Undo',
              child: IconButton(
                onPressed: value.canUndo ? undoController.undo : null,
                icon: const Icon(Icons.undo_rounded),
                tooltip: 'Undo (Ctrl+Z)',
                style: IconButton.styleFrom(
                  minimumSize: const Size(
                    AppTheme.touchTarget,
                    AppTheme.touchTarget,
                  ),
                  foregroundColor: value.canUndo ? cs.primary : cs.onSurfaceVariant,
                  disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
            Semantics(
              button: true,
              enabled: value.canRedo,
              label: 'Redo',
              child: IconButton(
                onPressed: value.canRedo ? undoController.redo : null,
                icon: const Icon(Icons.redo_rounded),
                tooltip: 'Redo (Ctrl+Shift+Z)',
                style: IconButton.styleFrom(
                  minimumSize: const Size(
                    AppTheme.touchTarget,
                    AppTheme.touchTarget,
                  ),
                  foregroundColor: value.canRedo ? cs.primary : cs.onSurfaceVariant,
                  disabledForegroundColor: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DraftGenerateTab extends StatefulWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String subject;
  final String classLevel;
  final List<_DraftTopicOption> options;
  final _DraftTopicOption? selectedOption;
  final bool isLoadingOptions;
  final bool isGenerating;
  final bool isOnline;
  final ValueChanged<_DraftTopicOption?> onChanged;
  final VoidCallback onGenerate;
  final VoidCallback onCreateNewTopic;
  final bool allowManualTopic;
  final TextEditingController? topicController;
  final ValueChanged<String>? onTopicChanged;

  const _DraftGenerateTab({
    required this.cs,
    required this.theme,
    required this.subject,
    required this.classLevel,
    required this.options,
    required this.selectedOption,
    required this.isLoadingOptions,
    required this.isGenerating,
    required this.isOnline,
    required this.onChanged,
    required this.onGenerate,
    required this.onCreateNewTopic,
    this.allowManualTopic = false,
    this.topicController,
    this.onTopicChanged,
  });

  @override
  State<_DraftGenerateTab> createState() => _DraftGenerateTabState();
}

class _DraftGenerateTabState extends State<_DraftGenerateTab> {
  String _sortBy = 'classLevel';

  List<_DraftTopicOption> get _sortedOptions {
    final list = List<_DraftTopicOption>.of(widget.options);
    switch (_sortBy) {
      case 'classLevel':
        list.sort((a, b) => a.classLevel.compareTo(b.classLevel));
        break;
      case 'week':
        list.sort((a, b) => a.week.compareTo(b.week));
        break;
    }
    return list;
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Sort by',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.school_rounded),
              title: const Text('Class level'),
              trailing: _sortBy == 'classLevel'
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'classLevel');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_rounded),
              title: const Text('Week number'),
              trailing: _sortBy == 'week'
                  ? const Icon(Icons.check, size: 20)
                  : null,
              onTap: () {
                setState(() => _sortBy = 'week');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDraftTopicSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final sorted = List<_DraftTopicOption>.of(widget.options);
            switch (_sortBy) {
              case 'classLevel':
                sorted.sort((a, b) => a.classLevel.compareTo(b.classLevel));
                break;
              case 'week':
                sorted.sort((a, b) => a.week.compareTo(b.week));
                break;
            }
            final cs = Theme.of(context).colorScheme;
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'All draft topics',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('Class'),
                            selected: _sortBy == 'classLevel',
                            onSelected: (_) {
                              setState(() => _sortBy = 'classLevel');
                              setSheetState(() {});
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Week'),
                            selected: _sortBy == 'week',
                            onSelected: (_) {
                              setState(() => _sortBy = 'week');
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: sorted.length,
                        itemBuilder: (context, index) {
                          final option = sorted[index];
                          return _DraftTopicCard(
                            option: option,
                            selected: widget.selectedOption?.lessonId == option.lessonId,
                            onTap: () {
                              widget.onChanged(option);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight.isFinite &&
            constraints.maxHeight < 560;
        final selected = widget.options.contains(widget.selectedOption) ? widget.selectedOption : null;
        final items = [
          ...widget.options.map(
            (option) => DropdownMenuItem<_DraftTopicOption>(
              value: option,
              child: Text(
                'Week ${option.week} • ${option.topic}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const DropdownMenuItem<_DraftTopicOption>(
            value: _DraftTopicOption.createNew(),
            child: Text('Create new topic'),
          ),
        ];
        final manualTopic = widget.topicController?.text.trim() ?? '';
        final canGenerate = ((selected != null && !selected.isCreateNew) ||
                (widget.allowManualTopic && manualTopic.isNotEmpty)) &&
            widget.isOnline &&
            !widget.isGenerating;

        return Center(
          child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          decoration: BoxDecoration(
            color: widget.cs.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: widget.cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 20 : 32,
              vertical: compact ? 20 : 32,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                CircleAvatar(
                  radius: compact ? 30 : 56,
                  backgroundColor: widget.cs.primary.withValues(alpha: 0.10),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: widget.cs.primary,
                    size: compact ? 36 : 64,
                  ),
                ),
                SizedBox(height: compact ? 16 : 32),
                Text(
                  'Generate Lesson Content',
                  textAlign: TextAlign.center,
                  style: widget.theme.textTheme.headlineLarge?.copyWith(
                    fontSize: compact ? 28 : 40,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: widget.cs.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose a draft topic and let AI create the lesson content for your students.',
                  textAlign: TextAlign.center,
                  style: widget.theme.textTheme.bodyLarge?.copyWith(
                    fontSize: compact ? 16 : 18,
                    height: 1.5,
                    color: widget.cs.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: compact ? 16 : 32),
                if (widget.options.isEmpty)
                  Text(
                    'No draft topics available yet.',
                    style: widget.theme.textTheme.bodyMedium?.copyWith(
                      color: widget.cs.onSurfaceVariant,
                    ),
                  )
                else ...[
                  if (selected == null && widget.options.length > 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _showSortSheet,
                        icon: const Icon(Icons.sort_rounded, size: 18),
                        label: const Text('Sort'),
                      ),
                    ),
                  if (selected != null)
                    _DraftTopicCard(
                      option: selected!,
                      selected: true,
                      onTap: () {},
                    )
                  else
                    for (final option in _sortedOptions.take(3))
                      _DraftTopicCard(
                        option: option,
                        selected: false,
                        onTap: () => widget.onChanged(option),
                      ),
                  if (widget.options.length > 3)
                    Center(
                      child: TextButton.icon(
                        onPressed: _showDraftTopicSheet,
                        icon: const Icon(Icons.expand_more_rounded),
                        label: const Text('More drafts'),
                      ),
                    ),
                ],
                if (widget.allowManualTopic && widget.options.isEmpty && selected == null)
                  TextField(
                    controller: widget.topicController,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: widget.onTopicChanged,
                    decoration: InputDecoration(
                      labelText: 'LESSON TOPIC',
                      hintText: 'e.g. Introduction to Fractions',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      ),
                      filled: true,
                      fillColor: widget.cs.surfaceBright,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: compact ? 16 : 24,
                        vertical: compact ? 16 : 24,
                      ),
                    ),
                  ),
                SizedBox(height: compact ? 16 : 32),
                SizedBox(
                  width: double.infinity,
                  height: compact ? 48 : 64,
                  child: FilledButton.icon(
                    onPressed: canGenerate ? widget.onGenerate : null,
                    icon: widget.isGenerating
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: widget.cs.onPrimary,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(widget.isGenerating ? 'Generating...' : 'Create with AI'),
                  ),
                ),
                if (!widget.isOnline) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Generation requires an internet connection.',
                    style: widget.theme.textTheme.bodySmall?.copyWith(color: widget.cs.error),
                  ),
                ],
              ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }
}

class _DraftTopicCard extends StatelessWidget {
  final _DraftTopicOption option;
  final bool selected;
  final VoidCallback onTap;

  const _DraftTopicCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                option.subject,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${option.classLevel} · ${option.term} · Week ${option.week}',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                option.topic,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// Preview Column (right side)
// ═══════════════════════════════════════════════════════════════════════
class _PreviewColumn extends StatefulWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool hasGenerated;
  final bool showGenerateSlide;
  final bool isGenerating;
  final bool isUnlocked;
  final bool isOnline;
  final String subscriptionTier;
  final List<String> assessmentAllowedTiers;
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
  final List<_DraftTopicOption> draftTopicOptions;
  final _DraftTopicOption? selectedDraftTopic;
  final bool isLoadingDraftTopics;
  final ValueChanged<_DraftTopicOption?>? onDraftTopicChanged;
  final VoidCallback? onDraftGenerate;
  final VoidCallback? onCreateNewTopic;
  final bool allowManualTopic;
  final TextEditingController topicController;
  final ValueChanged<String>? onTopicChanged;

  const _PreviewColumn({
    super.key,
    required this.cs,
    required this.theme,
    required this.hasGenerated,
    this.showGenerateSlide = false,
    this.isGenerating = false,
    required this.isUnlocked,
    required this.isOnline,
    required this.subscriptionTier,
    required this.assessmentAllowedTiers,
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
    this.draftTopicOptions = const [],
    this.selectedDraftTopic,
    this.isLoadingDraftTopics = false,
    this.onDraftTopicChanged,
    this.onDraftGenerate,
    this.onCreateNewTopic,
    this.allowManualTopic = false,
    required this.topicController,
    this.onTopicChanged,
  });

  @override
  State<_PreviewColumn> createState() => _PreviewColumnState();
}

class _PreviewColumnState extends State<_PreviewColumn> {
  late PageController _deckController;
  final FocusNode _tabFocusNode = FocusNode();
  int _activeDeckIndex = 0;
  _LessonEditorCardKey _activeCardKey = _LessonEditorCardKey.lessonNotes;

  // Shorthand getters for ColorScheme and ThemeData from widget.
  ColorScheme get cs => widget.cs;
  ThemeData get theme => widget.theme;
  bool get visibleReferences => widget.visibleReferences;

  @override
  void initState() {
    super.initState();
    _deckController = PageController(keepPage: true);
    _activeCardKey = widget.showGenerateSlide
        ? _LessonEditorCardKey.generate
        : _LessonEditorCardKey.lessonNotes;
  }

  @override
  void didUpdateWidget(covariant _PreviewColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _deckController.dispose();
      _deckController = PageController(keepPage: true);
      _activeDeckIndex = 0;
      _activeCardKey = widget.showGenerateSlide
          ? _LessonEditorCardKey.generate
          : _LessonEditorCardKey.lessonNotes;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onActiveCardChanged?.call(_activeCardKey);
      });
      return;
    }

    final oldKeys = _cardKeys(
      oldWidget.visibleReferences,
      oldWidget.visibleSuggestedImages,
    );
    final newKeys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    );
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
    if (clampedIndex != _activeDeckIndex ||
        _activeCardKey != newKeys[clampedIndex]) {
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

  List<_LessonEditorCardKey> _cardKeys(
    bool includeReferences,
    bool includeSuggestedImages,
  ) => [
        if (widget.showGenerateSlide) _LessonEditorCardKey.generate,
        _LessonEditorCardKey.lessonNotes,
        _LessonEditorCardKey.assessment,
        if (includeSuggestedImages) _LessonEditorCardKey.diagrams,
        if (includeReferences) _LessonEditorCardKey.references,
      ];

  void _setActiveDeckSlide(int index) {
    final keys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    );
    if (index < 0 || index >= keys.length) return;
    if (index == _activeDeckIndex && _activeCardKey == keys[index]) return;
    setState(() {
      _activeDeckIndex = index;
      _activeCardKey = keys[index];
    });
    widget.onActiveCardChanged?.call(_activeCardKey);
  }

  void _goToDeckSlide(int index) {
    final keys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    );
    if (index < 0 || index >= keys.length || index == _activeDeckIndex) {
      return;
    }
    if (_deckController.hasClients) {
      _deckController.animateToPage(
        index,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    } else {
      _setActiveDeckSlide(index);
    }
  }

  Widget _buildDeckArrow({required bool isPrevious}) {
    final keys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    );
    final compact = MediaQuery.sizeOf(context).width < 768;
    final arrowSize = compact ? 48.0 : 56.0;
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
          minimumSize: Size(arrowSize, arrowSize),
          foregroundColor: cs.onSurface,
          backgroundColor: cs.surfaceContainerHigh,
          side: BorderSide(color: cs.outlineVariant),
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  int _contentCardNumber(_LessonEditorCardKey key) {
    final contentKeys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    )
        .where((item) => item != _LessonEditorCardKey.generate)
        .toList();
    final index = contentKeys.indexOf(key);
    // Stitch treats Generate as slide 1 even after the generated content is
    // open, so the visible content cards are numbered 2, 3, and 4.
    return index < 0 ? 1 : index + 2;
  }

  int _stitchCardTotal() {
    final keys = _cardKeys(
      widget.visibleReferences,
      widget.visibleSuggestedImages,
    );
    return keys.contains(_LessonEditorCardKey.generate)
        ? keys.length
        : keys.length + 1;
  }

  Widget _buildCardMeta({
    required String label,
    required String title,
    required _LessonEditorCardKey cardKey,
    IconData? icon,
    bool showProgress = false,
  }) {
    final total = _stitchCardTotal();
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18, color: cs.primary),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: 16,
                          height: 1.5,
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: (cardKey == _LessonEditorCardKey.lessonNotes
                          ? theme.textTheme.displaySmall
                          : theme.textTheme.headlineLarge)
                      ?.copyWith(
                    fontSize: constraints.maxWidth < 520
                        ? 24
                        : cardKey == _LessonEditorCardKey.lessonNotes
                            ? 40
                            : 32,
                    height: 1.2,
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
          );
          final counterHasBorder =
              cardKey != _LessonEditorCardKey.assessment;
          final counter = Container(
              padding: counterHasBorder
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
                  : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                border: counterHasBorder
                    ? Border.all(color: cs.outlineVariant)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Card ${_contentCardNumber(cardKey)} of $total',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 16,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showProgress) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(total, (index) {
                        final selected =
                            index == _contentCardNumber(cardKey) - 1;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: selected ? 32 : 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: selected ? cs.primary : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: cs.primary.withValues(alpha: 0.4),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ],
              ),
            );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: 16),
                Align(alignment: Alignment.centerRight, child: counter),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: heading),
              const SizedBox(width: 16),
              counter,
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentCard({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.all(
        MediaQuery.sizeOf(context).width < 768 ? 16 : 32,
      ),
      child: child,
    );
  }

  // Shorthand getters for field access in helper methods
  bool get hasGenerated => widget.hasGenerated;
  bool get isUnlocked => widget.isUnlocked;
  bool get isOnline => widget.isOnline;
  String get subscriptionTier => widget.subscriptionTier;
  List<String> get assessmentAllowedTiers => widget.assessmentAllowedTiers;
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

  Widget _buildLockedPreviewOverlay() {
    return Container(
      color: cs.scrim.withValues(alpha: 0.68),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppTheme.radiusXl),
            border: Border.all(color: cs.tertiary.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.54),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, color: cs.tertiary, size: 32),
              const SizedBox(height: 12),
              Text(
                'Locked — Preview only',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Review the generated lesson content. Unlock to edit, save, or regenerate.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              if (onShowReferences != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onShowReferences,
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('View References'),
                  style: TextButton.styleFrom(foregroundColor: cs.tertiary),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: AppTheme.touchTarget,
                child: FilledButton.icon(
                  onPressed: onUnlock,
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.tertiary,
                    foregroundColor: cs.onTertiary,
                  ),
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(_buildUnlockLabel()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Empty state for a screen that has no deck yet. Draft lessons use the
    // deck below so Generate remains the first slide before the content tabs.
    if (!widget.hasGenerated && !widget.showGenerateSlide) {
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
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // ── Unlocked banner ─────────────────────────────────────
          if (hasGenerated &&
              isUnlocked &&
              _activeCardKey == _LessonEditorCardKey.diagrams)
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
          if (hasGenerated || widget.showGenerateSlide)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // The viewport is bounded by the parent SizedBox. Each
                  // card keeps its own vertical scroll for long content.
                  // On compact (phone) screens, put arrows above the card
                  // and reduce horizontal padding so the card fills width.
                  if (MediaQuery.sizeOf(context).width < 768)
                    Expanded(
                      child: Column(
                        children: [
                          // Navigation arrows above the card on phones.
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildDeckArrow(isPrevious: true),
                                const SizedBox(width: 16),
                                _buildDeckArrow(isPrevious: false),
                              ],
                            ),
                          ),
                          // Card fills remaining vertical space.
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: PageView.builder(
                                controller: _deckController,
                                itemCount: _cardKeys(
                                  visibleReferences,
                                  visibleSuggestedImages,
                                ).length,
                                onPageChanged: (i) {
                                  _setActiveDeckSlide(i);
                                },
                                itemBuilder: (context, index) {
                                  switch (_cardKeys(
                                    visibleReferences,
                                    visibleSuggestedImages,
                                  )[index]) {
                                    case _LessonEditorCardKey.generate:
                                      return _DraftGenerateTab(
                                        cs: cs,
                                        theme: theme,
                                        subject: widget.subject,
                                        classLevel: widget.classLevel,
                                        options: widget.draftTopicOptions,
                                        selectedOption: widget.selectedDraftTopic,
                                        isLoadingOptions:
                                            widget.isLoadingDraftTopics,
                                        isGenerating: widget.isGenerating,
                                        isOnline: isOnline,
                                        onChanged:
                                            widget.onDraftTopicChanged ?? (_) {},
                                        onGenerate:
                                            widget.onDraftGenerate ?? () {},
                                        onCreateNewTopic:
                                            widget.onCreateNewTopic ?? () {},
                                        allowManualTopic: widget.allowManualTopic,
                                        topicController: widget.topicController,
                                        onTopicChanged: widget.onTopicChanged,
                                      );
                                    case _LessonEditorCardKey.lessonNotes:
                                      return _buildLessonNoteTab(readOnly: !isUnlocked);
                                    case _LessonEditorCardKey.assessment:
                                      return _buildAssessmentTab(readOnly: !isUnlocked);
                                    case _LessonEditorCardKey.diagrams:
                                      return _buildDiagramsTab(readOnly: !isUnlocked);
                                    case _LessonEditorCardKey.references:
                                      return _buildReferencesTab();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(
                      child: Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 52),
                            child: PageView.builder(
                              controller: _deckController,
                              itemCount: _cardKeys(
                                visibleReferences,
                                visibleSuggestedImages,
                              ).length,
                              onPageChanged: (i) {
                                _setActiveDeckSlide(i);
                              },
                              itemBuilder: (context, index) {
                                switch (_cardKeys(
                                  visibleReferences,
                                  visibleSuggestedImages,
                                )[index]) {
                                  case _LessonEditorCardKey.generate:
                                    return _DraftGenerateTab(
                                      cs: cs,
                                      theme: theme,
                                      subject: widget.subject,
                                      classLevel: widget.classLevel,
                                      options: widget.draftTopicOptions,
                                      selectedOption: widget.selectedDraftTopic,
                                      isLoadingOptions:
                                          widget.isLoadingDraftTopics,
                                      isGenerating: widget.isGenerating,
                                      isOnline: isOnline,
                                      onChanged:
                                          widget.onDraftTopicChanged ?? (_) {},
                                      onGenerate:
                                          widget.onDraftGenerate ?? () {},
                                      onCreateNewTopic:
                                          widget.onCreateNewTopic ?? () {},
                                      allowManualTopic: widget.allowManualTopic,
                                      topicController: widget.topicController,
                                      onTopicChanged: widget.onTopicChanged,
                                    );
                                  case _LessonEditorCardKey.lessonNotes:
                                    return _buildLessonNoteTab(readOnly: !isUnlocked);
                                  case _LessonEditorCardKey.assessment:
                                    return _buildAssessmentTab(readOnly: !isUnlocked);
                                  case _LessonEditorCardKey.diagrams:
                                    return _buildDiagramsTab(readOnly: !isUnlocked);
                                  case _LessonEditorCardKey.references:
                                    return _buildReferencesTab();
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
            ),
            ],
          ),
          // ── Locked preview overlay (centered, darkened) ────────
          if (hasGenerated && !isUnlocked)
            Positioned.fill(
              child: _buildLockedPreviewOverlay(),
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
    final cs = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: cs.inverseSurface,
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
                color: cs.inverseSurface.withValues(alpha: 0.6),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.close, color: cs.onInverseSurface),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                    if (desc.isNotEmpty)
                      Expanded(
                        child: Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onInverseSurface,
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
          height: 1.55,
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
        blockSpacing: 12,
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

  String _stripInlineDocumentMarkup(String value) {
    return value
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'(\*\*|__|`|~~)'), '')
        .replaceFirst(RegExp(r'^>\s*'), '')
        .trim();
  }

  Widget _renderReadableLockedContent(String content) {
    final children = <Widget>[];
    for (final rawLine in content.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        children.add(const SizedBox(height: 8));
        continue;
      }
      final heading = RegExp(r'^#{1,6}\s+(.+)$').firstMatch(line);
      if (heading != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              _stripInlineDocumentMarkup(heading.group(1)!),
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
        );
        continue;
      }
      final bullet = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line);
      final numbered = RegExp(r'^(\d+)[.)]\s+(.+)$').firstMatch(line);
      if (bullet != null || numbered != null) {
        final marker = numbered?.group(1) ?? '•';
        final text = _stripInlineDocumentMarkup(
          numbered?.group(2) ?? bullet!.group(1)!,
        );
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: numbered == null ? 18 : 24,
                  child: Text(
                    numbered == null ? '•' : '$marker.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _stripInlineDocumentMarkup(line),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurface,
              height: 1.55,
            ),
          ),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildLessonNoteTab({required bool readOnly}) {
    final contextLabel = '${widget.subject} • ${widget.classLevel}';
    return _buildContentCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCardMeta(
              label: contextLabel,
              title: 'Presentation',
              cardKey: _LessonEditorCardKey.lessonNotes,
            ),
            _buildLessonField(
              title: 'Objectives',
              controller: widget.objectivesController,
              readOnly: readOnly,
              minLines: 4,
            ),
            if (widget.visibleVocabulary)
              _buildCollapsibleSection(
                title: 'Vocabulary',
                controller: widget.vocabularyController,
                readOnly: readOnly,
                undoController: readOnly ? null : widget.undoController,
              ),
            if (widget.visibleMaterials)
              _buildCollapsibleSection(
                title: 'Materials',
                controller: widget.materialsController,
                readOnly: readOnly,
                undoController: readOnly ? null : widget.undoController,
              ),
            _buildPresentationSection(readOnly: readOnly),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonField({
    required String title,
    required TextEditingController controller,
    required bool readOnly,
    int minLines = 4,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (readOnly)
            _buildLessonParagraphContent(controller.text)
          else
            _buildDocumentTextField(
              controller,
              undoController: undoController,
              minLines: minLines,
            ),
        ],
      ),
    );
  }

  Widget _buildLessonParagraphContent(String content) {
    if (content.trim().isEmpty) {
      return Text(
        'No content yet.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurfaceVariant,
          height: 1.55,
        ),
      );
    }

    final blocks = <Widget>[];
    final normalLines = <String>[];
    final keyLines = <String>[];
    var inKeyExample = false;

    void flushNormal() {
      final text = normalLines.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(_renderMarkdownContent(text));
      }
      normalLines.clear();
    }

    void flushKeyExample() {
      final text = keyLines.join('\n').trim();
      if (text.isNotEmpty) {
        blocks.add(
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border(
                left: BorderSide(color: cs.primary, width: 4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Key Example',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _renderMarkdownContent(text),
              ],
            ),
          ),
        );
      }
      keyLines.clear();
    }

    for (final line in content.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      final keyHeader = trimmed
          .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
          .toLowerCase()
          .startsWith('key example');
      if (keyHeader) {
        flushNormal();
        flushKeyExample();
        inKeyExample = true;
        final colon = trimmed.indexOf(':');
        if (colon >= 0 && colon + 1 < trimmed.length) {
          keyLines.add(trimmed.substring(colon + 1).trim());
        }
      } else if (inKeyExample && trimmed.isEmpty) {
        flushKeyExample();
        inKeyExample = false;
      } else if (inKeyExample) {
        keyLines.add(line);
      } else {
        normalLines.add(line);
      }
    }
    if (inKeyExample) {
      flushKeyExample();
    } else {
      flushNormal();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          blocks[i],
        ],
      ],
    );
  }

  Widget _buildAssessmentTab({required bool readOnly}) {
    final cs = widget.cs;
    final theme = widget.theme;
    final tierBlocked = !assessmentAllowedTiers
        .map((tier) => tier.trim().toLowerCase())
        .contains(widget.subscriptionTier.trim().toLowerCase());
    return _buildContentCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            _buildCardMeta(
              label: 'Assessment',
              title: '${widget.classLevel} ${widget.subject}',
              cardKey: _LessonEditorCardKey.assessment,
              showProgress: true,
            ),
          if (tierBlocked) ...[
            // Tier-locked state
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
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
            const SizedBox(height: 24),
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
            _buildHomeworkSection(readOnly: readOnly),
          ],
        ],
        ),
      ),
    );
  }


  Widget _buildDiagramsTab({required bool readOnly}) {
    return _buildContentCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSuggestedImagesSection(
              context,
              readOnly: readOnly,
              collapsible: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReferencesTab() {
    final cs = widget.cs;
    final theme = widget.theme;
    final readOnly = !widget.isUnlocked;
    // Build priority-ordered list
    final displayItems = <({
      String text,
      String origin,
      String metadata,
      String relatedTopics,
      bool removable,
      int? storedIndex,
    })>[];
    final schemeRef = widget.schemeReference?.trim() ?? '';
    if (schemeRef.isNotEmpty) {
      displayItems.add((
        text: schemeRef,
        origin: 'scheme',
        metadata: '',
        relatedTopics: '',
        removable: false,
        storedIndex: null,
      ));
    }
    var storedIdx = 0;
    for (final item in widget.references) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final origin = (item['origin'] ?? 'ai').toString();
      displayItems.add((
        text: text,
        origin: origin,
        metadata: _referenceMetadataText(item),
        relatedTopics: _referenceRelatedTopicsText(item),
        removable: !readOnly,
        storedIndex: storedIdx,
      ));
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
    return _buildContentCard(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            _buildCardMeta(
              label: 'References',
              title: 'Source References',
              cardKey: _LessonEditorCardKey.references,
            ),
          Text(
            'Source references used for this lesson.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
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
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
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
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 28, color: cs.onSurfaceVariant),
                  const SizedBox(height: 8),
                  Text(
                    'No source references available yet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            ...displayItems.map((item) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
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
                          Text(
                            item.text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: cs.onSurface,
                              height: 1.5,
                            ),
                          ),
                          if (item.metadata.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.metadata,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                          if (item.relatedTopics.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Builder(
                              builder: (context) {
                                final rt = item.relatedTopics;
                                final prefix = 'Related topics: ';
                                final prefixAlt = 'Related Topics: ';
                                String label;
                                String topics;
                                if (rt.startsWith(prefix)) {
                                  label = prefix.trimRight();
                                  topics = rt.substring(prefix.length).trim();
                                } else if (rt.startsWith(prefixAlt)) {
                                  label = prefixAlt.trimRight();
                                  topics = rt.substring(prefixAlt.length).trim();
                                } else {
                                  label = 'Related topics';
                                  topics = rt;
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: cs.secondaryContainer.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: Text(
                                        label,
                                        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (topics.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        topics,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
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
                  _buildLessonParagraphContent(controller.text)
                else
                  _buildDocumentTextField(
                    controller,
                    undoController: undoController,
                    minLines: 3,
                    hintText: '$label content...',
                    highlightKeyExample: controller.text
                        .toLowerCase()
                        .contains('key example'),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAssessmentMcqCard(int index) {
    final question = mcqs[index];
    final options = Map<String, dynamic>.from(
      question['options'] as Map? ?? const <String, dynamic>{},
    );
    final correct = question['correct']?.toString() ?? 'A';
    final optionKeys = ['A', 'B', 'C', 'D'];

    InputDecoration fieldDecoration({String? label}) {
      return InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );
    }

    Widget optionButton(String key) {
      final selected = key == correct;
      final optionText = options[key]?.toString() ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isUnlocked
                ? () => onUpdateMcq?.call(index, 'correct', key)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? cs.surfaceContainerHigh : cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? cs.primary : cs.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? cs.primary : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? cs.primary : cs.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Text(
                      key,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: optionText,
                      undoController: undoController,
                      readOnly: !isUnlocked,
                      onChanged: (value) =>
                          onUpdateMcqOption?.call(index, key, value),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface,
                        height: 1.45,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey(question),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: question['question']?.toString() ?? '',
                  undoController: undoController,
                  maxLines: 3,
                  onChanged: (value) => onUpdateMcq?.call(index, 'question', value),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface,
                    height: 1.45,
                  ),
                  decoration: fieldDecoration(label: 'Question'),
                ),
              ),
              if (onDeleteMcq != null)
                IconButton(
                  onPressed: () => _confirmDeleteQuestion(
                    questionType: 'MCQ',
                    onConfirm: () => onDeleteMcq!(index),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: cs.error,
                  tooltip: 'Delete question',
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Select the correct answer',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...optionKeys.map(optionButton),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteQuestion({
    required String questionType,
    required VoidCallback onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete question?'),
        content: Text(
          'Delete this $questionType assessment question? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      onConfirm();
    }
  }

  List<Widget> _buildQuestionCards() {
    final widgets = <Widget>[];
    // MCQs
    for (int i = 0; i < mcqs.length; i++) {
      widgets.add(_buildAssessmentMcqCard(i));
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
        onDelete: onDeleteTheory != null
            ? () => _confirmDeleteQuestion(
                  questionType: 'theory',
                  onConfirm: () => onDeleteTheory!(i),
                )
            : null,
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
            ? () => _confirmDeleteQuestion(
                  questionType: 'subjective',
                  onConfirm: () => onDeleteSubjective!(i),
                )
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

  Widget _buildHomeworkSection({required bool readOnly}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Homework',
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (readOnly)
            _buildLessonParagraphContent(widget.homeworkController.text)
          else ...[
            _buildDocumentTextField(
              widget.homeworkController,
              undoController: undoController,
              minLines: 4,
            ),
            if (widget.homeworkController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: widget.onRegenerateHomework,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate homework only'),
                ),
              ),
            ],
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
    bool collapsible = true,
  }) {
    final content = diagramResults.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Column(
                  children: [
                    Icon(Icons.image_not_supported_outlined,
                        size: 28, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(
                      'No suggested images yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
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
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant,
                        ),
                      ),
                      color: cs.surfaceContainerLow,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                            child: Text(
                              'Suggestion ${index + 1}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          if (desc.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                              child: Text(
                                desc,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: cs.onSurface,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          const SizedBox(height: 16),
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
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
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
                                          style: theme.textTheme.labelLarge
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
          );
    if (!collapsible) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 18, color: cs.onSurface),
              const SizedBox(width: 8),
              Text(
                'Suggested Images',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: cs.outlineVariant),
          const SizedBox(height: 16),
          content,
        ],
      );
    }
    return _DocumentSection(
      title: 'Suggested Images',
      icon: Icons.image_outlined,
      initiallyExpanded: true,
      child: content,
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
                : _buildLessonParagraphContent(controller.text))
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
    bool highlightKeyExample = false,
  }) {
    final field = TextFormField(
      controller: controller,
      undoController: undoController,
      maxLines: null,
      minLines: minLines,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: cs.onSurface,
        height: 1.5,
      ),
      decoration: InputDecoration(
        border: highlightKeyExample
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
        enabledBorder: highlightKeyExample
            ? InputBorder.none
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
        focusedBorder: highlightKeyExample ? InputBorder.none : null,
        contentPadding: const EdgeInsets.all(12),
        hintText: hintText ?? 'No content yet.',
        hintStyle: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    if (!highlightKeyExample) return field;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(color: cs.primary, width: 4),
        ),
      ),
      child: field,
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
                  _renderReadableLockedContent(text),
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
          : _renderReadableLockedContent(content),
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
    final cs = _lessonEditorStitchColorScheme(
      Theme.of(context).colorScheme,
    );
    final theme = ThemeData(
      colorScheme: cs,
      textTheme: GoogleFonts.workSansTextTheme(
        Theme.of(context).textTheme,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tappable header — plain row, no border, no filled background.
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.touchTarget),
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
    final displayItems = <({
      String text,
      String origin,
      String metadata,
      String relatedTopics,
      bool removable,
      int? storedIndex,
    })>[];
    final schemeRef = widget.schemeReference?.trim() ?? '';
    final topicRef = widget.topicReference?.trim() ?? '';
    if (schemeRef.isNotEmpty) {
      displayItems.add((
        text: schemeRef,
        origin: 'scheme',
        metadata: '',
        relatedTopics: '',
        removable: false,
        storedIndex: null,
      ));
    }
    if (topicRef.isNotEmpty) {
      displayItems.add((
        text: topicRef,
        origin: 'teacher',
        metadata: '',
        relatedTopics: '',
        removable: false,
        storedIndex: null,
      ));
    }
    var storedIndex = 0;
    for (final item in _items) {
      final text = (item['text'] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final origin = (item['origin'] ?? 'ai').toString();
      displayItems.add((
        text: text,
        origin: origin,
        metadata: _referenceMetadataText(item),
        relatedTopics: _referenceRelatedTopicsText(item),
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
                            if (item.metadata.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.metadata,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            if (item.relatedTopics.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.relatedTopics,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  height: 1.4,
                                ),
                              ),
                            ],
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
                  icon: Tooltip(
                    message: item.label,
                    child: item.isActive
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
// Floating Action Area (fixed at bottom)
// ═══════════════════════════════════════════════════════════════════════
class _StitchLessonFooter extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final VoidCallback? onRegenerate;
  final VoidCallback? onMarkCompleted;
  final String lessonStatus;
  final VoidCallback? onExportPdf;
  final bool isExporting;
  final VoidCallback? onShowVisibleSections;

  const _StitchLessonFooter({
    required this.cs,
    required this.theme,
    this.onRegenerate,
    this.onMarkCompleted,
    required this.lessonStatus,
    this.onExportPdf,
    this.isExporting = false,
    this.onShowVisibleSections,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: onRegenerate,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Regenerate'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.touchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: labelStyle,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onMarkCompleted,
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(
                  lessonStatus == 'completed' ? 'Completed' : 'Mark Completed',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.touchTarget),
                  backgroundColor: cs.primaryContainer,
                  foregroundColor: cs.onPrimaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: labelStyle,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 32,
                  child: VerticalDivider(
                    width: 1,
                    color: cs.outlineVariant,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onExportPdf == null || isExporting
                    ? null
                    : onExportPdf,
                icon: isExporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded),
                label: Text(isExporting ? 'Exporting...' : 'Export PDF'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.touchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: labelStyle,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: onShowVisibleSections,
                icon: const Icon(Icons.visibility_rounded),
                label: const Text('Visible Sections'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, AppTheme.touchTarget),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: labelStyle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StitchLessonFab extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final bool showReviewSection;
  final bool showActionMenu;
  final VoidCallback onToggleReview;
  final VoidCallback onToggleActions;
  final TextEditingController reviewController;
  final bool isRegenerating;
  final VoidCallback? onRegenerate;
  final VoidCallback? onMarkCompleted;
  final String lessonStatus;
  final VoidCallback? onSave;
  final VoidCallback? onExportPdf;
  final bool isExporting;
  final VoidCallback? onShowVisibleSections;
  final VoidCallback? onShowFontSize;

  const _StitchLessonFab({
    required this.cs,
    required this.theme,
    required this.showReviewSection,
    required this.showActionMenu,
    required this.onToggleReview,
    required this.onToggleActions,
    required this.reviewController,
    required this.isRegenerating,
    this.onRegenerate,
    this.onMarkCompleted,
    required this.lessonStatus,
    this.onSave,
    this.onExportPdf,
    this.isExporting = false,
    this.onShowVisibleSections,
    this.onShowFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final desktop = screenWidth >= 768;
    final isMobile = !desktop;
    final menuWidth = screenWidth < 352 ? screenWidth - 32 : 320.0;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(
            desktop ? 40 : 16,
        8,
        desktop ? 40 : 16,
        desktop ? 40 : 16,
      ),
      child: SizedBox(
        width: menuWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showReviewSection || (showActionMenu && !showReviewSection))
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: ((MediaQuery.sizeOf(context).height -
                              MediaQuery.viewInsetsOf(context).bottom -
                              (isMobile ? 104 : 96))
                          .clamp(96.0, 520.0))
                      .toDouble(),
                ),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: showReviewSection
                      ? _buildReviewPanel()
                      : _buildActionMenu(),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: showActionMenu || showReviewSection
                    ? 'Close lesson actions'
                    : 'Lesson actions',
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: FloatingActionButton(
                    heroTag: 'lesson-editor-actions',
                    tooltip: showActionMenu || showReviewSection
                        ? 'Close lesson actions'
                        : 'Lesson actions',
                    onPressed: showReviewSection
                        ? onToggleReview
                        : onToggleActions,
                    child: Icon(
                      showActionMenu || showReviewSection
                          ? Icons.close_rounded
                          : Icons.add_rounded,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Feedback for regeneration',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: onToggleReview,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Close feedback',
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
          TextField(
            controller: reviewController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Type feedback to guide regeneration...',
              filled: true,
              fillColor: cs.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: AppTheme.touchTarget,
            child: FilledButton.icon(
              onPressed: isRegenerating ? null : onRegenerate,
              icon: isRegenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(isRegenerating ? 'Regenerating...' : 'Regenerate'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionMenu() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _actionButton(
            label: 'Save',
            icon: Icons.save_rounded,
            filled: true,
            onPressed: onSave == null
                ? null
                : () {
                    onToggleActions();
                    onSave!();
                  },
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Regenerate',
            icon: Icons.refresh_rounded,
            filled: true,
            onPressed: onRegenerate == null || isRegenerating
                ? null
                : () {
                    onToggleActions();
                    onToggleReview();
                  },
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: lessonStatus == 'completed'
                ? 'Completed'
                : 'Mark Completed',
            icon: Icons.check_circle_rounded,
            filled: true,
            onPressed: onMarkCompleted == null
                ? null
                : () {
                    onToggleActions();
                    onMarkCompleted!();
                  },
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: isExporting ? 'Exporting...' : 'Export PDF',
            icon: Icons.picture_as_pdf_rounded,
            onPressed: onExportPdf == null || isExporting
                ? null
                : () {
                    onToggleActions();
                    onExportPdf!();
                  },
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Visible Sections',
            icon: Icons.visibility_rounded,
            onPressed: onShowVisibleSections == null
                ? null
                : () {
                    onToggleActions();
                    onShowVisibleSections!();
                  },
          ),
          const SizedBox(height: 8),
          _actionButton(
            label: 'Font Size',
            icon: Icons.format_size_rounded,
            onPressed: onShowFontSize == null
                ? null
                : () {
                    onToggleActions();
                    onShowFontSize!();
                  },
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final child = Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onPressed,
            tooltip: label,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              minimumSize: const Size(56, 56),
              backgroundColor: filled ? cs.primary : cs.surfaceContainerHigh,
              foregroundColor: filled ? cs.onPrimary : cs.onSurface,
              disabledBackgroundColor: cs.surfaceContainerLow,
              disabledForegroundColor: cs.onSurfaceVariant,
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Tooltip(message: label, child: child),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Font Size Picker Sheet
// ═══════════════════════════════════════════════════════════════════════
class _FontSizePickerSheet extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final String currentSize;
  final ValueChanged<String> onSelected;

  const _FontSizePickerSheet({
    required this.cs,
    required this.theme,
    required this.currentSize,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Card Font Size',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            for (final entry in const [
              ('small', 'Small', 13.0),
              ('medium', 'Medium', 15.0),
              ('large', 'Large', 17.0),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => onSelected(entry.$1),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: currentSize == entry.$1
                          ? cs.primaryContainer
                          : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: currentSize == entry.$1
                            ? cs.primary
                            : cs.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          currentSize == entry.$1
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: currentSize == entry.$1
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          entry.$2,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontSize: entry.$3,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surfaceContainerLow,
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
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
            color: cs.surfaceContainerLow,
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
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        option,
                        maxLines: 1,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
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
