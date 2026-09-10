-- Extend the dedicated household Cleaning kernel with canonical spaces and object-specific care.
-- Rooms remain atlas.household_spaces. Household care objects and their cleaning requirements are separate truths.

create table if not exists atlas.household_care_objects (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  space_id uuid references atlas.household_spaces(id) on delete set null,
  stable_key text not null,
  name text not null,
  object_type text not null default 'object',
  active boolean not null default true,
  source_kind text not null default 'principal_authoring',
  confidence text not null default 'confirmed' check (confidence in ('candidate','confirmed')),
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(household_id,stable_key)
);

create table if not exists atlas.household_object_care_requirements (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  object_id uuid not null references atlas.household_care_objects(id) on delete cascade,
  stable_key text not null,
  care_kind text not null default 'cleaning',
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
  unique(object_id,stable_key)
);

alter table atlas.household_care_objects enable row level security;
alter table atlas.household_object_care_requirements enable row level security;
revoke all on atlas.household_care_objects from public,anon,authenticated;
revoke all on atlas.household_object_care_requirements from public,anon,authenticated;

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
    'confidence',s.confidence
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

create or replace function atlas.upsert_personal_cleaning_space_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_request_key text;
  v_name text;
  v_type text;
  v_dwelling jsonb;
  v_space jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Space input must be an object.' using errcode='22023'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_request_key:=nullif(trim(p_input->>'requestKey'),'');
  v_name:=nullif(trim(p_input->>'name'),'');
  v_type:=coalesce(nullif(trim(p_input->>'spaceType'),''),'other');
  if v_request_key is null or v_name is null then raise exception 'requestKey and name are required.' using errcode='22023'; end if;

  -- "Home" is only a neutral structural container for user-confirmed spaces; it does not assert house/apartment size or ownership.
  v_dwelling:=atlas.principal_upsert_dwelling_api_v1(jsonb_build_object(
    'stableKey','home',
    'name','Home',
    'dwellingKind','dwelling',
    'active',true,
    'metadata',jsonb_build_object('source','personal_cleaning_space_authoring_v1')
  ));

  v_space:=atlas.principal_upsert_household_space_api_v1(jsonb_build_object(
    'dwellingId',v_dwelling->>'dwellingId',
    'stableKey','personal-cleaning:'||v_request_key,
    'name',v_name,
    'spaceType',v_type,
    'functionalTags',coalesce(p_input->'functionalTags','[]'::jsonb),
    'floorLevel',nullif(trim(p_input->>'floorLevel'),''),
    'careRelevant',true,
    'sourceKind','principal_authoring',
    'confidence','confirmed',
    'metadata',jsonb_build_object('source','personal_cleaning_space_authoring_v1')
  ));

  return jsonb_build_object('ok',true,'contractVersion','personal_cleaning_space_authoring_v1','space',v_space);
end;
$function$;

