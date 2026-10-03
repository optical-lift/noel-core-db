alter table ledger.booking_policies
  drop constraint if exists booking_policies_policy_kind_check;

alter table ledger.booking_policies
  add constraint booking_policies_policy_kind_check
  check (policy_kind = any (array['duration'::text,'booking_window'::text,'start_increment'::text,'buffer'::text,'approval'::text,'recurrence'::text,'commitment'::text]));

create table if not exists ledger.booking_agreements (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  agreement_key text not null check (btrim(agreement_key) <> ''),
  version integer not null check (version > 0),
  agreement_state text not null default 'draft' check (agreement_state in ('draft','issued','executed','superseded','void')),
  title text not null check (btrim(title) <> ''),
  offer_snapshot_id uuid null references atlas.commercial_offer_snapshots(id) on delete restrict,
  terms jsonb not null default '{}'::jsonb check (jsonb_typeof(terms)='object'),
  created_by_seat_id uuid not null references ledger.seats(id) on delete restrict,
  issued_at timestamptz null,
  executed_at timestamptz null,
  superseded_at timestamptz null,
  voided_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null check (idempotency_key is null or btrim(idempotency_key) <> ''),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (request_id, agreement_key, version)
);

create unique index if not exists booking_agreements_idempotency_uq
  on ledger.booking_agreements(request_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists booking_agreements_request_state_idx
  on ledger.booking_agreements(request_id,agreement_state,version desc);

create table if not exists ledger.booking_agreement_parties (
  id uuid primary key default gen_random_uuid(),
  agreement_id uuid not null references ledger.booking_agreements(id) on delete cascade,
  entity_id uuid not null references reality.entities(id) on delete restrict,
  party_role text not null check (btrim(party_role) <> ''),
  signature_required boolean not null default true,
  party_state text not null default 'pending' check (party_state in ('pending','accepted','declined','waived')),
  accepted_at timestamptz null,
  acceptance_method text null,
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (agreement_id,entity_id,party_role)
);

create or replace function ledger.guard_booking_policy_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare v_subject uuid;
begin
  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=new.ledger_id and l.ledger_state='active';

  if v_subject is null then
    raise exception 'Booking policy requires an active Ledger.' using errcode='23514';
  end if;

  if new.resource_id is not null and not exists(
    select 1 from reality.resources r
    where r.id=new.resource_id and r.owner_entity_id=v_subject and r.resource_state<>'retired'
  ) then
    raise exception 'Booking policy resource must belong to the Ledger subject Entity.'
      using errcode='23514';
  end if;

  if new.policy_kind='duration' then
    if (new.config ? 'minMinutes' and (new.config->>'minMinutes')::numeric < 0)
       or (new.config ? 'maxMinutes' and (new.config->>'maxMinutes')::numeric <= 0)
       or (
         new.config ? 'minMinutes' and new.config ? 'maxMinutes'
         and (new.config->>'maxMinutes')::numeric < (new.config->>'minMinutes')::numeric
       ) then
      raise exception 'Invalid duration policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='booking_window' then
    if (new.config ? 'minNoticeMinutes' and (new.config->>'minNoticeMinutes')::numeric < 0)
       or (new.config ? 'maxAdvanceMinutes' and (new.config->>'maxAdvanceMinutes')::numeric < 0) then
      raise exception 'Invalid booking-window policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='start_increment' then
    if not (new.config ? 'minutes') or (new.config->>'minutes')::integer <= 0 then
      raise exception 'Start-increment policy requires minutes > 0.' using errcode='22023';
    end if;
  elsif new.policy_kind='buffer' then
    if (new.config ? 'setupMinutes' and (new.config->>'setupMinutes')::numeric < 0)
       or (new.config ? 'teardownMinutes' and (new.config->>'teardownMinutes')::numeric < 0) then
      raise exception 'Invalid buffer policy config.' using errcode='22023';
    end if;
  elsif new.policy_kind='approval' then
    if new.config ? 'required' and jsonb_typeof(new.config->'required')<>'boolean' then
      raise exception 'Approval required must be boolean.' using errcode='22023';
    end if;
  elsif new.policy_kind='recurrence' then
    if new.config ? 'allowed' and jsonb_typeof(new.config->'allowed')<>'boolean' then
      raise exception 'Recurrence allowed must be boolean.' using errcode='22023';
    end if;
  elsif new.policy_kind='commitment' then
    if new.config ? 'agreementRequired' and jsonb_typeof(new.config->'agreementRequired')<>'boolean' then
      raise exception 'Commitment agreementRequired must be boolean.' using errcode='22023';
    end if;
  end if;

  return new;
end;
$function$;

create or replace function ledger.evaluate_booking_policies_v1(
  p_ledger_id uuid,
  p_resource_ids uuid[],
  p_booking_kind text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_is_recurring boolean default false,
  p_as_of timestamptz default now()
)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_policy ledger.booking_policies%rowtype;
  v_duration numeric;
  v_blockers jsonb:='[]'::jsonb;
  v_applied jsonb:='[]'::jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_approval boolean:=false;
  v_agreement boolean:=false;
  v_tz text:='UTC';
  v_local_start timestamp;
  v_increment integer;
  v_minute_of_day integer;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Booking policy window must have starts_at < ends_at.' using errcode='22023';
  end if;

  v_duration:=extract(epoch from (p_ends_at-p_starts_at))/60.0;

  if p_resource_ids is not null and cardinality(p_resource_ids)>0 then
    select coalesce(r.timezone_name,'UTC') into v_tz
    from reality.resources r where r.id=p_resource_ids[1];
  end if;

  for v_policy in
    select p.*
    from ledger.booking_policies p
    where p.ledger_id=p_ledger_id
      and p.policy_state='active'
      and (p.booking_kind is null or p.booking_kind=p_booking_kind)
      and (p.resource_id is null or p.resource_id=any(coalesce(p_resource_ids,'{}'::uuid[])))
    order by p.priority desc,p.stable_key,p.id
  loop
    v_applied:=v_applied||jsonb_build_array(jsonb_build_object(
      'policyId',v_policy.id,'stableKey',v_policy.stable_key,'policyKind',v_policy.policy_kind
    ));

    if v_policy.policy_kind='duration' then
      if v_policy.config ? 'minMinutes'
         and v_duration < (v_policy.config->>'minMinutes')::numeric then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','duration_too_short','policyId',v_policy.id,'minimumMinutes',(v_policy.config->>'minMinutes')::numeric
        ));
      end if;
      if v_policy.config ? 'maxMinutes'
         and v_duration > (v_policy.config->>'maxMinutes')::numeric then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','duration_too_long','policyId',v_policy.id,'maximumMinutes',(v_policy.config->>'maxMinutes')::numeric
        ));
      end if;

    elsif v_policy.policy_kind='booking_window' then
      if v_policy.config ? 'minNoticeMinutes'
         and p_starts_at < p_as_of + make_interval(mins=>(v_policy.config->>'minNoticeMinutes')::integer) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','minimum_notice_not_met','policyId',v_policy.id,'minimumNoticeMinutes',(v_policy.config->>'minNoticeMinutes')::integer
        ));
      end if;
      if v_policy.config ? 'maxAdvanceMinutes'
         and p_starts_at > p_as_of + make_interval(mins=>(v_policy.config->>'maxAdvanceMinutes')::integer) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','maximum_advance_exceeded','policyId',v_policy.id,'maximumAdvanceMinutes',(v_policy.config->>'maxAdvanceMinutes')::integer
        ));
      end if;

    elsif v_policy.policy_kind='start_increment' then
      v_increment:=(v_policy.config->>'minutes')::integer;
      v_local_start:=p_starts_at at time zone coalesce(nullif(v_policy.config->>'timezoneName',''),v_tz);
      v_minute_of_day:=extract(hour from v_local_start)::integer*60+extract(minute from v_local_start)::integer;
      if mod(v_minute_of_day-coalesce((v_policy.config->>'offsetMinutes')::integer,0),v_increment)<>0
         or extract(second from v_local_start)<>0 then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','start_increment_mismatch','policyId',v_policy.id,'incrementMinutes',v_increment
        ));
      end if;

    elsif v_policy.policy_kind='buffer' then
      v_setup:=greatest(v_setup,coalesce((v_policy.config->>'setupMinutes')::integer,0));
      v_teardown:=greatest(v_teardown,coalesce((v_policy.config->>'teardownMinutes')::integer,0));

    elsif v_policy.policy_kind='approval' then
      if coalesce((v_policy.config->>'required')::boolean,false) then
        v_approval:=true;
      end if;

    elsif v_policy.policy_kind='recurrence' then
      if p_is_recurring and not coalesce((v_policy.config->>'allowed')::boolean,true) then
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'reasonCode','recurrence_not_allowed','policyId',v_policy.id
        ));
      end if;

    elsif v_policy.policy_kind='commitment' then
      if coalesce((v_policy.config->>'agreementRequired')::boolean,false) then
        v_agreement:=true;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_booking_policy_evaluation_v2',
    'ledgerId',p_ledger_id,
    'bookingKind',p_booking_kind,
    'allowed',jsonb_array_length(v_blockers)=0,
    'blockingReasons',v_blockers,
    'appliedPolicies',v_applied,
    'requirements',jsonb_build_object(
      'setupBufferMinutes',v_setup,
      'teardownBufferMinutes',v_teardown,
      'approvalRequired',v_approval,
      'agreementRequired',v_agreement
    )
  );
