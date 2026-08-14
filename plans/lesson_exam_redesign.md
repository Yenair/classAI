# Lesson + Exam Redesign — Merging Assessment Generation into the Lesson Editor

**Date:** 2026-08-12
**Status:** Design proposal only — no code changes.
**Target user:** Average Nigerian teacher, very low technical literacy (assume IQ 60). Flows must require as few taps as possible and be nearly impossible to get wrong.

---

## 1. Executive summary

Today, assessment exists in two disconnected places:

1. **Inside the lesson editor** — Assessment/Homework are free-text sections of the lesson-note JSON, driven by a decorative "Assessment Format" dropdown that is never passed to the prompt (verified: `_handleGenerate` calls `PromptTemplates.lessonNote(...)` without `_assessmentFormat`). Difficulty and Bloom's chips do reach the prompt, but they shape the *lesson note*, not any real question bank.
2. **In a separate exam editor** — a real question engine (MCQ/Theory/Subjective types + counts + difficulty) with its own generation prompts, its own tier gate, and its own save flow. Compilation exams ("Full-Term Exam") live on a third screen that re-generates from scheme topics.

The user's idea is to merge these: move the question engine into the lesson editor as a collapsible **"Assessment and Homework"** section, generate lesson + questions in **one click**, gate the section by subscription, remove the old Assessment/Homework text sections and the top-level difficulty/assessment-format dropdowns, and redesign the exam editor to support exactly two compilation types — **Term Exam** (all term topics) and **CA Test** (a few chosen topics).

