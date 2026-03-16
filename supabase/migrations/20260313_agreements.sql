-- ============================================================
-- Agreement acceptance flow for intensjonsavtale
-- ============================================================

-- Token table for tracking agreement acceptance
CREATE TABLE IF NOT EXISTS agreement_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id      UUID NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  token       UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  customer_email TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, approved
  pdf_path    TEXT,                              -- storage path in agreements bucket
  accepted_at TIMESTAMPTZ,
  accepted_name TEXT,                            -- customer name when accepting
  approved_at TIMESTAMPTZ,
  approved_by UUID REFERENCES auth.users(id),
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE agreement_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read agreement_tokens"
  ON agreement_tokens FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert agreement_tokens"
  ON agreement_tokens FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Authenticated users can update agreement_tokens"
  ON agreement_tokens FOR UPDATE
  TO authenticated
  USING (true);

-- Service role full access (for edge functions)
CREATE POLICY "Service role full access on agreement_tokens"
  ON agreement_tokens FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Anon can read (for public accept page)
CREATE POLICY "Anon can read agreement_tokens"
  ON agreement_tokens FOR SELECT
  TO anon
  USING (true);

-- Anon can update status (for accepting via public link)
CREATE POLICY "Anon can update agreement_tokens"
  ON agreement_tokens FOR UPDATE
  TO anon
  USING (true);

-- Storage bucket for agreement PDFs
INSERT INTO storage.buckets (id, name, public)
VALUES ('agreements', 'agreements', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to agreement PDFs (customers need to view them)
CREATE POLICY "Public read agreements"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'agreements');

-- Allow authenticated users to upload agreement PDFs
CREATE POLICY "Authenticated upload agreements"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'agreements');

-- Allow service role full access
CREATE POLICY "Service role agreements"
  ON storage.objects FOR ALL
  TO service_role
  USING (bucket_id = 'agreements')
  WITH CHECK (bucket_id = 'agreements');
