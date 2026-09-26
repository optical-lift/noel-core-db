create table ledger.booking_requests (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  occurrence_id uuid null references local_intel.occurrences(id) on delete restrict,
  requester_entity_id uuid null references reality.entities(id) on delete set null,
  requester_seat_id uuid null references ledger.seats(id) on delete set null,
  customer_entity_id uuid null references reality.entities(id) on delete set null,
  booking_kind text not null,
  business_model_key text null,
  request_label text null,
  purpose text null,
  request_state text not null default 'submitted'
    check (request_state in ('submitted','approved','rejected','withdrawn','converted')),
  submission_evaluation jsonb not null default '{}'::jsonb
    check (jsonb_typeof(submission_evaluation)='object'),
  decision_reason text null,
  decided_at timestamptz null,
  approved_at timestamptz null,
  rejected_at timestamptz null,
  withdrawn_at timestamptz null,
  converted_at timestamptz null,
  converted_booking_id uuid null references ledger.bookings(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(booking_kind)<>''),
  check (idempotency_key is null or btrim(idempotency_key)<>'')
);
create unique index booking_requests_idempotency_uq
  on ledger.booking_requests(ledger_id,idempotency_key)
  where idempotency_key is not null;
create index booking_requests_ledger_state_idx
  on ledger.booking_requests(ledger_id,request_state,created_at desc);
create index booking_requests_occurrence_idx
  on ledger.booking_requests(occurrence_id)
  where occurrence_id is not null;
alter table ledger.booking_requests enable row level security;
create trigger booking_requests_set_updated_at
before update on ledger.booking_requests
for each row execute function atlas.set_updated_at();

