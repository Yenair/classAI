-- Update the shared school-wide lesson/exam storage limits to the 10x plan.
-- Elite remains unlimited (-1).
UPDATE public.app_config
SET value = '{"free":100,"basic":200,"standard":500,"elite":-1}'
WHERE key = 'lesson_storage_limits';
