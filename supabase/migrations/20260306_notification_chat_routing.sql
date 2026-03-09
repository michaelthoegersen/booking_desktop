-- Add chat routing columns to notifications table
-- so we can deep-link to the correct chat screen.

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS peer_id uuid;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS group_id uuid;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS group_name text;
