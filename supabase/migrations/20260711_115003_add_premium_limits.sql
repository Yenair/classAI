-- Insert teacher_seat_limits and lesson_storage_limits into app_config
INSERT INTO public.app_config (key, value) VALUES
  ('teacher_seat_limits', '{"free":5,"basic":10,"standard":20,"elite":100}'),
  ('lesson_storage_limits', '{"free":10,"basic":20,"standard":50,"elite":-1}')
ON CONFLICT (key) DO NOTHING;
