begin;

-- Atlas provider connection foundation used first by Stripe Apps OAuth.
-- Provider custody is generic; Stripe remains an application adapter.
-- Provider observations remain source evidence and never directly establish domain truth.

create or replace function atlas.organization_connected_source_authorized_self_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
  select auth.uid() is not null and (
    exists (
      select 1
      from atlas.organization_memberships membership
      where membership.organization_id = p_organization_id
        and membership.user_id = auth.uid()
        and membership.active
        and membership.role = 'owner'
    )
    or exists (
      select 1
      from atlas.organization_onboarding_actors actor
      where actor.organization_id = p_organization_id
        and actor.human_user_id = auth.uid()
        and actor.actor_kind = 'setup_actor'
        and actor.active
    )
  );
$function$;

create or replace function atlas.register_organization_connected_source_self_api_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_provider_account_key text,
  p_display_label text default null,
  p_account_hint text default null,
  p_authorization_state text default 'connected',
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_provider_key text := btrim(coalesce(p_provider_key,''));
  v_provider_account_key text := btrim(coalesce(p_provider_account_key,''));
  v_state text := btrim(coalesce(p_authorization_state,''));
  v_metadata jsonb := coalesce(p_metadata,'{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
begin
  if not atlas.organization_connected_source_authorized_self_v1(p_organization_id) then
    raise exception 'Organization provider connection authority required.' using errcode='42501';
  end if;
  if v_provider_key='' or v_provider_account_key='' then
    raise exception 'Provider identity is required.' using errcode='22023';
  end if;
  if v_state not in ('pending','connected') then
    raise exception 'A source may only be registered as pending or connected.' using errcode='22023';
  end if;
  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023';
  end if;

  select source.* into v_source
  from atlas.connected_sources source
  where source.custodian_organization_id=p_organization_id
    and source.provider_key=v_provider_key
    and source.provider_account_key=v_provider_account_key
  for update;

  if found then
    if v_source.authorization_state='revoked' then
      raise exception 'A revoked provider source cannot be silently rebound.' using errcode='55000';
    end if;
    update atlas.connected_sources source
    set display_label=coalesce(nullif(btrim(p_display_label),''),source.display_label),
        account_hint=coalesce(nullif(btrim(p_account_hint),''),source.account_hint),
        authorization_state=v_state,
        granted_scopes=coalesce(p_granted_scopes,source.granted_scopes),
        capabilities=coalesce(p_capabilities,source.capabilities),
        revoked_at=null,
        metadata=source.metadata || v_metadata,
        updated_at=now()
    where source.id=v_source.id
    returning source.* into v_source;
  else
    insert into atlas.connected_sources(
      custodian_user_id,custodian_organization_id,provider_key,provider_account_key,
      display_label,account_hint,authorization_state,granted_scopes,capabilities,metadata
    ) values (
      null,p_organization_id,v_provider_key,v_provider_account_key,
      nullif(btrim(p_display_label),''),nullif(btrim(p_account_hint),''),v_state,
      coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),v_metadata
    ) returning * into v_source;
  end if;

  return jsonb_build_object(
    'sourceId',v_source.id,
    'organizationId',v_source.custodian_organization_id,
    'providerKey',v_source.provider_key,
    'providerAccountKey',v_source.provider_account_key,
    'authorizationState',v_source.authorization_state,
    'grantedScopes',v_source.granted_scopes,
    'capabilities',v_source.capabilities
  );
end;
$function$;

