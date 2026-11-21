-- U1A composed structural-only native source (never migration).
-- All four component source packages are pinned at this held Noel commit.
-- No current source data, no real authorization, no durable Work or Review.
-- This validates compatibility, not signed approval or role membership.
BEGIN;
SET LOCAL statement_timeout='120s';
DO $composition_guard$
BEGIN
 IF current_database()<>'atlas_work_disposable'
  OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
  OR current_setting('port')='55432'
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR to_regclass('atlas.work_requirements') IS NOT NULL
  OR to_regclass('foundry.events') IS NOT NULL
  OR to_regclass('foundry.workspace_authority_registry_v1') IS NOT NULL
  OR to_regclass('foundry.source_custody_review_cases_v1') IS NOT NULL
  OR to_regprocedure('atlas.foundry_current_signed_principal_v1()') IS NOT NULL
 THEN RAISE EXCEPTION 'Refusing U1A structural-only composition outside pristine disposable source'
  USING ERRCODE='42501';
 END IF;
END $composition_guard$;

-- BEGIN PINNED ORIGINAL COMPONENT 1: structural_only_requirement_contract_rollback_v1.sql
-- U1A: STRUCTURAL PROOF ONLY. This is NOT a migration or authorization.
-- Provenance: live Noel read-only pg_catalog, 2026-11-03.
-- Canonical full table contract md5: 6bad563a25890c2c6315305b1b61a8d5
-- Never apply to production, persistent dev, or the RiverSong 55432 source.
-- Runner must provision a separate PG17 cluster and restore source schema.

SET LOCAL statement_timeout = '60s';
DO $preflight$
BEGIN
 IF current_database() IS DISTINCT FROM 'atlas_work_disposable'
    OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
    OR current_setting('port')='55432'
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR to_regclass('atlas.work_requirements') IS NOT NULL
    OR to_regclass('atlas.organization_units') IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM pg_index i
      WHERE i.indrelid='atlas.organization_units'::regclass
        AND i.indisunique AND i.indisvalid
        AND i.indpred IS NULL AND i.indexprs IS NULL
        AND i.indnkeyatts=2
        AND pg_get_indexdef(i.indexrelid,1,true)='organization_id'
        AND pg_get_indexdef(i.indexrelid,2,true)='id')
    OR to_regrole('service_role') IS NULL
    OR to_regrole('anon') IS NULL
    OR to_regrole('authenticated') IS NULL
 THEN
   RAISE EXCEPTION 'STOP: isolated current-source native Requirements prerequisites not established'
     USING ERRCODE='42501';
 END IF;
END
$preflight$;

-- Column sequence, defaults, generated constraints and indexes transcribed
-- from the actual read-only native catalog; NOT generated from historical docs.
CREATE TABLE atlas.work_requirements (
 id uuid NOT NULL DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 requirement_kind text NOT NULL DEFAULT 'operational'::text,
 summary text NOT NULL,
 source_object_type text,
 source_object_id uuid,
 state text NOT NULL DEFAULT 'active'::text,
 established_at timestamptz NOT NULL DEFAULT now(),
 requirement_began_at timestamptz,
 earliest_relevant_at timestamptz,
 latest_satisfactory_at timestamptz,
 consequence_of_delay jsonb NOT NULL DEFAULT '{}'::jsonb,
 jurisdiction_key text,
 satisfied_at timestamptz,
 cancelled_at timestamptz,
 superseded_by_requirement_id uuid,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 organization_unit_id uuid,
 stable_key text,
 CONSTRAINT work_requirements_pkey PRIMARY KEY (id),
 CONSTRAINT work_requirements_state_check CHECK (
   state = ANY (ARRAY['active'::text,'satisfied'::text,'cancelled'::text,'superseded'::text])),
 CONSTRAINT work_requirements_check CHECK (
   latest_satisfactory_at IS NULL OR earliest_relevant_at IS NULL
   OR latest_satisfactory_at >= earliest_relevant_at),
 CONSTRAINT work_requirements_check1 CHECK (
   ((state='satisfied'::text) = (satisfied_at IS NOT NULL)) OR state<>'satisfied'::text),
 CONSTRAINT work_requirements_check2 CHECK (
   ((state='cancelled'::text) = (cancelled_at IS NOT NULL)) OR state<>'cancelled'::text),
 CONSTRAINT work_requirements_superseded_by_requirement_id_fkey
   FOREIGN KEY (superseded_by_requirement_id) REFERENCES atlas.work_requirements(id),
 CONSTRAINT work_requirements_organization_unit_org_fk
   FOREIGN KEY (organization_id,organization_unit_id)
     REFERENCES atlas.organization_units(organization_id,id) ON DELETE RESTRICT
);

CREATE UNIQUE INDEX work_requirements_org_id_identity_idx
 ON atlas.work_requirements (organization_id,id);
CREATE INDEX work_requirements_org_latest_idx
 ON atlas.work_requirements (organization_id,latest_satisfactory_at)
 WHERE state='active'::text;
CREATE INDEX work_requirements_org_state_idx
 ON atlas.work_requirements (organization_id,state);
CREATE INDEX work_requirements_org_unit_state_idx
 ON atlas.work_requirements (organization_id,organization_unit_id,state);
CREATE INDEX work_requirements_source_idx
 ON atlas.work_requirements (source_object_type,source_object_id)
 WHERE source_object_type IS NOT NULL AND source_object_id IS NOT NULL;
CREATE UNIQUE INDEX work_requirements_org_stable_key_uq
 ON atlas.work_requirements (organization_id,stable_key)
 WHERE stable_key IS NOT NULL;

ALTER TABLE atlas.work_requirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.work_requirements FROM PUBLIC, anon, authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON atlas.work_requirements TO service_role;

-- Exact read-only native catalog fingerprint after transient DDL. All
-- identities, constraints, indexes, owner and actual RLS/ACL must agree.
DO $verify$
DECLARE
 v_actual text;