create or replace function atlas.upsert_personal_cleaning_object_care_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_request_key text;
  v_object_name text;
  v_object_type text;
  v_space_id uuid;
  v_action text;
  v_cadence text;
  v_expected integer;
  v_season text;
  v_notes text;
  v_object atlas.household_care_objects%rowtype;
  v_requirement atlas.household_object_care_requirements%rowtype;
  v_rhythm jsonb;
  v_rhythm_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Object care input must be an object.' using errcode='22023'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_request_key:=nullif(trim(p_input->>'requestKey'),'');
  v_object_name:=nullif(trim(p_input->>'objectName'),'');
  v_object_type:=coalesce(nullif(trim(p_input->>'objectType'),''),'object');
  v_action:=nullif(trim(p_input->>'actionTitle'),'');
  v_cadence:=nullif(trim(p_input->>'cadenceRule'),'');
  v_expected:=coalesce(nullif(p_input->>'expectedMinutes','')::integer,15);
  v_season:=coalesce(nullif(trim(p_input->>'season'),''),'year_round');
  v_notes:=nullif(trim(p_input->>'notes'),'');
  if nullif(trim(p_input->>'spaceId'),'') is not null then v_space_id:=(p_input->>'spaceId')::uuid; end if;

  if v_request_key is null or v_object_name is null or v_action is null or v_cadence is null then
    raise exception 'requestKey, objectName, actionTitle, and cadenceRule are required.' using errcode='22023';
  end if;
  if v_expected<=0 then raise exception 'expectedMinutes must be positive.' using errcode='22023'; end if;
  if v_season not in ('year_round','winter','spring','summer','fall','custom') then raise exception 'Unsupported season.' using errcode='22023'; end if;
  if v_space_id is not null and not exists(
    select 1 from atlas.household_spaces s where s.id=v_space_id and s.household_id=v_household_id and s.active
  ) then raise exception 'Space does not belong to the active household.' using errcode='22023'; end if;

  insert into atlas.household_care_objects(
    household_id,space_id,stable_key,name,object_type,active,source_kind,confidence,confirmed_at,metadata
  ) values(
    v_household_id,v_space_id,'personal-cleaning:'||v_request_key,v_object_name,v_object_type,true,'principal_authoring','confirmed',now(),
    jsonb_build_object('source','personal_cleaning_object_care_v1')
  )
  on conflict(household_id,stable_key) do update set
    space_id=excluded.space_id,
    name=excluded.name,
    object_type=excluded.object_type,
    active=true,
    confidence='confirmed',
    confirmed_at=coalesce(atlas.household_care_objects.confirmed_at,now()),
    metadata=atlas.household_care_objects.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_object;

  v_rhythm:=atlas.principal_upsert_household_rhythm_api_v1(jsonb_build_object(
    'stableKey','object-care:'||v_object.id::text||':cleaning',
    'area','cleaning',
    'title',v_action||' — '||v_object_name,
    'cadenceRule',v_cadence,
    'expectedMinutes',v_expected,
    'protectionLevel','protected',
    'floorClass',3,
    'interruptibility','interruptible',
    'principalRequired',true,
    'blocksCapacity',true,
    'consequence','A user-confirmed household object has its own recurring cleaning or care need.',
    'reasonForFloor','Object-specific care requirement established through the Cleaning kernel.',
    'metadata',jsonb_strip_nulls(jsonb_build_object(
      'source','personal_cleaning_object_care_v1',
      'householdCareObjectId',v_object.id,
      'season',v_season,
      'semanticCadence',true,
      'clockWindowEstablished',false
    ))
  ));
  v_rhythm_id:=nullif(v_rhythm#>>'{rhythm,id}','')::uuid;

  insert into atlas.household_object_care_requirements(
    household_id,object_id,stable_key,care_kind,action_title,cadence_rule,expected_minutes,season,rhythm_id,notes,active,metadata
  ) values(
    v_household_id,v_object.id,'cleaning','cleaning',v_action,v_cadence,v_expected,v_season,v_rhythm_id,v_notes,true,
    jsonb_build_object('source','personal_cleaning_object_care_v1')
  )
  on conflict(object_id,stable_key) do update set
    action_title=excluded.action_title,
    cadence_rule=excluded.cadence_rule,
    expected_minutes=excluded.expected_minutes,
    season=excluded.season,
    rhythm_id=excluded.rhythm_id,
    notes=excluded.notes,
    active=true,
    metadata=atlas.household_object_care_requirements.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_requirement;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_object_care_v1',
    'object',jsonb_build_object('id',v_object.id,'name',v_object.name,'objectType',v_object.object_type,'spaceId',v_object.space_id),
    'requirement',jsonb_build_object('id',v_requirement.id,'actionTitle',v_requirement.action_title,'cadenceRule',v_requirement.cadence_rule,'expectedMinutes',v_requirement.expected_minutes,'season',v_requirement.season,'rhythmId',v_requirement.rhythm_id),
    'rhythm',v_rhythm
  );
end;
$function$;

revoke all on function atlas.personal_cleaning_inventory_self_api_v1() from public,anon;
revoke all on function atlas.upsert_personal_cleaning_space_self_api_v1(jsonb) from public,anon;
revoke all on function atlas.upsert_personal_cleaning_object_care_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.personal_cleaning_inventory_self_api_v1() to authenticated,service_role;
grant execute on function atlas.upsert_personal_cleaning_space_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.upsert_personal_cleaning_object_care_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.personal_cleaning_inventory_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_cleaning_inventory_self_api_v1(); $function$;

create or replace function public.upsert_personal_cleaning_space_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.upsert_personal_cleaning_space_self_api_v1(p_input); $function$;

create or replace function public.upsert_personal_cleaning_object_care_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.upsert_personal_cleaning_object_care_self_api_v1(p_input); $function$;

revoke all on function public.personal_cleaning_inventory_self_api_v1() from public,anon;
revoke all on function public.upsert_personal_cleaning_space_self_api_v1(jsonb) from public,anon;
revoke all on function public.upsert_personal_cleaning_object_care_self_api_v1(jsonb) from public,anon;
grant execute on function public.personal_cleaning_inventory_self_api_v1() to authenticated,service_role;
grant execute on function public.upsert_personal_cleaning_space_self_api_v1(jsonb) to authenticated,service_role;
grant execute on function public.upsert_personal_cleaning_object_care_self_api_v1(jsonb) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.personal_cleaning_inventory_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Read user-confirmed household spaces and object-specific Cleaning care requirements.'),now()),
  ('atlas.upsert_personal_cleaning_space_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Author a user-confirmed Cleaning-relevant household space through canonical household space authority.'),now()),
  ('atlas.upsert_personal_cleaning_object_care_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Establish a household care object, its Cleaning requirement, and a semantic household rhythm without inventing an exact clock window.'),now())
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
