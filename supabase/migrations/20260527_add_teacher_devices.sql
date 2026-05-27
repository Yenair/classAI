-- Teacher devices table for "Verify on new device" flow.
-- When a teacher logs in from a device they haven't used before,
-- they must re-verify their email. Once verified, the device is
-- registered here so subsequent logins skip verification.

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

-- Index for fast lookup during login
CREATE INDEX IF NOT EXISTS idx_teacher_devices_lookup
  ON teacher_devices(teacher_id, device_id);
