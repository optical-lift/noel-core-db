-- Organization Membership Calendar Context v1 candidate.
-- Effective Time Phase A only.
-- Candidate source only. Promote to supabase/migrations only with a Supabase-generated migration identity.

begin;

do $precondition$
declare
  v_elm uuid;
begin
  if to_regclass('atlas.organization_membership_calendar_contexts') is not null then
    raise exception 'Organization Membership Calendar Context already exists; reconcile source before applying candidate.'
      using errcode='55000';
  end if;

  select o.id into v_elm
  from atlas.organizations o
  where o.stable_key='elm_farm';

  if v_elm is null then
    raise exception 'Expected exactly one Elm Farm Organization for audited compatibility adjudication.'
      using errcode='55000';
  end if;

  if not exists(
    select 1
    from atlas.organization_memberships m
    where m.organization_id=v_elm
      and m.active
      and (m.eligibility_begins_on is not null or m.eligibility_ends_on is not null)
  ) then
    raise exception 'Audited Elm Farm bounded Membership state changed; adjudicate before promotion.'
      using errcode='55000';
  end if;
end;
$precondition$;

create table atlas.organization_membership_calendar_contexts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references atlas.organizations(id) on delete restrict,
  timezone_name text not null
    check (btrim(timezone_name)<>''),
  context_state text not null default 'active'
    check (context_state in ('active','superseded')),
  basis_kind text not null
    check (
      basis_kind in (
        'organization_setup_actor_declaration',
        'principal_root_governing_declaration',
        'current_state_compatibility_adjudication'
      )
    ),
  established_by_person_id uuid
    references atlas.people(id) on delete restrict,
  established_by_principal_id uuid
    references atlas.principals(id) on delete restrict,
  established_by_setup_actor_user_id uuid
    references auth.users(id) on delete restrict,
  authority_evidence jsonb not null default '{}'::jsonb
    check (jsonb_typeof(authority_evidence)='object'),
  established_at timestamptz not null default now(),
  superseded_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  check (
    (context_state='active' and superseded_at is null)
    or
    (context_state='superseded' and superseded_at is not null and superseded_at>=established_at)
  ),
  check (
    (
      basis_kind='organization_setup_actor_declaration'
      and established_by_person_id is not null
      and established_by_principal_id is null
      and established_by_setup_actor_user_id is not null
    )
    or
    (
      basis_kind='principal_root_governing_declaration'
      and established_by_person_id is not null
      and established_by_principal_id is not null
      and established_by_setup_actor_user_id is null
    )
    or
    (
      basis_kind='current_state_compatibility_adjudication'
      and established_by_person_id is null
      and established_by_principal_id is null
      and established_by_setup_actor_user_id is null
    )
  )
);

create unique index organization_membership_calendar_contexts_one_active_uq
  on atlas.organization_membership_calendar_contexts(organization_id)
  where context_state='active';

create index organization_membership_calendar_contexts_org_history_idx
  on atlas.organization_membership_calendar_contexts(
    organization_id,established_at desc,id
  );

alter table atlas.organization_membership_calendar_contexts enable row level security;
revoke all on atlas.organization_membership_calendar_contexts
  from public,anon,authenticated,service_role;

comment on table atlas.organization_membership_calendar_contexts is
'Append-preserving Organization-governed civil-calendar context whose sole initial jurisdiction is interpreting Organization Membership eligibility date boundaries. It is not a generic Organization timezone.';
comment on column atlas.organization_membership_calendar_contexts.timezone_name is
'IANA/PostgreSQL timezone name used only to derive the civil date for Organization Membership eligibility.';
comment on column atlas.organization_membership_calendar_contexts.basis_kind is
'Exact authority origin for establishing this calendar context. Change is supersede + append; origin is immutable.';

create or replace function atlas.guard_organization_membership_calendar_context_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal atlas.principals%rowtype;
  v_person_id uuid;
  v_authority_id uuid;
