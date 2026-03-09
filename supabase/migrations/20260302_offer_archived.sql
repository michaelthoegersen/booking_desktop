ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS archived boolean DEFAULT false;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS archived boolean DEFAULT false;
