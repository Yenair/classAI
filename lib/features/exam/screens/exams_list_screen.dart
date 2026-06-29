import 'dart:convert';
import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide Column;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider that fetches all exams from the database.
final examsListProvider = FutureProvider<List<Exam>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.examsDao.getAll();
});

/// Displays a list of exams from the local database.
class ExamsListScreen extends ConsumerStatefulWidget {
  const ExamsListScreen({super.key});

  @override
  ConsumerState<ExamsListScreen> createState() => _ExamsListScreenState();
}

class _ExamsListScreenState extends ConsumerState<ExamsListScreen> {
  static const _termFilters = ['All', '1st Term', '2nd Term', '3rd Term'];
  static const _statusFilters = [
    _StatusFilterItem('All', Icons.layers_rounded),
    _StatusFilterItem('Draft', Icons.edit_note_rounded),
    _StatusFilterItem('Completed', Icons.check_circle_rounded),
    _StatusFilterItem('Unlocked', Icons.lock_open_rounded),
    _StatusFilterItem('Linked to Scheme', Icons.link_rounded),
    _StatusFilterItem('Needs Sync', Icons.sync_rounded),
  ];

  String _selectedStatusFilter = 'All';
  String _selectedTermFilter = 'All';
  String _selectedClassFilter = 'All';
  String _selectedSubjectFilter = 'All';
  bool _schemeDraftsBootstrapped = false;
  final Map<int, SchemeOfWorkData> _schemesById = {};

  static const _prefPrefix = 'exams_filter_';

