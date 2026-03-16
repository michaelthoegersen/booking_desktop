-- Junction table: gig_offers → many gigs
CREATE TABLE gig_offer_gigs (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id   uuid NOT NULL REFERENCES gig_offers(id) ON DELETE CASCADE,
  gig_id     uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  sort_order integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  UNIQUE(offer_id, gig_id)
);
ALTER TABLE gig_offer_gigs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Auth full access" ON gig_offer_gigs FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Backfill existing offers
INSERT INTO gig_offer_gigs (offer_id, gig_id, sort_order)
SELECT id, gig_id, 0 FROM gig_offers WHERE gig_id IS NOT NULL
ON CONFLICT DO NOTHING;

-- Rehearsal + markup + overrides columns on gig_offers
ALTER TABLE gig_offers
  ADD COLUMN IF NOT EXISTS rehearsal_performers integer,
  ADD COLUMN IF NOT EXISTS rehearsal_count integer,
  ADD COLUMN IF NOT EXISTS rehearsal_price_per_person numeric,
  ADD COLUMN IF NOT EXISTS rehearsal_transport numeric,
  ADD COLUMN IF NOT EXISTS markup_on_all boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS calc_overrides jsonb;
