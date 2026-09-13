-- Atlas Institutional Custody Reconstruction v1.
-- Replacement for superseded 20260913221918 candidate.
-- Reconstructs canonical Elm / Feast Guild institutional identity after Ledger Graph v1
-- using evidence-backed custody movement only.
-- Temporary FK deferral is selected by referenced parent-key semantics, not child-column names.

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
  'Immutable evidence separating historical storage custody from canonical institutional custody.';

-- Production anchors and schema assumptions must still match the adjudicated evidence.
do $function$
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and status='active'
  ) then
    raise exception 'Expected historical mixed Organization is unavailable.' using errcode='P0002';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid and status='active'
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

-- Capture negative-control and communication behavior baselines before any custody mutation.
create temporary table custody_reconstruction_guard_v1 on commit drop as
select
  (select count(*) from atlas.composition_runs where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) as composition_count,
  (select count(*) from local_intel.recommendation_lenses where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) as recommendation_lens_count;

create temporary table custody_source_guard_v1 on commit drop as
select id,authorization_state,granted_scopes,capabilities,last_sync_at,revoked_at
from atlas.connected_sources
where id in (
  '188291ac-3b08-429b-8ea1-a2bf3f3833ef'::uuid,
  '238df033-5704-4404-bf34-a509f4e4d1c1'::uuid
);

-- Capture the exact Organization-bearing parent-key constraints that may need temporary deferral.
-- Parent-key semantics govern selection so custom child names such as custodian_organization_id are included.
create temporary table custody_fk_deferral_guard_v1 (
  child_schema text not null,
  child_table text not null,
  conname text not null,
  was_deferrable boolean not null,
  was_deferred boolean not null,
  primary key (child_schema,child_table,conname)
) on commit drop;

insert into custody_fk_deferral_guard_v1(child_schema,child_table,conname,was_deferrable,was_deferred)
select nch.nspname,ch.relname,c.conname,c.condeferrable,c.condeferred
from pg_constraint c
join pg_class ch on ch.oid=c.conrelid
join pg_namespace nch on nch.oid=ch.relnamespace
join pg_class pa on pa.oid=c.confrelid
join pg_namespace npa on npa.oid=pa.relnamespace
where c.contype='f'
  and nch.nspname in ('atlas','local_intel')
  and npa.nspname in ('atlas','local_intel')
  and array_length(c.confkey,1) > 1
  and exists (
    select 1
    from generate_subscripts(c.confkey,1) s(i)
    join pg_attribute ppa on ppa.attrelid=c.confrelid and ppa.attnum=c.confkey[s.i]
    where ppa.attname='organization_id'
  );

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

  -- Compatibility owner membership preserves current Organization-owner read surfaces only.
  insert into atlas.organization_memberships(
    organization_id,user_id,person_id,role,active,permissions
  ) values (
    v_elm_org,
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
    '59e9fd9d-e7fd-48ca-91e0-ee271c05148e'::uuid,
    'owner',true,
    jsonb_build_object('source','institutional_custody_reconstruction_v1','authorityTruth','principal_ledger_authority')
  );
end;
$function$;

-- Temporarily defer the captured parent-semantic constraints that were originally non-deferrable.
do $function$
declare
  r record;
begin
  for r in
    select child_schema,child_table,conname
    from custody_fk_deferral_guard_v1
    where not was_deferrable
    order by child_schema,child_table,conname
  loop
    execute format(
      'alter table %I.%I alter constraint %I deferrable initially deferred',
      r.child_schema,r.child_table,r.conname
    );
  end loop;
end;
$function$;

SET CONSTRAINTS ALL DEFERRED;

-- Elm Unit itself is a preserved identity moved into the canonical Elm Organization.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  ) values (
    'atlas','organization_units','1b65ac99-0f00-4ca2-9488-e8539cae2a1b','reassigned',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,v_elm_org,
    'explicit_elm_organization_unit',jsonb_build_object('legacyStableKey','elm')
  );

  update atlas.organization_units
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object(
        'historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642',
        'custodyReconstructedBy','institutional_custody_reconstruction_v1'
      )
  where id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