  @override
  void initState() {
    super.initState();
    _loadFilterPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(creditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
      _bootstrapSchemeDrafts();
    });
  }

  Future<void> _loadFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedStatusFilter = prefs.getString('${_prefPrefix}status') ?? 'All';
      _selectedTermFilter = prefs.getString('${_prefPrefix}term') ?? 'All';
      _selectedClassFilter = prefs.getString('${_prefPrefix}class') ?? 'All';
      _selectedSubjectFilter = prefs.getString('${_prefPrefix}subject') ?? 'All';
    });
  }

  Future<void> _bootstrapSchemeDrafts() async {
    if (_schemeDraftsBootstrapped) return;
    _schemeDraftsBootstrapped = true;

    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) return;

      final schemes = (await db.schemeOfWorkDao.getApproved())
          .where((scheme) => scheme.schoolId == school.localId)
          .toList();
      if (schemes.isEmpty) return;

      final subjects = await db.subjectsDao.getAll();
      final subjectNamesById = <int, String>{
        for (final subject in subjects) subject.id: subject.name,
      };
      final lessons = await db.lessonsDao.getAll();
      final exams = await db.examsDao.getAll();
      final teacherServerId = authState.currentTeacher?.serverId;

      final schemeMap = <int, SchemeOfWorkData>{
        for (final scheme in schemes) scheme.id: scheme,
      };
      if (mounted) {
        setState(() {
          _schemesById
            ..clear()
            ..addAll(schemeMap);
        });
      } else {
        _schemesById
          ..clear()
          ..addAll(schemeMap);
      }

      final existingDraftKeys = <String>{};
      for (final exam in exams) {
        final termLabel = _termLabelForExam(exam);
        if (termLabel == null || exam.weekNumber == null) continue;
        existingDraftKeys.add(
          _draftKey(
            subject: exam.subject,
            classLevel: exam.classLevel,
            term: termLabel,
            weekNumber: exam.weekNumber!,
          ),
        );
      }

      var insertedCount = 0;
      for (final scheme in schemes) {
        final subjectName = subjectNamesById[scheme.subjectId];
        if (subjectName == null || subjectName.isEmpty) continue;

        final classLevel = _inferClassLevelForScheme(
          scheme: scheme,
          subjectName: subjectName,
          lessons: lessons,
          exams: exams,
          teacherServerId: teacherServerId,
        );
        if (classLevel == null || classLevel.isEmpty) continue;

        final termLabel = _normalizeTermLabel(scheme.term);
        if (termLabel.isEmpty) continue;

        final key = _draftKey(
          subject: subjectName,
          classLevel: classLevel,
          term: termLabel,
          weekNumber: scheme.weekNumber,
        );
        if (existingDraftKeys.contains(key)) continue;

        final existingForScheme = exams.any((exam) {
          final linkedSchemeId = int.tryParse(exam.schemeOfWorkId ?? '');
          return linkedSchemeId == scheme.id &&
              exam.subject == subjectName &&
              exam.classLevel == classLevel &&
              exam.weekNumber == scheme.weekNumber &&
              !exam.isDeleted;
        });
        if (existingForScheme) {
          existingDraftKeys.add(key);
          continue;
        }

        await db.examsDao.insertExam(
          ExamsCompanion.insert(
            subject: subjectName,
            classLevel: classLevel,
            topic: scheme.adminEditedTopic ?? scheme.topic,
            difficulty: 'medium',
            curriculum: 'NERDC',
            content: jsonEncode({
              'mcqs': const [],
              'theory': const [],
              'subjective': const [],
            }),
            teacherServerId: teacherServerId != null
                ? Value(teacherServerId)
                : const Value.absent(),
            schoolServerId: school.serverId != null
                ? Value(school.serverId)
                : const Value.absent(),
            isUnlocked: const Value(false),
            schemeOfWorkId: Value(scheme.id.toString()),
            weekNumber: Value(scheme.weekNumber),
            createdAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
            isDeleted: const Value(false),
          ),
        );
        existingDraftKeys.add(key);
        insertedCount++;
      }

      if (insertedCount > 0 && mounted) {
        ref.invalidate(examsListProvider);
      }
    } catch (_) {
      // Keep the screen silent if draft seeding fails.
    }
  }

  List<Exam> _applyFilters(List<Exam> exams) {
    return exams.where((exam) {
      if (!_matchesStatusFilter(exam)) return false;
      if (!_matchesTermFilter(exam)) return false;
      if (!_matchesClassFilter(exam)) return false;
      if (!_matchesSubjectFilter(exam)) return false;
      return true;
    }).toList();
  }

  bool _matchesStatusFilter(Exam exam) {
    switch (_selectedStatusFilter) {
      case 'Draft':
        return !exam.isUnlocked;
      case 'Completed':
      case 'Unlocked':
        return exam.isUnlocked;
      case 'Linked to Scheme':
        return exam.schemeOfWorkId != null;
      case 'Needs Sync':
        return exam.serverId == null;
      default:
        return true;
    }
  }

  bool _matchesTermFilter(Exam exam) {
    if (_selectedTermFilter == 'All') return true;
    final termLabel = _termLabelForExam(exam);
    return termLabel == _selectedTermFilter;
  }

  bool _matchesClassFilter(Exam exam) {
    if (_selectedClassFilter == 'All') return true;
    return exam.classLevel == _selectedClassFilter;
  }

  bool _matchesSubjectFilter(Exam exam) {
    if (_selectedSubjectFilter == 'All') return true;
    return exam.subject == _selectedSubjectFilter;
  }

  void _setStatusFilter(String filter) {
    setState(() => _selectedStatusFilter = filter);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}status', filter);
    });
  }

  void _setTermFilter(String filter) {
    setState(() => _selectedTermFilter = filter);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}term', filter);
    });
  }

  void _setClassFilter(String filter) {
    setState(() => _selectedClassFilter = filter);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}class', filter);
    });
  }

  void _setSubjectFilter(String filter) {
    setState(() => _selectedSubjectFilter = filter);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('${_prefPrefix}subject', filter);
    });
  }

  List<String> _buildFilterOptions(Iterable<String> values) {
    final items = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All', ...items];
  }

  String? _termLabelForExam(Exam exam) {
    // Use the real term column first
    if (exam.term != null && exam.term!.trim().isNotEmpty) {
      final normalized = _normalizeTermLabel(exam.term!);
      if (normalized.isNotEmpty) return normalized;
    }

    // Fall back to linked scheme of work
    final schemeId = int.tryParse(exam.schemeOfWorkId ?? '');
    if (schemeId == null) return null;
    final scheme = _schemesById[schemeId];
    if (scheme == null) return null;
    return _normalizeTermLabel(scheme.term);
  }

  String _classLevelLabelForExam(Exam exam) {
    final termLabel = _termLabelForExam(exam);
    if (termLabel == null || termLabel.isEmpty) {
      return exam.classLevel;
    }
    return '${exam.classLevel} ($termLabel)';
  }

  String _draftKey({
    required String subject,
    required String classLevel,
    required String term,
    required int weekNumber,
  }) {
    return '${subject.trim().toLowerCase()}|${classLevel.trim().toLowerCase()}|'
        '${term.trim().toLowerCase()}|$weekNumber';
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

  String? _inferClassLevelForScheme({
    required SchemeOfWorkData scheme,
    required String subjectName,
    required List<Lesson> lessons,
    required List<Exam> exams,
    required String? teacherServerId,
  }) {
    final schemeId = scheme.id.toString();
    final linkedLessons = lessons.where((lesson) {
      if (lesson.isDeleted) return false;
      if (lesson.schemeOfWorkId != schemeId) return false;
      if (teacherServerId != null && lesson.teacherServerId != teacherServerId) {
        return false;
      }
      return true;
    }).toList();
    if (linkedLessons.isNotEmpty) {
      return linkedLessons.first.classLevel;
    }

    final matchingLessons = lessons.where((lesson) {
      if (lesson.isDeleted) return false;
      if (teacherServerId != null && lesson.teacherServerId != teacherServerId) {
        return false;
      }
      if (lesson.subject != subjectName) return false;
      final lessonWeek = lesson.weekNumber ?? lesson.week;
      return lessonWeek == scheme.weekNumber;
    }).toList();
    if (matchingLessons.isNotEmpty) {
      return matchingLessons.first.classLevel;
    }

    final linkedExams = exams.where((exam) {
      if (exam.isDeleted) return false;
      final linkedSchemeId = int.tryParse(exam.schemeOfWorkId ?? '');
      return linkedSchemeId == scheme.id;
    }).toList();
    if (linkedExams.isNotEmpty) {
      return linkedExams.first.classLevel;
    }

    return null;
  }

  String _createExamLocation({
    required String subject,
    required String classLevel,
    required String term,
  }) {
    final queryParameters = <String, String>{};
    if (subject.isNotEmpty) queryParameters['subject'] = subject;
    if (classLevel.isNotEmpty) queryParameters['classLevel'] = classLevel;
    if (term.isNotEmpty) queryParameters['term'] = term;
    return Uri(
      path: '/exam-editor',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  void _openNewExam() {
    final subject = _selectedSubjectFilter == 'All' ? '' : _selectedSubjectFilter;
    final classLevel =
        _selectedClassFilter == 'All' ? '' : _selectedClassFilter;
    final term = _selectedTermFilter == 'All' ? '' : _selectedTermFilter;
    context.push(
      _createExamLocation(
        subject: subject,
        classLevel: classLevel,
        term: term,
      ),
    );
  }

  Future<void> _confirmDeleteExam(Exam exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Exam'),
        content: Text('Are you sure you want to delete "${exam.topic}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final db = ref.read(databaseProvider);
        await db.examsDao.deleteExam(exam.id);
        await db.syncQueueDao.insertEntry(
          queueTable: 'exams',
          recordLocalId: exam.id,
          operation: 'DELETE',
          payload: {
            'id': exam.id,
            if (exam.serverId != null) 'server_id': exam.serverId,
          },
        );
        ref.invalidate(examsListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exam deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsListProvider);
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
          'Exams',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
        ),
          actions: [
            const SyncIndicator(),
            const SizedBox(width: 8),
            CreditCounter(visible: ref.watch(isOfflineProvider)),
            const SizedBox(width: 8),
          ],
        elevation: 0,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: cs.surface,
      ),
      body: Column(
        children: [
          const ConflictBanner(),
          Expanded(
            child: examsAsync.when(
              loading: () => ListView(
                physics: (Platform.isAndroid || Platform.isIOS)
                    ? const BouncingScrollPhysics()
                    : null,
                padding: const EdgeInsets.all(16),
                children: List.generate(
                  4,
                  (i) => _ExamCardSkeleton(cs: cs),
                ),
              ),
              error: (error, stack) => Center(
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
                        'Failed to load exams',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$error',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: () => ref.invalidate(examsListProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (exams) {
                final filteredExams = _applyFilters(exams);
                filteredExams.sort((a, b) => (a.weekNumber ?? 0).compareTo(b.weekNumber ?? 0));
                final termOptions = _termFilters;
                final classOptions = _buildFilterOptions(
                  exams.map((exam) => exam.classLevel),
                );
                final subjectOptions = _buildFilterOptions(
                  exams.map((exam) => exam.subject),
                );

                final filterPanel = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: _ExamFiltersPanel(
                    cs: cs,
                    theme: theme,
                    selectedStatusFilter: _selectedStatusFilter,
                    selectedTermFilter: _selectedTermFilter,
                    selectedClassFilter: _selectedClassFilter,
                    selectedSubjectFilter: _selectedSubjectFilter,
                    statusFilters: _statusFilters,
                    termFilters: termOptions,
                    classFilters: classOptions,
                    subjectFilters: subjectOptions,
                    onStatusChanged: _setStatusFilter,
                    onTermChanged: _setTermFilter,
                    onClassChanged: _setClassFilter,
                    onSubjectChanged: _setSubjectFilter,
                  ),
                );

                if (exams.isEmpty) {
                  return Column(
                    children: [
                      filterPanel,
                      Expanded(
                        child: ListView(
                          physics: (Platform.isAndroid || Platform.isIOS)
                              ? const BouncingScrollPhysics()
                              : null,
                          padding: const EdgeInsets.all(32),
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainer,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Icon(
                                      Icons.quiz_rounded,
                                      size: 38,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No exams yet',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Tap New Exam to create one.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                if (filteredExams.isEmpty) {
                  return Column(
                    children: [
                      filterPanel,
                      Expanded(
                        child: ListView(
                          physics: (Platform.isAndroid || Platform.isIOS)
                              ? const BouncingScrollPhysics()
                              : null,
                          padding: const EdgeInsets.all(32),
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainer,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Icon(
                                      Icons.filter_alt_off_rounded,
                                      size: 38,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No exams match the selected filters',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Try a different filter or clear it to see all exams.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    filterPanel,
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async => ref.invalidate(examsListProvider),
                        child: ListView.builder(
                          physics: (Platform.isAndroid || Platform.isIOS)
                              ? const BouncingScrollPhysics()
                              : null,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: filteredExams.length,
                          itemBuilder: (context, index) {
                            final exam = filteredExams[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ExamCard(
                                exam: exam,
                                classLevelLabel: _classLevelLabelForExam(exam),
                                onTap: () => context.push('/exams/${exam.id}'),
                                onEdit: () => context.push('/exams/${exam.id}'),
                                onDelete: () => _confirmDeleteExam(exam),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.30),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _openNewExam,
          heroTag: 'newExam',
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'New Exam',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ExamFiltersPanel extends StatelessWidget {
  const _ExamFiltersPanel({
    required this.cs,
    required this.theme,
    required this.selectedStatusFilter,
    required this.selectedTermFilter,
    required this.selectedClassFilter,
    required this.selectedSubjectFilter,
    required this.statusFilters,
    required this.termFilters,
    required this.classFilters,
    required this.subjectFilters,
    required this.onStatusChanged,
    required this.onTermChanged,
    required this.onClassChanged,
    required this.onSubjectChanged,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final String selectedStatusFilter;
  final String selectedTermFilter;
  final String selectedClassFilter;
  final String selectedSubjectFilter;
  final List<_StatusFilterItem> statusFilters;
  final List<String> termFilters;
  final List<String> classFilters;
  final List<String> subjectFilters;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onTermChanged;
  final ValueChanged<String> onClassChanged;
  final ValueChanged<String> onSubjectChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: statusFilters.map((item) {
                final selected = item.label == selectedStatusFilter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(
                      item.icon,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    label: Text(item.label),
                    selected: selected,
                    showCheckmark: false,
                    onSelected: (_) => onStatusChanged(item.label),
                    labelStyle: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    backgroundColor: cs.surfaceContainerLow,
                    selectedColor: cs.primaryContainer.withValues(alpha: 0.45),
                    side: BorderSide(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.25)
                          : cs.outlineVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: _FilterDropdownField(
                  cs: cs,
                  label: 'Term',
                  value: selectedTermFilter,
                  items: termFilters,
                  onChanged: onTermChanged,
                ),
              ),
              SizedBox(
                width: 220,
                child: _FilterDropdownField(
                  cs: cs,
                  label: 'Class Level',
                  value: selectedClassFilter,
                  items: classFilters,
                  onChanged: onClassChanged,
                ),
              ),
              SizedBox(
                width: 220,
                child: _FilterDropdownField(
                  cs: cs,
                  label: 'Subject',
                  value: selectedSubjectFilter,
                  items: subjectFilters,
                  onChanged: onSubjectChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdownField extends StatelessWidget {
  const _FilterDropdownField({
    required this.cs,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final ColorScheme cs;
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : 'All',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: cs.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _StatusFilterItem {
  const _StatusFilterItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _ExamCard extends StatelessWidget {
  final Exam exam;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExamCard({
    required this.exam,
    required this.classLevelLabel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.onSurface.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: cs.tertiary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exam.topic,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          exam.subject,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    classLevelLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDate(exam.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit_rounded, size: 20, color: cs.primary),
                      onPressed: onEdit,
                      tooltip: 'Edit',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 20,
                        color: cs.error,
                      ),
                      onPressed: onDelete,
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamCardSkeleton extends StatelessWidget {
  const _ExamCardSkeleton({required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 160,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        height: 20,
                        width: 64,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 20,
                        width: 92,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              height: 14,
              width: 48,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
