-- Atlas financial evidence resolution v1
--
-- Many source witnesses may describe one economic event. This layer establishes the governed
-- economic meaning of money evidence without collapsing source custody, movement reconciliation,
-- obligation/settlement, or accounting treatment.
--
-- Truth sequence:
--   source observation -> financial source transaction -> optional movement match
--   -> operator-confirmed economic event -> optional obligation/settlement -> accounting
--
-- A monetary allocation consumes source capacity. A witness link does not. This distinction lets
-- a GiveWP record, Stripe event, email, and bank row all support one event without multiplying it.

begin;

create table if not exists atlas.financial_economic_events (
  id uuid primary key default gen_random_uuid(),
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  event_key text not null,
  occurred_on date not null,
  occurred_at timestamptz,
  event_amount numeric not null,
  currency text not null,
  meaning_statement text not null,
  resolution_state text not null default 'confirmed',
  input_sha256 text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  voided_by_user_id uuid references auth.users(id) on delete set null,
  void_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint financial_economic_events_key_nonempty check (btrim(event_key)<>''),
  constraint financial_economic_events_amount_check check (event_amount>0),
  constraint financial_economic_events_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint financial_economic_events_meaning_nonempty check (btrim(meaning_statement)<>''),
  constraint financial_economic_events_state_check check (resolution_state in ('confirmed','voided')),
  constraint financial_economic_events_hash_nonempty check (btrim(input_sha256)<>''),
  constraint financial_economic_events_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_economic_events_metadata_object check (jsonb_typeof(metadata)='object'),
  constraint financial_economic_events_void_shape check (
    (resolution_state='confirmed' and voided_at is null and voided_by_user_id is null and void_reason is null)
    or
    (resolution_state='voided' and voided_at is not null and voided_by_user_id is not null and nullif(btrim(void_reason),'') is not null)
  ),
  unique(created_by_principal_id,event_key)
);

create index if not exists financial_economic_events_date_idx
  on atlas.financial_economic_events(created_by_principal_id,occurred_on,resolution_state,id);

create table if not exists atlas.financial_economic_event_source_allocations (
  id uuid primary key default gen_random_uuid(),
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  allocation_ordinal integer not null,
  financial_transaction_id uuid references atlas.financial_source_transactions(id) on delete restrict,
  movement_match_id uuid references atlas.financial_source_movement_matches(id) on delete restrict,
  attributed_amount numeric not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_economic_event_source_ordinal_check check (allocation_ordinal>0),
  constraint financial_economic_event_source_xor_check check (num_nonnulls(financial_transaction_id,movement_match_id)=1),
  constraint financial_economic_event_source_amount_check check (attributed_amount>0),
  constraint financial_economic_event_source_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_economic_event_source_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(economic_event_id,allocation_ordinal)
);

create unique index if not exists financial_economic_event_source_transaction_unique_idx
  on atlas.financial_economic_event_source_allocations(economic_event_id,financial_transaction_id)
  where financial_transaction_id is not null;
create unique index if not exists financial_economic_event_source_movement_unique_idx
  on atlas.financial_economic_event_source_allocations(economic_event_id,movement_match_id)
  where movement_match_id is not null;
create index if not exists financial_economic_event_source_transaction_lookup_idx
  on atlas.financial_economic_event_source_allocations(financial_transaction_id,economic_event_id)
  where financial_transaction_id is not null;
create index if not exists financial_economic_event_source_movement_lookup_idx
  on atlas.financial_economic_event_source_allocations(movement_match_id,economic_event_id)
  where movement_match_id is not null;

create table if not exists atlas.financial_economic_event_evidence_links (
  id uuid primary key default gen_random_uuid(),
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  link_key text not null,
  evidence_record_id uuid references atlas.evidence_records(id) on delete restrict,
  financial_transaction_id uuid references atlas.financial_source_transactions(id) on delete restrict,
  movement_match_id uuid references atlas.financial_source_movement_matches(id) on delete restrict,
  relation_kind text not null,
  note text,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  linked_by_principal_id uuid references atlas.principals(id) on delete restrict,
  linked_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint financial_economic_event_evidence_key_nonempty check (btrim(link_key)<>''),
  constraint financial_economic_event_evidence_xor_check check (
    num_nonnulls(evidence_record_id,financial_transaction_id,movement_match_id)=1
  ),
  constraint financial_economic_event_evidence_relation_check check (relation_kind in ('supports','contradicts','context')),
  constraint financial_economic_event_evidence_note_nonempty check (note is null or btrim(note)<>''),
  constraint financial_economic_event_evidence_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_economic_event_evidence_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(economic_event_id,link_key)
);

create index if not exists financial_economic_event_evidence_record_idx
  on atlas.financial_economic_event_evidence_links(evidence_record_id,economic_event_id)
  where evidence_record_id is not null;
create index if not exists financial_economic_event_evidence_transaction_idx
  on atlas.financial_economic_event_evidence_links(financial_transaction_id,economic_event_id)
  where financial_transaction_id is not null;
create index if not exists financial_economic_event_evidence_movement_idx
  on atlas.financial_economic_event_evidence_links(movement_match_id,economic_event_id)
  where movement_match_id is not null;

