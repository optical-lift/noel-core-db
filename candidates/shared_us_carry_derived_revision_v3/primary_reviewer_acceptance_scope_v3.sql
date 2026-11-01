-- HELD Gate G2: independent nominee acceptance + owner-scoped, expiring,
-- revocable opening-ATTESTATION-ONLY access. Not Case approval or disclosure
-- of raw financial lines. No new Person, no Ledger grant, no default Us route.
-- Depends on F primary request + G1 canonical Person nomination.
BEGIN;

CREATE TABLE us.carry_primary_reviewer_acceptances_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 nomination_id uuid NOT NULL UNIQUE REFERENCES us.carry_primary_reviewer_nominations_v3(id) ON DELETE RESTRICT,
 nominee_auth_user_id uuid NOT NULL,
 nominee_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 acceptance_key text NOT NULL CHECK (length(btrim(acceptance_key)) BETWEEN 8 AND 160),
 acceptance_scope text NOT NULL DEFAULT 'consider_opening_attestation'
   CHECK (acceptance_scope='consider_opening_attestation'),
 accepted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(nominee_auth_user_id,acceptance_key)
);
CREATE TABLE us.carry_primary_review_disclosure_grants_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 nomination_id uuid NOT NULL UNIQUE REFERENCES us.carry_primary_reviewer_nominations_v3(id) ON DELETE RESTRICT,
 acceptance_id uuid NOT NULL REFERENCES us.carry_primary_reviewer_acceptances_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL,
 grant_key text NOT NULL CHECK (length(btrim(grant_key)) BETWEEN 8 AND 160),
 review_scope text NOT NULL DEFAULT 'opening_attestation_only'
  CHECK (review_scope='opening_attestation_only'),
 granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 UNIQUE(owner_auth_user_id,grant_key),
 CHECK(expires_at>granted_at),
 CHECK(expires_at<=granted_at + interval '7 days')
);
CREATE TABLE us.carry_primary_review_disclosure_revocations_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 grant_id uuid NOT NULL UNIQUE REFERENCES us.carry_primary_review_disclosure_grants_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL,
 revoke_key text NOT NULL CHECK (length(btrim(revoke_key)) BETWEEN 8 AND 160),
 reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 10 AND 400),
 revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(owner_auth_user_id,revoke_key)
);

CREATE TRIGGER carry_reviewer_acceptance_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_reviewer_acceptances_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
CREATE TRIGGER carry_reviewer_grant_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_review_disclosure_grants_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
CREATE TRIGGER carry_reviewer_revocation_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_review_disclosure_revocations_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();

ALTER TABLE us.carry_primary_reviewer_acceptances_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_reviewer_acceptances_v3 FORCE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_review_disclosure_grants_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_review_disclosure_grants_v3 FORCE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_review_disclosure_revocations_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_review_disclosure_revocations_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_primary_reviewer_acceptances_v3,
 us.carry_primary_review_disclosure_grants_v3,
 us.carry_primary_review_disclosure_revocations_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

-- Shared private source identity check: both roles have canonical, distinct,
-- unambiguous active Reality Person/Auth binding at the time of each action.
-- Nominations with retired/disputed Persons are not reusable credentials.
CREATE FUNCTION us.carry_primary_reviewer_identity_live_v3(
 p_nomination_id uuid
) RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='' AS $fn$
DECLARE v us.carry_primary_reviewer_nominations_v3%ROWTYPE;
        n integer;
BEGIN
 SELECT * INTO v FROM us.carry_primary_reviewer_nominations_v3
  WHERE id=p_nomination_id FOR SHARE;
 IF v.id IS NULL OR v.owner_auth_user_id=v.nominee_auth_user_id
  OR v.owner_person_entity_id=v.nominee_person_entity_id THEN RETURN false; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM reality.auth_person_bindings b
   JOIN reality.entities e ON e.id=b.person_entity_id
   JOIN auth.users u ON u.id=b.auth_user_id
   WHERE b.auth_user_id=v.owner_auth_user_id
    AND b.person_entity_id=v.owner_person_entity_id
    AND b.binding_state='active' AND b.retired_at IS NULL
    AND e.entity_kind='person' AND e.identity_state='canonical'
    AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
    AND (u.banned_until IS NULL OR u.banned_until<=pg_catalog.now())
   FOR SHARE OF b,e,u
 ) THEN RETURN false; END IF;
 IF NOT EXISTS (
   SELECT 1 FROM reality.auth_person_bindings b
   JOIN reality.entities e ON e.id=b.person_entity_id
   JOIN auth.users u ON u.id=b.auth_user_id
   WHERE b.id=v.nominee_binding_id
    AND b.auth_user_id=v.nominee_auth_user_id
    AND b.person_entity_id=v.nominee_person_entity_id
    AND b.binding_state='active' AND b.retired_at IS NULL
    AND e.entity_kind='person' AND e.identity_state='canonical'
    AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
    AND (u.banned_until IS NULL OR u.banned_until<=pg_catalog.now())
   FOR SHARE OF b,e,u
 ) THEN RETURN false; END IF;
 SELECT count(*)::integer INTO n FROM reality.auth_person_bindings b
 WHERE b.binding_state='active' AND b.retired_at IS NULL AND (
  b.person_entity_id=v.owner_person_entity_id OR
  b.person_entity_id=v.nominee_person_entity_id OR
  b.auth_user_id=v.owner_auth_user_id OR
  b.auth_user_id=v.nominee_auth_user_id);
 RETURN n=2;
