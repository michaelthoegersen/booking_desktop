-- Per-company vehicle type categories (replaces hardcoded BusType enum)
-- These appear in the "Type kjøretøy" dropdown in offers.
-- Examples: "12-sleeper", "16-sleeper", "20-50 seats", "Lastebil"
CREATE TABLE IF NOT EXISTS vehicle_categories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        text NOT NULL,           -- display name, e.g. "12-sleeper"
  capacity    integer DEFAULT 0,       -- used for auto-selection by pax count
  sort_order  integer DEFAULT 0,
  active      boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vehicle_categories_company ON vehicle_categories(company_id);

ALTER TABLE vehicle_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vehicle_categories_select"
  ON vehicle_categories FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "vehicle_categories_insert"
  ON vehicle_categories FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

CREATE POLICY "vehicle_categories_update"
  ON vehicle_categories FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "vehicle_categories_delete"
  ON vehicle_categories FOR DELETE TO authenticated
  USING (is_admin_in(company_id));
