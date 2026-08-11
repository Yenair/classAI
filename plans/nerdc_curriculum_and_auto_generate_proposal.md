# Part 2 — Curated NERDC Topic List + Part 3 — "Plan My Term" Auto Generate

**Status: PROPOSAL ONLY — no files have been changed. Diffs below are for review. You tell me when to apply.**

---

## Audit log (verified against the real codebase on Flutter 3.41.7)

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | `DropdownButtonFormField` needs `value:`, not `initialValue:` — would be a compile error | **AI wrong — plan correct.** On Flutter 3.41.7 `value` is deprecated in favor of `initialValue`; the entire codebase already uses `initialValue` (lessons_list:1056, scheme_of_work:1395/1407/1419/1470, editors, admin) and `flutter analyze --no-pub` passes. Using `value:` would add deprecation warnings. | `flutter --version`; grep of all `DropdownButtonFormField` call sites |
| 2 | `subjectName` is undefined in `SchemeOfWorkService` (param is `subject`) | **TRUE — draft bug, fixed below.** All `subjectName` references in the service were replaced with `subject`. | proposal §3.1 (now corrected) |
| 3 | Duplicate `week:` + `weekNumber:` in lesson/exam inserts | **Not a problem.** `Lessons` has both columns — `week` is non-nullable and required by `LessonsCompanion.insert`, `weekNumber` is the nullable scheme-linked one; the app reads `weekNumber ?? week` everywhere. The existing `_saveScheme` sets both. `Exams` has only `weekNumber`, and the draft sets only that. Removing `week` from lessons would break compilation. | `lib/core/database/tables/lessons.dart`, `exams.dart` |
| 4 | `PlatformHelper.isOnline()` may not exist | **Verified real.** `static Future<bool> isOnline()` exists and returns `Future<bool>` as assumed. | `lib/core/utils/platform_helper.dart` |

**Additional issues found in audit and fixed in this doc:**
1. `_loadSchemesForDisplay` populated `_schemesById` without `setState` → term labels on legacy cards could fail to refresh. Now calls `setState` when mounted (mirrors the old bootstrap).
2. The dialog's subject list was hard-coded to 4 items, so a teacher filtering on e.g. "French" would silently fall back to "Mathematics". The dialog now receives subject options built from the curated subjects **plus** the filter-derived subjects, and pre-fills with the filter selection when present.
3. Recreate flow runs delete and save as **two transactions** — if save fails after delete, the old plan is lost. Flagged below (not fixed, needs your call; recommended fix: one combined transaction).

---

## Part 2.1 — Design decisions

### Where the list lives → a Dart data file (`lib/core/data/nerdc_curriculum.dart`)

| Option | Verdict | Why |
|---|---|---|
| **Dart data file** | ✅ **Chosen** | Compile-time checked, typed, available instantly offline, zero async loading, zero schema changes (respects our AGENTS.md rule against DB schema changes), consistent with the existing `curriculum_types.dart` pattern. |
| Local DB table (`nerdc_topics`) | ❌ | Needs a schema change, a migration, and server sync plumbing for data that is static anyway. Heavy for data that never changes per-install. |
| Bundled JSON asset | ❌ | Needs asset registration, async loading, error handling for a file that is loaded on every screen. Dart code is simpler and type-safe. |

### How it's used → the curated list is the **primary source for topic titles**; AI is not called for topics at all

Following your recommendation, the list is the source of truth for week topics. The AI is used only in two places, and only when the curated list has no entry for that subject/class/term:

1. **Topics:** curated list → no AI call (instant, offline, deterministic, zero cost).
2. **Fallback:** subject/class/term not in the list → existing `PromptTemplates.schemeOfWork` AI path (unchanged behavior, so nothing breaks for uncommon subjects).
3. **Lesson content:** unchanged — the teacher still taps a lesson and generates content with AI as they do today. Auto Generate only *creates the plan and draft shells*, it never generates lesson content.

This removes one AI dependency per plan (13 weeks of topics no longer depend on the network or the model) and guarantees NERDC accuracy.

### Data structure (example — Mathematics, JSS 1, 1st Term, first three weeks)

```dart
class NerdcWeekTopic {
  final String topic;
  final List<String> objectives;
  const NerdcWeekTopic(this.topic, this.objectives);
}

// subject (lowercase) → class level ('jss 1' … 'sss 3') → term ('1st'|'2nd'|'3rd') → 13 weeks
const Map<String, Map<String, Map<String, List<NerdcWeekTopic>>>> nerdcCurriculum = {
  'mathematics': {
    'jss 1': {
      '1st': [
        NerdcWeekTopic(
          'Whole Numbers: Counting and Writing Numbers in Words',
          ['Count and write numbers in words up to millions',
           'Identify place values of digits in large numbers'],
        ),
        NerdcWeekTopic(
          'Whole Numbers: Place Values and Numeration of Large Numbers',
          ['Read and write numbers in figures and words',
           'Compare and order large numbers'],
        ),
        NerdcWeekTopic(
          'Fractions: Types and Equivalent Fractions',
          ['Identify proper, improper and mixed fractions',
           'Find equivalent fractions and simplify'],
        ),
        // … weeks 4–13
      ],
    },
  },
};
```

The helper (`getNerdcTopics`) normalizes any input spelling (`JSS1`, `Jss 1`, `jss1`, `First`, `1st term` …) and returns `null` when the combo isn't covered, which is the caller's signal to fall back to AI.

---

## Part 2.2 — Proposed implementation: `lib/core/data/nerdc_curriculum.dart` (new file)

