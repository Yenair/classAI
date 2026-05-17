import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/constants/prompt_templates.dart';

void main() {
  group('PromptTemplates', () {
    group('lessonNote', () {
      test('produces a valid prompt string', () {
        final prompt = PromptTemplates.lessonNote(
          'Mathematics',
          'NERDC',
          'JSS 1',
          1,
          'Algebra',
          'medium',
          'Remember, Understand',
        );
        expect(prompt, contains('Mathematics'));
        expect(prompt, contains('NERDC'));
        expect(prompt, contains('JSS 1'));
        expect(prompt, contains('Week 1'));
        expect(prompt, contains('Algebra'));
        expect(prompt, contains('medium'));
        expect(prompt, contains('Remember, Understand'));
        expect(prompt, contains('ONLY valid JSON'));
      });

      test('prompt is not empty', () {
        final prompt = PromptTemplates.lessonNote(
          'Science', 'NERDC', 'SSS 1', 3, 'Photosynthesis', 'hard', 'Analyze',
        );
        expect(prompt.isNotEmpty, isTrue);
        expect(prompt.length, greaterThan(100));
      });
    });

    group('mcqs', () {
      test('produces a valid prompt string', () {
        final prompt = PromptTemplates.mcqs(
          'Mathematics', 'JSS 2', 'Fractions', 'easy',
        );
        expect(prompt, contains('10 MCQs'));
        expect(prompt, contains('Mathematics'));
        expect(prompt, contains('JSS 2'));
        expect(prompt, contains('Fractions'));
        expect(prompt, contains('easy'));
        expect(prompt, contains('ONLY valid JSON'));
      });

      test('prompt requests options A-D', () {
        final prompt = PromptTemplates.mcqs(
          'English', 'SSS 1', 'Comprehension', 'medium',
        );
        expect(prompt, contains('"A"'));
        expect(prompt, contains('"B"'));
        expect(prompt, contains('"C"'));
        expect(prompt, contains('"D"'));
      });
    });

    group('theoryQuestions', () {
      test('produces a valid prompt string', () {
        final prompt = PromptTemplates.theoryQuestions(
          'Physics', 'SSS 2', 'Thermodynamics',
        );
        expect(prompt, contains('5 theory questions'));
        expect(prompt, contains('Physics'));
        expect(prompt, contains('SSS 2'));
        expect(prompt, contains('Thermodynamics'));
        expect(prompt, contains('modelAnswer'));
        expect(prompt, contains('cognitiveLevel'));
      });
    });
  });
}
