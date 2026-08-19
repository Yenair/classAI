import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/pdf_service.dart';

void main() {
  group('PdfContentParser.parseLessonContent', () {
    test('parses valid lesson content into all six sections', () {
      final content = jsonEncode({
        'objectives': 'Understand fractions',
        'vocabulary': ['Numerator', 'Denominator'],
        'materials': 'Fraction circles',
        'presentation': 'Show examples on board',
        'assessment': 'Quiz',
        'homework': 'Worksheet page 5',
      });

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections.length, 6);
      expect(sections[0].key, 'Objectives');
      expect(sections[0].value, 'Understand fractions');
      expect(sections[1].key, 'Vocabulary');
      expect(sections[1].value, contains('Numerator'));
      expect(sections[2].key, 'Materials');
      expect(sections[3].key, 'Presentation');
      expect(sections[4].key, 'Assessment');
      expect(sections[5].key, 'Homework');
    });

    test('skips empty sections', () {
      final content = jsonEncode({
        'objectives': 'Learn about verbs',
        'vocabulary': '',
        'materials': null,
        'presentation': 'Demo',
        'assessment': '',
        'homework': [],
      });

      final sections = PdfContentParser.parseLessonContent(content);

      // Only 'objectives' and 'presentation' have non-empty values
      final keys = sections.map((s) => s.key).toList();
      expect(keys, contains('Objectives'));
      expect(keys, contains('Presentation'));
      expect(keys, isNot(contains('Vocabulary')));
      expect(keys, isNot(contains('Materials')));
      expect(keys, isNot(contains('Assessment')));
      expect(keys, isNot(contains('Homework')));
    });

    test('handles malformed JSON by returning raw text', () {
      const content = '{invalid json content';

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections.length, 1);
      expect(sections[0].key, '');
      expect(sections[0].value, content);
    });

    test('handles non-map JSON (array) by returning raw text', () {
      final content = jsonEncode(['item1', 'item2']);

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections.length, 1);
      expect(sections[0].key, '');
      expect(sections[0].value, content);
    });

    test('handles list-valued sections with bullet formatting', () {
      final content = jsonEncode({
        'objectives': ['Goal 1', 'Goal 2', 'Goal 3'],
      });

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections.length, 1);
      expect(sections[0].key, 'Objectives');
      expect(sections[0].value, contains('• Goal 1'));
      expect(sections[0].value, contains('• Goal 2'));
      expect(sections[0].value, contains('• Goal 3'));
    });

    test('returns empty list for empty content', () {
      final sections = PdfContentParser.parseLessonContent('');
      expect(sections, isEmpty);
    });

    test('handles Nigerian diacritics and Unicode characters', () {
      final content = jsonEncode({
        'objectives:': 'Learn about ẹ̀kọ́ and àwọn ìjà',
      });

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections, isNotEmpty);
      // The key 'objectives:' is not a standard section key so goes to additional notes
      expect(sections[0].value, contains('ẹ̀kọ́'));
    });

    test('handles smart quotes and em dashes in content', () {
      final content = jsonEncode({
        'presentation': "The teacher said \u201cWelcome\u201d to the class\u2009\u2014\u2009and began",
      });

      final sections = PdfContentParser.parseLessonContent(content);

      expect(sections.length, 1);
      expect(sections[0].value, contains('\u201c'));
      expect(sections[0].value, contains('\u2014'));
    });
  });

  group('sanitizePdfFilename', () {
    test('removes unsafe characters', () {
      expect(sanitizePdfFilename('file<name>'), 'filename');
    });

    test('collapses whitespace into underscores', () {
      expect(sanitizePdfFilename('my lesson plan'), 'my_lesson_plan');
    });

    test('returns default for empty input', () {
      expect(sanitizePdfFilename(''), 'lesson');
    });

    test('returns default for whitespace-only input', () {
      expect(sanitizePdfFilename('   '), 'lesson');
    });

    test('preserves normal alphanumeric text', () {
      expect(sanitizePdfFilename('MathLesson1'), 'MathLesson1');
    });

    test('trims leading and trailing underscores', () {
      expect(sanitizePdfFilename('_hello_'), 'hello');
    });
  });
}
