-- ============================================================
-- Chat attachments storage bucket
-- Public bucket for chat images, files, GIFs
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('chat-attachments', 'chat-attachments', true, 26214400)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload
CREATE POLICY "Authenticated users can upload chat attachments"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND auth.role() = 'authenticated'
  );

-- Allow authenticated users to update their own uploads
CREATE POLICY "Users can update own chat attachments"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-attachments'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Public read access
CREATE POLICY "Public read access for chat attachments"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'chat-attachments');
