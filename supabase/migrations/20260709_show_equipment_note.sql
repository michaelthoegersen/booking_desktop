-- Per-link comment on show equipment (e.g. "ta med 14\" og 13\" skarp").
ALTER TABLE show_type_equipment ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE gig_show_equipment  ADD COLUMN IF NOT EXISTS note text;

NOTIFY pgrst, 'reload schema';
