-- Video call signaling table
-- Used for incoming call notifications between users
CREATE TABLE IF NOT EXISTS video_calls (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  caller_id uuid NOT NULL REFERENCES auth.users(id),
  callee_id uuid NOT NULL REFERENCES auth.users(id),
  channel_name text NOT NULL,
  status text NOT NULL DEFAULT 'ringing', -- ringing, answered, declined, missed
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE video_calls ENABLE ROW LEVEL SECURITY;

-- Caller and callee can see their own calls
CREATE POLICY "Users can see own calls"
  ON video_calls FOR SELECT
  USING (auth.uid() = caller_id OR auth.uid() = callee_id);

-- Any authenticated user can create a call
CREATE POLICY "Users can create calls"
  ON video_calls FOR INSERT
  WITH CHECK (auth.uid() = caller_id);

-- Caller and callee can update status
CREATE POLICY "Users can update own calls"
  ON video_calls FOR UPDATE
  USING (auth.uid() = caller_id OR auth.uid() = callee_id);

-- Clean up old calls (auto-expire after 2 minutes)
CREATE POLICY "Users can delete own calls"
  ON video_calls FOR DELETE
  USING (auth.uid() = caller_id OR auth.uid() = callee_id);

-- Enable realtime for this table
ALTER publication supabase_realtime ADD TABLE video_calls;