BEGIN
 WITH contract AS (
  SELECT jsonb_build_object(
   'table','atlas.work_requirements',
   'postgresMajor',split_part(current_setting('server_version'),'.',1)::integer,
   'owner',pg_get_userbyid(c.relowner),
   'rls',c.relrowsecurity,
   'forceRls',c.relforcerowsecurity,
   'acl',coalesce(c.relacl::text,'NULL'),
   'columns',coalesce((SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid)) ORDER BY a.attnum)
     FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'[]'::jsonb),
   'constraints',coalesce((SELECT jsonb_agg(jsonb_build_object('name',x.conname,'type',x.contype,'def',pg_get_constraintdef(x.oid,true)) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),'[]'::jsonb),
   'indexes',coalesce((SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid)) FROM pg_index i WHERE i.indrelid=c.oid),'[]'::jsonb),
   'policies',coalesce((SELECT jsonb_agg(jsonb_build_object('name',p.polname,'roles',p.polroles::text,'cmd',p.polcmd,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),'[]'::jsonb),
   'triggers',coalesce((SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'[]'::jsonb)
  ) AS j
  FROM pg_class c WHERE c.oid='atlas.work_requirements'::regclass
 ) SELECT md5(j::text) INTO v_actual FROM contract;

 IF v_actual IS DISTINCT FROM '6bad563a25890c2c6315305b1b61a8d5' THEN
   RAISE EXCEPTION 'STOP: native Requirement table contract does not match current Noel catalog'
     USING ERRCODE='42501';
 END IF;
 RAISE NOTICE 'REQUIREMENT_CONTRACT_PASS: current PG17 table structure and RLS/ACL exactly match native catalog';
END
$verify$;

-- PROVE ROLLBACK, never leave an extra table in the temporary cluster.
-- END PINNED COMPONENT 1

-- BEGIN PINNED ORIGINAL COMPONENT 2: structural_only_foundry_event_store_rollback_v1.sql
-- U1A foundry event store: source-owned structural-only, NOT migration.
-- Original source: supabase/migrations/20260927213513_create_foundry_store_v0_1.sql
-- Noel native catalog read-only fingerprint November 3 2026: 4d4b78504168e6359fe9e236bbbfa5d9
-- No durable source events, workspace, authority, Rulebook, Work or grants.

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
 v_first jsonb;
 v_replay jsonb;
 v_written jsonb;
 v_read jsonb;
BEGIN
 -- Never combine side-effecting SQL functions in one Boolean expression:
 -- PostgreSQL need not preserve their left-to-right evaluation order.
 v_first:=foundry.append_event(v_event);
 IF v_first->>'status'<>'APPENDED' THEN
  RAISE EXCEPTION 'First original event append failed';
 END IF;
 v_replay:=foundry.append_event(v_event);
 IF v_replay->>'status'<>'REPLAYED' THEN
  RAISE EXCEPTION 'Identical original event replay failed';
 END IF;
 IF NOT foundry.has_event('u1a-fictional-source-only-001')
    OR (SELECT count(*) FROM foundry.read_events('u1a-fictional-disposable-only',0,NULL,NULL))<>1
 THEN RAISE EXCEPTION 'Original event read-after-write contract failed'; END IF;
 BEGIN
  UPDATE foundry.events SET event_type='invalid_write' WHERE event_id='u1a-fictional-source-only-001';
 EXCEPTION WHEN OTHERS THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Original append-only trigger permitted UPDATE'; END IF;
 v_denied:=false;
 BEGIN
  DELETE FROM foundry.events WHERE event_id='u1a-fictional-source-only-001';
 EXCEPTION WHEN OTHERS THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Original append-only trigger permitted DELETE'; END IF;
 v_written:=foundry.write_snapshot(v_snapshot);
 v_read:=foundry.read_latest_snapshot('u1a-fictional-disposable-only');
 IF v_written IS DISTINCT FROM v_snapshot OR v_read IS DISTINCT FROM v_snapshot
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
-- END PINNED COMPONENT 2

-- BEGIN PINNED ORIGINAL COMPONENT 3: structural_only_foundry_custody_tables_rollback_v1.sql
-- U1A custody table structural-only native source probe (NOT migration).
-- Original unmodified source blocks: Noel
-- supabase/migrations/20261024010000_shared_foundry_connected_workspace_gate1_signed_v1.sql
-- Current Noel normalized table catalog MD5 with C-collated index sort (2026-11-03):
-- d61fb82fb37dbc9d8b31ccbfce09bebf
-- No Person/Principal, source Review Case, Work or Rulebook records generated.

SET LOCAL statement_timeout='60s';
DO $guard$
BEGIN
 IF current_database()<>'atlas_work_disposable'
  OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
  OR current_setting('port')='55432'
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR to_regclass('atlas.principals') IS NULL
  OR to_regclass('foundry.workspace_authority_registry_v1') IS NOT NULL
  OR to_regclass('foundry.source_custody_review_cases_v1') IS NOT NULL
  OR to_regrole('service_role') IS NULL
  OR to_regrole('anon') IS NULL
  OR to_regrole('authenticated') IS NULL
 THEN RAISE EXCEPTION 'Refusing Foundry custody structural source in unverified PG17'
    USING ERRCODE='42501';
 END IF;
END $guard$;

-- Only the previously versioned original source may establish this namespace.
CREATE SCHEMA IF NOT EXISTS foundry;

-- BEGIN VERBATIM PRIVATE WORKSPACE CUSTODY TABLE SOURCE

CREATE TABLE foundry.workspace_authority_registry_v1 (
  workspace_id text PRIMARY KEY
    CHECK (length(btrim(workspace_id)) BETWEEN 1 AND 180),
  creation_request_id uuid NOT NULL,
  owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  protocol_version text NOT NULL DEFAULT '0.1'
    CHECK (protocol_version='0.1'),
  provisional_subject_label text NOT NULL
    CHECK (length(btrim(provisional_subject_label)) BETWEEN 1 AND 500),
  provisional_field text NOT NULL
    CHECK (length(btrim(provisional_field)) BETWEEN 1 AND 2000),
  -- A subject label never establishes or merges a canonical Person.
  -- A verified Person link needs a separate owning-domain identity command.
  subject_identity_state text NOT NULL DEFAULT 'unresolved'
    CHECK (subject_identity_state IN ('unresolved','provisional')),
  custody_scope_kind text NOT NULL
    CHECK (custody_scope_kind IN ('verified_self','documented_external')),
  -- The initial source-custody decision is explicitly pending. It is NOT
  -- authorized merely because the operator knows a name or has an AI transcript.
  custody_review_state text NOT NULL DEFAULT 'pending'
    CHECK (custody_review_state IN ('pending','reviewed','suspended','revoked')),
  custody_basis_refs text[] NOT NULL DEFAULT '{}'::text[],
  custody_reviewed_by_principal_id uuid REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  custody_reviewed_at timestamptz,
  custody_review_method text
    CHECK (custody_review_method IS NULL
      OR custody_review_method IN ('canonical_self','reviewed_source_authorization')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by_principal_id uuid NOT NULL REFERENCES atlas.principals(id)
    ON DELETE RESTRICT,
  suspended_at timestamptz,
  revoked_at timestamptz,
  CHECK (
    (custody_review_state='reviewed'
     AND cardinality(custody_basis_refs)>0
     AND custody_reviewed_by_principal_id IS NOT NULL
     AND custody_reviewed_at IS NOT NULL
     AND custody_review_method IS NOT NULL)
    OR
    (custody_review_state<>'reviewed')
  ),
  CHECK (
    (custody_scope_kind='verified_self'
      AND (custody_review_method IS NULL OR custody_review_method='canonical_self'))
    OR
    (custody_scope_kind='documented_external'
      AND (custody_review_method IS NULL OR custody_review_method='reviewed_source_authorization'))
  ),
  UNIQUE (owner_principal_id, creation_request_id),
  CHECK (custody_review_state<>'revoked' OR revoked_at IS NOT NULL),
  CHECK (custody_review_state<>'suspended' OR suspended_at IS NOT NULL)
);

-- Guarding private data at the table boundary is defense in depth.
-- NO direct client grants, public views, AI-written ownership or subject claims.
ALTER TABLE foundry.workspace_authority_registry_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON foundry.workspace_authority_registry_v1
  FROM PUBLIC, anon, authenticated, service_role;
-- END VERBATIM PRIVATE WORKSPACE CUSTODY TABLE SOURCE

-- BEGIN VERBATIM INDEPENDENT SOURCE REVIEW CASE TABLE SOURCE

CREATE TABLE foundry.source_custody_review_cases_v1 (
  case_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id text NOT NULL REFERENCES foundry.workspace_authority_registry_v1(workspace_id),
  request_id uuid NOT NULL,
  owner_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  reviewer_principal_id uuid NOT NULL REFERENCES atlas.principals(id),
  claim_basis_kind text NOT NULL CHECK (claim_basis_kind IN (
    'first_party','public_source','subject_authorization','custodian_authorization'
  )),
  source_refs text[] NOT NULL CHECK(cardinality(source_refs) BETWEEN 1 AND 12),
  permitted_human_actions text[] NOT NULL CHECK(cardinality(permitted_human_actions) BETWEEN 1 AND 4),
  scope_description text NOT NULL CHECK(length(btrim(scope_description)) BETWEEN 15 AND 2000),
  claimed_authority_basis text NOT NULL CHECK(length(btrim(claimed_authority_basis)) BETWEEN 20 AND 3000),
  review_state text NOT NULL DEFAULT 'pending' CHECK (
    review_state IN ('pending','approved','rejected','revoked')
  ),
  review_basis text,
  reviewed_at timestamptz,
  revoked_at timestamptz,
  revoked_by_principal_id uuid REFERENCES atlas.principals(id),
  revoke_reason text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(owner_principal_id,request_id),
  CHECK(owner_principal_id<>reviewer_principal_id),
  CHECK(review_state<>'approved' OR (reviewed_at IS NOT NULL AND length(btrim(review_basis)) >= 25)),
  CHECK(review_state<>'revoked' OR (revoked_at IS NOT NULL AND revoked_by_principal_id IS NOT NULL)),
  CHECK(permitted_human_actions <@ ARRAY['catalog','preserve','transcribe','analyze']::text[]),
  CHECK(NOT ('agent_access' = ANY(permitted_human_actions))),
  CHECK(expires_at IS NULL OR expires_at>created_at)
);
CREATE INDEX source_custody_review_cases_workspace_owner_v1
  ON foundry.source_custody_review_cases_v1(workspace_id,owner_principal_id);
CREATE INDEX source_custody_review_cases_reviewer_pending_v1
  ON foundry.source_custody_review_cases_v1(reviewer_principal_id,review_state);

ALTER TABLE foundry.source_custody_review_cases_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON foundry.source_custody_review_cases_v1
  FROM PUBLIC,anon,authenticated,service_role;
-- END VERBATIM INDEPENDENT SOURCE REVIEW CASE TABLE SOURCE

DO $contract$
DECLARE v_actual text;v_tables integer;v_component record;v_index record;
BEGIN
 WITH c AS (
 SELECT jsonb_build_object(
 'tables',(SELECT jsonb_agg(jsonb_build_object(
 'name',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity,'acl',coalesce(c.relacl::text,'NULL'),
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',con.conname,'def',pg_get_constraintdef(con.oid,true)) ORDER BY con.conname) FROM pg_constraint con WHERE con.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid) COLLATE "C") FROM pg_index i WHERE i.indrelid=c.oid),
 'triggers',(SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)
 ) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='foundry' AND c.relname IN ('workspace_authority_registry_v1','source_custody_review_cases_v1') AND c.relkind='r')
 ) AS j
 ) SELECT md5(j::text),jsonb_array_length(j->'tables') INTO v_actual,v_tables FROM c;
 -- Hashes are harmless structural metadata. When the source and the current
 -- catalog disagree, the disposable test publishes ONLY these fixed-size
 -- hashes, not table contents, SQL, credentials or Principal identities.
 FOR v_component IN
  SELECT c.relname,
  md5(jsonb_build_object('owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity,'acl',coalesce(c.relacl::text,'NULL'))::text) AS meta_md5,
  md5(coalesce((SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'null'::jsonb)::text) AS columns_md5,
  md5(coalesce((SELECT jsonb_agg(jsonb_build_object('name',con.conname,'def',pg_get_constraintdef(con.oid,true)) ORDER BY con.conname) FROM pg_constraint con WHERE con.conrelid=c.oid),'null'::jsonb)::text) AS constraints_md5,
  md5(coalesce((SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid) COLLATE "C") FROM pg_index i WHERE i.indrelid=c.oid),'null'::jsonb)::text) AS indexes_md5,
  md5(coalesce((SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),'null'::jsonb)::text) AS triggers_md5
  FROM pg_class c
  WHERE c.oid IN ('foundry.workspace_authority_registry_v1'::regclass,'foundry.source_custody_review_cases_v1'::regclass)
  ORDER BY c.relname
 LOOP
  RAISE NOTICE 'U1A_CUSTODY_COMPONENT_HASH: % % % % % %',
   v_component.relname,v_component.meta_md5,v_component.columns_md5,
   v_component.constraints_md5,v_component.indexes_md5,v_component.triggers_md5;
 END LOOP;
 -- Exact per-index fingerprints identify source-definition discrepancies
 -- without exposing private table rows or arbitrary SQL text.
 FOR v_index IN
  SELECT cls.relname AS index_name,md5(pg_get_indexdef(i.indexrelid)) AS md5_value
  FROM pg_index i JOIN pg_class cls ON cls.oid=i.indexrelid
  WHERE i.indrelid='foundry.source_custody_review_cases_v1'::regclass
  ORDER BY cls.relname
 LOOP
  RAISE NOTICE 'U1A_REVIEW_INDEX_HASH: % %',v_index.index_name,v_index.md5_value;
 END LOOP;
 IF v_tables<>2 OR v_actual IS DISTINCT FROM 'd61fb82fb37dbc9d8b31ccbfce09bebf' THEN
  RAISE EXCEPTION 'Actual current Noel Foundry custody table contract differs from original source'
   USING ERRCODE='42501';
 END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='foundry.workspace_authority_registry_v1'::regclass)
   OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='foundry.source_custody_review_cases_v1'::regclass)
 THEN RAISE EXCEPTION 'Noel private Foundry custody storage must retain RLS';
 END IF;
 RAISE NOTICE 'FOUNDRY_CUSTODY_TABLES_STRUCTURAL_PASS: exact private native review registry and ACL/constraint fingerprint';
END $contract$;
-- END PINNED COMPONENT 3

-- BEGIN PINNED ORIGINAL COMPONENT 4: structural_only_foundry_signed_principal_rollback_v1.sql
-- U1A original Foundry signed principal source: compile-only/negative-source test.
-- This is NOT a migration or a live signed authorization test.
-- Exact Noel native signed principal definition md5 (read-only 2026-11-03):
-- e69b3383920f43c664d58e4b527c6d6d

SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 IF current_database()<>'atlas_work_disposable'
  OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
  OR current_setting('port')='55432'
  OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
  OR to_regprocedure('atlas.foundry_current_signed_principal_v1()') IS NOT NULL
  OR to_regclass('atlas.principals') IS NULL
  OR to_regclass('auth.users') IS NULL
  OR to_regclass('auth.sessions') IS NULL
  OR to_regprocedure('auth.uid()') IS NULL
  OR to_regprocedure('auth.jwt()') IS NULL
  OR to_regrole('authenticated') IS NULL
  OR to_regrole('anon') IS NULL
  OR to_regrole('service_role') IS NULL
 THEN RAISE EXCEPTION 'Existing original native signed Principal schema dependencies unavailable on disposable clone'
  USING ERRCODE='42501';
 END IF;
END $preflight$;

-- BEGIN VERBATIM REVIEWED NOEL SIGNED PRINCIPAL SOURCE

CREATE OR REPLACE FUNCTION atlas.foundry_current_signed_principal_v1()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','pg_temp'
AS $fn$
DECLARE v_user uuid:=auth.uid();
        v_session uuid;
        v_principal uuid;
BEGIN
  IF v_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.users u
    WHERE u.id=v_user AND u.is_anonymous=false
    AND (u.banned_until IS NULL OR u.banned_until<=now())
  ) THEN
    RAISE EXCEPTION 'Active non-anonymous Atlas sign-in required' USING ERRCODE='42501';
  END IF;
  BEGIN
    v_session:=NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'Invalid signed session' USING ERRCODE='42501';
  END;
  IF v_session IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s
    WHERE s.id=v_session AND s.user_id=v_user
    AND (s.not_after IS NULL OR s.not_after>now())
  ) THEN
    RAISE EXCEPTION 'Revoked or missing signed session' USING ERRCODE='42501';
  END IF;
  SELECT p.id INTO v_principal FROM atlas.principals p
    WHERE p.user_id=v_user AND p.status='active';
  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Active Atlas Principal required' USING ERRCODE='42501';
  END IF;
  RETURN v_principal;
