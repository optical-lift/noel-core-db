begin;

set local statement_timeout = '15min';
set local lock_timeout = '30s';

-- Freeze writes to every table that can carry an Organization/Ledger coordinate
-- (plus the institutional graph/notebook roots touched by this cut) before any
-- physical rewrite begins. SHARE ROW EXCLUSIVE permits reads but blocks
-- concurrent INSERT/UPDATE/DELETE, closing the live-write race that can otherwise
-- append a retired id after the generic re-home pass has already visited a table.
do $lock_cut$
declare
  r record;
begin
  for r in
    with target_tables as (
      select distinct c.table_schema,c.table_name
      from information_schema.columns c
      join information_schema.tables t
        on t.table_schema=c.table_schema and t.table_name=c.table_name
      where c.table_schema in ('atlas','local_intel')
        and t.table_type='BASE TABLE'
        and c.data_type='uuid'
        and (
          c.column_name ~ '(^|_)organization_id
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Organization anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Ledger anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and name='Elm Farm' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and name='Elm Farm' and status='active'
  ) then
    raise exception 'Canonical Elm anchors changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and name='Feast Guild' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and name='Feast Guild' and status='active'
  ) then
    raise exception 'Canonical Feast Guild anchors changed.';
  end if;

  if (select count(*) from atlas.institutional_custody_carriers) <> 1
     or exists (
       select 1
       from atlas.institutional_custody_carriers
       where carrier_organization_id <> '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
          or carrier_ledger_id is distinct from '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
     ) then
    raise exception 'Custody carrier state changed; refusing destructive cut.';
  end if;

  if exists (
    select 1
    from atlas.institutional_custody_adjudications
    where historical_organization_id is distinct from '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Custody adjudications now cover another Organization.';
  end if;
end;
$anchors$;

-- One-time physical rewrite of Atlas build-state. Unique indexes remain active.
-- Transaction-scoped writer locks above remain held through COMMIT/ROLLBACK.
set local session_replication_role = replica;

-- Move typed Organization coordinates, excluding rows with canonical duplicates.
do $organization_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)organization_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
      and not (c.table_schema='atlas' and c.table_name in (
        'organization_memberships',
        'ledger_organization_participations'
      ))
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
      '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$organization_cut$;

-- Collapse duplicate Lex owner membership into canonical Elm owner membership.
do $owner_membership_cut$
declare r record;
begin
  for r in
    select distinct
      ns.nspname as table_schema,
      cl.relname as table_name,
      att.attname as column_name
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(fk_attnum,target_attnum,ord) on true
    join pg_attribute att
      on att.attrelid=cl.oid and att.attnum=u.fk_attnum
    join pg_attribute attt
      on attt.attrelid=clt.oid and attt.attnum=u.target_attnum
    where con.contype='f'
      and nst.nspname='atlas'
      and clt.relname='organization_memberships'
      and attt.attname='id'
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'b528660c-19d7-4411-b293-879fd74809c8'::uuid,
      '427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;
  end loop;
end;
$owner_membership_cut$;

delete from atlas.organization_memberships
where id='427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;

update atlas.organization_memberships
set organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
where organization_id='818b9a23-65e9-4198-b86c-9496ba548642';

delete from atlas.principal_ledger_authorities
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.ledger_organization_participations
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
   or organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Move typed Ledger coordinates.
do $ledger_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)ledger_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      '0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid,
      '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;
  end loop;
end;
$ledger_cut$;

-- Durable notebook state follows canonical Elm.
update atlas.notebook_spread_instances
set scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where scope_kind='organization'
  and scope_id='818b9a23-65e9-4198-b86c-9496ba548642';

update atlas.notebook_spread_instances
set spread_key='ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    title='Elm Farm',
    scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    subject_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    thread_key='thread:organization-ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where id='5644a8b7-f97c-46c3-b9c3-2fc5b3e3f2f6'::uuid;

update atlas.notebook_spread_source_bindings
set source_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where source_id='818b9a23-65e9-4198-b86c-9496ba548642';

-- Remove the compatibility state and obsolete graph identities.
delete from atlas.institutional_custody_carrier_targets;
delete from atlas.institutional_custody_carriers;
delete from atlas.institutional_custody_adjudications;

delete from atlas.ledgers
where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.organizations
where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Canonical roots take the human-readable stable keys.
update atlas.organizations
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Elm Farm')
where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;

update atlas.ledgers
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Elm Farm')
where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid;

update atlas.organizations
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Feast Guild')
where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid;

update atlas.ledgers
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Feast Guild')
where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid;

update atlas.organization_memberships
set permissions=(permissions - 'source' - 'compatibilityOnly')
where id='b528660c-19d7-4411-b293-879fd74809c8'::uuid;

set local session_replication_role = origin;

-- Stable call seams now resolve directly from physical canonical custody.
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
  select
    p_physical_organization_id,
    p_physical_ledger_id,
    'physical'::text,
    'physical_custody'::text,
    false;
$function$;

