-- Atlas Sealed Reality Phase C v1.
-- Cut Treasury carrier-backed execution over to the shared Sealed Reality kernel.
-- Treasury standing and durable operation grants remain domain-owned.
-- Treasury-specific warrant/receipt/event tables are retained for compatibility/history;
-- new carrier-backed request/completion flow no longer writes them.

-- Backfill active Treasury endpoints that already satisfy their creator bootstrap
-- delegation authority. Current production count is zero, but preserve a lawful
-- migration path for any endpoint created before this cutover.
insert into atlas.sealed_reality_handles(
  domain_key,
  domain_object_id,
  handle_state,
  registered_by_principal_id,
  metadata
)
select
  'sealed_treasury_endpoint',
  e.id,
  'active',
  e.created_by_principal_id,
  jsonb_build_object(
    'basis','sealed_treasury_phase_c_backfill',
    'sourceEndpointId',e.id
  )
from atlas.sealed_treasury_endpoints e
where e.endpoint_state='active'
  and exists(
    select 1
    from atlas.sealed_treasury_operation_grants g
    where g.endpoint_id=e.id
      and g.principal_id=e.created_by_principal_id
      and g.operation_key='delegate_operation'
      and g.grant_state='active'
      and g.valid_from<=now()
      and (g.valid_until is null or g.valid_until>now())
  )
on conflict (domain_key,domain_object_id) do nothing;

create or replace function atlas.create_sealed_treasury_endpoint_service_v1(
  p_ledger_id uuid,
  p_created_by_principal_id uuid,
  p_stable_key text,
  p_title text,
  p_carrier_key text,
  p_carrier_locator text,
  p_carrier_version text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_key text:=lower(btrim(coalesce(p_stable_key,'')));
  v_carrier text:=lower(btrim(coalesce(p_carrier_key,'')));
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_operation text;
  v_handle jsonb;
begin
  if not atlas.principal_has_ledger_authority_v1(
    p_created_by_principal_id,p_ledger_id
  ) then
    raise exception 'Principal lacks governing authority over Ledger.'
      using errcode='42501';
  end if;

  if not exists(
    select 1
    from atlas.ledgers l
    where l.id=p_ledger_id and l.status='active'
  ) then
    raise exception 'Active Ledger not found.' using errcode='P0002';
  end if;

  if v_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or v_carrier !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_title,''))=''
     or btrim(coalesce(p_carrier_locator,''))='' then
    raise exception 'Treasury endpoint key/title/carrier locator are invalid.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Treasury endpoint metadata must be a JSON object.'
      using errcode='22023';
  end if;

  insert into atlas.sealed_treasury_endpoints(
    ledger_id,stable_key,title,endpoint_kind,endpoint_state,
    carrier_key,carrier_locator,carrier_version,created_by_principal_id,metadata
  )
  values(
    p_ledger_id,v_key,btrim(p_title),'bank_destination','active',
    v_carrier,btrim(p_carrier_locator),nullif(btrim(p_carrier_version),''),
    p_created_by_principal_id,coalesce(p_metadata,'{}'::jsonb)
  )
  returning * into v_endpoint;

  foreach v_operation in array array[
    'observe_existence','delegate_operation','audit_operations'
  ]::text[]
  loop
    insert into atlas.sealed_treasury_operation_grants(
      endpoint_id,principal_id,operation_key,purpose_scope,grant_state,
      valid_from,granted_by_principal_id,grant_basis,metadata
    )
    values(
      v_endpoint.id,p_created_by_principal_id,v_operation,'{}'::text[],'active',
      now(),p_created_by_principal_id,
      jsonb_build_object('basis','endpoint_creator_bootstrap'),
      '{}'::jsonb
    );
  end loop;

  -- Treasury lifecycle remains domain-owned; preserve the existing domain event.
  perform atlas.write_sealed_treasury_event_internal_v1(
    v_endpoint.id,p_created_by_principal_id,'endpoint_create','completed',
    null,null,null,null,'sealed treasury endpoint established',
    jsonb_build_object('ledgerId',p_ledger_id,'stableKey',v_key)
  );

  -- Phase C: every new active Treasury endpoint receives its shared execution handle
  -- immediately after domain governance has been established.
  v_handle:=atlas.register_sealed_reality_handle_service_v1(
    'sealed_treasury_endpoint',
    v_endpoint.id,
    p_created_by_principal_id,
    jsonb_build_object(
      'basis','treasury_endpoint_creation',
      'sourceEndpointId',v_endpoint.id
    )
  );

  return jsonb_build_object(
    'contractVersion','sealed_treasury_endpoint_v1',
    'endpointId',v_endpoint.id,
    'ledgerId',v_endpoint.ledger_id,
    'stableKey',v_endpoint.stable_key,
    'title',v_endpoint.title,
    'endpointKind',v_endpoint.endpoint_kind,
    'endpointState',v_endpoint.endpoint_state,
    'carrierKey',v_endpoint.carrier_key,
    'sealedRealityHandleId',v_handle->>'handleId'
  );
