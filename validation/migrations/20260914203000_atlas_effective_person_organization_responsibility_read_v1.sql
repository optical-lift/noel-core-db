begin;

-- The authority and exact resolver exist and remain internal.
do $postconditions$
begin
  if to_regprocedure('atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)') is null then
    raise exception 'effective current durable-responsibility authority is missing';
  end if;

  if to_regprocedure('atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)') is null then
    raise exception 'exact current durable-responsibility resolver is missing';
  end if;

  if has_function_privilege('anon','atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)','EXECUTE')
     or has_function_privilege('authenticated','atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)','EXECUTE') then
    raise exception 'effective durable-responsibility authority widened browser execution';
  end if;

  if has_function_privilege('anon','atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)','EXECUTE')
     or has_function_privilege('authenticated','atlas.resolve_person_organization_responsibility_current_v1(uuid,uuid,uuid,text,text)','EXECUTE') then
    raise exception 'effective durable-responsibility resolver widened browser execution';
  end if;

  if not exists (
    select 1
    from atlas.architecture_truth_authorities a
    where a.authority_key='person_organization_current_durable_responsibility'
      and a.authority_owner='atlas.effective_person_organization_responsibilities_current_v1(uuid,uuid)'
      and a.authority_status='canonical'
  ) then
    raise exception 'architecture truth authority catalog entry is missing or noncanonical';
  end if;
end;
$postconditions$;

-- Synthetic current institutional reality. The organization membership compatibility
-- trigger creates/binds the canonical Person for this validation auth identity.
insert into auth.users(id,email)
values ('81000000-0000-0000-0000-000000000001'::uuid,'effective-responsibility-validation@example.invalid');

insert into atlas.organizations(id,stable_key,name,status)
values (
  '82000000-0000-0000-0000-000000000001'::uuid,
  'effective_responsibility_validation_org',
  'Effective Responsibility Validation Org',
  'active'
);

insert into atlas.identity_subjects(id,organization_id,state,creation_basis)
values (
  '83000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  'active',
  jsonb_build_object('validation',true)
);

insert into atlas.organization_units(id,organization_id,stable_key,name,unit_kind,status)
values
  (
    '84000000-0000-0000-0000-000000000001'::uuid,
    '82000000-0000-0000-0000-000000000001'::uuid,
    'operations',
    'Operations',
    'operating_unit',
    'active'
  ),
  (
    '84000000-0000-0000-0000-000000000002'::uuid,
    '82000000-0000-0000-0000-000000000001'::uuid,
    'other_operations',
    'Other Operations',
    'operating_unit',
    'active'
  );

insert into atlas.organization_memberships(
  id,organization_id,user_id,role,active,identity_subject_id
) values (
  '85000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  '81000000-0000-0000-0000-000000000001'::uuid,
  'member',
  true,
  '83000000-0000-0000-0000-000000000001'::uuid
);

insert into atlas.organization_positions(
  id,organization_id,organization_unit_id,stable_key,display_title,position_kind,status
) values (
  '86000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  '84000000-0000-0000-0000-000000000001'::uuid,
  'validation_steward',
  'Validation Steward',
  'operations',
  'active'
);

insert into atlas.organization_responsibilities(
  id,organization_id,stable_key,name,responsibility_kind,status
) values (
  '87000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  'validation_stewardship',
  'Validation stewardship',
  'stewardship',
  'active'
);

insert into atlas.organization_position_responsibilities(
  position_id,responsibility_id,relationship_kind
) values (
  '86000000-0000-0000-0000-000000000001'::uuid,
  '87000000-0000-0000-0000-000000000001'::uuid,
  'accountable'
);

insert into atlas.organization_responsibility_scopes(
  id,organization_id,responsibility_id,scope_kind,scope_id,relation_kind
) values (
  '88000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  '87000000-0000-0000-0000-000000000001'::uuid,
  'organization_unit',
  '84000000-0000-0000-0000-000000000001',
  'stewards'
);

insert into atlas.organization_position_appointments(
  id,organization_id,position_id,identity_subject_id,organization_membership_id,
  appointment_kind,status,begins_at
) values (
  '89000000-0000-0000-0000-000000000001'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  '86000000-0000-0000-0000-000000000001'::uuid,
  '83000000-0000-0000-0000-000000000001'::uuid,
  '85000000-0000-0000-0000-000000000001'::uuid,
  'primary',
  'active',
  now()-interval '1 day'
);

do $behavior$
declare
  v_person_id uuid;
  v_count integer;
  v_result jsonb;