This document audits the current screens and gating, proposes **five designs** (the user's idea plus four alternatives), compares them, and recommends **Design A — the user's idea, refined** with an explicit topic picker, a shared engine widget, and removal of the implicit exam-creation paths already flagged in `plans/exams_generation_redesign.md`.

---

## 2. Current-state audit (read-only)

### 2.1 Screens involved

| Screen | Route | What it does today |
|---|---|---|
| `LessonEditorScreen` | `/lesson-editor`, `/lessons/:id` | Subject/class/week/topic, difficulty segmented, Bloom's chips, **Assessment Format segmented (MCQ/Theory/Both)**; "Generate with AI" → one `PromptTemplates.lessonNote` call → Objectives / Vocabulary / Materials / Presentation / **Assessment (free text)** / **Homework (free text)** preview cards. Auto-saves after generation; content is locked until unlock. |
| `ExamEditorScreen` | `/exam-editor`, `/exams/:id` | Subject/class/topic/week, **question-type multi-select (MCQ/Theory/Subjective) + per-type counts**, difficulty. Three separate validated prompts (`mcqs`, `theoryQuestions`, `subjectiveQuestions`); content JSON `{mcqs, theory, subjective}`. |
| `ExamsListScreen` | `/exams` | Filters (status/term/class/subject), list of exam cards, "New Exam" FAB → `/exam-editor` with subject/class/term query params. **Silently seeds a draft exam per scheme week (`_bootstrapSchemeDrafts`).** |
| `FullTermExamScreen` | `/full-term-exam` | Lists **every scheme topic** for the school with per-topic question-count fields, a total + "Auto-Distribute", then a single combined `PromptTemplates.examQuestions` prompt → saves draft "Full-Term Exam (N topics)" → pushes `/exams/:id`. |

### 2.2 Key finding — the Assessment Format dropdown is decorative

`_handleGenerate` (lesson editor, ~line 643) builds the prompt as:

```dart
PromptTemplates.lessonNote(_subject, 'NERDC', _classLevel, _week, topic,
    _difficulty, bloomsStr, teacherName: ..., schoolName: ...);
```

`_assessmentFormat` is **never** passed to the prompt and has no effect on the output. Removing it (as the user requests) loses no behavior — it is purely cosmetic today. The difficulty and Bloom's chips *do* affect the lesson-note tone, so the design must decide where they live after the merge (see §3.3).

### 2.3 Subscription / tier gating today

- **Lesson generation:** blocked only for `free` (`authTier == 'free'` → `_showUpgradeRequiredDialog()`, which requests **elite**). Any paid tier can generate lessons.
- **Exam generation:** gated by `config.examGenerationAllowedTiers`, a remote config key seeded to `["basic","standard","elite"]` (migration `20260716_000002_seed_exam_and_sync_config.sql`). The exam editor shows the upgrade dialog on failure; the full-term screen shows a toast ("Contact your school admin to upgrade.").
- **Storage:** per-tier limits (`lesson_storage_limits`, `teacher_seat_limits`); both editors enforce counts before insert.
- **User requirement:** the locked section must say **"Upgrade to Standard/Elite to generate assessment"** — i.e. the lesson-embedded engine should be gated to **standard + elite**, which is *stricter* than the current exam gate (which includes basic). This implies a new config key (e.g. `assessment_generation_allowed_tiers = ["standard","elite"]`) so the copy and the policy stay aligned.

### 2.4 Data model (relevant)

- **`Lessons`**: `content` JSON (objectives/vocabulary/materials/presentation/assessment/homework/diagrams), `difficulty`, `bloomsVerbs`, `schemeOfWorkId`, `weekNumber`, `term`, `status`.
- **`Exams`**: `content` JSON (`{mcqs, theory, subjective}`), `difficulty`, `schemeOfWorkId`, `weekNumber`, `term`, `isUnlocked`. **No `status` column** (lessons have one; exams do not), no `lesson_id` link, no `compilation_type`.
- `export_service.dart` reads the lesson's `assessment` field for CSV export; `exportLessonPdf` renders lesson sections — removing the `assessment` field needs a compatibility shim (derive a summary line from the new `questions` array).

### 2.5 Existing risk surface (carried over)

- **Implicit exam creation:** bulk lesson generation (`saveScheme`), the scheme save screen, and `_bootstrapSchemeDrafts` all auto-create draft exams the teacher never asked for (audited in `plans/exams_generation_redesign.md`, which recommends removing all three).
- **Orphaned links:** exams carry `schemeOfWorkId`; plan regeneration/deletion can strand links (the repo has shipped one repair script already: `supabase/scripts/restore_orphaned_scheme_links.sql`).
- **Duplicate engines:** question-generation logic (type selection, counts, validation, difficulty) is duplicated between the exam editor and the full-term screen.

---

## 3. Shared design requirements

These apply to every design below:

1. **One question engine, one source of truth.** Question types (MCQ/Theory/Subjective) + per-type counts, difficulty (Easy/Medium/Hard), cognitive objectives (Bloom's levels), and assessment format collapse into a single reusable widget. The old "Assessment Format (MCQ/Theory/Both)" dropdown is *subsumed* by the question-type multi-select (they are the same choice; the "Both" case is just MCQ+Theory selected).
2. **Exam editor supports two compilation types:** **Term Exam** (all topics of the term — defaults to "everything") and **CA Test** (a few topics — explicit topic picker).
3. **Topic selection** uses the scheme-of-work topics (the list the teacher already knows), with a manual "type a topic" fallback, exactly like today's dropdowns.
4. **IQ-60 rule:** one visible decision per screen; big labels; checkboxes with plain words; a single primary action button at the bottom; no cascading menus.
5. **Tap counting convention** (used in the comparison table): each screen navigation, button press, dropdown selection, or checkbox tick counts as 1 tap. Typing a topic and AI wait time are noted separately but not counted.

---

## 4. Design A — Embedded Engine (the user's idea, refined)

### 4.1 What it is

The lesson editor's config column keeps Subject/Class/Week/Topic exactly as today, then replaces the "Generation Parameters" card (difficulty + Bloom's + Assessment Format) with a collapsible **"Assessment and Homework"** section containing the full question engine:

- **Include assessment** toggle (default **ON** for new lessons) — the only on/off decision the teacher ever faces.
- **Question types** (MCQ / Theory / Subjective chips) with per-type counts (defaults: 5/5/0).
- **Difficulty** (Easy/Medium/Hard segmented).
- **Cognitive objectives** (Bloom's chips).
- **Homework** toggle + optional homework-text field (reuses today's homework section).

The single button becomes **"Generate Lesson + Assessment"**. One generation call returns the lesson note *plus* a `questions` array; the lesson preview shows the Objectives→Presentation cards, then the assessment as **editable question cards** (same card UI as the exam editor), then Homework as text. The lesson's `content` JSON gains `"questions": {mcqs, theory, subjective}` and keeps `"homework"`; the free-text `"assessment"` field is dropped (export shim derives a summary). **No separate exam row is created.**

The exam editor is redesigned: its config opens with **"What are you making?"** — two large choice cards:

- **Term Exam** — after subject/class (term auto-derived from the scheme/current term), the topic list auto-loads **all term topics** with per-topic question counts (the existing `FullTermExamScreen` list, moved in). Teacher just taps **Generate**.
- **CA Test** — the same topic list appears as a **multi-select checkbox list** ("tick the topics you taught"); un-ticked topics contribute nothing. Default = the most recent few topics, so a CA test is one tap from correct.

The standalone `/full-term-exam` route is removed; its screen becomes the Term Exam mode inside the editor.

### 4.2 Task walkthroughs

**a) Create a lesson with assessment — 5–6 taps (+ typing topic, + 1 AI wait):**
1. Lessons tab → New Lesson (`/lesson-editor`). *(1)*
2. Pick Subject, Class. *(2)*
3. Pick topic from the scheme dropdown (or type it). *(1)*
4. Tap **Generate Lesson + Assessment** (engine defaults: MCQ+Theory, Medium, all Bloom's, assessment on). *(1)*
5. Tap **Unlock** when the preview is ready. *(1)*

**b) Create a term exam from all term topics — 4 taps (+ 1 AI wait):**
1. Exams tab → New Exam. *(1)*
2. Tap **Term Exam**. *(1)* — subject/class carried from list filters; all term topics auto-selected.
3. Tap **Generate**. *(1)*
4. Tap **Unlock**. *(1)*

**c) Create a CA test from a few topics — 6–7 taps (+ typing, + 1 AI wait):**
1. Exams tab → New Exam. *(1)*
2. Tap **CA Test**. *(1)*
3. Tick 2–3 topics ("Topics I taught"). *(2–3)*
4. Tap **Generate**. *(1)*
5. Tap **Unlock**. *(1)*

### 4.3 Assessment criteria

- **Accidental assessments / mixed content:** **Low.** Assessment is bundled with lesson generation by design (the user's explicit requirement), and the "Include assessment" toggle is OFF for regenerations of existing lessons, so a teacher editing a lesson never silently changes questions. Because the questions live *inside* the lesson row, there is no lesson/exam row-mixing. Compilation exams are always explicit (New Exam → Term/CA → Generate).
- **Subscription gating:** the whole "Assessment and Homework" section renders **locked** when the tier is not in `assessment_generation_allowed_tiers` (default `["standard","elite"]`): lock icon + **"Upgrade to Standard/Elite to generate assessment"** + an Upgrade button (admin → `/payment`; teacher → upgrade-request dialog). The lesson itself still generates on basic. The exam editor shows the same banner and disables Generate.
- **Orphan / duplication risk:** **Medium-low.** Lesson questions can't orphan (they are in the lesson row). Compilation exams are independent rows — deleting a lesson or scheme never breaks them (copies, not links), but a regenerated plan re-runs AI so a term exam's questions may diverge from the per-lesson assessments (acceptable: they are different exams). Engine code is written once as a shared widget and used by both editors.
- **IQ-60 clarity:** **Excellent.** "One button makes the lesson and its questions." The only extra decision is the CA topic checkboxes, which mirror "topics I taught so far."

---

## 5. Design B — Reuse Generated Assessments (compile from the question bank)

### 5.1 What it is

Same lesson-editor embedding as A, but the generated questions are **not** stored inside the lesson JSON — generation writes **two rows atomically**: the lesson *and* a linked exam row (a new `lesson_id` column on `exams`, type `lesson-assessment`). Compilation exams (**Term Exam / CA Test**) then **compile by copying questions from the linked assessment rows** — **no AI call at all** (optionally an AI "re-mix" pass for a fresh ordering/wordings).

### 5.2 Task walkthroughs

Same tap counts as A for all three tasks (a: 5–6, b: 4, c: 6–7), but the term-exam/CA "Generate" step is instant (0 AI waits) because it copies saved questions.

### 5.3 Assessment criteria

- **Accidental / mixed content:** **Low**, but with a new structural wrinkle: every generated lesson now *also* creates an exam row — the "mixed lesson/exam content" concern is built into the data model. Teacher sees assessment questions in both the lesson editor and the exams list, which can read as duplication.
- **Gating:** identical to A (locked section + banner).
- **Orphan / duplication risk:** **Medium.** The linked assessment row orphans if the lesson is deleted (or the link breaks in sync); compilation exams **copy** questions so a later edit to the source lesson does **not** propagate (divergence), or if they link instead of copy, deletion of the source breaks the compiled exam. Two-row transactions and link lifecycle handling add real engineering risk.
- **IQ-60 clarity:** **Excellent** — "Your term exam is built from the questions you already made" is the most intuitive mental model. But the exams list suddenly contains ~13 auto-created "lesson assessment" rows that the teacher must distinguish from real exams.

---

## 6. Design C — Guided Wizard Flow

### 6.1 What it is

Same engine as A, but generation is a **two-step wizard** instead of one long form:

- **Step 1 (Lesson):** subject, class, week, topic. → **Next**.
- **Step 2 (Assessment and Homework):** the engine, or a big **"No assessment"** card. → **Generate**.

The exam editor opens on a full-screen **"What do you want to make?"** picker with two large illustrated cards (Term Exam / CA Test), then the topic checklist, then Generate. Every screen shows exactly one decision.

### 6.2 Task walkthroughs

- **a) Lesson with assessment — 7 taps:** nav (1) + step 1 fields (3) + Next (1) + step 2 Generate (1) + Unlock (1).
- **b) Term exam — 4 taps:** New Exam (1) + Term Exam (1) + Generate (1) + Unlock (1).
- **c) CA test — 6–7 taps:** New Exam (1) + CA Test (1) + tick 2–3 (2–3) + Generate (1) + Unlock (1).

