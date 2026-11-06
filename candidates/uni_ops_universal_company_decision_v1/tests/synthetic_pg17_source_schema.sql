-- TEST-ONLY synthetic PostgreSQL 17 schema for the six held sources.
-- NO production data, no real GoTrue, NO migration, no public API transport.
-- This is NOT a proxy for production-shaped signed clone validation.
\set ON_ERROR_STOP on
CREATE SCHEMA atlas;
CREATE SCHEMA auth;
CREATE SCHEMA reality;
CREATE SCHEMA ledger;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE TABLE reality.entities(id uuid PRIMARY KEY);
CREATE TABLE atlas.organizations(id uuid PRIMARY KEY,status text NOT NULL);
CREATE TABLE atlas.ledgers(id uuid PRIMARY KEY,organization_id uuid,status text NOT NULL);
CREATE TABLE ledger.ledgers(id uuid PRIMARY KEY,ledger_state text NOT NULL,retired_at timestamptz);
CREATE TABLE atlas.ledger_organization_participations(
 ledger_id uuid NOT NULL,organization_id uuid NOT NULL,status text,
 ended_at timestamptz,participation_kind text,is_compatibility_primary boolean
);
CREATE TABLE atlas.farms(id uuid PRIMARY KEY,organization_id uuid,status text);
CREATE TABLE atlas.farm_crop_ledger_custody_v1(
 farm_id uuid,ledger_id uuid,custody_state text,ended_at timestamptz
);
CREATE TABLE atlas.tasks(id uuid PRIMARY KEY,farm_id uuid,task_series_key text);
CREATE TABLE atlas.farm_memberships(id uuid PRIMARY KEY,farm_id uuid);
CREATE TABLE atlas.flower_harvest_batches(id uuid PRIMARY KEY,farm_id uuid);
CREATE TABLE atlas.flower_harvest_bucket_observations(
 id uuid PRIMARY KEY,farm_id uuid,batch_id uuid,task_id uuid,
 recorded_by_membership_id uuid,created_at timestamptz,
 bucket_band text,bucket_equivalent_floor numeric
);
CREATE TABLE atlas.flower_preparation_directives(
 id uuid PRIMARY KEY,farm_id uuid,harvest_batch_id uuid
);
CREATE TABLE atlas.seed_lots(
 id uuid PRIMARY KEY,farm_id uuid,status text,quantity_unit text
);
CREATE TABLE atlas.seed_inventory_events(
 id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,
 seed_lot_id uuid,observed_at timestamptz,outcome text
);
CREATE TABLE atlas.seed_inventory_position_v1(
 seed_lot_id uuid,farm_id uuid,source_event_id uuid,count_trusted boolean,
 projected_on_hand_quantity numeric
);
CREATE TABLE atlas.seed_allocation_coverage_v1(
 seed_lot_id uuid,outstanding_quantity numeric
);
CREATE TABLE atlas.journal_event_index(
 id uuid PRIMARY KEY,organization_id uuid,farm_id uuid,
 event_kind text,visibility_scope text,importance text,
 task_id uuid,source_kind text,source_event text,event_key text,
 source_id uuid,payload jsonb,provenance jsonb,occurred_at timestamptz
);
CREATE TABLE atlas.subject_disclosure_decision_events_v1(
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 organization_id uuid,ledger_id uuid,target_person_id uuid,
 subject_domain text,subject_kind text,subject_id uuid,
 disclosure_class text,decision_kind text,source_action_id uuid,
 reason text,decided_by_person_id uuid,recorded_at timestamptz,
 UNIQUE(ledger_id,source_action_id),
 CONSTRAINT subject_disclosure_supported_subject_v1 CHECK (
 (((subject_domain = 'spatial'::text) AND (subject_kind = 'growing_object'::text) AND
  (disclosure_class = ANY (ARRAY['identity'::text,'condition'::text])))
  OR ((subject_domain = 'event'::text) AND (subject_kind = 'occurrence'::text) AND
  (disclosure_class = 'identity'::text))
  OR ((subject_domain = 'spatial'::text) AND (subject_kind = 'farm'::text) AND
  (disclosure_class = 'current_inventory'::text)))
 )
);

-- Explicitly fake ledger/person authority, confined to this disposable
-- contract fixture; the protected full clone must use real signed sources.
CREATE TABLE atlas._synthetic_root(
 organization_id uuid,ledger_id uuid,user_id uuid,person_id uuid
);
CREATE TABLE atlas._synthetic_connection(
 organization_id uuid,ledger_id uuid,person_id uuid
);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
 AS $$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
CREATE TABLE atlas._synthetic_actor(user_id uuid,person_id uuid);
CREATE FUNCTION atlas.current_person_id_v1() RETURNS uuid
 LANGUAGE sql STABLE AS $$
  SELECT r.person_id FROM atlas._synthetic_root r WHERE r.user_id=auth.uid()
  UNION ALL
  SELECT c.person_id FROM atlas._synthetic_actor c WHERE c.user_id=auth.uid()
  LIMIT 1
 $$;
CREATE FUNCTION atlas.company_work_native_ledger_owner_self_v1(
 p_organization_id uuid,p_ledger_id uuid
) RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT r.person_id FROM atlas._synthetic_root r
 WHERE r.organization_id=p_organization_id
   AND r.ledger_id=p_ledger_id
   AND r.user_id=auth.uid()
 LIMIT 1
 $$;
CREATE FUNCTION atlas.person_has_native_ledger_connection_v1(
 p_organization_id uuid,p_ledger_id uuid,p_person_id uuid
) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT EXISTS(SELECT 1 FROM atlas._synthetic_connection x
 WHERE x.organization_id=p_organization_id
  AND x.ledger_id=p_ledger_id AND x.person_id=p_person_id)
 $$;
CREATE FUNCTION atlas.has_current_subject_disclosure_v1(
 p_ledger_id uuid,p_person_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid,
 p_disclosure_class text
) RETURNS boolean LANGUAGE sql STABLE AS $$
 SELECT COALESCE((
   SELECT e.decision_kind='grant'
   FROM atlas.subject_disclosure_decision_events_v1 e
   WHERE e.ledger_id=p_ledger_id AND e.target_person_id=p_person_id
     AND e.subject_domain=p_subject_domain
     AND e.subject_kind=p_subject_kind AND e.subject_id=p_subject_id
     AND e.disclosure_class=p_disclosure_class
   ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
 ),false)
 $$;
CREATE FUNCTION atlas.block_subject_disclosure_mutation_v1()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Subject disclosure event is immutable'
  USING ERRCODE='42501'; END;
$$;
CREATE TRIGGER subject_disclosure_no_rewrite
BEFORE UPDATE OR DELETE ON atlas.subject_disclosure_decision_events_v1
FOR EACH ROW EXECUTE FUNCTION atlas.block_subject_disclosure_mutation_v1();

-- The pin in candidate 06 MUST match live pg_get_constraintdef, or
-- the test fails closed and reveals fixture/production contract drift.
DO $pin$
DECLARE v text;
BEGIN
 SELECT md5(pg_get_constraintdef(c.oid)) INTO v
 FROM pg_constraint c JOIN pg_class t ON t.oid=c.conrelid
 WHERE t.oid='atlas.subject_disclosure_decision_events_v1'::regclass
  AND c.conname='subject_disclosure_supported_subject_v1';
 IF v<>'d485d918b633c4ba51ea013f99e12e53'
 THEN RAISE EXCEPTION 'Original Subject CHECK fixture mismatch %',v; END IF;
END;
$pin$;