create or replace function atlas.effective_communication_endpoint_organization_v1(
  p_endpoint_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select ep.organization_id
  from atlas.communication_endpoints ep
  where ep.id=p_endpoint_id;
$function$;

create or replace function atlas.effective_work_item_organization_v1(
  p_work_item_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select w.organization_id
  from atlas.work_items w
  where w.id=p_work_item_id;
$function$;

create or replace function atlas.current_effective_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select om.id
  from atlas.organization_memberships om
  where om.person_id=atlas.current_person_id_v1()
    and om.active
    and om.organization_id=p_organization_id
  order by
    case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
    om.created_at,
    om.id
  limit 1;
$function$;

create or replace function atlas.is_effective_organization_owner_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select p_organization_id is not null and (
    exists (
      select 1
      from atlas.organization_memberships om
      where om.person_id=atlas.current_person_id_v1()
        and om.active
        and om.role='owner'
        and om.organization_id=p_organization_id
    )
    or exists (
      select 1
      from atlas.principal_ledger_authorities pla
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=pla.ledger_id
       and lop.organization_id=p_organization_id
       and lop.status='active'
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.ledgers l on l.id=pla.ledger_id and l.status='active'
      where pla.principal_id=atlas.current_principal_id_v1()
        and pla.status='active'
        and pla.authority_kind='root_governing'
    )
  );
$function$;

create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v3',
      'state','principal_required',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.sort_name,x.ledger_id),'[]'::jsonb)
  into v_items
  from (
    select
      l.id as ledger_id,
      coalesce(po.organization_name,l.name) as sort_name,
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',po.organization_id,
        'organizationStableKey',po.organization_stable_key,
        'organizationName',po.organization_name,
        'organizations',coalesce(orgs.items,'[]'::jsonb),
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) as item
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    left join lateral (
      select
        o.id as organization_id,
        o.stable_key as organization_stable_key,
        o.name as organization_name
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id and o.status='active'
      where p.ledger_id=l.id
        and p.status='active'
        and p.is_compatibility_primary
      limit 1
    ) po on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'participationKind',p.participation_kind,
        'isCompatibilityPrimary',p.is_compatibility_primary
      ) order by o.name,p.participation_kind) as items
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id
      where p.ledger_id=l.id and p.status='active'
    ) orgs on true
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) x;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v3',
    'state','ready',
    'principalId',v_principal_id,
    'items',v_items,
    'physicalCustodyOnly',true
  );
end;
$function$;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_ledgers jsonb;
  v_orgs jsonb;
  v_principal jsonb;
  v_principal_id uuid;
begin
  v_base:=atlas.principal_self_context_physical_compatibility_internal_v1();
  if coalesce(v_base->>'state','')<>'ready' then
    return v_base;
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  v_ledgers:=atlas.principal_ledgers_self_api_v1();

  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',q.id,
    'organizationStableKey',q.stable_key,
    'organizationName',q.name
  ) order by q.name,q.id),'[]'::jsonb)
  into v_orgs
  from (
    select distinct o.id,o.stable_key,o.name
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    join atlas.ledger_organization_participations p
      on p.ledger_id=l.id and p.status='active'
    join atlas.organizations o
      on o.id=p.organization_id and o.status='active'
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) q;

  v_principal:=(((v_base->'principal')::jsonb - 'organizationId'::text)
    || jsonb_build_object(
      'organizationId',null,
      'organizationIdSemantics','principal_ledger_graph'
    ));

  return v_base || jsonb_build_object(
    'contractVersion','principal_self_context_v4',
    'principal',v_principal,
    'governedLedgers',coalesce(v_ledgers->'items','[]'::jsonb),
    'governedOrganizations',v_orgs,
    'institutionalRoot','principal_ledger_graph',
    'physicalCustodyOnly',true
  );
end;
$function$;

-- The compatibility subsystem existed only for the retired mixed carrier.
drop table atlas.institutional_custody_carrier_targets;
drop table atlas.institutional_custody_carriers;
drop table atlas.institutional_custody_adjudications;
drop function atlas.institutional_custody_adjudication_immutable_v1();

do $function_dependency_check$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('atlas','public','local_intel')
      and (
        p.prosrc ilike '%institutional_custody_adjudications%'
        or p.prosrc ilike '%institutional_custody_carriers%'
        or p.prosrc ilike '%institutional_custody_carrier_targets%'
      )
  ) then
    raise exception 'Executable logic still depends on removed custody compatibility tables.';
  end if;
end;
$function_dependency_check$;

-- Typed coordinates must contain no retired ids.
do $typed_reference_check$
declare
  r record;
  n bigint;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and (
        c.column_name ~ '(^|_)organization_id$'
        or c.column_name ~ '(^|_)ledger_id$'
      )
  loop
    if r.column_name ~ '(^|_)organization_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

      if n<>0 then
        raise exception 'Retired Organization id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;

    if r.column_name ~ '(^|_)ledger_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

      if n<>0 then
        raise exception 'Retired Ledger id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;
  end loop;
end;
$typed_reference_check$;

-- Full FK audit because RI triggers were intentionally suppressed during the rewrite.
do $foreign_key_audit$
declare
  r record;
  join_pred text;
  child_present text;
  bad boolean;
