// lib/core/widgets/question_cards.dart
//
// Shared MCQ / Theory / Subjective question cards used by both the exam
// editor and the lesson editor (Design A, Stage 3).
//
// Extracted from lib/features/exam/screens/exam_editor_screen.dart so the
// two editors render question cards identically. Each card supports:
//   - Editable mode (default, unlocked): question text, options, correct
//     answer key and model answer are editable through the update callbacks.
//   - Delete action: pass [onDelete] to show a delete button.
//   - Read-only mode ([readOnly], locked): renders the question content
//     without any editable fields.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:classai/core/theme/app_theme.dart';

/// Shared MCQ question card.
class McqQuestionCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> mcq;
  final ColorScheme cs;
  final ThemeData theme;
  final UndoHistoryController? undoController;

  /// Called with (index, field, value) when the question text or the
  /// correct-answer key changes.
  final void Function(int index, String field, String value)? onUpdateMcq;

  /// Called with (index, optionKey, value) when an option text changes.
  final void Function(int index, String optionKey, String value)?
      onUpdateMcqOption;

  /// When provided, a delete button is shown and this is invoked on tap.
  final VoidCallback? onDelete;

  /// When true, renders a read-only (locked) version of the card.
  final bool readOnly;

  const McqQuestionCard({
    super.key,
    required this.index,
    required this.mcq,
    required this.cs,
    required this.theme,
    this.undoController,
    this.onUpdateMcq,
    this.onUpdateMcqOption,
    this.onDelete,
    this.readOnly = false,
  });

  @override
  State<McqQuestionCard> createState() => _McqQuestionCardState();
}

class _McqQuestionCardState extends State<McqQuestionCard> {
  late final TextEditingController _questionController;
  late final Map<String, TextEditingController> _optionControllers;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final mcq = widget.mcq;
    final question = mcq['question'] as String? ?? '';
    final options = mcq['options'] as Map<String, dynamic>? ?? {};

    _questionController = TextEditingController(text: question)
      ..addListener(_onQuestionChanged);

