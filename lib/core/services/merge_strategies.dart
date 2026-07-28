import 'merge_engine.dart';

const lessonMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounterThenUpdatedAt,
  'content': MergeStrategy.lwwByUpdateCounterThenUpdatedAt,
  'objectives': MergeStrategy.union,
  'materials': MergeStrategy.union,
};

const examMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounterThenUpdatedAt,
  'questions': MergeStrategy.union,
  'theoryQuestions': MergeStrategy.union,
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
