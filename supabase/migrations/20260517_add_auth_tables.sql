-- Migration: Add pending_activations and admin_recovery_otps tables
-- Run this in the Supabase SQL Editor via Dashboard > SQL Editor

-- 1. pending_activations table
-- Stores pre-generated activation codes for admin and teacher onboarding.
CREATE TABLE IF NOT EXISTS public.pending_activations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL CHECK (role IN ('admin', 'teacher')),
  school_id UUID REFERENCES public.schools(id) ON DELETE SET NULL, -- nullable for admin; for teacher links to existing school
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '7 days'),
  used_at TIMESTAMPTZ -- null until used
);

CREATE INDEX idx_pending_activations_code ON public.pending_activations(code);
CREATE INDEX idx_pending_activations_expires ON public.pending_activations(expires_at);

-- 2. admin_recovery_otps table
-- Stores OTPs for admin password recovery flow.
CREATE TABLE IF NOT EXISTS public.admin_recovery_otps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  otp_hash TEXT NOT NULL, -- SHA-256 hash of the 6-digit OTP
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_admin_recovery_otps_email ON public.admin_recovery_otps(email);
CREATE INDEX idx_admin_recovery_otps_expires ON public.admin_recovery_otps(expires_at);

-- 3. Update recovery_codes table on server side
-- The existing server-side recovery_codes table already has most columns,
-- but ensure it has email, used, attempts columns for teacher recovery flow.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'recovery_codes' AND column_name = 'email'
  ) THEN
    ALTER TABLE public.recovery_codes ADD COLUMN email TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'recovery_codes' AND column_name = 'used'
  ) THEN
    ALTER TABLE public.recovery_codes ADD COLUMN used BOOLEAN NOT NULL DEFAULT false;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'recovery_codes' AND column_name = 'attempts'
  ) THEN
    ALTER TABLE public.recovery_codes ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'recovery_codes' AND column_name = 'expires_at'
  ) THEN
    ALTER TABLE public.recovery_codes ADD COLUMN expires_at TIMESTAMPTZ;
  END IF;
END $$;

-- Enable RLS but allow service_role full access
ALTER TABLE public.pending_activations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_recovery_otps ENABLE ROW LEVEL SECURITY;

-- Service role bypasses RLS, so no additional policies needed for edge functions
-- But create a policy that allows service_role full access explicitly
CREATE POLICY service_role_all ON public.pending_activations
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY service_role_all ON public.admin_recovery_otps
  FOR ALL TO service_role USING (true) WITH CHECK (true);
