begin;

do $validation$
declare
  r record;
  n bigint;
  join_pred text;
  child_present text;
  bad boolean;
begin
  -- Retired compatibility identities and tables must be gone.
  if exists (
    select 1 from atlas.organizations
    where id='818b9a23-65e9-4198-b86c-9496ba548642'::uuid
  ) then
    raise exception 'Retired mixed Organization still exists.';
  end if;

  if exists (
    select 1 from atlas.ledgers
    where id='6dab72b7-cb2f-43eb-855e-c0c99756e0d6'::uuid
  ) then
    raise exception 'Retired mixed Ledger still exists.';
  end if;

  if to_regclass('atlas.institutional_custody_adjudications') is not null
     or to_regclass('atlas.institutional_custody_carriers') is not null
     or to_regclass('atlas.institutional_custody_carrier_targets') is not null then
    raise exception 'Institutional custody compatibility tables remain.';
  end if;

  if to_regprocedure('atlas.institutional_custody_adjudication_immutable_v1()') is not null then
    raise exception 'Institutional custody compatibility trigger function remains.';
  end if;

  -- Canonical institution/Ledger roots must be clean and distinct.
  if not exists (
    select 1 from atlas.organizations
    where id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
      and stable_key='elm_farm'
      and name='Elm Farm'
      and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='0c5f53dd-3659-4fed-b8d7-a771a4172f36'::uuid
      and stable_key='elm_farm'
      and name='Elm Farm'
      and status='active'
  ) then
    raise exception 'Canonical Elm Farm root is missing or malformed.';
  end if;

  if not exists (
    select 1 from atlas.organizations
    where id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and stable_key='feast_guild'
      and name='Feast Guild'
      and status='active'
  ) or not exists (
    select 1 from atlas.ledgers
    where id='147c8900-1cad-4936-85a3-9bfc73415df3'::uuid
      and stable_key='feast_guild'
      and name='Feast Guild'
      and status='active'
  ) then
    raise exception 'Canonical Feast Guild root is missing or malformed.';
  end if;

  -- No typed Organization/Ledger coordinate may retain the retired ids.
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

  -- No executable database logic may retain compatibility-table dependency.
  if exists (
    select 1
    from pg_proc p
    join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname in ('atlas','public','local_intel')
      and (
        p.prosrc ilike '%institutional_custody_adjudications%'
        or p.prosrc ilike '%institutional_custody_carriers%'
        or p.prosrc ilike '%institutional_custody_carrier_targets%'
      )
  ) then
    raise exception 'Executable database logic retains removed custody compatibility dependency.';
  end if;

  -- Product-critical Elm correspondence custody must now be physical.
  if (select organization_id
      from atlas.communication_endpoints
      where id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid)
     <> 'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid then
    raise exception 'hello@elmfarm.co is not physically owned by canonical Elm Farm.';
  end if;

  if (select count(*)
      from atlas.communication_conversations cc
      join atlas.communication_conversation_endpoints cce
        on cce.communication_conversation_id=cc.id
      where cce.communication_endpoint_id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
        and cc.organization_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid) < 23 then
    raise exception 'Existing Elm correspondence Conversations were lost during physical custody cut.';
  end if;

  if exists (
    select 1
    from atlas.communication_conversations cc
    join atlas.communication_conversation_endpoints cce
      on cce.communication_conversation_id=cc.id
    where cce.communication_endpoint_id='7617a7b1-8713-4520-923f-51a15c6b2d7f'::uuid
      and cc.organization_id<>'fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'::uuid
  ) then
    raise exception 'Elm correspondence still has a non-Elm physical Conversation.';
  end if;

  if not exists (
    select 1 from atlas.notebook_spread_instances
    where spread_key='letters:7617a7b1-8713-4520-923f-51a15c6b2d7f'
      and scope_kind='organization'
      and scope_id='fc4ad5aa-2d09-4ea6-ba50-eaf0f34fc3f2'
      and title='Letters · Elm Farm'
  ) then
    raise exception 'Letters · Elm Farm is not scoped to canonical Elm Farm.';
  end if;

  if exists (
    select 1 from atlas.communication_endpoints
    where organization_id='c46593ea-43d6-41db-ad8f-215f4d93a78b'::uuid
      and address='hello@elmfarm.co'
  ) then
    raise exception 'Elm communication endpoint leaked into canonical Feast Guild.';
  end if;

  -- Full FK audit: migration intentionally bypasses RI triggers during physical rewrite.
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
      raise exception 'Foreign-key integrity failed after carrier eradication: % on %.%',
        r.conname,r.child_schema,r.child_table;
    end if;
  end loop;
end;
$validation$;

rollback;
