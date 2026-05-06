-- Athar mask dispatcher (v1).
-- Walks an array of "column:mask_name[:arg1:arg2]" specs and applies each
-- mask to the named column inside the supplied jsonb object. Built-ins
-- are dispatched via a hardcoded CASE; unknown names are routed to a
-- custom user-installed athar_mask_<name>(jsonb) RETURNS jsonb function
-- via EXECUTE (the format() call %I-quotes the identifier).
--
-- IMPORTANT: jsonb_set propagates SQL NULL through `new_value`, which
-- would wipe the entire `data` object if a mask returned SQL NULL. We
-- COALESCE to JSON null so NULL-returning masks (e.g. athar_mask_email
-- on a NULL input) preserve the column as JSON null without corrupting
-- the surrounding object.

CREATE OR REPLACE FUNCTION athar_apply_masks(
  data jsonb,
  masks text[]
) RETURNS jsonb AS $$
DECLARE
  spec text;
  parts text[];
  column_name text;
  mask_name text;
  value jsonb;
  masked_value jsonb;
  head_arg int;
  tail_arg int;
BEGIN
  IF data IS NULL OR masks IS NULL THEN
    RETURN data;
  END IF;

  FOREACH spec IN ARRAY masks LOOP
    parts := string_to_array(spec, ':');
    column_name := parts[1];
    mask_name := parts[2];

    IF NOT (data ? column_name) THEN
      CONTINUE;
    END IF;

    value := data -> column_name;
    masked_value := NULL;

    CASE mask_name
      WHEN 'email' THEN
        masked_value := athar_mask_email(value);
      WHEN 'partial' THEN
        head_arg := parts[3]::int;
        tail_arg := parts[4]::int;
        masked_value := athar_mask_partial(value, head_arg, tail_arg);
      WHEN 'hash' THEN
        masked_value := athar_mask_hash(value);
      ELSE
        EXECUTE format('SELECT %I($1)', 'athar_mask_' || mask_name)
          INTO masked_value
          USING value;
    END CASE;

    data := jsonb_set(
      data,
      ARRAY[column_name],
      COALESCE(masked_value, 'null'::jsonb)
    );
  END LOOP;

  RETURN data;
END;
$$ LANGUAGE plpgsql;
