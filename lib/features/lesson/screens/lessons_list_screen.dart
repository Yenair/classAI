import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide Column;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/pdf_service_provider.dart';
import 'package:classai/core/services/pdf_service.dart';
import 'package:classai/core/utils/platform_helper.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;

/// Provider that fetches all lessons from the database.
final lessonsListProvider = FutureProvider<List<Lesson>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.lessonsDao.getAll();
});

/// Displays a list of lessons from the local database.
class LessonsListScreen extends ConsumerStatefulWidget {
  const LessonsListScreen({super.key});

  @override
  ConsumerState<LessonsListScreen> createState() => _LessonsListScreenState();
}

class _LessonsListScreenState extends ConsumerState<LessonsListScreen> {
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

  static const _prefPrefix = 'lessons_filter_';

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

      final schemes = (await db.schemeOfWorkDao.getSaved())
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
      for (final lesson in lessons) {
        if (lesson.isDeleted || lesson.status != 'draft') continue;
        final termLabel = _termLabelForLesson(lesson);
        if (termLabel == null || lesson.weekNumber == null) continue;
        existingDraftKeys.add(
          _draftKey(
            subject: lesson.subject,
            classLevel: lesson.classLevel,
            term: termLabel,
            weekNumber: lesson.weekNumber!,
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

        final existingForScheme = lessons.any((lesson) {
          if (lesson.isDeleted || lesson.status != 'draft') return false;
          final linkedSchemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
          return linkedSchemeId == scheme.id &&
              lesson.subject == subjectName &&
              lesson.classLevel == classLevel &&
              (lesson.weekNumber ?? lesson.week) == scheme.weekNumber;
        });
        if (existingForScheme) {
          existingDraftKeys.add(key);
          continue;
        }

        await db.lessonsDao.insertLesson(
          LessonsCompanion.insert(
            subject: subjectName,
            classLevel: classLevel,
            week: scheme.weekNumber,
            topic: _displayTopicForScheme(scheme),
            difficulty: 'medium',
            bloomsVerbs: '',
            curriculum: 'NERDC',
            content: jsonEncode({
              'objectives': const [],
              'vocabulary': const [],
              'materials': const [],
              'presentation': const [],
              'assessment': '',
              'homework': '',
            }),
            teacherServerId: teacherServerId != null
                ? Value(teacherServerId)
                : const Value.absent(),
            schoolServerId: school.serverId != null
                ? Value(school.serverId)
                : const Value.absent(),
            schemeOfWorkId: Value(scheme.id.toString()),
            weekNumber: Value(scheme.weekNumber),
            isUnlocked: const Value(false),
            status: const Value('draft'),
          ),
        );
        existingDraftKeys.add(key);
        insertedCount++;
      }

      if (insertedCount > 0 && mounted) {
        ref.invalidate(lessonsListProvider);
      }
    } catch (_) {
      // Keep the screen silent if draft seeding fails.
    }
  }

  List<Lesson> _applyFilters(List<Lesson> lessons) {
    return lessons.where((lesson) {
      if (!_matchesStatusFilter(lesson)) return false;
      if (!_matchesTermFilter(lesson)) return false;
      if (!_matchesClassFilter(lesson)) return false;
      if (!_matchesSubjectFilter(lesson)) return false;
      return true;
    }).toList();
  }

  bool _matchesStatusFilter(Lesson lesson) {
    switch (_selectedStatusFilter) {
      case 'Draft':
        return lesson.status == 'draft';
      case 'Completed':
        return lesson.status == 'completed';
      case 'Unlocked':
        return lesson.isUnlocked;
      case 'Linked to Scheme':
        return lesson.schemeOfWorkId != null;
      case 'Needs Sync':
        return lesson.serverId == null;
      default:
        return true;
    }
  }

  bool _matchesTermFilter(Lesson lesson) {
    if (_selectedTermFilter == 'All') return true;
    final termLabel = _termLabelForLesson(lesson);
    return termLabel == _selectedTermFilter;
  }

  bool _matchesClassFilter(Lesson lesson) {
    if (_selectedClassFilter == 'All') return true;
    return lesson.classLevel == _selectedClassFilter;
  }

