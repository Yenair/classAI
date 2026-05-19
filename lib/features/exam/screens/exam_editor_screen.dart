import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/main.dart' show databaseProvider;

enum QuestionType { mcq, theory, both }

/// Material Design exam editor with AI generation.
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
  int _creditBalance = 3;
  QuestionType _questionType = QuestionType.both;

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
    });
  }

  void _registerWithEmergencyFlush() {
    final flushService = ref.read(emergencyFlushServiceProvider);
    flushService.register(() async {
      if (_hasGenerated && _formKey.currentState!.validate()) {
        await _saveExam(notify: false);
      }
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient credits')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final topic = _topicController.text.trim();
      final generateMcq = _questionType != QuestionType.theory;
      final generateTheory = _questionType != QuestionType.mcq;

      // Spend credit (1 credit for the entire exam generation)
      final creditService = CreditService(ref.read(databaseProvider));
      final topicId = _topicController.text.trim();
      await creditService.spendCredits(
        amount: 1,
        contentIds: ['exam_$_subject\$$topicId'],
      );

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
        }
        final theoryRaw =
            theoryResult['raw'] as Map<String, dynamic>? ?? theoryResult;
        final theoryList = theoryRaw['questions'] as List<dynamic>? ?? [];
        _theoryQuestions =
            theoryList.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      }

      setState(() {
        _hasGenerated = true;
        _creditBalance = _creditBalance - 1;
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Generated ${_mcqs.length} MCQs and ${_theoryQuestions.length} theory questions',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e')),
        );
      }
    }
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exam saved (id=$id)')),
        );
      }
    } catch (e) {
      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    const v08 = SizedBox(height: 8);
    const v12 = SizedBox(height: 12);
    const v16 = SizedBox(height: 16);
    const v20 = SizedBox(height: 20);
    const v24 = SizedBox(height: 24);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface.withValues(alpha: 0.55),
              cs.surfaceContainerLowest,
            ],
          ),
        ),
        child: Column(
          children: [
            // ── AppBar ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  bottom: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: AppBar(
                backgroundColor: cs.surface,
                elevation: 0,
                surfaceTintColor: cs.surface,
                title: Text(
                  'Exam Editor',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                actions: [
                  // Credits pill
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text(
                          '$_creditBalance',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Scrollable body ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Form card ─────────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 24),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Subject dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _subject,
                              decoration: const InputDecoration(
                                labelText: 'Subject',
                              ),
                              items: _subjects
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(s)))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _subject = v ?? _subject),
                            ),
                            v12,

                            // Class level dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _classLevel,
                              decoration: const InputDecoration(
                                labelText: 'Class',
                              ),
                              items: _classLevels
                                  .map((c) => DropdownMenuItem(
                                      value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _classLevel = v ?? _classLevel),
                            ),
                            v12,

                            // Topic text field
                            TextFormField(
                              controller: _topicController,
                              decoration: const InputDecoration(
                                labelText: 'Topic',
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Topic is required'
                                  : null,
                            ),
                            v12,

                            // Number of Questions
                            TextFormField(
                              controller: _questionCountController,
                              decoration: const InputDecoration(
                                labelText: 'Number of Questions',
                              ),
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Number of questions is required';
                                }
                                final count = int.tryParse(v);
                                if (count == null || count < 1) {
                                  return 'Enter a valid number (minimum 1)';
                                }
                                if (count > 100) {
                                  return 'Maximum 100 questions allowed';
                                }
                                return null;
                              },
                            ),
                            v12,

                            // Difficulty dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _difficulty,
                              decoration: const InputDecoration(
                                labelText: 'Difficulty',
                              ),
                              items: _difficulties
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text(d)))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _difficulty = v ?? _difficulty),
                            ),
                            v16,

                            // Question type label
                            Text(
                              'Question Type:',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            v08,
                            SegmentedButton<QuestionType>(
                              segments: const [
                                ButtonSegment(
                                    value: QuestionType.mcq,
                                    label: Text('MCQ')),
                                ButtonSegment(
                                    value: QuestionType.theory,
                                    label: Text('Theory')),
                                ButtonSegment(
                                    value: QuestionType.both,
                                    label: Text('Both')),
                              ],
                              selected: {_questionType},
                              style: ButtonStyle(
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                side: WidgetStateProperty.all(
                                  BorderSide(color: cs.outlineVariant),
                                ),
                              ),
                              onSelectionChanged: (selection) {
                                setState(() => _questionType = selection.first);
                              },
                            ),
                            v24,

                            // Generate button
                            SizedBox(
                              height: 56,
                              child: FilledButton.icon(
                                onPressed:
                                    _isGenerating ? null : _handleGenerate,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome_rounded),
                                label: Text(
                                  _isGenerating ? 'Generating...' : 'Generate',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      v24,

                      // ── MCQ preview cards ───────────────────────────
                      if (_hasGenerated && _mcqs.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.check_circle_rounded,
                          label: 'MCQs (${_mcqs.length})',
                          cs: cs,
                          theme: theme,
                        ),
                        v12,
                        ...List.generate(
                            _mcqs.length, (i) => _buildMcqCard(i, theme, cs)),
                        v20,
                      ],

                      // ── Theory preview cards ────────────────────────
                      if (_hasGenerated && _theoryQuestions.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.article_rounded,
                          label:
                              'Theory Questions (${_theoryQuestions.length})',
                          cs: cs,
                          theme: theme,
                        ),
                        v12,
                        ...List.generate(_theoryQuestions.length,
                            (i) => _buildTheoryCard(i, theme, cs)),
                        v20,
                      ],

                      // ── Save / Discard ──────────────────────────────
                      (_hasGenerated)
                          ? Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _saveExam(),
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text(
                                      'Save',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _discard,
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                    label: const Text(
                                      'Discard',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox(),
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

  Widget _buildMcqCard(int index, ThemeData theme, ColorScheme cs) {
    final mcq = _mcqs[index];
    final question = mcq['question'] as String? ?? '';
    final options = mcq['options'] as Map<String, dynamic>? ?? {};
    final correct = mcq['correct'] as String? ?? 'A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Q${index + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Question',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: question,
            maxLines: 2,
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) => _updateMcq(index, 'question', v),
          ),
          const SizedBox(height: 12),
          Text(
            'Answer Options:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: correct,
            onChanged: (v) => _updateMcq(index, 'correct', v ?? 'A'),
            child: Column(
              children: ['A', 'B', 'C', 'D'].map((key) {
                final optVal = options[key] as String? ?? '';
                final isCorrect = correct == key;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Radio<String>(value: key),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextFormField(
                          initialValue: optVal,
                          decoration: InputDecoration(
                            labelText: 'Option $key',
                            isDense: true,
                            prefixIcon: isCorrect
                                ? Icon(Icons.check_circle_rounded,
                                    size: 18, color: cs.primary)
                                : null,
                          ),
                          onChanged: (v) => _updateMcqOption(index, key, v),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTheoryCard(int index, ThemeData theme, ColorScheme cs) {
    final theory = _theoryQuestions[index];
    final question = theory['question'] as String? ?? '';
    final modelAnswer = theory['modelAnswer'] as String? ?? '';
    final cognitiveLevel = theory['cognitiveLevel'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.tertiary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'T${index + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.tertiary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Theory Q${index + 1}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: question,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Question',
              isDense: false,
            ),
            onChanged: (v) => _updateTheory(index, 'question', v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: modelAnswer,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Model Answer',
              isDense: false,
            ),
            onChanged: (v) => _updateTheory(index, 'modelAnswer', v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: cognitiveLevel,
            decoration: const InputDecoration(
              labelText: 'Cognitive Level',
              isDense: false,
            ),
            onChanged: (v) => _updateTheory(index, 'cognitiveLevel', v),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.cs,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final ColorScheme cs;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
