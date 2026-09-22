-- Atlas Development Kernel v1 candidate.
-- Native institutional Development: Standard Version -> Case -> Criterion Resolution -> Release.
-- This candidate deliberately reuses Organization/Ledger custody and keeps Work, Evidence,
-- Operating Knowledge, Communication, and target-domain truth outside Development.

begin;

-- ---------------------------------------------------------------------------
-- Development Standard Version
-- ---------------------------------------------------------------------------

create table atlas.development_standard_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  stable_key text not null check (btrim(stable_key) <> ''),
  version integer not null check (version > 0),
  title text not null check (btrim(title) <> ''),
  purpose text not null check (btrim(purpose) <> ''),
  eligible_subject_kinds text[] not null,
  status text not null default 'draft'
    check (status in ('draft','established')),
  established_at timestamptz,
  established_by_label text,
  provenance jsonb not null default '{}'::jsonb
    check (jsonb_typeof(provenance)='object'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, stable_key, version),
  check (cardinality(eligible_subject_kinds) > 0),
  check (
    (status='draft' and established_at is null)
    or
    (status='established' and established_at is not null and nullif(btrim(coalesce(established_by_label,'')),'') is not null)
  )
);

comment on table atlas.development_standard_versions is
  'Organization/Ledger-custodied immutable-after-establishment Development Standard versions. A Standard defines questions and release gates; it does not contain subject answers.';

create table atlas.development_standard_criteria (
  id uuid primary key default gen_random_uuid(),
  standard_version_id uuid not null references atlas.development_standard_versions(id) on delete restrict,
  criterion_key text not null check (btrim(criterion_key) <> ''),
  question text not null check (btrim(question) <> ''),
  rationale text not null default '',
  applicability jsonb not null default '{}'::jsonb
    check (jsonb_typeof(applicability)='object'),
  allowed_resolution_kinds text[] not null default array[
    'established','inherited','local','not_applicable',
    'needs_evidence','deferred','unresolved','conflicted'
  ]::text[],
  base_score integer not null default 0,
  consequence_value integer not null default 0,
  information_gain integer not null default 0,
  expected_friction integer not null default 0 check (expected_friction >= 0),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (standard_version_id, criterion_key),
  check (cardinality(allowed_resolution_kinds) > 0),
  check (
    allowed_resolution_kinds <@ array[
      'established','inherited','local','not_applicable',
      'needs_evidence','deferred','unresolved','conflicted'
    ]::text[]
  )
);

comment on table atlas.development_standard_criteria is
  'Criterion definitions inside one exact Development Standard Version. Criteria are questions/requirements, not answers for any Development Case.';

create table atlas.development_standard_gates (
  id uuid primary key default gen_random_uuid(),
  standard_version_id uuid not null references atlas.development_standard_versions(id) on delete restrict,
  gate_key text not null check (btrim(gate_key) <> ''),
  label text not null check (btrim(label) <> ''),
  description text not null default '',
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (standard_version_id, gate_key)
);

comment on table atlas.development_standard_gates is
  'Domain-defined Development maturity/release gates. Gate names such as Buildable or Delegable are data, not Atlas-wide enum values.';

create table atlas.development_standard_gate_requirements (
  id uuid primary key default gen_random_uuid(),
  gate_id uuid not null references atlas.development_standard_gates(id) on delete restrict,
  criterion_id uuid not null references atlas.development_standard_criteria(id) on delete restrict,
  accepted_resolution_kinds text[] not null,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (gate_id, criterion_id),
  check (cardinality(accepted_resolution_kinds) > 0),
  check (
    accepted_resolution_kinds <@ array[
      'established','inherited','local','not_applicable'
    ]::text[]
  )
);

comment on table atlas.development_standard_gate_requirements is
  'Exact criterion requirements for one Development gate, including which explicit Criterion Resolution kinds satisfy that gate.';

-- ---------------------------------------------------------------------------
-- Development Case
-- ---------------------------------------------------------------------------

