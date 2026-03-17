-- Allow authenticated users to delete offer tokens
CREATE POLICY "Authenticated users can delete offer_tokens"
  ON offer_tokens FOR DELETE TO authenticated USING (true);

-- Allow authenticated users to delete from offers-pdf storage
CREATE POLICY "Authenticated delete offers-pdf"
  ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'offers-pdf');