END $fn$;
REVOKE ALL ON FUNCTION us.carry_primary_reviewer_identity_live_v3(uuid)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

-- Nominee supplies their own real, newly verified GoTrue bearer to private
-- service; does not need or obtain a roster or the financial Case content.
CREATE FUNCTION us.carry_accept_primary_reviewer_v3(
 p_verified_nominee_auth_user_id uuid,
 p_nomination_id uuid,
 p_acceptance_key text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
        v_req us.carry_financial_open_requests_v3%ROWTYPE;
        v_prior us.carry_primary_reviewer_acceptances_v3%ROWTYPE;
        v_id uuid;
BEGIN
 IF p_verified_nominee_auth_user_id IS NULL OR p_nomination_id IS NULL
    OR p_acceptance_key IS NULL OR length(btrim(p_acceptance_key)) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Exact nominee acceptance required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3
 WHERE id=p_nomination_id AND nominee_auth_user_id=p_verified_nominee_auth_user_id
  AND nomination_state='pending_nominee_acceptance'
 FOR UPDATE;
 IF v_nom.id IS NULL THEN RAISE EXCEPTION 'Nomination unavailable' USING ERRCODE='42501'; END IF;
 IF NOT us.carry_primary_reviewer_identity_live_v3(v_nom.id) THEN
   RAISE EXCEPTION 'Current canonical Person binding required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=v_nom.open_request_id AND r.owner_auth_user_id=v_nom.owner_auth_user_id
  AND r.disposition='pending_independent_approval' AND r.case_kind='primary'
 FOR SHARE;
 IF v_req.id IS NULL OR EXISTS(
    SELECT 1 FROM us.carry_case_streams_v1 s WHERE s.financial_plan_id=v_req.plan_id)
 THEN RAISE EXCEPTION 'Pending Case not eligible for acceptance'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_primary_reviewer_acceptances_v3 a
 WHERE a.nomination_id=v_nom.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
   IF v_prior.acceptance_key IS DISTINCT FROM p_acceptance_key
      OR v_prior.nominee_person_entity_id IS DISTINCT FROM v_nom.nominee_person_entity_id
      OR v_prior.nominee_auth_user_id IS DISTINCT FROM p_verified_nominee_auth_user_id
   THEN RAISE EXCEPTION 'Conflicting nominee acceptance' USING ERRCODE='23505'; END IF;
   v_id:=v_prior.id;
 ELSE
  INSERT INTO us.carry_primary_reviewer_acceptances_v3(
   nomination_id,nominee_auth_user_id,nominee_person_entity_id,acceptance_key)
  VALUES(v_nom.id,p_verified_nominee_auth_user_id,
         v_nom.nominee_person_entity_id,p_acceptance_key)
  RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object(
  'acceptance_id',v_id::text,'nomination_id',v_nom.id::text,
  'state','accepted_pending_owner_disclosure_grant',
  'financial_access_granted',false,'approval_authority_granted',false,
  'case_opened',false,'recorded_event',false,
  'replayed',v_prior.id IS NOT NULL);
END $fn$;

CREATE FUNCTION us.carry_grant_primary_attestation_v3(
 p_verified_owner_auth_user_id uuid, p_nomination_id uuid,
 p_grant_key text, p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
        v_req us.carry_financial_open_requests_v3%ROWTYPE;
        v_accept us.carry_primary_reviewer_acceptances_v3%ROWTYPE;
        v_prior us.carry_primary_review_disclosure_grants_v3%ROWTYPE;
        v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_nomination_id IS NULL
    OR p_grant_key IS NULL OR length(btrim(p_grant_key)) NOT BETWEEN 8 AND 160
    OR p_expires_at IS NULL
 THEN RAISE EXCEPTION 'Exact owner-scoped expiry required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3
 WHERE id=p_nomination_id AND owner_auth_user_id=p_verified_owner_auth_user_id FOR UPDATE;
 IF v_nom.id IS NULL OR NOT us.carry_primary_reviewer_identity_live_v3(v_nom.id) THEN
  RAISE EXCEPTION 'Nominated canonical Persons unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=v_nom.open_request_id AND r.owner_auth_user_id=p_verified_owner_auth_user_id
  AND r.case_kind='primary' AND r.disposition='pending_independent_approval'
 FOR SHARE;
 IF v_req.id IS NULL OR EXISTS(
  SELECT 1 FROM us.carry_case_streams_v1 s WHERE s.financial_plan_id=v_req.plan_id)
 THEN RAISE EXCEPTION 'Pending financial Case not available' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_accept FROM us.carry_primary_reviewer_acceptances_v3 a
 WHERE a.nomination_id=v_nom.id AND a.nominee_auth_user_id=v_nom.nominee_auth_user_id
 FOR SHARE;
 IF v_accept.id IS NULL THEN RAISE EXCEPTION 'Nominee has not independently accepted'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_primary_review_disclosure_grants_v3 g
 WHERE g.nomination_id=v_nom.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.grant_key IS DISTINCT FROM p_grant_key
   OR v_prior.expires_at IS DISTINCT FROM p_expires_at
   OR v_prior.acceptance_id IS DISTINCT FROM v_accept.id
   OR EXISTS(SELECT 1 FROM us.carry_primary_review_disclosure_revocations_v3 x
             WHERE x.grant_id=v_prior.id)
  THEN RAISE EXCEPTION 'Conflicting or revoked review scope' USING ERRCODE='23505'; END IF;
  v_id:=v_prior.id;
 ELSE
  IF p_expires_at<=(pg_catalog.now()+interval '5 minutes')
   OR p_expires_at>(pg_catalog.now()+interval '7 days')
  THEN RAISE EXCEPTION 'Review expiry must be between 5 minutes and 7 days'
    USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_primary_review_disclosure_grants_v3(
   nomination_id,acceptance_id,owner_auth_user_id,grant_key,expires_at)
  VALUES(v_nom.id,v_accept.id,p_verified_owner_auth_user_id,
         p_grant_key,p_expires_at) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object(
  'grant_id',v_id::text,'nomination_id',v_nom.id::text,
  'scope','opening_attestation_only','expires_at',p_expires_at,
  'financial_lines_visible',false,'event_approval_allowed',false,
  'case_opened',false,'recorded_event',false,
  'replayed',v_prior.id IS NOT NULL);
END $fn$;

CREATE FUNCTION us.carry_revoke_primary_attestation_v3(
 p_verified_owner_auth_user_id uuid, p_nomination_id uuid,
 p_revoke_key text, p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
        v_grant us.carry_primary_review_disclosure_grants_v3%ROWTYPE;
        v_prior us.carry_primary_review_disclosure_revocations_v3%ROWTYPE;
        v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_nomination_id IS NULL
  OR p_revoke_key IS NULL OR length(btrim(p_revoke_key)) NOT BETWEEN 8 AND 160
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 400
 THEN RAISE EXCEPTION 'Exact owner revocation and reason required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3 n
 WHERE n.id=p_nomination_id AND n.owner_auth_user_id=p_verified_owner_auth_user_id
 FOR UPDATE;
 IF v_nom.id IS NULL THEN RAISE EXCEPTION 'Private nomination unavailable'
   USING ERRCODE='42501'; END IF;
 -- Revocation remains possible even after nominee retires or grant expires.
 SELECT * INTO v_grant FROM us.carry_primary_review_disclosure_grants_v3 g
 WHERE g.nomination_id=v_nom.id AND g.owner_auth_user_id=p_verified_owner_auth_user_id
 FOR UPDATE;
 IF v_grant.id IS NULL THEN RAISE EXCEPTION 'No exact disclosure grant'
   USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_primary_review_disclosure_revocations_v3 r
 WHERE r.grant_id=v_grant.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.revoke_key IS DISTINCT FROM p_revoke_key
    OR v_prior.reason IS DISTINCT FROM p_reason
  THEN RAISE EXCEPTION 'Conflicting revocation' USING ERRCODE='23505'; END IF;
  v_id:=v_prior.id;
 ELSE
  INSERT INTO us.carry_primary_review_disclosure_revocations_v3(
   grant_id,owner_auth_user_id,revoke_key,reason)
  VALUES(v_grant.id,p_verified_owner_auth_user_id,p_revoke_key,p_reason)
  RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object(
  'revocation_id',v_id::text,'nomination_id',v_nom.id::text,
  'review_access','revoked','event_approval_allowed',false,
  'replayed',v_prior.id IS NOT NULL);
END $fn$;

-- Only this explicitly granted, accepted, nonexpired, nonrevoked, exact
-- nomination may see a bounded source-attestation summary. No plan name,
-- source text, line values, bank amounts, user IDs or event payloads.
CREATE FUNCTION us.carry_read_primary_attestation_v3(
 p_verified_nominee_auth_user_id uuid, p_nomination_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path='' AS $fn$
DECLARE v_nom us.carry_primary_reviewer_nominations_v3%ROWTYPE;
        v_req us.carry_financial_open_requests_v3%ROWTYPE;
        v_accept us.carry_primary_reviewer_acceptances_v3%ROWTYPE;
        v_grant us.carry_primary_review_disclosure_grants_v3%ROWTYPE;
        v_count integer; v_digest text;
BEGIN
 IF p_verified_nominee_auth_user_id IS NULL OR p_nomination_id IS NULL
 THEN RAISE EXCEPTION 'Exact signed nominee and nomination required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_nom FROM us.carry_primary_reviewer_nominations_v3 n
 WHERE n.id=p_nomination_id AND n.nominee_auth_user_id=p_verified_nominee_auth_user_id
 FOR SHARE;
 IF v_nom.id IS NULL OR NOT us.carry_primary_reviewer_identity_live_v3(v_nom.id)
 THEN RAISE EXCEPTION 'Private reviewer authority unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_accept FROM us.carry_primary_reviewer_acceptances_v3 a
 WHERE a.nomination_id=v_nom.id AND a.nominee_auth_user_id=p_verified_nominee_auth_user_id
 FOR SHARE;
 SELECT * INTO v_grant FROM us.carry_primary_review_disclosure_grants_v3 g
 WHERE g.nomination_id=v_nom.id AND g.acceptance_id=v_accept.id
  AND g.review_scope='opening_attestation_only' AND g.expires_at>pg_catalog.now()
 FOR SHARE;
 IF v_accept.id IS NULL OR v_grant.id IS NULL
  OR EXISTS(SELECT 1 FROM us.carry_primary_review_disclosure_revocations_v3 x
            WHERE x.grant_id=v_grant.id)
 THEN RAISE EXCEPTION 'Review grant missing, expired or revoked' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=v_nom.open_request_id AND r.owner_auth_user_id=v_nom.owner_auth_user_id
 AND r.case_kind='primary' AND r.disposition='pending_independent_approval'
 FOR SHARE;
 IF v_req.id IS NULL OR EXISTS(SELECT 1 FROM us.carry_case_streams_v1 s
   WHERE s.financial_plan_id=v_req.plan_id)
 THEN RAISE EXCEPTION 'Case no longer eligible for attestation'
   USING ERRCODE='42501'; END IF;
 -- Recompute exact original financial baseline, refusing stale witness
 -- instead of exposing or quietly repairing the financial source.
 SELECT count(*)::int,
  pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
   coalesce(jsonb_agg(jsonb_build_array(
    l.period_month,l.line_key,l.economic_scope,l.subject_key,l.money_role,
    l.expectation_state,l.forecast_amount,l.currency,l.explanation)
    ORDER BY l.period_month,l.line_key),'[]'::jsonb)::text,'UTF8'),
   'sha256'),'hex')
 INTO v_count,v_digest FROM us.financial_expectation_lines l
 WHERE l.revision_id=v_req.baseline_revision_id
  AND l.owner_auth_user_id=v_nom.owner_auth_user_id;
 IF v_count<>v_req.baseline_line_count
  OR v_digest<>v_req.baseline_snapshot_digest
  OR NOT EXISTS(SELECT 1 FROM us.financial_expectation_revisions r
    WHERE r.id=v_req.baseline_revision_id
      AND r.plan_id=v_req.plan_id
      AND r.owner_auth_user_id=v_nom.owner_auth_user_id
      AND r.revision=1 AND r.standing='adopted')
 THEN RAISE EXCEPTION 'Original financial attestation no longer matches'
   USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'nomination_id',v_nom.id::text,'case_open_request_id',v_req.id::text,
  'scope','opening_attestation_only',
  'baseline_line_count',v_req.baseline_line_count,
  'baseline_snapshot_digest',v_req.baseline_snapshot_digest,
  'expires_at',v_grant.expires_at,
  'financial_lines_visible',false,'event_approval_allowed',false,
  'case_opened',false,'recorded_event',false);
END $fn$;

REVOKE ALL ON FUNCTION
 us.carry_accept_primary_reviewer_v3(uuid,uuid,text),
 us.carry_grant_primary_attestation_v3(uuid,uuid,text,timestamptz),
 us.carry_revoke_primary_attestation_v3(uuid,uuid,text,text),
 us.carry_read_primary_attestation_v3(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_accept_primary_reviewer_v3(uuid,uuid,text)
 TO us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_grant_primary_attestation_v3(uuid,uuid,text,timestamptz)
 TO us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_revoke_primary_attestation_v3(uuid,uuid,text,text)
 TO us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_read_primary_attestation_v3(uuid,uuid)
 TO us_carry_backend;
-- No adoption, ordinary append, owner table or reviewer full-line SELECT.
COMMIT;
