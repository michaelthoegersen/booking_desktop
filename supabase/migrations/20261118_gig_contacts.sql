-- Tre kontakter per gig: kontaktperson, kontraktperson og fakturaperson.
--
-- Kontaktpersonen ligger fra før i customer_name/phone/email. Disse to
-- settene er de to andre rollene. De er egne felter og ikke en del av
-- «alternativ fakturamottaker», som handler om et annet FIRMA — her er det
-- snakk om ulike personer hos samme kunde.

ALTER TABLE gigs ADD COLUMN IF NOT EXISTS contract_name TEXT;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS contract_phone TEXT;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS contract_email TEXT;

ALTER TABLE gigs ADD COLUMN IF NOT EXISTS invoice_contact_name TEXT;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS invoice_contact_phone TEXT;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS invoice_contact_email TEXT;

COMMENT ON COLUMN gigs.contract_name IS 'Kontraktperson: den som signerer avtalen hos kunden.';
COMMENT ON COLUMN gigs.invoice_contact_name IS 'Fakturaperson: den som håndterer fakturaen hos kunden.';
