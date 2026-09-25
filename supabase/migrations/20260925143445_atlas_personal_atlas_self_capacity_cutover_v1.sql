create or replace function atlas.personal_atlas_compatibility_principal_id_v1(
  p_person_entity_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_ids uuid[];
begin
  if p_person_entity_id is null then
    return null;
  end if;

  perform reality.assert_person_entity_v1(p_person_entity_id);

  if not exists(
    select 1
    from personal.atlases pa
    where pa.person_entity_id=p_person_entity_id
      and pa.atlas_state='active'
      and pa.native
  ) then
    return null;
  end if;

  select array_agg(p.id order by p.id)
  into v_ids
  from atlas.principals p
  where p.person_id=p_person_entity_id
    and p.status='active';

  if coalesce(cardinality(v_ids),0)<>1 then
    return null;
  end if;

  return v_ids[1];
end
$function$;

revoke all on function atlas.personal_atlas_compatibility_principal_id_v1(uuid)
  from public,anon,authenticated;

create or replace function atlas.personal_capacity_policies_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_policies jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal capacity compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',p.id,
        'stableKey',p.stable_key,
        'name',p.name,
        'weekdays',to_jsonb(p.weekdays),
        'localStart',to_char(p.local_start,'HH24:MI'),
        'localEnd',to_char(p.local_end,'HH24:MI'),
        'defaultDiscretionaryMinutes',p.default_discretionary_minutes,
        'maximumPlannedMinutes',p.maximum_planned_minutes,
        'effectiveFrom',p.effective_from,
        'effectiveThrough',p.effective_through,
        'active',p.active,
        'metadata',p.metadata,
        'createdAt',p.created_at,
        'updatedAt',p.updated_at
      )
      order by p.effective_from desc,p.created_at desc
    ),
    '[]'::jsonb
  )
  into v_policies
  from atlas.principal_capacity_policies p
  where p.principal_id=v_compat_principal_id
    and p.active;

  return jsonb_build_object(
    'contractVersion','personal_capacity_policies_self_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'policies',v_policies,
    'capacityToday',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,current_date
    ),
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;

revoke all on function atlas.personal_capacity_policies_self_api_v1()
  from public,anon;
grant execute on function atlas.personal_capacity_policies_self_api_v1()
  to authenticated,service_role;

