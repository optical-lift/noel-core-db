-- Newsroom Institutional Root v1
-- Separates whole-product company/publication membership from domain-specific custody.
-- Transcript Core remains authoritative for transcript access; this layer only binds it beneath Newsroom context.

create schema if not exists newsroom;

create table if not exists newsroom.workspaces (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  state text not null default 'active' check (state in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint newsroom_workspaces_slug_not_blank check (length(btrim(slug)) > 0),
  constraint newsroom_workspaces_name_not_blank check (length(btrim(name)) > 0)
);

create table if not exists newsroom.publications (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references newsroom.workspaces(id) on delete cascade,
  slug text not null,
  name text not null,
  state text not null default 'active' check (state in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, slug),
  constraint newsroom_publications_slug_not_blank check (length(btrim(slug)) > 0),
  constraint newsroom_publications_name_not_blank check (length(btrim(name)) > 0)
);

create table if not exists newsroom.workspace_memberships (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references newsroom.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  membership_state text not null default 'active' check (membership_state in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workspace_id, user_id)
);

create table if not exists newsroom.publication_memberships (
  publication_id uuid not null references newsroom.publications(id) on delete cascade,
  membership_id uuid not null references newsroom.workspace_memberships(id) on delete cascade,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (publication_id, membership_id)
);

create unique index if not exists newsroom_publication_memberships_one_default_uq
  on newsroom.publication_memberships (membership_id)
  where is_default;

create table if not exists newsroom.publication_domain_bindings (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null references newsroom.publications(id) on delete cascade,
  domain_key text not null,
  binding_kind text not null,
  external_ref text not null,
  state text not null default 'active' check (state in ('active', 'inactive')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (publication_id, domain_key, binding_kind),
  constraint newsroom_domain_key_not_blank check (length(btrim(domain_key)) > 0),
  constraint newsroom_binding_kind_not_blank check (length(btrim(binding_kind)) > 0),
  constraint newsroom_external_ref_not_blank check (length(btrim(external_ref)) > 0)
);

alter table newsroom.workspaces enable row level security;
alter table newsroom.publications enable row level security;
alter table newsroom.workspace_memberships enable row level security;
alter table newsroom.publication_memberships enable row level security;
alter table newsroom.publication_domain_bindings enable row level security;

revoke all on newsroom.workspaces from anon, authenticated;
revoke all on newsroom.publications from anon, authenticated;
revoke all on newsroom.workspace_memberships from anon, authenticated;
revoke all on newsroom.publication_memberships from anon, authenticated;
revoke all on newsroom.publication_domain_bindings from anon, authenticated;

insert into newsroom.workspaces (slug, name)
values ('forum', 'Forum Communications')
on conflict (slug) do update
set name = excluded.name,
    updated_at = now();

insert into newsroom.publications (workspace_id, slug, name)
select w.id, 'mitchell-republic', 'Mitchell Republic'
from newsroom.workspaces w
where w.slug = 'forum'
on conflict (workspace_id, slug) do update
set name = excluded.name,
    updated_at = now();

with transcript_workspace as (
  select id
  from transcript_core.workspaces
  where name = 'Forum / Mitchell Republic'
  order by created_at asc
  limit 1
), forum_workspace as (
  select id from newsroom.workspaces where slug = 'forum'
)
insert into newsroom.workspace_memberships (workspace_id, user_id)
select fw.id, twm.user_id
from forum_workspace fw
cross join transcript_workspace tw
join transcript_core.workspace_memberships twm on twm.workspace_id = tw.id
on conflict (workspace_id, user_id) do update
set membership_state = 'active',
    updated_at = now();

insert into newsroom.publication_memberships (publication_id, membership_id, is_default)
select p.id, wm.id, true
from newsroom.publications p
join newsroom.workspaces w on w.id = p.workspace_id and w.slug = 'forum'
join newsroom.workspace_memberships wm on wm.workspace_id = w.id and wm.membership_state = 'active'
where p.slug = 'mitchell-republic'
on conflict (publication_id, membership_id) do update
set is_default = true;

with transcript_workspace as (
  select id
  from transcript_core.workspaces
  where name = 'Forum / Mitchell Republic'
  order by created_at asc
  limit 1
)
insert into newsroom.publication_domain_bindings (
  publication_id,
  domain_key,
  binding_kind,
  external_ref,
  metadata
)
select p.id, 'transcript_core', 'workspace', tw.id::text,
       jsonb_build_object('bootstrap_source', 'transcript_core.workspace_memberships')
from newsroom.publications p
join newsroom.workspaces w on w.id = p.workspace_id and w.slug = 'forum'
cross join transcript_workspace tw
where p.slug = 'mitchell-republic'
on conflict (publication_id, domain_key, binding_kind) do update
set external_ref = excluded.external_ref,
    metadata = excluded.metadata,
    state = 'active',
    updated_at = now();

create or replace function public.newsroom_current_context_v1(
  p_workspace_slug text,
  p_publication_slug text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, newsroom
as $$
declare
  v_user_id uuid := auth.uid();
  v_workspace newsroom.workspaces%rowtype;
  v_membership newsroom.workspace_memberships%rowtype;
  v_publication newsroom.publications%rowtype;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'NEWSROOM_AUTH_REQUIRED';
  end if;

  select w.*
  into v_workspace
  from newsroom.workspaces w
  where w.slug = btrim(coalesce(p_workspace_slug, ''))
    and w.state = 'active';

  if v_workspace.id is null then
    raise exception 'NEWSROOM_WORKSPACE_NOT_FOUND';
  end if;

  select m.*
  into v_membership
  from newsroom.workspace_memberships m
  where m.workspace_id = v_workspace.id
    and m.user_id = v_user_id
    and m.membership_state = 'active';

  if v_membership.id is null then
    raise exception 'NEWSROOM_WORKSPACE_ACCESS_FORBIDDEN';
  end if;

  if nullif(btrim(coalesce(p_publication_slug, '')), '') is not null then
    select p.*
    into v_publication
    from newsroom.publications p
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = v_membership.id
    where p.workspace_id = v_workspace.id
      and p.slug = btrim(p_publication_slug)
      and p.state = 'active'
    limit 1;
  else
    select p.*
    into v_publication
    from newsroom.publications p
    join newsroom.publication_memberships pm
      on pm.publication_id = p.id
     and pm.membership_id = v_membership.id
    where p.workspace_id = v_workspace.id
      and p.state = 'active'
    order by pm.is_default desc, p.created_at asc
    limit 1;
  end if;

  if v_publication.id is null then
    raise exception 'NEWSROOM_PUBLICATION_ACCESS_FORBIDDEN';
  end if;

  select jsonb_build_object(
    'workspace', jsonb_build_object(
      'id', v_workspace.id,
      'slug', v_workspace.slug,
      'name', v_workspace.name
    ),
    'membership', jsonb_build_object(
      'id', v_membership.id,
      'state', v_membership.membership_state
    ),
    'publication', jsonb_build_object(
      'id', v_publication.id,
      'slug', v_publication.slug,
      'name', v_publication.name
    ),
    'publications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'slug', p.slug,
        'name', p.name,
        'isDefault', pm.is_default
      ) order by pm.is_default desc, p.name)
      from newsroom.publications p
      join newsroom.publication_memberships pm
        on pm.publication_id = p.id
       and pm.membership_id = v_membership.id
      where p.workspace_id = v_workspace.id
        and p.state = 'active'
    ), '[]'::jsonb),
    'domainBindings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'domainKey', b.domain_key,
        'bindingKind', b.binding_kind,
        'externalRef', b.external_ref,
        'metadata', b.metadata
      ) order by b.domain_key, b.binding_kind)
      from newsroom.publication_domain_bindings b
      where b.publication_id = v_publication.id
        and b.state = 'active'
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.newsroom_current_context_v1(text, text) from public, anon;
grant execute on function public.newsroom_current_context_v1(text, text) to authenticated;

comment on function public.newsroom_current_context_v1(text, text) is
  'Returns the authenticated member Newsroom workspace/publication context and bounded publication domain bindings. Does not replace domain-specific authorization.';