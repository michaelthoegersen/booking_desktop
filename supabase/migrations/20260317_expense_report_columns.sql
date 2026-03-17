-- ============================================================
-- EXPENSE REPORT: multi-item support + driving fields
-- ============================================================

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS group_id         UUID,
  ADD COLUMN IF NOT EXISTS expense_type     TEXT NOT NULL DEFAULT 'receipt',
  ADD COLUMN IF NOT EXISTS transport_km     INT,
  ADD COLUMN IF NOT EXISTS transport_rate   NUMERIC(4,2),
  ADD COLUMN IF NOT EXISTS toll_cost        NUMERIC(10,2),
  ADD COLUMN IF NOT EXISTS route_from       TEXT,
  ADD COLUMN IF NOT EXISTS route_to         TEXT,
  ADD COLUMN IF NOT EXISTS route_via        TEXT,
  ADD COLUMN IF NOT EXISTS has_trailer      BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS passenger_count  INT DEFAULT 1;

-- Index for grouping report items
CREATE INDEX IF NOT EXISTS idx_expenses_group ON expenses(group_id) WHERE group_id IS NOT NULL;
