-- ============================================================
-- Add missing DELETE policy for gig_messages
-- Aligns with direct_messages and group_chat_messages delete
-- policies which check profiles.role (not company_members).
-- ============================================================

DROP POLICY IF EXISTS "gig_msg_delete_own" ON gig_messages;

CREATE POLICY "gig_msg_delete"
  ON gig_messages FOR DELETE TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role IN ('admin', 'management')
    )
  );