END
$fn$;
REVOKE ALL ON FUNCTION atlas.foundry_current_signed_principal_v1()
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.foundry_current_signed_principal_v1()
  TO authenticated;
-- END VERBATIM REVIEWED NOEL SIGNED PRINCIPAL SOURCE

DO $contract$
DECLARE
 v_owner text;
 v_acl text;
 v_definer boolean;
 v_definition_md5 text;
 v_denied boolean:=false;
BEGIN
 SELECT pg_get_userbyid(p.proowner),coalesce(p.proacl::text,'NULL'),
        p.prosecdef,md5(pg_get_functiondef(p.oid))
 INTO v_owner,v_acl,v_definer,v_definition_md5
 FROM pg_proc p
 WHERE p.oid='atlas.foundry_current_signed_principal_v1()'::regprocedure;
 IF v_owner<>'postgres'
    OR v_definer IS DISTINCT FROM true
    OR v_acl<>'{postgres=X/postgres,authenticated=X/postgres}'
    OR v_definition_md5<>'e69b3383920f43c664d58e4b527c6d6d'
 THEN RAISE EXCEPTION 'Foundry signed Principal definition or permissions differ from native Noel'
  USING ERRCODE='42501';
 END IF;
 -- Without an actual GoTrue signed session, the unaltered source MUST deny.
 -- This is not an attempt to forge or impersonate a user.
 BEGIN
  PERFORM atlas.foundry_current_signed_principal_v1();
 EXCEPTION WHEN SQLSTATE '42501' THEN
  v_denied:=true;
 END;
 IF NOT v_denied THEN
  RAISE EXCEPTION 'Original signed Principal source accepted an unsigned session'
   USING ERRCODE='42501';
 END IF;
 RAISE NOTICE 'FOUNDRY_SIGNED_PRINCIPAL_STRUCTURAL_PASS: exact source grants and unsigned denial';
