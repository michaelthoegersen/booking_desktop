-- Direct message reactions (emoji reactions on DMs)
CREATE TABLE IF NOT EXISTS direct_message_reactions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid REFERENCES direct_messages(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES profiles(id) NOT NULL,
  emoji text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);

ALTER PUBLICATION supabase_realtime ADD TABLE direct_message_reactions;
ALTER TABLE direct_message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read reactions on own DMs"
  ON direct_message_reactions FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM direct_messages dm
    WHERE dm.id = message_id
    AND (auth.uid() = dm.sender_id OR auth.uid() = dm.receiver_id)
  ));

CREATE POLICY "Users can insert reactions"
  ON direct_message_reactions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own reactions"
  ON direct_message_reactions FOR DELETE
  USING (auth.uid() = user_id);
