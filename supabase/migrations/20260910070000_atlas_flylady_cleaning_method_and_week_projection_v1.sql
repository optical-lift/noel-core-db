-- Use FlyLady's five-zone rotation as Atlas's standing household Cleaning attention engine.
-- FlyLady is not a selectable household Cleaning model. The household's rooms/spaces are the real subjects;
-- this policy decides which group of spaces Atlas exposes for attention on a given date, analogous to the
-- way farm weeding rhythm exposes the beds currently needing stewardship.
--
-- Room existence, room Cleaning requirements, current room condition, and the attention schedule remain
-- separate truths. The schedule never claims a room is dirty merely because its zone is active.

-- Rotation is an exposure policy, not a model choice. Remove the two model rows that would make it look optional.
delete from atlas.world_kernel_models
where kernel_key='household.cleaning'
  and kernel_version=2
  and model_key in ('cleaning_zone_rotation','cleaning_flylady');

create table if not exists atlas.household_cleaning_zone_assignments (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  space_id uuid not null references atlas.household_spaces(id) on delete cascade,
  zone_id uuid not null references atlas.household_zones(id) on delete cascade,
  source_kind text not null default 'principal_confirmation',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(space_id)
);

alter table atlas.household_cleaning_zone_assignments enable row level security;
revoke all on atlas.household_cleaning_zone_assignments from public,anon,authenticated;

-- FlyLady calendar exposure: Zone 1 is the first partial/full week of the month,
-- Zones 2-4 follow, and Zone 5 is the final partial/full week. A notebook Monday-Sunday
-- week may therefore show two zones when the month changes during that week.
create or replace function atlas.flylady_zone_number_for_date_v1(p_day date)
returns smallint
language sql
immutable
strict
set search_path=pg_catalog
as $function$
  select least(
    5,
    1 + ((extract(day from p_day)::integer - 1 + extract(dow from date_trunc('month',p_day))::integer) / 7)
  )::smallint;
$function$;

-- This is proposal logic only. The user's confirmed assignment is stored separately.
create or replace function atlas.flylady_suggested_zone_for_space_v1(p_space_type text,p_tags text[])
returns smallint
language sql
immutable
set search_path=pg_catalog
as $function$
  select case
    when coalesce(p_space_type,'') in ('entry_mudroom','entry','porch','dining','dining_room')
      or coalesce(p_tags,'{}'::text[]) && array['arrival','transition','dining']::text[] then 1
    when coalesce(p_space_type,'') in ('kitchen','pantry','food_storage')
      or coalesce(p_tags,'{}'::text[]) && array['food','kitchen','pantry']::text[] then 2
    when coalesce(p_space_type,'') in ('bathroom','bedroom','office','utility','craft_room','kids_room','guest_room','secondary_room')
      or coalesce(p_tags,'{}'::text[]) && array['hygiene','secondary_room']::text[] then 3
    when coalesce(p_space_type,'') in ('primary_bedroom','primary_closet','primary_bathroom')
      or coalesce(p_tags,'{}'::text[]) && array['primary_sleeping','dressing']::text[] then 4
    when coalesce(p_space_type,'') in ('living_space','living_room','family_room')
      or coalesce(p_tags,'{}'::text[]) && array['primary_gathering']::text[] then 5
    else null
  end::smallint;
$function$;

-- The inherited policy created five hidden every-5-weeks rhythms. Those are superseded by one visible
-- date-driven attention projection. Keep historical rows inactive so they cannot create a second schedule.
update atlas.household_rhythms
set active=false,
    metadata=metadata||jsonb_build_object(
      'retiredBy','atlas_cleaning_flylady_attention_v1',
      'retiredReason','Five hidden zone rhythms were replaced by the visible date-driven Cleaning attention projection.'
    )
where stable_key like 'atlas_household_zone_attention_%';

