-- Company branding for PDF offers, invoices, etc.
CREATE TABLE IF NOT EXISTS company_branding (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,

  -- Logo (stored in Supabase Storage bucket 'company-logos')
  logo_url TEXT,

  -- Header/contact shown at top of PDFs
  company_name TEXT,
  address_line TEXT,        -- e.g. 'Ring Lillgård 1585 62 Linköping, SE'
  contact_line_1 TEXT,      -- e.g. 'Michael: +47 948 93 820  sales@coachservicescandinavia.com'
  contact_line_2 TEXT,      -- optional second contact

  -- Signature block on offers
  signature_name TEXT,      -- e.g. 'For Coach Service Scandinavia'

  -- Terms & conditions (full text shown on offer PDFs)
  terms_text TEXT,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),

  UNIQUE(company_id)
);

-- Enable RLS
ALTER TABLE company_branding ENABLE ROW LEVEL SECURITY;

-- Users can read/write branding for their own companies
CREATE POLICY "Users can view own company branding"
  ON company_branding FOR SELECT
  USING (company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can upsert own company branding"
  ON company_branding FOR INSERT
  WITH CHECK (company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  ));

CREATE POLICY "Users can update own company branding"
  ON company_branding FOR UPDATE
  USING (company_id IN (
    SELECT company_id FROM company_members WHERE user_id = auth.uid()
  ));

-- Storage bucket for logos
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-logos', 'company-logos', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to their company folder
CREATE POLICY "Users can upload company logos"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'company-logos' AND auth.role() = 'authenticated');

CREATE POLICY "Public can read company logos"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'company-logos');

CREATE POLICY "Users can update company logos"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'company-logos' AND auth.role() = 'authenticated');

CREATE POLICY "Users can delete company logos"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'company-logos' AND auth.role() = 'authenticated');
