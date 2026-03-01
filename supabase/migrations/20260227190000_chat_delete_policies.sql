-- ============================================================
-- DELETE policies for chat tables — admin only
-- ============================================================

-- direct_messages: admin kan slette DM-er
-- (reactions cascader automatisk via FK ON DELETE CASCADE)
CREATE POLICY "Admin can delete direct messages"
  ON public.direct_messages FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- group_chats: admin kan slette grupper
-- (members + messages cascader automatisk via FK ON DELETE CASCADE)
CREATE POLICY "Admin can delete group chats"
  ON public.group_chats FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('admin', 'management')
    )
  );

-- group_chat_messages: admin kan slette enkeltmeldinger
CREATE POLICY "Admin can delete group chat messages"
  ON public.group_chat_messages FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role IN ('admin', 'management')
    )
  );
