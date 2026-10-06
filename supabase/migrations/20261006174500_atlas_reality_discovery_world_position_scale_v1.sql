begin;

-- First-day orientation: WORLD -> POSITION -> SCALE.
--
-- This replaces the ambiguous "world / carry" cold-start in the live product.
-- Orientation remains evidence about where Atlas should look first. It does
-- not establish owning-domain truth and its ranking influence decays as
-- governed Discovery answers accumulate.

alter table atlas.reality_discovery_orientation_events
  add column if not exists orientation_version integer not null default 1,
  add column if not exists position_map jsonb not null default '{}'::jsonb,
  add column if not exists scale_map jsonb not null default '{}'::jsonb;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='atlas.reality_discovery_orientation_events'::regclass
      and conname='reality_discovery_orientation_version_positive'
  ) then
    alter table atlas.reality_discovery_orientation_events
      add constraint reality_discovery_orientation_version_positive
      check(orientation_version>=1);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='atlas.reality_discovery_orientation_events'::regclass
      and conname='reality_discovery_orientation_position_object'
  ) then
    alter table atlas.reality_discovery_orientation_events
      add constraint reality_discovery_orientation_position_object
      check(jsonb_typeof(position_map)='object');
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='atlas.reality_discovery_orientation_events'::regclass
      and conname='reality_discovery_orientation_scale_object'
  ) then
    alter table atlas.reality_discovery_orientation_events
      add constraint reality_discovery_orientation_scale_object
      check(jsonb_typeof(scale_map)='object');
  end if;
end;
$constraints$;

