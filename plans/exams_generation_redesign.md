# Exams-Generation Flow Redesign — Design Proposal

**Date:** 2026-08-12
**Status:** Proposal only — no code changes.
**Target user:** Average Nigerian teacher, very low technical literacy (assume IQ 60). Flow must be nearly impossible to get wrong.

---

## 1. Executive summary

Today the teacher cannot create exams *intentionally*. "Bulk Generate" silently
creates **13 linked draft exams** as a side effect of generating 13 lessons, and
two other implicit paths (the scheme-of-work save screen and the exams list's
silent draft-seeding) create exams without the teacher asking. The only explicit
path — the "New Exam" button — builds one exam at a time.

This proposal audits every current exam-creation path, proposes four designs that
**separate exam generation from lesson generation** (A: a "Generate Exams"
button on the Exams List; B: an "Add Single Exam" flyout item plus a bulk button;
C: an opt-in "Also generate exams" checkbox; D: "Generate Exams from My Plan"),
rates them, and recommends **Design A, refined with D's plan-alignment idea**,
together with the mandatory removal of all implicit exam creation so there is
exactly one explicit path to creating exams.

---

## 2. Audit of the current exams-generation flow

### 2.1 Where the teacher starts

- Teacher opens the app → **Dashboard** (Home tab) → **Exams** tab
  (`context.go('/exams')`) → `ExamsListScreen`
  (`lib/features/exam/screens/exams_list_screen.dart`).
- The screen shows term/status/class/subject filters, a list of exam cards, and
  a **"New Exam"** extended FAB.

### 2.2 How exams are created today — four paths, three of them implicit

**Path 1 — Bulk Generate (lessons list, implicit).** `LessonsListScreen` →
"Create" flyout → "📋 Bulk Generate" → plan dialog (subject/class/term) →
`SchemeOfWorkService.saveScheme`
(`lib/core/services/scheme_of_work_service.dart`, ~line 195) writes **13 scheme
rows + 13 linked draft lessons + 13 linked draft exams** in one transaction.
The exam block is literally commented *"Auto-create draft exam if not already
existing"* — the teacher gets 13 exams whether they wanted them or not.

**Path 2 — Exams list silent seeding (implicit).** On opening `ExamsListScreen`,
`_bootstrapSchemeDrafts` (~line 100) scans saved schemes and **inserts missing
linked draft exams** for every scheme week. Exams appear "out of nowhere" the
first time the teacher opens the Exams tab after creating a plan.

**Path 3 — Scheme of Work screen save (implicit).** The admin/scheme screen's
save path (`lib/features/scheme_of_work/screens/scheme_of_work_screen.dart`,
~line 677) also auto-creates a linked draft exam per week with empty content.

**Path 4 — New Exam FAB (explicit, single).** `ExamsListScreen` → **"New Exam"**
FAB → `/exam-editor` (`exam_editor_screen.dart`). The editor opens with its
config form expanded; the teacher picks **subject** and **class**, then picks a
topic from the **Topics dropdown** (scheme topics) or types a new topic
(`_isManualTopicEntry`). **No linked scheme is required.** Generate content (AI)
→ unlock (online credits) → save.

### 2.3 How many taps from "I want an exam" to "a ready-to-edit exam"?

**Single exam (Path 4):**
| Step | Taps |
|---|---|
| Exams tab → New Exam FAB | 2 |
| Pick subject / class / topic (or type one) | 2–4 |
| Generate content (AI wait) | 1 |
| Unlock (online/offline credit) | 1 |
| Save | 1 |
| **Total (one exam)** | **≈ 7–9 taps + typing + 1–2 AI waits** |

**A full set of 13 exams:**
| Route | Taps | Side effects |
|---|---|---|
| New Exam ×13 (Path 4) | **≈ 90+ taps** | None — but no teacher will do this |
| Bulk Generate (Path 1) | **4 taps** (Create → Bulk Generate → dialog → confirm) | Also creates 13 lessons **and** 13 scheme rows |
| Open Exams tab with a saved plan (Path 2) | **1 tap** | Silent, invisible, unrequested |

