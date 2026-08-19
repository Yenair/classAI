class PromptTemplates {
  /// Curated list of real, widely used NERDC-aligned Nigerian textbook
  /// titles. These are safe to reference — no fabricated page numbers,
  /// chapter numbers, or invented authors.
  static const List<String> curatedTextbookTitles = [
    'New General Mathematics for Junior Secondary Schools',
    'Basic Science and Technology for Junior Secondary Schools',
    'English Studies for Junior Secondary Schools',
    'Basic Technology for Junior Secondary Schools',
    'Agricultural Science for Junior Secondary Schools',
    'Civic Education for Junior Secondary Schools',
    'Social Studies for Junior Secondary Schools',
    'Christian Religious Studies for Junior Secondary Schools',
    'Home Economics for Junior Secondary Schools',
    'Physical and Health Education for Junior Secondary Schools',
    'New General Mathematics for Senior Secondary Schools',
    'Further Mathematics for Senior Secondary Schools',
    'Comprehensive Physical and Health Education for Senior Secondary Schools',
    'Computer Studies for Senior Secondary Schools',
  ];

  static const String _selfCheckInstruction =
      'After generating the questions, double-check each answer. If any answer is likely incorrect, replace it with a correct one. Do not output questions you are unsure about - omit them and reduce the count accordingly. Return only valid JSON.';

  static String lessonNote(String subject, String curriculum, String classLevel,
      int week, String topic, String difficulty, String bloomsVerbs,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'You are a professional educator designing a lesson note for $subject '
        '($curriculum curriculum), $classLevel, Week $week, Topic: "$topic". '
        'Difficulty: $difficulty. Target cognitive levels: $bloomsVerbs. '
        'Use the following clear section headings in the output:\n'
        '## Learning Objectives\n'
        '## Key Vocabulary\n'
        '## Materials\n'
        '## Lesson Presentation\n'
        '## Assessment\n'
        '## Homework\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        'Return ONLY valid JSON: '
        '{"objectives":[...],"vocabulary":[...],"materials":[...],"presentation":{...},"assessment":"...","homework":"...","diagrams":[{"description":"..."}],"references":[{"title":"...","author":"...","chapter":"...","page":"..."}],"attribution":"$attribution"} '
        'Include between 1 and 3 diagram descriptions in the "diagrams" array. '
        'Use 1 prompt for simple topics, 2 for moderately complex topics, and 3 for complex topics. '
        'Each description should be a concise prompt for generating a single educational image relevant to the topic. '
        'For the "references" array: do NOT invent textbook titles, chapter numbers, or page numbers. '
        'Do NOT include author names unless you are certain they are correct. '
        'Only return references from this curated list of real Nigerian textbooks: '
        '${curatedTextbookTitles.join('; ')}. '
        'Return a reference object {"title":"..."} only when a curated title is relevant to the topic. '
        'Do NOT add chapter, page, or author fields — leave them out. '
        'Return "references": [] when none of the curated titles are relevant. '
        '$_selfCheckInstruction';
  }

  /// Generate only the source references for an existing lesson.
  static String referencesOnly(
      String subject, String classLevel, int week, String topic,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate source references for $subject, $classLevel, Week $week, '
        'Topic: "$topic". Return only references relevant to this lesson. '
        'Do NOT change or generate lesson objectives, vocabulary, materials, '
        'presentation, assessment, homework, or diagrams. '
        'Only return references from this curated list of real Nigerian textbooks: '
        '${curatedTextbookTitles.join('; ')}. '
        'Do NOT invent textbook titles, chapter numbers, page numbers, or authors. '
        'Return a reference object {"title":"..."} only when a curated title '
        'is relevant to the topic. Return "references": [] when none apply. '
        'Return ONLY valid JSON: '
        '{"references":[{"title":"..."}],"attribution":"$attribution"}';
  }

  /// Generate a combined exam prompt that supports MCQ, Theory, and Subjective.
  /// [typeCounts] maps question type names ("MCQ", "Theory", "Subjective") to their counts.
  static String examQuestions(
      String subject, String classLevel, String topic, String difficulty,
      Map<String, int> typeCounts,
      {String teacherName = 'Teacher',
      String schoolName = 'School',
      String bloomsVerbs = ''}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';

    // Build dynamic description of requested types
    final parts = <String>[];
    for (final entry in typeCounts.entries) {
      if (entry.value > 0) {
        parts.add('${entry.value} ${entry.key} questions');
      }
    }
    final typeDescription = parts.isEmpty ? '10 MCQs' : parts.join(', ');

    final jsonStructure = <String>[];
    if ((typeCounts['MCQ'] ?? 0) > 0) {
      jsonStructure.add(
          '"mcq":[{"question":"...","options":{"A":"...","B":"...","C":"...","D":"..."},"correct":"A"}]');
    }
    if ((typeCounts['Theory'] ?? 0) > 0) {
      jsonStructure.add(
          '"theory":[{"question":"...","modelAnswer":"...","cognitiveLevel":"..."}]');
    }
    if ((typeCounts['Subjective'] ?? 0) > 0) {
      jsonStructure.add(
          '"subjective":[{"question":"...","answer":"...","rubric":"..."}]');
    }

    final cognitive = bloomsVerbs.trim().isEmpty
        ? ''
        : ' Target cognitive levels: $bloomsVerbs.';
    return 'Generate $typeDescription for $subject, $classLevel, "$topic". '
        'Difficulty: $difficulty.$cognitive '
        'Use the following clear section headings in the output:\n'
        '## MCQ Questions\n'
        '## Theory Questions\n'
        '## Subjective Questions\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        'Return ONLY valid JSON: '
        '{$jsonStructure,"attribution":"$attribution"} '
        '$_selfCheckInstruction';
  }

  /// Generates the structured assessment questions embedded in a lesson
  /// (Phase 2). Delegates to [examQuestions] with the lesson's Bloom's
  /// levels injected, so there is exactly one combined-question prompt
  /// contract. Returns `{"mcq":[...],"theory":[...],"subjective":[...],
  /// "attribution":...}`.
  static String lessonQuestions(
      String subject, String classLevel, String topic, String difficulty,
      String bloomsVerbs, Map<String, int> typeCounts,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    return examQuestions(
      subject,
      classLevel,
      topic,
      difficulty,
      typeCounts,
      teacherName: teacherName,
      schoolName: schoolName,
      bloomsVerbs: bloomsVerbs,
    );
  }

  static String mcqs(
      String subject, String classLevel, String topic, String difficulty,
      {int count = 10,
      String teacherName = 'Teacher',
      String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate $count MCQs for $subject, $classLevel, "$topic". Difficulty: $difficulty. '
        'Use the following clear section heading in the output:\n'
        '## MCQ Questions\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        '4 options each (A-D). Return ONLY valid JSON: '
        '{"questions":[{"question":"...","options":{"A":"...","B":"...","C":"...","D":"..."},"correct":"A"}],"attribution":"$attribution"} '
        '$_selfCheckInstruction';
  }

  static String theoryQuestions(String subject, String classLevel, String topic,
      {int count = 5,
      String teacherName = 'Teacher',
      String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate $count theory questions for $subject, $classLevel, "$topic". '
        'Use the following clear section heading in the output:\n'
        '## Theory Questions\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        'Include model answer and cognitive level. Return ONLY valid JSON: '
        '{"questions":[{"question":"...","modelAnswer":"...","cognitiveLevel":"..."}],"attribution":"$attribution"} '
        '$_selfCheckInstruction';
  }

  static String subjectiveQuestions(
      String subject, String classLevel, String topic,
      {int count = 5,
      String teacherName = 'Teacher',
      String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate $count subjective questions for $subject, $classLevel, "$topic". '
        'Use the following clear section heading in the output:\n'
        '## Subjective Questions\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        'Include a correct answer and marking rubric. Return ONLY valid JSON: '
        '{"questions":[{"question":"...","answer":"...","rubric":"..."}],"attribution":"$attribution"} '
        '$_selfCheckInstruction';
  }

  /// Appended to a generation prompt when saved lesson questions are already
  /// part of the exam (Phase 3 hybrid) so the AI does not regenerate them.
  /// Returns '' when [questionTexts] is empty so callers can concatenate
  /// unconditionally.
  static String doNotRepeatInstruction(
      String type, List<String> questionTexts) {
    if (questionTexts.isEmpty) return '';
    final list = questionTexts.map((q) => '- $q').join('\n');
    return '\n\nThe following $type questions are ALREADY included in this '
        'exam from saved lesson notes — do NOT repeat or rephrase any of '
        'them:\n$list';
  }

  /// Generate a Scheme of Work for a NERDC subject across a full term.
  static String schemeOfWork(String subject, String classLevel, String term,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'You are a curriculum planner for the Nigerian Educational Research and Development Council (NERDC). '
        'Generate a complete Scheme of Work for $subject, $classLevel, $term Term. '
        'Create exactly 13 weeks of content, each with a clear topic and 2-3 specific learning objectives. '
        'Follow the official NERDC curriculum for Nigerian secondary schools. '
        'Each week should build logically on the previous weeks. '
        'Use the following clear section heading in the output:\n'
        '## Scheme of Work\n'
        'Do NOT include any introductory or concluding text. Return ONLY the structured content with the headings above. '
        'Return ONLY valid JSON: '
        '{"weeks":[{"week":1,"topic":"...","objectives":["...","..."]},{"week":2,"topic":"...","objectives":["...","..."]},...],"attribution":"$attribution"}';
  }
}
