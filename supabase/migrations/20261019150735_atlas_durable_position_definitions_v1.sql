begin;

-- Build 5 continuation, Slice B: institutional Position definition history.
-- Definition text is NEVER an access grant, Work allocation, or appointment.
-- Reuses atlas.organization_positions and its existing appointment identities.

-- Composite foreign keys below prove both referenced objects belong to the
-- same institution. The existing single-column IDs remain canonical.
create unique index organization_positions_org_id_position_id_definitions_v1
  on atlas.organization_positions(organization_id,id);
create unique index ledgers_org_id_ledger_id_definitions_v1
  on atlas.ledgers(organization_id,id);

create table atlas.position_definition_kernels (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null,
  kernel_version integer not null check (kernel_version > 0),
  display_name text not null check (length(btrim(display_name)) between 1 and 160),
  suggested_document jsonb not null check (jsonb_typeof(suggested_document) = 'object'),
  published_at timestamptz not null default now(),
  unique (stable_key, kernel_version),
  check (stable_key ~ '^[a-z][a-z0-9_]*$')
);
comment on table atlas.position_definition_kernels is
  'Immutable reusable position suggestions; adoption copies a snapshot. No authority or appointment follows from a kernel.';

create table atlas.organization_position_ledger_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  position_id uuid not null references atlas.organization_positions(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  source_kernel_id uuid references atlas.position_definition_kernels(id) on delete restrict,
  source_kernel_version integer,
  established_by_person_id uuid not null references reality.entities(id) on delete restrict,
  established_at timestamptz not null default now(),
  unique (position_id, ledger_id),
  foreign key (organization_id,position_id)
    references atlas.organization_positions(organization_id,id) on delete restrict,
  foreign key (organization_id,ledger_id)
    references atlas.ledgers(organization_id,id) on delete restrict,
  check ((source_kernel_id is null) = (source_kernel_version is null))
);
create index organization_position_ledger_definitions_scope_v1
  on atlas.organization_position_ledger_definitions(organization_id, ledger_id, position_id);
comment on table atlas.organization_position_ledger_definitions is
  'Institution-owned definition for one existing Position in one exact native Ledger. Survives vacancy and does not itself confer Ledger access.';

create table atlas.organization_position_definition_revisions (
  id uuid primary key default gen_random_uuid(),
  definition_id uuid not null references atlas.organization_position_ledger_definitions(id) on delete restrict,
  revision_no integer not null check (revision_no > 0),
  document jsonb not null,
  effective_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  authorized_by_person_id uuid not null references reality.entities(id) on delete restrict,
  change_reason text not null check (length(btrim(change_reason)) between 1 and 1200),
  affected_appointment_ids uuid[] not null default '{}',
  unique (definition_id, revision_no),
  check (jsonb_typeof(document) = 'object'),
  check (octet_length(document::text) <= 32768)
);
create index organization_position_definition_revisions_time_v1
  on atlas.organization_position_definition_revisions
  (definition_id, effective_at desc, revision_no desc);
comment on table atlas.organization_position_definition_revisions is
  'Append-only authored/effective history of institutional position expectations. Affected appointment IDs are factual at authoring time, not proof of accepted expanded authority.';

-- No direct reads or writes on these tables by API roles; authenticated
-- projections must pass owner authorization at the RPC boundary.
alter table atlas.position_definition_kernels enable row level security;
alter table atlas.organization_position_ledger_definitions enable row level security;
alter table atlas.organization_position_definition_revisions enable row level security;
revoke all on table atlas.position_definition_kernels from public, anon, authenticated;
revoke all on table atlas.organization_position_ledger_definitions from public, anon, authenticated;
revoke all on table atlas.organization_position_definition_revisions from public, anon, authenticated;

create function atlas.prevent_position_definition_history_mutation_v1()
returns trigger language plpgsql volatile security invoker set search_path to ''
as $fn$
begin
  raise exception 'Published position definition provenance/history is append-only'
    using errcode = '23514';
end
$fn$;
create trigger position_definition_kernels_immutable_v1
  before update or delete on atlas.position_definition_kernels
  for each row execute function atlas.prevent_position_definition_history_mutation_v1();
create trigger organization_position_definitions_immutable_v1
  before update or delete on atlas.organization_position_ledger_definitions
  for each row execute function atlas.prevent_position_definition_history_mutation_v1();