Full proposed content. Data covers **1st Term only** for **Mathematics, English Studies, and Biology across JSS 1–SSS 3** (13 weeks each, matching the app's existing 13-week convention; weeks 11–13 are revision/exam, matching the real Nigerian school calendar). Everything else (2nd/3rd terms, other subjects, primary levels) returns `null` → AI fallback, so the app keeps working everywhere.

> **Data accuracy caveat:** topics below were drafted from public NERDC curriculum knowledge. They are realistic and structured, but I recommend a quick pass by a Nigerian subject teacher before wide rollout. The structure makes edits trivial (one list per subject/class/term). Also note: Biology is officially an SSS subject — at JSS the equivalent is Basic Science — so the JSS "Biology" entries below use the biology strand of Basic Science. If you'd rather JSS Biology fall back to AI, we just drop those three lists.

```dart
// lib/core/data/nerdc_curriculum.dart
//
// Curated NERDC weekly topics for Nigerian secondary schools.
// This list is the PRIMARY source for scheme-of-work topic titles:
//  - If a subject/class/term combo exists here, NO AI call is made for topics.
//  - If it is missing, callers fall back to PromptTemplates.schemeOfWork (AI).
//
// Keys are normalized: subject → lowercase; class level → 'jss 1'..'sss 3';
// term → '1st' | '2nd' | '3rd'. Weeks are ordered 1..13 (index + 1 = week number).

/// One week's topic plus 2–3 learning objectives (mirrors the AI response shape).
class NerdcWeekTopic {
  final String topic;
  final List<String> objectives;
  const NerdcWeekTopic(this.topic, this.objectives);
}

const Map<String, Map<String, Map<String, List<NerdcWeekTopic>>>> nerdcCurriculum = {
  // ─────────────────────────── MATHEMATICS ───────────────────────────
  'mathematics': {
    'jss 1': {
      '1st': [
        NerdcWeekTopic('Whole Numbers: Counting and Writing Numbers in Words',
            ['Count and write numbers in words up to millions', 'Identify place values of digits in large numbers']),
        NerdcWeekTopic('Whole Numbers: Place Values and Numeration of Large Numbers',
            ['Read and write large numbers in figures and words', 'Compare and order large numbers']),
        NerdcWeekTopic('Fractions: Types and Equivalent Fractions',
            ['Identify proper, improper and mixed fractions', 'Find equivalent fractions and simplify']),
        NerdcWeekTopic('Fractions: Addition and Subtraction',
            ['Add and subtract fractions with like and unlike denominators', 'Solve word problems involving fractions']),
        NerdcWeekTopic('Fractions: Multiplication and Division',
            ['Multiply and divide fractions and mixed numbers', 'Apply fractions to real-life problems']),
        NerdcWeekTopic('Decimal Fractions: Place Values and Conversion',
            ['Read and write decimals to three places', 'Convert between fractions and decimals']),
        NerdcWeekTopic('Decimal Fractions: Operations',
            ['Add, subtract, multiply and divide decimals', 'Solve problems involving money and measurement']),
        NerdcWeekTopic('Approximation: Rounding and Significant Figures',
            ['Round numbers to a given degree of accuracy', 'Identify significant figures in a number']),
        NerdcWeekTopic('Estimation: Lengths, Mass and Time',
            ['Estimate lengths, masses and time intervals', 'Use estimation to check the reasonableness of answers']),
        NerdcWeekTopic('Whole Numbers: Multiplication and Division of Large Numbers',
            ['Multiply and divide multi-digit numbers', 'Apply the four operations to word problems']),
        NerdcWeekTopic('Revision: Fractions, Decimals and Approximation',
            ['Revise fractions, decimals and approximation', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 2': {
      '1st': [
        NerdcWeekTopic('Revision of JSS 1 Work: Whole Numbers',
            ['Revise place values and operations on whole numbers', 'Tackle mixed revision exercises']),
        NerdcWeekTopic('Large and Small Numbers: Standard Form',
            ['Express very large and very small numbers in standard form', 'Convert between ordinary and standard form']),
        NerdcWeekTopic('Indices: Laws of Indices',
            ['State and apply the laws of indices', 'Simplify expressions using index laws']),
        NerdcWeekTopic('Fractions and Decimals: Review and Applications',
            ['Revise operations on fractions and decimals', 'Apply them to everyday problems']),
        NerdcWeekTopic('Approximation: Rounding and Significant Figures',
            ['Round numbers to decimal places and significant figures', 'Apply approximation to calculations']),
        NerdcWeekTopic('Ratio and Proportion: Introduction',
            ['Express ratios in simplest form', 'Share quantities in a given ratio']),
        NerdcWeekTopic('Ratio and Proportion: Applications',
            ['Solve direct and inverse proportion problems', 'Apply ratio to scale drawings']),
        NerdcWeekTopic('Percentages: Conversions and Applications',
            ['Convert between fractions, decimals and percentages', 'Find percentages of quantities']),
        NerdcWeekTopic('Percentages: Increase, Decrease, Profit and Loss',
            ['Calculate percentage increase and decrease', 'Solve profit and loss problems']),
        NerdcWeekTopic('Simple Interest: Calculating Interest and Amount',
            ['Use the simple interest formula', 'Calculate principal, rate, time and amount']),
        NerdcWeekTopic('Revision: Ratio, Proportion and Percentages',
            ['Revise ratio, proportion and percentages', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 3': {
      '1st': [
        NerdcWeekTopic('Revision of JSS 2 Work',
            ['Revise ratios, percentages and simple interest', 'Tackle mixed revision exercises']),
        NerdcWeekTopic('Binary Numbers: Introduction and Place Values',
            ['Understand the base-two number system', 'Convert binary numbers to denary']),
        NerdcWeekTopic('Binary Numbers: Addition, Subtraction and Conversion',
            ['Add and subtract binary numbers', 'Convert denary numbers to binary']),
        NerdcWeekTopic('Number Bases: Conversion Between Bases',
            ['Convert numbers between different bases', 'Perform operations in other bases']),
        NerdcWeekTopic('Integers: Directed Numbers and Operations',
            ['Add, subtract, multiply and divide directed numbers', 'Apply integers to real-life situations']),
        NerdcWeekTopic('Fractions, Decimals and Percentages: Review',
            ['Revise conversions and operations', 'Solve combined problems']),
        NerdcWeekTopic('Ratio and Proportion: Review and Applications',
            ['Revise ratio and proportion', 'Solve real-life proportion problems']),
        NerdcWeekTopic('Approximation and Estimation: Review',
            ['Revise rounding and significant figures', 'Estimate answers to calculations']),
        NerdcWeekTopic('Commercial Arithmetic: Profit, Loss and Discount',
            ['Calculate profit, loss and discount', 'Solve problems on marked price and selling price']),
        NerdcWeekTopic('Simple and Compound Interest: Introduction',
            ['Distinguish simple from compound interest', 'Calculate simple interest and amounts']),
        NerdcWeekTopic('Revision: Number Bases and Commercial Arithmetic',
            ['Revise number bases and commercial arithmetic', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 1': {
      '1st': [
        NerdcWeekTopic('Number Bases: Binary, Octal and Hexadecimal',
            ['Understand base-two, base-eight and base-sixteen systems', 'Convert between different bases']),
        NerdcWeekTopic('Number Bases: Operations and Conversions',
            ['Perform arithmetic in different bases', 'Solve problems involving base conversions']),
        NerdcWeekTopic('Modular Arithmetic: Addition, Subtraction and Multiplication',
            ['Understand the concept of modulo', 'Perform operations in modular arithmetic']),
        NerdcWeekTopic('Modular Arithmetic: Applications and Problem Solving',
            ['Apply modular arithmetic to real-life problems', 'Solve congruence problems']),
        NerdcWeekTopic('Indices: Laws and Simplification',
            ['State and apply the laws of indices', 'Simplify expressions with positive, negative and zero indices']),
        NerdcWeekTopic('Logarithms: Introduction and Laws',
            ['Define logarithms and their laws', 'Convert between index and logarithm form']),
        NerdcWeekTopic('Logarithms: Tables and Calculations',
            ['Use logarithm tables for multiplication and division', 'Solve problems using logarithms']),
        NerdcWeekTopic('Sets: Notation, Types and Venn Diagrams',
            ['Use set notation and identify set types', 'Represent sets on Venn diagrams']),
        NerdcWeekTopic('Sets: Union, Intersection and Complement',
            ['Find union, intersection and complement of sets', 'Solve set problems with Venn diagrams']),
        NerdcWeekTopic('Surds: Introduction, Simplification and Rationalization',
            ['Simplify surds', 'Rationalize the denominator of surd expressions']),
        NerdcWeekTopic('Revision: Indices, Logarithms and Sets',
            ['Revise indices, logarithms and sets', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 2': {
      '1st': [
        NerdcWeekTopic('Logarithms of Numbers: Theory and Laws',
            ['Recall the laws of logarithms', 'Express products and quotients in logarithmic form']),
        NerdcWeekTopic('Logarithms: Calculations Using Tables',
            ['Use logarithm tables for complex calculations', 'Solve problems involving powers and roots']),
        NerdcWeekTopic('Approximations and Percentages: Errors and Bounds',
            ['Find the limits of accuracy of measurements', 'Calculate relative and percentage errors']),
        NerdcWeekTopic('Sequence and Series: Introduction',
            ['Identify patterns in sequences', 'Define the nth term of a sequence']),
        NerdcWeekTopic('Arithmetic Progression: Terms and Sum',
            ['Find the nth term of an AP', 'Find the sum of the first n terms of an AP']),
        NerdcWeekTopic('Geometric Progression: Terms and Sum',
            ['Find the nth term of a GP', 'Find the sum of the first n terms of a GP']),
        NerdcWeekTopic('Geometric Progression: Applications (Compound Interest)',
            ['Apply GP to compound interest problems', 'Solve real-life growth and decay problems']),
        NerdcWeekTopic('Quadratic Equations: Factorization',
            ['Solve quadratic equations by factorization', 'Form quadratic equations from given roots']),
        NerdcWeekTopic('Quadratic Equations: Completing the Square and Formula',
            ['Solve quadratics by completing the square', 'Apply the quadratic formula']),
        NerdcWeekTopic('Simultaneous Equations: Linear and Quadratic',
            ['Solve simultaneous linear equations', 'Solve one linear and one quadratic equation']),
        NerdcWeekTopic('Revision: Progressions and Quadratics',
            ['Revise AP, GP and quadratic equations', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 3': {
      '1st': [
        NerdcWeekTopic('Review of Surds and Indices',
            ['Revise surds and the laws of indices', 'Tackle WAEC-style review questions']),
        NerdcWeekTopic('Matrices and Determinants: Introduction',
            ['Understand matrix notation and order', 'Add, subtract and multiply matrices by scalars']),
        NerdcWeekTopic('Matrices: Multiplication and Determinants',
            ['Multiply matrices', 'Find the determinant of 2x2 matrices']),
        NerdcWeekTopic('Logarithm and Indices: Applications Review',
            ['Revise applications of logarithms and indices', 'Solve examination-style problems']),
        NerdcWeekTopic('Fractions and Decimals: WAEC-Style Review',
            ['Revise operations on fractions and decimals', 'Attempt WAEC past questions']),
        NerdcWeekTopic('Inequalities: Linear Inequalities',
            ['Solve linear inequalities', 'Represent solutions on the number line']),
        NerdcWeekTopic('Quadratic Inequalities',
            ['Solve quadratic inequalities', 'Represent solutions graphically']),
        NerdcWeekTopic('Factorization of Polynomials',
            ['Factorize polynomials by common factors and grouping', 'Factorize quadratic expressions']),
        NerdcWeekTopic('Remainder and Factor Theorems',
            ['Apply the remainder theorem', 'Apply the factor theorem to factorize polynomials']),
        NerdcWeekTopic('Simultaneous Linear and Quadratic Equations',
            ['Solve simultaneous equations involving quadratics', 'Apply to word problems']),
        NerdcWeekTopic('Revision: WAEC Past Questions',
            ['Revise all first term topics', 'Practice WAEC past questions']),
        NerdcWeekTopic('Mock Examination',
            ['Sit a mock examination', 'Practise examination technique under time']),
        NerdcWeekTopic('WAEC Past Questions Review',
            ['Review mock scripts and WAEC questions', 'Clarify weak areas']),
      ],
    },
  },

  // ─────────────────────────── ENGLISH STUDIES ───────────────────────────
  'english studies': {
    'jss 1': {
      '1st': [
        NerdcWeekTopic('Speech Work: Introduction to Vowel Sounds',
            ['Identify the vowel sounds of English', 'Produce short and long vowel sounds correctly']),
        NerdcWeekTopic('Comprehension: Reading for Main Ideas',
            ['Read a passage and identify the main idea', 'Answer comprehension questions accurately']),
        NerdcWeekTopic('Grammar: Nouns and Pronouns',
            ['Identify nouns and their types', 'Use pronouns correctly in sentences']),
        NerdcWeekTopic('Grammar: Adjectives and Adverbs',
            ['Identify adjectives and adverbs', 'Use descriptive words correctly']),
        NerdcWeekTopic('Composition: Narrative Essay (My School)',
            ['Plan a narrative essay', 'Write a coherent narrative about my school']),
        NerdcWeekTopic('Speech Work: Consonant Sounds',
            ['Identify consonant sounds', 'Produce consonant sounds correctly']),
        NerdcWeekTopic('Comprehension: Listening and Following Directions',
            ['Listen attentively to instructions', 'Follow directions accurately']),
        NerdcWeekTopic('Grammar: Verbs and Tenses',
            ['Identify verbs and their tenses', 'Use present, past and future tenses correctly']),
        NerdcWeekTopic('Composition: Descriptive Essay',
            ['Use descriptive words and details', 'Write a description of a person or place']),
        NerdcWeekTopic('Spelling and Punctuation: Common Errors',
            ['Spell commonly used words correctly', 'Use capital letters, full stops and commas correctly']),
        NerdcWeekTopic('Revision: Grammar and Composition',
            ['Revise grammar topics covered', 'Practise essay writing']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 2': {
      '1st': [
        NerdcWeekTopic('Speech Work: Short and Long Vowel Sounds',
            ['Distinguish between short and long vowel sounds', 'Produce the sounds correctly']),
        NerdcWeekTopic('Comprehension: Skimming and Scanning',
            ['Skim a passage to get the general idea', 'Scan for specific information']),
        NerdcWeekTopic('Grammar: Tenses (Present, Past, Future)',
            ['Identify the three main tenses', 'Use tenses correctly in sentences']),
        NerdcWeekTopic('Composition: Narrative Essay',
            ['Plan a narrative with a clear beginning, middle and end', 'Write an interesting story']),
        NerdcWeekTopic('Vocabulary Development: Synonyms and Antonyms',
            ['Identify synonyms and antonyms', 'Use them to enrich writing']),
        NerdcWeekTopic('Speech Work: Consonant Clusters',
            ['Identify consonant clusters at word beginnings and endings', 'Pronounce words with consonant clusters']),
        NerdcWeekTopic('Grammar: Direct and Indirect Speech',
            ['Change direct speech to indirect speech', 'Use reporting verbs correctly']),
        NerdcWeekTopic('Comprehension: Reading for Inference',
            ['Read between the lines of a passage', 'Answer inference questions']),
        NerdcWeekTopic('Composition: Descriptive Essay',
            ['Use vivid details in description', 'Write a descriptive essay']),
        NerdcWeekTopic('Spelling: Commonly Misspelt Words',
            ['Identify commonly misspelt words', 'Spell them correctly in writing']),
        NerdcWeekTopic('Revision: Grammar and Comprehension',
            ['Revise all grammar and comprehension topics', 'Practise mixed exercises']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 3': {
      '1st': [
        NerdcWeekTopic('Speech Work: Diphthongs',
            ['Identify diphthongs in words', 'Produce diphthongs correctly']),
        NerdcWeekTopic('Comprehension: Intensive and Extensive Reading',
            ['Differentiate intensive and extensive reading', 'Apply both reading types to passages']),
        NerdcWeekTopic('Grammar: Active and Passive Voice',
            ['Change active sentences to passive', 'Change passive sentences to active']),
        NerdcWeekTopic('Composition: Argumentative Essay',
            ['Present arguments for and against a topic', 'Write a balanced argumentative essay']),
        NerdcWeekTopic('Vocabulary Development: Idioms and Proverbs',
            ['Identify common idioms and proverbs', 'Use them appropriately in sentences']),
        NerdcWeekTopic('Speech Work: Stress and Intonation',
            ['Identify stressed syllables in words', 'Use intonation to express meaning']),
        NerdcWeekTopic('Grammar: Question Tags and Auxiliary Verbs',
            ['Form question tags correctly', 'Use auxiliary verbs in questions and answers']),
        NerdcWeekTopic('Comprehension: Critical Reading',
            ['Evaluate information in a passage', 'Distinguish fact from opinion']),
        NerdcWeekTopic('Composition: Formal Letter Writing',
            ['Identify the features of a formal letter', 'Write a formal letter correctly']),
        NerdcWeekTopic('Summary Writing: Introduction to Summarizing',
            ['Identify key points in a passage', 'Summarize a passage in your own words']),
        NerdcWeekTopic('Revision: All Topics',
            ['Revise speech, grammar, comprehension and composition', 'Practise past questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 1': {
      '1st': [
        NerdcWeekTopic('Speech Work: Review of Vowels and Consonants',
            ['Revise vowel and consonant sounds', 'Produce sounds accurately in connected speech']),
        NerdcWeekTopic('Comprehension: Structure of Long Passages',
            ['Analyse the structure of a long passage', 'Answer questions on content and structure']),
        NerdcWeekTopic('Grammar: Parts of Speech Review',
            ['Revise all eight parts of speech', 'Identify parts of speech in sentences']),
        NerdcWeekTopic('Grammar: Verbs, Tenses and Aspect',
            ['Use tenses and aspects correctly', 'Revise the use of modal verbs']),
        NerdcWeekTopic('Composition: Narrative Essay',
            ['Plan a narrative essay with good structure', 'Write a vivid narrative']),
        NerdcWeekTopic('Speech Work: Stress Patterns in Words',
            ['Identify stress patterns in polysyllabic words', 'Produce correct word stress']),
        NerdcWeekTopic('Comprehension: Listening and Note-Taking',
            ['Listen to a passage and take notes', 'Summarise main points from listening']),
        NerdcWeekTopic('Vocabulary Development: Word Formation Processes',
            ['Identify prefixes, suffixes and roots', 'Form new words from roots']),
        NerdcWeekTopic('Composition: Expository Essay',
            ['Explain ideas clearly in an expository essay', 'Write an expository essay on a given topic']),
        NerdcWeekTopic('Summary Writing: Identifying Main Points',
            ['Identify main points and supporting details', 'Summarise passages concisely']),
        NerdcWeekTopic('Revision: Grammar and Composition',
            ['Revise grammar, vocabulary and composition topics', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 2': {
      '1st': [
        NerdcWeekTopic('Speech Work: Intonation Patterns',
            ['Identify rising and falling intonation', 'Use intonation for statements and questions']),
        NerdcWeekTopic('Comprehension: Inference and Deduction',
            ['Draw inferences from passages', 'Answer deduction questions']),
        NerdcWeekTopic('Grammar: Sentence Types (Simple, Compound, Complex)',
            ['Identify simple, compound and complex sentences', 'Construct each sentence type correctly']),
        NerdcWeekTopic('Composition: Argumentative Essay',
            ['Develop clear arguments with evidence', 'Write a persuasive argumentative essay']),
        NerdcWeekTopic('Vocabulary Development: Register (Education, Law)',
            ['Identify words and expressions of registers', 'Use register appropriately in context']),
        NerdcWeekTopic('Grammar: Concord (Subject–Verb Agreement)',
            ['Match subjects with verbs correctly', 'Correct concord errors in sentences']),
        NerdcWeekTopic('Comprehension: Cloze Passages',
            ['Fill gaps in cloze passages with suitable words', 'Justify word choices']),
        NerdcWeekTopic('Composition: Formal and Informal Letters',
            ['Distinguish formal from informal letters', 'Write both letter types correctly']),
        NerdcWeekTopic('Summary Writing: Paraphrasing and Condensing',
            ['Paraphrase ideas in your own words', 'Condense passages without losing meaning']),
        NerdcWeekTopic('Literature: Introduction to Genres (Prose, Poetry, Drama)',
            ['Identify the three literary genres', 'Analyse simple literary texts']),
        NerdcWeekTopic('Revision: All Topics',
            ['Revise speech, grammar, composition and summary', 'Attempt mixed practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 3': {
      '1st': [
        NerdcWeekTopic('Comprehension: WAEC-Style Passages',
            ['Attempt WAEC-style comprehension passages', 'Answer questions on content, structure and inference']),
        NerdcWeekTopic('Grammar: Sentence Structure and Concord Review',
            ['Revise sentence types and concord', 'Correct errors in examination-style sentences']),
        NerdcWeekTopic('Composition: Expository and Argumentative Essays',
            ['Write clear expository and argumentative essays', 'Practise planning and time management']),
        NerdcWeekTopic('Summary Writing: WAEC Techniques',
            ['Summarise passages within word limits', 'Follow WAEC summary requirements']),
        NerdcWeekTopic('Vocabulary Development: Idioms and Phrasal Verbs',
            ['Identify idioms and phrasal verbs', 'Use them correctly in sentences']),
        NerdcWeekTopic('Speech Work: Stress, Rhythm and Intonation Review',
            ['Revise stress, rhythm and intonation', 'Practise oral skills for examinations']),
        NerdcWeekTopic('Comprehension: Oral Skills Practice',
            ['Practise listening comprehension', 'Respond correctly to spoken questions']),
        NerdcWeekTopic('Composition: Letter Writing Review',
            ['Revise formal and informal letter formats', 'Write letters under examination conditions']),
        NerdcWeekTopic('Lexis and Structure: Practice Questions',
            ['Attempt lexis and structure questions', 'Review correct answers']),
        NerdcWeekTopic('WAEC Past Questions: Practice and Marking',
            ['Practise WAEC past questions', 'Mark answers and identify weak areas']),
        NerdcWeekTopic('Revision: All Topics',
            ['Revise all first term topics', 'Practise past questions']),
        NerdcWeekTopic('Mock Examination',
            ['Sit a mock examination', 'Practise examination technique under time']),
        NerdcWeekTopic('WAEC Past Questions Review',
            ['Review mock scripts and WAEC questions', 'Clarify weak areas']),
      ],
    },
  },

  // ─────────────────────────── BIOLOGY ───────────────────────────
  // Note: at JSS level this is the biology strand of Basic Science.
  'biology': {
    'jss 1': {
      '1st': [
        NerdcWeekTopic('Living and Non-Living Things: Meaning and Differences',
            ['Differentiate living from non-living things', 'Give examples of each']),
        NerdcWeekTopic('Characteristics of Living Things',
            ['List the characteristics of living things', 'Explain each characteristic with examples']),
        NerdcWeekTopic('Classification of Living Things: Plants and Animals',
            ['Group living things into plants and animals', 'Give examples of each group']),
        NerdcWeekTopic('Plants: Parts and Functions',
            ['Identify the main parts of a plant', 'State the function of each part']),
        NerdcWeekTopic('Animals: Major Groups and Features',
            ['Group animals by their features', 'Give examples of each group']),
        NerdcWeekTopic('The Human Body: Parts and Functions',
            ['Identify major parts of the human body', 'State the function of each part']),
        NerdcWeekTopic('Sense Organs: Structure and Functions',
            ['Identify the five sense organs', 'Explain what each sense organ does']),
        NerdcWeekTopic('Nutrition: Food Groups and Balanced Diet',
            ['Identify the major food groups', 'Explain the importance of a balanced diet']),
        NerdcWeekTopic('Diseases: Causes, Symptoms and Prevention',
            ['Identify common diseases', 'Explain how to prevent them']),
        NerdcWeekTopic('First Aid and Safety Education',
            ['Explain the meaning of first aid', 'Demonstrate basic first aid skills']),
        NerdcWeekTopic('Revision: Living Things and Nutrition',
            ['Revise living things and nutrition topics', 'Attempt practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 2': {
      '1st': [
        NerdcWeekTopic('Living Things and Their Habitat',
            ['Define habitat and list types of habitats', 'Identify organisms in different habitats']),
        NerdcWeekTopic('Adaptation of Living Things to Their Environment',
            ['Explain the concept of adaptation', 'Give examples of adaptations in plants and animals']),
        NerdcWeekTopic('The Cell: Introduction and Structure',
            ['Define the cell', 'Identify the main parts of a cell']),
        NerdcWeekTopic('Plant and Animal Cells: Similarities and Differences',
            ['Compare plant and animal cells', 'Draw and label both cell types']),
        NerdcWeekTopic('Growth and Development in Living Things',
            ['Explain the meaning of growth and development', 'Describe growth in plants and animals']),
        NerdcWeekTopic('Reproduction in Plants',
            ['Explain reproduction in flowering plants', 'Describe pollination and fertilization']),
        NerdcWeekTopic('Reproduction in Animals',
            ['Describe reproduction in animals', 'Explain internal and external fertilization']),
        NerdcWeekTopic('The Skeleton and Muscular System',
            ['Identify major bones of the skeleton', 'Explain the functions of the skeleton and muscles']),
        NerdcWeekTopic('The Respiratory System',
            ['Identify the organs of respiration', 'Explain the process of breathing']),
        NerdcWeekTopic('The Circulatory System and Blood',
            ['Identify the parts of the circulatory system', 'State the functions of blood']),
        NerdcWeekTopic('Revision: Cells and Body Systems',
            ['Revise cells and body systems topics', 'Attempt practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'jss 3': {
      '1st': [
        NerdcWeekTopic('Nervous System: Coordination and Control',
            ['Identify the parts of the nervous system', 'Explain how the body coordinates actions']),
        NerdcWeekTopic('The Eye: Structure and Vision',
            ['Identify the parts of the eye', 'Explain how the eye sees']),
        NerdcWeekTopic('The Ear: Structure and Hearing',
            ['Identify the parts of the ear', 'Explain how the ear hears']),
        NerdcWeekTopic('Endocrine System: Hormones and Their Functions',
            ['Identify major endocrine glands', 'State the functions of their hormones']),
        NerdcWeekTopic('Blood Groups and Blood Transfusion',
            ['Identify the major blood groups', 'Explain the importance of blood transfusion']),
        NerdcWeekTopic('Excretory System: Organs and Functions',
            ['Identify the organs of excretion', 'Explain how each organ removes waste']),
        NerdcWeekTopic('The Skin and Temperature Regulation',
            ['Describe the structure of the skin', 'Explain how the skin regulates temperature']),
        NerdcWeekTopic('Diseases and Immunization',
            ['Explain how immunization prevents disease', 'Identify common vaccine-preventable diseases']),
        NerdcWeekTopic('Drug Abuse: Effects and Prevention',
            ['Explain the meaning of drug abuse', 'List the effects of drug abuse and how to prevent it']),
        NerdcWeekTopic('Family Life Education: Reproductive Health',
            ['Explain the meaning of family life education', 'Discuss responsible reproductive health']),
        NerdcWeekTopic('Revision: All Topics',
            ['Revise all first term topics', 'Attempt practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 1': {
      '1st': [
        NerdcWeekTopic('Introduction to Biology: Meaning and Branches',
            ['Define biology and its major branches', 'State the importance of studying biology']),
        NerdcWeekTopic('Characteristics of Living Things',
            ['List the characteristics of living things', 'Explain each characteristic with examples']),
        NerdcWeekTopic('Classification of Living Things: Kingdoms',
            ['Explain the concept of classification', 'Identify the major kingdoms of living things']),
        NerdcWeekTopic('Classification: Binomial Nomenclature',
            ['Explain binomial nomenclature', 'Write scientific names correctly']),
        NerdcWeekTopic('The Cell: Structure and Functions',
            ['Identify the parts of the cell', 'State the function of each part']),
        NerdcWeekTopic('Cell Organelles and Their Functions',
            ['Identify major cell organelles', 'Describe the function of each organelle']),
        NerdcWeekTopic('Cell Division: Mitosis',
            ['Describe the stages of mitosis', 'State the significance of mitosis']),
        NerdcWeekTopic('Cell Division: Meiosis',
            ['Describe the stages of meiosis', 'Compare mitosis and meiosis']),
        NerdcWeekTopic('The Cell and Its Environment: Osmosis and Diffusion',
            ['Explain diffusion and osmosis', 'Describe their importance to living cells']),
        NerdcWeekTopic('Ecology: Habitat, Niche and Population',
            ['Define habitat, niche and population', 'Give examples of each']),
        NerdcWeekTopic('Revision: Cell and Ecology',
            ['Revise cell biology and ecology topics', 'Attempt practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 2': {
      '1st': [
        NerdcWeekTopic('Organisation of Life: Cell to Organism',
            ['Describe the levels of biological organisation', 'Explain how cells form tissues, organs and systems']),
        NerdcWeekTopic('Plant Tissues: Types and Functions',
            ['Identify the major plant tissues', 'State the function of each tissue']),
        NerdcWeekTopic('Animal Tissues: Types and Functions',
            ['Identify the major animal tissues', 'State the function of each tissue']),
        NerdcWeekTopic('Nutrition in Plants: Photosynthesis',
            ['Explain the process of photosynthesis', 'State the conditions and products of photosynthesis']),
        NerdcWeekTopic('Nutrition in Plants: Mineral Requirements',
            ['Identify essential plant minerals', 'Explain the effects of mineral deficiency']),
        NerdcWeekTopic('Nutrition in Animals: Mammalian Teeth',
            ['Identify the types of mammalian teeth', 'Relate tooth structure to function']),
        NerdcWeekTopic('The Digestive System: Alimentary Canal',
            ['Identify the parts of the alimentary canal', 'Describe the process of digestion']),
        NerdcWeekTopic('Enzymes and Digestion',
            ['Define enzymes and their properties', 'Explain the role of enzymes in digestion']),
        NerdcWeekTopic('Transport in Plants: Xylem and Phloem',
            ['Explain the functions of xylem and phloem', 'Describe the transport of water and food']),
        NerdcWeekTopic('Transport in Animals: Circulatory System and Blood',
            ['Identify the parts of the circulatory system', 'Explain the functions of blood components']),
        NerdcWeekTopic('Revision: Nutrition and Transport',
            ['Revise nutrition and transport topics', 'Attempt practice questions']),
        NerdcWeekTopic('Examination: First Term Examination',
            ['Sit the first term examination', 'Demonstrate mastery of first term topics']),
        NerdcWeekTopic('Exam Review and Correction',
            ['Review the examination script', 'Correct mistakes and clarify difficult topics']),
      ],
    },
    'sss 3': {
      '1st': [
        NerdcWeekTopic('Ecology: Ecosystems and Niche',
            ['Define ecosystem and niche', 'Identify components of an ecosystem']),
        NerdcWeekTopic('Population Studies: Sampling Techniques',
            ['Explain population sampling techniques', 'Describe quadrat and transect methods']),
        NerdcWeekTopic('Energy Flow: Food Chains and Food Webs',
            ['Construct food chains and food webs', 'Explain energy transfer between trophic levels']),
        NerdcWeekTopic('Nutrient Cycling: Carbon and Nitrogen Cycles',
            ['Describe the carbon cycle', 'Describe the nitrogen cycle']),
        NerdcWeekTopic('Pollution: Types, Causes and Effects',
            ['Identify types of pollution', 'Explain the causes and effects of each type']),
        NerdcWeekTopic('Conservation of Natural Resources',
            ['Explain the meaning of conservation', 'Describe methods of conserving resources']),
        NerdcWeekTopic('Pests and Diseases of Agricultural Importance',
            ['Identify common agricultural pests and diseases', 'Explain their control measures']),
        NerdcWeekTopic('Genetics: Mendelian Inheritance',
            ['Explain Mendel\'s laws of inheritance', 'Solve simple genetic crosses']),
        NerdcWeekTopic('Genetics: Variation and Chromosomes',
            ['Distinguish continuous and discontinuous variation', 'Explain the role of chromosomes in inheritance']),
        NerdcWeekTopic('Evolution: Evidences and Theories',
            ['List the evidences of evolution', 'Explain the theories of evolution']),
        NerdcWeekTopic('Revision: All Topics',
            ['Revise all first term topics', 'Attempt practice questions']),
        NerdcWeekTopic('Mock Examination',
            ['Sit a mock examination', 'Practise examination technique under time']),
        NerdcWeekTopic('WAEC Past Questions Review',
            ['Review mock scripts and WAEC questions', 'Clarify weak areas']),
      ],
    },
  },
};

/// Returns the curated topics for a subject/class/term, or null when the
/// combination is not covered (caller then falls back to AI generation).
/// Weeks are ordered — week number = index + 1.
List<NerdcWeekTopic>? getNerdcTopics(String subject, String classLevel, String term) {
  final subjectKey = subject.trim().toLowerCase();
  final classKey = _normalizeClassKey(classLevel);
  final termKey = _normalizeTermKey(term);
  return nerdcCurriculum[subjectKey]?[classKey]?[termKey];
}

/// 'jss1' / 'JSS1' / 'JSS 1' → 'jss 1'; 'sss 3' / 'SSS3' → 'sss 3'.
String _normalizeClassKey(String value) {
  final compact = value.trim().toLowerCase().replaceAll(' ', '');
  final match = RegExp(r'^(jss|sss)(\d)$').firstMatch(compact);
  if (match != null) return '${match.group(1)} ${match.group(2)}';
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// 'First', 'first term', '1st term', '1' → '1st' (likewise 2nd/3rd).
String _normalizeTermKey(String value) {
  final lower = value.trim().toLowerCase();
  if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) return '1st';
  if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) return '2nd';
  if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) return '3rd';
  return lower;
}
```

### Fallback behavior

If `getNerdcTopics` returns `null` (e.g., subject "French", or 2nd term, or Primary level): the Auto Generate flow calls the existing `PromptTemplates.schemeOfWork` AI path — identical to today. The app never breaks; the curated list only *adds* determinism where data exists.

---

## Part 3 — Design A: "Plan My Term" button (proposed implementation)

### Files touched

| File | Change |
|---|---|
| `lib/core/services/scheme_of_work_service.dart` | **NEW** — shared save/delete transaction (extracted from the SoW screen) + AI-result week parser |
| `lib/core/database/daos/scheme_of_work_dao.dart` | +1 method: `hardDelete(id)` (no schema change) |
| `lib/features/lesson/screens/lessons_list_screen.dart` | "Plan My Term" button + dialog + generation flow; silent draft seeding removed |
| `lib/features/scheme_of_work/screens/scheme_of_work_screen.dart` | `_saveScheme` becomes a thin call into the shared service |
| `lib/router/app_router.dart` | `/scheme-of-work` becomes admin-only |
| `lib/features/dashboard/screens/dashboard_screen.dart` | SoW tab/nav item hidden for non-admins (editor + reader layouts) |

---

### 3.1 NEW FILE — `lib/core/services/scheme_of_work_service.dart`

The transaction logic from `_saveScheme` (scheme rows + linked draft lessons + linked draft exams + sync queue entries), moved verbatim into a shared service so the admin screen and the Auto Generate button use exactly the same write path. **All writes run inside one Drift transaction** — a mid-way failure rolls the whole plan back (requirement 3.2.5 "partial generation rollback").

```dart
// lib/core/services/scheme_of_work_service.dart
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:classai/core/database/database.dart';

/// Shared persistence for Scheme-of-Work rows and their linked draft
/// lessons/exams. Used by both the admin SchemeOfWorkScreen and the
/// teacher "Plan My Term" auto-generate flow so they never drift apart.
class SchemeOfWorkService {
  final AppDatabase db;
  SchemeOfWorkService(this.db);

  /// Writes one scheme_of_work row per week and auto-creates a linked draft
  /// lesson and exam for each week. Everything runs inside a single database
  /// transaction — a partial failure rolls the whole plan back.
  ///
  /// [weeks] is a list of `{'week': int, 'topic': String, 'objectives': String}`
  /// maps, exactly the shape produced by the existing AI parsing and by the
  /// curated NERDC list.
  ///
  /// Returns weekNumber → scheme row id, so callers can keep their week
  /// record lookup in sync (the admin screen needs this for approval).
  Future<Map<int, int>> saveScheme({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
    required List<Map<String, dynamic>> weeks,
    Map<int, int> existingWeekRecordIds = const {},
  }) {
    return db.transaction(() async {
      var subjectId = await _resolveOrInsertSubjectId(schoolId, subject);

      final teacher = await db.teachersDao.getById(teacherId);
      final teacherServerId = teacher?.serverId;
      final school = await db.schoolsDao.getByLocalId(schoolId);
      final schoolServerId = school?.serverId;
      final termLabel = _normalizeTermLabelForDraft(term);
      final subject = await db.subjectsDao.getById(subjectId);
      final subjectServerId = subject?.serverId;

      final weekRecordIds = <int, int>{...existingWeekRecordIds};

      for (var index = 0; index < weeks.length; index++) {
        final week = weeks[index];
        final weekNumber =
            (week['week'] as int?) ?? (index + 1);
        final topicText = week['topic']?.toString().trim() ?? '';
        final objectivesText = week['objectives']?.toString() ?? '';
        final existingId = weekRecordIds[weekNumber];

        final recordId = existingId ?? await _insertWeekRow(
          schoolId: schoolId,
          teacherId: teacherId,
          subjectId: subjectId,
          classLevel: classLevel,
          term: term,
          weekNumber: weekNumber,
          topic: topicText,
          objectives: objectivesText,
          teacherServerId: teacherServerId,
          schoolServerId: schoolServerId,
          subjectServerId: subjectServerId,
        );
        weekRecordIds[weekNumber] = recordId;

        // Auto-create draft lesson if not already existing
        if (teacherServerId != null && termLabel.isNotEmpty) {
          final existingLessons = await db.lessonsDao.getAll();
          final weekId = weekRecordIds[weekNumber];
          final lessonExists = existingLessons.any((l) {
            if (l.isDeleted || l.status != 'draft') return false;
            if (weekId != null) {
              final existingSchemeId = int.tryParse(l.schemeOfWorkId ?? '');
              if (existingSchemeId == weekId) return true;
            }
            return l.teacherServerId == teacherServerId &&
                l.classLevel == classLevel &&
                (l.term ?? '') == termLabel &&
                (l.weekNumber ?? l.week) == weekNumber;
          });
          if (!lessonExists) {
            final lessonContent = jsonEncode({
              'objectives': [],
              'vocabulary': [],
              'materials': [],
              'presentation': [],
              'assessment': '',
              'homework': '',
            });
            final lessonId = await db.lessonsDao.insertLesson(
              LessonsCompanion.insert(
                subject: subject,
                classLevel: classLevel,
                week: weekNumber,
                topic: topicText,
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: lessonContent,
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                schemeOfWorkId: Value(weekId.toString()),
                weekNumber: Value(weekNumber),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                term: Value(termLabel),
              ),
            );
            await db.syncQueueDao.insertEntry(
              queueTable: 'lessons',
              recordLocalId: lessonId,
              operation: 'INSERT',
              payload: {
                'subject': subject,
                'classLevel': classLevel,
                'week': weekNumber,
                'topic': topicText,
                'difficulty': 'medium',
                'bloomsVerbs': '',
                'curriculum': 'NERDC',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'content': lessonContent,
                'content_hash': lessonContent.hashCode.toString(),
                'is_unlocked': false,
                'scheme_of_work_id': weekId.toString(),
                'week_number': weekNumber,
                'term': termLabel,
              },
            );
          }

          // Auto-create draft exam if not already existing
          final existingExams = await db.examsDao.getAll();
          final examExists = existingExams.any((e) {
            if (e.isDeleted) return false;
            if (weekId != null) {
              final existingSchemeId = int.tryParse(e.schemeOfWorkId ?? '');
              if (existingSchemeId == weekId) return true;
            }
            return e.teacherServerId == teacherServerId &&
                e.classLevel == classLevel &&
                (e.term ?? '') == termLabel &&
                e.weekNumber == weekNumber;
          });
          if (!examExists) {
            final examContent = jsonEncode({
              'mcqs': [],
              'theory': [],
              'subjective': [],
            });
            final examId = await db.examsDao.insertExam(
              ExamsCompanion.insert(
                subject: subject,
                classLevel: classLevel,
                topic: topicText,
                difficulty: 'medium',
                curriculum: 'NERDC',
                content: examContent,
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                isUnlocked: const Value(false),
                schemeOfWorkId: Value(weekId.toString()),
                weekNumber: Value(weekNumber),
                term: Value(termLabel),
              ),
            );
            await db.syncQueueDao.insertEntry(
              queueTable: 'exams',
              recordLocalId: examId,
              operation: 'INSERT',
              payload: {
                'subject': subject,
                'classLevel': classLevel,
                'topic': topicText,
                'difficulty': 'medium',
                'curriculum': 'NERDC',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'content': examContent,
                'is_unlocked': false,
                'scheme_of_work_id': weekId.toString(),
                'week_number': weekNumber,
                'term': termLabel,
              },
            );
          }
        }
      }
      return weekRecordIds;
    });
  }

  /// Finds an existing saved plan for the same subject/class/term.
  /// Used by the Auto Generate flow to warn before recreating.
  Future<List<SchemeOfWorkData>> findSchemes({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
  }) async {
    final subjectId = await findSubjectId(schoolId: schoolId, subject: subject);
    if (subjectId == null) return const [];
    final rows = await db.schemeOfWorkDao.getBySchool(schoolId);
    final termKey = _normalizeTermKey(term);
    return rows
        .where((r) =>
            !r.isDeleted &&
            r.teacherId == teacherId &&
            r.subjectId == subjectId &&
            r.classLevel == classLevel &&
            _normalizeTermKey(r.term) == termKey)
        .toList();
  }

  /// Looks up a subject id WITHOUT creating the subject row.
  Future<int?> findSubjectId({
    required int schoolId,
    required String subject,
  }) async {
    final school = await db.schoolsDao.getByLocalId(schoolId);
    final schoolServerId = school?.serverId;
    final row = schoolServerId != null
        ? await db.subjectsDao.getByNameAndSchool(subject, schoolServerId)
        : await db.subjectsDao.getByName(subject);
    return row?.id;
  }

  /// Deletes an existing plan: scheme rows are hard-deleted locally (with a
  /// sync DELETE queued for server-synced rows); linked draft lessons/exams
  /// are soft-deleted via the existing DAO methods (isDeleted=true) with a
  /// sync DELETE queued when the row has a server id. Runs in one transaction.
  Future<void> deleteSchemeAndLinkedDrafts({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
  }) {
    return db.transaction(() async {
      final subjectId = await findSubjectId(schoolId: schoolId, subject: subject);
      if (subjectId == null) return;
      final rows = await findSchemes(
        schoolId: schoolId,
        teacherId: teacherId,
        subject: subject,
        classLevel: classLevel,
        term: term,
      );
      for (final row in rows) {
        final lessons = await db.lessonsDao.getAll();
        for (final lesson in lessons) {
          if (lesson.isDeleted) continue;
          if (lesson.schemeOfWorkId != row.id.toString()) continue;
          await db.lessonsDao.deleteLesson(lesson.id);
          if (lesson.serverId != null && lesson.serverId!.isNotEmpty) {
            await db.syncQueueDao.insertEntry(
              queueTable: 'lessons',
              recordLocalId: lesson.id,
              operation: 'DELETE',
              payload: {'id': lesson.id, 'server_id': lesson.serverId},
            );
          }
        }
        final exams = await db.examsDao.getAll();
        for (final exam in exams) {
          if (exam.isDeleted) continue;
          if (exam.schemeOfWorkId != row.id.toString()) continue;
          await db.examsDao.deleteExam(exam.id);
          if (exam.serverId != null && exam.serverId!.isNotEmpty) {
            await db.syncQueueDao.insertEntry(
              queueTable: 'exams',
              recordLocalId: exam.id,
              operation: 'DELETE',
              payload: {'id': exam.id, 'server_id': exam.serverId},
            );
          }
        }
        if (row.serverId != null && row.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'scheme_of_work',
            recordLocalId: row.id,
            operation: 'DELETE',
            payload: {'id': row.id, 'server_id': row.serverId},
          );
        }
        await db.schemeOfWorkDao.hardDelete(row.id);
      }
    });
  }

  Future<int> _resolveOrInsertSubjectId(int schoolId, String subject) async {
    final existing = await findSubjectId(schoolId: schoolId, subject: subject);
    if (existing != null) return existing;
    final school = await db.schoolsDao.getByLocalId(schoolId);
    final schoolServerId = school?.serverId;
    final subjectId = await db.subjectsDao.insert(
      name: subject,
      schoolId: schoolServerId,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'subjects',
      recordLocalId: subjectId,
      operation: 'INSERT',
      payload: {'name': subject, 'school_id': schoolServerId},
    );
    return subjectId;
  }

  Future<int> _insertWeekRow({
    required int schoolId,
    required int teacherId,
    required int subjectId,
    required String classLevel,
    required String term,
    required int weekNumber,
    required String topic,
    required String objectives,
    required String? teacherServerId,
    required String? schoolServerId,
    required String? subjectServerId,
  }) async {
    final newId = await db.schemeOfWorkDao.insert(
      SchemeOfWorkCompanion.insert(
        schoolId: Value(schoolId),
        teacherId: Value(teacherId),
        subjectId: Value(subjectId),
        term: Value(term),
        classLevel: Value(classLevel),
        weekNumber: Value(weekNumber),
        topic: Value(topic),
        objectives: Value(objectives),
        status: const Value('draft'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (subjectServerId != null) {
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: newId,
        operation: 'INSERT',
        payload: {
          'teacher_server_id': teacherServerId,
          'school_server_id': schoolServerId,
          'subject_id': subjectServerId,
          'term': term,
          'week_number': weekNumber,
          'topic': topic,
          'objectives': objectives,
          'status': 'draft',
          'admin_edited_topic': null,
          'admin_comment': null,
          'class_level': classLevel,
        },
      );
    }
    return newId;
  }

  String _normalizeTermLabelForDraft(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) return '1st Term';
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) return '2nd Term';
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) return '3rd Term';
    return term.trim();
  }

  String _normalizeTermKey(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) return '1st';
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) return '2nd';
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) return '3rd';
    return lower;
  }
}

/// Parses the AI scheme-of-work response into week maps, mirroring the
/// existing logic in SchemeOfWorkScreen._extractSchemePayload.
/// Shared so the Auto Generate AI fallback and the admin screen agree.
List<Map<String, dynamic>> parseSchemeWeeks(Map<String, dynamic> aiResult) {
  final raw = aiResult['raw'] ?? aiResult;
  Map<String, dynamic> payload;
  if (raw is String) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    } else if (decoded is Map) {
      payload = decoded.cast<String, dynamic>();
    } else {
      throw FormatException('Scheme response did not contain a JSON object');
    }
  } else if (raw is Map<String, dynamic>) {
    payload = raw;
  } else if (raw is Map) {
    payload = raw.cast<String, dynamic>();
  } else {
    throw FormatException('Scheme response did not contain a JSON object');
  }
  return (payload['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
}
```


---

### 3.2 `lib/core/database/daos/scheme_of_work_dao.dart` — one added method (no schema change)

```diff
   /// Hard-delete only confirmed-synced rows for a given teacher.
   /// Used during logout to scope-clean the outgoing teacher's data
   /// while leaving unsynced (pending) rows intact (Option b).
   /// [teacherLocalId] is the integer FK into Teachers.localId.
   Future<void> deleteSyncedRowsByTeacher(int teacherLocalId) {
     return (delete(schemeOfWork)
           ..where((t) => t.teacherId.equals(teacherLocalId))
           ..where((t) => t.serverId.isNotNull()))
         .go();
   }
+
+  /// Hard-delete a single scheme row. Used by the "Plan My Term" recreate
+  /// flow AFTER the row's linked draft lessons/exams have been soft-deleted
+  /// and DELETE sync entries queued.
+  Future<void> hardDelete(int id) {
+    return (delete(schemeOfWork)..where((t) => t.id.equals(id))).go();
+  }
 }
```

---

### 3.3 `lib/features/lesson/screens/lessons_list_screen.dart`

**a) Imports** — add:

```dart
import 'package:classai/core/constants/curriculum_types.dart' show nerdcSubjects;
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/data/nerdc_curriculum.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
```

**b) State field** — `bool _schemeDraftsBootstrapped = false;` is **removed** (seeding is deleted), replaced by a generation flag:

```diff
   String _selectedSubjectFilter = 'All';
   bool _filtersExpanded = true;
-  bool _schemeDraftsBootstrapped = false;
+  bool _autoGenerating = false;
   final Map<int, SchemeOfWorkData> _schemesById = {};
```

**c) `initState`** — the silent seeding call becomes a display-only lookup:

```diff
     WidgetsBinding.instance.addPostFrameCallback((_) {
       ref.read(syncStatusProvider.notifier).refresh();
       ref.read(offlineCreditStateProvider.notifier).refresh();
       ref.read(unresolvedConflictsProvider.notifier).refresh();
-      _bootstrapSchemeDrafts();
+      _loadSchemesForDisplay();
     });
```

**d) `_bootstrapSchemeDrafts` is replaced** by `_loadSchemesForDisplay` (only populates `_schemesById` so term labels still display; **no lesson inserts**). The now-unused `_draftKey`, `_displayTopicForScheme` and `_inferClassLevelForScheme` helpers are deleted:

```dart
  /// Populates the scheme lookup used to display term labels on lesson
  /// cards. Does NOT create lessons — plan creation is now exclusively the
  /// explicit "Plan My Term" flow (silent draft seeding was removed).
  Future<void> _loadSchemesForDisplay() async {
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) return;

      final schemes = (await db.schemeOfWorkDao.getSaved())
          .where((scheme) => scheme.schoolId == school.localId)
          .toList();
      final schemeMap = <int, SchemeOfWorkData>{
        for (final scheme in schemes) scheme.id: scheme,
      };
      if (mounted) {
        setState(() {
          _schemesById
            ..clear()
            ..addAll(schemeMap);
        });
      } else {
        _schemesById
          ..clear()
          ..addAll(schemeMap);
      }
    } catch (_) {
      // Display-only; failure is not worth interrupting the screen.
    }
  }
```