begin
  for r in
    select
      con.oid,
      con.conname,
      ns.nspname as child_schema,
      cl.relname as child_table,
      nst.nspname as parent_schema,
      clt.relname as parent_table
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    where con.contype='f'
      and ns.nspname in ('atlas','local_intel')
    order by ns.nspname,cl.relname,con.conname
  loop
    select
      string_agg(
        format('c.%I = p.%I',ca.attname,pa.attname),
        ' and ' order by u.ord
      ),
      string_agg(
        format('c.%I is not null',ca.attname),
        ' and ' order by u.ord
      )
    into join_pred,child_present
    from pg_constraint con
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(catt,patt,ord) on true
    join pg_attribute ca
      on ca.attrelid=con.conrelid and ca.attnum=u.catt
    join pg_attribute pa
      on pa.attrelid=con.confrelid and pa.attnum=u.patt
    where con.oid=r.oid;

    execute format(
      'select exists(
         select 1
         from %I.%I c
         left join %I.%I p on %s
         where %s and p.ctid is null
       )',
      r.child_schema,r.child_table,
      r.parent_schema,r.parent_table,
      join_pred,child_present
    )
    into bad;

    if bad then
      raise exception 'Foreign-key integrity failed after carrier cut: % on %.%',
        r.conname,r.child_schema,r.child_table;
    end if;
  end loop;
end;
$foreign_key_audit$;

do $product_proof$
begin
  if to_regclass('atlas.institutional_custody_adjudications') is not null
     or to_regclass('atlas.institutional_custody_carriers') is not null
     or to_regclass('atlas.institutional_custody_carrier_targets') is not null then
    raise exception 'Custody compatibility tables survived eradication.';
  end if;

  if exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) or exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
  ) then
    raise exception 'Retired mixed Organization/Ledger survived eradication.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) then
    raise exception 'Canonical Elm root is not clean.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) then
    raise exception 'Canonical Feast Guild root is not clean.';
  end if;

  if (select organization_id
      from atlas.communication_endpoints
      where id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid)
     <> 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid then
    raise exception 'Elm communication endpoint did not move to canonical Elm.';
  end if;

  if exists (
    select 1
    from atlas.communication_conversations cc
    join atlas.communication_conversation_endpoints cce
      on cce.communication_conversation_id=cc.id
    where cce.communication_endpoint_id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
      and cc.organization_id<>'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
  ) then
    raise exception 'Elm conversations retained non-Elm physical custody.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances
    where spread_key='letters:7617a7b1-8713-4520-923f-51a15c6b2d7f'
      and scope_kind='organization'
      and scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
  ) then
    raise exception 'Letters · Elm Farm did not move to canonical Elm scope.';
  end if;

  if exists (
    select 1
    from atlas.communication_endpoints
    where organization_id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and address='hello@elmfarm.co'
  ) then
    raise exception 'Elm email leaked into canonical Feast Guild.';
  end if;
end;
$product_proof$;

commit;

          or c.column_name ~ '(^|_)ledger_id
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Organization anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Ledger anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and name='Elm Farm' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and name='Elm Farm' and status='active'
  ) then
    raise exception 'Canonical Elm anchors changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and name='Feast Guild' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and name='Feast Guild' and status='active'
  ) then
    raise exception 'Canonical Feast Guild anchors changed.';
  end if;

  if (select count(*) from atlas.institutional_custody_carriers) <> 1
     or exists (
       select 1
       from atlas.institutional_custody_carriers
       where carrier_organization_id <> '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
          or carrier_ledger_id is distinct from '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
     ) then
    raise exception 'Custody carrier state changed; refusing destructive cut.';
  end if;

  if exists (
    select 1
    from atlas.institutional_custody_adjudications
    where historical_organization_id is distinct from '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Custody adjudications now cover another Organization.';
  end if;
end;
$anchors$;

-- One-time physical rewrite of Atlas build-state. Unique indexes remain active.
set local session_replication_role = replica;

-- Move typed Organization coordinates, excluding rows with canonical duplicates.
do $organization_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)organization_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
      and not (c.table_schema='atlas' and c.table_name in (
        'organization_memberships',
        'ledger_organization_participations'
      ))
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
      '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$organization_cut$;

-- Collapse duplicate Lex owner membership into canonical Elm owner membership.
do $owner_membership_cut$
declare r record;
begin
  for r in
    select distinct
      ns.nspname as table_schema,
      cl.relname as table_name,
      att.attname as column_name
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(fk_attnum,target_attnum,ord) on true
    join pg_attribute att
      on att.attrelid=cl.oid and att.attnum=u.fk_attnum
    join pg_attribute attt
      on attt.attrelid=clt.oid and attt.attnum=u.target_attnum
    where con.contype='f'
      and nst.nspname='atlas'
      and clt.relname='organization_memberships'
      and attt.attname='id'
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'b528660c-19d7-4411-b293-879fd74809c8'::uuid,
      '427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;
  end loop;
end;
$owner_membership_cut$;

delete from atlas.organization_memberships
where id='427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;

update atlas.organization_memberships
set organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
where organization_id='818b9a23-65e9-4198-b86c-9496ba548642';

delete from atlas.principal_ledger_authorities
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.ledger_organization_participations
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
   or organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Move typed Ledger coordinates.
do $ledger_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)ledger_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      '0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid,
      '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;
  end loop;
end;
$ledger_cut$;

-- Durable notebook state follows canonical Elm.
update atlas.notebook_spread_instances
set scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where scope_kind='organization'
  and scope_id='818b9a23-65e9-4198-b86c-9496ba548642';