create trigger organization_position_revisions_immutable_v1
  before update or delete on atlas.organization_position_definition_revisions
  for each row execute function atlas.prevent_position_definition_history_mutation_v1();
revoke all on function atlas.prevent_position_definition_history_mutation_v1()
  from public, anon, authenticated;

create function atlas.position_definition_document_valid_v1(p_document jsonb)
returns boolean language sql immutable security invoker set search_path to ''
as $fn$
  select coalesce(
    jsonb_typeof(p_document) = 'object'
    and octet_length(p_document::text) <= 32768
    and jsonb_typeof(p_document->'purpose') = 'string'
    and length(btrim(p_document->>'purpose')) between 1 and 4000
    and jsonb_typeof(p_document->'outcomes') = 'array'
    and jsonb_typeof(p_document->'requirements') = 'array'
    and jsonb_typeof(p_document->'responsibilityNotes') = 'array'
    and jsonb_typeof(p_document->'reporting') = 'object'
    and jsonb_typeof(p_document->'operatingConditions') = 'object'
    and jsonb_typeof(p_document->'requestedAccess') = 'object'
    and (p_document->'requestedAccess' ?& array['view','record','manage','approve','excluded'])
    and jsonb_typeof(p_document#>'{requestedAccess,view}') = 'array'
    and jsonb_typeof(p_document#>'{requestedAccess,record}') = 'array'
    and jsonb_typeof(p_document#>'{requestedAccess,manage}') = 'array'
    and jsonb_typeof(p_document#>'{requestedAccess,approve}') = 'array'
    and jsonb_typeof(p_document#>'{requestedAccess,excluded}') = 'array'
    and not exists (
      select 1 from jsonb_object_keys(p_document) as k(key)
      where k.key not in ('purpose','outcomes','requirements','responsibilityNotes',
        'reporting','operatingConditions','requestedAccess')
    ), false);
$fn$;
revoke all on function atlas.position_definition_document_valid_v1(jsonb)
  from public, anon, authenticated;
alter table atlas.organization_position_definition_revisions
  add constraint organization_position_revision_document_valid_v1
  check (atlas.position_definition_document_valid_v1(document));

-- A small general catalog; no Farm Steward hard-coded privilege. Catalog
-- publication is deliberately versioned and templates cannot be edited in place.
insert into atlas.position_definition_kernels
  (stable_key, kernel_version, display_name, suggested_document)
select k.stable_key, 1, k.display_name,
  jsonb_build_object(
    'purpose', k.purpose,
    'outcomes', '[]'::jsonb,
    'requirements', '[]'::jsonb,
    'responsibilityNotes', '[]'::jsonb,
    'reporting', '{}'::jsonb,
    'operatingConditions', '{}'::jsonb,
    'requestedAccess', jsonb_build_object(
      'view', '[]'::jsonb, 'record', '[]'::jsonb,
      'manage', '[]'::jsonb, 'approve', '[]'::jsonb,
      'excluded', '[]'::jsonb))
from (values
  ('farm_operations','Farm Operations','Coordinate routine farm operations and maintain agreed operating standards.'),
  ('production_steward','Production Steward','Steward the continuity and quality of an institution''s production.'),
  ('administrative_coordinator','Administrative Coordinator','Coordinate administrative processes and reporting.'),
  ('sales_representative','Sales Representative','Support authorized sales relationships and follow-through.'),
  ('marketing_manager','Marketing Manager','Coordinate authorized marketing plans and execution.')
) as k(stable_key,display_name,purpose)
on conflict (stable_key,kernel_version) do nothing;

create function atlas.position_definition_kernels_self_api_v1()
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
begin
  if auth.uid() is null or atlas.current_person_id_v1() is null then
    raise exception 'Canonical signed-in Person required' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'contractVersion','position_definition_kernels_v1',
    'kernels',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',k.id,'stableKey',k.stable_key,'version',k.kernel_version,
        'displayName',k.display_name,'suggestedDocument',k.suggested_document)
        order by k.display_name,k.kernel_version desc)
      from atlas.position_definition_kernels k
    ),'[]'::jsonb));
end
$fn$;
revoke all on function atlas.position_definition_kernels_self_api_v1()
  from public, anon, authenticated;
grant execute on function atlas.position_definition_kernels_self_api_v1()
  to authenticated;