create table atlas.development_cases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  standard_version_id uuid not null references atlas.development_standard_versions(id) on delete restrict,
  case_key text not null check (btrim(case_key) <> ''),
  target_domain text not null check (btrim(target_domain) <> ''),
  target_kind text not null check (btrim(target_kind) <> ''),
  target_ref text not null check (btrim(target_ref) <> ''),
  purpose text not null check (btrim(purpose) <> ''),
  state text not null default 'open'
    check (state in ('open','closed','cancelled')),
  opened_by_label text not null check (btrim(opened_by_label) <> ''),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, case_key),
  check (
    (state='open' and closed_at is null)
    or
    (state in ('closed','cancelled') and closed_at is not null)
  )
);

comment on table atlas.development_cases is
  'Durable organization-owned effort to develop one exact target subject under one exact established Development Standard Version. Development does not copy the target-domain subject.';

-- ---------------------------------------------------------------------------
-- Criterion Resolution history
-- ---------------------------------------------------------------------------

create sequence atlas.development_resolution_revision_seq_v1 as bigint start 1;

create table atlas.development_criterion_resolution_events (
  id uuid primary key default gen_random_uuid(),
  development_case_id uuid not null references atlas.development_cases(id) on delete restrict,
  criterion_id uuid not null references atlas.development_standard_criteria(id) on delete restrict,
  resolution_kind text not null
    check (resolution_kind in (
      'established','inherited','local','not_applicable',
      'needs_evidence','deferred','unresolved','conflicted'
    )),
  basis_kind text not null check (btrim(basis_kind) <> ''),
  basis_domain text not null check (btrim(basis_domain) <> ''),
  basis_ref text,
  statement text not null check (btrim(statement) <> ''),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  actor_label text not null check (btrim(actor_label) <> ''),
  occurred_at timestamptz not null default clock_timestamp(),
  revision bigint not null default nextval('atlas.development_resolution_revision_seq_v1'),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (development_case_id, idempotency_key),
  check (
    resolution_kind not in ('established','inherited','local','not_applicable')
    or nullif(btrim(coalesce(basis_ref,'')),'') is not null
  )
);

comment on table atlas.development_criterion_resolution_events is
  'Append-only institutional accounting for the current and historical position of one Case criterion. Work completion or evidence alone does not create Criterion Resolution.';

create index development_resolution_case_criterion_time_idx
  on atlas.development_criterion_resolution_events(
    development_case_id,criterion_id,revision desc
  );

-- ---------------------------------------------------------------------------
-- Development Release accounting
-- ---------------------------------------------------------------------------

create table atlas.development_releases (
  id uuid primary key default gen_random_uuid(),
  development_case_id uuid not null references atlas.development_cases(id) on delete restrict,
  target_version_ref text not null check (btrim(target_version_ref) <> ''),
  release_basis text not null check (btrim(release_basis) <> ''),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  released_by_label text not null check (btrim(released_by_label) <> ''),
  released_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (development_case_id,idempotency_key)
);

comment on table atlas.development_releases is
  'Immutable accounting that an exact target-domain version satisfied exact Development gate(s) under the Case Standard Version. Development does not own the released target semantics.';

