import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:classai/core/database/database.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/core/widgets/credit_counter.dart';
import 'package:classai/core/widgets/status_chip.dart';
import 'package:classai/core/widgets/sync_indicator.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart'
    show examsListProvider;
import 'package:classai/features/exam/screens/exam_choice_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// examsListProvider is defined in
/// lib/features/dashboard/providers/dashboard_data_providers.dart.

/// One reversible delete performed on this screen. Holds the exam snapshot
/// taken before the soft-delete, the id of the DELETE sync entry created by
/// this delete (null when the exam has no server row), and the ids of any
/// DELETE entries that were already pending for the exam before this delete.
class _DeleteRecord {
  _DeleteRecord({
    required this.exam,
    required this.queueEntryId,
    required this.pendingDeleteEntryIds,
  });

  final Exam exam;

  /// Id of the DELETE sync entry created by this delete. Replaced on redo
  /// (the undo that preceded it removed the previous entry).
  int? queueEntryId;

  final List<int> pendingDeleteEntryIds;
}

/// Displays a list of exams from the local database.
class ExamsListScreen extends ConsumerStatefulWidget {
  const ExamsListScreen({super.key});

  @override
  ConsumerState<ExamsListScreen> createState() => _ExamsListScreenState();
}

class _ExamsListScreenState extends ConsumerState<ExamsListScreen> {

  /// How long the Undo SnackBar stays visible. The DELETE sync entry created
  /// by a delete is held (`next_retry_at` in the future) for exactly this
  /// window so the sync engine cannot push it before Undo is possible.
  static const _undoWindow = Duration(seconds: 4);

  /// Flow-local reversible command stack for deletes on this screen. Undo
  /// (SnackBar action or Ctrl+Z) restores the row and drops the held DELETE
  /// entry; redo (Ctrl+Y) re-applies the delete and re-queues the entry.
  final List<_DeleteRecord> _undoStack = [];
  final List<_DeleteRecord> _redoStack = [];

  /// Release timers for held DELETE entries, keyed by queue entry id. Each
  /// fires at the end of the Undo window and clears `next_retry_at` so the
  /// sync engine pushes the delete normally. Cancelled by Undo (the entry is
  /// removed anyway) and on dispose (the timestamp itself still auto-releases
  /// the entry).
  final Map<int, Timer> _heldDeleteTimers = {};

  @override
  void dispose() {
    for (final timer in _heldDeleteTimers.values) {
      timer.cancel();
    }
    _heldDeleteTimers.clear();
    super.dispose();
  }

  static const _termFilters = ['All', '1st Term', '2nd Term', '3rd Term'];
  static const _statusFilters = [
    _StatusFilterItem('All', Icons.layers_rounded),
    _StatusFilterItem('Draft', Icons.edit_note_rounded),
    _StatusFilterItem('Completed', Icons.check_circle_rounded),
    _StatusFilterItem('Unlocked', Icons.lock_open_rounded),
    _StatusFilterItem('Generated', Icons.auto_awesome_rounded),
    _StatusFilterItem('Needs Sync', Icons.sync_rounded),
  ];

  /// Type tab filter — `All | CA Test (Class Test) | Term Exam`.
  static const _typeTabs = ['All', 'CA Test (Class Test)', 'Term Exam'];

  String _selectedTypeTab = 'All';
  String _selectedStatusFilter = 'All';
  String _selectedTermFilter = 'All';
  String _selectedClassFilter = 'All';
  String _selectedSubjectFilter = 'All';
  bool _filtersExpanded = false;
  bool _schemesLoaded = false;
  final Map<int, SchemeOfWorkData> _schemesById = {};

