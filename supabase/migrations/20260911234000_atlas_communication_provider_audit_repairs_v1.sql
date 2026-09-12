begin;

-- 1. A social_reply transport operation must be a Facebook Messenger reply.
-- Public comments are a different transport semantic and must never fall through
-- to the Messenger /messages endpoint.
create or replace function atlas.guard_social_reply_transport_semantics_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_event atlas.communication_events%rowtype;
  v_kind text;
  v_thread_ref text;
begin
  if new.operation_kind<>'social_reply' then return new; end if;
  if new.reply_to_communication_event_id is null then
    raise exception 'Social reply requires a source communication event.' using errcode='23514';
  end if;
  select * into v_event from atlas.communication_events where id=new.reply_to_communication_event_id;
  if v_event.id is null or v_event.direction<>'incoming' then
    raise exception 'Social reply requires an incoming source communication event.' using errcode='23514';
  end if;
  v_kind:=lower(btrim(coalesce(v_event.canonical_event#>>'{source,kind}','')));
  v_thread_ref:=btrim(coalesce(v_event.canonical_event#>>'{source,threadRef}',''));
  if v_kind<>'facebook' or v_thread_ref not like 'messenger:%' then
    raise exception 'Facebook Messenger reply transport cannot be used for comments or other social event kinds.' using errcode='23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists communication_outbound_social_reply_semantics_guard on atlas.communication_outbound_operations;
create trigger communication_outbound_social_reply_semantics_guard
before insert or update of operation_kind,reply_to_communication_event_id on atlas.communication_outbound_operations
for each row
when (new.operation_kind='social_reply')
execute function atlas.guard_social_reply_transport_semantics_v1();

-- 2. Provider delivery identifiers are provider-account/source local unless a
-- provider contract proves otherwise. Universal transport must not assume global uniqueness.
alter table atlas.provider_webhook_deliveries
  drop constraint if exists provider_webhook_deliveries_provider_key_provider_delivery_key_key;
alter table atlas.provider_webhook_deliveries
  add constraint provider_webhook_deliveries_source_provider_delivery_key_key
  unique(connected_source_id,provider_key,provider_delivery_key);

create or replace function atlas.record_provider_webhook_delivery_service_v1(
  p_connected_source_id uuid,
  p_provider_key text,
  p_provider_delivery_key text,
  p_payload_sha256 text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_delivery atlas.provider_webhook_deliveries%rowtype;
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_key text:=btrim(coalesce(p_provider_delivery_key,''));
  v_hash text:=lower(btrim(coalesce(p_payload_sha256,'')));
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id;
  if v_source.id is null or v_source.authorization_state<>'connected' then
    raise exception 'Connected source is required.' using errcode='42501';
  end if;
  if v_provider='' or v_provider is distinct from v_source.provider_key or v_key='' or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Webhook source identity is invalid.' using errcode='22023';
  end if;

  select * into v_delivery
  from atlas.provider_webhook_deliveries
  where connected_source_id=v_source.id
    and provider_key=v_provider
    and provider_delivery_key=v_key
  for update;

  if found then
    if v_delivery.payload_sha256 is distinct from v_hash then
      update atlas.provider_webhook_deliveries
      set delivery_state='conflict',attempt_count=attempt_count+1,
          last_error='provider delivery key replayed for this source with a mismatched payload hash',updated_at=now()
      where id=v_delivery.id
      returning * into v_delivery;
      return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state','conflict','shouldProcess',false,'attemptCount',v_delivery.attempt_count);
    end if;
    update atlas.provider_webhook_deliveries
    set attempt_count=attempt_count+1,updated_at=now()
    where id=v_delivery.id
    returning * into v_delivery;
    return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state',v_delivery.delivery_state,'shouldProcess',v_delivery.delivery_state in ('received','failed'),'attemptCount',v_delivery.attempt_count);
  end if;

  insert into atlas.provider_webhook_deliveries(connected_source_id,provider_key,provider_delivery_key,payload_sha256,metadata)
  values(v_source.id,v_provider,v_key,v_hash,coalesce(p_metadata,'{}'::jsonb))
  returning * into v_delivery;
  return jsonb_build_object('contractVersion','provider_webhook_delivery_v1','deliveryId',v_delivery.id,'state','received','shouldProcess',true,'attemptCount',1);
end;
$function$;
revoke all on function atlas.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.record_provider_webhook_delivery_service_v1(uuid,text,text,text,jsonb) to service_role;

-- 3. Provider webhook echoes of an outbound event corroborate the already-admitted
-- event when provider event identity, direction, body and thread continuity agree.
-- A disagreement is not suppressed; it proceeds to ordinary custody conflict checks.
create or replace function atlas.ingest_provider_webhook_events_service_v1(
  p_provider_webhook_delivery_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_delivery atlas.provider_webhook_deliveries%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_receipt jsonb;
  v_manifest jsonb;
  v_event jsonb;
  v_existing atlas.communication_events%rowtype;
  v_events_to_ingest jsonb:='[]'::jsonb;
  v_corroborated jsonb:='[]'::jsonb;
  v_ref text;
  v_body text;
  v_thread text;
  v_existing_thread text;
begin
  select * into v_delivery from atlas.provider_webhook_deliveries where id=p_provider_webhook_delivery_id for update;
  if v_delivery.id is null then raise exception 'Provider webhook delivery not found.' using errcode='P0002'; end if;
  if v_delivery.delivery_state='processed' then
    return coalesce(v_delivery.ingest_receipt,'{}'::jsonb)||jsonb_build_object('webhookDeliveryId',v_delivery.id,'alreadyProcessed',true);
  end if;
  if v_delivery.delivery_state='conflict' then raise exception 'Conflicted provider delivery cannot be ingested.' using errcode='55000'; end if;
  select * into v_source from atlas.connected_sources where id=v_delivery.connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Webhook source is not connected.' using errcode='42501'; end if;
  if jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)<1 then raise exception 'Provider webhook events must be a non-empty array.' using errcode='22023'; end if;

  for v_event in select value from jsonb_array_elements(p_events) loop
    v_ref:=nullif(btrim(v_event#>>'{source,eventRef}'),'');
    v_body:=v_event->>'body';
    v_thread:=nullif(btrim(v_event#>>'{source,threadRef}'),'');
    v_existing:=null;
    if v_ref is not null then
      select * into v_existing
      from atlas.communication_events
      where connected_source_id=v_source.id and source_event_ref=v_ref;
    end if;
    if v_existing.id is not null
       and v_existing.direction='outgoing'
       and lower(coalesce(v_event->>'direction',''))='outgoing'
       and v_existing.body is not distinct from v_body then
      v_existing_thread:=nullif(btrim(v_existing.canonical_event#>>'{source,threadRef}'),'');
      if v_existing_thread is not distinct from v_thread then
        v_corroborated:=v_corroborated||jsonb_build_array(jsonb_build_object(
          'communicationEventId',v_existing.id,
          'sourceEventRef',v_ref,
          'corroboration','provider_webhook_echo'
        ));
        continue;
      end if;
    end if;
    v_events_to_ingest:=v_events_to_ingest||jsonb_build_array(v_event);
  end loop;

  v_manifest:=coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
    'providerWebhookDeliveryId',v_delivery.id,
    'corroboratedExistingEvents',v_corroborated
  );

  if jsonb_array_length(v_events_to_ingest)>0 then
    if v_source.custodian_user_id is not null then
      if to_regprocedure('atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)') is null then
        raise exception 'Principal provider communication ingest is unavailable.' using errcode='55000';
      end if;
      execute 'select atlas.ingest_principal_communication_events_service_v1($1,$2,$3)'
        into v_receipt using v_source.id,v_events_to_ingest,v_manifest;
    elsif v_source.custodian_organization_id is not null then
      v_receipt:=atlas.ingest_organization_communication_events_service_v3(v_source.id,v_events_to_ingest,v_manifest);
    else
      raise exception 'Connected source has no valid custody root.' using errcode='23514';
    end if;
  else
    v_receipt:=jsonb_build_object(
      'contractVersion','provider_webhook_corroboration_receipt_v1',
      'eventsIngested',0,
      'corroboratedExistingEvents',v_corroborated
    );
  end if;

  v_receipt:=coalesce(v_receipt,'{}'::jsonb)||jsonb_build_object('corroboratedExistingEvents',v_corroborated);
  update atlas.provider_webhook_deliveries
  set delivery_state='processed',processed_at=now(),last_error=null,ingest_receipt=v_receipt,updated_at=now()
  where id=v_delivery.id;
  return v_receipt||jsonb_build_object('contractVersion','provider_webhook_ingest_v1','webhookDeliveryId',v_delivery.id,'alreadyProcessed',false);
exception when others then
  update atlas.provider_webhook_deliveries
  set delivery_state=case when delivery_state='conflict' then 'conflict' else 'failed' end,
      last_error=left(sqlerrm,1000),updated_at=now()
  where id=p_provider_webhook_delivery_id;
  raise;
end;
$function$;
revoke all on function atlas.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.ingest_provider_webhook_events_service_v1(uuid,jsonb,jsonb) to service_role;

-- 4. Historical one-to-one Messenger continuity is participant based, matching
-- live webhooks. Provider conversation ids remain source payload evidence, not the
-- durable thread key used by Atlas admission.
create or replace function atlas.ingest_provider_history_events_service_v1(
  p_connected_source_id uuid,
  p_events jsonb,
  p_manifest jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_receipt jsonb;
  v_manifest jsonb:=coalesce(p_manifest,'{}'::jsonb)||jsonb_build_object(
    'captureKind','provider_history_sync','historicalBackfill',true,'responseWorkCreated',false
  );
  v_principal_ingest regprocedure;
  v_event jsonb;
  v_participant jsonb;
  v_events jsonb:='[]'::jsonb;
  v_external_address text;
  v_external_count integer;
  v_thread_ref text;
begin
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Connected source is required.' using errcode='42501'; end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then raise exception 'Connected source is not authorized for communication capture.' using errcode='42501'; end if;
  if jsonb_typeof(p_events)<>'array' or jsonb_array_length(p_events)<1 then raise exception 'Historical provider events must be a non-empty JSON array.' using errcode='22023'; end if;

  for v_event in select value from jsonb_array_elements(p_events) loop
    v_thread_ref:=coalesce(v_event#>>'{source,threadRef}','');
    if lower(coalesce(v_event#>>'{source,kind}',''))='facebook'
       and v_thread_ref like 'messenger-conversation:%' then
      v_external_address:=null;
      v_external_count:=0;
      for v_participant in select value from jsonb_array_elements(coalesce(v_event->'participants','[]'::jsonb)) loop
        if coalesce((v_participant->>'isSelf')::boolean,false)=false
           and nullif(btrim(v_participant->>'address'),'') is not null then
          if v_external_address is null then
            v_external_address:=btrim(v_participant->>'address');
            v_external_count:=1;
          elsif v_external_address is distinct from btrim(v_participant->>'address') then
            v_external_count:=v_external_count+1;
          end if;
        end if;
      end loop;
      if v_external_count<>1 or v_external_address is null then
        raise exception 'Historical Messenger event requires exactly one external participant for durable one-to-one continuity.' using errcode='23514';
      end if;
      v_event:=jsonb_set(v_event,'{source,threadRef}',to_jsonb('messenger:'||v_external_address),false);
    end if;
    v_events:=v_events||jsonb_build_array(v_event);
  end loop;

  if v_source.custodian_user_id is not null then
    v_principal_ingest:=to_regprocedure('atlas.ingest_principal_communication_events_service_v1(uuid,jsonb,jsonb)');
    if v_principal_ingest is null then raise exception 'Principal communication ingest seam is unavailable.' using errcode='55000'; end if;
    execute format('select %s($1,$2,$3)',v_principal_ingest) into v_receipt using v_source.id,v_events,v_manifest;
  elsif v_source.custodian_organization_id is not null then
    v_receipt:=atlas.ingest_organization_communication_events_service_v2(v_source.id,v_events,v_manifest);
  else
    raise exception 'Connected source has no valid custody root.' using errcode='23514';
  end if;

  return coalesce(v_receipt,'{}'::jsonb)||jsonb_build_object(
    'contractVersion','provider_history_ingest_receipt_v1',
    'historicalBackfill',true,
    'responseWorkCreated',false,
    'governingStateChanged',false,
    'durableThreadContinuity','participant_based_when_one_to_one'
  );
end;
$function$;
revoke all on function atlas.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.ingest_provider_history_events_service_v1(uuid,jsonb,jsonb) to service_role;

-- 5. Temporary provider-user authorization secrets have an actual lifecycle.
-- One OAuth discovery session selects one source. Once that selection connects,
-- the temporary user authorization is revoked and its Vault secret is deleted.
alter table atlas.provider_asset_authorizations alter column vault_secret_id drop not null;

create or replace function atlas.cleanup_provider_asset_authorization_secret_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,vault
as $function$
declare v_secret_id uuid:=old.vault_secret_id;
begin
  if v_secret_id is null then return new; end if;
  update atlas.provider_asset_authorizations
  set vault_secret_id=null,updated_at=now()
  where id=new.id and vault_secret_id=v_secret_id;
  delete from vault.secrets where id=v_secret_id;
  return new;
end;
$function$;

drop trigger if exists provider_asset_authorization_secret_cleanup on atlas.provider_asset_authorizations;
create trigger provider_asset_authorization_secret_cleanup
after update of authorization_state on atlas.provider_asset_authorizations
for each row
when (old.authorization_state is distinct from new.authorization_state and new.authorization_state in ('expired','revoked'))
execute function atlas.cleanup_provider_asset_authorization_secret_v1();

create or replace function atlas.complete_provider_asset_selection_service_v1(
  p_provider_asset_selection_id uuid,
  p_required_credential_kind text,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_selection atlas.provider_asset_selections%rowtype;
  v_source atlas.connected_sources%rowtype;
  v_kind text:=lower(btrim(coalesce(p_required_credential_kind,'')));
  v_authorization_id uuid;
begin
  select * into v_selection from atlas.provider_asset_selections where id=p_provider_asset_selection_id for update;
  if v_selection.id is null or v_selection.connected_source_id is null then raise exception 'Provider asset source has not been created.' using errcode='55000'; end if;
  v_authorization_id:=v_selection.provider_asset_authorization_id;
  if v_selection.selection_state='connected' then
    update atlas.provider_asset_authorizations set authorization_state='revoked',updated_at=now()
    where id=v_authorization_id and authorization_state='ready';
    return jsonb_build_object('contractVersion','provider_asset_selection_complete_v1','selectionId',v_selection.id,'connectedSourceId',v_selection.connected_source_id,'alreadyConnected',true);
  end if;
  if v_selection.selection_state<>'source_pending' then raise exception 'Provider asset selection is not ready for activation.' using errcode='55000'; end if;
  if v_kind='' or not exists(
    select 1 from atlas.connected_source_secret_refs r
    where r.connected_source_id=v_selection.connected_source_id and r.credential_kind=v_kind
  ) then raise exception 'Required provider credential is not in Vault custody.' using errcode='55000'; end if;

  update atlas.connected_sources
  set authorization_state='connected',revoked_at=null,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now()
  where id=v_selection.connected_source_id and authorization_state in ('pending','reauthorization_required','error')
  returning * into v_source;
  if v_source.id is null then raise exception 'Selected source cannot be activated from its current state.' using errcode='55000'; end if;

  update atlas.provider_asset_selections
  set selection_state='connected',last_error=null,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now()
  where id=v_selection.id;
  update atlas.provider_asset_authorizations
  set authorization_state='revoked',updated_at=now()
  where id=v_authorization_id and authorization_state='ready';

  return jsonb_build_object('contractVersion','provider_asset_selection_complete_v1','selectionId',v_selection.id,'connectedSourceId',v_source.id,'authorizationState',v_source.authorization_state,'alreadyConnected',false,'temporaryAuthorizationRetired',true);
end;
$function$;
revoke all on function atlas.complete_provider_asset_selection_service_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.complete_provider_asset_selection_service_v1(uuid,text,jsonb) to service_role;

create or replace function atlas.cleanup_expired_provider_asset_authorizations_service_v1()
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_count integer;
begin
  update atlas.provider_asset_authorizations
  set authorization_state='expired',updated_at=now()
  where authorization_state='ready' and expires_at<=now();
  get diagnostics v_count=row_count;
  return jsonb_build_object('contractVersion','provider_asset_authorization_cleanup_v1','expiredAuthorizations',v_count);
end;
$function$;
revoke all on function atlas.cleanup_expired_provider_asset_authorizations_service_v1() from public,anon,authenticated;
grant execute on function atlas.cleanup_expired_provider_asset_authorizations_service_v1() to service_role;

-- 6. setup_actor authority is explicitly temporary. Owners remain authoritative,
-- while setup actors may configure provider/endpoint infrastructure only during
-- an unfinished organization onboarding lifecycle.
create or replace function atlas.organization_connected_source_authorized_self_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null and (
    exists (
      select 1 from atlas.organization_memberships membership
      where membership.organization_id=p_organization_id
        and membership.user_id=auth.uid()
        and membership.active
        and membership.role='owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      join atlas.organizations organization on organization.id=actor.organization_id
      where actor.organization_id=p_organization_id
        and actor.human_user_id=auth.uid()
        and actor.actor_kind='setup_actor'
        and actor.active
        and actor.ended_at is null
        and organization.status='active'
        and organization.onboarding_state<>'ready'
        and organization.onboarding_completed_at is null
    )
  );
$function$;

create or replace function atlas.organization_communication_endpoint_setup_authorized_self_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select atlas.organization_connected_source_authorized_self_v1(p_organization_id);
$function$;
revoke all on function atlas.organization_communication_endpoint_setup_authorized_self_v1(uuid) from public,anon,authenticated;

create or replace function atlas.retire_organization_setup_actors_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if (new.onboarding_state='ready' or new.onboarding_completed_at is not null)
     and (old.onboarding_state is distinct from new.onboarding_state or old.onboarding_completed_at is distinct from new.onboarding_completed_at) then
    update atlas.organization_onboarding_actors
    set active=false,ended_at=coalesce(ended_at,now()),metadata=metadata||jsonb_build_object('retiredBy','organization_onboarding_completion'),
        started_at=started_at
    where organization_id=new.id and actor_kind='setup_actor' and active;
  end if;
  return new;
end;
$function$;

drop trigger if exists organization_setup_actor_retirement on atlas.organizations;
create trigger organization_setup_actor_retirement
after update of onboarding_state,onboarding_completed_at on atlas.organizations
for each row execute function atlas.retire_organization_setup_actors_v1();

create or replace function atlas.retire_binding_setup_actor_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if new.state='ended' or new.ended_at is not null then
    update atlas.organization_onboarding_actors
    set active=false,ended_at=coalesce(ended_at,now()),metadata=metadata||jsonb_build_object('retiredBy','ledger_entitlement_binding_end')
    where organization_id=new.organization_id
      and actor_kind='setup_actor'
      and active
      and metadata->>'ledgerEntitlementBindingId'=new.id::text;
  end if;
  return new;
end;
$function$;

drop trigger if exists ledger_binding_setup_actor_retirement on atlas.ledger_entitlement_bindings;
create trigger ledger_binding_setup_actor_retirement
after update of state,ended_at on atlas.ledger_entitlement_bindings
for each row
when (new.state='ended' or new.ended_at is not null)
execute function atlas.retire_binding_setup_actor_v1();

comment on function atlas.guard_social_reply_transport_semantics_v1() is
  'Fail-closed transport guard: social_reply currently means Facebook Messenger only; public comments require a distinct transport operation.';
comment on function atlas.cleanup_expired_provider_asset_authorizations_service_v1() is
  'Expires stale temporary provider asset authorizations. State transition triggers deletion of the temporary Vault token.';
comment on function atlas.organization_communication_endpoint_setup_authorized_self_v1(uuid) is
  'Infrastructure setup authority: active owner, or active unfinished-onboarding setup_actor. Setup authority ends when onboarding is ready/completed.';

commit;
