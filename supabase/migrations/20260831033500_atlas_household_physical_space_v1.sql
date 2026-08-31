-- Atlas Household Physical Space v1
-- Canonical dwelling and room/space topology. Floor topology does not determine Care meaning.

begin;

create table atlas.dwellings (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references atlas.households(id) on delete cascade,
  stable_key text not null,
  name text not null,
  dwelling_kind text not null default 'dwelling',
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint dwellings_stable_key_not_blank check (btrim(stable_key) <> ''),
  constraint dwellings_name_not_blank check (btrim(name) <> ''),
  constraint dwellings_kind_not_blank check (btrim(dwelling_kind) <> ''),
  constraint dwellings_household_stable_key_key unique (household_id, stable_key),
  constraint dwellings_id_household_key unique (id, household_id)
);

create index dwellings_household_active_idx
  on atlas.dwellings(household_id, active, created_at);

create trigger dwellings_set_updated_at
before update on atlas.dwellings
for each row execute function atlas.set_updated_at();

alter table atlas.dwellings enable row level security;

create policy dwellings_principal_read
on atlas.dwellings
for select
to authenticated
using (
  exists (
    select 1
    from atlas.households h
    join atlas.principals p on p.id = h.principal_id
    where h.id = dwellings.household_id
      and h.status = 'active'
      and p.status = 'active'
      and p.user_id = auth.uid()
  )
);

grant select on atlas.dwellings to authenticated;
grant select, insert, update, delete on atlas.dwellings to service_role;

create table atlas.household_spaces (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null,
  dwelling_id uuid not null,
  parent_space_id uuid,
  stable_key text not null,
  name text not null,
  space_type text not null,
  functional_tags text[] not null default '{}'::text[],
  floor_level text,
  care_relevant boolean not null default true,
  active boolean not null default true,
  source_kind text not null default 'principal_authoring',
  confidence text not null default 'confirmed',
  confirmed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint household_spaces_stable_key_not_blank check (btrim(stable_key) <> ''),
  constraint household_spaces_name_not_blank check (btrim(name) <> ''),
  constraint household_spaces_type_not_blank check (btrim(space_type) <> ''),
  constraint household_spaces_source_not_blank check (btrim(source_kind) <> ''),
  constraint household_spaces_confidence_check check (confidence in ('candidate', 'confirmed')),
  constraint household_spaces_confirmation_check check (
    (confidence = 'candidate' and confirmed_at is null)
    or (confidence = 'confirmed' and confirmed_at is not null)
  ),
  constraint household_spaces_dwelling_stable_key_key unique (dwelling_id, stable_key),
  constraint household_spaces_id_dwelling_household_key unique (id, dwelling_id, household_id),
  constraint household_spaces_dwelling_household_fkey
    foreign key (dwelling_id, household_id)
    references atlas.dwellings(id, household_id)
    on delete cascade,
  constraint household_spaces_parent_same_dwelling_fkey
    foreign key (parent_space_id, dwelling_id, household_id)
    references atlas.household_spaces(id, dwelling_id, household_id)
    on delete restrict
);

create index household_spaces_household_active_idx
  on atlas.household_spaces(household_id, active, care_relevant);
create index household_spaces_dwelling_parent_idx
  on atlas.household_spaces(dwelling_id, parent_space_id, active);
create index household_spaces_functional_tags_gin
  on atlas.household_spaces using gin(functional_tags);

create trigger household_spaces_set_updated_at
before update on atlas.household_spaces
for each row execute function atlas.set_updated_at();

create or replace function atlas.household_space_parent_acyclic_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
begin
  if new.parent_space_id is null then
    return new;
  end if;

  if new.parent_space_id = new.id then
    raise exception 'A household space cannot be its own parent.' using errcode = '23514';
  end if;

  if exists (
    with recursive ancestors as (
      select s.id, s.parent_space_id
      from atlas.household_spaces s
      where s.id = new.parent_space_id
        and s.dwelling_id = new.dwelling_id
        and s.household_id = new.household_id
      union all
      select s.id, s.parent_space_id
      from atlas.household_spaces s
      join ancestors a on a.parent_space_id = s.id
      where s.dwelling_id = new.dwelling_id
        and s.household_id = new.household_id
    )
    select 1
    from ancestors
    where id = new.id
  ) then
    raise exception 'Household space parentage cannot contain a cycle.' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function atlas.household_space_parent_acyclic_v1() from public, anon, authenticated;

create trigger household_spaces_parent_acyclic
before insert or update of parent_space_id, dwelling_id, household_id on atlas.household_spaces
for each row execute function atlas.household_space_parent_acyclic_v1();

alter table atlas.household_spaces enable row level security;

create policy household_spaces_principal_read
on atlas.household_spaces
for select
to authenticated
using (
  exists (
    select 1
    from atlas.households h
    join atlas.principals p on p.id = h.principal_id
    where h.id = household_spaces.household_id
      and h.status = 'active'
      and p.status = 'active'
      and p.user_id = auth.uid()
  )
);

grant select on atlas.household_spaces to authenticated;
grant select, insert, update, delete on atlas.household_spaces to service_role;

commit;