  static const _prefPrefix = 'exams_filter_';

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
      // Collapsed by default; the teacher expands "Filter my exams" on demand.
      _filtersExpanded = prefs.getBool('exams_filters_expanded') ?? false;
    });
  }

  Future<void> _toggleFiltersExpanded() async {
    setState(() => _filtersExpanded = !_filtersExpanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('exams_filters_expanded', _filtersExpanded);
  }

  /// Populates the scheme lookup used to display term labels on exam cards.
  /// Does NOT create exams — creation happens only through the explicit
  /// Generate buttons on the setup screens; the old silent draft-exam
  /// seeding from saved schemes was removed.
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
      if (!_matchesTypeFilter(exam)) return false;
      if (!_matchesStatusFilter(exam)) return false;
      if (!_matchesTermFilter(exam)) return false;
      if (!_matchesClassFilter(exam)) return false;
      if (!_matchesSubjectFilter(exam)) return false;
      return true;
    }).toList();
  }

  void _setTypeTab(String tab) {
    setState(() => _selectedTypeTab = tab);
  }

  bool _matchesTypeFilter(Exam exam) {
    switch (_selectedTypeTab) {
      case 'CA Test (Class Test)':
        return _examTypeOf(exam) == _ExamType.caTest;
      case 'Term Exam':
        return _examTypeOf(exam) == _ExamType.termExam;
      default:
        return true;
    }
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
      await _deleteExam(exam);
    }
  }

  /// Applies a delete as a reversible command:
  ///  1. captures DELETE entries already pending for the exam,
  ///  2. soft-deletes the local row immediately,
  ///  3. queues the remote DELETE but holds it (`next_retry_at` in the
  ///     future) so the sync engine cannot push it before the Undo window
  ///     elapses,
  ///  4. pushes the operation onto the flow-local undo stack.
  Future<void> _deleteExam(Exam exam) async {
    try {
      final db = ref.read(databaseProvider);
      // Capture pending DELETE queue entries before deleting so Undo can drop
      // them — otherwise the queued DELETE would still remove the server row
      // after the local row is restored.
      final pendingDeleteEntries = (await db.syncQueueDao.pendingEntries())
          .where((e) =>
              e.queueTable == 'exams' &&
              e.recordLocalId == exam.id &&
              e.operation == 'DELETE')
          .map((e) => e.id)
          .toList();

      await db.examsDao.deleteExam(exam.id);

      // Only queue a remote DELETE when the exam has a server UUID. Exams
      // whose original INSERT was skipped server-side have no server row;
      // queueing a DELETE with only the local id caused the server to fail
      // `.eq("id", <localInt>)` forever.
      int? newQueueEntryId;
      if (exam.serverId != null && exam.serverId!.isNotEmpty) {
        newQueueEntryId = await _queueHeldDelete(
          db,
          table: 'exams',
          localId: exam.id,
          serverId: exam.serverId!,
        );
      }

      // Any new delete invalidates the redo history — the stack only covers
      // the current delete flow.
      _redoStack.clear();
      _undoStack.add(_DeleteRecord(
        exam: exam,
        queueEntryId: newQueueEntryId,
        pendingDeleteEntryIds: pendingDeleteEntries,
      ));
      ref.invalidate(examsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: _undoWindow,
            content: const Text('Exam deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: _undo),
          ),
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

  /// Inserts a DELETE sync entry for [localId] and immediately holds it by
  /// setting `next_retry_at` past the Undo window, so a sync cycle cannot
  /// push the delete before the user's Undo opportunity elapses. A release
  /// timer clears `next_retry_at` once the window passes, making the entry
  /// due for a normal push; Undo cancels the timer and removes the entry.
  Future<int> _queueHeldDelete(
    AppDatabase db, {
    required String table,
    required int localId,
    required String serverId,
  }) async {
    final entryId = await db.into(db.syncQueue).insert(
          SyncQueueCompanion.insert(
            queueTable: table,
            recordLocalId: localId,
            operation: 'DELETE',
            payload: jsonEncode({'id': localId, 'server_id': serverId}),
          ),
        );
    // `where` on a drift statement returns void, so the write must be chained
    // through a parenthesized cascade (same pattern as the DAOs).
    await (db.update(db.syncQueue)..where((t) => t.id.equals(entryId))).write(
          SyncQueueCompanion(
            nextRetryAt: Value(DateTime.now().add(_undoWindow)),
          ),
        );
    final releaseTimer = Timer(_undoWindow, () {
      _heldDeleteTimers.remove(entryId);
      (db.update(db.syncQueue)..where((t) => t.id.equals(entryId)))
          .write(const SyncQueueCompanion(nextRetryAt: Value(null)));
    });
    _heldDeleteTimers[entryId] = releaseTimer;
    return entryId;
  }

  /// Undo the most recent delete — shared by the SnackBar action and the
  /// Ctrl+Z shortcut, so both operate on the same flow-local stack.
  void _undo() {
    if (_undoStack.isEmpty) return;
    final record = _undoStack.removeLast();
    _redoStack.add(record);
    unawaited(_applyUndo(record));
  }

  /// Restores a soft-deleted exam and drops the DELETE entries created by the
  /// delete plus any that were pending before it, so the server row is left
  /// untouched.
  Future<void> _applyUndo(_DeleteRecord record) async {
    // Stop the release timer — the entry is being removed anyway.
    final newEntryId = record.queueEntryId;
    if (newEntryId != null) {
      _heldDeleteTimers.remove(newEntryId)?.cancel();
    }
    try {
      final db = ref.read(databaseProvider);
      await db.examsDao.updateExam(
        record.exam.id,
        ExamsCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (newEntryId != null) {
        await db.syncQueueDao.deleteById(newEntryId);
      }
      for (final entryId in record.pendingDeleteEntryIds) {
        await db.syncQueueDao.deleteById(entryId);
      }
      ref.invalidate(examsListProvider);
    } catch (_) {
      // Undo is best-effort; the exam remains deleted if it fails.
    }
  }

  /// Re-applies the most recently undone delete (Ctrl+Y).
  void _redo() {
    if (_redoStack.isEmpty) return;
    final record = _redoStack.removeLast();
    _undoStack.add(record);
    unawaited(_applyRedo(record));
  }

  /// Re-applies a delete: soft-deletes the row again and re-queues a held
  /// DELETE entry. The record's [queueEntryId] is refreshed so a subsequent
  /// Undo removes the newly queued entry.
  Future<void> _applyRedo(_DeleteRecord record) async {
    try {
      final db = ref.read(databaseProvider);
      await db.examsDao.deleteExam(record.exam.id);
      int? newQueueEntryId;
      if (record.exam.serverId != null && record.exam.serverId!.isNotEmpty) {
        newQueueEntryId = await _queueHeldDelete(
          db,
          table: 'exams',
          localId: record.exam.id,
          serverId: record.exam.serverId!,
        );
      }
      record.queueEntryId = newQueueEntryId;
      ref.invalidate(examsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: _undoWindow,
            content: const Text('Exam deleted'),
            action: SnackBarAction(label: 'Undo', onPressed: _undo),
          ),
        );
      }
    } catch (_) {
      // Best-effort — the row stays deleted even if re-queueing failed.
    }
  }

  @override
  Widget build(BuildContext context) {
    final examsAsync = ref.watch(examsListProvider);
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    // CallbackShortcuts must sit ABOVE the autofocused node so key events
    // bubbling up from it reach the bindings (Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z).
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        // Ctrl+Shift+Z is the conventional redo shortcut on Windows/Linux.
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ):
            _redo,
      },
      child: Focus(
        autofocus: true,
        child: PopScope(
          // Normal popping is preserved when the list was pushed (e.g. from
          // /exams); only when there is no history to pop do we fall back to
          // Home, keeping the previous behavior for deep links. Uses the
          // plain Navigator so the screen also builds standalone (no router).
          canPop: Navigator.of(context).canPop(),
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && mounted) {
              context.go('/');
            }
          },
          child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back',
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

                // Type tabs — the primary way to filter the list (All |
                // CA Test (Class Test) | Term Exam).
                final typeTabs = Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final tab in _typeTabs)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _TypeTab(
                              label: tab,
                              icon: _typeTabIcon(tab),
                              selected: _selectedTypeTab == tab,
                              onTap: () => _setTypeTab(tab),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                  // Zero state: "No exams yet" then the two primary creation
                  // cards.
                  return ListView(
                    physics: (Platform.isAndroid || Platform.isIOS)
                        ? const BouncingScrollPhysics()
                        : null,
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    children: [
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.fact_check_rounded,
                            size: 38,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No exams yet',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Make your first exam below.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      const ExamCreationCards(),
                    ],
                  );
                }

                if (filteredExams.isEmpty) {
                  return Column(
                    children: [
                      typeTabs,
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
                    typeTabs,
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
                                type: _examTypeOf(exam),
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
  /// "Filter my exams" header, before the expand chevron.
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
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  // Flexible lets the label ellipsize on narrow widths
                  // instead of overflowing the header row.
                  Flexible(
                    child: Text(
                      'Filter my exams',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
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

/// The two exam types shown as tabs and badges. Type is derived from the
/// generated topic title: combined exams are prefixed "Term Exam (...)" or
/// "CA Test (...)". Legacy weekly draft exams (no prefix) carry no type and
/// show no badge. Colors/icons reuse the shared choice-screen coding (blue
/// quiz / green assignment) so the mapping is identical wherever a type
/// appears.
enum _ExamType { caTest, termExam }

_ExamType? _examTypeOf(Exam exam) {
  final topic = exam.topic.trim().toLowerCase();
  if (topic.startsWith('term exam')) return _ExamType.termExam;
  if (topic.startsWith('ca test')) return _ExamType.caTest;
  return null;
}

String _examTypeLabel(_ExamType type) {
  switch (type) {
    case _ExamType.caTest:
      return 'CA Test';
    case _ExamType.termExam:
      return 'Term Exam';
  }
}

Color _examTypeColor(_ExamType type) {
  switch (type) {
    case _ExamType.caTest:
      return kCaTestColor;
    case _ExamType.termExam:
      return kTermExamColor;
  }
}

IconData _examTypeIcon(_ExamType type) {
  switch (type) {
    case _ExamType.caTest:
      return Icons.quiz_rounded;
    case _ExamType.termExam:
      return Icons.assignment_turned_in_rounded;
  }
}

/// Icon for a type tab label ('' for All), so the tabs carry the same
/// exclusive type icons as the badges.
IconData? _typeTabIcon(String label) {
  switch (label) {
    case 'CA Test (Class Test)':
      return Icons.quiz_rounded;
    case 'Term Exam':
      return Icons.assignment_turned_in_rounded;
    default:
      return null;
  }
}

class _ExamCard extends StatelessWidget {
  final Exam exam;
  /// Null for legacy weekly draft exams — they stay visible in the list but
  /// show no type badge.
  final _ExamType? type;
  final int position;
  final String classLevelLabel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExamCard({
    required this.exam,
    required this.type,
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

    // Status / secondary chips — shared by both layouts. On wide (desktop)
    // cards the chips sit inline at the start of the main row; on narrow
    // cards they move to their own line so they can wrap without starving
    // the text/actions siblings for width.
    final chipsWrap = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        examRowStatusChip(unlocked: exam.isUnlocked),
        // Secondary "Needs Sync" chip — the Unlocked primary chip
        // is the only generated signal for exams, so no Generated
        // chip is added here.
        if (exam.serverId == null || exam.serverId!.isEmpty)
          const StatusChip(
            label: 'Needs Sync',
            icon: Icons.sync_rounded,
            color: kStatusNeedsSyncColor,
            dense: true,
          ),
        if (exam.schemeOfWorkId != null) schemeLinkedChip(),
      ],
    );

    // Position + icon + text + actions — the shared main row body used by
    // both the desktop (chips inline) and narrow (chips stacked) layouts.
    final mainRowChildren = <Widget>[
      const SizedBox(width: 10),
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
            // Flexible + ellipsis keeps the subject badge from
            // overflowing the text column on narrow cards.
            Row(
              children: [
                Flexible(
                  child: Container(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
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
          // Type badge — always visible regardless of the active
          // tab, except for legacy weekly draft exams (type ==
          // null) which show no badge at all.
          if (type != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: _examTypeColor(type!).withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _examTypeIcon(type!),
                    size: 13,
                    color: _examTypeColor(type!),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _examTypeLabel(type!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _examTypeColor(type!),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
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
                icon: Icon(
                  Icons.edit_rounded,
                  size: 20,
                  color: cs.primary,
                ),
                onPressed: onEdit,
                tooltip: 'Edit',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
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
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
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
    ];

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
        // Desktop (>= 480dp): chips inline where they originally sat, then
        // the position/icon/text/actions row. Narrow (< 480dp): chips wrap
        // on their own line above the same row, keeping 320dp safe.
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 480) {
              return Row(
                children: [
                  chipsWrap,
                  const SizedBox(width: 10),
                  ...mainRowChildren,
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                chipsWrap,
                const SizedBox(height: 8),
                Row(children: mainRowChildren),
              ],
            );
          },
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
                  // Flexible placeholders shrink with the text column so
                  // the skeleton never overflows at 320dp.
                  Row(
                    children: [
                      Flexible(
                        flex: 2,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 3,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
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

/// One pill-shaped type tab (All | CA Test (Class Test) | Term Exam). The
/// active tab stays highlighted; type tabs carry the same exclusive type
/// icon as the badges.
class _TypeTab extends StatelessWidget {
  const _TypeTab({
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? cs.primary : cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