end
$function$;

create or replace function atlas.request_sealed_treasury_operation_service_v1(
  p_endpoint_id uuid,
  p_principal_id uuid,
  p_operation_key text,
  p_purpose_key text,
  p_reason text,
  p_context jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_operation_key text:=lower(btrim(coalesce(p_operation_key,'')));
  v_purpose text:=lower(btrim(coalesce(p_purpose_key,'')));
  v_endpoint atlas.sealed_treasury_endpoints%rowtype;
  v_operation atlas.sealed_treasury_operations%rowtype;
  v_handle_id uuid;
  v_shared jsonb;
begin
  if v_purpose !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'
     or btrim(coalesce(p_reason,''))='' then
    raise exception 'Purpose and operation reason are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_context,'{}'::jsonb))<>'object' then
    raise exception 'Operation context must be a JSON object.'
      using errcode='22023';
  end if;

  select * into v_operation
  from atlas.sealed_treasury_operations o
  where o.operation_key=v_operation_key
    and o.operation_state='active';

  if v_operation.operation_key is null then
    raise exception 'Treasury operation is missing or inactive.'
      using errcode='P0002';
  end if;

  select * into v_endpoint
  from atlas.sealed_treasury_endpoints e
  where e.id=p_endpoint_id
    and e.endpoint_state='active';

  if v_endpoint.id is null then
    raise exception 'Active sealed treasury endpoint not found.'
      using errcode='P0002';
  end if;

  select h.id into v_handle_id
  from atlas.sealed_reality_handles h
  where h.domain_key='sealed_treasury_endpoint'
    and h.domain_object_id=p_endpoint_id
    and h.handle_state='active';

  if v_handle_id is null then
    raise exception 'Active Sealed Reality handle missing for Treasury endpoint.'
      using errcode='55000';
  end if;

  v_shared:=atlas.request_sealed_reality_operation_service_v1(
    v_handle_id,
    p_principal_id,
    v_operation_key,
    v_purpose,
    p_reason,
    coalesce(p_context,'{}'::jsonb)
  );

  if not coalesce((v_shared->>'authorized')::boolean,false) then
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_request_v1',
      'authorized',false,
      'operationKey',v_operation_key,
      'purposeKey',v_purpose,
      'reason',coalesce(v_shared->>'reason','operation_authority_required')
    );
  end if;

  if not coalesce((v_shared->>'requiresCarrier')::boolean,false) then
    if v_operation_key='observe_existence' then
      return jsonb_build_object(
        'contractVersion','sealed_treasury_operation_request_v1',
        'authorized',true,
        'requiresCarrier',false,
        'operationKey',v_operation_key,
        'purposeKey',v_purpose,
        'endpoint',jsonb_build_object(
          'endpointId',v_endpoint.id,
          'ledgerId',v_endpoint.ledger_id,
          'stableKey',v_endpoint.stable_key,
          'title',v_endpoint.title,
          'endpointKind',v_endpoint.endpoint_kind,
          'endpointState',v_endpoint.endpoint_state,
          'carrierKey',v_endpoint.carrier_key
        )
      );
    end if;

    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_request_v1',
      'authorized',true,
      'requiresCarrier',false,
      'operationKey',v_operation_key,
      'purposeKey',v_purpose
    );
  end if;

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_request_v1',
    'authorized',true,
    'requiresCarrier',true,
    'operationKey',v_operation_key,
    'purposeKey',v_purpose,
    'warrantId',v_shared->>'warrantId',
    'warrantToken',v_shared->>'warrantToken',
    'expiresAt',v_shared->>'expiresAt',
    'carrier',v_shared->'carrier',
    'resultPolicy',v_shared->>'resultPolicy',
    'revealsPlaintext',(v_shared->>'revealsPlaintext')::boolean
  );
end
$function$;

create or replace function atlas.complete_sealed_treasury_operation_service_v1(
  p_warrant_token text,
  p_outcome text,
  p_carrier_key text,
  p_safe_result jsonb default null,
  p_carrier_receipt_ref text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_shared jsonb;
begin
  v_shared:=atlas.complete_sealed_reality_operation_service_v1(
    p_warrant_token,
    p_outcome,
    p_carrier_key,
    p_safe_result,
    p_carrier_receipt_ref,
    coalesce(p_metadata,'{}'::jsonb)
  );

  -- Preserve the legacy Treasury contract's carrier-mismatch failure behavior.
  if not coalesce((v_shared->>'completed')::boolean,false)
     and v_shared->>'reason'='carrier_mismatch' then
    raise exception 'Carrier key does not match endpoint carrier.'
      using errcode='42501';
  end if;

  if not coalesce((v_shared->>'completed')::boolean,false)
     and v_shared->>'reason'='warrant_expired' then
    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_completion_v1',
      'completed',false,
      'reason','warrant_expired'
    );
  end if;

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_completion_v1',
    'completed',coalesce((v_shared->>'completed')::boolean,false),
    'receiptId',v_shared->>'receiptId',
    'warrantId',v_shared->>'warrantId',
    'operationKey',v_shared->>'operationKey',
    'purposeKey',v_shared->>'purposeKey',
    'resultPolicy',v_shared->>'resultPolicy',
    'safeResult',v_shared->'safeResult',
    'carrierReceiptRef',v_shared->>'carrierReceiptRef'
  );
