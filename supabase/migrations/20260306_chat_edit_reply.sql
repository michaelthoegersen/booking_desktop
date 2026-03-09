-- ============================================================
-- Chat edit & reply support
-- Adds edited_at + reply_to_id to all 4 message tables
-- + UPDATE policy so users can edit own messages
-- ============================================================

-- ── direct_messages ─────────────────────────────────────────
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES direct_messages(id) ON DELETE SET NULL;

CREATE POLICY "direct_messages_update_own" ON direct_messages
  FOR UPDATE USING (sender_id = auth.uid())
  WITH CHECK (sender_id = auth.uid());

-- ── group_chat_messages ─────────────────────────────────────
ALTER TABLE group_chat_messages ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE group_chat_messages ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES group_chat_messages(id) ON DELETE SET NULL;

CREATE POLICY "group_chat_messages_update_own" ON group_chat_messages
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── tour_messages ───────────────────────────────────────────
ALTER TABLE tour_messages ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE tour_messages ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES tour_messages(id) ON DELETE SET NULL;

CREATE POLICY "tour_messages_update_own" ON tour_messages
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── gig_messages ────────────────────────────────────────────
ALTER TABLE gig_messages ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE gig_messages ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES gig_messages(id) ON DELETE SET NULL;

CREATE POLICY "gig_messages_update_own" ON gig_messages
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
