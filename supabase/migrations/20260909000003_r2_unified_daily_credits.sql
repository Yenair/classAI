-- R2 Block 4: unified daily credits
-- 2A.5: Remove the legacy per-feature limit keys — the unified
--       daily_credits_limit key (20260908000002) replaces both.
-- 2A.6a/2A.6b: Unlock content that was generated before the manual
--       unlock flow was removed, so it does not become permanently
--       read-only in clients that ship Release 2.
--
-- Safe to re-apply (idempotent).

-- ── 2A.5: remove legacy limit keys ──────────────────────────────────────
DELETE FROM public.app_config WHERE key = 'daily_preview_limits';
DELETE FROM public.app_config WHERE key = 'daily_generation_limits';

-- ── 2A.6a: lessons — status-based (generated or completed) ──────────────
-- Drafts the teacher created by hand stay locked, matching the plan's
-- choice of status over content heuristics.
UPDATE public.lessons
SET is_unlocked = true
WHERE is_unlocked = false
  AND status IN ('generated', 'completed');

-- ── 2A.6b: exams — no status column, inspect content instead ────────────
-- Unlock any exam whose content JSON has at least one question of any
-- type. Legacy rows whose content is not valid JSON (encrypted rows)
-- do not match and stay locked — audit those manually if any remain.
UPDATE public.exams
SET is_unlocked = true
WHERE is_unlocked = false
  AND (
    COALESCE(json_array_length(json_extract(content, '$.mcqs')), 0) > 0
    OR COALESCE(json_array_length(json_extract(content, '$.theory')), 0) > 0
    OR COALESCE(json_array_length(json_extract(content, '$.subjective')), 0) > 0
  );
