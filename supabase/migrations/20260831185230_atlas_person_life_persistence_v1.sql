-- Atlas Person-Owned Life Persistence v1
--
-- Gives the generic Life Signal / Goal / Rhythm / State Consequence cores a
-- first-party persistence envelope rooted in the authenticated human. A person
-- is not represented as a Farm, Organization, or Household to reuse old storage.
--
-- This migration creates no task, Clock placement, diagnosis, domain Result,
-- practitioner grant, employer grant, household grant, or organization grant.

begin;

create table atlas.person_life_definitions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  signal_kind text not null check (signal_kind in ('goal','rhythm','consequence')),
  source_key text not null check (btrim(source_key) <> ''),
  subject_domain text not null check (btrim(subject_domain) <> ''),
  subject_kind text not null check (btrim(subject_kind) <> ''),
  subject_id text not null check (btrim(subject_id) <> ''),
  source_domain text not null check (btrim(source_domain) <> ''),
  source_kind text not null check (btrim(source_kind) <> ''),
  source_id text not null check (btrim(source_id) <> ''),
  life_signal jsonb not null,
  engine_packet jsonb not null,
  status text not null default 'active' check (status in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (owner_user_id, signal_kind, source_key)
);

comment on table atlas.person_life_definitions is
  'Private first-party definitions for person-owned Goal, explicit Rhythm, and State Consequence intelligence. Canonical Life Signal plus its pure shared-engine packet are retained without fake institutional identity.';

create index person_life_definitions_owner_subject_idx
  on atlas.person_life_definitions(owner_user_id, subject_domain, subject_kind, subject_id, created_at, id);
create index person_life_definitions_principal_kind_idx
  on atlas.person_life_definitions(principal_id, signal_kind, status, created_at, id);

create table atlas.person_life_relations (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  relation_kind text not null check (btrim(relation_kind) <> ''),
  target_domain text not null check (btrim(target_domain) <> ''),
  target_kind text not null check (btrim(target_kind) <> ''),
  target_id text not null check (btrim(target_id) <> ''),
  relation_basis text,
  relation_status text,
  provenance jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (definition_id, relation_kind, target_domain, target_kind, target_id)
);

comment on table atlas.person_life_relations is
  'Neutral queryable relations carried by a person-owned Life Signal. Relation custody is preserved separately; no row establishes causation by itself.';

create index person_life_relations_owner_target_idx
  on atlas.person_life_relations(owner_user_id, target_domain, target_kind, target_id, definition_id);

create table atlas.person_life_state_events (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  event_kind text not null check (event_kind in (
    'goal_evaluation',
    'rhythm_satisfaction',
    'rhythm_evaluation',
    'consequence_evaluation',
    'consequence_resolution'
  )),
  source_key text not null check (btrim(source_key) <> ''),
  occurred_at timestamptz not null,
  input_payload jsonb not null,
  evidence jsonb not null default '{}'::jsonb,
  evaluation jsonb not null,
  created_at timestamptz not null default now(),
  unique (owner_user_id, source_key)
);

comment on table atlas.person_life_state_events is
  'Append-oriented first-party evidence/evaluation history. A reducer output remains derived state and cannot manufacture its own evidence, task, or Clock placement.';

create index person_life_state_events_definition_time_idx
  on atlas.person_life_state_events(definition_id, occurred_at desc, created_at desc, id);

