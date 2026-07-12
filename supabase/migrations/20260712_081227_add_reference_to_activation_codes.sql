-- Add reference (Paystack transaction reference) and school_id columns
-- to activation_codes for idempotency across payment finalization paths.

ALTER TABLE public.activation_codes
  ADD COLUMN IF NOT EXISTS reference TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES public.schools(id);

-- Index for fast idempotency lookups by reference
CREATE INDEX IF NOT EXISTS idx_activation_codes_reference
  ON public.activation_codes (reference);
