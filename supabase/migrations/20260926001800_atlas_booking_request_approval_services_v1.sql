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
    where r.id=(v_line->>'resourceId')::uuid and l.id=p_ledger_id
      and l.ledger_state='active' and r.resource_state<>'retired';
    if v_capacity_mode is null then
      raise exception 'Requested Resource is outside this Ledger subject.' using errcode='23514';
    end if;
    if v_line->>'claimKind'='capacity'
       and (v_capacity_mode<>'quantity' or nullif(v_line->>'quantity','') is null or (v_line->>'quantity')::numeric<=0) then
      raise exception 'Capacity request requires a quantity-governed Resource and quantity > 0.' using errcode='22023';
    end if;
    v_apply_buffers:=coalesce((v_line->>'applyPolicyBuffers')::boolean,true);
    v_line_start:=(v_line->>'startsAt')::timestamptz
      - case when v_apply_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_line_end:=(v_line->>'endsAt')::timestamptz
      + case when v_apply_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
    v_av:=ledger.resource_claim_availability_v1(
      p_ledger_id,(v_line->>'resourceId')::uuid,v_line_start,v_line_end,v_line->>'claimKind',
      case when nullif(v_line->>'quantity','') is null then null else (v_line->>'quantity')::numeric end,null,null
    );
    v_availability:=v_availability||jsonb_build_array(jsonb_build_object(
      'resourceId',(v_line->>'resourceId')::uuid,
      'requestedStartsAt',(v_line->>'startsAt')::timestamptz,'requestedEndsAt',(v_line->>'endsAt')::timestamptz,
      'effectiveStartsAt',v_line_start,'effectiveEndsAt',v_line_end,'availability',v_av
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
      v_request_id,(v_line->>'resourceId')::uuid,v_line->>'claimKind',
      (v_line->>'startsAt')::timestamptz,(v_line->>'endsAt')::timestamptz,
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
  v_hold_id uuid;
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
    select 1 from ledger.booking_request_events e
    where e.request_id=p_request_id and e.idempotency_key=btrim(p_idempotency_key)
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
  get diagnostics v_expired = row_count;

  update ledger.booking_request_holds
  set hold_state='released',released_at=coalesce(released_at,now()),reason='replaced by refreshed hold'
  where request_id=p_request_id and hold_state='active';
  get diagnostics v_released = row_count;

  for v_line in
    select * from ledger.booking_request_resources rr where rr.request_id=p_request_id order by rr.starts_at,rr.id
  loop
    v_start_effective:=v_line.starts_at
      - case when v_line.apply_policy_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_end_effective:=v_line.ends_at
      + case when v_line.apply_policy_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
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
      p_request_id,v_line.id,v_request.ledger_id,v_line.resource_id,v_line.claim_kind,
      v_start_effective,v_end_effective,v_line.quantity,v_line.quantity_unit,'active',p_expires_at,p_created_by_seat_id,
      jsonb_build_object(
        'setupBufferMinutes',case when v_line.apply_policy_buffers then v_setup else 0 end,
        'teardownBufferMinutes',case when v_line.apply_policy_buffers then v_teardown else 0 end
      ),
      coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('bookingRequestResourceId',v_line.id)
    ) returning id into v_hold_id;
    v_hold_ids:=v_hold_ids||jsonb_build_array(v_hold_id);
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
declare
  v_request ledger.booking_requests%rowtype;
  v_existing ledger.booking_request_approval_assignments%rowtype;
  v_assignment_id uuid;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state<>'submitted' then
    raise exception 'Only submitted requests may receive an approver.' using errcode='23514';
  end if;
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
  ) values(
    p_request_id,v_request.ledger_id,p_approver_seat_id,p_assigned_by_seat_id,'active',p_reason,coalesce(p_provenance,'{}'::jsonb)
  ) returning id into v_assignment_id;
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
declare
  v_request ledger.booking_requests%rowtype;
  v_assignment ledger.booking_request_approval_assignments%rowtype;
  v_new_id uuid;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state<>'submitted' then
    raise exception 'Only submitted requests may delegate approval.' using errcode='23514';
  end if;
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
    jsonb_build_object(
      'fromAssignmentId',v_assignment.id,'toAssignmentId',v_new_id,
      'fromSeatId',p_from_seat_id,'toSeatId',p_target_seat_id,'reason',p_reason
    ),p_provenance,p_idempotency_key,now()
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
declare
  v_request ledger.booking_requests%rowtype;
  v_assignment ledger.booking_request_approval_assignments%rowtype;
  v_assignment_id uuid;
  v_released integer:=0;