update atlas.notebook_spread_instances
set spread_key='ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    title='Elm Farm',
    scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    subject_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    thread_key='thread:organization-ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where id='5644a8b7-f97c-46c3-b9c3-2fc5b3e3f2f6'::uuid;

update atlas.notebook_spread_source_bindings
set source_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where source_id='818b9a23-65e9-4198-b86c-9496ba548642';

-- Remove the compatibility state and obsolete graph identities.
delete from atlas.institutional_custody_carrier_targets;
delete from atlas.institutional_custody_carriers;
delete from atlas.institutional_custody_adjudications;

delete from atlas.ledgers
where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.organizations
where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Canonical roots take the human-readable stable keys.
update atlas.organizations
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Elm Farm')
where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;

update atlas.ledgers
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Elm Farm')
where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid;

update atlas.organizations
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Feast Guild')
where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid;

update atlas.ledgers
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Feast Guild')
where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid;

update atlas.organization_memberships
set permissions=(permissions - 'source' - 'compatibilityOnly')
where id='b528660c-19d7-4411-b293-879fd74809c8'::uuid;

set local session_replication_role = origin;

-- Stable call seams now resolve directly from physical canonical custody.
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
  select
    p_physical_organization_id,
    p_physical_ledger_id,
    'physical'::text,
    'physical_custody'::text,
    false;
$function$;

create or replace function atlas.effective_communication_endpoint_organization_v1(
  p_endpoint_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select ep.organization_id
  from atlas.communication_endpoints ep
  where ep.id=p_endpoint_id;
$function$;

create or replace function atlas.effective_work_item_organization_v1(
  p_work_item_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select w.organization_id
  from atlas.work_items w
  where w.id=p_work_item_id;
$function$;

create or replace function atlas.current_effective_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select om.id
  from atlas.organization_memberships om
  where om.person_id=atlas.current_person_id_v1()
    and om.active
    and om.organization_id=p_organization_id
  order by
    case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
    om.created_at,
    om.id
  limit 1;
$function$;

create or replace function atlas.is_effective_organization_owner_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select p_organization_id is not null and (
    exists (
      select 1
      from atlas.organization_memberships om
      where om.person_id=atlas.current_person_id_v1()
        and om.active
        and om.role='owner'
        and om.organization_id=p_organization_id
    )
    or exists (
      select 1
      from atlas.principal_ledger_authorities pla
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=pla.ledger_id
       and lop.organization_id=p_organization_id
       and lop.status='active'
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.ledgers l on l.id=pla.ledger_id and l.status='active'
      where pla.principal_id=atlas.current_principal_id_v1()
        and pla.status='active'
        and pla.authority_kind='root_governing'
    )
  );
$function$;

create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v3',
      'state','principal_required',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.sort_name,x.ledger_id),'[]'::jsonb)
  into v_items
  from (
    select
      l.id as ledger_id,
      coalesce(po.organization_name,l.name) as sort_name,
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',po.organization_id,
        'organizationStableKey',po.organization_stable_key,
        'organizationName',po.organization_name,
        'organizations',coalesce(orgs.items,'[]'::jsonb),
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) as item
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    left join lateral (
      select
        o.id as organization_id,
        o.stable_key as organization_stable_key,
        o.name as organization_name
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id and o.status='active'
      where p.ledger_id=l.id
        and p.status='active'
        and p.is_compatibility_primary
      limit 1
    ) po on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'participationKind',p.participation_kind,
        'isCompatibilityPrimary',p.is_compatibility_primary
      ) order by o.name,p.participation_kind) as items
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id
      where p.ledger_id=l.id and p.status='active'
    ) orgs on true
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) x;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v3',
    'state','ready',
    'principalId',v_principal_id,
    'items',v_items,
    'physicalCustodyOnly',true
  );
end;
$function$;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_ledgers jsonb;
  v_orgs jsonb;
  v_principal jsonb;
  v_principal_id uuid;
begin
  v_base:=atlas.principal_self_context_physical_compatibility_internal_v1();
  if coalesce(v_base->>'state','')<>'ready' then
    return v_base;
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  v_ledgers:=atlas.principal_ledgers_self_api_v1();

  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',q.id,
    'organizationStableKey',q.stable_key,
    'organizationName',q.name
  ) order by q.name,q.id),'[]'::jsonb)
  into v_orgs
  from (
    select distinct o.id,o.stable_key,o.name
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    join atlas.ledger_organization_participations p
      on p.ledger_id=l.id and p.status='active'
    join atlas.organizations o
      on o.id=p.organization_id and o.status='active'
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) q;

  v_principal:=(((v_base->'principal')::jsonb - 'organizationId'::text)
    || jsonb_build_object(
      'organizationId',null,
      'organizationIdSemantics','principal_ledger_graph'
    ));

  return v_base || jsonb_build_object(
    'contractVersion','principal_self_context_v4',
    'principal',v_principal,
    'governedLedgers',coalesce(v_ledgers->'items','[]'::jsonb),
    'governedOrganizations',v_orgs,
    'institutionalRoot','principal_ledger_graph',
    'physicalCustodyOnly',true
  );
end;
$function$;

