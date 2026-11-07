-- READ-ONLY structural/privilege postconditions.
-- Run ONLY after installing HELD_source_candidate.sql in a disposable
-- protected full-schema clone. This is not a production migration and
-- these booleans are NOT independent signed-actor authorization proof.

WITH assertions(check_name, passed) AS (
  SELECT 'offer table exists',
    to_regclass('atlas.venue_bed_shared_use_authorizations_v1') IS NOT NULL
  UNION ALL
  SELECT 'Venue Work reference table exists',
    to_regclass('atlas.venue_bed_work_references_v1') IS NOT NULL
  UNION ALL
  SELECT 'offer table has RLS',
    EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas'
        AND c.relname='venue_bed_shared_use_authorizations_v1'
        AND c.relrowsecurity
    )
  UNION ALL
  SELECT 'Venue reference table has RLS',
    EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='atlas'
        AND c.relname='venue_bed_work_references_v1'
        AND c.relrowsecurity
    )
  UNION ALL
  SELECT 'authenticated cannot directly read offer table',
    NOT has_table_privilege(
      'authenticated',
      'atlas.venue_bed_shared_use_authorizations_v1',
      'SELECT')
  UNION ALL
  SELECT 'authenticated cannot directly write offer table',
    NOT has_table_privilege(
      'authenticated',
      'atlas.venue_bed_shared_use_authorizations_v1',
      'INSERT,UPDATE,DELETE')
  UNION ALL
  SELECT 'authenticated cannot directly read Venue references',
    NOT has_table_privilege(
      'authenticated',
      'atlas.venue_bed_work_references_v1',
      'SELECT')
  UNION ALL
  SELECT 'authenticated cannot directly write Venue references',
    NOT has_table_privilege(
      'authenticated',
      'atlas.venue_bed_work_references_v1',
      'INSERT,UPDATE,DELETE')
  UNION ALL
  SELECT 'anon cannot directly read offer',
    NOT has_table_privilege(
      'anon',
      'atlas.venue_bed_shared_use_authorizations_v1',
      'SELECT')
  UNION ALL
  SELECT 'no callable authenticated offer',
    NOT has_function_privilege(
      'authenticated',
      'atlas.offer_venue_bed_shared_use_self_v1(uuid,uuid,uuid,text)',
      'EXECUTE')
  UNION ALL
  SELECT 'no callable authenticated accept',
    NOT has_function_privilege(
      'authenticated',
      'atlas.accept_venue_bed_shared_use_self_v1(uuid)',
      'EXECUTE')
  UNION ALL
  SELECT 'no callable authenticated Work link',
    NOT has_function_privilege(
      'authenticated',
      'atlas.establish_venue_work_bed_reference_self_v1(uuid,uuid,text,jsonb)',
      'EXECUTE')
  UNION ALL
  SELECT 'no callable authenticated withdraw',
    NOT has_function_privilege(
      'authenticated',
      'atlas.withdraw_venue_bed_shared_use_self_v1(uuid)',
      'EXECUTE')
  UNION ALL
  SELECT 'Flower original Bed context guard unchanged',
    md5(pg_get_functiondef(
      'atlas.guard_work_growing_object_context_v1()'::regprocedure
    )) = '2c7de5ef8fa2519a5afec4feecf28f4a'
  UNION ALL
  SELECT 'Flower original Bed context writer unchanged',
    md5(pg_get_functiondef(
      'atlas.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)'::regprocedure
    )) = 'd430424f04b3e27a09be3bae00f7d821'
  UNION ALL
  SELECT 'existing unique active Flower Farm custody index preserved',
    EXISTS (
      SELECT 1 FROM pg_index i
      JOIN pg_class c ON c.oid=i.indexrelid
      WHERE c.relname='farm_crop_ledger_custody_one_active_v1'
        AND i.indisunique
        AND pg_get_indexdef(i.indexrelid) ILIKE '%(farm_id)%'
    )
)
-- A false postcondition must fail the clone job, never merely print a row.
-- Zero denominator is evaluated only for failed source-dependent checks.
SELECT check_name,
  (1 / CASE WHEN coalesce(passed,false) THEN 1 ELSE 0 END) = 1 AS passed
FROM assertions ORDER BY check_name;
