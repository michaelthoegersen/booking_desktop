-- Per-company contract configuration, loaded by
-- IntensjonsavtalePdfService at PDF generation time.
--
-- Structure (all fields optional — empty strings by default):
--   header_contact_name  — person shown in header
--   header_phone         — phone in header
--   header_email         — email in header
--   signature_label      — text above tenant signature line
--   show_label           — label used in price summary (fallback: company name)
--   translations         — per-language title + body
--
-- translations is a map keyed by locale code (e.g. "no", "en", "sv",
-- "da", "de"). Each value is `{ "title": string, "body": string }`.
-- Tenants add/remove languages from Settings as they wish.
--
-- Body text supports placeholders:
--   {us}            — the tenant company's name
--   {firma}         — the customer's company name
--   {kontaktperson} — the customer contact person
--   {spillested}    — the venue name (or "venue, city")

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS contract_config jsonb NOT NULL DEFAULT jsonb_build_object(
    'header_contact_name',   '',
    'header_phone',          '',
    'header_email',          '',
    'signature_label',       '',
    'show_label',            '',
    'translations',          '{}'::jsonb
  );
