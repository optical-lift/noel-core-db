-- HELD P1C. Apply after G3, P0, P1A and P1B on a disposable clone.
-- The P0 revoked owner-only adoption stays private to this source transaction.
BEGIN;

CREATE TABLE us.carry_revision_proposals_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 stream_id uuid NOT NULL REFERENCES us.carry_case_streams_v1(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 proposal_key text NOT NULL CHECK(length(btrim(proposal_key)) BETWEEN 8 AND 160),
 source_cutoff bigint NOT NULL CHECK(source_cutoff>=3),
 baseline_revision_id uuid NOT NULL REFERENCES us.financial_expectation_revisions(id) ON DELETE RESTRICT,
 candidate_digest text NOT NULL CHECK(candidate_digest ~ '^[0-9a-f]{64}$'),
 line_count integer NOT NULL CHECK(line_count>0),
 projection_version text NOT NULL,
 envelope_digest text NOT NULL CHECK(envelope_digest ~ '^[0-9a-f]{64}$'),
 proposed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(stream_id,proposal_key)
);
CREATE TABLE us.carry_revision_review_grants_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 proposal_id uuid NOT NULL REFERENCES us.carry_revision_proposals_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 reviewer_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 grant_key text NOT NULL CHECK(length(btrim(grant_key)) BETWEEN 8 AND 160),
 granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 UNIQUE(proposal_id,reviewer_person_entity_id), UNIQUE(owner_auth_user_id,grant_key),
 CHECK(expires_at>granted_at AND expires_at<=granted_at+interval '7 days')
);
CREATE TABLE us.carry_revision_review_revocations_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 grant_id uuid NOT NULL UNIQUE REFERENCES us.carry_revision_review_grants_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 revoke_key text NOT NULL CHECK(length(btrim(revoke_key)) BETWEEN 8 AND 160),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 400),
 revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(owner_auth_user_id,revoke_key)
);
CREATE TABLE us.carry_revision_approved_decisions_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 proposal_id uuid NOT NULL UNIQUE REFERENCES us.carry_revision_proposals_v3(id) ON DELETE RESTRICT,
 grant_id uuid NOT NULL REFERENCES us.carry_revision_review_grants_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 approver_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 approver_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 decision_key text NOT NULL CHECK(length(btrim(decision_key)) BETWEEN 8 AND 160),
 envelope_digest text NOT NULL CHECK(envelope_digest ~ '^[0-9a-f]{64}$'),
 source_cutoff bigint NOT NULL,
 revision_id uuid NOT NULL UNIQUE REFERENCES us.financial_expectation_revisions(id) ON DELETE RESTRICT,
 seal_event_id uuid NOT NULL UNIQUE REFERENCES us.carry_case_events_v1(id) ON DELETE RESTRICT,
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(approver_auth_user_id,decision_key),
 CHECK(owner_auth_user_id<>approver_auth_user_id),
 CHECK(owner_person_entity_id<>approver_person_entity_id)
);
DO $immutability$
DECLARE v_table text;
BEGIN
 FOREACH v_table IN ARRAY ARRAY[
  'carry_revision_proposals_v3','carry_revision_review_grants_v3',
  'carry_revision_review_revocations_v3','carry_revision_approved_decisions_v3'] LOOP
  EXECUTE pg_catalog.format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON us.%I FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1()',v_table||'_immutable',v_table);
  EXECUTE pg_catalog.format('ALTER TABLE us.%I ENABLE ROW LEVEL SECURITY',v_table);
  EXECUTE pg_catalog.format('ALTER TABLE us.%I FORCE ROW LEVEL SECURITY',v_table);
  EXECUTE pg_catalog.format('REVOKE ALL ON us.%I FROM PUBLIC,anon,authenticated,service_role,us_carry_backend',v_table);
 END LOOP;
END $immutability$;

