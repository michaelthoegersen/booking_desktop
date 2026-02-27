ALTER TABLE bus_requests
  ADD COLUMN IF NOT EXISTS archived_css boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS archived_mgmt boolean NOT NULL DEFAULT false;
