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
    'New Oxford Secondary English Course for Junior Secondary Schools '
        '(Upper Basic Education)',
    'Oxford Advanced Learner\'s Dictionary, International Student\'s Edition',
    'Excellence in Basic Science and Technology Book 1–3',
    'WABP Basic Technology for Junior Secondary Schools 1–3',
    'New Computer Studies for Junior Secondary Schools 1–3',
    'Spectrum Social Studies for Junior Secondary Schools '
        '(Upper Basic Education)',
    'The Basic Concepts of Civic Education for Upper Levels, Junior '
        'Secondary Schools',
  ];

  static const String _curatedTextbookCatalog =
      'New General Mathematics for Junior Secondary Schools — authors M. F. '
      'Macrae, A. O. Kalejaiye, Z. I. Chima, G. U. Garba, and M. O. Ademosu; '
      'publisher Pearson Education Limited; 2013 NERDC curriculum edition. '
      'New Oxford Secondary English Course for Junior Secondary Schools '
      '(Upper Basic Education) — author Ayo Banjo et al.; publisher University '
      'Press PLC; 2014 UBE edition. Oxford Advanced Learner\'s Dictionary, '
      'International Student\'s Edition — author A. S. Hornby; publisher Oxford '
      'University Press; 8th edition, 2014. Excellence in Basic Science and '
      'Technology Book 1–3 — authors M. O. Olaitan, A. H. Iyabo, and '
      'S. Olatunde; publisher Cambridge University Press. WABP Basic '
      'Technology for Junior Secondary Schools 1–3 — authors M. B. Adeyemi, '
      'M. Ukadiko, and S. Danladi; publisher Melrose Publication. New '
      'Computer Studies for Junior Secondary Schools 1–3 — authors J. O. E. '
      'Otuka, A. F. Akande, and S. L. Iginla. Home Economics for Junior '
      'Secondary Schools — author E. U. Anyakola; publisher Africana First '
      'Publishers. Spectrum Social Studies for Junior Secondary Schools '
      '(Upper Basic Education) — authors Dayo Ogunniyi, G. I. Ehon, Abbas '
      'Mohammed, and Nwakaego U. Ogbajie; publisher Spectrum Books Limited. '
      'The Basic Concepts of Civic Education for Upper Levels, Junior '
      'Secondary Schools — author Oladele Odanye; publisher Holad Publishers.';

  static String _referenceInstructions() {
    return 'Use only the verified catalog records below. $_curatedTextbookCatalog '
        'First identify the distinct curriculum subtopics directly related to '
        'the lesson topic, then return every catalog record that genuinely '
        'supports one of those subtopics. Do not return unrelated books. For '
        'each returned record, include the exact title, author or authors, '
        'publisher, edition or year when known, ISBN only when known for that '
        'exact edition, a relatedTopics array, and a searchQuery containing '
        'the title plus the strongest author/publisher identifier. Never '
        'invent an author, publisher, edition, ISBN, chapter, page, or URL. '
        'If a field is not verified, omit it. Return an empty array when no '
        'catalog record is relevant. Return only valid JSON.';
  }

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
        '{"objectives":[...],"vocabulary":[...],"materials":[...],"presentation":{...},"assessment":"...","homework":"...","diagrams":[{"description":"..."}],"references":[{"title":"...","author":"...","publisher":"...","edition":"...","isbn":"...","relatedTopics":["..."],"searchQuery":"..."}],"attribution":"$attribution"} '
        'Include between 1 and 3 diagram descriptions in the "diagrams" array. '
        'Use 1 prompt for simple topics, 2 for moderately complex topics, and 3 for complex topics. '
        'Each description should be a concise prompt for generating a single educational image relevant to the topic. '
        '${_referenceInstructions()} '
        ''
        'The verified catalog instructions override any earlier generic '
        'reference wording; include verified author and publisher fields. '
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
        '${_referenceInstructions()} '
        'Return ONLY valid JSON: '
        '{"references":[{"title":"...","author":"...","publisher":"...","edition":"...","isbn":"...","relatedTopics":["..."],"searchQuery":"..."}],"attribution":"$attribution"}';
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
