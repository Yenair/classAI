# Feasibility Report: Standard In-Session Typing Undo (Ctrl+Z) for Lesson & Exam Editors

**Date:** 2026-07-28
**Status:** Research-only (no implementation)

---

## 1. Flutter SDK Version Check

The project's [`pubspec.yaml`](pubspec.yaml:7) specifies:

```yaml
environment:
  sdk: '>=3.4.0 <4.0.0'
```

Flutter's built-in [`UndoHistoryController`](https://api.flutter.dev/flutter/widgets/UndoHistoryController-class.html) was introduced in **Flutter 3.13** (stable channel, September 2023). Since the project requires `>=3.4.0`, **the SDK fully supports `UndoHistoryController` with no upgrade needed**.

---

## 2. How Text Input Is Currently Implemented

Both editors use **only plain `TextField` / `TextFormField` widgets**. No rich-text editors (FlutterQuill, SuperEditor, Zefyr, etc.) are used anywhere. This is important because `UndoHistoryController` integrates directly with Flutter's built-in text fields.

### Text Input Patterns Found

There are **two patterns** for managing text input state:

| Pattern | Mechanism | Example | Undo Support |
|---------|-----------|---------|-------------|
| **Controller-based** | `TextEditingController` passed to widget's `controller` param | Topic, Review fields | ✅ Easy — just attach `undoController` |
| **initialValue-based** | `initialValue` string + `onChanged` callback that updates a parent `String` state variable | Preview section fields, MCQ options, Theory answers | ⚠️ Needs conversion to `TextEditingController` |

---

## 3. Every Text-Editableditable Field — Complete Inventory

### Lesson Editor (`lesson_editor_screen.dart`)

| # | Field | Widget | Controller/Value | File & Line | Expected Ctrl+Z? |
|---|-------|--------|-----------------|-------------|-----------------|
| 1 | **Topic** | `_StyledTextField` → `TextField` | `TextEditingController` (`_topicController`) | [lesson_editor_screen.dart:54](lib/features/lesson/screens/lesson_editor_screen.dart:54) | ✅ Yes |
| 2 | **Objectives** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_objectivesText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 3 | **Vocabulary** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_vocabularyText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 4 | **Materials** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_materialsText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 5 | **Presentation** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_presentationText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 6 | **Assessment** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_assessmentText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 7 | **Homework** | `_buildPreviewCard` → `TextFormField` | `initialValue` + `onChanged` → `_homeworkText` | [lesson_editor_screen.dart:3404](lib/features/lesson/screens/lesson_editor_screen.dart:3404) | ✅ Yes |
| 8 | **Review/Feedback** | `TextField` | `TextEditingController` (`_reviewController`) | [lesson_editor_screen.dart:71](lib/features/lesson/screens/lesson_editor_screen.dart:71) | ✅ Yes |
| 9 | **Subject** (config) | `DropdownButtonFormField` | Dropdown, not free-text | [lesson_editor_screen.dart:2376](lib/features/lesson/screens/lesson_editor_screen.dart:2376) | ❌ N/A |
| 10 | **Class** (config) | `DropdownButtonFormField` | Dropdown, not free-text | — | ❌ N/A |
| 11 | **Week** (config) | `_WeekControl` (custom +/- widget) | Numeric increment/decrement | — | ❌ N/A |

**Note on `_buildPreviewCard`:** The same widget at [line 3374](lib/features/lesson/screens/lesson_editor_screen.dart:3374) is reused for all 6 preview sections (objectives, vocabulary, materials, presentation, assessment, homework). Each passes different `content` (the `initialValue`) and a different `onChanged` callback. Because they all use `initialValue` instead of a controller, each would need its own `TextEditingController` to support undo.

### Exam Editor (`exam_editor_screen.dart`)

| # | Field | Widget | Controller/Value | File & Line | Expected Ctrl+Z? |
|---|-------|--------|-----------------|-------------|-----------------|
| 1 | **Topic** | `TextFormField` | `TextEditingController` (`_topicController`) | [exam_editor_screen.dart:47](lib/features/exam/screens/exam_editor_screen.dart:47) | ✅ Yes |
| 2 | **Question Count** (config) | `TextFormField` | `initialValue` + `onChanged` | [exam_editor_screen.dart:2343](lib/features/exam/screens/exam_editor_screen.dart:2343) | 🟡 Low priority (numeric, single line) |
| 3 | **MCQ Question text** | `TextFormField` | `initialValue` + `onChanged` → `_updateMcq()` | [exam_editor_screen.dart:3269](lib/features/exam/screens/exam_editor_screen.dart:3269) | ✅ Yes |
| 4 | **MCQ Option A/B/C/D** | `TextFormField` | `initialValue` + `onChanged` → `_updateMcqOption()` | [exam_editor_screen.dart:3330](lib/features/exam/screens/exam_editor_screen.dart:3330) | ✅ Yes |
| 5 | **Theory Question** | `TextFormField` | `initialValue` + `onChanged` → `_updateTheory()` | [exam_editor_screen.dart:3411](lib/features/exam/screens/exam_editor_screen.dart:3411) | ✅ Yes |
| 6 | **Theory Model Answer** | `TextFormField` | `initialValue` + `onChanged` → `_updateTheory()` | [exam_editor_screen.dart:3433](lib/features/exam/screens/exam_editor_screen.dart:3433) | ✅ Yes |
| 7 | **Review/Feedback** | `TextField` | `TextEditingController` (`_reviewController`) | [exam_editor_screen.dart:48](lib/features/exam/screens/exam_editor_screen.dart:48) | ✅ Yes |
| 8 | **Difficulty** (config) | `DropdownButtonFormField` | Dropdown | [exam_editor_screen.dart:2516](lib/features/exam/screens/exam_editor_screen.dart:2516) | ❌ N/A |
| 9 | **Subject/Class** (config) | `DropdownButtonFormField` | Dropdown | — | ❌ N/A |
| 10 | **Question type checkboxes** | Checkboxes | Boolean selection | — | ❌ N/A |