end;
$function$;

-- Six known Elm production Ledger entries preserve identity/revision and move to Elm Farm Ledger.
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
         jsonb_build_object('organizationUnitId',e.organization_unit_id,'eventKey',e.event_key,'revision',e.revision)
  from atlas.organization_ledger_entries e
  where e.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and e.organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_ledger_entries
  set organization_id=v_elm_org,ledger_id=v_farm_ledger
  where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and organization_unit_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
end;
$function$;

-- Any row that directly names the preserved Elm Unit is direct Elm evidence.
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
      and t.table_schema in ('atlas','local_intel')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_id')
      and exists (select 1 from information_schema.columns c where c.table_schema=t.table_schema and c.table_name=t.table_name and c.column_name='organization_unit_id')
      and not (t.table_schema='atlas' and t.table_name in ('organization_units','organization_ledger_entries'))
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
               'explicit_elm_organization_unit',jsonb_build_object('organizationUnitId',$2::text)
        from %I.%I t
        where t.organization_id=$3 and t.organization_unit_id=$2
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
      using v_elm_org,
            '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid,
            '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
    end if;

    execute format(
      'update %I.%I set organization_id=$1 where organization_id=$2 and organization_unit_id=$3',
      r.table_schema,r.table_name
    )
    using v_elm_org,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
          '1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
  end loop;
end;
$function$;

-- Connected-source custody uses custom column names but the same explicit Elm Unit evidence.
do $function$
declare
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

-- Any Organization-scoped row that directly names Elm Farm is direct Elm evidence.
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

    execute format(
      'update %I.%I set organization_id=$1 where organization_id=$2 and farm_id=$3',
      r.table_schema,r.table_name
    )
    using v_elm_org,
          '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
          '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
  end loop;
end;
$function$;

-- Farm-only historical rows receive canonical custody evidence without inventing an Organization column.
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
        or r.table_name in ('field_logs','weekly_harvest_task_results')
      then v_farm_ledger
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
      using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
            v_elm_org,v_canonical_ledger,
            '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid;
    end if;
  end loop;
end;
$function$;

-- Routes without Organization Unit columns move only when their own metadata explicitly carries Elm Farm.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','operational_routes',r.id::text,'reassigned',r.organization_id,v_elm_org,
         'explicit_elm_farm_metadata',jsonb_build_object('farmId',r.metadata->>'farmId','stableKey',r.stable_key)
  from atlas.operational_routes r
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and r.metadata->>'farmId'='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.operational_routes
  set organization_id=v_elm_org
  where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and metadata->>'farmId'='6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f';
end;
$function$;

-- Identity subjects move only when direct Elm relationship evidence or Anna's known institutional identity proves custody.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','identity_subjects',s.id::text,'reassigned',s.organization_id,v_elm_org,
         case when s.id='0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid
              then 'anna_known_elm_institutional_identity'
              else 'elm_external_relationship_subject' end,
         jsonb_build_object('subjectId',s.id)
  from atlas.identity_subjects s
  where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and (
      s.id='0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid
      or exists (
        select 1 from atlas.external_relationships r
        where r.subject_id=s.id and r.organization_id=v_elm_org
      )
    )
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.identity_subjects s
  set organization_id=v_elm_org
  where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and (
      s.id='0b87334c-56e0-44c2-a7d7-57d6df60f705'::uuid
      or exists (
        select 1 from atlas.external_relationships r
        where r.subject_id=s.id and r.organization_id=v_elm_org
      )
    );
end;
$function$;

-- Anna's existing membership is direct Elm employment evidence. Preserve the row identity.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','organization_memberships',m.id::text,'reassigned',m.organization_id,v_elm_org,
         'anna_is_sole_elm_employee',jsonb_build_object('personId',m.person_id)
  from atlas.organization_memberships m
  where m.id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_memberships
  set organization_id=v_elm_org
  where id='4bda9631-07a6-43ae-9f51-4cb63d78c803'::uuid;

  update atlas.organization_member_credentials
  set issued_by_organization_id=v_elm_org,
      provenance=provenance || jsonb_build_object(
        'historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642',
        'custodyReconstructedBy','institutional_custody_reconstruction_v1'
      )
  where id='385673ab-cf4e-4dbe-8c1d-11cb244143f2'::uuid;
