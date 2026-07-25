import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';

/// Screen that lists all unresolved sync conflicts and allows the user to
/// resolve them by choosing "Keep Mine", "Keep Theirs", or "Merge".
class ConflictResolutionScreen extends ConsumerStatefulWidget {
  const ConflictResolutionScreen({super.key});

  @override
  ConsumerState<ConflictResolutionScreen> createState() =>
      _ConflictResolutionScreenState();
}

class _ConflictResolutionScreenState
    extends ConsumerState<ConflictResolutionScreen> {
  List<Conflict> _conflicts = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConflicts());
  }

  Future<void> _loadConflicts() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(databaseProvider);

      // Use raw SQL to exclude rows where conflicting_fields is NULL,
      // because Drift's generated map() uses a null-check (!) on this
      // column and would crash on corrupt rows from a prior debugging
      // session (the column is non-nullable in schema but old rows may
      // have NULL values). Delegate deserialization to Drift's table
      // map() which handles type conversion correctly.
      final rows = await db.customSelect(
        'SELECT id, record_type, record_local_id, conflicting_fields, '
        'local_value, remote_value, resolution, notified, '
        'created_at, updated_at '
        'FROM conflicts '
        'WHERE resolution = ? AND conflicting_fields IS NOT NULL',
        variables: [Variable.withString('unresolved')],
      ).get();

      final conflicts = rows
          .map((r) => db.conflicts.map(r.data))
          .toList();

      setState(() {
        _conflicts = conflicts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load conflicts: $e';
        _loading = false;
      });
    }
  }

  Future<void> _resolveConflict(
    Conflict conflict,
    String resolution,
  ) async {
    try {
      final db = ref.read(databaseProvider);

      // 1. Update the conflict record with the chosen resolution
      await (db.update(db.conflicts)..where((t) => t.id.equals(conflict.id)))
          .write(
        ConflictsCompanion(
          resolution: Value(resolution),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // 2. If merging, update the underlying data record
      //    (auto-union for array fields)
      if (resolution == 'merged') {
        final fields = List<String>.from(
          jsonDecode(conflict.conflictingFields) as List,
        );
        await _applyMerge(db, conflict, fields);
      }

      // 3. Refresh the list and the unresolved conflicts count
      await _loadConflicts();
      ref.read(unresolvedConflictsProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Resolution failed: $e')),
        );
      }
    }
  }

  Future<void> _applyMerge(
    AppDatabase db,
    Conflict conflict,
    List<String> fields,
  ) async {
    final tableName = conflict.recordType;
    final localId = conflict.recordLocalId;

    // Read the current version hash snapshot
    final hashRow = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .getSingleOrNull();

    if (hashRow == null) return;

    final snapshot = Map<String, dynamic>.from(
      jsonDecode(hashRow.snapshotJson ?? '{}') as Map,
    );

    // Auto-union array fields, prefer local for scalar fields
    for (final field in fields) {
      final currentValue = snapshot[field];
      if (currentValue is List) {
        // Keep local value as-is (auto-union placeholder)
        snapshot[field] = currentValue;
      }
      // For scalar fields, keep local value (no change needed)
    }

    // Save the merged snapshot back
    final mergedJson = jsonEncode(snapshot);
    await (db.delete(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId)))
        .go();
    await db.into(db.versionHashes).insert(
          VersionHashesCompanion.insert(
            table: tableName,
            recordLocalId: localId,
            hash: mergedJson.hashCode.toString(),
            snapshotJson: Value(mergedJson),
            setAt: DateTime.now(),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflict Resolution'),
        elevation: 0,
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: cs.error.withValues(alpha: 0.8),
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.error,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _loadConflicts,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_conflicts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_circle_outline_rounded,
                size: 36,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No unresolved conflicts',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConflicts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conflicts.length,
        itemBuilder: (context, index) => _ConflictCard(
          key: ValueKey(_conflicts[index].id),
          conflict: _conflicts[index],
          onResolve: _resolveConflict,
        ),
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final Conflict conflict;
  final Future<void> Function(Conflict conflict, String resolution) onResolve;

  const _ConflictCard({
    super.key,
    required this.conflict,
    required this.onResolve,
  });

  /// Decodes a JSON string into a [Map], returning an empty map on null/error.
  Map<String, dynamic> _decodeValues(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }

  /// Formats a raw value for display — strings are quoted, null shows "—".
  String _formatValue(dynamic value) {
    if (value == null) return '\u2014';
    if (value is String) {
      return value.isEmpty ? '(empty)' : value;
    }
    if (value is List) {
      return value.isEmpty ? '[]' : value.join(', ');
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fields = List<String>.from(
      jsonDecode(conflict.conflictingFields) as List,
    );
    final localMap = _decodeValues(conflict.localValue);
    final remoteMap = _decodeValues(conflict.remoteValue);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Record type and ID
            Row(
              children: [
                Chip(
                  label: Text(
                    conflict.recordType,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ID: ${conflict.recordLocalId}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Conflicting fields with local vs remote values
            Text(
              'Conflicting fields:',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            ...fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field name header
                    Text(
                      field,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    // Local value — surrounded by fixed-width container
                    // to avoid Expanded-in-nested-Column intrinsic sizing issues
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Local:',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    cs.primaryContainer.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _formatValue(localMap[field]),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Remote value
                    SizedBox(
                      width: double.infinity,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: cs.errorContainer.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                'Remote:',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: cs.errorContainer.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _formatValue(remoteMap[field]),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onResolve(conflict, 'local'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Keep Mine'),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => onResolve(conflict, 'remote'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: const Text('Keep Theirs'),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FilledButton.tonal(
                    onPressed: () => onResolve(conflict, 'merged'),
                    child: const Text('Merge'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
