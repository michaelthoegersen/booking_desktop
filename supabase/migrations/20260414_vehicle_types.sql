-- Per-company vehicle types (replaces hardcoded BusType enum and company_vehicles.dart)
CREATE TABLE IF NOT EXISTS vehicle_types (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name        text NOT NULL,           -- e.g. "CSS_1034", "Lastebil 1"
  description text,                    -- e.g. "12-sleeper", "16-sleeper", "Lastebil"
  capacity    integer DEFAULT 0,       -- passenger/bunk capacity
  is_conference boolean DEFAULT false, -- conference/special type (excluded from sleeper lists)
  sort_order  integer DEFAULT 0,
  active      boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_vehicle_types_company ON vehicle_types(company_id);

ALTER TABLE vehicle_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY "vehicle_types_select"
  ON vehicle_types FOR SELECT TO authenticated
  USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "vehicle_types_insert"
  ON vehicle_types FOR INSERT TO authenticated
  WITH CHECK (is_admin_in(company_id));

CREATE POLICY "vehicle_types_update"
  ON vehicle_types FOR UPDATE TO authenticated
  USING (is_admin_in(company_id));

CREATE POLICY "vehicle_types_delete"
  ON vehicle_types FOR DELETE TO authenticated
  USING (is_admin_in(company_id));

-- Also store vehicle label/icon config per company
ALTER TABLE companies ADD COLUMN IF NOT EXISTS vehicle_label text DEFAULT 'bus';
ALTER TABLE companies ADD COLUMN IF NOT EXISTS vehicle_label_plural text DEFAULT 'busser';
ALTER TABLE companies ADD COLUMN IF NOT EXISTS vehicle_icon text DEFAULT 'directions_bus';
