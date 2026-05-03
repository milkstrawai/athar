-- Athar capture delete trigger function (v1).
-- Args:
--   TG_ARGV[0] record_type        (e.g. 'User') or 'null'
--   TG_ARGV[1] schema_name        (e.g. 'public')
--   TG_ARGV[2] table_name         (e.g. 'users')
--   TG_ARGV[3] primary_key        (e.g. 'id')
--   TG_ARGV[4] id_type            ('bigint' | 'integer' | 'uuid')
--   TG_ARGV[5] record_type_column ('type' | 'null')
--   TG_ARGV[6] capture_mode       ('identity' | 'only' | 'snapshot')
--   TG_ARGV[7] columns            ('{email,name}' or 'null')

CREATE OR REPLACE FUNCTION athar_capture_delete()
RETURNS trigger AS $$
DECLARE
  arg_record_type text;
  arg_schema_name text;
  arg_table_name text;
  arg_primary_key text;
  arg_id_type text;
  arg_record_type_column text;
  arg_capture_mode text;
  arg_columns text[];

  full_row jsonb;
  filtered_data jsonb;
  meta jsonb;
  meta_text text;
  computed_record_type text;
  computed_record_id text;
  computed_actor_type text;
  computed_actor_id text;
BEGIN
  arg_record_type := NULLIF(TG_ARGV[0], 'null');
  arg_schema_name := NULLIF(TG_ARGV[1], 'null');
  arg_table_name := NULLIF(TG_ARGV[2], 'null');
  arg_primary_key := NULLIF(TG_ARGV[3], 'null');
  arg_id_type := NULLIF(TG_ARGV[4], 'null');
  arg_record_type_column := NULLIF(TG_ARGV[5], 'null');
  arg_capture_mode := NULLIF(TG_ARGV[6], 'null');
  arg_columns := NULLIF(TG_ARGV[7], 'null')::text[];

  full_row := to_jsonb(OLD);

  computed_record_type := arg_record_type;
  IF arg_record_type_column IS NOT NULL AND full_row ? arg_record_type_column THEN
    IF (full_row ->> arg_record_type_column) IS NOT NULL THEN
      computed_record_type := full_row ->> arg_record_type_column;
    END IF;
  END IF;

  IF arg_capture_mode = 'identity' THEN
    filtered_data := '{}'::jsonb;
  ELSIF arg_capture_mode = 'snapshot' THEN
    filtered_data := full_row;
  ELSIF arg_capture_mode = 'only' THEN
    filtered_data := athar_filter_keys(full_row, arg_columns);
  ELSE
    RAISE EXCEPTION 'Unsupported Athar capture mode: %', arg_capture_mode;
  END IF;

  meta := '{}'::jsonb;
  meta_text := current_setting('athar.meta', true);
  IF coalesce(meta_text, '') <> '' THEN
    meta := meta_text::jsonb;
  END IF;

  computed_record_id := full_row ->> arg_primary_key;
  computed_actor_type := meta ->> 'actor_type';
  computed_actor_id := meta ->> 'actor_id';

  EXECUTE format(
    'INSERT INTO athar_deletions (
      record_type,
      record_id,
      actor_type,
      actor_id,
      schema_name,
      table_name,
      deleted_at,
      record_data,
      metadata,
      created_at
    )
    VALUES (
      $1,
      ($2)::%s,
      $3,
      CASE WHEN $4 IS NULL THEN NULL ELSE ($4)::%s END,
      $5,
      $6,
      statement_timestamp(),
      $7,
      $8,
      statement_timestamp()
    )',
    arg_id_type,
    arg_id_type
  )
  USING
    computed_record_type,
    computed_record_id,
    computed_actor_type,
    computed_actor_id,
    arg_schema_name,
    arg_table_name,
    filtered_data,
    meta - 'actor_type' - 'actor_id';

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;
