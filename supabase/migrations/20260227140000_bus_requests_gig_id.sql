-- Add gig support to bus_requests
ALTER TABLE bus_requests
  ADD COLUMN IF NOT EXISTS gig_id uuid REFERENCES gigs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bus_requests_gig ON bus_requests(gig_id);

ALTER TABLE bus_requests
  ADD COLUMN IF NOT EXISTS trailer boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS bus_count integer DEFAULT 1;

-- Junction table for multi-gig bus requests (one request = one tour/route)
CREATE TABLE IF NOT EXISTS bus_request_gigs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_request_id uuid NOT NULL REFERENCES bus_requests(id) ON DELETE CASCADE,
  gig_id uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0,
  UNIQUE(bus_request_id, gig_id)
);

CREATE INDEX IF NOT EXISTS idx_brg_request ON bus_request_gigs(bus_request_id);
CREATE INDEX IF NOT EXISTS idx_brg_gig ON bus_request_gigs(gig_id);
