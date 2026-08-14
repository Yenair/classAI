-- Seed assessment_generation_allowed_tiers (Phase 2 lesson questions gate)
-- Gates structured assessment-question generation inside the lesson editor to
-- standard + elite tiers. The `get-config` edge function returns every
-- app_config row, so no function change is needed.
INSERT INTO public.app_config (key, value) VALUES
  ('assessment_generation_allowed_tiers', '["standard","elite"]')
ON CONFLICT (key) DO NOTHING;
