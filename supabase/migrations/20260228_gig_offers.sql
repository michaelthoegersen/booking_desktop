-- Gig offer tables for Complete pristilbud
-- Run in Supabase SQL Editor

CREATE TABLE IF NOT EXISTS gig_offers (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id             uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  gig_id                 uuid REFERENCES gigs(id) ON DELETE SET NULL,
  customer_firma         text,
  customer_name          text,
  customer_email         text,
  customer_phone         text,
  customer_org_nr        text,
  customer_address       text,
  -- Redigerbare prisparametre (defaults fra Excel)
  creo_fee_minimum       numeric(10,2) DEFAULT 5500,
  extra_show_fee         numeric(10,2) DEFAULT 1500,
  markup_pct             numeric(5,4)  DEFAULT 0.25,
  booking_ext_pct        numeric(5,4)  DEFAULT 0.025,
  inear_included         boolean DEFAULT false,
  inear_price            numeric(10,2) DEFAULT 7000,
  transport_km           integer DEFAULT 0,
  transport_price_per_km numeric(10,2) DEFAULT 45,
  -- Overstyrt total
  total_excl_override    numeric(10,2),
  total_override         numeric(10,2),
  status                 text DEFAULT 'draft',
  notes                  text,
  created_by             uuid REFERENCES auth.users(id),
  created_at             timestamptz DEFAULT now(),
  updated_at             timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS gig_offer_shows (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id      uuid NOT NULL REFERENCES gig_offers(id) ON DELETE CASCADE,
  show_type_id  uuid REFERENCES show_types(id),
  show_name     text NOT NULL,
  drummers      integer DEFAULT 0,
  dancers       integer DEFAULT 0,
  others        integer DEFAULT 0,
  selected      boolean DEFAULT true,
  sort_order    integer DEFAULT 0
);

-- RLS
ALTER TABLE gig_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE gig_offer_shows ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Auth full access gig_offers"
  ON gig_offers FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Auth full access gig_offer_shows"
  ON gig_offer_shows FOR ALL TO authenticated USING (true) WITH CHECK (true);