begin
  if tg_op='DELETE' then
    raise exception 'Organization Membership Calendar Context is append-preserving and cannot be deleted.'
      using errcode='55000';
  end if;

  if tg_op='UPDATE' then
    if new.organization_id is distinct from old.organization_id
       or new.timezone_name is distinct from old.timezone_name
       or new.basis_kind is distinct from old.basis_kind
       or new.established_by_person_id is distinct from old.established_by_person_id
       or new.established_by_principal_id is distinct from old.established_by_principal_id
       or new.established_by_setup_actor_user_id is distinct from old.established_by_setup_actor_user_id
       or new.authority_evidence is distinct from old.authority_evidence
       or new.established_at is distinct from old.established_at
       or new.metadata is distinct from old.metadata then
      raise exception 'Organization Membership Calendar Context origin is immutable; supersede and append instead.'
        using errcode='23514';
    end if;

    if old.context_state='superseded' and new.context_state='active' then
      raise exception 'Superseded Organization Membership Calendar Context cannot be reactivated.'
        using errcode='23514';
    end if;

    if old.context_state='active'
       and not (
         new.context_state='superseded'
         and new.superseded_at is not null
         and new.superseded_at>=old.established_at
       ) then
      raise exception 'Active Organization Membership Calendar Context may only transition to superseded.'
        using errcode='23514';
    end if;

    if old.context_state='superseded'
       and (
         new.context_state is distinct from old.context_state
         or new.superseded_at is distinct from old.superseded_at
       ) then
      raise exception 'Superseded Organization Membership Calendar Context is immutable.'
        using errcode='23514';
    end if;

    return new;
  end if;

  if new.context_state<>'active' or new.superseded_at is not null then
    raise exception 'New Organization Membership Calendar Context must begin active.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from atlas.organizations o
    where o.id=new.organization_id
      and o.status='active'
  ) then
    raise exception 'Active Organization required for Membership Calendar Context.'
      using errcode='23514';
  end if;

  if not exists(
    select 1
    from pg_catalog.pg_timezone_names
    where name=btrim(new.timezone_name)
  ) then
    raise exception 'Recognized PostgreSQL timezone name required for Membership Calendar Context.'
      using errcode='22023';
  end if;

  new.timezone_name:=btrim(new.timezone_name);

  if new.basis_kind='organization_setup_actor_declaration' then
    if not exists(
      select 1
      from atlas.organization_onboarding_actors a
      where a.organization_id=new.organization_id
        and a.human_user_id=new.established_by_setup_actor_user_id
        and a.actor_kind='setup_actor'
        and a.active
    ) then
      raise exception 'Active Organization setup actor required for setup-actor calendar declaration.'
        using errcode='42501';
    end if;

    select c.person_id into v_person_id
    from atlas.person_auth_credentials c
    join atlas.people p on p.id=c.person_id and p.status='active'
    where c.auth_user_id=new.established_by_setup_actor_user_id
      and c.status='active'
    order by c.bound_at,c.id
    limit 1;

    if v_person_id is null
       or v_person_id is distinct from new.established_by_person_id then
      raise exception 'Setup actor / canonical Person provenance contradiction.'
        using errcode='23514';
    end if;
  elsif new.basis_kind='principal_root_governing_declaration' then
    select * into v_principal
    from atlas.principals p
    where p.id=new.established_by_principal_id
      and p.status='active';

    if v_principal.id is null
       or v_principal.person_id is null
       or v_principal.person_id is distinct from new.established_by_person_id then
      raise exception 'Active Principal / canonical Person provenance required.'
        using errcode='23514';
    end if;

    select pla.id into v_authority_id
    from atlas.principal_ledger_authorities pla
    join atlas.ledgers l
      on l.id=pla.ledger_id
     and l.status='active'
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=pla.ledger_id
     and lop.organization_id=new.organization_id
     and lop.status='active'
     and lop.participation_kind='governing'
     and lop.is_compatibility_primary
    where pla.principal_id=new.established_by_principal_id
      and pla.authority_kind='root_governing'
      and pla.status='active'
    order by pla.established_at,pla.id
    limit 1;

    if v_authority_id is null then
      raise exception 'Principal Ledger root-governing authority over Organization required.'
        using errcode='42501';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_organization_membership_calendar_context_v1()
  from public,anon,authenticated,service_role;