end
$function$;

create or replace function atlas.read_sealed_treasury_operation_events_service_v1(
  p_endpoint_id uuid,
  p_principal_id uuid,
  p_limit integer default 100,
  p_reason text default 'treasury operation audit review'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_allowed boolean;
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
  v_handle_id uuid;
  v_events jsonb;
begin
  v_allowed:=atlas.principal_has_sealed_treasury_operation_v1(
    p_principal_id,p_endpoint_id,'audit_operations',null
  );

  select h.id into v_handle_id
  from atlas.sealed_reality_handles h
  where h.domain_key='sealed_treasury_endpoint'
    and h.domain_object_id=p_endpoint_id
    and h.handle_state='active';

  if not v_allowed then
    if v_handle_id is not null then
      perform atlas.write_sealed_reality_operation_event_internal_v1(
        v_handle_id,p_principal_id,'sealed_treasury_endpoint',
        'audit_read','denied','audit_operations',null,null,null,p_reason,
        jsonb_build_object('limit',v_limit)
      );
    else
      perform atlas.write_sealed_treasury_event_internal_v1(
        p_endpoint_id,p_principal_id,'audit_read','denied',
        'audit_operations',null,null,null,p_reason,
        jsonb_build_object('limit',v_limit)
      );
    end if;

    return jsonb_build_object(
      'contractVersion','sealed_treasury_operation_audit_v1',
      'authorized',false,
      'reason','audit_operations_required',
      'events','[]'::jsonb
    );
  end if;

  if v_handle_id is null then
    raise exception 'Active Sealed Reality handle missing for Treasury endpoint.'
      using errcode='55000';
  end if;

  perform atlas.write_sealed_reality_operation_event_internal_v1(
    v_handle_id,p_principal_id,'sealed_treasury_endpoint',
    'audit_read','allowed','audit_operations',null,null,null,p_reason,
    jsonb_build_object('limit',v_limit)
  );

  -- Preserve historical Treasury-domain events while projecting all Phase C
  -- shared execution events through the existing Treasury audit contract.
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'eventId',q.event_id,
      'principalId',q.principal_id,
      'eventKey',q.event_key,
      'outcome',q.outcome,
      'operationKey',q.operation_key,
      'purposeKey',q.purpose_key,
      'warrantId',q.warrant_id,
      'receiptId',q.receipt_id,
      'reason',q.reason_text,
      'context',q.context,
      'occurredAt',q.occurred_at
    )
    order by q.occurred_at desc,q.event_id
  ),'[]'::jsonb)
  into v_events
  from (
    select
      e.id as event_id,
      e.principal_id,
      e.event_key,
      e.outcome,
      e.operation_key,
      e.purpose_key,
      e.warrant_id,
      e.receipt_id,
      e.reason_text,
      e.context,
      e.occurred_at
    from atlas.sealed_reality_operation_events e
    where e.sealed_reality_handle_id=v_handle_id

    union all

    select
      e.id as event_id,
      e.principal_id,
      e.event_key,
      e.outcome,
      e.operation_key,
      e.purpose_key,
      e.warrant_id,
      e.receipt_id,
      e.reason_text,
      e.context,
      e.occurred_at
    from atlas.sealed_treasury_operation_events e
    where e.endpoint_id=p_endpoint_id

    order by occurred_at desc,event_id
    limit v_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','sealed_treasury_operation_audit_v1',
    'authorized',true,
    'endpointId',p_endpoint_id,
    'events',v_events
  );
end
$function$;

revoke all on function atlas.create_sealed_treasury_endpoint_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.create_sealed_treasury_endpoint_service_v1(
  uuid,uuid,text,text,text,text,text,jsonb
) to service_role;

revoke all on function atlas.request_sealed_treasury_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.request_sealed_treasury_operation_service_v1(
  uuid,uuid,text,text,text,jsonb
) to service_role;

revoke all on function atlas.complete_sealed_treasury_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.complete_sealed_treasury_operation_service_v1(
  text,text,text,jsonb,text,jsonb
) to service_role;

revoke all on function atlas.read_sealed_treasury_operation_events_service_v1(
  uuid,uuid,integer,text
) from public,anon,authenticated;
grant execute on function atlas.read_sealed_treasury_operation_events_service_v1(
  uuid,uuid,integer,text
) to service_role;