begin
  if p_decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected.' using errcode='22023';
  end if;
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
      p_request_id,v_request.ledger_id,p_decided_by_seat_id,p_decided_by_seat_id,
      'active','self-claimed for decision',jsonb_build_object('assignmentMode','self_claimed'),coalesce(p_provenance,'{}'::jsonb)
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
    get diagnostics v_released = row_count;
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
  if v_request.request_state not in ('submitted','approved') then
    raise exception 'This booking request can no longer be withdrawn.' using errcode='23514';
  end if;
  if v_request.requester_entity_id is not null then
    if v_request.requester_entity_id<>p_requester_entity_id then
      raise exception 'Only the original requester may withdraw this request.' using errcode='42501';
    end if;
  elsif v_request.requester_seat_id is distinct from p_requester_seat_id then
    raise exception 'Only the original requesting Seat may withdraw this request.' using errcode='42501';
  end if;
  update ledger.booking_requests
  set request_state='withdrawn',withdrawn_at=now(),decision_reason=coalesce(p_reason,decision_reason)
  where id=p_request_id;
  update ledger.booking_request_holds
  set hold_state='released',released_at=coalesce(released_at,now()),reason=coalesce(p_reason,'request withdrawn')
  where request_id=p_request_id and hold_state='active';
  get diagnostics v_released = row_count;
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
  v_approved_request ledger.booking_requests%rowtype;
  v_actor_entity uuid;
  v_expired_holds integer:=0;
  v_converted_holds integer:=0;
