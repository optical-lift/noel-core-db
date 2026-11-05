-- UNI-OPS-01 / held source-backed SCHEMA-ONLY reconstruction for disposable P1.
-- 2026-11-05 READ-ONLY Noel live pg_catalog audit: atlas.goals is a current
-- existing table. Main and P1 SQL checkout contain no CREATE TABLE atlas.goals.
-- RiverSong's protected schema clone omitted it, while the real existing
-- AFTER weed_cards change trigger calls goal_source_changed_v1(), which reads
-- this table. Do NOT disable that real trigger or invent a result.
-- This staged table reproduces the EXACT observed live columns, defaults,
-- PK/FKs/check, btree indexes, RLS enabled, zero client ACL and no policies.
-- No live rows copied, no historical goal fabricated, no production mutation.
DO $source_dependencies$
BEGIN
 IF to_regclass('atlas.goals') IS NOT NULL THEN
    RAISE EXCEPTION 'STOP: live goals table already exists in scratch schema';
 END IF;
 IF to_regclass('atlas.farms') IS NULL OR
    to_regclass('atlas.projects') IS NULL THEN
    RAISE EXCEPTION 'STOP: source-governed existing farms/projects references unavailable';
 END IF;
END;$source_dependencies$;

CREATE TABLE atlas.goals (
 id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
 farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE CASCADE,
 project_id uuid REFERENCES atlas.projects(id) ON DELETE SET NULL,
 stable_key text NOT NULL,
 title text NOT NULL,
 summary text NOT NULL DEFAULT ''::text,
 goal_kind text NOT NULL DEFAULT 'deliverable'::text,
 visibility_scope text NOT NULL DEFAULT 'farm_shared'::text,
 priority integer NOT NULL DEFAULT 0,
 near_threshold integer NOT NULL DEFAULT 1
   CONSTRAINT goals_near_threshold_check CHECK (near_threshold >= 0),
 state_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
 release_config jsonb NOT NULL DEFAULT '{}'::jsonb,
 active boolean NOT NULL DEFAULT true,
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT goals_farm_id_stable_key_key UNIQUE (farm_id,stable_key)
);
CREATE INDEX goals_farm_active_idx ON atlas.goals USING btree
 (farm_id,active,priority DESC);
ALTER TABLE atlas.goals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.goals FROM PUBLIC,anon,authenticated,service_role;

DO $verified$
BEGIN
 IF (SELECT count(*) FROM atlas.goals)<>0 OR
    (SELECT count(*) FROM pg_attribute a
     WHERE a.attrelid='atlas.goals'::regclass
       AND a.attnum>0 AND NOT a.attisdropped)<>16 OR
    (SELECT count(*) FROM pg_constraint c
     WHERE c.conrelid='atlas.goals'::regclass)<>5 OR
    NOT (SELECT c.relrowsecurity FROM pg_class c
         WHERE c.oid='atlas.goals'::regclass) OR
    pg_catalog.has_table_privilege('authenticated','atlas.goals','SELECT') OR
    pg_catalog.has_table_privilege('anon','atlas.goals','SELECT') THEN
   RAISE EXCEPTION 'Live goal schema-only proof drift; do not use fixture';
 END IF;
 RAISE NOTICE 'PASS observed live goals metadata reconstructed only in disposable DB, with no rows/permissions';
END;$verified$;