create or replace function atlas.transition_organization_connected_source_authorization_self_api_v1(
  p_source_id uuid,
  p_to_state text,
  p_granted_scopes text[] default null,
  p_capabilities jsonb default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_to text := btrim(coalesce(p_to_state,''));
  v_metadata jsonb := coalesce(p_metadata,'{}'::jsonb);
  v_source atlas.connected_sources%rowtype;
  v_from text;
begin
  select source.* into v_source
  from atlas.connected_sources source
  where source.id=p_source_id and source.custodian_organization_id is not null
  for update;
  if not found then raise exception 'Organization connected source is unavailable.' using errcode='22023'; end if;
  if not atlas.organization_connected_source_authorized_self_v1(v_source.custodian_organization_id) then
    raise exception 'Organization provider connection authority required.' using errcode='42501';
  end if;
  if v_to not in ('pending','connected','reauthorization_required','revoked','error') then
    raise exception 'Unknown provider authorization state.' using errcode='22023';
  end if;
  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023';
  end if;

  v_from:=v_source.authorization_state;
  if v_from='revoked' and v_to<>'revoked' then
    raise exception 'Revoked sources cannot be silently reactivated.' using errcode='55000';
  end if;
  if v_from<>v_to and not (
    (v_from='pending' and v_to in ('connected','error','revoked')) or
    (v_from='connected' and v_to in ('reauthorization_required','error','revoked')) or
    (v_from='reauthorization_required' and v_to in ('connected','error','revoked')) or
    (v_from='error' and v_to in ('pending','connected','reauthorization_required','revoked'))
  ) then
    raise exception 'Illegal provider authorization transition from % to %.',v_from,v_to using errcode='55000';
  end if;

  update atlas.connected_sources source
  set authorization_state=v_to,
      granted_scopes=coalesce(p_granted_scopes,source.granted_scopes),
      capabilities=coalesce(p_capabilities,source.capabilities),
      revoked_at=case when v_to='revoked' then coalesce(source.revoked_at,now()) else null end,
      metadata=source.metadata || v_metadata,
      updated_at=now()
  where source.id=p_source_id
  returning source.* into v_source;

  return jsonb_build_object('sourceId',v_source.id,'fromState',v_from,'authorizationState',v_source.authorization_state);
end;
$function$;

create or replace function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(
  p_source_id uuid,
  p_synced_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_when timestamptz:=coalesce(p_synced_at,now());
  v_metadata jsonb:=coalesce(p_metadata,'{}'::jsonb);
begin
  select source.* into v_source from atlas.connected_sources source where source.id=p_source_id for update;
  if not found or v_source.custodian_organization_id is null then raise exception 'Organization connected source is unavailable.' using errcode='22023'; end if;
  if not atlas.organization_connected_source_authorized_self_v1(v_source.custodian_organization_id) then raise exception 'Organization provider connection authority required.' using errcode='42501'; end if;
  if v_source.authorization_state<>'connected' then raise exception 'Only a connected source may advance its sync checkpoint.' using errcode='55000'; end if;
  if v_when>now()+interval '5 minutes' then raise exception 'Sync checkpoint cannot be materially in the future.' using errcode='22023'; end if;
  if lower(v_metadata::text) ~ '"(access_token|refresh_token|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then raise exception 'Reusable provider credentials are not allowed in connected-source metadata.' using errcode='22023'; end if;

  update atlas.connected_sources source
  set last_sync_at=case when source.last_sync_at is null then v_when else greatest(source.last_sync_at,v_when) end,
      metadata=source.metadata || v_metadata,
      updated_at=now()
  where source.id=p_source_id
  returning source.* into v_source;
  return jsonb_build_object('sourceId',v_source.id,'authorizationState',v_source.authorization_state,'lastSyncAt',v_source.last_sync_at);
end;
$function$;

-- Verified implementation setup sponsor becomes the existing temporary setup_actor
-- once the practitioner establishes a canonical Organization scope. This grants no membership.
create or replace function atlas.materialize_implementation_setup_actor_from_binding_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $function$
declare
  v_human uuid;
begin
  if new.organization_id is null or new.implementation_case_id is null or new.ended_at is not null then return new; end if;
  select participant.human_user_id into v_human
  from atlas.implementation_case_participants participant
  where participant.implementation_case_id=new.implementation_case_id
    and participant.relationship_kind='setup_sponsor'
    and participant.active
    and participant.human_user_id is not null
  order by participant.started_at desc,participant.id
  limit 1;
  if v_human is null then return new; end if;

  insert into atlas.organization_onboarding_actors(
    organization_id,human_user_id,actor_kind,active,started_at,ended_at,metadata
  ) values (
    new.organization_id,v_human,'setup_actor',true,now(),null,
    jsonb_build_object('source','implementation_setup_sponsor_scope_binding','implementationCaseId',new.implementation_case_id,'ledgerEntitlementBindingId',new.id)
  )
  on conflict (organization_id,human_user_id) do update
  set active=true,ended_at=null,metadata=atlas.organization_onboarding_actors.metadata || excluded.metadata;
  return new;
end;
$function$;

drop trigger if exists materialize_implementation_setup_actor_from_binding_v1 on atlas.ledger_entitlement_bindings;
create trigger materialize_implementation_setup_actor_from_binding_v1
after insert or update of organization_id,ended_at on atlas.ledger_entitlement_bindings
for each row
when (new.organization_id is not null and new.implementation_case_id is not null and new.ended_at is null)
execute function atlas.materialize_implementation_setup_actor_from_binding_v1();

insert into atlas.organization_onboarding_actors(
  organization_id,human_user_id,actor_kind,active,started_at,ended_at,metadata
)
select binding.organization_id,sponsor.human_user_id,'setup_actor',true,now(),null,
  jsonb_build_object('source','implementation_setup_sponsor_scope_binding_backfill','implementationCaseId',binding.implementation_case_id,'ledgerEntitlementBindingId',binding.id)
from atlas.ledger_entitlement_bindings binding
join lateral (
  select participant.human_user_id
  from atlas.implementation_case_participants participant
  where participant.implementation_case_id=binding.implementation_case_id
    and participant.relationship_kind='setup_sponsor'
    and participant.active
    and participant.human_user_id is not null
  order by participant.started_at desc,participant.id
  limit 1
) sponsor on true
where binding.organization_id is not null and binding.ended_at is null
on conflict (organization_id,human_user_id) do update
set active=true,ended_at=null,metadata=atlas.organization_onboarding_actors.metadata || excluded.metadata;

-- Provider credentials: only references live in Atlas. Plaintext lives encrypted in Vault.
create table atlas.connected_source_secret_refs (
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  credential_kind text not null check (btrim(credential_kind)<>''),
  vault_secret_id uuid not null references vault.secrets(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(connected_source_id,credential_kind),
  unique(vault_secret_id)
);
alter table atlas.connected_source_secret_refs enable row level security;
revoke all on table atlas.connected_source_secret_refs from public,anon,authenticated;
grant select,insert,update,delete on table atlas.connected_source_secret_refs to service_role;

create or replace function atlas.store_connected_source_secret_service_v1(
  p_connected_source_id uuid,p_credential_kind text,p_secret text,p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, vault
as $function$
declare
  v_kind text:=btrim(coalesce(p_credential_kind,''));
  v_existing uuid;
  v_secret_id uuid;
begin
  if p_connected_source_id is null or v_kind='' or coalesce(p_secret,'')='' then raise exception 'Connected source, credential kind, and secret are required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.connected_sources source where source.id=p_connected_source_id) then raise exception 'Connected source is unavailable.' using errcode='22023'; end if;

  select ref.vault_secret_id into v_existing
  from atlas.connected_source_secret_refs ref
  where ref.connected_source_id=p_connected_source_id and ref.credential_kind=v_kind
  for update;

  if found then
    perform vault.update_secret(v_existing,p_secret,null,coalesce(nullif(btrim(p_description),''),'Atlas external provider credential'),null);
    v_secret_id:=v_existing;
    update atlas.connected_source_secret_refs set updated_at=now() where connected_source_id=p_connected_source_id and credential_kind=v_kind;
  else
    v_secret_id:=vault.create_secret(
      p_secret,
      format('atlas-source-%s-%s',replace(p_connected_source_id::text,'-',''),regexp_replace(v_kind,'[^a-zA-Z0-9_-]+','_','g')),
      coalesce(nullif(btrim(p_description),''),'Atlas external provider credential'),null
    );
    insert into atlas.connected_source_secret_refs(connected_source_id,credential_kind,vault_secret_id)
    values(p_connected_source_id,v_kind,v_secret_id);
  end if;
  return jsonb_build_object('stored',true,'connectedSourceId',p_connected_source_id,'credentialKind',v_kind);
end;
$function$;

create or replace function atlas.read_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text)
returns text
language sql
stable
security definer
set search_path = pg_catalog, atlas, vault
as $function$
  select secret.decrypted_secret
  from atlas.connected_source_secret_refs ref
  join vault.decrypted_secrets secret on secret.id=ref.vault_secret_id
  where ref.connected_source_id=p_connected_source_id and ref.credential_kind=btrim(coalesce(p_credential_kind,''));
$function$;

create or replace function atlas.delete_connected_source_secret_service_v1(p_connected_source_id uuid,p_credential_kind text)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, atlas, vault
as $function$
declare v_id uuid;
begin
  select ref.vault_secret_id into v_id from atlas.connected_source_secret_refs ref
  where ref.connected_source_id=p_connected_source_id and ref.credential_kind=btrim(coalesce(p_credential_kind,'')) for update;
  if not found then return false; end if;
  delete from atlas.connected_source_secret_refs where connected_source_id=p_connected_source_id and credential_kind=btrim(coalesce(p_credential_kind,''));
  delete from vault.secrets where id=v_id;
  return true;
end;
$function$;

-- Append-only provider record observations.
create table atlas.connected_source_observations (
  id uuid primary key default gen_random_uuid(),
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  provider_object_kind text not null check (btrim(provider_object_kind)<>''),
  provider_object_key text not null check (btrim(provider_object_key)<>''),
  provider_created_at timestamptz,
  observed_at timestamptz not null default now(),
  payload jsonb not null check (jsonb_typeof(payload)='object'),
  payload_sha256 text not null,
  provenance jsonb not null default '{}'::jsonb check (jsonb_typeof(provenance)='object'),
  created_at timestamptz not null default now(),
  unique(connected_source_id,provider_object_kind,provider_object_key,payload_sha256)
);
create index connected_source_observations_source_time_idx on atlas.connected_source_observations(connected_source_id,observed_at desc,id);
create index connected_source_observations_object_idx on atlas.connected_source_observations(connected_source_id,provider_object_kind,provider_object_key,observed_at desc);
alter table atlas.connected_source_observations enable row level security;
revoke all on table atlas.connected_source_observations from public,anon,authenticated;
grant select,insert on table atlas.connected_source_observations to service_role;

create or replace function atlas.record_connected_source_observation_batch_service_v1(
  p_connected_source_id uuid,
  p_provider_object_kind text,
  p_records jsonb,
  p_observed_at timestamptz default now(),
  p_provenance jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, extensions
as $function$
declare
  v_kind text:=btrim(coalesce(p_provider_object_kind,''));
  v_records jsonb:=coalesce(p_records,'[]'::jsonb);
  v_record jsonb;
  v_key text;
  v_payload jsonb;
  v_created timestamptz;
  v_hash text;
  v_inserted integer:=0;
  v_total integer:=0;
begin
  if p_connected_source_id is null or v_kind='' or jsonb_typeof(v_records)<>'array' then raise exception 'Connected source, provider object kind, and record array are required.' using errcode='22023'; end if;
  if jsonb_array_length(v_records)>500 then raise exception 'A provider observation batch may contain at most 500 records.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_provenance,'{}'::jsonb))<>'object' then raise exception 'Provider provenance must be an object.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.connected_sources source where source.id=p_connected_source_id and source.authorization_state='connected') then raise exception 'Provider observations require a connected source.' using errcode='55000'; end if;

  for v_record in select value from jsonb_array_elements(v_records)
  loop
    v_total:=v_total+1;
    v_key:=btrim(coalesce(v_record->>'key',''));
    v_payload:=coalesce(v_record->'payload','{}'::jsonb);
    if v_key='' or jsonb_typeof(v_payload)<>'object' then raise exception 'Each provider record requires a key and object payload.' using errcode='22023'; end if;
    v_created:=case when nullif(v_record->>'providerCreatedAt','') is null then null else (v_record->>'providerCreatedAt')::timestamptz end;
    v_hash:=encode(extensions.digest(convert_to(v_payload::text,'utf8'),'sha256'),'hex');
    insert into atlas.connected_source_observations(
      connected_source_id,provider_object_kind,provider_object_key,provider_created_at,observed_at,payload,payload_sha256,provenance
    ) values(
      p_connected_source_id,v_kind,v_key,v_created,coalesce(p_observed_at,now()),v_payload,v_hash,coalesce(p_provenance,'{}'::jsonb)
    ) on conflict(connected_source_id,provider_object_kind,provider_object_key,payload_sha256) do nothing;
    if found then v_inserted:=v_inserted+1; end if;
  end loop;
  return jsonb_build_object('connectedSourceId',p_connected_source_id,'providerObjectKind',v_kind,'recordCount',v_total,'insertedCount',v_inserted,'duplicateCount',v_total-v_inserted);
end;
$function$;

-- Privileges.
revoke all on function atlas.organization_connected_source_authorized_self_v1(uuid) from public,anon;
revoke all on function atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb) from public,anon;
revoke all on function atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb) from public,anon;
revoke all on function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb) from public,anon;
grant execute on function atlas.organization_connected_source_authorized_self_v1(uuid) to authenticated,service_role;
grant execute on function atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb) to authenticated,service_role;
grant execute on function atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb) to authenticated,service_role;
grant execute on function atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb) to authenticated,service_role;