### 6.3 Assessment criteria

- **Accidental / mixed content:** **Lowest** — every decision is explicit on its own screen.
- **Gating:** locked step 2 card with the upgrade message; Generate disabled in the exam editor.
- **Orphan / duplication risk:** same as A (Medium-low).
- **IQ-60 clarity:** **Excellent** (one decision per screen), but the wizard adds a **Next** tap to every flow and forces the teacher to *finish step 1 before* reaching the engine, which punishes teachers who mostly accept defaults. More taps and more navigation than A for the same outcome.

---

## 7. Design D — Plan-First Bulk Generation

### 7.1 What it is

Generation is driven from the **Scheme of Work** screen, not the editors:

- The plan screen gains **"Generate all lessons (with assessments)"** (bulk) and **"Generate Term Exam"** buttons.
- The lesson editor keeps the A-style engine section for single-lesson regeneration.
- **CA tests** are created from the **Lessons list** via multi-select: tick 2–3 lessons → "Make CA Test" → generate from those topics.

### 7.2 Task walkthroughs

- **a) Lesson with assessment (single):** 5–6 taps, same as A. **(Bulk, all 13):** Plan tab → Generate all lessons (1) → confirm (1) = 2 taps + one long AI wait.
- **b) Term exam — 2 taps:** Plan tab → **Generate Term Exam** (1) → confirm (1).
- **c) CA test — 6–7 taps:** Lessons tab → tick 2–3 lessons (2–3) → Make CA Test (1) → Generate (1) → Unlock (1), plus nav (1).

