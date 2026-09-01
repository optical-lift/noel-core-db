-- Atlas Organization Connected Source Commands v1 — executable architecture source.
--
-- This is not a canonical migration. It closes the provider-neutral mutation seam
-- needed by Financial Reality before any Stripe/bank/accounting adapter is added.

create or replace function atlas.organization_connected_source_actor_authorized_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select auth.uid() is not null and (
    atlas.is_organization_owner(p_organization_id)
    or exists(
      select 1
      from atlas.organization_onboarding_actors a
      where a.organization_id=p_organization_id
        and a.human_user_id=auth.uid()
        and a.actor_kind='setup_actor'
        and a.active=true
        and a.ended_at is null
    )
  );
$function$;

revoke all on function atlas.organization_connected_source_actor_authorized_v1(uuid)
  from public,anon,authenticated,service_role;

create or replace function atlas.register_organization_connected_source_api_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text,
  p_account_hint text,
  p_authorization_state text,
  p_granted_scopes text[],
  p_capabilities jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_provider_key text:=lower(nullif(btrim(coalesce(p_provider_key,'')),''));
  v_provider_account_key text:=nullif(btrim(coalesce(p_provider_account_key,'')),'');
  v_state text:=lower(nullif(btrim(coalesce(p_authorization_state,'')),''));
  v_existing atlas.connected_sources%rowtype;
  v_row atlas.connected_sources%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated organization connector actor required.' using errcode='42501';
  end if;
  if p_organization_id is null
     or v_provider_key is null
     or v_provider_account_key is null then
    raise exception 'Organization, provider key, and stable provider account key are required.' using errcode='22023';
  end if;
  if not atlas.organization_connected_source_actor_authorized_v1(p_organization_id) then
    raise exception 'Organization owner or active setup actor authority required.' using errcode='42501';
  end if;
  if v_state not in ('pending','connected','reauthorization_required','error') then
    raise exception 'New source authorization state must be pending, connected, reauthorization_required, or error.' using errcode='22023';
  end if;
  if p_capabilities is null or jsonb_typeof(p_capabilities)<>'object' then
    raise exception 'Connected source capabilities must be a JSON object.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Connected source metadata must be a JSON object.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text||':'||v_provider_key||':'||v_provider_account_key,0
  ));

  select * into v_existing
  from atlas.connected_sources s
  where s.custodian_organization_id=p_organization_id
    and s.provider_key=v_provider_key
    and s.provider_account_key=v_provider_account_key
  limit 1;

  if v_existing.id is not null then
    -- Source identity is stable. Registration retry may refresh descriptive
    -- provider evidence, but it may not silently resurrect a revoked source.
    if v_existing.custodian_user_id is not null then
      raise exception 'Connected source custody shape is invalid.' using errcode='23514';
    end if;
    if v_existing.authorization_state='revoked' then
      raise exception 'Revoked source requires explicit reauthorization command.' using errcode='55000';
    end if;

    update atlas.connected_sources
    set display_label=coalesce(nullif(btrim(coalesce(p_display_label,'')),''),display_label),
        account_hint=coalesce(nullif(btrim(coalesce(p_account_hint,'')),''),account_hint),
        authorization_state=v_state,
        granted_scopes=coalesce(p_granted_scopes,'{}'::text[]),
        capabilities=p_capabilities,
        metadata=coalesce(metadata,'{}'::jsonb)||p_metadata,
        revoked_at=null
    where id=v_existing.id
    returning * into v_row;

    return jsonb_build_object(
      'contractVersion','register_organization_connected_source_api_v1',
      'state','reused','sourceId',v_row.id,'deduplicated',true,
      'authorizationState',v_row.authorization_state
    );
  end if;

  insert into atlas.connected_sources(
    custodian_user_id,custodian_organization_id,provider_key,provider_account_key,
    display_label,account_hint,authorization_state,granted_scopes,capabilities,metadata
  ) values (
    null,p_organization_id,v_provider_key,v_provider_account_key,
    nullif(btrim(coalesce(p_display_label,'')),''),
    nullif(btrim(coalesce(p_account_hint,'')),''),
    v_state,coalesce(p_granted_scopes,'{}'::text[]),p_capabilities,p_metadata
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','register_organization_connected_source_api_v1',
    'state','registered','sourceId',v_row.id,'deduplicated',false,
    'authorizationState',v_row.authorization_state
  );
end;
$function$;

revoke all on function atlas.register_organization_connected_source_api_v1(
  uuid,text,text,text,text,text,text[],jsonb,jsonb
) from public,anon;
grant execute on function atlas.register_organization_connected_source_api_v1(
  uuid,text,text,text,text,text,text[],jsonb,jsonb
) to authenticated,service_role;

