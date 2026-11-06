-- Synthetic PG17 smoke behavior, NOT genuine signed Auth/REST.
-- All actors are FICTIONAL, claim values are injected SQL session variables.
-- This can prove SQL behavior only. RiverSong protected clone must separately
-- prove genuine GoTrue tokens, current seats, ledger roots, privilege/RLS,
-- revocations and original end-to-end source ownership.
\set ON_ERROR_STOP on
\set VERBOSITY verbose

INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000010'),
 ('00000000-0000-4000-8000-000000000012');
INSERT INTO reality.entities(id) VALUES
 ('00000000-0000-4000-8000-000000000011'),
 ('00000000-0000-4000-8000-000000000013');
INSERT INTO atlas.organizations(id,status)
 VALUES ('00000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.ledgers(id,organization_id,status)
 VALUES ('00000000-0000-4000-8000-000000000002',
 '00000000-0000-4000-8000-000000000001','active');
INSERT INTO ledger.ledgers(id,ledger_state,retired_at)
 VALUES ('00000000-0000-4000-8000-000000000002','active',NULL);
INSERT INTO atlas.ledger_organization_participations
 VALUES ('00000000-0000-4000-8000-000000000002',
 '00000000-0000-4000-8000-000000000001','active',
 NULL,'governing',true);
INSERT INTO atlas.farms(id,organization_id,status)
 VALUES ('00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000001','active');
INSERT INTO atlas.farm_crop_ledger_custody_v1
 VALUES ('00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000002','active',NULL);
INSERT INTO atlas._synthetic_root VALUES
 ('00000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000002',
 '00000000-0000-4000-8000-000000000010',
 '00000000-0000-4000-8000-000000000011');
INSERT INTO atlas._synthetic_actor VALUES
 ('00000000-0000-4000-8000-000000000012',
 '00000000-0000-4000-8000-000000000013');
INSERT INTO atlas._synthetic_connection VALUES
 ('00000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000002',
 '00000000-0000-4000-8000-000000000011');
INSERT INTO atlas.tasks(id,farm_id,task_series_key)
 VALUES ('00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000003','ordinary_harvest');
INSERT INTO atlas.farm_memberships(id,farm_id)
 VALUES ('00000000-0000-4000-8000-000000000023',
 '00000000-0000-4000-8000-000000000003');
INSERT INTO atlas.flower_harvest_batches(id,farm_id)
 VALUES ('00000000-0000-4000-8000-000000000020',
 '00000000-0000-4000-8000-000000000003');
INSERT INTO atlas.flower_harvest_bucket_observations(
 id,farm_id,batch_id,task_id,recorded_by_membership_id,
 created_at,bucket_band,bucket_equivalent_floor)
 VALUES (
 '00000000-0000-4000-8000-000000000021',
 '00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000020',
 '00000000-0000-4000-8000-000000000022',
 '00000000-0000-4000-8000-000000000023',
 '2026-11-06 08:00:00+00','one',1);
INSERT INTO atlas.journal_event_index(
 id,organization_id,farm_id,event_kind,visibility_scope,importance,
 task_id,source_kind,source_event,event_key,source_id,payload,
 provenance,occurred_at)
 VALUES (
 '00000000-0000-4000-8000-000000000024',
 '00000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000003',
 'owner_decision','owner','attention',NULL,
 'flower_harvest_batch','harvest_output_recorded',
 'harvest-preparation-needs-owner-direction:00000000-0000-4000-8000-000000000020',
 '00000000-0000-4000-8000-000000000020',
 '{"contractVersion":"harvest_output_owner_attention_6a_v1","sourceBucketObservationId":"00000000-0000-4000-8000-000000000021","harvestBatchId":"00000000-0000-4000-8000-000000000020","operationalOwnerReviewOnly":true,"principalEscalationQualified":false,"principalClockCandidateCreated":false}',
 '{"sourceTable":"atlas.flower_harvest_bucket_observations","sourceObservationId":"00000000-0000-4000-8000-000000000021"}',
 '2026-11-06 08:00:00+00');

INSERT INTO atlas.seed_lots(id,farm_id,status,quantity_unit)
 VALUES('00000000-0000-4000-8000-000000000030',
 '00000000-0000-4000-8000-000000000003','available','count');
INSERT INTO atlas.seed_inventory_events(
 id,organization_id,farm_id,seed_lot_id,observed_at,outcome)
 VALUES('00000000-0000-4000-8000-000000000031',
 '00000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000030',
 '2026-11-06 09:00:00+00','count_confirmed');
INSERT INTO atlas.seed_inventory_position_v1(
 seed_lot_id,farm_id,source_event_id,count_trusted,
 projected_on_hand_quantity)
 VALUES('00000000-0000-4000-8000-000000000030',
 '00000000-0000-4000-8000-000000000003',
 '00000000-0000-4000-8000-000000000031',true,5);
INSERT INTO atlas.seed_allocation_coverage_v1
 VALUES ('00000000-0000-4000-8000-000000000030',10);
INSERT INTO atlas.journal_event_index(
 id,organization_id,farm_id,event_kind,visibility_scope,importance,
 task_id,source_kind,source_event,event_key,source_id,payload,
 provenance,occurred_at)
 VALUES (
 '00000000-0000-4000-8000-000000000032',
 '00000000-0000-4000-8000-000000000001',
 '00000000-0000-4000-8000-000000000003',
 'owner_decision','owner','attention',NULL,
 'seed_lot','verified_shortfall',
 'seed-shortfall-needs-owner-decision:00000000-0000-4000-8000-000000000030',
 '00000000-0000-4000-8000-000000000030',
 '{"contractVersion":"seed_shortfall_owner_attention_6a_v1","seedInventoryEventId":"00000000-0000-4000-8000-000000000031","operationalOwnerReviewOnly":true,"principalEscalationQualified":false,"principalClockCandidateCreated":false}',
 '{"sourceTable":"atlas.seed_inventory_events","sourceEventId":"00000000-0000-4000-8000-000000000031"}',
 '2026-11-06 09:00:00+00');

SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000010',false);

-- Exact private ACL and RLS: source-only "authenticated" role must
-- not be able to read/write or directly invoke the internal functions.
DO $security$
DECLARE v boolean;
BEGIN
 IF has_table_privilege('authenticated',
   'atlas.uni_ops_governed_source_cases_v1','SELECT')
   OR has_table_privilege('service_role',
   'atlas.uni_ops_governed_case_decision_events_v1','INSERT')
   OR has_function_privilege('authenticated',
   'atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(uuid,uuid)',
   'EXECUTE')
   OR has_function_privilege('service_role',
   'atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(uuid,uuid,uuid,text,text,uuid,text)',
   'EXECUTE')
 THEN RAISE EXCEPTION 'Private API role gained unexpected universal source privileges'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class
  WHERE oid='atlas.uni_ops_governed_source_cases_v1'::regclass
    AND relrowsecurity AND relforcerowsecurity)
 OR NOT EXISTS(SELECT 1 FROM pg_class
  WHERE oid='atlas.uni_ops_farm_company_source_links_v1'::regclass
    AND relrowsecurity AND relforcerowsecurity)
 THEN RAISE EXCEPTION 'Private source RLS/FORCE RLS absent'; END IF;
 RAISE NOTICE 'PASS private ACL and forced source RLS (catalog only)';
