# Lesson Editor UI Match Plan

## Purpose

This file is a plan only.

No app code is changed by this file.
No test code is changed by this file.
No database table, provider logic, or auth flow is changed by this plan.

The goal is to make the Flutter Lesson Editor look and work like the screens in the stitch_design_LessonEditor folder.

The goal is also to make every visible button work.

The Generate Lesson Content page is an optional first tab.
It appears only for draft lessons that have not been generated.
It is not scrollable.
The Generate tab has no FAB.
The final FAB decision is recorded in the Open logic points section below.

## Confirmed design rules

The reference folder has four related screens.
The updated plan uses them as one flow with these rules:

- lesson_editor_lesson_notes_card uses a left sidebar, a top header, one large lesson card, side arrows, and a bottom action bar.
- lesson_editor_assessment_card uses the same left sidebar and card shell, but it shows an assessment question with answer buttons.
- lesson_editor_diagrams_card uses the sidebar and card shell, but it shows tabs, an unlocked banner, suggested images, and image buttons.
- lesson_editor_card_deck_view uses a top header and full-page deck slides. It also shows the Generate Lesson Content first slide, page dots, and the round add FAB with action buttons.

The current app has a sidebar and a bottom action area.
The bottom action area will be replaced by the FAB action structure on the lesson tabs.
The Generate tab will not show the FAB.

The dark ClassAI shell from the lesson notes, assessment, and diagrams screens remains the main shell.
The deck behavior from the card deck screen remains the navigation model.
The existing lesson data and callbacks remain behind the new visual layer.

## Reference files checked

| Reference | What it shows |
| --- | --- |
| stitch_design_LessonEditor/academic_focus/DESIGN.md | Colors, text sizes, spacing, card shapes, and touch target rules |
| lesson_editor_lesson_notes_card/screen.png | Lesson Note card and side navigation |
| lesson_editor_lesson_notes_card/code.html | Lesson Note structure and button names |
| lesson_editor_assessment_card/screen.png | Assessment card and selected answer state |
| lesson_editor_assessment_card/code.html | Assessment button structure |
| lesson_editor_diagrams_card/screen.png | Diagrams tab and Suggested Images section |
| lesson_editor_diagrams_card/code.html | Diagrams controls and footer buttons |
| lesson_editor_card_deck_view/screen.png | Generate slide, page dots, and FAB |
| lesson_editor_card_deck_view/code.html | Deck slide order and FAB action list |

## Current Flutter code checked

| File | Current area | Plan use |
| --- | --- | --- |
| lib/features/lesson/screens/lesson_editor_screen.dart | LessonEditorScreen and _LessonEditorScreenState | Keep the existing lesson state and callbacks |
| Same file | _buildEntryScreenSkeleton | Restyle and move this content into slide 1 |
| Same file | _NavigationDrawer | Restyle to match the reference sidebar |
| Same file | _ToolHeader and _MobileHeader | Use one responsive header pattern |
| Same file | _PreviewColumn | Render the lesson, assessment, and diagrams slides |
| Same file | _FloatingActionArea | Replace or adapt to the reference FAB and action menu |
| Same file | _BottomNavBar | Keep only where it is needed on small screens |
| test/features/lesson_editor_test.dart | Existing generation, preview, tab, and action tests | Update finders and add interaction tests |

## Main result after implementation

The user will see a focused lesson deck.

The normal generated lesson tab order will be:

1. Lesson Notes
2. Assessment
3. Suggested Diagrams
4. References

References is still controlled by the existing visibility setting.
When References is hidden, the visible content tabs are Lesson Notes, Assessment, and Suggested Diagrams.

For a draft lesson only, the non-scrollable Generate Lesson Content tab is inserted before Lesson Notes.
It is an optional first tab.
It disappears after the lesson is generated.

The bottom Regenerate, Mark Completed, Export PDF, and Visible Sections row will not be used on the other tabs.
Those actions will use the expanded FAB structure instead.

The Generate tab will show Create with AI instead of Regenerate Deck.
The Generate tab will include a Create new topic option at the bottom of the topic dropdown.
Tapping Create new topic will use the existing Lessons route and go to the lessons list screen.

The page counter and dots will show the current slide.
The left and right arrows will move between slides.
The same movement will work with the keyboard arrows when a text field is not focused.

## Detailed implementation plan

### 1. Keep the business logic in place

The visual work must not change these areas:

- authentication and route guards;
- database tables or migrations;
- existing lesson provider logic;
- generation prompts and response parsing;
- lesson save and sync behavior;
- unlock rules and subscription checks;
- existing undo snapshot behavior;
- existing PDF export behavior.

The change will be at the widget layout and interaction layer.

Existing methods such as _handleGenerate, _handleRegenerate, _saveLesson, _handleMarkCompleted, _handleExportPdf, _showVisibleSectionsSheet, and _generateSuggestedImage will remain the action owners.

### 2. Add design tokens for the reference screen

Use the values in academic_focus/DESIGN.md through the existing theme where possible.

The visual plan is:

- page background: #131315;
- main card surface: about #1E1E22;
- lower surface layers: #1B1B1D, #2A2A2C, and #353437;
- main text: #E5E1E4;
- muted text: #C5C5D3;
- border: #454652;
- primary blue: #B8C3FF;
- primary button fill: #8FA3FF;
- active sidebar purple: the existing secondary color;
- Work Sans, with the existing Flutter text theme mapped to the design sizes.

Do not add a font package.
Use the current project font setup and map the existing text theme to the design sizes.

All buttons, chips, arrows, and text fields will have at least a 48 by 48 logical pixel hit area.

### 3. Build one responsive page shell

The screen shell will have these layers:

~~~text
Scaffold
└── Row
    ├── Reference sidebar on tablet and desktop
    └── Expanded main area
        ├── Top header
        ├── Deck viewport
        ├── Page dots / slide indicator
        └── FAB and expanded action menu on lesson tabs
~~~

Desktop and tablet:

- show the left sidebar;
- show the Lesson Editor title in the top header;
- show Back, Undo, and Redo in the header;
- show large side arrows around the active card;
- keep the FAB and its menu clear of the card;
- keep the deck card inside the content max width.

Small screens:

- hide the large sidebar;
- show a compact header with Back, Undo, and Redo;
- show arrows inside the card or as large edge hit areas;
- allow the card content to scroll vertically;
- keep the FAB above the safe area and above the bottom navigation on lesson tabs;
- do not show the FAB on the Generate tab;
- use the expanded FAB menu so action buttons do not clip.