-- The compatibility subsystem existed only for the retired mixed carrier.
drop table atlas.institutional_custody_carrier_targets;
drop table atlas.institutional_custody_carriers;
drop table atlas.institutional_custody_adjudications;
drop function atlas.institutional_custody_adjudication_immutable_v1();

do $function_dependency_check$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('atlas','public','local_intel')
      and (
        p.prosrc ilike '%institutional_custody_adjudications%'
        or p.prosrc ilike '%institutional_custody_carriers%'
        or p.prosrc ilike '%institutional_custody_carrier_targets%'
      )
  ) then
    raise exception 'Executable logic still depends on removed custody compatibility tables.';
  end if;
end;
$function_dependency_check$;

-- Typed coordinates must contain no retired ids.
do $typed_reference_check$
declare
  r record;
  n bigint;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and (
        c.column_name ~ '(^|_)organization_id$'
        or c.column_name ~ '(^|_)ledger_id$'
      )
  loop
    if r.column_name ~ '(^|_)organization_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

      if n<>0 then
        raise exception 'Retired Organization id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;

    if r.column_name ~ '(^|_)ledger_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

      if n<>0 then
        raise exception 'Retired Ledger id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;
  end loop;
end;
$typed_reference_check$;

-- Full FK audit because RI triggers were intentionally suppressed during the rewrite.
do $foreign_key_audit$
declare
  r record;
  join_pred text;
  child_present text;
  bad boolean;
begin
  for r in
    select
      con.oid,
      con.conname,
      ns.nspname as child_schema,
      cl.relname as child_table,
      nst.nspname as parent_schema,
      clt.relname as parent_table
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    where con.contype='f'
      and ns.nspname in ('atlas','local_intel')
    order by ns.nspname,cl.relname,con.conname
  loop
    select
      string_agg(
        format('c.%I = p.%I',ca.attname,pa.attname),
        ' and ' order by u.ord
      ),
      string_agg(
        format('c.%I is not null',ca.attname),
        ' and ' order by u.ord
      )
    into join_pred,child_present
    from pg_constraint con
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(catt,patt,ord) on true
    join pg_attribute ca
      on ca.attrelid=con.conrelid and ca.attnum=u.catt
    join pg_attribute pa
      on pa.attrelid=con.confrelid and pa.attnum=u.patt
    where con.oid=r.oid;

    execute format(
      'select exists(
         select 1
         from %I.%I c
         left join %I.%I p on %s
         where %s and p.ctid is null
       )',
      r.child_schema,r.child_table,
      r.parent_schema,r.parent_table,
      join_pred,child_present
    )
    into bad;

    if bad then
      raise exception 'Foreign-key integrity failed after carrier cut: % on %.%',
        r.conname,r.child_schema,r.child_table;
    end if;
  end loop;
end;
$foreign_key_audit$;

do $product_proof$
begin
  if to_regclass('atlas.institutional_custody_adjudications') is not null
     or to_regclass('atlas.institutional_custody_carriers') is not null
     or to_regclass('atlas.institutional_custody_carrier_targets') is not null then
    raise exception 'Custody compatibility tables survived eradication.';
  end if;

  if exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) or exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
  ) then
    raise exception 'Retired mixed Organization/Ledger survived eradication.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) then
    raise exception 'Canonical Elm root is not clean.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) then
    raise exception 'Canonical Feast Guild root is not clean.';
  end if;

  if (select organization_id
      from atlas.communication_endpoints
      where id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid)
     <> 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid then
    raise exception 'Elm communication endpoint did not move to canonical Elm.';
  end if;

  if exists (
    select 1
    from atlas.communication_conversations cc
    join atlas.communication_conversation_endpoints cce
      on cce.communication_conversation_id=cc.id
    where cce.communication_endpoint_id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
      and cc.organization_id<>'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
  ) then
    raise exception 'Elm conversations retained non-Elm physical custody.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances
    where spread_key='letters:7617a7b1-8713-4520-923f-51a15c6b2d7f'
      and scope_kind='organization'
      and scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
  ) then
    raise exception 'Letters · Elm Farm did not move to canonical Elm scope.';
  end if;

  if exists (
    select 1
    from atlas.communication_endpoints
    where organization_id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and address='hello@elmfarm.co'
  ) then
    raise exception 'Elm email leaked into canonical Feast Guild.';
  end if;
end;
$product_proof$;

commit;

        )

      union
      select *
      from (values
        ('atlas','organizations'),
        ('atlas','ledgers'),
        ('atlas','organization_memberships'),
        ('atlas','principal_ledger_authorities'),
        ('atlas','ledger_organization_participations'),
        ('atlas','notebook_spread_instances'),
        ('atlas','notebook_spread_source_bindings'),
        ('atlas','institutional_custody_adjudications'),
        ('atlas','institutional_custody_carriers'),
        ('atlas','institutional_custody_carrier_targets')
      ) v(table_schema,table_name)
    )
    select table_schema,table_name
    from target_tables
    order by table_schema,table_name
  loop
    execute format(
      'lock table %I.%I in share row exclusive mode',
      r.table_schema,r.table_name
    );
  end loop;
end;
$lock_cut$;

