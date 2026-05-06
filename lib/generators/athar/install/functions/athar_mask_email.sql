-- Athar email mask (v1).
-- Keeps the first 3 characters of the local part, appends 3 literal
-- asterisks, then the original domain. NULL and non-string inputs pass
-- through unchanged.

CREATE OR REPLACE FUNCTION athar_mask_email(value jsonb) RETURNS jsonb AS $$
DECLARE
  text_value text;
  at_position int;
  local_part text;
  domain text;
BEGIN
  IF value IS NULL OR jsonb_typeof(value) <> 'string' THEN
    RETURN value;
  END IF;

  text_value := value #>> '{}';
  at_position := position('@' in text_value);
  IF at_position = 0 THEN
    RETURN value;
  END IF;

  local_part := substring(text_value, 1, at_position - 1);
  domain := substring(text_value, at_position + 1);

  RETURN to_jsonb(left(local_part, 3) || '***@' || domain);
END;
$$ LANGUAGE plpgsql IMMUTABLE;