end;
$function$;

create or replace function ledger.guard_booking_agreement_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_ledger_id uuid;
  v_seat_ledger uuid;
begin
  select br.ledger_id into v_ledger_id
  from ledger.booking_requests br where br.id=new.request_id;
  if v_ledger_id is null then
    raise exception 'Booking agreement requires a valid booking request.' using errcode='23514';
  end if;

  select s.ledger_id into v_seat_ledger
  from ledger.seats s where s.id=new.created_by_seat_id and s.seat_state='active';
  if v_seat_ledger is null or v_seat_ledger<>v_ledger_id then
    raise exception 'Booking agreement creator must have an active Seat in the request Ledger.' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    if new.request_id<>old.request_id
       or new.agreement_key<>old.agreement_key
       or new.version<>old.version
       or new.title<>old.title
       or new.offer_snapshot_id is distinct from old.offer_snapshot_id
       or new.terms is distinct from old.terms
       or new.created_by_seat_id<>old.created_by_seat_id
       or new.idempotency_key is distinct from old.idempotency_key then
      raise exception 'Booking agreement identity and terms are immutable after creation.' using errcode='23514';
    end if;
    if old.agreement_state<>new.agreement_state and not (
      (old.agreement_state='draft' and new.agreement_state in ('issued','void'))
      or (old.agreement_state='issued' and new.agreement_state in ('executed','superseded','void'))
      or (old.agreement_state='executed' and new.agreement_state='superseded')
    ) then
      raise exception 'Invalid booking agreement transition: % -> %',old.agreement_state,new.agreement_state using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create or replace function ledger.guard_booking_agreement_party_v1()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if not exists(select 1 from reality.entities e where e.id=new.entity_id and e.identity_state='canonical') then
    raise exception 'Agreement party must be a canonical Reality Entity.' using errcode='23514';
  end if;
  if tg_op='UPDATE' then
    if new.agreement_id<>old.agreement_id
       or new.entity_id<>old.entity_id
       or new.party_role<>old.party_role
       or new.signature_required<>old.signature_required then
      raise exception 'Booking agreement party identity is immutable.' using errcode='23514';
    end if;
    if old.party_state<>new.party_state and not (
      old.party_state='pending' and new.party_state in ('accepted','declined','waived')
    ) then
      raise exception 'Invalid booking agreement party transition: % -> %',old.party_state,new.party_state using errcode='23514';
    end if;
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

