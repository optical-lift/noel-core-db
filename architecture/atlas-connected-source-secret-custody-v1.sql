-- Atlas Connected Source Secret Custody v1 — executable architecture source.
--
-- Reusable OAuth/API credentials are encrypted in Supabase Vault. Atlas stores
-- only immutable references and append-only revocation/rotation provenance.
-- No authenticated API returns decrypted credential material.

create table atlas.connected_source_secret_refs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  secret_kind text not null check (btrim(secret_kind) <> ''),
  version_number integer not null check (version_number > 0),
  vault_secret_id uuid not null,
  prior_secret_ref_id uuid references atlas.connected_source_secret_refs(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint connected_source_secret_version_uq unique(connected_source_id,secret_kind,version_number),
  constraint connected_source_secret_vault_uq unique(vault_secret_id),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.connected_source_secret_refs is
  'Immutable reference history for reusable credentials encrypted in Supabase Vault. This table contains no secret plaintext.';

create index connected_source_secret_refs_lookup_idx
  on atlas.connected_source_secret_refs(connected_source_id,secret_kind,version_number desc,id desc);

create table atlas.connected_source_secret_revocation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  secret_ref_id uuid not null references atlas.connected_source_secret_refs(id) on delete restrict,
  reason text not null check (btrim(reason) <> ''),
  replacement_secret_ref_id uuid references atlas.connected_source_secret_refs(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  revoked_at timestamptz not null default now(),
  constraint connected_source_secret_revocation_once_uq unique(secret_ref_id),
  check (replacement_secret_ref_id is null or replacement_secret_ref_id <> secret_ref_id),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.connected_source_secret_revocation_events is
  'Append-only evidence that a connected-source secret version is no longer current. Rotation creates a new Vault secret and revokes the prior reference.';

create or replace function atlas.reject_connected_source_secret_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Connected-source credential reference history is append-only.' using errcode='55000';
end;
$function$;

revoke all on function atlas.reject_connected_source_secret_history_mutation_v1()
  from public,anon,authenticated,service_role;

create trigger connected_source_secret_refs_append_only_v1
before update or delete on atlas.connected_source_secret_refs
for each row execute function atlas.reject_connected_source_secret_history_mutation_v1();
create trigger connected_source_secret_revocation_events_append_only_v1
before update or delete on atlas.connected_source_secret_revocation_events
for each row execute function atlas.reject_connected_source_secret_history_mutation_v1();

create or replace function atlas.guard_connected_source_secret_ref_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source_org uuid;
  v_prior atlas.connected_source_secret_refs%rowtype;
begin
  select s.custodian_organization_id into v_source_org
  from atlas.connected_sources s
  where s.id=new.connected_source_id
    and s.custodian_user_id is null;
  if v_source_org is null or v_source_org is distinct from new.organization_id then
    raise exception 'Connected-source secret reference is outside organization custody.' using errcode='42501';
  end if;

  if new.prior_secret_ref_id is not null then
    select * into v_prior from atlas.connected_source_secret_refs where id=new.prior_secret_ref_id;
    if v_prior.id is null
       or v_prior.organization_id is distinct from new.organization_id
       or v_prior.connected_source_id is distinct from new.connected_source_id
       or v_prior.secret_kind is distinct from new.secret_kind
       or v_prior.version_number+1 is distinct from new.version_number then
      raise exception 'Connected-source secret rotation chain is invalid.' using errcode='23514';
    end if;
  elsif new.version_number<>1 then
    raise exception 'First connected-source secret version must be version 1.' using errcode='23514';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_connected_source_secret_ref_custody_v1()
  from public,anon,authenticated,service_role;

create trigger connected_source_secret_ref_custody_guard_v1
before insert on atlas.connected_source_secret_refs
for each row execute function atlas.guard_connected_source_secret_ref_custody_v1();

create or replace function atlas.guard_connected_source_secret_revocation_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_secret atlas.connected_source_secret_refs%rowtype;
  v_replacement atlas.connected_source_secret_refs%rowtype;
begin
  select * into v_secret from atlas.connected_source_secret_refs where id=new.secret_ref_id;
  if v_secret.id is null or v_secret.organization_id is distinct from new.organization_id then
    raise exception 'Connected-source secret revocation is outside organization custody.' using errcode='42501';
  end if;
  if new.replacement_secret_ref_id is not null then
    select * into v_replacement from atlas.connected_source_secret_refs where id=new.replacement_secret_ref_id;
    if v_replacement.id is null
       or v_replacement.organization_id is distinct from new.organization_id
       or v_replacement.connected_source_id is distinct from v_secret.connected_source_id
       or v_replacement.secret_kind is distinct from v_secret.secret_kind
       or v_replacement.prior_secret_ref_id is distinct from v_secret.id then
      raise exception 'Replacement credential does not continue the revoked secret chain.' using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_connected_source_secret_revocation_custody_v1()
  from public,anon,authenticated,service_role;

create trigger connected_source_secret_revocation_custody_guard_v1
before insert on atlas.connected_source_secret_revocation_events
for each row execute function atlas.guard_connected_source_secret_revocation_custody_v1();

create or replace function atlas.current_connected_source_secret_ref_core_v1(
  p_connected_source_id uuid,
  p_secret_kind text
)
returns atlas.connected_source_secret_refs
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select r
  from atlas.connected_source_secret_refs r
  where r.connected_source_id=p_connected_source_id
    and r.secret_kind=btrim(p_secret_kind)
    and not exists(
      select 1 from atlas.connected_source_secret_revocation_events x
      where x.secret_ref_id=r.id
    )
  order by r.version_number desc,r.id desc
  limit 1;
$function$;

revoke all on function atlas.current_connected_source_secret_ref_core_v1(uuid,text)
  from public,anon,authenticated,service_role;

create or replace function atlas.put_connected_source_secret_core_v1(
  p_connected_source_id uuid,
  p_secret_kind text,
  p_secret_value text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,vault
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_kind text:=lower(nullif(btrim(coalesce(p_secret_kind,'')),''));
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_prior atlas.connected_source_secret_refs%rowtype;
  v_new atlas.connected_source_secret_refs%rowtype;
  v_new_vault_id uuid;
  v_version integer;
  v_secret_name text;
begin
  if p_connected_source_id is null
     or v_kind is null
     or p_secret_value is null or p_secret_value=''
     or v_reason is null then
    raise exception 'Connected-source credential storage requires source, kind, secret value, and reason.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Connected-source credential metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_source
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id is not null
    and s.custodian_user_id is null;
  if v_source.id is null then
    raise exception 'Organization-owned connected source not found.' using errcode='P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_source.id::text||':'||v_kind,0));
  select * into v_prior from atlas.current_connected_source_secret_ref_core_v1(v_source.id,v_kind);
  v_version:=coalesce(v_prior.version_number,0)+1;
  v_secret_name:='atlas_source_'||replace(v_source.id::text,'-','')||'_'||regexp_replace(v_kind,'[^a-z0-9_]+','_','g')||'_v'||v_version::text||'_'||replace(gen_random_uuid()::text,'-','');

  v_new_vault_id:=vault.create_secret(
    p_secret_value,
    v_secret_name,
    'Atlas connected source credential. source='||v_source.id::text||' kind='||v_kind||' version='||v_version::text,
    null
  );

  insert into atlas.connected_source_secret_refs(
    organization_id,connected_source_id,secret_kind,version_number,vault_secret_id,
    prior_secret_ref_id,metadata
  ) values (
    v_source.custodian_organization_id,v_source.id,v_kind,v_version,v_new_vault_id,
    v_prior.id,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('reason',v_reason)
  ) returning * into v_new;

  if v_prior.id is not null then
    insert into atlas.connected_source_secret_revocation_events(
      organization_id,secret_ref_id,reason,replacement_secret_ref_id,metadata
    ) values (
      v_source.custodian_organization_id,v_prior.id,'rotated: '||v_reason,v_new.id,
      jsonb_build_object('rotation',true)
    );
    -- Destroy the reusable prior plaintext in Vault while preserving its secret id
    -- as historical custody provenance. The generated marker is not usable auth material.
    perform vault.update_secret(
      v_prior.vault_secret_id,
      'revoked:'||gen_random_uuid()::text,
      null,
      'Revoked Atlas connected source credential reference '||v_prior.id::text,
      null
    );
  end if;

  return jsonb_build_object(
    'contractVersion','put_connected_source_secret_core_v1',
    'sourceId',v_source.id,
    'secretKind',v_kind,
    'secretRefId',v_new.id,
    'versionNumber',v_new.version_number,
    'rotated',v_prior.id is not null
  );
end;
$function$;

create or replace function atlas.read_connected_source_secret_core_v1(
  p_connected_source_id uuid,
  p_secret_kind text
)
returns text
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,vault
as $function$
declare
  v_ref atlas.connected_source_secret_refs%rowtype;
  v_secret text;
begin
  select * into v_ref
  from atlas.current_connected_source_secret_ref_core_v1(p_connected_source_id,btrim(p_secret_kind));
  if v_ref.id is null then
    return null;
  end if;
  select d.decrypted_secret into v_secret
  from vault.decrypted_secrets d
  where d.id=v_ref.vault_secret_id;
  return v_secret;
end;
$function$;

create or replace function atlas.revoke_connected_source_secret_core_v1(
  p_connected_source_id uuid,
  p_secret_kind text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,vault
as $function$
declare
  v_ref atlas.connected_source_secret_refs%rowtype;
  v_source atlas.connected_sources%rowtype;
begin
  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Connected-source credential revocation requires an explicit reason.' using errcode='22023';
  end if;
  select * into v_source from atlas.connected_sources where id=p_connected_source_id and custodian_organization_id is not null;
  if v_source.id is null then raise exception 'Organization-owned connected source not found.' using errcode='P0002'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_source.id::text||':'||lower(btrim(p_secret_kind)),0));
  select * into v_ref from atlas.current_connected_source_secret_ref_core_v1(v_source.id,lower(btrim(p_secret_kind)));
  if v_ref.id is null then
    return jsonb_build_object(
      'contractVersion','revoke_connected_source_secret_core_v1','state','already_absent',
      'sourceId',v_source.id,'secretKind',lower(btrim(p_secret_kind))
    );
  end if;

  insert into atlas.connected_source_secret_revocation_events(
    organization_id,secret_ref_id,reason,metadata
  ) values (
    v_source.custodian_organization_id,v_ref.id,btrim(p_reason),coalesce(p_metadata,'{}'::jsonb)
  );
  perform vault.update_secret(
    v_ref.vault_secret_id,
    'revoked:'||gen_random_uuid()::text,
    null,
    'Revoked Atlas connected source credential reference '||v_ref.id::text,
    null
  );

  return jsonb_build_object(
    'contractVersion','revoke_connected_source_secret_core_v1','state','revoked',
    'sourceId',v_source.id,'secretKind',v_ref.secret_kind,'secretRefId',v_ref.id
  );
end;
$function$;

alter table atlas.connected_source_secret_refs enable row level security;
alter table atlas.connected_source_secret_revocation_events enable row level security;

revoke all on atlas.connected_source_secret_refs from public,anon,authenticated,service_role;
revoke all on atlas.connected_source_secret_revocation_events from public,anon,authenticated,service_role;
grant select,insert on atlas.connected_source_secret_refs to service_role;
grant select,insert on atlas.connected_source_secret_revocation_events to service_role;

revoke all on function atlas.put_connected_source_secret_core_v1(uuid,text,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.put_connected_source_secret_core_v1(uuid,text,text,text,jsonb)
  to service_role;
revoke all on function atlas.read_connected_source_secret_core_v1(uuid,text)
  from public,anon,authenticated;
grant execute on function atlas.read_connected_source_secret_core_v1(uuid,text)
  to service_role;
revoke all on function atlas.revoke_connected_source_secret_core_v1(uuid,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.revoke_connected_source_secret_core_v1(uuid,text,text,jsonb)
  to service_role;

-- Vault itself remains inaccessible to browser roles. Service code receives only
-- the requested secret through the narrow source/kind resolver above.
do $proof$
begin
  if has_table_privilege('anon','vault.decrypted_secrets','SELECT')
     or has_table_privilege('authenticated','vault.decrypted_secrets','SELECT') then
    raise exception 'Connected-source secret proof failed: Vault decrypted secrets leaked to browser role.';
  end if;
  if has_function_privilege('authenticated','atlas.read_connected_source_secret_core_v1(uuid,text)','EXECUTE') then
    raise exception 'Connected-source secret proof failed: decrypted secret resolver leaked to authenticated.';
  end if;
  if has_table_privilege('authenticated','atlas.connected_source_secret_refs','SELECT') then
    raise exception 'Connected-source secret proof failed: credential reference table leaked to authenticated.';
  end if;
end;
$proof$;
