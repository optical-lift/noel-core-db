begin;

create table atlas.provider_asset_authorizations (
  id uuid primary key default gen_random_uuid(),
  provider_connection_session_id uuid not null unique,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  custodian_kind text not null check (custodian_kind in ('human','organization')),
  custodian_user_id uuid references auth.users(id) on delete cascade,
  custodian_organization_id uuid references atlas.organizations(id) on delete cascade,
  provider_key text not null check (btrim(provider_key)<>''),
  authorization_subject_key text not null check (btrim(authorization_subject_key)<>''),
  vault_secret_id uuid not null unique references vault.secrets(id) on delete restrict,
  authorization_state text not null default 'ready' check (authorization_state in ('ready','expired','revoked')),
  expires_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (((custodian_user_id is not null)::int + (custodian_organization_id is not null)::int)=1),
  check ((custodian_kind='human' and custodian_user_id is not null and custodian_organization_id is null)
      or (custodian_kind='organization' and custodian_user_id is null and custodian_organization_id is not null))
);
create index provider_asset_authorizations_actor_idx on atlas.provider_asset_authorizations(actor_user_id,created_at desc);

create table atlas.provider_asset_candidates (
  id uuid primary key default gen_random_uuid(),
  provider_asset_authorization_id uuid not null references atlas.provider_asset_authorizations(id) on delete cascade,
  asset_kind text not null check (asset_kind in ('facebook_page','instagram_business')),
  provider_asset_key text not null check (btrim(provider_asset_key)<>''),
  parent_provider_asset_key text,
  display_label text,
  provider_tasks text[] not null default '{}'::text[],
  capabilities jsonb not null default '{}'::jsonb check (jsonb_typeof(capabilities)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique(provider_asset_authorization_id,asset_kind,provider_asset_key)
);

create table atlas.provider_asset_selections (
  id uuid primary key default gen_random_uuid(),
  provider_asset_authorization_id uuid not null references atlas.provider_asset_authorizations(id) on delete cascade,
  provider_asset_candidate_id uuid not null references atlas.provider_asset_candidates(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  selection_state text not null default 'requested' check (selection_state in ('requested','source_pending','connected','failed')),
  connected_source_id uuid references atlas.connected_sources(id) on delete restrict,
  last_error text,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_asset_authorization_id,provider_asset_candidate_id)
);

comment on table atlas.provider_asset_authorizations is 'Short-lived provider-human authorization used only to discover/select provider business assets. Reusable user token remains in Vault; this row is not a Connected Source.';
comment on table atlas.provider_asset_candidates is 'Non-secret assets observed through one temporary provider authorization. Discovery is evidence, not Atlas ownership or source activation.';
comment on table atlas.provider_asset_selections is 'Explicit signed-in selection of a discovered provider asset for the custody root fixed by the originating connection session.';

create or replace function atlas.create_provider_asset_authorization_service_v1(
  p_provider_connection_session_id uuid,
  p_provider_key text,
  p_authorization_subject_key text,
  p_access_token text,
  p_expires_at timestamptz,
  p_candidates jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=pg_catalog,atlas,vault as $function$
declare
  v_session jsonb; v_provider text:=lower(btrim(coalesce(p_provider_key,''))); v_subject text:=btrim(coalesce(p_authorization_subject_key,''));
  v_authorization_id uuid:=gen_random_uuid(); v_secret_id uuid; v_candidate jsonb; v_kind text; v_key text; v_parent text; v_label text; v_count integer:=0;
  v_session_relation regclass;
begin
  v_session_relation:=to_regclass('atlas.provider_connection_sessions');
  if v_session_relation is null then raise exception 'Provider connection session rail is unavailable.' using errcode='55000'; end if;
  if v_provider='' or v_subject='' or p_access_token is null or p_access_token='' or p_expires_at<=now() then raise exception 'Valid provider authorization is required.' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_candidates,'[]'::jsonb))<>'array' or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'Candidates must be an array and metadata an object.' using errcode='22023'; end if;

  execute format(
    'select jsonb_build_object(''actorUserId'',actor_user_id,''custodianKind'',custodian_kind,''custodianUserId'',custodian_user_id,''organizationId'',custodian_organization_id,''providerKey'',provider_key,''sessionState'',session_state,''expiresAt'',expires_at) from %s where id=$1 for update',
    v_session_relation
  ) into v_session using p_provider_connection_session_id;
  if v_session is null then raise exception 'Provider connection session not found.' using errcode='P0002'; end if;
  if v_session->>'sessionState'<>'pending' or (v_session->>'expiresAt')::timestamptz<=now() then raise exception 'Provider connection session is not available for asset discovery.' using errcode='55000'; end if;
  if v_provider is distinct from v_session->>'providerKey' then raise exception 'Provider authorization does not match the connection session.' using errcode='42501'; end if;

  select vault.create_secret(p_access_token,'atlas-provider-asset-auth-'||v_authorization_id::text,'Temporary provider user authorization for asset discovery',null) into v_secret_id;
  insert into atlas.provider_asset_authorizations(id,provider_connection_session_id,actor_user_id,custodian_kind,custodian_user_id,custodian_organization_id,provider_key,authorization_subject_key,vault_secret_id,expires_at,metadata)
  values(v_authorization_id,p_provider_connection_session_id,(v_session->>'actorUserId')::uuid,v_session->>'custodianKind',nullif(v_session->>'custodianUserId','')::uuid,nullif(v_session->>'organizationId','')::uuid,v_provider,v_subject,v_secret_id,least(p_expires_at,now()+interval '24 hours'),coalesce(p_metadata,'{}'::jsonb));

  for v_candidate in select value from jsonb_array_elements(coalesce(p_candidates,'[]'::jsonb)) loop
    v_kind:=lower(btrim(coalesce(v_candidate->>'assetKind',''))); v_key:=btrim(coalesce(v_candidate->>'providerAssetKey','')); v_parent:=nullif(btrim(coalesce(v_candidate->>'parentProviderAssetKey','')),''); v_label:=nullif(btrim(coalesce(v_candidate->>'displayLabel','')),'');
    if v_kind not in ('facebook_page','instagram_business') or v_key='' then raise exception 'Invalid provider asset candidate.' using errcode='22023'; end if;
    if v_kind='instagram_business' and v_parent is null then raise exception 'Instagram business candidate requires its parent Page key.' using errcode='22023'; end if;
    insert into atlas.provider_asset_candidates(provider_asset_authorization_id,asset_kind,provider_asset_key,parent_provider_asset_key,display_label,provider_tasks,capabilities,metadata)
    values(v_authorization_id,v_kind,v_key,v_parent,v_label,coalesce(array(select jsonb_array_elements_text(coalesce(v_candidate->'providerTasks','[]'::jsonb))),'{}'::text[]),coalesce(v_candidate->'capabilities','{}'::jsonb),coalesce(v_candidate->'metadata','{}'::jsonb));
    v_count:=v_count+1;
  end loop;

  execute format('update %s set metadata=metadata||$1::jsonb,updated_at=now() where id=$2',v_session_relation)
    using jsonb_build_object('providerAssetAuthorizationId',v_authorization_id),p_provider_connection_session_id;
  return jsonb_build_object('contractVersion','provider_asset_authorization_v1','authorizationId',v_authorization_id,'providerKey',v_provider,'candidateCount',v_count,'expiresAt',least(p_expires_at,now()+interval '24 hours'));
