// lib/core/services/diagram_service.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:classai/core/services/auth_service.dart';

/// Service that generates diagrams via the `generate-diagram` Edge Function
/// and stores the resulting URL in the lesson content for sync.
///
/// Offline access is provided by [flutter_cache_manager]'s [DefaultCacheManager],
/// which caches downloaded images to disk. The [DiagramImage] widget wraps
/// this logic and shows a placeholder when the image hasn't been downloaded yet.
///
/// Why [flutter_cache_manager] instead of [cached_network_image]:
/// Neither was a dependency before this change. [flutter_cache_manager] is the
/// leaner, lower-level choice — [cached_network_image] wraps it anyway and adds
/// widget sugar we don't strictly need. Using [flutter_cache_manager] directly
/// gives us full control over the download/cache lifecycle via the
/// [DefaultCacheManager] singleton and [DiagramImage] handles display.
class DiagramService {
  static const String _prefPrefix = 'diagram_';
  static const String _indexPrefKey = 'diagram_keys';

  final SupabaseClient _client;

  DiagramService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Generate diagrams for the given [diagrams] list.
  ///
  /// [lessonId] is required — it's used as part of the Storage filename so
  /// images are grouped by lesson. If [oldUrl] is provided (e.g. during
  /// regeneration), the Edge Function will clean up the old Storage object
  /// *after* the new upload succeeds.
  ///
  /// Returns a list of results in the same order, each containing:
  /// - `index`: original index
  /// - `description`: the description text
  /// - `imageUrl`: public URL of the uploaded image (null on failure)
  /// - `error`: error message (null on success)
  Future<List<DiagramResult>> generateDiagrams(
    List<DiagramRequest> diagrams, {
    String? jwt,
    required String lessonId,
    String? oldUrl,
  }) async {
    try {
      // Read the custom ClassAI JWT from the caller-supplied param, falling
      // back to the static singleton (consistent with AiService) so callers
      // that don't pass `jwt` still send the required x-classai-jwt header.
      final effectiveJwt = jwt ?? SupabaseAuthService().currentJwt;
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (effectiveJwt != null && effectiveJwt.isNotEmpty) {
        headers['x-classai-jwt'] = effectiveJwt;
      }

      final response = await _client.functions.invoke(
        'generate-diagram',
        body: {
          'diagrams': diagrams.map((d) => d.toJson()).toList(),
          'lessonId': lessonId,
          if (oldUrl != null) 'oldUrl': oldUrl,
        },
        method: HttpMethod.post,
        headers: headers,
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['results'] == null) {
        return diagrams.asMap().entries.map((entry) {
          return DiagramResult(
            index: entry.key,
            description: entry.value.description,
            imageUrl: null,
            error: 'Empty response from server',
          );
        }).toList();
      }

      final results = (data['results'] as List)
          .map((r) => DiagramResult.fromJson(r as Map<String, dynamic>))
          .toList();

      // Pre-cache the new image URLs in the background so they're available
      // offline on the next view.
      for (final result in results) {
        if (result.imageUrl != null) {
          unawaited(_precacheImage(result.imageUrl!));
        }
      }

      return results;
    } catch (e) {
      debugPrint('[DiagramService] generateDiagrams failed: $e');
      return diagrams.asMap().entries.map((entry) {
        return DiagramResult(
          index: entry.key,
          description: entry.value.description,
          imageUrl: null,
          error: 'Failed to generate diagram: $e',
        );
      }).toList();
    }
  }

  /// Pre-cache a diagram image to disk via [DefaultCacheManager].
  Future<void> _precacheImage(String url) async {
    try {
      await DefaultCacheManager().getSingleFile(url);
    } catch (e) {
      debugPrint('[DiagramService] Failed to precache $url: $e');
    }
  }

  // Legacy methods kept for backward compatibility but marked deprecated.
  // They will be removed once all base64-stored diagrams have been migrated.

  /// Retrieve a stored diagram's base64 data by [key] (legacy).
  @Deprecated('Use URL-based storage via lesson content instead')
  Future<String?> getDiagram(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefPrefix$key');
  }

