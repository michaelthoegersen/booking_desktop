-- Add feature toggle columns to companies
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS show_tours boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_bus_requests boolean DEFAULT true;