create trigger booking_agreements_guard_v1
before insert or update on ledger.booking_agreements
for each row execute function ledger.guard_booking_agreement_v1();

create trigger booking_agreement_parties_guard_v1
before insert or update on ledger.booking_agreement_parties
for each row execute function ledger.guard_booking_agreement_party_v1();

create or replace function ledger.booking_agreement_detail_v1(p_agreement_id uuid)
returns jsonb
language sql
stable security definer
set search_path to ''
as $function$
  select jsonb_build_object(
    'contractVersion','ledger_booking_agreement_v1',
    'agreementId',a.id,
    'requestId',a.request_id,
    'agreementKey',a.agreement_key,
    'version',a.version,
    'agreementState',a.agreement_state,
    'title',a.title,
    'offerSnapshotId',a.offer_snapshot_id,
    'terms',a.terms,
    'issuedAt',a.issued_at,
    'executedAt',a.executed_at,
    'metadata',a.metadata,
    'provenance',a.provenance,
    'createdAt',a.created_at,
    'parties',coalesce((
      select jsonb_agg(jsonb_build_object(
        'partyId',p.id,
        'entityId',p.entity_id,
        'displayName',e.display_name,
        'partyRole',p.party_role,
        'signatureRequired',p.signature_required,
        'partyState',p.party_state,
        'acceptedAt',p.accepted_at,
        'acceptanceMethod',p.acceptance_method,
        'evidence',p.evidence,
        'metadata',p.metadata
      ) order by p.party_role,e.display_name,p.id)
      from ledger.booking_agreement_parties p
      join reality.entities e on e.id=p.entity_id
      where p.agreement_id=a.id
    ),'[]'::jsonb)
  )
  from ledger.booking_agreements a
  where a.id=p_agreement_id;