The card must not overflow horizontally.
The FAB menu must not cover the main text or the tab controls.

### 4. Turn the current content into deck slides

The current parent uses a SingleChildScrollView and then places the generated preview below the form.
The planned layout will keep the existing parent and helper structure, but it will place the current content helpers inside a bounded deck viewport.

The deck viewport must have a bounded height from the available screen height.
The inner content may scroll vertically inside its card.
The Generate tab itself must not be scrollable.

The tab list will be built from the current lesson state:

- draft lesson: Generate Lesson Content, Lesson Notes, Assessment, Suggested Diagrams, and References when visible;
- generated lesson: Lesson Notes, Assessment, Suggested Diagrams, and References when visible.

The Generate tab is not a numbered content card.
It is a temporary draft-only first tab.

The numbered content cards always start at Lesson Notes:

- Lesson Notes is card 1;
- Assessment is card 2;
- Suggested Diagrams is card 3;
- References is card 4 when it is visible.

The Generate tab has no card number.

The controller will have a stable slide list.
The slide list will include the Generate slide even before content is generated.

The first slide will contain:

- the auto_awesome visual at the top;
- the heading Generate Lesson Content;
- the supporting text from the design;
- the floating label LESSON TOPIC;
- the existing topic controller;
- the primary Create with AI button;
- the existing loading state and disabled state;
- no FAB.

When generation succeeds, the same deck will show the generated slides.
The topic value will remain connected to _topicController.
The current read-only topic rule after generation will remain only if it is still needed by the existing lesson flow.

Immediately after generation, make Lesson Notes the active tab.
The PageView index must be set to the Lesson Notes index after the draft-only tab is removed.
Do not leave the user on a removed Generate tab index.

When References is hidden or shown, rebuild the visible tab list and clamp the current index to a valid tab.
Use the tab label or a stable tab key when possible, so a visibility change does not open the wrong card.

The Lesson Topic control will be a dropdown.
It will not be an editable TextField.
The dropdown options will contain existing draft lesson records from the existing lessons data for the selected class and selected subject only.
Each dropdown item must carry the draft lesson local ID or server ID, topic, class, subject, and week.
The implementation will use the existing lessons DAO/provider data.
It will not add a new database table or provider.

The last dropdown option will be Create new topic.
It will not be treated as a lesson topic.
When it is selected, call the existing route navigation to the Lessons list screen.
Do not create a new route.

When the user selects another draft topic:

- update the selected topic in the existing lesson state;
- update the week number in the top-right card metadata;
- update the card context line that uses the subject, class, and week;
- store the selected draft lesson ID as the active generation and save target;
- load the selected draft lesson content before editing it, if it already has content;
- do not save the selected topic into the previous lesson ID;
- keep the selected topic ready for the existing Create with AI callback;
- do not load a topic from another class or subject.

If there are no matching draft topics, keep Create new topic available and explain that no draft topic is available for the selected class and subject.

The Generate card must fit in the available height without a vertical scroll view.
Use LayoutBuilder to reduce gaps and icon size on small screens while keeping the dropdown and Create with AI button at their minimum touch size.
Do not put an Expanded widget inside this card when its parent has an unbounded height.

### 5. Lesson Note slide

Match the lesson notes reference:

- show the English Studies • JSS 2 context chip;
- show the current card number;
- show the lesson title, such as Presentation;
- show the lesson text with the current controllers;
- show the highlighted Key Example block when the content contains one;
- keep the current edit fields and undo support;
- allow vertical scrolling inside the card;
- preserve the existing optional Vocabulary and Materials rules.

The lesson note text must look like a word document.
Render separate paragraphs instead of one large text block.
Use clear paragraph spacing, a readable line height, and a content width that keeps the reading line short.
Use the same paragraph rules for read-only text and the same line-height rules for editable fields.
Do not add a rich text dependency.

The content may be split into the design sections instead of being shown as one long form.
The same controllers and update callbacks must still be used.

The Edit Layout control in the deck reference must either open the existing visible-section/settings action or be removed from the final visual if it has no real product action.
It must not be a no-op button.

### 6. Assessment slide

Match the assessment reference:

- show the Assessment chip or the Assessment heading;
- show Card 2 of 4 on the Assessment card;
- show progress dots with the third dot active;
- show the question text;
- show each answer as a large button;
- show the selected answer with the primary border and filled answer letter;
- keep answer selection state in the current question data model;
- keep MCQ, Theory, and Both controls connected to the existing assessment format state;
- keep question count controls connected to _mcqCount and _theoryCount;
- keep edit and delete behavior for stored questions.

Every answer option will use a real callback.
The button will update state and repaint the selected style.
If answer selection is not part of the current business model, the plan will use local view state only and will not write a new database field.

The assessment navigation arrows must align with each other.
They must sit at the same vertical center on the left and right edges of the card.
They must use equal inset values and equal size.
They must not move down beside the answer list.
Use a bounded Stack with centered Positioned controls, and give the card content horizontal padding so the arrows cannot cover answer text.
The same alignment rule must work at desktop, tablet, and phone widths.

Assessment access will use the existing subscription-tier rules.
The current code already blocks assessment access for tiers below Standard.
Standard and Elite may use the assessment content.
Free and Basic remain blocked by the existing tier blocker.
Use the current subscription configuration and the existing upgrade callback.
Show the existing Upgrade Plan action when the tier is blocked.
Do not invent new tier names or limits.

The current assessment-only generator works in this order:

1. Build a separate questions prompt with the existing lesson-question prompt builder.
2. Check the existing assessmentGenerationAllowedTiers configuration.
3. Call the existing generateCallback in tests, or the existing AiService in production.
4. Read only the mcq, mcqs, theory, and subjective fields from the result.
5. Parse and validate the questions with the existing question parser.
6. Update only _mcqs, _theoryQuestions, _subjectiveQuestions, and the related question status fields.
7. Keep the other lesson fields unchanged when the assessment-only call fails.

Assessment-only regeneration will use this same path.
It will not call the main lesson prompt when the Assessment card is open.

### 7. Diagrams slide

Match the diagrams reference:

- show Preview Generated Content and the settings control;
- show the unlocked banner when the current lesson is unlocked;
- show a locked blocker and the existing unlock button when the lesson is not unlocked;
- show Card 3 of 4 on the Suggested Diagrams card;
- show the Lesson Note, Assessment, and Diagrams tabs;
- show Suggested Images;
- show one card per suggestion;
- show the suggestion text;
- show Generate Image on each suggestion;
- show progress while one image is being generated;
- open the existing image viewer when a generated image is tapped;
- keep the current subscription gate for diagram generation.

The existing _generateSuggestedImage(index) callback will own every Generate Image button.
The button must not only change color.
It must call the existing action.

Lesson Notes, Assessment, Suggested Diagrams, and References must keep their locked state when the lesson is generated but not unlocked.
The blocker must prevent editing and actions until the existing unlock callback succeeds.
Assessment must apply the existing subscription-tier blocker in addition to the lesson unlock state.

### 8. References slide

The current References visibility rule stays in place.

When References is visible, it is the fourth content tab:

1. Lesson Notes
2. Assessment
3. Suggested Diagrams
4. References

When References is visible:

- show the References slide or tab in the same deck style;
- keep add-reference and remove-reference behavior;
- add an onRegenerateReferences callback to the existing preview/reference widget path;
- show Regenerate for References only when this callback is available;
- make the callback regenerate references only, not the whole lesson;
- show the same loading and error state used by the other card-specific regeneration actions;
- keep the current references sheet behavior if that is still the approved interaction;
- show a clear disabled or empty state when there are no references.

No database schema change is needed.

The parent screen will own the callback.
It will call the existing generation service or callback with a references-only request, update the existing references list, and preserve the current lesson content.
The callback will be passed into _PreviewColumn and then into the References tab.

References-only regeneration will follow the assessment-only pattern:

1. Build a references-only prompt from the current topic, subject, class, week, and teacher feedback.
2. Call the existing generateCallback in tests, or the existing AiService in production.
3. Read only the references field from the result.
4. Parse it with the existing _parseReferences helper.
5. Update only _references and the References loading/error state.
6. Keep objectives, vocabulary, materials, presentation, assessment, homework, and diagrams unchanged.
7. Save the changed References data through the existing lesson save path after success.

The expected references-only result is a map with a references list.
Each item can use the same title, text, and origin fields already accepted by _parseReferences.
If the current generator returns a full lesson map, extract only references and ignore every other field.
Do not make the References call block or replace the whole lesson.

The planned shared dispatch shape is:

~~~dart
Future<void> _regenerateCurrentCard() async {
  await _openReviewSectionFirst();

  switch (_activeCardKey) {
    case LessonCardKey.assessment:
      await _regenerateAssessmentOnly();
      return;
    case LessonCardKey.references:
      await _handleRegenerateReferences();
      return;
    case LessonCardKey.lessonNotes:
    case LessonCardKey.diagrams:
      await _regenerateCurrentLessonCard();
      return;
  }
}
~~~

The Assessment and References branches must update only their own state fields.
The lesson prompt must not run for either branch.

### 9. Header controls

The top header will match the reference:

- Back: call maybePop or the current route back action;
- Undo: call the existing UndoHistoryController.undo;
- Redo: call the existing UndoHistoryController.redo;
- disabled Undo and Redo: use the controller state and keep the visual disabled state;
- Lesson Editor title: use the desktop and mobile sizes from the design.

The current CallbackShortcuts behavior will stay.
Keyboard arrows will move the deck only when no text field is focused.

### 10. Slide controls

The left and right arrow buttons will:

- go to the previous or next slide;
- stop at the first and last slide;
- use the same controller as the dots and tabs;
- have tooltips and semantic labels;
- be hidden only when the reference layout says they are not useful on small screens;
- keep an equivalent touch area on small screens.

The page dots will:

- show one dot for each visible slide;
- show the active dot in primary blue;
- use a longer active pill if that is needed to match the deck picture;
- move to a slide when tapped;
- expose a semantic label such as Go to Lesson Notes.

### 11. Floating Action Button on lesson tabs

The Generate Lesson Content tab must not show the FAB.
The FAB is visible only when the current lesson is unlocked.
When the lesson is locked, Lesson Notes and the other generated tabs show their blocker and the existing unlock button instead.
Assessment also checks the existing subscription-tier rule before showing an enabled action.

The FAB replaces the bottom row that contains Regenerate, Mark Completed, Export PDF, and Visible Sections.
The bottom action row must not be rendered as a second copy of those actions.

The FAB will be a real FloatingActionButton or an equivalent button with a 48 pixel minimum hit area.
It will have:

- the primary blue fill;
- the dark icon color;
- the add icon when closed;
- a clear tooltip, such as Lesson actions;
- an accessible label;
- a visible focus state;
- a visible pressed state.

On tap, it will open the action menu.
On a second tap, it will close the action menu.
The icon may rotate to a close icon if this matches the final approved picture.

The expanded menu will expose these real actions:

| FAB action | Existing action to call |
| --- | --- |
| Regenerate | _handleRegenerate or the existing review opener |
| Export PDF | _handleExportPdf |
| Mark Completed | _handleMarkCompleted when unlocked and not already complete |
| Visible Sections | _showVisibleSectionsSheet |

The menu will not show an enabled action when the action cannot run.
For example, Regenerate and Mark Completed will use the current unlock and lesson state.
Export will show the current exporting state.

The menu will close after an action is selected when that is safe.
It will stay open while a long action is in progress only if the loading state needs to remain visible.

The FAB action menu is the only generated-tab action surface for these four actions.
It must not duplicate the same action in a bottom bar.

### 12. Sidebar buttons

The reference shows Home, Lessons, and Exams.

Remove only the Admin icon/item from the Lesson Editor sidebar.
Do not edit the app router.
Do not delete the Admin route.
Do not change auth guards or any other Admin code.

The visible sidebar items will call the current route navigation methods.
The active Lessons item will have the purple active background from the reference.
Teacher Profile will remain visual only unless there is an existing profile action to call.
There must be no new no-op button.

### 13. Replace the bottom actions with the FAB structure

Do not render the old bottom row with Regenerate, Mark Completed, Export PDF, and Visible Sections on the generated tabs.
Use the FAB structure from the Generate page design, but place it only on the other slides as described in section 11.

The FAB menu will contain:

1. Regenerate, which opens the existing feedback and regeneration flow;
2. Mark Completed, which calls the existing completion flow;
3. Export PDF, which calls the existing export flow;
4. Visible Sections, which opens the existing visibility sheet.

Save Lesson is removed from the FAB menu.
Do not add a second Save action to the FAB.
The existing Save button inside the preview may remain because it is part of the current save flow, but it must not be duplicated in the FAB.

