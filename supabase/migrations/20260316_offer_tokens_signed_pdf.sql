-- Add signed_pdf_path column to offer_tokens
ALTER TABLE offer_tokens ADD COLUMN IF NOT EXISTS signed_pdf_path TEXT;