create or replace function atlas.reality_discovery_orientation_profile_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select * into v_event
  from atlas.reality_discovery_orientation_events
  where principal_id=v_principal_id
    and owner_user_id=v_user_id
    and orientation_version=2
  order by occurred_at desc,id desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_orientation_profile_self_api_v1',
    'model','world_position_scale',
    'captured',v_event.id is not null,
    'worldDomains',coalesce(v_event.world_domains,'[]'::jsonb),
    'positionMap',coalesce(v_event.position_map,'{}'::jsonb),
    'scaleMap',coalesce(v_event.scale_map,'{}'::jsonb),
    'occurredAt',v_event.occurred_at,
    'truthBoundary',jsonb_build_object(
      'orientationIsColdStartEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'worldLocatesRelevantLifeArenas',true,
      'positionLocatesHumanRelationWithinThoseArenas',true,
      'scaleEstimatesOperationalMagnitude',true,
      'orientationMayReorderDiscovery',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_orientation_profile_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.reality_discovery_orientation_profile_self_api_v1() to service_role;

create or replace function public.reality_discovery_orientation_profile_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_orientation_profile_self_api_v1();
$function$;

revoke all on function public.reality_discovery_orientation_profile_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_orientation_profile_self_api_v1() to authenticated,service_role;

create or replace function atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_source_action_id text;
  v_world jsonb;
  v_positions jsonb;
  v_scale jsonb;
  v_position_world text;
  v_position_value text;
  v_scale_key text;
  v_scale_value text;
  v_existing atlas.reality_discovery_orientation_events%rowtype;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Orientation profile input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then
    raise exception 'sourceActionId required.' using errcode='22023';
  end if;

  if coalesce(jsonb_typeof(p_input->'worldDomains'),'array')<>'array'
     or coalesce(jsonb_typeof(p_input->'positionMap'),'object')<>'object'
     or coalesce(jsonb_typeof(p_input->'scaleMap'),'object')<>'object' then
    raise exception 'WORLD must be an array; POSITION and SCALE must be objects.' using errcode='22023';
  end if;

  if exists(
    select 1
    from jsonb_each(coalesce(p_input->'positionMap','{}'::jsonb)) e
    where jsonb_typeof(e.value)<>'array'
  ) then
    raise exception 'Each POSITION world must contain an array of roles.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
  into v_world
  from (
    select distinct trim(value) as domain
    from jsonb_array_elements_text(coalesce(p_input->'worldDomains','[]'::jsonb))
    where nullif(trim(value),'') is not null
  ) s;

  select coalesce(jsonb_object_agg(world,roles order by world),'{}'::jsonb)
  into v_positions
  from (
    select e.key as world,
      coalesce(jsonb_agg(to_jsonb(role) order by role),'[]'::jsonb) as roles
    from jsonb_each(coalesce(p_input->'positionMap','{}'::jsonb)) e
    cross join lateral (
      select distinct trim(value) as role
      from jsonb_array_elements_text(e.value)
      where nullif(trim(value),'') is not null
    ) r
    group by e.key
  ) s;

  select coalesce(jsonb_object_agg(key,value order by key),'{}'::jsonb)
  into v_scale
  from jsonb_each(coalesce(p_input->'scaleMap','{}'::jsonb))
  where jsonb_typeof(value)='string'
    and nullif(trim(both '"' from value::text),'') is not null;

  if jsonb_array_length(v_world)=0 then
    raise exception 'Choose at least one WORLD.' using errcode='22023';
  end if;

  if exists(
    select 1 from jsonb_array_elements_text(v_world) d(value)
    where d.value not in (
      'home','family','job','business','property',
      'money','school','projects','community','hobbies'
    )
  ) then
    raise exception 'Unsupported WORLD orientation domain.' using errcode='22023';
  end if;

  for v_position_world,v_position_value in
    select e.key,r.value
    from jsonb_each(v_positions) e
    cross join lateral jsonb_array_elements_text(e.value) r(value)
  loop
    if not (v_world ? v_position_world) then
      raise exception 'POSITION world % is not selected in WORLD.',v_position_world using errcode='22023';
    end if;

    if not (
      (v_position_world='home' and v_position_value in ('owner','renter'))
      or (v_position_world='family' and v_position_value in ('partner','parent','caregiver'))
      or (v_position_world='job' and v_position_value in ('employee','contractor','leader','manager'))
      or (v_position_world='business' and v_position_value in ('owner','coowner','operator','employer','manager'))
      or (v_position_world='property' and v_position_value in ('owner','landlord','investor','agent','broker','manager'))
      or (v_position_world='school' and v_position_value in ('student','parent','educator'))
      or (v_position_world='projects' and v_position_value in ('maker','leader'))
      or (v_position_world='community' and v_position_value in ('member','leader','volunteer','caregiver'))
    ) then
      raise exception 'POSITION % is not coherent with WORLD %.',v_position_value,v_position_world using errcode='22023';
    end if;
  end loop;

  for v_scale_key,v_scale_value in
    select key,trim(both '"' from value::text)
    from jsonb_each(v_scale)
  loop
    if not (
      (v_scale_key='household' and v_scale_value in ('one','two','three_four','five_plus')
        and (v_world ? 'home' or v_world ? 'family'))
      or
      (v_scale_key='children' and v_scale_value in ('one','two','three_four','five_plus')
        and v_world ? 'family' and coalesce(v_positions->'family','[]'::jsonb) ? 'parent')
      or
      (v_scale_key='businesses' and v_scale_value in ('one','two_three','four_plus')
        and v_world ? 'business')
      or
      (v_scale_key='properties' and v_scale_value in ('one','two_five','six_plus')
        and v_world ? 'property')
      or
      (v_scale_key='team' and v_scale_value in ('one_five','six_twenty','twenty_one_plus')
        and (
          (v_world ? 'business' and (coalesce(v_positions->'business','[]'::jsonb) ? 'employer' or coalesce(v_positions->'business','[]'::jsonb) ? 'operator' or coalesce(v_positions->'business','[]'::jsonb) ? 'manager'))
          or (v_world ? 'job' and (coalesce(v_positions->'job','[]'::jsonb) ? 'leader' or coalesce(v_positions->'job','[]'::jsonb) ? 'manager'))
          or (v_world ? 'community' and coalesce(v_positions->'community','[]'::jsonb) ? 'leader')
        ))
      or
      (v_scale_key='projects' and v_scale_value in ('one','two_five','six_plus')
        and v_world ? 'projects')
      or
      (v_scale_key='hobbies' and v_scale_value in ('one','two_three','four_plus')
        and v_world ? 'hobbies')
      or
      (v_scale_key='groups' and v_scale_value in ('one','two_three','four_plus')
        and v_world ? 'community')
      or
      (v_scale_key='accounts' and v_scale_value in ('one_three','four_seven','eight_plus')
        and v_world ? 'money')
    ) then
      raise exception 'SCALE %=% is not coherent with WORLD / POSITION.',v_scale_key,v_scale_value using errcode='22023';
    end if;
  end loop;

  select * into v_existing
  from atlas.reality_discovery_orientation_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;

  if v_existing.id is not null then
    if v_existing.orientation_version<>2
       or v_existing.world_domains is distinct from v_world
       or v_existing.position_map is distinct from v_positions
       or v_existing.scale_map is distinct from v_scale then
      raise exception 'sourceActionId already belongs to different orientation evidence.' using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'idempotentReplay',true,
      'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  insert into atlas.reality_discovery_orientation_events(
    principal_id,owner_user_id,source_action_id,
    world_domains,carry_domains,position_map,scale_map,orientation_version,metadata
  ) values(
    v_principal_id,v_user_id,v_source_action_id,
    v_world,'[]'::jsonb,v_positions,v_scale,2,
    jsonb_build_object(
      'source','first_day_orientation_world_position_scale_v1',
      'model','world_position_scale'
    )
  )
  returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_reality_discovery_orientation_profile_self_api_v1',
    'eventId',v_event.id,
    'orientation',atlas.reality_discovery_orientation_profile_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'orientationIsHumanProvidedEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'orientationOnlyChangesAttentionOrder',true,
      'scaleIsApproximateOrientationNotCanonicalQuantity',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

