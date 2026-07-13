-- Create upgrade_requests table for teacher upgrade requests
-- Each teacher can request an upgrade once per day (UTC date).

CREATE TABLE IF NOT EXISTS public.upgrade_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    teacher_id UUID NOT NULL REFERENCES public.teachers(id) ON DELETE CASCADE,
    requested_tier TEXT NOT NULL,
    request_date DATE NOT NULL DEFAULT (CURRENT_DATE),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (teacher_id, request_date)
);

-- Index for looking up requests by teacher
CREATE INDEX IF NOT EXISTS idx_upgrade_requests_teacher_id
    ON public.upgrade_requests (teacher_id);

-- Index for looking up requests by date
CREATE INDEX IF NOT EXISTS idx_upgrade_requests_request_date
    ON public.upgrade_requests (request_date);