end;$function$;
revoke all on function atlas.create_provider_asset_authorization_service_v1(uuid,text,text,text,timestamptz,jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.create_provider_asset_authorization_service_v1(uuid,text,text,text,timestamptz,jsonb,jsonb) to service_role;

create or replace function atlas.provider_asset_authorization_self_api_v1(p_provider_asset_authorization_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_user uuid:=auth.uid(); v_auth atlas.provider_asset_authorizations%rowtype; v_items jsonb;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_auth from atlas.provider_asset_authorizations where id=p_provider_asset_authorization_id and actor_user_id=v_user;
  if v_auth.id is null then raise exception 'Provider asset authorization not found.' using errcode='P0002'; end if;
  if v_auth.authorization_state='ready' and v_auth.expires_at<=now() then update atlas.provider_asset_authorizations set authorization_state='expired',updated_at=now() where id=v_auth.id; v_auth.authorization_state:='expired'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('candidateId',c.id,'assetKind',c.asset_kind,'providerAssetKey',c.provider_asset_key,'parentProviderAssetKey',c.parent_provider_asset_key,'displayLabel',c.display_label,'providerTasks',c.provider_tasks,'capabilities',c.capabilities,'metadata',c.metadata) order by c.asset_kind,c.display_label,c.provider_asset_key),'[]'::jsonb)
    into v_items from atlas.provider_asset_candidates c where c.provider_asset_authorization_id=v_auth.id;
  return jsonb_build_object('contractVersion','provider_asset_authorization_self_v1','authorizationId',v_auth.id,'providerKey',v_auth.provider_key,'authorizationState',v_auth.authorization_state,'expiresAt',v_auth.expires_at,'candidates',v_items);
