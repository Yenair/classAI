-- Normalise existing teacher emails to lowercase for case‑insensitive uniqueness.
-- All new inserts/lookups are also lowercased in the Edge Functions and Flutter client.

UPDATE public.teachers SET email = LOWER(email);

-- Migration: add temp_password column to teachers table

ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS temp_password TEXT;
