import 'dart:convert';

enum MergeStrategy { lwwByUpdateCounter, union, keepLocal, keepRemote, manual }

enum MergeResolution { local, remote, merged, unresolved }

class MergeResult {
  final Map<String, dynamic> merged;
  final List<String> conflictingFields;
  final MergeResolution resolution;

  const MergeResult({
    required this.merged,
    required this.conflictingFields,
    required this.resolution,
  });
}

class MergeEngine {
  /// Three-way merge: local, remote, base (common ancestor).
  MergeResult merge({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required Map<String, dynamic>? base,
    required String tableName,
    required Map<String, MergeStrategy> fieldStrategies,
  }) {
    if (base == null) {
      return MergeResult(
        merged: remote,
        conflictingFields: local.keys.toList(),
        resolution: MergeResolution.remote,
      );
    }

    final merged = <String, dynamic>{};
    final conflicts = <String>[];

    final allFields = {...local.keys, ...remote.keys, ...base.keys};
    for (final field in allFields) {
      final localVal = local[field];
      final remoteVal = remote[field];
      final baseVal = base[field];

      final localChanged = !_valuesEqual(localVal, baseVal);
      final remoteChanged = !_valuesEqual(remoteVal, baseVal);

      if (!localChanged && !remoteChanged) {
        merged[field] = baseVal ?? localVal ?? remoteVal;
        continue;
      }

      if (localChanged && !remoteChanged) {
        merged[field] = localVal;
        continue;
      }

      if (!localChanged && remoteChanged) {
        merged[field] = remoteVal;
        continue;
      }

      final strategy = fieldStrategies[field] ?? MergeStrategy.lwwByUpdateCounter;
      final outcome = _applyStrategy(
        localValue: localVal,
        remoteValue: remoteVal,
        localUpdateCounter: (local['updateCounter'] as int?) ?? 0,
        remoteUpdateCounter: (remote['updateCounter'] as int?) ?? 0,
        strategy: strategy,
      );
      merged[field] = outcome.value;
      if (outcome.isConflict) {
        conflicts.add(field);
      }
    }

    return MergeResult(
      merged: merged,
      conflictingFields: conflicts,
      resolution: conflicts.isEmpty
          ? MergeResolution.merged
          : MergeResolution.unresolved,
    );
  }

  _StrategyOutcome _applyStrategy({
    required dynamic localValue,
    required dynamic remoteValue,
    required int localUpdateCounter,
    required int remoteUpdateCounter,
    required MergeStrategy strategy,
  }) {
    switch (strategy) {
      case MergeStrategy.keepLocal:
        return _StrategyOutcome(localValue, false);
      case MergeStrategy.keepRemote:
        return _StrategyOutcome(remoteValue, false);
      case MergeStrategy.manual:
        return _StrategyOutcome(remoteValue, !_valuesEqual(localValue, remoteValue));
      case MergeStrategy.union:
        return _StrategyOutcome(
          _unionValues(localValue, remoteValue),
          false,
        );
      case MergeStrategy.lwwByUpdateCounter:
        if (localUpdateCounter > remoteUpdateCounter) {
          return _StrategyOutcome(localValue, false);
        }
        if (remoteUpdateCounter > localUpdateCounter) {
          return _StrategyOutcome(remoteValue, false);
        }
        if (_valuesEqual(localValue, remoteValue)) {
          return _StrategyOutcome(localValue, false);
        }
        return _StrategyOutcome(remoteValue, true);
    }
  }

  dynamic _unionValues(dynamic localValue, dynamic remoteValue) {
    if (localValue is List || remoteValue is List) {
      final combined = <dynamic>[];
      final seen = <String>{};
      for (final value in [
        ..._toList(localValue),
        ..._toList(remoteValue),
      ]) {
        final key = _canonicalJson(value);
        if (seen.add(key)) {
          combined.add(value);
        }
      }
      return combined;
    }

    if (localValue == null) return remoteValue;
    if (remoteValue == null) return localValue;
    if (_valuesEqual(localValue, remoteValue)) return localValue;
    return [localValue, remoteValue];
  }

  List<dynamic> _toList(dynamic value) {
    if (value is List) return value;
    if (value == null) return const [];
    return [value];
  }

  bool _valuesEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_valuesEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  String _canonicalJson(dynamic value) {
    Object? normalize(dynamic input) {
      if (input is Map) {
        final keys = input.keys.map((key) => key.toString()).toList()..sort();
        return {
          for (final key in keys) key: normalize(input[key]),
        };
      }
      if (input is List) {
        return input.map(normalize).toList();
      }
      if (input is DateTime) {
        return input.toIso8601String();
      }
      return input;
    }

    return jsonEncode(normalize(value));
  }
}

class _StrategyOutcome {
  final dynamic value;
  final bool isConflict;

  const _StrategyOutcome(this.value, this.isConflict);
}
