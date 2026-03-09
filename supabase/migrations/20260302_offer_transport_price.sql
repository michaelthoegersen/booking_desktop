-- Add transport_price column to gig_offers so manually entered prices are persisted
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS transport_price numeric(10,2);