END;
$security$;

-- FIRST deny an ungranted exact farm Subject. No blanket owner disclosure.
DO $nogrant$
BEGIN
 BEGIN
 PERFORM atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid);
 RAISE EXCEPTION 'Unpermitted Subject was admitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   RAISE NOTICE 'PASS no implicit root Subject disclosure';
 END;
END;
$nogrant$;

-- Explicit, independent native Subject information grants.
SELECT atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 '00000000-0000-4000-8000-000000000011'::uuid,
 'identity','grant','00000000-0000-4000-8000-000000000040'::uuid,
 'Synthetic explicit Harvest identity grant on this subject.');
SELECT atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 '00000000-0000-4000-8000-000000000011'::uuid,
 'condition','grant','00000000-0000-4000-8000-000000000041'::uuid,
 'Synthetic separate Harvest condition grant on this subject.');
SELECT atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 '00000000-0000-4000-8000-000000000032'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 '00000000-0000-4000-8000-000000000011'::uuid,
 'identity','grant','00000000-0000-4000-8000-000000000042'::uuid,
 'Synthetic explicit Seed identity grant on this subject.');
SELECT atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 '00000000-0000-4000-8000-000000000032'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 '00000000-0000-4000-8000-000000000011'::uuid,
 'condition','grant','00000000-0000-4000-8000-000000000043'::uuid,
 'Synthetic separate Seed condition grant on this subject.');