**e) The "Plan My Term" button** — in the AppBar actions, visible to non-admins only (admins keep the dedicated SoW screen):

```diff
-            actions: [
+            actions: [
+              if (ref.read(authProvider).currentTeacher?.role != 'admin') ...[
+                FilledButton.tonalIcon(
+                  onPressed: _autoGenerating ? null : _openAutoGenerateDialog,
+                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
+                  label: const Text('Plan My Term'),
+                  style: FilledButton.styleFrom(
+                    padding: const EdgeInsets.symmetric(horizontal: 14),
+                    shape: RoundedRectangleBorder(
+                      borderRadius: BorderRadius.circular(14),
+                    ),
+                  ),
+                ),
+                const SizedBox(width: 8),
+              ],
               const SyncIndicator(),
               const SizedBox(width: 8),
               OfflineCreditCounter(visible: ref.watch(isOfflineProvider)),
```

**f) The dialog + generation flow** (new methods on the state class):

```dart
  static const _prefAutoGenerateSubject = 'auto_generate_subject';
  static const _prefAutoGenerateClass = 'auto_generate_class';
  static const _prefAutoGenerateTerm = 'auto_generate_term';

  Future<void> _openAutoGenerateDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSubject = prefs.getString(_prefAutoGenerateSubject) ?? 'Mathematics';
    final savedClass = prefs.getString(_prefAutoGenerateClass) ?? 'JSS 1';
    final savedTerm = prefs.getString(_prefAutoGenerateTerm) ?? '1st Term';

    final subject = _selectedSubjectFilter != 'All' ? _selectedSubjectFilter : savedSubject;
    final classLevel = _selectedClassFilter != 'All' ? _selectedClassFilter : savedClass;
    final termLabel = _selectedTermFilter != 'All' ? _selectedTermFilter : savedTerm;

    // Subject options = curated subjects + any subjects the teacher already
    // has lessons for (so a filter like "French" stays selected instead of
    // silently falling back to Mathematics).
    final filterSubjects = _selectedSubjectFilter != 'All'
        ? [_selectedSubjectFilter]
        : const <String>[];
    final subjectOptions = <String>[
      ...filterSubjects,
      ...nerdcSubjects,
    ].toSet().toList();

    final selection = await showDialog<_AutoGenerateSelection>(
      context: context,
      builder: (ctx) => _AutoGenerateDialog(
        subjectOptions: subjectOptions,
        initialSubject: subject,
        initialClassLevel: classLevel,
        initialTerm: termLabel,
      ),
    );
    if (selection == null || !mounted) return;

    await prefs.setString(_prefAutoGenerateSubject, selection.subject);
    await prefs.setString(_prefAutoGenerateClass, selection.classLevel);
    await prefs.setString(_prefAutoGenerateTerm, selection.termLabel);

    await _runAutoGenerate(selection);
  }

  Future<void> _runAutoGenerate(_AutoGenerateSelection selection) async {
    if (mounted) setState(() => _autoGenerating = true);
    try {
      final db = ref.read(databaseProvider);
      final authState = ref.read(authProvider);
      final school = authState.currentSchool ?? await db.schoolsDao.get();
      if (school == null) throw Exception('School data not available');

      // ── 1. Build the 13-week topic list (curated first, AI fallback) ──
      List<Map<String, dynamic>> weeks;
      final curated = getNerdcTopics(
        selection.subject, selection.classLevel, selection.termLabel);
      if (curated != null) {
        weeks = [
          for (var i = 0; i < curated.length; i++)
            {
              'week': i + 1,
              'topic': curated[i].topic,
              'objectives': curated[i].objectives.join('\n'),
            },
        ];
      } else {
        // AI fallback — requires internet.
        if (!await PlatformHelper.isOnline()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No internet connection. This subject is not in the built-in '
                  'list yet — connect to the internet to generate it.',
                ),
              ),
            );
          }
          return;
        }
        final aiService = AiService(db: db);
        await aiService.checkDailyLimit(
          school.subscriptionTier.isEmpty ? 'free' : school.subscriptionTier);
        final prompt = PromptTemplates.schemeOfWork(
          selection.subject, selection.classLevel, selection.termLabel);
        final result = await aiService.generate(prompt);
        weeks = parseSchemeWeeks(result);
        await aiService.logGeneration(
          teacherId: authState.currentTeacher?.localId?.toString(),
          schoolId: school.localId.toString(),
          topic: 'SoW: ${selection.subject} ${selection.termLabel}',
        );
        if (weeks.isEmpty) throw Exception('AI returned no weeks');
      }

      // ── 2. Resolve teacher local id ──
      final teacherServerId = authState.currentTeacher?.serverId;
      final teacher = teacherServerId != null
          ? await db.teachersDao.findByServerId(teacherServerId)
          : null;
      if (teacher == null) throw Exception('Teacher account not ready yet');

      final service = SchemeOfWorkService(db);

      // ── 3. Already have a plan? Warn before deleting + recreating ──
      final existing = await service.findSchemes(
        schoolId: school.localId,
        teacherId: teacher.localId,
        subject: selection.subject,
        classLevel: selection.classLevel,
        term: selection.termLabel,
      );
      if (existing.isNotEmpty) {
        if (!mounted) return;
        final recreate = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace your plan?'),
            content: const Text(
              'You already have a plan for this class and subject. '
              'Creating again will delete your existing plan and its draft '
              'lessons, then build a fresh one.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                child: const Text('Create Again'),
              ),
            ],
          ),
        );
        if (recreate != true || !mounted) return;
        await service.deleteSchemeAndLinkedDrafts(
          schoolId: school.localId,
          teacherId: teacher.localId,
          subject: selection.subject,
          classLevel: selection.classLevel,
          term: selection.termLabel,
        );
      }

      // ── 4. Write everything in one transaction ──
      await service.saveScheme(
        schoolId: school.localId,
        teacherId: teacher.localId,
        subject: selection.subject,
        classLevel: selection.classLevel,
        term: _termForStorage(selection.termLabel),
        weeks: weeks,
      );

      ref.invalidate(lessonsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your plan is ready! Tap a week to start writing.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create plan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _autoGenerating = false);
    }
  }

  /// Maps the dialog's '1st Term' labels to the storage form ('First') used
  /// by existing scheme rows.
  String _termForStorage(String termLabel) {
    switch (termLabel) {
      case '2nd Term':
        return 'Second';
      case '3rd Term':
        return 'Third';
      default:
        return 'First';
    }
  }
```

