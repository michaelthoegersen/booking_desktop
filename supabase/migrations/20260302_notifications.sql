-- ============================================================
-- NOTIFICATIONS TABLE
-- In-app bell + push notification tracking
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title      text        NOT NULL,
  body       text        DEFAULT '',
  read       boolean     DEFAULT false,
  draft_id   text,
  created_at timestamptz DEFAULT now()
);

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Users can read their own notifications
CREATE POLICY "users_read_own_notifications" ON notifications
  FOR SELECT USING (auth.uid() = user_id);

-- Users can update (mark as read) their own notifications
CREATE POLICY "users_update_own_notifications" ON notifications
  FOR UPDATE USING (auth.uid() = user_id);

-- Service role can insert (via edge functions)
-- No INSERT policy needed — edge functions use service_role key

-- ── Index for fast lookup ────────────────────────────────────
CREATE INDEX idx_notifications_user_created
  ON notifications (user_id, created_at DESC);

-- ── Realtime ─────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