revoke all on function atlas.set_reality_discovery_orientation_profile_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.set_reality_discovery_orientation_profile_self_api_v1(jsonb) to service_role;

create or replace function public.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input);
$function$;

revoke all on function public.set_reality_discovery_orientation_profile_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_reality_discovery_orientation_profile_self_api_v1(jsonb) to authenticated,service_role;

-- The current orientation vocabulary is part of the ranking metadata. Remove
-- the superseded "carry" vocabulary rather than leaving two competing models
-- on the question catalog.
update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('home','family'),
        'orientationPositionPairs',jsonb_build_array('family:partner','family:parent','family:caregiver','home:owner','home:renter'),
        'orientationScaleKeys',jsonb_build_array('household','children')
      ),
    updated_at=now()
where question_key in ('household.people_shape','household.child_count','children.school_calendar');

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('home','property'),
        'orientationPositionPairs',jsonb_build_array('home:owner','home:renter','property:owner','property:landlord','property:manager'),
        'orientationScaleKeys',jsonb_build_array('household','properties')
      ),
    updated_at=now()
where question_key in ('home.tenure','home.confirm_purchase_address','home.setting','home.dwelling_kind','home.major_repairs');

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('home','property','projects'),
        'orientationPositionPairs',jsonb_build_array('home:owner','home:renter','property:owner','property:landlord','property:manager','projects:maker'),
        'orientationScaleKeys',jsonb_build_array('properties','projects')
      ),
    updated_at=now()
where question_key in ('grounds.responsibility','grounds.scale','grounds.mowing_method','equipment.riding_mower_identity','laundry.location');

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('job','business','school','projects'),
        'orientationPositionPairs',jsonb_build_array('job:employee','job:contractor','job:leader','job:manager','business:owner','business:coowner','business:operator','business:employer','business:manager','school:student','school:educator','projects:maker','projects:leader'),
        'orientationScaleKeys',jsonb_build_array('businesses','team','projects')
      ),
    updated_at=now()
where question_key='life.weekday_anchor';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('home','job','business','property'),
        'orientationPositionPairs',jsonb_build_array('home:owner','job:employee','job:contractor','business:owner','business:operator','property:agent','property:broker'),
        'orientationScaleKeys',jsonb_build_array('businesses','properties')
      ),
    updated_at=now()
where question_key='transport.vehicle_count';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('home','family','hobbies'),
        'orientationPositionPairs',jsonb_build_array('family:caregiver','family:parent'),
        'orientationScaleKeys',jsonb_build_array('household','hobbies')
      ),
    updated_at=now()
where question_key='animals.responsibility';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('job','business'),
        'orientationPositionPairs',jsonb_build_array('job:employee','job:contractor','job:leader','job:manager','business:owner','business:coowner','business:operator','business:employer','business:manager'),
        'orientationScaleKeys',jsonb_build_array('businesses','team')
      ),
    updated_at=now()
where question_key='work.structure';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('business'),
        'orientationPositionPairs',jsonb_build_array('business:owner','business:coowner','business:operator','business:employer','business:manager'),
        'orientationScaleKeys',jsonb_build_array('businesses','team')
      ),
    updated_at=now()
where question_key='business.count';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('job','business','property'),
        'orientationPositionPairs',jsonb_build_array('job:contractor','business:owner','business:operator','business:manager','property:agent','property:broker','property:manager'),
        'orientationScaleKeys',jsonb_build_array('businesses','properties')
      ),
    updated_at=now()
where question_key='work.client_responsibility';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('property'),
        'orientationPositionPairs',jsonb_build_array('property:owner','property:landlord','property:investor','property:agent','property:broker','property:manager'),
        'orientationScaleKeys',jsonb_build_array('properties')
      ),
    updated_at=now()
