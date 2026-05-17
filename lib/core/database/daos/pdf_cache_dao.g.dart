// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_cache_dao.dart';

// ignore_for_file: type=lint
mixin _$PdfCacheDaoMixin on DatabaseAccessor<AppDatabase> {
  $PdfCacheTable get pdfCache => attachedDatabase.pdfCache;
  PdfCacheDaoManager get managers => PdfCacheDaoManager(this);
}

class PdfCacheDaoManager {
  final _$PdfCacheDaoMixin _db;
  PdfCacheDaoManager(this._db);
  $$PdfCacheTableTableManager get pdfCache =>
      $$PdfCacheTableTableManager(_db.attachedDatabase, _db.pdfCache);
}
