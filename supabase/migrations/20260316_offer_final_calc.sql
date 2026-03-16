-- Store the final calculated price lines on the offer
-- so the gig detail page can generate the correct PDF
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS final_calc jsonb;
