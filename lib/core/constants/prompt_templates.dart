class PromptTemplates {
  static String lessonNote(String subject, String curriculum, String classLevel,
      int week, String topic, String difficulty, String bloomsVerbs,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'You are a professional educator designing a lesson note for $subject '
        '($curriculum curriculum), $classLevel, Week $week, Topic: "$topic". '
        'Difficulty: $difficulty. Target cognitive levels: $bloomsVerbs. '
        'Include: Learning Objectives, Key Vocabulary, Materials, Lesson Presentation, '
        'Assessment, Homework. $attribution. '
        'Return ONLY valid JSON: '
        '{"objectives":[...],"vocabulary":[...],"materials":[...],"presentation":{...},"assessment":"...","homework":"..."}';
  }

  static String mcqs(
      String subject, String classLevel, String topic, String difficulty,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate 10 MCQs for $subject, $classLevel, "$topic". Difficulty: $difficulty. '
        '$attribution. '
        '4 options each (A-D). Return ONLY valid JSON: '
        '{"questions":[{"question":"...","options":{"A":"...","B":"...","C":"...","D":"..."},"correct":"A"}]}';
  }

  static String theoryQuestions(String subject, String classLevel, String topic,
      {String teacherName = 'Teacher', String schoolName = 'School'}) {
    final attribution =
        '— Generated for $teacherName, $schoolName. Not for redistribution.';
    return 'Generate 5 theory questions for $subject, $classLevel, "$topic". '
        '$attribution. '
        'Include model answer and cognitive level. Return ONLY valid JSON: '
        '{"questions":[{"question":"...","modelAnswer":"...","cognitiveLevel":"..."}]}';
  }
}