create function atlas.position_definition_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_position_id uuid)
returns jsonb language plpgsql stable security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_definition atlas.organization_position_ledger_definitions%rowtype;
begin
  if auth.uid() is null or p_organization_id is null
    or p_ledger_id is null or p_position_id is null then
    raise exception 'Exact signed-in organization, Ledger and Position required'
      using errcode = '42501';
  end if;
  v_owner := atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact native Ledger owner required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from atlas.organization_positions p
    where p.id=p_position_id and p.organization_id=p_organization_id
  ) then
    raise exception 'Position is outside this organization' using errcode='42501';
  end if;
  select * into v_definition from atlas.organization_position_ledger_definitions
    where organization_id=p_organization_id and ledger_id=p_ledger_id
      and position_id=p_position_id;
  return jsonb_build_object(
    'contractVersion','position_definition_owner_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'positionId',p_position_id,'definitionId',v_definition.id,
    'sourceKernelId',v_definition.source_kernel_id,
    'sourceKernelVersion',v_definition.source_kernel_version,
    'revisions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'revision',r.revision_no,'document',r.document,
        'effectiveAt',r.effective_at,'recordedAt',r.recorded_at,
        'authorizedByPersonId',r.authorized_by_person_id,
        'changeReason',r.change_reason,
        'affectedAppointmentIds',r.affected_appointment_ids)
        order by r.revision_no)
      from atlas.organization_position_definition_revisions r
      where r.definition_id=v_definition.id
    ),'[]'::jsonb),
    'effectiveRevision',(
      select r.revision_no from atlas.organization_position_definition_revisions r
      where r.definition_id=v_definition.id and r.effective_at<=now()
      order by r.effective_at desc,r.revision_no desc limit 1
    ),
    'latestRevision',(
      select max(r.revision_no) from atlas.organization_position_definition_revisions r
      where r.definition_id=v_definition.id
    ));
end
$fn$;
revoke all on function atlas.position_definition_owner_self_api_v1(uuid,uuid,uuid)
  from public, anon, authenticated;
grant execute on function atlas.position_definition_owner_self_api_v1(uuid,uuid,uuid)
  to authenticated;

create function atlas.save_position_definition_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_position_id uuid,
  p_document jsonb, p_reason text, p_expected_revision integer,
  p_source_kernel_id uuid default null, p_effective_at timestamptz default now())
returns jsonb language plpgsql volatile security definer set search_path to ''
as $fn$
declare
  v_owner uuid;
  v_definition atlas.organization_position_ledger_definitions%rowtype;
  v_kernel atlas.position_definition_kernels%rowtype;
  v_last_revision integer;
  v_last_effective timestamptz;
  v_affected uuid[];
  v_revision atlas.organization_position_definition_revisions%rowtype;
