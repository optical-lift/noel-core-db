-- HELD: source-only signed bridge to the single private lifecycle authority.
-- Exact historical review and current native Ledger governor only.
-- The immutable shadow base (04) predates historical review. Preserve its
-- existing allowed evidence sources and admit exactly this additional source.
ALTER TABLE atlas.work_lifecycle_events_v1
 DROP CONSTRAINT work_lifecycle_events_v1_source_table_check;
ALTER TABLE atlas.work_lifecycle_events_v1
 ADD CONSTRAINT work_lifecycle_events_v1_source_table_check
 CHECK(source_table IN (
   'atlas.work_items','atlas.work_execution_results',
   'atlas.work_result_acceptances','atlas.work_allocations',
   'atlas.work_execution_plan_events',
   'atlas.historical_self_adoption_review_events_v1'
 ));
CREATE OR REPLACE FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_review_id uuid,
 p_impact_token text,p_action_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $retire$
DECLARE
 v_actor uuid;
 v_review atlas.historical_self_adoption_review_events_v1%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_impact jsonb;
 v_receipt jsonb;
BEGIN
 v_actor:=atlas.company_work_native_ledger_owner_self_v1(
   p_organization_id,p_ledger_id);
 IF v_actor IS NULL OR p_review_id IS NULL OR p_action_id IS NULL
 OR p_impact_token IS NULL OR length(p_impact_token)<>32
 THEN RAISE EXCEPTION 'Exact native governor, review, token and action required'
 USING ERRCODE='42501'; END IF;
 SELECT * INTO v_review FROM atlas.historical_self_adoption_review_events_v1 h
 WHERE h.id=p_review_id AND h.organization_id=p_organization_id
 AND h.ledger_id=p_ledger_id AND h.event_kind='governor_reviewed'
 AND h.outcome='obsolete_cancelled';
 IF v_review.id IS NULL THEN RAISE EXCEPTION 'Exact obsolete historical review required'
 USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.work_lifecycle_events_v1:'||v_review.work_item_id::text,0));
 SELECT * INTO v_work FROM atlas.work_items w
 WHERE w.id=v_review.work_item_id AND w.organization_id=p_organization_id
 FOR UPDATE;
 IF v_work.id IS NULL THEN RAISE EXCEPTION 'Original Work unavailable'
 USING ERRCODE='42501'; END IF;
 -- Replay is validated against original reviewed source and signed actor
 -- by the private core, even after state changes.
 IF v_work.work_state='cancelled' THEN
   RETURN atlas.apply_work_lifecycle_transition_internal_v1(
     v_work.id,'cancel',v_review.id,
     'native-historical-retirement:'||p_action_id::text);
 END IF;
 v_impact:=atlas.company_work_retirement_dependency_snapshot_v1(v_work.id);
 IF md5(v_impact::text) IS DISTINCT FROM p_impact_token THEN
   RAISE EXCEPTION 'Retirement preflight stale; refresh impact'
   USING ERRCODE='40001'; END IF;
 v_receipt:=atlas.apply_work_lifecycle_transition_internal_v1(
   v_work.id,'cancel',v_review.id,
   'native-historical-retirement:'||p_action_id::text);
 IF v_receipt->>'workState' IS DISTINCT FROM 'cancelled'
 OR v_receipt->>'historicalReviewId' IS DISTINCT FROM v_review.id::text
 THEN RAISE EXCEPTION 'Single transition retirement not confirmed'
 USING ERRCODE='23514'; END IF;
 RETURN v_receipt;
END; $retire$;
REVOKE ALL ON FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_retire_historical_work_self_api_v1(
 uuid,uuid,uuid,text,uuid) TO authenticated;
