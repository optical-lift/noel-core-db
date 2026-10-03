create schema reality;
create schema personal;
create schema ledger;
create schema compatibility;

revoke all on schema reality from public;
revoke all on schema personal from public;
revoke all on schema ledger from public;
revoke all on schema compatibility from public;

grant usage on schema reality,personal,ledger,compatibility to service_role;

create table reality.entities (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique check (btrim(stable_key)<>''),
  entity_kind text not null check (btrim(entity_kind)<>''),
  display_name text not null check (btrim(display_name)<>''),
  identity_state text not null default 'canonical'
    check (identity_state in ('canonical','disputed','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table reality.entity_relationships (
  id uuid primary key default gen_random_uuid(),
  subject_entity_id uuid not null references reality.entities(id) on delete restrict,
  relationship_kind text not null check (btrim(relationship_kind)<>''),
  object_entity_id uuid not null references reality.entities(id) on delete restrict,
  relationship_state text not null default 'observed'
    check (relationship_state in ('observed','established','disputed','retired')),
  valid_from timestamptz null,
  valid_until timestamptz null,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (subject_entity_id<>object_entity_id),
  check (valid_until is null or valid_from is null or valid_until>valid_from)
);
create index reality_entity_relationships_subject_idx
  on reality.entity_relationships(subject_entity_id,relationship_kind,relationship_state);
create index reality_entity_relationships_object_idx
  on reality.entity_relationships(object_entity_id,relationship_kind,relationship_state);

create table reality.contact_routes (
  id uuid primary key default gen_random_uuid(),
  entity_id uuid not null references reality.entities(id) on delete cascade,
  route_kind text not null check (btrim(route_kind)<>''),
  route_value text not null check (btrim(route_value)<>''),
  normalized_value text null,
  route_state text not null default 'observed'
    check (route_state in ('observed','verified','suppressed','retired')),
  public_disclosure boolean not null default false,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  first_observed_at timestamptz not null default now(),
  last_verified_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(entity_id,route_kind,normalized_value)
);
create index reality_contact_routes_lookup_idx
  on reality.contact_routes(route_kind,normalized_value)
  where normalized_value is not null and route_state<>'retired';

create table reality.auth_person_bindings (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  binding_state text not null default 'active'
    check (binding_state in ('active','retired')),
  binding_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(binding_basis)='object'),
  bound_at timestamptz not null default now(),
  retired_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index reality_auth_person_bindings_one_active_user_idx
  on reality.auth_person_bindings(auth_user_id)
  where binding_state='active';
create index reality_auth_person_bindings_person_idx
  on reality.auth_person_bindings(person_entity_id)
  where binding_state='active';

create table personal.atlases (
  id uuid primary key default gen_random_uuid(),
  person_entity_id uuid not null unique references reality.entities(id) on delete restrict,
  atlas_state text not null default 'active'
    check (atlas_state in ('active','retired')),
  native boolean not null default true check (native),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table reality.entity_claims (
  id uuid primary key default gen_random_uuid(),
  claimant_person_entity_id uuid not null references reality.entities(id) on delete restrict,
  claimed_entity_id uuid not null references reality.entities(id) on delete restrict,
  claim_kind text not null default 'ledger_activation_interest'
    check (btrim(claim_kind)<>''),
  claim_state text not null default 'requested'
    check (claim_state in ('requested','challenge_pending','verified','rejected','withdrawn','expired')),
  claim_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(claim_basis)='object'),
  requested_at timestamptz not null default now(),
  verified_at timestamptz null,
  closed_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index reality_entity_claims_claimed_idx
  on reality.entity_claims(claimed_entity_id,claim_state,requested_at desc);
create index reality_entity_claims_claimant_idx
  on reality.entity_claims(claimant_person_entity_id,claim_state,requested_at desc);

create table reality.entity_claim_challenges (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid not null references reality.entity_claims(id) on delete cascade,
  contact_route_id uuid not null references reality.contact_routes(id) on delete restrict,
  delivery_channel text not null check (delivery_channel in ('email','sms','phone','postal')),
  challenge_state text not null default 'prepared'
    check (challenge_state in ('prepared','sent','verified','expired','failed','cancelled')),
  challenge_secret_hash text null,
  delivery_target_snapshot text not null check (btrim(delivery_target_snapshot)<>''),
  prepared_at timestamptz not null default now(),
  sent_at timestamptz null,
  verified_at timestamptz null,
  expires_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index reality_entity_claim_challenges_claim_idx
  on reality.entity_claim_challenges(claim_id,challenge_state);

create table ledger.onboarding_cases (
  id uuid primary key default gen_random_uuid(),
  subject_entity_id uuid not null references reality.entities(id) on delete restrict,
  requested_by_person_entity_id uuid null references reality.entities(id) on delete restrict,
  verified_claim_id uuid null references reality.entity_claims(id) on delete restrict,
  practitioner_person_entity_id uuid null references reality.entities(id) on delete restrict,
  desired_ledger_name text not null check (btrim(desired_ledger_name)<>''),
  onboarding_state text not null default 'requested'
    check (onboarding_state in (
      'requested','practitioner_assigned','in_progress','ready_to_activate','completed','cancelled'
    )),
  onboarding_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(onboarding_basis)='object'),
  requested_at timestamptz not null default now(),
  practitioner_assigned_at timestamptz null,
  ready_at timestamptz null,
  completed_at timestamptz null,
  cancelled_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ledger_onboarding_cases_subject_idx
  on ledger.onboarding_cases(subject_entity_id,onboarding_state,requested_at desc);
create index ledger_onboarding_cases_practitioner_idx
  on ledger.onboarding_cases(practitioner_person_entity_id,onboarding_state)
  where practitioner_person_entity_id is not null;
create index ledger_onboarding_cases_claim_idx
  on ledger.onboarding_cases(verified_claim_id)
  where verified_claim_id is not null;

create table ledger.ledgers (
  id uuid primary key default gen_random_uuid(),
  subject_entity_id uuid not null references reality.entities(id) on delete restrict,
  onboarding_case_id uuid not null unique references ledger.onboarding_cases(id) on delete restrict,
  stable_key text not null unique check (btrim(stable_key)<>''),
  name text not null check (btrim(name)<>''),
  ledger_state text not null default 'active'
    check (ledger_state in ('active','paused','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  activated_at timestamptz not null default now(),
  retired_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ledger_ledgers_subject_idx
  on ledger.ledgers(subject_entity_id,ledger_state,name);

create table ledger.seats (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  person_entity_id uuid not null references reality.entities(id) on delete restrict,
  seat_state text not null default 'active'
    check (seat_state in ('active','paused','ended')),
  seat_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(seat_basis)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index ledger_seats_one_active_person_per_ledger_idx
  on ledger.seats(ledger_id,person_entity_id)
  where seat_state='active';
create index ledger_seats_person_idx
  on ledger.seats(person_entity_id,seat_state,ledger_id);

create table ledger.seat_responsibilities (
  id uuid primary key default gen_random_uuid(),
  seat_id uuid not null references ledger.seats(id) on delete cascade,
  responsibility_key text not null check (btrim(responsibility_key)<>''),
  title text not null check (btrim(title)<>''),
  responsibility_state text not null default 'active'
    check (responsibility_state in ('active','ended')),
  scope jsonb not null default '{}'::jsonb check (jsonb_typeof(scope)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(seat_id,responsibility_key)
);

create table ledger.actions (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  action_kind text not null check (btrim(action_kind)<>''),
  performed_by_entity_id uuid null references reality.entities(id) on delete restrict,
  occurred_at timestamptz not null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  unique(ledger_id,idempotency_key)
);
create index ledger_actions_timeline_idx on ledger.actions(ledger_id,occurred_at desc,id);
create index ledger_actions_actor_idx
  on ledger.actions(performed_by_entity_id,occurred_at desc)
  where performed_by_entity_id is not null;

create table ledger.observations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  source_action_id uuid null references ledger.actions(id) on delete set null,
  observation_kind text not null check (btrim(observation_kind)<>''),
  observed_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now()
);
create index ledger_observations_timeline_idx
  on ledger.observations(ledger_id,observed_at desc,id);
create index ledger_observations_action_idx
  on ledger.observations(source_action_id)
  where source_action_id is not null;

create table ledger.summaries (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  summary_kind text not null check (btrim(summary_kind)<>''),
  coverage_from timestamptz null,
  coverage_until timestamptz null,
  production_mode text not null
    check (production_mode in ('atlas_derived','seat_published','hybrid')),
  produced_by_seat_id uuid null references ledger.seats(id) on delete set null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  check (coverage_until is null or coverage_from is null or coverage_until>=coverage_from)
);
create index ledger_summaries_ledger_idx
  on ledger.summaries(ledger_id,created_at desc);
create index ledger_summaries_seat_idx
  on ledger.summaries(produced_by_seat_id)
  where produced_by_seat_id is not null;

create table ledger.connections (
  id uuid primary key default gen_random_uuid(),
  source_ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  observer_ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  connection_kind text not null default 'summary_exposure'
    check (connection_kind='summary_exposure'),
  connection_state text not null default 'active'
    check (connection_state in ('active','paused','ended')),
  connection_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(connection_basis)='object'),
  began_at timestamptz not null default now(),
  ended_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_ledger_id<>observer_ledger_id)
);
create unique index ledger_connections_one_active_pair_idx
  on ledger.connections(source_ledger_id,observer_ledger_id)
  where connection_state='active';
create index ledger_connections_observer_idx
  on ledger.connections(observer_ledger_id,connection_state,source_ledger_id);

create table ledger.exposures (
  id uuid primary key default gen_random_uuid(),
  connection_id uuid not null references ledger.connections(id) on delete cascade,
  summary_id uuid not null references ledger.summaries(id) on delete restrict,
  exposure_state text not null default 'published'
    check (exposure_state in ('published','withdrawn','superseded')),
  exposed_at timestamptz not null default now(),
  withdrawn_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(connection_id,summary_id)
);
create index ledger_exposures_connection_idx
  on ledger.exposures(connection_id,exposed_at desc);

create table compatibility.legacy_bindings (
  id uuid primary key default gen_random_uuid(),
  legacy_schema text not null check (btrim(legacy_schema)<>''),
  legacy_table text not null check (btrim(legacy_table)<>''),
  legacy_key text not null check (btrim(legacy_key)<>''),
  disposition text not null
    check (disposition in ('maps_to','split_into','retired','unresolved')),
  new_schema text null,
  new_table text null,
  new_id uuid null,
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  created_at timestamptz not null default now(),
  check (
    (disposition in ('maps_to','split_into') and new_schema is not null and new_table is not null and new_id is not null)
    or
    (disposition in ('retired','unresolved'))
  ),
  unique(legacy_schema,legacy_table,legacy_key,new_schema,new_table,new_id)
);
create index compatibility_legacy_bindings_new_target_idx
  on compatibility.legacy_bindings(new_schema,new_table,new_id)
  where new_id is not null;

create or replace function reality.assert_person_entity_v1(p_entity_id uuid)
returns void
language plpgsql
stable
set search_path=''
as $function$
declare
  v_kind text;
  v_state text;
begin
  select entity_kind,identity_state into v_kind,v_state
  from reality.entities
  where id=p_entity_id;

  if v_kind is null then
    raise exception 'Reality entity not found.' using errcode='P0002';
  end if;
  if v_kind<>'person' or v_state='retired' then
    raise exception 'Active Person entity required.' using errcode='23514';
  end if;
end
$function$;

create or replace function reality.guard_auth_person_binding_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  perform reality.assert_person_entity_v1(new.person_entity_id);
  if new.binding_state='retired' and new.retired_at is null then
    new.retired_at:=now();
  end if;
  return new;
end
$function$;

create trigger reality_auth_person_bindings_guard_v1
before insert or update on reality.auth_person_bindings
for each row execute function reality.guard_auth_person_binding_v1();

create or replace function personal.ensure_native_atlas_from_auth_binding_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if new.binding_state='active' then
    insert into personal.atlases(person_entity_id)
    values(new.person_entity_id)
    on conflict(person_entity_id) do nothing;
  end if;
  return new;
end
$function$;

create trigger reality_auth_person_bindings_native_personal_atlas_v1
after insert or update of binding_state,person_entity_id on reality.auth_person_bindings
for each row execute function personal.ensure_native_atlas_from_auth_binding_v1();

create or replace function reality.guard_entity_claim_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  perform reality.assert_person_entity_v1(new.claimant_person_entity_id);
  if new.claim_state='verified' and new.verified_at is null then
    new.verified_at:=now();
  end if;
  if new.claim_state in ('rejected','withdrawn','expired') and new.closed_at is null then
    new.closed_at:=now();
  end if;
  return new;
end
$function$;

create trigger reality_entity_claim_guard_v1
before insert or update on reality.entity_claims
for each row execute function reality.guard_entity_claim_v1();

create or replace function reality.guard_entity_claim_challenge_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_claimed_entity uuid;
  v_route_entity uuid;
begin
  select claimed_entity_id into v_claimed_entity
  from reality.entity_claims
  where id=new.claim_id;

  select entity_id into v_route_entity
  from reality.contact_routes
  where id=new.contact_route_id;

  if v_claimed_entity is null or v_route_entity is null or v_claimed_entity<>v_route_entity then
    raise exception 'Claim challenge must use a contact route belonging to the claimed Entity.'
      using errcode='23514';
  end if;

  if new.challenge_state='verified' and new.verified_at is null then
    new.verified_at:=now();
  end if;

  return new;
end
$function$;

create trigger reality_entity_claim_challenge_guard_v1
before insert or update on reality.entity_claim_challenges
for each row execute function reality.guard_entity_claim_challenge_v1();

create or replace function ledger.guard_onboarding_case_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_claimed uuid;
  v_claim_state text;
begin
  if new.requested_by_person_entity_id is not null then
    perform reality.assert_person_entity_v1(new.requested_by_person_entity_id);
  end if;
  if new.practitioner_person_entity_id is not null then
    perform reality.assert_person_entity_v1(new.practitioner_person_entity_id);
  end if;

  if new.verified_claim_id is not null then
    select claimed_entity_id,claim_state into v_claimed,v_claim_state
    from reality.entity_claims
    where id=new.verified_claim_id;

    if v_claimed is null or v_claimed<>new.subject_entity_id or v_claim_state<>'verified' then
      raise exception 'Onboarding claim must be verified and must identify the Ledger subject Entity.'
        using errcode='23514';
    end if;
  end if;

  if new.onboarding_state in ('practitioner_assigned','in_progress','ready_to_activate','completed')
     and new.practitioner_person_entity_id is null then
    raise exception 'Practitioner is required once Ledger onboarding is assigned.'
      using errcode='23514';
  end if;

  if new.onboarding_state='ready_to_activate' and new.ready_at is null then
    new.ready_at:=now();
  end if;

  return new;
end
$function$;

create trigger ledger_onboarding_case_guard_v1
before insert or update on ledger.onboarding_cases
for each row execute function ledger.guard_onboarding_case_v1();

create or replace function ledger.guard_ledger_activation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_case ledger.onboarding_cases%rowtype;
begin
  select * into v_case
  from ledger.onboarding_cases
  where id=new.onboarding_case_id
  for update;

  if v_case.id is null then
    raise exception 'Practitioner onboarding case required.' using errcode='23514';
  end if;
  if v_case.subject_entity_id<>new.subject_entity_id then
    raise exception 'Ledger subject must match onboarding subject.' using errcode='23514';
  end if;
  if v_case.onboarding_state<>'ready_to_activate'
     or v_case.practitioner_person_entity_id is null then
    raise exception 'Ledger may only activate from a practitioner-owned ready onboarding case.'
      using errcode='23514';
  end if;
  return new;
end
$function$;

create trigger ledger_activation_guard_v1
before insert on ledger.ledgers
for each row execute function ledger.guard_ledger_activation_v1();

create or replace function ledger.complete_onboarding_after_activation_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  update ledger.onboarding_cases
  set onboarding_state='completed',
      completed_at=coalesce(completed_at,now()),
      updated_at=now()
  where id=new.onboarding_case_id
    and onboarding_state='ready_to_activate';
  return new;
end
$function$;

create trigger ledger_activation_completes_onboarding_v1
after insert on ledger.ledgers
for each row execute function ledger.complete_onboarding_after_activation_v1();

create or replace function ledger.guard_seat_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  perform reality.assert_person_entity_v1(new.person_entity_id);
  if new.seat_state='ended' and new.ended_at is null then
    new.ended_at:=now();
  end if;
  return new;
end
$function$;

create trigger ledger_seat_guard_v1
before insert or update on ledger.seats
for each row execute function ledger.guard_seat_v1();

create or replace function ledger.guard_summary_authorship_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_seat_ledger uuid;
begin
  if new.produced_by_seat_id is not null then
    select ledger_id into v_seat_ledger
    from ledger.seats
    where id=new.produced_by_seat_id and seat_state='active';

    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id then
      raise exception 'Summary author Seat must be active in the summarized Ledger.'
        using errcode='23514';
    end if;
  end if;

  if new.production_mode='seat_published' and new.produced_by_seat_id is null then
    raise exception 'Seat-published summary requires an active producing Seat.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

create trigger ledger_summary_authorship_guard_v1
before insert or update on ledger.summaries
for each row execute function ledger.guard_summary_authorship_v1();

create or replace function ledger.guard_exposure_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_source uuid;
  v_connection_state text;
  v_summary_ledger uuid;
begin
  select source_ledger_id,connection_state
  into v_source,v_connection_state
  from ledger.connections
  where id=new.connection_id;

  select ledger_id into v_summary_ledger
  from ledger.summaries
  where id=new.summary_id;

  if v_source is null or v_summary_ledger is null
     or v_source<>v_summary_ledger
     or v_connection_state<>'active' then
    raise exception 'Exposure must publish a source-Ledger summary through an active connection.'
      using errcode='23514';
  end if;

  if new.exposure_state='withdrawn' and new.withdrawn_at is null then
    new.withdrawn_at:=now();
  end if;

  return new;
end
$function$;

create trigger ledger_exposure_guard_v1
before insert or update on ledger.exposures
for each row execute function ledger.guard_exposure_v1();

do $block$
declare
  r record;
begin
  for r in
    select table_schema,table_name
    from information_schema.tables
    where table_type='BASE TABLE'
      and table_schema in ('reality','personal','ledger','compatibility')
  loop
    execute format('alter table %I.%I enable row level security',r.table_schema,r.table_name);
    execute format('revoke all on table %I.%I from public,anon,authenticated',r.table_schema,r.table_name);
    execute format('grant select,insert,update,delete on table %I.%I to service_role',r.table_schema,r.table_name);
  end loop;
end
$block$;

comment on schema reality is
  'Atlas canonical representation of real-world entities and relationships. Reality exists independently of Atlas signup, Ledger activation, or human access.';
comment on schema personal is
  'Native Personal Atlas state for authenticated human Persons. Personal Atlas is not a Ledger and requires no practitioner onboarding.';
comment on schema ledger is
  'Practitioner-onboarded institutional/business action worlds. A Ledger is a subject Entity expressing actions so they can be observed.';
comment on schema compatibility is
  'One-way migration mappings from legacy Atlas identity/custody structures into the Reality/Ledger core. Never an authority source.';

comment on table ledger.seats is
  'A Seat means a Person participates in a Ledger. It does not establish real-world ownership, representation, billing ownership, or canonical Entity identity.';
comment on table ledger.connections is
  'A directed observational composition edge. The observer Ledger may consume published summaries from the source Ledger; no raw access or permission inheritance is implied.';
comment on table ledger.exposures is
  'A published summary snapshot from one Ledger to an observing Ledger through an active Ledger connection.';
comment on table reality.entity_relationships is
  'Real-world relationship facts between canonical Entities. Relationships do not grant Ledger access.';
comment on table reality.entity_claims is
  'A Person asking to establish standing around an already-existing canonical Entity. A verified claim does not create or duplicate the Entity and does not itself create a Ledger.';
comment on table compatibility.legacy_bindings is
  'Migration-only map. Contains no foreign keys to legacy Atlas objects by design.';