create table ledger.booking_request_resources (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  resource_id uuid not null references reality.resources(id) on delete restrict,
  claim_kind text not null check (claim_kind in ('exclusive','shared','capacity')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  quantity numeric null,
  quantity_unit text null,
  apply_policy_buffers boolean not null default true,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  check (ends_at>starts_at),
  check ((claim_kind='capacity' and quantity is not null and quantity>0) or claim_kind<>'capacity')
);
create index booking_request_resources_request_idx
  on ledger.booking_request_resources(request_id,starts_at,ends_at);
create index booking_request_resources_resource_idx
  on ledger.booking_request_resources(resource_id,starts_at,ends_at);
alter table ledger.booking_request_resources enable row level security;

create table ledger.booking_request_holds (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  request_resource_id uuid not null references ledger.booking_request_resources(id) on delete cascade,
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  resource_id uuid not null references reality.resources(id) on delete restrict,
  claim_kind text not null check (claim_kind in ('exclusive','shared','capacity')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  quantity numeric null,
  quantity_unit text null,
  hold_state text not null default 'active'
    check (hold_state in ('active','released','expired','converted')),
  expires_at timestamptz not null,
  created_by_seat_id uuid not null references ledger.seats(id) on delete restrict,
  released_at timestamptz null,
  converted_at timestamptz null,
  reason text null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at>starts_at),
  check (expires_at>created_at),
  check ((claim_kind='capacity' and quantity is not null and quantity>0) or claim_kind<>'capacity')
);
create unique index booking_request_holds_active_line_uq
  on ledger.booking_request_holds(request_resource_id)
  where hold_state='active';
create index booking_request_holds_conflict_idx
  on ledger.booking_request_holds(ledger_id,resource_id,hold_state,starts_at,ends_at,expires_at);
create index booking_request_holds_request_idx
  on ledger.booking_request_holds(request_id,hold_state,expires_at);
alter table ledger.booking_request_holds enable row level security;
create trigger booking_request_holds_set_updated_at
before update on ledger.booking_request_holds
for each row execute function atlas.set_updated_at();

create table ledger.booking_request_approval_assignments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  approver_seat_id uuid not null references ledger.seats(id) on delete restrict,
  assigned_by_seat_id uuid not null references ledger.seats(id) on delete restrict,
  delegated_from_assignment_id uuid null references ledger.booking_request_approval_assignments(id) on delete set null,
  assignment_state text not null default 'active'
    check (assignment_state in ('active','delegated','decided','withdrawn')),
  assigned_at timestamptz not null default now(),
  ended_at timestamptz null,
  reason text null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index booking_request_approval_active_uq
  on ledger.booking_request_approval_assignments(request_id)
  where assignment_state='active';
create index booking_request_approval_approver_idx
  on ledger.booking_request_approval_assignments(approver_seat_id,assignment_state,assigned_at);
alter table ledger.booking_request_approval_assignments enable row level security;
create trigger booking_request_approval_assignments_set_updated_at
before update on ledger.booking_request_approval_assignments
for each row execute function atlas.set_updated_at();

create table ledger.booking_request_events (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references ledger.booking_requests(id) on delete cascade,
  event_kind text not null,
  occurred_at timestamptz not null default now(),
  performed_by_entity_id uuid null references reality.entities(id) on delete set null,
  performed_by_seat_id uuid null references ledger.seats(id) on delete set null,
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  idempotency_key text null,
  created_at timestamptz not null default now(),
  check (btrim(event_kind)<>''),
  check (idempotency_key is null or btrim(idempotency_key)<>'')
);
create unique index booking_request_events_idempotency_uq
  on ledger.booking_request_events(request_id,idempotency_key)
  where idempotency_key is not null;
create index booking_request_events_request_time_idx
  on ledger.booking_request_events(request_id,occurred_at,id);
alter table ledger.booking_request_events enable row level security;

revoke all on ledger.booking_requests from public,anon,authenticated;
revoke all on ledger.booking_request_resources from public,anon,authenticated;
revoke all on ledger.booking_request_holds from public,anon,authenticated;
revoke all on ledger.booking_request_approval_assignments from public,anon,authenticated;
revoke all on ledger.booking_request_events from public,anon,authenticated;

create or replace function ledger.guard_booking_request_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_subject uuid;
  v_seat_person uuid;
  v_booking_ledger uuid;
  v_booking_occurrence uuid;
begin
  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=new.ledger_id and l.ledger_state='active';
  if v_subject is null then
    raise exception 'Booking request requires an active Ledger.' using errcode='23514';
  end if;

  if new.requester_seat_id is not null then
    select s.person_entity_id into v_seat_person
    from ledger.seats s
    where s.id=new.requester_seat_id and s.ledger_id=new.ledger_id and s.seat_state='active';
    if v_seat_person is null then
      raise exception 'Booking request requester Seat must be active in the Ledger.' using errcode='23514';
    end if;
    if new.requester_entity_id is not null and new.requester_entity_id<>v_seat_person then
      raise exception 'Booking request requester Entity must match requester Seat.' using errcode='23514';
    end if;
  end if;

  if new.requester_entity_id is not null and not exists(
    select 1 from reality.entities e where e.id=new.requester_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Booking request requester must be a canonical Reality Entity.' using errcode='23514';
  end if;
  if new.customer_entity_id is not null and not exists(
    select 1 from reality.entities e where e.id=new.customer_entity_id and e.identity_state='canonical'
  ) then
    raise exception 'Booking request customer must be a canonical Reality Entity.' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    if new.ledger_id<>old.ledger_id
       or new.requester_entity_id is distinct from old.requester_entity_id
       or new.requester_seat_id is distinct from old.requester_seat_id
       or new.customer_entity_id is distinct from old.customer_entity_id
       or new.booking_kind<>old.booking_kind
       or new.business_model_key is distinct from old.business_model_key
       or new.submission_evaluation is distinct from old.submission_evaluation
       or new.idempotency_key is distinct from old.idempotency_key then
      raise exception 'Submitted booking request identity and submission evidence are immutable.' using errcode='23514';
    end if;

    if new.occurrence_id is distinct from old.occurrence_id then
      if old.occurrence_id is not null
         or new.occurrence_id is null
         or old.request_state<>'approved'
         or new.request_state not in ('approved','converted') then
        raise exception 'A booking request occurrence may only be attached during approved materialization.' using errcode='23514';
      end if;
    end if;

    if old.request_state<>new.request_state and not (
      (old.request_state='submitted' and new.request_state in ('approved','rejected','withdrawn'))
      or (old.request_state='approved' and new.request_state in ('withdrawn','converted'))
    ) then
      raise exception 'Invalid booking request transition: % -> %',old.request_state,new.request_state using errcode='23514';
    end if;
  end if;

  if new.converted_booking_id is not null then
    select b.ledger_id,b.occurrence_id into v_booking_ledger,v_booking_occurrence
    from ledger.bookings b where b.id=new.converted_booking_id;
    if v_booking_ledger is null or v_booking_ledger<>new.ledger_id then
      raise exception 'Converted booking must belong to the request Ledger.' using errcode='23514';
    end if;
    if new.occurrence_id is not null and v_booking_occurrence<>new.occurrence_id then
      raise exception 'Converted booking must use the request occurrence.' using errcode='23514';
    end if;
    if new.request_state<>'converted' then
      raise exception 'Converted booking may only be attached to a converted request.' using errcode='23514';
    end if;
  end if;

  return new;
end;
$$;
create trigger booking_requests_guard
before insert or update on ledger.booking_requests
for each row execute function ledger.guard_booking_request_v1();

create or replace function ledger.guard_booking_request_resource_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_subject uuid;
  v_capacity_mode text;
begin
  select l.subject_entity_id into v_subject
  from ledger.booking_requests br
  join ledger.ledgers l on l.id=br.ledger_id
  where br.id=new.request_id and l.ledger_state='active';
  if v_subject is null then
    raise exception 'Booking request resource requires an active request Ledger.' using errcode='23514';
  end if;
  select r.capacity_mode into v_capacity_mode
  from reality.resources r
  where r.id=new.resource_id and r.owner_entity_id=v_subject and r.resource_state<>'retired';
  if v_capacity_mode is null then
    raise exception 'Requested Resource must belong to the request Ledger subject.' using errcode='23514';
  end if;
  if new.claim_kind='capacity' and v_capacity_mode<>'quantity' then
    raise exception 'Capacity request requires a quantity-governed Resource.' using errcode='23514';
  end if;
  return new;
end;
$$;
create trigger booking_request_resources_guard
before insert on ledger.booking_request_resources
for each row execute function ledger.guard_booking_request_resource_v1();

create or replace function ledger.prevent_booking_request_resource_mutation_v1()
returns trigger language plpgsql set search_path='' as $$
begin
  raise exception 'Submitted booking request Resource lines are append-only and immutable.' using errcode='42501';
end;
$$;
create trigger booking_request_resources_no_mutation
before update or delete on ledger.booking_request_resources
for each row execute function ledger.prevent_booking_request_resource_mutation_v1();

create or replace function ledger.guard_booking_request_hold_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_request_ledger uuid;
  v_line ledger.booking_request_resources%rowtype;
  v_seat_ledger uuid;
begin
  select br.ledger_id into v_request_ledger
  from ledger.booking_requests br where br.id=new.request_id;
  select * into v_line from ledger.booking_request_resources rr where rr.id=new.request_resource_id;
  select s.ledger_id into v_seat_ledger from ledger.seats s
  where s.id=new.created_by_seat_id and s.seat_state='active';

  if v_request_ledger is null or v_request_ledger<>new.ledger_id then
    raise exception 'Booking request hold Ledger mismatch.' using errcode='23514';
  end if;
  if v_line.id is null or v_line.request_id<>new.request_id
     or v_line.resource_id<>new.resource_id
     or v_line.claim_kind<>new.claim_kind
     or v_line.starts_at<>new.starts_at
     or v_line.ends_at<>new.ends_at
     or v_line.quantity is distinct from new.quantity
     or v_line.quantity_unit is distinct from new.quantity_unit then
    if tg_op='INSERT' then
      null;
    elsif new.hold_state<>old.hold_state then
      null;
    else
      raise exception 'Booking request hold must remain anchored to its request Resource line.' using errcode='23514';
    end if;
  end if;
  if v_seat_ledger is null or v_seat_ledger<>new.ledger_id then
    raise exception 'Booking request hold creator must have an active Seat in the Ledger.' using errcode='23514';
  end if;

  if tg_op='UPDATE' then
    if new.request_id<>old.request_id
       or new.request_resource_id<>old.request_resource_id
       or new.ledger_id<>old.ledger_id
       or new.resource_id<>old.resource_id
       or new.claim_kind<>old.claim_kind
       or new.starts_at<>old.starts_at
       or new.ends_at<>old.ends_at
       or new.quantity is distinct from old.quantity
       or new.quantity_unit is distinct from old.quantity_unit
       or new.expires_at<>old.expires_at
       or new.created_by_seat_id<>old.created_by_seat_id then
      raise exception 'Booking request hold identity and interval are immutable.' using errcode='23514';
    end if;
    if old.hold_state<>new.hold_state
       and not (old.hold_state='active' and new.hold_state in ('released','expired','converted')) then
      raise exception 'Invalid booking request hold transition: % -> %',old.hold_state,new.hold_state using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_request_holds_guard
before insert or update on ledger.booking_request_holds
for each row execute function ledger.guard_booking_request_hold_v1();

create or replace function ledger.guard_booking_request_approval_assignment_v1()
returns trigger language plpgsql set search_path='' as $$
declare
  v_request_ledger uuid;
  v_approver_ledger uuid;
  v_assigner_ledger uuid;
  v_delegated_request uuid;
begin
  select br.ledger_id into v_request_ledger from ledger.booking_requests br where br.id=new.request_id;
  select s.ledger_id into v_approver_ledger from ledger.seats s where s.id=new.approver_seat_id and s.seat_state='active';
  select s.ledger_id into v_assigner_ledger from ledger.seats s where s.id=new.assigned_by_seat_id and s.seat_state='active';
  if v_request_ledger is null or new.ledger_id<>v_request_ledger
     or v_approver_ledger<>v_request_ledger or v_assigner_ledger<>v_request_ledger then
    raise exception 'Booking request approval assignment Seats must be active in the request Ledger.' using errcode='23514';
  end if;
  if new.delegated_from_assignment_id is not null then
    select a.request_id into v_delegated_request
    from ledger.booking_request_approval_assignments a where a.id=new.delegated_from_assignment_id;
    if v_delegated_request is null or v_delegated_request<>new.request_id then
      raise exception 'Delegated approval assignment must remain within one request.' using errcode='23514';
    end if;
  end if;
  if tg_op='UPDATE' then
    if new.request_id<>old.request_id or new.ledger_id<>old.ledger_id
       or new.approver_seat_id<>old.approver_seat_id
       or new.assigned_by_seat_id<>old.assigned_by_seat_id
       or new.delegated_from_assignment_id is distinct from old.delegated_from_assignment_id
       or new.assigned_at<>old.assigned_at then
      raise exception 'Approval assignment identity is immutable.' using errcode='23514';
    end if;
    if old.assignment_state<>new.assignment_state
       and not (old.assignment_state='active' and new.assignment_state in ('delegated','decided','withdrawn')) then
      raise exception 'Invalid approval assignment transition: % -> %',old.assignment_state,new.assignment_state using errcode='23514';
    end if;
  end if;
  return new;
end;
$$;
create trigger booking_request_approval_assignments_guard
before insert or update on ledger.booking_request_approval_assignments
for each row execute function ledger.guard_booking_request_approval_assignment_v1();

create or replace function ledger.prevent_booking_request_event_mutation_v1()
returns trigger language plpgsql set search_path='' as $$
begin
  raise exception 'Booking request events are append-only.' using errcode='42501';
end;
$$;
create trigger booking_request_events_no_mutation
before update or delete on ledger.booking_request_events
for each row execute function ledger.prevent_booking_request_event_mutation_v1();

create or replace function ledger.append_booking_request_event_v1(
  p_request_id uuid,
  p_event_kind text,
  p_performed_by_entity_id uuid default null,
  p_performed_by_seat_id uuid default null,
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null,
  p_occurred_at timestamptz default now()
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  insert into ledger.booking_request_events(
    request_id,event_kind,occurred_at,performed_by_entity_id,performed_by_seat_id,
    payload,provenance,idempotency_key
  ) values(
    p_request_id,btrim(p_event_kind),coalesce(p_occurred_at,now()),p_performed_by_entity_id,p_performed_by_seat_id,
    coalesce(p_payload,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb),nullif(btrim(p_idempotency_key),'')
  )
  on conflict(request_id,idempotency_key) where idempotency_key is not null do nothing
  returning id into v_id;
  if v_id is null and nullif(btrim(p_idempotency_key),'') is not null then
    select e.id into v_id from ledger.booking_request_events e
    where e.request_id=p_request_id and e.idempotency_key=btrim(p_idempotency_key);
  end if;
  return v_id;
end;
$$;

create or replace function ledger.booking_request_detail_v1(p_request_id uuid)
returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_resources jsonb;
  v_holds jsonb;
  v_approver jsonb;
  v_events jsonb;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then return null; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'requestResourceId',rr.id,'resourceId',rr.resource_id,'resourceLabel',r.label,
    'resourceKind',r.resource_kind,'claimKind',rr.claim_kind,
    'startsAt',rr.starts_at,'endsAt',rr.ends_at,'quantity',rr.quantity,'quantityUnit',rr.quantity_unit,
    'applyPolicyBuffers',rr.apply_policy_buffers,'metadata',rr.metadata
  ) order by rr.starts_at,r.label,rr.id),'[]'::jsonb)
  into v_resources
  from ledger.booking_request_resources rr
  join reality.resources r on r.id=rr.resource_id
  where rr.request_id=v_request.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'holdId',h.id,'requestResourceId',h.request_resource_id,'resourceId',h.resource_id,'resourceLabel',r.label,
    'claimKind',h.claim_kind,'startsAt',h.starts_at,'endsAt',h.ends_at,'quantity',h.quantity,'quantityUnit',h.quantity_unit,
    'holdState',h.hold_state,'effectiveState',case when h.hold_state='active' and h.expires_at<=now() then 'expired' else h.hold_state end,
    'expiresAt',h.expires_at,'releasedAt',h.released_at,'convertedAt',h.converted_at,'reason',h.reason
  ) order by h.created_at,h.id),'[]'::jsonb)
  into v_holds
  from ledger.booking_request_holds h
  join reality.resources r on r.id=h.resource_id
  where h.request_id=v_request.id;

  select jsonb_build_object(
    'assignmentId',a.id,'approverSeatId',a.approver_seat_id,'approverPersonEntityId',s.person_entity_id,
    'approverDisplayName',e.display_name,'assignedBySeatId',a.assigned_by_seat_id,
    'delegatedFromAssignmentId',a.delegated_from_assignment_id,'assignedAt',a.assigned_at,'reason',a.reason
  ) into v_approver
  from ledger.booking_request_approval_assignments a
  join ledger.seats s on s.id=a.approver_seat_id
  left join reality.entities e on e.id=s.person_entity_id
  where a.request_id=v_request.id and a.assignment_state='active'
  order by a.assigned_at desc,a.id desc limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'eventId',ev.id,'eventKind',ev.event_kind,'occurredAt',ev.occurred_at,
    'performedByEntityId',ev.performed_by_entity_id,'performedBySeatId',ev.performed_by_seat_id,
    'payload',ev.payload,'provenance',ev.provenance
  ) order by ev.occurred_at,ev.id),'[]'::jsonb)
  into v_events
  from ledger.booking_request_events ev where ev.request_id=v_request.id;

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_v1',
    'requestId',v_request.id,'ledgerId',v_request.ledger_id,'occurrenceId',v_request.occurrence_id,
    'requesterEntityId',v_request.requester_entity_id,'requesterSeatId',v_request.requester_seat_id,
    'requesterDisplayName',(select e.display_name from reality.entities e where e.id=v_request.requester_entity_id),
    'customerEntityId',v_request.customer_entity_id,
    'customerDisplayName',(select e.display_name from reality.entities e where e.id=v_request.customer_entity_id),
    'bookingKind',v_request.booking_kind,'businessModelKey',v_request.business_model_key,
    'requestLabel',v_request.request_label,'purpose',v_request.purpose,'requestState',v_request.request_state,
    'submissionEvaluation',v_request.submission_evaluation,'decisionReason',v_request.decision_reason,
    'decidedAt',v_request.decided_at,'approvedAt',v_request.approved_at,'rejectedAt',v_request.rejected_at,
    'withdrawnAt',v_request.withdrawn_at,'convertedAt',v_request.converted_at,'convertedBookingId',v_request.converted_booking_id,
    'resources',v_resources,'holds',v_holds,'currentApprover',v_approver,'events',v_events,
    'metadata',v_request.metadata,'createdAt',v_request.created_at,'updatedAt',v_request.updated_at
  );
