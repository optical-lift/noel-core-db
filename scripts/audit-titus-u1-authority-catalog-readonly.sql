-- U1.6. READ-ONLY production catalog contract audit (no customer rows).
-- This examines only function signatures, required column shapes, indexes,
-- one canonical responsibility trigger, and direct table privileges.
-- No DDL, no role/session impersonation, no source dump or release approval.
WITH
  required_functions(schema_name,function_signature) AS (
    VALUES
      ('atlas','atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)'),
      ('atlas','atlas.capability_root_authority_context_self_v1(uuid)'),
      ('atlas','atlas.current_active_ledger_seat_v1(uuid)'),
      ('atlas','atlas.current_person_id_v1()'),
      ('reality','reality.resolve_responsibility_relation_v1(uuid,text,text,text,uuid,text,jsonb)'),
      ('reality','reality.guard_responsibility_relation_v1()')
  ),
  function_audit AS (
    SELECT count(*) AS required_total,
       count(*) FILTER (WHERE to_regprocedure(function_signature) IS NOT NULL)
         AS present_total
    FROM required_functions
  ),
  required_columns(schema_name,table_name,column_name,type_name) AS (
    VALUES
      ('atlas','organizations','id','uuid'),
      ('atlas','organizations','status','text'),
      ('atlas','ledgers','id','uuid'),
      ('atlas','ledgers','status','text'),
      ('atlas','ledger_organization_participations','ledger_id','uuid'),
      ('atlas','ledger_organization_participations','organization_id','uuid'),
      ('atlas','ledger_organization_participations','participation_kind','text'),
      ('atlas','ledger_organization_participations','is_compatibility_primary','boolean'),
      ('atlas','ledger_organization_participations','status','text'),
      ('atlas','principals','person_id','uuid'),
      ('atlas','principals','status','text'),
      ('atlas','principal_ledger_authorities','principal_id','uuid'),
      ('atlas','principal_ledger_authorities','ledger_id','uuid'),
      ('atlas','principal_ledger_authorities','authority_kind','text'),
      ('atlas','principal_ledger_authorities','status','text'),
      ('ledger','ledgers','id','uuid'),
      ('ledger','ledgers','subject_entity_id','uuid'),
      ('ledger','ledgers','ledger_state','text'),
      ('ledger','ledgers','retired_at','timestamp with time zone'),
      ('reality','entities','id','uuid'),
      ('reality','entities','entity_kind','text'),
      ('reality','entities','identity_state','text'),
      ('reality','responsibility_relations','carrier_person_entity_id','uuid'),
      ('reality','responsibility_relations','responsibility_key','text'),
      ('reality','responsibility_relations','relation_state','text'),
      ('reality','responsibility_relations','jurisdiction_kind','text'),
      ('reality','responsibility_relations','jurisdiction_entity_id','uuid'),
      ('reality','responsibility_relations','jurisdiction_domain','text'),
      ('reality','responsibility_relations','scope','jsonb'),
      ('reality','responsibility_relations','permitted_operations','text[]'),
      ('reality','responsibility_relations','establishment_kind','text'),
      ('reality','responsibility_relations','source_person_entity_id','uuid'),
      ('reality','responsibility_relations','establishment_basis','jsonb'),
      ('reality','responsibility_relations','began_at','timestamp with time zone'),
      ('reality','responsibility_relations','ended_at','timestamp with time zone'),
      ('reality','auth_person_bindings','auth_user_id','uuid'),
      ('reality','auth_person_bindings','person_entity_id','uuid'),
      ('reality','auth_person_bindings','binding_state','text'),
      ('reality','auth_person_bindings','retired_at','timestamp with time zone'),
      ('compatibility','legacy_bindings','legacy_schema','text'),
      ('compatibility','legacy_bindings','legacy_table','text'),
      ('compatibility','legacy_bindings','legacy_key','text'),
      ('compatibility','legacy_bindings','disposition','text'),
      ('compatibility','legacy_bindings','new_schema','text'),
      ('compatibility','legacy_bindings','new_table','text'),
      ('compatibility','legacy_bindings','new_id','uuid'),
      ('auth','sessions','id','uuid'),
      ('auth','sessions','user_id','uuid'),
      ('auth','sessions','not_after','timestamp with time zone'),
      ('auth','users','id','uuid'),
      ('auth','users','deleted_at','timestamp with time zone'),
      ('auth','users','banned_until','timestamp with time zone')
  ),
  column_audit AS (
    SELECT count(*) AS required_total,
      count(*) FILTER(WHERE c.column_name IS NOT NULL) AS present_total
    FROM required_columns r
    LEFT JOIN information_schema.columns c
      ON c.table_schema=r.schema_name AND c.table_name=r.table_name
     AND c.column_name=r.column_name AND c.data_type=CASE
       WHEN r.type_name IN ('uuid','text','boolean','jsonb') THEN r.type_name
       WHEN r.type_name='text[]' THEN 'ARRAY'
       ELSE r.type_name END
     AND (r.type_name<>'text[]' OR c.udt_name='_text')
  ),
  trigger_audit AS (
    SELECT count(*) FILTER (WHERE t.tgenabled IN ('O','A')
      AND t.tgfoid=to_regprocedure('reality.guard_responsibility_relation_v1()')
      AND (t.tgtype & 1)=1 AND (t.tgtype & 2)=2 AND (t.tgtype & 16)=16
      AND (t.tgtype & 4)=4) AS required_guard_count
    FROM pg_trigger t
    WHERE t.tgrelid='reality.responsibility_relations'::regclass
      AND NOT t.tgisinternal
  ),
  uniqueness_audit AS (
    SELECT
      EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname='reality'
        AND i.tablename='auth_person_bindings'
        AND i.indexname='reality_auth_one_active_person_shared_v1'
        AND i.indexdef ILIKE '%UNIQUE INDEX%') AS one_active_person,
      EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname='reality'
        AND i.tablename='auth_person_bindings'
        AND i.indexname='reality_auth_person_bindings_one_active_user_idx'
        AND i.indexdef ILIKE '%UNIQUE INDEX%') AS one_active_auth,
      EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname='atlas'
        AND i.tablename='ledger_organization_participations'
        AND i.indexname='ledger_organization_participations_one_primary_org_uq'
        AND i.indexdef ILIKE '%UNIQUE INDEX%') AS one_primary_governing_ledger
  ),
  privacy_audit AS (
    SELECT
      has_table_privilege('anon','reality.responsibility_relations','SELECT')
        AS anon_can_directly_read_responsibility,
      has_table_privilege('authenticated','reality.responsibility_relations','SELECT')
        AS authenticated_can_directly_read_responsibility,
      to_regprocedure('atlas.current_person_for_private_course_v1()')
         IS NOT NULL AS titus_signed_person_already_live
  )
