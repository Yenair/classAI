-- Clean up stuck sync_queue entries that can never succeed:
--
-- 1. security_config entries   — table doesn't exist on server (returns 404)
-- 2. schools UPDATE from non-admin — blocked by adminTables guard (retryable: false)
-- 3. Any entry with attempts >= 5   — already exhausted retries
--
-- Also reset entries with 1-4 attempts so they get a fresh try with the fixed code.

-- ── 1. Remove security_config entries (table has no server-side counterpart) ──
DELETE FROM public.sync_queue
WHERE queue_table = 'security_config';

-- ── 2. Remove schools entries queued by non-admin users ─────────────────────
-- These get "Admin access required" from sync-push with retryable=false.
-- We can't tell which user queued each entry from the queue alone, so
-- we remove ALL schools UPDATE entries that have >= 1 attempt (they failed).
DELETE FROM public.sync_queue
WHERE queue_table = 'schools'
  AND operation = 'UPDATE'
  AND attempts >= 1;

-- ── 3. Remove any other entries that have exhausted retries ─────────────────
DELETE FROM public.sync_queue
WHERE attempts >= 5;

-- ── 4. Reset remaining entries so they retry with the fixed code ────────────
UPDATE public.sync_queue
SET attempts = 0,
    last_attempt_at = NULL
WHERE attempts > 0;
