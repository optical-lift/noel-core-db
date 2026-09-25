
create or replace function ledger.resource_conflict_domain_v1(p_resource_id uuid)
returns table(resource_id uuid)
language sql
stable
security definer
set search_path=''
as $$
  with recursive
  ancestors as (
    select r.id,r.parent_resource_id
    from reality.resources r
    where r.id=p_resource_id
    union all
    select p.id,p.parent_resource_id
    from reality.resources p
    join ancestors a on p.id=a.parent_resource_id
  ),
  descendants as (
    select r.id
    from reality.resources r
    where r.id=p_resource_id
    union all
    select c.id
    from reality.resources c
    join descendants d on c.parent_resource_id=d.id
  )
  select distinct id
  from (
    select id from ancestors
    union all
    select id from descendants
  ) q
  order by id;
$$;

create or replace function ledger.lock_resource_conflict_domains_v1(p_resource_ids uuid[])
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_resource_id uuid;
begin
  if p_resource_ids is null or cardinality(p_resource_ids)=0 then
    return;
  end if;

  if exists(
    select 1
    from unnest(p_resource_ids) x(resource_id)
    where not exists(select 1 from reality.resources r where r.id=x.resource_id)
  ) then
    raise exception 'One or more resources do not exist.' using errcode='P0002';
  end if;

  for v_resource_id in
    select distinct d.resource_id
    from unnest(p_resource_ids) x(resource_id)
    cross join lateral ledger.resource_conflict_domain_v1(x.resource_id) d
    order by d.resource_id
  loop
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('atlas_resource_conflict:'||v_resource_id::text,0)
    );
  end loop;
end;
$$;

create or replace function ledger.establish_occurrence_resource_claim_service_v1(
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
  p_idempotency_key text default null,
  p_allow_conflict boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_claim ledger.occurrence_resource_claims%rowtype;
  v_availability jsonb;
begin
  if p_claim_kind not in ('exclusive','shared','capacity') then
    raise exception 'Unknown claim kind: %',p_claim_kind using errcode='22023';
  end if;

  if p_claim_state not in ('tentative','confirmed','released','cancelled') then
    raise exception 'Unknown claim state: %',p_claim_state using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Claim metadata and provenance must be JSON objects.'
      using errcode='22023';
  end if;

  if p_claim_state in ('tentative','confirmed') then
    perform ledger.lock_resource_conflict_domains_v1(array[p_resource_id]);

    v_availability:=ledger.resource_claim_availability_v1(
      p_ledger_id,p_resource_id,p_starts_at,p_ends_at,
      p_claim_kind,p_quantity,null,p_occurrence_id
    );

    if coalesce((v_availability->>'available')::boolean,false)=false
       and not p_allow_conflict then
      raise exception 'Resource claim conflicts with current occupancy: %',v_availability
        using errcode='23P01';
    end if;
  else
    v_availability:='{}'::jsonb;
  end if;

  insert into ledger.occurrence_resource_claims(
    ledger_id,occurrence_id,booking_id,resource_id,
    claim_kind,claim_state,starts_at,ends_at,quantity,quantity_unit,
    metadata,provenance,idempotency_key
  ) values(
    p_ledger_id,p_occurrence_id,p_booking_id,p_resource_id,
    p_claim_kind,p_claim_state,p_starts_at,p_ends_at,p_quantity,
    nullif(btrim(p_quantity_unit),''),
    p_metadata||
      case when p_allow_conflict then jsonb_build_object('conflictOverride',true) else '{}'::jsonb end,
    p_provenance,
    nullif(btrim(p_idempotency_key),'')
  )
  on conflict(ledger_id,idempotency_key)
    where idempotency_key is not null
  do nothing
  returning * into v_claim;

  if v_claim.id is null then
    select * into v_claim
    from ledger.occurrence_resource_claims c
    where c.ledger_id=p_ledger_id
      and c.idempotency_key=nullif(btrim(p_idempotency_key),'')
    order by c.created_at desc,c.id
    limit 1;

    if v_claim.id is null
       or v_claim.occurrence_id<>p_occurrence_id
       or v_claim.resource_id<>p_resource_id
       or v_claim.claim_kind<>p_claim_kind then
      raise exception 'Resource claim idempotency key collides with a different claim.'
        using errcode='23505';
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','ledger_occurrence_resource_claim_v2',
    'claimId',v_claim.id,
    'ledgerId',v_claim.ledger_id,
    'occurrenceId',v_claim.occurrence_id,
    'bookingId',v_claim.booking_id,
    'resourceId',v_claim.resource_id,
    'claimKind',v_claim.claim_kind,
    'claimState',v_claim.claim_state,
    'startsAt',v_claim.starts_at,
    'endsAt',v_claim.ends_at,
    'conflictDomainLocked',p_claim_state in ('tentative','confirmed'),
    'availabilityAtEstablishment',v_availability
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
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_booking_json jsonb;
  v_booking_id uuid;
  v_resource_ids uuid[];
  v_claim jsonb;
  v_claim_result jsonb;
  v_claim_results jsonb:='[]'::jsonb;
  v_idx integer:=0;
  v_claim_idem text;
begin
  if p_claims is null or jsonb_typeof(p_claims)<>'array' or jsonb_array_length(p_claims)=0 then
    raise exception 'Booking bundle requires a non-empty JSON array of resource claims.'
      using errcode='22023';
  end if;

  if exists(
    select 1
    from jsonb_array_elements(p_claims) x
    where jsonb_typeof(x)<>'object'
       or nullif(x->>'resourceId','') is null
       or nullif(x->>'claimKind','') is null
       or nullif(x->>'startsAt','') is null
       or nullif(x->>'endsAt','') is null
  ) then
    raise exception 'Every booking bundle claim requires resourceId, claimKind, startsAt, and endsAt.'
      using errcode='22023';
  end if;

  select array_agg(distinct (x->>'resourceId')::uuid order by (x->>'resourceId')::uuid)
    into v_resource_ids
  from jsonb_array_elements(p_claims) x;

  perform ledger.lock_resource_conflict_domains_v1(v_resource_ids);

  v_booking_json:=ledger.establish_booking_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,p_created_by_seat_id,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb)||
      jsonb_build_object('atomicResourceBundle',true),
    p_idempotency_key
  );
  v_booking_id:=(v_booking_json->>'bookingId')::uuid;

  for v_claim in
    select value
    from jsonb_array_elements(p_claims)
  loop
    v_idx:=v_idx+1;
    v_claim_idem:=coalesce(
      nullif(v_claim->>'idempotencyKey',''),
      case
        when nullif(p_idempotency_key,'') is null then null
        else p_idempotency_key||':claim:'||v_idx::text
      end
    );

    v_claim_result:=ledger.establish_occurrence_resource_claim_service_v1(
      p_ledger_id,
      p_occurrence_id,
      (v_claim->>'resourceId')::uuid,
      v_claim->>'claimKind',
      (v_claim->>'startsAt')::timestamptz,
      (v_claim->>'endsAt')::timestamptz,
      v_booking_id,
      coalesce(nullif(v_claim->>'claimState',''),
        case when p_booking_state='confirmed' then 'confirmed' else 'tentative' end),
      case when nullif(v_claim->>'quantity','') is null then null else (v_claim->>'quantity')::numeric end,
      nullif(v_claim->>'quantityUnit',''),
      coalesce(v_claim->'metadata','{}'::jsonb),
      coalesce(v_claim->'provenance','{}'::jsonb)||
        jsonb_build_object('atomicBookingBundleId',v_booking_id),
      v_claim_idem,
      false
    );

    v_claim_results:=v_claim_results||jsonb_build_array(v_claim_result);
  end loop;

  return jsonb_build_object(
    'contractVersion','ledger_booking_bundle_v1',
    'booking',v_booking_json,
    'resourceClaims',v_claim_results,
    'atomic',true
  );
