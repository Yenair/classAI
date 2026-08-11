# Scheme of Work UX Redesign — Design Proposal

**Date:** 2026-08-11
**Status:** Proposal only — no code changes.
**Target user:** Average Nigerian teacher, very low technical literacy (assume IQ 60). Flow must be nearly impossible to get wrong.

---

## 1. Executive summary

The current Scheme of Work (SoW) feature forces a teacher through a dedicated,
form-heavy screen (subject / class / term pickers → AI generate → review 13 rows →
save → optional approval) *before* they can write a single lesson. The data model is
healthy and widely used; the *flow* is the problem.

This report audits the current flow end-to-end, proposes four alternative designs
(A: the user's "Auto Generate" button; B: inline scheme editing in the lesson
editor; C: a radically simplified single-page scheme editor; D: a bold variant that
hides the "scheme" concept from teachers entirely), rates them, and recommends
**Design A refined with a piece of D**: an "Auto Generate" button on the Lessons
List screen that creates the term plan (scheme rows + linked draft lessons) in one
action. The dedicated SoW screen survives, but only as an admin review tool.

---

## 2. Audit of the current creation & linking flow

### 2.1 Where the teacher starts

- Teacher opens the app → **Dashboard** (Home tab).
- Navigation (mobile): bottom bar with 5 tabs — Home, Lessons, Exams,
  **Scheme of Work**, More. Desktop: sidebar with the same items
  (`dashboard_screen.dart:183`).
- The "Scheme of Work" tab does `context.go('/scheme-of-work')` — it is a **full
  screen route**, not a tab panel. The bottom bar disappears; the teacher must use
  the system back gesture to return. This is the first get-lost trap.

### 2.2 Creating a new scheme (the dedicated screen)

`lib/features/scheme_of_work/screens/scheme_of_work_screen.dart`
(1,864 lines — itself a complexity signal):

1. **Subject** dropdown — 36 NERDC subjects, defaults to *Mathematics*.
2. **Class Level** dropdown — 12 options (JSS/SSS/Primary), defaults *JSS 1*.
3. **Term** dropdown — First/Second/Third, defaults *First*.
4. **Generate Scheme** button → AI call (`PromptTemplates.schemeOfWork`, hard-coded
   to **exactly 13 weeks**) → 13 week rows appear, each with an editable **topic**
   text field and an **objectives** text field. There is no add/remove-week UI.
5. **Save Scheme** button → writes **one `scheme_of_work` row per week**
   (status `draft`) **and silently auto-creates a linked draft lesson and draft
   exam for every week** (`_saveScheme`, ~line 502–690).
6. **Submit for Approval** button → status `pending` → an admin must approve each
   week before it becomes `approved`. Admins can edit topics (`admin_edited_topic`)
   and reject.

Decisions required: subject, class, term, review of up to 13 rows, whether to
submit for approval. Confusingly, "Submit for Approval" is *optional* for lesson
creation (drafts are already usable), but nothing explains that.

### 2.3 Populating topics

Topics come **only from AI generation** — 13 at once. The teacher can edit the
generated topic text per week, but cannot add extra weeks or reorder. (Server-side
there is a `scheme_generation_queue` table that nothing writes to — dead
infrastructure, `lib/core/database/tables/scheme_generation_queue.dart`.)

### 2.4 Linking a lesson to a topic later

1. **Lessons** tab → **New Lesson** → `LessonEditorScreen` (`/lesson-editor`).
2. "Curriculum Context" card → Subject + Class dropdowns.
3. **Topics** dropdown → items: "✏️ Write a new topic" plus every saved scheme
   week for that subject (`getSavedBySubject`, excludes only `rejected`).
