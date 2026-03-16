-- Add round_index to bus_request_gigs so website requests can have multiple rounds
ALTER TABLE bus_request_gigs
  ADD COLUMN IF NOT EXISTS round_index integer NOT NULL DEFAULT 0;

-- Also store start/end city per round
ALTER TABLE bus_request_gigs
  ADD COLUMN IF NOT EXISTS round_start_city text,
  ADD COLUMN IF NOT EXISTS round_end_city text;