end;
$$;

create or replace function atlas.establish_ledger_booking_bundle_self_api_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_booking_kind text,
  p_claims jsonb,
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
  v_booking_relation uuid;
  v_claim_relation uuid;
begin
  v_booking_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'booking.write');
  v_claim_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'resource_claim.write');
  v_person:=atlas.current_person_id_v1();

  select s.id into v_seat
  from ledger.seats s
  where s.ledger_id=p_ledger_id
    and s.person_entity_id=v_person
    and s.seat_state='active'
  order by s.began_at desc,s.id
  limit 1;

  if v_seat is null then
    raise exception 'Active Ledger Seat required to establish a booking bundle.'
      using errcode='42501';
  end if;

  return ledger.establish_booking_bundle_service_v1(
    p_ledger_id,p_occurrence_id,p_booking_kind,p_claims,p_customer_entity_id,
    p_business_model_key,p_booking_label,p_booking_state,v_seat,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'bookingResponsibilityRelationId',v_booking_relation,
      'resourceClaimResponsibilityRelationId',v_claim_relation
    ),
    p_idempotency_key
  );
end;
$$;

revoke execute on function ledger.resource_conflict_domain_v1(uuid) from public,anon,authenticated;
revoke execute on function ledger.lock_resource_conflict_domains_v1(uuid[]) from public,anon,authenticated;
revoke execute on function ledger.establish_booking_bundle_service_v1(uuid,uuid,text,jsonb,uuid,text,text,text,uuid,jsonb,jsonb,text)
  from public,anon,authenticated;
revoke execute on function atlas.establish_ledger_booking_bundle_self_api_v1(uuid,uuid,text,jsonb,uuid,text,text,text,jsonb,jsonb,text)
  from public,anon;
grant execute on function atlas.establish_ledger_booking_bundle_self_api_v1(uuid,uuid,text,jsonb,uuid,text,text,text,jsonb,jsonb,text)
  to authenticated;

comment on function ledger.lock_resource_conflict_domains_v1(uuid[]) is
'Transaction-scoped serialization lock over each resource conflict domain (resource + ancestors + descendants), acquired in deterministic UUID order.';
comment on function ledger.establish_booking_bundle_service_v1(uuid,uuid,text,jsonb,uuid,text,text,text,uuid,jsonb,jsonb,text) is
'Atomically establishes one booking plus all requested resource claims after locking the union of their conflict domains.';
