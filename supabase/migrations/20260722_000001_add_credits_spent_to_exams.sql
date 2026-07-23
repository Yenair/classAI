-- Add credits_spent to exams with same definition as lessons.
-- The sync-push Edge Function always sends credits_spent: 0 for exams
-- (see EXAM_DEFAULTS in sync-push/index.ts), but the exams table
-- never had this column, causing every exam push to fail with:
--   "Could not find the 'credits_spent' column of 'exams' in the schema cache"

ALTER TABLE public.exams
  ADD COLUMN IF NOT EXISTS credits_spent INTEGER NOT NULL DEFAULT 0;