The requested replacement must always include the four actions above.

Regenerate always opens the review section first.
It must never call regeneration directly from the closed FAB.
After the user confirms the review action, regeneration must target only the current content card:

- Lesson Notes: regenerate only the lesson-note content for the open lesson-note card;
- Assessment: regenerate only the assessment content for the open assessment card;
- Suggested Diagrams: regenerate only the open diagram suggestion/card;
- References: call the new references-only regeneration callback.

Pass the active tab/card key into the existing regeneration flow.
Do not regenerate the whole lesson when only one card is open.
Keep the existing undo snapshot limited to the changed card.

The current loading labels, confirmation dialog, disabled rules, and callback methods remain.
Only their visual container changes from the bottom row to the expanded FAB menu.

On small screens, the FAB menu will use a bounded Column and safe-area padding.
It must not use an unbounded or overlapping layout.

### 14. Accessibility and interaction rules

Every control will have:

- a real callback;
- a semantic label or visible text;
- a minimum 48 by 48 hit target;
- a disabled state when the action cannot run;
- a loading state for long work;
- a visible focus state;
- no overlapping hit areas.

The screen will also support:

- keyboard focus for tabs and arrows;
- keyboard arrow movement when text fields are not focused;
- normal text editing and undo/redo;
- screen-reader labels for page dots and slide arrows;
- vertical scroll inside long cards;
- safe-area padding around the FAB and its action menu.

### 15. Keep the current code structure and avoid RenderBox issues

Keep the current main classes and helper methods where possible:

- _LessonEditorScreenState remains the owner of lesson state and callbacks;
- _NavigationDrawer remains the sidebar widget;
- _ToolHeader and _MobileHeader remain the header widgets;
- _PreviewColumn remains the generated content owner;
- _FloatingActionArea is changed into the FAB action surface or is replaced by a small FAB widget with the same callback inputs;
- existing document, question, diagram, references, and sheet helpers remain in place.

Do not rewrite the whole screen into a new feature or add a new state-management layer.
Do not add a dependency.

To avoid RenderBox and layout errors:

- give the PageView a bounded height from the available Scaffold area;
- use LayoutBuilder or ConstrainedBox before placing the deck card;
- do not put an Expanded widget inside an unbounded SingleChildScrollView;
- do not nest two vertical scroll views without a bounded inner height;
- keep long lesson text scrolling inside the card content area;
- use Stack only inside a bounded deck area;
- use centered Positioned arrows with fixed equal insets;
- keep the FAB menu inside SafeArea and give it a maximum width;
- do not use a full-screen Positioned widget that covers the card controls;
- test desktop, tablet, and phone sizes for overflow before visual review.

The diffs in Appendix B are structural examples only.
The final diff must be small enough to review and must preserve the existing callback and controller flow.

## Open logic points

The Save action is resolved:

- Save Lesson is removed from the FAB menu;
- the existing preview Save button may remain;
- no second Save action is added.

The other three content cards and References will regenerate only their current open card.

There is one implementation check that must be completed before coding:

- Selecting an existing draft topic must load and use that draft lesson ID as the active editor target. It must not accidentally overwrite a different lesson.

When the topic changes, compare the current controllers with the last loaded or saved draft snapshot.

- If there are no unsaved changes, load the selected draft record immediately.
- If there are unsaved changes, show a confirmation dialog with Keep editing and Switch topic actions.
- Keep editing closes the dialog and restores the current dropdown value.
- Switch topic discards only the unsaved editor changes after confirmation, loads the selected draft record, updates the topic and week, and changes the active lesson ID.
- Selecting Create new topic uses the same confirmation check before routing to the Lessons list.
- The previous lesson ID must never receive the newly selected topic by accident.

## Remaining logic checks

After the latest decisions, these are the only remaining checks:

There are no remaining product logic breaks in the plan.
The two items above are now defined as implementation rules.
They do not require a new table, provider, dependency, auth flow, or route.

## Phase-by-phase implementation plan

The work should be done in small phases.
Each phase should be implemented, reviewed, and tested before the next phase starts.
Do not change the whole screen in one large edit.

### Phase 0 — Confirm the current baseline

Inspect the current lesson screen, lesson tests, existing lessons data source, route, prompt builders, assessment parser, Save button, review section, and undo snapshot code.

Confirm:

- draft lesson fields include a stable local or server ID;
- draft topics can be filtered by class and subject;
- the Lessons list route already exists;
- assessment generation uses a separate question prompt;
- Standard and Elite are allowed for assessment, while Free and Basic are blocked;
- the current generator can return or be asked for a References-only result.

Stop if a required field or callback is missing.
Do not add a database column, dependency, auth change, or new route.

### Phase 1 — Add safe deck state

File: lib/features/lesson/screens/lesson_editor_screen.dart

Add or adapt:

- stable deck/card keys;
- active deck index;
- bounded PageController;
- selected draft lesson ID;
- active card key;
- References regeneration loading and error state.

Rules:

- Generate has no card number;
- Lesson Notes is card 1;
- Assessment is card 2;
- Suggested Diagrams is card 3;
- References is card 4 when visible;
- Lesson Notes becomes active after generation;
- the index is clamped when Generate disappears or References visibility changes.

Acceptance: existing generation, save, and provider callbacks remain connected, and no unbounded-height or RenderBox error appears.

### Phase 2 — Build the bounded responsive shell

File: lib/features/lesson/screens/lesson_editor_screen.dart

Keep the current Scaffold, sidebar, headers, and helper classes.
Put the deck inside a bounded LayoutBuilder or ConstrainedBox.
Keep long content scrollable inside its card.
Keep Generate non-scrollable.
Add page dots, counters, and previous/next controls.
Place both assessment arrows at the same vertical center with equal insets.
Test desktop, tablet, and phone sizes.

Do not put Expanded inside an unbounded vertical scroll view.

### Phase 3 — Implement the draft Generate tab

File: lib/features/lesson/screens/lesson_editor_screen.dart

Tasks:

1. Show this tab only for ungenerated draft lessons.
2. Use Create with AI instead of Regenerate Deck.
3. Use a type-safe dropdown option wrapper.
4. Load options from existing lessons data only.
5. Filter by selected class and subject.
6. Add Create new topic as the final option.
7. Route Create new topic to the existing Lessons list screen.
8. Store the selected draft lesson ID, topic, and week.
9. Load the selected draft before editing it.
10. Show Keep editing and Switch topic if there are unsaved changes.
11. Do not silently overwrite the previous lesson.
12. Do not show the FAB on this tab.