END $contract$;
-- END PINNED COMPONENT 4

DO $composition_post$
BEGIN
 IF to_regclass('atlas.work_requirements') IS NULL
  OR to_regclass('foundry.events') IS NULL
  OR to_regclass('foundry.snapshots') IS NULL
  OR to_regclass('foundry.workspace_authority_registry_v1') IS NULL
  OR to_regclass('foundry.source_custody_review_cases_v1') IS NULL
  OR to_regprocedure('atlas.foundry_current_signed_principal_v1()') IS NULL
  OR (SELECT count(*) FROM atlas.work_requirements)<>0
  OR (SELECT count(*) FROM foundry.workspace_authority_registry_v1)<>0
  OR (SELECT count(*) FROM foundry.source_custody_review_cases_v1)<>0
  OR (SELECT count(*) FROM foundry.events)<>1
  OR (SELECT count(*) FROM foundry.snapshots)<>1
 THEN RAISE EXCEPTION 'The four separate native source subgates did not compose'
   USING ERRCODE='42501';
 END IF;
 RAISE NOTICE 'U1A_COMPOSED_STRUCTURAL_PASS: Work Requirement, Foundry events, private custody and signed Principal source coexist in one rolled-back transaction';
END $composition_post$;

-- BEGIN SEVEN ADDITIONAL AUTHENTIC NOEL AUTHORITY SOURCES, NO RELEASE.

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 2; atlas.persons_share_active_native_ledger_v1(uuid,uuid)
CREATE OR REPLACE FUNCTION atlas.persons_share_active_native_ledger_v1(
  p_first_person_id uuid,p_second_person_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT p_first_person_id IS NOT NULL AND p_second_person_id IS NOT NULL
 AND p_first_person_id<>p_second_person_id AND EXISTS(
  SELECT 1 FROM ledger.seats first_seat
  JOIN ledger.seats second_seat ON second_seat.ledger_id=first_seat.ledger_id
    AND second_seat.person_entity_id=p_second_person_id
    AND second_seat.seat_state='active' AND second_seat.ended_at IS NULL
  JOIN reality.entities first_person ON first_person.id=first_seat.person_entity_id
    AND first_person.entity_kind='person' AND first_person.identity_state='canonical'
  JOIN reality.entities second_person ON second_person.id=second_seat.person_entity_id
    AND second_person.entity_kind='person' AND second_person.identity_state='canonical'
  JOIN ledger.ledgers native_ledger ON native_ledger.id=first_seat.ledger_id
    AND native_ledger.ledger_state='active' AND native_ledger.retired_at IS NULL
  JOIN atlas.ledgers atlas_ledger ON atlas_ledger.id=native_ledger.id
    AND atlas_ledger.status='active'
  WHERE first_seat.person_entity_id=p_first_person_id
    AND first_seat.seat_state='active' AND first_seat.ended_at IS NULL
 );
$fn$;
REVOKE ALL ON FUNCTION atlas.persons_share_active_native_ledger_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 1; atlas.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)
CREATE OR REPLACE FUNCTION atlas.prepare_foundry_workspace_self_api_v1(
  p_request_id uuid,
  p_subject_label text,
  p_provisional_field text,
  p_custody_scope_kind text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE
  v_actor_user_id uuid := auth.uid();
  v_owner atlas.principals%rowtype;
  v_auth_user auth.users%rowtype;
  v_session_id uuid;
  v_label text := NULLIF(BTRIM(p_subject_label),'');
  v_field text := NULLIF(BTRIM(p_provisional_field),'');
  v_existing foundry.workspace_authority_registry_v1%rowtype;
  v_workspace_id text;
  v_event_id text;
  v_append jsonb;
BEGIN
  IF v_actor_user_id IS NULL THEN
    RAISE EXCEPTION 'verified Atlas sign-in required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_auth_user FROM auth.users WHERE id=v_actor_user_id;
  IF NOT FOUND OR v_auth_user.is_anonymous
     OR (v_auth_user.banned_until IS NOT NULL AND v_auth_user.banned_until>now())
  THEN
    RAISE EXCEPTION 'active non-anonymous verified Atlas authentication required' USING ERRCODE='42501';
  END IF;

  -- A genuine signed JWT must reference an active GoTrue session, and
  -- deleting that session must revoke this operation immediately even
  -- while the JWT itself has not yet expired.
  BEGIN
    v_session_id := NULLIF(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'valid GoTrue signed session required' USING ERRCODE='42501';
  END;
  IF v_session_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions sess
    WHERE sess.id=v_session_id
      AND sess.user_id=v_actor_user_id
      AND (sess.not_after IS NULL OR sess.not_after>now())
  ) THEN
    RAISE EXCEPTION 'active GoTrue session required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_owner FROM atlas.principals
    WHERE user_id=v_actor_user_id AND status='active';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active Atlas Principal required' USING ERRCODE='42501';
  END IF;

  IF p_request_id IS NULL THEN RAISE EXCEPTION 'stable request ID required'; END IF;
  IF v_label IS NULL OR length(v_label)>500 THEN
    RAISE EXCEPTION 'provisional subject label required within bounds';
  END IF;
  IF v_field IS NULL OR length(v_field)>2000 THEN
    RAISE EXCEPTION 'provisional field required within bounds';
  END IF;
  IF p_custody_scope_kind NOT IN ('verified_self','documented_external')
    OR p_custody_scope_kind IS NULL THEN
    RAISE EXCEPTION 'invalid requested source-custody classification';
  END IF;

  -- Serialize one human's same idempotent preparation request. A client
  -- can choose the request ID, never the owner Principal or workspace ID.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'foundry-prepare:'||v_owner.id::text||':'||p_request_id::text, 0
  ));

  SELECT * INTO v_existing FROM foundry.workspace_authority_registry_v1
    WHERE owner_principal_id=v_owner.id
      AND creation_request_id=p_request_id
    FOR UPDATE;
  IF FOUND THEN
    IF v_existing.provisional_subject_label IS DISTINCT FROM v_label
       OR v_existing.provisional_field IS DISTINCT FROM v_field
       OR v_existing.custody_scope_kind IS DISTINCT FROM p_custody_scope_kind THEN
      RAISE EXCEPTION 'request ID already used for different Foundry preparation';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'replayed',true,
      'workspaceId',v_existing.workspace_id,
      'custodyReviewState',v_existing.custody_review_state,
      'subjectIdentityState',v_existing.subject_identity_state,
      'canonicalAtlasMutation',false
    );
  END IF;

  v_workspace_id := 'foundry-' || gen_random_uuid()::text;
  v_event_id := 'foundry-event-' || gen_random_uuid()::text;

  INSERT INTO foundry.workspace_authority_registry_v1(
    workspace_id,creation_request_id,owner_principal_id,
    provisional_subject_label,provisional_field,
    subject_identity_state,custody_scope_kind,custody_review_state,
    custody_basis_refs,created_by_principal_id
  ) VALUES(
    v_workspace_id,p_request_id,v_owner.id,
    v_label,v_field,'unresolved',p_custody_scope_kind,
    'pending','{}'::text[],v_owner.id
  );

  -- Append and registry INSERT run in the same transaction.
  -- This is a provisional operator claim, NOT verified testimony or
  -- permission to access or act on the subject's private records.
  v_append := foundry.append_event(jsonb_build_object(
    'event_id',v_event_id,
    'workspace_id',v_workspace_id,
    'event_type','WORKSPACE_CREATED',
    'sequence',1,
    'payload',jsonb_build_object(
      'status','DISCOVERY',
      'owner_principal_id',v_owner.id,
      'provisional_subject',jsonb_build_object(
        'label',v_label,'subject_ref',NULL,'subject_kind',NULL
      ),
      'provisional_field',v_field,
      'boundary_status','UNRESOLVED',
      'custody_review_state','pending',
      'subject_identity_state','unresolved'
    ),
    'basis_refs','[]'::jsonb,
    'authority','authenticated_owner_preparation_only',
    'actor_kind','human',
    'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
                         'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));

  IF v_append->>'status' IS DISTINCT FROM 'APPENDED' THEN
    RAISE EXCEPTION 'Foundry workspace initial event was not appended';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'replayed',false,
    'workspaceId',v_workspace_id,
    'custodyReviewState','pending',
    'subjectIdentityState','unresolved',
    'canonicalAtlasMutation',false
  );
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.prepare_foundry_workspace_self_api_v1(uuid,text,text,text) TO authenticated;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 2; atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)
CREATE OR REPLACE FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(p_workspace_id text, p_request_id uuid, p_reviewer_principal_id uuid, p_claim_basis_kind text, p_source_refs text[], p_permitted_human_actions text[], p_scope_description text, p_claimed_authority_basis text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'foundry', 'auth', 'pg_temp'
AS $function$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_ws foundry.workspace_authority_registry_v1%rowtype;
        v_existing foundry.source_custody_review_cases_v1%rowtype;
        v_case_id uuid;
        v_seq bigint;
        v_source text;
BEGIN
  IF p_request_id IS NULL OR p_reviewer_principal_id IS NULL
     OR NULLIF(btrim(p_workspace_id),'') IS NULL THEN
    RAISE EXCEPTION 'Workspace, stable request, and human reviewer required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_ws FROM foundry.workspace_authority_registry_v1
   WHERE workspace_id=p_workspace_id AND owner_principal_id=v_actor
   FOR UPDATE;
  IF NOT FOUND OR v_ws.custody_review_state<>'pending'
    OR v_ws.revoked_at IS NOT NULL OR v_ws.suspended_at IS NOT NULL THEN
    RAISE EXCEPTION 'Workspace inaccessible or not in pending human custody' USING ERRCODE='42501';
  END IF;
  IF p_reviewer_principal_id=v_actor OR NOT EXISTS (
    SELECT 1 FROM atlas.principals p
    WHERE p.id=p_reviewer_principal_id AND p.status='active'
      AND p.user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A distinct active human reviewer is required' USING ERRCODE='22023';
  END IF;
  -- The writer independently verifies canonical Ledger participation;
  -- browser-selected Principal IDs and organization membership give no grant.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.principals operator
    JOIN atlas.principals reviewer ON reviewer.id=p_reviewer_principal_id
      AND reviewer.status='active'
    JOIN auth.users reviewer_user ON reviewer_user.id=reviewer.user_id
      AND reviewer_user.is_anonymous=false
      AND (reviewer_user.banned_until IS NULL OR reviewer_user.banned_until<=now())
    WHERE operator.id=v_actor AND operator.status='active'
      AND atlas.persons_share_active_native_ledger_v1(
        operator.person_id,reviewer.person_id)
  ) THEN
    RAISE EXCEPTION 'Reviewer lacks a verified canonical Person-to-Ledger connection'
      USING ERRCODE='42501';
  END IF;
  IF p_claim_basis_kind IS NULL OR p_claim_basis_kind NOT IN (
      'first_party','public_source','subject_authorization','custodian_authorization')
     OR coalesce(cardinality(p_source_refs),0) NOT BETWEEN 1 AND 12
     OR coalesce(cardinality(p_permitted_human_actions),0) NOT BETWEEN 1 AND 4
     OR p_permitted_human_actions <@ ARRAY['catalog','preserve','transcribe','analyze']::text[] IS NOT TRUE
     OR NULLIF(btrim(p_scope_description),'') IS NULL
     OR length(btrim(p_scope_description)) NOT BETWEEN 15 AND 2000
     OR NULLIF(btrim(p_claimed_authority_basis),'') IS NULL
     OR length(btrim(p_claimed_authority_basis)) NOT BETWEEN 20 AND 3000
  THEN RAISE EXCEPTION 'Precise source scope and basis required' USING ERRCODE='22023'; END IF;
  FOREACH v_source IN ARRAY p_source_refs LOOP
    IF v_source IS NULL OR length(btrim(v_source)) NOT BETWEEN 3 AND 300
    THEN RAISE EXCEPTION 'Every source reference must be bounded and nonempty' USING ERRCODE='22023'; END IF;
  END LOOP;

  -- Serializes retries and Foundry sequence against existing append_event lock.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
  SELECT * INTO v_existing FROM foundry.source_custody_review_cases_v1
    WHERE owner_principal_id=v_actor AND request_id=p_request_id FOR UPDATE;
  IF FOUND THEN
    IF v_existing.workspace_id IS DISTINCT FROM p_workspace_id
      OR v_existing.reviewer_principal_id IS DISTINCT FROM p_reviewer_principal_id
      OR v_existing.claim_basis_kind IS DISTINCT FROM p_claim_basis_kind
      OR v_existing.source_refs IS DISTINCT FROM p_source_refs
      OR v_existing.permitted_human_actions IS DISTINCT FROM p_permitted_human_actions
      OR v_existing.scope_description IS DISTINCT FROM btrim(p_scope_description)
      OR v_existing.claimed_authority_basis IS DISTINCT FROM btrim(p_claimed_authority_basis)
    THEN RAISE EXCEPTION 'Changed payload for previously used source-custody request' USING ERRCODE='22023'; END IF;
    RETURN jsonb_build_object('ok',true,'caseId',v_existing.case_id,
      'reviewState',v_existing.review_state,'replayed',true,'aiCarrierAccess',false);
  END IF;
  INSERT INTO foundry.source_custody_review_cases_v1(
    workspace_id,request_id,owner_principal_id,reviewer_principal_id,
    claim_basis_kind,source_refs,permitted_human_actions,
    scope_description,claimed_authority_basis
  ) VALUES(
    p_workspace_id,p_request_id,v_actor,p_reviewer_principal_id,
    p_claim_basis_kind,p_source_refs,p_permitted_human_actions,
    btrim(p_scope_description),btrim(p_claimed_authority_basis)
  ) RETURNING case_id INTO v_case_id;

  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=p_workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',p_workspace_id,'event_type','SOURCE_CUSTODY_REVIEW_REQUESTED',
    'sequence',v_seq,'payload',jsonb_build_object(
      'case_id',v_case_id,'scope_description',btrim(p_scope_description),
      'source_refs',to_jsonb(p_source_refs),'permitted_human_actions',to_jsonb(p_permitted_human_actions),
      'claimed_authority_basis',btrim(p_claimed_authority_basis),'claim_basis_kind',p_claim_basis_kind,'review_state','pending',
      'ai_carrier_access',false),
    'basis_refs',to_jsonb(p_source_refs),
    'authority','authenticated_owner_attestation_unreviewed',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',v_case_id,
    'reviewState','pending','replayed',false,'aiCarrierAccess',false);