create table if not exists atlas.financial_economic_event_parties (
  id uuid primary key default gen_random_uuid(),
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  entity_id uuid not null references reality.entities(id) on delete restrict,
  role_kind text not null,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_economic_event_parties_role_check check (
    role_kind in (
      'payer','payee','principal','agent','processor','merchant','platform','owner','beneficiary',
      'donor','recipient','customer','vendor','employer','employee','borrower','lender','counterparty','other'
    )
  ),
  constraint financial_economic_event_parties_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_economic_event_parties_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(economic_event_id,entity_id,role_kind)
);

create index if not exists financial_economic_event_parties_entity_idx
  on atlas.financial_economic_event_parties(entity_id,role_kind,economic_event_id);

create table if not exists atlas.financial_economic_event_dimensions (
  id uuid primary key default gen_random_uuid(),
  economic_event_id uuid not null references atlas.financial_economic_events(id) on delete restrict,
  dimension_ordinal integer not null,
  dimension_kind text not null,
  entity_id uuid references reality.entities(id) on delete restrict,
  subject_domain text,
  subject_kind text,
  subject_id text,
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint financial_economic_event_dimensions_ordinal_check check (dimension_ordinal>0),
  constraint financial_economic_event_dimensions_kind_check check (
    dimension_kind in ('business_context','property','activity','project','location','contract','fund','other')
  ),
  constraint financial_economic_event_dimensions_target_check check (
    (entity_id is not null and subject_domain is null and subject_kind is null and subject_id is null)
    or
    (entity_id is null
      and nullif(btrim(coalesce(subject_domain,'')),'') is not null
      and nullif(btrim(coalesce(subject_kind,'')),'') is not null
      and nullif(btrim(coalesce(subject_id,'')),'') is not null)
  ),
  constraint financial_economic_event_dimensions_provenance_object check (jsonb_typeof(provenance)='object'),
  constraint financial_economic_event_dimensions_metadata_object check (jsonb_typeof(metadata)='object'),
  unique(economic_event_id,dimension_ordinal)
);

create index if not exists financial_economic_event_dimensions_entity_idx
  on atlas.financial_economic_event_dimensions(entity_id,dimension_kind,economic_event_id)
  where entity_id is not null;
create index if not exists financial_economic_event_dimensions_subject_idx
  on atlas.financial_economic_event_dimensions(subject_domain,subject_kind,subject_id,economic_event_id)
  where entity_id is null;

alter table atlas.financial_economic_events enable row level security;
alter table atlas.financial_economic_event_source_allocations enable row level security;
alter table atlas.financial_economic_event_evidence_links enable row level security;
alter table atlas.financial_economic_event_parties enable row level security;
alter table atlas.financial_economic_event_dimensions enable row level security;

revoke all on table atlas.financial_economic_events from public,anon,authenticated;
revoke all on table atlas.financial_economic_event_source_allocations from public,anon,authenticated;
revoke all on table atlas.financial_economic_event_evidence_links from public,anon,authenticated;
revoke all on table atlas.financial_economic_event_parties from public,anon,authenticated;
revoke all on table atlas.financial_economic_event_dimensions from public,anon,authenticated;

create or replace function atlas.guard_financial_economic_event_entity_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.entity_id is not null and not exists(
    select 1 from reality.entities entity
    where entity.id=new.entity_id
      and entity.identity_state='canonical'
  ) then
    raise exception 'Economic-event entity targets must be canonical Reality entities.' using errcode='23514';
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_economic_event_entity_v1() from public,anon,authenticated;

create trigger financial_economic_event_parties_canonical_guard_v1
before insert or update of entity_id on atlas.financial_economic_event_parties
for each row execute function atlas.guard_financial_economic_event_entity_v1();
create trigger financial_economic_event_dimensions_canonical_guard_v1
before insert or update of entity_id on atlas.financial_economic_event_dimensions
for each row execute function atlas.guard_financial_economic_event_entity_v1();

create or replace function atlas.prevent_financial_economic_event_child_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'Economic-event source allocations, witness links, parties, and dimensions are append-only.' using errcode='55000';
end;
$$;
revoke all on function atlas.prevent_financial_economic_event_child_mutation_v1() from public,anon,authenticated;

create trigger financial_economic_event_source_allocations_immutable_v1
before update or delete on atlas.financial_economic_event_source_allocations
for each row execute function atlas.prevent_financial_economic_event_child_mutation_v1();
create trigger financial_economic_event_evidence_links_immutable_v1
before update or delete on atlas.financial_economic_event_evidence_links
for each row execute function atlas.prevent_financial_economic_event_child_mutation_v1();
create trigger financial_economic_event_parties_immutable_v1
before update or delete on atlas.financial_economic_event_parties
for each row execute function atlas.prevent_financial_economic_event_child_mutation_v1();
create trigger financial_economic_event_dimensions_immutable_v1
before update or delete on atlas.financial_economic_event_dimensions
for each row execute function atlas.prevent_financial_economic_event_child_mutation_v1();