-- The inherited household trigger already calls this function after household creation. It now ensures
-- the five Cleaning attention containers for every household, without claiming anything about room count
-- or whether the user has finished configuring Cleaning.
create or replace function atlas.ensure_household_care_policy_v1(p_household_id uuid,p_as_of timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_zone_number integer;
  v_zone_stable_key text;
  v_zone_name text;
  v_zone_tags text[];
begin
  if not exists(select 1 from atlas.households h where h.id=p_household_id and h.status='active') then
    raise exception 'Active household not found.' using errcode='P0002';
  end if;

  update atlas.household_rhythms
    set active=false
  where household_id=p_household_id
    and stable_key like 'atlas_household_zone_attention_%';

  for v_zone_number in 1..5 loop
    v_zone_stable_key:=case v_zone_number
      when 1 then 'cleaning_zone_1_entry_dining'
      when 2 then 'cleaning_zone_2_kitchen'
      when 3 then 'cleaning_zone_3_bath_secondary'
      when 4 then 'cleaning_zone_4_primary_bedroom'
      when 5 then 'cleaning_zone_5_living'
    end;
    v_zone_name:=case v_zone_number
      when 1 then 'Entry / porch / dining'
      when 2 then 'Kitchen / pantry'
      when 3 then 'Bathroom + secondary rooms'
      when 4 then 'Primary bedroom / closet / bath'
      when 5 then 'Living / family room'
    end;
    v_zone_tags:=case v_zone_number
      when 1 then array['arrival','transition','dining']::text[]
      when 2 then array['food','kitchen','pantry']::text[]
      when 3 then array['hygiene','secondary_room']::text[]
      when 4 then array['primary_sleeping','dressing']::text[]
      when 5 then array['primary_gathering']::text[]
    end;

    insert into atlas.household_zones(household_id,zone_number,stable_key,name,active,metadata)
    values(
      p_household_id,
      v_zone_number,
      v_zone_stable_key,
      v_zone_name,
      true,
      jsonb_build_object(
        'attentionPolicyKey','atlas_cleaning_flylady_attention',
        'attentionPolicyVersion',1,
        'sourceMethod','FlyLady five-zone rotation',
        'zoneMinutes',15,
        'functionalTags',to_jsonb(v_zone_tags),
        'rotationKind','calendar_month_week_segments',
        'physicalConditionClaim',false
      )
    )
    on conflict(household_id,zone_number) do update set
      stable_key=excluded.stable_key,
      name=excluded.name,
      active=true,
      metadata=coalesce(atlas.household_zones.metadata,'{}'::jsonb)||excluded.metadata,
      updated_at=now();
  end loop;

  return jsonb_build_object(
    'householdId',p_household_id,
    'policyKey','atlas_cleaning_flylady_attention',
    'active',true,
    'zonesEnsured',5,
    'hiddenRhythmsCreated',0,
    'physicalConditionClaim',false
  );
end;
$function$;

-- A previous pending draft coupled zone creation to the Cleaning kernel instance. Remove that coupling.
drop trigger if exists cleaning_method_policy_after_instance_write_v1 on atlas.household_kernel_instances;
drop function if exists atlas.cleaning_method_policy_after_instance_write_v1();

-- Ensure existing active households have the same attention containers as newly created households.
do $block$
declare
  r record;
begin
  for r in select id from atlas.households where status='active' loop
    perform atlas.ensure_household_care_policy_v1(r.id,now());
  end loop;
end;
$block$;

create or replace function atlas.set_personal_cleaning_space_zone_self_api_v1(p_space_id uuid,p_zone_number integer)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_zone atlas.household_zones%rowtype;
  v_space atlas.household_spaces%rowtype;
  v_assignment atlas.household_cleaning_zone_assignments%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;
  if p_zone_number not between 1 and 5 then raise exception 'Cleaning zone must be 1 through 5.' using errcode='22023'; end if;

  select * into v_space from atlas.household_spaces
  where id=p_space_id and household_id=v_household_id and active;
  if v_space.id is null then raise exception 'Active household space required.' using errcode='22023'; end if;

  select * into v_zone from atlas.household_zones
  where household_id=v_household_id and zone_number=p_zone_number and active
    and metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention'
  limit 1;
  if v_zone.id is null then raise exception 'Cleaning attention zone is unavailable.' using errcode='55000'; end if;

  insert into atlas.household_cleaning_zone_assignments(household_id,space_id,zone_id,source_kind,metadata)
  values(
    v_household_id,v_space.id,v_zone.id,'principal_confirmation',
    jsonb_build_object('source','personal_cleaning_zone_assignment_v1','attentionPolicyKey','atlas_cleaning_flylady_attention')
  )
  on conflict(space_id) do update set
    household_id=excluded.household_id,
    zone_id=excluded.zone_id,
    source_kind='principal_confirmation',
    metadata=atlas.household_cleaning_zone_assignments.metadata||excluded.metadata,
    updated_at=now()
  returning * into v_assignment;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_zone_assignment_v1',
    'space',jsonb_build_object('id',v_space.id,'name',v_space.name,'spaceType',v_space.space_type),
    'zone',jsonb_build_object('id',v_zone.id,'zoneNumber',v_zone.zone_number,'name',v_zone.name),
    'assignmentId',v_assignment.id
  );
