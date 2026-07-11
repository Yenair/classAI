import 'dart:convert';
import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide Column;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Holds topic info from the scheme of work for the full-term exam builder.
class _TopicEntry {
  final SchemeOfWorkData scheme;
  int questionCount;
  bool hasLesson;

  _TopicEntry({
    required this.scheme,
    this.questionCount = 5,
    this.hasLesson = false,
  });
}

/// Screen that lets a teacher build a full-term exam by selecting topics from
/// the scheme of work and assigning question counts per topic.
class FullTermExamScreen extends ConsumerStatefulWidget {
  const FullTermExamScreen({super.key});

  @override
  ConsumerState<FullTermExamScreen> createState() =>
      _FullTermExamScreenState();
}

class _FullTermExamScreenState extends ConsumerState<FullTermExamScreen> {
  List<_TopicEntry> _topics = [];
  bool _isLoading = true;
  bool _isGenerating = false;
  String? _error;
  final _totalQuestionsController = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSchemes());
  }

  @override
  void dispose() {
    _totalQuestionsController.dispose();
    super.dispose();
  }

  Future<void> _loadSchemes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final authData = ref.read(authProvider);
      final teacher = authData.currentTeacher;
      final school = authData.currentSchool;

      if (teacher == null || school == null) {
        setState(() {
          _error = 'Teacher or school data not available.';
          _isLoading = false;
        });
        return;
      }

      // Get all schemes for this school (draft, pending, approved - not rejected)
      final allSchemes = await db.schemeOfWorkDao.getBySchool(school.localId);
      final activeSchemes = allSchemes
          .where((s) => !s.isDeleted && s.status != 'rejected')
          .toList();

      if (activeSchemes.isEmpty) {
        setState(() {
          _error = 'No scheme of work entries found. '
              'Please create a scheme of work first.';
          _isLoading = false;
        });
        return;
      }

      // Get all lessons to check which topics have generated lessons
      final lessons = await db.lessonsDao.getAll();
      final lessonTopics = lessons
          .where((l) =>
              l.teacherServerId == teacher.serverId && !l.isDeleted)
          .map((l) => l.topic.trim().toLowerCase())
          .toSet();

      // Build topic entries, sorted by week number
      final sortedSchemes = List<SchemeOfWorkData>.from(activeSchemes)
        ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));

      final topics = sortedSchemes
          .map((scheme) => _TopicEntry(
                scheme: scheme,
                questionCount: 5,
                hasLesson: lessonTopics
                    .contains(scheme.topic.trim().toLowerCase()),
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _topics = topics;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load schemes: $e';
        _isLoading = false;
      });
    }
  }

  void _autoDistribute() {
    final totalText = _totalQuestionsController.text.trim();
    final total = int.tryParse(totalText);
    if (total == null || total <= 0) {
      showErrorToast(context: context, message: 'Enter a valid total question count.');
      return;
    }

    if (_topics.isEmpty) return;

    final base = total ~/ _topics.length;
    var remainder = total % _topics.length;

    setState(() {
      for (var i = 0; i < _topics.length; i++) {
        _topics[i].questionCount = base + (i < remainder ? 1 : 0);
      }
    });

    showInfoToast(
      context: context,
      message: 'Distributed $total questions across ${_topics.length} topics.',
    );
  }

  Future<void> _generateExam() async {
    // Validate that at least one topic has questions
    final hasQuestions = _topics.any((t) => t.questionCount > 0);
    if (!hasQuestions) {
      showErrorToast(context: context, message: 'Assign at least one question to a topic.');
      return;
    }

    // Tier gate: check school tier against allowed tiers for exam generation
    final authTier = ref.read(authProvider).currentSchool?.subscriptionTier.toLowerCase() ?? '';
    final config = ref.read(configServiceProvider);
    final allowedTiers = config.examGenerationAllowedTiers;
    if (!allowedTiers.contains(authTier)) {
      showErrorToast(
        context: context,
        message: 'Contact your school admin to upgrade.',
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final db = ref.read(databaseProvider);
      final authData = ref.read(authProvider);
      final teacher = authData.currentTeacher;
      final school = authData.currentSchool;

      if (teacher == null || school == null) {
        showErrorToast(context: context, message: 'Authentication data not available.');
        setState(() => _isGenerating = false);
        return;
      }

      // Build a combined prompt from all selected topics
      final topicParts = <String>[];
      var totalMcq = 0;
      var totalTheory = 0;
      var totalSubjective = 0;

      for (final entry in _topics) {
        if (entry.questionCount <= 0) continue;
        topicParts.add(
          '- Week ${entry.scheme.weekNumber}: "${entry.scheme.topic}" '
          '(${entry.questionCount} questions)',
        );
        // Distribute across question types evenly
        final mcq = (entry.questionCount * 0.5).round();
        final theory = (entry.questionCount * 0.3).round();
        final subjective =
            entry.questionCount - mcq - theory;
        totalMcq += mcq;
        totalTheory += theory;
        totalSubjective += subjective;
      }

      // Build prompt
      final typeCounts = <String, int>{
        'MCQ': totalMcq > 0 ? totalMcq : 0,
        'Theory': totalTheory > 0 ? totalTheory : 0,
        'Subjective': totalSubjective > 0 ? totalSubjective : 0,
      };

      final prompt = PromptTemplates.examQuestions(
        _topics.first.scheme.topic, // main topic
        _topics.first.scheme.classLevel.isNotEmpty
            ? _topics.first.scheme.classLevel
            : 'JSS 1',
        topicParts.join('\n'),
        'medium',
        typeCounts,
      );

      // Call AI
      final aiService = AiService(db: db);
      final result = await aiService.generate(prompt);

      // Parse the result
      Map<String, dynamic> content;
      if (result.containsKey('encryptedContent')) {
        // Content is encrypted, use the raw field
        content = Map<String, dynamic>.from(result['raw'] as Map);
      } else {
        content = result;
      }

      // Build exam content JSON
      final examContent = {
        'mcqs': (content['mcq'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            (content['mcqs'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            (content['questions'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[],
        'theory': (content['theory'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[],
        'subjective': (content['subjective'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            <Map<String, dynamic>>[],
      };

      // Build the subject/topic name for the exam
      final subjectName = _topics.first.scheme.topic;
      final classLevel = _topics.first.scheme.classLevel.isNotEmpty
          ? _topics.first.scheme.classLevel
          : 'JSS 1';
      final termLabel = _normalizeTermLabel(_topics.first.scheme.term);

      // Save as a draft exam
      final insertCompanion = ExamsCompanion.insert(
        subject: subjectName,
        classLevel: classLevel,
        topic: 'Full-Term Exam (${_topics.length} topics)',
        difficulty: 'medium',
        curriculum: 'NERDC',
        content: jsonEncode(examContent),
        teacherServerId: Value(teacher.serverId),
        schoolServerId: Value(school.serverId),
        isUnlocked: const Value(false),
        term: termLabel.isNotEmpty ? Value(termLabel) : const Value.absent(),
      );

      final examId = await db.examsDao.insertExam(insertCompanion);

      // Queue sync entry
      await db.syncQueueDao.insertEntry(
        queueTable: 'exams',
        recordLocalId: examId,
        operation: 'INSERT',
        payload: {
          'subject': subjectName,
          'classLevel': classLevel,
          'topic': 'Full-Term Exam (${_topics.length} topics)',
          'difficulty': 'medium',
          'curriculum': 'NERDC',
          'teacher_server_id': teacher.serverId,
          'school_server_id': school.serverId,
          if (termLabel.isNotEmpty) 'term': termLabel,
        },
      );

      if (!mounted) return;
      setState(() => _isGenerating = false);

      showInfoToast(
        context: context,
        message: 'Full-term exam created as draft!',
      );

      // Navigate to the exam editor to view it
      context.push('/exams/$examId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      showErrorToast(context: context, message: 'Failed to generate exam: $e');
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      appBar: AppBar(
        leading: canPop
            ? IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
              )
            : null,
        title: Text(
          'Full-Term Exam',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
        ),
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
      ),
      body: _buildBody(cs, theme),
    );
  }

  Widget _buildBody(ColorScheme cs, ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 34,
                  color: cs.onErrorContainer,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loadSchemes,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            physics: (Platform.isAndroid || Platform.isIOS)
                ? const BouncingScrollPhysics()
                : null,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _topics.length,
            itemBuilder: (context, index) {
              final entry = _topics[index];
              final scheme = entry.scheme;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TopicCard(
                  weekNumber: scheme.weekNumber,
                  topicName: scheme.adminEditedTopic ?? scheme.topic,
                  questionCount: entry.questionCount,
                  hasLesson: entry.hasLesson,
                  onQuestionCountChanged: (value) {
                    setState(() => entry.questionCount = value);
                  },
                  cs: cs,
                  theme: theme,
                ),
              );
            },
          ),
        ),
        // Bottom action bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Total questions row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _totalQuestionsController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Total Questions',
                          filled: true,
                          fillColor: cs.surfaceContainerLow,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide:
                                BorderSide(color: cs.outlineVariant),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _autoDistribute,
                      icon: const Icon(Icons.shuffle_rounded, size: 20),
                      label: const Text('Auto-Distribute'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGenerating ? null : _generateExam,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                        _isGenerating ? 'Generating...' : 'Generate Exam'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  final int weekNumber;
  final String topicName;
  final int questionCount;
  final bool hasLesson;
  final ValueChanged<int> onQuestionCountChanged;
  final ColorScheme cs;
  final ThemeData theme;

  const _TopicCard({
    required this.weekNumber,
    required this.topicName,
    required this.questionCount,
    required this.hasLesson,
    required this.onQuestionCountChanged,
    required this.cs,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Week badge
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                ),
                child: Center(
                  child: Text(
                    'W$weekNumber',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimaryContainer,
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
                      topicName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    if (!hasLesson) ...[
                      const SizedBox(height: 4),
                      Text(
                        'No lesson yet — generate one first',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Question count input
              SizedBox(
                width: 72,
                child: TextField(
                  controller: TextEditingController(
                    text: questionCount.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: cs.surfaceContainer,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.outlineVariant),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    isDense: true,
                    labelText: 'Q',
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  onChanged: (value) {
                    final count = int.tryParse(value);
                    if (count != null && count >= 0) {
                      onQuestionCountChanged(count);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
