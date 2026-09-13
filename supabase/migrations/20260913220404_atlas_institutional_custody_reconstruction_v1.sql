-- Atlas Institutional Custody Reconstruction v1.
-- Reconstructs canonical Elm / Feast Guild institutional identity after Ledger Graph v1
-- while preserving the historical mixed container and original record identities.

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

alter table atlas.institutional_custody_adjudications enable row level security;
revoke all on atlas.institutional_custody_adjudications from anon, authenticated;
grant select, insert on atlas.institutional_custody_adjudications to service_role;

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

comment on table atlas.institutional_custody_adjudications is
  'Immutable evidence that distinguishes historical storage custody from canonical institutional custody.';

-- Production anchors must still match the evidence adjudicated before this migration was authored.
do $function$
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and status='active'
  ) then
    raise exception 'Expected historical mixed Organization is unavailable.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and status='active'
  ) then
    raise exception 'Expected historical mixed Ledger is unavailable.' using errcode='P0002';
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
      and person_id='998e6116-6d9d-4ee5-9d48-6c239d58507b'::uuid
      and active
  ) or not exists (
    select 1 from atlas.organization_employee_seats
    where id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid
      and status='active'
  ) then
    raise exception 'Expected Anna Elm employment anchors are unavailable.' using errcode='P0002';
  end if;
end;
$function$;

-- Establish fresh canonical institutional identity with opaque stable keys.
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
  v_lex_owner_membership uuid;
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
  set metadata = metadata || jsonb_build_object(
    'custody_reconstruction_key','elm_farm_organization_v1',
    'canonicalInstitution','Elm Farm',
    'reconstructedFromOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642'
  )
  where id=v_elm_org;

  update atlas.ledgers
  set metadata = metadata || jsonb_build_object(
    'custody_reconstruction_key','elm_farm_ledger_v1',
    'canonicalEndeavor','Elm Farm'
  )
  where id=v_elm_farm_ledger;

  v_venue_result := atlas.establish_ledger_for_principal_v1(
    'e99e759c-1a65-4ddc-ba41-91f72c5981d8'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    'Elm Venue',
    'governed_reality',
    'institutional_custody_reconstruction_v1',
    jsonb_build_object('custody_reconstruction_key','elm_venue_ledger_v1','canonicalEndeavor','Elm Venue')
  );
  v_elm_venue_ledger := (v_venue_result->'ledger'->>'id')::uuid;

  perform atlas.establish_ledger_organization_participation_v1(
    v_elm_venue_ledger,
    v_elm_org,
    'operating',
    false,
    jsonb_build_object('source','institutional_custody_reconstruction_v1'),
    jsonb_build_object('endeavor','Elm Venue')
  );

  perform atlas.establish_ledger_relationship_v1(
    v_elm_farm_ledger,
    v_elm_venue_ledger,
    'sibling',
    'symmetric',
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
  set metadata = metadata || jsonb_build_object(
    'custody_reconstruction_key','feast_guild_organization_v1',
    'canonicalInstitution','Feast Guild',
    'cleanRoom',true
  )
  where id=v_fg_org;

  update atlas.ledgers
  set metadata = metadata || jsonb_build_object(
    'custody_reconstruction_key','feast_guild_ledger_v1',
    'canonicalEndeavor','Feast Guild',
    'cleanRoom',true
  )
  where id=v_fg_ledger;

  -- Compatibility owner membership gives Lex existing Organization-owner read paths for Elm.
  -- It does not create an employee seat and is not the source of Ledger authority.
  insert into atlas.organization_memberships(
    organization_id,user_id,person_id,role,active,permissions
  ) values (
    v_elm_org,
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    'owner',true,
    jsonb_build_object('source','institutional_custody_reconstruction_v1','authorityTruth','principal_ledger_authority')
  )
  returning id into v_lex_owner_membership;

  -- Feast Guild intentionally gets no membership/seat/operating data: Lex governance is direct Ledger authority.
end;
$function$;

-- Resolve canonical IDs from opaque metadata tags in all later steps.
-- Make composite Organization+Unit FKs temporarily deferrable so the preserved Elm Unit ID
-- can move institutions atomically with all of its child rows.
do $function$
declare
  r record;
begin
  for r in
    select n.nspname,cl.relname,c.conname
    from pg_constraint c
    join pg_class cl on cl.oid=c.conrelid
    join pg_namespace n on n.oid=cl.relnamespace
    where c.contype='f'
      and c.confrelid='atlas.organization_units'::regclass
      and array_length(c.conkey,1)=2
  loop
    execute format('alter table %I.%I alter constraint %I deferrable initially deferred',r.nspname,r.relname,r.conname);
  end loop;
end;
$function$;

SET CONSTRAINTS ALL DEFERRED;

-- Preserve the Elm Unit identity while assigning it to the fresh canonical Elm Organization.
do $function$
declare
  v_elm_org uuid;
  v_farm_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  ) values (
    'atlas','organization_units','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','reassigned',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,null,
    'explicit_elm_organization_unit',jsonb_build_object('legacyStableKey','elm')
  );

  update atlas.organization_units
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object(
        'historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642',
        'custodyReconstructedBy','institutional_custody_reconstruction_v1'
      )
  where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;

  -- The six historical Ledger entries are known Elm production evidence. Move Organization
  -- custody and Ledger governance together so the row IDs and revisions do not change.
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,historical_ledger_id,
    canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  )
  select 'atlas','organization_ledger_entries',e.id::text,'reassigned',e.organization_id,e.ledger_id,
         v_elm_org,v_farm_ledger,'explicit_elm_unit_production_ledger_entry',
         jsonb_build_object('organizationUnitId',e.organization_unit_id,'eventKey',e.event_key,'revision',e.revision)
  from atlas.organization_ledger_entries e
  where e.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and e.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_ledger_entries
  set organization_id=v_elm_org,
      ledger_id=v_farm_ledger
  where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