end;
$$;

create or replace function ledger.booking_request_approver_authorized_v1(
  p_request_id uuid,
  p_seat_id uuid
) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare
  v_person uuid;
  v_ledger uuid;
  v_subject uuid;
  v_relation uuid;
begin
  select s.person_entity_id,s.ledger_id,l.subject_entity_id
    into v_person,v_ledger,v_subject
  from ledger.seats s
  join ledger.ledgers l on l.id=s.ledger_id
  join ledger.booking_requests br on br.id=p_request_id and br.ledger_id=s.ledger_id
  where s.id=p_seat_id and s.seat_state='active' and l.ledger_state='active';
  if v_person is null then return false; end if;
  v_relation:=reality.resolve_responsibility_relation_v1(
    v_person,'institutional_schedule_operations','booking_request.approve',
    'entity',v_subject,null,jsonb_build_object('ledgerIds',jsonb_build_array(v_ledger::text))
  );
  return v_relation is not null;
end;
$$;

create or replace function ledger.booking_request_approval_matches_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_occurrence_id uuid,
  p_booking_kind text,
  p_claims jsonb
) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare v_request ledger.booking_requests%rowtype; v_count integer;
begin
  select * into v_request from ledger.booking_requests br
  where br.id=p_request_id and br.ledger_id=p_ledger_id and br.request_state in ('approved','converted');
  if v_request.id is null or v_request.booking_kind<>p_booking_kind then return false; end if;
  if v_request.occurrence_id is not null and v_request.occurrence_id<>p_occurrence_id then return false; end if;
  if p_claims is null or jsonb_typeof(p_claims)<>'array' then return false; end if;
  select count(*) into v_count from ledger.booking_request_resources rr where rr.request_id=p_request_id;
  if jsonb_array_length(p_claims)<>v_count then return false; end if;
  if exists(
    select 1
    from ledger.booking_request_resources rr
    where rr.request_id=p_request_id
      and not exists(
        select 1 from jsonb_array_elements(p_claims) c
        where (c->>'resourceId')::uuid=rr.resource_id
          and c->>'claimKind'=rr.claim_kind
          and (c->>'startsAt')::timestamptz=rr.starts_at
          and (c->>'endsAt')::timestamptz=rr.ends_at
          and (case when nullif(c->>'quantity','') is null then null else (c->>'quantity')::numeric end) is not distinct from rr.quantity
          and nullif(c->>'quantityUnit','') is not distinct from rr.quantity_unit
          and coalesce((c->>'applyPolicyBuffers')::boolean,true)=rr.apply_policy_buffers
      )
  ) then return false; end if;
  return true;
exception when others then
  return false;
end;
$$;

create or replace function ledger.submit_booking_request_service_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_requester_entity_id uuid,
  p_requester_seat_id uuid,
  p_customer_entity_id uuid,
  p_booking_kind text,
  p_business_model_key text,
  p_request_label text,
  p_purpose text,
  p_resource_requests jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_request_id uuid;
  v_existing uuid;
  v_resource_ids uuid[];
  v_start timestamptz;
  v_end timestamptz;
  v_policy jsonb;
  v_availability jsonb:='[]'::jsonb;
  v_line jsonb;
  v_av jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_line_start timestamptz;
  v_line_end timestamptz;
  v_apply_buffers boolean;
  v_capacity_mode text;
begin
  if nullif(btrim(p_booking_kind),'') is null then
    raise exception 'Booking request kind is required.' using errcode='22023';
  end if;
  if p_resource_requests is null or jsonb_typeof(p_resource_requests)<>'array' or jsonb_array_length(p_resource_requests)=0 then
    raise exception 'Booking request requires at least one Resource request.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Booking request metadata/provenance must be JSON objects.' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_resource_requests) x
    where jsonb_typeof(x)<>'object'
       or nullif(x->>'resourceId','') is null
       or nullif(x->>'claimKind','') is null
       or nullif(x->>'startsAt','') is null
       or nullif(x->>'endsAt','') is null
  ) then
    raise exception 'Every booking request Resource requires resourceId, claimKind, startsAt, and endsAt.' using errcode='22023';
  end if;

  if nullif(btrim(p_idempotency_key),'') is not null then
    select br.id into v_existing from ledger.booking_requests br
    where br.ledger_id=p_ledger_id and br.idempotency_key=btrim(p_idempotency_key);
    if v_existing is not null then return ledger.booking_request_detail_v1(v_existing); end if;
  end if;

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid),
         min((x->>'startsAt')::timestamptz),max((x->>'endsAt')::timestamptz)
    into v_resource_ids,v_start,v_end
  from jsonb_array_elements(p_resource_requests) x;
  if v_start is null or v_end is null or v_end<=v_start then
    raise exception 'Booking request Resource intervals are invalid.' using errcode='22023';
  end if;

  v_policy:=ledger.evaluate_booking_policies_v1(p_ledger_id,v_resource_ids,p_booking_kind,v_start,v_end,false,now());
  v_setup:=coalesce((v_policy->'requirements'->>'setupBufferMinutes')::integer,0);
  v_teardown:=coalesce((v_policy->'requirements'->>'teardownBufferMinutes')::integer,0);

  for v_line in select value from jsonb_array_elements(p_resource_requests)
  loop
    if (v_line->>'claimKind') not in ('exclusive','shared','capacity') then
      raise exception 'Unknown booking request claim kind: %',v_line->>'claimKind' using errcode='22023';
    end if;
    if (v_line->>'endsAt')::timestamptz <= (v_line->>'startsAt')::timestamptz then
      raise exception 'Booking request Resource interval must have startsAt < endsAt.' using errcode='22023';
    end if;
    select r.capacity_mode into v_capacity_mode
    from reality.resources r
    join ledger.ledgers l on l.subject_entity_id=r.owner_entity_id
    where r.id=(v_line->>'resourceId')::uuid and l.id=p_ledger_id and l.ledger_state='active' and r.resource_state<>'retired';
    if v_capacity_mode is null then
      raise exception 'Requested Resource is outside this Ledger subject.' using errcode='23514';
    end if;
    if v_line->>'claimKind'='capacity' and (v_capacity_mode<>'quantity' or nullif(v_line->>'quantity','') is null or (v_line->>'quantity')::numeric<=0) then
      raise exception 'Capacity request requires a quantity-governed Resource and quantity > 0.' using errcode='22023';
    end if;
    v_apply_buffers:=coalesce((v_line->>'applyPolicyBuffers')::boolean,true);
    v_line_start:=(v_line->>'startsAt')::timestamptz - case when v_apply_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_line_end:=(v_line->>'endsAt')::timestamptz + case when v_apply_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
    v_av:=ledger.resource_claim_availability_v1(
      p_ledger_id,(v_line->>'resourceId')::uuid,v_line_start,v_line_end,v_line->>'claimKind',
      case when nullif(v_line->>'quantity','') is null then null else (v_line->>'quantity')::numeric end,null,null
    );
    v_availability:=v_availability||jsonb_build_array(jsonb_build_object(
      'resourceId',(v_line->>'resourceId')::uuid,'requestedStartsAt',(v_line->>'startsAt')::timestamptz,
      'requestedEndsAt',(v_line->>'endsAt')::timestamptz,'effectiveStartsAt',v_line_start,'effectiveEndsAt',v_line_end,
      'availability',v_av
    ));
  end loop;

  insert into ledger.booking_requests(
    ledger_id,occurrence_id,requester_entity_id,requester_seat_id,customer_entity_id,
    booking_kind,business_model_key,request_label,purpose,request_state,submission_evaluation,
    metadata,provenance,idempotency_key
  ) values(
    p_ledger_id,p_occurrence_id,p_requester_entity_id,p_requester_seat_id,p_customer_entity_id,
    btrim(p_booking_kind),nullif(btrim(p_business_model_key),''),nullif(btrim(p_request_label),''),nullif(btrim(p_purpose),''),'submitted',
    jsonb_build_object('contractVersion','ledger_booking_request_submission_evaluation_v1','policy',v_policy,'resourceAvailability',v_availability),
    coalesce(p_metadata,'{}'::jsonb),coalesce(p_provenance,'{}'::jsonb),nullif(btrim(p_idempotency_key),'')
  ) returning id into v_request_id;

  for v_line in select value from jsonb_array_elements(p_resource_requests)
  loop
    insert into ledger.booking_request_resources(
      request_id,resource_id,claim_kind,starts_at,ends_at,quantity,quantity_unit,apply_policy_buffers,metadata,provenance
    ) values(
      v_request_id,(v_line->>'resourceId')::uuid,v_line->>'claimKind',(v_line->>'startsAt')::timestamptz,(v_line->>'endsAt')::timestamptz,
      case when nullif(v_line->>'quantity','') is null then null else (v_line->>'quantity')::numeric end,
      nullif(v_line->>'quantityUnit',''),coalesce((v_line->>'applyPolicyBuffers')::boolean,true),
      coalesce(v_line->'metadata','{}'::jsonb),coalesce(v_line->'provenance','{}'::jsonb)
    );
  end loop;

  perform ledger.append_booking_request_event_v1(
    v_request_id,'request.submitted',p_requester_entity_id,p_requester_seat_id,
    jsonb_build_object('policyEvaluation',v_policy,'resourceAvailability',v_availability),p_provenance,
    case when nullif(btrim(p_idempotency_key),'') is null then null else btrim(p_idempotency_key)||':submitted' end,now()
  );
  return ledger.booking_request_detail_v1(v_request_id);
