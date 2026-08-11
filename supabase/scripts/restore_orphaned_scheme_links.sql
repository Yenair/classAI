-- restore_orphaned_scheme_links.sql
--
-- MANUAL ADMIN SCRIPT — DO NOT AUTO-RUN.
--
-- Root cause (Task 1a investigation):
--   lessons.scheme_of_work_id / exams.scheme_of_work_id store LOCAL Drift
--   INTEGER ids (e.g. '1'..'117'), but the server-side `scheme_of_work` table
--   only holds a handful of UUID-id rows (server_id = null, E2E test data).
--   The sync-push pipeline passes these integer values through unchanged with
--   no server-side mapping, so none of the affected links can resolve. As a
--   result those lessons/exams show "scheme of work no longer available".
--
-- This script clears the broken links for the affected school
-- (school_name = 'Yeneabasi Foundation', id = 9ae4dd4d-436b-4aad-8827-81c53920c4dd).
-- It is scoped by school_id (verified against information_schema) and only
-- touches non-deleted rows (is_deleted = false), matching the client-side repair.
--
-- Run it ONLY after confirming the affected set, and review the row counts
-- returned before committing. It is wrapped in a transaction; do not schedule it.
--
-- NOTE: This is a server-side data correction. It complements the client-side
-- repair in lib/core/database/repair_orphaned_scheme_links.dart (which clears
-- the local links). Run this manually; do not auto-run.

BEGIN;

-- Sanity check: how many rows will be affected before running the UPDATEs.
SELECT 'lessons' AS entity, count(*) AS affected_rows
FROM lessons
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

SELECT 'exams' AS entity, count(*) AS affected_rows
FROM exams
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

-- Clear the orphaned scheme_of_work links for Yeneabasi Foundation lessons.
UPDATE lessons
SET scheme_of_work_id = NULL,
    updated_at = now()
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

-- Clear the orphaned scheme_of_work links for Yeneabasi Foundation exams.
UPDATE exams
SET scheme_of_work_id = NULL,
    updated_at = now()
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

-- Verify nothing remains linked to a non-existent scheme for this school.
SELECT 'lessons' AS entity, count(*) AS remaining
FROM lessons
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

SELECT 'exams' AS entity, count(*) AS remaining
FROM exams
WHERE school_id = '9ae4dd4d-436b-4aad-8827-81c53920c4dd'
  AND is_deleted = false
  AND scheme_of_work_id IS NOT NULL;

COMMIT;
