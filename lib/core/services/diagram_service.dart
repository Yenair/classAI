// lib/core/services/diagram_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Service that generates diagrams via the `generate-diagram` Edge Function
/// and stores them locally (SharedPreferences).
///
/// Diagrams are identified by a UUID key and stored as base64 strings.
/// They are NOT synced to Supabase — purely local to the device.
class DiagramService {
  static const String _prefPrefix = 'diagram_';
  static const String _indexPrefKey = 'diagram_keys';

  final SupabaseClient _client;
  final Uuid _uuid = const Uuid();

  DiagramService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Generate diagrams for the given [diagrams] list.
  ///
  /// Returns a list of results in the same order, each containing:
  /// - `index`: original index
  /// - `description`: the description text
  /// - `base64`: base64 image data (null on failure)
  /// - `error`: error message (null on success)
  Future<List<DiagramResult>> generateDiagrams(
    List<DiagramRequest> diagrams, {
    String? jwt,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (jwt != null) {
        headers['Authorization'] = 'Bearer $jwt';
      }

      final response = await _client.functions.invoke(
        'generate-diagram',
        body: {'diagrams': diagrams.map((d) => d.toJson()).toList()},
        method: HttpMethod.post,
        headers: headers,
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['results'] == null) {
        return diagrams.asMap().entries.map((entry) {
          return DiagramResult(
            index: entry.key,
            description: entry.value.description,
            base64: null,
            error: 'Empty response from server',
          );
        }).toList();
      }

      final results = (data['results'] as List)
          .map((r) => DiagramResult.fromJson(r as Map<String, dynamic>))
          .toList();

      // Persist successfully generated diagrams to local storage
      final prefs = await SharedPreferences.getInstance();
      final keys = <String>[];
      for (final result in results) {
        if (result.base64 != null) {
          final key = _uuid.v4();
          await prefs.setString('$_prefPrefix$key', result.base64!);
          keys.add(key);
        }
      }
      if (keys.isNotEmpty) {
        final existingKeys = _loadKeyList(prefs);
        existingKeys.addAll(keys);
        await prefs.setString(_indexPrefKey, json.encode(existingKeys));
      }

      return results;
    } catch (e) {
      debugPrint('[DiagramService] generateDiagrams failed: $e');
      return diagrams.asMap().entries.map((entry) {
        return DiagramResult(
          index: entry.key,
          description: entry.value.description,
          base64: null,
          error: 'Failed to generate diagram: $e',
        );
      }).toList();
    }
  }

  /// Retrieve a stored diagram's base64 data by [key].
  Future<String?> getDiagram(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefPrefix$key');
  }

  /// Delete a stored diagram by [key].
  Future<void> deleteDiagram(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$key');
    final keys = _loadKeyList(prefs);
    keys.remove(key);
    await prefs.setString(_indexPrefKey, json.encode(keys));
  }

  /// List all stored diagram keys.
  Future<List<String>> listDiagramKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadKeyList(prefs);
  }

  /// Clear all stored diagrams.
  Future<void> clearAllDiagrams() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = _loadKeyList(prefs);
    for (final key in keys) {
      await prefs.remove('$_prefPrefix$key');
    }
    await prefs.remove(_indexPrefKey);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  List<String> _loadKeyList(SharedPreferences prefs) {
    final raw = prefs.getString(_indexPrefKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) return decoded.cast<String>();
      return [];
    } catch (_) {
      return [];
    }
  }
}

/// Represents a single diagram generation request.
class DiagramRequest {
  final String description;
  final String style;

  const DiagramRequest({
    required this.description,
    this.style = 'educational',
  });

  Map<String, dynamic> toJson() => {
        'description': description,
        'style': style,
      };
}

/// Represents the result of a single diagram generation.
class DiagramResult {
  final int index;
  final String description;
  final String? base64;
  final String? error;

  const DiagramResult({
    required this.index,
    required this.description,
    this.base64,
    this.error,
  });

  factory DiagramResult.fromJson(Map<String, dynamic> json) {
    return DiagramResult(
      index: json['index'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      base64: json['base64'] as String?,
      error: json['error'] as String?,
    );
  }
}
