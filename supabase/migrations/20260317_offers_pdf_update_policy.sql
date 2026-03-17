-- Allow authenticated users to update (overwrite) files in offers-pdf storage.
-- Supabase Storage uses UPSERT, which requires both INSERT and UPDATE policies.
CREATE POLICY "Authenticated update offers-pdf"
  ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'offers-pdf');
