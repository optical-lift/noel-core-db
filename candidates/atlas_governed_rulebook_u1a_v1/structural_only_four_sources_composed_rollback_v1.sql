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
ROLLBACK;
