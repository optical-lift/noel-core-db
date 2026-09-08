begin;

-- Atlas universal organization structure v1
-- Separates institutional structure from portfolio and domain reality.
-- Organization employee seats remain organization-wide billing/access objects.
-- Positions and appointments establish institutional placement inside organization units.

create table atlas.organization_positions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid not null,
  stable_key text not null,
  display_title text not null,
  position_kind text not null default 'staff',
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_positions_stable_key_nonblank check (btrim(stable_key) <> ''),
  constraint organization_positions_display_title_nonblank check (btrim(display_title) <> ''),
  constraint organization_positions_kind_nonblank check (btrim(position_kind) <> ''),
  constraint organization_positions_unit_org_fk
    foreign key (organization_id, organization_unit_id)
    references atlas.organization_units(organization_id, id)
    on delete restrict,
  constraint organization_positions_org_unit_key_uq
    unique (organization_id, organization_unit_id, stable_key)
);

comment on table atlas.organization_positions is
  'Persistent institutional positions inside generic organization units. Titles are organization language; authority and responsibility are separate.';

create table atlas.organization_position_appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  position_id uuid not null references atlas.organization_positions(id) on delete restrict,
  identity_subject_id uuid not null references atlas.identity_subjects(id) on delete restrict,
  organization_membership_id uuid not null references atlas.organization_memberships(id) on delete restrict,
  appointment_kind text not null default 'primary',
  status text not null default 'active' check (status in ('active','inactive','ended')),
  begins_at timestamptz not null default now(),
  ends_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_position_appointments_kind_nonblank check (btrim(appointment_kind) <> ''),
  constraint organization_position_appointments_window_check check (ends_at is null or ends_at >= begins_at)
);

create unique index organization_position_appointments_active_person_position_uq
  on atlas.organization_position_appointments(position_id, identity_subject_id)
  where status = 'active' and ends_at is null;

comment on table atlas.organization_position_appointments is
  'Time-bounded occupancy of an institutional position by an identity subject. Appointment, membership, billing seat, authority, and exposure remain distinct.';

create table atlas.organization_responsibilities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  stable_key text not null,
  name text not null,
  responsibility_kind text not null default 'stewardship',
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_responsibilities_key_nonblank check (btrim(stable_key) <> ''),
  constraint organization_responsibilities_name_nonblank check (btrim(name) <> ''),
  constraint organization_responsibilities_kind_nonblank check (btrim(responsibility_kind) <> ''),
  constraint organization_responsibilities_org_key_uq unique (organization_id, stable_key)
);

comment on table atlas.organization_responsibilities is
  'Reusable institutional responsibilities. A responsibility describes what a position stewards; domain-specific reality is linked separately through scopes.';

create table atlas.organization_position_responsibilities (
  position_id uuid not null references atlas.organization_positions(id) on delete cascade,
  responsibility_id uuid not null references atlas.organization_responsibilities(id) on delete cascade,
  relationship_kind text not null default 'accountable',
  created_at timestamptz not null default now(),
  primary key (position_id, responsibility_id),
  constraint organization_position_responsibilities_kind_nonblank check (btrim(relationship_kind) <> '')
);

create table atlas.organization_responsibility_scopes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  responsibility_id uuid not null references atlas.organization_responsibilities(id) on delete cascade,
  scope_kind text not null,
  scope_id text not null,
  relation_kind text not null default 'stewards',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint organization_responsibility_scopes_kind_nonblank check (btrim(scope_kind) <> ''),
  constraint organization_responsibility_scopes_id_nonblank check (btrim(scope_id) <> ''),
  constraint organization_responsibility_scopes_relation_nonblank check (btrim(relation_kind) <> ''),
  constraint organization_responsibility_scopes_identity_uq
    unique (organization_id, responsibility_id, scope_kind, scope_id, relation_kind)
);

comment on table atlas.organization_responsibility_scopes is
  'Typed links from institutional responsibilities to the organization units or domain realities they govern. This avoids putting farm/customer/order/etc. columns on positions.';

alter table atlas.organization_positions enable row level security;
alter table atlas.organization_position_appointments enable row level security;
alter table atlas.organization_responsibilities enable row level security;
alter table atlas.organization_position_responsibilities enable row level security;
alter table atlas.organization_responsibility_scopes enable row level security;

