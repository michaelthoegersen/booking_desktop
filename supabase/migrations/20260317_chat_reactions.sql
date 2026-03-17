-- Emoji reactions for gig messages
CREATE TABLE IF NOT EXISTS gig_message_reactions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid REFERENCES gig_messages(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES profiles(id) NOT NULL,
  emoji text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);

ALTER PUBLICATION supabase_realtime ADD TABLE gig_message_reactions;
ALTER TABLE gig_message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read gig message reactions"
  ON gig_message_reactions FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert gig message reactions"
  ON gig_message_reactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own gig message reactions"
  ON gig_message_reactions FOR DELETE
  USING (auth.uid() = user_id);

-- Emoji reactions for group chat messages
CREATE TABLE IF NOT EXISTS group_message_reactions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid REFERENCES group_chat_messages(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES profiles(id) NOT NULL,
  emoji text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);

ALTER PUBLICATION supabase_realtime ADD TABLE group_message_reactions;
ALTER TABLE group_message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read group message reactions"
  ON group_message_reactions FOR SELECT TO authenticated USING (true);

CREATE POLICY "Users can insert group message reactions"
  ON group_message_reactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own group message reactions"
  ON group_message_reactions FOR DELETE
  USING (auth.uid() = user_id);
