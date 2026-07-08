-- Per-row flag: does `price` hold a custom override, or should we fall back
-- to the CREO-based auto-calculation (performers × creo_fee_minimum for the
-- main show, × extra_show_fee for extras)?
--
-- Default FALSE everywhere so existing gig_shows (which stored auto-computed
-- CREO values) get recomputed on next load — no data mismatch.
-- Existing show_types with a non-zero price were entered manually → mark
-- those as custom so the stored number is respected.

ALTER TABLE gig_shows
  ADD COLUMN IF NOT EXISTS price_is_custom BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE show_types
  ADD COLUMN IF NOT EXISTS price_is_custom BOOLEAN NOT NULL DEFAULT FALSE;

-- Backfill: manually-entered show_type prices should remain custom.
UPDATE show_types
SET price_is_custom = TRUE
WHERE price IS NOT NULL AND price > 0;