CREATE FUNCTION us.carry_propose_revision_v3(
 p_verified_owner_auth_user_id uuid,p_stream_id uuid,p_proposal_key text,p_source_cutoff bigint
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_person uuid;v_stream us.carry_case_streams_v1%ROWTYPE;
 v_old us.carry_revision_proposals_v3%ROWTYPE;v_candidate jsonb;
 v_digest text;v_id uuid;v_last bigint;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_stream_id IS NULL
  OR p_proposal_key IS NULL OR length(btrim(p_proposal_key)) NOT BETWEEN 8 AND 160
  OR p_source_cutoff IS NULL OR p_source_cutoff<3
 THEN RAISE EXCEPTION 'Exact owner revision proposal required' USING ERRCODE='22023'; END IF;
 v_person:=us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id);
 SELECT * INTO v_stream FROM us.carry_case_streams_v1 s
 WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_verified_owner_auth_user_id
  AND s.subject_kind='financial_expectation' FOR UPDATE;
 IF v_person IS NULL OR v_stream.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
  WHERE d.canonical_stream_id=v_stream.id AND d.owner_auth_user_id=p_verified_owner_auth_user_id
   AND d.owner_person_entity_id=v_person)
 THEN RAISE EXCEPTION 'Approved original Case unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_revision_proposals_v3 p
  WHERE p.stream_id=p_stream_id AND p.proposal_key=p_proposal_key FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.owner_auth_user_id IS DISTINCT FROM p_verified_owner_auth_user_id
   OR v_old.source_cutoff IS DISTINCT FROM p_source_cutoff
   OR v_old.owner_person_entity_id IS DISTINCT FROM v_person
  THEN RAISE EXCEPTION 'Conflicting proposal key' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('proposal_id',v_old.id::text,'candidate_digest',v_old.candidate_digest,
   'envelope_digest',v_old.envelope_digest,'source_cutoff',v_old.source_cutoff,
   'revision_created',false,'replayed',true);
 END IF;
 SELECT max(e.stream_sequence) INTO v_last FROM us.carry_case_events_v1 e WHERE e.stream_id=p_stream_id;
 IF v_last IS DISTINCT FROM p_source_cutoff THEN
  RAISE EXCEPTION 'Source event cutoff changed' USING ERRCODE='40001'; END IF;
 v_candidate:=us.carry_candidate_core_v3(p_verified_owner_auth_user_id,p_stream_id,p_source_cutoff);
 IF (v_candidate->>'line_count')::integer<=0 THEN
  RAISE EXCEPTION 'Empty derived revision' USING ERRCODE='42501'; END IF;
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(p_stream_id,p_source_cutoff,v_candidate->>'baseline_revision_id',
   v_candidate->>'candidate_digest',v_candidate->>'line_count',
   v_candidate->>'projection_version')::text,'UTF8'),'sha256'),'hex');
 INSERT INTO us.carry_revision_proposals_v3(stream_id,owner_auth_user_id,
  owner_person_entity_id,proposal_key,source_cutoff,baseline_revision_id,
  candidate_digest,line_count,projection_version,envelope_digest)
 VALUES(p_stream_id,p_verified_owner_auth_user_id,v_person,p_proposal_key,
  p_source_cutoff,(v_candidate->>'baseline_revision_id')::uuid,
  v_candidate->>'candidate_digest',(v_candidate->>'line_count')::integer,
  v_candidate->>'projection_version',v_digest) RETURNING id INTO v_id;
 RETURN jsonb_build_object('proposal_id',v_id::text,'candidate_digest',v_candidate->>'candidate_digest',
  'envelope_digest',v_digest,'source_cutoff',p_source_cutoff,
  'revision_created',false,'replayed',false);
END $fn$;