end;
$function$;

-- Move every standard Organization+Unit row that explicitly names the preserved Elm Unit.
do $function$
declare
  r record;
  v_key_col text;
  v_elm_org uuid;
  v_farm_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';

  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE'
      and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_unit_id')
      and not (t.table_schema='atlas' and t.table_name in ('organization_units','organization_ledger_entries'))
  loop
    select c.column_name into v_key_col
    from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';

    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p
      join pg_class cl on cl.oid=p.conrelid
      join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1
        and n.nspname=r.table_schema and cl.relname=r.table_name
      limit 1;
    end if;

    if v_key_col is not null then
      execute format($sql$
        insert into atlas.institutional_custody_adjudications(
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,
          canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'reassigned',t.organization_id,$1,
               case when %L='farms' then $2 else null end,
               'explicit_elm_organization_unit',jsonb_build_object('organizationUnitId',$3::text)
        from %I.%I t
        where t.organization_id=$4 and t.organization_unit_id=$3
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_name,r.table_schema,r.table_name)
      using v_elm_org,v_farm_ledger,
            '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
            '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
    end if;

    execute format('update %I.%I set organization_id=$1 where organization_id=$2 and organization_unit_id=$3',r.table_schema,r.table_name)
    using v_elm_org,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
          '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
  end loop;
end;
$function$;

-- Move custom-named Organization+Unit custody columns (currently connected_sources) by FK semantics.
do $function$
declare
  r record;
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','connected_sources',s.id::text,'reassigned',s.custodian_organization_id,
         v_elm_org,'explicit_elm_organization_unit',jsonb_build_object('organizationUnitId',s.custodian_organization_unit_id)
  from atlas.connected_sources s
  where s.custodian_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and s.custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.connected_sources
  set custodian_organization_id=v_elm_org
  where custodian_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and custodian_organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
end;
$function$;

-- Move Organization-scoped rows that explicitly reference Elm Farm even when they do not carry an Organization Unit.
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
    where t.table_type='BASE TABLE'
      and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='farm_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col
    from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p
      join pg_class cl on cl.oid=p.conrelid
      join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1
        and n.nspname=r.table_schema and cl.relname=r.table_name
      limit 1;
    end if;

    v_canonical_ledger := case
      when r.table_name ~ '^(production_|crop_|flower_|seed_|growing_|plant_|propagation_|postharvest_)'
        or r.table_name in ('field_logs','weekly_harvest_task_results')
      then v_farm_ledger else null end;

    if v_key_col is not null then
      execute format($sql$
        insert into atlas.institutional_custody_adjudications(
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,
          canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'reassigned',t.organization_id,$1,$2,
               'explicit_elm_farm',jsonb_build_object('farmId',$3::text)
        from %I.%I t
        where t.organization_id=$4 and t.farm_id=$3
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
      using v_elm_org,v_canonical_ledger,
            '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid,
            '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
    end if;

    execute format('update %I.%I set organization_id=$1 where organization_id=$2 and farm_id=$3',r.table_schema,r.table_name)
    using v_elm_org,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
          '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
  end loop;
end;
$function$;

-- Move institutional domains whose base reality is already proven entirely Elm.
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
    where t.table_type='BASE TABLE'
      and (
        (t.table_schema='atlas' and (
          t.table_name like 'identity\_%' escape '\'
          or t.table_name like 'external\_relationship%' escape '\'
          or t.table_name like 'communication\_%' escape '\'
          or t.table_name like 'institutional\_communication%' escape '\'
          or t.table_name like 'institutional\_conversation%' escape '\'
          or t.table_name like 'commercial\_%' escape '\'
          or t.table_name='recurring_commercial_commitments'
          or t.table_name like 'work\_%' escape '\'
          or t.table_name like 'worker\_%' escape '\'
          or t.table_name like 'composition\_%' escape '\'
          or t.table_name like 'operational\_route%' escape '\'
          or t.table_name like 'company\_operating\_knowledge%' escape '\'
        ))
        or t.table_schema='local_intel'
      )
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col
    from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p
      join pg_class cl on cl.oid=p.conrelid
      join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1
        and n.nspname=r.table_schema and cl.relname=r.table_name
      limit 1;
    end if;

    if v_key_col is not null then
      execute format($sql$
        insert into atlas.institutional_custody_adjudications(
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,
          canonical_organization_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'reassigned',t.organization_id,$1,
               'elm_institutional_domain',jsonb_build_object('domainTable',%L)
        from %I.%I t
        where t.organization_id=$2
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_name,r.table_schema,r.table_name)
      using v_elm_org,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
    end if;

    execute format('update %I.%I set organization_id=$1 where organization_id=$2',r.table_schema,r.table_name)
    using v_elm_org,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$function$;

-- Farm-only history inherits canonical Organization custody from the preserved Farm ID.
-- Ledger assignment is conservative: production-specific domains -> Elm Farm; community domains -> Elm Venue.
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
    where t.table_type='BASE TABLE'
      and t.table_schema='atlas'
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='farm_id')
      and not exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
  loop
    v_key_col := null;
    select c.column_name into v_key_col
    from information_schema.columns c
    where c.table_schema=r.table_schema and c.table_name=r.table_name and c.column_name='id';
    if v_key_col is null then
      select a.attname into v_key_col
      from pg_constraint p
      join pg_class cl on cl.oid=p.conrelid
      join pg_namespace n on n.oid=cl.relnamespace
      join pg_attribute a on a.attrelid=p.conrelid and a.attnum=p.conkey[1]
      where p.contype='p' and array_length(p.conkey,1)=1
        and n.nspname=r.table_schema and cl.relname=r.table_name
      limit 1;
    end if;

    v_canonical_ledger := case
      when r.table_name like 'community\_%' escape '\' then v_venue_ledger
      when r.table_name ~ '^(production_|crop_|flower_|seed_|growing_|plant_|propagation_|postharvest_)'
        or r.table_name in ('field_logs','weekly_harvest_task_results') then v_farm_ledger
      else null end;

    if v_key_col is not null then
      execute format($sql$
        insert into atlas.institutional_custody_adjudications(
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,
          canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'reassigned',$1,$2,$3,
               'historical_elm_farm_anchor',jsonb_build_object('farmId',$4::text)
        from %I.%I t
        where t.farm_id=$4
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
      using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,v_canonical_ledger,
            '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
    end if;
  end loop;
end;
$function$;

-- Canonical Elm structure keeps the same Anna / Farm Steward / responsibility identities.
do $function$
declare
  v_elm_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
  r record;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';

  -- The five historical responsibilities are all Elm. Venue preparation is governed by Venue;
  -- the remaining four are farm-production/grounds responsibilities.
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,canonical_ledger_id,evidence_basis,evidence
  )
  select 'atlas','organization_responsibilities',r.id::text,'reassigned',r.organization_id,v_elm_org,
         case when r.stable_key='venue_preparation' then v_venue_ledger else v_farm_ledger end,
         'elm_responsibility_semantics',jsonb_build_object('stableKey',r.stable_key,'name',r.name)
  from atlas.organization_responsibilities r
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_responsibilities
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','organization_responsibility_scopes',s.id::text,'reassigned',s.organization_id,v_elm_org,
         'elm_responsibility_scope',jsonb_build_object('scopeKind',s.scope_kind,'scopeId',s.scope_id)
  from atlas.organization_responsibility_scopes s
  where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_responsibility_scopes
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

  -- Anna's existing institutional identity, membership, seat, credential, and appointment are
  -- canonically Elm; preserve every row ID and carry the original container in adjudication evidence.
  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,canonical_ledger_id,evidence_basis,evidence)
  select 'atlas','organization_memberships',m.id::text,'reassigned',m.organization_id,v_elm_org,null,'anna_is_sole_elm_employee',jsonb_build_object('personId',m.person_id)
  from atlas.organization_memberships m where m.id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
  update atlas.organization_memberships set organization_id=v_elm_org where id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid;

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,canonical_ledger_id,evidence_basis,evidence)
  select 'atlas','organization_employee_seats',s.id::text,'reassigned',s.organization_id,v_elm_org,null,'anna_is_sole_elm_employee',jsonb_build_object('membershipId',s.organization_membership_id)
  from atlas.organization_employee_seats s where s.id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
  update atlas.organization_employee_seats set organization_id=v_elm_org where id='74e1ec6b-6c6b-45b2-b1cf-4a76303b8ec0'::uuid;

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence)
  select 'atlas','organization_member_credentials',c.id::text,'reassigned',c.organization_id,v_elm_org,'anna_is_sole_elm_employee',jsonb_build_object('authUserId',c.auth_user_id)
  from atlas.organization_member_credentials c where c.id='385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
  update atlas.organization_member_credentials
  set organization_id=v_elm_org,issued_by_organization_id=v_elm_org,
      provenance=provenance || jsonb_build_object('historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where id='385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid;

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,canonical_ledger_id,evidence_basis,evidence)
  select 'atlas','organization_position_appointments',a.id::text,'reassigned',a.organization_id,v_elm_org,v_farm_ledger,'anna_farm_steward_appointment',jsonb_build_object('positionId',a.position_id)
  from atlas.organization_position_appointments a where a.id='1baf1031-cbe3-4520-9b5d-485bb5c9a59c'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;
  update atlas.organization_position_appointments
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where id='1baf1031-cbe3-4520-9b5d-485bb5c9a59c'::uuid;
end;
$function$;

-- Restore all Organization Unit foreign keys to their original immediate behavior now that the move is consistent.
do $function$
declare
  r record;
begin
  set constraints all immediate;
  for r in
    select n.nspname,cl.relname,c.conname
    from pg_constraint c
    join pg_class cl on cl.oid=c.conrelid
    join pg_namespace n on n.oid=cl.relnamespace
    where c.contype='f'
      and c.confrelid='atlas.organization_units'::regclass
      and array_length(c.conkey,1)=2
  loop
    execute format('alter table %I.%I alter constraint %I not deferrable',r.nspname,r.relname,r.conname);
  end loop;
end;
$function$;

-- Current profile defaults follow canonical Elm only for Lex and Anna. Inactive legacy collaborators
-- remain historical and do not gain new institutional access.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,canonical_organization_id,evidence_basis,evidence)
  select 'atlas','user_profiles',p.user_id::text,'reassigned',p.default_organization_id,v_elm_org,'current_elm_profile_default',jsonb_build_object('displayName',p.display_name)
  from atlas.user_profiles p
  where p.user_id in ('4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,'21436a28-40fd-4914-8015-a248d0dca14e'::uuid)
    and p.default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.user_profiles
  set default_organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalDefaultOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where user_id in ('4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,'21436a28-40fd-4914-8015-a248d0dca14e'::uuid)
    and default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
end;
$function$;

-- Archive Waiting Room and every farm-keyed test record without deleting it.
do $function$
declare
  r record;
  v_key_col text;
begin
  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence)
  values
    ('atlas','organization_units','999569f3-8ae5-4bd0-b74d-f586b6b39d8d','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'waiting_room_test_scope',jsonb_build_object('decision','archive test scope')),
    ('atlas','farms','f6592422-cf2b-4375-ba8f-f00828a05c18','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'waiting_room_test_scope',jsonb_build_object('decision','archive test scope'))
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_units
  set status='archived',metadata=metadata || jsonb_build_object('archivedBy','institutional_custody_reconstruction_v1','archiveReason','waiting_room_test_scope')
  where id='999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid;
  update atlas.farms
  set status='archived',metadata=metadata || jsonb_build_object('archivedBy','institutional_custody_reconstruction_v1','archiveReason','waiting_room_test_scope')
  where id='f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid;

  for r in
    select t.table_schema,t.table_name
    from information_schema.tables t
    where t.table_type='BASE TABLE' and t.table_schema='atlas'
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
    if v_key_col is not null then
      execute format($sql$
        insert into atlas.institutional_custody_adjudications(
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
               'waiting_room_test_scope',jsonb_build_object('farmId',$1::text)
        from %I.%I t where t.farm_id=$1
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
      using 'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid;
    end if;
  end loop;
end;
$function$;

-- Archive owner-level portfolio tasks/projects that have no farm identity.
insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence)
select 'atlas','tasks',t.id::text,'archived',t.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',t.title)
from atlas.tasks t
where t.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and t.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence)
select 'atlas','projects',p.id::text,'archived',p.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',p.title)
from atlas.projects p
where p.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and p.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

-- Retire the historical mixed Ledger and archive/reclassify the old Organization.
do $function$
declare
  v_old_org_key text;
  v_old_ledger_key text;
  v_elm_org uuid;
  v_fg_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
  v_fg_ledger uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_fg_org from atlas.organizations where metadata->>'custody_reconstruction_key'='feast_guild_organization_v1';
  select id into v_farm_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_farm_ledger_v1';
  select id into v_venue_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='elm_venue_ledger_v1';
  select id into v_fg_ledger from atlas.ledgers where metadata->>'custody_reconstruction_key'='feast_guild_ledger_v1';

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence)
  values ('atlas','organizations','818b9a23-65e9-4198-b86c-9496ba548642','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'legacy_mixed_portfolio_container',jsonb_build_object('newElmOrganizationId',v_elm_org,'newFeastGuildOrganizationId',v_fg_org))
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  insert into atlas.institutional_custody_adjudications(subject_schema,subject_table,subject_key,disposition,historical_organization_id,historical_ledger_id,evidence_basis,evidence)
  values ('atlas','ledgers','6dab72b7-cb2f-43eb-855e-c0c99756e0d6','archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,'legacy_mixed_portfolio_container',jsonb_build_object('newElmFarmLedgerId',v_farm_ledger,'newElmVenueLedgerId',v_venue_ledger,'newFeastGuildLedgerId',v_fg_ledger))
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.principal_ledger_authorities
  set status='ended',ended_at=coalesce(ended_at,now()),
      metadata=metadata || jsonb_build_object('endedBy','institutional_custody_reconstruction_v1','reason','legacy_mixed_ledger_retired')
  where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid and status='active';

  update atlas.ledger_organization_participations
  set status='ended',ended_at=coalesce(ended_at,now()),
      metadata=metadata || jsonb_build_object('endedBy','institutional_custody_reconstruction_v1','reason','legacy_mixed_ledger_retired')
  where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid and status='active';

  v_old_ledger_key := atlas.new_opaque_stable_key_v1();
  update atlas.ledgers
  set stable_key=v_old_ledger_key,
      name='Legacy Principal Portfolio Ledger',
      status='retired',
      metadata=metadata || jsonb_build_object(
        'legacyStableKey','feast_guild','legacyName','Feast Guild',
        'scope_state','adjudicated_legacy_portfolio',
        'retiredBy','institutional_custody_reconstruction_v1'
      )
  where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

  -- The legacy owner membership is no longer an active institutional ownership relation.
  update atlas.organization_memberships
  set active=false,
      permissions=permissions || jsonb_build_object('archivedLegacyPortfolioMembership',true)
  where id='427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;

  v_old_org_key := atlas.new_opaque_stable_key_v1();
  update atlas.organizations
  set stable_key=v_old_org_key,
      name='Legacy Principal Portfolio',
      status='archived',
      metadata=metadata || jsonb_build_object(
        'legacyStableKey','feast_guild','legacyName','Feast Guild',
        'organization_kind','legacy_principal_portfolio',
        'custodyAdjudicatedBy','institutional_custody_reconstruction_v1',
        'elmFarmOrganizationId',v_elm_org,
        'feastGuildOrganizationId',v_fg_org
      )
  where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
end;
$function$;

COMMIT;
