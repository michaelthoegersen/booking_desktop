-- Add ekstrainnslag (extra acts description) to gig_shows and gig_offer_shows
ALTER TABLE gig_shows ADD COLUMN IF NOT EXISTS ekstrainnslag text;
ALTER TABLE gig_offer_shows ADD COLUMN IF NOT EXISTS ekstrainnslag text;
