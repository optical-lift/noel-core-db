begin;

-- Atlas Institutional Person Record v1
--
-- Governing boundary:
--   Person != auth credential != Institutional Person Record != Organization Membership
--   != Position Appointment != Employee Seat != Responsibility.
--
-- This migration makes "this institution knows this human" durable without
-- requiring auth.users. Existing membership-rooted rows remain valid compatibility
-- carriers and are bridged in place; no login, responsibility, role, permission,
-- or work is manufactured by the record itself.

create table atlas.institutional_person_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  person_id uuid not null references atlas.people(id) on delete restrict,
  identity_subject_id uuid references atlas.identity_subjects(id) on delete restrict,
  status text not null default 'active'
    check (status in ('active','retired')),
  establishment_basis jsonb not null default '{}'::jsonb
    check (jsonb_typeof(establishment_basis)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,person_id),
  unique (organization_id,id)
);

create unique index institutional_person_records_org_subject_uq
  on atlas.institutional_person_records(organization_id,identity_subject_id)
  where identity_subject_id is not null;

create index institutional_person_records_person_status_idx
  on atlas.institutional_person_records(person_id,status,organization_id);

comment on table atlas.institutional_person_records is
  'Durable Organization-scoped record that a canonical Person is known in institutional reality. It does not imply login, Organization Membership, Position, employee status, seat, responsibility, authority, permission, or delivery access.';

comment on column atlas.institutional_person_records.identity_subject_id is
  'Optional Organization-scoped reconciliation anchor. Canonical Person + Organization establishes the Institutional Person Record; Identity Subject is supporting identity evidence and is not required for a human to exist institutionally.';

alter table atlas.institutional_person_records enable row level security;
revoke all on table atlas.institutional_person_records from public,anon,authenticated;

create or replace function atlas.guard_institutional_person_record_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_subject_org uuid;
begin
  if new.status='active'
     and not exists(
       select 1 from atlas.people p
       where p.id=new.person_id and p.status='active'
     ) then
    raise exception 'Active Institutional Person Record requires an active canonical Person.'
      using errcode='23514';
  end if;

  if new.identity_subject_id is not null then
    select s.organization_id into v_subject_org
    from atlas.identity_subjects s
    where s.id=new.identity_subject_id;

    if v_subject_org is null or v_subject_org<>new.organization_id then
      raise exception 'Institutional Person identity subject must belong to the same Organization.'
        using errcode='23514';
    end if;

    if exists(
      select 1
      from atlas.identity_subject_projections p
      where p.subject_id=new.identity_subject_id
        and p.organization_id=new.organization_id
        and p.subject_kind<>'person'
    ) then
      raise exception 'Institutional Person identity subject is explicitly classified as non-person.'
        using errcode='23514';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end;
$function$;

revoke all on function atlas.guard_institutional_person_record_v1() from public,anon,authenticated,service_role;

create trigger institutional_person_record_guard_v1
before insert or update of organization_id,person_id,identity_subject_id,status
on atlas.institutional_person_records
for each row execute function atlas.guard_institutional_person_record_v1();

alter table atlas.organization_memberships
  add column institutional_person_record_id uuid;

alter table atlas.organization_position_appointments
  add column institutional_person_record_id uuid;

alter table atlas.organization_employee_seats
  add column institutional_person_record_id uuid;

alter table atlas.work_allocations
  add column assignee_institutional_person_record_id uuid,
  add column assigned_by_institutional_person_record_id uuid;

alter table atlas.work_execution_results
  add column reported_by_institutional_person_record_id uuid;

-- Existing authenticated memberships are high-confidence evidence that the
-- canonical Person is already known to the Organization. Backfill without
-- requiring an Identity Subject where none exists.
insert into atlas.institutional_person_records(
  organization_id,person_id,identity_subject_id,status,establishment_basis
)
select
  m.organization_id,
  m.person_id,
  m.identity_subject_id,
  'active',
  jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','institutional_person_record_v1',
    'basisKind','existing_organization_membership_bridge',
    'organizationMembershipId',m.id,
    'bridgedAt',now()
  ))
from atlas.organization_memberships m
where m.person_id is not null
on conflict (organization_id,person_id)
do update set
  identity_subject_id=coalesce(
    atlas.institutional_person_records.identity_subject_id,
    excluded.identity_subject_id
  ),
  updated_at=now();

update atlas.organization_memberships m
set institutional_person_record_id=ipr.id,
    updated_at=now()
from atlas.institutional_person_records ipr
where ipr.organization_id=m.organization_id
  and ipr.person_id=m.person_id
  and m.institutional_person_record_id is distinct from ipr.id;

