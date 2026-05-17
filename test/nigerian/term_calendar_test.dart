import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/academic_calendar_service.dart';

void main() {
  group('AcademicCalendarService (static helpers)', () {
    group('academicYearForDate', () {
      test('returns correct year for First Term (Sept-Dec)', () {
        // September 2025 -> academic year 2025/2026
        final date = DateTime(2025, 9, 15);
        expect(AcademicCalendarService.academicYearForDate(date), '2025/2026');
      });

      test('returns correct year for Second Term (Jan-March)', () {
        // January 2026 -> academic year 2025/2026
        final date = DateTime(2026, 1, 15);
        expect(AcademicCalendarService.academicYearForDate(date), '2025/2026');
      });

      test('returns correct year for Third Term (April-July)', () {
        // June 2026 -> academic year 2025/2026
        final date = DateTime(2026, 6, 15);
        expect(AcademicCalendarService.academicYearForDate(date), '2025/2026');
      });

      test('handles year boundary in August', () {
        // August 2026 is the end of academic year 2025/2026
        // (First Term starts in September, so August is still previous year)
        final date = DateTime(2026, 8, 15);
        expect(AcademicCalendarService.academicYearForDate(date), '2025/2026');
      });
    });

    group('termNumberForDate', () {
      test('returns 1 for First Term months (Sept-Dec)', () {
        expect(AcademicCalendarService.termNumberForDate(DateTime(2025, 9, 1)),
            1);
        expect(AcademicCalendarService.termNumberForDate(DateTime(2025, 10, 15)),
            1);
        expect(AcademicCalendarService.termNumberForDate(DateTime(2025, 12, 31)),
            1);
      });

      test('returns 2 for Second Term months (Jan-March)', () {
        expect(AcademicCalendarService.termNumberForDate(DateTime(2026, 1, 15)),
            2);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 3, 1)), 2);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 3, 31)), 2);
      });

      test('returns 3 for Third Term months (April-July)', () {
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 4, 1)), 3);
        expect(AcademicCalendarService.termNumberForDate(DateTime(2026, 5, 1)),
            3);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 6, 15)), 3);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 7, 31)), 3);
      });

      test('returns null for off-term months (August)', () {
        expect(AcademicCalendarService.termNumberForDate(DateTime(2026, 8, 15)),
            isNull);
      });
    });

    group('termNameForDate', () {
      test('returns correct NERDC term names', () {
        expect(AcademicCalendarService.termNameForDate(DateTime(2025, 9, 1)),
            'First Term');
        expect(AcademicCalendarService.termNameForDate(DateTime(2026, 1, 15)),
            'Second Term');
        expect(AcademicCalendarService.termNameForDate(DateTime(2026, 5, 1)),
            'Third Term');
      });

      test('returns null for off-term months', () {
        expect(AcademicCalendarService.termNameForDate(DateTime(2026, 8, 15)),
            isNull);
      });
    });

    group('NERDC trimester date boundaries', () {
      test('First Term starts September and ends December', () {
        // First Term: Sept - Dec
        expect(AcademicCalendarService.termNumberForDate(DateTime(2025, 8, 31)),
            isNull); // August - off term
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2025, 9, 1)),
            1); // Sept 1 - First Term
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2025, 12, 31)),
            1); // Dec 31 - still First Term
      });

      test('Second Term starts January and ends March', () {
        // Second Term: Jan - March
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 1, 1)), 2);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 3, 31)), 2);
        expect(AcademicCalendarService.termNumberForDate(DateTime(2026, 4, 1)),
            3); // April - Third Term
      });

      test('Third Term starts April and ends July', () {
        // Third Term: April - July
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 4, 1)), 3);
        expect(
            AcademicCalendarService.termNumberForDate(DateTime(2026, 7, 31)), 3);
        expect(AcademicCalendarService.termNumberForDate(DateTime(2026, 8, 1)),
            isNull); // August - off term
      });
    });
  });
}
