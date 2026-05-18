import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../constants/app_constants.dart';

/// Low storage monitoring service for ClassAI.
///
/// Monitors available disk space and provides alerts:
/// - **Warning**: < 500MB available (alert user)
/// - **Critical**: < 100MB available (block PDF generation)
///
/// This is critical for devices with limited storage common
/// in Nigerian schools.
class LowStorageService {
  /// The current disk space status.
  late LowStorageLevel _currentLevel;
  LowStorageLevel get currentLevel => _currentLevel;

  /// Callback when storage level changes.
  void Function(LowStorageLevel level)? onLevelChanged;

  /// Set to true when disk space measurement fails.
  /// When true, storage checks are skipped (assume OK) to avoid
  /// false-positive blocks (e.g., on emulators where disk queries fail).
  bool _diskQueryFailed = false;

  LowStorageService() {
    _currentLevel = LowStorageLevel.ok;
  }

  /// Check available disk space for the app's documents directory.
  ///
  /// Returns [LowStorageLevel] indicating the current status.
  Future<LowStorageLevel> checkDiskSpace() async {
    try {
      // If the disk query previously failed, skip the check entirely
      // and assume storage is OK. This prevents false-positive blocks
      // on platforms where disk queries are unsupported (e.g. emulators).
      if (_diskQueryFailed) {
        return LowStorageLevel.ok;
      }

      final availableMB = await _getAvailableMb();
      if (availableMB == null) return LowStorageLevel.ok;

      LowStorageLevel newLevel;
      if (availableMB < AppConstants.criticalStorageThresholdMB) {
        newLevel = LowStorageLevel.critical;
      } else if (availableMB < AppConstants.warningStorageThresholdMB) {
        newLevel = LowStorageLevel.warning;
      } else {
        newLevel = LowStorageLevel.ok;
      }

      if (newLevel != _currentLevel) {
        _currentLevel = newLevel;
        onLevelChanged?.call(newLevel);
      }

      return newLevel;
    } catch (e) {
      debugPrint('LowStorageService.checkDiskSpace failed: $e');
      return LowStorageLevel.ok;
    }
  }

  /// Check if PDF generation is allowed based on available disk space.
  ///
  /// PDF generation is blocked when storage is critical (< 100MB).
  Future<bool> canGeneratePdf() async {
    final level = await checkDiskSpace();
    return level != LowStorageLevel.critical;
  }

  /// Get available disk space as a human-readable string.
  Future<String> getDiskSpaceDisplay() async {
    try {
      final availableMB = await _getAvailableMb();
      if (availableMB == null) return 'Unknown';

      if (availableMB >= 1024) {
        final availableGB = availableMB / 1024;
        return '${availableGB.toStringAsFixed(1)} GB';
      }
      return '${availableMB.toStringAsFixed(0)} MB';
    } catch (_) {
      return 'Unknown';
    }
  }

  /// Get available disk space in megabytes.
  ///
  /// Uses platform-specific queries via [Process.run] where available,
  /// and falls back to [Directory.statSync] heuristic on mobile.
  Future<double?> _getAvailableMb() async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final path = docDir.path;

      // Try platform-specific shell commands first
      double? freeBytes;

      if (Platform.isWindows) {
        // `wmic` on Windows returns free space in bytes
        freeBytes = await _queryWindowsDiskFree(path);
      } else if (Platform.isLinux || Platform.isMacOS) {
        freeBytes = await _queryUnixDiskFree(path);
      }

      if (freeBytes != null && freeBytes > 0) {
        return freeBytes / (1024 * 1024);
      }

      // Fallback: use stat on the directory itself.
      // On most platforms stat.size is the directory entry size,
      // not the free space, so this is a coarse estimate.
      try {
        final dir = Directory(path);
        final stat = dir.statSync();
        if (stat.size > 10 * 1024 * 1024) {
          // If stat.size is large, it might actually be free space
          return stat.size / (1024 * 1024);
        }
      } catch (_) {
        // Ignore stat errors
      }

      // Last resort: disk measurement failed. Instead of returning 0.0
      // (which would trigger a false-positive storage block), set a flag
      // so the caller can skip the check, and return a conservative
      // estimate (500 MB) to avoid blocking PDF generation on platforms
      // where disk queries fail (e.g. most mobile emulators).
      _diskQueryFailed = true;
      debugPrint(
        'LowStorageService._getAvailableMb: disk query failed on all '
        'platform-specific methods; falling back to 500 MB estimate',
      );
      await Sentry.captureException(
        Exception(
          'LowStorageService: disk query failed on all methods for path: $path',
        ),
      );
      return 500.0;
    } catch (e) {
      _diskQueryFailed = true;
      debugPrint('LowStorageService._getAvailableMb: unexpected error: $e');
      await Sentry.captureException(e);
      return null;
    }
  }

  /// Query free disk space on Windows using `wmic`.
  Future<double?> _queryWindowsDiskFree(String path) async {
    try {
      // Extract drive letter (e.g., "C:" from "C:\Users\...")
      final drive = path.substring(0, 2); // e.g., "C:"
      final result = await Process.run(
        'wmic',
        ['logicaldisk', 'where', 'DeviceID="$drive"', 'get', 'FreeSpace'],
        runInShell: true,
      );
      // Parse output — first line is header, second line has the value
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      for (final line in lines) {
        final parsed = double.tryParse(line);
        if (parsed != null && parsed > 0) return parsed;
      }
    } catch (_) {
      // Silently fall through
    }
    return null;
  }

  /// Query free disk space on Linux/macOS using `df`.
  Future<double?> _queryUnixDiskFree(String path) async {
    try {
      // `df -k` gives free space in 1K blocks
      final result = await Process.run(
        'df',
        ['-k', path],
        runInShell: true,
      );
      // Parse output: skip header line, second line has free block count
      // Typical output: "Filesystem  1K-blocks   Used  Available  Use%  Mounted"
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lines.length >= 2) {
        final parts = lines[1].split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          // Available blocks is typically the 4th column (index 3)
          final availableBlocks = double.tryParse(parts[3]);
          if (availableBlocks != null && availableBlocks > 0) {
            // Convert 1K blocks to bytes
            return availableBlocks * 1024;
          }
        }
      }
    } catch (_) {
      // Silently fall through
    }
    return null;
  }
}

/// Levels of storage availability.
enum LowStorageLevel {
  /// Sufficient disk space available.
  ok,

  /// Low disk space (< 500MB). Should alert user.
  warning,

  /// Critical disk space (< 100MB). Block PDF generation.
  critical,
}
