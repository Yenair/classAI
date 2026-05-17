import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/utils/token_counter.dart';

void main() {
  group('TokenCounter', () {
    group('estimateTokens', () {
      test('empty string returns 0', () {
        expect(TokenCounter.estimateTokens(''), equals(0));
      });

      test('estimates ASCII text (~1 token per 4 chars)', () {
        // "Hello, World!" = 13 chars → ~3 tokens
        final tokens = TokenCounter.estimateTokens('Hello, World!');
        expect(tokens, greaterThanOrEqualTo(2));
        expect(tokens, lessThanOrEqualTo(5));
      });

      test('estimates longer text proportionally', () {
        final short = TokenCounter.estimateTokens('Hello World');
        final long = TokenCounter.estimateTokens(
          'Hello World ' * 100,
        );
        // ~1100 chars → ~275 tokens
        expect(long, greaterThan(short * 50));
      });

      test('multibyte characters count more', () {
        final ascii = TokenCounter.estimateTokens('hello world');
        final unicode = TokenCounter.estimateTokens('hélló wörld');
        // Unicode chars cost 2 per char → more tokens
        // "hello world": 11 ASCII = 11 cost → 2 tokens
        // "hélló wörld": 7 ASCII + 4 unicode = 7+8 = 15 cost → 3 tokens
        expect(unicode, greaterThan(ascii));
      });
    });

    group('truncateIfNeeded', () {
      test('returns original text if within 110% of limit', () {
        const text = 'Short text';
        expect(TokenCounter.truncateIfNeeded(text, 100), equals(text));
      });

      test('truncates when over 110% of limit', () {
        // Create a long string
        final longText = 'Hello World! ' * 200; // ~2800 chars → ~700 tokens
        final result = TokenCounter.truncateIfNeeded(longText, 100);
        expect(result.length, lessThan(longText.length));
        expect(result.endsWith('...'), isTrue);
      });

      test('truncated text has reasonable token estimate', () {
        final longText = 'Word ' * 500; // ~2500 chars
        final truncated = TokenCounter.truncateIfNeeded(longText, 100);
        final est = TokenCounter.estimateTokens(truncated);
        // Should be within ~110% of maxTokens
        expect(est, lessThanOrEqualTo(150));
      });
    });
  });
}