begin
  if p_claims is null or jsonb_typeof(p_claims)<>'array' or jsonb_array_length(p_claims)=0 then
    raise exception 'Booking bundle requires a non-empty JSON array of resource claims.' using errcode='22023';
  end if;
  if exists(
    select 1 from jsonb_array_elements(p_claims) x
    where jsonb_typeof(x)<>'object'
       or nullif(x->>'resourceId','') is null or nullif(x->>'claimKind','') is null
       or nullif(x->>'startsAt','') is null or nullif(x->>'endsAt','') is null
  ) then
    raise exception 'Every booking bundle claim requires resourceId, claimKind, startsAt, and endsAt.' using errcode='22023';
  end if;

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid)
    into v_resource_ids from jsonb_array_elements(p_claims) x;
  select o.start_at,o.end_at into v_occ_start,v_occ_end
  from local_intel.occurrences o where o.id=p_occurrence_id;
  if v_occ_start is null then raise exception 'Booking occurrence not found.' using errcode='P0002'; end if;
  if v_occ_end is null then
    select min((x->>'startsAt')::timestamptz),max((x->>'endsAt')::timestamptz)
      into v_occ_start,v_occ_end from jsonb_array_elements(p_claims) x;
  end if;

  v_policy:=ledger.evaluate_booking_policies_v1(
    p_ledger_id,v_resource_ids,p_booking_kind,v_occ_start,v_occ_end,false,now()
  );
  if not coalesce((v_policy->>'allowed')::boolean,false) then
    raise exception 'Booking violates policy: %',v_policy using errcode='23514';
  end if;

  if nullif(p_metadata->>'approvedBookingRequestId','') is not null then
    begin
      v_approved_request_id:=(p_metadata->>'approvedBookingRequestId')::uuid;
    exception when others then
      raise exception 'approvedBookingRequestId must be a UUID.' using errcode='22023';
    end;
    select * into v_approved_request
    from ledger.booking_requests br
    where br.id=v_approved_request_id and br.ledger_id=p_ledger_id
    for update;
    if v_approved_request.id is null or v_approved_request.request_state<>'approved' then
      raise exception 'Approved booking request evidence is missing, consumed, or no longer approved.' using errcode='23514';
    end if;
    if p_booking_state<>'confirmed' then
      raise exception 'Approved booking request evidence is consumed only by confirmed materialization.' using errcode='23514';
    end if;
    if not ledger.booking_request_approval_matches_v1(
      p_ledger_id,v_approved_request_id,p_occurrence_id,p_booking_kind,p_claims
    ) then
      raise exception 'Approved booking request does not match this booking bundle.' using errcode='23514';
    end if;
  end if;

  if p_booking_state='confirmed'
     and coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false)
     and v_approved_request_id is null then
    raise exception 'Booking requires approved request materialization before confirmation: %',v_policy using errcode='23514';
  end if;

  v_setup:=coalesce((v_policy->'requirements'->>'setupBufferMinutes')::integer,0);
  v_teardown:=coalesce((v_policy->'requirements'->>'teardownBufferMinutes')::integer,0);
  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);

  if v_approved_request_id is not null then
    update ledger.booking_request_holds
    set hold_state='expired',released_at=coalesce(released_at,now()),reason=coalesce(reason,'expired before booking conversion')
    where request_id=v_approved_request_id and hold_state='active' and expires_at<=now();
    get diagnostics v_expired_holds = row_count;
    update ledger.booking_request_holds
    set hold_state='converted',converted_at=now(),reason=coalesce(reason,'converted to booking')
    where request_id=v_approved_request_id and hold_state='active' and expires_at>now();
    get diagnostics v_converted_holds = row_count;
  end if;

  v_booking_json:=ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,p_created_by_seat_id,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('policyEvaluation',v_policy),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object('atomicResourceBundle',true),
    p_idempotency_key
  );
  v_booking_id:=(v_booking_json->>'bookingId')::uuid;

  for v_claim in select value from jsonb_array_elements(p_claims)
  loop
    v_idx:=v_idx+1;
    v_claim_idem:=coalesce(
      nullif(v_claim->>'idempotencyKey',''),
      case when nullif(p_idempotency_key,'') is null then null else p_idempotency_key||':claim:'||v_idx::text end
    );
    v_apply_buffers:=coalesce((v_claim->>'applyPolicyBuffers')::boolean,true);
    v_claim_start:=(v_claim->>'startsAt')::timestamptz
      - case when v_apply_buffers then make_interval(mins=>v_setup) else interval '0 minutes' end;
    v_claim_end:=(v_claim->>'endsAt')::timestamptz
      + case when v_apply_buffers then make_interval(mins=>v_teardown) else interval '0 minutes' end;
    v_claim_result:=ledger.establish_occurrence_resource_claim_service_v1(
      p_ledger_id,p_occurrence_id,(v_claim->>'resourceId')::uuid,v_claim->>'claimKind',
      v_claim_start,v_claim_end,v_booking_id,
      coalesce(nullif(v_claim->>'claimState',''),case when p_booking_state='confirmed' then 'confirmed' else 'tentative' end),
      case when nullif(v_claim->>'quantity','') is null then null else (v_claim->>'quantity')::numeric end,
      nullif(v_claim->>'quantityUnit',''),
      coalesce(v_claim->'metadata','{}'::jsonb)||jsonb_build_object(
        'policyBuffersApplied',v_apply_buffers,
        'setupBufferMinutes',case when v_apply_buffers then v_setup else 0 end,
        'teardownBufferMinutes',case when v_apply_buffers then v_teardown else 0 end
      ),
      coalesce(v_claim->'provenance','{}'::jsonb)||jsonb_build_object('atomicBookingBundleId',v_booking_id),
      v_claim_idem,false
    );
    v_claim_results:=v_claim_results||jsonb_build_array(v_claim_result);
  end loop;

  if v_approved_request_id is not null then
    update ledger.booking_requests
    set occurrence_id=coalesce(occurrence_id,p_occurrence_id),
        request_state='converted',converted_at=now(),converted_booking_id=v_booking_id
    where id=v_approved_request_id;
    select s.person_entity_id into v_actor_entity
    from ledger.seats s where s.id=p_created_by_seat_id;
    perform ledger.append_booking_request_event_v1(
      v_approved_request_id,'request.converted',v_actor_entity,p_created_by_seat_id,
      jsonb_build_object(
        'bookingId',v_booking_id,'occurrenceId',p_occurrence_id,
        'convertedHolds',v_converted_holds,'expiredHolds',v_expired_holds
      ),p_provenance,
      case when nullif(btrim(p_idempotency_key),'') is null then null else btrim(p_idempotency_key)||':request-converted' end,
      now()
    );
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_booking_bundle_v3','booking',v_booking_json,
    'resourceClaims',v_claim_results,'policyEvaluation',v_policy,
    'approvedBookingRequestId',v_approved_request_id,'atomic',true
  );
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
begin
  if p_new_state not in ('hold','confirmed','cancelled','completed','no_show') then
    raise exception 'Unknown booking state: %',p_new_state using errcode='22023';
  end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Booking event payload and provenance must be JSON objects.' using errcode='22023';
  end if;
  select * into v_booking from ledger.bookings b where b.id=p_booking_id for update;
  if v_booking.id is null then raise exception 'Booking not found.' using errcode='P0002'; end if;
  v_old_state:=v_booking.booking_state;

  if v_old_state<>p_new_state then
    if not ((v_old_state='hold' and p_new_state in ('confirmed','cancelled'))
      or (v_old_state='confirmed' and p_new_state in ('cancelled','completed','no_show'))) then
      raise exception 'Invalid booking state transition: % -> %',v_old_state,p_new_state using errcode='23514';
    end if;

    if p_new_state='confirmed' then
      select array_agg(distinct c.resource_id order by c.resource_id),min(c.starts_at),max(c.ends_at)
        into v_resource_ids,v_occ_start,v_occ_end
      from ledger.occurrence_resource_claims c
      where c.booking_id=v_booking.id and c.claim_state in ('tentative','confirmed');
      if v_occ_start is null then
        select o.start_at,o.end_at into v_occ_start,v_occ_end
        from local_intel.occurrences o where o.id=v_booking.occurrence_id;
      end if;
      if v_occ_start is not null and v_occ_end is not null then
        v_policy:=ledger.evaluate_booking_policies_v1(
          v_booking.ledger_id,v_resource_ids,v_booking.booking_kind,v_occ_start,v_occ_end,false,p_occurred_at
        );
        if not coalesce((v_policy->>'allowed')::boolean,false) then
          raise exception 'Booking cannot be confirmed under current policy: %',v_policy using errcode='23514';
        end if;
        if coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false) then
          raise exception 'Approval-required holds must be materialized through an approved booking request.' using errcode='23514';
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
      set claim_state='confirmed',metadata=metadata||jsonb_build_object(
        'confirmedByBookingState','confirmed','confirmedAt',p_occurred_at
      )
      where booking_id=p_booking_id and claim_state='tentative';
    elsif p_new_state='cancelled' then
      update ledger.occurrence_resource_claims
      set claim_state='released',metadata=metadata||jsonb_build_object(
        'releasedByBookingState','cancelled','releasedAt',p_occurred_at
      )
      where booking_id=p_booking_id and claim_state in ('tentative','confirmed');
    end if;
  end if;

  insert into ledger.booking_events(
    booking_id,event_kind,occurred_at,performed_by_entity_id,payload,provenance,idempotency_key
  ) values(
    p_booking_id,'state.'||p_new_state,p_occurred_at,p_performed_by_entity_id,
    jsonb_build_object('fromState',v_old_state,'toState',p_new_state)||p_payload,
    p_provenance,nullif(btrim(p_idempotency_key),'')
  )
  on conflict(booking_id,idempotency_key) where idempotency_key is not null do nothing;

  return jsonb_build_object(
    'contractVersion','ledger_booking_state_v2','bookingId',v_booking.id,
    'previousState',v_old_state,'bookingState',v_booking.booking_state
  );
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
  v_claims jsonb;
  v_bundle jsonb;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id for update;
  if v_request.id is null then raise exception 'Booking request not found.' using errcode='P0002'; end if;
  if v_request.request_state='converted' and v_request.converted_booking_id is not null then
    return jsonb_build_object(
      'contractVersion','ledger_booking_request_materialization_v1',
      'request',ledger.booking_request_detail_v1(p_request_id),
      'bookingId',v_request.converted_booking_id,'alreadyConverted',true
    );
  end if;
  if v_request.request_state<>'approved' then
    raise exception 'Booking request must be approved before materialization.' using errcode='23514';
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
      'bookingRequestId',p_request_id,'approvedBookingRequestId',p_request_id,'requestPurpose',v_request.purpose
    ),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'bookingRequestId',p_request_id,'approvedRequestMaterialization',true
    ),p_idempotency_key
  );

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_materialization_v1',
    'request',ledger.booking_request_detail_v1(p_request_id),
    'bookingBundle',v_bundle,'alreadyConverted',false
  );
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
  select s.id into v_seat
  from ledger.seats s
  where s.ledger_id=p_ledger_id and s.person_entity_id=v_person and s.seat_state='active'
  order by s.began_at desc,s.id limit 1;
  if v_seat is null then raise exception 'Active Ledger Seat required.' using errcode='42501'; end if;
  return v_seat;