begin
  select m.person_id into strict v_person_id
  from atlas.organization_memberships m
  where m.id='85000000-0000-0000-0000-000000000001'::uuid;

  if v_person_id is null then
    raise exception 'validation Organization Membership did not bind to canonical Person';
  end if;

  select count(*)::integer into v_count
  from atlas.effective_person_organization_responsibilities_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid
  ) x
  where x.responsibility_id='87000000-0000-0000-0000-000000000001'::uuid
    and x.scope_kind='organization_unit'
    and x.scope_id='84000000-0000-0000-0000-000000000001'
    and x.resolution_state='established_current';

  if v_count<>1 then
    raise exception 'expected exactly one established current durable responsibility; found %',v_count;
  end if;

  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    'organization_unit',
    '84000000-0000-0000-0000-000000000001'
  );

  if v_result->>'state'<>'established_current' then
    raise exception 'exact resolver failed established_current proof: %',v_result;
  end if;

  -- A different but valid active Organization Unit is resolved reality; this
  -- responsibility simply does not currently cover it.
  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    'organization_unit',
    '84000000-0000-0000-0000-000000000002'
  );

  if v_result->>'state'<>'established_not_current'
     or v_result->>'reason'<>'responsibility_not_current_for_requested_scope' then
    raise exception 'valid scope mismatch did not resolve as established_not_current: %',v_result;
  end if;

  -- Unsupported scope identity cannot be treated as a negative responsibility fact.
  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    'farm',
    '84000000-0000-0000-0000-000000000001'
  );

  if v_result->>'state'<>'indeterminate'
     or v_result->>'reason'<>'requested_scope_kind_not_supported' then
    raise exception 'unsupported requested Scope kind did not fail closed: %',v_result;
  end if;

  -- A UUID-shaped but nonexistent Organization Unit is unresolved, not a negative fact.
  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    'organization_unit',
    '84000000-0000-0000-0000-000000000099'
  );

  if v_result->>'state'<>'indeterminate'
     or v_result->>'reason'<>'requested_scope_unresolved' then
    raise exception 'dangling requested Organization Unit Scope did not fail closed: %',v_result;
  end if;
end;
$behavior$;

-- Replace the valid definition with a dangling Scope row. The canonical rowset
-- preserves the unresolved evidence as indeterminate and the exact unscoped
-- resolver must not silently promote it into responsibility truth.
delete from atlas.organization_responsibility_scopes
where id='88000000-0000-0000-0000-000000000001'::uuid;

insert into atlas.organization_responsibility_scopes(
  id,organization_id,responsibility_id,scope_kind,scope_id,relation_kind
) values (
  '88000000-0000-0000-0000-000000000099'::uuid,
  '82000000-0000-0000-0000-000000000001'::uuid,
  '87000000-0000-0000-0000-000000000001'::uuid,
  'organization_unit',
  '84000000-0000-0000-0000-000000000099',
  'stewards'
);

do $dangling_scope$
declare
  v_person_id uuid;
  v_count integer;
  v_result jsonb;
begin
  select m.person_id into strict v_person_id
  from atlas.organization_memberships m
  where m.id='85000000-0000-0000-0000-000000000001'::uuid;

  select count(*)::integer into v_count
  from atlas.effective_person_organization_responsibilities_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid
  ) x
  where x.responsibility_id='87000000-0000-0000-0000-000000000001'::uuid
    and x.scope_link_id='88000000-0000-0000-0000-000000000099'::uuid
    and x.resolution_state='indeterminate'
    and x.evidence->>'scopeResolution'='organization_unit_unresolved';

  if v_count<>1 then
    raise exception 'dangling Scope evidence was not preserved as one indeterminate row; found %',v_count;
  end if;

  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    null,
    null
  );

  if v_result->>'state'<>'indeterminate'
     or v_result->>'reason'<>'current_responsibility_scope_unresolved' then
    raise exception 'dangling current Scope did not become indeterminate: %',v_result;
  end if;
end;
$dangling_scope$;

-- With no Scope evidence at all, bounded responsibility remains indeterminate for
-- a different reason: the required governed target is missing rather than dangling.
delete from atlas.organization_responsibility_scopes
where id='88000000-0000-0000-0000-000000000099'::uuid;

do $missing_scope$
declare
  v_person_id uuid;
  v_result jsonb;
begin
  select m.person_id into strict v_person_id
  from atlas.organization_memberships m
  where m.id='85000000-0000-0000-0000-000000000001'::uuid;

  v_result:=atlas.resolve_person_organization_responsibility_current_v1(
    v_person_id,
    '82000000-0000-0000-0000-000000000001'::uuid,
    '87000000-0000-0000-0000-000000000001'::uuid,
    null,
    null
  );

  if v_result->>'state'<>'indeterminate'
     or v_result->>'reason'<>'current_responsibility_scope_missing' then
    raise exception 'missing bounded Scope did not become indeterminate: %',v_result;
  end if;
end;
$missing_scope$;

rollback;
