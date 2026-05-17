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

  static String sanitize(String input) =>
      input.replaceAll(RegExp(r'[^\x20-\x7E\u00C0-\u00FF]'), '');
}
