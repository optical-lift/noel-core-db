-- U1A: STRUCTURAL PROOF ONLY. This is NOT a migration or authorization.
-- Provenance: live Noel read-only pg_catalog, 2026-11-03.
-- Canonical full table contract md5: 6bad563a25890c2c6315305b1b61a8d5
-- Never apply to production, persistent dev, or the RiverSong 55432 source.
-- Runner must provision a separate PG17 cluster and restore source schema.
BEGIN;
SET LOCAL statement_timeout = '60s';
DO $preflight$
BEGIN
 IF current_database() IS DISTINCT FROM 'atlas_work_disposable'
    OR inet_server_addr() IS DISTINCT FROM inet '127.0.0.1'
    OR current_setting('port')='55432'
    OR current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
    OR to_regclass('atlas.work_requirements') IS NOT NULL
    OR to_regclass('atlas.organization_units') IS NULL
    OR NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid='atlas.organization_units'::regclass
                     AND contype IN ('p','u')
                     AND conkey=ARRAY[
                       (SELECT attnum FROM pg_attribute WHERE attrelid='atlas.organization_units'::regclass AND attname='organization_id'),
                       (SELECT attnum FROM pg_attribute WHERE attrelid='atlas.organization_units'::regclass AND attname='id')
                     ]::smallint[])
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
ROLLBACK;
