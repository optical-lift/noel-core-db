-- Atlas Person Life Persistence + Clock v1
--
-- Adds private person-owned custody around the generic Life reducers without
-- changing farm-rooted Goal/Rhythm/Consequence persistence. Person observations
-- cannot become Clock claims directly: Clock entry requires an established
-- consequence from an accepted policy plus an accepted temporal carrier.

begin;

create table if not exists atlas.person_life_events (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  actor_user_id uuid references auth.users(id) on delete set null,
  source_kind text not null,
  source_key text not null,
  source_record_id uuid,
  event_kind text not null,
  claim_state text not null default 'reported'
    check (claim_state in ('reported','observed','accepted','proposed','rejected','superseded','expired','unknown')),
  authority_kind text not null default 'first_party',
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  unique (person_user_id, source_kind, source_key)
);

create table if not exists atlas.person_life_event_subjects (
  event_id uuid not null references atlas.person_life_events(id) on delete cascade,
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  relation_kind text not null default 'about',
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  primary key (event_id, subject_domain, subject_kind, subject_id, relation_kind)
);

create table if not exists atlas.person_life_event_relations (
  from_event_id uuid not null references atlas.person_life_events(id) on delete cascade,
  to_event_id uuid not null references atlas.person_life_events(id) on delete cascade,
  relation_kind text not null,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  primary key (from_event_id, to_event_id, relation_kind),
  check (from_event_id <> to_event_id)
);

create table if not exists atlas.person_life_goals (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null,
  title text not null,
  goal_packet jsonb not null
    check (jsonb_typeof(goal_packet)='object' and goal_packet->>'contractVersion'='life_goal_packet_v1'),
  authorization_state text not null default 'proposed'
    check (authorization_state in ('proposed','accepted','rejected','superseded','withdrawn')),
  status text not null default 'active'
    check (status in ('active','realized','superseded','withdrawn')),
  source_event_id uuid references atlas.person_life_events(id) on delete restrict,
  effective_at timestamptz not null default now(),
  expires_at timestamptz,
  last_evaluation jsonb,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_user_id, stable_key),
  check (authorization_state <> 'accepted' or source_event_id is not null),
  check (expires_at is null or expires_at >= effective_at)
);

create table if not exists atlas.person_life_goal_requirements (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references atlas.person_life_goals(id) on delete cascade,
  person_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null,
  label text not null,
  requirement_packet jsonb not null check (jsonb_typeof(requirement_packet)='object'),
  authorization_state text not null default 'proposed'
    check (authorization_state in ('proposed','accepted','rejected','superseded','withdrawn')),
  status text not null default 'active'
    check (status in ('active','satisfied','superseded','withdrawn','expired')),
  source_event_id uuid references atlas.person_life_events(id) on delete restrict,
  window_start timestamptz,
  window_end timestamptz,
  must_begin_by timestamptz,
  must_finish_by timestamptz,
  expected_minutes integer check (expected_minutes is null or expected_minutes > 0),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (goal_id, stable_key),
  check (authorization_state <> 'accepted' or source_event_id is not null),
  check (window_end is null or window_start is null or window_end >= window_start),
  check (must_finish_by is null or must_begin_by is null or must_finish_by >= must_begin_by)
);

create table if not exists atlas.person_life_consequence_policies (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null,
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  policy_packet jsonb not null check (jsonb_typeof(policy_packet)='object'),
  authorization_state text not null default 'proposed'
    check (authorization_state in ('proposed','accepted','rejected','superseded','withdrawn')),
  active boolean not null default true,
  source_event_id uuid references atlas.person_life_events(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_user_id, stable_key),
  check (authorization_state <> 'accepted' or source_event_id is not null)
);

create table if not exists atlas.person_life_consequence_instances (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null,
  policy_id uuid not null references atlas.person_life_consequence_policies(id) on delete restrict,
  source_event_id uuid not null references atlas.person_life_events(id) on delete restrict,
  source_requirement_id uuid references atlas.person_life_goal_requirements(id) on delete restrict,
  consequence_role text not null
    check (consequence_role in ('operation_requirement','truth_acquisition','repair','preparation')),
  consequence_kind text,
  action_key text,
  requirement_state text not null default 'established',
  carrier_ref text,
  carrier_state text not null default 'unresolved',
  placement_state text not null default 'unresolved',
  execution_readiness text not null default 'not_evaluated',
  consequence_packet jsonb not null check (jsonb_typeof(consequence_packet)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (person_user_id, stable_key)
);

create table if not exists atlas.person_life_rhythm_bindings (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null,
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  rhythm_packet jsonb not null
    check (jsonb_typeof(rhythm_packet)='object' and rhythm_packet->>'contractVersion'='life_rhythm_packet_v1'),
  authorization_state text not null default 'proposed'
    check (authorization_state in ('proposed','accepted','rejected','superseded','withdrawn')),
  status text not null default 'active'
    check (status in ('active','superseded','withdrawn')),
  source_event_id uuid references atlas.person_life_events(id) on delete restrict,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_user_id, stable_key),
  check (authorization_state <> 'accepted' or source_event_id is not null)
);