end;
$function$;

create or replace function atlas.personal_cleaning_week_self_api_v1(p_anchor_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_household_id uuid;
  v_week_start date;
  v_week_end date;
  v_zone_minutes integer := 15;
  v_zones jsonb := '[]'::jsonb;
  v_spaces jsonb := '[]'::jsonb;
  v_days jsonb := '[]'::jsonb;
  v_objects jsonb := '[]'::jsonb;
  v_blessings jsonb := jsonb_build_array(
    jsonb_build_object('key','trash','title','Gather household trash'),
    jsonb_build_object('key','sheets','title','Change sheets'),
    jsonb_build_object('key','dust','title','Quick whole-house dust'),
    jsonb_build_object('key','glass','title','Shine mirrors / door glass'),
    jsonb_build_object('key','hotspots','title','Clear hot spots'),
    jsonb_build_object('key','vacuum','title','Vacuum the middles'),
    jsonb_build_object('key','mop','title','Quick mop kitchen / bathrooms')
  );
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_household_id:=atlas.principal_current_household_id_v1();
  if v_household_id is null then raise exception 'Active Principal household required.' using errcode='42501'; end if;

  v_week_start:=p_anchor_date-(extract(isodow from p_anchor_date)::integer-1);
  v_week_end:=v_week_start+6;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',z.id,
    'zoneNumber',z.zone_number,
    'name',z.name,
    'minutes',coalesce(nullif(z.metadata->>'zoneMinutes','')::integer,v_zone_minutes)
  ) order by z.zone_number),'[]'::jsonb)
  into v_zones
  from atlas.household_zones z
  where z.household_id=v_household_id
    and z.active
    and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'name',s.name,
    'spaceType',s.space_type,
    'confirmedZoneNumber',z.zone_number,
    'suggestedZoneNumber',atlas.flylady_suggested_zone_for_space_v1(s.space_type,s.functional_tags),
    'requirements',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,
        'actionTitle',r.action_title,
        'cadenceRule',r.cadence_rule,
        'expectedMinutes',r.expected_minutes,
        'season',r.season
      ) order by r.created_at,r.id)
      from atlas.household_space_cleaning_requirements r
      where r.household_id=v_household_id and r.space_id=s.id and r.active
    ),'[]'::jsonb)
  ) order by s.created_at,s.id),'[]'::jsonb)
  into v_spaces
  from atlas.household_spaces s
  left join atlas.household_cleaning_zone_assignments a
    on a.space_id=s.id and a.household_id=v_household_id
  left join atlas.household_zones z on z.id=a.zone_id and z.active
  where s.household_id=v_household_id and s.active and s.care_relevant;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date',d.day,
    'dayName',trim(to_char(d.day,'FMDay')),
    'isoDow',extract(isodow from d.day)::integer,
    'zoneNumber',d.zone_number,
    'zoneName',z.name,
    'zoneFocus',case when extract(isodow from d.day)::integer between 1 and 5 then jsonb_build_object(
      'minutes',coalesce(nullif(z.metadata->>'zoneMinutes','')::integer,v_zone_minutes),
      'spaces',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',s.id,
          'name',s.name,
          'spaceType',s.space_type,
          'requirements',coalesce((
            select jsonb_agg(jsonb_build_object(
              'id',r.id,
              'actionTitle',r.action_title,
              'cadenceRule',r.cadence_rule,
              'expectedMinutes',r.expected_minutes,
              'season',r.season
            ) order by r.created_at,r.id)
            from atlas.household_space_cleaning_requirements r
            where r.space_id=s.id and r.household_id=v_household_id and r.active
          ),'[]'::jsonb)
        ) order by s.name)
        from atlas.household_cleaning_zone_assignments a
        join atlas.household_spaces s on s.id=a.space_id and s.active
        join atlas.household_zones az on az.id=a.zone_id and az.active
        where a.household_id=v_household_id and az.zone_number=d.zone_number
      ),'[]'::jsonb)
    ) else null end,
    'weeklyHomeBlessing',case when extract(isodow from d.day)::integer=1 then v_blessings else '[]'::jsonb end
  ) order by d.day),'[]'::jsonb)
  into v_days
  from (
    select g::date as day,atlas.flylady_zone_number_for_date_v1(g::date) as zone_number
    from generate_series(v_week_start,v_week_end,interval '1 day') g
  ) d
  left join atlas.household_zones z
    on z.household_id=v_household_id
    and z.zone_number=d.zone_number
    and z.active
    and z.metadata->>'attentionPolicyKey'='atlas_cleaning_flylady_attention';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',o.id,
    'name',o.name,
    'spaceName',s.name,
    'actionTitle',r.action_title,
    'cadenceRule',r.cadence_rule,
    'expectedMinutes',r.expected_minutes,
    'season',r.season
  ) order by o.name,r.action_title),'[]'::jsonb)
  into v_objects
  from atlas.household_care_objects o
  join atlas.household_object_care_requirements r
    on r.object_id=o.id and r.active and r.care_kind='cleaning'
  left join atlas.household_spaces s on s.id=o.space_id
  where o.household_id=v_household_id and o.active;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_cleaning_week_self_api_v1',
    'attentionPolicy',jsonb_build_object(
      'key','atlas_cleaning_flylady_attention',
      'sourceMethod','FlyLady five-zone rotation',
      'zoneMinutes',v_zone_minutes,
      'zoneWeekStarts','sunday',
      'spreadWeekStarts','monday',
      'physicalConditionClaim',false,
      'optional',false
    ),
    'anchorDate',p_anchor_date,
    'weekStart',v_week_start,
    'weekEnd',v_week_end,
    'zones',v_zones,
    'spaces',v_spaces,
    'days',v_days,
    'weeklyHomeBlessingItems',v_blessings,
    'specialObjectCare',v_objects,
    'truthBoundary',jsonb_build_object(
      'spacesAreRealSubjects',true,
      'zoneAssignmentsAreConfirmedTruth',true,
      'suggestedZonesAreNotTruth',true,
      'zoneCalendarIsAttentionExposure',true,
      'zoneCalendarDoesNotClaimPhysicalCondition',true,
      'roomRequirementsRemainCanonical',true,
      'currentRoomConditionIsSeparate',true,
      'flyLadyIsNotASelectableModel',true
    )
  );
