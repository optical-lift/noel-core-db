-- HELD Carry G3: explicit owner authorization for two-event Case opening,
-- then independent currently authorized Person approves that exact snapshot.
-- Uses canonical v1 event appender without changing its digest or actor law.
-- G2 attestation-only permission DOES NOT grant approval; separate owner action
-- required. Source-only draft, no hosted/prod migration or broader append grant.
BEGIN;
CREATE TABLE us.carry_primary_open_approval_grants_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 nomination_id uuid NOT NULL UNIQUE
  REFERENCES us.carry_primary_reviewer_nominations_v3(id) ON DELETE RESTRICT,
 attestation_grant_id uuid NOT NULL
  REFERENCES us.carry_primary_review_disclosure_grants_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL,
 approval_key text NOT NULL CHECK(length(btrim(approval_key)) BETWEEN 8 AND 160),
 baseline_revision_id uuid NOT NULL,
 baseline_line_count integer NOT NULL CHECK(baseline_line_count>0),
 baseline_snapshot_digest text NOT NULL CHECK(baseline_snapshot_digest ~ '^[0-9a-f]{64}$'),
 scope text NOT NULL DEFAULT 'open_primary_case_and_import_attested_baseline'
  CHECK(scope='open_primary_case_and_import_attested_baseline'),
 expires_at timestamptz NOT NULL,
 granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(owner_auth_user_id,approval_key),
 CHECK(expires_at>granted_at)
);
CREATE TABLE us.carry_primary_open_approval_decisions_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 nomination_id uuid NOT NULL UNIQUE
  REFERENCES us.carry_primary_reviewer_nominations_v3(id) ON DELETE RESTRICT,
 approval_grant_id uuid NOT NULL UNIQUE
  REFERENCES us.carry_primary_open_approval_grants_v3(id) ON DELETE RESTRICT,
 open_request_id uuid NOT NULL UNIQUE
  REFERENCES us.carry_financial_open_requests_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 approver_auth_user_id uuid NOT NULL,
 approver_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decision_key text NOT NULL CHECK(length(btrim(decision_key)) BETWEEN 8 AND 160),
 decision_scope text NOT NULL DEFAULT 'open_primary_case_and_import_attested_baseline'
  CHECK(decision_scope='open_primary_case_and_import_attested_baseline'),
 baseline_revision_id uuid NOT NULL,
 baseline_snapshot_digest text NOT NULL CHECK(baseline_snapshot_digest ~ '^[0-9a-f]{64}$'),
 baseline_line_count integer NOT NULL CHECK(baseline_line_count>0),
 canonical_stream_id uuid NOT NULL UNIQUE REFERENCES us.carry_case_streams_v1(id) ON DELETE RESTRICT,
 case_opened_event_id uuid NOT NULL UNIQUE REFERENCES us.carry_case_events_v1(id) ON DELETE RESTRICT,
 baseline_imported_event_id uuid NOT NULL UNIQUE REFERENCES us.carry_case_events_v1(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(owner_auth_user_id<>approver_auth_user_id),
 CHECK(owner_person_entity_id<>approver_person_entity_id),
 UNIQUE(approver_auth_user_id,decision_key)
);
CREATE TRIGGER carry_approval_grant_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_open_approval_grants_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
CREATE TRIGGER carry_approval_decision_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_open_approval_decisions_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
ALTER TABLE us.carry_primary_open_approval_grants_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_open_approval_grants_v3 FORCE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_open_approval_decisions_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_open_approval_decisions_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_primary_open_approval_grants_v3,
 us.carry_primary_open_approval_decisions_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_authorize_primary_open_approval_v3(
 p_verified_owner_auth_user_id uuid,p_nomination_id uuid,
 p_approval_key text,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
 v_req us.carry_financial_open_requests_v3%ROWTYPE;
 v_review us.carry_primary_review_disclosure_grants_v3%ROWTYPE;
 v_prior us.carry_primary_open_approval_grants_v3%ROWTYPE;
 v_att jsonb; v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_nomination_id IS NULL
 OR p_approval_key IS NULL OR length(btrim(p_approval_key)) NOT BETWEEN 8 AND 160
 OR p_expires_at IS NULL
 THEN RAISE EXCEPTION 'Exact owner approval grant required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3 n
 WHERE n.id=p_nomination_id AND n.owner_auth_user_id=p_verified_owner_auth_user_id
 FOR UPDATE;
 IF v_nom.id IS NULL OR NOT us.carry_primary_reviewer_identity_live_v3(v_nom.id)
 THEN RAISE EXCEPTION 'Canonical owner and nominee unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=v_nom.open_request_id AND r.owner_auth_user_id=p_verified_owner_auth_user_id
 AND r.case_kind='primary' AND r.disposition='pending_independent_approval'
 FOR SHARE;
 IF v_req.id IS NULL OR EXISTS (SELECT 1 FROM us.carry_case_streams_v1 s
  WHERE s.financial_plan_id=v_req.plan_id)
 THEN RAISE EXCEPTION 'Only pending unopened primary Case eligible' USING ERRCODE='42501'; END IF;
 -- G2 consent and owner scoped read must both be current, never inherited.
 SELECT * INTO v_review FROM us.carry_primary_review_disclosure_grants_v3 g
 WHERE g.nomination_id=v_nom.id AND g.owner_auth_user_id=p_verified_owner_auth_user_id
  AND g.review_scope='opening_attestation_only'
  AND g.expires_at>clock_timestamp()
  AND NOT EXISTS (SELECT 1 FROM us.carry_primary_review_disclosure_revocations_v3 x
   WHERE x.grant_id=g.id)
 FOR SHARE;
 IF v_review.id IS NULL THEN RAISE EXCEPTION 'Active G2 owner disclosure required'
  USING ERRCODE='42501'; END IF;
 -- Reuse G2 source-derived original baseline attestation, no client digest.
 v_att:=us.carry_read_primary_attestation_v3(v_nom.nominee_auth_user_id,v_nom.id);
 IF v_att->>'baseline_snapshot_digest' IS DISTINCT FROM v_req.baseline_snapshot_digest
 OR (v_att->>'baseline_line_count')::integer IS DISTINCT FROM v_req.baseline_line_count
 THEN RAISE EXCEPTION 'Original source attestation changed' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_primary_open_approval_grants_v3 g
 WHERE g.nomination_id=v_nom.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.owner_auth_user_id IS DISTINCT FROM p_verified_owner_auth_user_id
   OR v_prior.approval_key IS DISTINCT FROM p_approval_key
   OR v_prior.expires_at IS DISTINCT FROM p_expires_at
   OR v_prior.attestation_grant_id IS DISTINCT FROM v_review.id
   OR v_prior.baseline_revision_id IS DISTINCT FROM v_req.baseline_revision_id
   OR v_prior.baseline_snapshot_digest IS DISTINCT FROM v_req.baseline_snapshot_digest
  THEN RAISE EXCEPTION 'Conflicting approval authority' USING ERRCODE='23505'; END IF;
  v_id:=v_prior.id;
 ELSE
  IF p_expires_at<=clock_timestamp()+interval '5 minutes'
   OR p_expires_at>clock_timestamp()+interval '7 days'
   OR p_expires_at>v_review.expires_at
  THEN RAISE EXCEPTION 'Approval must expire before active G2 permission'
   USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_primary_open_approval_grants_v3(
   nomination_id,attestation_grant_id,owner_auth_user_id,
   approval_key,baseline_revision_id,baseline_line_count,
   baseline_snapshot_digest,expires_at)
  VALUES(v_nom.id,v_review.id,p_verified_owner_auth_user_id,
   p_approval_key,v_req.baseline_revision_id,v_req.baseline_line_count,
   v_req.baseline_snapshot_digest,p_expires_at) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object(
  'approval_grant_id',v_id::text,'nomination_id',v_nom.id::text,
  'scope','open_primary_case_and_import_attested_baseline',
  'expires_at',p_expires_at,
  'decision_recorded',false,'case_opened',false,'recorded_event',false,
  'replayed',v_prior.id IS NOT NULL);
END $fn$;

-- Exactly one single database transaction, on the signed nominated actor,
-- containing the two canonical v1 events and the independent approval record.
-- Neither the owner nor a machine credential can invoke as the distinct actor
-- without a genuine fresh GoTrue bearer verified by the isolated service.
CREATE FUNCTION us.carry_approve_and_open_primary_v3(
 p_verified_approver_auth_user_id uuid,p_nomination_id uuid,p_decision_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
 v_req us.carry_financial_open_requests_v3%ROWTYPE;
 v_grant us.carry_primary_open_approval_grants_v3%ROWTYPE;
 v_review us.carry_primary_review_disclosure_grants_v3%ROWTYPE;
 v_prior us.carry_primary_open_approval_decisions_v3%ROWTYPE;
 v_att jsonb; v_stream uuid; v_first uuid; v_second uuid;
 v_first_seq bigint;v_second_seq bigint;
 v_id uuid;
BEGIN
 IF p_verified_approver_auth_user_id IS NULL OR p_nomination_id IS NULL
 OR p_decision_key IS NULL OR length(btrim(p_decision_key)) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Signed independent decision required' USING ERRCODE='22023'; END IF;
 -- Serializes other approval attempts, owner G2 revocation and authority
 -- mutations for this nomination. First winner owns one canonical stream.
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3 n
 WHERE n.id=p_nomination_id
  AND n.nominee_auth_user_id=p_verified_approver_auth_user_id FOR UPDATE;
 IF v_nom.id IS NULL OR v_nom.owner_auth_user_id=p_verified_approver_auth_user_id
 OR v_nom.owner_person_entity_id=v_nom.nominee_person_entity_id
 OR NOT us.carry_primary_reviewer_identity_live_v3(v_nom.id)
 THEN RAISE EXCEPTION 'Independent verified Person unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_grant FROM us.carry_primary_open_approval_grants_v3 g
 WHERE g.nomination_id=v_nom.id AND g.scope='open_primary_case_and_import_attested_baseline'
 FOR SHARE;
 IF v_grant.id IS NULL OR v_grant.owner_auth_user_id<>v_nom.owner_auth_user_id
 THEN RAISE EXCEPTION 'No explicit owner opening authorization' USING ERRCODE='42501'; END IF;
 -- Successful replay has no side effect; it must match the same actor/grant/key.
 SELECT * INTO v_prior FROM us.carry_primary_open_approval_decisions_v3 d
 WHERE d.nomination_id=v_nom.id FOR SHARE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.approver_auth_user_id IS DISTINCT FROM p_verified_approver_auth_user_id
   OR v_prior.approver_person_entity_id IS DISTINCT FROM v_nom.nominee_person_entity_id
   OR v_prior.decision_key IS DISTINCT FROM p_decision_key
   OR v_prior.approval_grant_id IS DISTINCT FROM v_grant.id
  THEN RAISE EXCEPTION 'Conflicting independent approval' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('approval_decision_id',v_prior.id::text,
   'stream_id',v_prior.canonical_stream_id::text,
   'status','approved_primary_opened','event_count',2,'replayed',true);
 END IF;
 SELECT * INTO v_review FROM us.carry_primary_review_disclosure_grants_v3 g
 WHERE g.id=v_grant.attestation_grant_id AND g.nomination_id=v_nom.id
 AND g.expires_at>clock_timestamp() FOR SHARE;
 IF v_grant.expires_at<=clock_timestamp() OR v_review.id IS NULL
 OR EXISTS(SELECT 1 FROM us.carry_primary_review_disclosure_revocations_v3 x
   WHERE x.grant_id=v_review.id)
 THEN RAISE EXCEPTION 'Approval authority expired or revoked' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=v_nom.open_request_id AND r.owner_auth_user_id=v_nom.owner_auth_user_id
  AND r.case_kind='primary' AND r.disposition='pending_independent_approval'
 FOR UPDATE;
 IF v_req.id IS NULL OR EXISTS(
   SELECT 1 FROM us.carry_case_streams_v1 s WHERE s.financial_plan_id=v_req.plan_id)
 THEN RAISE EXCEPTION 'Existing or ineligible canonical Case' USING ERRCODE='42501'; END IF;
 v_att:=us.carry_read_primary_attestation_v3(p_verified_approver_auth_user_id,v_nom.id);
 IF v_att->>'baseline_snapshot_digest' IS DISTINCT FROM v_grant.baseline_snapshot_digest
  OR (v_att->>'baseline_line_count')::integer IS DISTINCT FROM v_grant.baseline_line_count
  OR v_grant.baseline_revision_id IS DISTINCT FROM v_req.baseline_revision_id
 THEN RAISE EXCEPTION 'Original adopted financial baseline changed'
  USING ERRCODE='42501'; END IF;
 -- This is the sole canonical financial stream, not a second financial store.
 INSERT INTO us.carry_case_streams_v1(owner_auth_user_id,stream_key,subject_kind,financial_plan_id)
 VALUES(v_req.owner_auth_user_id,'primary-financial:'||v_req.id::text,
        'financial_expectation',v_req.plan_id)
 RETURNING id INTO v_stream;
 SELECT ev.event_id,ev.event_sequence INTO v_first,v_first_seq
 FROM us.carry_append_event_v1(
  v_stream,'primary-open:'||v_req.id::text,'CASE_OPENED',NULL,'COMMITTED',
  'us:approved-open:'||v_nom.id::text,
  jsonb_build_object('question','Open primary Carry Case with approved, attested financial baseline'),
  1) ev;
 SELECT ev.event_id,ev.event_sequence INTO v_second,v_second_seq
 FROM us.carry_append_event_v1(
  v_stream,'primary-baseline:'||v_req.id::text,'BASELINE_IMPORTED',NULL,'COMMITTED',
  'us:approved-baseline:'||v_nom.id::text,
  jsonb_build_object('revision_id',v_req.baseline_revision_id::text),2) ev;
 IF v_first IS NULL OR v_second IS NULL OR v_first_seq<>1 OR v_second_seq<>2
 THEN RAISE EXCEPTION 'Canonical opening history incomplete' USING ERRCODE='42501'; END IF;
 INSERT INTO us.carry_primary_open_approval_decisions_v3(
  nomination_id,approval_grant_id,open_request_id,owner_auth_user_id,
  owner_person_entity_id,approver_auth_user_id,approver_person_entity_id,
  decision_key,baseline_revision_id,baseline_snapshot_digest,
  baseline_line_count,canonical_stream_id,case_opened_event_id,
  baseline_imported_event_id)
 VALUES(v_nom.id,v_grant.id,v_req.id,v_req.owner_auth_user_id,
  v_nom.owner_person_entity_id,p_verified_approver_auth_user_id,
  v_nom.nominee_person_entity_id,p_decision_key,v_req.baseline_revision_id,
  v_grant.baseline_snapshot_digest,v_grant.baseline_line_count,v_stream,
  v_first,v_second) RETURNING id INTO v_id;
 RETURN jsonb_build_object('approval_decision_id',v_id::text,
  'stream_id',v_stream::text,'status','approved_primary_opened',
  'event_count',2,'replayed',false);
END $fn$;

REVOKE ALL ON FUNCTION
 us.carry_authorize_primary_open_approval_v3(uuid,uuid,text,timestamptz),
 us.carry_approve_and_open_primary_v3(uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_authorize_primary_open_approval_v3(uuid,uuid,text,timestamptz)
 TO us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_approve_and_open_primary_v3(uuid,uuid,text)
 TO us_carry_backend;
-- No direct table INSERT or legacy appender permission gained by backend role.
COMMIT;
