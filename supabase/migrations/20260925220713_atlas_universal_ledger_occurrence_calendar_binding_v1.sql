
create table ledger.occurrence_calendar_bindings (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references ledger.ledgers(id) on delete cascade,
  occurrence_id uuid not null references local_intel.occurrences(id) on delete restrict,
  binding_state text not null default 'active' check (binding_state in ('active','inactive')),
  role_keys text[] not null default '{}'::text[],
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(ledger_id,occurrence_id)
);
create index occurrence_calendar_bindings_occurrence_fk_idx on ledger.occurrence_calendar_bindings(occurrence_id);
create index occurrence_calendar_bindings_ledger_state_idx on ledger.occurrence_calendar_bindings(ledger_id,binding_state);
alter table ledger.occurrence_calendar_bindings enable row level security;
create trigger occurrence_calendar_bindings_set_updated_at
before update on ledger.occurrence_calendar_bindings
for each row execute function atlas.set_updated_at();

create or replace function ledger.bind_occurrence_to_calendar_service_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_binding ledger.occurrence_calendar_bindings%rowtype;
begin
  if not exists(select 1 from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active') then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;
  if not exists(select 1 from local_intel.occurrences o where o.id=p_occurrence_id) then
    raise exception 'Occurrence not found.' using errcode='P0002';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object'
     or p_provenance is null or jsonb_typeof(p_provenance)<>'object' then
    raise exception 'Calendar binding metadata and provenance must be JSON objects.'
      using errcode='22023';
  end if;

  insert into ledger.occurrence_calendar_bindings(
    ledger_id,occurrence_id,binding_state,role_keys,metadata,provenance
  ) values(
    p_ledger_id,p_occurrence_id,'active',coalesce(p_role_keys,'{}'::text[]),p_metadata,p_provenance
  )
  on conflict(ledger_id,occurrence_id) do update
  set binding_state='active',
      role_keys=(
        select coalesce(array_agg(distinct x order by x),'{}'::text[])
        from unnest(ledger.occurrence_calendar_bindings.role_keys||excluded.role_keys) x
      ),
      metadata=ledger.occurrence_calendar_bindings.metadata||excluded.metadata,
      provenance=ledger.occurrence_calendar_bindings.provenance||excluded.provenance,
      updated_at=now()
  returning * into v_binding;

  return jsonb_build_object(
    'contractVersion','ledger_occurrence_calendar_binding_v1',
    'bindingId',v_binding.id,
    'ledgerId',v_binding.ledger_id,
    'occurrenceId',v_binding.occurrence_id,
    'bindingState',v_binding.binding_state,
    'roleKeys',v_binding.role_keys
  );
end;
$$;

create or replace function ledger.sync_calendar_binding_from_booking_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.booking_state<>'cancelled' then
    perform ledger.bind_occurrence_to_calendar_service_v1(
      new.ledger_id,new.occurrence_id,array['booking']::text[],
      jsonb_build_object('derivedFromBookingId',new.id),
      jsonb_build_object('source','booking_auto_binding_v1')
    );
  end if;
  return new;
end;
$$;

create trigger bookings_calendar_binding
after insert or update of booking_state,occurrence_id on ledger.bookings
for each row execute function ledger.sync_calendar_binding_from_booking_v1();

create or replace function ledger.sync_calendar_binding_from_resource_claim_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.claim_state in ('tentative','confirmed') then
    perform ledger.bind_occurrence_to_calendar_service_v1(
      new.ledger_id,new.occurrence_id,array['resource_claim']::text[],
      jsonb_build_object('derivedFromResourceClaimId',new.id),
      jsonb_build_object('source','resource_claim_auto_binding_v1')
    );
  end if;
  return new;
end;
$$;

create trigger occurrence_resource_claims_calendar_binding
after insert or update of claim_state,occurrence_id on ledger.occurrence_resource_claims
for each row execute function ledger.sync_calendar_binding_from_resource_claim_v1();

create or replace function atlas.bind_occurrence_to_ledger_calendar_self_api_v1(
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_role_keys text[] default '{}'::text[],
  p_metadata jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb
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
  v_relation:=atlas.require_ledger_schedule_responsibility_v1(p_ledger_id,'calendar.write');
  v_person:=atlas.current_person_id_v1();

  return ledger.bind_occurrence_to_calendar_service_v1(
    p_ledger_id,p_occurrence_id,p_role_keys,p_metadata,
    coalesce(p_provenance,'{}'::jsonb)||jsonb_build_object(
      'performedByPersonEntityId',v_person,
      'responsibilityRelationId',v_relation
    )
  );
end;
$$;

create or replace function atlas.ledger_resource_calendar_service_v1(
  p_ledger_id uuid,
  p_window_start timestamptz,
  p_window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_result jsonb;
begin
  if p_window_start is null or p_window_end is null or p_window_end<=p_window_start then
    raise exception 'Calendar window must have window_start < window_end.'
      using errcode='22023';
  end if;
  if not exists(select 1 from ledger.ledgers l where l.id=p_ledger_id and l.ledger_state='active') then
    raise exception 'Active Ledger required.' using errcode='23514';
  end if;

  with calendar_occurrences as (
    select distinct o.id,o.title,o.occurrence_type,o.start_at,o.end_at,o.status,o.venue_name,o.city,o.state
    from local_intel.occurrences o
    where o.start_at<p_window_end
      and coalesce(o.end_at,o.start_at+interval '1 minute')>p_window_start
      and (
        exists(select 1 from ledger.occurrence_calendar_bindings cb where cb.ledger_id=p_ledger_id and cb.occurrence_id=o.id and cb.binding_state='active')
        or exists(select 1 from ledger.occurrence_resource_claims c where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed'))
        or exists(select 1 from ledger.bookings b where b.ledger_id=p_ledger_id and b.occurrence_id=o.id and b.booking_state<>'cancelled')
      )
  )
  select jsonb_build_object(
    'contractVersion','ledger_resource_calendar_v1',
    'ledgerId',p_ledger_id,
    'windowStart',p_window_start,
    'windowEnd',p_window_end,
    'items',coalesce(jsonb_agg(item order by item->>'startAt',item->>'title'),'[]'::jsonb)
  )
  into v_result
  from (
    select jsonb_build_object(
      'occurrenceId',o.id,
      'title',o.title,
      'occurrenceType',o.occurrence_type,
      'startAt',o.start_at,
      'endAt',o.end_at,
      'occurrenceState',o.status,
      'venueName',o.venue_name,
      'city',o.city,
      'state',o.state,
      'calendarBinding',(
        select jsonb_build_object(
          'bindingId',cb.id,
          'bindingState',cb.binding_state,
          'roleKeys',cb.role_keys,
          'metadata',cb.metadata
        )
        from ledger.occurrence_calendar_bindings cb
        where cb.ledger_id=p_ledger_id and cb.occurrence_id=o.id
        limit 1
      ),
      'bookings',coalesce((
        select jsonb_agg(jsonb_build_object(
          'bookingId',b.id,
          'bookingKind',b.booking_kind,
          'bookingState',b.booking_state,
          'bookingLabel',b.booking_label,
          'businessModelKey',b.business_model_key,
          'customerEntityId',b.customer_entity_id,
          'customerDisplayName',ce.display_name,
          'references',coalesce((
            select jsonb_agg(jsonb_build_object(
              'referenceKind',br.reference_kind,
              'systemKey',br.system_key,
              'referenceKey',br.reference_key,
              'metadata',br.metadata
            ) order by br.reference_kind,br.system_key,br.reference_key)
            from ledger.booking_references br
            where br.booking_id=b.id
          ),'[]'::jsonb),
          'commercialSnapshot',(
            select jsonb_build_object(
              'orderId',co.id,'orderKind',co.order_kind,'totalAmount',co.total_amount,'currency',co.currency,
              'paymentState',cp.observed_state,'paidAt',cp.paid_at
            )
            from ledger.booking_references obr
            join atlas.commercial_orders co
              on obr.system_key='atlas_commercial'
             and obr.reference_kind='commercial_order'
             and obr.reference_key=co.id::text
            left join lateral (
              select p.observed_state,p.paid_at
              from atlas.commercial_payments p
              where p.commercial_order_id=co.id
              order by p.paid_at desc nulls last,p.created_at desc
              limit 1
            ) cp on true
            where obr.booking_id=b.id
            limit 1
          )
        ) order by b.created_at,b.id)
        from ledger.bookings b
        left join reality.entities ce on ce.id=b.customer_entity_id
        where b.ledger_id=p_ledger_id and b.occurrence_id=o.id
      ),'[]'::jsonb),
      'resourceClaims',coalesce((
        select jsonb_agg(jsonb_build_object(
          'claimId',c.id,'resourceId',r.id,'resourceLabel',r.label,'resourceKind',r.resource_kind,
          'parentResourceId',r.parent_resource_id,'claimKind',c.claim_kind,'claimState',c.claim_state,
          'startsAt',c.starts_at,'endsAt',c.ends_at,'quantity',c.quantity,'quantityUnit',c.quantity_unit,
          'classificationState',coalesce(c.metadata->>'classificationState','classified')
        ) order by c.starts_at,r.label,c.id)
        from ledger.occurrence_resource_claims c
        join reality.resources r on r.id=c.resource_id
        where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
      ),'[]'::jsonb),
      'occupancyState',case
        when not exists(
          select 1 from ledger.occurrence_resource_claims c
          where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
        ) then 'unclassified'
        when exists(
          select 1
          from ledger.occurrence_resource_claims c
          cross join lateral (
            select ledger.resource_claim_availability_v1(
              p_ledger_id,c.resource_id,c.starts_at,c.ends_at,c.claim_kind,c.quantity,c.id,c.occurrence_id
            ) as availability
          ) a
          where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
            and coalesce((a.availability->>'available')::boolean,false)=false
        ) then 'conflict'
        else 'clear'
      end,
      'conflicts',coalesce((
        select jsonb_agg(jsonb_build_object('claimId',c.id,'resourceId',c.resource_id,'availability',a.availability))
        from ledger.occurrence_resource_claims c
        cross join lateral (
          select ledger.resource_claim_availability_v1(
            p_ledger_id,c.resource_id,c.starts_at,c.ends_at,c.claim_kind,c.quantity,c.id,c.occurrence_id
          ) as availability
        ) a
        where c.ledger_id=p_ledger_id and c.occurrence_id=o.id and c.claim_state in ('tentative','confirmed')
          and coalesce((a.availability->>'available')::boolean,false)=false
      ),'[]'::jsonb)
    ) as item
    from calendar_occurrences o
  ) q;

  return coalesce(v_result,jsonb_build_object(
    'contractVersion','ledger_resource_calendar_v1',
    'ledgerId',p_ledger_id,
    'windowStart',p_window_start,
    'windowEnd',p_window_end,
    'items','[]'::jsonb
  ));
end;
$$;

revoke all on ledger.occurrence_calendar_bindings from public,anon,authenticated;
revoke execute on function ledger.bind_occurrence_to_calendar_service_v1(uuid,uuid,text[],jsonb,jsonb)
  from public,anon,authenticated;
revoke execute on function atlas.bind_occurrence_to_ledger_calendar_self_api_v1(uuid,uuid,text[],jsonb,jsonb)
  from public,anon;
grant execute on function atlas.bind_occurrence_to_ledger_calendar_self_api_v1(uuid,uuid,text[],jsonb,jsonb)
  to authenticated;

comment on table ledger.occurrence_calendar_bindings is
'Ledger-native calendar membership for canonical occurrences. Calendar membership does not require a booking or a resolved resource claim.';
