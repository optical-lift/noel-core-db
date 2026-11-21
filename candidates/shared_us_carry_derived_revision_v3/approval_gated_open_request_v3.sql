-- HELD Carry F: explicit, staged financial Case-opening *request*, not history.
-- Requires finance baseline, Carry custody v1, v3 restricted backend reader.
-- Owner direction 1D/2D/3C/4D/5C. No separate authorized Person means no event.
-- Never apply directly to production; this is not a generated migration.
BEGIN;

CREATE TABLE us.carry_financial_open_requests_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 owner_auth_user_id uuid NOT NULL,
 plan_id uuid NOT NULL,
 case_kind text NOT NULL CHECK (case_kind IN ('primary','additional')),
 request_key text NOT NULL CHECK (length(btrim(request_key)) BETWEEN 8 AND 160),
 requester_auth_user_id uuid NOT NULL,
 baseline_revision_id uuid NOT NULL,
 baseline_line_count integer NOT NULL CHECK (baseline_line_count>0),
 baseline_snapshot_digest text NOT NULL CHECK (baseline_snapshot_digest ~ '^[0-9a-f]{64}$'),
 disposition text NOT NULL DEFAULT 'pending_independent_approval'
   CHECK (disposition='pending_independent_approval'),
 requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT carry_open_request_is_owner CHECK(requester_auth_user_id=owner_auth_user_id),
 CONSTRAINT carry_open_request_plan_owner FOREIGN KEY(plan_id,owner_auth_user_id)
   REFERENCES us.financial_expectation_plans(id,owner_auth_user_id) ON DELETE RESTRICT,
 CONSTRAINT carry_open_request_revision_owner FOREIGN KEY(baseline_revision_id,owner_auth_user_id)
   REFERENCES us.financial_expectation_revisions(id,owner_auth_user_id) ON DELETE RESTRICT,
 CONSTRAINT carry_open_request_one_plan UNIQUE (plan_id),
 CONSTRAINT carry_open_request_action UNIQUE (owner_auth_user_id,request_key)
);
CREATE UNIQUE INDEX carry_open_request_one_primary_v3
 ON us.carry_financial_open_requests_v3(owner_auth_user_id)
 WHERE case_kind='primary';

CREATE TRIGGER carry_open_requests_no_mutation_v3 BEFORE UPDATE OR DELETE
 ON us.carry_financial_open_requests_v3 FOR EACH ROW
 EXECUTE FUNCTION us.carry_case_immutable_v1();
