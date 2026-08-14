import 'dart:io' show Platform;

import 'package:classai/core/constants/curriculum_types.dart' show nerdcSubjects;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/exam_generation_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show examsListProvider;
import 'package:classai/main.dart' show databaseProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// examsListProvider is defined in
/// lib/features/dashboard/providers/dashboard_data_providers.dart.

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
    _StatusFilterItem('Generated', Icons.auto_awesome_rounded),
    _StatusFilterItem('Needs Sync', Icons.sync_rounded),
  ];

  String _selectedStatusFilter = 'All';
  String _selectedTermFilter = 'All';
  String _selectedClassFilter = 'All';
  String _selectedSubjectFilter = 'All';
  bool _filtersExpanded = true;
  bool _schemesLoaded = false;
  bool _isGeneratingWeekly = false;
  final Map<int, SchemeOfWorkData> _schemesById = {};

  static const _prefPrefix = 'exams_filter_';
  static const _prefWeeklySubject = 'weekly_exams_subject';
  static const _prefWeeklyClass = 'weekly_exams_class';
  static const _prefWeeklyTerm = 'weekly_exams_term';

  @override
  void initState() {
    super.initState();
    _loadFilterPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(offlineCreditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
      _loadSchemesForDisplay();
    });
  }

  Future<void> _loadFilterPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedStatusFilter = prefs.getString('${_prefPrefix}status') ?? 'All';
      _selectedTermFilter = prefs.getString('${_prefPrefix}term') ?? 'All';
      _selectedClassFilter = prefs.getString('${_prefPrefix}class') ?? 'All';
      _selectedSubjectFilter = prefs.getString('${_prefPrefix}subject') ?? 'All';
      _filtersExpanded = prefs.getBool('exams_filters_expanded') ?? true;
    });
  }

  Future<void> _toggleFiltersExpanded() async {
    setState(() => _filtersExpanded = !_filtersExpanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('exams_filters_expanded', _filtersExpanded);
  }

  /// Populates the scheme lookup used to display term labels on exam cards.
  /// Does NOT create exams — exam creation is now exclusively explicit
  /// ("Generate Weekly Exams" and "Term Exam / CA Test"); the old silent
  /// draft-exam seeding from saved schemes was removed.
  Future<void> _loadSchemesForDisplay() async {
    if (_schemesLoaded) return;
    _schemesLoaded = true;

    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) return;

      final schemes = (await db.schemeOfWorkDao.getSaved())
          .where((scheme) => scheme.schoolId == school.localId)
          .toList();
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
    } catch (_) {
      // Display-only; failure is not worth interrupting the screen.
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
      case 'Generated':
        return exam.isUnlocked;
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
    final weekLabel = exam.weekNumber != null ? ' - Week ${exam.weekNumber}' : '';
    if (termLabel == null || termLabel.isEmpty) {
      return '${exam.classLevel}$weekLabel';
    }
    return '${exam.classLevel} ($termLabel)$weekLabel';
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

  /// Opens the normal exam editor in the combined-exam mode. The teacher then
  /// picks Term Exam or CA Test inside the editor. Pre-fills subject/class/
  /// term from the active filters when they are set.
  void _openCombinedExam() {
    final subject = _selectedSubjectFilter == 'All' ? '' : _selectedSubjectFilter;
    final classLevel =
        _selectedClassFilter == 'All' ? '' : _selectedClassFilter;
    final term = _selectedTermFilter == 'All' ? '' : _selectedTermFilter;
    final queryParameters = <String, String>{
      'compilationType': 'termExam',
      if (subject.isNotEmpty) 'subject': subject,
      if (classLevel.isNotEmpty) 'classLevel': classLevel,
      if (term.isNotEmpty) 'term': term,
    };
    context.push(
      Uri(
        path: '/exam-editor',
        queryParameters: queryParameters,
      ).toString(),
    );
  }

  /// Opens the "Generate Weekly Exams" dialog, pre-filled from the active
  /// filters or last-used values, then runs the generation.
  Future<void> _openGenerateWeeklyExams() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSubject = prefs.getString(_prefWeeklySubject) ?? 'Mathematics';
    final savedClass = prefs.getString(_prefWeeklyClass) ?? 'JSS 1';
    final savedTerm = prefs.getString(_prefWeeklyTerm) ?? '1st Term';

    final subject =
        _selectedSubjectFilter != 'All' ? _selectedSubjectFilter : savedSubject;
    final classLevel =
        _selectedClassFilter != 'All' ? _selectedClassFilter : savedClass;
    final termLabel =
        _selectedTermFilter != 'All' ? _selectedTermFilter : savedTerm;

    // Subject options = any subject the teacher filters on + the curated
    // subjects, so a filter like "French" stays selected instead of silently
    // falling back to Mathematics.
    final filterSubjects = _selectedSubjectFilter != 'All'
        ? [_selectedSubjectFilter]
        : const <String>[];
    final subjectOptions =
        <String>[...filterSubjects, ...nerdcSubjects].toSet().toList();

    final selection = await showDialog<_WeeklyExamsSelection>(
      context: context,
      builder: (ctx) => _WeeklyExamsDialog(
        subjectOptions: subjectOptions,
        initialSubject: subject,
        initialClassLevel: classLevel,
        initialTerm: termLabel,
      ),
    );
    if (selection == null || !mounted) return;

    await prefs.setString(_prefWeeklySubject, selection.subject);
    await prefs.setString(_prefWeeklyClass, selection.classLevel);
    await prefs.setString(_prefWeeklyTerm, selection.termLabel);

    await _runGenerateWeeklyExams(selection);
  }

  Future<void> _runGenerateWeeklyExams(_WeeklyExamsSelection selection) async {
    setState(() => _isGeneratingWeekly = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      final teacherServerId = authState.currentTeacher?.serverId;
      if (school == null || teacherServerId == null) {
        _showToast('Teacher or school data not available.');
        return;
      }
      final teacher = await db.teachersDao.findByServerId(teacherServerId);
      if (teacher == null) {
        _showToast('Teacher account not ready yet.');
        return;
      }

      final service = ExamGenerationService(db);
      await service.generateWeeklyExams(
        schoolId: school.localId,
        teacherId: teacher.localId,
        teacherServerId: teacherServerId,
        schoolServerId: school.serverId,
        subject: selection.subject,
        classLevel: selection.classLevel,
        termLabel: selection.termLabel,
        subscriptionTier: school.subscriptionTier.toLowerCase(),
        lessonStorageLimits:
            ref.read(configServiceProvider).lessonStorageLimits,
        aiGenerate: (prompt) async {
          // AI fallback is only reached when no scheme/NERDC topics exist;
          // generation requires internet for that path.
          if (!await PlatformHelper.isOnline()) {
            throw const ExamTopicsUnavailableException();
          }
          return AiService(db: db).generate(prompt);
        },
      );

      ref.invalidate(examsListProvider);
      _showToast('13 weekly exams created. Tap any week to add questions.');
    } on ExamTopicsUnavailableException {
      _showToast(
        'No topics available for ${selection.subject}, '
        '${selection.classLevel}, ${selection.termLabel}. '
        'Check your internet connection and try again.',
      );
    } on ExamStorageLimitExceededException {
      _showToast(
        'Exam storage limit reached. Upgrade your school plan to create '
        'more exams.',
      );
    } catch (e) {
      _showToast('Could not create exams: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingWeekly = false);
    }
  }

  /// Shows a readable toast (dark background, white text) on this screen.
  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF323232),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
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
        // Only queue a remote DELETE when the exam has a server UUID.
        // Exams whose original INSERT was skipped server-side have no server
        // row; queueing a DELETE with only the local id caused the server to
        // fail `.eq("id", <localInt>)` forever.
        if (exam.serverId != null && exam.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'exams',
            recordLocalId: exam.id,
            operation: 'DELETE',
            payload: {
              'id': exam.id,
              'server_id': exam.serverId,
            },
          );
        }
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          context.go('/');
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Home',
        ),
        title: Text(
          'Exams',
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
      body: Column(
        children: [
          const ConflictBanner(),
          // Primary actions — full width, directly under the banner. Same
          // clean full-width button style as the Lessons list.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _FullWidthActionButton(
              cs: cs,
              theme: theme,
              label: 'Generate Weekly Exams',
              icon: Icons.calendar_view_week_rounded,
              busy: _isGeneratingWeekly,
              onTap: _openGenerateWeeklyExams,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _FullWidthActionButton(
              cs: cs,
              theme: theme,
              label: 'Term Exam / CA Test',
              icon: Icons.assignment_rounded,
              tonal: true,
              onTap: _openCombinedExam,
            ),
          ),
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
                    expanded: _filtersExpanded,
                    onToggleExpanded: _toggleFiltersExpanded,
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
                    headerTrailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SyncIndicator(),
                        const SizedBox(width: 4),
                        OfflineCreditCounter(
                          visible: ref.watch(isOfflineProvider),
                        ),
                      ],
                    ),
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
                                    'Tap Generate Weekly Exams or Term Exam / '
                                    'CA Test to create exams.',
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
                                position: index + 1,
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
      ),
    );
  }
}

