create or replace function atlas.resolve_connected_source_external_relationship_service_v1(
  p_connected_source_id uuid,
  p_organization_unit_id uuid default null,
  p_display_name text default null,
  p_subject_kind text default 'unknown',
  p_identifiers jsonb default '[]'::jsonb,
  p_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_identifier jsonb;
  v_provider_key text;
  v_type text;
  v_value text;
  v_normalized text;
  v_candidates uuid[];
  v_subject_id uuid;
  v_relationship_id uuid;
  v_match_state text := 'created_unresolved';
  v_stable_key text;
begin
  select * into v_source from atlas.connected_sources where id = p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state <> 'connected' then
    raise exception 'A connected organization source is required.' using errcode='55000';
  end if;
  if jsonb_typeof(coalesce(p_identifiers, '[]'::jsonb)) <> 'array' then
    raise exception 'Identifiers must be an array.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_basis, '{}'::jsonb)) <> 'object' then
    raise exception 'Relationship basis must be an object.' using errcode='22023';
  end if;
  if p_organization_unit_id is not null and not exists (
    select 1 from atlas.organization_units ou
    where ou.organization_id = v_source.custodian_organization_id and ou.id = p_organization_unit_id
  ) then
    raise exception 'Organization unit is outside connected source organization.' using errcode='23514';
  end if;

  select array_agg(distinct i.subject_id)
  into v_candidates
  from atlas.identity_subject_external_identifiers i
  join jsonb_array_elements(coalesce(p_identifiers, '[]'::jsonb)) x on true
  where i.organization_id = v_source.custodian_organization_id
    and i.is_current
    and i.identifier_type = nullif(btrim(x->>'type'), '')
    and i.identifier_normalized = coalesce(nullif(btrim(x->>'normalized'), ''), lower(btrim(x->>'value')))
    and coalesce(i.provider_key, '') = coalesce(nullif(btrim(x->>'providerKey'), ''), '');

  if coalesce(array_length(v_candidates, 1), 0) = 1 then
    v_subject_id := v_candidates[1];
    v_match_state := 'matched_exact_identifier';
  else
    insert into atlas.identity_subjects(organization_id, state, creation_basis)
    values (
      v_source.custodian_organization_id,
      'active',
      jsonb_build_object(
        'source', 'connected_source_commercial_interpretation',
        'connectedSourceId', v_source.id,
        'matchState', case when coalesce(array_length(v_candidates, 1), 0) > 1 then 'ambiguous_identifier_candidates' else 'no_identifier_match' end,
        'candidateSubjectIds', coalesce(to_jsonb(v_candidates), '[]'::jsonb)
      ) || coalesce(p_basis, '{}'::jsonb)
    ) returning id into v_subject_id;

    insert into atlas.identity_subject_projections(
      subject_id, organization_id, subject_kind, display_name, aliases, contact_points,
      unresolved_identity, confidence, projection_basis
    ) values (
      v_subject_id, v_source.custodian_organization_id,
      coalesce(nullif(btrim(p_subject_kind), ''), 'unknown'), nullif(btrim(p_display_name), ''),
      '[]'::jsonb, '[]'::jsonb, true, null,
      jsonb_build_object('source', 'connected_source_commercial_interpretation', 'connectedSourceId', v_source.id)
    );

    if coalesce(array_length(v_candidates, 1), 0) > 1 then
      v_match_state := 'created_ambiguous';
    end if;
  end if;

  select r.id into v_relationship_id
  from atlas.external_relationships r
  where r.organization_id = v_source.custodian_organization_id
    and r.subject_id = v_subject_id
    and r.relationship_state in ('active','prospective','unknown')
    and ((p_organization_unit_id is null and r.organization_unit_id is null) or r.organization_unit_id = p_organization_unit_id)
  order by case r.relationship_state when 'active' then 0 when 'prospective' then 1 else 2 end, r.created_at
  limit 1;

  if v_relationship_id is null then
    v_stable_key := 'connected-source:' || v_source.id::text || ':subject:' || v_subject_id::text;
    insert into atlas.external_relationships(
      organization_id, organization_unit_id, subject_id, stable_key, relationship_state, metadata
    ) values (
      v_source.custodian_organization_id, p_organization_unit_id, v_subject_id, v_stable_key, 'active',
      jsonb_build_object('source', 'connected_source_commercial_interpretation', 'connectedSourceId', v_source.id) || coalesce(p_basis, '{}'::jsonb)
    ) returning id into v_relationship_id;
  end if;

  insert into atlas.external_relationship_roles(external_relationship_id, role_key, role_state, basis)
  values (v_relationship_id, 'customer', 'active', jsonb_build_object('source', 'connected_source_commercial_interpretation', 'connectedSourceId', v_source.id))
  on conflict (external_relationship_id, role_key) do nothing;

  for v_identifier in select value from jsonb_array_elements(coalesce(p_identifiers, '[]'::jsonb))
  loop
    v_provider_key := nullif(btrim(v_identifier->>'providerKey'), '');
    v_type := nullif(btrim(v_identifier->>'type'), '');
    v_value := nullif(btrim(v_identifier->>'value'), '');
    v_normalized := coalesce(nullif(btrim(v_identifier->>'normalized'), ''), lower(v_value));
    if v_type is not null and v_value is not null and v_normalized is not null then
      insert into atlas.identity_subject_external_identifiers(
        organization_id, subject_id, provider_key, identifier_type, identifier_value,
        identifier_normalized, is_current, priority, metadata
      ) values (
        v_source.custodian_organization_id, v_subject_id, v_provider_key, v_type, v_value,
        v_normalized, true, 5,
        jsonb_build_object('source', 'connected_source_commercial_interpretation', 'connectedSourceId', v_source.id)
      ) on conflict do nothing;
    end if;
  end loop;

  if nullif(btrim(p_display_name), '') is not null then
    update atlas.identity_subject_projections
    set display_name = coalesce(display_name, nullif(btrim(p_display_name), '')),
        projection_basis = projection_basis || jsonb_build_object('connectedSourceId', v_source.id)
    where subject_id = v_subject_id;
  end if;

  return jsonb_build_object(
    'organizationId', v_source.custodian_organization_id,
    'subjectId', v_subject_id,
    'externalRelationshipId', v_relationship_id,
    'matchState', v_match_state
  );
end;
$function$;

create or replace function atlas.record_connected_source_commercial_order_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_organization_unit_id uuid default null,
  p_customer_relationship_id uuid default null,
  p_customer_subject_id uuid default null,
  p_order_kind text default 'sale',
  p_order_date date default current_date,
  p_channel text default null,
  p_subtotal_amount numeric default 0,
  p_tax_amount numeric default 0,
  p_tip_amount numeric default 0,
  p_total_amount numeric default 0,
  p_currency text default 'USD',
  p_idempotency_key text default null,
  p_note text default null,
  p_lines jsonb default '[]'::jsonb,
  p_metadata jsonb default '{}'::jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_observation_id uuid;
  v_order_id uuid;
  v_created boolean := false;
  v_line jsonb;
  v_line_id uuid;
  v_offering_id uuid;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state <> 'connected' then
    raise exception 'A connected organization source is required.' using errcode='55000';
  end if;
  select o.id into v_observation_id
  from atlas.connected_source_observations o
  where o.connected_source_id=v_source.id
    and o.provider_object_kind=btrim(p_provider_object_kind)
    and o.provider_object_key=btrim(p_provider_object_key)
  order by o.observed_at desc, o.created_at desc limit 1;
  if v_observation_id is null then raise exception 'Commercial interpretation requires recorded source evidence.' using errcode='P0002'; end if;
  if jsonb_typeof(coalesce(p_lines,'[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb)) <> 'object' or jsonb_typeof(coalesce(p_interpretation_basis,'{}'::jsonb)) <> 'object' then
    raise exception 'Lines must be an array and metadata/basis must be objects.' using errcode='22023';
  end if;

  if nullif(btrim(p_idempotency_key),'') is not null then
    select id into v_order_id from atlas.commercial_orders
    where organization_id=v_source.custodian_organization_id and idempotency_key=btrim(p_idempotency_key);
  end if;
  if v_order_id is null then
    insert into atlas.commercial_orders(
      organization_id,organization_unit_id,customer_relationship_id,customer_subject_id,order_kind,order_date,channel,
      subtotal_amount,tax_amount,tip_amount,total_amount,currency,idempotency_key,note,metadata
    ) values (
      v_source.custodian_organization_id,p_organization_unit_id,p_customer_relationship_id,p_customer_subject_id,
      coalesce(nullif(btrim(p_order_kind),''),'sale'),coalesce(p_order_date,current_date),nullif(btrim(p_channel),''),
      coalesce(p_subtotal_amount,0),coalesce(p_tax_amount,0),coalesce(p_tip_amount,0),coalesce(p_total_amount,0),upper(coalesce(nullif(btrim(p_currency),''),'USD')),
      nullif(btrim(p_idempotency_key),''),nullif(btrim(p_note),''),coalesce(p_metadata,'{}'::jsonb)
    ) returning id into v_order_id;
    v_created := true;

    for v_line in select value from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb))
    loop
      begin v_offering_id := nullif(btrim(v_line->>'offeringId'),'')::uuid; exception when invalid_text_representation then v_offering_id := null; end;
      insert into atlas.commercial_order_lines(
        commercial_order_id,offering_id,description,quantity,unit,unit_price,line_total,metadata
      ) values (
        v_order_id,v_offering_id,coalesce(nullif(btrim(v_line->>'description'),''),'Unclassified item'),
        coalesce(nullif(v_line->>'quantity','')::numeric,1),coalesce(nullif(btrim(v_line->>'unit'),''),'item'),
        coalesce(nullif(v_line->>'unitPrice','')::numeric,0),coalesce(nullif(v_line->>'lineTotal','')::numeric,0),coalesce(v_line->'metadata','{}'::jsonb)
      ) returning id into v_line_id;
      insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
      values (v_observation_id,'commercial_order_line',v_line_id,'provider_commercial_interpretation',coalesce(p_interpretation_basis,'{}'::jsonb))
      on conflict do nothing;
    end loop;
  end if;

  insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
  values (v_observation_id,'commercial_order',v_order_id,'provider_commercial_interpretation',coalesce(p_interpretation_basis,'{}'::jsonb))
  on conflict do nothing;

  if p_customer_relationship_id is not null then
    insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
    values (v_observation_id,'external_relationship',p_customer_relationship_id,'provider_identity_resolution',coalesce(p_interpretation_basis,'{}'::jsonb))
    on conflict do nothing;
  end if;

  return jsonb_build_object('commercialOrderId',v_order_id,'created',v_created,'observationId',v_observation_id);
end;
$function$;

create or replace function atlas.record_connected_source_commercial_payment_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_organization_unit_id uuid default null,
  p_commercial_order_id uuid default null,
  p_payer_relationship_id uuid default null,
  p_payer_subject_id uuid default null,
  p_provider_key text default null,
  p_provider_payment_key text default null,
  p_amount numeric default 0,
  p_currency text default 'USD',
  p_observed_state text default 'unknown',
  p_paid_at timestamptz default null,
  p_success_amount_delta numeric default null,
  p_success_event_key text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_observation_id uuid;
  v_payment_id uuid;
  v_event_id uuid;
  v_created boolean := false;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state <> 'connected' then
    raise exception 'A connected organization source is required.' using errcode='55000';
  end if;
  select o.id into v_observation_id from atlas.connected_source_observations o
  where o.connected_source_id=v_source.id and o.provider_object_kind=btrim(p_provider_object_kind) and o.provider_object_key=btrim(p_provider_object_key)
  order by o.observed_at desc,o.created_at desc limit 1;
  if v_observation_id is null then raise exception 'Commercial interpretation requires recorded source evidence.' using errcode='P0002'; end if;

  if nullif(btrim(p_provider_key),'') is not null and nullif(btrim(p_provider_payment_key),'') is not null then
    select id into v_payment_id from atlas.commercial_payments
    where organization_id=v_source.custodian_organization_id and provider_key=btrim(p_provider_key) and provider_payment_key=btrim(p_provider_payment_key);
  end if;
  if v_payment_id is null then
    insert into atlas.commercial_payments(
      organization_id,organization_unit_id,commercial_order_id,payer_relationship_id,payer_subject_id,provider_key,provider_payment_key,
      amount,currency,observed_state,paid_at,metadata
    ) values (
      v_source.custodian_organization_id,p_organization_unit_id,p_commercial_order_id,p_payer_relationship_id,p_payer_subject_id,
      nullif(btrim(p_provider_key),''),nullif(btrim(p_provider_payment_key),''),coalesce(p_amount,0),upper(coalesce(nullif(btrim(p_currency),''),'USD')),
      coalesce(nullif(btrim(p_observed_state),''),'unknown'),p_paid_at,coalesce(p_metadata,'{}'::jsonb)
    ) returning id into v_payment_id;
    v_created := true;
  end if;

  insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
  values (v_observation_id,'commercial_payment',v_payment_id,'provider_payment_interpretation',coalesce(p_interpretation_basis,'{}'::jsonb))
  on conflict do nothing;

  if p_success_amount_delta is not null and nullif(btrim(p_success_event_key),'') is not null then
    insert into atlas.commercial_payment_events(commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata)
    values (v_payment_id,'succeeded',p_success_amount_delta,upper(coalesce(nullif(btrim(p_currency),''),'USD')),coalesce(p_paid_at,now()),btrim(p_success_event_key),jsonb_build_object('source','connected_source_commercial_interpretation'))
    on conflict (commercial_payment_id,provider_event_key) where provider_event_key is not null do nothing
    returning id into v_event_id;
    if v_event_id is not null then
      insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
      values (v_observation_id,'commercial_payment_event',v_event_id,'provider_payment_event_interpretation',coalesce(p_interpretation_basis,'{}'::jsonb))
      on conflict do nothing;
    end if;
  end if;

  return jsonb_build_object('commercialPaymentId',v_payment_id,'created',v_created,'observationId',v_observation_id);
end;
$function$;

create or replace function atlas.record_connected_source_commercial_payment_event_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_provider_object_key text,
  p_provider_key text,
  p_provider_payment_key text,
  p_event_kind text,
  p_amount_delta numeric,
  p_currency text,
  p_occurred_at timestamptz,
  p_provider_event_key text,
  p_metadata jsonb default '{}'::jsonb,
  p_interpretation_basis jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_observation_id uuid;
  v_payment_id uuid;
  v_event_id uuid;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.custodian_organization_id is null or v_source.authorization_state <> 'connected' then
    raise exception 'A connected organization source is required.' using errcode='55000';
  end if;
  select o.id into v_observation_id from atlas.connected_source_observations o
  where o.connected_source_id=v_source.id and o.provider_object_kind=btrim(p_provider_object_kind) and o.provider_object_key=btrim(p_provider_object_key)
  order by o.observed_at desc,o.created_at desc limit 1;
  if v_observation_id is null then raise exception 'Commercial interpretation requires recorded source evidence.' using errcode='P0002'; end if;
  select id into v_payment_id from atlas.commercial_payments
  where organization_id=v_source.custodian_organization_id and provider_key=btrim(p_provider_key) and provider_payment_key=btrim(p_provider_payment_key);
  if v_payment_id is null then raise exception 'Referenced commercial payment does not exist.' using errcode='P0002'; end if;

  select id into v_event_id from atlas.commercial_payment_events
  where commercial_payment_id=v_payment_id and provider_event_key=btrim(p_provider_event_key);
  if v_event_id is null then
    insert into atlas.commercial_payment_events(commercial_payment_id,event_kind,amount_delta,currency,occurred_at,provider_event_key,metadata)
    values (v_payment_id,btrim(p_event_kind),p_amount_delta,upper(btrim(p_currency)),coalesce(p_occurred_at,now()),btrim(p_provider_event_key),coalesce(p_metadata,'{}'::jsonb))
    returning id into v_event_id;
  end if;

  insert into atlas.commercial_source_links(connected_source_observation_id,target_kind,target_id,interpretation_kind,interpretation_basis)
  values (v_observation_id,'commercial_payment_event',v_event_id,'provider_payment_event_interpretation',coalesce(p_interpretation_basis,'{}'::jsonb))
  on conflict do nothing;
  return jsonb_build_object('commercialPaymentId',v_payment_id,'commercialPaymentEventId',v_event_id,'observationId',v_observation_id);
end;
$function$;

revoke all on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_connected_source_commercial_order_service_v1(uuid,text,text,uuid,uuid,uuid,text,date,text,numeric,numeric,numeric,numeric,text,text,text,jsonb,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_connected_source_commercial_payment_service_v1(uuid,text,text,uuid,uuid,uuid,uuid,text,text,numeric,text,text,timestamptz,numeric,text,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.record_connected_source_commercial_payment_event_service_v1(uuid,text,text,text,text,text,numeric,text,timestamptz,text,jsonb,jsonb) from public, anon, authenticated;
grant execute on function atlas.resolve_connected_source_external_relationship_service_v1(uuid,uuid,text,text,jsonb,jsonb) to service_role;
grant execute on function atlas.record_connected_source_commercial_order_service_v1(uuid,text,text,uuid,uuid,uuid,text,date,text,numeric,numeric,numeric,numeric,text,text,text,jsonb,jsonb,jsonb) to service_role;
grant execute on function atlas.record_connected_source_commercial_payment_service_v1(uuid,text,text,uuid,uuid,uuid,uuid,text,text,numeric,text,text,timestamptz,numeric,text,jsonb,jsonb) to service_role;
grant execute on function atlas.record_connected_source_commercial_payment_event_service_v1(uuid,text,text,text,text,text,numeric,text,timestamptz,text,jsonb,jsonb) to service_role;