create table if not exists atlas.person_life_rhythm_state (
  binding_id uuid primary key references atlas.person_life_rhythm_bindings(id) on delete cascade,
  person_user_id uuid not null references auth.users(id) on delete cascade,
  last_satisfied_at timestamptz,
  evaluated_at timestamptz not null default now(),
  state_packet jsonb not null check (jsonb_typeof(state_packet)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  updated_at timestamptz not null default now()
);

create table if not exists atlas.person_life_clock_claims (
  id uuid primary key default gen_random_uuid(),
  person_user_id uuid not null references auth.users(id) on delete cascade,
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  stable_key text not null,
  consequence_instance_id uuid not null references atlas.person_life_consequence_instances(id) on delete restrict,
  requirement_id uuid not null references atlas.person_life_goal_requirements(id) on delete restrict,
  domain text not null default 'life',
  title text not null,
  eligibility_state text not null default 'eligible'
    check (eligibility_state in ('eligible','deferred','withdrawn','expired','consumed')),
  floor_class smallint not null check (floor_class in (1,2,3,4,5,6,7)),
  window_start timestamptz,
  window_end timestamptz,
  fixed_start timestamptz,
  must_begin_by timestamptz,
  must_finish_by timestamptz,
  expected_minutes integer check (expected_minutes is null or expected_minutes > 0),
  protection_level text not null check (protection_level in ('critical','protected','standard','optional')),
  interruptibility text not null,
  delegable boolean not null default false,
  owner_required boolean not null default true,
  consequence text,
  reason_for_floor text not null,
  temporal_claim jsonb not null check (jsonb_typeof(temporal_claim)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (person_user_id, stable_key)
);

create index if not exists person_life_events_person_time_idx
  on atlas.person_life_events(person_user_id, occurred_at desc);
create index if not exists person_life_event_subjects_subject_idx
  on atlas.person_life_event_subjects(subject_domain, subject_kind, subject_id, event_id);
create index if not exists person_life_goals_person_status_idx
  on atlas.person_life_goals(person_user_id, status, authorization_state);
create index if not exists person_life_requirements_person_status_idx
  on atlas.person_life_goal_requirements(person_user_id, status, authorization_state);
create index if not exists person_life_consequence_instances_person_state_idx
  on atlas.person_life_consequence_instances(person_user_id, placement_state, requirement_state);
create index if not exists person_life_clock_claims_principal_state_idx
  on atlas.person_life_clock_claims(principal_id, eligibility_state, must_finish_by);

alter table atlas.person_life_events enable row level security;
alter table atlas.person_life_event_subjects enable row level security;
alter table atlas.person_life_event_relations enable row level security;
alter table atlas.person_life_goals enable row level security;
alter table atlas.person_life_goal_requirements enable row level security;
alter table atlas.person_life_consequence_policies enable row level security;
alter table atlas.person_life_consequence_instances enable row level security;
alter table atlas.person_life_rhythm_bindings enable row level security;
alter table atlas.person_life_rhythm_state enable row level security;
alter table atlas.person_life_clock_claims enable row level security;

drop policy if exists person_life_events_owner_read on atlas.person_life_events;
create policy person_life_events_owner_read on atlas.person_life_events
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_event_subjects_owner_read on atlas.person_life_event_subjects;
create policy person_life_event_subjects_owner_read on atlas.person_life_event_subjects
for select to authenticated using (
  exists (select 1 from atlas.person_life_events e where e.id=event_id and e.person_user_id=auth.uid())
);

drop policy if exists person_life_event_relations_owner_read on atlas.person_life_event_relations;
create policy person_life_event_relations_owner_read on atlas.person_life_event_relations
for select to authenticated using (
  exists (select 1 from atlas.person_life_events e where e.id=from_event_id and e.person_user_id=auth.uid())
  and exists (select 1 from atlas.person_life_events e where e.id=to_event_id and e.person_user_id=auth.uid())
);

drop policy if exists person_life_goals_owner_read on atlas.person_life_goals;
create policy person_life_goals_owner_read on atlas.person_life_goals
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_goal_requirements_owner_read on atlas.person_life_goal_requirements;
create policy person_life_goal_requirements_owner_read on atlas.person_life_goal_requirements
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_consequence_policies_owner_read on atlas.person_life_consequence_policies;
create policy person_life_consequence_policies_owner_read on atlas.person_life_consequence_policies
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_consequence_instances_owner_read on atlas.person_life_consequence_instances;
create policy person_life_consequence_instances_owner_read on atlas.person_life_consequence_instances
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_rhythm_bindings_owner_read on atlas.person_life_rhythm_bindings;
create policy person_life_rhythm_bindings_owner_read on atlas.person_life_rhythm_bindings
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_rhythm_state_owner_read on atlas.person_life_rhythm_state;
create policy person_life_rhythm_state_owner_read on atlas.person_life_rhythm_state
for select to authenticated using (person_user_id=auth.uid());

drop policy if exists person_life_clock_claims_owner_read on atlas.person_life_clock_claims;
create policy person_life_clock_claims_owner_read on atlas.person_life_clock_claims
for select to authenticated using (person_user_id=auth.uid());

create or replace function atlas.person_life_event_immutable_guard_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog
as $$
begin
  raise exception 'person_life_events are append-only; correct with a new event.' using errcode='55000';
end;
$$;

drop trigger if exists person_life_events_immutable on atlas.person_life_events;
create trigger person_life_events_immutable
before update or delete on atlas.person_life_events
for each row execute function atlas.person_life_event_immutable_guard_v1();

create or replace function atlas.record_person_life_event_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
  v_source_kind text:=btrim(coalesce(p_payload->>'sourceKind',''));
  v_source_key text:=btrim(coalesce(p_payload->>'sourceKey',''));
  v_event_kind text:=btrim(coalesce(p_payload->>'eventKind',''));
  v_claim_state text:=coalesce(nullif(btrim(p_payload->>'claimState'),''),'reported');
  v_authority_kind text:=coalesce(nullif(btrim(p_payload->>'authorityKind'),''),'first_party');
  v_occurred_at timestamptz;
  v_subject jsonb;
  v_relation jsonb;
  v_to_event uuid;
  v_existing atlas.person_life_events%rowtype;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception 'payload object required.' using errcode='22023'; end if;
  if v_source_kind='' or v_source_key='' or v_event_kind='' then
    raise exception 'sourceKind, sourceKey, and eventKind are required.' using errcode='22023';
  end if;
  if v_claim_state not in ('reported','observed','accepted','proposed','rejected','superseded','expired','unknown') then
    raise exception 'Unsupported claimState.' using errcode='22023';
  end if;
  if nullif(p_payload->>'occurredAt','') is null then
    raise exception 'occurredAt is required for replayable person-life events.' using errcode='22023';
  end if;
  v_occurred_at:=(p_payload->>'occurredAt')::timestamptz;
  if jsonb_typeof(coalesce(p_payload->'subjects','[]'::jsonb))<>'array' then
    raise exception 'subjects must be an array.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_payload->'relations','[]'::jsonb))<>'array' then
    raise exception 'relations must be an array.' using errcode='22023';
  end if;

  insert into atlas.person_life_events(
    person_user_id,actor_user_id,source_kind,source_key,source_record_id,event_kind,
    claim_state,authority_kind,occurred_at,payload,provenance,metadata
  ) values (
    v_user,v_user,v_source_kind,v_source_key,nullif(p_payload->>'sourceRecordId','')::uuid,v_event_kind,
    v_claim_state,v_authority_kind,v_occurred_at,coalesce(p_payload->'payload','{}'::jsonb),
    coalesce(p_payload->'provenance','{}'::jsonb),coalesce(p_payload->'metadata','{}'::jsonb)
  ) on conflict (person_user_id,source_kind,source_key) do nothing
  returning id into v_id;

  if v_id is null then
    select * into v_existing from atlas.person_life_events
    where person_user_id=v_user and source_kind=v_source_kind and source_key=v_source_key;
    if v_existing.id is null
       or v_existing.event_kind is distinct from v_event_kind
       or v_existing.claim_state is distinct from v_claim_state
       or v_existing.authority_kind is distinct from v_authority_kind
       or v_existing.occurred_at is distinct from v_occurred_at
       or v_existing.payload is distinct from coalesce(p_payload->'payload','{}'::jsonb) then
      raise exception 'sourceKey retry does not match existing person-life event.' using errcode='23505';
    end if;
    v_id:=v_existing.id;
  end if;

  for v_subject in select value from jsonb_array_elements(coalesce(p_payload->'subjects','[]'::jsonb)) loop
    if btrim(coalesce(v_subject->>'domain',''))='' or btrim(coalesce(v_subject->>'kind',''))='' or btrim(coalesce(v_subject->>'id',''))='' then
      raise exception 'Each subject requires domain, kind, and id.' using errcode='22023';
    end if;
    insert into atlas.person_life_event_subjects(event_id,subject_domain,subject_kind,subject_id,relation_kind,provenance,metadata)
    values (v_id,btrim(v_subject->>'domain'),btrim(v_subject->>'kind'),btrim(v_subject->>'id'),
      coalesce(nullif(btrim(v_subject->>'relationKind'),''),'about'),
      coalesce(v_subject->'provenance','{}'::jsonb),coalesce(v_subject->'metadata','{}'::jsonb))
    on conflict do nothing;
  end loop;

  for v_relation in select value from jsonb_array_elements(coalesce(p_payload->'relations','[]'::jsonb)) loop
    v_to_event:=nullif(v_relation->>'toEventId','')::uuid;
    if v_to_event is null or btrim(coalesce(v_relation->>'relationKind',''))='' then
      raise exception 'Each relation requires toEventId and relationKind.' using errcode='22023';
    end if;
    if not exists(select 1 from atlas.person_life_events e where e.id=v_to_event and e.person_user_id=v_user) then
      raise exception 'Related event is outside person custody.' using errcode='42501';
    end if;
    insert into atlas.person_life_event_relations(from_event_id,to_event_id,relation_kind,provenance,metadata)
    values(v_id,v_to_event,btrim(v_relation->>'relationKind'),coalesce(v_relation->'provenance','{}'::jsonb),coalesce(v_relation->'metadata','{}'::jsonb))
    on conflict do nothing;
  end loop;

  return jsonb_build_object('ok',true,'eventId',v_id,'personUserId',v_user,'claimState',v_claim_state,'authorityKind',v_authority_kind);
end;
$$;

create or replace function atlas.upsert_person_life_goal_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
  v_key text:=btrim(coalesce(p_payload->>'stableKey',''));
  v_title text:=btrim(coalesce(p_payload->>'title',''));
  v_auth text:=coalesce(nullif(btrim(p_payload->>'authorizationState'),''),'proposed');
  v_packet jsonb:=coalesce(p_payload->'goalPacket','{}'::jsonb);
  v_source uuid:=nullif(p_payload->>'sourceEventId','')::uuid;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_key='' or v_title='' then raise exception 'stableKey and title are required.' using errcode='22023'; end if;
  if jsonb_typeof(v_packet)<>'object' or v_packet->>'contractVersion'<>'life_goal_packet_v1' then
    raise exception 'life_goal_packet_v1 is required.' using errcode='22023';
  end if;
  if jsonb_array_length(coalesce(v_packet->'requirements','[]'::jsonb))<>0 then
    raise exception 'Persisted person goals cannot embed requirements; authorize requirements separately.' using errcode='22023';
  end if;
  if v_auth not in ('proposed','accepted','rejected','superseded','withdrawn') then raise exception 'Unsupported authorizationState.' using errcode='22023'; end if;
  if v_source is not null and not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user) then
    raise exception 'sourceEventId is outside person custody.' using errcode='42501';
  end if;
  if v_auth='accepted' and (v_source is null or not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user and e.claim_state='accepted')) then
    raise exception 'Accepted goal requires an accepted first-party source event.' using errcode='22023';
  end if;

  insert into atlas.person_life_goals(person_user_id,stable_key,title,goal_packet,authorization_state,status,source_event_id,effective_at,expires_at,provenance,metadata)
  values(v_user,v_key,v_title,v_packet,v_auth,coalesce(nullif(p_payload->>'status',''),'active'),v_source,
    coalesce(nullif(p_payload->>'effectiveAt','')::timestamptz,now()),nullif(p_payload->>'expiresAt','')::timestamptz,
    coalesce(p_payload->'provenance','{}'::jsonb),coalesce(p_payload->'metadata','{}'::jsonb))
  on conflict(person_user_id,stable_key) do update set
    title=excluded.title, goal_packet=excluded.goal_packet, authorization_state=excluded.authorization_state,
    status=excluded.status, source_event_id=excluded.source_event_id, effective_at=excluded.effective_at,
    expires_at=excluded.expires_at, provenance=excluded.provenance, metadata=excluded.metadata, updated_at=now()
  returning id into v_id;

  return jsonb_build_object('ok',true,'goalId',v_id,'authorizationState',v_auth);