where question_key='property.relationship';

update atlas.reality_discovery_questions
set metadata=(coalesce(metadata,'{}'::jsonb)-'orientationCarryDomains')
      ||jsonb_build_object(
        'orientationWorldDomains',jsonb_build_array('property'),
        'orientationPositionPairs',jsonb_build_array('property:owner','property:landlord','property:investor','property:manager'),
        'orientationScaleKeys',jsonb_build_array('properties')
      ),
    updated_at=now()
where question_key='property.portfolio_size';

-- A hobby-oriented human and a project-oriented human now have a real first
-- branch rather than being redirected into unrelated household detail.
insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,
  reason_text,active,metadata
) values
(
  'hobbies.kind','hobbies','Hobbies?',null,'single_choice',
  '[{"key":"creative","label":"creative"},{"key":"outdoors","label":"outdoors"},{"key":"sports","label":"sports"},{"key":"other","label":"other"}]'::jsonb,
  70,1,55,82,'hobbies.kind',
  'A hobby shape gives Atlas a first route into recurring interests, equipment, events, projects, and commitments.',
  true,
  jsonb_build_object(
    'encounterCluster','hobbies',
    'encounterClusterLabel','HOBBIES',
    'orientationWorldDomains',jsonb_build_array('hobbies'),
    'orientationPositionPairs',jsonb_build_array(),
    'orientationScaleKeys',jsonb_build_array('hobbies')
  )
),
(
  'projects.kind','projects','Projects?',null,'single_choice',
  '[{"key":"home","label":"home"},{"key":"creative","label":"creative"},{"key":"business","label":"business"},{"key":"other","label":"other"}]'::jsonb,
  72,1,68,88,'projects.kind',
  'Project shape tells Atlas which obligations, materials, people, dates, and recurrence are likely to matter.',
  true,
  jsonb_build_object(
    'encounterCluster','projects',
    'encounterClusterLabel','PROJECTS',
    'orientationWorldDomains',jsonb_build_array('projects'),
    'orientationPositionPairs',jsonb_build_array('projects:maker','projects:leader'),
    'orientationScaleKeys',jsonb_build_array('projects')
  )
),
(
  'money.scope','money','Money?',null,'single_choice',
  '[{"key":"personal","label":"personal"},{"key":"household","label":"household"},{"key":"business","label":"business"},{"key":"mixed","label":"mixed"}]'::jsonb,
  66,1,82,78,'money.scope',
  'Money scope tells Atlas whether personal, household, business, or mixed financial reality deserves the first financial branch.',
  true,
  jsonb_build_object(
    'encounterCluster','money',
    'encounterClusterLabel','MONEY',
    'orientationWorldDomains',jsonb_build_array('money'),
    'orientationPositionPairs',jsonb_build_array(),
    'orientationScaleKeys',jsonb_build_array('accounts')
  )
),
(
  'community.kind','community','Community?',null,'single_choice',
  '[{"key":"church","label":"church"},{"key":"nonprofit","label":"nonprofit"},{"key":"club","label":"club"},{"key":"other","label":"other"}]'::jsonb,
  62,1,58,72,'community.kind',
  'Community shape gives Atlas a first route into recurring people, events, service, leadership, and commitments.',
  true,
  jsonb_build_object(
    'encounterCluster','community',
    'encounterClusterLabel','COMMUNITY',
    'orientationWorldDomains',jsonb_build_array('community'),
    'orientationPositionPairs',jsonb_build_array('community:member','community:leader','community:volunteer'),
    'orientationScaleKeys',jsonb_build_array('groups')
  )
)
on conflict(question_key) do update set
  section_key=excluded.section_key,
  prompt=excluded.prompt,
  help_text=excluded.help_text,
  answer_kind=excluded.answer_kind,
  options=excluded.options,
  base_score=excluded.base_score,
  friction=excluded.friction,
  consequence_value=excluded.consequence_value,
  information_gain=excluded.information_gain,
  resolved_signal_key=excluded.resolved_signal_key,
  reason_text=excluded.reason_text,
  active=excluded.active,
  metadata=excluded.metadata,
  updated_at=now();

