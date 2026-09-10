-- Add user-confirmed room/space Cleaning expectations.
-- These are durable requirements attached to canonical household_spaces, not current-condition observations
-- and not the generic five-zone household-care policy.

create table if not exists atlas.household_space_cleaning_requirements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  space_id uuid not null references atlas.household_spaces(id) on delete cascade,
  stable_key text not null,
  action_title text not null,
  cadence_rule text not null,
  expected_minutes integer not null check (expected_minutes > 0),
  season text not null default 'year_round' check (season in ('year_round','winter','spring','summer','fall','custom')),
  rhythm_id uuid references atlas.household_rhythms(id) on delete set null,
  notes text,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(space_id,stable_key)
);

alter table atlas.household_space_cleaning_requirements enable row level security;
revoke all on atlas.household_space_cleaning_requirements from public,anon,authenticated;

create or replace function atlas.upsert_personal_cleaning_space_requirement_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_space_id uuid;
  v_requirement_id uuid;
  v_request_key text;
  v_action text;
  v_cadence text;
  v_expected integer;
  v_season text;
  v_notes text;
  v_space atlas.household_spaces%rowtype;
  v_requirement atlas.household_space_cleaning_requirements%rowtype;
  v_rhythm jsonb;
  v_rhythm_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Space Cleaning requirement input must be an object.' using errcode='22023'; end if;

  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_space_id:=nullif(trim(p_input->>'spaceId'),'')::uuid;
  v_requirement_id:=nullif(trim(p_input->>'requirementId'),'')::uuid;
  v_request_key:=nullif(trim(p_input->>'requestKey'),'');
  v_action:=nullif(trim(p_input->>'actionTitle'),'');
  v_cadence:=nullif(trim(p_input->>'cadenceRule'),'');
  v_expected:=coalesce(nullif(p_input->>'expectedMinutes','')::integer,15);
  v_season:=coalesce(nullif(trim(p_input->>'season'),''),'year_round');
  v_notes:=nullif(trim(p_input->>'notes'),'');

  if v_space_id is null or v_action is null or v_cadence is null then
    raise exception 'spaceId, actionTitle, and cadenceRule are required.' using errcode='22023';
  end if;
  if v_expected<=0 then raise exception 'expectedMinutes must be positive.' using errcode='22023'; end if;
  if v_season not in ('year_round','winter','spring','summer','fall','custom') then raise exception 'Unsupported season.' using errcode='22023'; end if;

  select * into v_space
  from atlas.household_spaces s
  where s.id=v_space_id and s.household_id=v_household_id and s.active;
  if v_space.id is null then raise exception 'Active household space required.' using errcode='22023'; end if;

  if v_requirement_id is not null then
    select * into v_requirement
    from atlas.household_space_cleaning_requirements r
    where r.id=v_requirement_id and r.household_id=v_household_id and r.space_id=v_space_id
    for update;
    if v_requirement.id is null then raise exception 'Space Cleaning requirement not found.' using errcode='22023'; end if;
    v_request_key:=v_requirement.stable_key;
  elsif v_request_key is null then
    raise exception 'requestKey required for a new Space Cleaning requirement.' using errcode='22023';
  end if;

  -- Persist the semantic recurring obligation first. Exact clock windows remain unknown until Clock scheduling.
  v_rhythm:=atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
    'stableKey','space-care:'||v_space_id::text||':'||coalesce(v_requirement_id::text,v_request_key),
    'area','cleaning',
    'title',v_action||' — '||v_space.name,
    'cadenceRule',v_cadence,
    'expectedMinutes',v_expected,
    'protectionLevel','protected',
    'floorClass',3,
    'interruptibility','interruptible',
    'principalRequired',true,
    'blocksCapacity',true,
    'consequence','A user-confirmed household space has a recurring Cleaning requirement.',
    'reasonForFloor','Room-level Cleaning expectation established through the Cleaning kernel.',
    'metadata',jsonb_strip_nulls(jsonb_build_object(
      'source','personal_cleaning_space_requirement_v1',
      'householdSpaceId',v_space_id,
      'season',v_season,
      'semanticCadence',true,
      'clockWindowEstablished',false
    ))
  ));
  v_rhythm_id:=nullif(v_rhythm#>>'{rhythm,id}','')::uuid;

  if v_requirement_id is not null then
    update atlas.household_space_cleaning_requirements
    set action_title=v_action,
        cadence_rule=v_cadence,
        expected_minutes=v_expected,
        season=v_season,
        rhythm_id=v_rhythm_id,
        notes=v_notes,
        active=true,
        metadata=metadata||jsonb_build_object('source','personal_cleaning_space_requirement_v1'),
        updated_at=now()
    where id=v_requirement_id
    returning * into v_requirement;
  else
    insert into atlas.household_space_cleaning_requirements(
      household_id,space_id,stable_key,action_title,cadence_rule,expected_minutes,season,rhythm_id,notes,active,metadata
    ) values(
      v_household_id,v_space_id,'personal-cleaning:'||v_request_key,v_action,v_cadence,v_expected,v_season,v_rhythm_id,v_notes,true,
      jsonb_build_object('source','personal_cleaning_space_requirement_v1')
    )
    on conflict(space_id,stable_key) do update set
      action_title=excluded.action_title,
      cadence_rule=excluded.cadence_rule,
      expected_minutes=excluded.expected_minutes,
      season=excluded.season,
      rhythm_id=excluded.rhythm_id,
      notes=excluded.notes,
      active=true,
      metadata=atlas.household_space_cleaning_requirements.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_requirement;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_space_requirement_v1',
    'space',jsonb_build_object('id',v_space.id,'name',v_space.name,'spaceType',v_space.space_type),
    'requirement',jsonb_build_object(
      'id',v_requirement.id,
      'actionTitle',v_requirement.action_title,
      'cadenceRule',v_requirement.cadence_rule,
      'expectedMinutes',v_requirement.expected_minutes,
      'season',v_requirement.season,
      'notes',v_requirement.notes,
      'rhythmId',v_requirement.rhythm_id
    ),
    'rhythm',v_rhythm
  );