4. Selecting a scheme topic auto-fills the topic field and remembers the link
   (`schemeOfWorkId` = the week's row id). A "Linked to Scheme of Work" banner
   appears.
5. Save persists the link.

**Nuance:** the Lessons List silently *pre-seeds* draft lessons for saved schemes
(`_bootstrapSchemeDrafts` in `lessons_list_screen.dart`) — so linked draft lessons
often appear "out of nowhere" without the teacher doing anything. This existing
behavior is a half-finished version of the auto-generate idea and should be
replaced by an explicit flow.

### 2.5 What happens if no scheme exists yet

The dropdown hint reads **"No approved scheme of work"** — but the query actually
includes drafts and pending rows, so the hint is wrong. The teacher can always pick
"✏️ Write a new topic", which saves the lesson with **no scheme link, silently**.
No error, no guidance. A teacher with no scheme gets an unlinked lesson and never
knows anything was missing.

Other failure modes observed:
- If a scheme row is deleted, linked lessons show a "linked scheme of work is no
  longer available" banner (`_LinkedSchemeBanner`) — handled gracefully, but it
  exists because broken links are a real occurrence.
- Admins are blocked from editing/deleting schemes that lessons/exams reference
  ("Scheme in Use" dialog).
- **Pre-existing sync gap (out of scope but relevant):** Flutter queues
  `scheme_of_work` sync entries, but the `sync-push` Edge Function has no
  `scheme_of_work` handler and the server schema is missing columns the push code
  assumes (`status`, `teacher_id`) — per `plans/sync_pipeline_audit_report.md` and
  `plans/schema_coverage_audit_report.md`. SoW changes stay local-only today.
  Auto-generation will create *more* schemes and make this gap more visible.

### 2.6 Tap / screen / decision count for the typical task

Task: *"Create a scheme of work for ~10 weeks and start writing the first lesson."*

| Step | Taps |
|---|---|
| Tap "Scheme of Work" tab | 1 |
| (Optional) adjust Subject / Class / Term | 0–6 |
| Tap **Generate Scheme** (AI wait ~30–60 s) | 1 |
| (Optional) review/edit week topics | 0–13+ |
| Tap **Save Scheme** | 1 |
| Navigate back → Lessons tab → New Lesson (or tap a pre-seeded draft) | 2–3 |
| Pick topic in Topics dropdown (if not pre-filled) | 1–2 |
| Generate lesson content (AI wait) | 1 |
| Tap Save | 1 |

**Totals (current):** ≈ **9–13 taps**, **4 screens**, **2 AI waits**,
**3–6 decisions** (subject, class, term, review rows, approval, topic pick).
**Points of confusion:** 5 (see §2.7).

### 2.7 Confusion points

1. "Scheme of Work" is a full-screen route — the bottom bar vanishes; returning needs a back gesture.
2. "Submit for Approval" — optional but unexplained; statuses (draft/pending/approved) are invisible to the teacher.
3. 13 pre-filled rows to review feels like homework before any payoff.
4. The misleading "No approved scheme of work" hint (drafts *are* shown).
5. Lessons silently pre-seeded from schemes — teacher can't tell what created them.

---

## 3. Alternative designs

All designs assume we keep the underlying data model (one `scheme_of_work` row per
week; lessons link via `schemeOfWorkId`), because it already powers the dashboard
"current week" widget, full-term exams, list filters, and PDFs.

### Design A — "Auto Generate" button on the Lessons List screen (user's idea)

**How it works:**

- On the **Lessons List** screen (where the teacher already lives), a prominent
  **"Auto Generate"** button (extended FAB / header action) sits next to "New Lesson".
- Tapping it shows **one simple dialog**: "Plan for: [Mathematics] [JSS 1] [1st Term] —
  Create 13 weekly lessons?" with a single **Create** button. The three values
  pre-fill from the screen's existing Term/Class/Subject **filters** (already on
  that screen) or last-used values; the teacher only confirms.
- One AI call generates 13 weeks (topic + objectives). For each week the app
  writes the `scheme_of_work` row **and** the linked draft lesson in the **same
  transaction** (this is exactly what `_saveScheme` + `_bootstrapSchemeDrafts` do
  today, but explicit, visible, and immediate).