  /// Delete a stored diagram by [key] (legacy).
  @Deprecated('Use URL-based storage via lesson content instead')
  Future<void> deleteDiagram(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefPrefix$key');
    final keys = _loadKeyList(prefs);
    keys.remove(key);
    await prefs.setString(_indexPrefKey, json.encode(keys));
  }

  /// List all stored diagram keys (legacy).
  @Deprecated('Use URL-based storage via lesson content instead')
  Future<List<String>> listDiagramKeys() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadKeyList(prefs);
  }

  /// Clear all stored diagrams (legacy).
  @Deprecated('Use URL-based storage via lesson content instead')
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

// ═══════════════════════════════════════════════════════════════════════════
// DiagramImage widget — offline-capable diagram display
// ═══════════════════════════════════════════════════════════════════════════

/// A widget that displays a diagram from a [url], backed by
/// [flutter_cache_manager] for offline disk caching.
///
/// When the image is cached locally (previously viewed online), it is shown
/// from disk even when the device is offline. If the image has never been
/// fetched and the device is offline, a graceful placeholder is shown instead
/// of a broken-image icon.
class DiagramImage extends StatefulWidget {
  final String url;
  final double? maxHeight;
  final BoxFit fit;

  const DiagramImage({
    super.key,
    required this.url,
    this.maxHeight = 220,
    this.fit = BoxFit.contain,
  });

  @override
  State<DiagramImage> createState() => _DiagramImageState();
}

class _DiagramImageState extends State<DiagramImage> {
  FileInfo? _cachedFile;
  bool _isLoadingCache = true;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(DiagramImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _cachedFile = null;
      _isLoadingCache = true;
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(widget.url);
      if (mounted) {
        setState(() {
          _cachedFile = fileInfo;
          _isLoadingCache = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCache = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (_isLoadingCache) {
      return Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 220),
        color: cs.surfaceContainerLowest,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    // ── Cached on disk — show from file ──────────────────────────────
    if (_cachedFile != null && _cachedFile!.file.existsSync()) {
      return Container(
        constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 220),
        color: cs.surfaceContainerLowest,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _cachedFile!.file,
              fit: widget.fit,
              // These only affect in-memory decode size, not disk cache.
              // Disk cache is already provided by flutter_cache_manager above.
              cacheWidth: 1024,
              cacheHeight: 1024,
              errorBuilder: (_, __, ___) => _buildErrorPlaceholder(cs, tt),
            ),
          ),
        ),
      );
    }

    // ── Not cached yet — try network with cache-on-success ───────────
    return Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight ?? 220),
      color: cs.surfaceContainerLowest,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            widget.url,
            fit: widget.fit,
            cacheWidth: 1024,
            cacheHeight: 1024,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                // Download complete — precache to disk for offline access
                _precacheForOffline(widget.url);
                return child;
              }
              final total = loadingProgress.expectedTotalBytes;
              final progress = total != null
                  ? loadingProgress.cumulativeBytesLoaded / total
                  : null;
              return Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: progress,
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => _buildNotDownloadedPlaceholder(cs, tt),
          ),
        ),
      ),
    );
  }

  /// Fire-and-forget disk caching after a successful network download.
  Future<void> _precacheForOffline(String url) async {
    try {
      await DefaultCacheManager().getSingleFile(url);
    } catch (_) {
      // Non-critical; the network image already displayed successfully.
    }
  }

  Widget _buildErrorPlaceholder(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 40, color: cs.error),
          const SizedBox(height: 8),
          Text(
            'Failed to load diagram',
            style: tt.bodySmall?.copyWith(color: cs.error),
          ),
        ],
      ),
    );
  }

  Widget _buildNotDownloadedPlaceholder(ColorScheme cs, TextTheme tt) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'Diagram not yet downloaded — connect to the internet to view',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
  final String? imageUrl;
  final String? error;

  const DiagramResult({
    required this.index,
    required this.description,
    this.imageUrl,
    this.error,
  });

  factory DiagramResult.fromJson(Map<String, dynamic> json) {
    return DiagramResult(
      index: json['index'] as int? ?? 0,
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      error: json['error'] as String?,
    );
  }
}
