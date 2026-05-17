class TokenCounter {
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    int tokens = 0;
    for (final char in text.runes) {
      tokens += (char <= 0x7F) ? 1 : 2;
    }
    return tokens ~/ 4;
  }

  static String truncateIfNeeded(String text, int maxTokens) {
    final est = estimateTokens(text);
    if (est <= maxTokens * 1.1) return text;
    final ratio = maxTokens / est;
    final targetLen = (text.length * ratio * 0.9).round();
    return '${text.substring(0, targetLen)}...';
  }
}