### 7.3 Assessment criteria

- **Accidental / mixed content:** **Low-Medium** — bulk "generate all lessons" auto-creates 13 assessments (intended but sweeping), and the entry point for term exams moves to the plan screen, where teachers may not expect it.
- **Gating:** locked engine section in the lesson editor; disabled buttons with the upgrade message on plan/lessons screens.
- **Orphan / duplication risk:** **Medium** — bulk generation reproduces today's plan↔lesson↔exam link mechanics, including the orphan surface (`saveScheme` cleanup exists but is more code to maintain).
- **IQ-60 clarity:** **Good for bulk, confusing for single.** "Exams come from my plan" is a new mental model on top of "exams come from the Exams tab"; a low-literacy user will look for Term Exam inside the Exams app and not find it.

---

## 8. Design E — Minimal Change Baseline (for contrast)

### 8.1 What it is

Keep the current architecture: lesson editor keeps its free-text Assessment/Homework sections; the question engine stays only in the exam editor; the exam editor gains the two compilation modes (Term/CA) with topic multi-select; the full-term screen is folded into the editor. No lesson+assessment bundling, no merged engine.

### 8.2 Task walkthroughs

- **a) Lesson with assessment — 14–15 taps across two flows:** Lessons → New Lesson → fields (3) → Generate (1) → Unlock (1); then Exams → New Exam → fields (3) → engine (2) → Generate (1) → Unlock (1). Two AI waits.
- **b) Term exam — 4 taps** (as A).
- **c) CA test — 6–7 taps** (as A).