create trigger organization_membership_calendar_context_guard_v1
before insert or update or delete
on atlas.organization_membership_calendar_contexts
for each row
execute function atlas.guard_organization_membership_calendar_context_v1();

create or replace function atlas.organization_membership_calendar_context_current_v1(
  p_organization_id uuid
)
returns table(
  context_id uuid,
  organization_id uuid,
  timezone_name text,
  basis_kind text,
  established_by_person_id uuid,
  established_by_principal_id uuid,
  established_by_setup_actor_user_id uuid,
  authority_evidence jsonb,
  established_at timestamptz,
  metadata jsonb
)
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select
    c.id,
    c.organization_id,
    c.timezone_name,
    c.basis_kind,
    c.established_by_person_id,
    c.established_by_principal_id,
    c.established_by_setup_actor_user_id,
    c.authority_evidence,
    c.established_at,
    c.metadata
  from atlas.organization_membership_calendar_contexts c
  where c.organization_id=p_organization_id
    and c.context_state='active'
  order by c.established_at desc,c.id
  limit 1
$function$;

revoke all on function atlas.organization_membership_calendar_context_current_v1(uuid)
  from public,anon,authenticated;
grant execute on function atlas.organization_membership_calendar_context_current_v1(uuid)
  to postgres,service_role;

comment on function atlas.organization_membership_calendar_context_current_v1(uuid) is
'Internal exact current Organization Membership Calendar Context. No row means unresolved; callers must not infer Principal, Household, farm, browser, event, notification, or database/session time.';

create or replace function atlas.organization_membership_calendar_date_at_v1(
  p_organization_id uuid,
  p_as_of timestamptz
)
returns date
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_timezone text;
begin
  if p_organization_id is null or p_as_of is null then
    return null;
  end if;

  select c.timezone_name into v_timezone
  from atlas.organization_membership_calendar_contexts c
  where c.organization_id=p_organization_id
    and c.context_state='active'
  order by c.established_at desc,c.id
  limit 1;

  if v_timezone is null then
    return null;
  end if;

  return (p_as_of at time zone v_timezone)::date;
end;
$function$;

revoke all on function atlas.organization_membership_calendar_date_at_v1(uuid,timestamptz)
  from public,anon,authenticated;
grant execute on function atlas.organization_membership_calendar_date_at_v1(uuid,timestamptz)
  to postgres,service_role;

comment on function atlas.organization_membership_calendar_date_at_v1(uuid,timestamptz) is
'Internal civil-date resolver for Organization Membership eligibility. Returns null when the Organization has no governed Membership Calendar Context; never falls back to database/session or another domain timezone.';