create table atlas.person_life_consequence_instances (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references atlas.person_life_definitions(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  stable_key text not null check (btrim(stable_key) <> ''),
  consequence_role text not null check (consequence_role in ('operation_requirement','truth_acquisition','repair','preparation')),
  consequence_kind text,
  action_key text,
  requirement_state text not null default 'established',
  carrier_ref text,
  carrier_state text not null default 'unresolved',
  placement_state text not null default 'unresolved',
  execution_readiness text not null default 'not_evaluated',
  action_spec jsonb not null default '{}'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  opened_by_event_id uuid not null references atlas.person_life_state_events(id),
  last_seen_event_id uuid not null references atlas.person_life_state_events(id),
  resolved_by_event_id uuid references atlas.person_life_state_events(id),
  status text not null default 'open' check (status in ('open','resolved')),
  opened_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (definition_id, stable_key)
);

comment on table atlas.person_life_consequence_instances is
  'Current projection of explicitly established person-owned State Consequences. Requirement, carrier, execution readiness, and placement remain separate authorities; a later non-match does not silently resolve an instance.';

create index person_life_consequence_instances_owner_status_idx
  on atlas.person_life_consequence_instances(owner_user_id, status, updated_at desc, id);

create or replace function atlas.guard_person_life_definition_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_principal_user_id uuid;
  v_validation jsonb;
  v_expected_packet jsonb;
begin
  select p.user_id
  into v_principal_user_id
  from atlas.principals p
  where p.id = new.principal_id
    and p.status = 'active';

  if v_principal_user_id is null then
    raise exception 'An active Principal is required for person-owned life persistence.' using errcode='23503';
  end if;
  if v_principal_user_id is distinct from new.owner_user_id then
    raise exception 'Principal/user custody mismatch.' using errcode='23514';
  end if;

  v_validation := atlas.validate_life_signal_v1(new.life_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'Invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  if new.life_signal->'scope'->>'kind' <> 'person'
     or new.life_signal->'scope'->>'id' <> new.owner_user_id::text then
    raise exception 'Person-owned life scope must be the owner user.' using errcode='23514';
  end if;
  if new.life_signal->>'signalKind' is distinct from new.signal_kind then
    raise exception 'Life definition signal kind mismatch.' using errcode='23514';
  end if;
  if new.life_signal->'subject'->>'domain' is distinct from new.subject_domain
     or new.life_signal->'subject'->>'kind' is distinct from new.subject_kind
     or new.life_signal->'subject'->>'id' is distinct from new.subject_id then
    raise exception 'Life definition subject columns must match the canonical signal.' using errcode='23514';
  end if;
  if new.life_signal->'source'->>'domain' is distinct from new.source_domain
     or new.life_signal->'source'->>'kind' is distinct from new.source_kind
     or new.life_signal->'source'->>'id' is distinct from new.source_id then
    raise exception 'Life definition source columns must match the canonical signal.' using errcode='23514';
  end if;

  if new.signal_kind = 'goal' then
    v_expected_packet := atlas.life_signal_to_goal_packet_v1(new.life_signal);
  elsif new.signal_kind = 'rhythm' then
    v_expected_packet := atlas.life_signal_to_rhythm_packet_v1(new.life_signal);
  elsif new.signal_kind = 'consequence' then
    v_expected_packet := atlas.life_signal_to_consequence_packet_v1(new.life_signal);
  else
    raise exception 'Unsupported person life signal kind.' using errcode='22023';
  end if;

  if new.engine_packet is distinct from v_expected_packet then
    raise exception 'Engine packet must be the canonical packet derived from the stored Life Signal.' using errcode='23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.guard_person_life_definition_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_life_definition_custody_v1() to service_role;

create trigger person_life_definitions_custody_guard_v1
before insert or update on atlas.person_life_definitions
for each row execute function atlas.guard_person_life_definition_custody_v1();

create or replace function atlas.guard_person_life_relation_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_owner uuid;
begin
  select d.owner_user_id into v_owner
  from atlas.person_life_definitions d
  where d.id = new.definition_id;
  if v_owner is null or v_owner is distinct from new.owner_user_id then
    raise exception 'Life relation custody must match its parent definition.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_person_life_relation_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_life_relation_custody_v1() to service_role;

create trigger person_life_relations_custody_guard_v1
before insert or update on atlas.person_life_relations
for each row execute function atlas.guard_person_life_relation_custody_v1();

create or replace function atlas.guard_person_life_state_event_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_owner uuid;
  v_kind text;
begin
  select d.owner_user_id, d.signal_kind into v_owner, v_kind
  from atlas.person_life_definitions d
  where d.id = new.definition_id;

  if v_owner is null or v_owner is distinct from new.owner_user_id then
    raise exception 'Life state-event custody must match its parent definition.' using errcode='23514';
  end if;
  if (v_kind='goal' and new.event_kind <> 'goal_evaluation')
     or (v_kind='rhythm' and new.event_kind not in ('rhythm_satisfaction','rhythm_evaluation'))
     or (v_kind='consequence' and new.event_kind not in ('consequence_evaluation','consequence_resolution')) then
    raise exception 'Life state-event kind is incompatible with its parent definition.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_person_life_state_event_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_life_state_event_custody_v1() to service_role;

create trigger person_life_state_events_custody_guard_v1
before insert or update on atlas.person_life_state_events
for each row execute function atlas.guard_person_life_state_event_custody_v1();

create or replace function atlas.guard_person_life_consequence_instance_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_owner uuid;
  v_kind text;
begin
  select d.owner_user_id, d.signal_kind into v_owner, v_kind
  from atlas.person_life_definitions d
  where d.id = new.definition_id;
  if v_owner is null or v_owner is distinct from new.owner_user_id or v_kind <> 'consequence' then
    raise exception 'Consequence instance requires same-owner consequence definition.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_person_life_consequence_instance_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_life_consequence_instance_custody_v1() to service_role;

create trigger person_life_consequence_instances_custody_guard_v1
before insert or update on atlas.person_life_consequence_instances
for each row execute function atlas.guard_person_life_consequence_instance_custody_v1();

alter table atlas.person_life_definitions enable row level security;
alter table atlas.person_life_relations enable row level security;
alter table atlas.person_life_state_events enable row level security;
alter table atlas.person_life_consequence_instances enable row level security;

create policy person_life_definitions_self_read
on atlas.person_life_definitions for select to authenticated
using (owner_user_id = auth.uid());
create policy person_life_relations_self_read
on atlas.person_life_relations for select to authenticated
using (owner_user_id = auth.uid());
create policy person_life_state_events_self_read
on atlas.person_life_state_events for select to authenticated
using (owner_user_id = auth.uid());
create policy person_life_consequence_instances_self_read
on atlas.person_life_consequence_instances for select to authenticated
using (owner_user_id = auth.uid());

grant select on atlas.person_life_definitions to authenticated;
grant select on atlas.person_life_relations to authenticated;
grant select on atlas.person_life_state_events to authenticated;
grant select on atlas.person_life_consequence_instances to authenticated;

grant select, insert, update, delete on atlas.person_life_definitions to service_role;
grant select, insert, update, delete on atlas.person_life_relations to service_role;
grant select, insert, update, delete on atlas.person_life_state_events to service_role;
grant select, insert, update, delete on atlas.person_life_consequence_instances to service_role;

create or replace function atlas.create_person_life_definition_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_source_key text;
  v_signal jsonb;
  v_validation jsonb;
  v_kind text;
  v_packet jsonb;
  v_initial jsonb;
  v_definition_id uuid;
  v_created boolean := false;
  v_existing_signal jsonb;
  v_existing_packet jsonb;
  v_existing_metadata jsonb;
  v_metadata jsonb;
  v_relation jsonb;
  v_target jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  if v_source_key = '' then
    raise exception 'sourceKey is required.' using errcode='22023';
  end if;
  v_signal := p_payload->'signal';
  v_metadata := coalesce(p_payload->'metadata','{}'::jsonb);
  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be an object.' using errcode='22023';
  end if;

  v_validation := atlas.validate_life_signal_v1(v_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;
  if v_signal->'scope'->>'kind' <> 'person' or v_signal->'scope'->>'id' <> v_user_id::text then
    raise exception 'Person life signal scope must be the authenticated user.' using errcode='42501';
  end if;

  v_kind := v_signal->>'signalKind';
  if v_kind not in ('goal','rhythm','consequence') then
    raise exception 'Person life persistence supports goal, rhythm, and consequence definitions only.' using errcode='22023';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active';
  if v_principal_id is null then
    raise exception 'An active Atlas Principal is required.' using errcode='42501';
  end if;

  if v_kind='goal' then
    v_packet := atlas.life_signal_to_goal_packet_v1(v_signal);
    v_initial := atlas.evaluate_life_goal_state_v1(v_packet,'[]'::jsonb);
  elsif v_kind='rhythm' then
    v_packet := atlas.life_signal_to_rhythm_packet_v1(v_signal);
    if v_packet->>'strategyState' <> 'supported' then
      raise exception 'Person Rhythm persistence v1 requires an explicit supported strategy.' using errcode='22023';
    end if;
    v_initial := atlas.evaluate_life_lease_rhythm_v1(v_packet,null,now());
  else
    v_packet := atlas.life_signal_to_consequence_packet_v1(v_signal);
    v_initial := null;
  end if;

  insert into atlas.person_life_definitions(
    principal_id, owner_user_id, signal_kind, source_key,
    subject_domain, subject_kind, subject_id,
    source_domain, source_kind, source_id,
    life_signal, engine_packet, metadata
  ) values (
    v_principal_id, v_user_id, v_kind, v_source_key,
    v_signal->'subject'->>'domain', v_signal->'subject'->>'kind', v_signal->'subject'->>'id',
    v_signal->'source'->>'domain', v_signal->'source'->>'kind', v_signal->'source'->>'id',
    v_signal, v_packet, v_metadata
  )
  on conflict (owner_user_id, signal_kind, source_key) do nothing
  returning id into v_definition_id;

  if v_definition_id is not null then
    v_created := true;
  else
    select d.id,d.life_signal,d.engine_packet,d.metadata
    into v_definition_id,v_existing_signal,v_existing_packet,v_existing_metadata
    from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id and d.signal_kind=v_kind and d.source_key=v_source_key;

    if v_definition_id is null
       or v_existing_signal is distinct from v_signal
       or v_existing_packet is distinct from v_packet
       or v_existing_metadata is distinct from v_metadata then
      raise exception 'sourceKey retry does not match existing person-life definition.' using errcode='23505';
    end if;
  end if;

  if v_created then
    for v_relation in select value from jsonb_array_elements(coalesce(v_signal->'relations','[]'::jsonb)) loop
      v_target := v_relation->'target';
      if jsonb_typeof(v_target)='object'
         and nullif(btrim(v_target->>'domain'),'') is not null
         and nullif(btrim(v_target->>'kind'),'') is not null
         and nullif(btrim(v_target->>'id'),'') is not null then
        insert into atlas.person_life_relations(
          definition_id,owner_user_id,relation_kind,target_domain,target_kind,target_id,
          relation_basis,relation_status,provenance
        ) values (
          v_definition_id,v_user_id,v_relation->>'relationKind',
          v_target->>'domain',v_target->>'kind',v_target->>'id',
          nullif(v_relation->>'relationBasis',''),nullif(v_relation->>'relationStatus',''),
          jsonb_build_object('source',v_signal->'source','epistemic',v_signal->'epistemic','relation',v_relation)
        ) on conflict do nothing;
      end if;
    end loop;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'created',v_created,
    'definitionId',v_definition_id,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'signalKind',v_kind,
    'subject',v_signal->'subject',
    'source',v_signal->'source',
    'enginePacket',v_packet,
    'initialEvaluation',v_initial,
    'truthBoundary',jsonb_build_object(
      'personCustodyOnly',true,
      'definitionDoesNotCreateTask',true,
      'definitionDoesNotCreateClockPlacement',true,
      'goalDoesNotInventRequirements',true,
      'rhythmRequiresExplicitStrategy',true
    )
  ));
end;
$$;

comment on function atlas.create_person_life_definition_api_v1(jsonb) is
  'First-party Goal/Rhythm/State Consequence definition writer. Custody is fixed to auth.uid(); shared packets are recomputed from source-custodied Life Signals; no task or Clock authority is created.';

create or replace function atlas.record_person_life_state_api_v1(p_definition_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_kind text;
  v_packet jsonb;
  v_source_key text;
  v_event_kind text;
  v_occurred_at timestamptz;
  v_evaluation jsonb;
  v_evidence jsonb;
  v_event_id uuid;
  v_existing_definition_id uuid;
  v_existing_event_kind text;
  v_existing_payload jsonb;
  v_existing_evaluation jsonb;
  v_existing_occurred_at timestamptz;
  v_last_satisfied_at timestamptz;
  v_results jsonb;
  v_snapshot jsonb;
  v_policies jsonb;
  v_stable_key text;
  v_consequence jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  select d.signal_kind,d.engine_packet into v_kind,v_packet
  from atlas.person_life_definitions d
  where d.id=p_definition_id and d.owner_user_id=v_user_id and d.status='active';
  if v_kind is null then
    raise exception 'Active person-life definition not found for this user.' using errcode='42501';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  v_event_kind := btrim(coalesce(p_payload->>'eventKind',''));
  if v_source_key='' or v_event_kind='' then
    raise exception 'sourceKey and eventKind are required.' using errcode='22023';
  end if;

  select e.id,e.definition_id,e.event_kind,e.input_payload,e.evaluation,e.occurred_at
  into v_event_id,v_existing_definition_id,v_existing_event_kind,v_existing_payload,v_existing_evaluation,v_existing_occurred_at
  from atlas.person_life_state_events e
  where e.owner_user_id=v_user_id and e.source_key=v_source_key;

  if v_event_id is not null then
    if v_existing_definition_id is distinct from p_definition_id
       or v_existing_event_kind is distinct from v_event_kind
       or v_existing_payload is distinct from p_payload then
      raise exception 'sourceKey retry does not match existing person-life state event.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'replayed',true,'eventId',v_event_id,'definitionId',p_definition_id,
      'eventKind',v_event_kind,'occurredAt',v_existing_occurred_at,'evaluation',v_existing_evaluation
    );
  end if;

  if v_event_kind='goal_evaluation' then
    if v_kind<>'goal' then raise exception 'goal_evaluation requires a Goal definition.' using errcode='22023'; end if;
    v_results := coalesce(p_payload->'requirementResults','[]'::jsonb);
    if jsonb_typeof(v_results)<>'array' then raise exception 'requirementResults must be an array.' using errcode='22023'; end if;
    v_occurred_at := coalesce(nullif(p_payload->>'observedAt','')::timestamptz,now());
    v_evaluation := atlas.evaluate_life_goal_state_v1(v_packet,v_results);
    v_evidence := jsonb_build_object('requirementResults',v_results,'source',coalesce(p_payload->'evidence','{}'::jsonb));

  elsif v_event_kind='rhythm_satisfaction' then
    if v_kind<>'rhythm' then raise exception 'rhythm_satisfaction requires a Rhythm definition.' using errcode='22023'; end if;
    if nullif(p_payload->>'satisfiedAt','') is null then raise exception 'satisfiedAt is required.' using errcode='22023'; end if;
    v_occurred_at := (p_payload->>'satisfiedAt')::timestamptz;
    v_evaluation := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_occurred_at,coalesce(nullif(p_payload->>'asOf','')::timestamptz,now()));
    v_evidence := jsonb_build_object('satisfiedAt',v_occurred_at,'source',coalesce(p_payload->'evidence','{}'::jsonb));

  elsif v_event_kind='rhythm_evaluation' then
    if v_kind<>'rhythm' then raise exception 'rhythm_evaluation requires a Rhythm definition.' using errcode='22023'; end if;
    v_occurred_at := coalesce(nullif(p_payload->>'asOf','')::timestamptz,now());
    select max(e.occurred_at) into v_last_satisfied_at
    from atlas.person_life_state_events e
    where e.definition_id=p_definition_id and e.owner_user_id=v_user_id
      and e.event_kind='rhythm_satisfaction' and e.occurred_at<=v_occurred_at;
    v_evaluation := atlas.evaluate_life_lease_rhythm_v1(v_packet,v_last_satisfied_at,v_occurred_at);
    v_evidence := jsonb_build_object('lastSatisfiedAt',v_last_satisfied_at);

  elsif v_event_kind='consequence_evaluation' then
    if v_kind<>'consequence' then raise exception 'consequence_evaluation requires a Consequence definition.' using errcode='22023'; end if;
    v_snapshot := p_payload->'snapshot';
    v_policies := p_payload->'policies';
    if jsonb_typeof(v_snapshot)<>'object' or jsonb_typeof(v_policies)<>'array' then
      raise exception 'consequence evaluation requires snapshot object and policies array.' using errcode='22023';
    end if;
    v_occurred_at := coalesce(nullif(p_payload->>'observedAt','')::timestamptz,now());
    v_evaluation := atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
    v_evidence := jsonb_build_object('snapshot',v_snapshot,'policies',v_policies,'source',coalesce(p_payload->'evidence','{}'::jsonb));

  elsif v_event_kind='consequence_resolution' then
    if v_kind<>'consequence' then raise exception 'consequence_resolution requires a Consequence definition.' using errcode='22023'; end if;
    v_stable_key := btrim(coalesce(p_payload->>'stableKey',''));
    if v_stable_key='' then raise exception 'stableKey is required for explicit consequence resolution.' using errcode='22023'; end if;
    if not exists (
      select 1 from atlas.person_life_consequence_instances i
      where i.definition_id=p_definition_id and i.owner_user_id=v_user_id and i.stable_key=v_stable_key and i.status='open'
    ) then
      raise exception 'Open consequence instance not found.' using errcode='22023';
    end if;
    v_occurred_at := coalesce(nullif(p_payload->>'resolvedAt','')::timestamptz,now());
    v_evidence := coalesce(p_payload->'evidence','{}'::jsonb);
    v_evaluation := jsonb_build_object(
      'contractVersion','person_life_consequence_resolution_v1',
      'stableKey',v_stable_key,'state','resolved','resolvedAt',v_occurred_at,
      'explicitResolutionEvidence',v_evidence,
      'truthBoundary',jsonb_build_object('resolutionIsExplicitNotInferredFromAbsence',true,'doesNotCreateTask',true,'doesNotCreateClockPlacement',true)
    );
  else
    raise exception 'Unsupported person-life eventKind.' using errcode='22023';
  end if;

  insert into atlas.person_life_state_events(
    definition_id,owner_user_id,event_kind,source_key,occurred_at,input_payload,evidence,evaluation
  ) values (
    p_definition_id,v_user_id,v_event_kind,v_source_key,v_occurred_at,p_payload,v_evidence,v_evaluation
  ) returning id into v_event_id;

  if v_event_kind='consequence_evaluation' then
    for v_consequence in select value from jsonb_array_elements(coalesce(v_evaluation->'openConsequences','[]'::jsonb)) loop
      insert into atlas.person_life_consequence_instances(
        definition_id,owner_user_id,stable_key,consequence_role,consequence_kind,action_key,
        requirement_state,carrier_ref,carrier_state,placement_state,execution_readiness,
        action_spec,evidence,opened_by_event_id,last_seen_event_id,status,opened_at
      ) values (
        p_definition_id,v_user_id,v_consequence->>'stableKey',v_consequence->>'consequenceRole',
        nullif(v_consequence->>'consequenceKind',''),nullif(v_consequence->>'actionKey',''),
        coalesce(nullif(v_consequence->>'requirementState',''),'established'),nullif(v_consequence->>'carrierRef',''),
        coalesce(nullif(v_consequence->>'carrierState',''),'unresolved'),coalesce(nullif(v_consequence->>'placementState',''),'unresolved'),
        coalesce(nullif(v_consequence->>'executionReadiness',''),'not_evaluated'),
        coalesce(v_consequence->'actionSpec','{}'::jsonb),coalesce(v_consequence->'evidence','{}'::jsonb),
        v_event_id,v_event_id,'open',v_occurred_at
      )
      on conflict (definition_id,stable_key) do update set
        consequence_role=excluded.consequence_role,
        consequence_kind=excluded.consequence_kind,
        action_key=excluded.action_key,
        requirement_state=excluded.requirement_state,
        carrier_ref=excluded.carrier_ref,
        carrier_state=excluded.carrier_state,
        placement_state=excluded.placement_state,
        execution_readiness=excluded.execution_readiness,
        action_spec=excluded.action_spec,
        evidence=excluded.evidence,
        opened_by_event_id=case when atlas.person_life_consequence_instances.status='resolved' then excluded.opened_by_event_id else atlas.person_life_consequence_instances.opened_by_event_id end,
        last_seen_event_id=excluded.last_seen_event_id,
        status='open',
        opened_at=case when atlas.person_life_consequence_instances.status='resolved' then excluded.opened_at else atlas.person_life_consequence_instances.opened_at end,
        resolved_by_event_id=null,
        resolved_at=null,
        updated_at=now();
    end loop;
  elsif v_event_kind='consequence_resolution' then
    update atlas.person_life_consequence_instances i
    set status='resolved',resolved_by_event_id=v_event_id,resolved_at=v_occurred_at,updated_at=now()
    where i.definition_id=p_definition_id and i.owner_user_id=v_user_id and i.stable_key=v_stable_key;
  end if;

  return jsonb_build_object(
    'ok',true,'replayed',false,'eventId',v_event_id,'definitionId',p_definition_id,
    'eventKind',v_event_kind,'occurredAt',v_occurred_at,'evaluation',v_evaluation,
    'truthBoundary',jsonb_build_object(
      'evidenceRemainsSourceOwned',true,
      'evaluationDoesNotCreateTask',true,
      'evaluationDoesNotCreateClockPlacement',true,
      'requirementCarrierReadinessPlacementRemainSeparate',true
    )
  );