revoke all on function atlas.materialize_implementation_setup_actor_from_binding_v1() from public,anon,authenticated,service_role;
revoke all on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) from public,anon,authenticated;
revoke all on function atlas.read_connected_source_secret_service_v1(uuid,text) from public,anon,authenticated;
revoke all on function atlas.delete_connected_source_secret_service_v1(uuid,text) from public,anon,authenticated;
revoke all on function atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb) from public,anon,authenticated;
grant execute on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) to service_role;
grant execute on function atlas.read_connected_source_secret_service_v1(uuid,text) to service_role;
grant execute on function atlas.delete_connected_source_secret_service_v1(uuid,text) to service_role;
grant execute on function atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb) to service_role;

-- RPC custody registry.
insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,anonymous_execute_expected
) values
('atlas.organization_connected_source_authorized_self_v1(uuid)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Check current-human authority before provider authorization.','truthBoundary','Read only.'),false),
('atlas.register_organization_connected_source_self_api_v1(uuid,text,text,text,text,text,text[],jsonb,jsonb)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Register organization-owned provider custody after provider identity is verified.','truthBoundary','Provider custody only; no domain truth.'),false),
('atlas.transition_organization_connected_source_authorization_self_api_v1(uuid,text,text[],jsonb,jsonb)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Govern provider authorization-state transitions.','truthBoundary','Provider custody only.'),false),
('atlas.update_organization_connected_source_sync_checkpoint_self_api_v1(uuid,timestamptz,jsonb)','app_endpoint','verified','active',true,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Advance provider acquisition checkpoint.','truthBoundary','Acquisition progress only.'),false),
('atlas.store_connected_source_secret_service_v1(uuid,text,text,text)','service_internal','verified','active',false,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Store or rotate encrypted provider credential in Vault.','truthBoundary','Credential transport only.'),false),
('atlas.read_connected_source_secret_service_v1(uuid,text)','service_internal','verified','active',false,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Read provider credential for server adapter.','truthBoundary','Credential transport only.'),false),
('atlas.delete_connected_source_secret_service_v1(uuid,text)','service_internal','verified','active',false,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Delete provider credential on deliberate disconnect.','truthBoundary','Credential custody only.'),false),
('atlas.record_connected_source_observation_batch_service_v1(uuid,text,jsonb,timestamptz,jsonb)','service_internal','verified','active',false,true,true,1,1,jsonb_build_object('source','atlas_stripe_connected_source_foundation_v1','purpose','Preserve bounded batches of provider observations.','truthBoundary','Source evidence only; never direct domain truth.'),false)
on conflict(signature) do update
set classification=excluded.classification,
    confidence=excluded.confidence,
    review_status=excluded.review_status,
    authenticated_execute_expected=excluded.authenticated_execute_expected,
    security_definer_expected=excluded.security_definer_expected,
    service_execute_expected=excluded.service_execute_expected,
    caller_count=excluded.caller_count,
    policy_reference_count=excluded.policy_reference_count,
    evidence=excluded.evidence,
    anonymous_execute_expected=excluded.anonymous_execute_expected,
    reviewed_at=now();

commit;