    _optionControllers = {
      for (final key in ['A', 'B', 'C', 'D'])
        key: TextEditingController(text: options[key] as String? ?? '')
          ..addListener(() => _onOptionChanged(key)),
    };
  }

  @override
  void didUpdateWidget(McqQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the underlying question map changes (e.g. a card above was
    // deleted and this widget now renders a different question), resync the
    // local controllers so stale text is not shown.
    if (oldWidget.mcq != widget.mcq) {
      final nextQuestion = widget.mcq['question'] as String? ?? '';
      if (_questionController.text != nextQuestion) {
        _questionController.text = nextQuestion;
      }
      final options = widget.mcq['options'] as Map<String, dynamic>? ?? {};
      for (final key in ['A', 'B', 'C', 'D']) {
        final next = options[key] as String? ?? '';
        if (_optionControllers[key]!.text != next) {
          _optionControllers[key]!.text = next;
        }
      }
    }
  }

  void _onQuestionChanged() {
    widget.onUpdateMcq?.call(
      widget.index,
      'question',
      _questionController.text,
    );
  }

  void _onOptionChanged(String key) {
    widget.onUpdateMcqOption?.call(
      widget.index,
      key,
      _optionControllers[key]?.text ?? '',
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final cs = widget.cs;
    if (widget.readOnly) {
      return _buildReadOnly(theme, cs);
    }
    return _buildEditable(theme, cs);
  }

  Widget _buildReadOnly(ThemeData theme, ColorScheme cs) {
    final mcq = widget.mcq;
    final question = mcq['question'] as String? ?? '';
    final options = mcq['options'] as Map<String, dynamic>? ?? {};
    final correct = mcq['correct']?.toString() ?? 'A';

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
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Center(
              child: Text(
                '${widget.index + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ...options.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          entry.key == correct
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: entry.key == correct
                              ? cs.primary
                              : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${entry.key}. ${entry.value}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditable(ThemeData theme, ColorScheme cs) {
    final mcq = widget.mcq;
    final correct = mcq['correct']?.toString() ?? 'A';

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
                    '${widget.index + 1}',
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
                  controller: _questionController,
                  undoController: widget.undoController,
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
                ),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: cs.error,
                  tooltip: 'Delete question',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          // Options grid
          ...['A', 'B', 'C', 'D'].map((key) {
            final isCorrect = correct == key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  InkWell(
                    onTap: () =>
                        widget.onUpdateMcq?.call(widget.index, 'correct', key),
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusFull),
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
                      controller: _optionControllers[key]!,
                      undoController: widget.undoController,
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
}

/// Shared Theory / Subjective question card.
///
/// The answer field is bound to the `modelAnswer` key (theory style) which
/// mirrors `answer` (subjective style) after validation — matching the
/// behavior of the previous private card in the exam editor.
class TheoryQuestionCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> question;
  final ColorScheme cs;
  final ThemeData theme;
  final UndoHistoryController? undoController;

  /// Called with (index, field, value) when the question text or the model
  /// answer changes.
  final void Function(int index, String field, String value)? onUpdateTheory;

  /// When provided, a delete button is shown and this is invoked on tap.
  final VoidCallback? onDelete;

  /// When true, renders a read-only (locked) version of the card.
  final bool readOnly;

  const TheoryQuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.cs,
    required this.theme,
    this.undoController,
    this.onUpdateTheory,
    this.onDelete,
    this.readOnly = false,
  });

  @override
  State<TheoryQuestionCard> createState() => _TheoryQuestionCardState();
}

class _TheoryQuestionCardState extends State<TheoryQuestionCard> {
  late final TextEditingController _questionController;
  late final TextEditingController _answerController;

  @override
  void initState() {
    super.initState();
    _initControllers();
  }

  void _initControllers() {
    final q = widget.question;
    _questionController = TextEditingController(
      text: q['question'] as String? ?? '',
    )..addListener(_onQuestionChanged);

    _answerController = TextEditingController(
      text: q['modelAnswer'] as String? ?? q['answer'] as String? ?? '',
    )..addListener(_onAnswerChanged);
  }

  @override
  void didUpdateWidget(TheoryQuestionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.question != widget.question) {
      final nextQuestion = widget.question['question'] as String? ?? '';
      if (_questionController.text != nextQuestion) {
        _questionController.text = nextQuestion;
      }
      final nextAnswer = widget.question['modelAnswer'] as String? ??
          widget.question['answer'] as String? ??
          '';
      if (_answerController.text != nextAnswer) {
        _answerController.text = nextAnswer;
      }
    }
  }

  void _onQuestionChanged() {
    widget.onUpdateTheory?.call(
      widget.index,
      'question',
      _questionController.text,
    );
  }

  void _onAnswerChanged() {
    widget.onUpdateTheory?.call(
      widget.index,
      'modelAnswer',
      _answerController.text,
    );
  }

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final cs = widget.cs;
    if (widget.readOnly) {
      return _buildReadOnly(theme, cs);
    }
    return _buildEditable(theme, cs);
  }

  Widget _buildReadOnly(ThemeData theme, ColorScheme cs) {
    final q = widget.question;
    final question = q['question'] as String? ?? '';
    final answer = q['modelAnswer'] as String? ??
        q['answer'] as String? ??
        '';

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
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Center(
              child: Text(
                '${widget.index + 1}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
                if (answer.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Model answer:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    answer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditable(ThemeData theme, ColorScheme cs) {
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
                    '${widget.index + 1}',
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
                  controller: _questionController,
                  undoController: widget.undoController,
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
                ),
              ),
              if (widget.onDelete != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  color: cs.error,
                  tooltip: 'Delete question',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _answerController,
            undoController: widget.undoController,
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
          ),
        ],
      ),
    );
  }
}
