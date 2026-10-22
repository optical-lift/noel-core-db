-- Protected production-schema clone ONLY. Synthetic actors and history.
DO $structural$
DECLARE v_source oid;v_api oid;
BEGIN
 v_source:=to_regprocedure('atlas.set_ledger_occurrence_schedule_self_api_v1(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)');
 v_api:=to_regprocedure('public.set_ledger_occurrence_schedule_self_api_v1(uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)');
 IF v_source IS NULL OR v_api IS NULL
   OR NOT EXISTS (SELECT 1 FROM pg_proc WHERE oid=v_source AND prosecdef)
   OR EXISTS (SELECT 1 FROM pg_proc WHERE oid=v_api AND prosecdef)
   OR has_function_privilege('anon',v_source,'EXECUTE')
   OR has_function_privilege('anon',v_api,'EXECUTE')
   OR NOT has_function_privilege('authenticated',v_api,'EXECUTE')
   OR to_regclass('atlas.calendar_events') IS NOT NULL
 THEN RAISE EXCEPTION 'Writer must preserve exact privileged source/private ACL and no Calendar duplicate'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM pg_trigger t
  WHERE t.tgrelid='atlas.community_events'::regclass
    AND t.tgname='aa_block_unowned_operational_event_retime_v1'
    AND NOT t.tgisinternal AND t.tgenabled='O'
 ) THEN RAISE EXCEPTION 'Parallel operational schedule writer remains unguarded'; END IF;
END
$structural$;

-- As database owner, directly invoking the old parallel source writer must
-- also be blocked for operator-provided Events; not merely blocked by client ACL.
BEGIN;
DO $legacy_guard$
DECLARE v_denied boolean := false;
BEGIN
 BEGIN
   UPDATE atlas.community_events ce SET start_local_time='17:00'
   WHERE ce.id='f5210000-0000-4000-8000-000000000301'::uuid;
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN
   RAISE EXCEPTION 'Privileged legacy operational path produced another calendar schedule';
 END IF;
END
$legacy_guard$;
ROLLBACK;

BEGIN;
SET LOCAL ROLE authenticated;
DO $proof$
DECLARE
 v_org constant uuid := 'f5210000-0000-4000-8000-000000000010';
 v_ledger constant uuid := 'f5210000-0000-4000-8000-000000000014';
 v_occ_id constant uuid := 'f5210000-0000-4000-8000-000000000101';
 v_other constant uuid := 'f5210000-0000-4000-8000-000000000102';
 v_root constant uuid := 'f5210000-0000-4000-8000-000000000403';
 v_member constant uuid := 'f5210000-0000-4000-8000-000000000401';
 v_outsider constant uuid := 'f5210000-0000-4000-8000-000000000402';
 v_occ_before local_intel.occurrences%rowtype;
 v_occ_after local_intel.occurrences%rowtype;
 v_overlay atlas.community_events%rowtype;
 v_result jsonb;
 v_receipt uuid;
 v_expected timestamptz;
 v_denied boolean;
 v_claimid uuid;
 v_claimstart timestamptz;
 v_claimend timestamptz;
 v_bad boolean;
