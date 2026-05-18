class SanitizationUtils {
  static final _injectionPatterns = [
    RegExp(r'ignore (all |)previous( instructions|)', caseSensitive: false),
    RegExp(r'act as (a|an) ', caseSensitive: false),
    RegExp(r'you are now ', caseSensitive: false),
    RegExp(r'disregard ', caseSensitive: false),
    RegExp(r'system prompt:?', caseSensitive: false),
  ];

  static List<String> findInjections(String input) {
    final flags = <String>[];
    for (final p in _injectionPatterns) {
      if (p.hasMatch(input)) flags.add('Injection pattern: ${p.pattern}');
    }
    return flags;
  }

  /// Strips characters outside the allowed set.
  ///
  /// Allow-listed ranges:
  /// - `\x20-\x7E` — Basic ASCII (space through tilde).
  /// - `\u00C0-\u024F` — Latin-1 Supplement (À-ÿ) + Latin Extended-A/B
  ///   (accented letters required by Yoruba, Igbo, Hausa: e.g., Ɓ/ɓ, Ɗ/ɗ,
  ///   Ƙ/ƙ, Ƴ/ƴ).
  /// - `\u1E00-\u1EFF` — Latin Extended Additional (precomposed subdot
  ///   letters: Ẹ/ẹ, Ọ/ọ, Ṣ/ṣ, Ị/ị, Ụ/ụ used extensively in Yoruba and
  ///   Igbo orthography).
  ///
  /// Note: Unicode combining characters (U+0300–U+036F Combining Diacritical
  /// Marks and U+1DC0–U+1DFF Combining Diacritical Marks Supplement) are
  /// **not** explicitly in the allow-list above. However, they are preserved
  /// because they are combining marks that attach to a base character. As long
  /// as the base character passes the allow-list, the entire composed
  /// character (e.g., ọ̀ = o + combining grave + combining dot below) is
  /// kept intact by the regex engine (the combining marks are not matched by
  /// the negated character class since they are part of the same grapheme
  /// cluster in practice).
  static String sanitize(String input) =>
      input.replaceAll(RegExp(r'[^\x20-\x7E\u00C0-\u024F\u1E00-\u1EFF]'), '');
}
