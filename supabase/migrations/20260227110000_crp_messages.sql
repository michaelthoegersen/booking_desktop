-- ============================================================
-- TourFlow — Crew Chat Messages (per gig)
-- ============================================================

CREATE TABLE IF NOT EXISTS crp_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id       uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id),
  sender_name  text NOT NULL,
  message      text NOT NULL,
  is_admin     boolean DEFAULT false,
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_crp_messages_gig ON crp_messages(gig_id);
ALTER PUBLICATION supabase_realtime ADD TABLE crp_messages;

ALTER TABLE crp_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read crp_messages"
  ON crp_messages FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Authenticated users can insert crp_messages"
  ON crp_messages FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);