create or replace function atlas.personal_set_capacity_policy_self_api_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_stable_key text;
  v_name text;
  v_weekdays smallint[];
  v_local_start time;
  v_local_end time;
  v_default integer;
  v_maximum integer;
  v_window_minutes integer;
  v_from date;
  v_through date;
  v_metadata jsonb;
  v_row atlas.principal_capacity_policies%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal capacity compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Capacity policy input must be an object.' using errcode='22023';
  end if;

  v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
  v_name:=nullif(trim(p_input->>'name'),'');
  if v_stable_key is null or v_name is null then
    raise exception 'stableKey and name are required.' using errcode='22023';
  end if;

  if jsonb_typeof(p_input->'weekdays')<>'array' then
    raise exception 'weekdays must be an array.' using errcode='22023';
  end if;

  select coalesce(array_agg(value::smallint order by ord),array[]::smallint[])
  into v_weekdays
  from jsonb_array_elements_text(p_input->'weekdays')
       with ordinality e(value,ord);

  if cardinality(v_weekdays)=0 then
    raise exception 'At least one weekday is required.' using errcode='22023';
  end if;

  if exists(select 1 from unnest(v_weekdays) d where d<0 or d>6) then
    raise exception 'weekdays values must be integers from 0 through 6.'
      using errcode='22023';
  end if;

  if (
    select count(*)<>count(distinct d)
    from unnest(v_weekdays) d
  ) then
    raise exception 'weekdays must not contain duplicates.' using errcode='22023';
  end if;

  if nullif(p_input->>'localStart','') is null
     or nullif(p_input->>'localEnd','') is null then
    raise exception 'localStart and localEnd are required.' using errcode='22023';
  end if;

  begin
    v_local_start:=(p_input->>'localStart')::time;
    v_local_end:=(p_input->>'localEnd')::time;
  exception when others then
    raise exception 'localStart and localEnd must be valid local times.'
      using errcode='22023';
  end;

  if v_local_end<=v_local_start then
    raise exception 'localEnd must be later than localStart on the same local day.'
      using errcode='22023';
  end if;

  v_window_minutes:=round(
    extract(epoch from (v_local_end-v_local_start))/60.0
  )::integer;

  if nullif(p_input->>'defaultDiscretionaryMinutes','') is null
     or nullif(p_input->>'maximumPlannedMinutes','') is null then
    raise exception 'defaultDiscretionaryMinutes and maximumPlannedMinutes are required.'
      using errcode='22023';
  end if;

  begin
    v_default:=(p_input->>'defaultDiscretionaryMinutes')::integer;
    v_maximum:=(p_input->>'maximumPlannedMinutes')::integer;
  exception when others then
    raise exception 'Capacity minute values must be integers.' using errcode='22023';
  end;

  if v_default<0 or v_maximum<0 then
    raise exception 'Capacity minute values cannot be negative.' using errcode='22023';
  end if;

  if v_default>v_maximum then
    raise exception 'defaultDiscretionaryMinutes cannot exceed maximumPlannedMinutes.'
      using errcode='22023';
  end if;

  if v_maximum>v_window_minutes then
    raise exception 'maximumPlannedMinutes cannot exceed the local capacity window itself.'
      using errcode='22023';
  end if;

  if nullif(p_input->>'effectiveFrom','') is null then
    raise exception 'effectiveFrom is required.' using errcode='22023';
  end if;

  begin
    v_from:=(p_input->>'effectiveFrom')::date;
    v_through:=case
      when nullif(p_input->>'effectiveThrough','') is null then null
      else (p_input->>'effectiveThrough')::date
    end;
  exception when others then
    raise exception 'Capacity policy dates must be valid dates.' using errcode='22023';
  end;

  if v_through is not null and v_through<v_from then
    raise exception 'effectiveThrough cannot be earlier than effectiveFrom.'
      using errcode='22023';
  end if;

  v_metadata:=case
    when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata'
    else '{}'::jsonb
  end;

  insert into atlas.principal_capacity_policies(
    principal_id,stable_key,name,weekdays,local_start,local_end,
    default_discretionary_minutes,maximum_planned_minutes,
    effective_from,effective_through,active,metadata
  ) values (
    v_compat_principal_id,v_stable_key,v_name,v_weekdays,v_local_start,v_local_end,
    v_default,v_maximum,v_from,v_through,true,
    v_metadata||jsonb_build_object(
      'source','personal_set_capacity_policy_self_api_v1',
      'personEntityId',v_person_id,
      'personalAtlasId',v_personal_atlas_id,
      'legacyPrincipalStorageOnly',true
    )
  )
  on conflict(principal_id,stable_key,effective_from) do update set
    name=excluded.name,
    weekdays=excluded.weekdays,
    local_start=excluded.local_start,
    local_end=excluded.local_end,
    default_discretionary_minutes=excluded.default_discretionary_minutes,
    maximum_planned_minutes=excluded.maximum_planned_minutes,
    effective_through=excluded.effective_through,
    active=true,
    metadata=atlas.principal_capacity_policies.metadata||excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','personal_capacity_policy_authoring_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'policy',to_jsonb(v_row)-'principal_id',
    'capacityOnEffectiveFrom',atlas.principal_capacity_day_state_v1(
      v_compat_principal_id,v_from
    ),
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;

revoke all on function atlas.personal_set_capacity_policy_self_api_v1(jsonb)
  from public,anon;
grant execute on function atlas.personal_set_capacity_policy_self_api_v1(jsonb)
  to authenticated;

