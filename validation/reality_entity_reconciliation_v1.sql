-- Contract validation: Reality Entity Reconciliation v1.
--
-- Read-only assertions. This file does not open, preview, confirm, or mutate a
-- reconciliation case.

do $block$
declare
  v_operator uuid;
  v_def text;
  v_count integer;
begin
  if to_regclass('reality.entity_reconciliation_cases') is null then
    raise exception 'Reality reconciliation case table is missing.';
  end if;

  if to_regclass('reality.entity_supersessions') is null then
    raise exception 'Reality entity supersession table is missing.';
  end if;

  if to_regprocedure('reality.resolve_canonical_entity_v1(uuid)') is null then
    raise exception 'Canonical Reality Entity resolver is missing.';
  end if;

  select count(*)::integer into v_count
  from pg_constraint con
  join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f'
    and con.confrelid='reality.entities'::regclass
    and n.nspname='reality'
    and c.relname='entity_supersessions';

  if v_count<>3 then
    raise exception
      'Expected three Reality Entity foreign keys on entity_supersessions, found %.',
      v_count;
  end if;

  select id into v_operator
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  if v_operator is null then
    raise exception 'Canonical Reality reconciliation operator is unavailable.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,
    'reality_identity_reconciliation',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  ) is null then
    raise exception 'Explicit canonical merge responsibility is unavailable.';
  end if;

  if reality.resolve_responsibility_relation_v1(
    v_operator,
    'reality_identity_adjudication',
    'canonical_merge.execute',
    'domain',
    null,
    'reality.identity_resolution',
    '{}'::jsonb
  ) is not null then
    raise exception 'Identity evidence review improperly grants canonical merge authority.';
  end if;

  if not has_function_privilege(
    'authenticated',
    'atlas.reality_entity_reconciliation_propose_self_api_v1(jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.reality_entity_reconciliation_preview_self_api_v1(uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated reconciliation membrane is incomplete.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'service_role can execute canonical merge confirmation.';
  end if;

  if not has_function_privilege(
    'service_role',
    'atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(uuid,uuid,jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'Evidence-side proposal membrane is unavailable to service_role.';
  end if;

  if has_table_privilege(
    'authenticated','reality.entity_supersessions','INSERT'
  ) or has_table_privilege(
    'service_role','reality.entity_supersessions','INSERT'
  ) then
    raise exception 'Raw supersession insertion is exposed.';
  end if;

  select pg_get_functiondef(
    'atlas.reality_entity_reconciliation_confirm_self_api_v1(uuid,text)'::regprocedure
  ) into v_def;

  if position('canonical_merge.execute' in v_def)=0
     or position('execute_entity_reconciliation_internal_v1' in v_def)=0
     or position('local_intel' in lower(v_def))<>0 then
    raise exception 'Confirmation membrane does not terminate in explicit Reality authority.';
  end if;

  select pg_get_functiondef(
    'atlas.reality_entity_reconciliation_propose_from_evidence_service_v1(uuid,uuid,jsonb,text)'::regprocedure
  ) into v_def;

  if position('execute_entity_reconciliation_internal_v1' in v_def)<>0
     or position('canonical_merge.execute' in v_def)<>0 then
    raise exception 'Evidence proposal membrane contains canonical merge execution authority.';
  end if;

  select pg_get_functiondef(
    'reality.execute_entity_reconciliation_internal_v1(uuid,uuid,uuid,text)'::regprocedure
  ) into v_def;

  if position('pg_catalog.pg_constraint' in v_def)=0
     or position('identity_state=''retired''' in v_def)=0
     or position('compatibility.legacy_bindings' in v_def)=0
     or position('entity_supersessions' in v_def)=0 then
    raise exception 'Atomic reconciliation executor is missing a required continuity step.';
  end if;
end
$block$;

select
  'reality_entity_reconciliation_v1' as contract,
  'pass' as result,
  true as evidence_may_propose,
  false as evidence_may_confirm,
  true as superseded_identity_retained;
