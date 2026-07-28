-- ============================================================================
-- Migration: Cleanup orphan server_id=NULL duplicate lessons/exams
-- Date: 2026-07-27 20:55:00 UTC+1
-- Description:
--   During the July 21–25 backlog-repair window, a lesson could be pushed
--   to the server (creating a row where server_id=NULL because the push
--   succeeded but _updateLocalServerId crashed before storing the returned
--   UUID), then the queue entry was reset on July 25 and re-pushed
--   successfully — creating a second row with server_id=NULL (the re-push
--   was a fresh INSERT without a server_id since the local row still had
--   no serverId stored locally).
--
--   Both rows have server_id=NULL, so the partial UNIQUE index
--   `idx_lessons_server_id WHERE server_id IS NOT NULL` does NOT catch
--   them — it only applies to non-null values.
--
--   === Curriculum-slot identity (what makes two lessons "the same") ===
--   For lessons: (school_id, subject_id, class_level, week, topic, teacher_id)
--   For exams:   (school_id, subject_id, class_level, topic, teacher_id)
--     (exams don't have a `week` column)
--
--   These are the UUID FK columns set by resolveForeignKeys() during the
--   sync-push INSERT flow.  We use COALESCE to handle any edge-case NULLs.
--
--   === Strategy ===
--   For each group of server_id IS NULL rows sharing the same slot identity,
--   keep the row with the LATEST created_at (the July 25 one — which is
--   complete and correctly formed) and remove the earlier orphan(s).
--
-- SAFETY: Full table snapshots are taken BEFORE any destructive operations
-- so you can restore any row if needed.
-- ============================================================================

-- ╔═════════════════════════════════════════════════════════════════════════╗
-- ║  DIAGNOSTIC QUERIES — Run these FIRST before any DELETE               ║
-- ╚═════════════════════════════════════════════════════════════════════════╝
--
-- ── DIAG 1: How many duplicate groups exist in lessons? ──────────────────
--   SELECT COUNT(*) AS lesson_duplicate_group_count FROM (
--     SELECT COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--            COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--            class_level, week, topic,
--            COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     FROM lessons
--     WHERE server_id IS NULL
--       AND is_deleted = false
--     GROUP BY COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--              COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--              class_level, week, topic,
--              COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     HAVING COUNT(*) > 1
--   ) AS dupes;
--
-- ── DIAG 2: Show all orphan rows (server_id IS NULL) that are part of a
--            duplicate group, ordered by group size DESC then by created_at ASC.
--            The row with rn=1 in each group is the KEEPER (latest created_at).
--            Rows with rn>1 will be DELETED. ──────────────────────────────
--   SELECT *, ranked.rn
--   FROM (
--     SELECT *,
--            ROW_NUMBER() OVER (
--              PARTITION BY
--                COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--                COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--                class_level, week, topic,
--                COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--              ORDER BY created_at DESC
--            ) AS rn,
--            COUNT(*) OVER (
--              PARTITION BY
--                COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--                COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--                class_level, week, topic,
--                COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--            ) AS group_size
--     FROM lessons
--     WHERE server_id IS NULL
--       AND is_deleted = false
--   ) ranked
--   WHERE group_size > 1
--   ORDER BY group_size DESC, rn ASC, created_at ASC;
--
-- ── DIAG 3: Same as DIAG 2 but ONLY for the specific teacher ────────────
--   (replace the UUID with the actual teacher id)
--   SELECT *, ranked.rn
--   FROM (
--     SELECT *,
--            ROW_NUMBER() OVER (
--              PARTITION BY
--                COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--                COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--                class_level, week, topic,
--                COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--              ORDER BY created_at DESC
--            ) AS rn,
--            COUNT(*) OVER (
--              PARTITION BY
--                COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--                COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--                class_level, week, topic,
--                COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--            ) AS group_size
--     FROM lessons
--     WHERE server_id IS NULL
--       AND is_deleted = false
--       AND teacher_id = 'f51dce33-3aa8-425a-9c19-c14334a49cfa'
--   ) ranked
--   WHERE group_size > 1
--   ORDER BY group_size DESC, rn ASC, created_at ASC;
--
-- ── DIAG 4: How many orphan rows will be DELETED from lessons? ──────────
--   SELECT COUNT(*) AS lessons_rows_to_delete FROM (
--     SELECT id, ROW_NUMBER() OVER (
--       PARTITION BY
--         COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--         COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--         class_level, week, topic,
--         COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--       ORDER BY created_at DESC
--     ) AS rn
--     FROM lessons
--     WHERE server_id IS NULL AND is_deleted = false
--   ) ranked
--   WHERE rn > 1;
--
-- ── DIAG 5: How many orphan rows will be KEPT in lessons? ──────────────
--   SELECT COUNT(*) AS lessons_rows_to_keep FROM (
--     SELECT id, ROW_NUMBER() OVER (
--       PARTITION BY
--         COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--         COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--         class_level, week, topic,
--         COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--       ORDER BY created_at DESC
--     ) AS rn
--     FROM lessons
--     WHERE server_id IS NULL AND is_deleted = false
--   ) ranked
--   WHERE rn = 1;
--
-- ── DIAG 6: Same as DIAG 4 & 5 for exams ───────────────────────────────
--   SELECT COUNT(*) AS exams_rows_to_delete FROM (
--     SELECT id, ROW_NUMBER() OVER (
--       PARTITION BY
--         COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--         COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--         class_level, topic,
--         COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--       ORDER BY created_at DESC
--     ) AS rn
--     FROM exams
--     WHERE server_id IS NULL AND is_deleted = false
--   ) ranked
--   WHERE rn > 1;

-- ╔═════════════════════════════════════════════════════════════════════════╗
-- ║  ACTUAL CLEANUP — Run AFTER confirming diagnostic counts               ║
-- ╚═════════════════════════════════════════════════════════════════════════╝

-- ── STEP 0: Snapshot tables before any destructive operations ─────────────
CREATE TABLE IF NOT EXISTS lessons_backup_20260727_orphan_dedup AS
SELECT * FROM lessons;

CREATE TABLE IF NOT EXISTS exams_backup_20260727_orphan_dedup AS
SELECT * FROM exams;

-- ── STEP 1: Delete orphan duplicate lessons ──────────────────────────────
-- For each group of server_id IS NULL rows sharing the same curriculum slot,
-- keep the row with the LATEST created_at (the July 25 one).
WITH ranked_lessons AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY
        COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
        COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
        class_level, week, topic,
        COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
      ORDER BY created_at DESC
    ) AS rn
  FROM lessons
  WHERE server_id IS NULL
    AND is_deleted = false
)
DELETE FROM lessons
WHERE id IN (
  SELECT id FROM ranked_lessons WHERE rn > 1
);

