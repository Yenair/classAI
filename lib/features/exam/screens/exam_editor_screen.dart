import 'dart:convert';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
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
import 'package:classai/main.dart' show databaseProvider;

enum QuestionType { mcq, theory, both }

/// Stitch‑designed exam editor with AI generation.
///
/// Generates MCQ + theory questions. Preview as editable list of question cards.
/// Save inserts into `exams` table.
class ExamEditorScreen extends ConsumerStatefulWidget {
  /// Callback invoked with the generated prompt; returns parsed JSON map.
  final Future<Map<String, dynamic>> Function(String prompt)? generateCallback;

  const ExamEditorScreen({super.key, this.generateCallback});

  @override
  ConsumerState<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends ConsumerState<ExamEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
  final _questionCountController = TextEditingController(text: '10');
  String _subject = 'Mathematics';
  String _classLevel = 'JSS 1';
  String _difficulty = 'medium';
  bool _isGenerating = false;
  bool _hasGenerated = false;
  bool _isUnlocked = false;
  int _creditBalance = 3;
  QuestionType _questionType = QuestionType.both;
  String? _teacherId;
  String? _schoolId;
  String _subscriptionTier = 'free';

  /// Loaded from subjectsDao, falls back to [_subjects] if empty.
  List<String> _loadedSubjects = [];

  // Generated MCQ data
  List<Map<String, dynamic>> _mcqs = [];