The Generate card must fit without a vertical scroll view at small sizes.

### Phase 4 — Implement the numbered content tabs

File: lib/features/lesson/screens/lesson_editor_screen.dart

Use this order:

1. Lesson Notes
2. Assessment
3. Suggested Diagrams
4. References when visible

Start numbering at Lesson Notes.
Do not number Generate.
Use paragraph blocks and readable line spacing for Lesson Notes.
Keep the blocker and Unlock button on locked generated tabs.
Use the existing assessment tier gate and Upgrade Plan action.
Keep the existing References visibility setting.

### Phase 5 — Implement current-card regeneration

File: lib/features/lesson/screens/lesson_editor_screen.dart

Every Regenerate action opens the review section first.
The active card key is passed into the review and regeneration flow.

- Lesson Notes changes only Lesson Notes content.
- Assessment uses the existing assessment-only generator pattern.
- Suggested Diagrams changes only the open diagram card.
- References uses the new References-only callback in Phase 6.

Assessment-only generation must build the separate questions prompt, apply assessmentGenerationAllowedTiers, call the existing callback or AiService, parse only MCQ/Theory/Subjective fields, and preserve every other field.

### Phase 6 — Add References-only regeneration

Files:

- lib/features/lesson/screens/lesson_editor_screen.dart
- the existing prompt-template file only if a reusable References prompt does not exist

Add onRegenerateReferences to the existing preview/reference path.
Build a References-only prompt from the current lesson context and review text.
Call the existing callback in tests or AiService in production.
Parse only the references field with _parseReferences.
Update only _references and its loading/error state.
Save through the existing lesson save path.

If the result is a full lesson map, extract only references and leave every other field unchanged.

### Phase 7 — Implement the action surface

File: lib/features/lesson/screens/lesson_editor_screen.dart

Remove the old bottom action row and use the FAB action surface.
Show the FAB only on unlocked numbered tabs.
Keep it hidden on Generate and locked tabs.
The menu contains Regenerate, Mark Completed, Export PDF, and Visible Sections.
Remove Save Lesson from the FAB.
Keep the existing preview Save button without adding a duplicate.
Keep loading, disabled, SafeArea, and bounded-menu behavior.

### Phase 8 — Remove only the Admin sidebar item

File: lib/features/lesson/screens/lesson_editor_screen.dart

Remove the Admin item from the Lesson Editor sidebar only.
Do not edit app_router.dart.
Do not delete the Admin route.
Do not change auth guards or other Admin code.

### Phase 9 — Add and update tests

File: test/features/lesson_editor_test.dart

Add tests for:

- draft topic filtering and Create new topic navigation;
- unsaved topic switching and lesson ID safety;
- active Lesson Notes tab after generation;
- index clamping when tabs change;
- numbered tab order and card counters;
- locked, unlocked, and assessment tier states;
- review-first current-card regeneration;
- assessment-only data preservation;
- References-only data preservation;
- FAB visibility and all FAB actions;
- absence of the Admin sidebar item;
- desktop, tablet, and phone overflow safety.

### Phase 10 — Validate one phase at a time

Run only after a phase is complete:

~~~powershell
flutter analyze --no-pub lib/features/lesson/screens/lesson_editor_screen.dart test/features/lesson_editor_test.dart
flutter test test/features/lesson_editor_test.dart
~~~

Do not run flutter clean.
Do not run a full project analysis unless the changed-file command shows a project-level error.

## Test file update plan

The test file to update is:

test/features/lesson_editor_test.dart

The current generation and database behavior tests should stay.
Their assertions should be updated only where the visible control labels or widget locations change.

### Test helpers to add or update

Add small helpers for:

~~~dart
Future<void> _goToSlide(WidgetTester tester, String label) async {
  final control = find.text(label);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _tapLessonAction(
  WidgetTester tester,
  String label,
) async {
  final action = find.text(label);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}
~~~

The final helper names may change to fit the existing test style.
The helpers must use stable visible labels or semantic labels.
They must not depend on private widget class names unless there is no safer finder.

### Tests for the first slide

Add or update tests for:

1. A draft lesson shows the optional Generate Lesson Content first tab.
2. A generated lesson does not show the Generate Lesson Content tab.
3. The Generate tab is not wrapped in a vertical scroll view.
4. The first tab shows the topic dropdown with the design label.
5. The topic control is not an editable TextField.
6. The dropdown contains only draft topics for the selected class and subject.
7. The dropdown always includes Create new topic after the existing draft topics.
8. Tapping Create new topic routes to the existing lessons list screen.
9. The dropdown shows a safe empty state when no matching draft topic exists, while keeping Create new topic available.
10. Selecting a different topic updates the week number in the top-right metadata.
11. The topic list comes from existing lessons data.
12. The Create with AI button is disabled when no valid topic is selected.
13. The Create with AI button calls the existing generation callback.
14. The button changes to the loading state during generation.
15. The Generate tab has no FAB.

### Tests for the FAB actions

Add interaction tests for:

- FAB is visible on Lesson Notes, Assessment, Suggested Diagrams, and References only when the lesson is unlocked and those tabs are visible;
- FAB is not visible on the Generate Lesson Content tab;
- FAB Regenerate opens the existing review section and regeneration flow;
- FAB Regenerate does not call regeneration before the review section is opened;
- regeneration updates only the currently open Lesson Notes, Assessment, or Suggested Diagrams card;
- References Regenerate calls the new references-only callback;
- Assessment-only regeneration preserves lesson-note, homework, diagram, and References data;
- References-only regeneration preserves lesson-note, assessment, homework, and diagram data;
- FAB Mark Completed calls the existing completion path after unlock;
- FAB Export PDF calls the existing export path;
- FAB Visible Sections opens the existing visible sections sheet;
- locked lessons do not show an enabled Mark Completed action;
- completed lessons do not show an enabled Mark Completed action;
- locked Lesson Notes, Assessment, Suggested Diagrams, and References show the existing blocker and unlock button;
- the FAB is hidden while the lesson is locked;
- assessment actions use the existing subscription-tier blocker and upgrade callback;
- the FAB becomes visible after unlock;
- Export PDF shows the exporting state and then returns to the normal state;
- the old bottom action row is not rendered;
- each action has one visible, tappable control and is not duplicated by a hidden overlay.

The FAB remains conditional on the lesson being unlocked. The Generate tab and locked tabs must not show it.

Where database work is needed, use the existing mocks and database setup in this test file.
Do not add a new database test fixture unless the current fixture cannot test the existing callback.

### Tests for slide movement

Add tests for:

- the generated page order: Lesson Notes, Assessment, Suggested Diagrams, References;
- the draft page order: Generate Lesson Content, Lesson Notes, Assessment, Suggested Diagrams, References when visible;
- References stays fourth among content tabs when its visibility setting is enabled;
- after generation, Lesson Notes is the active tab;
- after generation, the Generate tab is removed and the active index is valid;
- hiding References clamps or preserves the active tab without opening the wrong card;
- the current card counter;
- the active page dot;
- tapping each page dot moves to the correct slide;
- tapping the next arrow moves forward;
- tapping the previous arrow moves backward;
- the previous arrow is disabled or has no effect on the first slide;
- the next arrow is disabled or has no effect on the last visible slide;
- keyboard arrows move the slide when no text field is focused;
- keyboard arrows do not move the slide while a text field is focused.

### Tests for Lesson Notes

Add tests for:

- context chip and title;
- card counter;
- lesson note text;
- paragraph separation and readable line spacing;
- word-document style paragraph spacing in read-only and editable states;
- editable text fields when unlocked;
- locked preview when not unlocked;
- optional Vocabulary and Materials visibility;
- the Key Example visual when the content has that section;
- vertical scrolling does not cause an overflow.

### Tests for Assessment

Add tests for:

- Assessment slide appears in the correct position;
- question text is visible;
- all answer buttons are visible;
- tapping an answer changes the selected visual state;
- left and right assessment arrows have the same vertical center and equal inset;
- arrows do not cover question or answer text;
- MCQ, Theory, and Both controls change the selected format;
- question count plus and minus buttons change the displayed count;
- update and delete callbacks still work;
- assessment tier blocking uses the existing subscription configuration;
- the assessment slide has no horizontal overflow at the reference test sizes.

### Tests for Diagrams

Add tests for:

- Diagrams slide appears in the correct position;
- Suggested Images heading is visible;
- each suggestion has a Generate Image button;
- tapping Generate Image calls the correct index callback;
- tapping References Regenerate calls the references-only callback;
- loading state is shown for the selected suggestion;
- the generated image can be opened in the viewer;
- the subscription gate still blocks the action when required;
- tabs can move between Lesson Note, Assessment, and Diagrams.

### Tests for header, sidebar, and footer

Add tests for:

- Back calls the existing navigation behavior;
- Undo calls the existing undo controller;
- Redo calls the existing redo controller;
- Home navigates to /;
- Lessons navigates to /lessons;
- Exams navigates to /exams;
- the active Lessons item is visible;
- Admin is not visible in the Lesson Editor sidebar;
- no Admin route or other Admin code is changed by this UI task;
- Regenerate opens the current review section;
- Export PDF is tappable;
- Visible Sections opens the sheet;
- Mark Completed appears only when it can work.

### Test sizes

Use at least these test sizes:

- a desktop size close to the 1600 pixel reference screenshots;
- a tablet size where the sidebar is visible;
- a small phone size where the sidebar is hidden.

For each size, check:

- no RenderFlex overflow;
- no clipped action buttons;
- no card hidden behind the footer;
- FAB is inside the safe area;
- all required controls can be found and tapped.

## Validation plan after implementation

The following commands are for after the UI change is implemented.
They are not run as part of this planning task.

Run analysis only on the changed files:

~~~powershell
flutter analyze --no-pub lib/features/lesson/screens/lesson_editor_screen.dart test/features/lesson_editor_test.dart
~~~

Run the focused test file once after the change is complete:

~~~powershell
flutter test test/features/lesson_editor_test.dart
~~~

Do not run flutter clean.
Do not run a full project analysis for this UI task unless a changed-file command shows a project-level error.

After running the commands, share the output if any test or analysis line fails.

## Appendix A — planned code snippets

These snippets show the planned shape only.
They are not applied code.

### A.1 Deck slide model

~~~dart
class _LessonDeckSlide {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  final bool draftOnly;

  const _LessonDeckSlide({
    required this.label,
    required this.icon,
    required this.builder,
    this.draftOnly = false,
  });
}
~~~

The slide list will be built from the current state.
The Generate slide will use draftOnly: true.
The References slide will be added only when the existing visibility rule allows it.
The generated content order will always be Lesson Notes, Assessment, Suggested Diagrams, References.

### A.2 Deck controller movement

~~~dart
void _goToDeckSlide(int index) {
  if (index < 0 || index >= _deckSlides.length) return;

  _deckController.animateToPage(
    index,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeInOut,
  );
}

void _goToNextDeckSlide() => _goToDeckSlide(_deckIndex + 1);

void _goToPreviousDeckSlide() => _goToDeckSlide(_deckIndex - 1);
~~~

After generation removes the draft-only tab, set the controller to the Lesson Notes index.
When References visibility changes, preserve the current tab by key when possible and clamp the index when it is no longer visible.

### A.3 Optional draft Generate tab shape

~~~dart
Widget _buildGenerateLessonSlide(ColorScheme cs, ThemeData theme) {
  return _DeckCard(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 40,
          backgroundColor: cs.primary.withValues(alpha: 0.10),
          child: Icon(Icons.auto_awesome_rounded, color: cs.primary, size: 48),
        ),
        const SizedBox(height: 32),
        Text('Generate Lesson Content', style: theme.textTheme.headlineLarge),
        const SizedBox(height: 12),
        Text(
          'Choose your topic and let AI draft the perfect lesson structure for your students.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        DropdownButtonFormField<_DraftTopicOption>(
          value: _selectedDraftTopic,
          items: _draftTopicsForClassAndSubject
              .map((topic) => DropdownMenuItem<_DraftTopicOption>(
                    value: _DraftTopicOption.fromLesson(topic),
                    child: Text(topic.topic),
                  ))
              .followedBy([
                const DropdownMenuItem<_DraftTopicOption>(
                  value: _DraftTopicOption.createNew(),
                  child: Text('Create new topic'),
                ),
              ])
              .toList(),
          onChanged: _onDraftTopicOrCreateNewTopicChanged,
          decoration: _lessonTopicDecoration(cs),
        ),
        const SizedBox(height: 24),
        _buildCreateWithAiButton(cs, theme),
      ],
    ),
  );
}
~~~

