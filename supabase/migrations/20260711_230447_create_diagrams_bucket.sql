-- Create the `diagrams` storage bucket for diagram images.
-- Bucket is public: any diagram URL is fetchable by anyone with the link.
-- File size limit: 5 MB. Allowed MIME types: image/png, image/jpeg, image/webp.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('diagrams', 'diagrams', true, 5242880, '{image/png,image/jpeg,image/webp}')
ON CONFLICT (id) DO NOTHING;
