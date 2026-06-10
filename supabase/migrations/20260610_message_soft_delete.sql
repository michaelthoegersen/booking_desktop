-- ============================================================
-- Soft-delete for chat messages + notification cleanup
-- ============================================================
-- Replaces hard DELETE of chat messages with a soft delete so the
-- chat can show a "X slettet en melding" tombstone, and so the
-- related in-app notification can be removed automatically.
--
-- Shared across mobile (tourflow_mobile) and desktop (booking_desktop)
-- — both run on the same Supabase project.
-- ============================================================

-- ── 1. Soft-delete columns on message tables ────────────────
ALTER TABLE direct_messages      ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE direct_messages      ADD COLUMN IF NOT EXISTS deleted_by uuid;
ALTER TABLE group_chat_messages  ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE group_chat_messages  ADD COLUMN IF NOT EXISTS deleted_by uuid;
ALTER TABLE gig_messages         ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE gig_messages         ADD COLUMN IF NOT EXISTS deleted_by uuid;
ALTER TABLE tour_messages        ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE tour_messages        ADD COLUMN IF NOT EXISTS deleted_by uuid;

-- ── 2. Link notifications to the message that created them ───
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS message_id uuid;
CREATE INDEX IF NOT EXISTS notifications_message_id_idx
  ON notifications(message_id);

-- ── 3. UPDATE policies so the actors who could DELETE before
--       can now set deleted_at (soft delete). The existing
--       *_update_own policies still cover owners editing their
--       own messages; these add admin/management on top.
--       Multiple PERMISSIVE policies are OR'd together.
-- ------------------------------------------------------------
DROP POLICY IF EXISTS "direct_messages_update_admin" ON direct_messages;
CREATE POLICY "direct_messages_update_admin" ON direct_messages
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')));

DROP POLICY IF EXISTS "group_chat_messages_update_admin" ON group_chat_messages;
CREATE POLICY "group_chat_messages_update_admin" ON group_chat_messages
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')));

-- gig_messages already allows own-update; add admin/management.
DROP POLICY IF EXISTS "gig_messages_update_admin" ON gig_messages;
CREATE POLICY "gig_messages_update_admin" ON gig_messages
  FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')))
  WITH CHECK (EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND role IN ('admin', 'management')));

-- ── 4. Trigger: when a message is soft-deleted, drop the
--       in-app notification(s) that pointed at it. SECURITY
--       DEFINER so it can delete recipients' notification rows
--       (notifications RLS only lets a user delete their own).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION clear_notifications_on_message_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    DELETE FROM notifications WHERE message_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clear_notifications ON direct_messages;
CREATE TRIGGER trg_clear_notifications
  AFTER UPDATE OF deleted_at ON direct_messages
  FOR EACH ROW EXECUTE FUNCTION clear_notifications_on_message_delete();

DROP TRIGGER IF EXISTS trg_clear_notifications ON group_chat_messages;
CREATE TRIGGER trg_clear_notifications
  AFTER UPDATE OF deleted_at ON group_chat_messages
  FOR EACH ROW EXECUTE FUNCTION clear_notifications_on_message_delete();

DROP TRIGGER IF EXISTS trg_clear_notifications ON gig_messages;
CREATE TRIGGER trg_clear_notifications
  AFTER UPDATE OF deleted_at ON gig_messages
  FOR EACH ROW EXECUTE FUNCTION clear_notifications_on_message_delete();
