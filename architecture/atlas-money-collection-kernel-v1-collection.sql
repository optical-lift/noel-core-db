-- Atlas Money Collection Kernel v1 — collection-attempt/provider-evidence tranche.
-- Reviewed migration-source SQL only; not a generated Supabase migration.

-- Structural custody: a money provider source must be organization-owned.
alter table atlas.connected_sources
  add constraint connected_sources_id_org_unique unique (id,custodian_organization_id);

alter table atlas.money_collection_attempts
  add constraint money_collection_attempts_id_org_source_unique
    unique (id,organization_id,connected_source_id),
  add constraint money_collection_attempts_source_org_fkey
    foreign key (connected_source_id,organization_id)
    references atlas.connected_sources(id,custodian_organization_id)
    on delete restrict;

alter table atlas.money_collection_attempt_obligations
  add column currency text not null check (currency ~ '^[A-Z]{3}$'),
  add constraint money_collection_attempt_obligations_attempt_fkey
    foreign key (collection_attempt_id,organization_id,currency)
    references atlas.money_collection_attempts(id,organization_id,currency)
    on delete restrict,
  add constraint money_collection_attempt_obligations_obligation_fkey
    foreign key (obligation_id,organization_id,currency)
    references atlas.money_obligations(id,organization_id,currency)
    on delete restrict;

alter table atlas.money_collection_provider_bindings
  add constraint money_collection_provider_bindings_attempt_fkey
    foreign key (collection_attempt_id,organization_id,connected_source_id)
    references atlas.money_collection_attempts(id,organization_id,connected_source_id)
    on delete restrict,
  add constraint money_collection_provider_bindings_source_org_fkey
    foreign key (connected_source_id,organization_id)
    references atlas.connected_sources(id,custodian_organization_id)
    on delete restrict;

alter table atlas.money_provider_events
  add constraint money_provider_events_id_org_source_unique
    unique (id,organization_id,connected_source_id),
  add constraint money_provider_events_source_org_fkey
    foreign key (connected_source_id,organization_id)
    references atlas.connected_sources(id,custodian_organization_id)
    on delete restrict,
  add constraint money_provider_events_attempt_fkey
    foreign key (collection_attempt_id,organization_id,connected_source_id)
    references atlas.money_collection_attempts(id,organization_id,connected_source_id)
    on delete restrict;