end;
$function$;

-- Responsibilities move only when their scopes explicitly name the preserved Elm Unit.
do $function$
declare
  v_elm_org uuid;
  v_farm_ledger uuid;
  v_venue_ledger uuid;
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
         'explicit_elm_responsibility_scope',jsonb_build_object('stableKey',r.stable_key,'name',r.name)
  from atlas.organization_responsibilities r
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and exists (
      select 1 from atlas.organization_responsibility_scopes s
      where s.responsibility_id=r.id
        and s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
        and s.scope_kind='organization_unit'
        and s.scope_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'
    )
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.organization_responsibilities r
  set organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where r.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
    and exists (
      select 1 from atlas.organization_responsibility_scopes s
      where s.responsibility_id=r.id
        and s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
        and s.scope_kind='organization_unit'
        and s.scope_id='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'
    );
end;
$function$;

-- Propagate canonical Organization custody only through actual FK relationships from already-proven Elm rows.
-- No table-name/domain family is treated as evidence.
do $function$
declare
  r record;
  v_join text;
  v_key_col text;
  v_changed integer;
  v_iteration_changes integer;
  v_iteration integer := 0;
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  loop
    v_iteration := v_iteration + 1;
    v_iteration_changes := 0;

    for r in
      select c.oid,c.conrelid,c.confrelid,c.conkey,c.confkey,c.conname,
             nch.nspname child_schema,ch.relname child_table,
             npa.nspname parent_schema,pa.relname parent_table
      from pg_constraint c
      join pg_class ch on ch.oid=c.conrelid
      join pg_namespace nch on nch.oid=ch.relnamespace
      join pg_class pa on pa.oid=c.confrelid
      join pg_namespace npa on npa.oid=pa.relnamespace
      where c.contype='f'
        and nch.nspname in ('atlas','local_intel')
        and npa.nspname in ('atlas','local_intel')
        and exists (
          select 1 from pg_attribute a
          where a.attrelid=c.conrelid and a.attname='organization_id' and not a.attisdropped
        )
        and exists (
          select 1 from pg_attribute a
          where a.attrelid=c.confrelid and a.attname='organization_id' and not a.attisdropped
        )
    loop
      select string_agg(
        format('p.%I is not distinct from ch.%I',ppa.attname,ca.attname),
        ' and ' order by s.i
      ) into v_join
      from generate_subscripts(r.conkey,1) s(i)
      join pg_attribute ca on ca.attrelid=r.conrelid and ca.attnum=r.conkey[s.i]
      join pg_attribute ppa on ppa.attrelid=r.confrelid and ppa.attnum=r.confkey[s.i]
      where not (ca.attname='organization_id' and ppa.attname='organization_id');

      if v_join is null or btrim(v_join)='' then
        continue;
      end if;

      v_key_col := null;
      select a.attname into v_key_col
      from pg_constraint pk
      join pg_attribute a on a.attrelid=pk.conrelid and a.attnum=pk.conkey[1]
      where pk.contype='p' and pk.conrelid=r.conrelid and array_length(pk.conkey,1)=1
      limit 1;

      if v_key_col is not null then
        execute format($sql$
          insert into atlas.institutional_custody_adjudications(
            subject_schema,subject_table,subject_key,disposition,historical_organization_id,
            canonical_organization_id,evidence_basis,evidence
          )
          select %L,%L,(ch.%I)::text,'reassigned',ch.organization_id,$1,
                 'derived_from_reassigned_parent',
                 jsonb_build_object('constraint',%L,'parentSchema',%L,'parentTable',%L)
          from %I.%I ch
          where ch.organization_id=$2
            and exists (
              select 1 from %I.%I p
              where p.organization_id=$1 and %s
            )
          on conflict (subject_schema,subject_table,subject_key) do nothing
        $sql$,
          r.child_schema,r.child_table,v_key_col,r.conname,r.parent_schema,r.parent_table,
          r.child_schema,r.child_table,r.parent_schema,r.parent_table,v_join
        ) using v_elm_org,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
      end if;

      execute format($sql$
        update %I.%I ch
        set organization_id=$1
        where ch.organization_id=$2
          and exists (
            select 1 from %I.%I p
            where p.organization_id=$1 and %s
          )
      $sql$,r.child_schema,r.child_table,r.parent_schema,r.parent_table,v_join)
      using v_elm_org,'818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

      get diagnostics v_changed = row_count;
      v_iteration_changes := v_iteration_changes + v_changed;
    end loop;

    -- Identity source records are upstream evidence containers. Promote them only when a moved
    -- source-subject assertion proves the record belongs to a canonical Elm identity.
    insert into atlas.institutional_custody_adjudications(
      subject_schema,subject_table,subject_key,disposition,historical_organization_id,
      canonical_organization_id,evidence_basis,evidence
    )
    select 'atlas','identity_source_records',s.id::text,'reassigned',s.organization_id,v_elm_org,
           'derived_from_elm_identity_assertion',jsonb_build_object('sourceRecordId',s.id)
    from atlas.identity_source_records s
    where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and exists (
        select 1 from atlas.identity_source_subject_assertions a
        where a.source_record_id=s.id and a.organization_id=v_elm_org
      )
    on conflict (subject_schema,subject_table,subject_key) do nothing;

    update atlas.identity_source_records s
    set organization_id=v_elm_org
    where s.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and exists (
        select 1 from atlas.identity_source_subject_assertions a
        where a.source_record_id=s.id and a.organization_id=v_elm_org
      );
    get diagnostics v_changed = row_count;
    v_iteration_changes := v_iteration_changes + v_changed;

    exit when v_iteration_changes=0;
    if v_iteration>=24 then
      raise exception 'Elm custody FK propagation did not converge.' using errcode='55000';
    end if;
  end loop;