CREATE FUNCTION us.carry_grant_revision_review_v3(
 p_verified_owner_auth_user_id uuid,p_proposal_id uuid,p_reviewer_person_id uuid,
 p_grant_key text,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_revision_proposals_v3%ROWTYPE;
 v_old us.carry_revision_review_grants_v3%ROWTYPE;v_reviewer uuid;v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_proposal_id IS NULL
  OR p_reviewer_person_id IS NULL OR p_grant_key IS NULL
  OR length(btrim(p_grant_key)) NOT BETWEEN 8 AND 160 OR p_expires_at IS NULL
 THEN RAISE EXCEPTION 'Exact individual reviewer grant required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_p FROM us.carry_revision_proposals_v3 p
  WHERE p.id=p_proposal_id AND p.owner_auth_user_id=p_verified_owner_auth_user_id FOR UPDATE;
 IF v_p.id IS NULL OR us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id)
  IS DISTINCT FROM v_p.owner_person_entity_id
  OR EXISTS(SELECT 1 FROM us.carry_revision_approved_decisions_v3 d WHERE d.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'Owner proposal unavailable' USING ERRCODE='42501'; END IF;
 SELECT b.auth_user_id INTO v_reviewer FROM reality.auth_person_bindings b
 WHERE b.person_entity_id=p_reviewer_person_id AND b.binding_state='active'
  AND b.retired_at IS NULL FOR SHARE;
 IF v_reviewer IS NULL OR v_reviewer=p_verified_owner_auth_user_id
  OR p_reviewer_person_id=v_p.owner_person_entity_id
  OR us.carry_live_canonical_person_v3(v_reviewer) IS DISTINCT FROM p_reviewer_person_id
 THEN RAISE EXCEPTION 'Distinct canonical reviewer required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_revision_review_grants_v3 g
  WHERE g.proposal_id=v_p.id AND g.reviewer_person_entity_id=p_reviewer_person_id FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.grant_key IS DISTINCT FROM p_grant_key OR v_old.expires_at IS DISTINCT FROM p_expires_at
   OR v_old.reviewer_auth_user_id IS DISTINCT FROM v_reviewer
  THEN RAISE EXCEPTION 'Conflicting reviewer grant' USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  IF p_expires_at<=clock_timestamp()+interval '5 minutes'
   OR p_expires_at>clock_timestamp()+interval '7 days'
  THEN RAISE EXCEPTION 'Review expiry outside accepted bounds' USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_revision_review_grants_v3(proposal_id,owner_auth_user_id,
   reviewer_person_entity_id,reviewer_auth_user_id,grant_key,expires_at)
  VALUES(v_p.id,p_verified_owner_auth_user_id,p_reviewer_person_id,v_reviewer,p_grant_key,p_expires_at)
  RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('grant_id',v_id::text,'proposal_id',v_p.id::text,
  'scope','this_derived_revision_only','expires_at',p_expires_at,
  'full_case_visible',false,'replayed',v_old.id IS NOT NULL);
END $fn$;

CREATE FUNCTION us.carry_revoke_revision_review_v3(
 p_verified_owner_auth_user_id uuid,p_grant_id uuid,p_revoke_key text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_g us.carry_revision_review_grants_v3%ROWTYPE;
 v_old us.carry_revision_review_revocations_v3%ROWTYPE;v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_grant_id IS NULL
  OR p_revoke_key IS NULL OR length(btrim(p_revoke_key)) NOT BETWEEN 8 AND 160
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 400
 THEN RAISE EXCEPTION 'Exact owner revocation required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_g FROM us.carry_revision_review_grants_v3 g
  WHERE g.id=p_grant_id AND g.owner_auth_user_id=p_verified_owner_auth_user_id FOR UPDATE;
 IF v_g.id IS NULL OR us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id) IS NULL
 THEN RAISE EXCEPTION 'Review grant unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_revision_review_revocations_v3 x
  WHERE x.grant_id=v_g.id FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.revoke_key IS DISTINCT FROM p_revoke_key OR v_old.reason IS DISTINCT FROM p_reason
  THEN RAISE EXCEPTION 'Conflicting revocation' USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  INSERT INTO us.carry_revision_review_revocations_v3(grant_id,owner_auth_user_id,revoke_key,reason)
  VALUES(v_g.id,p_verified_owner_auth_user_id,p_revoke_key,p_reason) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('grant_id',v_g.id::text,'state','revoked',
  'replayed',v_old.id IS NOT NULL);
END $fn$;

CREATE FUNCTION us.carry_read_revision_review_packet_v3(
 p_verified_reviewer_auth_user_id uuid,p_proposal_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_revision_proposals_v3%ROWTYPE;
 v_g us.carry_revision_review_grants_v3%ROWTYPE;v_candidate jsonb;
BEGIN
 SELECT * INTO v_p FROM us.carry_revision_proposals_v3 p WHERE p.id=p_proposal_id FOR SHARE;
 IF v_p.id IS NULL OR us.carry_live_canonical_person_v3(v_p.owner_auth_user_id)
  IS DISTINCT FROM v_p.owner_person_entity_id
 THEN RAISE EXCEPTION 'Revision review unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_g FROM us.carry_revision_review_grants_v3 g
  WHERE g.proposal_id=v_p.id AND g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
   AND g.expires_at>clock_timestamp() FOR SHARE;
 IF v_g.id IS NULL OR v_g.reviewer_person_entity_id=v_p.owner_person_entity_id
  OR us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id)
   IS DISTINCT FROM v_g.reviewer_person_entity_id
  OR EXISTS(SELECT 1 FROM us.carry_revision_review_revocations_v3 x WHERE x.grant_id=v_g.id)
  OR EXISTS(SELECT 1 FROM us.carry_revision_approved_decisions_v3 d WHERE d.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'Current exact review grant required' USING ERRCODE='42501'; END IF;
 v_candidate:=us.carry_candidate_core_v3(v_p.owner_auth_user_id,v_p.stream_id,v_p.source_cutoff);
 IF v_candidate->>'candidate_digest' IS DISTINCT FROM v_p.candidate_digest
  OR (v_candidate->>'baseline_revision_id')::uuid IS DISTINCT FROM v_p.baseline_revision_id
  OR (v_candidate->>'line_count')::integer IS DISTINCT FROM v_p.line_count
 THEN RAISE EXCEPTION 'Revision source changed' USING ERRCODE='40001'; END IF;
 RETURN jsonb_build_object('proposal_id',v_p.id::text,'source_cutoff',v_p.source_cutoff,
  'candidate_digest',v_p.candidate_digest,'envelope_digest',v_p.envelope_digest,
  'projection_version',v_p.projection_version,'lines',v_candidate->'lines',
  'causal_events',v_candidate->'causal_events','expires_at',v_g.expires_at,
  'scope','this_derived_revision_only','full_case_visible',false);
END $fn$;

CREATE FUNCTION us.carry_approve_revision_v3(
 p_verified_reviewer_auth_user_id uuid,p_proposal_id uuid,p_decision_key text,
 p_expected_envelope_digest text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_revision_proposals_v3%ROWTYPE;
 v_g us.carry_revision_review_grants_v3%ROWTYPE;
 v_prior us.carry_revision_approved_decisions_v3%ROWTYPE;
 v_candidate jsonb;v_digest text;v_last bigint;v_adopt record;v_id uuid;
BEGIN
 IF p_verified_reviewer_auth_user_id IS NULL OR p_proposal_id IS NULL
  OR p_decision_key IS NULL OR length(btrim(p_decision_key)) NOT BETWEEN 8 AND 160
  OR p_expected_envelope_digest IS NULL OR p_expected_envelope_digest !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Exact signed approval required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_p FROM us.carry_revision_proposals_v3 p WHERE p.id=p_proposal_id FOR UPDATE;
 IF v_p.id IS NULL OR v_p.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
 THEN RAISE EXCEPTION 'Exact revision proposal unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_revision_approved_decisions_v3 d
  WHERE d.proposal_id=v_p.id FOR SHARE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.approver_auth_user_id IS DISTINCT FROM p_verified_reviewer_auth_user_id
   OR v_prior.decision_key IS DISTINCT FROM p_decision_key
   OR v_prior.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
  THEN RAISE EXCEPTION 'Different decision already recorded' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('decision_id',v_prior.id::text,'revision_id',v_prior.revision_id::text,
   'seal_event_id',v_prior.seal_event_id::text,'state','approved_revision_sealed','replayed',true);
 END IF;
 SELECT * INTO v_g FROM us.carry_revision_review_grants_v3 g
  WHERE g.proposal_id=v_p.id AND g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
   AND g.expires_at>clock_timestamp() FOR SHARE;
 IF v_g.id IS NULL OR EXISTS(SELECT 1 FROM us.carry_revision_review_revocations_v3 x WHERE x.grant_id=v_g.id)
  OR us.carry_live_canonical_person_v3(v_p.owner_auth_user_id)
   IS DISTINCT FROM v_p.owner_person_entity_id
  OR us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id)
   IS DISTINCT FROM v_g.reviewer_person_entity_id
  OR v_p.owner_person_entity_id=v_g.reviewer_person_entity_id
  OR NOT EXISTS(SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
   WHERE d.canonical_stream_id=v_p.stream_id AND d.owner_auth_user_id=v_p.owner_auth_user_id
    AND d.owner_person_entity_id=v_p.owner_person_entity_id)
 THEN RAISE EXCEPTION 'Independent current reviewer authority required' USING ERRCODE='42501'; END IF;
 SELECT max(e.stream_sequence) INTO v_last FROM us.carry_case_events_v1 e
  WHERE e.stream_id=v_p.stream_id;
 IF v_last IS DISTINCT FROM v_p.source_cutoff THEN
  RAISE EXCEPTION 'Source cutoff changed' USING ERRCODE='40001'; END IF;
 v_candidate:=us.carry_candidate_core_v3(v_p.owner_auth_user_id,v_p.stream_id,v_p.source_cutoff);
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(v_p.stream_id,v_p.source_cutoff,v_candidate->>'baseline_revision_id',
   v_candidate->>'candidate_digest',v_candidate->>'line_count',
   v_candidate->>'projection_version')::text,'UTF8'),'sha256'),'hex');
 IF v_candidate->>'candidate_digest' IS DISTINCT FROM v_p.candidate_digest
  OR (v_candidate->>'baseline_revision_id')::uuid IS DISTINCT FROM v_p.baseline_revision_id
  OR (v_candidate->>'line_count')::integer IS DISTINCT FROM v_p.line_count
  OR v_candidate->>'projection_version' IS DISTINCT FROM v_p.projection_version
  OR v_digest IS DISTINCT FROM v_p.envelope_digest
 THEN RAISE EXCEPTION 'Source-derived review changed' USING ERRCODE='40001'; END IF;
 -- P0 revoked this historical writer from every client role. The definer can
 -- invoke it internally; all writes and decision below are one transaction.
 SELECT * INTO v_adopt FROM us.carry_adopt_derived_revision_v3(
  v_p.owner_auth_user_id,v_p.stream_id,'approved-revision:'||v_p.id::text,
  v_p.source_cutoff,v_p.candidate_digest);
 IF v_adopt.revision_id IS NULL OR v_adopt.replayed THEN
  RAISE EXCEPTION 'Revision source seal unavailable' USING ERRCODE='23514'; END IF;
 INSERT INTO us.carry_revision_approved_decisions_v3(proposal_id,grant_id,
  owner_auth_user_id,owner_person_entity_id,approver_auth_user_id,
  approver_person_entity_id,decision_key,envelope_digest,source_cutoff,
  revision_id,seal_event_id)
 VALUES(v_p.id,v_g.id,v_p.owner_auth_user_id,v_p.owner_person_entity_id,
  p_verified_reviewer_auth_user_id,v_g.reviewer_person_entity_id,
  p_decision_key,v_p.envelope_digest,v_p.source_cutoff,
  v_adopt.revision_id,v_adopt.seal_event_id) RETURNING id INTO v_id;
 RETURN jsonb_build_object('decision_id',v_id::text,'revision_id',v_adopt.revision_id::text,
  'seal_event_id',v_adopt.seal_event_id::text,'state','approved_revision_sealed','replayed',false);
END $fn$;

REVOKE ALL ON FUNCTION
 us.carry_propose_revision_v3(uuid,uuid,text,bigint),
 us.carry_grant_revision_review_v3(uuid,uuid,uuid,text,timestamptz),
 us.carry_revoke_revision_review_v3(uuid,uuid,text,text),
 us.carry_read_revision_review_packet_v3(uuid,uuid),
 us.carry_approve_revision_v3(uuid,uuid,text,text)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION
 us.carry_propose_revision_v3(uuid,uuid,text,bigint),
 us.carry_grant_revision_review_v3(uuid,uuid,uuid,text,timestamptz),
 us.carry_revoke_revision_review_v3(uuid,uuid,text,text),
 us.carry_read_revision_review_packet_v3(uuid,uuid),
 us.carry_approve_revision_v3(uuid,uuid,text,text)
 TO us_carry_backend;
COMMIT;