**Dynamic nature:** MCQ options (4 per question) × N questions means the number of editable fields varies. Theory questions similarly scale with N questions. Each dynamically-created field uses `initialValue`.

---

## 4. Existing Keyboard Shortcut Handling

**Neither editor has any keyboard shortcut handling.** I searched both files for:
- `Shortcuts` / `Actions` widgets
- `RawKeyboardListener`
- `KeyboardListener`
- `CallbackShortcuts`
- `OnKey` / `KeyEvent`
- `HardwareKeyboard` / `LogicalKeyboardKey` / `PhysicalKeyboardKey`

**Results: 0 matches in both files.**

This means:
- There is **zero risk of conflict** with existing shortcut handlers
- There is **no existing pattern** to follow or extend — a new undo implementation would be the first shortcut handling in either editor
- Global app-level shortcuts (e.g., from the router or a parent widget) would need to be checked, but nothing in the editor screens themselves handles shortcuts

---

## 5. Feasibility Assessment

### Approach: Flutter's Built-in `UndoHistoryController`

Flutter provides [`UndoHistoryController`](https://api.flutter.dev/flutter/widgets/UndoHistoryController-class.html) which works with any `TextField` or `TextFormField` via the [`undoController`](https://api.flutter.dev/flutter/material/TextField/undoController.html) property (introduced in Flutter 3.13). When set, the field automatically handles Ctrl+Z (undo) and Ctrl+Shift+Z / Ctrl+Y (redo) without any additional keyboard listener code.

### Required Changes Summary

| Change Type | Count (Lesson) | Count (Exam) | Effort |
|-------------|---------------|--------------|--------|
| **No change needed** (already uses controller) | 2 fields (topic, review) | 2 fields (topic, review) | None |
| **Convert `initialValue` → `TextEditingController`** | 6 preview fields | 3+ MCQ fields + 2 theory fields + 1 count field | Medium — per-field conversion |
| **Add `undoController` to each `TextField`/`TextFormField`** | All editable fields | All editable fields | Low — one property per field |
| **Dispose undo controllers** | In `dispose()` | In `dispose()` | Low — 2-3 lines per screen |

### Considerations

1. **`_buildPreviewCard` in lesson editor** (line 3374): This single widget is reused for all 6 preview sections. Currently it accepts `String content` (for `initialValue`) and `ValueChanged<String> onChanged`. To support undo, it would need to accept `TextEditingController` instead/as well. This is a clean refactor since the pattern already exists (topic/review use controllers).

2. **Exam editor dynamic fields** (MCQs, theory): Each `TextFormField` in `_buildMcqCard` and `_buildTheoryCard` uses `initialValue`. These would need individual `TextEditingController` instances — one per question/option. Given N questions × 4 options + 2 theory fields, this could add 6N controllers. These would need to be created when questions are generated and disposed when regenerated or the screen is disposed.

3. **No new dependencies required**: `UndoHistoryController` is part of the Flutter framework. No pub.dev packages needed.

4. **State management impact**: The `initialValue` → controller conversion doesn't change the state flow — `onChanged` callbacks still update the parent `State`'s `_objectivesText`, `_mcqs` list, etc. The controller simply becomes an additional intermediary between the widget and the callback.

### Recommendation

**Feasible with moderate effort.** The main work is mechanical (converting `initialValue` fields to `TextEditingController` fields) and well-scoped. No architectural changes, no new dependencies, no risk of shortcut conflicts. The SDK already supports it.

### Implementation Order (if/when implementing)

1. Create a single shared `UndoHistoryController` instance for each editor screen
2. Convert `_buildPreviewCard` in lesson editor to accept `TextEditingController` instead of `initialValue`
3. Convert MCQ/theory card builders in exam editor similarly
4. Pass `undoController:` to every `TextField`/`TextFormField`
5. Dispose the `UndoHistoryController` in `dispose()`

### Alternative Considered

**Manual `Shortcuts` + `Actions` widget approach**: Roll a custom undo stack. This is NOT recommended — it would duplicate existing framework functionality, require custom keystroke capture, and introduce edge cases with cursor position restoration.
