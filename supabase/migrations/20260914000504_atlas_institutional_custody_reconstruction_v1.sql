-- Atlas Institutional Custody Reconstruction v1.
-- Canonical forward reconstruction after Ledger Graph v1.
-- Governing rule: no production/runtime trigger is suspended, disabled, skipped,
-- bypassed, or made conditionally inert for custody reconstruction.
-- Existing mixed-container rows remain physically preserved. Canonical custody is
-- established through immutable adjudication plus a compatibility-carrier membrane.

BEGIN;

create table atlas.institutional_custody_adjudications (
  id uuid primary key default gen_random_uuid(),
  subject_schema text not null check (btrim(subject_schema) <> ''),
  subject_table text not null check (btrim(subject_table) <> ''),
  subject_key text not null check (btrim(subject_key) <> ''),
  disposition text not null check (disposition in ('reassigned','archived','unresolved')),
  historical_organization_id uuid references atlas.organizations(id) on delete restrict,
  historical_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  canonical_organization_id uuid references atlas.organizations(id) on delete restrict,
  canonical_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  evidence_basis text not null check (btrim(evidence_basis) <> ''),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  adjudicated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (subject_schema,subject_table,subject_key),
  check (
    disposition <> 'reassigned'
    or canonical_organization_id is not null
    or canonical_ledger_id is not null
  )
);

create table atlas.institutional_custody_carriers (
  id uuid primary key default gen_random_uuid(),
  carrier_organization_id uuid not null references atlas.organizations(id) on delete restrict,
  carrier_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  carrier_kind text not null check (carrier_kind in ('legacy_mixed_scope')),
  status text not null default 'active' check (status in ('active','ended')),
  basis text not null check (btrim(basis) <> ''),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (carrier_organization_id,carrier_ledger_id)
);

create table atlas.institutional_custody_carrier_targets (
  id uuid primary key default gen_random_uuid(),
  carrier_id uuid not null references atlas.institutional_custody_carriers(id) on delete restrict,
  target_key text not null check (btrim(target_key) <> ''),
  canonical_organization_id uuid references atlas.organizations(id) on delete restrict,
  canonical_ledger_id uuid references atlas.ledgers(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  unique (carrier_id,target_key),
  check (canonical_organization_id is not null or canonical_ledger_id is not null)
);

alter table atlas.institutional_custody_adjudications enable row level security;
alter table atlas.institutional_custody_carriers enable row level security;
alter table atlas.institutional_custody_carrier_targets enable row level security;

revoke all on atlas.institutional_custody_adjudications from anon,authenticated;
revoke all on atlas.institutional_custody_carriers from anon,authenticated;
revoke all on atlas.institutional_custody_carrier_targets from anon,authenticated;
grant select,insert on atlas.institutional_custody_adjudications to service_role;
grant select,insert,update on atlas.institutional_custody_carriers to service_role;
grant select,insert on atlas.institutional_custody_carrier_targets to service_role;

create or replace function atlas.institutional_custody_adjudication_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Institutional custody adjudications are append-only.' using errcode='55000';
end;
$function$;

revoke all on function atlas.institutional_custody_adjudication_immutable_v1()
  from public,anon,authenticated;

drop trigger if exists institutional_custody_adjudications_immutable_v1
  on atlas.institutional_custody_adjudications;
create trigger institutional_custody_adjudications_immutable_v1
before update or delete on atlas.institutional_custody_adjudications
for each row execute function atlas.institutional_custody_adjudication_immutable_v1();

create or replace function atlas.effective_institutional_custody_v1(
  p_subject_schema text,
  p_subject_table text,
  p_subject_key text,
  p_physical_organization_id uuid default null,
  p_physical_ledger_id uuid default null
)
returns table(
  effective_organization_id uuid,
  effective_ledger_id uuid,
  disposition text,
  evidence_basis text,
  from_adjudication boolean
)
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  with a as (
    select x.*
    from atlas.institutional_custody_adjudications x
    where x.subject_schema=btrim(p_subject_schema)
      and x.subject_table=btrim(p_subject_table)
      and x.subject_key=btrim(p_subject_key)
    limit 1
  )
  select
    case when a.id is not null then a.canonical_organization_id else p_physical_organization_id end,
    case when a.id is not null then a.canonical_ledger_id else p_physical_ledger_id end,
    coalesce(a.disposition,'physical'),
    coalesce(a.evidence_basis,'physical_custody'),
    a.id is not null
  from (select 1) q
  left join a on true;
$function$;

revoke all on function atlas.effective_institutional_custody_v1(text,text,text,uuid,uuid)
  from public,anon,authenticated;
grant execute on function atlas.effective_institutional_custody_v1(text,text,text,uuid,uuid)
  to service_role;

comment on table atlas.institutional_custody_adjudications is
  'Immutable canonical custody decisions over physically preserved historical/compatibility rows.';
comment on table atlas.institutional_custody_carriers is
  'Explicit compatibility carriers whose physical scope remains in place while canonical custody converges forward.';
comment on function atlas.effective_institutional_custody_v1(text,text,text,uuid,uuid) is
  'Resolves canonical custody from immutable adjudication without rewriting source history.';

-- Exact production anchors. Fail closed if the mixed-container evidence changed.
do $function$
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Expected historical mixed Organization is unavailable or changed.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Expected historical mixed Ledger is unavailable or changed.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.principals
    where id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
      and person_id='59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid
      and status='active'
  ) then
    raise exception 'Expected Lex Principal / Person identity is unavailable.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.organization_units
    where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) or not exists (
    select 1 from atlas.farms
    where id='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Expected Elm historical anchors are unavailable.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.organization_units
    where id='999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) or not exists (
    select 1 from atlas.farms
    where id='f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid
      and organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Expected Waiting Room historical anchors are unavailable.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.organization_memberships
    where id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid
      and person_id='998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid and active
  ) or not exists (
    select 1 from atlas.organization_employee_seats
    where id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid and status='active'
  ) then
    raise exception 'Expected Anna employment anchors are unavailable.' using errcode='P0002';
  end if;