$function$;

create or replace function ledger.create_booking_agreement_service_v1(
  p_request_id uuid,
  p_agreement_key text,
  p_title text,
  p_terms jsonb,
  p_required_parties jsonb,
  p_created_by_seat_id uuid,
  p_offer_snapshot_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_version integer;
  v_agreement_id uuid;
  v_existing uuid;
  v_party jsonb;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state not in ('submitted','approved') then
    raise exception 'Agreement may only be prepared for a submitted or approved request.' using errcode='23514';
  end if;
  if nullif(btrim(p_agreement_key),'') is null or nullif(btrim(p_title),'') is null then
    raise exception 'Agreement key and title are required.' using errcode='22023';
  end if;
  if p_terms is null or jsonb_typeof(p_terms)<>'object'
     or p_required_parties is null or jsonb_typeof(p_required_parties)<>'array'
     or p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Agreement terms/metadata/provenance must be objects and parties must be an array.' using errcode='22023';
  end if;
  if jsonb_array_length(p_required_parties)=0 then
    raise exception 'Agreement requires at least one party.' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_required_parties) x where nullif(x->>'entityId','') is null) then
    raise exception 'Every agreement party requires entityId.' using errcode='22023';
  end if;

  if nullif(btrim(p_idempotency_key),'') is not null then
    select a.id into v_existing from ledger.booking_agreements a
    where a.request_id=p_request_id and a.idempotency_key=btrim(p_idempotency_key);
    if v_existing is not null then return ledger.booking_agreement_detail_v1(v_existing); end if;
  end if;

  select coalesce(max(a.version),0)+1 into v_version
  from ledger.booking_agreements a
  where a.request_id=p_request_id and a.agreement_key=btrim(p_agreement_key);

  update ledger.booking_agreements
  set agreement_state='superseded',superseded_at=now()
  where request_id=p_request_id and agreement_key=btrim(p_agreement_key)
    and agreement_state in ('issued','executed');

  insert into ledger.booking_agreements(
    request_id,agreement_key,version,agreement_state,title,offer_snapshot_id,terms,
    created_by_seat_id,metadata,provenance,idempotency_key
  ) values(
    p_request_id,btrim(p_agreement_key),v_version,'draft',btrim(p_title),p_offer_snapshot_id,p_terms,
    p_created_by_seat_id,p_metadata,p_provenance,nullif(btrim(p_idempotency_key),'')
  ) returning id into v_agreement_id;

  for v_party in select value from jsonb_array_elements(p_required_parties)
  loop
    insert into ledger.booking_agreement_parties(
      agreement_id,entity_id,party_role,signature_required,metadata
    ) values(
      v_agreement_id,(v_party->>'entityId')::uuid,coalesce(nullif(btrim(v_party->>'partyRole'),''),'signer'),
      coalesce((v_party->>'signatureRequired')::boolean,true),coalesce(v_party->'metadata','{}'::jsonb)
    );
  end loop;

  perform ledger.append_booking_request_event_v1(
    p_request_id,'agreement.drafted',null,p_created_by_seat_id,
    jsonb_build_object('agreementId',v_agreement_id,'agreementKey',btrim(p_agreement_key),'version',v_version),
    p_provenance,
    case when nullif(btrim(p_idempotency_key),'') is null then null else btrim(p_idempotency_key)||':drafted' end,
    now()
  );
  return ledger.booking_agreement_detail_v1(v_agreement_id);
