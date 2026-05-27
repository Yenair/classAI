-- Migration: Reset email_verified for existing teachers
-- Ensures all existing teachers start as unverified so the email verification
-- popup appears on next login.

-- 1. Ensure the email_verified column exists (idempotent)
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Reset all existing teachers to unverified
-- This forces the email verification dialog to appear on next login
-- for all accounts created before this feature was fully implemented.
UPDATE public.teachers
SET email_verified = false
WHERE email_verified IS DISTINCT FROM false;
