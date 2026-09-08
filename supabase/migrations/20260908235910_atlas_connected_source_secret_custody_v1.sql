-- Atlas connected-source secret custody v1.
--
-- Provider credentials remain outside atlas.connected_sources. This table stores only
-- a reference to an encrypted Supabase Vault secret and the provider-neutral credential kind.
-- Decrypted credential access is service-role only.

create table if not exists atlas.connected_source_secret_refs (
  connected_source_id uuid not null
    references atlas.connected_sources(id) on delete cascade,
  credential_kind text not null,
  vault_secret_id uuid not null
    references vault.secrets(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (connected_source_id, credential_kind),
  unique (vault_secret_id),
  constraint connected_source_secret_refs_kind_check
    check (btrim(credential_kind) <> '')
);

alter table atlas.connected_source_secret_refs enable row level security;

revoke all on table atlas.connected_source_secret_refs from public, anon, authenticated;
grant select, insert, update, delete on table atlas.connected_source_secret_refs to service_role;

create or replace function atlas.store_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text,
  p_secret text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, vault
as $function$
declare
  v_kind text := btrim(coalesce(p_credential_kind, ''));
  v_secret text := coalesce(p_secret, '');
  v_description text := coalesce(nullif(btrim(p_description), ''), 'Atlas external provider credential');
  v_existing_secret_id uuid;
  v_secret_id uuid;
  v_provider_key text;
begin
  if p_connected_source_id is null or v_kind = '' or v_secret = '' then
    raise exception 'Connected source, credential kind, and secret are required.' using errcode = '22023';
  end if;

  select source.provider_key
    into v_provider_key
  from atlas.connected_sources source
  where source.id = p_connected_source_id;

  if v_provider_key is null then
    raise exception 'Connected source is unavailable.' using errcode = '22023';
  end if;

  select ref.vault_secret_id
    into v_existing_secret_id
  from atlas.connected_source_secret_refs ref
  where ref.connected_source_id = p_connected_source_id
    and ref.credential_kind = v_kind
  for update;

  if found then
    perform vault.update_secret(
      v_existing_secret_id,
      v_secret,
      null,
      v_description,
      null
    );
    v_secret_id := v_existing_secret_id;

    update atlas.connected_source_secret_refs ref
    set updated_at = now()
    where ref.connected_source_id = p_connected_source_id
      and ref.credential_kind = v_kind;
  else
    v_secret_id := vault.create_secret(
      v_secret,
      format('atlas-source-%s-%s', replace(p_connected_source_id::text, '-', ''), regexp_replace(v_kind, '[^a-zA-Z0-9_-]+', '_', 'g')),
      v_description,
      null
    );

    insert into atlas.connected_source_secret_refs (
      connected_source_id,
      credential_kind,
      vault_secret_id
    ) values (
      p_connected_source_id,
      v_kind,
      v_secret_id
    );
  end if;

  return jsonb_build_object(
    'stored', true,
    'connectedSourceId', p_connected_source_id,
    'providerKey', v_provider_key,
    'credentialKind', v_kind
  );
end;
$function$;

create or replace function atlas.read_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, atlas, vault
as $function$
  select secret.decrypted_secret
  from atlas.connected_source_secret_refs ref
  join vault.decrypted_secrets secret
    on secret.id = ref.vault_secret_id
  where ref.connected_source_id = p_connected_source_id
    and ref.credential_kind = btrim(coalesce(p_credential_kind, ''));
$function$;

create or replace function atlas.delete_connected_source_secret_service_v1(
  p_connected_source_id uuid,
  p_credential_kind text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, atlas, vault
as $function$
declare
  v_kind text := btrim(coalesce(p_credential_kind, ''));
  v_secret_id uuid;
begin
  select ref.vault_secret_id
    into v_secret_id
  from atlas.connected_source_secret_refs ref
  where ref.connected_source_id = p_connected_source_id
    and ref.credential_kind = v_kind
  for update;

  if not found then
    return false;
  end if;

  delete from atlas.connected_source_secret_refs ref
  where ref.connected_source_id = p_connected_source_id
    and ref.credential_kind = v_kind;

  delete from vault.secrets secret
  where secret.id = v_secret_id;

  return true;
end;
$function$;

comment on table atlas.connected_source_secret_refs is
'Provider-neutral references from Atlas connected sources to encrypted Supabase Vault secrets. This table never stores decrypted credentials.';

comment on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) is
'Service-only provider credential create/rotation membrane. Secret plaintext is written directly into Supabase Vault and is never returned.';

comment on function atlas.read_connected_source_secret_service_v1(uuid,text) is
'Service-only provider credential read membrane for server-side provider adapters. Never grant to authenticated or anonymous clients.';

comment on function atlas.delete_connected_source_secret_service_v1(uuid,text) is
'Service-only provider credential deletion membrane used by explicit provider disconnect/revocation flows.';

revoke all on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) from public, anon, authenticated;
revoke all on function atlas.read_connected_source_secret_service_v1(uuid,text) from public, anon, authenticated;
revoke all on function atlas.delete_connected_source_secret_service_v1(uuid,text) from public, anon, authenticated;

