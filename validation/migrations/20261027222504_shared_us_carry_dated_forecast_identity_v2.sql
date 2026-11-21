-- Synthetic postconditions for Us Carry dated event admission.
-- Runs after BOTH prior Us migrations plus this candidate; rollback-only.
BEGIN;
DO $test$
DECLARE
  v_owner uuid:=pg_catalog.gen_random_uuid();
  v_plan uuid;
  v_stream uuid;
  v_kind text;
  v_payload jsonb;
  v_count integer;
  v_bad boolean;
  v_name text:='monthly_income';
BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='us' AND c.relname='carry_case_events_v1'
      AND t.tgname='carry_forecast_line_event_scope_guard_v2' AND t.tgenabled='O')
  THEN RAISE EXCEPTION 'Dated event trigger absent'; END IF;

  INSERT INTO us.financial_expectation_plans
    (owner_auth_user_id,plan_key,title,period_start,period_end,source_ref)
  VALUES(v_owner,'synthetic:dated_carry_plan','Synthetic dated Carry forecast',
         '2027-01-01','2027-03-31','synthetic:source')
  RETURNING id INTO v_plan;
  INSERT INTO us.carry_case_streams_v1(owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
  VALUES(v_owner,'synthetic:dated_carry_stream','financial_expectation',v_plan)
  RETURNING id INTO v_stream;
  PERFORM us.carry_append_event_v1(v_stream,'synthetic:open_case','CASE_OPENED',
       '2027-01-01','USER_ASSERTED','synthetic:source',
       '{"question":"Can dated sources carry these obligations?"}'::jsonb,1);

  FOR v_count IN 1..2 LOOP
    v_payload:=jsonb_build_object('reason','Synthetic dated monthly candidate',
        'value',jsonb_build_object(
          'period_month',CASE WHEN v_count=1 THEN '2027-01-01' ELSE '2027-02-01' END,
          'line_key',v_name,'economic_scope','household','subject_key',NULL,
          'money_role','available_inflow','expectation_state','estimated',
          'forecast_amount','100.00','currency','USD','explanation','Synthetic only'));
    PERFORM us.carry_append_event_v1(
       v_stream,'synthetic:monthly_'||v_count,'FORECAST_LINE_PROPOSED',
       '2027-01-01','PROJECTED','synthetic:source',v_payload,v_count+1);
  END LOOP;
  SELECT count(*) INTO v_count FROM us.carry_case_events_v1
   WHERE stream_id=v_stream AND event_type='FORECAST_LINE_PROPOSED';
  IF v_count<>2 THEN RAISE EXCEPTION 'Repeated name across months was lost'; END IF;

  -- Missing month, amount with JSON number rather than text, and the
  -- illegitimate future month must each be source-enforced denials.
  SELECT payload INTO v_payload FROM us.carry_case_events_v1
   WHERE stream_id=v_stream AND stream_sequence=2;
  v_bad:=false;
  BEGIN
    PERFORM us.carry_append_event_v1(v_stream,'synthetic:bad_no_month',
      'FORECAST_LINE_PROPOSED','2027-01-01','PROJECTED','synthetic:source',
      jsonb_set(v_payload,'{value}',(v_payload->'value')-'period_month'),4);
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN v_bad:=true; END;
  IF NOT v_bad THEN RAISE EXCEPTION 'Missing dated period admitted'; END IF;

  v_bad:=false;
  BEGIN
    PERFORM us.carry_append_event_v1(v_stream,'synthetic:bad_float',
      'FORECAST_LINE_PROPOSED','2027-01-01','PROJECTED','synthetic:source',
      jsonb_set(v_payload,'{value,forecast_amount}','100.5'::jsonb),4);
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN v_bad:=true; END;
  IF NOT v_bad THEN RAISE EXCEPTION 'Nonnormalized money amount admitted'; END IF;

  v_bad:=false;
  BEGIN
    PERFORM us.carry_append_event_v1(v_stream,'synthetic:bad_future',
      'FORECAST_LINE_PROPOSED','2027-01-01','PROJECTED','synthetic:source',
      jsonb_set(v_payload,'{value,period_month}','"2027-12-01"'::jsonb),4);
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN v_bad:=true; END;
  IF NOT v_bad THEN RAISE EXCEPTION 'Out of plan month admitted'; END IF;

  v_bad:=false;
  BEGIN
    PERFORM us.carry_append_event_v1(v_stream,'synthetic:bad_venture',
      'FORECAST_LINE_PROPOSED','2027-01-01','PROJECTED','synthetic:source',
      jsonb_set(v_payload,'{value,economic_scope}','"venture"'::jsonb),4);
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN v_bad:=true; END;
  IF NOT v_bad THEN RAISE EXCEPTION 'Venture with no subject admitted'; END IF;

  v_bad:=false;
  BEGIN
    PERFORM us.carry_append_event_v1(v_stream,'synthetic:bad_extra',
      'FORECAST_LINE_PROPOSED','2027-01-01','PROJECTED','synthetic:source',
      jsonb_set(v_payload,'{value,unapproved_field}','true'::jsonb),4);
  EXCEPTION WHEN invalid_parameter_value OR insufficient_privilege THEN v_bad:=true; END;
  IF NOT v_bad THEN RAISE EXCEPTION 'Unexpected field admitted'; END IF;

  SELECT count(*) INTO v_count FROM us.carry_case_events_v1 WHERE stream_id=v_stream;
  IF v_count<>3 THEN
    RAISE EXCEPTION 'Rejected insert changed event history: %',v_count; END IF;
END
$test$;
ROLLBACK;