create or replace function atlas.create_money_collection_attempt_core_v1(
  p_organization_id uuid,
  p_connected_source_id uuid,
  p_requested_amount numeric,
  p_currency text,
  p_allocations jsonb,
  p_idempotency_key text,
  p_created_by_user_id uuid,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric(14,2) := round(p_requested_amount,2);
  v_currency text := upper(nullif(btrim(p_currency),''));
  v_key text := nullif(btrim(p_idempotency_key),'');
  v_existing atlas.money_collection_attempts%rowtype;
  v_attempt atlas.money_collection_attempts%rowtype;
  v_item jsonb;
  v_obligation_id uuid;
  v_requested numeric(14,2);
  v_total numeric(14,2) := 0;
  v_position record;
  v_count integer;
  v_distinct_count integer;
begin
  if p_organization_id is null or p_connected_source_id is null or v_key is null then
    raise exception 'Money collection attempt identity is incomplete.' using errcode='22023';
  end if;
  if v_amount is null or v_amount<=0 then
    raise exception 'Collection attempt amount must be positive.' using errcode='22023';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'Collection attempt currency must be a three-letter code.' using errcode='22023';
  end if;
  if p_allocations is null or jsonb_typeof(p_allocations)<>'array'
     or jsonb_array_length(p_allocations)<1 or jsonb_array_length(p_allocations)>50 then
    raise exception 'Collection attempt requires between 1 and 50 obligation applications.' using errcode='22023';
  end if;

  if not exists(
    select 1
    from atlas.connected_sources s
    where s.id=p_connected_source_id
      and s.custodian_organization_id=p_organization_id
      and s.custodian_user_id is null
      and s.authorization_state='connected'
      and s.revoked_at is null
      and s.capabilities @> '{"moneyCollection":true}'::jsonb
  ) then
    raise exception 'Connected source is not an active money-collection source for this organization.' using errcode='42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_organization_id::text||':money-attempt:'||v_key,0)
  );

  select * into v_existing
  from atlas.money_collection_attempts a
  where a.organization_id=p_organization_id and a.idempotency_key=v_key;

  if v_existing.id is not null then
    if v_existing.connected_source_id is distinct from p_connected_source_id
       or v_existing.requested_amount is distinct from v_amount
       or v_existing.currency is distinct from v_currency then
      raise exception 'Collection attempt retry conflicts with existing attempt.' using errcode='23505';
    end if;

    if jsonb_array_length(p_allocations) is distinct from (
      select count(*)::integer
      from atlas.money_collection_attempt_obligations x
      where x.collection_attempt_id=v_existing.id
    ) or exists (
      select 1
      from jsonb_array_elements(p_allocations) supplied
      left join atlas.money_collection_attempt_obligations x
        on x.collection_attempt_id=v_existing.id
       and x.obligation_id=(supplied->>'obligationId')::uuid
       and x.requested_amount=round((supplied->>'amount')::numeric,2)
       and x.currency=v_currency
      where x.id is null
    ) then
      raise exception 'Collection attempt retry carries different obligation applications.' using errcode='23505';
    end if;

    return v_existing.id;
  end if;

  select count(*),count(distinct value->>'obligationId')
  into v_count,v_distinct_count
  from jsonb_array_elements(p_allocations);
  if v_count<>v_distinct_count then
    raise exception 'An obligation may appear only once in a collection attempt.' using errcode='22023';
  end if;

  -- Lock all obligations in deterministic order before evaluating open amounts.
  for v_obligation_id in
    select o.id
    from atlas.money_obligations o
    where o.id in (
      select (value->>'obligationId')::uuid from jsonb_array_elements(p_allocations)
    )
    order by o.id
    for update
  loop
    null;
  end loop;

  if (
    select count(*)
    from atlas.money_obligations o
    where o.id in (select (value->>'obligationId')::uuid from jsonb_array_elements(p_allocations))
  )<>v_count then
    raise exception 'One or more money obligations were not found.' using errcode='P0002';
  end if;

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    begin
      v_obligation_id := (v_item->>'obligationId')::uuid;
      v_requested := round((v_item->>'amount')::numeric,2);
    exception when others then
      raise exception 'Each collection application requires a valid obligationId and amount.' using errcode='22023';
    end;

    if v_requested is null or v_requested<=0 then
      raise exception 'Collection application amount must be positive.' using errcode='22023';
    end if;

    if not exists(
      select 1 from atlas.money_obligations o
      where o.id=v_obligation_id
        and o.organization_id=p_organization_id
        and o.currency=v_currency
    ) then
      raise exception 'Collection application crosses organization or currency custody.' using errcode='42501';
    end if;

    select * into v_position
    from atlas.money_obligation_position_v1 p
    where p.obligation_id=v_obligation_id;
    if v_position.obligation_id is null or v_requested>v_position.open_amount then
      raise exception 'Collection application exceeds the obligation open amount.' using errcode='23514';
    end if;

    v_total := v_total + v_requested;
  end loop;

  if v_total is distinct from v_amount then
    raise exception 'Collection applications must sum exactly to the requested attempt amount.' using errcode='23514';
  end if;

  insert into atlas.money_collection_attempts(
    organization_id,connected_source_id,requested_amount,currency,idempotency_key,
    created_by_user_id,metadata
  ) values (
    p_organization_id,p_connected_source_id,v_amount,v_currency,v_key,
    p_created_by_user_id,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_attempt;

  for v_item in select value from jsonb_array_elements(p_allocations)
  loop
    insert into atlas.money_collection_attempt_obligations(
      organization_id,collection_attempt_id,obligation_id,requested_amount,currency
    ) values (
      p_organization_id,v_attempt.id,(v_item->>'obligationId')::uuid,
      round((v_item->>'amount')::numeric,2),v_currency
    );
  end loop;

  return v_attempt.id;
end;
$$;

create or replace function atlas.bind_money_collection_provider_object_core_v1(
  p_collection_attempt_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text := lower(nullif(btrim(p_provider_object_kind),''));
  v_object_key text := nullif(btrim(p_provider_object_key),'');
  v_attempt atlas.money_collection_attempts%rowtype;
  v_existing atlas.money_collection_provider_bindings%rowtype;
begin
  if p_collection_attempt_id is null or v_kind is null or v_object_key is null then
    raise exception 'Provider binding identity is incomplete.' using errcode='22023';
  end if;

  select * into v_attempt
  from atlas.money_collection_attempts a
  where a.id=p_collection_attempt_id
  for update;
  if v_attempt.id is null then
    raise exception 'Collection attempt not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.money_collection_provider_bindings b
  where b.connected_source_id=v_attempt.connected_source_id
    and b.provider_object_kind=v_kind
    and b.provider_object_key=v_object_key;
  if v_existing.id is not null then
    if v_existing.collection_attempt_id is distinct from v_attempt.id
       or v_existing.organization_id is distinct from v_attempt.organization_id then
      raise exception 'Provider object is already bound to another Atlas collection attempt.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  select * into v_existing
  from atlas.money_collection_provider_bindings b
  where b.collection_attempt_id=v_attempt.id and b.provider_object_kind=v_kind;
  if v_existing.id is not null then
    if v_existing.provider_object_key is distinct from v_object_key then
      raise exception 'Collection attempt already has a different provider object of this kind.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.money_collection_provider_bindings(
    organization_id,collection_attempt_id,connected_source_id,
    provider_object_kind,provider_object_key,metadata
  ) values (
    v_attempt.organization_id,v_attempt.id,v_attempt.connected_source_id,
    v_kind,v_object_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

create or replace function atlas.admit_money_provider_event_core_v1(
  p_connected_source_id uuid,
  p_collection_attempt_id uuid,
  p_provider_event_key text,
  p_event_kind text,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_occurred_at timestamptz,
  p_payload_sha256 text,
  p_normalized_evidence jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_key text := nullif(btrim(p_provider_event_key),'');
  v_event_kind text := lower(nullif(btrim(p_event_kind),''));
  v_object_kind text := lower(nullif(btrim(p_provider_object_kind),''));
  v_object_key text := nullif(btrim(p_provider_object_key),'');
  v_hash text := lower(nullif(btrim(p_payload_sha256),''));
  v_source atlas.connected_sources%rowtype;
  v_attempt atlas.money_collection_attempts%rowtype;
  v_existing atlas.money_provider_events%rowtype;
  v_resolved_attempt_id uuid := p_collection_attempt_id;
begin
  if p_connected_source_id is null or v_event_key is null or v_event_kind is null
     or v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Provider event identity or payload digest is invalid.' using errcode='22023';
  end if;
  if (v_object_kind is null)<>(v_object_key is null) then
    raise exception 'Provider object kind and key must be supplied together.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id is not null
    and s.custodian_user_id is null
    and s.capabilities @> '{"moneyCollection":true}'::jsonb;
  if v_source.id is null then
    raise exception 'Provider event source is not an organization-owned money source.' using errcode='42501';
  end if;

  if v_resolved_attempt_id is null and v_object_kind is not null then
    select b.collection_attempt_id into v_resolved_attempt_id
    from atlas.money_collection_provider_bindings b
    where b.connected_source_id=p_connected_source_id
      and b.provider_object_kind=v_object_kind
      and b.provider_object_key=v_object_key;
  end if;
  if v_resolved_attempt_id is null then
    raise exception 'Provider event is not linked to a known Atlas collection attempt.' using errcode='P0002';
  end if;

  select * into v_attempt
  from atlas.money_collection_attempts a
  where a.id=v_resolved_attempt_id
    and a.organization_id=v_source.custodian_organization_id
    and a.connected_source_id=v_source.id;
  if v_attempt.id is null then
    raise exception 'Provider event crosses collection-attempt custody.' using errcode='42501';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_connected_source_id::text||':provider-event:'||v_event_key,0)
  );

  select * into v_existing
  from atlas.money_provider_events e
  where e.connected_source_id=p_connected_source_id and e.provider_event_key=v_event_key;
  if v_existing.id is not null then
    if v_existing.payload_sha256 is distinct from v_hash
       or v_existing.organization_id is distinct from v_attempt.organization_id
       or v_existing.collection_attempt_id is distinct from v_attempt.id
       or v_existing.event_kind is distinct from v_event_kind then
      raise exception 'Provider event replay conflicts with evidence already in custody.' using errcode='23505';
    end if;
    return v_existing.id;
  end if;

  insert into atlas.money_provider_events(
    organization_id,connected_source_id,collection_attempt_id,provider_event_key,event_kind,
    provider_object_kind,provider_object_key,occurred_at,payload_sha256,normalized_evidence,metadata
  ) values (
    v_attempt.organization_id,v_source.id,v_attempt.id,v_event_key,v_event_kind,
    v_object_kind,v_object_key,p_occurred_at,v_hash,
    coalesce(p_normalized_evidence,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) returning * into v_existing;

  return v_existing.id;
end;
$$;

revoke execute on function atlas.create_money_collection_attempt_core_v1(uuid,uuid,numeric,text,jsonb,text,uuid,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.bind_money_collection_provider_object_core_v1(uuid,text,text,jsonb)
  from public,anon,authenticated,service_role;
revoke execute on function atlas.admit_money_provider_event_core_v1(uuid,uuid,text,text,text,text,timestamptz,text,jsonb,jsonb)
  from public,anon,authenticated,service_role;

-- The internal money tables are not service-role application APIs either.
revoke all on atlas.money_obligations from service_role;
revoke all on atlas.money_obligation_void_events from service_role;
revoke all on atlas.money_collection_attempts from service_role;
revoke all on atlas.money_collection_attempt_obligations from service_role;
revoke all on atlas.money_collection_provider_bindings from service_role;
revoke all on atlas.money_provider_events from service_role;
revoke all on atlas.money_receipts from service_role;
revoke all on atlas.money_receipt_allocations from service_role;
revoke all on atlas.money_receipt_reversal_events from service_role;
revoke all on atlas.money_receipt_allocation_reversal_events from service_role;