end;
$$;

create or replace function atlas.upsert_person_life_goal_requirement_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
  v_goal uuid:=nullif(p_payload->>'goalId','')::uuid;
  v_key text:=btrim(coalesce(p_payload->>'stableKey',''));
  v_label text:=btrim(coalesce(p_payload->>'label',''));
  v_auth text:=coalesce(nullif(btrim(p_payload->>'authorizationState'),''),'proposed');
  v_packet jsonb:=coalesce(p_payload->'requirementPacket','{}'::jsonb);
  v_source uuid:=nullif(p_payload->>'sourceEventId','')::uuid;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_goal is null or v_key='' or v_label='' then raise exception 'goalId, stableKey, and label are required.' using errcode='22023'; end if;
  if jsonb_typeof(v_packet)<>'object' then raise exception 'requirementPacket must be an object.' using errcode='22023'; end if;
  if coalesce(v_packet->>'requirementKey',v_packet->>'requirement_key','')<>v_key then
    raise exception 'requirementPacket.requirementKey must equal stableKey.' using errcode='22023';
  end if;
  if not exists(select 1 from atlas.person_life_goals g where g.id=v_goal and g.person_user_id=v_user) then raise exception 'Goal outside person custody.' using errcode='42501'; end if;
  if v_source is not null and not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user) then raise exception 'sourceEventId outside person custody.' using errcode='42501'; end if;
  if v_auth='accepted' then
    if not exists(select 1 from atlas.person_life_goals g where g.id=v_goal and g.person_user_id=v_user and g.authorization_state='accepted' and g.status='active') then
      raise exception 'Accepted requirement requires an accepted active goal.' using errcode='22023';
    end if;
    if v_source is null or not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user and e.claim_state='accepted') then
      raise exception 'Accepted requirement requires an accepted first-party source event.' using errcode='22023';
    end if;
  end if;

  insert into atlas.person_life_goal_requirements(goal_id,person_user_id,stable_key,label,requirement_packet,authorization_state,status,source_event_id,
    window_start,window_end,must_begin_by,must_finish_by,expected_minutes,provenance,metadata)
  values(v_goal,v_user,v_key,v_label,v_packet,v_auth,coalesce(nullif(p_payload->>'status',''),'active'),v_source,
    nullif(p_payload->>'windowStart','')::timestamptz,nullif(p_payload->>'windowEnd','')::timestamptz,
    nullif(p_payload->>'mustBeginBy','')::timestamptz,nullif(p_payload->>'mustFinishBy','')::timestamptz,
    nullif(p_payload->>'expectedMinutes','')::integer,coalesce(p_payload->'provenance','{}'::jsonb),coalesce(p_payload->'metadata','{}'::jsonb))
  on conflict(goal_id,stable_key) do update set
    label=excluded.label, requirement_packet=excluded.requirement_packet, authorization_state=excluded.authorization_state,
    status=excluded.status, source_event_id=excluded.source_event_id, window_start=excluded.window_start, window_end=excluded.window_end,
    must_begin_by=excluded.must_begin_by, must_finish_by=excluded.must_finish_by, expected_minutes=excluded.expected_minutes,
    provenance=excluded.provenance, metadata=excluded.metadata, updated_at=now()
  returning id into v_id;

  return jsonb_build_object('ok',true,'requirementId',v_id,'authorizationState',v_auth);
