-- Fix sync-push: Add local_id to lessons/exams for FK resolution from progress_logs.
-- The sync-push Edge Function now resolves:
--   school_server_id (TEXT UUID) → school_id (uuid FK)
--   teacher_server_id (TEXT UUID) → teacher_id (uuid FK)
--   subject (TEXT name) → subject_id (uuid FK, via subjects.subject_name)
-- and fills NOT NULL defaults for title, credits_spent, objectives, etc.
--
-- For progress_logs, the client sends lesson_id as a local Drift integer.
-- We need a local_id column on lessons to look up the server UUID.

-- ── 1. Add local_id to lessons for progress_logs FK resolution ───
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS local_id INTEGER;
CREATE INDEX IF NOT EXISTS idx_lessons_local_id ON public.lessons(local_id);

-- ── 2. Add local_id to exams for consistency ─────────────────────
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS local_id INTEGER;
CREATE INDEX IF NOT EXISTS idx_exams_local_id ON public.exams(local_id);

-- ── 3. Add missing columns to progress_logs for sync support ─────
ALTER TABLE public.progress_logs ADD COLUMN IF NOT EXISTS server_id TEXT;
ALTER TABLE public.progress_logs ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;

-- ── 4. Reset all stuck queue entries so they retry with the fix ──
UPDATE public.sync_queue
SET attempts = 0,
    last_attempt_at = NULL
WHERE attempts > 0;
