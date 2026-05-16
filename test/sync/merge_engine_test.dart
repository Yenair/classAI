import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/merge_strategies.dart';

void main() {
  group('MergeEngine', () {
    test('merges by field strategy using base hashes', () {
      final engine = MergeEngine();

      final result = engine.merge(
        local: {
          'title': 'Local title',
          'objectives': ['A', 'B'],
          'updateCounter': 2,
        },
        remote: {
          'title': 'Remote title',
          'objectives': ['B', 'C'],
          'updateCounter': 3,
        },
        base: {
          'title': 'Base title',
          'objectives': ['A'],
          'updateCounter': 1,
        },
        tableName: 'lessons',
        fieldStrategies: lessonMergeStrategies,
      );

      expect(result.merged['title'], 'Remote title');
      expect(result.merged['objectives'], ['A', 'B', 'C']);
      expect(result.resolution, MergeResolution.merged);
      expect(result.conflictingFields, isEmpty);
    });

    test('records conflicts when both sides change the same field', () {
      final engine = MergeEngine();

      final result = engine.merge(
        local: {
          'markingScheme': 'Local scheme',
          'updateCounter': 1,
        },
        remote: {
          'markingScheme': 'Remote scheme',
          'updateCounter': 1,
        },
        base: {
          'markingScheme': 'Base scheme',
          'updateCounter': 0,
        },
        tableName: 'exams',
        fieldStrategies: examMergeStrategies,
      );

      expect(result.merged['markingScheme'], 'Remote scheme');
      expect(result.conflictingFields, contains('markingScheme'));
      expect(result.resolution, MergeResolution.unresolved);
    });

    test('treats missing base as first sync and prefers remote', () {
      final engine = MergeEngine();

      final result = engine.merge(
        local: {
          'title': 'Local title',
          'content': 'Local body',
        },
        remote: {
          'title': 'Remote title',
          'content': 'Remote body',
        },
        base: null,
        tableName: 'lessons',
        fieldStrategies: lessonMergeStrategies,
      );

      expect(result.merged['title'], 'Remote title');
      expect(result.conflictingFields, containsAll(['title', 'content']));
      expect(result.resolution, MergeResolution.remote);
    });
  });
}
