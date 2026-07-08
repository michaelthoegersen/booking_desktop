-- Add owner_company_id to companies table for data isolation between
-- logistics companies (CSS, Moss Turbusser, etc.)
-- This ensures each logistics company only sees their own customers.

ALTER TABLE companies ADD COLUMN IF NOT EXISTS owner_company_id uuid REFERENCES companies(id);

-- Set existing companies to CSS as owner (Coach Service Scandinavia)
-- since all current customers belong to CSS
UPDATE companies
SET owner_company_id = 'd3695282-4eb2-4883-8580-581b0f261ae3'
WHERE owner_company_id IS NULL
  AND id != 'd3695282-4eb2-4883-8580-581b0f261ae3'   -- not CSS itself
  AND id != '4b73ccfc-3aab-435e-9539-85680a34b0f8'   -- not Moss Turbusser
  AND id != '46b78e84-77ee-4899-a00d-b39b6aac817d'   -- not COMPLETE DRUMS
  AND id != 'bb14ab05-8680-4320-a2e0-984cc9454caa'   -- not Complete Drums
  AND id != '66e6e7c2-24e0-47ee-ac42-b85285152e88'   -- not TOURFLOW AS
  AND id != '3bc96ad2-bb9d-4523-9a9c-ae54137251c3'   -- not TourFlow AS
  AND id != '6ac3e881-2b04-422f-817c-163e3fce82a3';  -- not MICHAEL THØGERSEN
