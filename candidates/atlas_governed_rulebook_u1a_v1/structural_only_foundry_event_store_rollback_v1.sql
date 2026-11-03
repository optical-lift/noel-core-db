-- U1A foundry event store: source-owned structural-only, NOT migration.
-- Original source: supabase/migrations/20260927213513_create_foundry_store_v0_1.sql
-- Noel native catalog read-only fingerprint November 3 2026: 4d4b78504168e6359fe9e236bbbfa5d9
-- No durable source events, workspace, authority, Rulebook, Work or grants.
BEGIN;
SET LOCAL statement_timeout='60s';
DO $guard$
BEGIN
 IF current_database()<>'atlas_work_disposable'
    OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
    OR current_setting('port')='55432'
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR to_regclass('foundry.events') IS NOT NULL
    OR to_regclass('foundry.snapshots') IS NOT NULL
    OR to_regrole('service_role') IS NULL
    OR to_regrole('anon') IS NULL
    OR to_regrole('authenticated') IS NULL
 THEN RAISE EXCEPTION 'Refusing Foundry source outside isolated current PG17 structural test'
   USING ERRCODE='42501';
 END IF;
END $guard$;

-- BEGIN VERBATIM ORIGINAL NOEL MAIN FOUNDRY STORE SOURCE.

create schema if not exists foundry;

create table if not exists foundry.events (
  workspace_id text not null,
  sequence bigint not null check (sequence >= 1),
  event_id text not null unique,
  event_type text not null,
  envelope jsonb not null check (jsonb_typeof(envelope) = 'object'),
  inserted_at timestamptz not null default now(),
  primary key (workspace_id, sequence)
);

create table if not exists foundry.snapshots (
  workspace_id text primary key,
  through_sequence bigint not null check (through_sequence >= 0),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  inserted_at timestamptz not null default now()
);

create or replace function foundry.prevent_event_mutation()
returns trigger
language plpgsql
set search_path = foundry, pg_temp
as $$
begin
  raise exception 'foundry events are append-only';
end;
$$;

drop trigger if exists foundry_events_append_only on foundry.events;
create trigger foundry_events_append_only
before update or delete on foundry.events
for each row execute function foundry.prevent_event_mutation();

create or replace function foundry.append_event(p_event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = foundry, pg_temp
as $$
declare
  v_event_id text;
  v_workspace_id text;
  v_event_type text;
  v_sequence bigint;
  v_expected bigint;
  v_existing jsonb;
begin
  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    raise exception 'event must be a JSON object';
  end if;

  v_event_id := nullif(p_event->>'event_id', '');
  v_workspace_id := nullif(p_event->>'workspace_id', '');
  v_event_type := nullif(p_event->>'event_type', '');

  if v_event_id is null then raise exception 'missing event_id'; end if;
  if v_workspace_id is null then raise exception 'missing workspace_id'; end if;
  if v_event_type is null then raise exception 'missing event_type'; end if;
  if not (p_event ? 'sequence') then raise exception 'missing sequence'; end if;
  if not (p_event ? 'payload') or jsonb_typeof(p_event->'payload') <> 'object' then raise exception 'payload must be an object'; end if;
  if not (p_event ? 'basis_refs') or jsonb_typeof(p_event->'basis_refs') <> 'array' then raise exception 'basis_refs must be an array'; end if;
  if nullif(p_event->>'authority','') is null then raise exception 'missing authority'; end if;
  if nullif(p_event->>'actor_kind','') is null then raise exception 'missing actor_kind'; end if;
  if nullif(p_event->>'recorded_at','') is null then raise exception 'missing recorded_at'; end if;
  if nullif(p_event->>'protocol_version','') is null then raise exception 'missing protocol_version'; end if;

  begin
    v_sequence := (p_event->>'sequence')::bigint;
  exception when others then
    raise exception 'sequence must be a positive integer';
  end;
  if v_sequence < 1 then raise exception 'sequence must be a positive integer'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_workspace_id, 0));

  select envelope into v_existing from foundry.events where event_id = v_event_id;
  if found then
    if v_existing = p_event then
      return jsonb_build_object('status','REPLAYED','event',v_existing);
    end if;
    raise exception 'event_id % already exists with different content', v_event_id;
  end if;

  select coalesce(max(sequence), 0) + 1 into v_expected
  from foundry.events
  where workspace_id = v_workspace_id;

  if v_sequence <> v_expected then
    raise exception 'workspace % expected sequence %, received %', v_workspace_id, v_expected, v_sequence;
  end if;

  insert into foundry.events(workspace_id, sequence, event_id, event_type, envelope)
  values (v_workspace_id, v_sequence, v_event_id, v_event_type, p_event);

  return jsonb_build_object('status','APPENDED','event',p_event);
