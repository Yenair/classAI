import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
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

  const LessonEditorScreen({super.key, this.generateCallback});

  @override
  ConsumerState<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _LessonEditorScreenState extends ConsumerState<LessonEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  int _week = 1;
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  String _assessmentFormat = 'Both';
  final Set<String> _selectedBlooms = {};
  bool _isGenerating = false;
  bool _hasGenerated = false;
  bool _isUnlocked = false;
  int _creditBalance = 0;
  String? _encryptedContent;
  String? _teacherId;
  String? _schoolId;
  String _subscriptionTier = 'free';

  /// Loaded from subjectsDao, falls back to [_subjects] if empty.
  List<String> _loadedSubjects = [];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithEmergencyFlush();
      _loadCreditBalance();
      _loadAuthInfo();
      _loadSubjects();
    });
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
      }
      if (authData.currentSchool != null) {
        _schoolId = authData.currentSchool!.serverId;
        _subscriptionTier = authData.currentSchool!.subscriptionTier;
      }
      // Fallback: read from DB if auth provider has null data
      if (_teacherId == null || _schoolId == null) {
        final db = ref.read(databaseProvider);
        final school = await db.schoolsDao.get();
        if (school != null) {
          _schoolId ??= school.serverId;
          _subscriptionTier = school.subscriptionTier;
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

    if (_creditBalance < 1) {
      showErrorToast(context: context, message: 'Insufficient credits');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final db = ref.read(databaseProvider);

      // Build prompt (without teacher/school for now - attribution added via template)
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

      final db = ref.read(databaseProvider);
      final id = await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: _subject,
          classLevel: _classLevel,
          week: _week,
          topic: _topicController.text.trim(),
          difficulty: _difficulty,
          bloomsVerbs: _selectedBlooms.join(', '),
          curriculum: 'NERDC',
          content: _encryptedContent ?? jsonEncode(content),
        ),
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
          _NavigationDrawer(cs: cs, theme: theme),

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
                        child: Column(
                          children: [
                            // ── Tool Header Area ────────────────────
                            _ToolHeader(cs: cs, theme: theme),

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
                                              onSubjectChanged: (v) =>
                                                  setState(() =>
                                                      _subject = v),
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
                                            onSubjectChanged: (v) =>
                                                setState(() => _subject = v),
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
  const _NavigationDrawer({required this.cs, required this.theme});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 768) return const SizedBox.shrink();
        return Container(
          width: 288,
          color: cs.surfaceContainerLow,
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Logo area
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
                          child: const Icon(
                            Icons.person_rounded,
                            color: Colors.white,
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
              ),
              const SizedBox(height: 32),
              // Nav items
              ..._LessonEditorScreenState._navItems.map((item) {
                return Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  transform: item.isActive
                      ? Matrix4.translationValues(4.0, 0.0, 0.0)
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
                    onTap: () {
                      // Navigation handled by router in real app
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
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
                              fontWeight:
                                  item.isActive ? FontWeight.w700 : FontWeight.w500,
                              color: item.isActive
                                  ? cs.onSecondaryFixed
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
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
                child: const Icon(Icons.person_rounded, size: 18, color: Colors.white),
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
  const _ToolHeader({required this.cs, required this.theme});

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
          // Back link
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
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<String> onDifficultyChanged;
  final ValueChanged<String> onAssessmentFormatChanged;
  final ValueChanged<String> onBloomToggled;
  final VoidCallback onGenerate;

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
    required this.onSubjectChanged,
    required this.onClassChanged,
    required this.onWeekChanged,
    required this.onDifficultyChanged,
    required this.onAssessmentFormatChanged,
    required this.onBloomToggled,
    required this.onGenerate,
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
              // Topic + Week row
              Row(
                children: [
                  Expanded(
                    child: _StyledTextField(
                      cs: cs,
                      theme: theme,
                      label: 'Topic',
                      controller: null,
                      initialValue: '',
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
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              'Estimated Cost: 20 Credits',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
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
                  Text(
                    'Preview Generated Content',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
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
                Text(
                  'Preview Generated Content',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
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
                      Text(
                        'Locked — Unlock for 1 credit',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.tertiary,
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
            Text(
              content.isEmpty ? 'No content yet.' : content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
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
              onTap: (_) {},
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

  const _StyledDropdown({
    required this.cs,
    required this.theme,
    required this.label,
    required this.value,
    required this.items,
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
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
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
