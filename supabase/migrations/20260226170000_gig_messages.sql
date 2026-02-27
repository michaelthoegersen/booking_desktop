-- ============================================================
-- TourFlow — Gig Chat Messages + Profile/Gig additions
-- ============================================================

CREATE TABLE IF NOT EXISTS gig_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gig_id       uuid NOT NULL REFERENCES gigs(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id),
  sender_name  text NOT NULL,
  message      text NOT NULL,
  is_admin     boolean DEFAULT false,
  created_at   timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_gig_messages_gig ON gig_messages(gig_id);
ALTER PUBLICATION supabase_realtime ADD TABLE gig_messages;

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE gigs ADD COLUMN IF NOT EXISTS type text DEFAULT 'gig';