- Result: the Lessons list fills with 13 draft cards, each labeled
  "Week 1 — <topic>". **Writing the first lesson = tapping the Week-1 card.** No
  linking step exists anywhere; the link is created for free.
- Editing a lesson: the topic field is free to edit; the scheme link remains
  untouched (the scheme week topic and the lesson topic are independent, as today).
  If the teacher edits the topic before generating content, we keep the lesson
  topic as-is and do **not** rewrite the scheme week — no surprise mutations.
- Statuses: rows are created as `draft` — usable immediately, exactly like today
  (the lesson-editor picker already shows drafts). Admin approval stays a
  separate, admin-only concern.
- A "Regenerate" option can replace the plan if the teacher mistypes the subject
  (with a confirm dialog, since old draft lessons would be deleted).

**Tap count for the typical task:** 1 (Auto Generate) + 1 (confirm Create) + 1
(tap Week-1 lesson) + 1 (generate content) + 1 (save) = **~5–6 taps**, **1–2
screens**, **2 AI waits** (or 1 if lesson content is also pre-seeded — see §3.5).

**Data it needs:** subject, class, term (all pre-fillable from existing filters /
last-used). Nothing else. Teacher identity and school resolve from auth state.

### Design B — Inline scheme editing from the lesson editor's topic picker (original Task 5)

**How it works:**

