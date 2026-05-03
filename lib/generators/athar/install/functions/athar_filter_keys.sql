-- Athar filter keys function (v1).
-- Keeps only the listed keys from a JSONB object.
-- Missing keys are ignored. Empty column list returns {}.

CREATE OR REPLACE FUNCTION athar_filter_keys(
  data jsonb,
  columns text[]
) RETURNS jsonb AS $$
DECLARE
  result jsonb := '{}'::jsonb;
  column_name text;
BEGIN
  IF data IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  IF columns IS NULL OR array_length(columns, 1) IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  FOREACH column_name IN ARRAY columns LOOP
    IF data ? column_name THEN
      result := result || jsonb_build_object(column_name, data -> column_name);
    END IF;
  END LOOP;

  RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;
