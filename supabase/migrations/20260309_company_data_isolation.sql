-- ============================================================
-- Add owner_company_id to offers and samletdata for data isolation
-- ============================================================

-- 1. Add column to offers
ALTER TABLE offers
ADD COLUMN IF NOT EXISTS owner_company_id uuid REFERENCES companies(id);

-- 2. Add column to samletdata
ALTER TABLE samletdata
ADD COLUMN IF NOT EXISTS owner_company_id uuid REFERENCES companies(id);

-- 3. Backfill existing data to CSS (Coach Service Scandinavia)
UPDATE offers
SET owner_company_id = (SELECT id FROM companies WHERE name = 'Coach Service Scandinavia' LIMIT 1)
WHERE owner_company_id IS NULL;

UPDATE samletdata
SET owner_company_id = (SELECT id FROM companies WHERE name = 'Coach Service Scandinavia' LIMIT 1)
WHERE owner_company_id IS NULL;
