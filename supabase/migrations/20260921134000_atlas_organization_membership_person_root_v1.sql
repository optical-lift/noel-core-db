-- Atlas Organization Membership Person Root v1.
-- Makes canonical Person, rather than auth.users, the required durable
-- Person↔Organization relationship root while preserving authenticated
-- compatibility and existing application access paths.

BEGIN;

do $precondition$
begin
  if exists (
    select 1
    from atlas.organization_memberships m
    where m.person_id is null
  ) then
    raise exception 'Organization Membership Person-root cutover requires every existing membership to have person_id.';
  end if;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid='atlas.organization_memberships'::regclass
      and c.conname='organization_memberships_user_id_fkey'
      and c.contype='f'
  ) then
    raise exception 'Expected organization_memberships_user_id_fkey is missing.';
  end if;

  if not exists (
    select 1
    from pg_indexes i
    where i.schemaname='atlas'
      and i.tablename='organization_memberships'
      and i.indexname='organization_memberships_organization_person_uq'
  ) then
    raise exception 'Canonical Organization Membership Person uniqueness is missing.';
  end if;
end;
$precondition$;

-- Person is now the durable relationship identity. A credential may be absent.
alter table atlas.organization_memberships
  alter column person_id set not null,
  alter column user_id drop not null;

-- Authentication is compatibility/access evidence, not relationship custody.
-- Deleting an auth credential must not erase the Person↔Organization relation.
alter table atlas.organization_memberships
  drop constraint organization_memberships_user_id_fkey;

alter table atlas.organization_memberships
  add constraint organization_memberships_user_id_fkey
  foreign key (user_id)
  references auth.users(id)
  on delete set null;

comment on column atlas.organization_memberships.person_id is
  'Canonical Person who holds this durable Person↔Organization relationship. Required independently of authentication credentials.';

comment on column atlas.organization_memberships.user_id is
  'Optional legacy/authentication compatibility carrier. Access credentials may resolve to this membership, but auth.users does not own the relationship and credential deletion must not delete it.';

do $postcondition$
begin
  if exists (
    select 1
    from atlas.organization_memberships m
    where m.person_id is null
  ) then
    raise exception 'Organization Membership Person root is incomplete.';
  end if;

  if exists (
    select 1
    from atlas.organization_memberships m
    join atlas.person_auth_credentials c
      on c.auth_user_id=m.user_id
     and c.status='active'
    where m.user_id is not null
      and c.person_id is distinct from m.person_id
  ) then
    raise exception 'Organization Membership credential/Person compatibility was broken.';
  end if;
end;
$postcondition$;

COMMIT;
