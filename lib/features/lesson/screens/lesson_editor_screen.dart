import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/services/emergency_flush_service.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Material Design lesson note editor with AI generation.
///
/// Form fields: Subject dropdown, Class dropdown, Week spinbox,
/// Topic textfield, Difficulty dropdown, Bloom's verbs multi-select chips.
/// "Generate" builds a prompt, calls the provided [generateCallback],
/// then populates preview cards with editable text fields per section.
/// "Save" inserts into `lessons` table.
/// Registers with [EmergencyFlushService] on init.
class LessonEditorScreen extends ConsumerStatefulWidget {
  /// Callback invoked with the generated prompt; returns parsed JSON map.
  /// In production this wraps [AiService.generate]; in tests a mock is used.
  final Future<Map<String, dynamic>> Function(String prompt)?
      generateCallback;

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
  final Set<String> _selectedBlooms = {};
  bool _isGenerating = false;
  bool _hasGenerated = false;
  int _creditBalance = 0;
  String? _encryptedContent;

  // Generated content (editable after generation)
  String _objectivesText = '';
  String _vocabularyText = '';
  String _materialsText = '';
  String _presentationText = '';
  String _assessmentText = '';
  String _homeworkText = '';

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

  final List<String> _bloomVerbs = [
    'Remember', 'Understand', 'Apply', 'Analyze', 'Evaluate', 'Create',
  ];

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
        await _saveLesson(notify: false);
      }
    });
  }

  Future<void> _loadCreditBalance() async {
    try {
      await ref.read(creditStateProvider.notifier).refresh();
      if (mounted) {
        setState(() => _creditBalance = ref.read(creditStateProvider).currentCredits);
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
      // Build prompt
      final bloomsStr = _selectedBlooms.isEmpty
          ? 'All levels'
          : _selectedBlooms.join(', ');
      final prompt = PromptTemplates.lessonNote(
        _subject,
        'NERDC',
        _classLevel,
        _week,
        _topicController.text.trim(),
        _difficulty,
        bloomsStr,
      );

      // Spend credit
      final creditService = CreditService(ref.read(databaseProvider));
      await creditService.spendCredits(amount: 1, contentIds: ['lesson_draft']);

      // Generate via callback or fallback
      Map<String, dynamic> result;
      if (widget.generateCallback != null) {
        result = await widget.generateCallback!(prompt);
      } else {
        // No callback provided – prompt is built for external use
        // (e.g. manual generation or future integration)
        result = <String, dynamic>{};
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Generate callback not configured. '
                  'Prompt ready for external AI service.'),
            ),
          );
        }
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
        _creditBalance = _creditBalance - 1;
        _isGenerating = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson generated successfully!')),
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
      final id = await db.into(db.lessons).insert(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lesson saved (id=$id)')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lesson Editor'),
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

              // Week spinbox
              Row(
                children: [
                  const Text('Week:'),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _week > 1
                        ? () => setState(() => _week--)
                        : null,
                  ),
                  Text('$_week', style: theme.textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _week < 52
                        ? () => setState(() => _week++)
                        : null,
                  ),
                ],
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

              // Bloom's verbs multi-select chips
              const Text('Target Cognitive Levels:'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: _bloomVerbs.map((verb) {
                  final selected = _selectedBlooms.contains(verb);
                  return FilterChip(
                    label: Text(verb),
                    selected: selected,
                    onSelected: (sel) {
                      setState(() {
                        if (sel) {
                          _selectedBlooms.add(verb);
                        } else {
                          _selectedBlooms.remove(verb);
                        }
                      });
                    },
                  );
                }).toList(),
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

              // Preview cards (shown after generation)
              if (_hasGenerated) ...[
                _buildPreviewCard('Learning Objectives', _objectivesText,
                    (v) => _objectivesText = v),
                _buildPreviewCard('Key Vocabulary', _vocabularyText,
                    (v) => _vocabularyText = v),
                _buildPreviewCard('Materials', _materialsText,
                    (v) => _materialsText = v),
                _buildPreviewCard('Lesson Presentation', _presentationText,
                    (v) => _presentationText = v),
                _buildPreviewCard('Assessment', _assessmentText,
                    (v) => _assessmentText = v),
                _buildPreviewCard('Homework', _homeworkText,
                    (v) => _homeworkText = v),
                const SizedBox(height: 20),

                // Save / Discard buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _saveLesson(),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(
      String title, String content, ValueChanged<String> onChanged) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: content,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
