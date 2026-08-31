BEGIN;

-- Atlas Continuity — source identity links.
--
-- Communication capture preserves source identities without pretending that a
-- phone number, email address, or thread is itself a canonical person. This
-- table records an evidential link from one source identity to an existing Atlas
-- target (for example a farm membership today, and eventually a Principal),
-- while preserving basis, confidence, and provenance.

create table atlas.communication_identity_links (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete cascade,
  thread_id uuid references atlas.communication_threads(id) on delete cascade,
  source_identity_kind text not null check (btrim(source_identity_kind) <> ''),
  source_identity_key text not null check (btrim(source_identity_key) <> ''),
  target_domain text not null check (btrim(target_domain) <> ''),
  target_kind text not null check (btrim(target_kind) <> ''),
  target_id text not null check (btrim(target_id) <> ''),
  target_label text,
  relation_basis text not null check (btrim(relation_basis) <> ''),
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  relation_status text not null default 'active'
    check (relation_status in ('active','review','rejected','superseded')),
  provenance jsonb not null default '{}'::jsonb,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index communication_identity_links_one_active_source_identity_idx
  on atlas.communication_identity_links (connected_source_id, source_identity_kind, source_identity_key)
  where relation_status = 'active';

create index communication_identity_links_thread_idx
  on atlas.communication_identity_links (thread_id)
  where thread_id is not null;

create index communication_identity_links_target_idx
  on atlas.communication_identity_links (target_domain, target_kind, target_id)
  where relation_status = 'active';

create or replace function atlas.communication_identity_links_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_owner_user_id uuid;
  v_thread_source_id uuid;
  v_thread_principal_id uuid;
begin
  select p.user_id
    into v_owner_user_id
  from atlas.principals p
  where p.id = new.principal_id
    and p.status = 'active';

  if v_owner_user_id is null then
    raise exception 'Communication identity links require an active Principal.' using errcode = '23514';
  end if;

  if not exists (
    select 1
    from atlas.connected_sources s
    where s.id = new.connected_source_id
      and s.custodian_user_id = v_owner_user_id
      and s.authorization_state = 'connected'
  ) then
    raise exception 'Communication identity source is not owned by the Principal.' using errcode = '23514';
  end if;

  if new.thread_id is not null then
    select t.connected_source_id, t.principal_id
      into v_thread_source_id, v_thread_principal_id
    from atlas.communication_threads t
    where t.id = new.thread_id;

    if v_thread_source_id is distinct from new.connected_source_id
       or v_thread_principal_id is distinct from new.principal_id then
      raise exception 'Communication identity thread does not belong to the same Principal/source.' using errcode = '23514';
    end if;
  end if;

  new.source_identity_kind := lower(btrim(new.source_identity_kind));
  new.source_identity_key := btrim(new.source_identity_key);
  new.target_domain := lower(btrim(new.target_domain));
  new.target_kind := lower(btrim(new.target_kind));
  new.target_id := btrim(new.target_id);
  new.target_label := nullif(btrim(new.target_label), '');
  new.relation_basis := lower(btrim(new.relation_basis));
  new.updated_at := now();
  return new;
end;
$function$;

create trigger communication_identity_links_guard
before insert or update on atlas.communication_identity_links
for each row execute function atlas.communication_identity_links_guard_v1();

alter table atlas.communication_identity_links enable row level security;

revoke all on atlas.communication_identity_links from public, anon, authenticated;
grant select, insert, update, delete on atlas.communication_identity_links to service_role;

revoke all on function atlas.communication_identity_links_guard_v1() from public, anon, authenticated;

comment on table atlas.communication_identity_links is
  'Evidential source-identity links for Atlas Continuity. Source identifiers remain distinct from canonical people/entities; active links preserve target, basis, confidence, and provenance.';

COMMIT;
