-- Us Carry v2: dated forecast-event identity admission. SOURCE CANDIDATE ONLY.
-- Depends on live-source migrations 20261027171353 and 20261027204404.
-- Never directly execute on production; no Atlas objects, grants or data.
BEGIN;

CREATE FUNCTION us.carry_forecast_line_event_guard_v2()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE
 v jsonb;
 v_month text;
 v_key text;
 v_scope text;
 v_subject text;
 v_amount text;
 v_start date;
 v_end date;
 v_date date;
BEGIN
 IF NEW.event_type NOT IN
  ('FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED')
 THEN RETURN NEW; END IF;

 v := NEW.payload->'value';
 IF jsonb_typeof(v)<>'object' THEN
  RAISE EXCEPTION 'Dated forecast event requires value object'
   USING ERRCODE='22023'; END IF;
 IF NOT (v ? 'period_month' AND v ? 'line_key')
    OR jsonb_typeof(v->'period_month')<>'string'
    OR jsonb_typeof(v->'line_key')<>'string'
 THEN RAISE EXCEPTION 'Dated month and line key required' USING ERRCODE='22023'; END IF;
 v_month:=v->>'period_month';
 v_key:=v->>'line_key';
 IF v_month !~ '^[0-9]{4}-[0-9]{2}-01$' OR
    v_key !~ '^[a-z][a-z0-9_:-]{3,159}$'
 THEN RAISE EXCEPTION 'Invalid dated forecast identity' USING ERRCODE='22023'; END IF;
 BEGIN
  v_date:=v_month::date;
 EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
  RAISE EXCEPTION 'Invalid calendar month' USING ERRCODE='22023';
 END;
 IF to_char(v_date,'YYYY-MM-DD')<>v_month THEN
  RAISE EXCEPTION 'Invalid canonical forecast month' USING ERRCODE='22023'; END IF;

 SELECT p.period_start,p.period_end INTO v_start,v_end
 FROM us.carry_case_streams_v1 s
 JOIN us.financial_expectation_plans p ON p.id=s.financial_plan_id
   AND p.owner_auth_user_id=s.owner_auth_user_id
 WHERE s.id=NEW.stream_id AND s.owner_auth_user_id=NEW.owner_auth_user_id
   AND s.subject_kind='financial_expectation';
 IF v_start IS NULL OR
    v_date NOT BETWEEN date_trunc('month',v_start::timestamp)::date
      AND date_trunc('month',v_end::timestamp)::date
 THEN RAISE EXCEPTION 'Forecast event outside owned plan period' USING ERRCODE='42501'; END IF;

 IF NEW.event_type='FORECAST_LINE_RELEASED' THEN
  IF (v-'period_month'-'line_key')<>'{}'::jsonb
  THEN RAISE EXCEPTION 'Released line requires only month and key'
      USING ERRCODE='22023'; END IF;
  RETURN NEW;
 END IF;

 IF NOT (v ? 'economic_scope' AND v ? 'subject_key'
      AND v ? 'money_role' AND v ? 'expectation_state'
      AND v ? 'forecast_amount' AND v ? 'currency'
      AND v ? 'explanation')
    OR (v-'period_month'-'line_key'-'economic_scope'-'subject_key'
           -'money_role'-'expectation_state'-'forecast_amount'
           -'currency'-'explanation')<>'{}'::jsonb
 THEN RAISE EXCEPTION 'Forecast line requires complete fields'
   USING ERRCODE='22023'; END IF;

 IF jsonb_typeof(v->'economic_scope')<>'string'
    OR jsonb_typeof(v->'money_role')<>'string'
    OR jsonb_typeof(v->'expectation_state')<>'string'
    OR jsonb_typeof(v->'forecast_amount')<>'string'
    OR jsonb_typeof(v->'currency')<>'string'
    OR jsonb_typeof(v->'explanation') NOT IN ('string','null')
 THEN RAISE EXCEPTION 'Forecast line data types invalid'
    USING ERRCODE='22023'; END IF;

 v_scope:=v->>'economic_scope';
 v_subject:=v->>'subject_key';
 v_amount:=v->>'forecast_amount';
 IF v_scope NOT IN ('household','personal','venture') OR
    v->>'money_role' NOT IN ('gross_inflow','available_inflow','cash_outflow',
                            'card_charge','card_payment','debt_balance','capital_budget') OR
    v->>'expectation_state' NOT IN ('committed','estimated','conditional','target') OR
    (v->>'currency') !~ '^[A-Z]{3}$' OR
    v_amount !~ '^(0|[1-9][0-9]{0,15})\.[0-9]{2}$'
 THEN RAISE EXCEPTION 'Forecast role, state, currency or amount invalid'
    USING ERRCODE='22023'; END IF;
 IF (v_scope='venture' AND
       (jsonb_typeof(v->'subject_key')<>'string' OR
        v_subject IS NULL OR btrim(v_subject)=''))
    OR (v_scope<>'venture' AND
       jsonb_typeof(v->'subject_key')<>'null')
 THEN RAISE EXCEPTION 'Financial subject and scope mismatch'
    USING ERRCODE='42501'; END IF;
 IF v->>'explanation' IS NOT NULL AND
    length(v->>'explanation')>2000
 THEN RAISE EXCEPTION 'Forecast explanation too long'
    USING ERRCODE='22023'; END IF;
 RETURN NEW;
END
$fn$;

CREATE TRIGGER carry_forecast_line_event_scope_guard_v2
 BEFORE INSERT ON us.carry_case_events_v1
 FOR EACH ROW EXECUTE FUNCTION us.carry_forecast_line_event_guard_v2();

REVOKE ALL ON FUNCTION us.carry_forecast_line_event_guard_v2()
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