END
$function$;
REVOKE ALL ON FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text) TO authenticated;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 1; atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)
CREATE OR REPLACE FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(
  p_case_id uuid,p_decision text,p_review_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_case foundry.source_custody_review_cases_v1%rowtype;
        v_seq bigint;
        v_new_state text;
BEGIN
  IF p_decision NOT IN ('approve','reject') OR p_decision IS NULL
     OR NULLIF(btrim(p_review_basis),'') IS NULL
     OR length(btrim(p_review_basis)) NOT BETWEEN 25 AND 2500 THEN
    RAISE EXCEPTION 'Human review decision and explicit independent basis required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_case FROM foundry.source_custody_review_cases_v1
    WHERE case_id=p_case_id FOR UPDATE;
  IF NOT FOUND OR v_case.reviewer_principal_id IS DISTINCT FROM v_actor THEN
    RAISE EXCEPTION 'Only the designated independent reviewer may decide' USING ERRCODE='42501';
  END IF;
  IF v_case.review_state<>'pending' THEN
    RAISE EXCEPTION 'Custody review decision already recorded' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM foundry.workspace_authority_registry_v1 w
    WHERE w.workspace_id=v_case.workspace_id AND w.owner_principal_id=v_case.owner_principal_id
      AND w.custody_review_state='pending' AND w.revoked_at IS NULL AND w.suspended_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Owner workspace no longer eligible for custody review' USING ERRCODE='42501';
  END IF;
  v_new_state:=CASE WHEN p_decision='approve' THEN 'approved' ELSE 'rejected' END;
  UPDATE foundry.source_custody_review_cases_v1 SET
    review_state=v_new_state,review_basis=btrim(p_review_basis),
    reviewed_at=now()
  WHERE case_id=p_case_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_case.workspace_id,0));
  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=v_case.workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',v_case.workspace_id,
    'event_type',CASE WHEN v_new_state='approved'
       THEN 'SOURCE_CUSTODY_HUMAN_REVIEW_APPROVED'
       ELSE 'SOURCE_CUSTODY_HUMAN_REVIEW_REJECTED' END,
    'sequence',v_seq,
    'payload',jsonb_build_object('case_id',p_case_id,'review_state',v_new_state,
      'reviewer_principal_id',v_actor,'review_basis',btrim(p_review_basis),
      'ai_carrier_access',false),
    'basis_refs',to_jsonb(v_case.source_refs),
    'authority','independent_human_source_scope_review_only',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
    'reviewState',v_new_state,'aiCarrierAccess',false,
    'workspaceCustodyState','pending');