create or replace function atlas.personal_upsert_household_rhythm_local_self_api_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_household_id uuid;
  v_timezone text;
  v_stable_key text;
  v_area text;
  v_title text;
  v_cadence text;
  v_expected integer;
  v_protection text;
  v_floor smallint;
  v_interruptibility text;
  v_consequence text;
  v_reason text;
  v_start_local timestamp without time zone;
  v_end_local timestamp without time zone;
  v_start timestamptz;
  v_end timestamptz;
  v_active boolean;
  v_blocks_capacity boolean;
  v_metadata jsonb;
  v_row atlas.household_rhythms%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id
  into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal household compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  select p.active_household_id,h.timezone
  into v_household_id,v_timezone
  from atlas.principals p
  join atlas.households h
    on h.id=p.active_household_id
   and h.status='active'
  where p.id=v_compat_principal_id
    and p.status='active';

  if v_household_id is null or v_timezone is null then
    raise exception 'Active household required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Household rhythm input must be an object.' using errcode='22023';
  end if;

  v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
  v_area:=nullif(trim(p_input->>'area'),'');
  v_title:=nullif(trim(p_input->>'title'),'');
  v_cadence:=nullif(trim(p_input->>'cadenceRule'),'');
  v_protection:=coalesce(nullif(trim(p_input->>'protectionLevel'),''),'protected');
  v_interruptibility:=coalesce(
    nullif(trim(p_input->>'interruptibility'),''),
    'interruptible'
  );
  v_consequence:=nullif(trim(p_input->>'consequence'),'');
  v_reason:=coalesce(
    nullif(trim(p_input->>'reasonForFloor'),''),
    'Protected household rhythm.'
  );

  begin
    v_expected:=(p_input->>'expectedMinutes')::integer;
    v_floor:=coalesce(nullif(p_input->>'floorClass','')::smallint,3);
  exception when others then
    raise exception 'expectedMinutes and floorClass must be integers.'
      using errcode='22023';
  end;

  if v_stable_key is null or v_area is null or v_title is null
     or v_expected is null or v_expected<=0 then
    raise exception 'stableKey, area, title, and positive expectedMinutes are required.'
      using errcode='22023';
  end if;

  if v_cadence not in ('once','daily','weekly','every_5_weeks') then
    raise exception 'Unsupported household cadence.' using errcode='22023';
  end if;

  if v_protection not in ('critical','protected','standard','optional') then
    raise exception 'Unsupported household protection level.' using errcode='22023';
  end if;

  if v_floor<1 or v_floor>7 then
    raise exception 'floorClass must be between 1 and 7.' using errcode='22023';
  end if;

  if v_interruptibility not in (
    'interruptible','low_interruptibility','should_not_interrupt'
  ) then
    raise exception 'Unsupported household interruptibility.'
      using errcode='22023';
  end if;

  if v_consequence is null then
    raise exception 'consequence is required.' using errcode='22023';
  end if;

  if nullif(trim(p_input->>'nextWindowStartLocal'),'') is null
     or nullif(trim(p_input->>'nextWindowEndLocal'),'') is null then
    raise exception 'Local household window start and end are required.'
      using errcode='22023';
  end if;

  begin
    v_start_local:=(p_input->>'nextWindowStartLocal')::timestamp;
    v_end_local:=(p_input->>'nextWindowEndLocal')::timestamp;
  exception when others then
    raise exception 'Household window must use valid local date/time values.'
      using errcode='22023';
  end;

  if v_end_local<=v_start_local then
    raise exception 'Household window end must be after its start.'
      using errcode='22023';
  end if;

  v_start:=v_start_local at time zone v_timezone;
  v_end:=v_end_local at time zone v_timezone;
  v_active:=coalesce((p_input->>'active')::boolean,true);
  v_blocks_capacity:=coalesce((p_input->>'blocksCapacity')::boolean,true);
  v_metadata:=coalesce(
    case
      when jsonb_typeof(p_input->'metadata')='object' then p_input->'metadata'
    end,
    '{}'::jsonb
  )||jsonb_build_object(
    'source','personal_upsert_household_rhythm_local_self_api_v1',
    'authoringTimezone',v_timezone,
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'legacyPrincipalStorageOnly',true,
    'legacyPrincipalRequiredCompatibility',true
  );

  insert into atlas.household_rhythms(
    household_id,stable_key,area,title,cadence_rule,
    next_window_start,next_window_end,expected_minutes,
    protection_level,floor_class,interruptibility,
    principal_required,consequence,reason_for_floor,
    active,blocks_capacity,metadata
  ) values (
    v_household_id,v_stable_key,v_area,v_title,v_cadence,
    v_start,v_end,v_expected,
    v_protection,v_floor,v_interruptibility,
    true,v_consequence,v_reason,
    v_active,v_blocks_capacity,v_metadata
  )
  on conflict(household_id,stable_key) do update set
    area=excluded.area,
    title=excluded.title,
    cadence_rule=excluded.cadence_rule,
    next_window_start=excluded.next_window_start,
    next_window_end=excluded.next_window_end,
    expected_minutes=excluded.expected_minutes,
    protection_level=excluded.protection_level,
    floor_class=excluded.floor_class,
    interruptibility=excluded.interruptibility,
    principal_required=true,
    consequence=excluded.consequence,
    reason_for_floor=excluded.reason_for_floor,
    active=excluded.active,
    blocks_capacity=excluded.blocks_capacity,
    metadata=atlas.household_rhythms.metadata||excluded.metadata
  returning * into v_row;

  return jsonb_build_object(
    'contractVersion','personal_household_rhythm_authoring_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'rhythm',to_jsonb(v_row)-'principal_required',
    'candidate',(
      select to_jsonb(c)
      from atlas.principal_clock_candidates_v1 c
      where c.source_type='household_rhythm'
        and c.source_id=v_row.id
    ),
    'authoringTimezone',v_timezone,
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'legacyPrincipalRequiredFieldIsStorageCompatibility',true,
      'principalDoesNotEstablishIdentity',true,
      'organizationRoleDoesNotEstablishAccess',true
    )
  );
