create or replace function ledger.capture_booking_request_selection_service_v1(
  p_request_id uuid,
  p_resource_requests jsonb,
  p_performed_by_entity_id uuid default null,
  p_performed_by_seat_id uuid default null,
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
  v_inserted_ids jsonb:='[]'::jsonb;
  v_resource_line_id uuid;
begin
  if p_resource_requests is null or jsonb_typeof(p_resource_requests)<>'array' or jsonb_array_length(p_resource_requests)=0 then
    raise exception 'Booking request selection requires at least one Resource request.' using errcode='22023';
  end if;
  if p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Booking request selection provenance must be a JSON object.' using errcode='22023';
  end if;

  select * into v_request
  from ledger.booking_requests br
  where br.id=p_request_id
  for update;

  if v_request.id is null then
    raise exception 'Booking request not found.' using errcode='P0002';
  end if;
  if v_request.request_state<>'submitted' then
    raise exception 'Resource selection may only be captured on a submitted booking request.' using errcode='23514';
  end if;

  if nullif(btrim(p_idempotency_key),'') is not null and exists(
    select 1 from ledger.booking_request_events e
    where e.request_id=p_request_id and e.idempotency_key=btrim(p_idempotency_key)
  ) then
    return ledger.booking_request_detail_v1(p_request_id);
  end if;

  if exists(select 1 from ledger.booking_request_resources rr where rr.request_id=p_request_id) then
    raise exception 'Booking request already has an immutable Resource selection. Create a revision request rather than overwriting established selection evidence.' using errcode='23514';
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

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid),
         min((x->>'startsAt')::timestamptz),
         max((x->>'endsAt')::timestamptz)
    into v_resource_ids,v_start,v_end
  from jsonb_array_elements(p_resource_requests) x;

  if v_start is null or v_end is null or v_end<=v_start then
    raise exception 'Booking request Resource intervals are invalid.' using errcode='22023';
  end if;

  v_policy:=ledger.evaluate_booking_policies_v1(
    v_request.ledger_id,v_resource_ids,v_request.booking_kind,v_start,v_end,false,now()
  );
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
    where r.id=(v_line->>'resourceId')::uuid
      and l.id=v_request.ledger_id
      and l.ledger_state='active'
      and r.resource_state<>'retired';

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
      v_request.ledger_id,
      (v_line->>'resourceId')::uuid,
      v_line_start,
      v_line_end,
      v_line->>'claimKind',
      case when nullif(v_line->>'quantity','') is null then null else (v_line->>'quantity')::numeric end,
      null,
      null
    );

    v_availability:=v_availability||jsonb_build_array(jsonb_build_object(
      'resourceId',(v_line->>'resourceId')::uuid,
      'requestedStartsAt',(v_line->>'startsAt')::timestamptz,
      'requestedEndsAt',(v_line->>'endsAt')::timestamptz,
      'effectiveStartsAt',v_line_start,
      'effectiveEndsAt',v_line_end,
      'availability',v_av
    ));
  end loop;

  for v_line in select value from jsonb_array_elements(p_resource_requests)
  loop
    insert into ledger.booking_request_resources(
      request_id,resource_id,claim_kind,starts_at,ends_at,quantity,quantity_unit,
      apply_policy_buffers,metadata,provenance
    ) values(
      p_request_id,
      (v_line->>'resourceId')::uuid,
      v_line->>'claimKind',
      (v_line->>'startsAt')::timestamptz,
      (v_line->>'endsAt')::timestamptz,
      case when nullif(v_line->>'quantity','') is null then null else (v_line->>'quantity')::numeric end,
      nullif(v_line->>'quantityUnit',''),
      coalesce((v_line->>'applyPolicyBuffers')::boolean,true),
      coalesce(v_line->'metadata','{}'::jsonb),
      coalesce(v_line->'provenance','{}'::jsonb)||coalesce(p_provenance,'{}'::jsonb)
    ) returning id into v_resource_line_id;
    v_inserted_ids:=v_inserted_ids||jsonb_build_array(v_resource_line_id);
  end loop;

  perform ledger.append_booking_request_event_v1(
    p_request_id,
    'selection.captured',
    p_performed_by_entity_id,
    p_performed_by_seat_id,
    jsonb_build_object(
      'resourceLineIds',v_inserted_ids,
      'policyEvaluation',v_policy,
      'resourceAvailability',v_availability,
      'selectionImmutable',true,
      'nextState',case
        when coalesce((v_policy->>'allowed')::boolean,false)
         and not exists(
           select 1 from jsonb_array_elements(v_availability) a
           where not coalesce((a->'availability'->>'available')::boolean,false)
         )
        then 'eligible_for_hold'
        else 'selection_requires_resolution'
      end
    ),
    p_provenance,
    nullif(btrim(p_idempotency_key),''),
    now()
  );

  return ledger.booking_request_detail_v1(p_request_id);
end;
$function$;

create or replace function ledger.booking_request_current_evaluation_v1(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_request ledger.booking_requests%rowtype;
  v_event ledger.booking_request_events%rowtype;
begin
  select * into v_request from ledger.booking_requests br where br.id=p_request_id;
  if v_request.id is null then
    raise exception 'Booking request not found.' using errcode='P0002';
  end if;

  select * into v_event
  from ledger.booking_request_events e
  where e.request_id=p_request_id
    and e.event_kind in ('selection.captured','request.submitted')
  order by e.occurred_at desc,e.created_at desc,e.id desc
  limit 1;

  if v_event.id is not null and v_event.event_kind='selection.captured' then
    return jsonb_build_object(
      'contractVersion','ledger_booking_request_current_evaluation_v1',
      'requestId',p_request_id,
      'evaluationSource','selection.captured',
      'eventId',v_event.id,
      'policyEvaluation',coalesce(v_event.payload->'policyEvaluation','{}'::jsonb),
      'resourceAvailability',coalesce(v_event.payload->'resourceAvailability','[]'::jsonb),
      'nextState',v_event.payload->>'nextState'
    );
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_booking_request_current_evaluation_v1',
    'requestId',p_request_id,
    'evaluationSource','submission',
    'submissionEvaluation',coalesce(v_request.submission_evaluation,'{}'::jsonb)
  );
end;
$function$;

create or replace function atlas.capture_ledger_booking_request_selection_self_api_v1(
  p_ledger_id uuid,
  p_request_id uuid,
  p_resource_requests jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_person uuid;
  v_seat uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking_request.submit');
  if not exists(
    select 1 from ledger.booking_requests br
    where br.id=p_request_id and br.ledger_id=p_ledger_id
  ) then
    raise exception 'Booking request is outside this Ledger.' using errcode='42501';
  end if;
  v_person:=atlas.current_person_id_v1();
  v_seat:=atlas.current_active_ledger_seat_v1(p_ledger_id);
  return ledger.capture_booking_request_selection_service_v1(
    p_request_id,
    p_resource_requests,
    v_person,
    v_seat,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'responsibilityRelationId',v_relation
    ),
    p_idempotency_key
  );
end;
$function$;