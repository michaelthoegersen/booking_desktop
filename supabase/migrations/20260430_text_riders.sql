-- ============================================================
-- Extend company_riders with text + dynamic quantity
-- ============================================================

ALTER TABLE company_riders
  ADD COLUMN IF NOT EXISTS body_text       text,
  ADD COLUMN IF NOT EXISTS quantity_source  text,
  ADD COLUMN IF NOT EXISTS quantity_fixed   int;

ALTER TABLE company_riders
  ALTER COLUMN file_path DROP NOT NULL;

ALTER TABLE company_riders
  DROP CONSTRAINT IF EXISTS company_riders_quantity_source_chk;
ALTER TABLE company_riders
  ADD CONSTRAINT company_riders_quantity_source_chk
  CHECK (
    quantity_source IS NULL OR quantity_source IN
      ('drummers','dancers','others','show_total','fixed')
  );
