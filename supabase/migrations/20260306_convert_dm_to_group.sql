-- RPC function to atomically convert a DM conversation into a group chat
CREATE OR REPLACE FUNCTION convert_dm_to_group(
  p_peer_id uuid,
  p_group_name text,
  p_additional_member_ids uuid[] DEFAULT '{}'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_group_id uuid := gen_random_uuid();
  v_my_id uuid := auth.uid();
BEGIN
  -- Create group
  INSERT INTO group_chats (id, name, created_by)
  VALUES (v_group_id, p_group_name, v_my_id);

  -- Add creator + peer
  INSERT INTO group_chat_members (group_chat_id, user_id)
  VALUES (v_group_id, v_my_id), (v_group_id, p_peer_id);

  -- Add additional members
  IF array_length(p_additional_member_ids, 1) > 0 THEN
    INSERT INTO group_chat_members (group_chat_id, user_id)
    SELECT v_group_id, unnest(p_additional_member_ids);
  END IF;

  -- Copy DM messages (preserve original IDs for reply chains)
  INSERT INTO group_chat_messages (id, group_chat_id, user_id, sender_name, message, created_at, edited_at, reply_to_id, mentioned_user_ids)
  SELECT id, v_group_id, sender_id, sender_name, message, created_at, edited_at, reply_to_id, COALESCE(mentioned_user_ids, '{}')
  FROM direct_messages
  WHERE (sender_id = v_my_id AND receiver_id = p_peer_id)
     OR (sender_id = p_peer_id AND receiver_id = v_my_id)
  ORDER BY created_at;

  RETURN v_group_id;
END;
$$;
