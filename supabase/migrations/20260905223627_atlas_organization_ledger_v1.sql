-- Atlas Organization Ledger v1 — persistent projection contract.
-- Generic organization-scoped institutional movement projection beside the
-- legacy farm Journal. Canonical source-domain ownership remains unchanged.

-- Fail rather than collide with an independently released contract.
do $preflight$
begin
  if to_regclass('atlas.organization_ledger_entries') is not null
     or to_regclass('atlas.organization_ledger_subjects') is not null then
    raise exception 'Organization Ledger objects already exist; review the released contract instead of applying this migration.';
  end if;
end;
$preflight$;

create sequence atlas.organization_ledger_revision_seq_v1 as bigint start 1;

create table atlas.organization_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid,
  event_key text not null,
  source_domain text not null,
  semantic_type text not null,
  source_event_key text,
  occurred_at timestamptz not null,
  established_at timestamptz not null default now(),
  title text not null,
  detail text,
  truth_status text not null default 'established'
    check (truth_status in ('established','observed','inferred','disputed','unresolved')),
  designation_status text not null default 'designated'
    check (designation_status in ('designated','unresolved','conflict','closed')),
  payload jsonb not null default '{}'::jsonb,
  provenance jsonb not null default '{}'::jsonb,
  correlation jsonb not null default '{}'::jsonb,
  revision bigint not null default nextval('atlas.organization_ledger_revision_seq_v1'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_ledger_event_key_not_blank check (btrim(event_key) <> ''),
  constraint organization_ledger_source_domain_not_blank check (btrim(source_domain) <> ''),
  constraint organization_ledger_semantic_type_not_blank check (btrim(semantic_type) <> ''),
  constraint organization_ledger_title_not_blank check (btrim(title) <> ''),
  constraint organization_ledger_org_event_key_uq unique (organization_id,event_key),
  constraint organization_ledger_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id)
    on delete restrict
);

comment on table atlas.organization_ledger_entries is
  'Role-safe projection of meaningful institutional movement. This table is not canonical source-domain truth.';
comment on column atlas.organization_ledger_entries.revision is
  'Monotonic projection revision for targeted runtime reconciliation; not source-domain entity revision.';
comment on column atlas.organization_ledger_entries.designation_status is
  'Projection orientation only: whether the movement is lawfully situated, unresolved, conflicting, or closed. Does not replace source-domain lifecycle state.';

create index organization_ledger_entries_org_time_idx
  on atlas.organization_ledger_entries(organization_id,occurred_at,id);
create index organization_ledger_entries_org_revision_idx
  on atlas.organization_ledger_entries(organization_id,revision);
create index organization_ledger_entries_org_designation_idx
  on atlas.organization_ledger_entries(organization_id,designation_status,occurred_at desc);
create index organization_ledger_entries_unit_time_idx
  on atlas.organization_ledger_entries(organization_id,organization_unit_id,occurred_at,id)
  where organization_unit_id is not null;

create table atlas.organization_ledger_subjects (
  id uuid primary key default gen_random_uuid(),
  ledger_entry_id uuid not null references atlas.organization_ledger_entries(id) on delete cascade,
  subject_domain text not null,
  subject_kind text not null,
  subject_id text not null,
  relation_kind text not null default 'about',
  provenance jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint organization_ledger_subject_domain_not_blank check (btrim(subject_domain) <> ''),
  constraint organization_ledger_subject_kind_not_blank check (btrim(subject_kind) <> ''),
  constraint organization_ledger_subject_id_not_blank check (btrim(subject_id) <> ''),
  constraint organization_ledger_subject_relation_not_blank check (btrim(relation_kind) <> ''),
  constraint organization_ledger_subject_identity_uq
    unique (ledger_entry_id,subject_domain,subject_kind,subject_id,relation_kind)
);

comment on table atlas.organization_ledger_subjects is
  'Typed subject links for one Organization Ledger projection entry. Links do not copy source ownership or create causal truth.';

create index organization_ledger_subjects_entry_idx
  on atlas.organization_ledger_subjects(ledger_entry_id,created_at,id);