END
$fn$;
REVOKE ALL ON FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text) TO authenticated;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 1; atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text)
CREATE OR REPLACE FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(
  p_case_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $fn$
DECLARE v_actor uuid:=atlas.foundry_current_signed_principal_v1();
        v_case foundry.source_custody_review_cases_v1%rowtype;
        v_seq bigint;
BEGIN
  IF NULLIF(btrim(p_reason),'') IS NULL OR length(btrim(p_reason)) NOT BETWEEN 15 AND 1500
  THEN RAISE EXCEPTION 'Revocation reason required' USING ERRCODE='22023'; END IF;
  SELECT * INTO v_case FROM foundry.source_custody_review_cases_v1
   WHERE case_id=p_case_id FOR UPDATE;
  IF NOT FOUND OR v_actor NOT IN (v_case.owner_principal_id,v_case.reviewer_principal_id)
  THEN RAISE EXCEPTION 'Custody case inaccessible' USING ERRCODE='42501'; END IF;
  IF v_case.review_state='revoked' THEN
    RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
      'reviewState','revoked','replayed',true,'aiCarrierAccess',false);
  END IF;
  IF v_case.review_state NOT IN ('pending','approved') THEN
    RAISE EXCEPTION 'Rejected review cannot be revoked' USING ERRCODE='22023';
  END IF;
  UPDATE foundry.source_custody_review_cases_v1
    SET review_state='revoked',revoked_at=now(),
        revoked_by_principal_id=v_actor,revoke_reason=btrim(p_reason)
    WHERE case_id=p_case_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_case.workspace_id,0));
  SELECT coalesce(max(sequence),0)+1 INTO v_seq FROM foundry.events
    WHERE workspace_id=v_case.workspace_id;
  PERFORM foundry.append_event(jsonb_build_object(
    'event_id','foundry-custody-'||gen_random_uuid()::text,
    'workspace_id',v_case.workspace_id,'event_type','SOURCE_CUSTODY_HUMAN_REVIEW_REVOKED',
    'sequence',v_seq,'payload',jsonb_build_object(
      'case_id',p_case_id,'revoked_by_principal_id',v_actor,
      'reason',btrim(p_reason),'ai_carrier_access',false),
    'basis_refs',to_jsonb(v_case.source_refs),
    'authority','human_source_scope_review_revocation',
    'actor_kind','human','recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  RETURN jsonb_build_object('ok',true,'caseId',p_case_id,
    'reviewState','revoked','replayed',false,'aiCarrierAccess',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text) TO authenticated;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 3; atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)
