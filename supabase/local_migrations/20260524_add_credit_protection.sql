-- Migration: Add credit, anti-sharing, and content protection system tables and columns
-- Run this in the Supabase SQL Editor via Dashboard > SQL Editor
--
-- This migration creates:
--   1. audit_logs table for tracking security events
--   2. Adds current_device_id to teachers table
--   3. Adds daily counters to security_config table

-- ============================================================
-- 1. audit_logs table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID,
  school_id UUID,
  action TEXT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_teacher
  ON public.audit_logs(teacher_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_school
  ON public.audit_logs(school_id);

CREATE INDEX IF NOT EXISTS idx_audit_logs_action
  ON public.audit_logs(action);

-- ============================================================
-- 2. Add current_device_id to teachers table
-- ============================================================
ALTER TABLE public.teachers ADD COLUMN IF NOT EXISTS current_device_id TEXT;

-- ============================================================
-- 3. Add daily counters to security_config table
-- ============================================================
ALTER TABLE public.security_config ADD COLUMN IF NOT EXISTS daily_generations INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.security_config ADD COLUMN IF NOT EXISTS daily_generation_date TEXT;
ALTER TABLE public.security_config ADD COLUMN IF NOT EXISTS daily_pdf_exports INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.security_config ADD COLUMN IF NOT EXISTS daily_pdf_export_date TEXT;

-- ============================================================
-- Enable RLS and set policies
-- ============================================================
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS service_role_all_audit ON public.audit_logs;
CREATE POLICY service_role_all_audit ON public.audit_logs
  FOR ALL TO service_role USING (true) WITH CHECK (true);