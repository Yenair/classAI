-- Migration: add email_verified to teachers + create verification_codes table
-- Run this in the Supabase SQL Editor or via supabase db push

-- 1. Add email_verified column to teachers table (default false)
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Create verification_codes table for 6-digit OTP codes
CREATE TABLE IF NOT EXISTS public.verification_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN NOT NULL DEFAULT FALSE,
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Index on email for fast lookup
CREATE INDEX IF NOT EXISTS idx_verification_codes_email
  ON public.verification_codes (email);

-- 4. Enable RLS on verification_codes
ALTER TABLE public.verification_codes ENABLE ROW LEVEL SECURITY;

-- 5. Service role policy (full access, used by edge functions)
CREATE POLICY IF NOT EXISTS service_role_all ON public.verification_codes
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
