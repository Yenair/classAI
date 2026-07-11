-- Seed exam_generation_allowed_tiers, bulk_pdf_export_allowed_tiers,
-- ai_diagrams_allowed_tiers, and sync_health_allowed_tiers into app_config
INSERT INTO public.app_config (key, value) VALUES
  ('exam_generation_allowed_tiers', '["basic","standard","elite"]'),
  ('bulk_pdf_export_allowed_tiers', '["standard","elite"]'),
  ('ai_diagrams_allowed_tiers', '["elite"]'),
  ('sync_health_allowed_tiers', '["elite"]')
ON CONFLICT (key) DO NOTHING;