end;
$function$;

-- Cleaning Rhythm is a first-class household spread for every established Personal Atlas household.
create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;

  with descriptors as (
    select 0 as section_order,0 as item_order,jsonb_build_object('addressKind','today','spreadKey','today','templateKey','today','title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','day','id',current_date::text)) as item
    union all
    select 0,1,jsonb_build_object('addressKind','index','spreadKey','index','templateKey','index','title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','notebook','id',v_user_id))
    union all
    select 10,0,jsonb_build_object('addressKind','spread','spreadKey','household-rhythm','templateKey','rhythm','title','Household rhythm','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household','id',h.id)) from atlas.households h where h.id=v_household_id
    union all
    select 10,1,jsonb_build_object('addressKind','spread','spreadKey','laundry','templateKey','rhythm','title','Laundry','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','world_kernel','id','household.laundry')) from atlas.households h where h.id=v_household_id
    union all
    select 10,2,jsonb_build_object('addressKind','spread','spreadKey','cleaning-rhythm','templateKey','cleaning-rhythm','title','Cleaning rhythm','subtitle','Five-zone attention','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','world_kernel','id','household.cleaning')) from atlas.households h where h.id=v_household_id
    union all
    select 10,3,jsonb_build_object('addressKind','spread','spreadKey','home-care','templateKey','occurrence','title','Home care','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household_care','id',h.id)) from atlas.households h where h.id=v_household_id
    union all
    select 20,row_number() over(order by d.created_at,d.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey','life:'||d.id::text,
        'templateKey',case
          when d.signal_kind ilike '%goal%' or d.signal_kind ilike '%training%' or d.life_signal?'goal' or d.life_signal?'target' or d.life_signal?'milestones' then 'progress'
          when d.signal_kind ilike '%maintenance%' or d.signal_kind ilike '%rhythm%' or d.signal_kind ilike '%recurr%' or d.life_signal?'cadence' or d.life_signal?'interval' or d.life_signal?'nextDue' then 'occurrence'
          else 'log' end,
        'title',coalesce(nullif(d.life_signal->>'title',''),nullif(d.life_signal->>'label',''),initcap(replace(d.signal_kind,'_',' '))),
        'section','Life','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind',d.signal_kind,'id',d.id)
      )
    from atlas.person_life_definitions d where d.owner_user_id=v_user_id and d.status<>'retired'
    union all
    select 30,row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object('addressKind','spread','spreadKey','ledger:'||o.id::text,'templateKey','organization-ledger','title',o.name,'subtitle','Ledger','section','Organizations','scope',jsonb_build_object('kind','organization','id',o.id),'subject',jsonb_build_object('kind','organization_ledger','id',o.id))
    from atlas.organizations o where atlas.is_organization_owner(o.id)
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb) into v_items from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object('indexIsRetrievalProjection',true,'indexDoesNotGrantAccess',true,'spreadDescriptorsDoNotOwnSourceTruth',true,'ledgerDescriptorMatchesReadAuthority',true)
  );