end;
$function$;

-- Establish forward canonical identities without mutating the compatibility carrier.
do $function$
declare
  v_elm_result jsonb;
  v_fg_result jsonb;
  v_venue_result jsonb;
  v_elm_org uuid;
  v_elm_farm_ledger uuid;
  v_elm_venue_ledger uuid;
  v_fg_org uuid;
  v_fg_ledger uuid;
  v_carrier uuid;
begin
  v_elm_result := atlas.establish_organization_ledger_for_principal_v1(
    'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    null,
    'Elm Farm',
    false,
    false,
    'institutional_custody_reconstruction_v1'
  );
  v_elm_org := (v_elm_result->'organization'->>'id')::uuid;
  v_elm_farm_ledger := (v_elm_result->'ledger'->>'id')::uuid;

  update atlas.organizations
  set metadata=metadata || jsonb_build_object(
    'custody_reconstruction_key','elm_farm_organization_v1',
    'canonicalInstitution','Elm Farm',
    'custodyMode','adjudication_backed_pending_runtime_cutover'
  )
  where id=v_elm_org;

  update atlas.ledgers
  set metadata=metadata || jsonb_build_object(
    'custody_reconstruction_key','elm_farm_ledger_v1',
    'canonicalEndeavor','Elm Farm',
    'custodyMode','adjudication_backed_pending_runtime_cutover'
  )
  where id=v_elm_farm_ledger;

  v_venue_result := atlas.establish_ledger_for_principal_v1(
    'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    'Elm Venue','governed_reality','institutional_custody_reconstruction_v1',
    jsonb_build_object(
      'custody_reconstruction_key','elm_venue_ledger_v1',
      'canonicalEndeavor','Elm Venue',
      'custodyMode','adjudication_backed_pending_runtime_cutover'
    )
  );
  v_elm_venue_ledger := (v_venue_result->'ledger'->>'id')::uuid;

  perform atlas.establish_ledger_organization_participation_v1(
    v_elm_venue_ledger,v_elm_org,'operating',false,
    jsonb_build_object('source','institutional_custody_reconstruction_v1'),
    jsonb_build_object('endeavor','Elm Venue')
  );

  perform atlas.establish_ledger_relationship_v1(
    v_elm_farm_ledger,v_elm_venue_ledger,'sibling','symmetric',
    jsonb_build_object('source','institutional_custody_reconstruction_v1','reason','shared Elm institution with independent governing methods'),
    '{}'::jsonb
  );

  v_fg_result := atlas.establish_organization_ledger_for_principal_v1(
    'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    null,
    'Feast Guild',
    false,
    false,
    'institutional_custody_reconstruction_v1'
  );
  v_fg_org := (v_fg_result->'organization'->>'id')::uuid;
  v_fg_ledger := (v_fg_result->'ledger'->>'id')::uuid;

  update atlas.organizations
  set metadata=metadata || jsonb_build_object(
    'custody_reconstruction_key','feast_guild_organization_v1',
    'canonicalInstitution','Feast Guild','cleanRoom',true,
    'custodyMode','canonical_empty'
  )
  where id=v_fg_org;

  update atlas.ledgers
  set metadata=metadata || jsonb_build_object(
    'custody_reconstruction_key','feast_guild_ledger_v1',
    'canonicalEndeavor','Feast Guild','cleanRoom',true,
    'custodyMode','canonical_empty'
  )
  where id=v_fg_ledger;

  -- Lex compatibility owner membership on canonical Elm only; Ledger authority remains truth.
  insert into atlas.organization_memberships(
    organization_id,user_id,person_id,role,active,permissions
  ) values (
    v_elm_org,
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    'owner',true,
    jsonb_build_object('source','institutional_custody_reconstruction_v1','authorityTruth','principal_ledger_authority','compatibilityOnly',true)
  );

  insert into atlas.institutional_custody_carriers(
    carrier_organization_id,carrier_ledger_id,carrier_kind,status,basis,metadata
  ) values (
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
    '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
    'legacy_mixed_scope','active','historical_mixed_container_preserved_without_trigger_bypass',
    jsonb_build_object(
      'runtimeCutoverState','pending',
      'physicalRowsPreserved',true,
      'triggerBypassAllowed',false
    )
  ) returning id into v_carrier;

  insert into atlas.institutional_custody_carrier_targets(
    carrier_id,target_key,canonical_organization_id,canonical_ledger_id,metadata
  ) values
    (v_carrier,'elm_farm_organization',v_elm_org,null,'{}'::jsonb),
    (v_carrier,'elm_farm_ledger',v_elm_org,v_elm_farm_ledger,'{}'::jsonb),
    (v_carrier,'elm_venue_ledger',v_elm_org,v_elm_venue_ledger,'{}'::jsonb),
    (v_carrier,'feast_guild_organization',v_fg_org,null,jsonb_build_object('cleanRoom',true)),
    (v_carrier,'feast_guild_ledger',v_fg_org,v_fg_ledger,jsonb_build_object('cleanRoom',true));
