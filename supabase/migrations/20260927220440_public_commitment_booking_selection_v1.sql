create or replace function atlas.public_commitment_quote_for_selection_v1(
  p_surface_id uuid,
  p_selection jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_duration_minutes numeric;
  v_guest_count integer;
  v_resource_keys text[];
  v_addon_keys text[];
  v_resource_ids uuid[];
  v_requested_count integer;
  v_resolved_count integer;
  v_policy jsonb;
  v_availability jsonb:='[]'::jsonb;
  v_all_available boolean:=true;
  v_rec record;
  v_av jsonb;
  v_reasons jsonb:='[]'::jsonb;
  v_lines jsonb:='[]'::jsonb;
  v_total numeric:=0;
  v_currency text:='USD';
  v_duration_cfg jsonb;
  v_primary_key text;
  v_base_minutes integer;
  v_increment_minutes integer;
  v_base_basis text;
  v_additional_basis text;
  v_base_price numeric;
  v_additional_price numeric;
  v_extra_increments integer:=0;
  v_basis text;
  v_price numeric;
  v_key text;
  v_mapping jsonb;
  v_commitment jsonb:='{}'::jsonb;
  v_threshold numeric;
  v_deposit_percent numeric;
  v_due_now numeric;
  v_balance numeric;
  v_custom boolean:=false;
  v_submission_allowed boolean:=false;
  v_public_max_minutes integer;
  v_guest_max integer;
  v_require_guest boolean:=false;
begin
  if p_selection is null or jsonb_typeof(p_selection)<>'object' then
    raise exception 'Selection must be a JSON object.' using errcode='22023';
  end if;
  select * into v_surface from atlas.public_commitment_surfaces s where s.id=p_surface_id and s.surface_state='active';
  if v_surface.id is null then raise exception 'Active public surface not found.' using errcode='P0002'; end if;
  if v_surface.adapter_kind<>'ledger_booking' then raise exception 'Surface adapter does not support booking selection.' using errcode='23514'; end if;
  select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id and o.offering_state='active';
  if v_booking.id is null then raise exception 'Active booking offering not found.' using errcode='P0002'; end if;

  begin
    v_start:=(p_selection->>'startsAt')::timestamptz;
    v_end:=(p_selection->>'endsAt')::timestamptz;
  exception when others then
    raise exception 'Selection requires valid startsAt and endsAt timestamps.' using errcode='22023';
  end;
  if v_start is null or v_end is null or v_end<=v_start then
    raise exception 'Selection requires startsAt < endsAt.' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_selection->'resourceKeys','null'::jsonb))<>'array' or jsonb_array_length(p_selection->'resourceKeys')=0 then
    raise exception 'Selection requires at least one resource key.' using errcode='22023';
  end if;
  if p_selection ? 'addOnKeys' and jsonb_typeof(p_selection->'addOnKeys')<>'array' then
    raise exception 'addOnKeys must be an array.' using errcode='22023';
  end if;

  select array_agg(value order by value),count(*) into v_resource_keys,v_requested_count
  from jsonb_array_elements_text(p_selection->'resourceKeys');
  if (select count(distinct x) from unnest(v_resource_keys) x)<>v_requested_count then
    raise exception 'Resource keys may not be duplicated.' using errcode='22023';
  end if;
  select array_agg(value order by value) into v_addon_keys
  from jsonb_array_elements_text(coalesce(p_selection->'addOnKeys','[]'::jsonb));
  v_addon_keys:=coalesce(v_addon_keys,'{}'::text[]);
  if (select count(distinct x) from unnest(v_addon_keys) x)<>cardinality(v_addon_keys) then
    raise exception 'Add-on keys may not be duplicated.' using errcode='22023';
  end if;

  if exists(
    select 1 from unnest(v_resource_keys) k
    where not exists(
      select 1 from jsonb_array_elements_text(coalesce(v_surface.adapter_config->'publicResourceKeys','[]'::jsonb)) a where a.value=k
    )
  ) then
    raise exception 'Selection includes a Resource that is not exposed by this public surface.' using errcode='23514';
  end if;

  select array_agg(r.id order by r.id),count(*) into v_resource_ids,v_resolved_count
  from reality.resources r
  where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
    and r.resource_state='active' and r.reservable and r.stable_key=any(v_resource_keys);
  if v_resolved_count<>v_requested_count then
    raise exception 'One or more selected Resources are unavailable as canonical reservable Resources.' using errcode='23514';
  end if;

  v_duration_minutes:=extract(epoch from (v_end-v_start))/60.0;
  v_guest_count:=case when nullif(p_selection->>'guestCount','') is null then null else (p_selection->>'guestCount')::integer end;
  if v_guest_count is not null and v_guest_count<=0 then raise exception 'guestCount must be positive.' using errcode='22023'; end if;

  v_policy:=ledger.evaluate_booking_policies_v1(v_surface.ledger_id,v_resource_ids,v_booking.booking_kind,v_start,v_end,false,now());

  for v_rec in
    select r.id,r.stable_key,r.label from reality.resources r where r.id=any(v_resource_ids) order by r.label,r.id
  loop
    v_av:=ledger.resource_claim_availability_v1(v_surface.ledger_id,v_rec.id,v_start,v_end,'exclusive',null,null,null);
    v_availability:=v_availability||jsonb_build_array(jsonb_build_object(
      'resourceId',v_rec.id,'resourceKey',v_rec.stable_key,'resourceLabel',v_rec.label,'availability',v_av
    ));
    if not coalesce((v_av->>'available')::boolean,false) then v_all_available:=false; end if;
  end loop;

  v_duration_cfg:=coalesce(v_surface.adapter_config->'durationPricing','{}'::jsonb);
  v_primary_key:=v_duration_cfg->>'resourceKey';
  v_base_minutes:=coalesce((v_duration_cfg->>'baseIncludedMinutes')::integer,0);
  v_increment_minutes:=coalesce((v_duration_cfg->>'incrementMinutes')::integer,0);
  v_base_basis:=v_duration_cfg->>'basePriceBasis';
  v_additional_basis:=v_duration_cfg->>'additionalPriceBasis';
  v_public_max_minutes:=case when v_surface.adapter_config ? 'selfServiceMaxMinutes' then (v_surface.adapter_config->>'selfServiceMaxMinutes')::integer else null end;
  v_guest_max:=case when v_surface.adapter_config ? 'selfServiceGuestCountMax' then (v_surface.adapter_config->>'selfServiceGuestCountMax')::integer else null end;
  v_require_guest:=coalesce((v_surface.adapter_config->>'requireGuestCount')::boolean,false);

  if v_require_guest and v_guest_count is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','guest_count_required_for_standard_quote'));
  end if;
  if v_primary_key is null or not (v_primary_key=any(v_resource_keys)) then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','primary_resource_required_for_standard_quote','resourceKey',v_primary_key));
  end if;
  if v_public_max_minutes is not null and v_duration_minutes>v_public_max_minutes then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_requires_custom_quote','maxStandardMinutes',v_public_max_minutes));
  end if;
  if v_guest_max is not null and v_guest_count is not null and v_guest_count>v_guest_max then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','guest_count_requires_custom_quote','maxStandardGuests',v_guest_max));
  end if;
  if v_base_minutes<=0 or v_increment_minutes<=0 then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_pricing_not_configured'));
  else
    if v_duration_minutes<v_base_minutes
       or v_duration_minutes<>floor(v_duration_minutes)
       or mod((v_duration_minutes-v_base_minutes)::integer,v_increment_minutes)<>0 then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','duration_not_standard_pricing_increment','baseMinutes',v_base_minutes,'incrementMinutes',v_increment_minutes));
    end if;
  end if;

  select p.unit_price,p.currency into v_base_price,v_currency
  from atlas.commercial_offering_prices p
  where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_base_basis
    and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
  order by p.effective_from desc,p.created_at desc limit 1;
  select p.unit_price into v_additional_price
  from atlas.commercial_offering_prices p
  where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_additional_basis
    and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
  order by p.effective_from desc,p.created_at desc limit 1;
  if v_base_price is null or v_additional_price is null then
    v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','basePriceBasis',v_base_basis,'additionalPriceBasis',v_additional_basis));
  else
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'lineKey','base_rental','description','Base venue rental','priceBasis',v_base_basis,'quantity',1,'unitPrice',v_base_price,'lineTotal',v_base_price
    ));
    v_total:=v_total+v_base_price;
    if v_base_minutes>0 and v_increment_minutes>0 and v_duration_minutes>=v_base_minutes
       and v_duration_minutes=floor(v_duration_minutes)
       and mod((v_duration_minutes-v_base_minutes)::integer,v_increment_minutes)=0 then
      v_extra_increments:=((v_duration_minutes-v_base_minutes)/v_increment_minutes)::integer;
      if v_extra_increments>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineKey','duration_extension','description','Additional rental time','priceBasis',v_additional_basis,
          'quantity',v_extra_increments,'unitPrice',v_additional_price,'lineTotal',v_extra_increments*v_additional_price
        ));
        v_total:=v_total+(v_extra_increments*v_additional_price);
      end if;
    end if;
  end if;

  v_mapping:=coalesce(v_surface.adapter_config->'resourcePriceBasis','{}'::jsonb);
  foreach v_key in array v_resource_keys loop
    if v_key<>v_primary_key and v_mapping ? v_key then
      v_basis:=v_mapping->>v_key;
      select p.unit_price into v_price
      from atlas.commercial_offering_prices p
      where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_basis
        and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
      order by p.effective_from desc,p.created_at desc limit 1;
      if v_price is null then
        v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','priceBasis',v_basis));
      else
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineKey','resource_'||v_key,'description','Resource add-on: '||v_key,'priceBasis',v_basis,'quantity',1,'unitPrice',v_price,'lineTotal',v_price
        ));
        v_total:=v_total+v_price;
      end if;
    end if;
  end loop;

  v_mapping:=coalesce(v_surface.adapter_config->'addOnPriceBasis','{}'::jsonb);
  foreach v_key in array v_addon_keys loop
    if not (v_mapping ? v_key) then
      raise exception 'Selection includes an add-on that is not exposed by this public surface.' using errcode='23514';
    end if;
    v_basis:=v_mapping->>v_key;
    select p.unit_price into v_price
    from atlas.commercial_offering_prices p
    where p.offering_id=v_surface.commercial_offering_id and p.price_basis=v_basis
      and p.effective_from<=current_date and (p.effective_until is null or p.effective_until>=current_date)
    order by p.effective_from desc,p.created_at desc limit 1;
    if v_price is null then
      v_reasons:=v_reasons||jsonb_build_array(jsonb_build_object('reasonCode','pricing_component_missing','priceBasis',v_basis));
    else
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
        'lineKey','addon_'||v_key,'description','Add-on: '||replace(v_key,'_',' '),'priceBasis',v_basis,'quantity',1,'unitPrice',v_price,'lineTotal',v_price
      ));
      v_total:=v_total+v_price;
    end if;
  end loop;

  v_custom:=jsonb_array_length(v_reasons)>0;
  select coalesce(p.config,'{}'::jsonb) into v_commitment
  from ledger.booking_policies p
  where p.ledger_id=v_surface.ledger_id and p.policy_state='active' and p.policy_kind='commitment'
    and (p.booking_kind is null or p.booking_kind=v_booking.booking_kind)
  order by p.priority desc,p.id limit 1;
  v_threshold:=case when v_commitment ? 'fullPaymentAtOrBelowAmount' then (v_commitment->>'fullPaymentAtOrBelowAmount')::numeric else null end;
  v_deposit_percent:=case when v_commitment ? 'depositPercentAboveThreshold' then (v_commitment->>'depositPercentAboveThreshold')::numeric else null end;

  if not v_custom then
    v_total:=round(v_total,2);
    if coalesce((v_commitment->>'paymentRequiredBeforeConfirmation')::boolean,false) then
      if v_threshold is not null and v_total<=v_threshold then
        v_due_now:=v_total;
      elsif v_deposit_percent is not null then
        v_due_now:=round(v_total*v_deposit_percent/100.0,2);
      end if;
    else
      v_due_now:=0;
    end if;
    v_balance:=case when v_due_now is null then null else round(v_total-v_due_now,2) end;
  else
    v_total:=null;
    v_due_now:=null;
    v_balance:=null;
  end if;

  v_submission_allowed:=not v_custom
    and coalesce((v_policy->>'allowed')::boolean,false)
    and v_all_available;

  return jsonb_build_object(
    'contractVersion','atlas_public_commitment_quote_v1',
    'surfaceId',v_surface.id,
    'selection',jsonb_build_object(
      'startsAt',v_start,'endsAt',v_end,'durationMinutes',v_duration_minutes,
      'guestCount',v_guest_count,'resourceKeys',to_jsonb(v_resource_keys),'addOnKeys',to_jsonb(v_addon_keys),
      'eventType',p_selection->>'eventType'
    ),
    'policyEvaluation',v_policy,
    'resourceAvailability',v_availability,
    'allResourcesAvailable',v_all_available,
    'customQuoteRequired',v_custom,
    'customQuoteReasons',v_reasons,
    'quote',jsonb_build_object(
      'currency',v_currency,'lines',v_lines,'totalAmount',v_total,
      'requiredBeforeConfirmation',v_due_now,'remainingBalance',v_balance,
      'remainingBalanceDueTimingState',v_commitment->>'remainingBalanceDueTimingState'
    ),
    'submissionAllowed',v_submission_allowed
  );