insert into atlas.reality_discovery_encounter_admission(
  question_key,admission_class,first_day_disposition,reason_text,metadata
) values
(
  'hobbies.kind','high_leverage','admit',
  'Hobbies may be a meaningful recurring part of the human world and should be available when explicitly oriented.',
  '{}'::jsonb
),
(
  'projects.kind','high_leverage','admit',
  'Projects may be a major operational field and should be available when explicitly oriented.',
  '{}'::jsonb
),
(
  'money.scope','high_leverage','admit',
  'Money is a first-class Atlas domain when the human explicitly orients toward it.',
  '{}'::jsonb
),
(
  'community.kind','high_leverage','admit',
  'Community commitments may be a major recurring field and should be available when explicitly oriented.',
  '{}'::jsonb
)
on conflict(question_key) do update set
  admission_class=excluded.admission_class,
  first_day_disposition=excluded.first_day_disposition,
  reason_text=excluded.reason_text,
  metadata=excluded.metadata,
  updated_at=now();

create or replace function atlas.reality_discovery_ranked_questions_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_source_coverage jsonb;
  v_orientation jsonb;
  v_profile jsonb;
  v_legacy jsonb;
  v_world jsonb;
  v_position_map jsonb;
  v_position_pairs jsonb;
  v_scale jsonb;
  v_signals jsonb;
  v_answers jsonb;
  v_answer_count integer;
  v_orientation_factor integer;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_source_coverage:=atlas.reality_discovery_source_coverage_self_api_v1();
  v_profile:=atlas.reality_discovery_orientation_profile_self_api_v1();

  if coalesce((v_profile->>'captured')::boolean,false) then
    v_orientation:=v_profile;
  else
    -- Transitional compatibility for a first-day session created by the
    -- superseded two-axis client before this migration is released.
    v_legacy:=atlas.reality_discovery_orientation_self_api_v1();
    v_orientation:=jsonb_build_object(
      'ok',true,
      'model','legacy_world_only',
      'captured',coalesce((v_legacy->>'captured')::boolean,false),
      'worldDomains',coalesce(v_legacy->'worldDomains','[]'::jsonb),
      'positionMap','{}'::jsonb,
      'scaleMap','{}'::jsonb
    );
  end if;

  v_context:=v_context||jsonb_build_object(
    'sourceCoverage',v_source_coverage,
    'orientation',v_orientation
  );
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);
  v_answers:=coalesce(v_context->'answers','{}'::jsonb);
  v_world:=coalesce(v_orientation->'worldDomains','[]'::jsonb);
  v_position_map:=coalesce(v_orientation->'positionMap','{}'::jsonb);
  v_scale:=coalesce(v_orientation->'scaleMap','{}'::jsonb);

  select coalesce(jsonb_object_agg(pair,true),'{}'::jsonb)
  into v_position_pairs
  from (
    select e.key||':'||r.value as pair
    from jsonb_each(v_position_map) e
    cross join lateral jsonb_array_elements_text(e.value) r(value)
  ) p;

  v_answer_count:=jsonb_object_length(v_answers);
  v_orientation_factor:=case
    when v_answer_count>=12 then 0
    when v_answer_count>=6 then 50
    else 100
  end;

  with edge_eval as (
    select q.question_key,e.effect_kind,e.weight,
      atlas.reality_discovery_edge_matches_v1(v_signals->e.signal_key,e.operator,e.compare_value) as matched,
      e.reason_text
    from atlas.reality_discovery_questions q
    left join atlas.reality_discovery_edges e on e.question_key=q.question_key
    where q.active
  ), scored as (
    select q.*,
      case
        when jsonb_typeof(q.metadata->'sourceCoverageKeys')='array'
         and exists (
           select 1
           from jsonb_array_elements_text(q.metadata->'sourceCoverageKeys') requested(coverage_key)
           where coalesce(v_source_coverage->'keys','[]'::jsonb) ? requested.coverage_key
         )
         and (
           q.resolved_signal_key is null
           or not (coalesce(v_context->'candidateEvidence','{}'::jsonb) ? q.resolved_signal_key)
         )
        then greatest(0,coalesce(nullif(q.metadata->>'sourceCoveragePenalty','')::integer,0))
        else 0
      end as source_coverage_penalty,
      (
        case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationWorldDomains') d(domain)
             where v_world ? d.domain
           )
          then 105*v_orientation_factor/100 else 0
        end
        +
        case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationPositionPairs')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationPositionPairs') d(tag)
             where v_position_pairs ? d.tag
           )
          then 150*v_orientation_factor/100 else 0
        end
        +
        case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationScaleKeys')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationScaleKeys') d(scale_key)
             where v_scale ? d.scale_key
           )
          then 55*v_orientation_factor/100 else 0
        end
      )::integer as orientation_boost,
      (
        q.base_score+q.consequence_value+q.information_gain-q.friction
        +coalesce(sum(e.weight) filter(where e.effect_kind='boost' and e.matched),0)
        +case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationWorldDomains') d(domain)
             where v_world ? d.domain
           )
          then 105*v_orientation_factor/100 else 0
        end
        +case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationPositionPairs')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationPositionPairs') d(tag)
             where v_position_pairs ? d.tag
           )
          then 150*v_orientation_factor/100 else 0
        end
        +case
          when v_orientation_factor>0
           and jsonb_typeof(q.metadata->'orientationScaleKeys')='array'
           and exists(
             select 1
             from jsonb_array_elements_text(q.metadata->'orientationScaleKeys') d(scale_key)
             where v_scale ? d.scale_key
           )
          then 55*v_orientation_factor/100 else 0
        end
        -case
          when jsonb_typeof(q.metadata->'sourceCoverageKeys')='array'
           and exists (
             select 1
             from jsonb_array_elements_text(q.metadata->'sourceCoverageKeys') requested(coverage_key)
             where coalesce(v_source_coverage->'keys','[]'::jsonb) ? requested.coverage_key
           )
           and (
             q.resolved_signal_key is null
             or not (coalesce(v_context->'candidateEvidence','{}'::jsonb) ? q.resolved_signal_key)
           )
          then greatest(0,coalesce(nullif(q.metadata->>'sourceCoveragePenalty','')::integer,0))
          else 0
        end
      )::integer as score,
      coalesce(bool_and(e.matched) filter(where e.effect_kind='require'),true) as requirements_met,
      coalesce(bool_or(e.matched) filter(where e.effect_kind='suppress'),false) as suppressed,
      coalesce(jsonb_agg(e.reason_text) filter(where e.effect_kind='boost' and e.matched and e.reason_text is not null),'[]'::jsonb) as matched_reasons
    from atlas.reality_discovery_questions q
    left join edge_eval e on e.question_key=q.question_key
    where q.active
    group by q.question_key
  ), eligible as (
    select s.*
    from scored s
    where s.requirements_met
      and not s.suppressed
      and not (v_answers ? s.question_key)
      and not (
        coalesce((s.metadata->>'requiresCandidate')::boolean,false)
        and coalesce(v_signals->(s.metadata->>'candidateSignalKey'),'null'::jsonb)='null'::jsonb
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'questionKey',e.question_key,
    'sectionKey',e.section_key,
    'prompt',e.prompt,
    'helpText',e.help_text,
    'answerKind',e.answer_kind,
    'options',e.options,
    'score',e.score,
    'orientationBoost',e.orientation_boost,
    'reason',e.reason_text,
    'matchedReasons',case
      when e.source_coverage_penalty>0
      then e.matched_reasons||jsonb_build_array('Atlas has an authorized, recently synced source that may provide evidence here, so this question was moved later rather than suppressed.')
      else e.matched_reasons
    end,
    'sourceCoveragePenalty',e.source_coverage_penalty,
    'candidateValue',case when coalesce((e.metadata->>'requiresCandidate')::boolean,false)
      then v_signals->(e.metadata->>'candidateSignalKey') else null end
  ) order by e.score desc,e.question_key),'[]'::jsonb)
  into v_items
  from eligible e;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_ranked_questions_self_api_v1',
    'items',v_items,
    'context',v_context,
    'truthBoundary',jsonb_build_object(
      'rankingOrdersEligibleQuestions',true,
      'rankingDoesNotCreateEncounterAdmission',true,
      'sourceCoverageMayReorderButNeverSuppress',true,
      'sourceCoverageDoesNotAnswerQuestions',true,
      'orientationUsesWorldPositionScale',true,
      'orientationMayReorderButNeverAnswer',true,
      'orientationInfluenceDecaysWithEstablishedAnswers',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
(
  'atlas.reality_discovery_orientation_profile_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read the authenticated Principal current WORLD / POSITION / SCALE first-day orientation evidence.',
    'truthBoundary','Orientation changes attention order only and does not establish owning-domain truth.'
  ),
  now()
),
(
  'atlas.set_reality_discovery_orientation_profile_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append the authenticated Principal WORLD / POSITION / SCALE cold-start orientation evidence.',
    'truthBoundary','WORLD / POSITION / SCALE are decaying ranking priors; SCALE is approximate and noncanonical.'
  ),
  now()
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

commit;