end;
$$;

comment on function atlas.record_person_life_state_api_v1(uuid,jsonb) is
  'First-party evidence/evaluation writer for person-owned Goal, explicit lease Rhythm, and State Consequence state. Consequence absence never auto-resolves an established instance.';

create or replace function atlas.person_life_state_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_definitions jsonb;
  v_consequences jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select coalesce(jsonb_agg(x.item order by x.created_at,x.definition_id),'[]'::jsonb)
  into v_definitions
  from (
    select d.id definition_id,d.created_at,
      jsonb_build_object(
        'definitionId',d.id,
        'signalKind',d.signal_kind,
        'status',d.status,
        'subject',jsonb_build_object('domain',d.subject_domain,'kind',d.subject_kind,'id',d.subject_id),
        'source',jsonb_build_object('domain',d.source_domain,'kind',d.source_kind,'id',d.source_id,'sourceKey',d.source_key),
        'lifeSignal',d.life_signal,
        'enginePacket',d.engine_packet,
        'relations',coalesce((
          select jsonb_agg(jsonb_build_object(
            'relationKind',r.relation_kind,
            'target',jsonb_build_object('domain',r.target_domain,'kind',r.target_kind,'id',r.target_id),
            'relationBasis',r.relation_basis,'relationStatus',r.relation_status,'provenance',r.provenance
          ) order by r.created_at,r.id)
          from atlas.person_life_relations r
          where r.definition_id=d.id and r.owner_user_id=v_user_id
        ),'[]'::jsonb),
        'latestEvent',(
          select jsonb_build_object(
            'eventId',e.id,'eventKind',e.event_kind,'occurredAt',e.occurred_at,
            'evaluation',e.evaluation,'evidence',e.evidence
          )
          from atlas.person_life_state_events e
          where e.definition_id=d.id and e.owner_user_id=v_user_id
          order by e.occurred_at desc,e.created_at desc,e.id desc limit 1
        ),
        'createdAt',d.created_at
      ) item
    from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'instanceId',i.id,'definitionId',i.definition_id,'stableKey',i.stable_key,
    'consequenceRole',i.consequence_role,'consequenceKind',i.consequence_kind,'actionKey',i.action_key,
    'requirementState',i.requirement_state,'carrierRef',i.carrier_ref,'carrierState',i.carrier_state,
    'placementState',i.placement_state,'executionReadiness',i.execution_readiness,
    'actionSpec',i.action_spec,'evidence',i.evidence,'status',i.status,
    'openedAt',i.opened_at,'resolvedAt',i.resolved_at,'updatedAt',i.updated_at
  ) order by i.updated_at desc,i.id),'[]'::jsonb)
  into v_consequences
  from atlas.person_life_consequence_instances i
  where i.owner_user_id=v_user_id;

  return jsonb_build_object(
    'ok',true,
    'scope',jsonb_build_object('kind','person','id',v_user_id),
    'definitions',v_definitions,
    'consequenceInstances',v_consequences,
    'truthBoundary',jsonb_build_object(
      'privateByDefault',true,
      'practitionerAccessGranted',false,
      'clockPlacementAuthority',false,
      'taskGenerationAuthority',false
    )
  );
