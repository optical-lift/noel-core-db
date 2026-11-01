-- HELD Us Carry v3 increment C: database-derived candidate review.
-- Dependencies: isolated finance baseline, Carry v1, dated v2, v3 floor and
-- bounded ordinary event writer. Disposable PostgreSQL ONLY. NO deployment.
-- The trusted server verifies the caller's real GoTrue user before supplying
-- p_owner_auth_user_id; never use a request-supplied owner identifier.
BEGIN;

CREATE FUNCTION us.carry_candidate_core_v3(
 p_owner_auth_user_id uuid, p_stream_id uuid, p_expected_cutoff bigint
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_stream us.carry_case_streams_v1%ROWTYPE;
 v_plan us.financial_expectation_plans%ROWTYPE;
 v_event record;
 v_line record;
 v_entry record;
 v_revision us.financial_expectation_revisions%ROWTYPE;
 v_base_id uuid;
 v_base_digest text;
 v_base_count integer;
 v_count integer;
 v_db_digest text;
 v_prev_seq bigint:=0;
 v_prev_digest text;
 v_last_seal bigint:=0;
 v_causal int:=0;
 v_imports int:=0;
 v_lines jsonb:='{}'::jsonb;
 v_value jsonb;
 v_id text;
 v_serialized text:='';
 v_canonical text;
 v_digest text;
 v_ordered jsonb:='[]'::jsonb;
BEGIN
 IF p_owner_auth_user_id IS NULL OR p_stream_id IS NULL
    OR p_expected_cutoff IS NULL OR p_expected_cutoff < 3 THEN
    RAISE EXCEPTION 'Private Carry candidate unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_stream FROM us.carry_case_streams_v1
  WHERE id=p_stream_id AND owner_auth_user_id=p_owner_auth_user_id
   AND subject_kind='financial_expectation' FOR UPDATE;
 IF v_stream.id IS NULL THEN
   RAISE EXCEPTION 'Private Carry candidate unavailable' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_plan FROM us.financial_expectation_plans
 WHERE id=v_stream.financial_plan_id AND owner_auth_user_id=p_owner_auth_user_id
 FOR UPDATE;
 IF v_plan.id IS NULL THEN
   RAISE EXCEPTION 'Private Carry candidate unavailable' USING ERRCODE='42501';
 END IF;

 -- Revalidate a contiguous immutable digest chain under the same stream lock.
 -- The event appender, not the client, originally generated these digests.
 FOR v_event IN SELECT e.stream_sequence,e.event_type,e.event_schema_version,
        e.payload,e.previous_event_digest,e.event_digest,e.input_digest
    FROM us.carry_case_events_v1 e
    WHERE e.stream_id=p_stream_id AND e.owner_auth_user_id=p_owner_auth_user_id
    ORDER BY e.stream_sequence
 LOOP
   IF v_event.stream_sequence<>v_prev_seq+1
     OR v_event.event_schema_version<>1
     OR v_event.previous_event_digest IS DISTINCT FROM v_prev_digest
     OR v_event.event_digest IS DISTINCT FROM
       pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
         jsonb_build_array(p_stream_id::text,v_event.stream_sequence,
           v_event.input_digest,v_event.previous_event_digest)::text,'UTF8'),
       'sha256'),'hex')
   THEN RAISE EXCEPTION 'Private Carry event chain invalid' USING ERRCODE='23514'; END IF;
   v_prev_seq:=v_event.stream_sequence;
   v_prev_digest:=v_event.event_digest;
   IF v_event.event_type='REVISION_SEALED' THEN
     v_last_seal:=v_event.stream_sequence;
   ELSIF v_event.event_type='BASELINE_IMPORTED' THEN
     v_imports:=v_imports+1;
     IF v_imports<>1 OR jsonb_typeof(v_event.payload->'revision_id')<>'string'
        OR jsonb_typeof(v_event.payload->'snapshot_digest')<>'string'
     THEN RAISE EXCEPTION 'Imported source invalid' USING ERRCODE='23514'; END IF;
     v_base_id:=(v_event.payload->>'revision_id')::uuid;
     v_base_count:=(v_event.payload->>'line_count')::integer;
     v_base_digest:=v_event.payload->>'snapshot_digest';
   ELSIF v_event.event_type IN (
      'FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED')
      AND v_event.stream_sequence > v_last_seal THEN
     v_causal:=v_causal+1;
   END IF;
 END LOOP;
 IF v_prev_seq<>p_expected_cutoff OR v_imports<>1 OR v_base_id IS NULL THEN
  RAISE EXCEPTION 'Source event cutoff or import changed' USING ERRCODE='40001';
 END IF;
 IF v_causal=0 THEN
  RAISE EXCEPTION 'No new dated forecast changes' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_revision FROM us.financial_expectation_revisions
 WHERE id=v_base_id AND owner_auth_user_id=p_owner_auth_user_id
   AND plan_id=v_plan.id AND standing='adopted' FOR SHARE;
 IF v_revision.id IS NULL THEN
  RAISE EXCEPTION 'Original adopted financial snapshot unavailable'
    USING ERRCODE='42501';
 END IF;
 SELECT count(*)::integer,
  pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
   coalesce(jsonb_agg(jsonb_build_array(
       l.period_month,l.line_key,l.economic_scope,l.subject_key,l.money_role,
       l.expectation_state,l.forecast_amount,l.currency,l.explanation)
       ORDER BY l.period_month,l.line_key),'[]'::jsonb)::text,'UTF8'),
    'sha256'),'hex')
 INTO v_count,v_db_digest
 FROM us.financial_expectation_lines l
 WHERE l.revision_id=v_base_id AND l.owner_auth_user_id=p_owner_auth_user_id;
 IF v_count=0 OR v_count<>v_base_count OR v_db_digest IS DISTINCT FROM v_base_digest THEN
  RAISE EXCEPTION 'Original adopted financial snapshot digest changed'
    USING ERRCODE='23514';
 END IF;

 -- Original rows are never touched. Rehydrate all original months and amounts.
 FOR v_line IN SELECT l.* FROM us.financial_expectation_lines l
 WHERE l.revision_id=v_base_id AND l.owner_auth_user_id=p_owner_auth_user_id
 ORDER BY l.period_month,l.line_key
 LOOP
   v_id:=pg_catalog.to_char(v_line.period_month,'YYYY-MM-DD')||'|'||v_line.line_key;
   v_value:=jsonb_build_object(
     'period_month',pg_catalog.to_char(v_line.period_month,'YYYY-MM-DD'),
     'line_key',v_line.line_key,'economic_scope',v_line.economic_scope,
     'subject_key',v_line.subject_key,'money_role',v_line.money_role,
     'expectation_state',v_line.expectation_state,
     'forecast_amount',v_line.forecast_amount::text,
     'currency',v_line.currency,'explanation',v_line.explanation);
   v_lines:=jsonb_set(v_lines,ARRAY[v_id],v_value,true);
 END LOOP;

 -- Reconstruct every dated event in sequence, not just the last proposal.
 FOR v_event IN SELECT e.stream_sequence,e.event_type,e.payload
  FROM us.carry_case_events_v1 e
  WHERE e.stream_id=p_stream_id AND e.owner_auth_user_id=p_owner_auth_user_id
    AND e.event_type IN (
      'FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED')
  ORDER BY e.stream_sequence
 LOOP
  v_value:=v_event.payload->'value';
  IF jsonb_typeof(v_value)<>'object'
     OR jsonb_typeof(v_value->'period_month')<>'string'
     OR jsonb_typeof(v_value->'line_key')<>'string'
  THEN RAISE EXCEPTION 'Invalid dated event payload' USING ERRCODE='23514'; END IF;
  v_id:=v_value->>'period_month'||'|'||v_value->>'line_key';
  IF v_value->>'period_month' !~ '^[0-9]{4}-[0-9]{2}-01$'
   OR (v_value->>'line_key') !~ '^[a-z][a-z0-9_:-]{3,159}$'
  THEN RAISE EXCEPTION 'Invalid dated event identity' USING ERRCODE='23514'; END IF;
  IF v_event.event_type='FORECAST_LINE_PROPOSED' THEN
    IF v_lines ? v_id THEN
      RAISE EXCEPTION 'Proposed dated line already exists' USING ERRCODE='23514'; END IF;
    v_lines:=jsonb_set(v_lines,ARRAY[v_id],v_value,true);
  ELSIF v_event.event_type='FORECAST_LINE_REPLACED' THEN
    IF NOT(v_lines ? v_id) THEN
      RAISE EXCEPTION 'Cannot replace absent dated line' USING ERRCODE='23514'; END IF;
    v_lines:=jsonb_set(v_lines,ARRAY[v_id],v_value,true);
  ELSE
    IF NOT(v_lines ? v_id) THEN
      RAISE EXCEPTION 'Cannot release absent dated line' USING ERRCODE='23514'; END IF;
    v_lines:=v_lines-v_id;
  END IF;
 END LOOP;
 IF v_lines='{}'::jsonb THEN
    RAISE EXCEPTION 'Cannot adopt empty financial forecast' USING ERRCODE='22023';
 END IF;

 -- Keep the exact Python v0.1 JSON canonical hash, including key ordering.
 -- All identity keys are restricted to ASCII by the dated-v2 event guard.
 -- Review returns this digest, while adoption rechecks it under the stream lock.
 FOR v_entry IN SELECT key,value FROM jsonb_each(v_lines) ORDER BY key COLLATE "C"
 LOOP
  v_value:=v_entry.value;
  IF (v_value->>'period_month')::date NOT BETWEEN
    date_trunc('month',v_plan.period_start::timestamp)::date AND
    date_trunc('month',v_plan.period_end::timestamp)::date
  THEN RAISE EXCEPTION 'Financial line outside plan period' USING ERRCODE='42501'; END IF;
  IF v_serialized<>'' THEN v_serialized:=v_serialized||','; END IF;
  v_serialized:=v_serialized||
   '{"currency":'||to_json(v_value->>'currency')::text||
   ',"economic_scope":'||to_json(v_value->>'economic_scope')::text||
   ',"expectation_state":'||to_json(v_value->>'expectation_state')::text||
   ',"explanation":'||coalesce(to_json(v_value->>'explanation')::text,'null')||
   ',"forecast_amount":'||to_json(v_value->>'forecast_amount')::text||
   ',"line_key":'||to_json(v_value->>'line_key')::text||
   ',"money_role":'||to_json(v_value->>'money_role')::text||
   ',"period_month":'||to_json(v_value->>'period_month')::text||
   ',"subject_key":'||coalesce(to_json(v_value->>'subject_key')::text,'null')||'}';
  v_ordered:=v_ordered||jsonb_build_array(v_value);
 END LOOP;
 v_canonical:='{"baseline_revision_id":'||to_json(v_base_id::text)::text
   ||',"lines":['||v_serialized||'],"source_event_cutoff":'
   ||p_expected_cutoff::text||',"version":"carry-forecast-candidate-v0.1"}';
 v_digest:=pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to(v_canonical,'UTF8'),'sha256'),'hex');
 RETURN jsonb_build_object(
  'baseline_revision_id',v_base_id::text,
  'candidate_digest',v_digest,
  'line_count',jsonb_array_length(v_ordered),
  'lines',v_ordered,
  'plan_id',v_plan.id::text,
  'source_event_cutoff',p_expected_cutoff,
  'projection_version','carry-forecast-candidate-v0.1',
  'adopted',false);
END
$fn$;

-- No direct EXECUTE on the privileged core, including service_role.
REVOKE ALL ON FUNCTION us.carry_candidate_core_v3(uuid,uuid,bigint)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION us.carry_review_derived_revision_v3(
 p_owner_auth_user_id uuid, p_stream_id uuid, p_expected_cutoff bigint
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_candidate jsonb;
BEGIN
 v_candidate:=us.carry_candidate_core_v3(
  p_owner_auth_user_id,p_stream_id,p_expected_cutoff);
 -- Hide only the internal plan identity; show the exact reviewed line values.
 RETURN v_candidate-'plan_id';
END
$fn$;
REVOKE ALL ON FUNCTION us.carry_review_derived_revision_v3(uuid,uuid,bigint)
 FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION us.carry_review_derived_revision_v3(uuid,uuid,bigint)
 TO service_role;
COMMIT;