BEGIN
 SELECT * INTO v_occ_before FROM local_intel.occurrences WHERE id=v_occ_id;
 SELECT * INTO v_overlay FROM atlas.community_events
   WHERE id='f5210000-0000-4000-8000-000000000301'::uuid;
 SELECT id,starts_at,ends_at INTO v_claimid,v_claimstart,v_claimend
  FROM ledger.occurrence_resource_claims WHERE occurrence_id=v_occ_id;

 PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_member,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000411')::text,true);
 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 21:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'Confirmed owner public-event time is 4 to 8 PM','synthetic_member_denied_action');
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Ordinary connected Person retimed the Event'; END IF;

 PERFORM set_config('request.jwt.claim.sub',v_outsider::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_outsider,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000412',
   'user_metadata',jsonb_build_object('is_owner',true))::text,true);
 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 21:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'Confirmed owner public-event time is 4 to 8 PM','synthetic_outsider_denied');
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Outsider with forged metadata retimed the Event'; END IF;

 PERFORM set_config('request.jwt.claim.sub',v_root::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_root,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000413')::text,true);

 -- Direct legacy change cannot create an alternative Calendar schedule.
 v_bad:=false;
 BEGIN
  UPDATE atlas.community_events SET start_local_time='17:00'
   WHERE id=v_overlay.id;
 EXCEPTION WHEN insufficient_privilege THEN v_bad:=true;
 END;
 IF NOT v_bad THEN RAISE EXCEPTION 'Legacy independent operational retime accepted'; END IF;

 v_result:=public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 21:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'The public Event truly begins at 4 PM, not 6 PM.',
   'synthetic_root_single_event_repair');
 v_receipt:=(v_result->>'receiptId')::uuid;
 IF v_result->>'ok'<>'true'
   OR v_result->>'idempotentReplay'<>'false'
   OR v_result->>'occurrenceId'<>v_occ_id::text THEN
   RAISE EXCEPTION 'Root signed Event correction failed or invented subject: %',v_result;
 END IF;
 SELECT * INTO v_occ_after FROM local_intel.occurrences WHERE id=v_occ_id;
 IF v_occ_after.start_at<>'2030-10-30 21:00+00'::timestamptz
   OR v_occ_after.end_at IS DISTINCT FROM v_occ_before.end_at
   OR v_occ_after.metadata->>'publicEventLocalTime'<>'4:00 PM–8:00 PM'
   OR v_occ_after.metadata->>'keepMe'<>'original'
   OR v_occ_after.metadata->>'candyStandard'<>'dye-free'
   OR v_occ_after.title IS DISTINCT FROM v_occ_before.title
   OR v_occ_after.status IS DISTINCT FROM v_occ_before.status
   OR v_occ_after.stable_key IS DISTINCT FROM v_occ_before.stable_key THEN
    RAISE EXCEPTION 'Canonical Event history or rich metadata lost';
 END IF;

 IF EXISTS(SELECT 1 FROM atlas.community_events ce WHERE ce.id=v_overlay.id
   AND (ce.start_local_time IS DISTINCT FROM '16:00'::time
     OR ce.end_local_time IS DISTINCT FROM '20:00'::time
     OR ce.title IS DISTINCT FROM v_overlay.title)) THEN
  RAISE EXCEPTION 'Operational carrier was replaced or retimed';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM ledger.occurrence_resource_claims c
   WHERE c.id=v_claimid AND c.starts_at=v_claimstart
     AND c.ends_at=v_claimend AND c.claim_state='confirmed') THEN
  RAISE EXCEPTION 'Existing site reservation changed';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM atlas.evidence_records e
   WHERE e.id=v_receipt AND e.actor_user_id=v_root
     AND e.value#>>'{canonicalBefore,publicEventLocalTime}'='6:00 PM–8:00 PM'
     AND e.value#>>'{canonicalAfter,publicEventLocalTime}'='4:00 PM–8:00 PM'
     AND e.value#>>'{resourceClaimCountPreserved}'='1') THEN
  RAISE EXCEPTION 'Immutable prior/new time receipt absent';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM local_intel.occurrences
    WHERE id=v_other AND start_at='2030-10-30 13:00+00'::timestamptz) THEN
  RAISE EXCEPTION 'Distinct same-day Event was merged';
 END IF;

 -- Replay must not create a second receipt and must tolerate old versions.
 v_result:=public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 21:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'The public Event truly begins at 4 PM, not 6 PM.',
   'synthetic_root_single_event_repair');
 IF v_result->>'idempotentReplay'<>'true'
   OR (v_result->>'receiptId')::uuid<>v_receipt THEN
   RAISE EXCEPTION 'Retry created another Event action';
 END IF;
 IF (SELECT count(*) FROM atlas.evidence_records
   WHERE source_kind='ledger_occurrence_schedule_decision_v1'
     AND source_key='synthetic_root_single_event_repair')<>1 THEN
   RAISE EXCEPTION 'Duplicate schedule decision';
 END IF;

 v_bad:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 22:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'Stale source versions must fail without overwriting.',
   'synthetic_stale_source_version');
 EXCEPTION WHEN serialization_failure THEN v_bad:=true;
 END;
 IF NOT v_bad THEN RAISE EXCEPTION 'Stale source update accepted'; END IF;

 v_bad:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
   v_org,v_ledger,v_occ_id,
   '2030-10-30 22:00+00','2030-10-31 01:00+00',
   v_occ_before.updated_at,v_overlay.updated_at,
   'Reused action ID must not change its original meaning.',
   'synthetic_root_single_event_repair');
 EXCEPTION WHEN unique_violation THEN v_bad:=true;
 END;
 IF NOT v_bad THEN RAISE EXCEPTION 'Idempotency key reused with changed schedule'; END IF;
END
$proof$;
ROLLBACK;

SELECT jsonb_build_object(
 'contractVersion','atlas_one_event_schedule_writer_clone_proof_v1',
 'syntheticRootAndMemberAuthorization',true,
 'legacyIndependentWriterDenied',true,
 'canonicalRichMetadataPreserved',true,
 'sourceVersionCASAndIdempotency',true,
 'oneSameDayDistinctEventRemains',true,
 'noProductionSourceMutation',true
) AS proof_receipt;