ALTER TABLE us.carry_financial_open_requests_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_financial_open_requests_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_financial_open_requests_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_request_financial_open_v3(
 p_owner_auth_user_id uuid,
 p_plan_key text,
 p_request_key text,
 p_case_kind text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_plan us.financial_expectation_plans%ROWTYPE;
 v_rev us.financial_expectation_revisions%ROWTYPE;
 v_prior us.carry_financial_open_requests_v3%ROWTYPE;
 v_count integer;
 v_digest text;
 v_id uuid;
 v_has_primary boolean;
BEGIN
 IF p_owner_auth_user_id IS NULL
    OR p_plan_key IS NULL OR p_plan_key !~ '^[a-z][a-z0-9_:-]{7,159}$'
    OR p_request_key IS NULL OR length(btrim(p_request_key)) NOT BETWEEN 8 AND 160
    OR p_case_kind IS NULL OR p_case_kind NOT IN ('primary','additional')
 THEN RAISE EXCEPTION 'Invalid explicit Case-opening request' USING ERRCODE='22023'; END IF;

 -- Lock only this exact owner+plan. Do not scan the owner's other plans or
 -- reveal whether any foreign plan_key exists.
 SELECT * INTO v_plan FROM us.financial_expectation_plans p
 WHERE p.owner_auth_user_id=p_owner_auth_user_id AND p.plan_key=p_plan_key
 FOR UPDATE;
 IF v_plan.id IS NULL THEN
  RAISE EXCEPTION 'Financial plan unavailable' USING ERRCODE='42501';
 END IF;

 -- Existing canonical stream always wins: do not create a second Case, or
 -- silently "repair" an incomplete history as a side effect of opening.
 IF EXISTS(SELECT 1 FROM us.carry_case_streams_v1 s
           WHERE s.financial_plan_id=v_plan.id)
 THEN RAISE EXCEPTION 'Existing Carry Case requires separate history review'
      USING ERRCODE='42501'; END IF;

 -- The owner explicitly selects primary. Never infer it from recency.
 -- Additional Cases must wait until a later separately approved primary
 -- opening operation; no authority is fabricated from a pending request.
 SELECT EXISTS(
  SELECT 1 FROM us.carry_financial_open_requests_v3 r
  WHERE r.owner_auth_user_id=p_owner_auth_user_id AND r.case_kind='primary'
 ) INTO v_has_primary;
 IF (p_case_kind='primary' AND v_has_primary AND NOT EXISTS(
    SELECT 1 FROM us.carry_financial_open_requests_v3 r
    WHERE r.plan_id=v_plan.id AND r.case_kind='primary'
 )) OR p_case_kind='additional'
 THEN RAISE EXCEPTION 'Primary financial Case must be independently opened first'
      USING ERRCODE='42501'; END IF;

 -- Never bootstrap using latest/first arbitrary draft: revision 1 must
 -- already be source-adopted, intact and nonempty. The approver will recheck.
 SELECT * INTO v_rev FROM us.financial_expectation_revisions r
 WHERE r.plan_id=v_plan.id AND r.owner_auth_user_id=p_owner_auth_user_id
       AND r.revision=1 AND r.standing='adopted' FOR SHARE;
 IF v_rev.id IS NULL THEN
   RAISE EXCEPTION 'Source-attested first adopted baseline unavailable'
     USING ERRCODE='42501'; END IF;

 SELECT count(*)::int,
  pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
   coalesce(jsonb_agg(jsonb_build_array(
    l.period_month,l.line_key,l.economic_scope,l.subject_key,l.money_role,
    l.expectation_state,l.forecast_amount,l.currency,l.explanation)
    ORDER BY l.period_month,l.line_key),'[]'::jsonb)::text,'UTF8'),
   'sha256'),'hex')
 INTO v_count,v_digest FROM us.financial_expectation_lines l
 WHERE l.revision_id=v_rev.id AND l.owner_auth_user_id=p_owner_auth_user_id;
 IF v_count=0 THEN RAISE EXCEPTION 'Source-attested baseline is empty'
   USING ERRCODE='42501'; END IF;

 SELECT * INTO v_prior FROM us.carry_financial_open_requests_v3 r
 WHERE r.plan_id=v_plan.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
   IF v_prior.request_key IS DISTINCT FROM p_request_key
      OR v_prior.case_kind IS DISTINCT FROM p_case_kind
      OR v_prior.baseline_revision_id IS DISTINCT FROM v_rev.id
      OR v_prior.baseline_line_count IS DISTINCT FROM v_count
      OR v_prior.baseline_snapshot_digest IS DISTINCT FROM v_digest
   THEN RAISE EXCEPTION 'Conflicting Case opening request'
     USING ERRCODE='23505'; END IF;
   v_id:=v_prior.id;
 ELSE
   INSERT INTO us.carry_financial_open_requests_v3(
     owner_auth_user_id,plan_id,case_kind,request_key,
     requester_auth_user_id,baseline_revision_id,
     baseline_line_count,baseline_snapshot_digest)
   VALUES(p_owner_auth_user_id,v_plan.id,p_case_kind,p_request_key,
      p_owner_auth_user_id,v_rev.id,v_count,v_digest)
   RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object(
   'request_id',v_id::text,
   'case_kind',p_case_kind,
   'status','pending_independent_approval',
   'recorded_event',false,
   'case_opened',false,
   'replayed',v_prior.id IS NOT NULL
 );
END $fn$;

REVOKE ALL ON FUNCTION us.carry_request_financial_open_v3(
 uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_request_financial_open_v3(
 uuid,text,text,text) TO us_carry_backend;

-- No GRANT of raw INSERT or append/approve/adopt. The request is not
-- authorization for an event; independent active Person authority must follow.
COMMIT;