CREATE OR REPLACE FUNCTION atlas.capture_foundry_reality_input_self_api_v1(
  p_workspace_id text,
  p_request_id uuid,
  p_original_text text,
  p_segments jsonb DEFAULT '[]'::jsonb,
  p_source_kind text DEFAULT 'operator_statement',
  p_observed_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','auth','pg_temp'
AS $function$
DECLARE
  v_actor uuid := atlas.foundry_current_signed_principal_v1();
  v_workspace foundry.workspace_authority_registry_v1%rowtype;
  v_old foundry.events%rowtype;
  v_sequence bigint;
  v_event_id text;
  v_piece jsonb;
  v_text text;
  v_kind text;
  v_result jsonb;
  v_content text := p_original_text;
BEGIN
  IF p_workspace_id IS NULL OR length(p_workspace_id)>180
     OR p_request_id IS NULL THEN
    RAISE EXCEPTION 'Valid workspace and stable request IDs required' USING ERRCODE='22023';
  END IF;
  IF v_content IS NULL OR length(btrim(v_content))<1
     OR length(v_content)>20000 THEN
    RAISE EXCEPTION 'Original evidence must contain 1 to 20000 characters' USING ERRCODE='22023';
  END IF;
  IF p_source_kind IS NULL OR p_source_kind NOT IN
     ('operator_statement','firsthand_observation','authorized_source_reference') THEN
    RAISE EXCEPTION 'Unsupported source category' USING ERRCODE='22023';
  END IF;
  IF p_segments IS NULL OR jsonb_typeof(p_segments)<>'array'
     OR jsonb_array_length(p_segments)<1
     OR jsonb_array_length(p_segments)>24 THEN
    RAISE EXCEPTION 'Between 1 and 24 typed source segments required' USING ERRCODE='22023';
  END IF;

  -- Actual human owns this provisional workspace; mere Ledger proximity
  -- cannot expose someone else's Foundry evidence.
  SELECT * INTO v_workspace FROM foundry.workspace_authority_registry_v1 w
  WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workspace not accessible' USING ERRCODE='42501';
  END IF;
  IF v_workspace.revoked_at IS NOT NULL OR v_workspace.suspended_at IS NOT NULL
     OR v_workspace.custody_review_state IN ('revoked','suspended') THEN
    RAISE EXCEPTION 'Workspace cannot accept new evidence' USING ERRCODE='42501';
  END IF;

  FOR v_piece IN SELECT value FROM jsonb_array_elements(p_segments) LOOP
    IF jsonb_typeof(v_piece)<>'object' THEN
      RAISE EXCEPTION 'Each segment must be an object' USING ERRCODE='22023';
    END IF;
    v_text := v_piece->>'text';
    v_kind := v_piece->>'kind';
    IF v_text IS NULL OR length(btrim(v_text))<1
       OR length(v_text)>4000 OR strpos(v_content,v_text)=0 THEN
      RAISE EXCEPTION 'Each segment must quote the preserved original text' USING ERRCODE='22023';
    END IF;
    IF v_kind IS NULL OR v_kind NOT IN
       ('place','recurrence','commercial','operating_instruction',
        'work','observation','relationship','unresolved') THEN
      RAISE EXCEPTION 'Unknown segment interpretation kind' USING ERRCODE='22023';
    END IF;
    -- Unknown or future semantics are always unresolved evidence, never
    -- a user-asserted establishment or unverified foreign source grant.
    IF (v_piece - 'text' - 'kind') <> '{}'::jsonb THEN
      RAISE EXCEPTION 'Only literal segment and suggested kind are admitted' USING ERRCODE='22023';
    END IF;
  END LOOP;

  -- Serialize competing appends with foundry.append_event's own workspace
  -- lock. A browser-supplied request UUID is idempotency, not identity.
  PERFORM pg_advisory_xact_lock(hashtextextended(p_workspace_id,0));
  v_event_id := 'foundry-reality-intake-'||p_request_id::text;
  SELECT * INTO v_old FROM foundry.events WHERE event_id=v_event_id;
  IF FOUND THEN
    IF v_old.workspace_id<>p_workspace_id
      OR v_old.event_type<>'foundry_reality_input_v1'
      OR v_old.envelope->'payload'->>'original_text' IS DISTINCT FROM v_content
      OR v_old.envelope->'payload'->'segments' IS DISTINCT FROM p_segments
      OR v_old.envelope->'payload'->>'source_kind' IS DISTINCT FROM p_source_kind
      OR (v_old.envelope->'payload'->>'observed_at') IS DISTINCT FROM
          to_char(p_observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    THEN
      RAISE EXCEPTION 'Request ID already used for different evidence' USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('ok',true,'replayed',true,
      'entryId',v_old.event_id,'workspaceId',p_workspace_id,
      'sequence',v_old.sequence,'canonicalMutation',false,'aiCarrierAccess',false);
  END IF;

  SELECT coalesce(max(e.sequence),0)+1 INTO v_sequence
  FROM foundry.events e WHERE e.workspace_id=p_workspace_id;

  v_result := foundry.append_event(jsonb_build_object(
    'event_id',v_event_id,'workspace_id',p_workspace_id,
    'event_type','foundry_reality_input_v1',
    'sequence',v_sequence,
    'payload',jsonb_build_object(
      'original_text',v_content,
      'source_kind',p_source_kind,
      'observed_at',to_char(p_observed_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'segments',p_segments,
      'segment_status','unresolved',
      'subject_label',v_workspace.provisional_subject_label,
      'subject_identity_state',v_workspace.subject_identity_state,
      'author_principal_id',v_actor,
      'author_user_id',auth.uid(),
      'canonical_mutation',false
    ),
    'basis_refs','[]'::jsonb,
    'authority','signed_workspace_owner_unresolved_evidence',
    'actor_kind','human',
    'recorded_at',to_char(clock_timestamp() AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'protocol_version','0.1'
  ));
  IF v_result->>'status' <> 'APPENDED' THEN
    RAISE EXCEPTION 'Could not append source evidence' USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object('ok',true,'replayed',false,
    'entryId',v_event_id,'workspaceId',p_workspace_id,
    'sequence',v_sequence,'canonicalMutation',false,'aiCarrierAccess',false);
END;
$function$;
REVOKE ALL ON FUNCTION atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz) TO authenticated;

-- ORIGINAL MIGRATION SOURCE: verified Noel source index 4; atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)
CREATE OR REPLACE FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_disclosure_class text, p_decision_kind text, p_source_action_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_existing atlas.subject_disclosure_decision_events_v1%rowtype;
 v_created atlas.subject_disclosure_decision_events_v1%rowtype;
BEGIN
 IF p_target_person_id IS NULL OR p_subject_id IS NULL OR p_source_action_id IS NULL
   OR NOT ((
     p_subject_domain='spatial' AND p_subject_kind='growing_object'
     AND p_disclosure_class IN ('identity','condition')
   ) OR (
     p_subject_domain='event' AND p_subject_kind='occurrence'
     AND p_disclosure_class='identity'
   ))
   OR p_decision_kind NOT IN ('grant','withhold')
   OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact bounded original Subject disclosure decision required.'
     USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Connected Person or Ledger unavailable.' USING ERRCODE='42501';
 END IF;
 IF p_subject_domain='spatial' THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.growing_objects o
     JOIN atlas.farms f ON f.id=o.farm_id
     WHERE o.id=p_subject_id AND f.organization_id=p_organization_id
   ) THEN
     RAISE EXCEPTION 'Original Subject unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
 ELSE
   -- Bind the exact Event to both the governed Ledger and its one
   -- organization. An ambiguous or inactive binding is not shareable.
   IF NOT EXISTS(
     SELECT 1
     FROM ledger.occurrence_calendar_bindings cb
     JOIN local_intel.occurrences o ON o.id=cb.occurrence_id
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=o.id AND ob.organization_id=p_organization_id
       AND ob.binding_state='active'
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id
       AND lop.organization_id=p_organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   ) OR (
     SELECT count(DISTINCT lop.organization_id)
     FROM ledger.occurrence_calendar_bindings cb
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id AND lop.status='active'
       AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=cb.occurrence_id
       AND ob.organization_id=lop.organization_id
       AND ob.binding_state='active'
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   )<>1 THEN
     RAISE EXCEPTION 'Original Event unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
 END IF;
 -- Serialize all competing grants/withholds on this exact Person + Subject
 -- + field class, not just retries with the same idempotency key.
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_disclosure:'||p_ledger_id::text||':'||
  p_target_person_id::text||':'||p_subject_domain||':'||
  p_subject_kind||':'||p_subject_id::text||':'||p_disclosure_class,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_action:'||p_ledger_id::text||':'||p_source_action_id::text,0));
 SELECT * INTO v_existing
 FROM atlas.subject_disclosure_decision_events_v1
 WHERE ledger_id=p_ledger_id AND source_action_id=p_source_action_id;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.organization_id IS DISTINCT FROM p_organization_id
    OR v_existing.target_person_id IS DISTINCT FROM p_target_person_id
    OR v_existing.subject_domain IS DISTINCT FROM p_subject_domain
    OR v_existing.subject_kind IS DISTINCT FROM p_subject_kind
    OR v_existing.subject_id IS DISTINCT FROM p_subject_id
    OR v_existing.disclosure_class IS DISTINCT FROM p_disclosure_class
    OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
    OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
    RAISE EXCEPTION 'Decision action ID already used for different disclosure.'
      USING ERRCODE='23505';
   END IF;
   v_created:=v_existing;
 ELSE
   INSERT INTO atlas.subject_disclosure_decision_events_v1(
     organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
     subject_id,disclosure_class,decision_kind,source_action_id,reason,decided_by_person_id,recorded_at
   ) VALUES(
     p_organization_id,p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class,p_decision_kind,p_source_action_id,btrim(p_reason),v_owner,clock_timestamp()
   ) RETURNING * INTO v_created;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','bounded_original_subject_disclosure_v1',
   'decisionId',v_created.id,'sourceActionId',p_source_action_id,
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'targetPersonId',p_target_person_id,'subjectDomain',p_subject_domain,
   'subjectKind',p_subject_kind,'subjectId',p_subject_id,
   'disclosureClass',p_disclosure_class,'decisionKind',p_decision_kind,
   'currentlyGranted',atlas.has_current_subject_disclosure_v1(
     p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class),
   'historicalDecisionPreserved',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;

-- Compare original owner, ACL, security-definer and normalized function body.
DO $authority_contract$
DECLARE v_bad text;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.persons_share_active_native_ledger_v1(uuid,uuid)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres}' AND md5(pg_get_functiondef(p.oid))='acc5997f10542bcca9d2e576721ef23e') THEN RAISE EXCEPTION 'U1A native source mismatch: persons_share_active_native_ledger_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.prepare_foundry_workspace_self_api_v1(uuid,text,text,text)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres,authenticated=X/postgres}' AND md5(pg_get_functiondef(p.oid))='94f06408f95473db492d81b68ad84eae') THEN RAISE EXCEPTION 'U1A native source mismatch: prepare_foundry_workspace_self_api_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.request_foundry_source_custody_review_self_api_v1(text,uuid,uuid,text,text[],text[],text,text)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres,authenticated=X/postgres}' AND md5(pg_get_functiondef(p.oid))='3fecb8a04bf53eb88c4b9942faf28f60') THEN RAISE EXCEPTION 'U1A native source mismatch: request_foundry_source_custody_review_self_api_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.decide_foundry_source_custody_review_self_api_v1(uuid,text,text)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres,authenticated=X/postgres}' AND md5(pg_get_functiondef(p.oid))='b14875cb282e1bc3cf0e2b22de64607c') THEN RAISE EXCEPTION 'U1A native source mismatch: decide_foundry_source_custody_review_self_api_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.revoke_foundry_source_custody_review_self_api_v1(uuid,text)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres,authenticated=X/postgres}' AND md5(pg_get_functiondef(p.oid))='c6dd7ce2568f8eee70fa11f48f33d7e8') THEN RAISE EXCEPTION 'U1A native source mismatch: revoke_foundry_source_custody_review_self_api_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.capture_foundry_reality_input_self_api_v1(text,uuid,text,jsonb,text,timestamptz)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres,authenticated=X/postgres}' AND md5(pg_get_functiondef(p.oid))='38ca0bce0f4ca18e8ef42ebd9237ab8b') THEN RAISE EXCEPTION 'U1A native source mismatch: capture_foundry_reality_input_self_api_v1' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('atlas.governor_set_subject_disclosure_self_api_v1(uuid,uuid,uuid,text,text,uuid,text,text,uuid,text)') AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND coalesce(p.proacl::text,'NULL')='{postgres=X/postgres}' AND md5(pg_get_functiondef(p.oid))='fc074af1e7a00f47059f3d923d612ec7') THEN RAISE EXCEPTION 'U1A native source mismatch: governor_set_subject_disclosure_self_api_v1' USING ERRCODE='42501'; END IF;
 RAISE NOTICE 'U1A_SEVEN_NATIVE_AUTHORITIES_SOURCE_MATCH: all seven verified function definitions and ACLs';