end;
$$;

create or replace function atlas.evaluate_person_life_goal_v1(p_goal_id uuid,p_requirement_results jsonb default '[]'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_goal atlas.person_life_goals%rowtype;
  v_requirements jsonb;
  v_packet jsonb;
  v_result jsonb;
begin
  select * into v_goal from atlas.person_life_goals g where g.id=p_goal_id and (v_user is null or g.person_user_id=v_user);
  if v_goal.id is null then raise exception 'Goal not found in person custody.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(r.requirement_packet order by r.stable_key),'[]'::jsonb) into v_requirements
  from atlas.person_life_goal_requirements r
  where r.goal_id=v_goal.id and r.authorization_state='accepted' and r.status in ('active','satisfied');
  v_packet:=jsonb_set(v_goal.goal_packet,'{requirements}',v_requirements,true);
  v_result:=atlas.evaluate_life_goal_state_v1(v_packet,coalesce(p_requirement_results,'[]'::jsonb));
  return v_result || jsonb_build_object('persistenceBoundary',jsonb_build_object(
    'goalAuthorizationState',v_goal.authorization_state,
    'onlyAcceptedPersistedRequirementsWereEvaluated',true,
    'evaluationWasNotPersistedAsEvidence',true
  ));
end;
$$;

create or replace function atlas.upsert_person_life_consequence_policy_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
  v_key text:=btrim(coalesce(p_payload->>'stableKey',''));
  v_domain text:=btrim(coalesce(p_payload->>'subjectDomain',''));
  v_kind text:=btrim(coalesce(p_payload->>'subjectKind',''));
  v_subject text:=btrim(coalesce(p_payload->>'subjectId',''));
  v_auth text:=coalesce(nullif(btrim(p_payload->>'authorizationState'),''),'proposed');
  v_packet jsonb:=coalesce(p_payload->'policyPacket','{}'::jsonb);
  v_source uuid:=nullif(p_payload->>'sourceEventId','')::uuid;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if v_key='' or v_domain='' or v_kind='' or v_subject='' then raise exception 'stableKey and subject identity are required.' using errcode='22023'; end if;
  if jsonb_typeof(v_packet)<>'object' or coalesce(v_packet->>'stableKey',v_packet->>'stable_key','')<>v_key then
    raise exception 'policyPacket stableKey must equal stableKey.' using errcode='22023';
  end if;
  if v_auth not in ('proposed','accepted','rejected','superseded','withdrawn') then raise exception 'Unsupported authorizationState.' using errcode='22023'; end if;
  if v_source is not null and not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user) then raise exception 'sourceEventId outside person custody.' using errcode='42501'; end if;
  if v_auth='accepted' and (v_source is null or not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user and e.claim_state='accepted')) then
    raise exception 'Accepted consequence policy requires an accepted first-party source event.' using errcode='22023';
  end if;

  insert into atlas.person_life_consequence_policies(person_user_id,stable_key,subject_domain,subject_kind,subject_id,policy_packet,authorization_state,active,source_event_id,provenance,metadata)
  values(v_user,v_key,v_domain,v_kind,v_subject,v_packet,v_auth,coalesce((p_payload->>'active')::boolean,true),v_source,
    coalesce(p_payload->'provenance','{}'::jsonb),coalesce(p_payload->'metadata','{}'::jsonb))
  on conflict(person_user_id,stable_key) do update set
    subject_domain=excluded.subject_domain,subject_kind=excluded.subject_kind,subject_id=excluded.subject_id,
    policy_packet=excluded.policy_packet,authorization_state=excluded.authorization_state,active=excluded.active,
    source_event_id=excluded.source_event_id,provenance=excluded.provenance,metadata=excluded.metadata,updated_at=now()
  returning id into v_id;

  return jsonb_build_object('ok',true,'policyId',v_id,'authorizationState',v_auth);
end;
$$;

