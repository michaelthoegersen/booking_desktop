-- Separate bus requests flag for Complete/Management section
-- so it doesn't interfere with CSS sidebar bus requests toggle
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS show_bus_requests_mgmt boolean DEFAULT true;
