create or replace function atlas.submit_public_commitment_session_v1(
  p_access_token text,
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
  v_surface atlas.public_commitment_surfaces%rowtype;
  v_booking ledger.booking_offerings%rowtype;
  v_selection jsonb;
  v_eval jsonb;
  v_resources jsonb:='[]'::jsonb;
  v_key text;
  v_resource reality.resources%rowtype;
  v_request jsonb;
  v_request_id uuid;
  v_snapshot_id uuid;
  v_snapshot_key text;
  v_snapshot_hash text;
  v_line jsonb;
  v_idem text:=nullif(btrim(coalesce(p_idempotency_key,'')),'');
  v_label text;
  v_purpose text;
  v_business_model_key text;
begin
  if length(coalesce(p_access_token,''))<32 then raise exception 'Invalid access token.' using errcode='42501'; end if;
  v_hash:=encode(extensions.digest(p_access_token,'sha256'),'hex');
  select * into v_session from atlas.public_commitment_sessions s where s.public_token_sha256=v_hash for update;
  if v_session.id is null then raise exception 'Public commitment session not found.' using errcode='P0002'; end if;
  if v_session.session_state='materialized' then
    return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'idempotentReplay',true);
  end if;
  if v_session.session_state<>'draft' then raise exception 'Public commitment session is not submit-able.' using errcode='23514'; end if;
  if v_session.requester_entity_id is null then
    raise exception 'Canonical identity resolution is required before request materialization.' using errcode='23514';
  end if;
  if v_idem is not null and exists(select 1 from atlas.public_commitment_events e where e.session_id=v_session.id and e.idempotency_key=v_idem) then
    return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'idempotentReplay',true);
  end if;

  select * into v_surface from atlas.public_commitment_surfaces s where s.id=v_session.surface_id and s.surface_state='active';
  if v_surface.id is null or v_surface.adapter_kind<>'ledger_booking' then raise exception 'Active ledger-booking public surface required.' using errcode='23514'; end if;
  select * into v_booking from ledger.booking_offerings o where o.id=v_surface.booking_offering_id and o.offering_state='active';
  if v_booking.id is null then raise exception 'Active booking offering required.' using errcode='23514'; end if;

  v_selection:=v_session.current_payload->'bookingSelection';
  if v_selection is null then raise exception 'A booking selection must be evaluated before submission.' using errcode='23514'; end if;
  v_eval:=atlas.public_commitment_quote_for_selection_v1(v_surface.id,v_selection);
  if not coalesce((v_eval->>'submissionAllowed')::boolean,false) then
    update atlas.public_commitment_sessions
    set current_payload=jsonb_build_object('bookingSelection',v_selection,'selectionEvaluation',v_eval),updated_at=now()
    where id=v_session.id;
    raise exception 'Current selection is not available for standard public submission.' using errcode='23514';
  end if;

  v_snapshot_key:='public_commitment:'||v_session.id::text||':quote:v1';
  v_snapshot_hash:=encode(extensions.digest((v_eval->'quote')::text,'sha256'),'hex');
  insert into atlas.commercial_offer_snapshots(
    organization_id,organization_unit_id,snapshot_key,title,offer_state,valid_from,valid_until,
    snapshot_sha256,source_kind,source_ref,metadata
  ) values(
    v_surface.organization_id,v_surface.organization_unit_id,v_snapshot_key,
    coalesce(v_session.identity_snapshot->>'name','Customer')||' — '||v_surface.title||' quote',
    'complete',now(),null,v_snapshot_hash,'domain_snapshot',v_session.id::text,
    jsonb_build_object(
      'sourceDomain','public_commitment_surface','surfaceKey',v_surface.surface_key,'sessionId',v_session.id,
      'pricingPolicyKey',v_surface.adapter_config->>'pricingPolicyKey','selection',v_eval->'selection',
      'requiredBeforeConfirmation',v_eval->'quote'->'requiredBeforeConfirmation',
      'remainingBalance',v_eval->'quote'->'remainingBalance'
    )
  ) returning id into v_snapshot_id;

  for v_line in select value from jsonb_array_elements(v_eval->'quote'->'lines')
  loop
    insert into atlas.commercial_offer_snapshot_lines(
      offer_snapshot_id,line_key,commercial_offering_id,description,unit_price,currency,price_basis,terms,source_ref,metadata
    ) values(
      v_snapshot_id,v_line->>'lineKey',v_surface.commercial_offering_id,v_line->>'description',
      (v_line->>'lineTotal')::numeric,v_eval->'quote'->>'currency',v_line->>'priceBasis',
      jsonb_build_object('quantity',(v_line->>'quantity')::numeric,'componentUnitPrice',(v_line->>'unitPrice')::numeric),
      v_session.id::text,
      jsonb_build_object('publicCommitmentSessionId',v_session.id)
    );
  end loop;

  for v_key in select value from jsonb_array_elements_text(v_selection->'resourceKeys')
  loop
    select * into v_resource from reality.resources r
    where r.owner_entity_id=(select l.subject_entity_id from ledger.ledgers l where l.id=v_surface.ledger_id)
      and r.stable_key=v_key and r.resource_state='active' and r.reservable;
    if v_resource.id is null then raise exception 'Selected Resource is no longer available as a canonical Resource.' using errcode='23514'; end if;
    v_resources:=v_resources||jsonb_build_array(jsonb_build_object(
      'resourceId',v_resource.id,'claimKind','exclusive',
      'startsAt',v_selection->>'startsAt','endsAt',v_selection->>'endsAt','applyPolicyBuffers',true,
      'metadata',jsonb_build_object('sourceSurfaceKey',v_surface.surface_key,'publicCommitmentSessionId',v_session.id),
      'provenance',jsonb_build_object('sourceAuthority','direct_self_submission','publicCommitmentSessionId',v_session.id)
    ));
  end loop;

  v_label:=coalesce(v_session.identity_snapshot->>'name','Customer')||' — '||coalesce(nullif(v_selection->>'eventType',''),'private venue request');
  v_purpose:=coalesce(v_session.literal_request,
    'Public request for '||coalesce(nullif(v_selection->>'eventType',''),'private venue rental')||
    case when v_selection ? 'guestCount' then ' for approximately '||(v_selection->>'guestCount')||' guests' else '' end
  );
  v_business_model_key:=coalesce(v_surface.adapter_config->>'businessModelKey',v_surface.public_config->>'businessModelKey');

  v_request:=ledger.submit_booking_request_service_v1(
    v_surface.ledger_id,null,v_session.requester_entity_id,null,v_session.requester_entity_id,
    v_booking.booking_kind,v_business_model_key,v_label,v_purpose,v_resources,
    jsonb_build_object(
      'sourceType','public_commitment_surface','sourceDomain','venue','surfaceKey',v_surface.surface_key,
      'publicCommitmentSessionId',v_session.id,'quoteSnapshotId',v_snapshot_id,
      'eventType',v_selection->>'eventType','expectedGuestCount',case when nullif(v_selection->>'guestCount','') is null then null else (v_selection->>'guestCount')::integer end,
      'pricingPolicyKey',v_surface.adapter_config->>'pricingPolicyKey','truthState','public_request_submitted_not_booking'
    ),
    jsonb_build_object('sourceAuthority','direct_self_submission','publicCommitmentSessionId',v_session.id,'surfaceKey',v_surface.surface_key),
    coalesce(v_idem,'public-session:'||v_session.id::text)
  );
  v_request_id:=(v_request->>'requestId')::uuid;

  perform ledger.append_booking_request_event_v1(
    v_request_id,'public_surface.quote_frozen',v_session.requester_entity_id,null,
    jsonb_build_object('publicCommitmentSessionId',v_session.id,'offerSnapshotId',v_snapshot_id,'quote',v_eval->'quote'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),
    'public-session:'||v_session.id::text||':quote-frozen',now()
  );

  update atlas.public_commitment_sessions
  set session_state='materialized',domain_object_kind='ledger_booking_request',domain_object_id=v_request_id,
      quote_snapshot_id=v_snapshot_id,current_payload=jsonb_build_object('bookingSelection',v_selection,'selectionEvaluation',v_eval),
      materialized_at=now(),updated_at=now()
  where id=v_session.id;

  insert into atlas.public_commitment_events(session_id,event_kind,payload,provenance,idempotency_key)
  values(
    v_session.id,'session.materialized',
    jsonb_build_object('domainObjectKind','ledger_booking_request','bookingRequestId',v_request_id,'offerSnapshotId',v_snapshot_id,'quote',v_eval->'quote'),
    jsonb_build_object('sourceAuthority','direct_self_submission','surfaceKey',v_surface.surface_key),v_idem
  );

  return jsonb_build_object('session',atlas.public_commitment_session_v1(p_access_token),'bookingRequestId',v_request_id,'offerSnapshotId',v_snapshot_id,'idempotentReplay',false);
end;
$function$;

revoke all on function atlas.submit_public_commitment_session_v1(text,text) from public;