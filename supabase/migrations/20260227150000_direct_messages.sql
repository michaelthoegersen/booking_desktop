-- Add email column to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email text;

-- Direct messages table
CREATE TABLE IF NOT EXISTS direct_messages (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id uuid REFERENCES profiles(id) NOT NULL,
  receiver_id uuid REFERENCES profiles(id) NOT NULL,
  sender_name text NOT NULL DEFAULT '',
  message text NOT NULL DEFAULT '',
  created_at timestamptz DEFAULT now()
);

-- Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE direct_messages;

-- RLS
ALTER TABLE direct_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own DMs"
  ON direct_messages FOR SELECT
  USING (auth.uid() = sender_id OR auth.uid() = receiver_id);

CREATE POLICY "Users can insert own DMs"
  ON direct_messages FOR INSERT
  WITH CHECK (auth.uid() = sender_id);
