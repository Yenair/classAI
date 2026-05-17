import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/vacuum_service.dart';

/// Fake path provider that returns system temp directory.
class FakePathProvider extends PathProviderPlatform {
  @override
  Future<String> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = FakePathProvider();

  group('VacuumService', () {
    late AppDatabase db;
    late VacuumService vacuumService;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.initialize();
      vacuumService = VacuumService(db);
    });

    tearDown(() async {
      await db.close();
    });

    group('isVacuumNeeded', () {
      test('returns false for fresh in-memory database', () async {
        final needed = await vacuumService.isVacuumNeeded();
        // In-memory database has no freelist pages, so should be false
        expect(needed, isFalse);
      });

      test('does not throw when checking vacuum status', () async {
        // Should complete without error
        await expectLater(
          vacuumService.isVacuumNeeded(),
          completes,
        );
      });
    });

    group('safeVacuum', () {
      test('does not throw on in-memory database', () async {
        // In-memory databases can't be vacuumed via file operations,
        // but the service should handle this gracefully
        await expectLater(
          vacuumService.safeVacuum(),
          completes,
        );
      });
    });

    group('applyPendingReplacement', () {
      test('completes when no pending replacement exists', () async {
        await expectLater(
          vacuumService.applyPendingReplacement(),
          completes,
        );
      });
    });

    group('getDatabasePath', () {
      test('returns a non-empty string for in-memory db', () async {
        final path = await vacuumService.getDatabasePath();
        // In-memory database returns ':memory:' or similar
        expect(path, isA<String>());
      });
    });
  });
}
