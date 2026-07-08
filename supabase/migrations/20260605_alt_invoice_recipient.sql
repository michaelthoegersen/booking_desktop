-- Alternativ fakturamottaker for tilbud og gigs.
-- Når alt_invoice_enabled = true skal fakturaen sendes til alt_invoice_*-feltene
-- i stedet for til customer_*-feltene. Toggle og felter speiles på begge tabeller
-- så det kan settes både i tilbudsfasen (gig_offers) og direkte på en eksisterende
-- aktivitet (gigs).

alter table gigs
  add column if not exists alt_invoice_enabled boolean default false,
  add column if not exists alt_invoice_firma text,
  add column if not exists alt_invoice_name text,
  add column if not exists alt_invoice_email text,
  add column if not exists alt_invoice_phone text,
  add column if not exists alt_invoice_org_nr text,
  add column if not exists alt_invoice_address text,
  add column if not exists alt_invoice_on_ehf boolean default false;

alter table gig_offers
  add column if not exists alt_invoice_enabled boolean default false,
  add column if not exists alt_invoice_firma text,
  add column if not exists alt_invoice_name text,
  add column if not exists alt_invoice_email text,
  add column if not exists alt_invoice_phone text,
  add column if not exists alt_invoice_org_nr text,
  add column if not exists alt_invoice_address text,
  add column if not exists alt_invoice_on_ehf boolean default false;
