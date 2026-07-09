-- Fix sync-push: reset stuck queue entries and ensure all columns exist.
-- The root cause was in the sync-push KEY_MAP (ssid→school_server_id, tsid→teacher_server_id)
-- and resolveForeignKeys deleting the subject TEXT value.
-- This migration:
--   1. Ensures any columns the client sends actually exist on lessons/exams
--   2. Resets stuck queue entries so they get a fresh push attempt

-- ── 1. Ensure all client-pushed columns exist on lessons ────────────
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS server_id TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS subject TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS class_level TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS week INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS topic TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS difficulty TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS blooms_verbs TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS curriculum TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS content TEXT NOT NULL DEFAULT '';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS content_hash TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS scheme_of_work_id TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS week_number INTEGER;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS update_counter INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS last_modified_by TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS teacher_server_id TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS school_server_id TEXT;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS is_unlocked BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'draft';
ALTER TABLE public.lessons ADD COLUMN IF NOT EXISTS term TEXT;

-- ── 2. Ensure all client-pushed columns exist on exams ──────────────
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS server_id TEXT;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS subject TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS class_level TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS topic TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS difficulty TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS curriculum TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS content TEXT NOT NULL DEFAULT '';
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS scheme_of_work_id TEXT;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS week_number INTEGER;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS update_counter INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS last_modified_by TEXT;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS teacher_server_id TEXT;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS school_server_id TEXT;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS is_unlocked BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.exams ADD COLUMN IF NOT EXISTS term TEXT;

-- ── 3. Reset stuck queue entries so they retry with the fixed code ───
UPDATE public.sync_queue
SET attempts = 0,
    last_attempt_at = NULL
WHERE attempts > 5;
