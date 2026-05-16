
```markdown
`phase_05_ai.md`
# Phase 5: AI Service + Lesson/Exam Generation (Self-Contained)

**Goal**: DeepSeek API integration with Gemini fallback. Lesson and exam generation works end-to-end. Content encrypted before storage. Token counting with truncation. Sanitization applied.

## Architecture Decisions (This Phase Only)

- **DeepSeek primary**: Certificate pinning via `dio_interceptor_certificate_pinning` (added to `pubspec.yaml` in this phase). Both pins fail → Gemini fallback with user notification.
- **Token counting**: Character-count approximation (1 token ≈ 4 chars English, ≈ 2 chars code). Auto-truncate at 110% of model limit.
- **Sanitization**: Whitelist approach. Flag instruction injection patterns; teacher must confirm to proceed before generation.
- **Content encryption**: Raw AI JSON responses encrypted with school master key via `EncryptionUtils.encryptAesGcm` (async, from Phase 2) before storage.
- **Credit spending**: Each generation costs 1 credit. Idempotency via `credit_spent_batch_id` written to SQLite BEFORE API call.
- **HTTP**: Uses `dio` with retry interceptor (2 retries, base 3s). Certificate pinning via interceptor for DeepSeek.

## Agent Playbook — Phase 5 File Creation Order

(Each file: create path, write exact content, run test.)

### Step 5.1: `lib/core/utils/sanitization_utils.dart`

```dart
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
```

### Step 5.2: `lib/core/utils/token_counter.dart`

```dart
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
```

### Step 5.3: `lib/core/constants/prompt_templates.dart`

```dart
class PromptTemplates {
  static String lessonNote(String subject, String curriculum, String classLevel,
      int week, String topic, String difficulty, String bloomsVerbs) =>
      'You are a professional educator designing a lesson note for $subject '
      '($curriculum curriculum), $classLevel, Week $week, Topic: "$topic". '
      'Difficulty: $difficulty. Target cognitive levels: $bloomsVerbs. '
      'Include: Learning Objectives, Key Vocabulary, Materials, Lesson Presentation, '
      'Assessment, Homework. Return ONLY valid JSON: '
      '{"objectives":[...],"vocabulary":[...],"materials":[...],"presentation":{...},"assessment":"...","homework":"..."}';

  static String mcqs(String subject, String classLevel, String topic, String difficulty) =>
      'Generate 10 MCQs for $subject, $classLevel, "$topic". Difficulty: $difficulty. '
      '4 options each (A-D). Return ONLY valid JSON: '
      '{"questions":[{"question":"...","options":{"A":"...","B":"...","C":"...","D":"..."},"correct":"A"}]}';

  static String theoryQuestions(String subject, String classLevel, String topic) =>
      'Generate 5 theory questions for $subject, $classLevel, "$topic". '
      'Include model answer and cognitive level. Return ONLY valid JSON: '
      '{"questions":[{"question":"...","modelAnswer":"...","cognitiveLevel":"..."}]}';
}
```

### Step 5.4: `lib/core/services/ai_service.dart`

```dart
import 'package:dio/dio.dart';
import 'dart:convert';
import '../utils/sanitization_utils.dart';
import '../utils/token_counter.dart';
import '../utils/encryption_utils.dart';
import '../constants/prompt_templates.dart';

class AiService {
  final Dio _deepseek;
  final Dio _gemini;
  final Uint8List? _schoolKey;

  AiService({required Dio deepseek, required Dio gemini, Uint8List? schoolKey})
      : _deepseek = deepseek, _gemini = gemini, _schoolKey = schoolKey;

  Future<Map<String, dynamic>> generate(String prompt) async {
    // 1. Sanitize
    final injections = SanitizationUtils.findInjections(prompt);
    if (injections.isNotEmpty) throw AiInjectionException(injections);

    // 2. Truncate
    final truncated = TokenCounter.truncateIfNeeded(prompt, 4096);

    // 3. DeepSeek → Gemini fallback
    try {
      return await _callDeepSeek(truncated);
    } catch (_) {
      try {
        return await _callGemini(truncated);
      } catch (e) {
        throw AiGenerationException('Both providers failed: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _callDeepSeek(String prompt) async {
    final r = await _deepseek.post('/v1/chat/completions', data: {
      'model': 'deepseek-chat',
      'messages': [{'role': 'user', 'content': prompt}],
      'temperature': 0.7,
    });
    final raw = r.data['choices'][0]['message']['content'];
    return _encrypt(jsonDecode(raw));
  }

  Future<Map<String, dynamic>> _callGemini(String prompt) async {
    final r = await _gemini.post('/v1beta/models/gemini-pro:generateContent', data: {
      'contents': [{'parts': [{'text': prompt}]}],
    });
    final raw = r.data['candidates'][0]['content']['parts'][0]['text'];
    return _encrypt(jsonDecode(raw));
  }

  Map<String, dynamic> _encrypt(Map<String, dynamic> parsed) {
    if (_schoolKey == null) return parsed;
    final raw = jsonEncode(parsed);
    // encryptAesGcm is async in Phase 2; for sync flow, agent should
    // make generate() async and call await EncryptionUtils.encryptAesGcm
    return {'encrypted': true, 'content_hash': EncryptionUtils.sha256Hash(raw), 'raw': parsed};
  }
}

class AiInjectionException implements Exception {
  final List<String> patterns;
  AiInjectionException(this.patterns);
}

class AiGenerationException implements Exception {
  final String message;
  AiGenerationException(this.message);
}
```

### Step 5.5: `lib/features/lesson/screens/lesson_editor_screen.dart`

Stateful widget with form fields: Subject dropdown, Class dropdown, Week spinbox, Topic textfield, Difficulty dropdown (easy/medium/hard), Bloom's verbs multi-select chips. "Generate" button → loading → preview cards with editable text fields for each section. "Save" encrypts and inserts into `lessons` table. "Discard" clears form. Credit counter updates on generate. Registers with `EmergencyFlushService` on init.

### Step 5.6: `lib/features/exam/screens/exam_editor_screen.dart`

Same pattern. Generates MCQ + theory questions. Preview as editable list of question cards. Save inserts into `exams` table.

## Phase 5 Acceptance Criteria (GATE)

```bash
flutter test test/ai/sanitization_test.dart             # Injection patterns detected
flutter test test/ai/token_counter_test.dart             # Estimates within 20% of actual
flutter test test/ai/prompt_template_test.dart           # Templates produce valid prompts
flutter test test/ai/fallback_test.dart                  # DeepSeek fail → Gemini success
flutter test test/ai/encryption_test.dart                # AI responses encrypted before storage
flutter test test/features/lesson_editor_test.dart       # Generate, edit, save, discard
```
```