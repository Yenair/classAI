import 'package:drift/drift.dart';
import '../database/database.dart';

/// Academic calendar service with term-aware week numbering.
///
/// Integrates with the `terms` table to provide:
/// - Week number calculation within the current term
/// - Term-aware academic year context
/// - NERDC trimester schedule awareness
///
/// ## NERDC Trimesters
/// - First Term: September - December
/// - Second Term: January - April
/// - Third Term: April - July
///
/// Week numbering resets at the start of each term (Week 1).
class AcademicCalendarService {
  final AppDatabase _db;

  AcademicCalendarService(this._db);

  /// Get the current week number for a school within the active term.
  ///
  /// Returns 0 if no active term is set.
  Future<int> getCurrentWeekNumber(int schoolLocalId) async {
    final term = await _db.termsDao.getCurrent(schoolLocalId);
    if (term == null) return 0;
    return _weekNumberInTerm(term, DateTime.now());
  }

  /// Get the current term for a school.
  Future<Term?> getCurrentTerm(int schoolLocalId) async {
    return _db.termsDao.getCurrent(schoolLocalId);
  }

  /// Get all terms for a school.
  Future<List<Term>> getAllTerms(int schoolLocalId) async {
    return _db.termsDao.getBySchool(schoolLocalId);
  }

  /// Calculate the academic year for a given date.
  ///
  /// Academic years in Nigeria typically run September-August.
  /// For example, a date in October 2025 returns "2025/2026".
  static String academicYearForDate(DateTime date) {
    if (date.month >= 9) {
      // September onwards → start of academic year
      return '${date.year}/${date.year + 1}';
    } else {
      // January-August → end of academic year
      return '${date.year - 1}/${date.year}';
    }
  }

  /// Get the NERDC term name for a date.
  ///
  /// Returns null if the date doesn't fall within a known term.
  static String? termNameForDate(DateTime date) {
    // NERDC standard trimesters
    if (date.month >= 9 && date.month <= 12) {
      return 'First Term';
    } else if (date.month >= 1 && date.month <= 4) {
      return 'Second Term';
    } else if (date.month >= 4 && date.month <= 7) {
      return 'Third Term';
    }
    return null; // August break
  }

  /// Get the NERDC term number (1, 2, or 3) for a date.
  static int? termNumberForDate(DateTime date) {
    if (date.month >= 9 && date.month <= 12) return 1;
    if (date.month >= 1 && date.month <= 4) return 2;
    if (date.month >= 4 && date.month <= 7) return 3;
    return null; // August break
  }

  /// Create default NERDC terms for a school for a given academic year.
  ///
  /// This auto-generates the three trimester terms:
  /// - First Term: Sept 15 - Dec 15
  /// - Second Term: Jan 8 - April 8
  /// - Third Term: April 22 - July 22
  Future<List<int>> createDefaultTerms(
      int schoolLocalId, String academicYear) async {
    final year = int.tryParse(academicYear.split('/')[0]) ?? DateTime.now().year;

    final firstTerm = TermsCompanion.insert(
      name: 'First Term $academicYear',
      startDate: DateTime(year, 9, 15),
      endDate: DateTime(year, 12, 15),
      academicYear: academicYear,
      termNumber: 1,
      isCurrent: const Value(false),
      schoolLocalId: schoolLocalId,
    );

    final secondTerm = TermsCompanion.insert(
      name: 'Second Term $academicYear',
      startDate: DateTime(year + 1, 1, 8),
      endDate: DateTime(year + 1, 4, 8),
      academicYear: academicYear,
      termNumber: 2,
      isCurrent: const Value(false),
      schoolLocalId: schoolLocalId,
    );

    final thirdTerm = TermsCompanion.insert(
      name: 'Third Term $academicYear',
      startDate: DateTime(year + 1, 4, 22),
      endDate: DateTime(year + 1, 7, 22),
      academicYear: academicYear,
      termNumber: 3,
      isCurrent: const Value(false),
      schoolLocalId: schoolLocalId,
    );

    final ids = <int>[];
    ids.add(await _db.termsDao.insert(firstTerm));
    ids.add(await _db.termsDao.insert(secondTerm));
    ids.add(await _db.termsDao.insert(thirdTerm));

    return ids;
  }

  /// Calculate the total weeks in the current term.
  Future<int> getCurrentTermWeeks(int schoolLocalId) async {
    final term = await _db.termsDao.getCurrent(schoolLocalId);
    if (term == null) return 0;
    return _totalWeeksInTerm(term);
  }

  /// Calculate the week number within a term for a given date.
  int _weekNumberInTerm(Term term, DateTime date) {
    if (date.isBefore(term.startDate) || date.isAfter(term.endDate)) {
      return 0;
    }
    final diff = date.difference(term.startDate);
    return (diff.inDays ~/ 7) + 1;
  }

  /// Calculate the total number of weeks in a term.
  int _totalWeeksInTerm(Term term) {
    final diff = term.endDate.difference(term.startDate);
    return (diff.inDays ~/ 7) + 1;
  }
}