create or replace function atlas.reconcile_person_life_consequences_api_v1(p_source_event_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_event atlas.person_life_events%rowtype;
  v_policies jsonb;
  v_eval jsonb;
  v_match jsonb;
  v_policy atlas.person_life_consequence_policies%rowtype;
  v_instance uuid;
  v_ids jsonb:='[]'::jsonb;
  v_count integer:=0;
  v_carrier_requirement uuid;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_event from atlas.person_life_events e where e.id=p_source_event_id and e.person_user_id=v_user;
  if v_event.id is null then raise exception 'Source event outside person custody.' using errcode='42501'; end if;
  if jsonb_typeof(v_event.payload->'snapshot')<>'object' then raise exception 'Source event payload.snapshot is required.' using errcode='22023'; end if;

  select coalesce(jsonb_agg(p.policy_packet order by p.stable_key),'[]'::jsonb) into v_policies
  from atlas.person_life_consequence_policies p
  where p.person_user_id=v_user and p.authorization_state='accepted' and p.active;

  v_eval:=atlas.evaluate_life_state_consequence_policies_v1(v_event.payload->'snapshot',v_policies);

  for v_match in select value from jsonb_array_elements(coalesce(v_eval->'openConsequences','[]'::jsonb)) loop
    select * into v_policy from atlas.person_life_consequence_policies p
      where p.person_user_id=v_user and p.stable_key=v_match->>'stableKey' and p.authorization_state='accepted' and p.active limit 1;
    if v_policy.id is null then continue; end if;
    v_carrier_requirement:=null;
    begin
      if nullif(v_match->>'carrierRef','') is not null then v_carrier_requirement:=(v_match->>'carrierRef')::uuid; end if;
    exception when invalid_text_representation then
      v_carrier_requirement:=null;
    end;
    if v_carrier_requirement is not null and not exists(select 1 from atlas.person_life_goal_requirements r where r.id=v_carrier_requirement and r.person_user_id=v_user) then
      v_carrier_requirement:=null;
    end if;

    insert into atlas.person_life_consequence_instances(
      person_user_id,stable_key,policy_id,source_event_id,source_requirement_id,consequence_role,consequence_kind,action_key,
      requirement_state,carrier_ref,carrier_state,placement_state,execution_readiness,consequence_packet,provenance,metadata
    ) values (
      v_user,v_policy.stable_key||':'||v_event.id::text,v_policy.id,v_event.id,v_carrier_requirement,
      v_match->>'consequenceRole',v_match->>'consequenceKind',v_match->>'actionKey',
      coalesce(v_match->>'requirementState','established'),v_match->>'carrierRef',coalesce(v_match->>'carrierState','unresolved'),
      'unresolved',coalesce(v_match->>'executionReadiness','not_evaluated'),v_match,
      jsonb_build_object('sourceEventId',v_event.id,'policyId',v_policy.id,'evaluator','atlas.evaluate_life_state_consequence_policies_v1'),
      '{}'::jsonb
    ) on conflict(person_user_id,stable_key) do update set
      consequence_packet=excluded.consequence_packet,carrier_ref=excluded.carrier_ref,carrier_state=excluded.carrier_state,
      source_requirement_id=excluded.source_requirement_id,updated_at=now()
    returning id into v_instance;
    v_ids:=v_ids||jsonb_build_array(v_instance);
    v_count:=v_count+1;
  end loop;

  return jsonb_build_object('ok',true,'sourceEventId',v_event.id,'evaluation',v_eval,'persistedConsequenceIds',v_ids,'persistedCount',v_count,
    'truthBoundary',jsonb_build_object('sourceSnapshotWasCapturedEvidence',true,'onlyAcceptedPoliciesWereEvaluated',true,'noTaskWasCreated',true,'noClockClaimWasCreated',true));
end;
$$;

create or replace function atlas.upsert_person_life_rhythm_binding_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
  v_source uuid:=nullif(p_payload->>'sourceEventId','')::uuid;
  v_auth text:=coalesce(nullif(p_payload->>'authorizationState',''),'proposed');
  v_packet jsonb:=coalesce(p_payload->'rhythmPacket','{}'::jsonb);
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if btrim(coalesce(p_payload->>'stableKey',''))='' or btrim(coalesce(p_payload->>'subjectDomain',''))='' or btrim(coalesce(p_payload->>'subjectKind',''))='' or btrim(coalesce(p_payload->>'subjectId',''))='' then
    raise exception 'stableKey and subject identity are required.' using errcode='22023';
  end if;
  if jsonb_typeof(v_packet)<>'object' or v_packet->>'contractVersion'<>'life_rhythm_packet_v1' then raise exception 'life_rhythm_packet_v1 is required.' using errcode='22023'; end if;
  if v_auth='accepted' and (v_source is null or not exists(select 1 from atlas.person_life_events e where e.id=v_source and e.person_user_id=v_user and e.claim_state='accepted')) then
    raise exception 'Accepted rhythm requires an accepted first-party source event.' using errcode='22023';
  end if;
  insert into atlas.person_life_rhythm_bindings(person_user_id,stable_key,subject_domain,subject_kind,subject_id,rhythm_packet,authorization_state,status,source_event_id,provenance,metadata)
  values(v_user,btrim(p_payload->>'stableKey'),btrim(p_payload->>'subjectDomain'),btrim(p_payload->>'subjectKind'),btrim(p_payload->>'subjectId'),v_packet,v_auth,
    coalesce(nullif(p_payload->>'status',''),'active'),v_source,coalesce(p_payload->'provenance','{}'::jsonb),coalesce(p_payload->'metadata','{}'::jsonb))
  on conflict(person_user_id,stable_key) do update set rhythm_packet=excluded.rhythm_packet,authorization_state=excluded.authorization_state,status=excluded.status,
    source_event_id=excluded.source_event_id,provenance=excluded.provenance,metadata=excluded.metadata,updated_at=now()
  returning id into v_id;
  return jsonb_build_object('ok',true,'bindingId',v_id,'authorizationState',v_auth);
end;
$$;

create or replace function atlas.evaluate_person_life_rhythm_api_v1(p_binding_id uuid,p_last_satisfied_at timestamptz default null,p_as_of timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_binding atlas.person_life_rhythm_bindings%rowtype;
  v_eval jsonb;
begin
  select * into v_binding from atlas.person_life_rhythm_bindings b where b.id=p_binding_id and (v_user is null or b.person_user_id=v_user);
  if v_binding.id is null then raise exception 'Rhythm binding not found in person custody.' using errcode='42501'; end if;
  if v_binding.authorization_state<>'accepted' or v_binding.status<>'active' then raise exception 'Only accepted active rhythms may update runtime state.' using errcode='22023'; end if;
  v_eval:=atlas.evaluate_life_lease_rhythm_v1(v_binding.rhythm_packet,p_last_satisfied_at,p_as_of);
  insert into atlas.person_life_rhythm_state(binding_id,person_user_id,last_satisfied_at,evaluated_at,state_packet,provenance,metadata)
  values(v_binding.id,v_binding.person_user_id,p_last_satisfied_at,coalesce(p_as_of,now()),v_eval,jsonb_build_object('evaluator','atlas.evaluate_life_lease_rhythm_v1'),'{}'::jsonb)
  on conflict(binding_id) do update set last_satisfied_at=excluded.last_satisfied_at,evaluated_at=excluded.evaluated_at,state_packet=excluded.state_packet,
    provenance=excluded.provenance,updated_at=now();
  return v_eval||jsonb_build_object('persistenceBoundary',jsonb_build_object('doesNotCreateTask',true,'doesNotCreateClockClaim',true));
end;
$$;

create or replace function atlas.claim_person_life_consequence_for_clock_api_v1(p_consequence_instance_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_consequence atlas.person_life_consequence_instances%rowtype;
  v_policy atlas.person_life_consequence_policies%rowtype;
  v_requirement atlas.person_life_goal_requirements%rowtype;
  v_goal atlas.person_life_goals%rowtype;
  v_principal uuid;
  v_action jsonb;
  v_relation text;
  v_deadline timestamptz;
  v_floor smallint;
  v_expected integer;
  v_title text;
  v_protection text;
  v_interruptibility text;
  v_claim uuid;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_consequence from atlas.person_life_consequence_instances c where c.id=p_consequence_instance_id and c.person_user_id=v_user;
  if v_consequence.id is null then raise exception 'Consequence outside person custody.' using errcode='42501'; end if;
  if v_consequence.requirement_state<>'established' then raise exception 'Clock claim requires established consequence requirement.' using errcode='22023'; end if;
  if v_consequence.source_requirement_id is null then raise exception 'Observation cannot enter Clock directly; an accepted carrier requirement is required.' using errcode='22023'; end if;

  select * into v_policy from atlas.person_life_consequence_policies p where p.id=v_consequence.policy_id and p.person_user_id=v_user;
  if v_policy.id is null or v_policy.authorization_state<>'accepted' or not v_policy.active then raise exception 'Clock claim requires an accepted active consequence policy.' using errcode='22023'; end if;
  select * into v_requirement from atlas.person_life_goal_requirements r where r.id=v_consequence.source_requirement_id and r.person_user_id=v_user;
  if v_requirement.id is null or v_requirement.authorization_state<>'accepted' or v_requirement.status<>'active' then raise exception 'Clock claim requires an accepted active requirement.' using errcode='22023'; end if;
  select * into v_goal from atlas.person_life_goals g where g.id=v_requirement.goal_id and g.person_user_id=v_user;
  if v_goal.id is null or v_goal.authorization_state<>'accepted' or v_goal.status<>'active' then raise exception 'Clock claim requires an accepted active goal.' using errcode='22023'; end if;
  select p.id into v_principal from atlas.principals p where p.user_id=v_user and p.status='active';
  if v_principal is null then raise exception 'Active Principal identity required for Clock arbitration.' using errcode='22023'; end if;

  v_action:=coalesce(v_policy.policy_packet->'actionSpec','{}'::jsonb);
  if coalesce((v_action->>'clockEligible')::boolean,false) is not true then raise exception 'Accepted policy does not grant Clock eligibility.' using errcode='22023'; end if;
  if coalesce(v_action->>'carrierRef','')<>v_requirement.id::text then raise exception 'Accepted policy carrierRef does not match the persisted requirement.' using errcode='22023'; end if;
  v_relation:=coalesce(v_action->>'temporalRelation','');
  if v_relation<>'before_carrier_start' then raise exception 'Person-life Clock v1 only admits explicit before_carrier_start temporal claims.' using errcode='22023'; end if;
  v_deadline:=coalesce(v_requirement.must_begin_by,v_requirement.window_start,v_requirement.must_finish_by);
  if v_deadline is null then raise exception 'Carrier requirement has no temporal start boundary.' using errcode='22023'; end if;

  begin v_floor:=(v_action->>'floorClass')::smallint; exception when others then v_floor:=null; end;
  if v_floor not in (1,2,3,4,5,6,7) then raise exception 'Accepted policy must provide a valid floorClass.' using errcode='22023'; end if;
  begin v_expected:=(v_action->>'expectedMinutes')::integer; exception when others then v_expected:=null; end;
  if v_expected is not null and v_expected<=0 then raise exception 'expectedMinutes must be positive.' using errcode='22023'; end if;
  v_title:=nullif(btrim(v_action->>'title'),'');
  v_protection:=nullif(btrim(v_action->>'protectionLevel'),'');
  v_interruptibility:=nullif(btrim(v_action->>'interruptibility'),'');
  if v_title is null or v_protection not in ('critical','protected','standard','optional') or v_interruptibility is null or nullif(btrim(v_action->>'reasonForFloor'),'') is null then
    raise exception 'Accepted policy must provide title, protectionLevel, interruptibility, and reasonForFloor.' using errcode='22023';
  end if;

  insert into atlas.person_life_clock_claims(
    person_user_id,principal_id,stable_key,consequence_instance_id,requirement_id,domain,title,eligibility_state,floor_class,
    window_start,window_end,fixed_start,must_begin_by,must_finish_by,expected_minutes,protection_level,interruptibility,
    delegable,owner_required,consequence,reason_for_floor,temporal_claim,provenance,metadata
  ) values (
    v_user,v_principal,'consequence:'||v_consequence.id::text,v_consequence.id,v_requirement.id,
    coalesce(nullif(v_action->>'domain',''),'life'),v_title,'eligible',v_floor,
    v_consequence.created_at,v_deadline,null,v_deadline,v_deadline,v_expected,v_protection,v_interruptibility,
    false,true,nullif(v_action->>'consequence',''),v_action->>'reasonForFloor',
    jsonb_build_object('relation',v_relation,'carrierRequirementId',v_requirement.id,'deadline',v_deadline,'sourcePolicyId',v_policy.id),
    jsonb_build_object('consequenceInstanceId',v_consequence.id,'policyId',v_policy.id,'requirementId',v_requirement.id,'goalId',v_goal.id),
    jsonb_build_object('subjectDomain',v_policy.subject_domain,'subjectKind',v_policy.subject_kind,'subjectId',v_policy.subject_id)
  ) on conflict(person_user_id,stable_key) do update set
    principal_id=excluded.principal_id,title=excluded.title,eligibility_state='eligible',floor_class=excluded.floor_class,
    window_start=excluded.window_start,window_end=excluded.window_end,must_begin_by=excluded.must_begin_by,must_finish_by=excluded.must_finish_by,
    expected_minutes=excluded.expected_minutes,protection_level=excluded.protection_level,interruptibility=excluded.interruptibility,
    consequence=excluded.consequence,reason_for_floor=excluded.reason_for_floor,temporal_claim=excluded.temporal_claim,
    provenance=excluded.provenance,metadata=excluded.metadata,updated_at=now()
  returning id into v_claim;

  update atlas.person_life_consequence_instances set placement_state='eligible',updated_at=now() where id=v_consequence.id;
  return jsonb_build_object('ok',true,'clockClaimId',v_claim,'principalId',v_principal,'eligibilityState','eligible',
    'truthBoundary',jsonb_build_object('observationDidNotCreateClockClaimDirectly',true,'acceptedPolicyEstablishedConsequence',true,'acceptedRequirementCarriedTiming',true,'noTaskWasCreated',true));
end;
$$;

create or replace view atlas.person_life_clock_candidates_v1 as
select
  c.principal_id,
  c.domain,
  'person_life_consequence'::text as source_type,
  c.id as source_id,
  c.title,
  c.floor_class,
  c.window_start,
  c.window_end,
  c.fixed_start,
  c.must_begin_by,
  c.must_finish_by,
  c.expected_minutes,
  c.protection_level,
  c.interruptibility,
  c.delegable,
  c.owner_required,
  c.consequence,
  c.reason_for_floor,
  null::uuid as portfolio_unit_id,
  null::text as horizon,
  c.metadata || jsonb_build_object(
    'personUserId',c.person_user_id,
    'consequenceInstanceId',c.consequence_instance_id,
    'requirementId',c.requirement_id,
    'temporalClaim',c.temporal_claim,
    'provenance',c.provenance
  ) as metadata
from atlas.person_life_clock_claims c
join atlas.principals p on p.id=c.principal_id and p.user_id=c.person_user_id and p.status='active'
where c.eligibility_state='eligible';

create or replace view atlas.principal_clock_candidates_v1 as
select o.principal_id,o.domain,'owner_obligation'::text as source_type,o.id as source_id,o.title,o.floor_class,
  o.becomes_relevant_at as window_start,coalesce(o.expires_at,o.must_finish_by) as window_end,o.fixed_at as fixed_start,
  o.must_begin_by,o.must_finish_by,o.expected_minutes,o.protection_level,o.interruptibility,o.delegable,o.owner_required,
  o.consequence_of_delay as consequence,o.reason_for_floor,o.portfolio_unit_id,o.horizon,o.metadata
from atlas.owner_obligations o where o.status=any(array['open'::text,'in_progress'::text])
union all
select h.principal_id,'household'::text,'household_event'::text,e.id,e.title,e.floor_class,e.starts_at,e.ends_at,
  case when e.fixed then e.starts_at else null::timestamptz end,null::timestamptz,e.ends_at,
  coalesce(e.expected_minutes,greatest(1,round(extract(epoch from e.ends_at-e.starts_at)/60.0)::integer)),
  e.protection_level,e.interruptibility,false,e.principal_required,e.consequence,e.reason_for_floor,null::uuid,null::text,e.metadata
from atlas.household_events e join atlas.households h on h.id=e.household_id where e.principal_required
union all
select h.principal_id,'household'::text,'household_rhythm'::text,r.id,r.title,r.floor_class,r.next_window_start,r.next_window_end,
  null::timestamptz,r.next_window_start,r.next_window_end,r.expected_minutes,r.protection_level,r.interruptibility,false,r.principal_required,
  r.consequence,r.reason_for_floor,null::uuid,null::text,r.metadata
from atlas.household_rhythms r join atlas.households h on h.id=r.household_id where r.active and r.principal_required and r.next_window_start is not null
union all
select e.principal_id,'operations'::text,'operational_escalation'::text,e.id,initcap(replace(e.escalation_kind,'_',' ')),e.floor_class,
  e.window_start,e.window_end,null::timestamptz,e.window_start,e.window_end,e.expected_owner_minutes,e.protection_level,e.interruptibility,
  false,true,e.consequence,e.reason_for_floor,e.portfolio_unit_id,e.horizon,
  e.metadata||jsonb_build_object('sourceSystem',e.source_system,'sourceType',e.source_type,'sourceId',e.source_id,'thresholdCrossed',e.threshold_crossed,
    'ownerDecisionRequired',e.owner_decision_required,'severity',e.severity,'options',e.options_json)
from atlas.operational_escalations e where e.status=any(array['open'::text,'acknowledged'::text])
union all
select b.principal_id,'principal_capacity'::text,'capacity_block'::text,b.id,b.title,b.floor_class,b.starts_at,b.ends_at,b.starts_at,b.starts_at,b.ends_at,
  greatest(1,round(extract(epoch from b.ends_at-b.starts_at)/60.0)::integer),b.protection_level,b.interruptibility,false,true,b.consequence,b.reason_for_floor,
  null::uuid,null::text,b.metadata
from atlas.principal_capacity_blocks b where b.blocks_capacity
union all
select a.principal_id,'attention'::text,'attention_debt'::text,a.subject_id,a.title,a.floor_class,a.next_due_at,null::timestamptz,null::timestamptz,
  a.next_due_at,null::timestamptz,a.protected_owner_minutes,a.protection_level,a.interruptibility,false,true,a.consequence,a.reason_for_floor,
  a.portfolio_unit_id,a.horizon,a.metadata||jsonb_build_object('attentionState',a.attention_state,'attentionDebtDays',a.attention_debt_days,
    'lastMeaningfulAt',a.last_meaningful_at,'nextDueAt',a.next_due_at,'policyId',a.policy_id)
from atlas.attention_debt_v1 a where a.attention_state='needs_attention'
union all
select c.principal_id,c.domain,c.source_type,c.source_id,c.title,c.floor_class,c.window_start,c.window_end,c.fixed_start,c.must_begin_by,c.must_finish_by,
  c.expected_minutes,c.protection_level,c.interruptibility,c.delegable,c.owner_required,c.consequence,c.reason_for_floor,c.portfolio_unit_id,c.horizon,c.metadata
from atlas.principal_requirement_acquisition_clock_candidates_v1 c
union all
select c.principal_id,c.domain,c.source_type,c.source_id,c.title,c.floor_class,c.window_start,c.window_end,c.fixed_start,c.must_begin_by,c.must_finish_by,
  c.expected_minutes,c.protection_level,c.interruptibility,c.delegable,c.owner_required,c.consequence,c.reason_for_floor,c.portfolio_unit_id,c.horizon,c.metadata
from atlas.person_life_clock_candidates_v1 c;

create or replace function atlas.person_life_clock_claim_trace_v1(p_claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_user uuid:=auth.uid();
  v_claim atlas.person_life_clock_claims%rowtype;
  v_consequence atlas.person_life_consequence_instances%rowtype;
  v_policy atlas.person_life_consequence_policies%rowtype;
  v_requirement atlas.person_life_goal_requirements%rowtype;
  v_goal atlas.person_life_goals%rowtype;
  v_source_event atlas.person_life_events%rowtype;
  v_goal_event atlas.person_life_events%rowtype;
  v_context jsonb;
begin
  select * into v_claim from atlas.person_life_clock_claims c where c.id=p_claim_id and (v_user is null or c.person_user_id=v_user);
  if v_claim.id is null then raise exception 'Clock claim not found in person custody.' using errcode='42501'; end if;
  select * into v_consequence from atlas.person_life_consequence_instances where id=v_claim.consequence_instance_id;
  select * into v_policy from atlas.person_life_consequence_policies where id=v_consequence.policy_id;
  select * into v_requirement from atlas.person_life_goal_requirements where id=v_claim.requirement_id;
  select * into v_goal from atlas.person_life_goals where id=v_requirement.goal_id;
  select * into v_source_event from atlas.person_life_events where id=v_consequence.source_event_id;
  select * into v_goal_event from atlas.person_life_events where id=v_goal.source_event_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'relationKind',r.relation_kind,
    'event',jsonb_build_object('id',e.id,'eventKind',e.event_kind,'occurredAt',e.occurred_at,'claimState',e.claim_state,'authorityKind',e.authority_kind,'payload',e.payload)
  ) order by e.occurred_at),'[]'::jsonb) into v_context
  from atlas.person_life_event_relations r join atlas.person_life_events e on e.id=r.to_event_id
  where r.from_event_id=v_source_event.id and e.person_user_id=v_claim.person_user_id;

  return jsonb_build_object(
    'contractVersion','person_life_clock_claim_trace_v1',
    'clockClaim',jsonb_build_object('id',v_claim.id,'title',v_claim.title,'eligibilityState',v_claim.eligibility_state,'temporalClaim',v_claim.temporal_claim),
    'consequence',jsonb_build_object('id',v_consequence.id,'role',v_consequence.consequence_role,'kind',v_consequence.consequence_kind,'actionKey',v_consequence.action_key,'packet',v_consequence.consequence_packet),
    'acceptedPolicy',jsonb_build_object('id',v_policy.id,'stableKey',v_policy.stable_key,'authorizationState',v_policy.authorization_state,'packet',v_policy.policy_packet,'sourceEventId',v_policy.source_event_id),
    'sourceObservation',jsonb_build_object('id',v_source_event.id,'eventKind',v_source_event.event_kind,'occurredAt',v_source_event.occurred_at,'claimState',v_source_event.claim_state,'authorityKind',v_source_event.authority_kind,'sourceKind',v_source_event.source_kind,'sourceRecordId',v_source_event.source_record_id,'payload',v_source_event.payload),
    'contextEvents',v_context,
    'acceptedRequirement',jsonb_build_object('id',v_requirement.id,'stableKey',v_requirement.stable_key,'label',v_requirement.label,'authorizationState',v_requirement.authorization_state,'mustBeginBy',v_requirement.must_begin_by,'mustFinishBy',v_requirement.must_finish_by,'sourceEventId',v_requirement.source_event_id),
    'goal',jsonb_build_object('id',v_goal.id,'stableKey',v_goal.stable_key,'title',v_goal.title,'authorizationState',v_goal.authorization_state,'sourceEvent',jsonb_build_object('id',v_goal_event.id,'eventKind',v_goal_event.event_kind,'occurredAt',v_goal_event.occurred_at,'claimState',v_goal_event.claim_state,'payload',v_goal_event.payload)),
    'truthBoundary',jsonb_build_object('traceIsProvenanceNotCausation',true,'contextRelationDoesNotProveCause',true,'noDiagnosisInferred',true,'noTaskCreated',true)
  );
end;
$$;

create or replace view atlas.person_life_journal_events_v1 as
select
  e.id as journal_event_id,
  e.person_user_id,
  e.event_kind,
  e.claim_state,
  e.authority_kind,
  e.occurred_at,
  e.recorded_at,
  e.source_kind,
  e.source_key,
  e.source_record_id,
  e.payload,
  e.provenance,
  e.metadata,
  coalesce((select jsonb_agg(jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id,'relationKind',s.relation_kind) order by s.subject_domain,s.subject_kind,s.subject_id,s.relation_kind)
    from atlas.person_life_event_subjects s where s.event_id=e.id),'[]'::jsonb) as subjects