So today the *only* way to get a full set of exams in reasonable time is to
generate lessons — exam creation is an unavoidable by-product of lesson
generation.

### 2.4 Screens involved

| Screen | Role in exam creation |
|---|---|
| `ExamsListScreen` | Lists exams; New Exam FAB; **silently seeds draft exams** |
| `ExamEditorScreen` | Creates/edits one exam (no scheme required) |
| `LessonsListScreen` | Bulk Generate entry point (creates exams implicitly) |
| `SchemeOfWorkScreen` | Saves schemes; **auto-creates exams per week** |
| `FullTermExamScreen` | Builds a single term-exam from scheme topics |

### 2.5 Risks in the current flow

1. **No intentionality.** The dominant bulk path couples lessons and exams; the
   teacher cannot say "lessons only".
2. **Silent creation.** Draft exams appear from `_bootstrapSchemeDrafts` and the
   scheme screen with empty content — teachers can't tell what created them.
3. **Orphan exposure.** Exams carry `schemeOfWorkId`; if a plan is regenerated or
   deleted, links can point at rows that no longer exist (the repo has already
   shipped an orphan-repair script once:
   `supabase/scripts/restore_orphaned_scheme_links.sql`; `saveScheme` includes
   orphan cleanup for lessons/exams on replace).
4. **Storage cost.** Unwanted draft exams consume the school's storage quota
   (`exam_editor_screen.dart` enforces a per-tier exam count).
5. **Confusion.** The Exams list conflates "Unlocked" and "Completed" filters —
   a sign the state model for exams is thinner than for lessons (no `status`
   column).

---

## 3. Alternative designs

### Design A — "Generate Exams" button on the Exams List screen

**How it works:**

- On the **Exams List** screen (where the teacher already lives), a prominent
  **"Generate Exams"** button sits next to "New Exam" (second FAB action or a
  full-width header button).
- Tapping it shows **one simple dialog**: "Plan for: [Mathematics] [JSS 1]
  [1st Term] — Generate 13 weekly exams?" with a single **Generate** button.
  The three values pre-fill from the screen's existing filters (or last-used
  values); the teacher only confirms.
- The dialog uses the **curated NERDC weekly topics** when available
  (`getNerdcTopics` — the same list bulk generate uses) and falls back to AI
  online otherwise. For each of the 13 weeks the app writes **one draft exam**
  (empty content, `isUnlocked: false`, `weekNumber` 1–13) **and nothing else**.
  Exams are linked to a scheme **only if** a matching scheme row already exists
  for that subject/class/term/week — otherwise they stand alone (unlinked, like
  "write a new topic" exams today).
- Result: the Exams list fills with 13 draft cards. **Writing an exam = tapping
  the card.** No lesson or scheme rows are touched.

**Plain-English flow:** *"Tap the Exams tab. Tap Generate Exams. Check the
subject, class and term. Tap Generate. Your 13 exams appear — tap one to write
it."*

**Tap count for 13 exams:** 2–8 (button 1 + confirm 1; +0–6 only if the teacher
changes subject/class/term in the dialog).

**Accidental exam creation:** **None.** Lessons generation (Bulk Generate)
creates lessons only; nothing on the lessons flow touches exams.

**Orphan risk:** **Low.** Exam ↔ scheme links are written in the same
transaction when a matching plan exists; unlinked exams have no link to break.
Existing "Scheme in Use" guards and `saveScheme`'s orphan cleanup still cover
deleted plans.

**Interaction with SoW / lesson flows:** Independent. Bulk Generate stays as-is
but is stripped of its exam side effect. The NERDC/AI topic machinery is shared
(read-only) with lesson generation.

### Design B — "Add Single Exam" in the Create flyout + a separate bulk button

**How it works:**

- The lessons list's **Create flyout gains one item: "✏️ Add Single Exam"**
  (alongside "Add Single Lesson") → `/exam-editor`.
- A separate **"Bulk Generate Exams"** button lives on the **Exams List**
  screen, opening the same dialog as Design A.

**Plain-English flow (bulk):** *"Tap Exams. Tap Bulk Generate Exams. Tap
Generate. Done."* **Flow (single):** *"Tap Create. Tap Add Single Exam. Write
your exam."*