end;
$function$;

-- Historical carrier itself is mixed and therefore not falsely mapped to one canonical institution.
insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
) values (
  'atlas','organizations','818b9a23-65e9-4198-b86c-9496ba548642','unresolved',
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  'legacy_mixed_compatibility_carrier',jsonb_build_object('runtimeCutoverState','pending')
);

insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,historical_ledger_id,evidence_basis,evidence
) values (
  'atlas','ledgers','6dab72b7-cb2f-43eb-855e-c0c99756e0d6','unresolved',
  '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
  '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
  'legacy_mixed_compatibility_carrier',jsonb_build_object('runtimeCutoverState','pending')
);

-- Elm / Waiting Room anchors.
do $function$
declare
  v_elm_org uuid;
  v_farm_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  ) values (
    'atlas','organization_units','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','reassigned',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,
    'explicit_elm_organization_unit',jsonb_build_object('physicalRowPreserved',true)
  );

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  ) values (
    'atlas','farms','6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f','reassigned',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,v_farm_ledger,
    'explicit_elm_farm',jsonb_build_object('physicalRowPreserved',true)
  );

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
  ) values
    ('atlas','organization_units','999569f3-8ae5-4bd0-b74d-f586b6b39d8d','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'waiting_room_test_scope',jsonb_build_object('physicalRowPreserved',true)),
    ('atlas','farms','f6592422-cf2b-4375-ba8f-f00828a05c18','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'waiting_room_test_scope',jsonb_build_object('physicalRowPreserved',true));
end;
$function$;

-- Strongest evidence first: existing Elm production Ledger entries retain physical identity/revision.
do $function$
declare
  v_elm_org uuid;
  v_farm_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,historical_ledger_id,
    canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  )
  select 'atlas','organization_ledger_entries',e.id::text,'reassigned',e.organization_id,e.ledger_id,
         v_elm_org,v_farm_ledger,'explicit_elm_unit_production_ledger_entry',
         jsonb_build_object('organizationUnitId',e.organization_unit_id,'eventKey',e.event_key,'revision',e.revision,'physicalRowPreserved',true)
  from atlas.organization_ledger_entries e
  where e.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and e.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;
$function$;

-- Direct Elm Farm evidence on Organization-scoped rows. No source row is updated.
do $function$
declare
  r record;
  v_key_col text;
  v_elm_org uuid;
  v_farm_ledger uuid;
  v_canonical_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';

  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='farm_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p join pg_class cl on cl.oid=p.conrelid join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1 and n.nspname=r.table_schema and cl.relname=r.table_name limit 1;
    end if;
    if v_key_col is null then continue; end if;

    v_canonical_ledger := case
      when r.table_name ~ '^(production_|crop_|flower_|seed_|growing_|plant_|propagation_|postharvest_)'
        or r.table_name in ('field_logs','weekly_harvest_task_results')
      then v_farm_ledger else null end;

    execute format($sql$
      insert into atlas.institutional_custody_adjudications(
        subject_schema,subject_table,subject_key,disposition,historical_organization_id,
        canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
      )
      select %L,%L,(t.%I)::text,'reassigned',t.organization_id,$1,$2,
             'explicit_elm_farm',jsonb_build_object('farmId',$3::text,'physicalRowPreserved',true)
      from %I.%I t
      where t.organization_id=$4 and t.farm_id=$3
      on conflict (subject_schema,subject_table,subject_key) do nothing
    $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
    using v_elm_org,v_canonical_ledger,
          '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$function$;

-- Direct Elm Unit evidence, including immutable communication/commercial history.
do $function$
declare
  r record;
  v_key_col text;
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_unit_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p join pg_class cl on cl.oid=p.conrelid join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1 and n.nspname=r.table_schema and cl.relname=r.table_name limit 1;
    end if;
    if v_key_col is null then continue; end if;

    execute format($sql$
      insert into atlas.institutional_custody_adjudications(
        subject_schema,subject_table,subject_key,disposition,historical_organization_id,
        canonical_organization_id,evidence_basis,evidence
      )
      select %L,%L,(t.%I)::text,'reassigned',t.organization_id,$1,
             'explicit_elm_organization_unit',jsonb_build_object('organizationUnitId',$2::text,'physicalRowPreserved',true)
      from %I.%I t
      where t.organization_id=$3 and t.organization_unit_id=$2
      on conflict (subject_schema,subject_table,subject_key) do nothing
    $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
    using v_elm_org,
          '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$function$;

-- Farm-only historical truth receives effective custody without any physical rewrite.
do $function$
declare
  r record;
  v_key_col text;
  v_elm_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
  v_canonical_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';

  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema='atlas'
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='farm_id')
      and not exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p join pg_class cl on cl.oid=p.conrelid join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1 and n.nspname=r.table_schema and cl.relname=r.table_name limit 1;
    end if;
    if v_key_col is null then continue; end if;

    v_canonical_ledger := case
      when r.table_name like 'community\_%' escape '\' then v_venue_ledger
      when r.table_name ~ '^(production_|crop_|flower_|seed_|growing_|plant_|propagation_|postharvest_)'
        or r.table_name in ('field_logs','weekly_harvest_task_results')
      then v_farm_ledger else null end;

    execute format($sql$
      insert into atlas.institutional_custody_adjudications(
        subject_schema,subject_table,subject_key,disposition,historical_organization_id,
        canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
      )
      select %L,%L,(t.%I)::text,'reassigned',$1,$2,$3,
             'historical_elm_farm_anchor',jsonb_build_object('farmId',$4::text,'physicalRowPreserved',true)
      from %I.%I t where t.farm_id=$4
      on conflict (subject_schema,subject_table,subject_key) do nothing
    $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
    using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,v_canonical_ledger,
          '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
  end loop;
end;
$function$;

-- Connected source custody is adjudicated; authorization/capability/sync state remains untouched.
do $function$
declare v_elm_org uuid; begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','connected_sources',s.id::text,'reassigned',s.custodian_organization_id,v_elm_org,
         'explicit_elm_organization_unit',jsonb_build_object('organizationUnitId',s.custodian_organization_unit_id,'physicalRowPreserved',true)
  from atlas.connected_sources s
  where s.custodian_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and s.custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Routes whose own evidence names Elm Farm.
do $function$
declare v_elm_org uuid; begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','operational_routes',r.id::text,'reassigned',r.organization_id,v_elm_org,
         'explicit_elm_farm_metadata',jsonb_build_object('farmId',r.metadata->>'farmId','stableKey',r.stable_key,'physicalRowPreserved',true)
  from atlas.operational_routes r
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and r.metadata->>'farmId'='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Identity subjects are Elm when Anna or an explicitly Elm-scoped relationship identifies them.
do $function$
declare v_elm_org uuid; begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','identity_subjects',s.id::text,'reassigned',s.organization_id,v_elm_org,
         case when s.id='0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid then 'anna_known_elm_institutional_identity'
              else 'elm_external_relationship_subject' end,
         jsonb_build_object('physicalRowPreserved',true)
  from atlas.identity_subjects s
  where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and (s.id='0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid or exists (
      select 1 from atlas.external_relationships r
      where r.subject_id=s.id
        and r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
        and r.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
    ))
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Anna's existing employment identity is preserved by ID and canonically adjudicated to Elm.
do $function$
declare v_elm_org uuid; begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  ) values
    ('atlas','organization_memberships','4bda9631-07a6-43ae-9f51-4cb63d78c803','reassigned','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,'anna_is_sole_elm_employee',jsonb_build_object('physicalRowPreserved',true)),
    ('atlas','organization_employee_seats','74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0','reassigned','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,'anna_is_sole_elm_employee',jsonb_build_object('physicalRowPreserved',true)),
    ('atlas','organization_member_credentials','385673ab-cf4e-4dbe-8c1d-11cb244143f2','reassigned','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,'anna_is_sole_elm_employee',jsonb_build_object('physicalRowPreserved',true)),
    ('atlas','organization_positions','badd2192-28a7-4913-aa90-e7076cb419f5','reassigned','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,'elm_farm_steward_position',jsonb_build_object('physicalRowPreserved',true)),
    ('atlas','organization_position_appointments','1baf1031-cbe3-4520-9b5d-485bb5c9a59c','reassigned','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,'elm_farm_steward_appointment',jsonb_build_object('physicalRowPreserved',true))
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Responsibility scope determines Farm versus Venue Ledger without moving the source rows.
do $function$
declare
  v_elm_org uuid; v_farm_ledger uuid; v_venue_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  )
  select 'atlas','organization_responsibilities',r.id::text,'reassigned',r.organization_id,v_elm_org,
         case when r.stable_key='venue_preparation' then v_venue_ledger else v_farm_ledger end,
         'explicit_elm_responsibility_scope',jsonb_build_object('stableKey',r.stable_key,'physicalRowPreserved',true)
  from atlas.organization_responsibilities r
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and exists (
      select 1 from atlas.organization_responsibility_scopes s
      where s.responsibility_id=r.id and s.organization_id=r.organization_id
        and s.scope_kind='organization_unit' and s.scope_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'
    )
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Current Lex/Anna profile defaults are effectively Elm, while physical defaults remain compatibility data.
do $function$
declare v_elm_org uuid; begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','user_profiles',p.user_id::text,'reassigned',p.default_organization_id,v_elm_org,
         'current_elm_profile_default',jsonb_build_object('displayName',p.display_name,'physicalRowPreserved',true)
  from atlas.user_profiles p
  where p.user_id in ('4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,'21436a28-40fd-4914-8015-a248d0dca14e'::uuid)
    and p.default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
end;$function$;

-- Waiting Room test scope stays physical history and is canonically archived.
do $function$
declare r record; v_key_col text; begin
  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema='atlas'
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='farm_id')
  loop
    v_key_col:=null;
    select c.column_name into v_key_col from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p join pg_class cl on cl.oid=p.conrelid join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1 and n.nspname=r.table_schema and cl.relname=r.table_name limit 1;
    end if;
    if v_key_col is null then continue; end if;

    execute format($sql$
      insert into atlas.institutional_custody_adjudications(
        subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
      )
      select %L,%L,(t.%I)::text,'archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
             'waiting_room_test_scope',jsonb_build_object('farmId',$1::text,'physicalRowPreserved',true)
      from %I.%I t where t.farm_id=$1
      on conflict (subject_schema,subject_table,subject_key) do nothing
    $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
    using 'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid;
  end loop;
end;$function$;

-- Owner-level portfolio work remains legacy history.
insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'atlas','tasks',t.id::text,'archived',t.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',t.title,'physicalRowPreserved',true)
from atlas.tasks t
where t.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and t.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'atlas','projects',p.id::text,'archived',p.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',p.title,'physicalRowPreserved',true)
from atlas.projects p
where p.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and p.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

-- Generic composition / Local-Noel lens state stays portfolio history, never promoted by container coincidence.
insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'atlas','composition_runs',c.id::text,'archived',c.organization_id,'generic_portfolio_composition',jsonb_build_object('sourceDomain',c.source_domain,'physicalRowPreserved',true)
from atlas.composition_runs c
where c.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
on conflict (subject_schema,subject_table,subject_key) do nothing;

insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'local_intel','recommendation_lenses',l.id::text,'archived',l.organization_id,'generic_portfolio_recommendation_lens',jsonb_build_object('sourceSystem',l.source_system,'physicalRowPreserved',true)
from local_intel.recommendation_lenses l
where l.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
on conflict (subject_schema,subject_table,subject_key) do nothing;

-- Remaining old-Organization rows with stable single-column identity are explicitly unresolved,
-- never guessed into Elm or Feast Guild merely because they share the historical container.
do $function$
declare r record; v_key_col text; begin
  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and not (t.table_schema='atlas' and t.table_name in ('institutional_custody_adjudications','institutional_custody_carriers','institutional_custody_carrier_targets'))
  loop
    v_key_col:=null;
    select c.column_name into v_key_col from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p join pg_class cl on cl.oid=p.conrelid join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1 and n.nspname=r.table_schema and cl.relname=r.table_name limit 1;
    end if;
    if v_key_col is null then continue; end if;

    execute format($sql$
      insert into atlas.institutional_custody_adjudications(
        subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
      )
      select %L,%L,(t.%I)::text,'unresolved',t.organization_id,
             'legacy_mixed_remaining_unadjudicated',jsonb_build_object('physicalRowPreserved',true)
      from %I.%I t
      where t.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      on conflict (subject_schema,subject_table,subject_key) do nothing
    $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name);
  end loop;
end;$function$;

-- The compatibility carrier must remain physically untouched and Feast Guild must remain clean-room.
do $function$
declare
  v_elm_org uuid; v_fg_org uuid; v_fg_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_fg_org from atlas.organizations where metadata->>'custody_reconstruction_key'='feast_guild_organization_v1';
  select id into v_fg_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='feast_guild_ledger_v1';

  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Compatibility carrier was mutated during additive reconstruction.' using errcode='55000';
  end if;

  if exists (select 1 from atlas.organization_memberships where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_employee_seats where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_units where organization_id=v_fg_org)
     or exists (select 1 from atlas.farms where organization_id=v_fg_org)
     or exists (select 1 from atlas.identity_subjects where organization_id=v_fg_org)
     or exists (select 1 from atlas.external_relationships where organization_id=v_fg_org)
     or exists (select 1 from atlas.communication_endpoints where organization_id=v_fg_org)
     or exists (select 1 from atlas.tasks where organization_id=v_fg_org)
     or exists (select 1 from atlas.projects where organization_id=v_fg_org)
     or exists (select 1 from atlas.organization_ledger_entries where organization_id=v_fg_org) then
    raise exception 'Feast Guild clean-room boundary was violated.' using errcode='55000';
  end if;

  if not exists (
    select 1 from atlas.principal_ledger_authorities
    where principal_id='e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid
      and ledger_id=v_fg_ledger and authority_kind='root_governing' and status='active'
  ) then
    raise exception 'Feast Guild root authority missing.' using errcode='55000';
  end if;
end;
$function$;

COMMIT;