END $authority_contract$;

DO $authority_negative$
DECLARE v_denied boolean;
BEGIN
 -- Unsigned superuser source calls must not be mistaken for a human JWT.
 -- Test only the independent Foundry writers with a valid negative-input
 -- shape, with all previously held source readers left unmodified.
 v_denied:=false;
 BEGIN
  PERFORM atlas.prepare_foundry_workspace_self_api_v1(
   'e5200000-0000-4000-8000-000000009990'::uuid,
   'Fictional', 'Fictional', 'verified_self');
 EXCEPTION WHEN SQLSTATE '42501' THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Unsigned workspace preparation not denied' USING ERRCODE='42501'; END IF;

 IF (SELECT count(*) FROM atlas.work_requirements)<>0
 OR (SELECT count(*) FROM foundry.workspace_authority_registry_v1)<>0
 OR (SELECT count(*) FROM foundry.source_custody_review_cases_v1)<>0
 THEN RAISE EXCEPTION 'Source-only authority composition created durable operational data' USING ERRCODE='42501'; END IF;

 RAISE NOTICE 'U1A_AUTHORITY_NEGATIVE_PASS: unsigned owner denied and no Work/Requirement/Review generated';
END $authority_negative$;

-- The original four-source evidence was a single transaction; all seven
-- new permission sources are inside the SAME transaction and must vanish.
ROLLBACK;
