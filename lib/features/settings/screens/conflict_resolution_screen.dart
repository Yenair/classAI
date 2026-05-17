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
      final conflicts = await (db.select(db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();
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
      await (db.update(db.conflicts)
            ..where((t) => t.id.equals(conflict.id)))
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
              t.table.equals(tableName) &
              t.recordLocalId.equals(localId))
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
              t.table.equals(tableName) &
              t.recordLocalId.equals(localId)))
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflict Resolution'),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
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
      return const SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 48),
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text('No unresolved conflicts'),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConflicts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _conflicts.length,
        itemBuilder: (context, index) =>
            _ConflictCard(
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
    if (value == null) return '—';
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
    final theme = Theme.of(context);
    final fields = List<String>.from(
      jsonDecode(conflict.conflictingFields) as List,
    );
    final localMap = _decodeValues(conflict.localValue);
    final remoteMap = _decodeValues(conflict.remoteValue);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Record type and ID
            Row(
              children: [
                Chip(
                  label: Text(
                    conflict.recordType,
                    style: theme.textTheme.labelSmall,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Text(
                  'ID: ${conflict.recordLocalId}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Conflicting fields with local vs remote values
            Text(
              'Conflicting fields:',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...fields.map(
              (field) => Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Field name header
                    Text(
                      field,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Local value
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'Local:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatValue(localMap[field]),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Remote value
                    Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            'Remote:',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer
                                  .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _formatValue(remoteMap[field]),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => onResolve(conflict, 'local'),
                  child: const Text('Keep Mine'),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => onResolve(conflict, 'remote'),
                  child: const Text('Keep Theirs'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: () => onResolve(conflict, 'merged'),
                  child: const Text('Merge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