end;$function$;
revoke all on function atlas.provider_asset_authorization_self_api_v1(uuid) from public,anon;
grant execute on function atlas.provider_asset_authorization_self_api_v1(uuid) to authenticated;

create or replace function atlas.begin_provider_asset_selection_self_api_v1(p_provider_asset_authorization_id uuid,p_provider_asset_candidate_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_user uuid:=auth.uid(); v_auth atlas.provider_asset_authorizations%rowtype; v_candidate atlas.provider_asset_candidates%rowtype; v_selection atlas.provider_asset_selections%rowtype;
begin
  if v_user is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_auth from atlas.provider_asset_authorizations where id=p_provider_asset_authorization_id and actor_user_id=v_user for update;
  if v_auth.id is null or v_auth.authorization_state<>'ready' or v_auth.expires_at<=now() then raise exception 'Provider asset authorization is unavailable.' using errcode='42501'; end if;
  select * into v_candidate from atlas.provider_asset_candidates where id=p_provider_asset_candidate_id and provider_asset_authorization_id=v_auth.id;
  if v_candidate.id is null then raise exception 'Provider asset candidate not found.' using errcode='P0002'; end if;
  insert into atlas.provider_asset_selections(provider_asset_authorization_id,provider_asset_candidate_id,actor_user_id)
  values(v_auth.id,v_candidate.id,v_user)
  on conflict (provider_asset_authorization_id,provider_asset_candidate_id) do update set updated_at=now()
  returning * into v_selection;
  return jsonb_build_object('contractVersion','provider_asset_selection_v1','selectionId',v_selection.id,'selectionState',v_selection.selection_state,'candidateId',v_candidate.id,'assetKind',v_candidate.asset_kind,'providerAssetKey',v_candidate.provider_asset_key,'parentProviderAssetKey',v_candidate.parent_provider_asset_key,'displayLabel',v_candidate.display_label);
end;$function$;
revoke all on function atlas.begin_provider_asset_selection_self_api_v1(uuid,uuid) from public,anon;
grant execute on function atlas.begin_provider_asset_selection_self_api_v1(uuid,uuid) to authenticated;

create or replace function atlas.provider_asset_selection_context_service_v1(p_provider_asset_selection_id uuid)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,vault as $function$
declare v_selection atlas.provider_asset_selections%rowtype; v_auth atlas.provider_asset_authorizations%rowtype; v_candidate atlas.provider_asset_candidates%rowtype; v_token text;
begin
  select * into v_selection from atlas.provider_asset_selections where id=p_provider_asset_selection_id for update;
  if v_selection.id is null then raise exception 'Provider asset selection not found.' using errcode='P0002'; end if;
  select * into v_auth from atlas.provider_asset_authorizations where id=v_selection.provider_asset_authorization_id;
  select * into v_candidate from atlas.provider_asset_candidates where id=v_selection.provider_asset_candidate_id;
  if v_auth.authorization_state<>'ready' or v_auth.expires_at<=now() then raise exception 'Provider asset authorization expired or revoked.' using errcode='55000'; end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where id=v_auth.vault_secret_id;
  if v_token is null or v_token='' then raise exception 'Provider authorization token is unavailable.' using errcode='55000'; end if;
  return jsonb_build_object('contractVersion','provider_asset_selection_context_v1','selectionId',v_selection.id,'selectionState',v_selection.selection_state,'providerKey',v_auth.provider_key,'authorizationSubjectKey',v_auth.authorization_subject_key,'authorizationAccessToken',v_token,'custodianKind',v_auth.custodian_kind,'custodianUserId',v_auth.custodian_user_id,'organizationId',v_auth.custodian_organization_id,'assetKind',v_candidate.asset_kind,'providerAssetKey',v_candidate.provider_asset_key,'parentProviderAssetKey',v_candidate.parent_provider_asset_key,'displayLabel',v_candidate.display_label,'providerTasks',v_candidate.provider_tasks,'capabilities',v_candidate.capabilities);
end;$function$;
revoke all on function atlas.provider_asset_selection_context_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.provider_asset_selection_context_service_v1(uuid) to service_role;

create or replace function atlas.create_provider_asset_connected_source_service_v1(
  p_provider_asset_selection_id uuid,
  p_source_provider_key text,
  p_granted_scopes text[] default '{}'::text[],
  p_capabilities jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_selection atlas.provider_asset_selections%rowtype; v_auth atlas.provider_asset_authorizations%rowtype; v_candidate atlas.provider_asset_candidates%rowtype; v_source atlas.connected_sources%rowtype; v_provider text:=lower(btrim(coalesce(p_source_provider_key,'')));
begin
  select * into v_selection from atlas.provider_asset_selections where id=p_provider_asset_selection_id for update;
  if v_selection.id is null or v_selection.selection_state not in ('requested','source_pending') then raise exception 'Provider asset selection is not source-creatable.' using errcode='55000'; end if;
  select * into v_auth from atlas.provider_asset_authorizations where id=v_selection.provider_asset_authorization_id;
  select * into v_candidate from atlas.provider_asset_candidates where id=v_selection.provider_asset_candidate_id;
  if v_auth.authorization_state<>'ready' or v_auth.expires_at<=now() then raise exception 'Provider asset authorization is unavailable.' using errcode='55000'; end if;
  if (v_candidate.asset_kind='facebook_page' and v_provider<>'facebook') or (v_candidate.asset_kind='instagram_business' and v_provider<>'instagram') then raise exception 'Source provider does not match selected asset kind.' using errcode='22023'; end if;
  if exists(select 1 from atlas.connected_sources s where s.provider_key=v_provider and s.provider_account_key=v_candidate.provider_asset_key and s.authorization_state not in ('revoked') and ((v_auth.custodian_kind='human' and s.custodian_user_id is distinct from v_auth.custodian_user_id) or (v_auth.custodian_kind='organization' and s.custodian_organization_id is distinct from v_auth.custodian_organization_id))) then raise exception 'Provider asset is already associated with another Atlas custody root.' using errcode='55000'; end if;

  if v_auth.custodian_kind='human' then
    insert into atlas.connected_sources(custodian_user_id,provider_key,provider_account_key,display_label,authorization_state,granted_scopes,capabilities,metadata)
    values(v_auth.custodian_user_id,v_provider,v_candidate.provider_asset_key,v_candidate.display_label,'pending',coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),jsonb_build_object('providerAssetSelectionId',v_selection.id,'authorizationSubjectKey',v_auth.authorization_subject_key,'assetKind',v_candidate.asset_kind,'parentProviderAssetKey',v_candidate.parent_provider_asset_key)||coalesce(p_metadata,'{}'::jsonb))
    on conflict (custodian_user_id,provider_key,provider_account_key) where custodian_user_id is not null do update set display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),authorization_state=case when atlas.connected_sources.authorization_state='revoked' then 'revoked' else 'pending' end,granted_scopes=excluded.granted_scopes,capabilities=atlas.connected_sources.capabilities||excluded.capabilities,metadata=atlas.connected_sources.metadata||excluded.metadata,updated_at=now() returning * into v_source;
  else
    insert into atlas.connected_sources(custodian_organization_id,provider_key,provider_account_key,display_label,authorization_state,granted_scopes,capabilities,metadata)
    values(v_auth.custodian_organization_id,v_provider,v_candidate.provider_asset_key,v_candidate.display_label,'pending',coalesce(p_granted_scopes,'{}'::text[]),coalesce(p_capabilities,'{}'::jsonb),jsonb_build_object('providerAssetSelectionId',v_selection.id,'authorizationSubjectKey',v_auth.authorization_subject_key,'assetKind',v_candidate.asset_kind,'parentProviderAssetKey',v_candidate.parent_provider_asset_key)||coalesce(p_metadata,'{}'::jsonb))
    on conflict (custodian_organization_id,provider_key,provider_account_key) where custodian_organization_id is not null do update set display_label=coalesce(excluded.display_label,atlas.connected_sources.display_label),authorization_state=case when atlas.connected_sources.authorization_state='revoked' then 'revoked' else 'pending' end,granted_scopes=excluded.granted_scopes,capabilities=atlas.connected_sources.capabilities||excluded.capabilities,metadata=atlas.connected_sources.metadata||excluded.metadata,updated_at=now() returning * into v_source;
  end if;
  if v_source.authorization_state='revoked' then raise exception 'Revoked source cannot be silently reconnected.' using errcode='55000'; end if;
  update atlas.provider_asset_selections set selection_state='source_pending',connected_source_id=v_source.id,last_error=null,updated_at=now() where id=v_selection.id;
  return jsonb_build_object('contractVersion','provider_asset_source_pending_v1','selectionId',v_selection.id,'connectedSourceId',v_source.id,'providerKey',v_source.provider_key,'providerAccountKey',v_source.provider_account_key,'authorizationState',v_source.authorization_state);
