-- ═══════════════════════════════════════════════════════════════════════════════
-- Migration: Cleanup duplicate lessons and backfill subject text
-- Date: 2026-07-30 00:25:56
-- Purpose:
--   1. Backfill the lessons.subject column from the subjects table via
--      subject_id for rows where subject IS NULL (the sync-push Edge Function
--      deletes the subject text after resolving it to subject_id).
--   2. Delete duplicate lessons on the server that were created because the
--      empty subject caused duplicate-detection to fail on the client.
--   3. Update updated_at so the next sync pull picks up the corrected rows.
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Step 1: Backfill subject text from subjects table ──────────────────────
-- The sync-push Edge Function (line 232-233 in sync-push/index.ts) deletes
-- `subject` from the INSERT payload after resolving it to `subject_id`:
--     delete rowData["subject"];
-- This leaves subject=NULL on the server. The next sync pull then overwrites
-- the local subject (e.g. "Mathematics") with '' because _upsertLessonFromSync
-- reads: final subject = strVal('subject') ?? '';
UPDATE lessons l
SET subject = COALESCE(
    (SELECT s.subject_name FROM subjects s WHERE s.id = l.subject_id),
    ''
)
WHERE l.subject IS NULL OR l.subject = '';

-- ── Step 2: Identify and soft-delete duplicate lessons ────────────────────
-- Duplicate rows (weeks 2-10) were created because subject='' after the
-- first sync pull, causing the client-side check `l.subject == _subject`
-- to evaluate `"" == "Mathematics"` → false, bypassing dedup.
--
-- Strategy: Keep the OLDEST row per (subject_id, teacher_id, class_level,
-- week, term). Soft-delete newer duplicates.
--
-- The school_id UUID below matches the local school_server_id value.
-- This is the same UUID as schools.id in the Supabase schools table.

WITH dupe_ids AS (
  SELECT id
  FROM (
    SELECT
      id,
      subject_id,
      teacher_id,
      class_level,
      week,
      term,
      created_at,
      ROW_NUMBER() OVER (
        PARTITION BY subject_id, teacher_id, class_level, week, COALESCE(term, '')
        ORDER BY created_at ASC
      ) AS rn
    FROM lessons
    WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
      AND is_deleted = false
  ) ranked
  WHERE rn > 1  -- keep the first (oldest), soft-delete the rest
)
UPDATE lessons l
SET is_deleted = true,
    updated_at = now()
FROM dupe_ids d
WHERE l.id = d.id;

-- ── Step 3: Touch updated_at on corrected rows so sync pull finds them ───
UPDATE lessons
SET updated_at = now()
WHERE subject IS NOT NULL AND subject != ''
  AND updated_at < now() - interval '1 minute';
