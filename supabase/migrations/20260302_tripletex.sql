-- ════════════════════════════════════════════════════════
-- TRIPLETEX INTEGRATION
-- ════════════════════════════════════════════════════════

-- Tripletex API credentials per company
ALTER TABLE companies ADD COLUMN IF NOT EXISTS tripletex_consumer_token text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS tripletex_employee_token text;

-- Link gig offers to Tripletex invoices
ALTER TABLE gig_offers ADD COLUMN IF NOT EXISTS tripletex_invoice_id integer;
