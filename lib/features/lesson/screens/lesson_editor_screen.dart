import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/emergency_flush_provider.dart';
import 'package:classai/core/services/ai_service.dart';
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
        setState(() =>
            _creditBalance = ref.read(creditStateProvider).currentCredits);
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

      // Spend credit
      final creditService = CreditService(ref.read(databaseProvider));
      await creditService.spendCredits(amount: 1, contentIds: ['lesson_draft']);

      // Generate via callback or fallback to AiService
      Map<String, dynamic> result;
      if (widget.generateCallback != null) {
        result = await widget.generateCallback!(prompt);
      } else {
        // Production path: call the AI generation service directly
        final aiService = AiService();
        result = await aiService.generate(prompt);
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
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    const v08 = SizedBox(height: 8);
    const v12 = SizedBox(height: 12);
    const v16 = SizedBox(height: 16);
    const v24 = SizedBox(height: 24);
    // v20 and h16; used inside build and preview-builder helpers

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
                  'Lesson Editor',
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

            // ── Scrollable content ───────────────────────────────
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

                            // Week spinner row
                            Row(
                              children: [
                                Text(
                                  'Week:',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainer,
                                    borderRadius: BorderRadius.circular(10),
                                    border:
                                        Border.all(color: cs.outlineVariant),
                                  ),
                                  child: Row(
                                    children: [
                                      InkWell(
                                        borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(10),
                                            bottomLeft: Radius.circular(10)),
                                        onTap: _week > 1
                                            ? () => setState(() => _week--)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          child: Icon(Icons.remove,
                                              size: 16, color: cs.onSurface),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerLowest,
                                          border: Border(
                                            left: BorderSide(
                                                color: cs.outlineVariant),
                                            right: BorderSide(
                                                color: cs.outlineVariant),
                                          ),
                                        ),
                                        child: Text(
                                          '$_week',
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                      ),
                                      InkWell(
                                        borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(10),
                                            bottomRight: Radius.circular(10)),
                                        onTap: _week < 52
                                            ? () => setState(() => _week++)
                                            : null,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 6),
                                          child: Icon(Icons.add,
                                              size: 16, color: cs.onSurface),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                              ],
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

                            // Bloom's verbs section heading
                            Text(
                              'Target Cognitive Levels:',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            v08,
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: _bloomVerbs.map((verb) {
                                final selected = _selectedBlooms.contains(verb);
                                return FilterChip(
                                  label: Text(
                                    verb,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: selected
                                          ? cs.onPrimaryContainer
                                          : cs.onSurfaceVariant,
                                    ),
                                  ),
                                  selected: selected,
                                  checkmarkColor: cs.onPrimaryContainer,
                                  backgroundColor: selected
                                      ? cs.primaryContainer
                                      : cs.surfaceContainer,
                                  side: BorderSide(
                                    color: selected
                                        ? cs.primaryContainer
                                        : cs.outlineVariant,
                                  ),
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

                      // ── Preview cards ──────────────────────────────
                      if (_hasGenerated) ..._buildPreviewSections(theme, cs),
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

  /// Returns a list of preview-section widgets once generation is complete.
  List<Widget> _buildPreviewSections(ThemeData theme, ColorScheme cs) {
    return [
      _buildPreviewCard(
        'Learning Objectives',
        _objectivesText,
        theme,
        cs,
        (v) => _objectivesText = v,
      ),
      const SizedBox(height: 12),
      _buildPreviewCard(
        'Key Vocabulary',
        _vocabularyText,
        theme,
        cs,
        (v) => _vocabularyText = v,
      ),
      const SizedBox(height: 12),
      _buildPreviewCard(
        'Materials',
        _materialsText,
        theme,
        cs,
        (v) => _materialsText = v,
      ),
      const SizedBox(height: 12),
      _buildPreviewCard(
        'Lesson Presentation',
        _presentationText,
        theme,
        cs,
        (v) => _presentationText = v,
      ),
      const SizedBox(height: 12),
      _buildPreviewCard(
        'Assessment',
        _assessmentText,
        theme,
        cs,
        (v) => _assessmentText = v,
      ),
      const SizedBox(height: 12),
      _buildPreviewCard(
        'Homework',
        _homeworkText,
        theme,
        cs,
        (v) => _homeworkText = v,
      ),
      const SizedBox(height: 20),

      // Save / Discard
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () => _saveLesson(),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _discard,
              icon: const Icon(Icons.delete_outline_rounded),
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
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildPreviewCard(
    String title,
    String content,
    ThemeData theme,
    ColorScheme cs,
    ValueChanged<String> onChanged,
  ) {
    return Container(
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
                width: 3,
                height: 18,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: content,
            maxLines: 6,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
