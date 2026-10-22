-- Protected clone ONLY. All changes occur in a disposable transaction.
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
 THEN RAISE EXCEPTION 'Exact guarded writer privilege and no duplicate Calendar required'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger t
   WHERE t.tgrelid='atlas.community_events'::regclass
     AND t.tgname='aa_block_unowned_operational_event_retime_v1'
     AND NOT t.tgisinternal AND t.tgenabled='O')
 THEN RAISE EXCEPTION 'Alternate operator Event schedule writer not guarded'; END IF;
END
$structural$;

-- Privileged legacy direct UPDATE (with no signed Person) must fail too.
BEGIN;
DO $legacy_guard$
DECLARE v_denied boolean := false;
BEGIN
 BEGIN
   UPDATE atlas.community_events SET start_local_time='17:00'
   WHERE id='f5210000-0000-4000-8000-000000000301'::uuid;
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN
   RAISE EXCEPTION 'Legacy independent Event schedule mutation was permitted';
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
 v_occ constant uuid := 'f5210000-0000-4000-8000-000000000101';
 v_root constant uuid := 'f5210000-0000-4000-8000-000000000403';
 v_member constant uuid := 'f5210000-0000-4000-8000-000000000401';
 v_outsider constant uuid := 'f5210000-0000-4000-8000-000000000402';
 v_source jsonb;
 v_result jsonb;
 v_replay jsonb;
 v_canonical_version timestamptz;
 v_operational_version timestamptz;
 v_receipt uuid;
 v_denied boolean;
BEGIN
 PERFORM set_config('request.jwt.claim.sub',v_member::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_member,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000411')::text,true);
 v_source:=public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
    v_org,v_ledger,v_occ,NULL,NULL);
 v_canonical_version:=(v_source#>>'{canonicalSource,updatedAt}')::timestamptz;
 v_operational_version:=(v_source#>>'{operationalSource,updatedAt}')::timestamptz;
 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 21:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'Public Event has been confirmed as 4 through 8 PM.',
    'synthetic-member-denied-01');
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Ordinary Ledger Person changed Event time'; END IF;

 PERFORM set_config('request.jwt.claim.sub',v_outsider::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_outsider,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000412',
   'user_metadata',jsonb_build_object('is_owner',true))::text,true);
 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 21:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'Public Event has been confirmed as 4 through 8 PM.',
    'synthetic-outsider-denied-01');
 EXCEPTION WHEN insufficient_privilege THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Forged outsider changed Event time'; END IF;

 PERFORM set_config('request.jwt.claim.sub',v_root::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object(
   'sub',v_root,'role','authenticated',
   'session_id','f5210000-0000-4000-8000-000000000413')::text,true);
 v_result:=public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 21:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'The public Event begins at 4 PM and ends at 8 PM.',
    'synthetic-root-single-event-01');
 v_receipt:=(v_result->>'receiptId')::uuid;
 IF v_result->>'ok'<>'true'
    OR v_result->>'idempotentReplay'<>'false'
    OR v_result->>'occurrenceId'<>v_occ::text
    OR v_result->>'resourceClaimsUntouched'<>'true' THEN
   RAISE EXCEPTION 'Root command failed source-owned correction: %',v_result;
 END IF;

 v_replay:=public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 21:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'The public Event begins at 4 PM and ends at 8 PM.',
    'synthetic-root-single-event-01');
 IF v_replay->>'idempotentReplay'<>'true'
    OR (v_replay->>'receiptId')::uuid<>v_receipt THEN
   RAISE EXCEPTION 'Idempotent replay fabricated another correction';
 END IF;

 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 22:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'Second edit must be denied due to source version race.',
    'synthetic-root-stale-source-02');
 EXCEPTION WHEN serialization_failure THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Stale versions overwrote corrected source'; END IF;

 v_denied:=false;
 BEGIN
  PERFORM public.set_ledger_occurrence_schedule_self_api_v1(
    v_org,v_ledger,v_occ,
    '2030-10-30 22:00+00','2030-10-31 01:00+00',
    v_canonical_version,v_operational_version,
    'Reused action key with different target must be rejected.',
    'synthetic-root-single-event-01');
 EXCEPTION WHEN unique_violation THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Same action key accepted changed meaning'; END IF;
END
$proof$;

RESET ROLE;
DO $inspect_source$
DECLARE
 v_occ local_intel.occurrences%rowtype;
 v_operational atlas.community_events%rowtype;
BEGIN
 SELECT * INTO v_occ FROM local_intel.occurrences
  WHERE id='f5210000-0000-4000-8000-000000000101'::uuid;
 SELECT * INTO v_operational FROM atlas.community_events
  WHERE id='f5210000-0000-4000-8000-000000000301'::uuid;
 IF v_occ.start_at<>'2030-10-30 21:00+00'::timestamptz
   OR v_occ.end_at IS DISTINCT FROM '2030-10-31 01:00+00'::timestamptz
   OR v_occ.metadata->>'publicEventLocalTime'<>'4:00 PM–8:00 PM'
   OR v_occ.metadata->>'keepMe'<>'original'
   OR v_occ.metadata->>'candyStandard'<>'dye-free'
   OR v_occ.title<>'Synthetic Harvest Gathering'
   OR v_occ.stable_key<>'atlas-date-proof-occurrence-a-f521'
   OR v_operational.title<>'Synthetic Bonfire Evening'
   OR v_operational.start_local_time<>'16:00'::time
   OR v_operational.end_local_time<>'20:00'::time THEN
    RAISE EXCEPTION 'Single Event schedule correction lost original canonical/program metadata';
 END IF;
 IF (SELECT count(*) FROM ledger.occurrence_resource_claims c
    WHERE c.occurrence_id=v_occ.id AND c.claim_state='confirmed'
      AND c.starts_at='2030-10-30 21:00+00'::timestamptz
      AND c.ends_at='2030-10-31 01:00+00'::timestamptz)<>1 THEN
    RAISE EXCEPTION 'Confirmed site resource claim was changed or dropped';
 END IF;
 IF (SELECT count(*) FROM atlas.evidence_records e
    WHERE e.source_kind='ledger_occurrence_schedule_decision_v1'
      AND e.source_key='synthetic-root-single-event-01'
      AND e.value#>>'{canonicalBefore,publicEventLocalTime}'='6:00 PM–8:00 PM'
      AND e.value#>>'{canonicalAfter,publicEventLocalTime}'='4:00 PM–8:00 PM'
      AND e.value#>>'{resourceClaimCountPreserved}'='1'
      AND e.actor_user_id='f5210000-0000-4000-8000-000000000403'::uuid)<>1 THEN
    RAISE EXCEPTION 'Old/new historical schedule decision receipt missing';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM local_intel.occurrences
    WHERE id='f5210000-0000-4000-8000-000000000102'::uuid
    AND start_at='2030-10-30 13:00+00'::timestamptz) THEN
    RAISE EXCEPTION 'Separate same-date Event was incorrectly merged';
 END IF;
END
$inspect_source$;
ROLLBACK;

SELECT jsonb_build_object(
 'contractVersion','atlas_one_event_schedule_writer_clone_proof_v1',
 'rootAndOrdinaryPermissionBoundary',true,
 'legacyIndependentRetimeDenied',true,
 'sourceVersionAndIdempotency',true,
 'richMetadataAndConfirmedSiteHoldPreserved',true,
 'historicalOldNewScheduleReceipt',true,
 'distinctSameDateEventPreserved',true,
 'signedTransportProofInRunner',true
) AS acceptance_receipt;