  bool _matchesSubjectFilter(Lesson lesson) {
    if (_selectedSubjectFilter == 'All') return true;
    return lesson.subject == _selectedSubjectFilter;
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

  String? _termLabelForLesson(Lesson lesson) {
    // Use the real term column first
    if (lesson.term != null && lesson.term!.trim().isNotEmpty) {
      final normalized = _normalizeTermLabel(lesson.term!);
      if (normalized.isNotEmpty) return normalized;
    }

    // Fall back to linked scheme of work
    final schemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
    if (schemeId == null) return null;
    final scheme = _schemesById[schemeId];
    if (scheme == null) return null;
    return _normalizeTermLabel(scheme.term);
  }

  String _classLevelLabelForLesson(Lesson lesson) {
    final termLabel = _termLabelForLesson(lesson);
    final weekLabel = lesson.weekNumber != null ? ' - Week ${lesson.weekNumber}' : '';
    if (termLabel == null || termLabel.isEmpty) {
      return '${lesson.classLevel}$weekLabel';
    }
    return '${lesson.classLevel} ($termLabel)$weekLabel';
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

  String _displayTopicForScheme(SchemeOfWorkData scheme) {
    final edited = scheme.adminEditedTopic?.trim();
    if (edited != null && edited.isNotEmpty) {
      return edited;
    }
    return scheme.topic;
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

  String _createLessonLocation({
    required String subject,
    required String classLevel,
    required String term,
  }) {
    final queryParameters = <String, String>{};
    if (subject.isNotEmpty) queryParameters['subject'] = subject;
    if (classLevel.isNotEmpty) queryParameters['classLevel'] = classLevel;
    if (term.isNotEmpty) queryParameters['term'] = term;
    return Uri(
      path: '/lesson-editor',
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    ).toString();
  }

  void _openNewLesson() {
    final subject = _selectedSubjectFilter == 'All' ? '' : _selectedSubjectFilter;
    final classLevel =
        _selectedClassFilter == 'All' ? '' : _selectedClassFilter;
    final term = _selectedTermFilter == 'All' ? '' : _selectedTermFilter;
    context.push(
      _createLessonLocation(
        subject: subject,
        classLevel: classLevel,
        term: term,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lessonsAsync = ref.watch(lessonsListProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => Navigator.of(context).pop(),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: canPop
              ? IconButton(
                  onPressed: () => WidgetsBinding.instance.addPostFrameCallback(
                    (_) => Navigator.of(context).pop(),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                )
              : null,
          title: Text(
            'Lessons',
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
              child: lessonsAsync.when(
                loading: () => ListView(
                  physics: (Platform.isAndroid || Platform.isIOS)
                      ? const BouncingScrollPhysics()
                      : null,
                  padding: const EdgeInsets.all(16),
                  children: List.generate(
                    4,
                    (i) => _LessonCardSkeleton(cs: cs),
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
                          'Failed to load lessons',
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
                          onPressed: () => ref.invalidate(lessonsListProvider),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (lessons) {
                  final filteredLessons = _applyFilters(lessons);
                  filteredLessons.sort((a, b) => (a.weekNumber ?? 0).compareTo(b.weekNumber ?? 0));
                  final termOptions = _termFilters;
                  final classOptions = _buildFilterOptions(
                    lessons.map((lesson) => lesson.classLevel),
                  );
                  final subjectOptions = _buildFilterOptions(
                    lessons.map((lesson) => lesson.subject),
                  );

                  final filterPanel = Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _LessonFiltersPanel(
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

                  if (lessons.isEmpty) {
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
                                        Icons.book_rounded,
                                        size: 38,
                                        color: cs.onSurfaceVariant
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      'No lessons yet',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Tap New Lesson to create one.',
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

                  if (filteredLessons.isEmpty) {
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
                                      'No lessons match the selected filters',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Try a different filter or clear it to see all lessons.',
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
                          onRefresh: () async => ref.invalidate(lessonsListProvider),
                          child: ListView.builder(
                            physics: (Platform.isAndroid || Platform.isIOS)
                                ? const BouncingScrollPhysics()
                                : null,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filteredLessons.length,
                            itemBuilder: (context, index) {
                              final lesson = filteredLessons[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _LessonCard(
                                  lesson: lesson,
                                  classLevelLabel: _classLevelLabelForLesson(lesson),
                                  onTap: () => context.push('/lessons/${lesson.id}'),
                                  onEdit: () => context.push('/lessons/${lesson.id}'),
                                  onDelete: () => _confirmDeleteLesson(lesson),
                                  onExport: () => _exportLesson(lesson),
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
            onPressed: _openNewLesson,
            heroTag: 'newLesson',
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text(
              'New Lesson',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  /// Parse diagram URLs from lesson.content and attempt to delete each one
  /// via the `delete-diagram` Edge Function as a best-effort optimization.
  ///
  /// This runs BEFORE the local soft-delete so the lesson content is intact.
  /// Failure is logged but never blocks lesson deletion — section 2's
  /// sync-push cleanup is the authoritative path.
  Future<void> _cleanupDiagramsIfOnline(Lesson lesson) async {
    try {
      if (!await PlatformHelper.isOnline()) return;

      final contentRaw = lesson.content;
      if (contentRaw.isEmpty) return;

      final parsed = json.decode(contentRaw) as Map<String, dynamic>?;
      if (parsed == null) return;
      final diagrams = parsed['diagrams'] as List<dynamic>?;
      if (diagrams == null || diagrams.isEmpty) return;

      final jwt = ref.read(authServiceProvider).currentJwt;
      if (jwt == null || jwt.isEmpty) return;

      final client = supabase_pkg.Supabase.instance.client;

      for (final entry in diagrams) {
        if (entry is! Map<String, dynamic>) continue;
        final url = entry['imageUrl'] as String?;
        if (url == null || url.isEmpty) continue;

        try {
          await client.functions.invoke(
            'delete-diagram',
            headers: {'Authorization': 'Bearer $jwt'},
            body: {'url': url},
          );
        } catch (_) {
          // Best-effort only — sync-push will clean up via section 2.
        }
      }
    } catch (_) {
      // Entire cleanup is best-effort; never block deletion.
    }
  }

  Future<void> _confirmDeleteLesson(Lesson lesson) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Lesson'),
        content: Text('Are you sure you want to delete "${lesson.topic}"?'),
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
        // Best-effort diagram cleanup (online optimization only)
        await _cleanupDiagramsIfOnline(lesson);

        final db = ref.read(databaseProvider);
        await db.lessonsDao.deleteLesson(lesson.id);
        await db.syncQueueDao.insertEntry(
          queueTable: 'lessons',
          recordLocalId: lesson.id,
          operation: 'DELETE',
          payload: {
            'id': lesson.id,
            if (lesson.serverId != null) 'server_id': lesson.serverId,
          },
        );
        ref.invalidate(lessonsListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lesson deleted')),
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

  Future<void> _exportLesson(Lesson lesson) async {
    final db = ref.read(databaseProvider);
    final authState = ref.read(authProvider);
    final school = authState.currentSchool ?? await db.schoolsDao.get();
    if (school == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('School data not available')),
        );
      }
      return;
    }
    final teacherId = authState.currentTeacher?.serverId;
    final teacherEmail = authState.currentTeacher?.email;
    await exportLessonPdf(
      context,
      ref,
      lesson,
      school,
      teacherId,
      teacherEmail,
    );
  }
}

class _LessonFiltersPanel extends StatelessWidget {
  const _LessonFiltersPanel({
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

/// Shared helper: export a lesson as PDF and invoke the system share sheet.
/// Can be called from any widget that has access to [Lesson], [School],
/// and teacher info.
///
/// Handles daily limit enforcement and upgrade prompts consistently.
Future<void> exportLessonPdf(
  BuildContext context,
  WidgetRef ref,
  Lesson lesson,
  School school,
  String? teacherId,
  String? teacherEmail,
) async {
  final pdfService = ref.read(pdfServiceProvider);
  try {
    final pdfBytes = await pdfService.generateLessonPdf(
      lesson,
      school,
      teacherId: teacherId,
      teacherEmail: teacherEmail,
    );

    // Write to temp file for sharing
    final dir = await getTemporaryDirectory();
    final safeName = lesson.topic.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final file = File(
      '${dir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(pdfBytes);

    // Share via system share sheet
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Lesson: ${lesson.topic}',
      ),
    );
    // User cancellation is normal; no error SnackBar needed.
  } on PdfExportException catch (e) {
    // ── Unified daily limit handling ──
    if (e.remainingCount != null && e.remainingCount! <= 0) {
      // Remaining count is 0 (or negative for already-over-limit)
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('Daily Export Limit Reached'),
            content: const Text(
              'You have reached your daily PDF export limit. '
              'Upgrade to Elite for unlimited exports.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  // Navigate to payment or show upgrade request
                  context.push('/payment');
                },
                child: const Text('Upgrade'),
              ),
            ],
          ),
        );
      }
    } else {
      // Export succeeded within quota — informational notice only
      if (context.mounted && e.remainingCount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF exported. ${e.remainingCount} export(s) remaining today.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    }
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onExport;

  const _LessonCard({
    required this.lesson,
    required this.classLevelLabel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onExport,
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
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.menu_book_rounded,
                color: cs.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.topic,
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
                          lesson.subject,
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
                  _formatDate(lesson.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onExport != null)
                      IconButton(
                        icon: Icon(Icons.picture_as_pdf_rounded, size: 20, color: cs.tertiary),
                        onPressed: onExport,
                        tooltip: 'Export PDF',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
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
          ],
        ),
      ),
    );
  }
}

class _LessonCardSkeleton extends StatelessWidget {
  const _LessonCardSkeleton({required this.cs});

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
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  height: 14,
                  width: 48,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 8),
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
              ],
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
