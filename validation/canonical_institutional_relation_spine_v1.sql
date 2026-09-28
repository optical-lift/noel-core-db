-- Contract validation: Atlas Canonical Institutional Relation Spine v1.
--
-- Read-only structural assertions. This validator does not create customer data,
-- establish institutional relationships, or mutate production truth.

do $block$
declare
  v_count integer;
  v_def text;
  v_key text;
begin
  if to_regprocedure('reality.resolve_institution_relation_v1(uuid,text,uuid,timestamptz)') is null then
    raise exception 'Institutional as_of relation resolver is missing.';
  end if;

  if to_regprocedure('reality.institution_for_position_v1(uuid,timestamptz)') is null
     or to_regprocedure('reality.institution_for_responsibility_v1(uuid,timestamptz)') is null then
    raise exception 'Institution scope resolvers are incomplete.';
  end if;

  if to_regprocedure('reality.require_institution_structure_authority_v1(uuid,uuid,text)') is null then
    raise exception 'Institution structure authority resolver is missing.';
  end if;

  if to_regprocedure('atlas.establish_institutional_standing_api_v1(uuid,uuid,text,text,jsonb,timestamptz)') is null
     or to_regprocedure('atlas.establish_institution_position_api_v1(uuid,text,text,jsonb,timestamptz)') is null
     or to_regprocedure('atlas.establish_institution_responsibility_api_v1(uuid,text,text,jsonb,timestamptz)') is null
     or to_regprocedure('atlas.establish_position_appointment_api_v1(uuid,uuid,jsonb,timestamptz)') is null
     or to_regprocedure('atlas.establish_position_responsibility_api_v1(uuid,uuid,jsonb,timestamptz)') is null
     or to_regprocedure('atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)') is null then
    raise exception 'Institutional structure API membrane is incomplete.';
  end if;

  select count(*)::integer into v_count
  from pg_trigger t
  join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where not t.tgisinternal
    and n.nspname='reality'
    and c.relname='entity_relationships'
    and t.tgname='reality_institution_relation_spine_guard_v1';

  if v_count<>1 then
    raise exception 'Expected exactly one institutional relationship guard trigger, found %.',v_count;
  end if;

  select count(*)::integer into v_count
  from pg_indexes
  where schemaname='reality'
    and indexname in (
      'reality_institutional_standing_open_key_idx',
      'reality_institution_position_open_key_idx',
      'reality_position_open_scope_idx',
      'reality_institution_responsibility_open_key_idx',
      'reality_responsibility_open_scope_idx',
      'reality_position_appointment_open_pair_idx',
      'reality_position_responsibility_open_pair_idx'
    );

  if v_count<>7 then
    raise exception 'Expected seven institutional relation uniqueness indexes, found %.',v_count;
  end if;

  v_key:=reality.normalize_institution_key_v1('Farm Steward');
  if v_key<>'farm_steward' then
    raise exception 'Institution-local key normalization is not deterministic: %.',v_key;
  end if;

  select count(*)::integer into v_count
  from atlas.workbench_operation_registry r
  where r.operation_key in (
    'establish.institutional_standing',
    'establish.institution_position',
    'establish.institution_responsibility',
    'establish.position_appointment',
    'establish.position_responsibility',
    'establish.institution_relation_end'
  )
    and r.route_class='ESTABLISH'
    and r.destination_membrane='reality.institutional_structure'
    and r.requires_destination_input
    and not r.requires_operation_contract
    and r.human_route_confirmation_required
    and r.registry_state='active';

  if v_count<>6 then
    raise exception 'Expected six active institutional Workbench ESTABLISH routes, found %.',v_count;
  end if;

  if not has_function_privilege(
    'authenticated',
    'atlas.establish_institutional_standing_api_v1(uuid,uuid,text,text,jsonb,timestamptz)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.establish_institution_position_api_v1(uuid,text,text,jsonb,timestamptz)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.establish_institution_responsibility_api_v1(uuid,text,text,jsonb,timestamptz)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.establish_position_appointment_api_v1(uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.establish_position_responsibility_api_v1(uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated institutional structure membrane is incomplete.';
  end if;

  if has_function_privilege(
    'service_role',
    'atlas.establish_position_appointment_api_v1(uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'atlas.establish_position_responsibility_api_v1(uuid,uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)',
    'EXECUTE'
  ) then
    raise exception 'service_role has human institutional establishment authority.';
  end if;

  if has_table_privilege('authenticated','reality.entity_relationships','INSERT')
     or has_table_privilege('authenticated','reality.entity_relationships','UPDATE') then
    raise exception 'Authenticated caller can bypass institutional structure commands with raw relationship writes.';
  end if;

  select pg_get_functiondef(
    'reality.resolve_institution_relation_v1(uuid,text,uuid,timestamptz)'::regprocedure
  ) into v_def;

  if position('valid_from' in v_def)=0
     or position('valid_until' in v_def)=0
     or position('relationship_state = ''established''' in v_def)=0 then
    raise exception 'Institutional relation resolver is not explicitly temporal.';
  end if;

  select pg_get_functiondef(
    'reality.require_institution_structure_authority_v1(uuid,uuid,text)'::regprocedure
  ) into v_def;

  if position('institution_structure_governance' in v_def)=0
     or position('resolve_responsibility_relation_v1' in v_def)=0
     or position('''entity''' in v_def)=0 then
    raise exception 'Institutional structure authority does not terminate in exact responsibility resolution.';
  end if;

  select pg_get_functiondef(
    'atlas.establish_position_appointment_api_v1(uuid,uuid,jsonb,timestamptz)'::regprocedure
  ) into v_def;

  if position('position_appointment.establish' in v_def)=0
     or position('auth.users' in lower(v_def))<>0
     or position('organization_membership' in lower(v_def))<>0
     or position('principal' in lower(v_def))<>0
     or position('insert into reality.responsibility_relations' in lower(v_def))<>0 then
    raise exception 'Position appointment improperly depends on access/legacy authority or mints execution authority.';
  end if;

  select pg_get_functiondef(
    'atlas.establish_position_responsibility_api_v1(uuid,uuid,jsonb,timestamptz)'::regprocedure
  ) into v_def;

  if position('position_responsibility.establish' in v_def)=0
     or position('institution_for_position_v1' in v_def)=0
     or position('institution_for_responsibility_v1' in v_def)=0
     or position('insert into reality.responsibility_relations' in lower(v_def))<>0 then
    raise exception 'Position Responsibility command fails same-institution or authority-separation law.';
  end if;

  select pg_get_functiondef(
    'reality.guard_institution_relation_spine_v1()'::regprocedure
  ) into v_def;

  if position('institutional_standing' in v_def)=0
     or position('institution_has_position' in v_def)=0
     or position('institution_has_responsibility' in v_def)=0
     or position('occupies_position' in v_def)=0
     or position('position_carries_responsibility' in v_def)=0
     or position('Institutional relationship identity and establishment evidence are immutable.' in v_def)=0
     or position('institution_relation.end' in v_def)=0 then
    raise exception 'Institutional relationship guard is missing a governed family or immutability boundary.';
  end if;

  select pg_get_functiondef(
    'atlas.end_institution_relation_api_v1(uuid,jsonb,timestamptz)'::regprocedure
  ) into v_def;

  if position('relationship_state' in v_def)=0
     or position('valid_until' in v_def)=0
     or position('institution_relation.end' in v_def)=0
     or position('retired' in lower(v_def))<>0 then
    raise exception 'Normal institutional ending does not preserve established history correctly.';
  end if;
end
$block$;

select
  'canonical_institutional_relation_spine_v1' as contract,
  'pass' as result,
  true as target_person_auth_optional,
  true as temporal_as_of_resolution,
  true as position_responsibility_separate_from_execution_authority,
  true as workbench_establish_routes_registered,
  false as principal_or_clock_consequence_created;
