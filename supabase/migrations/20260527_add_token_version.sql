-- Migration: add token_version column to teachers table
-- Used for no-concurrent-sessions enforcement.
-- Run this in the Supabase SQL Editor or via supabase db push

ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS token_version INTEGER DEFAULT 1;