update atlas.organization_position_appointments a
set institutional_person_record_id=m.institutional_person_record_id,
    updated_at=now()
from atlas.organization_memberships m
where m.id=a.organization_membership_id
  and m.organization_id=a.organization_id
  and m.institutional_person_record_id is not null
  and a.institutional_person_record_id is distinct from m.institutional_person_record_id;

update atlas.organization_employee_seats s
set institutional_person_record_id=m.institutional_person_record_id,
    updated_at=now()
from atlas.organization_memberships m
where m.id=s.organization_membership_id
  and m.organization_id=s.organization_id
  and m.institutional_person_record_id is not null
  and s.institutional_person_record_id is distinct from m.institutional_person_record_id;

update atlas.work_allocations wa
set assignee_institutional_person_record_id=assignee.institutional_person_record_id,
    assigned_by_institutional_person_record_id=(
      select assigner.institutional_person_record_id
      from atlas.organization_memberships assigner
      where assigner.id=wa.assigned_by_membership_id
        and assigner.organization_id=wa.organization_id
    ),
    updated_at=now()
from atlas.organization_memberships assignee
where assignee.id=wa.assignee_membership_id
  and assignee.organization_id=wa.organization_id
  and assignee.institutional_person_record_id is not null;

update atlas.work_execution_results r
set reported_by_institutional_person_record_id=m.institutional_person_record_id
from atlas.organization_memberships m
where m.id=r.reported_by_organization_membership_id
  and m.organization_id=r.organization_id
  and m.institutional_person_record_id is not null
  and r.reported_by_institutional_person_record_id is distinct from m.institutional_person_record_id;

do $backfill_guard$
begin
  if exists(
    select 1
    from atlas.organization_memberships m
    where m.person_id is not null
      and m.institutional_person_record_id is null
  ) then
    raise exception 'Institutional Person bridge failed for an existing Organization Membership.';
  end if;

  if exists(
    select 1
    from atlas.organization_position_appointments a
    where a.organization_membership_id is not null
      and a.institutional_person_record_id is null
  ) then
    raise exception 'Institutional Person bridge failed for an existing Position Appointment.';
  end if;

  if exists(
    select 1
    from atlas.organization_employee_seats s
    where s.organization_membership_id is not null
      and s.institutional_person_record_id is null
  ) then
    raise exception 'Institutional Person bridge failed for an existing employee seat.';
  end if;

  if exists(
    select 1
    from atlas.work_allocations wa
    where wa.assignee_membership_id is not null
      and wa.assignee_institutional_person_record_id is null
  ) then
    raise exception 'Institutional Person bridge failed for an existing Work allocation.';
  end if;
end;
$backfill_guard$;

