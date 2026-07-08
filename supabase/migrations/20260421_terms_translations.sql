-- ============================================================
-- Auto-translated Terms & Conditions for offer PDFs
-- ============================================================
-- terms_text holds the Norwegian source (user input in settings).
-- terms_translations caches AI translations per language code:
--   { "en": "...", "sv": "...", "de": "..." }
-- Re-generated whenever terms_text changes in settings.

ALTER TABLE company_branding
ADD COLUMN IF NOT EXISTS terms_translations jsonb
  NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN company_branding.terms_translations IS
  'AI-translated versions of terms_text keyed by language code (en/sv/de). Auto-updated when terms_text changes.';
