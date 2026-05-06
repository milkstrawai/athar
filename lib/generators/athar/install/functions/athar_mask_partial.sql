-- Athar partial mask (v1).
-- Keeps the first `head` and last `tail` characters; replaces the middle
-- with `*` (length-preserving). When head+tail >= length, returns the
-- whole string as asterisks of the same length.

CREATE OR REPLACE FUNCTION athar_mask_partial(
  value jsonb,
  head int,
  tail int
) RETURNS jsonb AS $$
DECLARE
  text_value text;
  total_length int;
  middle_length int;
BEGIN
  IF value IS NULL OR jsonb_typeof(value) <> 'string' THEN
    RETURN value;
  END IF;

  IF head < 0 OR tail < 0 THEN
    RAISE EXCEPTION 'athar_mask_partial: head and tail must be non-negative (got %, %)', head, tail;
  END IF;

  text_value := value #>> '{}';
  total_length := char_length(text_value);

  IF head + tail >= total_length THEN
    RETURN to_jsonb(repeat('*', total_length));
  END IF;

  middle_length := total_length - head - tail;
  RETURN to_jsonb(
    substring(text_value, 1, head) ||
    repeat('*', middle_length) ||
    substring(text_value, total_length - tail + 1)
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;
