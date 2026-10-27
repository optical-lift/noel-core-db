-- Us-only Carry event custody v1. Source candidate ONLY, never run on production directly.
-- No Atlas/read/write dependencies; no real financial or person data.
BEGIN;

CREATE TABLE us.carry_case_streams_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  owner_auth_user_id uuid NOT NULL,
  stream_key text NOT NULL CHECK (length(btrim(stream_key)) BETWEEN 8 AND 160),
  subject_kind text NOT NULL CHECK (subject_kind IN ('financial_expectation','carry_case')),
  financial_plan_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT us_carry_stream_plan_scope CHECK(
    (subject_kind='financial_expectation' AND financial_plan_id IS NOT NULL) OR
    (subject_kind='carry_case' AND financial_plan_id IS NULL)),
  CONSTRAINT us_carry_stream_plan_fk FOREIGN KEY(financial_plan_id,owner_auth_user_id)
    REFERENCES us.financial_expectation_plans(id,owner_auth_user_id) ON DELETE RESTRICT,
  CONSTRAINT us_carry_stream_owner_key UNIQUE(id,owner_auth_user_id),
  CONSTRAINT us_carry_stream_natural UNIQUE(owner_auth_user_id,stream_key)
);
COMMENT ON TABLE us.carry_case_streams_v1 IS 'Private Us Carry history identity; not Atlas Event Work or a bank transaction ledger.';
-- Only one canonical financial-history stream per financial expectation.
CREATE UNIQUE INDEX carry_one_financial_stream_v1
 ON us.carry_case_streams_v1(financial_plan_id)
 WHERE financial_plan_id IS NOT NULL;

CREATE TABLE us.carry_case_events_v1 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 owner_auth_user_id uuid NOT NULL,
 stream_id uuid NOT NULL,
 stream_sequence bigint NOT NULL CHECK (stream_sequence>=1),
 event_type text NOT NULL CHECK (event_type IN
   ('CASE_OPENED','BASELINE_IMPORTED','FACT_ASSERTED','EVIDENCE_REFERENCED',
    'FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED',
    'SCENARIO_CREATED','SCENARIO_OVERRIDE_RECORDED','REVISION_SEALED','DECISION_RECORDED')),
 event_schema_version smallint NOT NULL CHECK (event_schema_version=1),
 idempotency_key text NOT NULL CHECK (length(btrim(idempotency_key)) BETWEEN 8 AND 160),
 actor_auth_user_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 effective_on date,
 source_ref text NOT NULL CHECK (length(btrim(source_ref)) BETWEEN 5 AND 250),
 epistemic_class text NOT NULL CHECK (epistemic_class IN
    ('OBSERVED','COMMITTED','DERIVED','PROJECTED','USER_ASSERTED','EXTERNAL_EVIDENCE','UNKNOWN')),
 payload jsonb NOT NULL CHECK (jsonb_typeof(payload)='object'),
 input_digest text NOT NULL CHECK (input_digest ~ '^[0-9a-f]{64}$'),
 previous_event_digest text CHECK (previous_event_digest ~ '^[0-9a-f]{64}$'),
 event_digest text NOT NULL CHECK (event_digest ~ '^[0-9a-f]{64}$'),
 CONSTRAINT us_carry_event_stream_scope FOREIGN KEY(stream_id,owner_auth_user_id)
    REFERENCES us.carry_case_streams_v1(id,owner_auth_user_id) ON DELETE RESTRICT,
 CONSTRAINT us_carry_event_owner_actor CHECK(actor_auth_user_id=owner_auth_user_id),
 CONSTRAINT us_carry_event_sequence_unique UNIQUE(stream_id,stream_sequence),
 CONSTRAINT us_carry_event_idempotency_unique UNIQUE(stream_id,idempotency_key)
);
CREATE INDEX carry_case_events_owner_time_idx
 ON us.carry_case_events_v1(owner_auth_user_id,recorded_at,id);

CREATE FUNCTION us.carry_case_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
BEGIN
 RAISE EXCEPTION 'Us Carry history is append-only' USING ERRCODE='42501';
END $fn$;
CREATE TRIGGER carry_streams_no_mutation_v1 BEFORE UPDATE OR DELETE
 ON us.carry_case_streams_v1 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
CREATE TRIGGER carry_events_no_mutation_v1 BEFORE UPDATE OR DELETE
 ON us.carry_case_events_v1 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();

