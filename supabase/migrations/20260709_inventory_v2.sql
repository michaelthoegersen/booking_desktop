-- ============================================================
-- Inventory v2: per-unit serial numbers + container units
-- ============================================================
-- serials   — jsonb array of per-unit serial numbers. When an item has
--             quantity > 1 the UI collects one serial per unit, and the
--             list is split/merged along with quantity on moves.
-- parent_id — self-reference making an item a "container" (e.g. a
--             Playbackrack). Contents are listed inside the unit, and the
--             whole container moves in/out of the warehouse as one unit.
--             ON DELETE SET NULL so deleting a rack frees its contents
--             rather than deleting them.
-- ============================================================

ALTER TABLE mgmt_inventory_items
  ADD COLUMN IF NOT EXISTS serials   jsonb,
  ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES mgmt_inventory_items(id) ON DELETE SET NULL;

ALTER TABLE logistics_inventory_items
  ADD COLUMN IF NOT EXISTS serials   jsonb,
  ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES logistics_inventory_items(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_mgmt_inventory_parent
  ON mgmt_inventory_items(parent_id);
CREATE INDEX IF NOT EXISTS idx_logistics_inventory_parent
  ON logistics_inventory_items(parent_id);