from atlas.person_life_events e;

grant select on atlas.person_life_events,atlas.person_life_event_subjects,atlas.person_life_event_relations,
  atlas.person_life_goals,atlas.person_life_goal_requirements,atlas.person_life_consequence_policies,
  atlas.person_life_consequence_instances,atlas.person_life_rhythm_bindings,atlas.person_life_rhythm_state,
  atlas.person_life_clock_claims,atlas.person_life_clock_candidates_v1,atlas.person_life_journal_events_v1 to authenticated;

grant select,insert,update,delete on atlas.person_life_events,atlas.person_life_event_subjects,atlas.person_life_event_relations,
  atlas.person_life_goals,atlas.person_life_goal_requirements,atlas.person_life_consequence_policies,
  atlas.person_life_consequence_instances,atlas.person_life_rhythm_bindings,atlas.person_life_rhythm_state,
  atlas.person_life_clock_claims to service_role;

revoke all on function atlas.person_life_event_immutable_guard_v1() from public,anon,authenticated;
revoke all on function atlas.record_person_life_event_api_v1(jsonb) from public,anon;
revoke all on function atlas.upsert_person_life_goal_api_v1(jsonb) from public,anon;
revoke all on function atlas.upsert_person_life_goal_requirement_api_v1(jsonb) from public,anon;
revoke all on function atlas.evaluate_person_life_goal_v1(uuid,jsonb) from public,anon;
revoke all on function atlas.upsert_person_life_consequence_policy_api_v1(jsonb) from public,anon;
revoke all on function atlas.reconcile_person_life_consequences_api_v1(uuid) from public,anon;
revoke all on function atlas.upsert_person_life_rhythm_binding_api_v1(jsonb) from public,anon;
revoke all on function atlas.evaluate_person_life_rhythm_api_v1(uuid,timestamptz,timestamptz) from public,anon;
revoke all on function atlas.claim_person_life_consequence_for_clock_api_v1(uuid) from public,anon;
revoke all on function atlas.person_life_clock_claim_trace_v1(uuid) from public,anon;