  // Generated theory questions
  List<Map<String, dynamic>> _theoryQuestions = [];

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
        await _saveExam(notify: false);
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
      final db = ref.read(databaseProvider);
      final config = await db.securityConfigDao.get();
      if (mounted) {
        setState(() => _creditBalance = config.offlineCredits);
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
      final aiService = AiService(db: db);
      final topic = _topicController.text.trim();
      final generateMcq = _questionType != QuestionType.theory;
      final generateTheory = _questionType != QuestionType.mcq;

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

      // Generate MCQ and Theory questions
      // NOTE: No credit is spent on AI generation - credit is spent on unlock
      _mcqs = [];
      _theoryQuestions = [];

      if (generateMcq) {
        final mcqPrompt = PromptTemplates.mcqs(
          _subject,
          _classLevel,
          topic,
          _difficulty,
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

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showInfoToast(
            context: context,
            message:
                'Generated ${_mcqs.length} MCQs and ${_theoryQuestions.length} theory questions',
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
      };

      final db = ref.read(databaseProvider);
      final id = await db.into(db.exams).insert(
            ExamsCompanion.insert(
              subject: _subject,
              classLevel: _classLevel,
              topic: _topicController.text.trim(),
              difficulty: _difficulty,
              curriculum: 'NERDC',
              content: jsonEncode(content),
            ),
          );

      if (notify && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showInfoToast(context: context, message: 'Exam saved (id=$id)');
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
      _difficulty = 'medium';
      _mcqs = [];
      _theoryQuestions = [];
      _hasGenerated = false;
    });
  }

  @override
  void dispose() {
    _topicController.dispose();
    _questionCountController.dispose();
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
    final totalQuestions = _mcqs.length + _theoryQuestions.length;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Navigation Drawer (tablet+) ──────────────────────────
          _NavDrawer(cs: cs, theme: theme),

          // ── Main Content ─────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                // ── Top AppBar ──────────────────────────────────────
                _TopBar(
                  cs: cs,
                  theme: theme,
                  creditBalance: _creditBalance,
                ),

                // ── Editor Workspace ────────────────────────────────
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 1024;
                      return SingleChildScrollView(
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
                                        topicController: _topicController,
                                        questionCountController:
                                            _questionCountController,
                                        difficulty: _difficulty,
                                        isGenerating: _isGenerating,
                                        creditBalance: _creditBalance,
                                        subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                        classLevels: _classLevels,
                                        difficulties: _difficulties,
                                        onSubjectChanged: (v) => setState(
                                            () => _subject = v),
                                        onClassChanged: (v) => setState(
                                            () => _classLevel = v),
                                        onDifficultyChanged: (v) => setState(
                                            () => _difficulty = v),
                                        onGenerate: _handleGenerate,
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
                                      topicController: _topicController,
                                      questionCountController:
                                          _questionCountController,
                                      difficulty: _difficulty,
                                      isGenerating: _isGenerating,
                                      creditBalance: _creditBalance,
                                      subjects: _loadedSubjects.isNotEmpty ? _loadedSubjects : _subjects,
                                      classLevels: _classLevels,
                                      difficulties: _difficulties,
                                      onSubjectChanged: (v) => setState(
                                          () => _subject = v),
                                      onClassChanged: (v) => setState(
                                          () => _classLevel = v),
                                      onDifficultyChanged: (v) => setState(
                                          () => _difficulty = v),
                                      onGenerate: _handleGenerate,
                                    ),
                                    const SizedBox(height: 24),
                                    _PreviewPanel(
                                      cs: cs,
                                      theme: theme,
                                      hasGenerated: _hasGenerated,
                                      isUnlocked: _isUnlocked,
                                      mcqs: _mcqs,
                                      theoryQuestions: _theoryQuestions,
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
  const _NavDrawer({required this.cs, required this.theme});

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
              const SizedBox(height: 32),
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
                      child: const Icon(
                        Icons.person_rounded,
                        size: 24,
                        color: Colors.white54,
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
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Column(
                  children: _ExamEditorScreenState._navItems.map((item) {
                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
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
                                  fontWeight: item.isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
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
                  }).toList(),
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
// Top Bar
// ═══════════════════════════════════════════════════════════════════════
class _TopBar extends StatelessWidget {
  final ColorScheme cs;
  final ThemeData theme;
  final int creditBalance;
  const _TopBar({
    required this.cs,
    required this.theme,
    required this.creditBalance,
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
                  child: const Icon(
                    Icons.person_rounded,
                    size: 22,
                    color: Colors.white54,
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
          Container(
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
  final TextEditingController topicController;
  final TextEditingController questionCountController;
  final String difficulty;
  final bool isGenerating;
  final int creditBalance;
  final List<String> subjects;
  final List<String> classLevels;
  final List<String> difficulties;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onDifficultyChanged;
  final VoidCallback onGenerate;

  const _ConfigPanel({
    required this.cs,
    required this.theme,
    required this.subject,
    required this.classLevel,
    required this.topicController,
    required this.questionCountController,
    required this.difficulty,
    required this.isGenerating,
    required this.creditBalance,
    required this.subjects,
    required this.classLevels,
    required this.difficulties,
    required this.onSubjectChanged,
    required this.onClassChanged,
    required this.onDifficultyChanged,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
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
              // Subject / Topic
              _FieldLabel(theme: theme, cs: cs, label: 'Subject / Topic'),
              const SizedBox(height: 4),
              SizedBox(
                height: AppTheme.touchTarget,
                child: TextFormField(
                  controller: topicController,
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
                  Text(
                    'Generation Engine',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // MCQ count
              _FieldLabel(
                theme: theme,
                cs: cs,
                label: 'Multiple Choice (MCQ)',
                color: Colors.white70,
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: AppTheme.touchTarget,
                child: TextFormField(
                  controller: questionCountController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.15),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: cs.onPrimaryContainer),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Required';
                    }
                    final count = int.tryParse(v);
                    if (count == null || count < 1) {
                      return 'Min 1';
                    }
                    if (count > 100) {
                      return 'Max 100';
                    }
                    return null;
                  },
                ),
              ),
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
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bolt_rounded),
                  label: Text(
                    isGenerating
                        ? 'Generating...'
                        : 'Generate Exam (-50 Credits)',
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
                      'Generated ${mcqs.length} MCQs and ${theoryQuestions.length} theory questions',
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
          Text(
            'Preview Draft',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          if (totalQuestions != null) ...[
            const Spacer(),
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
              onTap: (_) {},
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

  const _SimpleDropdown({
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
              items: items.map((item) {
                return DropdownMenuItem(
                  value: item,
                  child: Text(
                    item,
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
        Text(
          subtitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