- In the lesson editor's **Topics** dropdown, add a "+ New topic in my plan" row.
- Tapping it opens an inline form: one text field ("Topic for week 2?") and a
  **Save** button. Saving writes a scheme row (subject/class/term inherited from
  the editor's own Curriculum Context card — no separate pickers) and links the
  lesson immediately.
- A small "Plan" strip under the dropdown shows the growing week list
  (Week 1: …, Week 2: …) with delete (✕) per week; the teacher can also tap a week
  to jump the lesson to it.

**Tap count for the typical task (10 weeks):** New Lesson (2) + add topic ×10
(≈2 taps + typing each) + generate content (1) + save (1) ≈ **25+ taps** — terrible
for bulk planning, but **excellent for a single lesson** (~5 taps, zero new
screens). It is the best *complement* design, not a standalone one.

### Design C — Radically simplified dedicated screen ("weeks list")

**How it works:**

- From the lesson editor ("Plan my term" button) or Lessons list, open a **single
  page**: a numbered list of weeks 1–13, each with **one topic text field** and a
  big **"Save & Use"** button.
- Subject/class/term are **inherited** from wherever the teacher came from — no
  pickers on the page at all.
- "Save & Use" writes the scheme rows + linked draft lessons and returns the
  teacher to their lesson with Week 1 selected.
- Optionally a "Fill with AI" button that pre-fills all 13 topic fields (making it
  a 3-step flow), falling back to manual typing if the teacher prefers (offline-
  friendly).

**Tap count:** open (1) + [AI fill (1)] + Save & Use (1) + generate content (1) +
save (1) ≈ **5–6 taps**, **2 screens**, 1–2 AI waits. Still a *separate screen*
(the thing the user wants removed), but a single-purpose, unmissable one.

### Design D — "The lessons list IS the plan" (my idea)

**How it works:**

- On first use, the Lessons list offers **"Start Term Plan"** — one tap, defaults
  confirmed (as in A). The app generates 13 weeks and the list simply *becomes*
  the plan: Week 1 … Week 13 cards, each an editable lesson.
- The word **"Scheme of Work" disappears from the teacher-facing UI**. Week topics
  are edited by editing the lesson card's topic; the underlying scheme rows are
  updated in the background (single source of truth = the lesson; scheme row is a
  mirror). No separate screen, no "linking" concept, no statuses, no approval
  vocabulary.
- Admins still get a review surface (the existing screen, teacher-side UI hidden).
- Trade-off: it inverts the current data relationship (lesson is primary, scheme
  mirrors it), which is the most invasive change of the four — sync, dashboard
  "current week" logic, full-term exam topic source, and PDF attribution all read
  scheme rows today.

**Tap count:** 1 (Start Plan) + 1 (confirm) + 1 (tap Week 1) + 1 (generate) + 1
(save) = **5 taps**, **1 screen**, 1–2 AI waits. The fewest taps and **zero
concepts to learn** — the strongest fit for an IQ-60 user, at the highest build cost.

---

## 4. Comparison table

Typical task: *create a ~10-week scheme and start writing the first lesson*.
"Tap" = any distinct interaction (open dropdown + pick = 2; typing not counted).

| Design | Taps (approx) | Screens visited | Can the teacher get lost? | Risk of orphaned/broken links | Understandable by IQ 60? | Simplicity (1–10) |
|---|---|---|---|---|---|---|
| **Current** | 9–13 | 4 (Dashboard → SoW → Lessons → Editor) | **Yes** — bottom bar vanishes on the SoW screen; optional-but-unexplained approval; misleading "no approved scheme" hint; silently pre-seeded drafts | **Medium** — unlinked lessons are saved silently via "Write a new topic"; deleted schemes strand lessons (banner shows) | **No** — form fields, statuses, a separate linking step, and jargon | 3 |
| **A — Auto Generate on Lessons List** | 5–6 | 1–2 (Lessons → Editor) | **No** — one button, one confirm; result is visible immediately in the list they already understand | **Low** — scheme rows + lesson links written in the same transaction; nothing to forget | **Yes** — "press the big button, tap your week" | 9 |
| **B — Inline scheme editing in topic picker** | ~25 (bulk) / ~5 (single lesson) | 1 | **No** for single lessons; **Yes** for bulk — 10+ repetitive add-topic cycles | **Low** — link written at the moment the topic is created | **Partial** — great for one lesson, exhausting for planning a term | 6 |
| **C — Simplified weeks-list screen** | 5–6 | 2 | **Mostly no** — single-purpose page, but still a separate screen to find and leave | **Low** — inherited context, single save | **Yes** — "type topics or fill with AI, tap Save & Use" | 7 |
| **D — Lessons list IS the plan** | 5 | 1 | **No** — there is nothing else to navigate to | **Very low** — one source of truth; no link to break | **Yes** — the concept "scheme of work" never needs to be learned | 9.5 (best UX, highest build risk) |

---

## 5. Recommendation

**Design A ("Auto Generate" on the Lessons List), refined with one idea from D:
don't make the teacher review or save anything after generation — the 13 linked
draft lessons simply appear in the list.**

Why A over the others:

1. **It attacks the actual pain.** The audit shows the pain is not the data model
   or the linking — it's that the current flow front-loads a form-heavy, jargon-heavy
   screen before any payoff. A removes that screen from the teacher's path entirely
   and makes the payoff (13 lesson cards) the immediate, visible result.
2. **Lowest risk while still being a big win.** Unlike D, A keeps the existing data
   relationship (scheme row = primary, lesson links to it) — so the dashboard
   "current week" widget, full-term exams, list filters, PDF attribution, and admin
   approval keep working with **zero migration**.
3. **It reuses code that already exists.** `_saveScheme` already writes scheme rows
   + linked draft lessons in one go; `_bootstrapSchemeDrafts` already seeds drafts
   from schemes. Design A makes that machinery explicit, visible, and triggered by
   one button instead of hiding it.
4. **B is kept as a bolt-on, not the main flow.** Inline topic creation in the
   lesson editor is still valuable for teachers who want to deviate from the
   generated plan (add a week, change a topic) — but it is terrible for the
   10-week bulk task, so it should be an *extension* of A, not a replacement.
5. **Fits the IQ-60 constraint.** The entire teacher journey reduces to:
   *"Press Auto Generate. Confirm. Tap your week. Write your lesson."* Four actions,
   zero scheme vocabulary, zero linking decisions, immediate visible feedback.

Implementation shape (for when this is approved): a new button + one
confirmation/brief dialog on `LessonsListScreen`; a shared service that runs the
existing AI generation, then the existing scheme-row + draft-lesson creation in a
single DB transaction; remove/replace the silent `_bootstrapSchemeDrafts`
seeding so there is exactly one explicit path to creating drafts. The
"Scheme of Work" tab remains but is **admin-only** (or reachable via a small
"Plan details" link), removing the teacher-facing form.

### 5.1 Does the recommended design remove the existing screen?

Partially. The teacher-facing creation form goes away; the screen survives as the
**admin review/approval surface** (admins still filter by teacher/subject/term and
approve/reject weeks — that capability is load-bearing for the product's admin
workflow and should not be deleted).

If a later decision removes it entirely for teachers: **no migration or data loss
risk** — existing `scheme_of_work` rows and lesson/exam links are untouched by
removing a screen. What *would* break is only the **approval gate** (there'd be no
place for admins to approve/reject), so either keep the screen for admins
(recommended) or explicitly drop the approval workflow and treat all schemes as
approved.

### 5.2 Data-loss risks to flag

1. **Regenerate/delete-whole-plan must confirm** — deleting a generated plan
   removes scheme rows and their linked draft lessons. Confirm dialogs + a "keep
   lessons" option (unlink instead of delete) are required.
2. **Pre-existing sync gap will surface:** `scheme_of_work` is queued locally but
   the server push path is broken (no handler in `sync-push`, missing server
   columns `status`/`teacher_id`). Auto-generation multiplies scheme rows, so this
   gap must be fixed as part of the implementation, or teachers will see SoW data
   vanish/desync across devices. See `plans/sync_pipeline_audit_report.md` and
   `plans/schema_coverage_audit_report.md`.
3. **The "Scheme in Use" admin block** already prevents deleting referenced
   schemes — keep that guard so the new auto-created links are never orphaned by
   admin actions.
4. **Orphaned-link history:** the repo contains a real past incident of orphaned
   `scheme_of_work_id` values (`supabase/scripts/restore_orphaned_scheme_links.sql`).
   The new flow's same-transaction creation inherently avoids this class of bug;
   do not reintroduce separate "create scheme" / "link lesson" steps.

---

## 6. Appendix — key code references

| Concern | Location |
|---|---|
| SoW creation screen (subject/class/term, generate, save, approval) | `lib/features/scheme_of_work/screens/scheme_of_work_screen.dart` |
| AI prompt (13 weeks, JSON) | `lib/core/constants/prompt_templates.dart` (`schemeOfWork`) |
| Scheme rows + linked draft lessons/exams written in one save | `_saveScheme` / `_adminApprove` in the screen above |
| Silent draft seeding on Lessons list | `_bootstrapSchemeDrafts` in `lib/features/lesson/screens/lessons_list_screen.dart` |
| Lesson-editor Topics dropdown + link + banner | `lesson_editor_screen.dart` (`_onSchemeOfWorkSelected`, `_LinkedSchemeBanner`, `_ConfigColumn`) |
| Same picker in exam editor | `exam_editor_screen.dart` |
| Scheme consumers (dashboard widget, full-term exam, filters) | `dashboard_screen.dart:1742`, `full_term_exam_screen.dart`, `lessons_list_screen.dart`, `exams_list_screen.dart` |
| Scheme DAO (`getSavedBySubject` includes drafts) | `lib/core/database/daos/scheme_of_work_dao.dart` |
| Route registration | `lib/router/app_router.dart` (`/scheme-of-work`) |
| Known sync gaps for `scheme_of_work` | `plans/sync_pipeline_audit_report.md`, `plans/schema_coverage_audit_report.md` |
