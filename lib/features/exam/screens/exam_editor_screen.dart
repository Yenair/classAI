import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/features/lesson/screens/lesson_editor_screen.dart'
    show emergencyFlushServiceProvider;
import 'package:classai/main.dart' show databaseProvider;

enum QuestionType { mcq, theory, both }

/// Material Design exam editor with AI generation.
///
/// Generates MCQ + theory questions. Preview as editable list of question cards.
/// Save inserts into `exams` table.
class ExamEditorScreen extends ConsumerStatefulWidget {
  /// Callback invoked with the generated prompt; returns parsed JSON map.
  final Future<Map<String, dynamic>> Function(String prompt)?
      generateCallback;

  const ExamEditorScreen({super.key, this.generateCallback});

  @override
  ConsumerState<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends ConsumerState<ExamEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _topicController = TextEditingController();
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
    'Mathematics', 'English', 'Science', 'Social Studies',
    'Civic Education', 'Christian Religious Studies',
    'Agricultural Science', 'Home Economics', 'Physical Education',
  ];

  final List<String> _classLevels = [
    'JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3',
    'Primary 1', 'Primary 2', 'Primary 3',
    'Primary 4', 'Primary 5', 'Primary 6',
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
      await creditService.spendCredits(
        amount: 1,
        contentIds: ['exam_${_subject}_$topic'],
      );

      _mcqs = [];
      _theoryQuestions = [];

      if (generateMcq) {
        final mcqPrompt = PromptTemplates.mcqs(
          _subject, _classLevel, topic, _difficulty,
        );
        Map<String, dynamic> mcqResult = {};
        if (widget.generateCallback != null) {
          mcqResult = await widget.generateCallback!(mcqPrompt);
        }
        final mcqRaw =
            mcqResult['raw'] as Map<String, dynamic>? ?? mcqResult;
        final mcqList = mcqRaw['questions'] as List<dynamic>? ?? [];
        _mcqs =
            mcqList.map((q) => Map<String, dynamic>.from(q as Map)).toList();
      }

      if (generateTheory) {
        final theoryPrompt = PromptTemplates.theoryQuestions(
          _subject, _classLevel, topic,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exam Editor'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text('Credits: $_creditBalance',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Subject dropdown
              DropdownButtonFormField<String>(
                initialValue: _subject,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  border: OutlineInputBorder(),
                ),
                items: _subjects
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _subject = v ?? _subject),
              ),
              const SizedBox(height: 12),

              // Class level dropdown
              DropdownButtonFormField<String>(
                initialValue: _classLevel,
                decoration: const InputDecoration(
                  labelText: 'Class',
                  border: OutlineInputBorder(),
                ),
                items: _classLevels
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _classLevel = v ?? _classLevel),
              ),
              const SizedBox(height: 12),

              // Topic text field
              TextFormField(
                controller: _topicController,
                decoration: const InputDecoration(
                  labelText: 'Topic',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Topic is required' : null,
              ),
              const SizedBox(height: 12),

              // Difficulty dropdown
              DropdownButtonFormField<String>(
                initialValue: _difficulty,
                decoration: const InputDecoration(
                  labelText: 'Difficulty',
                  border: OutlineInputBorder(),
                ),
                items: _difficulties
                    .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                    .toList(),
                onChanged: (v) => setState(() => _difficulty = v ?? _difficulty),
              ),
              const SizedBox(height: 12),
              Text('Question Type:',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              SegmentedButton<QuestionType>(
                segments: const [
                  ButtonSegment(
                      value: QuestionType.mcq, label: Text('MCQ')),
                  ButtonSegment(
                      value: QuestionType.theory, label: Text('Theory')),
                  ButtonSegment(
                      value: QuestionType.both, label: Text('Both')),
                ],
                selected: {_questionType},
                onSelectionChanged: (selection) {
                  setState(() => _questionType = selection.first);
                },
              ),
              const SizedBox(height: 20),

              // Generate button
              ElevatedButton.icon(
                onPressed: _isGenerating ? null : _handleGenerate,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isGenerating ? 'Generating...' : 'Generate'),
              ),
              const SizedBox(height: 20),

              // MCQ preview cards
              if (_hasGenerated && _mcqs.isNotEmpty) ...[
                Text('MCQs (${_mcqs.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...List.generate(_mcqs.length, (i) => _buildMcqCard(i)),
                const SizedBox(height: 20),
              ],

              // Theory preview cards
              if (_hasGenerated && _theoryQuestions.isNotEmpty) ...[
                Text('Theory Questions (${_theoryQuestions.length})',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...List.generate(
                    _theoryQuestions.length, (i) => _buildTheoryCard(i)),
                const SizedBox(height: 20),
              ],

              // Save / Discard buttons
              if (_hasGenerated)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveExam(),
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _discard,
                        icon: const Icon(Icons.clear),
                        label: const Text('Discard'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMcqCard(int index) {
    final mcq = _mcqs[index];
    final question = mcq['question'] as String? ?? '';
    final options = mcq['options'] as Map<String, dynamic>? ?? {};
    final correct = mcq['correct'] as String? ?? 'A';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Q${index + 1}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: question,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Question',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _updateMcq(index, 'question', v),
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: correct,
              onChanged: (v) => _updateMcq(index, 'correct', v ?? 'A'),
              child: Column(
                children: ['A', 'B', 'C', 'D'].map((key) {
                  final optVal = options[key] as String? ?? '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Radio<String>(value: key),
                        Expanded(
                          child: TextFormField(
                            initialValue: optVal,
                            decoration: InputDecoration(
                              labelText: 'Option $key',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                _updateMcqOption(index, key, v),
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
      ),
    );
  }

  Widget _buildTheoryCard(int index) {
    final theory = _theoryQuestions[index];
    final question = theory['question'] as String? ?? '';
    final modelAnswer = theory['modelAnswer'] as String? ?? '';
    final cognitiveLevel = theory['cognitiveLevel'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theory Q${index + 1}',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: question,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Question',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _updateTheory(index, 'question', v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: modelAnswer,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Model Answer',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _updateTheory(index, 'modelAnswer', v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: cognitiveLevel,
              decoration: const InputDecoration(
                labelText: 'Cognitive Level',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => _updateTheory(index, 'cognitiveLevel', v),
            ),
          ],
        ),
      ),
    );
  }
}
