-- Athar SHA-256 hash mask (v1).
-- Hashes the textual representation of any JSON scalar. Deterministic
-- (no salt). NULL passes through. Uses Postgres built-in sha256() (PG 11+);
-- Athar requires PG 13+, so no extension is needed.

CREATE OR REPLACE FUNCTION athar_mask_hash(value jsonb) RETURNS jsonb AS $$
DECLARE
  text_value text;
BEGIN
  IF value IS NULL THEN
    RETURN value;
  END IF;

  IF jsonb_typeof(value) = 'string' THEN
    text_value := value #>> '{}';
  ELSE
    text_value := value::text;
  END IF;

  RETURN to_jsonb(encode(sha256(text_value::bytea), 'hex'));
END;
$$ LANGUAGE plpgsql IMMUTABLE;
