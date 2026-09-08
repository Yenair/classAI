-- R2 Block 1 (2A.2): seed daily_credits_limit — the per-tier unified daily
-- credit pool that replaces the separate generation/preview/offline-credit
-- quotas in Release 2 of the credits unification plan.
--
-- free=3 (vault acquisitions only — the tier gate blocks free-tier
--        generation), basic=1, standard=3, elite=-1 (unlimited).
--
-- The `get-config` edge function returns every app_config row, so no
-- function change is needed.
INSERT INTO public.app_config (key, value) VALUES
  ('daily_credits_limit', '{"free":3,"basic":1,"standard":3,"elite":-1}')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