create or replace function atlas.guard_financial_economic_event_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    raise exception 'Economic events are retained reality history; void rather than delete.' using errcode='55000';
  end if;

  if old.created_by_principal_id is distinct from new.created_by_principal_id
     or old.event_key is distinct from new.event_key
     or old.occurred_on is distinct from new.occurred_on
     or old.occurred_at is distinct from new.occurred_at
     or old.event_amount is distinct from new.event_amount
     or old.currency is distinct from new.currency
     or old.meaning_statement is distinct from new.meaning_statement
     or old.input_sha256 is distinct from new.input_sha256
     or old.provenance is distinct from new.provenance
     or old.metadata is distinct from new.metadata
     or old.created_by_user_id is distinct from new.created_by_user_id
     or old.created_at is distinct from new.created_at then
    raise exception 'Confirmed economic-event meaning is immutable; void and establish a new event to correct it.' using errcode='55000';
  end if;

  if old.resolution_state='voided' then
    raise exception 'Voided economic events cannot be revived or changed.' using errcode='55000';
  end if;

  if old.resolution_state='confirmed' and new.resolution_state='confirmed' then
    if new.voided_at is not null or new.voided_by_user_id is not null or new.void_reason is not null then
      raise exception 'Void metadata may only be supplied while voiding the event.' using errcode='55000';
    end if;
  elsif old.resolution_state='confirmed' and new.resolution_state='voided' then
    if new.voided_at is null or new.voided_by_user_id is null or nullif(btrim(new.void_reason),'') is null then
      raise exception 'Voiding an economic event requires actor, time, and reason.' using errcode='22023';
    end if;
  else
    raise exception 'Unsupported economic-event state transition.' using errcode='55000';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;
revoke all on function atlas.guard_financial_economic_event_mutation_v1() from public,anon,authenticated;

drop trigger if exists financial_economic_events_mutation_guard_v1 on atlas.financial_economic_events;
create trigger financial_economic_events_mutation_guard_v1
before update or delete on atlas.financial_economic_events
for each row execute function atlas.guard_financial_economic_event_mutation_v1();

