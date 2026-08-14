import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/question_validation.dart';

void main() {
  group('validateMcqs', () {
    test('keeps valid MCQs and normalizes option keys + correct', () {
      final result = validateMcqs([
        {
          'question': 'Q1',
          'options': {' A ': 'Opt A', 'B': 'Opt B'},
          'correct': 'a',
        },
      ]);
      expect(result.validQuestions.length, equals(1));
      final kept = result.validQuestions.first;
      expect(kept['options'], equals({'A': 'Opt A', 'B': 'Opt B'}));
      expect(kept['correct'], equals('A'));
      expect(result.invalidLabels, isEmpty);
    });

    test('drops MCQs without options or a matching correct key', () {
      final result = validateMcqs([
        {'question': 'No options'},
        {
          'question': 'No correct',
          'options': {'A': 'x', 'B': 'y'},
        },
        {
          'question': 'Bad correct',
          'options': {'A': 'x'},
          'correct': 'Z',
        },
      ]);
      expect(result.validQuestions, isEmpty);
      expect(result.invalidLabels.length, equals(3));
    });

    test('drops MCQs whose options is not a map', () {
      final result = validateMcqs([
        {'question': 'Q', 'options': 'A', 'correct': 'A'},
      ]);
      expect(result.validQuestions, isEmpty);
      expect(result.invalidLabels.length, equals(1));
    });
  });

  group('validateWrittenQuestions', () {
    test('folds answer into modelAnswer and keeps valid questions', () {
      final result = validateWrittenQuestions([
        {
          'question': 'Q',
          'answer': 'A sufficiently long model answer.',
        },
      ]);
      expect(result.validQuestions.length, equals(1));
      final kept = result.validQuestions.first;
      expect(kept['modelAnswer'], equals('A sufficiently long model answer.'));
      expect(kept['answer'], equals(kept['modelAnswer']));
      expect(result.invalidLabels, isEmpty);
    });

    test('drops written questions with short or missing answers', () {
      final result = validateWrittenQuestions([
        {'question': 'Q', 'modelAnswer': 'short'},
        {'question': 'Q2'},
      ]);
      expect(result.validQuestions, isEmpty);
      expect(result.invalidLabels.length, equals(2));
    });

    test('prefers modelAnswer over answer when both are present', () {
      final result = validateWrittenQuestions([
        {
          'question': 'Q',
          'answer': 'A shorter wrong answer.',
          'modelAnswer': 'The longer correct model answer used.',
        },
      ]);
      expect(result.validQuestions.length, equals(1));
      expect(
        result.validQuestions.first['modelAnswer'],
        equals('The longer correct model answer used.'),
      );
    });
  });

  group('parseLessonQuestions', () {
    test('parses the combined mcq/theory/subjective shape', () {
      final parsed = parseLessonQuestions({
        'mcq': [
          {
            'question': 'Q1',
            'options': {'A': 'a', 'B': 'b'},
            'correct': 'B',
          },
        ],
        'theory': [
          {
            'question': 'T1',
            'modelAnswer': 'A sufficiently detailed theory answer.',
          },
        ],
        'subjective': [
          {
            'question': 'S1',
            'answer': 'A sufficiently detailed subjective answer.',
          },
        ],
      });
      expect(parsed['mcqs']!.length, equals(1));
      expect(parsed['theory']!.length, equals(1));
      expect(parsed['subjective']!.length, equals(1));
    });

    test('accepts the mcqs key alias and drops invalid items', () {
      final parsed = parseLessonQuestions({
        'mcqs': [
          {
            'question': 'Q1',
            'options': {'A': 'a', 'B': 'b'},
            'correct': 'A',
          },
          {'question': 'Broken'},
        ],
        'theory': [
          {'question': 'T1', 'modelAnswer': 'short'},
        ],
      });
      expect(parsed['mcqs']!.length, equals(1));
      expect(parsed['theory'], isEmpty);
      expect(parsed['subjective'], isEmpty);
    });

    test('handles missing keys and malformed input safely', () {
      final parsed = parseLessonQuestions({});
      expect(parsed['mcqs'], isEmpty);
      expect(parsed['theory'], isEmpty);
      expect(parsed['subjective'], isEmpty);
    });
  });
}
