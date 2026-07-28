-- Add last_sync_at column to teachers table for admin dashboard sync status
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS last_sync_at TIMESTAMPTZ;

-- Backfill: set last_sync_at = updated_at for existing teachers
-- so they don't show "Never" after deploy
UPDATE public.teachers
  SET last_sync_at = updated_at
  WHERE last_sync_at IS NULL;