end;
$$;

create or replace function atlas.establish_ledger_booking_self_api_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_booking_kind text,
  p_customer_entity_id uuid default null,
  p_business_model_key text default null,
  p_booking_label text default null,
  p_booking_state text default 'hold',
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  v_person uuid;
  v_seat uuid;
  v_relation uuid;
  v_occ_start timestamptz;
  v_occ_end timestamptz;
  v_policy jsonb;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);

  select o.start_at,o.end_at into v_occ_start,v_occ_end
  from local_intel.occurrences o where o.id=p_occurrence_id;
  if v_occ_start is null then raise exception 'Booking occurrence not found.' using errcode='P0002'; end if;
  if v_occ_end is not null then
    v_policy:=ledger.evaluate_booking_policies_v1(
      p_ledger_id,'{}'::uuid[],p_booking_kind,v_occ_start,v_occ_end,false,now()
    );
    if not coalesce((v_policy->>'allowed')::boolean,false) then
      raise exception 'Booking violates current Ledger policy: %',v_policy using errcode='23514';
    end if;
    if p_booking_state='confirmed'
       and coalesce((v_policy->'requirements'->>'approvalRequired')::boolean,false) then
      raise exception 'Approval-required booking must be materialized from an approved booking request.' using errcode='23514';
    end if;
  else
    v_policy:='{}'::jsonb;
  end if;

  return ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,v_seat,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('policyEvaluation',v_policy),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
  );
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,'responsibilityRelationId',v_relation
    ),p_idempotency_key
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

comment on function atlas.submit_ledger_booking_request_self_api_v1(uuid,text,jsonb,uuid,uuid,text,text,text,jsonb,jsonb,text)
is 'Authenticated request submission. Records requested Resources/time and evaluation without establishing booking or occupancy truth.';
comment on function atlas.hold_ledger_booking_request_self_api_v1(uuid,uuid,timestamptz,jsonb,text)
is 'Authenticated expiring hold over all Resources requested by one booking request. Hold is provisional capacity, not a Booking or occurrence claim.';
comment on function atlas.decide_ledger_booking_request_self_api_v1(uuid,uuid,text,text,jsonb,text)
is 'Authenticated approve/reject decision by a Seat that already carries booking-request approval responsibility.';
comment on function atlas.materialize_ledger_booking_request_self_api_v1(uuid,uuid,uuid,jsonb,text)
is 'Materializes an approved request into one confirmed Booking plus its Resource Claims atomically. Canonical occurrence identity is required before materialization.';