create or replace function atlas.financial_evidence_record_authorized_self_v1(p_evidence_record_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_principal uuid;
  v_scope_kind text;
  v_scope_id uuid;
begin
  if auth.uid() is null or p_evidence_record_id is null then return false; end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then return false; end if;

  select evidence.scope_kind,evidence.scope_id
    into v_scope_kind,v_scope_id
  from atlas.evidence_records evidence
  where evidence.id=p_evidence_record_id;

  if v_scope_kind is null then return false; end if;
  if v_scope_kind='principal' then return v_scope_id=v_principal; end if;
  if v_scope_kind='ledger' then return atlas.principal_has_ledger_authority_v1(v_principal,v_scope_id); end if;
  if v_scope_kind='organization' then
    return exists(
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id=v_scope_id
        and membership.user_id=auth.uid()
        and atlas.organization_membership_present_effective_at_v1(
          membership.id,membership.organization_id,now()
        )
    ) or exists(
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id=v_scope_id
        and actor.human_user_id=auth.uid()
        and actor.active
    );
  end if;
  return false;
end;
$$;
revoke all on function atlas.financial_evidence_record_authorized_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.financial_evidence_record_authorized_self_v1(uuid) to authenticated,service_role;

create or replace function atlas.financial_evidence_target_authorized_self_v1(
  p_target_kind text,
  p_target_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_connected_source_id uuid;
  v_found boolean:=false;
  v_source uuid;
begin
  if auth.uid() is null or p_target_id is null then return false; end if;

  if p_target_kind='evidence_record' then
    return atlas.financial_evidence_record_authorized_self_v1(p_target_id);
  elsif p_target_kind='financial_transaction' then
    select transaction.connected_source_id into v_connected_source_id
    from atlas.financial_source_transactions transaction
    where transaction.id=p_target_id;
    return v_connected_source_id is not null
      and atlas.financial_connected_source_authorized_self_v1(v_connected_source_id);
  elsif p_target_kind='movement_match' then
    if not exists(select 1 from atlas.financial_source_movement_matches movement where movement.id=p_target_id) then
      return false;
    end if;
    for v_source in
      select distinct transaction.connected_source_id
      from atlas.financial_source_movement_match_members member
      join atlas.financial_source_transactions transaction
        on transaction.id=member.financial_transaction_id
      where member.movement_match_id=p_target_id
    loop
      v_found:=true;
      if not atlas.financial_connected_source_authorized_self_v1(v_source) then return false; end if;
    end loop;
    return v_found;
  end if;
  return false;
end;
$$;
revoke all on function atlas.financial_evidence_target_authorized_self_v1(text,uuid) from public,anon,authenticated;
grant execute on function atlas.financial_evidence_target_authorized_self_v1(text,uuid) to authenticated,service_role;

create or replace function atlas.financial_economic_event_authorized_self_v1(p_economic_event_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_allocation record;
  v_has_source boolean:=false;
begin
  if auth.uid() is null or p_economic_event_id is null then return false; end if;
  if not exists(select 1 from atlas.financial_economic_events event where event.id=p_economic_event_id) then return false; end if;

  for v_allocation in
    select allocation.financial_transaction_id,allocation.movement_match_id
    from atlas.financial_economic_event_source_allocations allocation
    where allocation.economic_event_id=p_economic_event_id
  loop
    v_has_source:=true;
    if v_allocation.financial_transaction_id is not null then
      if not atlas.financial_evidence_target_authorized_self_v1('financial_transaction',v_allocation.financial_transaction_id) then
        return false;
      end if;
    else
      if not atlas.financial_evidence_target_authorized_self_v1('movement_match',v_allocation.movement_match_id) then
        return false;
      end if;
    end if;
  end loop;
  return v_has_source;
end;
$$;
revoke all on function atlas.financial_economic_event_authorized_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.financial_economic_event_authorized_self_v1(uuid) to authenticated,service_role;

create or replace function atlas.establish_financial_economic_event_self_api_v1(
  p_event_key text,
  p_occurred_on date,
  p_occurred_at timestamptz,
  p_event_amount numeric,
  p_currency text,
  p_meaning_statement text,
  p_source_allocations jsonb,
  p_evidence_links jsonb default '[]'::jsonb,
  p_parties jsonb default '[]'::jsonb,
  p_dimensions jsonb default '[]'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth,extensions
as $$
declare
  v_principal uuid;
  v_key text:=btrim(coalesce(p_event_key,''));
  v_currency text:=upper(btrim(coalesce(p_currency,'')));
  v_meaning text:=btrim(coalesce(p_meaning_statement,''));
  v_input_hash text;
  v_existing atlas.financial_economic_events%rowtype;
  v_event atlas.financial_economic_events%rowtype;
  v_item jsonb;
  v_source_kind text;
  v_source_id uuid;
  v_source_token text;
  v_seen_sources text[]:='{}'::text[];
  v_amount numeric;
  v_total numeric:=0;
  v_transaction atlas.financial_source_transactions%rowtype;
  v_movement atlas.financial_source_movement_matches%rowtype;
  v_movement_matched numeric;
  v_economic_allocated numeric;
  v_link_key text;
  v_relation text;
  v_seen_link_keys text[]:='{}'::text[];
  v_entity_id uuid;
  v_role text;
  v_party_token text;
  v_seen_parties text[]:='{}'::text[];
  v_dimension_kind text;
  v_domain text;
  v_kind text;
  v_subject_id text;
  v_dimension_token text;
  v_seen_dimensions text[]:='{}'::text[];
  v_ordinal integer;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then raise exception 'Canonical Principal context required.' using errcode='42501'; end if;

  if v_key='' or p_occurred_on is null or p_event_amount is null or p_event_amount<=0
     or v_currency !~ '^[A-Z]{3}$' or v_meaning='' then
    raise exception 'Event key, date, positive amount, three-letter currency, and meaning statement are required.' using errcode='22023';
  end if;
  if p_source_allocations is null or jsonb_typeof(p_source_allocations)<>'array'
     or jsonb_array_length(p_source_allocations)=0 or jsonb_array_length(p_source_allocations)>50 then
    raise exception 'One to fifty monetary source allocations are required.' using errcode='22023';
  end if;
  if p_evidence_links is null or jsonb_typeof(p_evidence_links)<>'array' or jsonb_array_length(p_evidence_links)>100
     or p_parties is null or jsonb_typeof(p_parties)<>'array' or jsonb_array_length(p_parties)>50
     or p_dimensions is null or jsonb_typeof(p_dimensions)<>'array' or jsonb_array_length(p_dimensions)>50 then
    raise exception 'Evidence links, parties, and dimensions must be bounded JSON arrays.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Provenance and metadata must be JSON objects.' using errcode='22023';
  end if;

  v_input_hash:=encode(extensions.digest(convert_to(
    jsonb_build_object(
      'occurredOn',p_occurred_on,
      'occurredAt',p_occurred_at,
      'eventAmount',p_event_amount,
      'currency',v_currency,
      'meaningStatement',v_meaning,
      'sourceAllocations',p_source_allocations,
      'evidenceLinks',p_evidence_links,
      'parties',p_parties,
      'dimensions',p_dimensions,
      'provenance',p_provenance,
      'metadata',p_metadata
    )::text,'utf8'
  ),'sha256'),'hex');

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_economic_event:'||v_principal::text||':'||v_key,0
  ));

  select * into v_existing
  from atlas.financial_economic_events event
  where event.created_by_principal_id=v_principal and event.event_key=v_key
  for update;

  if v_existing.id is not null then
    if v_existing.input_sha256<>v_input_hash then
      raise exception 'Economic-event key already exists with different immutable meaning or evidence.' using errcode='23505';
    end if;
    if not atlas.financial_economic_event_authorized_self_v1(v_existing.id) then
      raise exception 'Current authority over every monetary source is required.' using errcode='42501';
    end if;
    return jsonb_build_object(
      'contractVersion','financial_economic_event_v1',
      'state','unchanged',
      'economicEventId',v_existing.id,
      'resolutionState',v_existing.resolution_state,
      'eventAmount',v_existing.event_amount,
      'currency',v_existing.currency,
      'meaningStatement',v_existing.meaning_statement,
      'truthBoundary',jsonb_build_object(
        'sourceEvidencePreserved',true,
        'movementIdentityChanged',false,
        'economicMeaningEstablished',v_existing.resolution_state='confirmed',
        'obligationSettlementEstablished',false,
        'accountingTreatmentEstablished',false,
        'journalPosted',false
      )
    );
  end if;

  -- Lock and consume only monetary source capacity. Witness links below never consume amount.
  for v_item in select value from jsonb_array_elements(p_source_allocations)
  loop
    if jsonb_typeof(v_item)<>'object' then
      raise exception 'Each source allocation must be an object.' using errcode='22023';
    end if;
    v_source_kind:=lower(btrim(coalesce(v_item->>'sourceKind','')));
    if v_source_kind not in ('financial_transaction','movement_match') then
      raise exception 'Source allocation kind must be financial_transaction or movement_match.' using errcode='22023';
    end if;
    begin
      v_source_id:=(v_item->>'sourceId')::uuid;
      v_amount:=(v_item->>'attributedAmount')::numeric;
    exception when others then
      raise exception 'Each source allocation requires UUID sourceId and numeric attributedAmount.' using errcode='22023';
    end;
    if v_source_id is null or v_amount is null or v_amount<=0 then
      raise exception 'Source allocation amount must be positive.' using errcode='22023';
    end if;
    v_source_token:=v_source_kind||':'||v_source_id::text;
    if v_source_token=any(v_seen_sources) then
      raise exception 'A monetary source may appear only once in one economic event.' using errcode='22023';
    end if;
    v_seen_sources:=array_append(v_seen_sources,v_source_token);
    v_total:=v_total+v_amount;

    if v_source_kind='financial_transaction' then
      select * into v_transaction
      from atlas.financial_source_transactions transaction
      where transaction.id=v_source_id
      for update;
      if v_transaction.id is null then raise exception 'Financial source transaction not found.' using errcode='23503'; end if;
      if not atlas.financial_connected_source_authorized_self_v1(v_transaction.connected_source_id) then
        raise exception 'Financial source authority required.' using errcode='42501';
      end if;
      if v_transaction.transaction_state<>'observed' then
        raise exception 'Only observed source transactions can supply confirmed economic capacity.' using errcode='23514';
      end if;
      if v_transaction.currency<>v_currency then
        raise exception 'Economic event and monetary source must share one currency.' using errcode='23514';
      end if;

      select coalesce(sum(member.matched_amount),0) into v_movement_matched
      from atlas.financial_source_movement_match_members member
      join atlas.financial_source_movement_matches movement
        on movement.id=member.movement_match_id and movement.match_state='confirmed'
      where member.financial_transaction_id=v_source_id;

      select coalesce(sum(allocation.attributed_amount),0) into v_economic_allocated
      from atlas.financial_economic_event_source_allocations allocation
      join atlas.financial_economic_events event
        on event.id=allocation.economic_event_id and event.resolution_state='confirmed'
      where allocation.financial_transaction_id=v_source_id;

      if v_movement_matched+v_economic_allocated+v_amount>abs(v_transaction.source_amount) then
        raise exception 'Economic attribution exceeds the unreconciled residual of the source transaction.' using errcode='23514';
      end if;
    else
      select * into v_movement
      from atlas.financial_source_movement_matches movement
      where movement.id=v_source_id
      for update;
      if v_movement.id is null then raise exception 'Source movement match not found.' using errcode='23503'; end if;
      if v_movement.match_state<>'confirmed' then
        raise exception 'Only confirmed source movements can supply economic-event capacity.' using errcode='23514';
      end if;
      if v_movement.currency<>v_currency then
        raise exception 'Economic event and source movement must share one currency.' using errcode='23514';
      end if;
      if not atlas.financial_evidence_target_authorized_self_v1('movement_match',v_source_id) then
        raise exception 'Authority over every movement source is required.' using errcode='42501';
      end if;

      select coalesce(sum(allocation.attributed_amount),0) into v_economic_allocated
      from atlas.financial_economic_event_source_allocations allocation
      join atlas.financial_economic_events event
        on event.id=allocation.economic_event_id and event.resolution_state='confirmed'
      where allocation.movement_match_id=v_source_id;

      if v_economic_allocated+v_amount>v_movement.movement_amount then
        raise exception 'Economic attribution exceeds the confirmed movement amount.' using errcode='23514';
      end if;
    end if;
  end loop;

  if v_total<>p_event_amount then
    raise exception 'Monetary source allocations must equal the economic event amount exactly.' using errcode='23514';
  end if;

  -- Validate non-consuming witness links. Contradictory evidence is retained, not merged away.
  for v_item in select value from jsonb_array_elements(p_evidence_links)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each evidence link must be an object.' using errcode='22023'; end if;
    v_link_key:=btrim(coalesce(v_item->>'linkKey',''));
    v_source_kind:=lower(btrim(coalesce(v_item->>'evidenceKind','')));
    v_relation:=lower(btrim(coalesce(v_item->>'relationKind','')));
    if v_link_key='' or v_source_kind not in ('evidence_record','financial_transaction','movement_match')
       or v_relation not in ('supports','contradicts','context') then
      raise exception 'Evidence link requires key, supported target kind, and supports/contradicts/context relation.' using errcode='22023';
    end if;
    begin v_source_id:=(v_item->>'evidenceId')::uuid;
    exception when others then raise exception 'Evidence link evidenceId must be a UUID.' using errcode='22023'; end;
    if v_source_id is null or not atlas.financial_evidence_target_authorized_self_v1(v_source_kind,v_source_id) then
      raise exception 'Evidence target not found or not authorized.' using errcode='42501';
    end if;
    if v_link_key=any(v_seen_link_keys) then raise exception 'Evidence link keys must be unique within an event.' using errcode='22023'; end if;
    v_seen_link_keys:=array_append(v_seen_link_keys,v_link_key);
  end loop;

  for v_item in select value from jsonb_array_elements(p_parties)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each party must be an object.' using errcode='22023'; end if;
    begin v_entity_id:=(v_item->>'entityId')::uuid;
    exception when others then raise exception 'Economic-event party entityId must be a UUID.' using errcode='22023'; end;
    v_role:=lower(btrim(coalesce(v_item->>'roleKind','')));
    if v_entity_id is null or v_role not in (
      'payer','payee','principal','agent','processor','merchant','platform','owner','beneficiary',
      'donor','recipient','customer','vendor','employer','employee','borrower','lender','counterparty','other'
    ) then raise exception 'Economic-event party requires a canonical entity and supported role.' using errcode='22023'; end if;
    if not exists(select 1 from reality.entities entity where entity.id=v_entity_id and entity.identity_state='canonical') then
      raise exception 'Economic-event parties must be canonical Reality entities.' using errcode='23514';
    end if;
    v_party_token:=v_entity_id::text||':'||v_role;
    if v_party_token=any(v_seen_parties) then raise exception 'Duplicate economic-event party role.' using errcode='22023'; end if;
    v_seen_parties:=array_append(v_seen_parties,v_party_token);
  end loop;

  for v_item in select value from jsonb_array_elements(p_dimensions)
  loop
    if jsonb_typeof(v_item)<>'object' then raise exception 'Each dimension must be an object.' using errcode='22023'; end if;
    v_dimension_kind:=lower(btrim(coalesce(v_item->>'dimensionKind','')));
    if v_dimension_kind not in ('business_context','property','activity','project','location','contract','fund','other') then
      raise exception 'Unsupported economic-event dimension kind.' using errcode='22023';
    end if;
    begin v_entity_id:=nullif(v_item->>'entityId','')::uuid;
    exception when others then raise exception 'Dimension entityId must be a UUID.' using errcode='22023'; end;
    v_domain:=nullif(btrim(coalesce(v_item->>'subjectDomain','')),'');
    v_kind:=nullif(btrim(coalesce(v_item->>'subjectKind','')),'');
    v_subject_id:=nullif(btrim(coalesce(v_item->>'subjectId','')),'');
    if not (
      (v_entity_id is not null and v_domain is null and v_kind is null and v_subject_id is null)
      or
      (v_entity_id is null and v_domain is not null and v_kind is not null and v_subject_id is not null)
    ) then raise exception 'Dimension must target either one canonical entity or one complete generic subject triple.' using errcode='22023'; end if;
    if v_entity_id is not null and not exists(
      select 1 from reality.entities entity where entity.id=v_entity_id and entity.identity_state='canonical'
    ) then raise exception 'Dimension entity target must be canonical Reality.' using errcode='23514'; end if;
    v_dimension_token:=v_dimension_kind||':'||coalesce(v_entity_id::text,v_domain||':'||v_kind||':'||v_subject_id);
    if v_dimension_token=any(v_seen_dimensions) then raise exception 'Duplicate economic-event dimension.' using errcode='22023'; end if;
    v_seen_dimensions:=array_append(v_seen_dimensions,v_dimension_token);
  end loop;

  insert into atlas.financial_economic_events(
    created_by_principal_id,event_key,occurred_on,occurred_at,event_amount,currency,
    meaning_statement,resolution_state,input_sha256,provenance,metadata,created_by_user_id
  ) values (
    v_principal,v_key,p_occurred_on,p_occurred_at,p_event_amount,v_currency,
    v_meaning,'confirmed',v_input_hash,
    p_provenance||jsonb_build_object(
      'authority','establish_financial_economic_event_self_api_v1',
      'sourceEvidencePreserved',true,
      'movementIdentityChanged',false,
      'obligationSettlementEstablished',false,
      'accountingTreatmentEstablished',false,
      'journalPosted',false
    ),p_metadata,auth.uid()
  ) returning * into v_event;

  v_ordinal:=0;
  for v_item in select value from jsonb_array_elements(p_source_allocations)
  loop
    v_ordinal:=v_ordinal+1;
    v_source_kind:=lower(btrim(v_item->>'sourceKind'));
    v_source_id:=(v_item->>'sourceId')::uuid;
    insert into atlas.financial_economic_event_source_allocations(
      economic_event_id,allocation_ordinal,financial_transaction_id,movement_match_id,
      attributed_amount,provenance,metadata
    ) values (
      v_event.id,v_ordinal,
      case when v_source_kind='financial_transaction' then v_source_id end,
      case when v_source_kind='movement_match' then v_source_id end,
      (v_item->>'attributedAmount')::numeric,
      jsonb_build_object('authority','establish_financial_economic_event_self_api_v1'),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb) else '{}'::jsonb end
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_evidence_links)
  loop
    v_link_key:=btrim(v_item->>'linkKey');
    v_source_kind:=lower(btrim(v_item->>'evidenceKind'));
    v_source_id:=(v_item->>'evidenceId')::uuid;
    insert into atlas.financial_economic_event_evidence_links(
      economic_event_id,link_key,evidence_record_id,financial_transaction_id,movement_match_id,
      relation_kind,note,provenance,metadata,linked_by_principal_id,linked_by_user_id
    ) values (
      v_event.id,v_link_key,
      case when v_source_kind='evidence_record' then v_source_id end,
      case when v_source_kind='financial_transaction' then v_source_id end,
      case when v_source_kind='movement_match' then v_source_id end,
      lower(btrim(v_item->>'relationKind')),
      nullif(btrim(coalesce(v_item->>'note','')),''),
      jsonb_build_object('authority','establish_financial_economic_event_self_api_v1'),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb) else '{}'::jsonb end,
      v_principal,auth.uid()
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_parties)
  loop
    insert into atlas.financial_economic_event_parties(
      economic_event_id,entity_id,role_kind,provenance,metadata
    ) values (
      v_event.id,(v_item->>'entityId')::uuid,lower(btrim(v_item->>'roleKind')),
      jsonb_build_object('authority','establish_financial_economic_event_self_api_v1'),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb) else '{}'::jsonb end
    );
  end loop;

  v_ordinal:=0;
  for v_item in select value from jsonb_array_elements(p_dimensions)
  loop
    v_ordinal:=v_ordinal+1;
    insert into atlas.financial_economic_event_dimensions(
      economic_event_id,dimension_ordinal,dimension_kind,entity_id,
      subject_domain,subject_kind,subject_id,provenance,metadata
    ) values (
      v_event.id,v_ordinal,lower(btrim(v_item->>'dimensionKind')),
      nullif(v_item->>'entityId','')::uuid,
      nullif(btrim(coalesce(v_item->>'subjectDomain','')),''),
      nullif(btrim(coalesce(v_item->>'subjectKind','')),''),
      nullif(btrim(coalesce(v_item->>'subjectId','')),''),
      jsonb_build_object('authority','establish_financial_economic_event_self_api_v1'),
      case when jsonb_typeof(coalesce(v_item->'metadata','{}'::jsonb))='object'
        then coalesce(v_item->'metadata','{}'::jsonb) else '{}'::jsonb end
    );
  end loop;

  return jsonb_build_object(
    'contractVersion','financial_economic_event_v1',
    'state','confirmed',
    'economicEventId',v_event.id,
    'eventAmount',v_event.event_amount,
    'currency',v_event.currency,
    'meaningStatement',v_event.meaning_statement,
    'sourceAllocationCount',jsonb_array_length(p_source_allocations),
    'evidenceLinkCount',jsonb_array_length(p_evidence_links),
    'truthBoundary',jsonb_build_object(
      'sourceEvidencePreserved',true,
      'movementIdentityChanged',false,
      'economicMeaningEstablished',true,
      'obligationSettlementEstablished',false,
      'accountingTreatmentEstablished',false,
      'journalPosted',false
    )
  );