revoke all on table atlas.organization_positions from public, anon, authenticated;
revoke all on table atlas.organization_position_appointments from public, anon, authenticated;
revoke all on table atlas.organization_responsibilities from public, anon, authenticated;
revoke all on table atlas.organization_position_responsibilities from public, anon, authenticated;
revoke all on table atlas.organization_responsibility_scopes from public, anon, authenticated;

do $migration$
declare
  v_org_id uuid;
  v_unit_id uuid;
  v_portfolio_id uuid;
  v_farm_id uuid;
  v_anna_subject_id uuid;
  v_anna_membership_id uuid;
  v_position_id uuid;
begin
  select id into strict v_org_id
  from atlas.organizations
  where stable_key = 'feast_guild';

  select id into strict v_unit_id
  from atlas.organization_units
  where organization_id = v_org_id
    and stable_key = 'elm_farm';

  select id into strict v_portfolio_id
  from atlas.portfolio_units
  where organization_id = v_org_id
    and stable_key = 'elm';

  select id into strict v_farm_id
  from atlas.farms
  where organization_id = v_org_id
    and stable_key = 'elm_farm';

  -- Make the institutional node generic. The physical/domain record remains Elm Farm.
  update atlas.organization_units
  set stable_key = 'elm',
      name = 'Elm',
      unit_kind = 'operating_business',
      metadata = jsonb_strip_nulls(
        (metadata - 'farm_id' - 'domain_adapter') ||
        jsonb_build_object(
          'institutional_model','organization_unit_v1',
          'legacy_stable_key','elm_farm'
        )
      ),
      updated_at = now()
  where id = v_unit_id;

  -- Portfolio expresses the Principal's venture view, not the employee's place in the institution.
  update atlas.portfolio_units
  set unit_kind = 'venture',
      organization_unit_id = v_unit_id,
      metadata = metadata || jsonb_build_object(
        'institutional_model','portfolio_projection_v1',
        'domain_kind','farm'
      ),
      updated_at = now()
  where id = v_portfolio_id;

  -- Domain reality remains domain-specific and points back to the generic institutional unit.
  update atlas.farms
  set organization_unit_id = v_unit_id,
      metadata = metadata || jsonb_build_object(
        'institutional_relation','operated_by_organization_unit',
        'organization_unit_stable_key','elm'
      ),
      updated_at = now()
  where id = v_farm_id;

  select identity_subject_id, id
    into strict v_anna_subject_id, v_anna_membership_id
  from atlas.organization_memberships
  where organization_id = v_org_id
    and user_id = '21436a28-40fd-4914-8015-a248d0dca14e'::uuid;

  if v_anna_subject_id is null then
    raise exception 'Anna institutional identity subject is required before organization appointment migration.';
  end if;

  insert into atlas.organization_positions (
    organization_id, organization_unit_id, stable_key, display_title, position_kind, metadata
  ) values (
    v_org_id, v_unit_id, 'operations_steward', 'Farm Steward', 'operations',
    jsonb_build_object('display_title_is_organization_language', true)
  )
  on conflict (organization_id, organization_unit_id, stable_key)
  do update set display_title = excluded.display_title,
                position_kind = excluded.position_kind,
                status = 'active',
                metadata = excluded.metadata,
                updated_at = now()
  returning id into v_position_id;

  insert into atlas.organization_position_appointments (
    organization_id, position_id, identity_subject_id, organization_membership_id,
    appointment_kind, status, metadata
  ) values (
    v_org_id, v_position_id, v_anna_subject_id, v_anna_membership_id,
    'primary', 'active', jsonb_build_object('migration','universal_organization_structure_v1')
  )
  on conflict (position_id, identity_subject_id) where status = 'active' and ends_at is null
  do update set organization_membership_id = excluded.organization_membership_id,
                appointment_kind = excluded.appointment_kind,
                metadata = excluded.metadata,
                updated_at = now();

  -- Responsibilities carry institutional meaning; domain nouns stay in typed scope links.
  insert into atlas.organization_responsibilities
    (organization_id, stable_key, name, responsibility_kind)
  values
    (v_org_id, 'production_stewardship', 'Production stewardship', 'stewardship'),
    (v_org_id, 'harvest_execution', 'Harvest execution', 'execution'),
    (v_org_id, 'nursery_care', 'Nursery care', 'stewardship'),
    (v_org_id, 'grounds_readiness', 'Grounds readiness', 'stewardship'),
    (v_org_id, 'venue_preparation', 'Venue preparation', 'execution')
  on conflict (organization_id, stable_key)
  do update set name = excluded.name,
                responsibility_kind = excluded.responsibility_kind,
                status = 'active',
                updated_at = now();

  insert into atlas.organization_position_responsibilities(position_id, responsibility_id, relationship_kind)
  select v_position_id, r.id, 'accountable'
  from atlas.organization_responsibilities r
  where r.organization_id = v_org_id
    and r.stable_key in (
      'production_stewardship','harvest_execution','nursery_care','grounds_readiness','venue_preparation'
    )
  on conflict (position_id, responsibility_id)
  do update set relationship_kind = excluded.relationship_kind;

  -- Every seeded responsibility is currently bounded to the Elm institutional operating unit.
  insert into atlas.organization_responsibility_scopes(
    organization_id, responsibility_id, scope_kind, scope_id, relation_kind
  )
  select v_org_id, r.id, 'organization_unit', v_unit_id::text, 'stewards'
  from atlas.organization_responsibilities r
  where r.organization_id = v_org_id
    and r.stable_key in (
      'production_stewardship','harvest_execution','nursery_care','grounds_readiness','venue_preparation'
    )
  on conflict (organization_id, responsibility_id, scope_kind, scope_id, relation_kind)
  do nothing;
