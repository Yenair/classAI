import 'package:drift/drift.dart';

class PdfCache extends Table {
  TextColumn get cacheKey => text()();
  BlobColumn get pdfData => blob()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cacheKey};
}
