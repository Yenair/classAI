-- Add all scheme_of_work columns that the Dart client and sync-push code
-- already reference but that don't exist server-side (Findings #3/#5/#9).
--
-- This table has zero production rows, so all additions are safe.
-- Uses IF NOT EXISTS throughout — no drops, no renames, no data risk.

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS server_id TEXT;

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS teacher_id uuid
    REFERENCES public.teachers(id);

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS status text
    NOT NULL DEFAULT 'draft';

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS admin_edited_topic TEXT;
ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS admin_comment TEXT;

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS class_level TEXT
    NOT NULL DEFAULT '';

ALTER TABLE public.scheme_of_work ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN
    NOT NULL DEFAULT false;

-- Ensure the status column only accepts the exact values the Dart client uses.
-- Four values confirmed from codebase analysis (scheme_of_work_screen.dart,
-- scheme_of_work_dao.dart, scheme_of_work.dart):
--   'draft'    — default/initial state (line 496, 516)
--   'pending'  — submitted for admin approval (line 685)
--   'approved' — admin-approved (line 737, 764)
--   'rejected' — admin-rejected (line 934)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.scheme_of_work'::regclass
        AND conname = 'scheme_of_work_status_check'
    ) THEN
        ALTER TABLE public.scheme_of_work
            ADD CONSTRAINT scheme_of_work_status_check
            CHECK (status IN ('draft', 'pending', 'approved', 'rejected'));
    END IF;
END $$;
