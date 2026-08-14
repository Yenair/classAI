// lib/core/services/question_validation.dart
//
// Shared, pure question validators used by the exam editor, the lesson
// editor (Phase 2 structured assessment questions), and Phase 3 hybrid exam
// compilation. Behavior is identical to the private copies that previously
// lived in lib/features/exam/screens/exam_editor_screen.dart.

/// Result of validating a generated question list.
typedef QuestionValidationResult = ({
  List<Map<String, dynamic>> validQuestions,
  List<String> invalidLabels,
});

/// Human-readable label for a question, used in validation messages.
String questionLabel(Map<String, dynamic> question) {
  final questionText = question['question']?.toString().trim();
  if (questionText != null && questionText.isNotEmpty) {
    return questionText;
  }
  final topic = question['topic']?.toString().trim();
  if (topic != null && topic.isNotEmpty) {
    return topic;
  }
  return 'untitled question';
}

/// Normalizes a written question so `answer` (subjective style) and
/// `modelAnswer` (theory style) agree on a single field, preferring
/// `modelAnswer` when both are present.
Map<String, dynamic> normalizeWrittenQuestion(
  Map<String, dynamic> question,
) {
  final normalized = Map<String, dynamic>.from(question);
  final modelAnswer = normalized['modelAnswer']?.toString().trim();
  final answer = normalized['answer']?.toString().trim();
  if (modelAnswer == null || modelAnswer.isEmpty) {
    if (answer != null && answer.isNotEmpty) {
      normalized['modelAnswer'] = answer;
    }
  } else {
    normalized['modelAnswer'] = modelAnswer;
  }
  return normalized;
}

/// Validates MCQ questions: normalizes the `options` map keys, matches the
/// `correct` key case-insensitively, and drops malformed items.
QuestionValidationResult validateMcqs(
  List<Map<String, dynamic>> questions,
) {
  final validQuestions = <Map<String, dynamic>>[];
  final invalidLabels = <String>[];

  for (final question in questions) {
    final normalized = Map<String, dynamic>.from(question);
    final optionsRaw = normalized['options'];
    if (optionsRaw is! Map) {
      invalidLabels.add(questionLabel(normalized));
      continue;
    }

    final options = <String, dynamic>{};
    for (final entry in optionsRaw.entries) {
      final key = entry.key.toString().trim();
      if (key.isNotEmpty) {
        options[key] = entry.value;
      }
    }

    if (options.isEmpty) {
      invalidLabels.add(questionLabel(normalized));
      continue;
    }

    final correctRaw = normalized['correct']?.toString().trim();
    if (correctRaw == null || correctRaw.isEmpty) {
      invalidLabels.add(questionLabel(normalized));
      continue;
    }

    String? matchedKey;
    for (final key in options.keys) {
      if (key.toLowerCase() == correctRaw.toLowerCase()) {
        matchedKey = key;
        break;
      }
    }

    if (matchedKey == null) {
      invalidLabels.add(questionLabel(normalized));
      continue;
    }

    normalized['options'] = options;
    normalized['correct'] = matchedKey;
    validQuestions.add(normalized);
  }

  return (
    validQuestions: validQuestions,
    invalidLabels: invalidLabels,
  );
}

/// Validates theory/subjective questions: normalizes `answer` → `modelAnswer`
/// and requires the model answer to be at least 10 characters.
QuestionValidationResult validateWrittenQuestions(
  List<Map<String, dynamic>> questions,
) {
  final validQuestions = <Map<String, dynamic>>[];
  final invalidLabels = <String>[];

  for (final question in questions) {
    final normalized = normalizeWrittenQuestion(question);
    final answer = normalized['modelAnswer']?.toString().trim();
    if (answer == null || answer.length < 10) {
      invalidLabels.add(questionLabel(normalized));
      continue;
    }

    normalized['modelAnswer'] = answer;
    if (normalized.containsKey('answer')) {
      normalized['answer'] = answer;
    }
    validQuestions.add(normalized);
  }

  return (
    validQuestions: validQuestions,
    invalidLabels: invalidLabels,
  );
}

/// Parses a combined AI result (`{"mcq"|"mcqs", "theory", "subjective"}`) —
/// the `lessonQuestions` / `examQuestions` contract — into the exam-content
/// shape `{mcqs, theory, subjective}`, running the shared validators and
/// dropping invalid items.
Map<String, List<Map<String, dynamic>>> parseLessonQuestions(
  Map<String, dynamic> raw,
) {
  List<Map<String, dynamic>> cast(dynamic list) =>
      (list as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

  final mcqList = cast(raw['mcq'] ?? raw['mcqs']);
  final theoryList = cast(raw['theory']);
  final subjectiveList = cast(raw['subjective']);

  return {
    'mcqs': validateMcqs(mcqList).validQuestions,
    'theory': validateWrittenQuestions(theoryList).validQuestions,
    'subjective': validateWrittenQuestions(subjectiveList).validQuestions,
  };
}