create table atlas.development_release_gates (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references atlas.development_releases(id) on delete restrict,
  gate_id uuid not null references atlas.development_standard_gates(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (release_id,gate_id)
);

comment on table atlas.development_release_gates is
  'Exact Standard gates included in one immutable Development Release.';

-- ---------------------------------------------------------------------------
-- Scope and immutability guards
-- ---------------------------------------------------------------------------

create or replace function atlas.guard_development_organization_ledger_scope_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_standard atlas.development_standard_versions%rowtype;
begin
  if not exists (
    select 1
    from atlas.ledger_organization_participations p
    join atlas.ledgers l on l.id=p.ledger_id
    join atlas.organizations o on o.id=p.organization_id
    where p.ledger_id=new.ledger_id
      and p.organization_id=new.organization_id
      and p.status='active'
      and l.status='active'
      and o.status='active'
  ) then
    raise exception 'Development custody requires an active Organization / Ledger participation.'
      using errcode='23514';
  end if;

  if tg_table_name='development_cases' then
    select * into v_standard
    from atlas.development_standard_versions s
    where s.id=new.standard_version_id;

    if v_standard.id is null
       or v_standard.organization_id is distinct from new.organization_id
       or v_standard.ledger_id is distinct from new.ledger_id then
      raise exception 'Development Case and Standard Version must share Organization / Ledger custody.'
        using errcode='23514';
    end if;

    if v_standard.status<>'established' then
      raise exception 'Development Case requires an established Standard Version.'
        using errcode='23514';
    end if;

    if not (new.target_kind=any(v_standard.eligible_subject_kinds)) then
      raise exception 'Development Case target kind is not eligible under this Standard Version.'
        using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger development_standard_scope_guard_v1
before insert or update on atlas.development_standard_versions
for each row execute function atlas.guard_development_organization_ledger_scope_v1();

create trigger development_case_scope_guard_v1
before insert or update on atlas.development_cases
for each row execute function atlas.guard_development_organization_ledger_scope_v1();

create or replace function atlas.guard_development_case_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  if tg_op='DELETE' then
    raise exception 'Development Case identity/history is durable; close or cancel the Case instead of deleting it.'
      using errcode='55000';
  end if;

  if new.organization_id is distinct from old.organization_id
     or new.ledger_id is distinct from old.ledger_id
     or new.standard_version_id is distinct from old.standard_version_id
     or new.case_key is distinct from old.case_key
     or new.target_domain is distinct from old.target_domain
     or new.target_kind is distinct from old.target_kind
     or new.target_ref is distinct from old.target_ref
     or new.opened_by_label is distinct from old.opened_by_label
     or new.opened_at is distinct from old.opened_at then
    raise exception 'Development Case custody, Standard binding, and target identity are immutable.'
      using errcode='55000';
  end if;

  if old.state<>'open' then
    raise exception 'Closed or cancelled Development Cases are immutable.'
      using errcode='55000';
  end if;

  if old.state='open' and new.state not in ('open','closed','cancelled') then
    raise exception 'Unsupported Development Case state transition.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

create trigger development_case_mutation_guard_v1
before update or delete on atlas.development_cases
for each row execute function atlas.guard_development_case_mutation_v1();

create or replace function atlas.guard_development_standard_version_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_missing_gate_count integer;
begin
  if tg_op='DELETE' then
    if old.status='established'
       or exists(select 1 from atlas.development_cases c where c.standard_version_id=old.id) then
      raise exception 'Established or used Development Standard Versions are immutable.'
        using errcode='55000';
    end if;
    return old;
  end if;

  if old.status='established' then
    raise exception 'Established Development Standard semantics are immutable; create a new version.'
      using errcode='55000';
  end if;

  if new.status='established' and old.status='draft' then
    if not exists (
      select 1 from atlas.development_standard_criteria c
      where c.standard_version_id=old.id
    ) then
      raise exception 'Development Standard cannot be established without criteria.'
        using errcode='23514';
    end if;

    if not exists (
      select 1 from atlas.development_standard_gates g
      where g.standard_version_id=old.id
    ) then
      raise exception 'Development Standard cannot be established without release gates.'
        using errcode='23514';
    end if;

    select count(*)::integer into v_missing_gate_count
    from atlas.development_standard_gates g
    where g.standard_version_id=old.id
      and not exists (
        select 1
        from atlas.development_standard_gate_requirements r
        where r.gate_id=g.id
      );

    if v_missing_gate_count>0 then
      raise exception 'Every Development Standard gate requires at least one criterion.'
        using errcode='23514';
    end if;

    new.established_at:=coalesce(new.established_at,now());
    if nullif(btrim(coalesce(new.established_by_label,'')),'') is null then
      raise exception 'Establishing a Development Standard requires an authority label.'
        using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger development_standard_version_immutability_v1
before update or delete on atlas.development_standard_versions
for each row execute function atlas.guard_development_standard_version_mutation_v1();

create or replace function atlas.guard_development_standard_child_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_standard_id uuid;
  v_gate_standard_id uuid;
  v_criterion_standard_id uuid;
  v_criterion_allowed text[];
  v_status text;
begin
  if tg_table_name in ('development_standard_criteria','development_standard_gates') then
    if tg_op='DELETE' then
      v_standard_id:=old.standard_version_id;
    else
      v_standard_id:=new.standard_version_id;
    end if;
  elsif tg_table_name='development_standard_gate_requirements' then
    if tg_op='DELETE' then
      select g.standard_version_id into v_gate_standard_id
      from atlas.development_standard_gates g where g.id=old.gate_id;
      select c.standard_version_id,c.allowed_resolution_kinds
      into v_criterion_standard_id,v_criterion_allowed
      from atlas.development_standard_criteria c where c.id=old.criterion_id;
    else
      select g.standard_version_id into v_gate_standard_id
      from atlas.development_standard_gates g where g.id=new.gate_id;
      select c.standard_version_id,c.allowed_resolution_kinds
      into v_criterion_standard_id,v_criterion_allowed
      from atlas.development_standard_criteria c where c.id=new.criterion_id;
    end if;

    if v_gate_standard_id is null
       or v_criterion_standard_id is null
       or v_gate_standard_id is distinct from v_criterion_standard_id then
      raise exception 'Development gate requirement must remain inside one Standard Version.'
        using errcode='23514';
    end if;

    if tg_op<>'DELETE'
       and not (new.accepted_resolution_kinds <@ v_criterion_allowed) then
      raise exception 'Development gate cannot accept a Resolution kind forbidden by its criterion.'
        using errcode='23514';
    end if;

    v_standard_id:=v_gate_standard_id;
  else
    raise exception 'Unexpected Development Standard child table.'
      using errcode='55000';
  end if;

  select s.status into v_status
  from atlas.development_standard_versions s
  where s.id=v_standard_id;

  if v_status is null then
    raise exception 'Development Standard Version not found.'
      using errcode='23503';
  end if;

  if v_status<>'draft' then
    raise exception 'Established Development Standard children are immutable; create a new Standard Version.'
      using errcode='55000';
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$;

create trigger development_standard_criteria_mutation_guard_v1
before insert or update or delete on atlas.development_standard_criteria
for each row execute function atlas.guard_development_standard_child_mutation_v1();

create trigger development_standard_gates_mutation_guard_v1
before insert or update or delete on atlas.development_standard_gates
for each row execute function atlas.guard_development_standard_child_mutation_v1();

create trigger development_standard_gate_requirements_mutation_guard_v1
before insert or update or delete on atlas.development_standard_gate_requirements
for each row execute function atlas.guard_development_standard_child_mutation_v1();

create or replace function atlas.guard_development_resolution_event_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_case atlas.development_cases%rowtype;
  v_criterion atlas.development_standard_criteria%rowtype;
  v_knowledge_org uuid;
begin
  select * into v_case
  from atlas.development_cases c
  where c.id=new.development_case_id;

  if v_case.id is null or v_case.state<>'open' then
    raise exception 'Criterion Resolution requires an open Development Case.'
      using errcode='23514';
  end if;

  select * into v_criterion
  from atlas.development_standard_criteria c
  where c.id=new.criterion_id;

  if v_criterion.id is null
     or v_criterion.standard_version_id is distinct from v_case.standard_version_id then
    raise exception 'Criterion Resolution must use a criterion from the Case Standard Version.'
      using errcode='23514';
  end if;

  if not (new.resolution_kind=any(v_criterion.allowed_resolution_kinds)) then
    raise exception 'Resolution kind is not allowed for this Development criterion.'
      using errcode='23514';
  end if;

  if new.basis_kind='company_operating_knowledge' then
    if nullif(btrim(coalesce(new.basis_ref,'')),'') is null
       or new.basis_ref !~ '^[0-9a-fA-F-]{36}$' then
      raise exception 'Company Operating Knowledge basis requires a UUID reference.'
        using errcode='22023';
    end if;

    select k.organization_id into v_knowledge_org
    from atlas.company_operating_knowledge k
    where k.id=new.basis_ref::uuid;

    if v_knowledge_org is null
       or v_knowledge_org is distinct from v_case.organization_id then
      raise exception 'Development cannot inherit Operating Knowledge across Organization custody.'
        using errcode='23514';
    end if;
  end if;

  return new;
end;
$function$;

create trigger development_resolution_event_guard_v1
before insert on atlas.development_criterion_resolution_events
for each row execute function atlas.guard_development_resolution_event_v1();

create or replace function atlas.prevent_development_history_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Development resolution/release history is append-only.'
    using errcode='55000';
end;
$function$;

create trigger development_resolution_events_immutable_v1
before update or delete on atlas.development_criterion_resolution_events
for each row execute function atlas.prevent_development_history_mutation_v1();

create trigger development_releases_immutable_v1
before update or delete on atlas.development_releases
for each row execute function atlas.prevent_development_history_mutation_v1();

create trigger development_release_gates_immutable_v1
before update or delete on atlas.development_release_gates
for each row execute function atlas.prevent_development_history_mutation_v1();

create or replace function atlas.guard_development_release_gate_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_case_standard_id uuid;
  v_gate_standard_id uuid;
begin
  select c.standard_version_id into v_case_standard_id
  from atlas.development_releases r
  join atlas.development_cases c on c.id=r.development_case_id
  where r.id=new.release_id;

  select g.standard_version_id into v_gate_standard_id
  from atlas.development_standard_gates g
  where g.id=new.gate_id;

  if v_case_standard_id is null
     or v_gate_standard_id is null
     or v_case_standard_id is distinct from v_gate_standard_id then
    raise exception 'Development Release gates must belong to the Case Standard Version.'
      using errcode='23514';
  end if;

  return new;
end;
$function$;

create trigger development_release_gate_scope_guard_v1
before insert on atlas.development_release_gates
for each row execute function atlas.guard_development_release_gate_v1();

-- ---------------------------------------------------------------------------
-- Read / command contracts
-- ---------------------------------------------------------------------------

create or replace function atlas.development_current_criterion_resolution_v1(
  p_development_case_id uuid,
  p_criterion_key text
)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select case when c.id is null then null else jsonb_build_object(
    'contractVersion','development_current_criterion_resolution_v1',
    'developmentCaseId',p_development_case_id,
    'criterionKey',c.criterion_key,
    'criterionId',c.id,
    'resolutionEventId',e.id,
    'resolutionKind',e.resolution_kind,
    'basisKind',e.basis_kind,
    'basisDomain',e.basis_domain,
    'basisRef',e.basis_ref,
    'statement',e.statement,
    'actorLabel',e.actor_label,
    'occurredAt',e.occurred_at,
    'revision',e.revision
  ) end
  from atlas.development_cases dc
  join atlas.development_standard_criteria c
    on c.standard_version_id=dc.standard_version_id
   and c.criterion_key=btrim(p_criterion_key)
  left join lateral (
    select r.*
    from atlas.development_criterion_resolution_events r
    where r.development_case_id=dc.id
      and r.criterion_id=c.id
    order by r.revision desc
    limit 1
  ) e on true
  where dc.id=p_development_case_id;
$function$;

create or replace function atlas.record_development_criterion_resolution_internal_v1(
  p_development_case_id uuid,
  p_criterion_key text,
  p_resolution_kind text,
  p_basis_kind text,
  p_basis_domain text,
  p_basis_ref text,
  p_statement text,
  p_idempotency_key text,
  p_actor_label text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_case atlas.development_cases%rowtype;
  v_criterion atlas.development_standard_criteria%rowtype;
  v_existing atlas.development_criterion_resolution_events%rowtype;
  v_row atlas.development_criterion_resolution_events%rowtype;
begin
  if p_development_case_id is null
     or nullif(btrim(coalesce(p_criterion_key,'')),'') is null
     or nullif(btrim(coalesce(p_resolution_kind,'')),'') is null
     or nullif(btrim(coalesce(p_basis_kind,'')),'') is null
     or nullif(btrim(coalesce(p_basis_domain,'')),'') is null
     or nullif(btrim(coalesce(p_statement,'')),'') is null
     or nullif(btrim(coalesce(p_idempotency_key,'')),'') is null
     or nullif(btrim(coalesce(p_actor_label,'')),'') is null then
    raise exception 'Development Criterion Resolution input is incomplete.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Development Criterion Resolution metadata must be an object.'
      using errcode='22023';
  end if;

  select * into v_case
  from atlas.development_cases c
  where c.id=p_development_case_id
  for key share;

  if v_case.id is null or v_case.state<>'open' then
    raise exception 'Open Development Case required.'
      using errcode='23514';
  end if;

  select * into v_criterion
  from atlas.development_standard_criteria c
  where c.standard_version_id=v_case.standard_version_id
    and c.criterion_key=btrim(p_criterion_key);

  if v_criterion.id is null then
    raise exception 'Criterion is not part of the Case Standard Version.'
      using errcode='23503';
  end if;

  select * into v_existing
  from atlas.development_criterion_resolution_events r
  where r.development_case_id=p_development_case_id
    and r.idempotency_key=btrim(p_idempotency_key);

  if v_existing.id is not null then
    if v_existing.criterion_id is distinct from v_criterion.id
       or v_existing.resolution_kind is distinct from btrim(p_resolution_kind)
       or v_existing.basis_kind is distinct from btrim(p_basis_kind)
       or v_existing.basis_domain is distinct from btrim(p_basis_domain)
       or v_existing.basis_ref is distinct from nullif(btrim(coalesce(p_basis_ref,'')),'')
       or v_existing.statement is distinct from btrim(p_statement)
       or v_existing.actor_label is distinct from btrim(p_actor_label)
       or v_existing.metadata is distinct from p_metadata then
      raise exception 'Development Criterion Resolution idempotency key contradiction.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'contractVersion','record_development_criterion_resolution_internal_v1',
      'state','unchanged',
      'resolutionEventId',v_existing.id
    );
  end if;

  insert into atlas.development_criterion_resolution_events(
    development_case_id,criterion_id,resolution_kind,
    basis_kind,basis_domain,basis_ref,statement,
    idempotency_key,actor_label,metadata
  ) values (
    p_development_case_id,v_criterion.id,btrim(p_resolution_kind),
    btrim(p_basis_kind),btrim(p_basis_domain),nullif(btrim(coalesce(p_basis_ref,'')),''),
    btrim(p_statement),btrim(p_idempotency_key),btrim(p_actor_label),p_metadata
  )
  returning * into v_row;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','record_development_criterion_resolution_internal_v1',
    'state','recorded',
    'resolutionEventId',v_row.id
  );