end;
$migration$;

create or replace function atlas.organization_employee_appointments_by_auth_user_v1(
  p_auth_user_id uuid,
  p_organization_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, atlas
as $function$
  with employee as (
    select c.id as credential_id,
           s.id as employee_seat_id,
           s.organization_id,
           s.organization_membership_id,
           s.identity_subject_id
    from atlas.organization_member_credentials c
    join atlas.organization_employee_seats s
      on s.id = c.employee_seat_id
    join atlas.organization_memberships m
      on m.id = s.organization_membership_id
     and m.organization_id = s.organization_id
     and m.identity_subject_id = s.identity_subject_id
    where c.auth_user_id = p_auth_user_id
      and c.status = 'active'
      and s.status = 'active'
      and s.billing_state in ('active','waived')
      and m.active = true
      and (p_organization_id is null or s.organization_id = p_organization_id)
  ), appts as (
    select e.*, a.id as appointment_id,
           a.appointment_kind,
           p.id as position_id,
           p.stable_key as position_key,
           p.display_title,
           p.position_kind,
           p.organization_unit_id,
           u.stable_key as organization_unit_key,
           u.name as organization_unit_name,
           u.unit_kind as organization_unit_kind
    from employee e
    join atlas.organization_position_appointments a
      on a.organization_id = e.organization_id
     and a.organization_membership_id = e.organization_membership_id
     and a.identity_subject_id = e.identity_subject_id
     and a.status = 'active'
     and a.begins_at <= now()
     and (a.ends_at is null or a.ends_at > now())
    join atlas.organization_positions p
      on p.id = a.position_id
     and p.organization_id = e.organization_id
     and p.status = 'active'
    join atlas.organization_units u
      on u.id = p.organization_unit_id
     and u.organization_id = e.organization_id
     and u.status = 'active'
  )
  select jsonb_build_object(
    'ok', true,
    'contractVersion','organization_employee_appointments_by_auth_user_v1',
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'credentialId',credential_id,
      'employeeSeatId',employee_seat_id,
      'organizationId',organization_id,
      'organizationMembershipId',organization_membership_id,
      'identitySubjectId',identity_subject_id,
      'appointmentId',appointment_id,
      'appointmentKind',appointment_kind,
      'positionId',position_id,
      'positionKey',position_key,
      'displayTitle',display_title,
      'positionKind',position_kind,
      'organizationUnitId',organization_unit_id,
      'organizationUnitKey',organization_unit_key,
      'organizationUnitName',organization_unit_name,
      'organizationUnitKind',organization_unit_kind
    ) order by appointment_kind, position_key), '[]'::jsonb)
  )
  from appts;
$function$;

revoke all on function atlas.organization_employee_appointments_by_auth_user_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.organization_employee_appointments_by_auth_user_v1(uuid,uuid) to postgres, service_role;

commit;
