// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_items_dao.dart';

// ignore_for_file: type=lint
mixin _$VaultItemsDaoMixin on DatabaseAccessor<AppDatabase> {
  $VaultItemsTable get vaultItems => attachedDatabase.vaultItems;
  VaultItemsDaoManager get managers => VaultItemsDaoManager(this);
}

class VaultItemsDaoManager {
  final _$VaultItemsDaoMixin _db;
  VaultItemsDaoManager(this._db);
  $$VaultItemsTableTableManager get vaultItems =>
      $$VaultItemsTableTableManager(_db.attachedDatabase, _db.vaultItems);
}