-- ── STEP 2: Delete orphan duplicate exams ────────────────────────────────
WITH ranked_exams AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY
        COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
        COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
        class_level, topic,
        COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
      ORDER BY created_at DESC
    ) AS rn
  FROM exams
  WHERE server_id IS NULL
    AND is_deleted = false
)
DELETE FROM exams
WHERE id IN (
  SELECT id FROM ranked_exams WHERE rn > 1
);

-- ╔═════════════════════════════════════════════════════════════════════════╗
-- ║  POST-CLEANUP VERIFICATION                                             ║
-- ╚═════════════════════════════════════════════════════════════════════════╝
--
-- Verify 1: Should return 0 rows
--   SELECT COUNT(*) AS remaining_lesson_duplicates FROM (
--     SELECT COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--            COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--            class_level, week, topic,
--            COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     FROM lessons
--     WHERE server_id IS NULL AND is_deleted = false
--     GROUP BY COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--              COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--              class_level, week, topic,
--              COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     HAVING COUNT(*) > 1
--   ) AS dupes;
--
-- Verify 2: Should return 0 rows
--   SELECT COUNT(*) AS remaining_exam_duplicates FROM (
--     SELECT COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--            COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--            class_level, topic,
--            COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     FROM exams
--     WHERE server_id IS NULL AND is_deleted = false
--     GROUP BY COALESCE(school_id, '00000000-0000-0000-0000-000000000000'),
--              COALESCE(subject_id, '00000000-0000-0000-0000-000000000000'),
--              class_level, topic,
--              COALESCE(teacher_id, '00000000-0000-0000-0000-000000000000')
--     HAVING COUNT(*) > 1
--   ) AS dupes;
--
-- Verify 3: Total remaining
--   SELECT 'lessons' AS tbl, COUNT(*) AS remaining FROM lessons WHERE is_deleted = false
--   UNION ALL
--   SELECT 'exams', COUNT(*) FROM exams WHERE is_deleted = false;
--
-- To restore from backup if needed:
--   TRUNCATE lessons;
--   INSERT INTO lessons SELECT * FROM lessons_backup_20260727_orphan_dedup;
--   TRUNCATE exams;
--   INSERT INTO exams SELECT * FROM exams_backup_20260727_orphan_dedup;
