-- Add pdf_path column to offers table
ALTER TABLE offers ADD COLUMN IF NOT EXISTS pdf_path text;

-- Create offer-pdfs storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('offer-pdfs', 'offer-pdfs', true, 52428800)
ON CONFLICT (id) DO UPDATE SET public = true;

-- RLS policies for storage
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Auth upload offer-pdfs'
  ) THEN
    CREATE POLICY "Auth upload offer-pdfs"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'offer-pdfs');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'Public read offer-pdfs'
  ) THEN
    CREATE POLICY "Public read offer-pdfs"
      ON storage.objects FOR SELECT USING (bucket_id = 'offer-pdfs');
  END IF;
END $$;
