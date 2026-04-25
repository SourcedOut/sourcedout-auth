/*
  # Add check_credits RPC

  ## Summary
  Adds a read-only `check_credits(p_user_id)` function that returns TRUE if the user
  is under their tier limit without incrementing lookups_used. Used by enrich-and-draft
  to gate the waterfall before running it, while deferring the actual deduction until
  after a successful email lookup.

  ## New RPC: check_credits(p_user_id uuid) → boolean
  - Returns TRUE if the user has quota remaining (same tier limits as deduct_credit)
  - Returns FALSE if the user is at or over their limit
  - Auto-creates the credits row for new users (same as deduct_credit)
  - Does NOT increment lookups_used
*/

CREATE OR REPLACE FUNCTION check_credits(p_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tier  text;
  v_used  integer;
  v_limit integer;
BEGIN
  INSERT INTO credits (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT tier, lookups_used
    INTO v_tier, v_used
    FROM credits
   WHERE user_id = p_user_id;

  v_limit := CASE v_tier
    WHEN 'pro'  THEN 100
    WHEN 'team' THEN 500
    ELSE 10
  END;

  RETURN v_used < v_limit;
END;
$$;