create index organization_ledger_subjects_subject_idx
  on atlas.organization_ledger_subjects(subject_domain,subject_kind,subject_id,ledger_entry_id);

alter table atlas.organization_ledger_entries enable row level security;
alter table atlas.organization_ledger_subjects enable row level security;

revoke all on table atlas.organization_ledger_entries from public,anon,authenticated;
revoke all on table atlas.organization_ledger_subjects from public,anon,authenticated;
revoke all on sequence atlas.organization_ledger_revision_seq_v1 from public,anon,authenticated;

-- Projection admission is an internal consequence adapter, never a public
-- canonical business writer.
create or replace function atlas.project_organization_ledger_event_internal_v1(
  p_organization_id uuid,
  p_organization_unit_id uuid,
  p_event_key text,
  p_source_domain text,
  p_semantic_type text,
  p_source_event_key text,
  p_occurred_at timestamptz,
  p_title text,
  p_detail text default null,
  p_truth_status text default 'established',
  p_designation_status text default 'designated',
  p_payload jsonb default '{}'::jsonb,
  p_provenance jsonb default '{}'::jsonb,
  p_correlation jsonb default '{}'::jsonb,
  p_established_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_existing atlas.organization_ledger_entries%rowtype;
  v_row atlas.organization_ledger_entries%rowtype;
  v_revision bigint;
begin
  if p_organization_id is null
     or not exists (select 1 from atlas.organizations o where o.id=p_organization_id) then
    raise exception 'Organization Ledger projection requires a valid Organization.' using errcode='23503';
  end if;
  if p_organization_unit_id is not null
     and not exists (
       select 1 from atlas.organization_units ou
       where ou.organization_id=p_organization_id and ou.id=p_organization_unit_id
     ) then
    raise exception 'Organization Unit does not belong to the Organization.' using errcode='23503';
  end if;
  if nullif(btrim(p_event_key),'') is null
     or nullif(btrim(p_source_domain),'') is null
     or nullif(btrim(p_semantic_type),'') is null
     or nullif(btrim(p_title),'') is null
     or p_occurred_at is null then
    raise exception 'Event key, source domain, semantic type, occurrence time, and title are required.' using errcode='22023';
  end if;
  if p_truth_status not in ('established','observed','inferred','disputed','unresolved') then
    raise exception 'Unsupported Ledger truth status.' using errcode='22023';
  end if;
  if p_designation_status not in ('designated','unresolved','conflict','closed') then
    raise exception 'Unsupported Ledger designation status.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('atlas.organization_ledger:'||p_organization_id::text||':'||btrim(p_event_key),0));

  select * into v_existing
  from atlas.organization_ledger_entries e
  where e.organization_id=p_organization_id and e.event_key=btrim(p_event_key)
  for update;

  if v_existing.id is not null then
    if v_existing.source_domain is distinct from lower(btrim(p_source_domain))
       or v_existing.semantic_type is distinct from lower(btrim(p_semantic_type))
       or v_existing.source_event_key is distinct from nullif(btrim(coalesce(p_source_event_key,'')),'') then
      raise exception 'Existing Ledger event identity cannot be rebound to different source semantics.' using errcode='23514';
    end if;

    if v_existing.organization_unit_id is not distinct from p_organization_unit_id
       and v_existing.occurred_at is not distinct from p_occurred_at
       and v_existing.title is not distinct from btrim(p_title)
       and v_existing.detail is not distinct from nullif(btrim(coalesce(p_detail,'')),'')
       and v_existing.truth_status is not distinct from p_truth_status
       and v_existing.designation_status is not distinct from p_designation_status
       and v_existing.payload is not distinct from coalesce(p_payload,'{}'::jsonb)
       and v_existing.provenance is not distinct from coalesce(p_provenance,'{}'::jsonb)
       and v_existing.correlation is not distinct from coalesce(p_correlation,'{}'::jsonb) then
      return jsonb_build_object(
        'contractVersion','project_organization_ledger_event_internal_v1',
        'state','unchanged','entryId',v_existing.id,'revision',v_existing.revision
      );
    end if;

    v_revision:=nextval('atlas.organization_ledger_revision_seq_v1');
    update atlas.organization_ledger_entries
    set organization_unit_id=p_organization_unit_id,
        occurred_at=p_occurred_at,
        established_at=coalesce(p_established_at,v_existing.established_at),
        title=btrim(p_title),
        detail=nullif(btrim(coalesce(p_detail,'')),''),
        truth_status=p_truth_status,
        designation_status=p_designation_status,
        payload=coalesce(p_payload,'{}'::jsonb),
        provenance=coalesce(p_provenance,'{}'::jsonb),
        correlation=coalesce(p_correlation,'{}'::jsonb),
        revision=v_revision,
        updated_at=now()
    where id=v_existing.id
    returning * into v_row;

    return jsonb_build_object(
      'contractVersion','project_organization_ledger_event_internal_v1',
      'state','revised','entryId',v_row.id,'revision',v_row.revision
    );
  end if;

  insert into atlas.organization_ledger_entries(
    organization_id,organization_unit_id,event_key,source_domain,semantic_type,source_event_key,
    occurred_at,established_at,title,detail,truth_status,designation_status,payload,provenance,correlation
  ) values (
    p_organization_id,p_organization_unit_id,btrim(p_event_key),lower(btrim(p_source_domain)),lower(btrim(p_semantic_type)),
    nullif(btrim(coalesce(p_source_event_key,'')),''),p_occurred_at,coalesce(p_established_at,now()),btrim(p_title),
    nullif(btrim(coalesce(p_detail,'')),''),p_truth_status,p_designation_status,coalesce(p_payload,'{}'::jsonb),
    coalesce(p_provenance,'{}'::jsonb),coalesce(p_correlation,'{}'::jsonb)
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','project_organization_ledger_event_internal_v1',
    'state','admitted','entryId',v_row.id,'revision',v_row.revision
  );
end;
$function$;

revoke all on function atlas.project_organization_ledger_event_internal_v1(
  uuid,uuid,text,text,text,text,timestamptz,text,text,text,text,jsonb,jsonb,jsonb,timestamptz
) from public,anon,authenticated;
grant execute on function atlas.project_organization_ledger_event_internal_v1(
  uuid,uuid,text,text,text,text,timestamptz,text,text,text,text,jsonb,jsonb,jsonb,timestamptz
) to postgres,service_role;

create or replace function atlas.link_organization_ledger_subject_internal_v1(
  p_ledger_entry_id uuid,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_relation_kind text default 'about',
  p_provenance jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog,atlas
as $function$
declare
  v_id uuid;
  v_revision bigint;
begin
  if p_ledger_entry_id is null
     or nullif(btrim(p_subject_domain),'') is null
     or nullif(btrim(p_subject_kind),'') is null
     or nullif(btrim(p_subject_id),'') is null
     or nullif(btrim(p_relation_kind),'') is null then
    raise exception 'Ledger subject identity and relation are required.' using errcode='22023';
  end if;
  if not exists (select 1 from atlas.organization_ledger_entries e where e.id=p_ledger_entry_id) then
    raise exception 'Ledger entry not found.' using errcode='P0002';
  end if;

  insert into atlas.organization_ledger_subjects(
    ledger_entry_id,subject_domain,subject_kind,subject_id,relation_kind,provenance,metadata
  ) values (
    p_ledger_entry_id,lower(btrim(p_subject_domain)),lower(btrim(p_subject_kind)),btrim(p_subject_id),
    lower(btrim(p_relation_kind)),coalesce(p_provenance,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb)
  ) on conflict (ledger_entry_id,subject_domain,subject_kind,subject_id,relation_kind) do nothing
  returning id into v_id;

  if v_id is null then
    select e.revision into v_revision from atlas.organization_ledger_entries e where e.id=p_ledger_entry_id;
    return jsonb_build_object('state','unchanged','entryId',p_ledger_entry_id,'revision',v_revision);
  end if;

  v_revision:=nextval('atlas.organization_ledger_revision_seq_v1');
  update atlas.organization_ledger_entries
  set revision=v_revision,updated_at=now()
  where id=p_ledger_entry_id;

  return jsonb_build_object('state','linked','entryId',p_ledger_entry_id,'subjectLinkId',v_id,'revision',v_revision);
end;
$function$;

revoke all on function atlas.link_organization_ledger_subject_internal_v1(uuid,text,text,text,text,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.link_organization_ledger_subject_internal_v1(uuid,text,text,text,text,jsonb,jsonb)
  to postgres,service_role;

-- Conservative V1 read: owner only. Final manager/steward scope must consume a
-- released authority/permission projection rather than infer authority from role labels.
create or replace function atlas.organization_ledger_owner_window_api_v1(
  p_organization_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_after_revision bigint default 0,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
as $function$
declare
  v_items jsonb;
  v_max_revision bigint;
begin
  if auth.uid() is null or not atlas.is_organization_owner(p_organization_id) then
    raise exception 'Organization owner access is required.' using errcode='42501';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then
    raise exception 'A valid half-open occurrence window is required.' using errcode='22023';
  end if;
  if coalesce(p_after_revision,0)<0 then
    raise exception 'Revision cursor cannot be negative.' using errcode='22023';
  end if;
  if coalesce(p_limit,0)<1 or p_limit>500 then
    raise exception 'Ledger page limit must be between 1 and 500.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(item order by occurred_at,revision,id),'[]'::jsonb),coalesce(max(revision),p_after_revision)
  into v_items,v_max_revision
  from (
    select e.id,e.event_key,e.source_domain,e.semantic_type,e.source_event_key,
      e.organization_unit_id,e.occurred_at,e.established_at,e.title,e.detail,
      e.truth_status,e.designation_status,e.payload,e.provenance,e.correlation,e.revision,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'subjectDomain',s.subject_domain,'subjectKind',s.subject_kind,'subjectId',s.subject_id,
          'relationKind',s.relation_kind,'provenance',s.provenance,'metadata',s.metadata
        ) order by s.created_at,s.id)
        from atlas.organization_ledger_subjects s
        where s.ledger_entry_id=e.id
      ),'[]'::jsonb) as subjects,
      jsonb_build_object(
        'entryId',e.id,'eventKey',e.event_key,'sourceDomain',e.source_domain,
        'semanticType',e.semantic_type,'sourceEventKey',e.source_event_key,
        'organizationUnitId',e.organization_unit_id,'occurredAt',e.occurred_at,
        'establishedAt',e.established_at,'title',e.title,'detail',e.detail,
        'truthStatus',e.truth_status,'designationStatus',e.designation_status,
        'payload',e.payload,'provenance',e.provenance,'correlation',e.correlation,
        'revision',e.revision,
        'subjects',coalesce((
          select jsonb_agg(jsonb_build_object(
            'subjectDomain',s2.subject_domain,'subjectKind',s2.subject_kind,'subjectId',s2.subject_id,
            'relationKind',s2.relation_kind,'provenance',s2.provenance,'metadata',s2.metadata
          ) order by s2.created_at,s2.id)
          from atlas.organization_ledger_subjects s2
          where s2.ledger_entry_id=e.id
        ),'[]'::jsonb)
      ) as item
    from atlas.organization_ledger_entries e
    where e.organization_id=p_organization_id
      and e.occurred_at>=p_start_at and e.occurred_at<p_end_at
      and e.revision>coalesce(p_after_revision,0)
    order by e.occurred_at,e.revision,e.id
    limit p_limit
  ) q;

  return jsonb_build_object(
    'contractVersion','organization_ledger_owner_window_api_v1',
    'organizationId',p_organization_id,
    'startAt',p_start_at,'endAt',p_end_at,
    'afterRevision',coalesce(p_after_revision,0),
    'maxRevision',v_max_revision,
    'items',v_items
  );
end;
$function$;

revoke all on function atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer)
  from public,anon;
grant execute on function atlas.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer)
  to authenticated;