end;
$$;

create or replace function ledger.establish_booking_request_holds_service_v1(
  p_request_id uuid,
  p_expires_at timestamptz,
  p_created_by_seat_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_resource_ids uuid[];
  v_start timestamptz;
  v_end timestamptz;
  v_policy jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_line ledger.booking_request_resources%rowtype;
  v_start_effective timestamptz;
  v_end_effective timestamptz;
  v_av jsonb;
  v_expired integer:=0;
  v_released integer:=0;
  v_hold_ids jsonb:='[]'::jsonb;
begin
  if p_expires_at is null or p_expires_at<=now() then
    raise exception 'Booking request hold expiration must be in the future.' using errcode='22023';
  end if;
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state not in ('submitted','approved') then
    raise exception 'Only submitted or approved booking requests may hold capacity.' using errcode='23514';
  end if;
  if nullif(btrim(p_idempotency_key),'') is not null and exists(
    select 1 from ledger.booking_request_events e where e.request_id=p_request_id and e.idempotency_key=btrim(p_idempotency_key)
  ) then return ledger.booking_request_detail_v1(p_request_id); end if;

  select array_agg(distinct rr.resource_id order by rr.resource_id),min(rr.starts_at),max(rr.ends_at)
    into v_resource_ids,v_start,v_end
  from ledger.booking_request_resources rr where rr.request_id=p_request_id;
  if v_resource_ids is null or cardinality(v_resource_ids)=0 then
    raise exception 'Booking request has no Resource lines.' using errcode='23514';
  end if;
  v_policy:=ledger.evaluate_booking_policies_v1(v_request.ledger_id,v_resource_ids,v_request.booking_kind,v_start,v_end,false,now());
  if not coalesce((v_policy->>'allowed')::boolean,false) then
    raise exception 'Booking request cannot be held because current policy blocks it: %',v_policy using errcode='23514';
  end if;
  v_setup:=coalesce((v_policy->'requirements'->>'setupBufferMinutes')::integer,0);
  v_teardown:=coalesce((v_policy->'requirements'->>'teardownBufferMinutes')::integer,0);

  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);

  update ledger.booking_request_holds
  set hold_state='expired',released_at=coalesce(released_at,now()),reason=coalesce(reason,'expired before refresh')
  where request_id=p_request_id and hold_state='active' and expires_at<=now();
  get diagnostics v_expired=row_count;

  update ledger.booking_request_holds
  set hold_state='released',released_at=coalesce(released_at,now()),reason='replaced by refreshed hold'
  where request_id=p_request_id and hold_state='active';
  get diagnostics v_released=row_count;

  for v_line in
    select * from ledger.booking_request_resources rr where rr.request_id=p_request_id order by rr.starts_at,rr.id
  loop
    v_start_effective:=v_line.starts_at - case when v_line.apply_policy_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_end_effective:=v_line.ends_at + case when v_line.apply_policy_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
    v_av:=ledger.resource_claim_availability_v1(
      v_request.ledger_id,v_line.resource_id,v_start_effective,v_end_effective,v_line.claim_kind,v_line.quantity,null,null
    );
    if not coalesce((v_av->>'available')::boolean,false) then
      raise exception 'Requested Resource cannot be held: %',v_av using errcode='23514';
    end if;
    insert into ledger.booking_request_holds(
      request_id,request_resource_id,ledger_id,resource_id,claim_kind,starts_at,ends_at,quantity,quantity_unit,
      hold_state,expires_at,created_by_seat_id,metadata,provenance
    ) values(
      p_request_id,v_line.id,v_request.ledger_id,v_line.resource_id,v_line.claim_kind,v_start_effective,v_end_effective,
      v_line.quantity,v_line.quantity_unit,'active',p_expires_at,p_created_by_seat_id,
      jsonb_build_object('setupBufferMinutes',case when v_line.apply_policy_buffers then v_setup else 0 end,
                         'teardownBufferMinutes',case when v_line.apply_policy_buffers then v_teardown else 0 end),
      coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('bookingRequestResourceId',v_line.id)
    ) returning v_hold_ids||jsonb_build_array(id) into v_hold_ids;
  end loop;

  perform ledger.append_booking_request_event_v1(
    p_request_id,'hold.established',null,p_created_by_seat_id,
    jsonb_build_object('expiresAt',p_expires_at,'holdIds',v_hold_ids,'expiredPriorHolds',v_expired,'releasedPriorHolds',v_released),
    p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_request_detail_v1(p_request_id);
end;
$$;

create or replace function ledger.assign_booking_request_approver_service_v1(
  p_request_id uuid,
  p_approver_seat_id uuid,
  p_assigned_by_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_request ledger.booking_requests%rowtype; v_existing ledger.booking_request_approval_assignments%rowtype; v_assignment_id uuid;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state<>'submitted' then raise exception 'Only submitted requests may receive an approver.' using errcode='23514'; end if;
  if not ledger.booking_request_approver_authorized_v1(p_request_id,p_approver_seat_id) then
    raise exception 'Assigned approver does not already carry booking-request approval responsibility.' using errcode='42501';
  end if;
  select * into v_existing from ledger.booking_request_approval_assignments a
  where a.request_id=p_request_id and a.assignment_state='active' for update;
  if v_existing.id is not null then
    if v_existing.approver_seat_id=p_approver_seat_id then return ledger.booking_request_detail_v1(p_request_id); end if;
    raise exception 'Booking request already has an active approver; use delegation.' using errcode='23514';
  end if;
  insert into ledger.booking_request_approval_assignments(
    request_id,ledger_id,approver_seat_id,assigned_by_seat_id,assignment_state,reason,provenance
  ) values(p_request_id,v_request.ledger_id,p_approver_seat_id,p_assigned_by_seat_id,'active',p_reason,coalesce(p_provenance,'{}'::jsonb))
  returning id into v_assignment_id;
  perform ledger.append_booking_request_event_v1(
    p_request_id,'approver.assigned',null,p_assigned_by_seat_id,
    jsonb_build_object('assignmentId',v_assignment_id,'approverSeatId',p_approver_seat_id,'reason',p_reason),
    p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_request_detail_v1(p_request_id);
end;
$$;

create or replace function ledger.delegate_booking_request_approver_service_v1(
  p_request_id uuid,
  p_from_seat_id uuid,
  p_target_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_request ledger.booking_requests%rowtype; v_assignment ledger.booking_request_approval_assignments%rowtype; v_new_id uuid;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state<>'submitted' then raise exception 'Only submitted requests may delegate approval.' using errcode='23514'; end if;
  select * into v_assignment from ledger.booking_request_approval_assignments a
  where a.request_id=p_request_id and a.assignment_state='active' for update;
  if v_assignment.id is null or v_assignment.approver_seat_id<>p_from_seat_id then
    raise exception 'Current active approver assignment is required for delegation.' using errcode='42501';
  end if;
  if p_target_seat_id=p_from_seat_id then return ledger.booking_request_detail_v1(p_request_id); end if;
  if not ledger.booking_request_approver_authorized_v1(p_request_id,p_target_seat_id) then
    raise exception 'Delegation target does not already carry booking-request approval responsibility.' using errcode='42501';
  end if;
  update ledger.booking_request_approval_assignments
  set assignment_state='delegated',ended_at=now(),reason=coalesce(p_reason,reason)
  where id=v_assignment.id;
  insert into ledger.booking_request_approval_assignments(
    request_id,ledger_id,approver_seat_id,assigned_by_seat_id,delegated_from_assignment_id,assignment_state,reason,provenance
  ) values(
    p_request_id,v_request.ledger_id,p_target_seat_id,p_from_seat_id,v_assignment.id,'active',p_reason,coalesce(p_provenance,'{}'::jsonb)
  ) returning id into v_new_id;
  perform ledger.append_booking_request_event_v1(
    p_request_id,'approver.delegated',null,p_from_seat_id,
    jsonb_build_object('fromAssignmentId',v_assignment.id,'toAssignmentId',v_new_id,'fromSeatId',p_from_seat_id,'toSeatId',p_target_seat_id,'reason',p_reason),
    p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_request_detail_v1(p_request_id);
end;
$$;

create or replace function ledger.decide_booking_request_service_v1(
  p_request_id uuid,
  p_decision text,
  p_decided_by_entity_id uuid,
  p_decided_by_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_request ledger.booking_requests%rowtype; v_assignment ledger.booking_request_approval_assignments%rowtype; v_assignment_id uuid; v_released integer:=0;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected.' using errcode='22023'; end if;
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state<>'submitted' then
    if v_request.request_state=p_decision then return ledger.booking_request_detail_v1(p_request_id); end if;
    raise exception 'Only submitted booking requests may be decided.' using errcode='23514';
  end if;
  if not ledger.booking_request_approver_authorized_v1(p_request_id,p_decided_by_seat_id) then
    raise exception 'Decision maker does not carry booking-request approval responsibility.' using errcode='42501';
  end if;
  select * into v_assignment from ledger.booking_request_approval_assignments a
  where a.request_id=p_request_id and a.assignment_state='active' for update;
  if v_assignment.id is not null and v_assignment.approver_seat_id<>p_decided_by_seat_id then
    raise exception 'Booking request is assigned to another approver.' using errcode='42501';
  end if;
  if v_assignment.id is null then
    insert into ledger.booking_request_approval_assignments(
      request_id,ledger_id,approver_seat_id,assigned_by_seat_id,assignment_state,reason,metadata,provenance
    ) values(
      p_request_id,v_request.ledger_id,p_decided_by_seat_id,p_decided_by_seat_id,'active','self-claimed for decision',
      jsonb_build_object('assignmentMode','self_claimed'),coalesce(p_provenance,'{}'::jsonb)
    ) returning id into v_assignment_id;
  else
    v_assignment_id:=v_assignment.id;
  end if;

  update ledger.booking_requests
  set request_state=p_decision,decision_reason=p_reason,decided_at=now(),
      approved_at=case when p_decision='approved' then now() else approved_at end,
      rejected_at=case when p_decision='rejected' then now() else rejected_at end
  where id=p_request_id;
  update ledger.booking_request_approval_assignments
  set assignment_state='decided',ended_at=now(),reason=coalesce(p_reason,reason)
  where id=v_assignment_id;

  if p_decision='rejected' then
    update ledger.booking_request_holds
    set hold_state='released',released_at=coalesce(released_at,now()),reason=coalesce(p_reason,'request rejected')
    where request_id=p_request_id and hold_state='active';
    get diagnostics v_released=row_count;
  end if;

  perform ledger.append_booking_request_event_v1(
    p_request_id,'decision.'||p_decision,p_decided_by_entity_id,p_decided_by_seat_id,
    jsonb_build_object('assignmentId',v_assignment_id,'reason',p_reason,'releasedHolds',v_released),
    p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_request_detail_v1(p_request_id);
end;
$$;

create or replace function ledger.withdraw_booking_request_service_v1(
  p_request_id uuid,
  p_requester_entity_id uuid,
  p_requester_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_request ledger.booking_requests%rowtype; v_released integer:=0;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state='withdrawn' then return ledger.booking_request_detail_v1(p_request_id); end if;
  if v_request.request_state not in ('submitted','approved') then raise exception 'This booking request can no longer be withdrawn.' using errcode='23514'; end if;
  if v_request.requester_seat_id is distinct from p_requester_seat_id
     or (v_request.requester_entity_id is not null and v_request.requester_entity_id<>p_requester_entity_id) then
    raise exception 'Only the original requesting Seat may withdraw this request.' using errcode='42501';
  end if;
  update ledger.booking_requests set request_state='withdrawn',withdrawn_at=now(),decision_reason=coalesce(p_reason,decision_reason)
  where id=p_request_id;
  update ledger.booking_request_holds
  set hold_state='released',released_at=coalesce(released_at,now()),reason=coalesce(p_reason,'request withdrawn')
  where request_id=p_request_id and hold_state='active';
  get diagnostics v_released=row_count;
  update ledger.booking_request_approval_assignments
  set assignment_state='withdrawn',ended_at=now(),reason=coalesce(p_reason,reason)
  where request_id=p_request_id and assignment_state='active';
  perform ledger.append_booking_request_event_v1(
    p_request_id,'request.withdrawn',p_requester_entity_id,p_requester_seat_id,
    jsonb_build_object('reason',p_reason,'releasedHolds',v_released),p_provenance,p_idempotency_key,now()
  );
  return ledger.booking_request_detail_v1(p_request_id);
end;
$$;

create or replace function ledger.resource_claim_availability_v1(
  p_ledger_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_requested_claim_kind text default 'exclusive',
  p_requested_quantity numeric default null,
  p_exclude_claim_id uuid default null,
  p_exclude_occurrence_id uuid default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_subject uuid;
  v_resource reality.resources%rowtype;
  v_blockers jsonb;
  v_hold_blockers jsonb;
  v_capacity_used numeric:=0;
  v_capacity_held numeric:=0;
  v_capacity_exceeded boolean:=false;
  v_schedule_checks jsonb:='[]'::jsonb;
  v_schedule_available boolean:=true;
  v_schedule_result jsonb;
  v_related_resource record;
  v_available boolean:=false;
begin
  if p_starts_at is null or p_ends_at is null or p_ends_at<=p_starts_at then
    raise exception 'Availability window must have starts_at < ends_at.' using errcode='22023';
  end if;
  if p_requested_claim_kind not in ('exclusive','shared','capacity') then
    raise exception 'Unknown requested claim kind: %',p_requested_claim_kind using errcode='22023';
  end if;
  select l.subject_entity_id into v_subject from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active';
  if v_subject is null then raise exception 'Active Ledger required.' using errcode='23514'; end if;
  select * into v_resource from reality.resources r where r.id=p_resource_id;
  if v_resource.id is null or v_resource.owner_entity_id<>v_subject then
    raise exception 'Resource is outside this Ledger subject.' using errcode='23514';
  end if;
  if v_resource.capacity_mode='quantity' and p_requested_claim_kind='capacity'
     and (p_requested_quantity is null or p_requested_quantity<=0) then
    raise exception 'Quantity-governed capacity request requires requested_quantity > 0.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'claimId',c.id,'occurrenceId',c.occurrence_id,'bookingId',c.booking_id,'resourceId',c.resource_id,
    'resourceLabel',rr.label,'claimKind',c.claim_kind,'claimState',c.claim_state,'startsAt',c.starts_at,'endsAt',c.ends_at
  ) order by c.starts_at,c.id),'[]'::jsonb)
  into v_blockers
  from ledger.occurrence_resource_claims c
  join reality.resources rr on rr.id=c.resource_id
  where c.ledger_id=p_ledger_id and c.claim_state in ('tentative','confirmed')
    and c.starts_at<p_ends_at and c.ends_at>p_starts_at
    and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
    and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id)
    and c.resource_id in (select d.resource_id from ledger.resource_conflict_domain_v1(p_resource_id) d)
    and (p_requested_claim_kind='exclusive' or c.claim_kind='exclusive');

  select coalesce(jsonb_agg(jsonb_build_object(
    'holdId',h.id,'bookingRequestId',h.request_id,'resourceId',h.resource_id,'resourceLabel',rr.label,
    'claimKind',h.claim_kind,'startsAt',h.starts_at,'endsAt',h.ends_at,'expiresAt',h.expires_at
  ) order by h.starts_at,h.id),'[]'::jsonb)
  into v_hold_blockers
  from ledger.booking_request_holds h
  join ledger.booking_requests br on br.id=h.request_id and br.request_state in ('submitted','approved')
  join reality.resources rr on rr.id=h.resource_id
  where h.ledger_id=p_ledger_id and h.hold_state='active' and h.expires_at>now()
    and h.starts_at<p_ends_at and h.ends_at>p_starts_at
    and h.resource_id in (select d.resource_id from ledger.resource_conflict_domain_v1(p_resource_id) d)
    and (p_requested_claim_kind='exclusive' or h.claim_kind='exclusive');

  if v_resource.capacity_mode='quantity' and p_requested_claim_kind='capacity' then
    select coalesce(sum(c.quantity),0) into v_capacity_used
    from ledger.occurrence_resource_claims c
    where c.ledger_id=p_ledger_id and c.resource_id=p_resource_id
      and c.claim_state in ('tentative','confirmed') and c.claim_kind='capacity'
      and c.starts_at<p_ends_at and c.ends_at>p_starts_at
      and (p_exclude_claim_id is null or c.id<>p_exclude_claim_id)
      and (p_exclude_occurrence_id is null or c.occurrence_id<>p_exclude_occurrence_id);
    select coalesce(sum(h.quantity),0) into v_capacity_held
    from ledger.booking_request_holds h
    join ledger.booking_requests br on br.id=h.request_id and br.request_state in ('submitted','approved')
    where h.ledger_id=p_ledger_id and h.resource_id=p_resource_id
      and h.hold_state='active' and h.expires_at>now() and h.claim_kind='capacity'
      and h.starts_at<p_ends_at and h.ends_at>p_starts_at;
    v_capacity_exceeded:=v_capacity_used+v_capacity_held+p_requested_quantity>v_resource.capacity_quantity;
  end if;

  for v_related_resource in
    select r.id,r.label from ledger.resource_conflict_domain_v1(p_resource_id) d
    join reality.resources r on r.id=d.resource_id order by r.id
  loop
    v_schedule_result:=reality.subject_schedule_availability_v1('resource',v_related_resource.id,p_starts_at,p_ends_at);
    v_schedule_checks:=v_schedule_checks||jsonb_build_array(jsonb_build_object(
      'resourceId',v_related_resource.id,'resourceLabel',v_related_resource.label,'availability',v_schedule_result
    ));
    if not coalesce((v_schedule_result->>'available')::boolean,true) then v_schedule_available:=false; end if;
  end loop;

  v_available:=v_resource.resource_state='active' and v_resource.reservable
    and jsonb_array_length(v_blockers)=0 and jsonb_array_length(v_hold_blockers)=0
    and not v_capacity_exceeded and v_schedule_available;

  return jsonb_build_object(
    'contractVersion','ledger_resource_availability_v3','ledgerId',p_ledger_id,
    'resourceId',v_resource.id,'resourceLabel',v_resource.label,'windowStart',p_starts_at,'windowEnd',p_ends_at,
    'requestedClaimKind',p_requested_claim_kind,'requestedQuantity',p_requested_quantity,
    'available',v_available,'resourceState',v_resource.resource_state,'reservable',v_resource.reservable,
    'capacityMode',v_resource.capacity_mode,'capacityQuantity',v_resource.capacity_quantity,'capacityUnit',v_resource.capacity_unit,
    'capacityUsed',v_capacity_used+v_capacity_held,'capacityCommitted',v_capacity_used,'capacityHeld',v_capacity_held,
    'capacityExceeded',v_capacity_exceeded,'scheduleAvailable',v_schedule_available,'scheduleChecks',v_schedule_checks,
    'blockingClaims',v_blockers,'blockingHolds',v_hold_blockers
  );
end;
$$;

create or replace function ledger.establish_booking_bundle_service_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_booking_kind text,
  p_claims jsonb,
  p_customer_entity_id uuid default null,
  p_business_model_key text default null,
  p_booking_label text default null,
  p_booking_state text default 'hold',
  p_created_by_seat_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_booking_json jsonb;
  v_booking_id uuid;
  v_resource_ids uuid[];
  v_claim jsonb;
  v_claim_result jsonb;
  v_claim_results jsonb:='[]'::jsonb;
  v_idx integer:=0;
  v_claim_idem text;
  v_occ_start timestamptz;
  v_occ_end timestamptz;
  v_policy jsonb;
  v_setup integer:=0;
  v_teardown integer:=0;
  v_claim_start timestamptz;
  v_claim_end timestamptz;
  v_apply_buffers boolean;
  v_approved_request_id uuid;
begin
  if p_claims is null or jsonb_typeof(p_claims)<>'array' or jsonb_array_length(p_claims)=0 then
    raise exception 'Booking bundle requires a non-empty JSON array of resource claims.' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_claims) x
    where jsonb_typeof(x)<>'object' or nullif(x->>'resourceId','') is null or nullif(x->>'claimKind','') is null
       or nullif(x->>'startsAt','') is null or nullif(x->>'endsAt','') is null
  ) then raise exception 'Every booking bundle claim requires resourceId, claimKind, startsAt, and endsAt.' using errcode='22023'; end if;

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid) into v_resource_ids
  from jsonb_array_elements(p_claims) x;
  select o.start_at,o.end_at into v_occ_start,v_occ_end from local_intel.occurrences o where o.id=p_occurrence_id;
  if v_occ_start is null then raise exception 'Booking occurrence not found.' using errcode='P0002'; end if;
  if v_occ_end is null then
    select min((x->>'startsAt')::timestamptz),max((x->>'endsAt')::timestamptz) into v_occ_start,v_occ_end
    from jsonb_array_elements(p_claims) x;
  end if;
  v_policy:=ledger.evaluate_booking_policies_v1(p_ledger_id,v_resource_ids,p_booking_kind,v_occ_start,v_occ_end,false,now());
  if not coalesce((v_policy->>'allowed')::boolean,false) then
    raise exception 'Booking violates policy: %',v_policy using errcode='23514';
  end if;

  if nullif(p_metadata->>'approvedBookingRequestId','') is not null then
    begin v_approved_request_id:=(p_metadata->>'approvedBookingRequestId')::uuid;
    exception when others then raise exception 'approvedBookingRequestId must be a UUID.' using errcode='22023'; end;
    if not ledger.booking_request_approval_matches_v1(p_ledger_id,v_approved_request_id,p_occurrence_id,p_booking_kind,p_claims) then
      raise exception 'Approved booking request does not match this booking bundle.' using errcode='23514';
    end if;
  end if;
  if p_booking_state='confirmed' and coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false)
     and v_approved_request_id is null then
    raise exception 'Booking requires approved request evidence before confirmation: %',v_policy using errcode='23514';
  end if;

  v_setup:=coalesce((v_policy->'requirements'->>'setupBufferMinutes')::integer,0);
  v_teardown:=coalesce((v_policy->'requirements'->>'teardownBufferMinutes')::integer,0);
  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);
  v_booking_json:=ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,p_business_model_key,p_booking_label,p_booking_state,p_created_by_seat_id,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('policyEvaluation',v_policy),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('atomicResourceBundle',true),p_idempotency_key
  );
  v_booking_id:=(v_booking_json->>'bookingId')::uuid;
  for v_claim in select value from jsonb_array_elements(p_claims)
  loop
    v_idx:=v_idx+1;
    v_claim_idem:=coalesce(nullif(v_claim->>'idempotencyKey',''),case when nullif(p_idempotency_key,'') is null then null else p_idempotency_key||':claim:'||v_idx::text end);
    v_apply_buffers:=coalesce((v_claim->>'applyPolicyBuffers')::boolean,true);
    v_claim_start:=(v_claim->>'startsAt')::timestamptz - case when v_apply_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_claim_end:=(v_claim->>'endsAt')::timestamptz + case when v_apply_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
    v_claim_result:=ledger.establish_occurrence_resource_claim_service_v1(
      p_ledger_id,p_occurrence_id,(v_claim->>'resourceId')::uuid,v_claim->>'claimKind',v_claim_start,v_claim_end,v_booking_id,
      coalesce(nullif(v_claim->>'claimState',''),case when p_booking_state='confirmed' then 'confirmed' else 'tentative' end),
      case when nullif(v_claim->>'quantity','') is null then null else (v_claim->>'quantity')::numeric end,
      nullif(v_claim->>'quantityUnit',''),
      coalesce(v_claim->'metadata','{}'::jsonb)||jsonb_build_object('policyBuffersApplied',v_apply_buffers,
        'setupBufferMinutes',case when v_apply_buffers then v_setup else 0 end,'teardownBufferMinutes',case when v_apply_buffers then v_teardown else 0 end),
      coalesce(v_claim->'provenance','{}'::jsonb)||jsonb_build_object('atomicBookingBundleId',v_booking_id),v_claim_idem,false
    );
    v_claim_results:=v_claim_results||jsonb_build_array(v_claim_result);
  end loop;
  return jsonb_build_object('contractVersion','ledger_booking_bundle_v3','booking',v_booking_json,
    'resourceClaims',v_claim_results,'policyEvaluation',v_policy,'approvedBookingRequestId',v_approved_request_id,'atomic',true);
