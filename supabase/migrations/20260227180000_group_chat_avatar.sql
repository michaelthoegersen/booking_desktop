-- Add avatar_url to group_chats
ALTER TABLE group_chats ADD COLUMN IF NOT EXISTS avatar_url text;

-- UPDATE policy on group_chats for members (set avatar/name)
CREATE POLICY "Members can update group_chats"
  ON group_chats FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM group_chat_members
      WHERE group_chat_members.group_chat_id = group_chats.id
        AND group_chat_members.user_id = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM group_chat_members
      WHERE group_chat_members.group_chat_id = group_chats.id
        AND group_chat_members.user_id = auth.uid()
    )
  );

-- DELETE policy on group_chat_members (remove members)
CREATE POLICY "Members can remove members from group"
  ON group_chat_members FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM group_chat_members AS gcm
      WHERE gcm.group_chat_id = group_chat_members.group_chat_id
        AND gcm.user_id = auth.uid()
    )
  );

-- Storage bucket for group avatars
INSERT INTO storage.buckets (id, name, public)
VALUES ('group-avatars', 'group-avatars', true)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users to upload to group-avatars
CREATE POLICY "Authenticated users can upload group avatars"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'group-avatars');

-- Allow authenticated users to update/overwrite group avatars
CREATE POLICY "Authenticated users can update group avatars"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'group-avatars')
  WITH CHECK (bucket_id = 'group-avatars');

-- Allow public read access to group avatars
CREATE POLICY "Public read access to group avatars"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'group-avatars');
