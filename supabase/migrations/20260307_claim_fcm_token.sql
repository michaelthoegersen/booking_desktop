-- Atomically claim an FCM token for the current user.
-- Clears the token from any other profile first, then sets it on the caller.
-- This prevents duplicate tokens across profiles (same device, multiple accounts).
CREATE OR REPLACE FUNCTION claim_fcm_token(p_token text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE profiles SET fcm_token = NULL
  WHERE fcm_token = p_token AND id != auth.uid();

  UPDATE profiles SET fcm_token = p_token
  WHERE id = auth.uid();
END;
$$;