end;
$function$;

-- Current defaults follow canonical Elm only for Lex and Anna; inactive collaborators remain historical.
do $function$
declare
  v_elm_org uuid;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,
    canonical_organization_id,evidence_basis,evidence
  )
  select 'atlas','user_profiles',p.user_id::text,'reassigned',p.default_organization_id,v_elm_org,
         'current_elm_profile_default',jsonb_build_object('displayName',p.display_name)
  from atlas.user_profiles p
  where p.user_id in (
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
    '21436a28-40fd-4914-8015-a248d0dca14e'::uuid
  )
    and p.default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  on conflict (subject_schema,subject_table,subject_key) do nothing;

  update atlas.user_profiles
  set default_organization_id=v_elm_org,
      metadata=metadata || jsonb_build_object('historicalDefaultOrganizationId','818b9a23-65e9-4198-b86c-9496ba548642')
  where user_id in (
    '4cd799e2-16d4-4020-9d21-ccf1a2b98553'::uuid,
    '21436a28-40fd-4914-8015-a248d0dca14e'::uuid
  )
    and default_organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
end;
$function$;

-- Enforce FK consistency before restoring only the constraints we temporarily changed.
SET CONSTRAINTS ALL IMMEDIATE;

do $function$
declare
  r record;
begin
  for r in
    select child_schema,child_table,conname
    from custody_fk_deferral_guard_v1
    where not was_deferrable
    order by child_schema,child_table,conname
  loop
    execute format(
      'alter table %I.%I alter constraint %I not deferrable',
      r.child_schema,r.child_table,r.conname
    );
  end loop;
end;
$function$;

-- Prove temporary deferral did not leak and preexisting selected constraint state was preserved.
do $function$
begin
  if exists (
    select 1
    from custody_fk_deferral_guard_v1 g
    join pg_namespace n on n.nspname=g.child_schema
    join pg_class ch on ch.relnamespace=n.oid and ch.relname=g.child_table
    join pg_constraint c on c.conrelid=ch.oid and c.conname=g.conname
    where (not g.was_deferrable and c.condeferrable)
       or (g.was_deferrable and (not c.condeferrable or c.condeferred is distinct from g.was_deferred))
  ) then
    raise exception 'Temporary Organization-bearing parent-key FK deferral was not restored exactly.' using errcode='55000';
  end if;