end;
$$;

create or replace function ledger.transition_booking_state_service_v1(
  p_booking_id uuid,
  p_new_state text,
  p_performed_by_entity_id uuid default null,
  p_occurred_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_booking ledger.bookings%rowtype;
  v_old_state text;
  v_resource_ids uuid[];
  v_occ_start timestamptz;
  v_occ_end timestamptz;
  v_policy jsonb;
  v_approved_request_id uuid;
begin
  if p_new_state not in ('hold','confirmed','cancelled','completed','no_show') then raise exception 'Unknown booking state: %',p_new_state using errcode='22023'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Booking event payload and provenance must be JSON objects.' using errcode='22023';
  end if;
  select * into v_booking from ledger.bookings b where b.id=p_booking_id for update;
  if v_booking.id is null then raise exception 'Booking not found.' using errcode='P0002'; end if;
  v_old_state:=v_booking.booking_state;
  if v_old_state<>p_new_state then
    if not ((v_old_state='hold' and p_new_state in ('confirmed','cancelled')) or (v_old_state='confirmed' and p_new_state in ('cancelled','completed','no_show'))) then
      raise exception 'Invalid booking state transition: % -> %',v_old_state,p_new_state using errcode='23514';
    end if;
    if p_new_state='confirmed' then
      select array_agg(distinct c.resource_id order by c.resource_id),min(c.starts_at),max(c.ends_at)
        into v_resource_ids,v_occ_start,v_occ_end
      from ledger.occurrence_resource_claims c where c.booking_id=v_booking.id and c.claim_state in ('tentative','confirmed');
      if v_occ_start is null then
        select o.start_at,o.end_at into v_occ_start,v_occ_end from local_intel.occurrences o where o.id=v_booking.occurrence_id;
      end if;
      if v_occ_start is not null and v_occ_end is not null then
        v_policy:=ledger.evaluate_booking_policies_v1(v_booking.ledger_id,v_resource_ids,v_booking.booking_kind,v_occ_start,v_occ_end,false,p_occurred_at);
        if not coalesce((v_policy->>'allowed')::boolean,false) then
          raise exception 'Booking cannot be confirmed under current policy: %',v_policy using errcode='23514';
        end if;
        if coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false) then
          begin v_approved_request_id:=nullif(v_booking.metadata->>'approvedBookingRequestId','')::uuid;
          exception when others then v_approved_request_id:=null; end;
          if v_approved_request_id is null or not exists(
            select 1 from ledger.booking_requests br
            where br.id=v_approved_request_id and br.ledger_id=v_booking.ledger_id
              and br.request_state in ('approved','converted') and br.booking_kind=v_booking.booking_kind
              and (br.occurrence_id is null or br.occurrence_id=v_booking.occurrence_id)
          ) then
            raise exception 'Booking requires approved request evidence before confirmation.' using errcode='23514';
          end if;
        end if;
      end if;
    end if;

    update ledger.bookings
    set booking_state=p_new_state,
        confirmed_at=case when p_new_state='confirmed' then coalesce(confirmed_at,p_occurred_at) else confirmed_at end,
        cancelled_at=case when p_new_state='cancelled' then coalesce(cancelled_at,p_occurred_at) else cancelled_at end,
        completed_at=case when p_new_state='completed' then coalesce(completed_at,p_occurred_at) else completed_at end
    where id=p_booking_id returning * into v_booking;
    if p_new_state='confirmed' then
      update ledger.occurrence_resource_claims
      set claim_state='confirmed',metadata=metadata||jsonb_build_object('confirmedByBookingState','confirmed','confirmedAt',p_occurred_at)
      where booking_id=p_booking_id and claim_state='tentative';
    elsif p_new_state='cancelled' then
      update ledger.occurrence_resource_claims
      set claim_state='released',metadata=metadata||jsonb_build_object('releasedByBookingState','cancelled','releasedAt',p_occurred_at)
      where booking_id=p_booking_id and claim_state in ('tentative','confirmed');
    end if;
  end if;
  insert into ledger.booking_events(booking_id,event_kind,occurred_at,performed_by_entity_id,payload,provenance,idempotency_key)
  values(p_booking_id,'state.'||p_new_state,p_occurred_at,p_performed_by_entity_id,
    jsonb_build_object('fromState',v_old_state,'toState',p_new_state)||p_payload,p_provenance,nullif(btrim(p_idempotency_key),''))
  on conflict(booking_id,idempotency_key) where idempotency_key is not null do nothing;
  return jsonb_build_object('contractVersion','ledger_booking_state_v2','bookingId',v_booking.id,'previousState',v_old_state,'bookingState',v_booking.booking_state);
