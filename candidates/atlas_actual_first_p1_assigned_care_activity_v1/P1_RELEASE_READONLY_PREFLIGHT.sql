-- UNI-OPS-01 P1 release eligibility: LIVE CATALOG READ ONLY.
-- This query checks exact public/private signatures, relations and the
-- fictional clone version; it changes NOTHING, grants NOTHING, and does not
-- establish independent source custody or production release authority.
-- Re-run against the intended live database with read-only credentials.
-- A requirement marked MISSING is a release prerequisite, not permission
-- to create a synthetic replacement or bypass the guarded domain writer.

WITH required(kind, identity, purpose) AS (
  VALUES
    ('function','atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text)','first-party existing manual Activity'),
    ('function','atlas.current_person_id_v1()','current signed canonical Person identity'),
    ('function','atlas.apply_work_lifecycle_transition_internal_v1(uuid,text,uuid,text)','universal source-owned Done'),
    ('function','atlas.establish_continuing_original_work_internal_v1(text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text)','governed continuing original'),
    ('function','atlas.continuing_original_work_result_continuation_internal_v1(uuid)','source-qualified physical continuation'),
    ('function','atlas.owner_establish_observed_continuing_care_work_self_api_v1(uuid,uuid,uuid,uuid,text,text,timestamptz,date,uuid)','signed governor original issuer used by test'),
    ('function','atlas.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)','required typed physical Result writer'),
    ('function','public.record_continuing_care_actual_self_api_v1(uuid,uuid,text,text,integer,text,date)','existing C1 signed care adapter'),
    ('function','atlas.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)','held P1 private source'),
    ('function','public.recognize_assigned_care_activity_self_api_v1(uuid,uuid,text,text)','held P1 authenticated public adapter'),
    ('relation','atlas.work_items','existing native original Work store'),
    ('relation','atlas.rhythm_satisfactions','existing physical satisfaction store'),
    ('relation','atlas.company_work_standing_assignment_scopes','existing native Ledger source scope'),
    ('relation','atlas.work_lifecycle_events_v1','new immutable universal lifecycle evidence'),
    ('relation','atlas.work_lifecycle_shadow_reconciliation_v1','new lifecycle audit reader'),
    ('relation','atlas.continuing_work_source_governance_events_v1','new source-governance evidence'),
    ('relation','atlas.assigned_care_activity_recognition_links_v1','held P1 append-only Activity-to-Result provenance'),
    ('migration','20261028235811','disposable clone-only validation version, NEVER canonical production release')
)
SELECT kind,identity,purpose,
 CASE
   WHEN kind='function' THEN pg_catalog.to_regprocedure(identity) IS NOT NULL
   WHEN kind='relation' THEN pg_catalog.to_regclass(identity) IS NOT NULL
   WHEN kind='migration' THEN EXISTS (
     SELECT 1 FROM supabase_migrations.schema_migrations m
     WHERE m.version=identity
   )
   ELSE false
 END AS exists_in_current_catalog,
 CASE
   WHEN kind='migration' THEN 'Must remain absent: test-only, not a releasable migration'
   ELSE 'Missing source: independently reconcile source custody before release'
 END AS review_rule
FROM required
ORDER BY kind,identity;