**Tap count for 13 exams:** 2–8 (bulk button path, same as A). Single exam:
Create (1) + Add Single Exam (1) + editor flow ≈ 9–11 taps — good for one exam,
bad for thirteen.

**Accidental exam creation:** **None** for bulk; single is explicit.

**Orphan risk:** **Low** (same as A).

**Interaction:** The lessons list gains one menu item; bulk lesson generation is
left untouched (still lessons-only after the exam side effect is removed).

### Design C — "Also generate exams" checkbox in the existing Bulk Generate

**How it works:**

- The existing Bulk Generate dialog gains a checkbox: **"☐ Also generate 13
  draft exams"** — **default unchecked**.
- Lessons are always generated; exams are created **only** when the teacher
  ticks the box.

**Plain-English flow:** *"Tap Create. Tap Bulk Generate. If you also want exams,
tick the box. Tap Generate."*

**Tap count for 13 exams:** 5 (Create → Bulk Generate → tick box → confirm → )
plus the lesson generation itself.

**Accidental exam creation:** **Low** — default off — but the coupling is still
one tap away, and the teacher can still get exams bundled with lessons.

**Orphan risk:** **Medium — unchanged from today** (same link mechanics, same
regenerate/delete paths).

**Interaction:** Minimal code change; preserves existing muscle memory. But it
keeps the conceptual coupling ("exams live inside lesson generation") that the
user explicitly wants gone.

### Design D — "Generate Exams from My Plan" (my idea)

**How it works:**

- Same entry as A (a "Generate Exams" button on the Exams List), but the dialog
  is **smarter**: it detects whether a saved scheme of work already exists for
  the selected subject/class/term.
- **If a plan exists:** the dialog says *"Use your plan for Mathematics / JSS 1
  / 1st Term"* and builds 13 exams whose topics come **1:1 from the plan's week
  rows** (same transaction, guaranteed alignment with the teacher's lessons).
- **If no plan exists:** it falls back to the curated NERDC list / AI (like A).
- Removes **all** implicit creation: `_bootstrapSchemeDrafts` exam seeding,
  `saveScheme`'s exam block, and the scheme screen's exam block.

**Plain-English flow:** *"Tap Exams. Tap Generate Exams. Tap Generate. Your
exams match your lessons."*

**Tap count for 13 exams:** 2–8 (same as A).

**Accidental exam creation:** **None.**

**Orphan risk:** **Lowest** — when a plan exists, exam links are created against
rows that provably exist; unlinked fallback is used otherwise.

**Interaction:** Deepest change — three implicit paths removed, lesson
generation becomes lessons-only, and exams can be regenerated from a refreshed
plan without touching lessons.

---

## 4. Comparison table

| Design | Taps for 13 exams | Accidental exam creation risk | Orphan risk | Understandable by IQ 60? | Simplicity (1–10) |
|---|---|---|---|---|---|
| **Current** | 4 (via lessons) — or ~90 via New Exam | **High** — bundled into Bulk Generate + silent seeding | **Medium** — links created without the teacher knowing | **No** — exams "just appear"; can't ask for lessons only | 3 |
| **A — Generate Exams on Exams List** | 2–8 | **None** | **Low** | **Yes** — "tap the big button, confirm, write" | 9 |
| **B — flyout item + bulk button** | 2–8 (bulk); ~9–11 (single) | **None** | **Low** | **Yes**, though two entry points to learn | 7 |
| **C — "Also generate exams" checkbox** | 5 (+lessons) | **Low** — default off, still coupled | **Medium** — unchanged mechanics | **Mostly** — checkbox is easy, coupling stays confusing | 6 |
| **D — Generate Exams from My Plan** | 2–8 | **None** | **Lowest** | **Yes** — "exams match your lessons" | 9 |

---

## 5. Recommendation

**Design A — a "Generate Exams" button on the Exams List — refined with D's
plan-alignment behavior, and implemented together with the removal of all three
implicit exam-creation paths.**

Why:

1. **It attacks the actual pain.** The audit shows the problem is *not* the exam
   data model — it's that exams can only be created as a side effect of lesson
   generation (or one at a time). A puts exam creation on the Exams screen, the
   one place teachers go when they want exams.
2. **Explicit and impossible to get wrong.** The teacher says exactly what they
   want on the screen they're looking at. Lessons generation becomes
   lessons-only; the IQ-60 flow is "tap Generate Exams, confirm, tap a card to
   write it."
3. **Lowest risk while still a big win.** Unlike B (two entry points) and C
   (keeps the coupling), A gives one button, one dialog, one result. D's
   plan-alignment is *free* on top of A: the dialog already knows subject/class/
   term, so reusing a matching plan's week topics is a small lookup — and it
   makes the exams match the lessons the teacher already wrote, which is what
   they actually want from a term's worth of exams.
4. **Kill the silent paths.** Removing the exam blocks from `saveScheme` and the
   scheme screen, and removing `_bootstrapSchemeDrafts`' exam seeding, is what
   actually guarantees "exams are never auto-created." Without that, any design
   still leaks exams.
5. **Orphan safety.** With plan-alignment, links are written in the same
   transaction against rows that exist; the unlinked fallback can't strand a
   link. The existing "Scheme in Use" guard and `saveScheme` orphan cleanup
   continue to protect regenerated plans.

**Implementation shape (for when this is approved):** a "Generate Exams" button
+ one confirmation dialog on `ExamsListScreen`; a shared service that resolves
subject/class/term, uses a matching saved plan's week topics when present (or
`getNerdcTopics` / AI otherwise), and inserts 13 draft exams in one DB
transaction; removal of the exam-creation blocks in `scheme_of_work_service.dart`
`saveScheme` and `scheme_of_work_screen.dart` `_saveScheme`; removal of the
exam-seeding branch in `exams_list_screen.dart` `_bootstrapSchemeDrafts`; and a
small copy update on the Bulk Generate dialog so it states "lessons only".