end;
$$;

create or replace function foundry.read_events(
  p_workspace_id text,
  p_after_sequence bigint default 0,
  p_through_sequence bigint default null,
  p_limit integer default null
)
returns setof jsonb
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select e.envelope
  from foundry.events e
  where e.workspace_id = p_workspace_id
    and e.sequence > greatest(coalesce(p_after_sequence,0),0)
    and (p_through_sequence is null or e.sequence <= p_through_sequence)
  order by e.sequence
  limit case when p_limit is not null and p_limit > 0 then p_limit else null end;
$$;

create or replace function foundry.has_event(p_event_id text)
returns boolean
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select exists(select 1 from foundry.events where event_id = p_event_id);
$$;

create or replace function foundry.write_snapshot(p_snapshot jsonb)
returns jsonb
language plpgsql
security definer
set search_path = foundry, pg_temp
as $$
declare
  v_workspace_id text;
  v_through bigint;
  v_latest bigint;
  v_prior bigint;
begin
  if p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then raise exception 'snapshot must be a JSON object'; end if;
  v_workspace_id := nullif(p_snapshot->>'workspace_id','');
  if v_workspace_id is null then raise exception 'missing workspace_id'; end if;
  if not (p_snapshot ? 'workspace') or jsonb_typeof(p_snapshot->'workspace') <> 'object' then raise exception 'workspace must be an object'; end if;
  if nullif(p_snapshot->>'created_at','') is null then raise exception 'missing created_at'; end if;
  if nullif(p_snapshot->>'protocol_version','') is null then raise exception 'missing protocol_version'; end if;
  begin
    v_through := (p_snapshot->>'through_sequence')::bigint;
  exception when others then
    raise exception 'through_sequence must be a non-negative integer';
  end;
  if v_through < 0 then raise exception 'through_sequence must be a non-negative integer'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_workspace_id, 0));
  select coalesce(max(sequence),0) into v_latest from foundry.events where workspace_id = v_workspace_id;
  if v_through > v_latest then raise exception 'snapshot through_sequence % exceeds stored event sequence %', v_through, v_latest; end if;

  select through_sequence into v_prior from foundry.snapshots where workspace_id = v_workspace_id;
  if found and v_through < v_prior then raise exception 'snapshot regression for %: % < %', v_workspace_id, v_through, v_prior; end if;

  insert into foundry.snapshots(workspace_id, through_sequence, snapshot)
  values (v_workspace_id, v_through, p_snapshot)
  on conflict (workspace_id) do update
    set through_sequence = excluded.through_sequence,
        snapshot = excluded.snapshot,
        inserted_at = now();

  return p_snapshot;
end;
$$;

create or replace function foundry.read_latest_snapshot(p_workspace_id text)
returns jsonb
language sql
stable
security definer
set search_path = foundry, pg_temp
as $$
  select snapshot from foundry.snapshots where workspace_id = p_workspace_id;
$$;

revoke all on schema foundry from public, anon, authenticated;
revoke all on all tables in schema foundry from public, anon, authenticated;
revoke all on all functions in schema foundry from public, anon, authenticated;
grant usage on schema foundry to service_role;
grant execute on function foundry.append_event(jsonb) to service_role;
grant execute on function foundry.read_events(text,bigint,bigint,integer) to service_role;
grant execute on function foundry.has_event(text) to service_role;
grant execute on function foundry.write_snapshot(jsonb) to service_role;
grant execute on function foundry.read_latest_snapshot(text) to service_role;
-- END VERBATIM ORIGINAL NOEL MAIN FOUNDRY STORE SOURCE.