end;$function$;
revoke all on function atlas.create_provider_asset_connected_source_service_v1(uuid,text,text[],jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.create_provider_asset_connected_source_service_v1(uuid,text,text[],jsonb,jsonb) to service_role;

create or replace function atlas.complete_provider_asset_selection_service_v1(p_provider_asset_selection_id uuid,p_required_credential_kind text,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_selection atlas.provider_asset_selections%rowtype; v_source atlas.connected_sources%rowtype; v_kind text:=lower(btrim(coalesce(p_required_credential_kind,'')));
begin
  select * into v_selection from atlas.provider_asset_selections where id=p_provider_asset_selection_id for update;
  if v_selection.id is null or v_selection.connected_source_id is null then raise exception 'Provider asset source has not been created.' using errcode='55000'; end if;
  if v_selection.selection_state='connected' then return jsonb_build_object('contractVersion','provider_asset_selection_complete_v1','selectionId',v_selection.id,'connectedSourceId',v_selection.connected_source_id,'alreadyConnected',true); end if;
  if v_selection.selection_state<>'source_pending' then raise exception 'Provider asset selection is not ready for activation.' using errcode='55000'; end if;
  if v_kind='' or not exists(select 1 from atlas.connected_source_secret_refs r where r.connected_source_id=v_selection.connected_source_id and r.credential_kind=v_kind) then raise exception 'Required provider credential is not in Vault custody.' using errcode='55000'; end if;
  update atlas.connected_sources set authorization_state='connected',revoked_at=null,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=v_selection.connected_source_id and authorization_state in ('pending','reauthorization_required','error') returning * into v_source;
  if v_source.id is null then raise exception 'Selected source cannot be activated from its current state.' using errcode='55000'; end if;
  update atlas.provider_asset_selections set selection_state='connected',last_error=null,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now() where id=v_selection.id;
  return jsonb_build_object('contractVersion','provider_asset_selection_complete_v1','selectionId',v_selection.id,'connectedSourceId',v_source.id,'authorizationState',v_source.authorization_state,'alreadyConnected',false);
end;$function$;
revoke all on function atlas.complete_provider_asset_selection_service_v1(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function atlas.complete_provider_asset_selection_service_v1(uuid,text,jsonb) to service_role;

create or replace function public.provider_asset_authorization_self_api_v1(p_provider_asset_authorization_id uuid)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.provider_asset_authorization_self_api_v1(p_provider_asset_authorization_id); $function$;
revoke all on function public.provider_asset_authorization_self_api_v1(uuid) from public,anon; grant execute on function public.provider_asset_authorization_self_api_v1(uuid) to authenticated;

create or replace function public.begin_provider_asset_selection_self_api_v1(p_provider_asset_authorization_id uuid,p_provider_asset_candidate_id uuid)
returns jsonb language sql set search_path=pg_catalog,atlas,public as $function$ select atlas.begin_provider_asset_selection_self_api_v1(p_provider_asset_authorization_id,p_provider_asset_candidate_id); $function$;
revoke all on function public.begin_provider_asset_selection_self_api_v1(uuid,uuid) from public,anon; grant execute on function public.begin_provider_asset_selection_self_api_v1(uuid,uuid) to authenticated;

revoke all on table atlas.provider_asset_authorizations from public,anon,authenticated;
revoke all on table atlas.provider_asset_candidates from public,anon,authenticated;
revoke all on table atlas.provider_asset_selections from public,anon,authenticated;
alter table atlas.provider_asset_authorizations enable row level security;
alter table atlas.provider_asset_candidates enable row level security;
alter table atlas.provider_asset_selections enable row level security;

commit;
