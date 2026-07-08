-- ============================================================
-- Lager / inventory — TWO separate systems
-- ============================================================
-- Per the design decision, logistics and management get fully
-- independent inventory tables (separate items, separate move
-- history). Both track a single CURRENT location per item plus a
-- full move history (timeline). Location is structured:
--   location_type in ('warehouse','vehicle','venue')
--   location_ref  = free text: vehicle name / venue name / lager name
-- Writes are allowed for any company member (operational data),
-- reads scoped to the member's companies via my_company_ids().
-- ============================================================

-- ---------- helper: create one items + one moves table ----------
-- (Duplicated inline for logistics and mgmt so the two systems stay
--  fully independent tables.)

-- ============================================================
-- 1) LOGISTICS inventory — "deler til busser/lastebiler"
-- ============================================================
CREATE TABLE IF NOT EXISTS logistics_inventory_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name          text NOT NULL,
  category      text,
  ref_number    text,                       -- delenr. / serienr.
  quantity      numeric DEFAULT 1,
  unit          text DEFAULT 'stk',
  notes         text,
  location_type text NOT NULL DEFAULT 'warehouse'
                CHECK (location_type IN ('warehouse','vehicle','venue')),
  location_ref  text,                        -- vehicle name / venue / lager name
  status        text,                        -- optional: ok / defekt / reparasjon
  created_at    timestamptz DEFAULT now(),
  created_by    uuid REFERENCES auth.users(id),
  updated_at    timestamptz DEFAULT now(),
  updated_by    uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_logistics_inventory_company
  ON logistics_inventory_items(company_id);

CREATE TABLE IF NOT EXISTS logistics_inventory_moves (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  item_id            uuid NOT NULL REFERENCES logistics_inventory_items(id) ON DELETE CASCADE,
  from_location_type text,
  from_location_ref  text,
  to_location_type   text,
  to_location_ref    text,
  quantity           numeric,
  note               text,
  moved_at           timestamptz DEFAULT now(),
  moved_by           uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_logistics_inventory_moves_item
  ON logistics_inventory_moves(item_id);

-- ============================================================
-- 2) MANAGEMENT inventory — "oversikt over utstyr og hvor det er"
-- ============================================================
CREATE TABLE IF NOT EXISTS mgmt_inventory_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  name          text NOT NULL,
  category      text,
  ref_number    text,                       -- serienr.
  quantity      numeric DEFAULT 1,
  unit          text DEFAULT 'stk',
  notes         text,
  location_type text NOT NULL DEFAULT 'warehouse'
                CHECK (location_type IN ('warehouse','vehicle','venue')),
  location_ref  text,
  status        text,
  created_at    timestamptz DEFAULT now(),
  created_by    uuid REFERENCES auth.users(id),
  updated_at    timestamptz DEFAULT now(),
  updated_by    uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_mgmt_inventory_company
  ON mgmt_inventory_items(company_id);

CREATE TABLE IF NOT EXISTS mgmt_inventory_moves (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  item_id            uuid NOT NULL REFERENCES mgmt_inventory_items(id) ON DELETE CASCADE,
  from_location_type text,
  from_location_ref  text,
  to_location_type   text,
  to_location_ref    text,
  quantity           numeric,
  note               text,
  moved_at           timestamptz DEFAULT now(),
  moved_by           uuid REFERENCES auth.users(id)
);
CREATE INDEX IF NOT EXISTS idx_mgmt_inventory_moves_item
  ON mgmt_inventory_moves(item_id);

-- ============================================================
-- RLS — read: my companies; write: any member of the company
-- ============================================================
ALTER TABLE logistics_inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE logistics_inventory_moves ENABLE ROW LEVEL SECURITY;
ALTER TABLE mgmt_inventory_items      ENABLE ROW LEVEL SECURITY;
ALTER TABLE mgmt_inventory_moves      ENABLE ROW LEVEL SECURITY;

-- logistics_inventory_items
CREATE POLICY "logistics_inv_items_select" ON logistics_inventory_items
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "logistics_inv_items_insert" ON logistics_inventory_items
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "logistics_inv_items_update" ON logistics_inventory_items
  FOR UPDATE TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "logistics_inv_items_delete" ON logistics_inventory_items
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));

-- logistics_inventory_moves
CREATE POLICY "logistics_inv_moves_select" ON logistics_inventory_moves
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "logistics_inv_moves_insert" ON logistics_inventory_moves
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "logistics_inv_moves_delete" ON logistics_inventory_moves
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));

-- mgmt_inventory_items
CREATE POLICY "mgmt_inv_items_select" ON mgmt_inventory_items
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "mgmt_inv_items_insert" ON mgmt_inventory_items
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "mgmt_inv_items_update" ON mgmt_inventory_items
  FOR UPDATE TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "mgmt_inv_items_delete" ON mgmt_inventory_items
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));

-- mgmt_inventory_moves
CREATE POLICY "mgmt_inv_moves_select" ON mgmt_inventory_moves
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "mgmt_inv_moves_insert" ON mgmt_inventory_moves
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "mgmt_inv_moves_delete" ON mgmt_inventory_moves
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));