-- A source-owned append-only test: all identifiers fictional and transaction-scoped.
DO $probe$
DECLARE
 v_event jsonb := jsonb_build_object(
  'event_id','u1a-fictional-source-only-001',
  'workspace_id','u1a-fictional-disposable-only',
  'event_type','fictional_structural_probe',
  'sequence',1,
  'payload',jsonb_build_object('fictional',true),
  'basis_refs','[]'::jsonb,
  'authority','source_only_never_adoption',
  'actor_kind','test_only',
  'recorded_at','2026-11-03T00:00:00Z',
  'protocol_version','u1a_structural_test_v1'
 );
 v_snapshot jsonb := jsonb_build_object(
  'workspace_id','u1a-fictional-disposable-only',
  'through_sequence',1,
  'workspace',jsonb_build_object('fictional',true),
  'created_at','2026-11-03T00:00:00Z',
  'protocol_version','u1a_structural_test_v1'
 );
 v_denied boolean := false;
BEGIN
 IF foundry.append_event(v_event)->>'status'<>'APPENDED'
    OR foundry.append_event(v_event)->>'status'<>'REPLAYED'
    OR NOT foundry.has_event('u1a-fictional-source-only-001')
    OR (SELECT count(*) FROM foundry.read_events('u1a-fictional-disposable-only',0,NULL,NULL))<>1
 THEN RAISE EXCEPTION 'Original event append, identical replay or read contract failed'; END IF;
 BEGIN
  UPDATE foundry.events SET event_type='invalid_write' WHERE event_id='u1a-fictional-source-only-001';
 EXCEPTION WHEN OTHERS THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Original append-only trigger permitted UPDATE'; END IF;
 v_denied:=false;
 BEGIN
  DELETE FROM foundry.events WHERE event_id='u1a-fictional-source-only-001';
 EXCEPTION WHEN OTHERS THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Original append-only trigger permitted DELETE'; END IF;
 IF foundry.write_snapshot(v_snapshot) IS DISTINCT FROM v_snapshot
    OR foundry.read_latest_snapshot('u1a-fictional-disposable-only') IS DISTINCT FROM v_snapshot
 THEN RAISE EXCEPTION 'Original Foundry snapshot write/read failed'; END IF;
END $probe$;

-- Compare exact native catalog contract (structural owner, role ACL, function
-- definitions, triggers, indexes). This comparison cannot establish live
-- source-custody permissions, membership, reviewer identity or Source adoption.
DO $contract$
DECLARE
 v_expected constant text := '4d4b78504168e6359fe9e236bbbfa5d9';
 v_actual text;
 v_tables integer;
 v_functions integer;
BEGIN
 WITH c AS (
 SELECT jsonb_build_object(
 'tables',(SELECT jsonb_agg(jsonb_build_object(
 'name',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity,'acl',coalesce(c.relacl::text,'NULL'),
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',con.conname,'def',pg_get_constraintdef(con.oid,true)) ORDER BY con.conname) FROM pg_constraint con WHERE con.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid)) FROM pg_index i WHERE i.indrelid=c.oid),
 'triggers',(SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)
 ) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='foundry' AND c.relname IN ('events','snapshots') AND c.relkind='r'),
 'functions',(SELECT jsonb_agg(jsonb_build_object('name',p.proname,'args',pg_get_function_identity_arguments(p.oid),'owner',pg_get_userbyid(p.proowner),'securityDefiner',p.prosecdef,'acl',coalesce(p.proacl::text,'NULL'),'definitionMd5',md5(pg_get_functiondef(p.oid))) ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='foundry' AND p.proname IN ('append_event','read_events','has_event','write_snapshot','read_latest_snapshot','prevent_event_mutation')),
 'schema',(SELECT jsonb_build_object('owner',pg_get_userbyid(n.nspowner),'acl',coalesce(n.nspacl::text,'NULL')) FROM pg_namespace n WHERE n.nspname='foundry')
 ) AS j
 ) SELECT md5(j::text),jsonb_array_length(j->'tables'),jsonb_array_length(j->'functions')
 INTO v_actual,v_tables,v_functions FROM c;
 IF v_tables<>2 OR v_functions<>6 OR v_actual IS DISTINCT FROM v_expected THEN
  RAISE EXCEPTION 'Current Noel Foundry Event source catalog differs from original migration'
    USING ERRCODE='42501';
 END IF;
 RAISE NOTICE 'FOUNDRY_STORE_STRUCTURAL_PASS: exact native table/function ACL fingerprint and append-only behavior';
END $contract$;

-- Always remove original source and fictional data: never migrate.
ROLLBACK;