create or replace function atlas.set_organization_membership_calendar_context_internal_v1(
  p_organization_id uuid,
  p_timezone_name text,
  p_basis_kind text,
  p_actor_user_id uuid default null,
  p_actor_principal_id uuid default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_timezone text:=btrim(coalesce(p_timezone_name,''));
  v_basis text:=btrim(coalesce(p_basis_kind,''));
  v_person_id uuid;
  v_authority_id uuid;
  v_ledger_id uuid;
  v_participation_id uuid;
  v_setup_started_at timestamptz;
  v_current atlas.organization_membership_calendar_contexts%rowtype;
  v_new atlas.organization_membership_calendar_contexts%rowtype;
  v_evidence jsonb:='{}'::jsonb;
begin
  if p_organization_id is null or v_timezone='' then
    raise exception 'Organization and timezone are required.'
      using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then
    raise exception 'Calendar context metadata must be an object.'
      using errcode='22023';
  end if;

  if v_basis not in (
    'organization_setup_actor_declaration',
    'principal_root_governing_declaration'
  ) then
    raise exception 'Unsupported interactive Membership Calendar Context basis.'
      using errcode='22023';
  end if;

  if not exists(
    select 1 from pg_catalog.pg_timezone_names where name=v_timezone
  ) then
    raise exception 'Recognized PostgreSQL timezone name required.'
      using errcode='22023';
  end if;

  perform 1
  from atlas.organizations o
  where o.id=p_organization_id
    and o.status='active'
  for update;

  if not found then
    raise exception 'Active Organization required.'
      using errcode='P0002';
  end if;

  if v_basis='organization_setup_actor_declaration' then
    if p_actor_user_id is null or p_actor_principal_id is not null then
      raise exception 'Setup-actor calendar declaration requires actor user only.'
        using errcode='22023';
    end if;

    select a.started_at into v_setup_started_at
    from atlas.organization_onboarding_actors a
    where a.organization_id=p_organization_id
      and a.human_user_id=p_actor_user_id
      and a.actor_kind='setup_actor'
      and a.active;

    if v_setup_started_at is null then
      raise exception 'Active Organization setup actor required.'
        using errcode='42501';
    end if;

    select c.person_id into v_person_id
    from atlas.person_auth_credentials c
    join atlas.people p on p.id=c.person_id and p.status='active'
    where c.auth_user_id=p_actor_user_id
      and c.status='active'
    order by c.bound_at,c.id
    limit 1;

    if v_person_id is null then
      raise exception 'Canonical Person required for setup actor declaration.'
        using errcode='42501';
    end if;

    v_evidence:=jsonb_build_object(
      'authorityKind','organization_setup_actor',
      'setupActorUserId',p_actor_user_id,
      'setupActorStartedAt',v_setup_started_at
    );
  else
    if p_actor_principal_id is null or p_actor_user_id is not null then
      raise exception 'Root-governing calendar declaration requires Principal only.'
        using errcode='22023';
    end if;

    select p.person_id into v_person_id
    from atlas.principals p
    where p.id=p_actor_principal_id
      and p.status='active';

    if v_person_id is null then
      raise exception 'Active Principal with canonical Person required.'
        using errcode='42501';
    end if;

    select pla.id,pla.ledger_id,lop.id
      into v_authority_id,v_ledger_id,v_participation_id
    from atlas.principal_ledger_authorities pla
    join atlas.ledgers l
      on l.id=pla.ledger_id
     and l.status='active'
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=pla.ledger_id
     and lop.organization_id=p_organization_id
     and lop.status='active'
     and lop.participation_kind='governing'
     and lop.is_compatibility_primary
    where pla.principal_id=p_actor_principal_id
      and pla.authority_kind='root_governing'
      and pla.status='active'
    order by pla.established_at,pla.id
    limit 1;

    if v_authority_id is null then
      raise exception 'Principal Ledger root-governing authority over Organization required.'
        using errcode='42501';
    end if;

    v_evidence:=jsonb_build_object(
      'authorityKind','principal_ledger_root_governing',
      'principalLedgerAuthorityId',v_authority_id,
      'ledgerId',v_ledger_id,
      'ledgerOrganizationParticipationId',v_participation_id
    );
  end if;

  select * into v_current
  from atlas.organization_membership_calendar_contexts c
  where c.organization_id=p_organization_id
    and c.context_state='active'
  order by c.established_at desc,c.id
  limit 1
  for update;

  if v_current.id is not null
     and v_current.timezone_name=v_timezone
     and v_current.basis_kind=v_basis
     and v_current.established_by_person_id=v_person_id
     and v_current.established_by_principal_id is not distinct from p_actor_principal_id
     and v_current.established_by_setup_actor_user_id is not distinct from p_actor_user_id then
    return jsonb_build_object(
      'contractVersion','organization_membership_calendar_context_v1',
      'organizationId',p_organization_id,
      'contextId',v_current.id,
      'timezoneName',v_current.timezone_name,
      'basisKind',v_current.basis_kind,
      'alreadyCurrent',true
    );
  end if;

  if v_current.id is not null then
    update atlas.organization_membership_calendar_contexts
    set context_state='superseded',
        superseded_at=now()
    where id=v_current.id;
  end if;

  insert into atlas.organization_membership_calendar_contexts(
    organization_id,
    timezone_name,
    context_state,
    basis_kind,
    established_by_person_id,
    established_by_principal_id,
    established_by_setup_actor_user_id,
    authority_evidence,
    metadata
  ) values (
    p_organization_id,
    v_timezone,
    'active',
    v_basis,
    v_person_id,
    p_actor_principal_id,
    p_actor_user_id,
    v_evidence,
    coalesce(p_metadata,'{}'::jsonb)
      ||jsonb_strip_nulls(jsonb_build_object(
        'source','set_organization_membership_calendar_context_internal_v1',
        'reason',nullif(btrim(coalesce(p_reason,'')),'')
      ))
  )
  returning * into v_new;

  return jsonb_build_object(
    'contractVersion','organization_membership_calendar_context_v1',
    'organizationId',p_organization_id,
    'contextId',v_new.id,
    'timezoneName',v_new.timezone_name,
    'basisKind',v_new.basis_kind,
    'supersededContextId',v_current.id,
    'alreadyCurrent',false
  );
end;
$function$;

revoke all on function atlas.set_organization_membership_calendar_context_internal_v1(
  uuid,text,text,uuid,uuid,text,jsonb
) from public,anon,authenticated;
grant execute on function atlas.set_organization_membership_calendar_context_internal_v1(
  uuid,text,text,uuid,uuid,text,jsonb
) to postgres,service_role;

comment on function atlas.set_organization_membership_calendar_context_internal_v1(uuid,text,text,uuid,uuid,text,jsonb) is
'Internal governed establish/supersede command for Organization Membership Calendar Context. Phase A admits only active setup-actor declaration or Principal Ledger root-governing declaration. Present-effective owner governance is added only after Effective Time Phase B exists.';

insert into atlas.organization_membership_calendar_contexts(
  organization_id,
  timezone_name,
  context_state,
  basis_kind,
  authority_evidence,
  metadata
)
select
  o.id,
  'America/Chicago',
  'active',
  'current_state_compatibility_adjudication',
  jsonb_build_object(
    'authorityKind','repository_governed_compatibility_adjudication',
    'auditedOn','2026-09-20',
    'architecture','atlas-organization-membership-calendar-context-current-canon-v1'
  ),
  jsonb_build_object(
    'source','organization_membership_calendar_context_v1_candidate',
    'compatibilityTruth','Explicit one-time Elm Farm Membership calendar adjudication. This does not create a continuing Principal/Household/farm timezone inheritance rule.'
  )
from atlas.organizations o
where o.stable_key='elm_farm';

do $verification$
declare
  v_elm uuid;
begin
  select o.id into v_elm
  from atlas.organizations o
  where o.stable_key='elm_farm';

  if (
    select count(*)
    from atlas.organization_membership_calendar_contexts c
    where c.organization_id=v_elm
      and c.context_state='active'
      and c.timezone_name='America/Chicago'
      and c.basis_kind='current_state_compatibility_adjudication'
  )<>1 then
    raise exception 'Elm Farm compatibility Membership Calendar Context was not established exactly once.';
  end if;

  if exists(
    select 1
    from atlas.organization_membership_calendar_contexts c
    join atlas.organizations o on o.id=c.organization_id
    where o.stable_key in ('feast_guild','atlas_reference_company')
  ) then
    raise exception 'Unbounded/current Organizations received an inferred Membership Calendar Context.';
  end if;

  if has_table_privilege('anon','atlas.organization_membership_calendar_contexts','SELECT')
     or has_table_privilege('authenticated','atlas.organization_membership_calendar_contexts','SELECT')
     or has_table_privilege('service_role','atlas.organization_membership_calendar_contexts','INSERT') then
    raise exception 'Membership Calendar Context table leaked direct browser/service mutation authority.';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.set_organization_membership_calendar_context_internal_v1(uuid,text,text,uuid,uuid,text,jsonb)',
       'EXECUTE'
     ) then
    raise exception 'Internal Membership Calendar Context command leaked to authenticated browser role.';
  end if;
end;
$verification$;

commit;
