-- Add mentioned_user_ids column to all chat message tables
ALTER TABLE direct_messages ADD COLUMN IF NOT EXISTS mentioned_user_ids uuid[] DEFAULT '{}';
ALTER TABLE group_chat_messages ADD COLUMN IF NOT EXISTS mentioned_user_ids uuid[] DEFAULT '{}';
ALTER TABLE tour_messages ADD COLUMN IF NOT EXISTS mentioned_user_ids uuid[] DEFAULT '{}';
ALTER TABLE gig_messages ADD COLUMN IF NOT EXISTS mentioned_user_ids uuid[] DEFAULT '{}';