**g) The dialog widget** (new, at file bottom near `_LessonFiltersPanel`):

```dart
class _AutoGenerateSelection {
  final String subject;
  final String classLevel;
  final String termLabel;
  const _AutoGenerateSelection(this.subject, this.classLevel, this.termLabel);
}

class _AutoGenerateDialog extends StatefulWidget {
  const _AutoGenerateDialog({
    required this.subjectOptions,
    required this.initialSubject,
    required this.initialClassLevel,
    required this.initialTerm,
  });

  final List<String> subjectOptions;
  final String initialSubject;
  final String initialClassLevel;
  final String initialTerm;

  @override
  State<_AutoGenerateDialog> createState() => _AutoGenerateDialogState();
}

class _AutoGenerateDialogState extends State<_AutoGenerateDialog> {
  static const _classes = ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];
  static const _terms = ['1st Term', '2nd Term', '3rd Term'];

  late String _subject;
  late String _classLevel;
  late String _term;

  @override
  void initState() {
    super.initState();
    _subject = widget.subjectOptions.contains(widget.initialSubject)
        ? widget.initialSubject
        : widget.subjectOptions.first;
    _classLevel = _classes.contains(widget.initialClassLevel)
        ? widget.initialClassLevel
        : _classes.first;
    _term = _terms.contains(widget.initialTerm) ? widget.initialTerm : _terms.first;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Plan My Term'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This will create a complete scheme of work for '
            '$_subject, $_classLevel, $_term with 13 weekly topics and '
            'linked draft lessons. Ready?',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _subject,
            decoration: const InputDecoration(labelText: 'Subject'),
            items: widget.subjectOptions
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) => setState(() => _subject = v ?? _subject),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _classLevel,
            decoration: const InputDecoration(labelText: 'Class Level'),
            items: _classes
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _classLevel = v ?? _classLevel),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _term,
            decoration: const InputDecoration(labelText: 'Term'),
            items: _terms
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _term = v ?? _term),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _AutoGenerateSelection(_subject, _classLevel, _term),
          ),
          child: const Text('Create'),
        ),
      ],
    );
  }
}
```

