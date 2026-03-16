-- ============================================================
-- Chat attachments support
-- Adds message_type + attachment_url to all 4 message tables
-- message_type: 'text' (default), 'image', 'file', 'gif', 'poll'
-- ============================================================

-- ── direct_messages ─────────────────────────────────────────
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS attachment_url text;

-- ── group_chat_messages ─────────────────────────────────────
ALTER TABLE group_chat_messages ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';
ALTER TABLE group_chat_messages ADD COLUMN IF NOT EXISTS attachment_url text;

-- ── tour_messages ───────────────────────────────────────────
ALTER TABLE tour_messages ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';
ALTER TABLE tour_messages ADD COLUMN IF NOT EXISTS attachment_url text;

-- ── gig_messages ────────────────────────────────────────────
ALTER TABLE gig_messages ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';
ALTER TABLE gig_messages ADD COLUMN IF NOT EXISTS attachment_url text;
