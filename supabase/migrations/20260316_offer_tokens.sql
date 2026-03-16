-- ============================================================
-- Offer acceptance flow for tilbud (CSS)
-- ============================================================

-- Drop existing table if it references wrong FK
DROP TABLE IF EXISTS offer_tokens;

-- Token table for tracking offer acceptance
CREATE TABLE offer_tokens (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id        UUID NOT NULL REFERENCES offers(id) ON DELETE CASCADE,
  token           UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  customer_email  TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',  -- pending, accepted, approved
  pdf_path        TEXT,                              -- storage path in offers bucket
  accepted_at     TIMESTAMPTZ,
  accepted_name   TEXT,                              -- customer name when accepting
  approved_at     TIMESTAMPTZ,
  approved_by     UUID REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- RLS
ALTER TABLE offer_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read offer_tokens"
  ON offer_tokens FOR SELECT TO authenticated USING (true);

CREATE POLICY "Authenticated users can insert offer_tokens"
  ON offer_tokens FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "Authenticated users can update offer_tokens"
  ON offer_tokens FOR UPDATE TO authenticated USING (true);

CREATE POLICY "Service role full access on offer_tokens"
  ON offer_tokens FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "Anon can read offer_tokens"
  ON offer_tokens FOR SELECT TO anon USING (true);

CREATE POLICY "Anon can update offer_tokens"
  ON offer_tokens FOR UPDATE TO anon USING (true);

-- Storage bucket for offer PDFs
INSERT INTO storage.buckets (id, name, public)
VALUES ('offers-pdf', 'offers-pdf', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Public read offers-pdf"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'offers-pdf');

CREATE POLICY "Authenticated upload offers-pdf"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'offers-pdf');

CREATE POLICY "Service role offers-pdf"
  ON storage.objects FOR ALL TO service_role
  USING (bucket_id = 'offers-pdf') WITH CHECK (bucket_id = 'offers-pdf');
