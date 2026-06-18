-- ============================================================
-- Custom + reorderable Tidsplan rows on gigs
-- ============================================================
-- The mgmt offer editor's "Tidsplan" section gets custom free-text rows
-- (title + value) in addition to the fixed time columns, and the full
-- row order (fixed + custom) is user-controlled. The fixed values still
-- live in their existing columns (meeting_time, get_in_time, …) so the
-- agreement/Intensjonsavtale is unchanged. This column stores the order
-- and the custom rows as an ordered jsonb array, e.g.:
--   [ {"k":"meeting"}, {"k":"custom","t":"Soundcheck","v":"14:00"}, ... ]
-- ============================================================

ALTER TABLE gigs ADD COLUMN IF NOT EXISTS schedule_items jsonb;
