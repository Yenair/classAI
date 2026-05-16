```markdown
### Step 4.3: Per-Table Merge Strategies

Define in `lib/core/services/merge_strategies.dart`:

```dart
const lessonMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounter,
  'content': MergeStrategy.lwwByUpdateCounter, // losing version saved to conflicts
  'objectives': MergeStrategy.union,           // JSON arrays unioned
  'materials': MergeStrategy.union,
  'assessment': MergeStrategy.lwwByUpdateCounter,
  'homework': MergeStrategy.lwwByUpdateCounter,
};

const examMergeStrategies = {
  'title': MergeStrategy.lwwByUpdateCounter,
  'questions': MergeStrategy.union,            // MCQs unioned
  'theoryQuestions': MergeStrategy.union,
  'markingScheme': MergeStrategy.lwwByUpdateCounter,
};
```

### Step 4.4: Sync Test File

`test/sync/sync_service_test.dart` — uses a mock HTTP client:

```dart
void main() {
  group('Sync flow', () {
    test('pull first, then merge, then push', () { /* ... */ });
    test('three-way merge with base hash', () { /* ... */ });
    test('three-way merge without base hash (first sync)', () { /* ... */ });
    test('topological sort: schools before subjects before lessons', () { /* ... */ });
    test('conflict detected when both local and remote change same field', () { /* ... */ });
    test('emergency queue preserved on force logout', () { /* ... */ });
    test('realtime deduplication by event_id, not timestamp', () { /* ... */ });
  });
}
```

## Phase 4 Acceptance Criteria (GATE)

```bash
flutter test test/sync/sync_service_test.dart           # All sync tests pass
flutter test test/sync/merge_engine_test.dart           # Merge logic correct for all table strategies
flutter test test/sync/conflict_detection_test.dart     # Conflicts saved, resolvable
flutter test test/sync/emergency_queue_test.dart        # Emergency queue survives logout
```
```