**h) Empty-state copy** (optional, plain English) — "Tap New Lesson to create one." becomes:

```
'Tap Plan My Term to build your whole term at once, or New Lesson for a single lesson.'
```

---

### 3.4 `lib/features/scheme_of_work/screens/scheme_of_work_screen.dart` — `_saveScheme` becomes a thin wrapper

The ~260-line `_saveScheme` body is replaced by a call to the shared service. Everything else in the screen is untouched (behavior identical for admins).

```dart
  Future<void> _saveScheme() async {
    if (_schoolId == null || _teacherId == null) return;
    try {
      final db = ref.read(databaseProvider);
      final service = SchemeOfWorkService(db);

      final weeks = _weeks.map((week) {
        final weekNumber = (week['week'] as int?) ?? 0;
        return <String, dynamic>{
          'week': weekNumber,
          'topic': _topicControllers[weekNumber]?.text ??
              week['topic']?.toString() ??
              '',
          'objectives': _objectivesControllers[weekNumber]?.text ??
              week['objectives']?.toString() ??
              '',
        };
      }).toList();

      _weekRecordIds = await service.saveScheme(
        schoolId: _schoolId!,
        teacherId: _teacherId!,
        subject: _subject,
        classLevel: _classLevel,
        term: _term,
        weeks: weeks,
        existingWeekRecordIds: _weekRecordIds,
      );

      await _loadSchemeForSelection();
      if (mounted) {
        showInfoToast(context: context, message: 'Scheme of Work saved!');
      }
    } catch (e, stackTrace) {
      debugPrint('[SOW] Save failed: $e');
      debugPrint('[SOW] Save stack trace:\n$stackTrace');
      if (mounted) {
        showErrorToast(context: context, message: 'Save failed: $e');
      }
    }
  }
```

