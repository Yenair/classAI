import 'merge_engine.dart';

const lessonMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounter,
  'content': MergeStrategy.lwwByUpdateCounter,
  'objectives': MergeStrategy.union,
  'materials': MergeStrategy.union,
  'assessment': MergeStrategy.lwwByUpdateCounter,
  'homework': MergeStrategy.lwwByUpdateCounter,
};

const examMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounter,
  'questions': MergeStrategy.union,
  'theoryQuestions': MergeStrategy.union,
  'markingScheme': MergeStrategy.lwwByUpdateCounter,
};

Map<String, MergeStrategy> mergeStrategiesForTable(String tableName) {
  switch (tableName) {
    case 'lessons':
      return lessonMergeStrategies;
    case 'exams':
      return examMergeStrategies;
    default:
      return const {};
  }
}
