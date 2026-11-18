-- U1.11 CATALOG ONLY. Returns relation names, never customer rows.
-- Do not run pg_dump; this is a source-review inventory, NOT backup proof.
-- Historical programs and Course descendants may reference independent
-- Song/teacher/lesson/Person originals; no deletion scope is inferred.
SELECT
    child_ns.nspname || '.' || child.relname AS child,
    parent_ns.nspname || '.' || parent.relname AS parent
FROM pg_catalog.pg_constraint AS fk
JOIN pg_catalog.pg_class AS child ON child.oid = fk.conrelid
JOIN pg_catalog.pg_namespace AS child_ns ON child_ns.oid = child.relnamespace
JOIN pg_catalog.pg_class AS parent ON parent.oid = fk.confrelid
JOIN pg_catalog.pg_namespace AS parent_ns ON parent_ns.oid = parent.relnamespace
WHERE fk.contype = 'f'
  AND (child_ns.nspname = 'titus' OR parent_ns.nspname = 'titus')
ORDER BY child, parent;
