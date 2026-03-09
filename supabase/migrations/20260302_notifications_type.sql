-- ============================================================
-- ADD type + gig_id TO notifications
-- Types: 'gig' | 'gig_chat' | 'chat_dm' | 'chat_group' | 'tour' | 'general'
-- ============================================================

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS type text DEFAULT 'general';
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS gig_id uuid;

-- Allow users to delete their own notifications (for "clear all" feature)
CREATE POLICY "users_delete_own_notifications" ON notifications
  FOR DELETE USING (auth.uid() = user_id);