DO $admission$
DECLARE x jsonb;y jsonb;r jsonb;c uuid;
BEGIN
 x:=atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid);
 y:=atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid);
 IF x->>'sourceCaseId' IS DISTINCT FROM y->>'sourceCaseId'
 THEN RAISE EXCEPTION 'Exact immutable Harvest case replay created duplicates'; END IF;
 c:=(x->>'sourceCaseId')::uuid;
 IF (SELECT count(*) FROM atlas.uni_ops_governed_source_cases_v1
     WHERE source_kind='flower_harvest_batch')<>1
 THEN RAISE EXCEPTION 'Harvest source produced multiple original cases'; END IF;
 r:=atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
   c,'00000000-0000-4000-8000-000000000024'::uuid,
   '00000000-0000-4000-8000-000000000002'::uuid,
   'request_independent_work_admission',
   'Synthetic root requests source admission but no original Work.',
   '00000000-0000-4000-8000-000000000050'::uuid,NULL);
 IF r->>'newWorkCreated' <> 'false'
    OR r->>'principalClockCandidateCreated' <> 'false'
 THEN RAISE EXCEPTION 'Decision created forbidden Work or Principal Clock'; END IF;
 x:=atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
   c,'00000000-0000-4000-8000-000000000024'::uuid,
   '00000000-0000-4000-8000-000000000002'::uuid,
   'request_independent_work_admission',
   'Synthetic root requests source admission but no original Work.',
   '00000000-0000-4000-8000-000000000050'::uuid,NULL);
 IF x->>'replay' <> 'true'
 THEN RAISE EXCEPTION 'Exact signed governor action replay not idempotent'; END IF;
 RAISE NOTICE 'PASS one true immutable Harvest source case and one decision/replay';
END;
$admission$;

DO $seed$
DECLARE x jsonb;c uuid;
BEGIN
 x:=atlas.uni_ops_farm_admit_owner_attention_case_self_held_v1(
  '00000000-0000-4000-8000-000000000032'::uuid,
  '00000000-0000-4000-8000-000000000002'::uuid);
 c:=(x->>'sourceCaseId')::uuid;
 IF c IS NULL OR (SELECT source_kind FROM
    atlas.uni_ops_governed_source_cases_v1 WHERE id=c)<>'seed_lot'
 THEN RAISE EXCEPTION 'Native trusted Seed source case missing'; END IF;
 RAISE NOTICE 'PASS trusted uncovered native Seed source admitted';
END;
$seed$;

-- A later replenishment may make the old Seed event insufficient for a
-- NEW decision; the immutable old case is kept as historical evidence.
UPDATE atlas.seed_inventory_position_v1
 SET projected_on_hand_quantity=12
 WHERE seed_lot_id='00000000-0000-4000-8000-000000000030';
DO $stale_seed$
DECLARE c uuid;
BEGIN
 SELECT id INTO c FROM atlas.uni_ops_governed_source_cases_v1
 WHERE source_kind='seed_lot';
 BEGIN
 PERFORM atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
  c,'00000000-0000-4000-8000-000000000032'::uuid,
  '00000000-0000-4000-8000-000000000002'::uuid,
  'request_independent_work_admission',
  'This old seed gap has been covered and should be denied.',
  '00000000-0000-4000-8000-000000000052'::uuid,NULL);
 RAISE EXCEPTION 'Stale Seed count qualified new decision';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   RAISE NOTICE 'PASS resolved seed shortage denied current governor choice';
 END;
