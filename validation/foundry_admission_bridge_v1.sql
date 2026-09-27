-- Contract validation: Atlas Foundry -> Atlas Admission Bridge v1.
--
-- Read-only assertions. This validator stages no package, creates no Entity,
-- opens no onboarding case, and performs no canonical Reality reconciliation.

do $block$
declare
  v_operator uuid;
  v_def text;
  v_source_check text;
  v_direct_table_grants integer;
begin
  if to_regclass('admission.foundry_packages') is null
     or to_regclass('admission.foundry_admission_cases') is null then
    raise exception 'Foundry admission bridge tables are unavailable.';
  end if;

  select id into v_operator
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  if v_operator is null then
    raise exception 'Foundry admission operator Reality Person is unavailable.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,'foundry_admission_governance','foundry_admission.read',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  ) is null
  or reality.resolve_responsibility_relation_v1(
    v_operator,'foundry_admission_governance','foundry_admission.plan',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  ) is null
  or reality.resolve_responsibility_relation_v1(
    v_operator,'foundry_admission_governance','foundry_admission.execute',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  ) is null then
    raise exception 'Foundry admission responsibility operation set is incomplete.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,'foundry_admission_governance','canonical_merge.execute',
    'domain',null,'atlas.foundry_admission','{}'::jsonb
  ) is not null then
    raise exception 'Foundry admission responsibility improperly grants canonical merge authority.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,'reality_identity_adjudication','canonical_merge.execute',
    'domain',null,'reality.identity_resolution','{}'::jsonb
  ) is not null then
    raise exception 'Identity evidence adjudication improperly grants canonical merge authority.';
  end if;

  if not has_function_privilege(
    'service_role','atlas.stage_foundry_ledger_candidate_service_v1(jsonb,text,jsonb)','EXECUTE'
  ) then
    raise exception 'Foundry staging service is not executable by service_role.';
  end if;

  if not has_function_privilege(
    'service_role','atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(uuid,uuid,jsonb,text)','EXECUTE'
  ) then
    raise exception 'Foundry reconciliation proposal service is unavailable.';
  end if;

  if has_function_privilege(
    'service_role','atlas.foundry_admission_plan_self_api_v1(uuid,jsonb)','EXECUTE'
  ) or has_function_privilege(
    'service_role','atlas.foundry_admission_case_self_api_v1(uuid)','EXECUTE'
  ) or has_function_privilege(
    'service_role','atlas.foundry_admission_handoff_self_api_v1(uuid,text)','EXECUTE'
  ) then
    raise exception 'service_role improperly holds human Foundry admission authority.';
  end if;

  if not has_function_privilege(
    'authenticated','atlas.foundry_admission_plan_self_api_v1(uuid,jsonb)','EXECUTE'
  ) or not has_function_privilege(
    'authenticated','atlas.foundry_admission_case_self_api_v1(uuid)','EXECUTE'
  ) or not has_function_privilege(
    'authenticated','atlas.foundry_admission_handoff_self_api_v1(uuid,text)','EXECUTE'
  ) then
    raise exception 'Authenticated Foundry admission command surface is incomplete.';
  end if;

  select count(*)::integer into v_direct_table_grants
  from information_schema.role_table_grants g
  where g.grantee in ('anon','authenticated','service_role')
    and g.table_schema='admission'
    and g.table_name in ('foundry_packages','foundry_admission_cases')
    and g.privilege_type in ('INSERT','UPDATE','DELETE');

  if v_direct_table_grants<>0 then
    raise exception 'Foundry admission tables expose % direct mutation grants.',v_direct_table_grants;
  end if;

  select pg_get_functiondef(
    'atlas.stage_foundry_ledger_candidate_service_v1(jsonb,text,jsonb)'::regprocedure
  ) into v_def;

  if position('insert into admission.foundry_packages' in lower(v_def))=0
     or position('insert into admission.foundry_admission_cases' in lower(v_def))=0 then
    raise exception 'Staging does not preserve package + admission case custody.';
  end if;

  if position('insert into reality.entities' in lower(v_def))<>0
     or position('insert into ledger.onboarding_cases' in lower(v_def))<>0
     or position('insert into ledger.ledgers' in lower(v_def))<>0 then
    raise exception 'Foundry staging crosses into canonical Atlas mutation.';
  end if;

  select pg_get_functiondef(
    'atlas.foundry_admission_handoff_self_api_v1(uuid,text)'::regprocedure
  ) into v_def;

  if position('foundry_admission.execute' in lower(v_def))=0 then
    raise exception 'Foundry handoff does not require explicit admission responsibility.';
  end if;

  if position('insert into reality.entities' in lower(v_def))=0
     or position('insert into ledger.onboarding_cases' in lower(v_def))=0 then
    raise exception 'Foundry handoff does not terminate at canonical subject + onboarding.';
  end if;

  if position('insert into ledger.ledgers' in lower(v_def))<>0 then
    raise exception 'Foundry handoff improperly activates a Ledger.';
  end if;

  if position("'requested'" in lower(v_def))=0
     or position("'practitioner_onboarding'" in lower(v_def))=0 then
    raise exception 'Foundry handoff bypasses normal requested practitioner onboarding.';
  end if;

  select pg_get_functiondef(
    'atlas.reality_entity_reconciliation_propose_from_foundry_service_v1(uuid,uuid,jsonb,text)'::regprocedure
  ) into v_def;

  if position("v_type<>'merge'" in lower(v_def))=0
     or position("v_reason_code<>'identity_merge'" in lower(v_def))=0
     or position("'foundry'" in lower(v_def))=0
     or position("'canonicalmergeexecuted',false" in replace(lower(v_def),' ',''))=0 then
    raise exception 'Foundry merge proposal provenance/authority boundary is incomplete.';
  end if;

  select pg_get_constraintdef(con.oid)
  into v_source_check
  from pg_constraint con
  where con.conrelid='reality.entity_reconciliation_cases'::regclass
    and con.contype='c'
    and pg_get_constraintdef(con.oid) ilike '%proposal_source_kind%'
  order by con.oid desc
  limit 1;

  if v_source_check is null
     or v_source_check not ilike '%foundry%'
     or v_source_check not ilike '%shared_intelligence%'
     or v_source_check not ilike '%human%'
     or v_source_check not ilike '%system%' then
    raise exception 'Reality reconciliation source-kind contract is incomplete: %',v_source_check;
  end if;
end
$block$;

select
  'foundry_admission_bridge_v1' as contract,
  'pass' as result,
  'sealed Foundry package -> immutable staging -> governed identity/topology plan -> requested practitioner onboarding' as path,
  false as foundry_can_activate_ledger,
  false as service_role_can_execute_human_admission,
  false as foundry_can_execute_canonical_reality_merge;