---

### 3.5 `lib/router/app_router.dart` — `/scheme-of-work` becomes admin-only

```diff
     final isAdminRoute =
-        location == '/admin' || location.startsWith('/admin/teachers/');
+        location == '/admin' ||
+        location.startsWith('/admin/teachers/') ||
+        location == '/scheme-of-work';
     final isPaymentRoute = location == '/payment';
-
-    // Override: /scheme-of-work is accessible by both roles so skip redirect
-    if (location == '/scheme-of-work') return null;
 
     if (role == 'admin') {
       // Teacher-only routes — admins should never access these.
       if (isTeacherRoute) return '/admin';
       return null;
     }
 
-    // Non-admin users should never reach admin-only routes.
-    if (isAdminRoute) return '/';
+    // Non-admin users should never reach admin-only routes (this now includes
+    // /scheme-of-work — teachers plan their term via "Plan My Term" instead).
+    if (isAdminRoute) return '/';
```

Result: teachers who know the URL are redirected to `/`; admins can still open the screen normally.

---

### 3.6 `lib/features/dashboard/screens/dashboard_screen.dart` — hide the SoW tab for teachers

**a) Editor layout side-nav** (`_EditorLayoutState._navItems`):

```diff
       NavItem(icon: Icons.quiz_rounded, label: 'Exams', route: '/exams'),
       // NavItem(icon: Icons.inventory_2_rounded, label: 'Vault', route: '/vault'), // Vault feature disabled
-      NavItem(icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
+      if (isAdmin)
+        NavItem(icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
       if (isAdmin)
         NavItem(icon: Icons.admin_panel_settings_rounded, label: 'Admin', route: '/admin'),
```

