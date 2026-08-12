import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSchemeWeeks', () {
    test('parses a normal {"weeks": [...]} payload', () {
      final weeks = parseSchemeWeeks({
        'weeks': [
          {'week': 1, 'topic': 'Intro', 'objectives': ['a', 'b']},
          {'week': 2, 'topic': 'Cells', 'objectives': ['c']},
        ],
      });
      expect(weeks, hasLength(2));
      expect(weeks.first['week'], 1);
      expect(weeks.first['topic'], 'Intro');
    });

    test(
        'recovers weeks from the proxy {text:...} fallback when the model '
        'wraps the JSON in a markdown code fence', () {
      // Regression: deepseek-proxy/gemini-proxy return
      // {"generatedJson": {"text": "<raw>"}} whenever server-side JSON.parse
      // fails — which happens when the model fences the JSON with ```json.
      // parseSchemeWeeks previously returned [] for this shape → the Auto
      // Generate flow threw "AI returned no weeks".
      final weeks = parseSchemeWeeks({
        'text': '```json\n'
            '{"weeks":[{"week":1,"topic":"Intro","objectives":["a"]}]}\n'
            '```',
      });
      expect(weeks, hasLength(1));
      expect(weeks.first['week'], 1);
    });

    test('recovers weeks from the {text:...} fallback with prose around it',
        () {
      final weeks = parseSchemeWeeks({
        'text': 'Here is your scheme of work:\n'
            '{"weeks":[{"week":1,"topic":"Intro","objectives":["a"]}]}\n'
            'Regards, the AI.',
      });
      expect(weeks, hasLength(1));
      expect(weeks.first['topic'], 'Intro');
    });

    test('recovers weeks nested under a wrapper key', () {
      final weeks = parseSchemeWeeks({
        'scheme_of_work': {
          'weeks': [
            {'week': 1, 'topic': 'Intro', 'objectives': ['a']},
          ],
        },
      });
      expect(weeks, hasLength(1));
    });

    test('decodes a string-encoded weeks array', () {
      final weeks = parseSchemeWeeks({
        'weeks': '[{"week":1,"topic":"Intro","objectives":["a"]}]',
      });
      expect(weeks, hasLength(1));
    });

    test('throws a descriptive error when the model returns an error object',
        () {
      expect(
        () => parseSchemeWeeks({'error': 'Content policy violation'}),
        throwsA(predicate<FormatException>(
          (e) => e.message.toString().contains('error'),
        )),
      );
    });

    test('returns an empty list when nothing is recoverable', () {
      expect(parseSchemeWeeks({'text': 'Sorry, I cannot help with that.'}),
          isEmpty);
      expect(parseSchemeWeeks(<String, dynamic>{}), isEmpty);
    });
  });
}
