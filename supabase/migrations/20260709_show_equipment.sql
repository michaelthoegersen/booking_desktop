-- ============================================================
-- Equipment on shows + per-gig packing check-off
-- ============================================================
-- Links equipment (mgmt_inventory_items) to shows, and lets crew tick
-- off gear per gig before departure (mobile app).
--
--   show_type_equipment  — gear ALWAYS used on a fixed show (show_types)
--   gig_show_equipment   — gear on a specific gig's show (incl. custom shows)
--   gig_equipment_checks — crew's packed/checked state per gig + item
--
-- A gig's full packing list = union of gear from every gig_shows row on it
-- (its show_type_id link ∪ its own gig_show_id link), DEDUPED by item — so
-- an item is listed once even if several shows on the gig use it.
--
-- company_id is denormalized on all three tables for simple RLS via
-- my_company_ids(). Reads AND writes are allowed for any company member,
-- because crew (non-admin) must be able to tick items off on mobile.
-- ============================================================

-- ---------- gear on a fixed show (catalog) ----------
CREATE TABLE IF NOT EXISTS show_type_equipment (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  show_type_id uuid NOT NULL REFERENCES show_types(id) ON DELETE CASCADE,
  item_id      uuid NOT NULL REFERENCES mgmt_inventory_items(id) ON DELETE CASCADE,
  quantity     numeric,
  created_at   timestamptz DEFAULT now(),
  created_by   uuid REFERENCES auth.users(id),
  UNIQUE (show_type_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_show_type_equipment_show ON show_type_equipment(show_type_id);
CREATE INDEX IF NOT EXISTS idx_show_type_equipment_item ON show_type_equipment(item_id);

-- ---------- gear on a specific gig's show ----------
CREATE TABLE IF NOT EXISTS gig_show_equipment (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  gig_show_id uuid NOT NULL REFERENCES gig_shows(id) ON DELETE CASCADE,
  item_id     uuid NOT NULL REFERENCES mgmt_inventory_items(id) ON DELETE CASCADE,
  quantity    numeric,
  created_at  timestamptz DEFAULT now(),
  created_by  uuid REFERENCES auth.users(id),
  UNIQUE (gig_show_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_gig_show_equipment_show ON gig_show_equipment(gig_show_id);
CREATE INDEX IF NOT EXISTS idx_gig_show_equipment_item ON gig_show_equipment(item_id);

-- ---------- per-gig packing check-off (mobile) ----------
CREATE TABLE IF NOT EXISTS gig_equipment_checks (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  gig_id     uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  item_id    uuid NOT NULL REFERENCES mgmt_inventory_items(id) ON DELETE CASCADE,
  checked    boolean NOT NULL DEFAULT true,
  checked_by uuid REFERENCES auth.users(id),
  checked_at timestamptz DEFAULT now(),
  UNIQUE (gig_id, item_id)
);
CREATE INDEX IF NOT EXISTS idx_gig_equipment_checks_gig ON gig_equipment_checks(gig_id);

-- ============================================================
-- RLS — read + write for any member of the company
-- ============================================================
ALTER TABLE show_type_equipment  ENABLE ROW LEVEL SECURITY;
ALTER TABLE gig_show_equipment   ENABLE ROW LEVEL SECURITY;
ALTER TABLE gig_equipment_checks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "show_type_equipment_select" ON show_type_equipment
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "show_type_equipment_insert" ON show_type_equipment
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "show_type_equipment_update" ON show_type_equipment
  FOR UPDATE TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "show_type_equipment_delete" ON show_type_equipment
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "gig_show_equipment_select" ON gig_show_equipment
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_show_equipment_insert" ON gig_show_equipment
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_show_equipment_update" ON gig_show_equipment
  FOR UPDATE TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_show_equipment_delete" ON gig_show_equipment
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));

CREATE POLICY "gig_equipment_checks_select" ON gig_equipment_checks
  FOR SELECT TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_equipment_checks_insert" ON gig_equipment_checks
  FOR INSERT TO authenticated WITH CHECK (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_equipment_checks_update" ON gig_equipment_checks
  FOR UPDATE TO authenticated USING (company_id IN (SELECT my_company_ids()));
CREATE POLICY "gig_equipment_checks_delete" ON gig_equipment_checks
  FOR DELETE TO authenticated USING (company_id IN (SELECT my_company_ids()));