The Generate tab will not contain the FAB and will not be placed inside a vertical scroll view.
The _DraftTopicOption wrapper keeps the lesson options and Create new topic option type-safe.
When the create-new option is selected, use the existing Lessons list route and do not change lesson state.

The selected item must also carry the active draft lesson ID.
Pass that ID through the existing generation and save path so another draft lesson is not overwritten.

### A.4b References regeneration callback

~~~dart
Future<void> _handleRegenerateReferences() async {
  if (!_isUnlocked || _lessonId == null) return;

  setState(() => _isRegeneratingReferences = true);
  try {
    final result = await _generateReferencesOnly(
      lessonId: _lessonId!,
      topic: _topicController.text,
      subject: _subject,
      classLevel: _classLevel,
      week: _week,
    );
    if (!mounted) return;
    setState(() => _references = result);
  } finally {
    if (mounted) setState(() => _isRegeneratingReferences = false);
  }
}
~~~

This callback is a planned screen callback.
It must use the existing generation service or callback and must update only the References data.

### A.4 Responsive action FAB shape on generated tabs

~~~dart
Widget _buildLessonActionFab(BuildContext context) {
  if (_isDraftLesson || _deckIndex == _generateTabIndex || !_isUnlocked) {
    return const SizedBox.shrink();
  }

  return SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_showLessonActions) _buildLessonActionMenu(context),
        FloatingActionButton(
          heroTag: 'lesson-editor-actions',
          tooltip: 'Lesson actions',
          onPressed: () {
            setState(() => _showLessonActions = !_showLessonActions);
          },
          child: Icon(
            _showLessonActions ? Icons.close_rounded : Icons.add_rounded,
          ),
        ),
      ],
    ),
  );
}
~~~

The final implementation will pass the existing callbacks into the action menu.
The menu will contain Regenerate, Mark Completed, Export PDF, and Visible Sections.
The menu will not create a new save, export, completion, regeneration, or visibility logic path.

### A.5 Button semantics

~~~dart
Semantics(
  button: true,
  label: 'Next lesson section',
  child: IconButton(
    tooltip: 'Next lesson section',
    onPressed: canMoveNext ? _goToNextDeckSlide : null,
    icon: const Icon(Icons.chevron_right_rounded),
  ),
)
~~~

## Appendix B — planned diffs

These are review diffs for the future implementation.
They show the intended file areas and behavior.
They are not applied to the repository.

### B.1 lesson_editor_screen.dart — keep the current shell and add a bounded deck

~~~diff
diff --git a/lib/features/lesson/screens/lesson_editor_screen.dart b/lib/features/lesson/screens/lesson_editor_screen.dart
--- a/lib/features/lesson/screens/lesson_editor_screen.dart
+++ b/lib/features/lesson/screens/lesson_editor_screen.dart
@@
- child: SingleChildScrollView(
-   child: Column(
-     children: [
-       if (showEntryScreen) _buildEntryScreenSkeleton(cs, theme),
-       if (!showEntryScreen) _buildEditorForm(cs, theme),
-     ],
-   ),
- ),
+ child: LayoutBuilder(
+   builder: (context, constraints) {
+     return ConstrainedBox(
+       constraints: BoxConstraints(maxHeight: constraints.maxHeight),
+       child: _buildLessonDeckWithExistingHelpers(cs, theme),
+     );
+   },
+ ),
~~~

The real diff will keep the current scaffold, state class, form, preview, and callbacks.
It will place the existing helpers inside a bounded deck viewport.
It will not put Expanded inside an unbounded scroll view.
The draft Generate tab will use a non-scrollable bounded card.

### B.2 lesson_editor_screen.dart — add deck movement controls

~~~diff
@@
+ IconButton(
+   tooltip: 'Previous lesson section',
+   onPressed: _deckIndex == 0 ? null : _goToPreviousDeckSlide,
+   icon: const Icon(Icons.chevron_left_rounded),
+ ),
+ Expanded(
+   child: PageView.builder(
+     controller: _deckController,
+     itemCount: _deckSlides.length,
+     onPageChanged: (index) {
+       setState(() => _deckIndex = index);
+     },
+     itemBuilder: (context, index) {
+       return _deckSlides[index].builder(context);
+     },
+   ),
+ ),
+ IconButton(
+   tooltip: 'Next lesson section',
+   onPressed: _deckIndex == _deckSlides.length - 1
+       ? null
+       : _goToNextDeckSlide,
+   icon: const Icon(Icons.chevron_right_rounded),
+ ),
~~~

The content tab list must be created in this order: Lesson Notes, Assessment, Suggested Diagrams, References.
The draft-only Generate tab is inserted at index zero only while the lesson is a draft.
The Generate tab must not be included in the scrollable content area.

For the assessment card, both arrow controls will be inside a bounded Stack and use the same centered alignment:

~~~dart
Positioned.fill(
  child: Align(
    alignment: Alignment.centerLeft,
    child: _buildDeckArrow(isPrevious: true),
  ),
),
Positioned.fill(
  child: Align(
    alignment: Alignment.centerRight,
    child: _buildDeckArrow(isPrevious: false),
  ),
),
~~~

The card content will use equal left and right padding so neither arrow covers text.

### B.3 lesson_editor_screen.dart — move the bottom actions into the FAB menu

~~~diff
@@
+ _LessonActionItem(
+   label: 'Regenerate',
+   icon: Icons.refresh_rounded,
+   onPressed: _isUnlocked
+       ? () => _openRegenerationReview(cardKey: _activeCardKey)
+       : null,
+ ),
+ _LessonActionItem(
+   label: 'Export PDF',
+   icon: Icons.picture_as_pdf_rounded,
+   onPressed: _isExporting ? null : _handleExportPdf,
+ ),
+ _LessonActionItem(
+   label: 'Mark Completed',
+   icon: Icons.check_circle_rounded,
+   onPressed: _isUnlocked && _lessonStatus != 'completed'
+       ? _handleMarkCompleted
+       : null,
+ ),
+ _LessonActionItem(
+   label: 'Visible Sections',
+   icon: Icons.visibility_rounded,
+   onPressed: _showVisibleSectionsSheet,
+ ),
~~~

The FAB is rendered only when the current tab is not the draft-only Generate tab.
The old bottom action row is removed so the actions are not duplicated.

### B.4 lesson_editor_screen.dart — remove the bottom action row

