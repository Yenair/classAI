import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Provider that fetches all lessons from the database.
final lessonsListProvider = FutureProvider<List<Lesson>>((ref) async {
  final db = ref.read(databaseProvider);
  return db.lessonsDao.getAll();
});

/// Displays a list of lessons from the local database.
///
/// Each lesson card shows subject, topic, and date information.
/// Tapping a card navigates to the lesson editor for that lesson.
/// A FAB allows creating a new lesson.
class LessonsListScreen extends ConsumerStatefulWidget {
  const LessonsListScreen({super.key});

  @override
  ConsumerState<LessonsListScreen> createState() => _LessonsListScreenState();
}

class _LessonsListScreenState extends ConsumerState<LessonsListScreen> {
  String _selectedFilter = 'All';

  List<Lesson> _applyFilter(List<Lesson> lessons) {
    switch (_selectedFilter) {
      case 'Draft':
        return lessons.where((lesson) => lesson.status == 'draft').toList();
      case 'Completed':
        return lessons.where((lesson) => lesson.status == 'completed').toList();
      case 'Unlocked':
        return lessons.where((lesson) => lesson.isUnlocked).toList();
      case 'Linked to Scheme':
        return lessons.where((lesson) => lesson.schemeOfWorkId != null).toList();
      case 'Needs Sync':
        return lessons.where((lesson) => lesson.serverId == null).toList();
      default:
        return lessons;
    }
  }

  void _setFilter(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncStatusProvider.notifier).refresh();
      ref.read(creditStateProvider.notifier).refresh();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lessonsAsync = ref.watch(lessonsListProvider);
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
          'Lessons',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.12,
          ),
        ),
        actions: [
          const Icon(Icons.cloud_off_rounded),
          const SizedBox(width: 8),
          const CreditCounter(),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: _LessonFilterRow(
              selectedFilter: _selectedFilter,
              cs: cs,
              theme: theme,
              onSelected: _setFilter,
            ),
          ),
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
              error: (error, stack) => ListView(
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
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: cs.errorContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.error_outline,
                              size: 34, color: cs.onErrorContainer),
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
                ],
              ),
              data: (lessons) {
                final filteredLessons = _applyFilter(lessons);
                if (lessons.isNotEmpty && filteredLessons.isEmpty) {
                  return ListView(
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
                                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'No lessons match "$_selectedFilter"',
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
                  );
                }

                if (lessons.isEmpty) {
                  return ListView(
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
                                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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
                  );
                }

                return RefreshIndicator(
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
                          onTap: () => context.push('/lessons/${lesson.id}'),
                          onEdit: () => context.push('/lessons/${lesson.id}'),
                          onDelete: () => _confirmDeleteLesson(lesson),
                        ),
                      );
                    },
                  ),
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
          onPressed: () => context.push('/lesson-editor'),
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
    );
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
        final db = ref.read(databaseProvider);
        // Soft-delete the lesson locally
        await db.lessonsDao.deleteLesson(lesson.id);
        // Queue a DELETE sync entry so the server is notified
        await db.syncQueueDao.insertEntry(
          queueTable: 'lessons',
          recordLocalId: lesson.id,
          operation: 'DELETE',
          payload: {
            'id': lesson.id,
            if (lesson.serverId != null) 'server_id': lesson.serverId,
          },
        );
        // Refresh the list
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
}

class _LessonFilterRow extends StatelessWidget {
  const _LessonFilterRow({
    required this.selectedFilter,
    required this.cs,
    required this.theme,
    required this.onSelected,
  });

  final String selectedFilter;
  final ColorScheme cs;
  final ThemeData theme;
  final ValueChanged<String> onSelected;

  static const _filters = [
    'All',
    'Draft',
    'Completed',
    'Unlocked',
    'Linked to Scheme',
    'Needs Sync',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((filter) {
          final selected = filter == selectedFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(filter),
              selected: selected,
              onSelected: (_) => onSelected(filter),
              labelStyle: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
              selectedColor: cs.primary,
              backgroundColor: cs.surfaceContainerLow,
              side: BorderSide(color: cs.outlineVariant),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LessonCard({
    required this.lesson,
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
                  Flexible(
                    child: Text(
                      lesson.topic,
                      maxLines: 3,
                      overflow: TextOverflow.visible,
                      softWrap: true,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
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
                      if (lesson.classLevel.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lesson.classLevel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatDate(lesson.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 4),
            // Edit button
            IconButton(
              onPressed: onEdit,
              icon: Icon(
                Icons.edit_rounded,
                size: 20,
                color: cs.primary,
              ),
              tooltip: 'Edit lesson',
              style: IconButton.styleFrom(
                foregroundColor: cs.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
            // Delete button
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: cs.error,
              ),
              tooltip: 'Delete lesson',
              style: IconButton.styleFrom(
                foregroundColor: cs.error,
                visualDensity: VisualDensity.compact,
              ),
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
                        width: 64,
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
