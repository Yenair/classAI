import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/pdf_cache.dart';

part 'pdf_cache_dao.g.dart';

@DriftAccessor(tables: [PdfCache])
class PdfCacheDao extends DatabaseAccessor<AppDatabase>
    with _$PdfCacheDaoMixin {
  PdfCacheDao(AppDatabase db) : super(db);

  /// Retrieve cached PDF bytes by composite key, or null if not cached.
  Future<Uint8List?> get(String cacheKey) async {
    final row = await (select(pdfCache)
          ..where((t) => t.cacheKey.equals(cacheKey)))
        .getSingleOrNull();
    return row?.pdfData;
  }

  /// Insert or replace a cached PDF entry.
  Future<void> insert(
    String cacheKey,
    Uint8List pdfData,
    DateTime cachedAt,
  ) async {
    await into(pdfCache).insertOnConflictUpdate(
      PdfCacheCompanion.insert(
        cacheKey: cacheKey,
        pdfData: pdfData,
        cachedAt: cachedAt,
      ),
    );
  }

  /// Clear all cached PDFs (e.g., on school change or logout).
  Future<void> clearAll() async {
    await delete(pdfCache).go();
  }
}