end
$function$;

revoke all on function atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)
  from public,anon;
grant execute on function atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.personal_capacity_policies_self_api_v1()',
  'app_endpoint','verified','active',
  true,true,true,1,0,
  jsonb_build_object(
    'purpose','Read signed-in Person capacity policy through Reality Person and native Personal Atlas.',
    'storageCompatibility','atlas.principal_capacity_policies',
    'authorityBoundary','No organization role or Principal identity establishes access.'
  ),
  now(),false
),
(
  'atlas.personal_set_capacity_policy_self_api_v1(jsonb)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Author signed-in Person capacity policy through Reality Person and native Personal Atlas.',
    'storageCompatibility','atlas.principal_capacity_policies',
    'authorityBoundary','Self-authored personal state; no institutional responsibility or owner role required.'
  ),
  now(),false
),
(
  'atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)',
  'app_endpoint','verified','active',
  true,true,false,1,0,
  jsonb_build_object(
    'purpose','Author the signed-in Person household rhythm through Reality Person and native Personal Atlas.',
    'storageCompatibility','atlas.household_rhythms via the one active legacy Principal household carrier',
    'authorityBoundary','Household self-governance is personal state, not organization-owner authority.'
  ),
  now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

comment on function atlas.personal_atlas_compatibility_principal_id_v1(uuid) is
  'Internal compatibility bridge from canonical Reality Person + active native Personal Atlas to exactly one active legacy Principal storage carrier. The Principal does not establish identity, access, or authority.';

comment on function atlas.personal_capacity_policies_self_api_v1() is
  'Read self-authored personal capacity through Reality Person + Personal Atlas while legacy Principal tables remain compatibility storage.';

comment on function atlas.personal_set_capacity_policy_self_api_v1(jsonb) is
  'Write self-authored personal capacity policy through Reality Person + Personal Atlas. No organization role, Ledger Seat, or institutional responsibility is required.';

comment on function atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb) is
  'Write self-authored household rhythm through Reality Person + Personal Atlas. Legacy Principal household columns are storage compatibility only.';

do $validation$
declare
  v_lex uuid;
  v_carrier uuid;
begin
  select id into v_lex
  from reality.entities
  where stable_key='lex'
    and entity_kind='person'
    and identity_state='canonical';

  v_carrier:=atlas.personal_atlas_compatibility_principal_id_v1(v_lex);

  if v_carrier is distinct from 'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid then
    raise exception 'Lex Personal Atlas did not resolve the expected compatibility Principal carrier.';
  end if;

  if pg_get_functiondef(
       'atlas.personal_capacity_policies_self_api_v1()'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.personal_capacity_policies_self_api_v1()'::regprocedure
     ) ilike '%organization_memberships%'
  then
    raise exception 'Personal capacity read retained legacy authority identity.';
  end if;

  if pg_get_functiondef(
       'atlas.personal_set_capacity_policy_self_api_v1(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.personal_set_capacity_policy_self_api_v1(jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.personal_set_capacity_policy_self_api_v1(jsonb)'::regprocedure
     ) ilike '%is_farm_owner%'
  then
    raise exception 'Personal capacity writer retained legacy authority identity.';
  end if;

  if pg_get_functiondef(
       'atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.personal_upsert_household_rhythm_local_self_api_v1(jsonb)'::regprocedure
     ) ilike '%is_farm_owner%'
  then
    raise exception 'Personal household writer retained legacy authority identity.';
  end if;
end
$validation$;
