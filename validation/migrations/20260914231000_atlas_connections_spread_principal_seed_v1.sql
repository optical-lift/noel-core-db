-- Package 1 postconditions for the permanent Principal Connections spread.
-- Runs only against the disposable production-schema clone and rolls back.

begin;

do $$
declare
  v_existing_spread uuid;
  v_triggered_spread uuid;
  v_before_sources integer;
  v_after_sources integer;
  v_result jsonb;
begin
  select s.id into v_existing_spread
  from atlas.notebook_spread_instances s
  where s.principal_id='66666666-6666-4666-8666-666666666666'
    and s.spread_key='connections';

  if v_existing_spread is null then
    raise exception 'Migration did not backfill Connections for an existing active Principal.';
  end if;

  if not exists(
    select 1
    from atlas.notebook_spread_instances s
    where s.id=v_existing_spread
      and s.scope_kind='person'
      and s.scope_id='66666666-6666-4666-8666-666666666666'
      and s.subject_domain='principal'
      and s.subject_kind='connections'
      and s.subject_id='66666666-6666-4666-8666-666666666666'
      and s.purpose_key='source-coverage-orientation'
      and s.horizon_key='current'
      and s.thread_key='connections'
      and s.title='Connections'
      and s.section_key='Connections'
      and s.spread_state='open'
      and coalesce((s.metadata->>'permanent')::boolean,false)
      and coalesce((s.metadata->>'truthOwner')::boolean,true)=false
      and s.composition_contract#>>'{forms,0,formFamily}'='ledger'
  ) then
    raise exception 'Connections spread identity/composition is not the governed permanent ledger.';
  end if;

  if not exists(
    select 1
    from atlas.notebook_spread_source_bindings b
    where b.spread_instance_id=v_existing_spread
      and b.source_domain='principal'
      and b.source_kind='connected_sources_v1'
      and b.source_id='66666666-6666-4666-8666-666666666666'
      and b.relationship_kind='evidence'
      and b.binding_state='active'
  ) then
    raise exception 'Connections spread is missing its governed connected-source evidence binding.';
  end if;

  if has_function_privilege('authenticated','atlas.establish_connections_spread_v1(uuid)','execute') then
    raise exception 'Authenticated callers can execute the internal Connections spread establishment writer.';
  end if;
  if not has_function_privilege('authenticated','atlas.ensure_connections_spread_self_api_v1()','execute') then
    raise exception 'Signed-in Principals cannot ensure/read their governed Connections spread.';
  end if;

  if not exists(
    select 1
    from pg_trigger t
    join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas'
      and c.relname='principals'
      and t.tgname='trg_seed_connections_spread_for_principal_v1'
      and not t.tgisinternal
  ) then
    raise exception 'Future active Principals are not protected by the Connections seed trigger.';
  end if;

  select count(*)::integer into v_before_sources from atlas.connected_sources;

  perform set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  v_result:=atlas.ensure_connections_spread_self_api_v1();

  if v_result#>>'{spread,spreadKey}' <> 'connections' then
    raise exception 'Authenticated ensure command did not return the durable Connections spread: %',v_result;
  end if;
  if (select count(*) from atlas.notebook_spread_instances where principal_id='66666666-6666-4666-8666-666666666666' and spread_key='connections') <> 1 then
    raise exception 'Connections ensure command is not idempotent.';
  end if;

  select count(*)::integer into v_after_sources from atlas.connected_sources;
  if v_after_sources <> v_before_sources then
    raise exception 'Creating/ensuring the Connections notebook page created provider/source truth.';
  end if;

  -- Prove future Principal seeding after the trigger exists.
  insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous)
  values('77777777-7777-4777-8777-777777777777','authenticated','authenticated','connections-trigger-fixture@example.invalid',now(),now(),false,false);

  insert into atlas.principals(id,user_id,stable_key,name,status,metadata)
  values('88888888-8888-4888-8888-888888888888','77777777-7777-4777-8777-777777777777','fixture-connections-trigger','Connections Trigger Fixture','active','{}'::jsonb);

  select s.id into v_triggered_spread
  from atlas.notebook_spread_instances s
  where s.principal_id='88888888-8888-4888-8888-888888888888'
    and s.spread_key='connections';

  if v_triggered_spread is null then
    raise exception 'New active Principal did not receive the permanent Connections spread.';
  end if;
end;
$$;

rollback;