-- Disallow inserting lines after a forecast revision is adopted, including
-- concurrent sealing: shared row lock on the revision serializes with a seal's UPDATE.
CREATE OR REPLACE FUNCTION us.financial_expectation_line_guard_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
DECLARE v_standing text;
BEGIN
 SELECT r.standing INTO v_standing FROM us.financial_expectation_revisions r
 JOIN us.financial_expectation_plans p
 ON p.id=r.plan_id AND p.owner_auth_user_id=r.owner_auth_user_id
 WHERE r.id=NEW.revision_id AND r.owner_auth_user_id=NEW.owner_auth_user_id
 AND NEW.period_month BETWEEN
   date_trunc('month',p.period_start::timestamp)::date AND
   date_trunc('month',p.period_end::timestamp)::date
 FOR SHARE OF r;
 IF v_standing IS NULL THEN
  RAISE EXCEPTION 'Forecast outside plan period or owner scope' USING ERRCODE='42501';
 END IF;
 IF v_standing<>'draft' THEN
  RAISE EXCEPTION 'Adopted or withdrawn forecast cannot gain lines' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END $fn$;

-- The only permissible revision UPDATE is a one-way draft-to-adopted transition
-- backed by a prior, exact, committed-to-in-this-transaction REVISION_SEALED event.
-- Direct UPDATE remains ungranted to service_role.
CREATE OR REPLACE FUNCTION us.financial_expectation_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path='' AS $fn$
BEGIN
 IF TG_TABLE_NAME='financial_expectation_revisions' AND TG_OP='UPDATE'
 AND OLD.standing='draft' AND NEW.standing='adopted'
 AND (to_jsonb(OLD)-'standing')=(to_jsonb(NEW)-'standing')
 AND EXISTS (
  SELECT 1 FROM us.carry_case_events_v1 ev
  JOIN us.carry_case_streams_v1 s ON s.id=ev.stream_id
    AND s.owner_auth_user_id=ev.owner_auth_user_id
  WHERE ev.owner_auth_user_id=OLD.owner_auth_user_id
    AND s.financial_plan_id=OLD.plan_id
    AND ev.event_type='REVISION_SEALED'
    AND ev.payload->>'revision_id'=OLD.id::text
 ) THEN RETURN NEW; END IF;
 RAISE EXCEPTION 'Financial expectation custody is append-only' USING ERRCODE='42501';
END $fn$;

-- Privileged appender: only callable by server-side service_role; a subsequent
-- authenticated Us adapter MUST verify owner and provenance before invoking it.
-- There is no client/public execution grant or direct event INSERT permission.
CREATE FUNCTION us.carry_append_event_v1(
 p_stream_id uuid, p_action_key text, p_event_type text, p_effective_on date,
 p_epistemic_class text, p_source_ref text, p_payload jsonb,
 p_expected_sequence bigint DEFAULT NULL
) RETURNS TABLE(event_id uuid, event_sequence bigint, digest text, replayed boolean)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_stream us.carry_case_streams_v1%ROWTYPE;
 v_last us.carry_case_events_v1%ROWTYPE;
 v_existing us.carry_case_events_v1%ROWTYPE;
 v_rev us.financial_expectation_revisions%ROWTYPE;
 v_payload jsonb:=p_payload;
 v_input text;
 v_prev text;
 v_hash text;
 v_seq bigint;
 v_line_count integer;
 v_lines_digest text;
 v_inserted uuid;
