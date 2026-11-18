-- Titus U1.14: pg_catalog relation and foreign-key COLUMN metadata only.
-- This does not read rows, choose historical records, authorize a capture,
-- define a migration, or authorize any retirement. Review before executing.
-- Keep returned metadata out of public Git until separately classified.
WITH fk_catalog AS (
  SELECT
    child_ns.nspname::text || '.' || child.relname::text AS child,
    parent_ns.nspname::text || '.' || parent.relname::text AS parent,
    fk.conname::text AS constraint_name,
    array_agg(child_attribute.attname::text ORDER BY key_pair.ordinality) AS child_columns,
    array_agg(parent_attribute.attname::text ORDER BY key_pair.ordinality) AS parent_columns,
    fk.confdeltype::text AS on_delete_code,
    fk.confupdtype::text AS on_update_code,
    fk.condeferrable AS is_deferrable,
    fk.condeferred AS initially_deferred
  FROM pg_catalog.pg_constraint AS fk
  JOIN pg_catalog.pg_class AS child ON child.oid = fk.conrelid
  JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
  JOIN pg_catalog.pg_class AS parent ON parent.oid = fk.confrelid
  JOIN pg_catalog.pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
  JOIN LATERAL unnest(fk.conkey, fk.confkey)
    WITH ORDINALITY AS key_pair(child_attnum, parent_attnum, ordinality) ON true
  JOIN pg_catalog.pg_attribute AS child_attribute
    ON child_attribute.attrelid = child.oid
   AND child_attribute.attnum = key_pair.child_attnum
  JOIN pg_catalog.pg_attribute AS parent_attribute
    ON parent_attribute.attrelid = parent.oid
   AND parent_attribute.attnum = key_pair.parent_attnum
  WHERE fk.contype = 'f'
    AND (child_ns.nspname = 'titus' OR parent_ns.nspname = 'titus')
  GROUP BY
    fk.oid, child_ns.nspname, child.relname,
    parent_ns.nspname, parent.relname,
    fk.conname, fk.confdeltype, fk.confupdtype,
    fk.condeferrable, fk.condeferred
)
SELECT jsonb_build_object(
  'contractVersion', 'titus_u114_fk_column_catalog_only_v1',
  'rowValuesIncluded', false,
  'rowSelectionAuthorized', false,
  'productionChangesAuthorized', false,
  'foreignKeys', COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'child', child,
        'parent', parent,
        'constraintName', constraint_name,
        'childColumns', child_columns,
        'parentColumns', parent_columns,
        'onDeleteCode', on_delete_code,
        'onUpdateCode', on_update_code,
        'deferrable', is_deferrable,
        'initiallyDeferred', initially_deferred
      )
      ORDER BY child, parent, constraint_name
    ),
    '[]'::jsonb
  )
) AS source_only_fk_column_catalog
FROM fk_catalog;
