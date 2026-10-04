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

  if tg_op='INSERT' and new.requester_seat_id is not null then
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
       or new.request_label is distinct from old.request_label
       or new.purpose is distinct from old.purpose
       or new.submission_evaluation is distinct from old.submission_evaluation
       or new.metadata is distinct from old.metadata
       or new.provenance is distinct from old.provenance
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
    raise exception 'Booking request Resource requires an active request Ledger.' using errcode='23514';
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

  if v_request_ledger is null or v_request_ledger<>new.ledger_id then
    raise exception 'Booking request hold Ledger mismatch.' using errcode='23514';
  end if;
  if v_line.id is null or v_line.request_id<>new.request_id
     or v_line.resource_id<>new.resource_id
     or v_line.claim_kind<>new.claim_kind
     or v_line.quantity is distinct from new.quantity
     or v_line.quantity_unit is distinct from new.quantity_unit then
    raise exception 'Booking request hold must remain anchored to its request Resource line.' using errcode='23514';
  end if;
  if new.starts_at>v_line.starts_at or new.ends_at<v_line.ends_at then
    raise exception 'Booking request hold must cover the requested Resource interval.' using errcode='23514';
  end if;

  if tg_op='INSERT' then
    select s.ledger_id into v_seat_ledger from ledger.seats s
    where s.id=new.created_by_seat_id and s.seat_state='active';
    if v_seat_ledger is null or v_seat_ledger<>new.ledger_id then
      raise exception 'Booking request hold creator must have an active Seat in the Ledger.' using errcode='23514';
    end if;
  else
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
  if v_request_ledger is null or new.ledger_id<>v_request_ledger then
    raise exception 'Booking request approval assignment Ledger mismatch.' using errcode='23514';
  end if;

  if tg_op='INSERT' then
    select s.ledger_id into v_approver_ledger from ledger.seats s where s.id=new.approver_seat_id and s.seat_state='active';
    select s.ledger_id into v_assigner_ledger from ledger.seats s where s.id=new.assigned_by_seat_id and s.seat_state='active';
    if v_approver_ledger<>v_request_ledger or v_assigner_ledger<>v_request_ledger then
      raise exception 'Booking request approval assignment Seats must be active in the request Ledger.' using errcode='23514';
    end if;
    if new.delegated_from_assignment_id is not null then
      select a.request_id into v_delegated_request
      from ledger.booking_request_approval_assignments a where a.id=new.delegated_from_assignment_id;
      if v_delegated_request is null or v_delegated_request<>new.request_id then
        raise exception 'Delegated approval assignment must remain within one request.' using errcode='23514';
      end if;
    end if;
  else
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
  where br.id=p_request_id and br.ledger_id=p_ledger_id and br.request_state='approved';
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

revoke execute on function ledger.append_booking_request_event_v1(uuid,text,uuid,uuid,jsonb,jsonb,text,timestamptz) from public,anon,authenticated;
revoke execute on function ledger.booking_request_detail_v1(uuid) from public,anon,authenticated;
revoke execute on function ledger.booking_request_approver_authorized_v1(uuid,uuid) from public,anon,authenticated;
revoke execute on function ledger.booking_request_approval_matches_v1(uuid,uuid,uuid,text,jsonb) from public,anon,authenticated;

comment on table ledger.booking_requests is 'Non-authoritative Ledger scheduling intentions. A request is not a booking, occurrence, or occupancy claim.';
comment on table ledger.booking_request_holds is 'Expiring provisional Resource-capacity reservations for booking requests. Holds block availability while active and unexpired but are not occurrence occupancy claims.';
comment on table ledger.booking_request_approval_assignments is 'Current/replayed routing of booking-request review to an already-authorized Ledger Seat. Assignment never grants approval authority.';