grant execute on function atlas.store_connected_source_secret_service_v1(uuid,text,text,text) to service_role;
grant execute on function atlas.read_connected_source_secret_service_v1(uuid,text) to service_role;
grant execute on function atlas.delete_connected_source_secret_service_v1(uuid,text) to service_role;

insert into atlas.authenticated_rpc_registry (
  signature,
  classification,
  confidence,
  review_status,
  authenticated_execute_expected,
  security_definer_expected,
  service_execute_expected,
  caller_count,
  policy_reference_count,
  evidence,
  anonymous_execute_expected
) values
(
  'atlas.store_connected_source_secret_service_v1(uuid,text,text,text)',
  'service_internal',
  'verified',
  'active',
  false,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_connected_source_secret_custody_v1',
    'purpose','Store or rotate a provider credential in encrypted Vault custody for a connected source.',
    'boundary','Service-role only. Plaintext is accepted only by the server-side adapter and is written into Vault; authenticated clients cannot execute this function.',
    'truthBoundary','Credential custody does not establish provider authorization state or any Atlas domain truth.'
  ),
  false
),
(
  'atlas.read_connected_source_secret_service_v1(uuid,text)',
  'service_internal',
  'verified',
  'active',
  false,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_connected_source_secret_custody_v1',
    'purpose','Retrieve a provider credential only for a server-side provider adapter that must call the external provider.',
    'boundary','Service-role only. Never expose this RPC to browser/authenticated application clients.',
    'truthBoundary','Secret retrieval supplies transport credentials only and carries no Atlas business-domain authority.'
  ),
  false
),
(
  'atlas.delete_connected_source_secret_service_v1(uuid,text)',
  'service_internal',
  'verified',
  'active',
  false,
  true,
  true,
  1,
  1,
  jsonb_build_object(
    'source','atlas_connected_source_secret_custody_v1',
    'purpose','Delete a provider credential from Vault during deliberate disconnect/revocation handling.',
    'boundary','Service-role only. Connected-source authorization state is changed separately through its governed command.',
    'truthBoundary','Credential deletion alone does not rewrite source authorization or other domain truth.'
  ),
  false
)
on conflict (signature) do update
set classification = excluded.classification,
    confidence = excluded.confidence,
    review_status = excluded.review_status,
    authenticated_execute_expected = excluded.authenticated_execute_expected,
    security_definer_expected = excluded.security_definer_expected,
    service_execute_expected = excluded.service_execute_expected,
    caller_count = excluded.caller_count,
    policy_reference_count = excluded.policy_reference_count,
    evidence = excluded.evidence,
    anonymous_execute_expected = excluded.anonymous_execute_expected,
    reviewed_at = now();
