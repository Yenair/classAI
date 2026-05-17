import 'package:drift/drift.dart';
import 'schools.dart';

/// NERDC trimester terms table.
///
/// Schema:
/// - `id`: auto-increment primary key
/// - `name`: e.g., "First Term 2025/2026"
/// - `start_date`: first day of the term
/// - `end_date`: last day of the term
/// - `academic_year`: e.g., "2025/2026"
/// - `term_number`: 1, 2, or 3 (First, Second, Third)
/// - `is_current`: boolean flag for the active term
/// - `school_local_id`: FK to schools.local_id
/// - `created_at`, `updated_at`: timestamps
class Terms extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  TextColumn get academicYear => text()();
  IntColumn get termNumber => integer()(); // 1, 2, or 3
  BoolColumn get isCurrent => boolean().withDefault(const Constant(false))();
  IntColumn get schoolLocalId => integer().references(Schools, #localId)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
