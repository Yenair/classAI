import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Payload compression utilities for 2G/3G optimization.
///
/// Provides:
/// - JSON key minification (shortens field names)
/// - Selective field stripping for sync payloads
/// - Content hashing for deduplication
/// - Compression ratio tracking
class PayloadCompressor {
  /// Compress a sync payload by minifying keys and removing nulls.
  ///
  /// Uses short key mappings for known fields to reduce payload size.
  /// This is especially important on 2G/3G networks common in Nigerian rural areas.
  static Map<String, dynamic> compress(Map<String, dynamic> payload) {
    final result = <String, dynamic>{};
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value == null) continue;

      final shortKey = _shortenKey(entry.key);
      if (value is Map<String, dynamic>) {
        result[shortKey] = compress(value);
      } else if (value is List) {
        result[shortKey] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return compress(item);
          }
          return item;
        }).toList();
      } else {
        result[shortKey] = value;
      }
    }
    return result;
  }

  /// Decompress a previously compressed payload.
  static Map<String, dynamic> decompress(Map<String, dynamic> compressed) {
    final result = <String, dynamic>{};
    for (final entry in compressed.entries) {
      final longKey = _lengthenKey(entry.key);
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        result[longKey] = decompress(value);
      } else if (value is List) {
        result[longKey] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return decompress(item);
          }
          return item;
        }).toList();
      } else {
        result[longKey] = value;
      }
    }
    return result;
  }

  /// Compute the compression ratio as a percentage.
  ///
  /// Returns the ratio of compressed size to original size (0.0 to 1.0).
  /// A lower value means better compression.
  static double compressionRatio(
      Map<String, dynamic> original, Map<String, dynamic> compressed) {
    final originalJson = jsonEncode(original);
    final compressedJson = jsonEncode(compressed);
    if (originalJson.isEmpty) return 1.0;
    return compressedJson.length / originalJson.length;
  }

  /// Estimate the JSON payload size in bytes.
  static int estimateSize(Map<String, dynamic> payload) {
    final encoded = utf8.encode(jsonEncode(payload));
    return encoded.length;
  }

  /// Compute a content hash for deduplication.
  static String contentHash(Map<String, dynamic> payload) {
    final json = jsonEncode(payload);
    return sha256.convert(utf8.encode(json)).toString();
  }

  /// Strip optional fields from a payload for minimal sync.
  ///
  /// Keeps only essential fields: id, type, updated_at, and the
  /// primary data fields. Removes metadata, display fields, etc.
  static Map<String, dynamic> stripOptionalFields(
    Map<String, dynamic> payload,
    List<String> keepFields,
  ) {
    final result = <String, dynamic>{};
    for (final key in keepFields) {
      if (payload.containsKey(key)) {
        result[key] = payload[key];
      }
    }
    return result;
  }

  // ---- Key shortening map ----
  // Common Drift-generated field names → short codes
  static const _keyMap = <String, String>{
    'local_id': 'lid',
    'server_id': 'sid',
    'school_local_id': 'slid',
    'school_server_id': 'ssid',
    'teacher_local_id': 'tlid',
    'teacher_server_id': 'tsid',
    'subject_id': 'subid',
    'created_at': 'ca',
    'updated_at': 'ua',
    'is_deleted': 'del',
    'update_counter': 'uc',
    'last_modified_by': 'lmb',
    'sync_status': 'ss',
    'content': 'c',
    'content_hash': 'ch',
    'topic': 't',
    'class_level': 'cl',
    'difficulty': 'd',
    'curriculum': 'cur',
    'week': 'w',
    'subject': 's',
    'teacher_name': 'tn',
    'school_name': 'sn',
    'email': 'e',
    'role': 'r',
    'is_active': 'ia',
    'password_hash_version': 'phv',
    'salt': 'sa',
    'school_key_wrapped': 'skw',
    'subscription_tier': 'st',
    'active_curriculum': 'ac',
    'total_seats': 'ts',
    'short_code': 'sc',
    'logo_url': 'lu',
    'expiry_date': 'ed',
    'admin_recovery_email': 'are',
    'admin_recovery_email_verified': 'arev',
    'id': 'id',
    'name': 'n',
    'description': 'desc',
    'term_number': 'tnum',
    'academic_year': 'ay',
    'start_date': 'sd',
    'end_date': 'ed',
    'is_current': 'ic',
  };

  static String _shortenKey(String key) {
    return _keyMap[key] ?? key;
  }

  static String _lengthenKey(String shortKey) {
    // Reverse lookup
    for (final entry in _keyMap.entries) {
      if (entry.value == shortKey) return entry.key;
    }
    return shortKey;
  }
}
