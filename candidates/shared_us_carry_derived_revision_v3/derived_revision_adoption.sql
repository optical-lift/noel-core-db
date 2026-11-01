-- HELD Us Carry v3 increment D: DB-only, source-derived financial adoption.
-- Unreleased source only. Requires A privilege floor, B ordinary event and
-- C source-derived review. The app MUST verify real GoTrue owner at its trusted
-- server and pass the verified ID; never trust an HTTP supplied owner UUID.
-- No caller-provided line array or source digest is authorization.
BEGIN;

CREATE FUNCTION us.carry_adopt_derived_revision_v3(
 p_owner_auth_user_id uuid,
 p_stream_id uuid,
 p_action_key text,
 p_expected_cutoff bigint,
 p_expected_candidate_digest text
) RETURNS TABLE(
 revision_id uuid,revision_number integer,seal_event_id uuid,
 seal_sequence bigint,source_cutoff bigint,replayed boolean
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_stream_id uuid;
 v_event us.carry_case_events_v1%ROWTYPE;
 v_previous us.financial_expectation_revisions%ROWTYPE;
 v_candidate jsonb;
 v_line jsonb;
 v_plan_id uuid;
 v_new_id uuid;
 v_number integer;
 v_seal record;
BEGIN
 IF p_owner_auth_user_id IS NULL OR p_stream_id IS NULL
    OR p_action_key IS NULL OR length(btrim(p_action_key)) NOT BETWEEN 8 AND 160
    OR p_expected_cutoff IS NULL OR p_expected_cutoff<3
    OR p_expected_candidate_digest IS NULL
    OR p_expected_candidate_digest !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid private Carry approval' USING ERRCODE='22023'; END IF;

 -- Preserve one serializable stream state for idempotent retry, candidate
 -- materialization, revision insertion and the final immutable seal event.
 SELECT s.id INTO v_stream_id FROM us.carry_case_streams_v1 s
  WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_owner_auth_user_id
    AND s.subject_kind='financial_expectation' FOR UPDATE;
 IF v_stream_id IS NULL THEN
    RAISE EXCEPTION 'Private Carry stream unavailable' USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_event FROM us.carry_case_events_v1 e
 WHERE e.stream_id=p_stream_id
   AND e.owner_auth_user_id=p_owner_auth_user_id
   AND e.idempotency_key=p_action_key;

 IF v_event.id IS NOT NULL THEN
   IF v_event.event_type<>'REVISION_SEALED' THEN
     RAISE EXCEPTION 'Approval key already identifies a different action'
      USING ERRCODE='23505';
   END IF;
   SELECT * INTO v_previous FROM us.financial_expectation_revisions r
    JOIN us.carry_case_streams_v1 s ON s.financial_plan_id=r.plan_id
     AND s.owner_auth_user_id=r.owner_auth_user_id
    WHERE r.id=(v_event.payload->>'revision_id')::uuid
      AND s.id=p_stream_id AND r.owner_auth_user_id=p_owner_auth_user_id
      AND r.standing='adopted';
   IF v_previous.id IS NULL
      OR v_previous.narrative->>'adoption_method'<>'carry_event_sql_v3'
      OR v_previous.narrative->>'event_cutoff'<>p_expected_cutoff::text
      OR v_previous.narrative->>'candidate_digest'<>p_expected_candidate_digest
   THEN RAISE EXCEPTION 'Approval key belongs to different preview'
     USING ERRCODE='23505'; END IF;
   RETURN QUERY SELECT v_previous.id,v_previous.revision,v_event.id,
      v_event.stream_sequence,p_expected_cutoff,true;
   RETURN;
 END IF;

 -- All amounts, scopes, months, unchanged lines and the canonical digest
 -- originate from the locked verified original baseline plus event history.
 v_candidate:=us.carry_candidate_core_v3(
   p_owner_auth_user_id,p_stream_id,p_expected_cutoff);
 IF v_candidate->>'candidate_digest'<>p_expected_candidate_digest THEN
  RAISE EXCEPTION 'Approved forecast differs from source-derived review'
    USING ERRCODE='40001';
 END IF;
 v_plan_id:=(v_candidate->>'plan_id')::uuid;
 SELECT coalesce(max(r.revision),0)+1 INTO v_number
 FROM us.financial_expectation_revisions r
 WHERE r.plan_id=v_plan_id AND r.owner_auth_user_id=p_owner_auth_user_id;

 INSERT INTO us.financial_expectation_revisions(
   owner_auth_user_id,plan_id,revision,standing,source_ref,narrative)
 VALUES(
   p_owner_auth_user_id,v_plan_id,v_number,'draft',
   'us:carry:adopt:'||p_action_key,
   jsonb_build_object(
     'adoption_method','carry_event_sql_v3',
     'event_cutoff',p_expected_cutoff,
     'baseline_revision_id',v_candidate->>'baseline_revision_id',
     'candidate_digest',v_candidate->>'candidate_digest'))
 RETURNING id INTO v_new_id;

 FOR v_line IN SELECT value FROM jsonb_array_elements(v_candidate->'lines')
 LOOP
   INSERT INTO us.financial_expectation_lines(
     owner_auth_user_id,revision_id,period_month,line_key,
     economic_scope,subject_key,money_role,expectation_state,
     forecast_amount,currency,explanation)
   VALUES(
     p_owner_auth_user_id,v_new_id,(v_line->>'period_month')::date,
     v_line->>'line_key',v_line->>'economic_scope',v_line->>'subject_key',
     v_line->>'money_role',v_line->>'expectation_state',
     (v_line->>'forecast_amount')::numeric(18,2),
     v_line->>'currency',v_line->>'explanation');
 END LOOP;

 -- Only this privileged function can seal after source-derived line writes.
 -- The v1 immutable appender checks state, recomputes the actual line count
 -- and snapshot digest, appends the exact seal and adopts the revision.
 SELECT a.event_id,a.event_sequence,a.replayed INTO v_seal
 FROM us.carry_append_event_v1(
   p_stream_id,p_action_key,'REVISION_SEALED',NULL,'DERIVED',
   'us:carry:derived-forecast',
   jsonb_build_object('revision_id',v_new_id::text),
   p_expected_cutoff+1) a;
 IF v_seal.event_id IS NULL OR v_seal.replayed THEN
   RAISE EXCEPTION 'Database-derived revision seal did not complete'
    USING ERRCODE='23514';
 END IF;

 RETURN QUERY SELECT v_new_id,v_number,v_seal.event_id,
     v_seal.event_sequence,p_expected_cutoff,false;
END
$fn$;

REVOKE ALL ON FUNCTION us.carry_adopt_derived_revision_v3(
 uuid,uuid,text,bigint,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION us.carry_adopt_derived_revision_v3(
 uuid,uuid,text,bigint,text) TO service_role;
COMMIT;
