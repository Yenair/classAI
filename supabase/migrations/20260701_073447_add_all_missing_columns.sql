-- Comprehensive migration: ensure every column the client pushes exists
-- on the lessons and exams tables with correct snake_case names.
-- Uses IF NOT EXISTS so repeats are safe.

-- ── Lessons table ──────────────────────────────────────────────
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

-- ── Exams table ────────────────────────────────────────────────
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