end;
$function$;

-- Archive Waiting Room and every farm-keyed test record without promoting it.
do $function$
declare
  r record;
  v_key_col text;
begin
  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
  ) values
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
          subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
        )
        select %L,%L,(t.%I)::text,'archived','818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
               'waiting_room_test_scope',jsonb_build_object('farmId',$1::text)
        from %I.%I t
        where t.farm_id=$1
        on conflict (subject_schema,subject_table,subject_key) do nothing
      $sql$,r.table_schema,r.table_name,v_key_col,r.table_schema,r.table_name)
      using 'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid;
    end if;
  end loop;
end;
$function$;

-- Owner-level projects/tasks remain portfolio history only.
insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'atlas','tasks',t.id::text,'archived',t.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',t.title)
from atlas.tasks t
where t.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and t.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

insert into atlas.institutional_custody_adjudications(
  subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
)
select 'atlas','projects',p.id::text,'archived',p.organization_id,'owner_level_portfolio_work',jsonb_build_object('title',p.title)
from atlas.projects p
where p.organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid and p.farm_id is null
on conflict (subject_schema,subject_table,subject_key) do nothing;

-- Negative-control and communication invariants are part of the migration itself.
do $function$
declare
  v_elm_org uuid;
  v_fg_org uuid;
  v_guard record;
  v_source record;
begin
  select id into v_elm_org from atlas.organizations where metadata->>'custody_reconstruction_key'='elm_farm_organization_v1';
  select id into v_fg_org from atlas.organizations where metadata->>'custody_reconstruction_key'='feast_guild_organization_v1';
  select * into v_guard from custody_reconstruction_guard_v1;

  if (select count(*) from atlas.composition_runs where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) <> v_guard.composition_count
     or exists (select 1 from atlas.composition_runs where organization_id in (v_elm_org,v_fg_org)) then
    raise exception 'Generic composition custody changed without direct institutional evidence.' using errcode='55000';
  end if;

  if (select count(*) from local_intel.recommendation_lenses where organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid) <> v_guard.recommendation_lens_count
     or exists (select 1 from local_intel.recommendation_lenses where organization_id in (v_elm_org,v_fg_org)) then
    raise exception 'Recommendation lens custody changed without direct institutional evidence.' using errcode='55000';
  end if;

  for v_source in select * from custody_source_guard_v1 loop
    if not exists (
      select 1 from atlas.connected_sources s
      where s.id=v_source.id
        and s.authorization_state=v_source.authorization_state
        and s.granted_scopes=v_source.granted_scopes
        and s.capabilities=v_source.capabilities
        and s.last_sync_at is not distinct from v_source.last_sync_at
        and s.revoked_at is not distinct from v_source.revoked_at
    ) then
      raise exception 'Communication source behavior changed during custody reconstruction.' using errcode='55000';
    end if;
  end loop;

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
end;
$function$;

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

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,evidence_basis,evidence
  ) values (
    'atlas','organizations','818b9a23-65e9-4198-b86c-9496ba548642','archived',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,'legacy_mixed_portfolio_container',
    jsonb_build_object('newElmOrganizationId',v_elm_org,'newFeastGuildOrganizationId',v_fg_org)
  ) on conflict (subject_schema,subject_table,subject_key) do nothing;

  insert into atlas.institutional_custody_adjudications(
    subject_schema,subject_table,subject_key,disposition,historical_organization_id,historical_ledger_id,evidence_basis,evidence
  ) values (
    'atlas','ledgers','6dab72b7-cb2f-43eb-855e-c0c99756e0d6','archived',
    '818b9a23-65e9-4198-b86c-9496ba548642'::uuid,
    '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid,
    'legacy_mixed_portfolio_container',
    jsonb_build_object('newElmFarmLedgerId',v_farm_ledger,'newElmVenueLedgerId',v_venue_ledger,'newFeastGuildLedgerId',v_fg_ledger)
  ) on conflict (subject_schema,subject_table,subject_key) do nothing;

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