### 8.3 Assessment criteria

- **Accidental / mixed content:** **Low** (no bundling) — that is its only virtue.
- **Gating:** unchanged (exam editor upgrade dialog only).
- **Orphan / duplication risk:** **Medium** (today's links unchanged).
- **IQ-60 clarity:** **Poor** — the teacher must learn two separate apps to do one conceptual thing ("a lesson and its questions"), and must re-enter subject/class/topic in the second flow.

---

## 9. Comparison table

Tap counts use the §3.5 convention (typing and AI waits excluded).

| Design | Taps (lesson + assessment) | Taps (term exam) | Taps (CA test) | Accidental generation risk | IQ‑60 clarity | Simplicity (1–10) | Overall (1–10) |
|---|---|---|---|---|---|---|---|
| **A — Embedded Engine (user's idea)** | 5–6 | 4 | 6–7 | Low (intended bundling, toggle off on edit) | Excellent | 9 | **9** |
| **B — Reuse Generated Assessments** | 5–6 | 4 (0 AI waits) | 6–7 (0 AI waits) | Low, but every lesson spawns an exam row | Excellent | 7 | 8 |
| **C — Guided Wizard** | 7 | 4 | 6–7 | Lowest (explicit per screen) | Excellent | 7 | 7 |
| **D — Plan-First Bulk** | 5–6 (single) / 2 (bulk) | 2 | 6–7 | Low-Med (13 assessments from one button) | Good | 7 | 7 |
| **E — Minimal Change (baseline)** | 14–15 (two flows) | 4 | 6–7 | Low | Poor | 6 | 5 |

---

## 10. Recommendation

**Design A — the user's idea, refined.** It is the only design that simultaneously:

1. **Meets the one-click requirement.** Lesson + questions in a single "Generate Lesson + Assessment" action on the screen the teacher already uses for lessons. No second flow, no re-entering subject/class/topic (the exact failing of E).
2. **Keeps the fewest taps.** Tied for the lowest tap counts on all three tasks (A and B tie; B only wins by removing AI waits, at the cost of a far riskier data model).
3. **Avoids the accidental-generation and orphan traps.** Questions live *inside* the lesson row (no orphanable link, no surprise exam rows polluting the Exams list — the main strike against B), and compilation exams are explicit, standalone rows that copy rather than link (nothing can orphan them). The "Include assessment" toggle defaults ON for new lessons (per the requirement) but OFF when editing an existing lesson, so regeneration never silently changes questions.
4. **Is the clearest for an IQ-60 user.** One button, one screen; the CA topic checkboxes mirror the teacher's own phrase "topics I taught so far"; Term Exam needs zero decisions (all topics, Generate).
5. **Is cheapest to build safely.** Reuses the exam editor's validated question pipeline, the full-term screen's topic-count list (moved into Term Exam mode), and one shared engine widget. B's two-row transactions and link lifecycle add risk without a tap-count win.

**Refinements applied to the raw user idea:**

- **Topic picker:** CA Test uses a checkbox multi-select of scheme topics (required by the brief); Term Exam defaults to "all topics" with per-topic counts so nothing is ever generated without the teacher seeing what will be included.
- **Gating copy + policy:** a new config key `assessment_generation_allowed_tiers` (default `["standard","elite"]`) drives both the locked-section message ("Upgrade to Standard/Elite to generate assessment") and the exam editor's banner, keeping basic-tier lesson generation working.
- **Kill the implicit paths:** remove the exam-creation side effects in `saveScheme`, the scheme save screen, and `_bootstrapSchemeDrafts` (already recommended by `plans/exams_generation_redesign.md`) so exams are only ever created by New Exam / Term Exam / CA Test. This is what guarantees "no accidental assessments."
- **One engine widget:** extract the engine (type chips, counts, difficulty, Bloom's) into a shared widget used by both the lesson editor section and the exam editor, so the two never drift.

**Fallback note:** if product later decides a term exam must contain *exactly* the questions from the per-lesson assessments (no AI re-run), Design B's compile-from-saved-questions can be layered onto A as an optional "Use my saved questions" mode — but it should not be the default, because row-linking is exactly the orphan/duplication surface this redesign is meant to retire.

---

## 11. Risks and implementation notes (when approved)

1. **Prompt changes.** `lessonNote` must accept a `questions` spec (types/counts/difficulty/blooms) and emit a `questions` array; the old `assessment` free-text field disappears. `examQuestions` already supports the multi-topic form used by full-term exams and can be reused for both compilation modes.
2. **Export compatibility.** `export_service.dart` (CSV) and `exportLessonPdf` read the lesson's `assessment` text; add a shim that derives a summary line ("5 MCQ + 3 Theory questions") from `content.questions` until exports are updated to render question cards.
3. **Schema.** `exams` gains a nullable `compilation_type` (`term` | `ca`) and the topic list is persisted in `content` (e.g. `"topics": [{week, topic, count}]`) so a compiled exam can be re-opened and edited without re-deriving topics. No new tables for A.
4. **Regeneration semantics.** Term/CA generation should adopt-in-place (find existing compilation exam for subject/class/term and refresh) rather than duplicate, mirroring `_hasDuplicateLessonForGeneration`.
5. **Storage quotas.** 13-term compilation creates one row, not 13 — a quota improvement over today's implicit per-week drafts, but the CA path still needs the existing storage-limit guard.
6. **Migration of existing data.** Existing lessons keep their `assessment` text in content (read-only legacy field); existing exams are untouched; `/full-term-exam` redirects to `/exam-editor` (Term Exam mode).
7. **Tests.** `test/features/lesson_editor_test.dart` and related widget tests assert the old config fields; they must be updated to the engine section, and new tests should cover the locked-section copy per tier and the CA topic-selection validation (at least one topic).

---

## 12. Appendix — key code references

| Concern | Location |
|---|---|
| Lesson editor config (difficulty, Bloom's, Assessment Format) | `lib/features/lesson/screens/lesson_editor_screen.dart` (`_ConfigColumn` ~line 2440; decorative `_assessmentFormat` ~line 69, unused in `_handleGenerate` ~line 643) |
| Lesson preview Assessment/Homework cards | `lesson_editor_screen.dart` (~line 3022) |
| Exam engine (types/counts/difficulty, 3 prompts, validation) | `lib/features/exam/screens/exam_editor_screen.dart` (`_handleGenerate` ~line 600; `_ConfigColumn` ~line 1478) |
| Exam tier gate | `exam_editor_screen.dart` ~line 649 (`examGenerationAllowedTiers` → upgrade dialog); `full_term_exam_screen.dart` ~line 163 (toast) |
| Lesson tier gate | `lesson_editor_screen.dart` ~line 625 (`authTier == 'free'`) |
| Full-term exam builder (topic list + counts + combined prompt) | `lib/features/exam/screens/full_term_exam_screen.dart` (`_generateExam` ~line 156) |
| Exams list + silent draft seeding | `lib/features/exam/screens/exams_list_screen.dart` (`_bootstrapSchemeDrafts` ~line 100; New Exam FAB → `/exam-editor`) |
| Prompts | `lib/core/constants/prompt_templates.dart` (`lessonNote`, `examQuestions`, `mcqs`, `theoryQuestions`, `subjectiveQuestions`) |
| Remote config (tiers) | `lib/core/services/config_service.dart` (`examGenerationAllowedTiers`); seed `supabase/migrations/20260716_000002_seed_exam_and_sync_config.sql` |
| Tables | `lib/core/database/tables/exams.dart`, `tables/lessons.dart` |
| Implicit exam creation (to remove) | `lib/core/services/scheme_of_work_service.dart` `saveScheme` (~line 195); `scheme_of_work_screen.dart` (~line 677); `exams_list_screen.dart` `_bootstrapSchemeDrafts` |
| Orphan history | `supabase/scripts/restore_orphaned_scheme_links.sql` |
| Prior audit | `plans/exams_generation_redesign.md` |
| Export reads `assessment` field | `lib/core/services/export_service.dart`; `lib/features/lesson/screens/lessons_list_screen.dart` (`exportLessonPdf`) |