end;
$function$;

create or replace function atlas.development_gate_position_v1(
  p_development_case_id uuid,
  p_gate_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_case atlas.development_cases%rowtype;
  v_gate atlas.development_standard_gates%rowtype;
  v_required integer;
  v_blocked integer;
  v_conflicted boolean;
  v_requirements jsonb;
  v_blockers jsonb;
  v_state text;
begin
  select * into v_case
  from atlas.development_cases c
  where c.id=p_development_case_id;

  if v_case.id is null then
    raise exception 'Development Case not found.' using errcode='23503';
  end if;

  select * into v_gate
  from atlas.development_standard_gates g
  where g.standard_version_id=v_case.standard_version_id
    and g.gate_key=btrim(p_gate_key);

  if v_gate.id is null then
    raise exception 'Development gate not found for Case Standard Version.'
      using errcode='23503';
  end if;

  with positions as (
    select
      c.id as criterion_id,
      c.criterion_key,
      r.accepted_resolution_kinds,
      e.id as resolution_event_id,
      e.resolution_kind,
      e.basis_kind,
      e.basis_domain,
      e.basis_ref,
      e.statement,
      (
        e.id is not null
        and e.resolution_kind=any(r.accepted_resolution_kinds)
      ) as satisfied
    from atlas.development_standard_gate_requirements r
    join atlas.development_standard_criteria c on c.id=r.criterion_id
    left join lateral (
      select re.*
      from atlas.development_criterion_resolution_events re
      where re.development_case_id=p_development_case_id
        and re.criterion_id=c.id
      order by re.revision desc
      limit 1
    ) e on true
    where r.gate_id=v_gate.id
  )
  select
    count(*)::integer,
    count(*) filter(where not satisfied)::integer,
    coalesce(bool_or(resolution_kind='conflicted'),false),
    coalesce(jsonb_agg(jsonb_build_object(
      'criterionKey',criterion_key,
      'criterionId',criterion_id,
      'acceptedResolutionKinds',accepted_resolution_kinds,
      'resolutionEventId',resolution_event_id,
      'resolutionKind',resolution_kind,
      'basisKind',basis_kind,
      'basisDomain',basis_domain,
      'basisRef',basis_ref,
      'statement',statement,
      'satisfied',satisfied
    ) order by criterion_key),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'criterionKey',criterion_key,
      'resolutionKind',resolution_kind,
      'reason',case
        when resolution_event_id is null then 'no_resolution'
        else 'resolution_not_accepted_for_gate'
      end
    ) order by criterion_key) filter(where not satisfied),'[]'::jsonb)
  into v_required,v_blocked,v_conflicted,v_requirements,v_blockers
  from positions;

  if v_required=0 then
    raise exception 'Development gate has no criterion requirements.'
      using errcode='23514';
  end if;

  v_state:=case
    when v_conflicted then 'conflicted'
    when v_blocked=0 then 'satisfied'
    else 'blocked'
  end;

  return jsonb_build_object(
    'contractVersion','development_gate_position_v1',
    'developmentCaseId',p_development_case_id,
    'standardVersionId',v_case.standard_version_id,
    'gateKey',v_gate.gate_key,
    'gateId',v_gate.id,
    'label',v_gate.label,
    'state',v_state,
    'requiredCount',v_required,
    'blockedCount',v_blocked,
    'requirements',v_requirements,
    'blockers',v_blockers
  );