end;
$$;

revoke all on function atlas.establish_financial_economic_event_self_api_v1(
  text,date,timestamptz,numeric,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb
) from public,anon;
grant execute on function atlas.establish_financial_economic_event_self_api_v1(
  text,date,timestamptz,numeric,text,text,jsonb,jsonb,jsonb,jsonb,jsonb,jsonb
) to authenticated;

create or replace function atlas.link_financial_economic_event_evidence_self_api_v1(
  p_economic_event_id uuid,
  p_link_key text,
  p_evidence_kind text,
  p_evidence_id uuid,
  p_relation_kind text,
  p_note text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_key text:=btrim(coalesce(p_link_key,''));
  v_kind text:=lower(btrim(coalesce(p_evidence_kind,'')));
  v_relation text:=lower(btrim(coalesce(p_relation_kind,'')));
  v_principal uuid;
  v_existing atlas.financial_economic_event_evidence_links%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  v_principal:=atlas.current_principal_id_v1();
  if v_principal is null then raise exception 'Canonical Principal context required.' using errcode='42501'; end if;
  if p_economic_event_id is null or v_key='' or p_evidence_id is null
     or v_kind not in ('evidence_record','financial_transaction','movement_match')
     or v_relation not in ('supports','contradicts','context') then
    raise exception 'Event, link key, evidence target, and supported relation are required.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Evidence-link metadata must be a JSON object.' using errcode='22023';
  end if;
  if not atlas.financial_economic_event_authorized_self_v1(p_economic_event_id) then
    raise exception 'Authority over the economic event monetary sources is required.' using errcode='42501';
  end if;
  if not atlas.financial_evidence_target_authorized_self_v1(v_kind,p_evidence_id) then
    raise exception 'Evidence target not found or not authorized.' using errcode='42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.financial_economic_event_evidence:'||p_economic_event_id::text||':'||v_key,0
  ));

  select * into v_existing
  from atlas.financial_economic_event_evidence_links link
  where link.economic_event_id=p_economic_event_id and link.link_key=v_key;

  if v_existing.id is not null then
    if v_existing.evidence_record_id is distinct from case when v_kind='evidence_record' then p_evidence_id end
       or v_existing.financial_transaction_id is distinct from case when v_kind='financial_transaction' then p_evidence_id end
       or v_existing.movement_match_id is distinct from case when v_kind='movement_match' then p_evidence_id end
       or v_existing.relation_kind<>v_relation
       or v_existing.note is distinct from nullif(btrim(coalesce(p_note,'')),'')
       or v_existing.metadata<>p_metadata then
      raise exception 'Evidence link key already exists with different immutable facts.' using errcode='23505';
    end if;
    return jsonb_build_object('contractVersion','financial_economic_event_evidence_link_v1','state','unchanged','evidenceLinkId',v_existing.id);
  end if;

  insert into atlas.financial_economic_event_evidence_links(
    economic_event_id,link_key,evidence_record_id,financial_transaction_id,movement_match_id,
    relation_kind,note,provenance,metadata,linked_by_principal_id,linked_by_user_id
  ) values (
    p_economic_event_id,v_key,
    case when v_kind='evidence_record' then p_evidence_id end,
    case when v_kind='financial_transaction' then p_evidence_id end,
    case when v_kind='movement_match' then p_evidence_id end,
    v_relation,nullif(btrim(coalesce(p_note,'')),''),
    jsonb_build_object('authority','link_financial_economic_event_evidence_self_api_v1'),
    p_metadata,v_principal,auth.uid()
  ) returning * into v_existing;

  return jsonb_build_object('contractVersion','financial_economic_event_evidence_link_v1','state','linked','evidenceLinkId',v_existing.id);
