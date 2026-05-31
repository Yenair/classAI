-- Teacher devices table, token_version column, and email_verified reset.

-- 1. Teacher devices table for "Verify on new device" flow.
CREATE TABLE IF NOT EXISTS teacher_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  teacher_id UUID NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  platform TEXT,
  last_active TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- A teacher can have many devices, but a device_id is unique per teacher
  UNIQUE(teacher_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_teacher_devices_lookup
  ON teacher_devices(teacher_id, device_id);

-- 2. Add token_version column for no-concurrent-sessions enforcement.
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS token_version INTEGER DEFAULT 1;

-- 3. Ensure email_verified column exists and reset existing teachers.
ALTER TABLE public.teachers
  ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.teachers
SET email_verified = false
WHERE email_verified IS DISTINCT FROM false;