end;
$function$;

create or replace function atlas.release_development_case_internal_v1(
  p_development_case_id uuid,
  p_target_version_ref text,
  p_gate_keys text[],
  p_release_basis text,
  p_idempotency_key text,
  p_released_by_label text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_case atlas.development_cases%rowtype;
  v_existing atlas.development_releases%rowtype;
  v_release_id uuid;
  v_gate_keys text[];
  v_existing_gate_keys text[];
  v_gate_key text;
  v_gate_position jsonb;
  v_gate_id uuid;
begin
  if p_development_case_id is null
     or nullif(btrim(coalesce(p_target_version_ref,'')),'') is null
     or nullif(btrim(coalesce(p_release_basis,'')),'') is null
     or nullif(btrim(coalesce(p_idempotency_key,'')),'') is null
     or nullif(btrim(coalesce(p_released_by_label,'')),'') is null
     or p_gate_keys is null
     or cardinality(p_gate_keys)=0 then
    raise exception 'Development Release input is incomplete.'
      using errcode='22023';
  end if;

  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Development Release metadata must be an object.'
      using errcode='22023';
  end if;

  select array_agg(x order by x) into v_gate_keys
  from (
    select distinct btrim(g) as x
    from unnest(p_gate_keys) g
    where nullif(btrim(coalesce(g,'')),'') is not null
  ) normalized;

  if v_gate_keys is null
     or cardinality(v_gate_keys)<>cardinality(p_gate_keys) then
    raise exception 'Development Release gate keys must be nonblank and unique.'
      using errcode='22023';
  end if;

  select * into v_case
  from atlas.development_cases c
  where c.id=p_development_case_id
  for key share;

  if v_case.id is null or v_case.state<>'open' then
    raise exception 'Open Development Case required for release.'
      using errcode='23514';
  end if;

  select * into v_existing
  from atlas.development_releases r
  where r.development_case_id=p_development_case_id
    and r.idempotency_key=btrim(p_idempotency_key);

  if v_existing.id is not null then
    select array_agg(g.gate_key order by g.gate_key)
    into v_existing_gate_keys
    from atlas.development_release_gates rg
    join atlas.development_standard_gates g on g.id=rg.gate_id
    where rg.release_id=v_existing.id;

    if v_existing.target_version_ref is distinct from btrim(p_target_version_ref)
       or v_existing.release_basis is distinct from btrim(p_release_basis)
       or v_existing.released_by_label is distinct from btrim(p_released_by_label)
       or v_existing.metadata is distinct from p_metadata
       or v_existing_gate_keys is distinct from v_gate_keys then
      raise exception 'Development Release idempotency key contradiction.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'contractVersion','release_development_case_internal_v1',
      'state','unchanged',
      'releaseId',v_existing.id,
      'gateKeys',v_existing_gate_keys
    );
  end if;

  foreach v_gate_key in array v_gate_keys loop
    v_gate_position:=atlas.development_gate_position_v1(
      p_development_case_id,
      v_gate_key
    );

    if v_gate_position->>'state'<>'satisfied' then
      raise exception 'Development gate % is not satisfied.',v_gate_key
        using errcode='23514';
    end if;
  end loop;

  insert into atlas.development_releases(
    development_case_id,target_version_ref,release_basis,
    idempotency_key,released_by_label,metadata
  ) values (
    p_development_case_id,btrim(p_target_version_ref),btrim(p_release_basis),
    btrim(p_idempotency_key),btrim(p_released_by_label),p_metadata
  )
  returning id into v_release_id;

  foreach v_gate_key in array v_gate_keys loop
    select g.id into v_gate_id
    from atlas.development_standard_gates g
    where g.standard_version_id=v_case.standard_version_id
      and g.gate_key=v_gate_key;

    if v_gate_id is null then
      raise exception 'Development gate % is not part of the Case Standard.',v_gate_key
        using errcode='23503';
    end if;

    insert into atlas.development_release_gates(release_id,gate_id)
    values(v_release_id,v_gate_id);
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','release_development_case_internal_v1',
    'state','released',
    'releaseId',v_release_id,
    'targetVersionRef',btrim(p_target_version_ref),
    'gateKeys',to_jsonb(v_gate_keys)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- Browser boundary