end;
$function$;

revoke all on function atlas.set_personal_cleaning_space_zone_self_api_v1(uuid,integer) from public,anon;
revoke all on function atlas.personal_cleaning_week_self_api_v1(date) from public,anon;
grant execute on function atlas.set_personal_cleaning_space_zone_self_api_v1(uuid,integer) to authenticated,service_role;
grant execute on function atlas.personal_cleaning_week_self_api_v1(date) to authenticated,service_role;

create or replace function public.set_personal_cleaning_space_zone_self_api_v1(p_space_id uuid,p_zone_number integer)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.set_personal_cleaning_space_zone_self_api_v1(p_space_id,p_zone_number); $function$;

create or replace function public.personal_cleaning_week_self_api_v1(p_anchor_date date default current_date)
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.personal_cleaning_week_self_api_v1(p_anchor_date); $function$;

revoke all on function public.set_personal_cleaning_space_zone_self_api_v1(uuid,integer) from public,anon;
revoke all on function public.personal_cleaning_week_self_api_v1(date) from public,anon;
grant execute on function public.set_personal_cleaning_space_zone_self_api_v1(uuid,integer) to authenticated,service_role;
grant execute on function public.personal_cleaning_week_self_api_v1(date) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
)
values
  (
    'atlas.set_personal_cleaning_space_zone_self_api_v1(p_space_id uuid, p_zone_number integer)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Confirm one real household space into one standing five-zone Cleaning attention group.'),now()
  ),
  (
    'atlas.personal_cleaning_week_self_api_v1(p_anchor_date date)',
    'app_endpoint','verified','active',true,true,true,false,1,0,
    jsonb_build_object('purpose','Expose the household spaces receiving Cleaning attention across a Monday-Sunday notebook week using the standing FlyLady five-zone rotation.'),now()
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
