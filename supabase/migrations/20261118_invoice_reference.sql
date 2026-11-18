-- Fakturareferanse: det kunden vil ha oppgitt som sin referanse på fakturaen.
--
-- Tre steder, fordi referansen kan høre til tre ting:
--   companies.invoice_reference      – kundens faste referanse (kunderegisteret)
--   gigs.invoice_reference           – referansen for denne jobben
--   gigs.alt_invoice_reference       – referansen til en annen fakturamottaker

ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS invoice_reference TEXT;

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS invoice_reference TEXT;

ALTER TABLE gigs
  ADD COLUMN IF NOT EXISTS alt_invoice_reference TEXT;

COMMENT ON COLUMN companies.invoice_reference IS
  'Kundens faste fakturareferanse. Forhåndsfyller feltet på nye tilbud/aktiviteter.';
COMMENT ON COLUMN gigs.invoice_reference IS
  'Kundens referanse for denne jobben, slik den skal oppgis på fakturaen.';
COMMENT ON COLUMN gigs.alt_invoice_reference IS
  'Referanse for alternativ fakturamottaker (alt_invoice_enabled = true).';
