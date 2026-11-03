-- U1A custody table structural-only native source probe (NOT migration).
-- Original unmodified source blocks: Noel
-- supabase/migrations/20261024010000_shared_foundry_connected_workspace_gate1_signed_v1.sql
-- Current Noel normalized table catalog MD5 (2026-11-03):
-- 784f26bdcbcf77ee5794bcab53848220
-- No Person/Principal, source Review Case, Work or Rulebook records generated.
BEGIN;
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
DECLARE v_actual text;v_tables integer;
BEGIN
 WITH c AS (
 SELECT jsonb_build_object(
 'tables',(SELECT jsonb_agg(jsonb_build_object(
 'name',c.relname,'owner',pg_get_userbyid(c.relowner),'rls',c.relrowsecurity,'forceRls',c.relforcerowsecurity,'acl',coalesce(c.relacl::text,'NULL'),
 'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'required',a.attnotnull,'default',pg_get_expr(ad.adbin,ad.adrelid)) ORDER BY a.attnum) FROM pg_attribute a LEFT JOIN pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
 'constraints',(SELECT jsonb_agg(jsonb_build_object('name',con.conname,'def',pg_get_constraintdef(con.oid,true)) ORDER BY con.conname) FROM pg_constraint con WHERE con.conrelid=c.oid),
 'indexes',(SELECT jsonb_agg(pg_get_indexdef(i.indexrelid) ORDER BY pg_get_indexdef(i.indexrelid)) FROM pg_index i WHERE i.indrelid=c.oid),
 'triggers',(SELECT jsonb_agg(pg_get_triggerdef(t.oid) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal)
 ) ORDER BY c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='foundry' AND c.relname IN ('workspace_authority_registry_v1','source_custody_review_cases_v1') AND c.relkind='r')
 ) AS j
 ) SELECT md5(j::text),jsonb_array_length(j->'tables') INTO v_actual,v_tables FROM c;
 IF v_tables<>2 OR v_actual IS DISTINCT FROM '784f26bdcbcf77ee5794bcab53848220' THEN
  RAISE EXCEPTION 'Actual current Noel Foundry custody table contract differs from original source'
   USING ERRCODE='42501';
 END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='foundry.workspace_authority_registry_v1'::regclass)
   OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='foundry.source_custody_review_cases_v1'::regclass)
 THEN RAISE EXCEPTION 'Noel private Foundry custody storage must retain RLS';
 END IF;
 RAISE NOTICE 'FOUNDRY_CUSTODY_TABLES_STRUCTURAL_PASS: exact private native review registry and ACL/constraint fingerprint';
END $contract$;
ROLLBACK;