end;
$function$;

create or replace function ledger.issue_booking_agreement_service_v1(
  p_agreement_id uuid,
  p_issued_by_seat_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_agreement ledger.booking_agreements%rowtype;
  v_request ledger.booking_requests%rowtype;
  v_seat_ledger uuid;
begin
  select * into v_agreement from ledger.booking_agreements a where a.id=p_agreement_id for update;
  if v_agreement.id is null then raise exception 'Booking agreement not found.' using errcode='P0002'; end if;
  if v_agreement.agreement_state='issued' then return ledger.booking_agreement_detail_v1(p_agreement_id); end if;
  if v_agreement.agreement_state<>'draft' then
    raise exception 'Only draft agreements may be issued.' using errcode='23514';
  end if;
  select * into v_request from ledger.booking_requests br where br.id=v_agreement.request_id;
  if v_request.request_state not in ('submitted','approved') then
    raise exception 'Request is not in a state that permits agreement issuance.' using errcode='23514';
  end if;
  select s.ledger_id into v_seat_ledger from ledger.seats s
  where s.id=p_issued_by_seat_id and s.seat_state='active';
  if v_seat_ledger is null or v_seat_ledger<>v_request.ledger_id then
    raise exception 'Agreement issuer must have an active Seat in the request Ledger.' using errcode='42501';
  end if;
  if not exists(select 1 from ledger.booking_agreement_parties p where p.agreement_id=p_agreement_id and p.signature_required) then
    raise exception 'Issued agreement requires at least one required signer.' using errcode='23514';
  end if;

  update ledger.booking_agreements
  set agreement_state='issued',issued_at=now()
  where id=p_agreement_id;

  perform ledger.append_booking_request_event_v1(
    v_agreement.request_id,'agreement.issued',null,p_issued_by_seat_id,
    jsonb_build_object('agreementId',p_agreement_id,'agreementKey',v_agreement.agreement_key,'version',v_agreement.version),
    p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_agreement_detail_v1(p_agreement_id);
end;
$function$;

create or replace function ledger.accept_booking_agreement_party_service_v1(
  p_agreement_id uuid,
  p_entity_id uuid,
  p_party_role text,
  p_acceptance_method text,
  p_evidence jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_agreement ledger.booking_agreements%rowtype;
  v_party ledger.booking_agreement_parties%rowtype;
  v_complete boolean;
begin
  if p_evidence is null or jsonb_typeof(p_evidence)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Agreement acceptance evidence/provenance must be JSON objects.' using errcode='22023';
  end if;
  if nullif(btrim(p_acceptance_method),'') is null then
    raise exception 'Acceptance method is required.' using errcode='22023';
  end if;
  select * into v_agreement from ledger.booking_agreements a where a.id=p_agreement_id for update;
  if v_agreement.id is null then raise exception 'Booking agreement not found.' using errcode='P0002'; end if;
  if v_agreement.agreement_state='executed' then return ledger.booking_agreement_detail_v1(p_agreement_id); end if;
  if v_agreement.agreement_state<>'issued' then
    raise exception 'Agreement must be issued before acceptance.' using errcode='23514';
  end if;

  select * into v_party from ledger.booking_agreement_parties p
  where p.agreement_id=p_agreement_id and p.entity_id=p_entity_id and p.party_role=p_party_role
  for update;
  if v_party.id is null then raise exception 'Agreement party not found.' using errcode='P0002'; end if;
  if v_party.party_state='accepted' then return ledger.booking_agreement_detail_v1(p_agreement_id); end if;
  if v_party.party_state<>'pending' then
    raise exception 'Agreement party is not pending acceptance.' using errcode='23514';
  end if;

  update ledger.booking_agreement_parties
  set party_state='accepted',accepted_at=now(),acceptance_method=btrim(p_acceptance_method),evidence=p_evidence
  where id=v_party.id;

  select not exists(
    select 1 from ledger.booking_agreement_parties p
    where p.agreement_id=p_agreement_id and p.signature_required and p.party_state not in ('accepted','waived')
  ) into v_complete;

  if v_complete then
    update ledger.booking_agreements set agreement_state='executed',executed_at=now() where id=p_agreement_id;
    perform ledger.append_booking_request_event_v1(
      v_agreement.request_id,'agreement.executed',p_entity_id,null,
      jsonb_build_object('agreementId',p_agreement_id,'acceptedByEntityId',p_entity_id),
      p_provenance,p_idempotency_key,now()
    );
  else
    perform ledger.append_booking_request_event_v1(
      v_agreement.request_id,'agreement.party_accepted',p_entity_id,null,
      jsonb_build_object('agreementId',p_agreement_id,'acceptedByEntityId',p_entity_id,'partyRole',p_party_role),
      p_provenance,p_idempotency_key,now()
    );
  end if;
  return ledger.booking_agreement_detail_v1(p_agreement_id);
end;
$function$;

create or replace function ledger.booking_request_commitment_evaluation_v1(p_request_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_agreement_required boolean:=false;
  v_agreement ledger.booking_agreements%rowtype;
  v_ready boolean:=false;
  v_unmet jsonb:='[]'::jsonb;
  v_active_holds integer:=0;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;

  select coalesce(bool_or(coalesce((p.config->>'agreementRequired')::boolean,false)),false)
  into v_agreement_required
  from ledger.booking_policies p
  where p.ledger_id=v_request.ledger_id and p.policy_state='active'
    and p.policy_kind='commitment'
    and (p.booking_kind is null or p.booking_kind=v_request.booking_kind);

  select * into v_agreement
  from ledger.booking_agreements a
  where a.request_id=p_request_id and a.agreement_state not in ('superseded','void')
  order by a.version desc,a.created_at desc,a.id desc
  limit 1;

  select count(*) into v_active_holds
  from ledger.booking_request_holds h
  where h.request_id=p_request_id and h.hold_state='active' and h.expires_at>now();

  if v_request.request_state<>'approved' and v_request.request_state<>'converted' then
    v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object('reasonCode','request_not_approved','requestState',v_request.request_state));
  end if;
  if v_agreement_required and (v_agreement.id is null or v_agreement.agreement_state<>'executed') then
    v_unmet:=v_unmet||jsonb_build_array(jsonb_build_object(
      'reasonCode','executed_agreement_required',
      'agreementId',v_agreement.id,
      'agreementState',v_agreement.agreement_state
    ));
  end if;

  v_ready:=jsonb_array_length(v_unmet)=0;

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_commitment_evaluation_v1',
    'requestId',v_request.id,
    'requestState',v_request.request_state,
    'bookingKind',v_request.booking_kind,
    'agreementRequired',v_agreement_required,
    'currentAgreement',case when v_agreement.id is null then null else ledger.booking_agreement_detail_v1(v_agreement.id) end,
    'activeHoldCount',v_active_holds,
    'readyForConfirmation',v_ready,
    'unmetRequirements',v_unmet,
    'truthBoundary',jsonb_build_object(
      'holdIsNotBooking',true,
      'approvalIsNotAgreement',true,
      'agreementIsNotPayment',true,
      'paymentRequirementNotYetEstablishedByThisContract',true
    )
  );
end;
$function$;

create or replace function ledger.materialize_booking_request_service_v1(
  p_request_id uuid,
  p_occurrence_id uuid,
  p_created_by_seat_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_occurrence_id uuid;
  v_claims jsonb;
  v_bundle jsonb;
  v_commitment jsonb;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state='converted' and v_request.converted_booking_id is not null then
    return jsonb_build_object(
      'contractVersion','ledger_booking_request_materialization_v2',
      'request',ledger.booking_request_detail_v1(p_request_id),
      'bookingId',v_request.converted_booking_id,'alreadyConverted',true
    );
  end if;
  if v_request.request_state<>'approved' then
    raise exception 'Booking request must be approved before materialization.' using errcode='23514';
  end if;

  v_commitment:=ledger.booking_request_commitment_evaluation_v1(p_request_id);
  if not coalesce((v_commitment->>'readyForConfirmation')::boolean,false) then
    raise exception 'Booking request is not ready for confirmation: %',v_commitment using errcode='23514';
  end if;

  v_occurrence_id:=coalesce(v_request.occurrence_id,p_occurrence_id);
  if v_occurrence_id is null then
    raise exception 'Approved request requires a canonical occurrence before booking materialization.' using errcode='23514';
  end if;
  if v_request.occurrence_id is not null and p_occurrence_id is not null
     and v_request.occurrence_id<>p_occurrence_id then
    raise exception 'Materialization occurrence does not match the approved request occurrence.' using errcode='23514';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=v_occurrence_id) then
    raise exception 'Canonical occurrence not found.' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'resourceId',rr.resource_id,'claimKind',rr.claim_kind,
    'startsAt',rr.starts_at,'endsAt',rr.ends_at,
    'quantity',rr.quantity,'quantityUnit',rr.quantity_unit,
    'applyPolicyBuffers',rr.apply_policy_buffers,
    'metadata',rr.metadata||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id),
    'provenance',rr.provenance||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id)
  ) order by rr.starts_at,rr.id),'[]'::jsonb)
  into v_claims
  from ledger.booking_request_resources rr where rr.request_id=p_request_id;
  if jsonb_array_length(v_claims)=0 then
    raise exception 'Booking request has no Resource lines.' using errcode='23514';
  end if;

  v_bundle:=ledger.establish_booking_bundle_service_v1(
    v_request.ledger_id,v_occurrence_id,v_request.booking_kind,v_claims,
    v_request.customer_entity_id,v_request.business_model_key,v_request.request_label,
    'confirmed',p_created_by_seat_id,
    v_request.metadata||jsonb_build_object(
      'bookingRequestId',p_request_id,'approvedBookingRequestId',p_request_id,'requestPurpose',v_request.purpose,
      'commitmentEvaluation',v_commitment
    ),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'bookingRequestId',p_request_id,'approvedRequestMaterialization',true
    ),p_idempotency_key
  );

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_materialization_v2',
    'request',ledger.booking_request_detail_v1(p_request_id),
    'commitmentEvaluation',v_commitment,
    'bookingBundle',v_bundle,'alreadyConverted',false
  );
