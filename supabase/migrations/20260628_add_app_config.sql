CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Insert default values
INSERT INTO public.app_config (key, value) VALUES
  ('subscription_prices', '{"basic":49999,"standard":99999,"elite":249999}'),
  ('daily_preview_limits', '{"free":0,"basic":10,"standard":10,"elite":-1}'),
  ('pdf_export_limits', '{"free":1,"basic":3,"standard":5,"elite":-1}'),
  ('feature_vault_publishing', 'true'),
  ('feature_scheme_generation', 'true'),
  ('announcement_text', ''),
  ('min_app_version', '1.0.0')
ON CONFLICT (key) DO NOTHING;
