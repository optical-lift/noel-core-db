-- Noel issue #2255 / draft PR #2263. READ-ONLY production compatibility audit.
-- No transaction, DDL, Auth/session mutation, data INSERT/UPDATE/DELETE,
-- privilege change, permission decision or public grant is authorized here.
-- Each statement returns aggregate counts or catalog names only.
-- DO NOT treat a catalog match as GoTrue signed privacy acceptance.
--
-- Check 1 — proposed Work field authority is NOT installed in production.
SELECT
 to_regclass('atlas.connected_person_work_field_decision_events_v1')::text
    AS proposed_decisions_table,
 to_regprocedure('atlas.connected_person_work_field_source_eligible_v1(uuid,uuid,uuid)')::text
    AS proposed_source_predicate,
 to_regprocedure('public.governor_decide_connected_person_work_field_self_api_v1(uuid,uuid,uuid,text,text,text,uuid,text,timestamptz)')::text
    AS proposed_governor_writer,
 to_regprocedure('public.connected_person_work_approved_fields_self_api_v1(uuid,uuid)')::text
    AS proposed_worker_reader;

-- Check 2 — exact SOURCE columns required by the held candidate.
WITH required(object_name,column_name,expected_type) AS (
VALUES
 ('atlas.work_items','id','uuid'),
 ('atlas.work_items','organization_id','uuid'),
 ('atlas.work_items','title','text'),
 ('atlas.work_items','instructions','text'),
 ('atlas.work_items','work_state','text'),
 ('atlas.work_allocations','work_item_id','uuid'),
 ('atlas.work_allocations','organization_id','uuid'),
 ('atlas.work_allocations','assignee_canonical_person_id','uuid'),
 ('atlas.work_allocations','assignee_membership_id','uuid'),
 ('atlas.work_allocations','allocation_role','text'),
 ('atlas.work_allocations','state','text'),
 ('atlas.work_allocations','establishment_basis','jsonb'),
 ('atlas.work_allocations','establishment_basis_kind','text'),
 ('atlas.company_work_native_ledger_relevance','organization_id','uuid'),
 ('atlas.company_work_native_ledger_relevance','work_item_id','uuid'),
 ('atlas.company_work_native_ledger_relevance','ledger_id','uuid'),
 ('atlas.company_work_native_ledger_relevance','attribution_state','text'),
 ('atlas.company_work_native_ledger_relevance','evidence_kind','text'),
 ('atlas.company_work_native_ledger_relevance','source_schema','text'),
 ('atlas.company_work_native_ledger_relevance','source_table','text'),
 ('atlas.company_work_native_ledger_relevance','source_id','uuid')
)
SELECT required.object_name,required.column_name,required.expected_type,
 COALESCE(pg_catalog.format_type(a.atttypid,a.atttypmod),'MISSING') AS actual_type,
 COALESCE(pg_catalog.format_type(a.atttypid,a.atttypmod)=required.expected_type,false)
   AS exact_type_matches
FROM required
LEFT JOIN pg_catalog.pg_class c ON c.oid=to_regclass(required.object_name)
LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid
 AND a.attname=required.column_name AND a.attnum>0 AND NOT a.attisdropped
ORDER BY exact_type_matches,required.object_name,required.column_name;

-- Check 3 — existing native authorization helpers and public alternative RPCs.
WITH required(signature) AS (VALUES
 ('auth.uid()'),
 ('atlas.current_person_id_v1()'),
 ('atlas.current_principal_id_v1()'),
 ('atlas.reality_access_self_api_v1()'),
 ('atlas.principal_has_ledger_authority_v1(uuid,uuid)'),
 ('atlas.person_has_native_ledger_connection_v1(uuid,uuid,uuid)'),
 ('atlas.company_work_native_ledger_exact_source_v1(uuid,uuid)'),
 ('pg_catalog.sha256(bytea)'),
 ('pg_catalog.hashtextextended(text,bigint)'),
 ('pg_catalog.pg_advisory_xact_lock(bigint)'),
 ('pg_catalog.gen_random_uuid()'),
 ('public.connected_person_my_work_self_api_v1(integer,uuid)'),
 ('public.connected_person_company_work_today_self_api_v1(integer)'),
 ('public.connected_person_company_work_day_self_api_v1(date)'),
 ('public.company_work_worker_day_self_api_v1(date,integer)')
)
SELECT signature,to_regprocedure(signature) IS NOT NULL AS exists
FROM required ORDER BY signature;

-- Check 4 — high-level number of real existing records, never their values.
SELECT resource,record_count FROM (
 SELECT 'auth.users' resource,count(*) record_count FROM auth.users
 UNION ALL SELECT 'auth.sessions',count(*) FROM auth.sessions
 UNION ALL SELECT 'reality.entities',count(*) FROM reality.entities
 UNION ALL SELECT 'ledger.seats',count(*) FROM ledger.seats
 UNION ALL SELECT 'atlas.work_items',count(*) FROM atlas.work_items
 UNION ALL SELECT 'atlas.work_allocations',count(*) FROM atlas.work_allocations
 UNION ALL SELECT 'atlas.company_work_native_ledger_relevance',count(*)
   FROM atlas.company_work_native_ledger_relevance
) totals ORDER BY resource;

-- Check 5 — separately protect original completed/released history.
WITH native AS MATERIALIZED (
 SELECT a.state AS allocation_state,w.work_state,
 a.assignee_canonical_person_id person_id,w.organization_id,
 w.id AS work_item_id,
 (a.establishment_basis->>'nativeLedgerId')::uuid AS ledger_id
 FROM atlas.work_allocations a
 JOIN atlas.work_items w ON w.id=a.work_item_id
   AND w.organization_id=a.organization_id
 WHERE a.assignee_canonical_person_id IS NOT NULL
   AND a.assignee_membership_id IS NULL
   AND a.allocation_role='responsible'
   AND a.establishment_basis_kind IN
    ('person_connection_receiver_uptake',
     'delegated_under_standing_scope',
     'ledger_connection_direct_assignment')
   AND a.establishment_basis ? 'nativeLedgerId'
   AND w.work_state IN ('open','completed')
)
SELECT allocation_state,work_state,
 COUNT(*) original_allocations,
 COUNT(*) FILTER (WHERE atlas.person_has_native_ledger_connection_v1(
   organization_id,ledger_id,person_id)) AS current_native_connections,
 COUNT(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
    WHERE rel.organization_id=native.organization_id
      AND rel.work_item_id=native.work_item_id
      AND rel.ledger_id=native.ledger_id
      AND rel.attribution_state='active')) AS current_original_work_relevance
FROM native GROUP BY allocation_state,work_state
ORDER BY allocation_state,work_state;