### 5.1 Risks to flag

1. **Storage quotas:** 13 draft exams consume per-tier exam quota. The dialog
   should show a count check and a friendly "storage limit" message (mirroring
   the editor's existing guard).
2. **Regeneration semantics:** "Generate Exams" with a plan that already has
   exams should reuse/refresh rather than duplicate (adopt-in-place, like
   `_findWeekExamBlocker` already does in `saveScheme`).
3. **Sync:** new draft exams are queued for push exactly like today's
   bulk-generated exams — no new sync surface.
4. **Unlocked vs Completed:** exams still have no `status` column; the "green =
   completed" status circle proposal on the list screens therefore only shows
   green for lessons until an exam-completed flag exists (documented in the
   cleanup plan).

---

## 6. Appendix — key code references

| Concern | Location |
|---|---|
| Bulk Generate dialog + plan flow | `lib/features/lesson/screens/lessons_list_screen.dart` (`_openAutoGenerateDialog`, `_runAutoGenerate`) |
| `saveScheme` — writes scheme rows + draft lessons **+ draft exams** | `lib/core/services/scheme_of_work_service.dart` (~line 195) |
| Exams list screen + silent draft-exam seeding | `lib/features/exam/screens/exams_list_screen.dart` (`_bootstrapSchemeDrafts`, `_openNewExam`, New Exam FAB) |
| Scheme screen — auto-creates exam per week on save | `lib/features/scheme_of_work/screens/scheme_of_work_screen.dart` (~line 677) |
| Single-exam editor (no scheme required) | `lib/features/exam/screens/exam_editor_screen.dart` (`_saveExam` ~line 1201; manual topic entry) |
| Full-term exam builder (one exam from scheme topics) | `lib/features/exam/screens/full_term_exam_screen.dart` (~line 268) |
| Curated NERDC weekly topics (13 weeks) | `lib/core/data/nerdc_curriculum.dart` (`getNerdcTopics`) |
| AI scheme prompt (13 weeks) | `lib/core/constants/prompt_templates.dart` (`schemeOfWork`) |
| Existing orphan-link repair (historic incident) | `supabase/scripts/restore_orphaned_scheme_links.sql` |
| Per-tier exam storage limits | `exam_editor_screen.dart` (`_saveExam` storage-limit guard) |
