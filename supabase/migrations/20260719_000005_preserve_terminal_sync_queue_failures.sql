-- Preserve terminal sync failures on the server-side queue table as well.
ALTER TABLE public.sync_queue
  ADD COLUMN IF NOT EXISTS is_terminal BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.sync_queue
  ADD COLUMN IF NOT EXISTS last_error TEXT;

ALTER TABLE public.sync_queue
  ADD COLUMN IF NOT EXISTS failed_at TIMESTAMPTZ;

-- security_config should not remain in the queue after the client-side fix.
DELETE FROM public.sync_queue
WHERE queue_table = 'security_config';
