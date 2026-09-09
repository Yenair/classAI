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
-- type. Rows whose content is not valid JSON (legacy encrypted rows)
-- or whose question fields are not JSON arrays cannot break the
-- migration: the exception-safe cast maps them to NULL and they stay
-- locked — audit those manually if any remain.
--
-- NOTE: json_extract/json_array_length are SQLite functions; Postgres
-- uses -> / jsonb_array_length. An earlier revision used the SQLite
-- dialect here and failed the push with SQLSTATE 42883.
CREATE OR REPLACE FUNCTION pg_temp.try_cast_jsonb(txt text)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  RETURN txt::jsonb;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

UPDATE public.exams e
SET is_unlocked = true
WHERE e.is_unlocked = false
  AND EXISTS (
    SELECT 1
    FROM (SELECT pg_temp.try_cast_jsonb(e.content) AS j) parsed
    WHERE parsed.j IS NOT NULL
      AND (
        COALESCE(
          CASE WHEN jsonb_typeof(parsed.j -> 'mcqs') = 'array'
               THEN jsonb_array_length(parsed.j -> 'mcqs') ELSE 0 END,
          0) > 0
        OR COALESCE(
          CASE WHEN jsonb_typeof(parsed.j -> 'theory') = 'array'
               THEN jsonb_array_length(parsed.j -> 'theory') ELSE 0 END,
          0) > 0
        OR COALESCE(
          CASE WHEN jsonb_typeof(parsed.j -> 'subjective') = 'array'
               THEN jsonb_array_length(parsed.j -> 'subjective') ELSE 0 END,
          0) > 0
      )
  );
