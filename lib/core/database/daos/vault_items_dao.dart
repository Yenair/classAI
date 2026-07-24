// lib/core/database/daos/vault_items_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/vault_items.dart';

part 'vault_items_dao.g.dart';

@DriftAccessor(tables: [VaultItems])
class VaultItemsDao extends DatabaseAccessor<AppDatabase>
    with _$VaultItemsDaoMixin {
  VaultItemsDao(AppDatabase db) : super(db);

  /// Get all approved vault items.
  Future<List<VaultItem>> getApprovedItems() {
    return (select(vaultItems)
          ..where((t) => t.approvalStatus.equals('approved'))
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get vault items pending approval.
  Future<List<VaultItem>> getPendingApproval() {
    return (select(vaultItems)
          ..where((t) => t.needsApproval.equals(true))
          ..where((t) => t.approvalStatus.equals('pending'))
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get published items by a specific author.
  Future<List<VaultItem>> getItemsByAuthor(String authorTeacherId) {
    return (select(vaultItems)
          ..where((t) => t.authorTeacherId.equals(authorTeacherId))
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get a single vault item by id.
  Future<VaultItem?> getById(int id) async {
    final results = await (select(vaultItems)..where((t) => t.id.equals(id))).get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Insert a new vault item.
  Future<int> insert({
    required String title,
    required String description,
    required String subject,
    required String classLevel,
    required String curriculum,
    required String content,
    required String authorTeacherId,
    required String authorName,
    String? schoolServerId,
    String minTier = 'free',
    int creditCost = 0,
    bool needsApproval = true,
    String approvalStatus = 'pending',
    String? rejectionReason,
    String? thumbnailUrl,
  }) async {
    return into(vaultItems).insert(
      VaultItemsCompanion.insert(
        title: title,
        description: description,
        subject: subject,
        classLevel: classLevel,
        curriculum: curriculum,
        content: content,
        authorTeacherId: authorTeacherId,
        schoolServerId: schoolServerId != null ? Value(schoolServerId) : const Value.absent(),
        authorName: authorName,
        minTier: Value(minTier),
        creditCost: Value(creditCost),
        needsApproval: Value(needsApproval),
        approvalStatus: Value(approvalStatus),
        rejectionReason: rejectionReason != null ? Value(rejectionReason) : const Value.absent(),
        thumbnailUrl: thumbnailUrl != null ? Value(thumbnailUrl) : const Value.absent(),
      ),
    );
  }

  /// Approve a vault item.
  Future<void> approve(int id, {String tier = 'free', DateTime? approvedAt}) async {
    await (update(vaultItems)..where((t) => t.id.equals(id))).write(
      VaultItemsCompanion(
        approvalStatus: const Value('approved'),
        minTier: Value(tier),
        updatedAt: Value(approvedAt ?? DateTime.now()),
      ),
    );
  }

  /// Reject a vault item with a reason.
  Future<void> reject(int id, String reason) async {
    await (update(vaultItems)..where((t) => t.id.equals(id))).write(
      VaultItemsCompanion(
        approvalStatus: const Value('rejected'),
        rejectionReason: Value(reason),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Mark a vault item as acquired (set acquisition date and credit batch).
  Future<void> markAcquired(int id, {required String creditSpentBatchId}) async {
    await (update(vaultItems)..where((t) => t.id.equals(id))).write(
      VaultItemsCompanion(
        acquisitionDate: Value(DateTime.now()),
        creditSpentBatchId: Value(creditSpentBatchId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Filter vault items by subject, class level, or curriculum.
  Future<List<VaultItem>> filter({
    String? subject,
    String? classLevel,
    String? curriculum,
  }) {
    final query = select(vaultItems)
      ..where((t) => t.approvalStatus.equals('approved'))
      ..where((t) => t.isDeleted.equals(false));

    if (subject != null && subject.isNotEmpty) {
      query.where((t) => t.subject.equals(subject));
    }
    if (classLevel != null && classLevel.isNotEmpty) {
      query.where((t) => t.classLevel.equals(classLevel));
    }
    if (curriculum != null && curriculum.isNotEmpty) {
      query.where((t) => t.curriculum.equals(curriculum));
    }

    return query.get();
  }

  /// Soft delete a vault item.
  Future<void> softDelete(int id) async {
    await (update(vaultItems)..where((t) => t.id.equals(id))).write(
      VaultItemsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Hard-delete only confirmed-synced rows authored by a given teacher.
  /// Used during logout to scope-clean the outgoing teacher's data
  /// while leaving unsynced (pending) rows intact (Option b).
  Future<void> deleteSyncedRowsByAuthor(String authorTeacherId) {
    return (delete(vaultItems)
          ..where((t) => t.authorTeacherId.equals(authorTeacherId))
          ..where((t) => t.serverId.isNotNull()))
        .go();
  }
}