create or replace function atlas.transition_organization_connected_source_api_v1(
  p_organization_id uuid,
  p_connected_source_id uuid,
  p_to_state text,
  p_granted_scopes text[],
  p_capabilities jsonb,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_to text:=lower(nullif(btrim(coalesce(p_to_state,'')),''));
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if auth.uid() is null then
    raise exception 'Authenticated organization connector actor required.' using errcode='42501';
  end if;
  if not atlas.organization_connected_source_actor_authorized_v1(p_organization_id) then
    raise exception 'Organization owner or active setup actor authority required.' using errcode='42501';
  end if;
  if p_connected_source_id is null or v_reason is null then
    raise exception 'Connected source and explicit transition reason are required.' using errcode='22023';
  end if;
  if v_to not in ('pending','connected','reauthorization_required','revoked','error') then
    raise exception 'Unsupported connected source authorization state.' using errcode='22023';
  end if;
  if p_capabilities is not null and jsonb_typeof(p_capabilities)<>'object' then
    raise exception 'Connected source capabilities must be a JSON object.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id=p_organization_id
    and s.custodian_user_id is null
  for update;

  if v_source.id is null then
    raise exception 'Organization-owned connected source not found.' using errcode='P0002';
  end if;

  if v_source.authorization_state='revoked' and v_to<>'connected' then
    raise exception 'Revoked source may only return through an explicit fresh connected authorization.' using errcode='23514';
  end if;

  update atlas.connected_sources
  set authorization_state=v_to,
      granted_scopes=case when p_granted_scopes is null then granted_scopes else p_granted_scopes end,
      capabilities=case when p_capabilities is null then capabilities else p_capabilities end,
      revoked_at=case when v_to='revoked' then now() else null end,
      metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
        'lastAuthorizationTransition',jsonb_build_object(
          'from',v_source.authorization_state,
          'to',v_to,
          'reason',v_reason,
          'actorUserId',auth.uid(),
          'at',now()
        )
      )
  where id=v_source.id
  returning * into v_source;

  return jsonb_build_object(
    'contractVersion','transition_organization_connected_source_api_v1',
    'state','transitioned','sourceId',v_source.id,
    'authorizationState',v_source.authorization_state
  );
end;
$function$;

revoke all on function atlas.transition_organization_connected_source_api_v1(
  uuid,uuid,text,text[],jsonb,text,jsonb
) from public,anon;
grant execute on function atlas.transition_organization_connected_source_api_v1(
  uuid,uuid,text,text[],jsonb,text,jsonb
) to authenticated,service_role;

-- Provider callbacks/synchronizers need a service-only path that cannot nominate
-- another organization. Source identity itself resolves organization custody.
create or replace function atlas.mark_connected_source_provider_state_core_v1(
  p_connected_source_id uuid,
  p_to_state text,
  p_reason text,
  p_last_sync_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_to text:=lower(nullif(btrim(coalesce(p_to_state,'')),''));
begin
  if p_connected_source_id is null
     or v_to not in ('connected','reauthorization_required','error')
     or nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Provider-state update requires source, supported state, and reason.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id is not null
    and s.custodian_user_id is null
  for update;
  if v_source.id is null then
    raise exception 'Organization-owned connected source not found.' using errcode='P0002';
  end if;
  if v_source.authorization_state='revoked' then
    raise exception 'Provider evidence cannot silently resurrect a revoked connected source.' using errcode='23514';
  end if;

  update atlas.connected_sources
  set authorization_state=v_to,
      last_sync_at=coalesce(p_last_sync_at,last_sync_at),
      metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
        'lastProviderStateEvidence',jsonb_build_object(
          'to',v_to,'reason',btrim(p_reason),'at',now()
        )
      )
  where id=v_source.id
  returning * into v_source;

  return jsonb_build_object(
    'contractVersion','mark_connected_source_provider_state_core_v1',
    'sourceId',v_source.id,'authorizationState',v_source.authorization_state,
    'lastSyncAt',v_source.last_sync_at
  );
end;
$function$;

revoke all on function atlas.mark_connected_source_provider_state_core_v1(
  uuid,text,text,timestamptz,jsonb
) from public,anon,authenticated;
grant execute on function atlas.mark_connected_source_provider_state_core_v1(
  uuid,text,text,timestamptz,jsonb
) to service_role;

-- Structural proof.
do $proof$
begin
  if has_function_privilege('anon','atlas.register_organization_connected_source_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)','EXECUTE') then
    raise exception 'Organization connected-source proof failed: anonymous mutation leaked.';
  end if;
  if not has_function_privilege('authenticated','atlas.register_organization_connected_source_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)','EXECUTE') then
    raise exception 'Organization connected-source proof failed: authenticated command unavailable.';
  end if;
  if has_function_privilege('authenticated','atlas.mark_connected_source_provider_state_core_v1(uuid,text,text,timestamptz,jsonb)','EXECUTE') then
    raise exception 'Organization connected-source proof failed: provider-state core leaked to authenticated.';
  end if;
end;
$proof$;