end;
$$;

create or replace function ledger.materialize_booking_request_service_v1(
  p_request_id uuid,
  p_occurrence_id uuid,
  p_created_by_seat_id uuid,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_request ledger.booking_requests%rowtype;
  v_occurrence_id uuid;
  v_resource_ids uuid[];
  v_claims jsonb;
  v_bundle jsonb;
  v_booking_id uuid;
  v_expired integer:=0;
  v_converted integer:=0;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state='converted' and v_request.converted_booking_id is not null then
    return jsonb_build_object('contractVersion','ledger_booking_request_materialization_v1','request',ledger.booking_request_detail_v1(p_request_id),
      'bookingId',v_request.converted_booking_id,'alreadyConverted',true);
  end if;
  if v_request.request_state<>'approved' then raise exception 'Booking request must be approved before materialization.' using errcode='23514'; end if;
  v_occurrence_id:=coalesce(v_request.occurrence_id,p_occurrence_id);
  if v_occurrence_id is null then
    raise exception 'Approved request requires a canonical occurrence before booking materialization.' using errcode='23514';
  end if;
  if v_request.occurrence_id is not null and p_occurrence_id is not null and v_request.occurrence_id<>p_occurrence_id then
    raise exception 'Materialization occurrence does not match the approved request occurrence.' using errcode='23514';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=v_occurrence_id) then
    raise exception 'Canonical occurrence not found.' using errcode='P0002';
  end if;
  if v_request.occurrence_id is null then
    update ledger.booking_requests set occurrence_id=v_occurrence_id where id=p_request_id returning * into v_request;
  end if;

  select array_agg(distinct rr.resource_id order by rr.resource_id),
         coalesce(jsonb_agg(jsonb_build_object(
           'resourceId',rr.resource_id,'claimKind',rr.claim_kind,'startsAt',rr.starts_at,'endsAt',rr.ends_at,
           'quantity',rr.quantity,'quantityUnit',rr.quantity_unit,'applyPolicyBuffers',rr.apply_policy_buffers,
           'metadata',rr.metadata||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id),
           'provenance',rr.provenance||jsonb_build_object('bookingRequestId',p_request_id,'bookingRequestResourceId',rr.id)
         ) order by rr.starts_at,rr.id),'[]'::jsonb)
    into v_resource_ids,v_claims
  from ledger.booking_request_resources rr where rr.request_id=p_request_id;
  if v_resource_ids is null or cardinality(v_resource_ids)=0 then raise exception 'Booking request has no Resource lines.' using errcode='23514'; end if;

  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);
  update ledger.booking_request_holds
  set hold_state='expired',released_at=coalesce(released_at,now()),reason=coalesce(reason,'expired before materialization')
  where request_id=p_request_id and hold_state='active' and expires_at<=now();
  get diagnostics v_expired=row_count;
  update ledger.booking_request_holds
  set hold_state='converted',converted_at=now(),reason=coalesce(reason,'converted to booking')
  where request_id=p_request_id and hold_state='active' and expires_at>now();
  get diagnostics v_converted=row_count;

  v_bundle:=ledger.establish_booking_bundle_service_v1(
    v_request.ledger_id,v_occurrence_id,v_request.booking_kind,v_claims,v_request.customer_entity_id,
    v_request.business_model_key,v_request.request_label,'confirmed',p_created_by_seat_id,
    v_request.metadata||jsonb_build_object('bookingRequestId',p_request_id,'approvedBookingRequestId',p_request_id,'requestPurpose',v_request.purpose),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('bookingRequestId',p_request_id,'approvedRequestMaterialization',true),
    p_idempotency_key
  );
  v_booking_id:=(v_bundle->'booking'->>'bookingId')::uuid;
  update ledger.booking_requests
  set request_state='converted',converted_at=now(),converted_booking_id=v_booking_id
  where id=p_request_id;
  perform ledger.append_booking_request_event_v1(
    p_request_id,'request.converted',null,p_created_by_seat_id,
    jsonb_build_object('bookingId',v_booking_id,'occurrenceId',v_occurrence_id,'convertedHolds',v_converted,'expiredHolds',v_expired),
    p_provenance,case when nullif(btrim(p_idempotency_key),'') is null then null else btrim(p_idempotency_key)||':converted' end,now()
  );
  return jsonb_build_object('contractVersion','ledger_booking_request_materialization_v1',
    'request',ledger.booking_request_detail_v1(p_request_id),'bookingBundle',v_bundle,'alreadyConverted',false);