class _ExamFiltersPanel extends StatelessWidget {
  const _ExamFiltersPanel({
    required this.cs,
    required this.theme,
    required this.expanded,
    required this.onToggleExpanded,
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
    this.headerTrailing,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final bool expanded;
  final VoidCallback onToggleExpanded;
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

  /// Compact status widgets (sync + offline credits) shown at the right of the
  /// "Filters" header, before the expand chevron.
  final Widget? headerTrailing;

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
          InkWell(
            onTap: onToggleExpanded,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
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
                  const Spacer(),
                  if (headerTrailing != null) ...[
                    headerTrailing!,
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
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
          if (expanded) ...[
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

/// Status-circle colors shared with the lessons list so the mapping stays
/// consistent across both screens: Draft → grey, Unlocked → blue,
/// linked to a scheme → orange border. (Green for "completed" only exists
/// on the lessons list — exams have no completed state.)
const _draftCircleColor = Color(0xFF9E9E9E);
const _unlockedCircleColor = Color(0xFF2196F3);
const _schemeLinkedCircleColor = Color(0xFFFF9800);

/// Exam → circle color: Unlocked → blue, Draft → grey. Exams have no separate
/// completed state today, so green (completed) only applies to lessons (see
/// the lessons list's `_lessonStatusCircleColor`).
Color _examStatusCircleColor(Exam exam) {
  if (exam.isUnlocked) return _unlockedCircleColor;
  return _draftCircleColor;
}

/// Small colored circle showing an item's state. An orange border is drawn
/// when the item is linked to a scheme of work. Identical implementation on
/// the lessons list so the two screens stay consistent.
class _StatusCircle extends StatelessWidget {
  const _StatusCircle({required this.color, required this.linked});

  final Color color;
  final bool linked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: linked
            ? Border.all(color: _schemeLinkedCircleColor, width: 2)
            : null,
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final Exam exam;
  final int position;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExamCard({
    required this.exam,
    required this.position,
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
            _StatusCircle(
              color: _examStatusCircleColor(exam),
              linked: exam.schemeOfWorkId != null,
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 18,
              child: Text(
                '$position',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
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

/// Full-width primary/tonal action button in the same clean style as the
/// Lessons list "Create" button (rounded 14, full width, centered icon+label).
class _FullWidthActionButton extends StatelessWidget {
  const _FullWidthActionButton({
    required this.cs,
    required this.theme,
    required this.label,
    required this.icon,
    required this.onTap,
    this.tonal = false,
    this.busy = false,
  });

  final ColorScheme cs;
  final ThemeData theme;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool tonal;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final background = tonal ? cs.secondaryContainer : cs.primary;
    final foreground = tonal ? cs.onSecondaryContainer : cs.onPrimary;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 20, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyExamsSelection {
  const _WeeklyExamsSelection(
    this.subject,
    this.classLevel,
    this.termLabel,
  );

  final String subject;
  final String classLevel;
  final String termLabel;
}

/// Small confirmation dialog for "Generate Weekly Exams": subject/class/term
/// pre-filled from the Exams list filters (or last-used values). Copy makes
/// explicit that lessons and the scheme of work are NOT touched.
class _WeeklyExamsDialog extends StatefulWidget {
  const _WeeklyExamsDialog({
    required this.subjectOptions,
    required this.initialSubject,
    required this.initialClassLevel,
    required this.initialTerm,
  });

  final List<String> subjectOptions;
  final String initialSubject;
  final String initialClassLevel;
  final String initialTerm;

  @override
  State<_WeeklyExamsDialog> createState() => _WeeklyExamsDialogState();
}

class _WeeklyExamsDialogState extends State<_WeeklyExamsDialog> {
  static const _classes = ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];
  static const _terms = ['1st Term', '2nd Term', '3rd Term'];

  late String _subject;
  late String _classLevel;
  late String _term;

  @override
  void initState() {
    super.initState();
    _subject = widget.subjectOptions.contains(widget.initialSubject)
        ? widget.initialSubject
        : widget.subjectOptions.first;
    _classLevel = _classes.contains(widget.initialClassLevel)
        ? widget.initialClassLevel
        : _classes.first;
    _term = _terms.contains(widget.initialTerm) ? widget.initialTerm : _terms.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Generate Weekly Exams'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create 13 weekly exam drafts for $_subject, $_classLevel, '
            '$_term. Lessons and scheme of work will NOT be changed.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: widget.subjectOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v ?? _subject),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _classLevel,
            decoration: const InputDecoration(labelText: 'Class Level'),
            items: _classes
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _classLevel = v ?? _classLevel),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _term,
            decoration: const InputDecoration(labelText: 'Term'),
            items: _terms
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _term = v ?? _term),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _WeeklyExamsSelection(_subject, _classLevel, _term),
          ),
          child: const Text('Generate'),
        ),
      ],
    );
  }
}
