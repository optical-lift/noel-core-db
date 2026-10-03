
create or replace function atlas.upsert_ledger_resource_self_api_v1(
  p_ledger_id uuid,
  p_parent_resource_id uuid,
  p_stable_key text,
  p_label text,
  p_resource_kind text,
  p_resource_state text default 'active',
  p_reservable boolean default true,
  p_capacity_mode text default 'exclusive',
  p_capacity_quantity numeric default null,
  p_capacity_unit text default null,
  p_timezone_name text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_subject uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'resource.manage');

  select l.subject_entity_id into v_subject
  from ledger.ledgers l
  where l.id=p_ledger_id and l.ledger_state='active';

  return reality.upsert_resource_service_v1(
    v_subject,p_parent_resource_id,p_stable_key,p_label,p_resource_kind,
    p_resource_state,p_reservable,p_capacity_mode,p_capacity_quantity,p_capacity_unit,p_timezone_name,
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'managedThroughLedgerId',p_ledger_id,
      'responsibilityRelationId',v_relation
    )
  );
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
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_person uuid;
  v_seat uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  v_person:=atlas.current_person_id_v1();

  select s.id into v_seat
  from ledger.seats s
  where s.ledger_id=p_ledger_id
    and s.person_entity_id=v_person
    and s.seat_state='active'
  order by s.began_at desc,s.id
  limit 1;

  if v_seat is null then
    raise exception 'Active Ledger Seat required to establish a booking.'
      using errcode='42501';
  end if;

  return ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,v_seat,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'responsibilityRelationId',v_relation
    ),
    p_idempotency_key
  );
end;
$$;

create or replace function atlas.transition_ledger_booking_self_api_v1(
  p_ledger_id uuid,
  p_booking_id uuid,
  p_new_state text,
  p_occurred_at timestamptz default now(),
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_person uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  v_person:=atlas.current_person_id_v1();

  if not exists(
    select 1 from ledger.bookings b
    where b.id=p_booking_id and b.ledger_id=p_ledger_id
  ) then
    raise exception 'Booking is outside this Ledger.' using errcode='42501';
  end if;

  return ledger.transition_booking_state_service_v1(
    p_booking_id,p_new_state,v_person,p_occurred_at,p_payload,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'responsibilityRelationId',v_relation
    ),
    p_idempotency_key
  );
end;
$$;

create or replace function atlas.establish_ledger_resource_claim_self_api_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_resource_id uuid,
  p_claim_kind text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_booking_id uuid default null,
  p_claim_state text default 'tentative',
  p_quantity numeric default null,
  p_quantity_unit text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_person uuid;
  v_relation uuid;
begin
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'resource_claim.write');
  v_person:=atlas.current_person_id_v1();

  return ledger.establish_occurrence_resource_claim_service_v1(
    p_ledger_id,p_occurrence_id,p_resource_id,p_claim_kind,p_starts_at,p_ends_at,
    p_booking_id,p_claim_state,p_quantity,p_quantity_unit,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'responsibilityRelationId',v_relation
    ),
    p_idempotency_key,
    false
  );
end;
$$;

revoke execute on function atlas.upsert_ledger_resource_self_api_v1(uuid,uuid,text,text,text,text,boolean,text,numeric,text,text,jsonb)
  from public,anon;
revoke execute on function atlas.establish_ledger_booking_self_api_v1(uuid,uuid,text,uuid,text,text,text,jsonb,jsonb,text)
  from public,anon;
revoke execute on function atlas.transition_ledger_booking_self_api_v1(uuid,uuid,text,timestamptz,jsonb,jsonb,text)
  from public,anon;
revoke execute on function atlas.establish_ledger_resource_claim_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text,numeric,text,jsonb,jsonb,text)
  from public,anon;

grant execute on function atlas.upsert_ledger_resource_self_api_v1(uuid,uuid,text,text,text,text,boolean,text,numeric,text,text,jsonb)
  to authenticated;
grant execute on function atlas.establish_ledger_booking_self_api_v1(uuid,uuid,text,uuid,text,text,text,jsonb,jsonb,text)
  to authenticated;
grant execute on function atlas.transition_ledger_booking_self_api_v1(uuid,uuid,text,timestamptz,jsonb,jsonb,text)
  to authenticated;
grant execute on function atlas.establish_ledger_resource_claim_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text,numeric,text,jsonb,jsonb,text)
  to authenticated;

comment on function atlas.upsert_ledger_resource_self_api_v1(uuid,uuid,text,text,text,text,boolean,text,numeric,text,text,jsonb)
is 'Authenticated universal institutional-resource authoring. Resource owner is derived from the Ledger subject; no company-specific schema or legacy organization membership is used.';
comment on function atlas.establish_ledger_booking_self_api_v1(uuid,uuid,text,uuid,text,text,text,jsonb,jsonb,text)
is 'Authenticated universal booking establishment through Reality responsibility plus active Ledger Seat.';
comment on function atlas.establish_ledger_resource_claim_self_api_v1(uuid,uuid,uuid,text,timestamptz,timestamptz,uuid,text,numeric,text,jsonb,jsonb,text)
is 'Authenticated universal occurrence-to-resource occupancy claim. Conflict overrides are intentionally unavailable through the self API.';
