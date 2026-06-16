// lib/core/database/daos/schools_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/schools.dart';

part 'schools_dao.g.dart';

@DriftAccessor(tables: [Schools])
class SchoolsDao extends DatabaseAccessor<AppDatabase> with _$SchoolsDaoMixin {
  SchoolsDao(AppDatabase db) : super(db);

  /// Get the school record.
  Future<School?> get() async {
    final results = await (select(schools)
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get the school by local ID.
  Future<School?> getByLocalId(int localId) async {
    final results =
        await (select(schools)..where((t) => t.localId.equals(localId))).get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Upsert a school record by [serverId] and return the resulting row.
  ///
  /// - If a row with [serverId] already exists, it is updated in place and
  ///   the existing [localId] is preserved.
  /// - If no row exists, a new row is inserted and the auto-generated
  ///   [localId] is returned.
  ///
  /// Returns the fully populated [School] row **including** [School.localId],
  /// so callers can immediately use it as a valid foreign key without any
  /// additional round-trip queries.
  Future<School> upsertByServerId({
    required String serverId,
    required String schoolName,
    required String shortCode,
    required String subscriptionTier,
    required String activeCurriculum,
    String? activeCurriculumVersion,
    required int totalSeats,
    String? schoolMasterKeyWrapped,
    String? adminRecoveryEmail,
    bool adminRecoveryEmailVerified = false,
    DateTime? expiryDate,
    String? activationCode,
  }) async {
    // ── UPDATE path: school already exists ───────────────────────────────────
    {
      final existing = await (select(schools)
            ..where((s) => s.serverId.equals(serverId))
            ..orderBy([(s) => OrderingTerm(expression: s.localId)])
            ..limit(1))
          .getSingleOrNull();

      if (existing != null) {
        await (update(schools)
              ..where((s) => s.localId.equals(existing.localId)))
            .write(
          SchoolsCompanion(
            schoolName: Value(schoolName),
            shortCode: Value(shortCode),
            subscriptionTier: Value(subscriptionTier),
            activeCurriculum: Value(activeCurriculum),
            activeCurriculumVersion: Value(activeCurriculumVersion),
            totalSeats: Value(totalSeats),
            schoolMasterKeyWrapped: Value(schoolMasterKeyWrapped),
            adminRecoveryEmail: Value(adminRecoveryEmail),
            adminRecoveryEmailVerified: Value(adminRecoveryEmailVerified),
            expiryDate: Value(expiryDate),
            activationCode: Value(activationCode),
            updatedAt: Value(DateTime.now()),
            updateCounter: Value(existing.updateCounter + 1),
          ),
        );
        return existing;
      }
    }

    // ── INSERT path: school is new ────────────────────────────────────────────
    {
      final newLocalId = await into(schools).insert(
        SchoolsCompanion.insert(
          serverId: Value(serverId),
          schoolName: schoolName,
          shortCode: shortCode,
          subscriptionTier: Value(subscriptionTier),
          activeCurriculum: Value(activeCurriculum),
          activeCurriculumVersion: Value(activeCurriculumVersion),
          totalSeats: Value(totalSeats),
          schoolMasterKeyWrapped: Value(schoolMasterKeyWrapped),
          adminRecoveryEmail: Value(adminRecoveryEmail),
          adminRecoveryEmailVerified: Value(adminRecoveryEmailVerified),
          expiryDate: Value(expiryDate),
          activationCode: Value(activationCode),
        ),
      );

      // Re-fetch so the caller gets a fully populated row
      // (all NOT-NULL columns with DB defaults are fully materialised).
      return (await (select(schools)
            ..where((s) => s.localId.equals(newLocalId))
            ..limit(1))
          .getSingle());
    }
  }

  /// Updates subscription-related fields on the school identified by [serverId].
  Future<void> updateSubscriptionFields({
    required String serverId,
    required String subscriptionTier,
    DateTime? expiryDate,
    String? activationCode,
  }) async {
    await (update(schools)
          ..where((s) => s.serverId.equals(serverId)))
        .write(
      SchoolsCompanion(
        subscriptionTier: Value(subscriptionTier),
        expiryDate: Value(expiryDate),
        activationCode: Value(activationCode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
