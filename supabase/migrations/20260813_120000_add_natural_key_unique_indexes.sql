-- ═══════════════════════════════════════════════════════════════════════════════
-- Migration: Natural-key unique indexes for sync full-table reconciliation
-- Date: 2026-08-13
-- Purpose (Fix 5, decision (a) — see plans/sync_full_table_reconciliation.md):
--   Atomic backstop for the sync-push check-before-insert guard. A first-time
--   INSERT re-pushed after the server committed but the client lost the
--   response (or a reconciliation re-queue racing a concurrent push) would
--   otherwise create a duplicate row. These partial unique indexes make the
--   duplicate impossible at the database level; sync-push converts the
--   resulting duplicate-key error into an UPDATE on the winning row.
--
--   All indexes are PARTIAL so soft-deleted / deactivated rows never block
--   re-creating a live row:
--     * scheme_of_work / lessons / exams: WHERE is_deleted = false
--       (the lessons index MUST be partial — one historical soft-deleted dup
--       verified live on 2026-08-13: teacher b9e5f991-…, week 1, JSS 1).
--     * subjects: WHERE is_active = true AND deleted_at IS NULL (subjects has
--       no is_deleted column).
--
--   Keys mirror the app's own identity rules:
--     * scheme_of_work: one school-shared row per subject+term+week (teacher
--       is NOT identity).
--     * lessons: (school, teacher, subject, class, week, term) — the exact key
--       migration 20260730_002556 used to dedupe lessons.
--     * exams: (school, teacher, subject, class, week_number, term, topic) —
--       the app's findByTopicSubjectTeacher key.
--     * subjects: (school, normalized name, class_level) — class_level is part
--       of the key because per-class provisioning is legitimate (same name,
--       different classes, e.g. "Mathematics"/"JSS 1").
--
--   Verified against live data on 2026-08-13: no active duplicate exists for
--   any of the four keys, so all indexes create cleanly.
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE UNIQUE INDEX IF NOT EXISTS idx_scheme_of_work_natural_key
  ON scheme_of_work (school_id, subject_id, term, week_number)
  WHERE is_deleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_lessons_natural_key
  ON lessons (
    school_id,
    teacher_id,
    subject_id,
    class_level,
    week,
    COALESCE(term, '')
  )
  WHERE is_deleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_exams_natural_key
  ON exams (
    school_id,
    teacher_id,
    subject_id,
    class_level,
    week_number,
    COALESCE(term, ''),
    COALESCE(topic, '')
  )
  WHERE is_deleted = false;

CREATE UNIQUE INDEX IF NOT EXISTS idx_subjects_natural_key
  ON subjects (
    school_id,
    LOWER(BTRIM(subject_name)),
    class_level
  )
  WHERE is_active = true AND deleted_at IS NULL;