BEGIN
 IF p_stream_id IS NULL OR p_action_key IS NULL
    OR length(btrim(p_action_key)) NOT BETWEEN 8 AND 160
    OR p_event_type IS NULL OR p_source_ref IS NULL
    OR length(btrim(p_source_ref)) NOT BETWEEN 5 AND 250
    OR p_epistemic_class IS NULL OR
    p_epistemic_class NOT IN ('OBSERVED','COMMITTED','DERIVED','PROJECTED','USER_ASSERTED','EXTERNAL_EVIDENCE','UNKNOWN')
    OR v_payload IS NULL OR jsonb_typeof(v_payload)<>'object'
 THEN RAISE EXCEPTION 'Invalid Us Carry event envelope' USING ERRCODE='22023'; END IF;
 IF p_event_type NOT IN
   ('CASE_OPENED','BASELINE_IMPORTED','FACT_ASSERTED','EVIDENCE_REFERENCED',
    'FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED',
    'SCENARIO_CREATED','SCENARIO_OVERRIDE_RECORDED','REVISION_SEALED','DECISION_RECORDED')
 THEN RAISE EXCEPTION 'Unknown Carry event type' USING ERRCODE='22023'; END IF;

 SELECT * INTO v_stream FROM us.carry_case_streams_v1 WHERE id=p_stream_id FOR UPDATE;
 IF v_stream.id IS NULL THEN
    RAISE EXCEPTION 'Unknown private stream' USING ERRCODE='42501'; END IF;

 -- Validate exact v1 payload shapes; refuse unknown structure instead of guessing.
 IF p_event_type='CASE_OPENED' THEN
   IF NOT (v_payload ? 'question') OR jsonb_typeof(v_payload->'question')<>'string'
    OR length(btrim(v_payload->>'question')) NOT BETWEEN 3 AND 1000
    OR (v_payload-'question')<>'{}'::jsonb
   THEN RAISE EXCEPTION 'CASE_OPENED payload invalid' USING ERRCODE='22023'; END IF;
 ELSIF p_event_type='BASELINE_IMPORTED' THEN
   IF v_stream.subject_kind<>'financial_expectation'
      OR NOT (v_payload ? 'revision_id') OR jsonb_typeof(v_payload->'revision_id')<>'string'
      OR (v_payload-'revision_id')<>'{}'::jsonb
   THEN RAISE EXCEPTION 'BASELINE_IMPORTED payload invalid' USING ERRCODE='22023'; END IF;
 ELSIF p_event_type='REVISION_SEALED' THEN
   IF v_stream.subject_kind<>'financial_expectation'
      OR NOT (v_payload ? 'revision_id') OR jsonb_typeof(v_payload->'revision_id')<>'string'
      OR (v_payload-'revision_id')<>'{}'::jsonb
   THEN RAISE EXCEPTION 'REVISION_SEALED payload invalid' USING ERRCODE='22023'; END IF;
 ELSE
   -- v1 holds a typed, bounded reason plus a value. The semantic reducer
   -- defines meaning; this capture does not authorize economic facts.
   IF NOT (v_payload ? 'reason') OR jsonb_typeof(v_payload->'reason')<>'string'
     OR length(btrim(v_payload->>'reason')) NOT BETWEEN 3 AND 1000
     OR NOT (v_payload ? 'value') OR length(v_payload::text)>8000
     OR (v_payload-'reason'-'value')<>'{}'::jsonb
   THEN RAISE EXCEPTION 'Carry v1 proposal payload invalid' USING ERRCODE='22023'; END IF;
 END IF;

 -- A retry after sealing must succeed even though the target revision now
 -- reads 'adopted'. Resolve an existing action BEFORE evaluating fresh state.
 SELECT * INTO v_existing FROM us.carry_case_events_v1
  WHERE stream_id=p_stream_id AND idempotency_key=p_action_key;
 IF v_existing.id IS NOT NULL THEN
  IF v_existing.event_type IS DISTINCT FROM p_event_type
   OR v_existing.effective_on IS DISTINCT FROM p_effective_on
   OR v_existing.source_ref IS DISTINCT FROM p_source_ref
   OR v_existing.epistemic_class IS DISTINCT FROM p_epistemic_class
   OR (CASE WHEN p_event_type IN ('BASELINE_IMPORTED','REVISION_SEALED')
       THEN jsonb_build_object('revision_id',v_existing.payload->>'revision_id')
       ELSE v_existing.payload END) IS DISTINCT FROM p_payload
  THEN RAISE EXCEPTION 'Idempotency key used for different Carry event'
     USING ERRCODE='23505'; END IF;
  RETURN QUERY SELECT v_existing.id,v_existing.stream_sequence,v_existing.event_digest,true;
  RETURN;
 END IF;

 -- Derive the provenance of imported or sealed financial snapshots ourselves.
 IF p_event_type IN ('BASELINE_IMPORTED','REVISION_SEALED') THEN
   BEGIN
    SELECT * INTO v_rev FROM us.financial_expectation_revisions
     WHERE id=(v_payload->>'revision_id')::uuid AND owner_auth_user_id=v_stream.owner_auth_user_id
       AND plan_id=v_stream.financial_plan_id FOR UPDATE;
   EXCEPTION WHEN invalid_text_representation THEN
     RAISE EXCEPTION 'Invalid revision reference' USING ERRCODE='22023';
   END;
   IF v_rev.id IS NULL OR
      (p_event_type='BASELINE_IMPORTED' AND v_rev.standing<>'adopted') OR
      (p_event_type='REVISION_SEALED' AND v_rev.standing<>'draft')
   THEN RAISE EXCEPTION 'Revision state or scope is not eligible' USING ERRCODE='42501'; END IF;
   SELECT count(*)::int,
     pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
       coalesce(jsonb_agg(jsonb_build_array(
         l.period_month,l.line_key,l.economic_scope,l.subject_key,l.money_role,
         l.expectation_state,l.forecast_amount,l.currency,l.explanation)
         ORDER BY l.period_month,l.line_key),'[]'::jsonb)::text,'UTF8'),'sha256'),'hex')
   INTO v_line_count,v_lines_digest FROM us.financial_expectation_lines l
   WHERE l.revision_id=v_rev.id AND l.owner_auth_user_id=v_stream.owner_auth_user_id;
   IF v_line_count=0 THEN RAISE EXCEPTION 'Cannot import or seal empty forecast' USING ERRCODE='22023'; END IF;
   v_payload:=jsonb_build_object('revision_id',v_rev.id::text,
      'line_count',v_line_count,'snapshot_digest',v_lines_digest);
 END IF;

 -- This digest does not cover generated event fields; it proves idempotent
 -- supplied action equivalence (after canonical server-derived v1 payload).
 v_input:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
    jsonb_build_array(p_event_type,1,p_effective_on,p_epistemic_class,
      p_source_ref,v_payload)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_last FROM us.carry_case_events_v1
  WHERE stream_id=p_stream_id ORDER BY stream_sequence DESC LIMIT 1;
 v_seq:=coalesce(v_last.stream_sequence,0)+1;
 v_prev:=v_last.event_digest;
 IF p_expected_sequence IS NOT NULL AND p_expected_sequence<>v_seq THEN
    RAISE EXCEPTION 'Carry event sequence mismatch' USING ERRCODE='40001'; END IF;
 IF p_event_type='CASE_OPENED' AND v_seq<>1 THEN
    RAISE EXCEPTION 'Case already opened' USING ERRCODE='22023'; END IF;
 IF p_event_type<>'CASE_OPENED' AND v_seq=1 THEN
    RAISE EXCEPTION 'Case opening event required' USING ERRCODE='22023'; END IF;
 IF p_event_type='BASELINE_IMPORTED' AND
   EXISTS(SELECT 1 FROM us.carry_case_events_v1
    WHERE stream_id=p_stream_id AND event_type='BASELINE_IMPORTED')
 THEN RAISE EXCEPTION 'Baseline already imported' USING ERRCODE='23505'; END IF;
 IF p_event_type='REVISION_SEALED' AND
   EXISTS(SELECT 1 FROM us.carry_case_events_v1
    WHERE stream_id=p_stream_id AND event_type='REVISION_SEALED'
     AND payload->>'revision_id'=v_rev.id::text)
 THEN RAISE EXCEPTION 'Revision already sealed' USING ERRCODE='23505'; END IF;
 v_hash:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(p_stream_id::text,v_seq,v_input,v_prev)::text,'UTF8'),'sha256'),'hex');
 INSERT INTO us.carry_case_events_v1(owner_auth_user_id,stream_id,stream_sequence,
  event_type,event_schema_version,idempotency_key,actor_auth_user_id,
  effective_on,source_ref,epistemic_class,payload,input_digest,previous_event_digest,event_digest)
 VALUES(v_stream.owner_auth_user_id,p_stream_id,v_seq,p_event_type,1,p_action_key,
    v_stream.owner_auth_user_id,p_effective_on,p_source_ref,p_epistemic_class,
    v_payload,v_input,v_prev,v_hash)
 RETURNING id INTO v_inserted;
 IF p_event_type='REVISION_SEALED' THEN
   UPDATE us.financial_expectation_revisions
   SET standing='adopted' WHERE id=v_rev.id AND owner_auth_user_id=v_stream.owner_auth_user_id;
 END IF;
 RETURN QUERY SELECT v_inserted,v_seq,v_hash,false;
END $fn$;

ALTER TABLE us.carry_case_streams_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_streams_v1 FORCE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_events_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_events_v1 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_case_streams_v1,us.carry_case_events_v1 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)
 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION us.carry_case_immutable_v1()
 FROM PUBLIC,anon,authenticated,service_role;
-- Trusted Us back-end only. Future reader/writer MUST bind an authenticated
-- principal to owner_auth_user_id before accessing any service-owned stream.
GRANT SELECT,INSERT ON us.carry_case_streams_v1 TO service_role;
GRANT SELECT ON us.carry_case_events_v1 TO service_role;
GRANT EXECUTE ON FUNCTION us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)
 TO service_role;
COMMIT;
