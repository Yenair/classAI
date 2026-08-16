-- Enforce subscription-tier gating on exam generation: only Standard and
-- Elite schools may generate exams. This overwrites any stale live value that
-- may still include "basic", so Free and Basic schools are locked out.
INSERT INTO public.app_config (key, value)
VALUES ('exam_generation_allowed_tiers', '["standard","elite"]')
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value;
