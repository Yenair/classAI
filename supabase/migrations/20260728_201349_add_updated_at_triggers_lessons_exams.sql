-- Add BEFORE UPDATE triggers on lessons and exams so updated_at is
-- automatically refreshed on every UPDATE, regardless of whether the
-- client sends the value. This is defense-in-depth for the
-- lwwByUpdateCounterThenUpdatedAt merge strategy.

-- ── 1. Reuse the existing public.set_updated_at() function ──────────
--      Already created in 20260725_040531_add_payment_events_updated_at.sql

-- ── 2. Wire up triggers on lessons and exams ───────────────────────
CREATE TRIGGER set_lessons_updated_at
  BEFORE UPDATE ON public.lessons
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_exams_updated_at
  BEFORE UPDATE ON public.exams
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();