end;
$function$;

create or replace function atlas.create_ledger_booking_agreement_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_agreement_key text,
  p_title text,
  p_terms jsonb,
  p_required_parties jsonb,
  p_offer_snapshot_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.create_booking_agreement_service_v1(
    p_request_id,p_agreement_key,p_title,p_terms,p_required_parties,v_seat,p_offer_snapshot_id,p_metadata,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),
    p_idempotency_key
  );
end;
$function$;

create or replace function atlas.issue_ledger_booking_agreement_self_api_v1(
  p_ledger_id uuid,
  p_agreement_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  if not exists(
    select 1 from ledger.booking_agreements a join ledger.booking_requests br on br.id=a.request_id
    where a.id=p_agreement_id and br.ledger_id=p_ledger_id
  ) then raise exception 'Booking agreement is outside this Ledger.' using errcode='42501'; end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.issue_booking_agreement_service_v1(
    p_agreement_id,v_seat,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),
    p_idempotency_key
  );
end;
$function$;

create or replace function atlas.accept_booking_agreement_self_api_v1(
  p_agreement_id uuid,
  p_party_role text,
  p_acceptance_method text,
  p_evidence jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v_person uuid;
begin
  v_person:=atlas.current_person_id_v1();
  return ledger.accept_booking_agreement_party_service_v1(
    p_agreement_id,v_person,p_party_role,p_acceptance_method,p_evidence,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person),
    p_idempotency_key
  );
end;
$function$;

grant execute on function atlas.create_ledger_booking_agreement_self_api_v1(uuid,uuid,text,text,jsonb,jsonb,uuid,jsonb,jsonb,text) to authenticated;
grant execute on function atlas.issue_ledger_booking_agreement_self_api_v1(uuid,uuid,jsonb,text) to authenticated;
grant execute on function atlas.accept_booking_agreement_self_api_v1(uuid,text,text,jsonb,jsonb,text) to authenticated;
grant execute on function ledger.booking_request_commitment_evaluation_v1(uuid) to authenticated;