alter table atlas.organization_memberships
  add constraint organization_memberships_institutional_person_org_fk
  foreign key (organization_id,institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete restrict;

alter table atlas.organization_position_appointments
  add constraint organization_position_appointments_institutional_person_org_fk
  foreign key (organization_id,institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete restrict;

alter table atlas.organization_employee_seats
  add constraint organization_employee_seats_institutional_person_org_fk
  foreign key (organization_id,institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete restrict;

alter table atlas.work_allocations
  add constraint work_allocations_assignee_institutional_person_org_fk
  foreign key (organization_id,assignee_institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete restrict,
  add constraint work_allocations_assigner_institutional_person_org_fk
  foreign key (organization_id,assigned_by_institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete restrict;

alter table atlas.work_execution_results
  add constraint work_execution_results_reported_by_institutional_person_org_fk
  foreign key (organization_id,reported_by_institutional_person_record_id)
  references atlas.institutional_person_records(organization_id,id)
  on delete set null;

create index organization_memberships_institutional_person_idx
  on atlas.organization_memberships(institutional_person_record_id,active);

create index work_allocations_assignee_institutional_person_idx
  on atlas.work_allocations(assignee_institutional_person_record_id,state,allocation_role);

create index work_execution_results_reported_by_institutional_person_idx
  on atlas.work_execution_results(reported_by_institutional_person_record_id,reported_at desc);

-- Position and employee-seat truth may now exist for an institutional human
-- without manufacturing auth.users or Organization Membership.
alter table atlas.organization_position_appointments
  alter column organization_membership_id drop not null,
  alter column identity_subject_id drop not null,
  alter column institutional_person_record_id set not null;

alter table atlas.organization_employee_seats
  alter column organization_membership_id drop not null,
  alter column identity_subject_id drop not null,
  alter column institutional_person_record_id set not null;

alter table atlas.organization_employee_seats
  drop constraint organization_employee_seats_subject_membership_match;

alter table atlas.organization_employee_seats
  add constraint organization_employee_seats_institutional_person_required
  check (institutional_person_record_id is not null);

create unique index organization_employee_seats_institutional_person_uq
  on atlas.organization_employee_seats(organization_id,institutional_person_record_id);

create unique index organization_position_appointments_active_institutional_person_position_uq
  on atlas.organization_position_appointments(position_id,institutional_person_record_id)
  where status='active' and ends_at is null;

comment on column atlas.organization_memberships.institutional_person_record_id is
  'Compatibility bridge from authenticated Organization Membership to the durable Institutional Person Record. Membership remains an access/participation carrier, not human identity.';

comment on column atlas.organization_position_appointments.institutional_person_record_id is
  'Canonical institutional human target for this Position Appointment. Organization Membership and Identity Subject are compatibility/supporting carriers and may be absent.';

comment on column atlas.organization_employee_seats.institutional_person_record_id is
  'Canonical institutional human target for this Organization-paid employee seat. The seat purchases product access/delivery capacity; it does not create responsibility or a Personal Atlas.';

comment on column atlas.work_allocations.assignee_institutional_person_record_id is
  'Additive canonical-human bridge for exact Company Work responsibility. Membership remains required by the current v2 responsibility writer until the dedicated convergence migration replaces that execution contract.';

comment on column atlas.work_execution_results.reported_by_institutional_person_record_id is
  'Canonical institutional-human attribution for a reported Work result when known. Auth user and membership IDs are supporting credential/relationship provenance, not the only possible actor identity.';

create or replace function atlas.guard_institutional_person_appointment_bridge_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_record atlas.institutional_person_records%rowtype;
  v_membership_record uuid;
begin
  select * into v_record
  from atlas.institutional_person_records ipr
  where ipr.id=new.institutional_person_record_id
    and ipr.organization_id=new.organization_id;

  if v_record.id is null or v_record.status<>'active' then
    raise exception 'Active Position Appointment requires an active Institutional Person Record in the same Organization.'
      using errcode='23514';
  end if;

  if new.organization_membership_id is not null then
    select m.institutional_person_record_id into v_membership_record
    from atlas.organization_memberships m
    where m.id=new.organization_membership_id
      and m.organization_id=new.organization_id;

    if v_membership_record is distinct from new.institutional_person_record_id then
      raise exception 'Position Appointment membership and Institutional Person Record identify different institutional humans.'
        using errcode='23514';
    end if;
  end if;

  if new.identity_subject_id is not null
     and v_record.identity_subject_id is not null
     and new.identity_subject_id<>v_record.identity_subject_id then
    raise exception 'Position Appointment identity subject conflicts with the Institutional Person Record.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_institutional_person_appointment_bridge_v1()
  from public,anon,authenticated,service_role;

create trigger institutional_person_appointment_bridge_guard_v1
before insert or update of organization_id,organization_membership_id,identity_subject_id,institutional_person_record_id,status
on atlas.organization_position_appointments
for each row execute function atlas.guard_institutional_person_appointment_bridge_v1();

create or replace function atlas.guard_institutional_person_seat_bridge_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_record atlas.institutional_person_records%rowtype;
  v_membership_record uuid;
begin
  select * into v_record
  from atlas.institutional_person_records ipr
  where ipr.id=new.institutional_person_record_id
    and ipr.organization_id=new.organization_id;

  if v_record.id is null then
    raise exception 'Employee seat requires an Institutional Person Record in the same Organization.'
      using errcode='23514';
  end if;

  if new.status='active' and v_record.status<>'active' then
    raise exception 'Active employee seat requires an active Institutional Person Record.'
      using errcode='23514';
  end if;

  if new.organization_membership_id is not null then
    select m.institutional_person_record_id into v_membership_record
    from atlas.organization_memberships m
    where m.id=new.organization_membership_id
      and m.organization_id=new.organization_id;

    if v_membership_record is distinct from new.institutional_person_record_id then
      raise exception 'Employee seat membership and Institutional Person Record identify different institutional humans.'
        using errcode='23514';
    end if;
  end if;

  if new.identity_subject_id is not null
     and v_record.identity_subject_id is not null
     and new.identity_subject_id<>v_record.identity_subject_id then
    raise exception 'Employee seat identity subject conflicts with the Institutional Person Record.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_institutional_person_seat_bridge_v1()
  from public,anon,authenticated,service_role;

create trigger institutional_person_seat_bridge_guard_v1
before insert or update of organization_id,organization_membership_id,identity_subject_id,institutional_person_record_id,status
on atlas.organization_employee_seats
for each row execute function atlas.guard_institutional_person_seat_bridge_v1();

-- Keep newly-created authenticated memberships bridged without changing their
-- existing authentication semantics.
create or replace function atlas.bridge_organization_membership_to_institutional_person_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_record atlas.institutional_person_records%rowtype;
begin
  if new.person_id is null then
    return null;
  end if;

  select * into v_record
  from atlas.institutional_person_records ipr
  where ipr.organization_id=new.organization_id
    and ipr.person_id=new.person_id
  for update;

  if v_record.id is null then
    insert into atlas.institutional_person_records(
      organization_id,person_id,identity_subject_id,status,establishment_basis
    ) values(
      new.organization_id,
      new.person_id,
      new.identity_subject_id,
      'active',
      jsonb_strip_nulls(jsonb_build_object(
        'contractVersion','institutional_person_record_v1',
        'basisKind','organization_membership_compatibility',
        'organizationMembershipId',new.id,
        'establishedAt',now()
      ))
    )
    returning * into v_record;
  elsif new.identity_subject_id is not null then
    if v_record.identity_subject_id is null then
      update atlas.institutional_person_records
      set identity_subject_id=new.identity_subject_id,
          updated_at=now()
      where id=v_record.id
      returning * into v_record;
    elsif v_record.identity_subject_id<>new.identity_subject_id then
      raise exception 'Organization Membership identity subject conflicts with its Institutional Person Record.'
        using errcode='23514';
    end if;
  end if;

  update atlas.organization_memberships m
  set institutional_person_record_id=v_record.id,
      updated_at=now()
  where m.id=new.id
    and m.institutional_person_record_id is distinct from v_record.id;

  return null;
end;
$function$;

revoke all on function atlas.bridge_organization_membership_to_institutional_person_v1()
  from public,anon,authenticated,service_role;

create trigger organization_membership_institutional_person_bridge_v1
after insert or update of organization_id,person_id,identity_subject_id
on atlas.organization_memberships
for each row execute function atlas.bridge_organization_membership_to_institutional_person_v1();

insert into atlas.architecture_truth_authorities(
  authority_key,
  domain_key,
  truth_question,
  authority_owner,
  authority_status,
  canonical_relations,
  canonical_functions,
  supporting_relations,
  consumer_surfaces,
  known_competitors,
  source_custody,
  rationale
) values (
  'institutional_person_record',
  'identity',
  'Which canonical human is durably known in this Organization independent of whether that human has an Atlas credential or Organization Membership?',
  'atlas.institutional_person_records',
  'canonical',
  array['atlas.people','atlas.institutional_person_records'],
  array[]::text[],
  array[
    'atlas.identity_subjects',
    'atlas.organization_memberships',
    'atlas.organization_position_appointments',
    'atlas.organization_employee_seats',
    'atlas.work_allocations',
    'atlas.work_execution_results'
  ],
  array[
    'People & Authority',
    'Position Appointment',
    'employee-seat access',
    'future relationship-scoped delivery',
    'future non-account Worker delivery'
  ],
  array[
    'auth.users treated as institutional human identity',
    'organization_memberships treated as required institutional human existence',
    'organization_employee_seats treated as human identity',
    'identity_subjects treated as the only canonical Person root'
  ],
  'optical-lift/noel-core-db:supabase/migrations/20260921150000_atlas_institutional_person_record_v1.sql',
  'Canonical Person is global human identity. Institutional Person Record is the Organization-scoped fact that this Person is known to the institution. Authentication, membership, position, commercial seat, exact Work responsibility, authority, permission, and delivery remain separate relationships or consequences.'
)
on conflict (authority_key)
do update set
  domain_key=excluded.domain_key,
  truth_question=excluded.truth_question,
  authority_owner=excluded.authority_owner,
  authority_status=excluded.authority_status,
  canonical_relations=excluded.canonical_relations,
  canonical_functions=excluded.canonical_functions,
  supporting_relations=excluded.supporting_relations,
  consumer_surfaces=excluded.consumer_surfaces,
  known_competitors=excluded.known_competitors,
  source_custody=excluded.source_custody,
  rationale=excluded.rationale,
  updated_at=now();

do $security_guard$
begin
  if has_table_privilege('anon','atlas.institutional_person_records','SELECT')
     or has_table_privilege('authenticated','atlas.institutional_person_records','SELECT')
     or has_table_privilege('anon','atlas.institutional_person_records','INSERT')
     or has_table_privilege('authenticated','atlas.institutional_person_records','INSERT') then
    raise exception 'Institutional Person Record table must not become a direct browser authority.';
  end if;
end;
$security_guard$;

commit;