end;
$$;

create or replace function ledger.booking_requests_service_v1(
  p_ledger_id uuid,
  p_request_state text default null
) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if not exists(select 1 from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active') then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;
  select jsonb_build_object(
    'contractVersion','ledger_booking_requests_v1','ledgerId',p_ledger_id,
    'items',coalesce(jsonb_agg(ledger.booking_request_detail_v1(br.id) order by br.created_at desc,br.id desc),'[]'::jsonb)
  ) into v_result
  from ledger.booking_requests br
  where br.ledger_id=p_ledger_id and (p_request_state is null or br.request_state=p_request_state);
  return v_result;
end;
$$;

create or replace function atlas.current_active_ledger_seat_v1(p_ledger_id uuid)
returns uuid
language plpgsql stable security definer set search_path='' as $$
declare v_person uuid; v_seat uuid;
begin
  v_person:=atlas.current_person_id_v1();
  select s.id into v_seat from ledger.seats s
  where s.ledger_id=p_ledger_id and s.person_entity_id=v_person and s.seat_state='active'
  order by s.began_at desc,s.id limit 1;
  if v_seat is null then raise exception 'Active Ledger Seat required.' using errcode='42501'; end if;
  return v_seat;
end;
$$;

create or replace function atlas.ledger_booking_requests_self_api_v1(
  p_ledger_id uuid,
  p_request_state text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.read');
  return ledger.booking_requests_service_v1(p_ledger_id,p_request_state);
end;
$$;

create or replace function atlas.submit_ledger_booking_request_self_api_v1(
  p_ledger_id uuid,
  p_booking_kind text,
  p_resource_requests jsonb,
  p_occurrence_id uuid default null,
  p_customer_entity_id uuid default null,
  p_business_model_key text default null,
  p_request_label text default null,
  p_purpose text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.submit');
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.submit_booking_request_service_v1(
    p_ledger_id,p_occurrence_id,v_person,v_seat,p_customer_entity_id,p_booking_kind,p_business_model_key,
    p_request_label,p_purpose,p_resource_requests,p_metadata,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),
    p_idempotency_key
  );
end;
$$;

create or replace function atlas.hold_ledger_booking_request_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_expires_at timestamptz,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.hold');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.establish_booking_request_holds_service_v1(
    p_request_id,p_expires_at,v_seat,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

create or replace function atlas.assign_ledger_booking_request_approver_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_approver_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.delegate');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.assign_booking_request_approver_service_v1(
    p_request_id,p_approver_seat_id,v_seat,p_reason,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

create or replace function atlas.delegate_ledger_booking_request_approver_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_target_seat_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.delegate');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.delegate_booking_request_approver_service_v1(
    p_request_id,v_seat,p_target_seat_id,p_reason,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

create or replace function atlas.decide_ledger_booking_request_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_decision text,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.approve');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.decide_booking_request_service_v1(
    p_request_id,p_decision,v_person,v_seat,p_reason,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

create or replace function atlas.withdraw_ledger_booking_request_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_reason text default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.submit');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.withdraw_booking_request_service_v1(
    p_request_id,v_person,v_seat,p_reason,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

create or replace function atlas.materialize_ledger_booking_request_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_occurrence_id uuid default null,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_person uuid; v_seat uuid; v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  if not exists(select 1 from ledger.booking_requests br where br.id=p_request_id and br.ledger_id=p_ledger_id) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.materialize_booking_request_service_v1(
    p_request_id,p_occurrence_id,v_seat,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation),p_idempotency_key
  );
end;
$$;

update reality.responsibility_relations
set permitted_operations=(
      select array_agg(distinct op order by op)
      from unnest(
        permitted_operations || array[
          'booking_request.read','booking_request.submit','booking_request.hold',
          'booking_request.approve','booking_request.delegate'
        ]::text[]
      ) op
    ),
    updated_at=now()
where responsibility_key='institutional_schedule_operations'
  and relation_state='active'
  and jurisdiction_kind='entity'
  and scope ? 'ledgerIds';

revoke execute on function ledger.append_booking_request_event_v1(uuid,text,uuid,uuid,jsonb,jsonb,text,timestamptz) from public,anon,authenticated;
revoke execute on function ledger.booking_request_detail_v1(uuid) from public,anon,authenticated;
revoke execute on function ledger.booking_request_approver_authorized_v1(uuid,uuid) from public,anon,authenticated;
revoke execute on function ledger.booking_request_approval_matches_v1(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;
revoke execute on function ledger.submit_booking_request_service_v1(uuid,uuid,uuid,uuid,uuid,text,text,text,text,jsonb,jsonb,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.establish_booking_request_holds_service_v1(uuid,timestamptz,uuid,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.assign_booking_request_approver_service_v1(uuid,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.delegate_booking_request_approver_service_v1(uuid,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.decide_booking_request_service_v1(uuid,text,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.withdraw_booking_request_service_v1(uuid,uuid,uuid,text,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.materialize_booking_request_service_v1(uuid,uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke execute on function ledger.booking_requests_service_v1(uuid,text) from public,anon,authenticated;
revoke execute on function atlas.current_active_ledger_seat_v1(uuid) from public,anon,authenticated;

revoke execute on function atlas.ledger_booking_requests_self_api_v1(uuid,text) from public,anon;
revoke execute on function atlas.submit_ledger_booking_request_self_api_v1(uuid,text,jsonb,uuid,uuid,text,text,text,jsonb,jsonb,text) from public,anon;
revoke execute on function atlas.hold_ledger_booking_request_self_api_v1(uuid,uuid,timestamptz,jsonb,text) from public,anon;
revoke execute on function atlas.assign_ledger_booking_request_approver_self_api_v1(uuid,uuid,uuid,text,jsonb,text) from public,anon;
revoke execute on function atlas.delegate_ledger_booking_request_approver_self_api_v1(uuid,uuid,uuid,text,jsonb,text) from public,anon;
revoke execute on function atlas.decide_ledger_booking_request_self_api_v1(uuid,uuid,text,text,jsonb,text) from public,anon;
revoke execute on function atlas.withdraw_ledger_booking_request_self_api_v1(uuid,uuid,text,jsonb,text) from public,anon;
revoke execute on function atlas.materialize_ledger_booking_request_self_api_v1(uuid,uuid,uuid,jsonb,text) from public,anon;

grant execute on function atlas.ledger_booking_requests_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.submit_ledger_booking_request_self_api_v1(uuid,text,jsonb,uuid,uuid,text,text,text,jsonb,jsonb,text) to authenticated;
grant execute on function atlas.hold_ledger_booking_request_self_api_v1(uuid,uuid,timestamptz,jsonb,text) to authenticated;
grant execute on function atlas.assign_ledger_booking_request_approver_self_api_v1(uuid,uuid,uuid,text,jsonb,text) to authenticated;
grant execute on function atlas.delegate_ledger_booking_request_approver_self_api_v1(uuid,uuid,uuid,text,jsonb,text) to authenticated;
grant execute on function atlas.decide_ledger_booking_request_self_api_v1(uuid,uuid,text,text,jsonb,text) to authenticated;
grant execute on function atlas.withdraw_ledger_booking_request_self_api_v1(uuid,uuid,text,jsonb,text) to authenticated;
grant execute on function atlas.materialize_ledger_booking_request_self_api_v1(uuid,uuid,uuid,jsonb,text) to authenticated;

comment on table ledger.booking_requests is 'Non-authoritative Ledger scheduling intentions. A request is not a booking, occurrence, or occupancy claim.';
comment on table ledger.booking_request_holds is 'Expiring provisional Resource-capacity reservations for booking requests. Holds block availability while active and unexpired but are not occurrence occupancy claims.';
comment on table ledger.booking_request_approval_assignments is 'Current/replayed routing of booking-request review to an already-authorized Ledger Seat. Assignment never grants approval authority.';
comment on function atlas.submit_ledger_booking_request_self_api_v1(uuid,text,jsonb,uuid,uuid,text,text,text,jsonb,jsonb,text)
is 'Authenticated request submission. Records requested Resources/time and evaluation without establishing booking or occupancy truth.';
comment on function atlas.hold_ledger_booking_request_self_api_v1(uuid,uuid,timestamptz,jsonb,text)
is 'Authenticated expiring hold over all Resources requested by one booking request. Hold is provisional capacity, not a Booking or occurrence claim.';
comment on function atlas.decide_ledger_booking_request_self_api_v1(uuid,uuid,text,text,jsonb,text)
is 'Authenticated approve/reject decision by a Seat that already carries booking-request approval responsibility.';
comment on function atlas.materialize_ledger_booking_request_self_api_v1(uuid,uuid,uuid,jsonb,text)
is 'Materializes an approved request into one confirmed Booking plus its Resource Claims atomically. Canonical occurrence identity is required before materialization.';
