-- Seed daily_generation_limits (per-tier AI generation quotas) and
-- topic_restrictions_by_tier (per-tier subject allow-lists) into app_config.
-- The `get-config` edge function returns every app_config row, so no
-- function change is needed.

-- Daily AI generation limits per tier.
-- free=0 (no AI generation), basic=5/day, standard=10/day, elite=-1 (unlimited).
-- These are SEPARATE from daily_preview_limits — generations call the AI;
-- previews may not.
INSERT INTO public.app_config (key, value) VALUES
  ('daily_generation_limits', '{"free":0,"basic":5,"standard":10,"elite":-1}')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Per-tier subject restrictions.
-- free tier is omitted: the tier gate blocks ALL free-tier generation before
-- subjects are ever checked, so a free entry is unreachable and misleading.
-- basic gets the four core academic subjects; standard/elite get all subjects
-- via the "*" wildcard. Subject name must be "Science" (not "Basic Science")
-- to match the hardcoded _subjects list in the editors. When the key is
-- absent the app treats every tier as unrestricted.
INSERT INTO public.app_config (key, value) VALUES
  ('topic_restrictions_by_tier', '{"basic":["Mathematics","English","Science","Social Studies"],"standard":["*"],"elite":["*"]}')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