end;
$function$;

-- Extend the Cleaning inventory read so the UI sees requirements grouped under the spaces they belong to.
create or replace function atlas.personal_cleaning_inventory_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_spaces jsonb := '[]'::jsonb;
  v_objects jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'stableKey',s.stable_key,
    'name',s.name,
    'spaceType',s.space_type,
    'functionalTags',to_jsonb(s.functional_tags),
    'floorLevel',s.floor_level,
    'careRelevant',s.care_relevant,
    'confidence',s.confidence,
    'requirements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'actionTitle',r.action_title,
        'cadenceRule',r.cadence_rule,
        'expectedMinutes',r.expected_minutes,
        'season',r.season,
        'notes',r.notes,
        'rhythmId',r.rhythm_id,
        'active',r.active
      ) order by r.created_at,r.id)
      from atlas.household_space_cleaning_requirements r
      where r.space_id=s.id and r.household_id=v_household_id and r.active
    ),'[]'::jsonb)
  ) order by s.created_at,s.id),'[]'::jsonb)
  into v_spaces
  from atlas.household_spaces s
  where s.household_id=v_household_id and s.active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,
    'stableKey',o.stable_key,
    'name',o.name,
    'objectType',o.object_type,
    'spaceId',o.space_id,
    'spaceName',s.name,
    'confidence',o.confidence,
    'requirement',case when r.id is null then null else jsonb_build_object(
      'id',r.id,
      'actionTitle',r.action_title,
      'cadenceRule',r.cadence_rule,
      'expectedMinutes',r.expected_minutes,
      'season',r.season,
      'notes',r.notes,
      'rhythmId',r.rhythm_id,
      'active',r.active
    ) end
  ) order by o.created_at,o.id),'[]'::jsonb)
  into v_objects
  from atlas.household_care_objects o
  left join atlas.household_spaces s on s.id=o.space_id
  left join atlas.household_object_care_requirements r
    on r.object_id=o.id and r.care_kind='cleaning' and r.active
  where o.household_id=v_household_id and o.active;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_inventory_self_api_v1',
    'householdId',v_household_id,
    'spaceCount',jsonb_array_length(v_spaces),
    'spaces',v_spaces,
    'objects',v_objects
  );
end;
$function$;

revoke all on function atlas.upsert_personal_cleaning_space_requirement_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.upsert_personal_cleaning_space_requirement_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.upsert_personal_cleaning_space_requirement_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.upsert_personal_cleaning_space_requirement_self_api_v1(p_input); $function$;

revoke all on function public.upsert_personal_cleaning_space_requirement_self_api_v1(jsonb) from public,anon;
grant execute on function public.upsert_personal_cleaning_space_requirement_self_api_v1(jsonb) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values(
  'atlas.upsert_personal_cleaning_space_requirement_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object('purpose','Establish or revise a user-confirmed Cleaning requirement for one canonical household space and project its semantic cadence into household rhythm authority.'),now()
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();