SELECT jsonb_build_object(
 'contractVersion','held_titus_u1_catalog_preflight_v1',
 'functionSignaturesPresent',f.present_total,
 'functionSignaturesExpected',f.required_total,
 'requiredColumnsPresent',c.present_total,
 'requiredColumnsExpected',c.required_total,
 'realityGuardEnabled',g.required_guard_count=1,
 'realityGuardCount',g.required_guard_count,
 'authUniquenessPreserved',u.one_active_person AND u.one_active_auth,
 'atlasPrimaryLedgerUniqueness',u.one_primary_governing_ledger,
 'anonResponsibilityDirectSelect',p.anon_can_directly_read_responsibility,
 'authenticatedResponsibilityDirectSelect',p.authenticated_can_directly_read_responsibility,
 'titusSignedPersonAlreadyLive',p.titus_signed_person_already_live,
 'structuralPreflightPass',
    f.present_total=f.required_total AND c.present_total=c.required_total
    AND g.required_guard_count=1 AND u.one_active_person AND u.one_active_auth
    AND u.one_primary_governing_ledger,
 'productionSchemaCloneTested',false,
 'ownerApprovedRelease',false
) AS report
FROM function_audit f
CROSS JOIN column_audit c
CROSS JOIN trigger_audit g
CROSS JOIN uniqueness_audit u
CROSS JOIN privacy_audit p;
