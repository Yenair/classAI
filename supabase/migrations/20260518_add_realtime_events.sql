-- Migration: Add realtime_events table and triggers for incremental sync
-- Run this in the Supabase SQL Editor via Dashboard > SQL Editor
--
-- This migration creates:
--   1. realtime_events table for capturing INSERT/UPDATE/DELETE on syncable tables
--   2. record_realtime_event() trigger function (generic, accepts table_name as argument)
--   3. Triggers on lessons, exams, progress_logs, vault_items, scheme_of_work, subjects

-- ============================================================
-- 1. realtime_events table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.realtime_events (
  id BIGSERIAL PRIMARY KEY,
  school_id UUID NOT NULL,
  table_name TEXT NOT NULL,
  record_id UUID NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('INSERT', 'UPDATE', 'DELETE')),
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_realtime_events_school
  ON public.realtime_events(school_id, id);

-- ============================================================
-- 2. Trigger function (generic, accepts table_name as TG_ARGV[0])
-- ============================================================
CREATE OR REPLACE FUNCTION public.record_realtime_event()
RETURNS TRIGGER AS $$
DECLARE
  table_name TEXT := TG_ARGV[0];
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.realtime_events (school_id, table_name, record_id, event_type, payload)
    VALUES (NEW.school_id, table_name, NEW.id, 'INSERT', row_to_json(NEW)::jsonb);
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.realtime_events (school_id, table_name, record_id, event_type, payload)
    VALUES (NEW.school_id, table_name, NEW.id, 'UPDATE', row_to_json(NEW)::jsonb);
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.realtime_events (school_id, table_name, record_id, event_type, payload)
    VALUES (OLD.school_id, table_name, OLD.id, 'DELETE', jsonb_build_object('deleted_at', now()));
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 3. Triggers on syncable tables
-- ============================================================

-- lessons
DROP TRIGGER IF EXISTS lessons_realtime ON public.lessons;
CREATE TRIGGER lessons_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.lessons
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('lessons');

-- exams
DROP TRIGGER IF EXISTS exams_realtime ON public.exams;
CREATE TRIGGER exams_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.exams
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('exams');

-- progress_logs
DROP TRIGGER IF EXISTS progress_logs_realtime ON public.progress_logs;
CREATE TRIGGER progress_logs_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.progress_logs
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('progress_logs');

-- vault_items
DROP TRIGGER IF EXISTS vault_items_realtime ON public.vault_items;
CREATE TRIGGER vault_items_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.vault_items
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('vault_items');

-- scheme_of_work
DROP TRIGGER IF EXISTS scheme_of_work_realtime ON public.scheme_of_work;
CREATE TRIGGER scheme_of_work_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.scheme_of_work
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('scheme_of_work');

-- subjects
DROP TRIGGER IF EXISTS subjects_realtime ON public.subjects;
CREATE TRIGGER subjects_realtime
  AFTER INSERT OR UPDATE OR DELETE ON public.subjects
  FOR EACH ROW EXECUTE FUNCTION public.record_realtime_event('subjects');

-- ============================================================
-- Enable RLS but allow service_role full access
-- ============================================================
ALTER TABLE public.realtime_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_role_all ON public.realtime_events;
CREATE POLICY service_role_all ON public.realtime_events
  FOR ALL TO service_role USING (true) WITH CHECK (true);