do $anchors$
begin
  if not exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Organization anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
      and stable_key='feast_guild' and name='Feast Guild' and status='active'
  ) then
    raise exception 'Retired mixed Ledger anchor changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and name='Elm Farm' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and name='Elm Farm' and status='active'
  ) then
    raise exception 'Canonical Elm anchors changed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and name='Feast Guild' and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and name='Feast Guild' and status='active'
  ) then
    raise exception 'Canonical Feast Guild anchors changed.';
  end if;

  if (select count(*) from atlas.institutional_custody_carriers) <> 1
     or exists (
       select 1
       from atlas.institutional_custody_carriers
       where carrier_organization_id <> '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
          or carrier_ledger_id is distinct from '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
     ) then
    raise exception 'Custody carrier state changed; refusing destructive cut.';
  end if;

  if exists (
    select 1
    from atlas.institutional_custody_adjudications
    where historical_organization_id is distinct from '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Custody adjudications now cover another Organization.';
  end if;
end;
$anchors$;

-- One-time physical rewrite of Atlas build-state. Unique indexes remain active.
set local session_replication_role = replica;

-- Move typed Organization coordinates, excluding rows with canonical duplicates.
do $organization_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)organization_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
      and not (c.table_schema='atlas' and c.table_name in (
        'organization_memberships',
        'ledger_organization_participations'
      ))
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid,
      '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  end loop;
end;
$organization_cut$;

-- Collapse duplicate Lex owner membership into canonical Elm owner membership.
do $owner_membership_cut$
declare r record;
begin
  for r in
    select distinct
      ns.nspname as table_schema,
      cl.relname as table_name,
      att.attname as column_name
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(fk_attnum,target_attnum,ord) on true
    join pg_attribute att
      on att.attrelid=cl.oid and att.attnum=u.fk_attnum
    join pg_attribute attt
      on attt.attrelid=clt.oid and attt.attnum=u.target_attnum
    where con.contype='f'
      and nst.nspname='atlas'
      and clt.relname='organization_memberships'
      and attt.attname='id'
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      'b528660c-19d7-4411-b293-879fd74809c8'::uuid,
      '427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;
  end loop;
end;
$owner_membership_cut$;

delete from atlas.organization_memberships
where id='427e84d8-e7dc-4292-8b25-002758d8d1f9'::uuid;

update atlas.organization_memberships
set organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
where organization_id='818b9a23-65e9-4198-b86c-9496ba548642';

delete from atlas.principal_ledger_authorities
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.ledger_organization_participations
where ledger_id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
   or organization_id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Move typed Ledger coordinates.
do $ledger_cut$
declare r record;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and c.column_name ~ '(^|_)ledger_id$'
      and not (c.table_schema='atlas' and c.table_name like 'institutional_custody_%')
    order by c.table_schema,c.table_name,c.ordinal_position
  loop
    execute format(
      'update %I.%I set %I=$1 where %I=$2',
      r.table_schema,r.table_name,r.column_name,r.column_name
    )
    using
      '0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid,
      '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;
  end loop;
end;
$ledger_cut$;

-- Durable notebook state follows canonical Elm.
update atlas.notebook_spread_instances
set scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where scope_kind='organization'
  and scope_id='818b9a23-65e9-4198-b86c-9496ba548642';

update atlas.notebook_spread_instances
set spread_key='ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    title='Elm Farm',
    scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    subject_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    thread_key='thread:organization-ledger:fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where id='5644a8b7-f97c-46c3-b9c3-2fc5b3e3f2f6'::uuid;

update atlas.notebook_spread_source_bindings
set source_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2',
    updated_at=now()
where source_id='818b9a23-65e9-4198-b86c-9496ba548642';

-- Remove the compatibility state and obsolete graph identities.
delete from atlas.institutional_custody_carrier_targets;
delete from atlas.institutional_custody_carriers;
delete from atlas.institutional_custody_adjudications;

delete from atlas.ledgers
where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

delete from atlas.organizations
where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

-- Canonical roots take the human-readable stable keys.
update atlas.organizations
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Elm Farm')
where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid;

update atlas.ledgers
set stable_key='elm_farm',
    metadata=(metadata
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Elm Farm')
where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid;

update atlas.organizations
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'membership_claimed')
      || jsonb_build_object('canonicalInstitution','Feast Guild')
where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid;

update atlas.ledgers
set stable_key='feast_guild',
    metadata=(metadata
      - 'cleanRoom'
      - 'custodyMode'
      - 'custody_reconstruction_key'
      - 'establishment_basis'
      - 'initialForOrganizationId')
      || jsonb_build_object('canonicalEndeavor','Feast Guild')
where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid;

update atlas.organization_memberships
set permissions=(permissions - 'source' - 'compatibilityOnly')
where id='b528660c-19d7-4411-b293-879fd74809c8'::uuid;

set local session_replication_role = origin;

-- Stable call seams now resolve directly from physical canonical custody.
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
  select
    p_physical_organization_id,
    p_physical_ledger_id,
    'physical'::text,
    'physical_custody'::text,
    false;
$function$;