~~~diff
@@ class _FloatingActionArea extends StatelessWidget
- return _buildBottomActionRow();
+ return _buildLessonActionFab(context);
~~~

The final code will keep the existing callback inputs and loading states.
It will use a bounded FAB menu inside SafeArea, so no RenderBox or overflow issue is introduced.

### B.4b lesson_editor_screen.dart — add References regeneration callback

~~~diff
@@ _PreviewColumn fields
+ final Future<void> Function()? onRegenerateReferences;

@@ _PreviewColumn constructor
+ this.onRegenerateReferences,

@@ References tab builder
+ onRegenerateReferences: widget.onRegenerateReferences,

@@ References FAB action
+ _LessonActionItem(
+   label: 'Regenerate',
+   icon: Icons.refresh_rounded,
+   onPressed: onRegenerateReferences,
+ ),
~~~

The parent callback must update only the References list.
It must not replace the other generated lesson fields.

### B.5 lesson_editor_test.dart — test the draft-only Generate tab

~~~diff
@@
+ testWidgets('draft lesson shows a non-scrollable Generate tab',
+     (tester) async {
+   await tester.pumpWidget(buildApp(generateCallback: dispatchCallback()));
+   await tester.pumpAndSettle();
+
+   expect(find.text('Generate Lesson Content'), findsOneWidget);
+   expect(find.text('Create with AI'), findsOneWidget);
+   expect(find.byType(DropdownButtonFormField), findsOneWidget);
+   expect(find.byTooltip('Lesson actions'), findsNothing);
+ }
~~~

Add tests that:

- select another existing draft topic and check that the week number in the card metadata changes;
- select Create new topic and verify navigation to the existing lessons list screen;
- verify the options come from existing lessons data and are filtered by class and subject;
- show Keep editing and Switch topic when the current draft has unsaved changes;
- keep the current draft when Keep editing is selected;
- load the selected lesson ID only after Switch topic is confirmed.

### B.6 lesson_editor_test.dart — test content tab order and navigation

~~~diff
@@
+ testWidgets('deck arrows and dots change the active slide', (tester) async {
+   await tester.pumpWidget(buildApp(generateCallback: dispatchCallback()));
+   await tester.pumpAndSettle();
+
+   expect(find.text('Lesson Notes'), findsOneWidget);
+   expect(find.text('Assessment'), findsOneWidget);
+   expect(find.text('Suggested Diagrams'), findsOneWidget);
+   expect(find.text('References'), findsOneWidget);
+
+   await tester.tap(find.byTooltip('Next lesson section'));
+   await tester.pumpAndSettle();
+   expect(find.text('Assessment'), findsOneWidget);
+
+   await tester.tap(find.bySemanticsLabel('Go to References'));
+   await tester.pumpAndSettle();
+   expect(find.text('References'), findsOneWidget);
+ });
~~~

Add a draft test that checks Generate Lesson Content is inserted before Lesson Notes.
Add a hidden-reference test that checks the generated content order has only three visible tabs.

### B.7 lesson_editor_test.dart — test every visible action

~~~diff
@@
+ testWidgets('diagram Generate Image button calls its index', (tester) async {
+   var generatedIndex = -1;
+
+   await tester.pumpWidget(buildApp(
+     generateCallback: dispatchCallback(),
+     onRegenerateDiagram: (index) async {
+       generatedIndex = index;
+     },
+   ));
+   await tester.pumpAndSettle();
+
+   await _goToSlide(tester, 'Diagrams');
+   await tester.tap(find.text('Generate Image').first);
+   await tester.pumpAndSettle();
+
+   expect(generatedIndex, 0);
+ });
~~~

The exact test constructor may need to use the current test wrapper because the existing screen test injects callbacks through the generated lesson flow.

### B.8 lesson_editor_screen.dart — remove only the Admin sidebar icon

~~~diff
@@ lesson_editor_screen.dart
- _NavItem('Admin', Icons.admin_panel_settings_rounded, false),
~~~

Do not change app_router.dart.
Do not delete the Admin route.
Only remove the Admin item from the Lesson Editor sidebar.

## Files planned for a future implementation

These files are expected to change for the first implementation pass:

- lib/features/lesson/screens/lesson_editor_screen.dart
- test/features/lesson_editor_test.dart

This planning task changes only:

- docs/lesson_editor_ui_match_plan.md

## Prompt to implement a phase later

Copy this prompt and replace PHASE_NUMBER with the phase to implement:

~~~text
Read AGENTS.md and docs/lesson_editor_ui_match_plan.md first.

Implement only Phase PHASE_NUMBER from the phase-by-phase plan.
Do not implement later phases in the same turn.

Important rules:

- Use the existing code structure and style.
- Do not change auth flow.
- Do not change database tables or schema.
- Do not change provider logic unless the selected phase directly requires it.
- Do not add dependencies.
- Use existing lessons data, callbacks, routes, parsers, and tier configuration.
- Use apply_patch for file edits.
- Do not run flutter clean.
- Do not run dart analyze, flutter analyze, or flutter test.
- Give me the changed-file commands to run after the work and ask me for the output.
- If you find a logic break or a missing callback, stop and ask me before assuming.
- Keep layouts bounded and avoid RenderBox, RenderFlex, and nested-scroll errors.

Before editing:

1. Inspect the current files named by the phase.
2. Check the current git status.
3. State the exact files you will change.
4. State how the phase will preserve the existing behavior.

During the phase:

1. Make only the requested phase changes.
2. Keep existing callbacks and controller flow connected.
3. Add or update only the tests required for this phase.
4. Do not make unrelated cleanup changes.

After the phase:

1. Review the diff.
2. Check that no protected area was changed.
3. Report the files changed.
4. Report any remaining logic breaks.
5. Give me the exact changed-file analysis and focused test commands, but do not run them.
~~~

Example:

~~~text
Implement only Phase 3 from docs/lesson_editor_ui_match_plan.md.
Follow all project instructions in AGENTS.md.
~~~

## Git commands for the future implementation

These commands are not run now because no app change was requested.

~~~powershell
git status --short
git add lib/features/lesson/screens/lesson_editor_screen.dart test/features/lesson_editor_test.dart docs/lesson_editor_ui_match_plan.md
git commit -m "Match lesson editor UI to Stitch design"
git push origin <your-branch-name>
~~~

Before the commit, review the final tab order, draft-topic filtering, FAB visibility, Save removal from the FAB, and Admin sidebar removal.