-- ---------------------------------------------------------------------------

alter table atlas.development_standard_versions enable row level security;
alter table atlas.development_standard_criteria enable row level security;
alter table atlas.development_standard_gates enable row level security;
alter table atlas.development_standard_gate_requirements enable row level security;
alter table atlas.development_cases enable row level security;
alter table atlas.development_criterion_resolution_events enable row level security;
alter table atlas.development_releases enable row level security;
alter table atlas.development_release_gates enable row level security;

revoke all on atlas.development_standard_versions from public,anon,authenticated;
revoke all on atlas.development_standard_criteria from public,anon,authenticated;
revoke all on atlas.development_standard_gates from public,anon,authenticated;
revoke all on atlas.development_standard_gate_requirements from public,anon,authenticated;
revoke all on atlas.development_cases from public,anon,authenticated;
revoke all on atlas.development_criterion_resolution_events from public,anon,authenticated;
revoke all on atlas.development_releases from public,anon,authenticated;
revoke all on atlas.development_release_gates from public,anon,authenticated;
revoke all on sequence atlas.development_resolution_revision_seq_v1 from public,anon,authenticated,service_role;

grant select,insert,update,delete on atlas.development_standard_versions to service_role;
grant select,insert,update,delete on atlas.development_standard_criteria to service_role;
grant select,insert,update,delete on atlas.development_standard_gates to service_role;
grant select,insert,update,delete on atlas.development_standard_gate_requirements to service_role;
grant select,insert,update,delete on atlas.development_cases to service_role;

