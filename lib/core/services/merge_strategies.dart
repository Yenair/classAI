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

const schemeOfWorkMergeStrategies = {
  'topic': MergeStrategy.keepRemote,
  'adminEditedTopic': MergeStrategy.keepRemote,
  'objectives': MergeStrategy.lwwByUpdateCounter,
  'status': MergeStrategy.keepRemote,
  'adminComment': MergeStrategy.keepRemote,
};

Map<String, MergeStrategy> mergeStrategiesForTable(String tableName) {
  switch (tableName) {
    case 'lessons':
      return lessonMergeStrategies;
    case 'exams':
      return examMergeStrategies;
    case 'scheme_of_work':
      return schemeOfWorkMergeStrategies;
    default:
      return const {};
  }
}