**b) Reader layout bottom-nav** (Android). Make the destinations data-driven so the Scheme tab can be omitted for teachers without breaking the index mapping:

```diff
-      bottomNavigationBar: _ReaderBottomNav(
-        selectedIndex: _selectedIndex,
-        cs: cs,
-        theme: theme,
-        onTap: (index) {
-          setState(() => _selectedIndex = index);
-          _onNavDestination(context, index);
-        },
-      ),
+      bottomNavigationBar: _ReaderBottomNav(
+        selectedIndex: _selectedIndex,
+        cs: cs,
+        theme: theme,
+        destinations: _navSpecs,
+        onTap: (spec) {
+          setState(() => _selectedIndex = spec.index);
+          _onNavDestination(context, spec.route);
+        },
+      ),
```

New getter on `_ReaderLayoutState`:

```dart
  List<_ReaderNavSpec> get _navSpecs {
    final isAdmin = ref.read(authProvider).currentTeacher?.role == 'admin';
    return [
      const _ReaderNavSpec(icon: Icons.home_rounded, label: 'Home', route: 'home'),
      const _ReaderNavSpec(
          icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons', isFilled: true),
      const _ReaderNavSpec(icon: Icons.quiz_rounded, label: 'Exams', route: 'exams'),
      if (isAdmin)
        const _ReaderNavSpec(
            icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
      const _ReaderNavSpec(icon: Icons.more_horiz_rounded, label: 'More', route: '/settings'),
    ];
  }
```

`_onNavDestination` becomes route-based (indices no longer shift):

```diff
-  void _onNavDestination(BuildContext context, int index) {
-    switch (index) {
-      case 0:
+  void _onNavDestination(BuildContext context, String route) {
+    switch (route) {
+      case 'home':
         break; // Home (already here)
-      case 1:
+      case '/lessons':
         _goToLessonsDeferred(context);
         break;
-      case 2:
+      case 'exams':
         _showReaderExamPopup(context);
         break;
-      case 3:
+      case '/scheme-of-work':
         context.go('/scheme-of-work');
         break;
-      case 4:
+      case '/settings':
         context.go('/settings');
         break;
     }
   }
```

`_ReaderBottomNav` renders the passed destinations and drops its hard-coded five items:

```dart
class _ReaderNavSpec {
  final IconData icon;
  final String label;
  final String route;
  final bool isFilled;
  const _ReaderNavSpec({
    required this.icon,
    required this.label,
    required this.route,
    this.isFilled = false,
  });
}

class _ReaderBottomNav extends StatelessWidget {
  const _ReaderBottomNav({
    required this.selectedIndex,
    required this.cs,
    required this.theme,
    required this.destinations,
    required this.onTap,
  });

  final int selectedIndex;
  final ColorScheme cs;
  final ThemeData theme;
  final List<_ReaderNavSpec> destinations;
  final ValueChanged<_ReaderNavSpec> onTap;

  // ... container/decoration unchanged ...
  child: Row(
    children: [
      for (final spec in destinations)
        Expanded(child: _BottomNavItem(
          icon: spec.icon,
          label: spec.label,
          isActive: selectedIndex == spec.index,
          isFilled: spec.isFilled,
          cs: cs,
          theme: theme,
          onTap: () => onTap(spec),
        )),
    ],
  ),
}
```

`_ReaderNavSpec.index` is the list position (computed in the getter as `_navSpecs.indexOf(spec)` or simply its position — teachers see 4 tabs, admins 5; `isActive` matches the tapped position). For the class to carry an index, the spec is constructed with `index` assigned from the getter:

```dart
  List<_ReaderNavSpec> get _navSpecs {
    final isAdmin = ref.read(authProvider).currentTeacher?.role == 'admin';
    final specs = <_ReaderNavSpec>[
      const _ReaderNavSpec(icon: Icons.home_rounded, label: 'Home', route: 'home'),
      const _ReaderNavSpec(
          icon: Icons.menu_book_rounded, label: 'Lessons', route: '/lessons', isFilled: true),
      const _ReaderNavSpec(icon: Icons.quiz_rounded, label: 'Exams', route: 'exams'),
      if (isAdmin)
        const _ReaderNavSpec(
            icon: Icons.calendar_month_rounded, label: 'Scheme of Work', route: '/scheme-of-work'),
      const _ReaderNavSpec(icon: Icons.more_horiz_rounded, label: 'More', route: '/settings'),
    ];
    for (var i = 0; i < specs.length; i++) {
      specs[i] = _ReaderNavSpec(
        icon: specs[i].icon,
        label: specs[i].label,
        route: specs[i].route,
        isFilled: specs[i].isFilled,
        index: i,
      );
    }
    return specs;
  }
```

---

## Edge cases (requirement 3.2.5)

| Case | Handling |
|---|---|
| **Offline + curated combo** | Works with no network — topics come from the Dart file, DB writes are local. |
| **Offline + missing combo** | `PlatformHelper.isOnline()` check before the AI call → clear "No internet connection" SnackBar, nothing is written. |
| **Already have a plan** | `findSchemes` match on subject+class+term → warning dialog ("Replace your plan? … will delete your existing plan and draft lessons") → only proceeds on explicit confirm. |
| **Partial failure** | `saveScheme` and `deleteSchemeAndLinkedDrafts` each run inside a single `db.transaction` — rollback on any error. |
| **AI returns malformed/empty** | `parseSchemeWeeks` throws → caught → error SnackBar; no partial data (transaction never started). |
| **Teacher row missing** | Guarded with a clear error message; nothing is written. |

**Audit finding #3 — recreate is two transactions (open question for you).** The "Create Again" path runs `deleteSchemeAndLinkedDrafts` (transaction 1) then `saveScheme` (transaction 2). If the save fails or the app is killed between the two, the old plan is gone and the new one is missing. Recommended fix (one line of API): add `bool deleteExistingFirst = false` to `saveScheme` and run both inside its single transaction — the confirmation dialog already happens before either call, so there is no UX downside. I did not bake this in without your call since it changes the service API shape.

---

## What happens to existing data — no migration needed

- **Existing schemes and topic links are untouched.** The recommended design does not remove the SoW screen — it hides it from teachers and keeps it for admins, and it does not drop any tables or columns.
- **Existing draft lessons** created by the old silent seeding remain in place (soft-delete free); only future silent seeding stops.
- **Regeneration** deletes only the specific plan's scheme rows + its linked draft lessons/exams, and only after the user confirms. That data is recreated immediately.
- **Risks to flag (not blockers):**
  1. **Pre-existing sync gap:** `scheme_of_work` rows are queued for sync but the server push path for schemes is broken today (found in the earlier audit). Regeneration queues local deletes/inserts; server-side rows may not reflect them until that gap is fixed. Recommend fixing the scheme sync push before shipping this feature.
  2. **Hard delete vs soft delete:** scheme rows are hard-deleted locally on regeneration (there is no `isDeleted` filter in the scheme queries, so soft-deleting wouldn't hide them). Linked lessons/exams are soft-deleted via the existing DAO methods. Because the plan is recreated immediately, the window of "missing" data is one transaction.
  3. **Curated-list accuracy:** drafted from public NERDC knowledge — recommend a subject-teacher review pass; the fallback covers anything not yet curated.

## What was NOT touched (per AGENTS.md)

- Auth flow — untouched.
- Database schema — no table/column changes (one DAO method added only).
- Existing provider logic — untouched.
- No new dependencies — `nerdc_curriculum.dart`, the service, the dialog all use existing packages (`drift`, `shared_preferences`, `supabase_flutter`).

## Verification plan (after you approve)

1. `flutter analyze --no-pub` (never `flutter clean` / `dart analyze`).
2. `flutter test --no-pub`.
3. Manual pass: teacher login → Lessons → Plan My Term → Create → 13 draft lessons appear; regenerate warns first; admin still sees the SoW tab and screen.