revoke all on atlas.development_criterion_resolution_events from service_role;
revoke all on atlas.development_releases from service_role;
revoke all on atlas.development_release_gates from service_role;
grant select on atlas.development_criterion_resolution_events to service_role;
grant select on atlas.development_releases to service_role;
grant select on atlas.development_release_gates to service_role;

revoke all on function atlas.guard_development_organization_ledger_scope_v1()
  from public,anon,authenticated;
revoke all on function atlas.guard_development_case_mutation_v1()
  from public,anon,authenticated;
revoke all on function atlas.guard_development_standard_version_mutation_v1()
  from public,anon,authenticated;
revoke all on function atlas.guard_development_standard_child_mutation_v1()
  from public,anon,authenticated;
revoke all on function atlas.guard_development_resolution_event_v1()
  from public,anon,authenticated;
revoke all on function atlas.prevent_development_history_mutation_v1()
  from public,anon,authenticated;
revoke all on function atlas.guard_development_release_gate_v1()
  from public,anon,authenticated;

revoke all on function atlas.development_current_criterion_resolution_v1(uuid,text)
  from public,anon,authenticated;
revoke all on function atlas.record_development_criterion_resolution_internal_v1(uuid,text,text,text,text,text,text,text,text,jsonb)
  from public,anon,authenticated;
revoke all on function atlas.development_gate_position_v1(uuid,text)
  from public,anon,authenticated;
revoke all on function atlas.release_development_case_internal_v1(uuid,text,text[],text,text,text,jsonb)
  from public,anon,authenticated;

grant execute on function atlas.development_current_criterion_resolution_v1(uuid,text)
  to service_role;
grant execute on function atlas.record_development_criterion_resolution_internal_v1(uuid,text,text,text,text,text,text,text,text,jsonb)
  to service_role;
grant execute on function atlas.development_gate_position_v1(uuid,text)
  to service_role;
grant execute on function atlas.release_development_case_internal_v1(uuid,text,text[],text,text,text,jsonb)
  to service_role;

commit;
