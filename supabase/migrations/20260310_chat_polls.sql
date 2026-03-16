-- ============================================================
-- Chat polls
-- Tables for polls, options, and votes
-- ============================================================

-- ── chat_polls ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_polls (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  question text NOT NULL,
  created_by uuid REFERENCES profiles(id) NOT NULL,
  created_at timestamptz DEFAULT now(),
  is_closed boolean NOT NULL DEFAULT false
);

ALTER TABLE chat_polls ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read polls"
  ON chat_polls FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Users can create polls"
  ON chat_polls FOR INSERT
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Poll creators can update"
  ON chat_polls FOR UPDATE
  USING (auth.uid() = created_by)
  WITH CHECK (auth.uid() = created_by);

-- ── chat_poll_options ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_poll_options (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id uuid REFERENCES chat_polls(id) ON DELETE CASCADE NOT NULL,
  label text NOT NULL,
  position int NOT NULL DEFAULT 0
);

ALTER TABLE chat_poll_options ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read poll options"
  ON chat_poll_options FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Poll creator can insert options"
  ON chat_poll_options FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM chat_polls WHERE id = poll_id AND created_by = auth.uid())
  );

-- ── chat_poll_votes ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_poll_votes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id uuid REFERENCES chat_polls(id) ON DELETE CASCADE NOT NULL,
  option_id uuid REFERENCES chat_poll_options(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES profiles(id) NOT NULL,
  voted_at timestamptz DEFAULT now(),
  UNIQUE (poll_id, user_id)
);

ALTER TABLE chat_poll_votes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can read votes"
  ON chat_poll_votes FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Users can insert own votes"
  ON chat_poll_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own votes"
  ON chat_poll_votes FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own votes"
  ON chat_poll_votes FOR DELETE
  USING (auth.uid() = user_id);

-- Realtime for live vote updates
ALTER PUBLICATION supabase_realtime ADD TABLE chat_poll_votes;
