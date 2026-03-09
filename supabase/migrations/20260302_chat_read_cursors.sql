-- Track when each user last read a DM conversation with a peer
CREATE TABLE IF NOT EXISTS dm_read_cursors (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  peer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, peer_id)
);

-- Track when each user last read a group chat
CREATE TABLE IF NOT EXISTS group_read_cursors (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  group_chat_id uuid NOT NULL REFERENCES group_chats(id) ON DELETE CASCADE,
  last_read_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, group_chat_id)
);

-- RLS
ALTER TABLE dm_read_cursors ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_read_cursors ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_dm_cursors" ON dm_read_cursors FOR ALL
  USING (user_id = auth.uid());

CREATE POLICY "users_own_group_cursors" ON group_read_cursors FOR ALL
  USING (user_id = auth.uid());
