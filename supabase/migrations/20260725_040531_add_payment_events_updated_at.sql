-- Add updated_at to payment_events with a BEFORE UPDATE trigger.
--
-- Root cause:
--   sync-pull/index.ts line 86 unconditionally orders EVERY table by
--   updated_at, but payment_events never had this column, causing:
--     "Could not find the 'updated_at' column of 'payment_events' in the
--      schema cache"
--
--   The column is NOT just for the sync error — it also ensures that when
--   confirmed_by_webhook flips to true (via the Flutter app's markConfirmed()
--   → sync-push upsert), the row's updated_at refreshes so sync-pull on
--   other devices picks up the change.
--
--   created_at is TIMESTAMPTZ NOT NULL DEFAULT now(), so updated_at uses
--   the same type for consistency.

-- ── 1. Add the column ────────────────────────────────────────────
ALTER TABLE public.payment_events
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- ── 2. Create a reusable trigger function (public schema) ─────────
--      Mirrors storage.update_updated_at_column() but in the public
--      schema so it can be used by any public table without coupling
--      to the storage extension.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ── 3. Wire up the trigger on payment_events ─────────────────────
--      Fires on every UPDATE so that sync-pull sees the latest
--      timestamp when confirmed_by_webhook changes.
CREATE TRIGGER set_payment_events_updated_at
  BEFORE UPDATE ON public.payment_events
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