end;
$$;

comment on function atlas.person_life_state_api_v1() is
  'First-party read membrane for person-owned Life definitions, neutral relations, latest evidence/evaluation state, and explicit State Consequence instances.';

revoke all on function atlas.create_person_life_definition_api_v1(jsonb) from public, anon;
revoke all on function atlas.record_person_life_state_api_v1(uuid,jsonb) from public, anon;
revoke all on function atlas.person_life_state_api_v1() from public, anon;
grant execute on function atlas.create_person_life_definition_api_v1(jsonb) to authenticated, service_role;
grant execute on function atlas.record_person_life_state_api_v1(uuid,jsonb) to authenticated, service_role;
grant execute on function atlas.person_life_state_api_v1() to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values
  (
    'atlas.create_person_life_definition_api_v1(p_payload jsonb)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Persist a first-party Goal, explicit Rhythm, or State Consequence definition from a validated Life Signal.',
      'authorizationBoundary','SECURITY DEFINER requires auth.uid(), active Principal ownership, and exact person scope. No task, Clock, or sharing authority.',
      'directSignedInEndpoint',true
    ),now(),false
  ),
  (
    'atlas.record_person_life_state_api_v1(p_definition_id uuid, p_payload jsonb)',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Record first-party evidence and reducer evaluations for an owned life definition.',
      'authorizationBoundary','SECURITY DEFINER resolves only definitions owned by auth.uid(); consequence resolution requires explicit evidence.',
      'directSignedInEndpoint',true
    ),now(),false
  ),
  (
    'atlas.person_life_state_api_v1()',
    'app_endpoint','verified','active',true,true,true,0,0,
    jsonb_build_object(
      'purpose','Read the signed-in person own Life definitions, relations, latest evaluation state, and consequence projection.',
      'authorizationBoundary','SECURITY DEFINER fixes the read to auth.uid(); no practitioner, household, employer, organization, task, or Clock authority is implied.',
      'directSignedInEndpoint',true
    ),now(),false
  )
on conflict (signature) do update set
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

select atlas.assert_authenticated_rpc_registry_complete_v1();

commit;