END;
$stale_seed$;

-- Separate, later signed WITHHOLD must revoke the appropriate class.
SELECT atlas.uni_ops_governor_decide_farm_attention_disclosure_held_v1(
 '00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 '00000000-0000-4000-8000-000000000011'::uuid,
 'condition','withhold','00000000-0000-4000-8000-000000000044'::uuid,
 'Synthetic explicit Harvest condition disclosure withdrawal.');
DO $revoked$
DECLARE c uuid;
BEGIN
 SELECT id INTO c FROM atlas.uni_ops_governed_source_cases_v1
 WHERE source_kind='flower_harvest_batch';
 BEGIN
 PERFORM atlas.uni_ops_farm_governor_decide_current_company_case_held_v1(
 c,'00000000-0000-4000-8000-000000000024'::uuid,
 '00000000-0000-4000-8000-000000000002'::uuid,
 'hold_for_more_source',
 'This subject is currently withheld and must be denied.',
 '00000000-0000-4000-8000-000000000053'::uuid,
 (SELECT id FROM atlas.uni_ops_governed_case_decision_events_v1
  WHERE case_id=c ORDER BY decided_at DESC,id DESC LIMIT 1));
 RAISE EXCEPTION 'Revoked condition disclosure still admitted governor choice';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   RAISE NOTICE 'PASS revoked exact Subject condition denies current choice';
 END;
END;
$revoked$;

-- Native and Company Ledger share an ID only because the legitimate
-- source explicitly bridges them. A paused NATIVE Ledger denies admission
-- even if the Company record and synthetic root appear active.
UPDATE ledger.ledgers SET ledger_state='paused'
WHERE id='00000000-0000-4000-8000-000000000002';
DO $paused_native$
BEGIN
 BEGIN
  PERFORM atlas.uni_ops_farm_current_attention_attestation_self_held_v1(
   '00000000-0000-4000-8000-000000000024'::uuid,
   '00000000-0000-4000-8000-000000000002'::uuid);
  RAISE EXCEPTION 'Paused native Ledger incorrectly admitted';
 EXCEPTION WHEN SQLSTATE '42501' THEN
  RAISE NOTICE 'PASS native Ledger pause denies farm to Company source authority';
 END;
END;
$paused_native$;
UPDATE ledger.ledgers SET ledger_state='active'
WHERE id='00000000-0000-4000-8000-000000000002';

-- No one except a legitimate current governor; wrong synthetic identity
-- cannot use the exact trusted source case. NOT genuine GoTrue proof.
SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000012',false);
DO $outsider$
DECLARE c uuid;
BEGIN
 SELECT id INTO c FROM atlas.uni_ops_governed_source_cases_v1
 WHERE source_kind='flower_harvest_batch';
 BEGIN
 PERFORM atlas.uni_ops_company_governor_decide_source_case_self_held_v1(
 c,'hold_for_more_source',
 'Outsider must not govern this company case.',
 '00000000-0000-4000-8000-000000000054'::uuid,NULL);
 RAISE EXCEPTION 'Wrong synthetic actor became governing root';
 EXCEPTION WHEN SQLSTATE '42501' THEN
   RAISE NOTICE 'PASS wrong synthetic actor cannot govern';
 END;
END;
$outsider$;

DO $summary$
BEGIN
 IF (SELECT count(*) FROM atlas.uni_ops_governed_source_cases_v1)<>2
    OR (SELECT count(*) FROM atlas.uni_ops_governed_case_decision_events_v1)<>1
 THEN RAISE EXCEPTION 'Synthetic case or decision totals changed unexpectedly'; END IF;
 RAISE NOTICE 'PASS: two original source cases, one immutable Company decision; no worker/Work/Result/Clock tables in synthetic test';
END;
$summary$;