end;
$$;

revoke all on function atlas.link_financial_economic_event_evidence_self_api_v1(uuid,text,text,uuid,text,text,jsonb)
  from public,anon;
grant execute on function atlas.link_financial_economic_event_evidence_self_api_v1(uuid,text,text,uuid,text,text,jsonb)
  to authenticated;

create or replace function atlas.void_financial_economic_event_self_api_v1(
  p_economic_event_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $$
declare
  v_event atlas.financial_economic_events%rowtype;
  v_reason text:=btrim(coalesce(p_reason,''));
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode='42501'; end if;
  if p_economic_event_id is null or v_reason='' then raise exception 'Economic event and void reason are required.' using errcode='22023'; end if;
  if not atlas.financial_economic_event_authorized_self_v1(p_economic_event_id) then
    raise exception 'Authority over the economic event monetary sources is required.' using errcode='42501';
  end if;

  select * into v_event
  from atlas.financial_economic_events event
  where event.id=p_economic_event_id
  for update;
  if v_event.id is null then raise exception 'Economic event not found.' using errcode='23503'; end if;
  if v_event.resolution_state='voided' then
    return jsonb_build_object('contractVersion','void_financial_economic_event_self_api_v1','state','unchanged','economicEventId',v_event.id);
  end if;

  update atlas.financial_economic_events event
  set resolution_state='voided',voided_at=now(),voided_by_user_id=auth.uid(),void_reason=v_reason
  where event.id=p_economic_event_id
  returning * into v_event;

  return jsonb_build_object('contractVersion','void_financial_economic_event_self_api_v1','state','voided','economicEventId',v_event.id,'voidedAt',v_event.voided_at);
end;
$$;

revoke all on function atlas.void_financial_economic_event_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.void_financial_economic_event_self_api_v1(uuid,text) to authenticated;

-- Provider/source refresh cannot invalidate already-confirmed direct economic allocations. Matched
-- movement capacity and direct economic capacity are additive consumers of the source-row magnitude.
create or replace function atlas.guard_financial_source_transaction_economic_resolution_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_direct numeric;
  v_matched numeric;
begin
  select coalesce(sum(allocation.attributed_amount),0) into v_direct
  from atlas.financial_economic_event_source_allocations allocation
  join atlas.financial_economic_events event
    on event.id=allocation.economic_event_id and event.resolution_state='confirmed'
  where allocation.financial_transaction_id=old.id;

  if v_direct>0 then
    select coalesce(sum(member.matched_amount),0) into v_matched
    from atlas.financial_source_movement_match_members member
    join atlas.financial_source_movement_matches movement
      on movement.id=member.movement_match_id and movement.match_state='confirmed'
    where member.financial_transaction_id=old.id;

    if new.transaction_state='voided' and old.transaction_state<>'voided' then
      raise exception 'Void economic resolutions before voiding their source transaction.' using errcode='55000';
    end if;
    if new.currency<>old.currency then
      raise exception 'An economically resolved source transaction cannot change currency.' using errcode='55000';
    end if;
    if v_direct+v_matched>abs(new.source_amount) then
      raise exception 'Provider refresh would reduce a source transaction below confirmed movement plus economic allocation.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_source_transaction_economic_resolution_v1() from public,anon,authenticated;

drop trigger if exists financial_source_transactions_economic_resolution_guard_v1 on atlas.financial_source_transactions;
create trigger financial_source_transactions_economic_resolution_guard_v1
before update on atlas.financial_source_transactions
for each row execute function atlas.guard_financial_source_transaction_economic_resolution_v1();

create or replace function atlas.guard_financial_source_movement_economic_resolution_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.match_state='confirmed' and new.match_state='voided' and exists(
    select 1
    from atlas.financial_economic_event_source_allocations allocation
    join atlas.financial_economic_events event
      on event.id=allocation.economic_event_id and event.resolution_state='confirmed'
    where allocation.movement_match_id=old.id
  ) then
    raise exception 'Void economic resolutions before voiding their source movement match.' using errcode='55000';
  end if;
  return new;
end;
$$;
revoke all on function atlas.guard_financial_source_movement_economic_resolution_v1() from public,anon,authenticated;

drop trigger if exists financial_source_movement_economic_resolution_guard_v1 on atlas.financial_source_movement_matches;
create trigger financial_source_movement_economic_resolution_guard_v1
before update of match_state on atlas.financial_source_movement_matches
for each row execute function atlas.guard_financial_source_movement_economic_resolution_v1();

comment on table atlas.financial_economic_events is
  'Operator-confirmed economic meaning for financial evidence. The event is not a bank row, movement match, obligation, settlement, accounting classification, or journal entry.';
comment on table atlas.financial_economic_event_source_allocations is
  'Monetary source capacity consumed by an economic event. Confirmed movement-matched capacity must be resolved through the movement; only unmatched source-transaction residual may be allocated directly.';
comment on table atlas.financial_economic_event_evidence_links is
  'Non-consuming witness links. Multiple supporting/context/contradictory witnesses may describe one economic event without multiplying its amount.';
comment on table atlas.financial_economic_event_parties is
  'Canonical Reality entities acting in event-specific capacities. Roles describe the event and do not establish accounting treatment.';
comment on table atlas.financial_economic_event_dimensions is
  'Structured context for an economic event. Canonical Reality entity targets are preferred when available; existing generic subject identities may be retained without inventing parallel entities.';

commit;