begin
  if auth.uid() is null or p_organization_id is null or p_ledger_id is null
     or p_position_id is null then
    raise exception 'Exact signed-in organization, Ledger and Position required'
      using errcode='42501';
  end if;
  v_owner := atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  if v_owner is distinct from atlas.current_person_id_v1() then
    raise exception 'Exact native Ledger owner required' using errcode='42501';
  end if;
  if not atlas.position_definition_document_valid_v1(p_document) then
    raise exception 'Structured position document is required' using errcode='22023';
  end if;
  if p_expected_revision is null or p_expected_revision<0
    or nullif(btrim(coalesce(p_reason,'')),'') is null
    or length(btrim(p_reason))>1200 or p_effective_at is null then
    raise exception 'Expected revision, change reason and effective time required'
      using errcode='22023';
  end if;
  if p_effective_at < now() - interval '5 minutes' then
    raise exception 'Historical effective-time backdating is not supported'
      using errcode='22023';
  end if;
  -- Serialize modifications to the canonical Position, including first save.
  perform 1 from atlas.organization_positions p
    where p.id=p_position_id and p.organization_id=p_organization_id
      and p.status='active' for update;
  if not found then
    raise exception 'Active Position in exact organization required'
      using errcode='23514';
  end if;
  if not exists (
    select 1 from atlas.ledgers l where l.id=p_ledger_id
      and l.organization_id=p_organization_id and l.status='active'
  ) then
    raise exception 'Active exact organization native Ledger required'
      using errcode='23514';
  end if;
  select * into v_definition from atlas.organization_position_ledger_definitions d
    where d.organization_id=p_organization_id
      and d.position_id=p_position_id and d.ledger_id=p_ledger_id for update;
  if v_definition.id is null then
    if p_expected_revision<>0 then
      raise exception 'Definition was concurrently established; reread'
        using errcode='40001';
    end if;
    if p_source_kernel_id is not null then
      select * into v_kernel from atlas.position_definition_kernels
        where id=p_source_kernel_id;
      if v_kernel.id is null then
        raise exception 'Known published kernel required' using errcode='23514';
      end if;
    end if;
    insert into atlas.organization_position_ledger_definitions
      (organization_id,position_id,ledger_id,source_kernel_id,
       source_kernel_version,established_by_person_id)
    values (p_organization_id,p_position_id,p_ledger_id,v_kernel.id,
      v_kernel.kernel_version,v_owner) returning * into v_definition;
    v_last_revision:=0;
  else
    if p_source_kernel_id is distinct from v_definition.source_kernel_id then
      raise exception 'Source-kernel provenance cannot be silently replaced'
        using errcode='23514';
    end if;
    select r.revision_no,r.effective_at
      into v_last_revision,v_last_effective
    from atlas.organization_position_definition_revisions r
    where r.definition_id=v_definition.id
    order by r.revision_no desc limit 1;
  end if;
  if p_expected_revision is distinct from v_last_revision then
    raise exception 'Position definition changed; reread before saving'
      using errcode='40001';
  end if;
  if v_last_effective is not null and p_effective_at < v_last_effective then
    raise exception 'Effective history must remain monotonic'
      using errcode='22023';
  end if;
  select coalesce(array_agg(a.id order by a.id),'{}'::uuid[])
    into v_affected
  from atlas.organization_position_appointments a
  where a.organization_id=p_organization_id and a.position_id=p_position_id
    and a.status='active' and a.begins_at<=p_effective_at
    and (a.ends_at is null or a.ends_at>p_effective_at);
  insert into atlas.organization_position_definition_revisions
    (definition_id,revision_no,document,effective_at,authorized_by_person_id,
     change_reason,affected_appointment_ids)
  values (v_definition.id,v_last_revision+1,p_document,p_effective_at,v_owner,
    btrim(p_reason),v_affected)
  returning * into v_revision;
  return jsonb_build_object(
    'ok',true,'contractVersion','position_definition_save_v1',
    'definitionId',v_definition.id,'revisionId',v_revision.id,
    'revision',v_revision.revision_no,'positionId',p_position_id,
    'ledgerId',p_ledger_id,'effectiveAt',v_revision.effective_at,
    'affectedAppointmentIds',v_affected,
    'accessChanged',false,'standingAssignmentChanged',false,
    'nativeLedgerSeatChanged',false,'workAllocationChanged',false);
end
$fn$;
revoke all on function atlas.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)
  from public, anon, authenticated;
grant execute on function atlas.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)
  to authenticated;

create function public.position_definition_kernels_self_api_v1()
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.position_definition_kernels_self_api_v1() $fn$;
create function public.position_definition_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_position_id uuid)
returns jsonb language sql stable security invoker set search_path to ''
as $fn$ select atlas.position_definition_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_position_id) $fn$;
create function public.save_position_definition_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_position_id uuid,
  p_document jsonb,p_reason text,p_expected_revision integer,
  p_source_kernel_id uuid default null,p_effective_at timestamptz default now())
returns jsonb language sql volatile security invoker set search_path to ''
as $fn$ select atlas.save_position_definition_owner_self_api_v1(
  p_organization_id,p_ledger_id,p_position_id,p_document,p_reason,
  p_expected_revision,p_source_kernel_id,p_effective_at) $fn$;

revoke all on function public.position_definition_kernels_self_api_v1()
  from public, anon, authenticated;
revoke all on function public.position_definition_owner_self_api_v1(uuid,uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)
  from public, anon, authenticated;
grant execute on function public.position_definition_kernels_self_api_v1()
  to authenticated;
grant execute on function public.position_definition_owner_self_api_v1(uuid,uuid,uuid)
  to authenticated;
grant execute on function public.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz)
  to authenticated;

comment on function public.save_position_definition_owner_self_api_v1(uuid,uuid,uuid,jsonb,text,integer,uuid,timestamptz) is
  'Owner-only, exact-Ledger append-only institutional definition revision. requestedAccess is descriptive intent ONLY, not a grant. Does not alter appointments, Work, native seats, permissions or accepted standing agreements.';

commit;