end;
$function$;

create or replace function atlas.set_public_commitment_selection_v1(
  p_access_token text,
  p_selection jsonb,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_hash text;
  v_session atlas.public_commitment_sessions%rowtype;
  v_eval jsonb;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash for update;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  if v_session.session_state<>'draft' then raise exception 'Only draft public commitment sessions may revise selection.' using errcode='23514'; end if;
  if v_idem is not null and exists(select 1 from atlas.public_commitment_events e where e.session_id=v_session.id and e.idempotency_key=v_idem) then
    return atlas.public_commitment_session_v1(p_access_token);
  end if;

  v_eval:=atlas.public_commitment_quote_for_selection_v1(v_session.surface_id,p_selection);
  update atlas.public_commitment_sessions
  set current_payload=jsonb_build_object('bookingSelection',p_selection,'selectionEvaluation',v_eval),updated_at=now()
  where id=v_session.id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session.id,'selection.evaluated',
    jsonb_build_object('selection',p_selection,'evaluation',v_eval),
    jsonb_build_object('sourceAuthority','direct_self_submission'),v_idem
  );
  return atlas.public_commitment_session_v1(p_access_token);
end;
$function$;

revoke all on function atlas.public_commitment_quote_for_selection_v1(uuid,jsonb) from public;
revoke all on function atlas.set_public_commitment_selection_v1(text,jsonb,text) from public;