grant execute on function atlas.record_person_life_event_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.upsert_person_life_goal_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.upsert_person_life_goal_requirement_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.evaluate_person_life_goal_v1(uuid,jsonb) to authenticated,service_role;
grant execute on function atlas.upsert_person_life_consequence_policy_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.reconcile_person_life_consequences_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.upsert_person_life_rhythm_binding_api_v1(jsonb) to authenticated,service_role;
grant execute on function atlas.evaluate_person_life_rhythm_api_v1(uuid,timestamptz,timestamptz) to authenticated,service_role;
grant execute on function atlas.claim_person_life_consequence_for_clock_api_v1(uuid) to authenticated,service_role;
grant execute on function atlas.person_life_clock_claim_trace_v1(uuid) to authenticated,service_role;

comment on table atlas.person_life_events is 'Private append-only person-owned evidence/event custody. Journal is a projection over these events; organization/farm identity is intentionally absent.';
comment on table atlas.person_life_goals is 'Person-owned Goal persistence around the generic life_goal_packet_v1 reducer. Accepted requirements are stored separately so Atlas cannot smuggle invented requirements into a goal packet.';
comment on table atlas.person_life_consequence_instances is 'Persisted consequences created only from captured evidence plus accepted person-owned consequence policy evaluation. They do not themselves create tasks or Clock claims.';
comment on table atlas.person_life_clock_claims is 'Temporal claims admitted to the unified Principal Clock only through an established consequence + accepted policy + accepted temporal carrier requirement.';
comment on view atlas.person_life_journal_events_v1 is 'Person Journal projection over private person-life evidence; not a second canonical data store.';

commit;