create or replace function atlas.effective_communication_endpoint_organization_v1(
  p_endpoint_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select ep.organization_id
  from atlas.communication_endpoints ep
  where ep.id=p_endpoint_id;
$function$;

create or replace function atlas.effective_work_item_organization_v1(
  p_work_item_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  select w.organization_id
  from atlas.work_items w
  where w.id=p_work_item_id;
$function$;

create or replace function atlas.current_effective_organization_membership_v1(
  p_organization_id uuid
)
returns uuid
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select om.id
  from atlas.organization_memberships om
  where om.person_id=atlas.current_person_id_v1()
    and om.active
    and om.organization_id=p_organization_id
  order by
    case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end,
    om.created_at,
    om.id
  limit 1;
$function$;

create or replace function atlas.is_effective_organization_owner_v1(
  p_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
  select p_organization_id is not null and (
    exists (
      select 1
      from atlas.organization_memberships om
      where om.person_id=atlas.current_person_id_v1()
        and om.active
        and om.role='owner'
        and om.organization_id=p_organization_id
    )
    or exists (
      select 1
      from atlas.principal_ledger_authorities pla
      join atlas.ledger_organization_participations lop
        on lop.ledger_id=pla.ledger_id
       and lop.organization_id=p_organization_id
       and lop.status='active'
       and lop.participation_kind='governing'
       and lop.is_compatibility_primary
      join atlas.ledgers l on l.id=pla.ledger_id and l.status='active'
      where pla.principal_id=atlas.current_principal_id_v1()
        and pla.status='active'
        and pla.authority_kind='root_governing'
    )
  );
$function$;

create or replace function atlas.principal_ledgers_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_principal_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  if v_principal_id is null then
    return jsonb_build_object(
      'contractVersion','principal_ledgers_self_v3',
      'state','principal_required',
      'items','[]'::jsonb
    );
  end if;

  select coalesce(jsonb_agg(x.item order by x.sort_name,x.ledger_id),'[]'::jsonb)
  into v_items
  from (
    select
      l.id as ledger_id,
      coalesce(po.organization_name,l.name) as sort_name,
      jsonb_build_object(
        'ledgerId',l.id,
        'ledgerStableKey',l.stable_key,
        'ledgerName',l.name,
        'ledgerKind',l.ledger_kind,
        'ledgerStatus',l.status,
        'organizationId',po.organization_id,
        'organizationStableKey',po.organization_stable_key,
        'organizationName',po.organization_name,
        'organizations',coalesce(orgs.items,'[]'::jsonb),
        'authorityKind',a.authority_kind,
        'scopeState',coalesce(l.metadata->>'scope_state','canonical')
      ) as item
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    left join lateral (
      select
        o.id as organization_id,
        o.stable_key as organization_stable_key,
        o.name as organization_name
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id and o.status='active'
      where p.ledger_id=l.id
        and p.status='active'
        and p.is_compatibility_primary
      limit 1
    ) po on true
    left join lateral (
      select jsonb_agg(jsonb_build_object(
        'organizationId',o.id,
        'organizationStableKey',o.stable_key,
        'organizationName',o.name,
        'participationKind',p.participation_kind,
        'isCompatibilityPrimary',p.is_compatibility_primary
      ) order by o.name,p.participation_kind) as items
      from atlas.ledger_organization_participations p
      join atlas.organizations o on o.id=p.organization_id
      where p.ledger_id=l.id and p.status='active'
    ) orgs on true
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) x;

  return jsonb_build_object(
    'contractVersion','principal_ledgers_self_v3',
    'state','ready',
    'principalId',v_principal_id,
    'items',v_items,
    'physicalCustodyOnly',true
  );
end;
$function$;

create or replace function atlas.principal_self_context_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_base jsonb;
  v_ledgers jsonb;
  v_orgs jsonb;
  v_principal jsonb;
  v_principal_id uuid;
begin
  v_base:=atlas.principal_self_context_physical_compatibility_internal_v1();
  if coalesce(v_base->>'state','')<>'ready' then
    return v_base;
  end if;

  v_principal_id:=atlas.current_principal_id_v1();
  v_ledgers:=atlas.principal_ledgers_self_api_v1();

  select coalesce(jsonb_agg(jsonb_build_object(
    'organizationId',q.id,
    'organizationStableKey',q.stable_key,
    'organizationName',q.name
  ) order by q.name,q.id),'[]'::jsonb)
  into v_orgs
  from (
    select distinct o.id,o.stable_key,o.name
    from atlas.principal_ledger_authorities a
    join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
    join atlas.ledger_organization_participations p
      on p.ledger_id=l.id and p.status='active'
    join atlas.organizations o
      on o.id=p.organization_id and o.status='active'
    where a.principal_id=v_principal_id
      and a.status='active'
      and a.authority_kind='root_governing'
  ) q;

  v_principal:=(((v_base->'principal')::jsonb - 'organizationId'::text)
    || jsonb_build_object(
      'organizationId',null,
      'organizationIdSemantics','principal_ledger_graph'
    ));

  return v_base || jsonb_build_object(
    'contractVersion','principal_self_context_v4',
    'principal',v_principal,
    'governedLedgers',coalesce(v_ledgers->'items','[]'::jsonb),
    'governedOrganizations',v_orgs,
    'institutionalRoot','principal_ledger_graph',
    'physicalCustodyOnly',true
  );
end;
$function$;

-- The compatibility subsystem existed only for the retired mixed carrier.
drop table atlas.institutional_custody_carrier_targets;
drop table atlas.institutional_custody_carriers;
drop table atlas.institutional_custody_adjudications;
drop function atlas.institutional_custody_adjudication_immutable_v1();

do $function_dependency_check$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('atlas','public','local_intel')
      and (
        p.prosrc ilike '%institutional_custody_adjudications%'
        or p.prosrc ilike '%institutional_custody_carriers%'
        or p.prosrc ilike '%institutional_custody_carrier_targets%'
      )
  ) then
    raise exception 'Executable logic still depends on removed custody compatibility tables.';
  end if;
end;
$function_dependency_check$;

-- Typed coordinates must contain no retired ids.
do $typed_reference_check$
declare
  r record;
  n bigint;
begin
  for r in
    select c.table_schema,c.table_name,c.column_name
    from information_schema.columns c
    join information_schema.tables t
      on t.table_schema=c.table_schema and t.table_name=c.table_name
    where c.table_schema in ('atlas','local_intel')
      and t.table_type='BASE TABLE'
      and c.data_type='uuid'
      and (
        c.column_name ~ '(^|_)organization_id$'
        or c.column_name ~ '(^|_)ledger_id$'
      )
  loop
    if r.column_name ~ '(^|_)organization_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '818b9a23-65e9-4198-b86c-9496ba548642'::uuid;

      if n<>0 then
        raise exception 'Retired Organization id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;

    if r.column_name ~ '(^|_)ledger_id$' then
      execute format(
        'select count(*) from %I.%I where %I=$1',
        r.table_schema,r.table_name,r.column_name
      )
      into n
      using '6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid;

      if n<>0 then
        raise exception 'Retired Ledger id remains in %.%.%',
          r.table_schema,r.table_name,r.column_name;
      end if;
    end if;
  end loop;
end;
$typed_reference_check$;

-- Full FK audit because RI triggers were intentionally suppressed during the rewrite.
do $foreign_key_audit$
declare
  r record;
  join_pred text;
  child_present text;
  bad boolean;
begin
  for r in
    select
      con.oid,
      con.conname,
      ns.nspname as child_schema,
      cl.relname as child_table,
      nst.nspname as parent_schema,
      clt.relname as parent_table
    from pg_constraint con
    join pg_class cl on cl.oid=con.conrelid
    join pg_namespace ns on ns.oid=cl.relnamespace
    join pg_class clt on clt.oid=con.confrelid
    join pg_namespace nst on nst.oid=clt.relnamespace
    where con.contype='f'
      and ns.nspname in ('atlas','local_intel')
    order by ns.nspname,cl.relname,con.conname
  loop
    select
      string_agg(
        format('c.%I = p.%I',ca.attname,pa.attname),
        ' and ' order by u.ord
      ),
      string_agg(
        format('c.%I is not null',ca.attname),
        ' and ' order by u.ord
      )
    into join_pred,child_present
    from pg_constraint con
    join lateral unnest(con.conkey,con.confkey) with ordinality
      u(catt,patt,ord) on true
    join pg_attribute ca
      on ca.attrelid=con.conrelid and ca.attnum=u.catt
    join pg_attribute pa
      on pa.attrelid=con.confrelid and pa.attnum=u.patt
    where con.oid=r.oid;

    execute format(
      'select exists(
         select 1
         from %I.%I c
         left join %I.%I p on %s
         where %s and p.ctid is null
       )',
      r.child_schema,r.child_table,
      r.parent_schema,r.parent_table,
      join_pred,child_present
    )
    into bad;

    if bad then
      raise exception 'Foreign-key integrity failed after carrier cut: % on %.%',
        r.conname,r.child_schema,r.child_table;
    end if;
  end loop;
end;
$foreign_key_audit$;

do $product_proof$
begin
  if to_regclass('atlas.institutional_custody_adjudications') is not null
     or to_regclass('atlas.institutional_custody_carriers') is not null
     or to_regclass('atlas.institutional_custody_carrier_targets') is not null then
    raise exception 'Custody compatibility tables survived eradication.';
  end if;

  if exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) or exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
  ) then
    raise exception 'Retired mixed Organization/Ledger survived eradication.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and stable_key='elm_farm' and name='Elm Farm'
  ) then
    raise exception 'Canonical Elm root is not clean.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and stable_key='feast_guild' and name='Feast Guild'
  ) then
    raise exception 'Canonical Feast Guild root is not clean.';
  end if;

  if (select organization_id
      from atlas.communication_endpoints
      where id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid)
     <> 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid then
    raise exception 'Elm communication endpoint did not move to canonical Elm.';
  end if;

  if exists (
    select 1
    from atlas.communication_conversations cc
    join atlas.communication_conversation_endpoints cce
      on cce.communication_conversation_id=cc.id
    where cce.communication_endpoint_id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
      and cc.organization_id<>'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
  ) then
    raise exception 'Elm conversations retained non-Elm physical custody.';
  end if;

  if not exists (
    select 1
    from atlas.notebook_spread_instances
    where spread_key='letters:7617a7b1-8713-4520-923f-51a15c6b2d7f'
      and scope_kind='organization'
      and scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
  ) then
    raise exception 'Letters · Elm Farm did not move to canonical Elm scope.';
  end if;

  if exists (
    select 1
    from atlas.communication_endpoints
    where organization_id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and address='hello@elmfarm.co'
  ) then
    raise exception 'Elm email leaked into canonical Feast Guild.';
  end if;
end;
$product_proof$;

commit;
