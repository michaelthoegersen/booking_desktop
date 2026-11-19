-- Kontakt- og fakturafeltene manglet på gig_offers.
--
-- Tilbudet lagres to steder: gigs (selve datoen) og gig_offers (tilbudet).
-- Begge skriver de samme kundefeltene, men migrasjonene for fakturareferanse
-- og de tre kontaktene la bare kolonnene på gigs. Dermed stoppet lagringen
-- med «Could not find the 'alt_invoice_reference' column of 'gig_offers'».

ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS invoice_reference TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS alt_invoice_reference TEXT;

ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS contract_name TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS contract_phone TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS contract_email TEXT;

ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS invoice_contact_name TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS invoice_contact_phone TEXT;
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS invoice_contact_email TEXT;

COMMENT ON COLUMN gig_offers.contract_name IS 'Kontraktperson: den som signerer avtalen hos kunden.';
COMMENT ON COLUMN gig_offers.invoice_contact_name IS 'Fakturaperson: den som håndterer fakturaen hos kunden.';
