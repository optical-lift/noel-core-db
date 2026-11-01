-- HELD P1B: bounded proposal queues and immutable decline/owner withdrawal.
-- Apply only after P0 + G3 + P1A source. Not a production migration.
-- Source owns disposition and privileges; Us is merely signed transport.
BEGIN;
CREATE TABLE us.carry_ordinary_dispositions_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 proposal_id uuid NOT NULL UNIQUE REFERENCES us.carry_ordinary_proposals_v3(id) ON DELETE RESTRICT,
 disposition text NOT NULL CHECK(disposition IN ('declined','withdrawn')),
 actor_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 grant_id uuid REFERENCES us.carry_ordinary_review_grants_v3(id) ON DELETE RESTRICT,
 decision_key text NOT NULL CHECK(length(btrim(decision_key)) BETWEEN 8 AND 160),
 envelope_digest text NOT NULL CHECK(envelope_digest ~ '^[0-9a-f]{64}$'),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 400),
 decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(actor_auth_user_id,decision_key),
 CHECK ((disposition='declined' AND grant_id IS NOT NULL) OR
        (disposition='withdrawn' AND grant_id IS NULL))
);
CREATE TRIGGER carry_p1b_disposition_immutable BEFORE UPDATE OR DELETE
 ON us.carry_ordinary_dispositions_v3 FOR EACH ROW
 EXECUTE FUNCTION us.carry_case_immutable_v1();
ALTER TABLE us.carry_ordinary_dispositions_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_ordinary_dispositions_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_ordinary_dispositions_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_dispose_ordinary_proposal_v3(
 p_verified_actor_auth_user_id uuid,p_proposal_id uuid,
 p_disposition text,p_decision_key text,p_expected_envelope_digest text,
 p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_ordinary_proposals_v3%ROWTYPE;
 v_g us.carry_ordinary_review_grants_v3%ROWTYPE;
 v_old us.carry_ordinary_dispositions_v3%ROWTYPE;
 v_actor_person uuid;v_id uuid;v_digest text;
BEGIN
 IF p_verified_actor_auth_user_id IS NULL OR p_proposal_id IS NULL
  OR p_disposition NOT IN ('declined','withdrawn')
  OR p_decision_key IS NULL OR length(btrim(p_decision_key)) NOT BETWEEN 8 AND 160
  OR p_expected_envelope_digest IS NULL
  OR p_expected_envelope_digest !~ '^[0-9a-f]{64}$'
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 400
 THEN RAISE EXCEPTION 'Exact bounded terminal decision required'
  USING ERRCODE='22023'; END IF;
 -- This lock also serializes P1A's independent approval and owner grant.
 SELECT * INTO v_p FROM us.carry_ordinary_proposals_v3 p
  WHERE p.id=p_proposal_id FOR UPDATE;
 IF v_p.id IS NULL OR v_p.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
 THEN RAISE EXCEPTION 'Exact original proposal unavailable' USING ERRCODE='42501'; END IF;
 v_actor_person:=us.carry_live_canonical_person_v3(p_verified_actor_auth_user_id);
 IF v_actor_person IS NULL THEN
  RAISE EXCEPTION 'Current canonical actor required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_ordinary_dispositions_v3 x
  WHERE x.proposal_id=v_p.id FOR SHARE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.disposition IS DISTINCT FROM p_disposition
   OR v_old.actor_auth_user_id IS DISTINCT FROM p_verified_actor_auth_user_id
   OR v_old.actor_person_entity_id IS DISTINCT FROM v_actor_person
   OR v_old.decision_key IS DISTINCT FROM p_decision_key
   OR v_old.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
   OR v_old.reason IS DISTINCT FROM p_reason
  THEN RAISE EXCEPTION 'Conflicting terminal decision' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('proposal_id',v_p.id::text,
   'decision_id',v_old.id::text,'state',v_old.disposition,'replayed',true,
   'event_created',false,'full_case_visible',false);
 END IF;
 IF EXISTS (SELECT 1 FROM us.carry_ordinary_approved_decisions_v3 d
  WHERE d.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'Already approved; terminal decision prohibited'
  USING ERRCODE='23505'; END IF;
 IF us.carry_live_canonical_person_v3(v_p.owner_auth_user_id)
   IS DISTINCT FROM v_p.owner_person_entity_id
 THEN RAISE EXCEPTION 'Owner identity no longer current'
  USING ERRCODE='42501'; END IF;
 IF p_disposition='withdrawn' THEN
  IF p_verified_actor_auth_user_id IS DISTINCT FROM v_p.owner_auth_user_id
    OR v_actor_person IS DISTINCT FROM v_p.owner_person_entity_id
  THEN RAISE EXCEPTION 'Only current original owner may withdraw'
   USING ERRCODE='42501'; END IF;
 ELSE
  SELECT * INTO v_g FROM us.carry_ordinary_review_grants_v3 g
   WHERE g.proposal_id=v_p.id
    AND g.reviewer_auth_user_id=p_verified_actor_auth_user_id
    AND g.expires_at>clock_timestamp() FOR SHARE;
  IF v_g.id IS NULL
    OR v_g.reviewer_person_entity_id IS DISTINCT FROM v_actor_person
    OR v_actor_person=v_p.owner_person_entity_id
    OR EXISTS(SELECT 1 FROM us.carry_ordinary_review_revocations_v3 x
      WHERE x.grant_id=v_g.id)
  THEN RAISE EXCEPTION 'Current independent decline grant required'
   USING ERRCODE='42501'; END IF;
 END IF;
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(v_p.event_type,v_p.effective_on,v_p.epistemic_class,
   v_p.source_ref,v_p.payload,v_p.expected_sequence)::text,'UTF8'),
  'sha256'),'hex');
 IF v_digest IS DISTINCT FROM v_p.envelope_digest
 THEN RAISE EXCEPTION 'Immutable source envelope no longer matches'
   USING ERRCODE='42501'; END IF;
 INSERT INTO us.carry_ordinary_dispositions_v3(
  proposal_id,disposition,actor_auth_user_id,actor_person_entity_id,
  grant_id,decision_key,envelope_digest,reason)
 VALUES(v_p.id,p_disposition,p_verified_actor_auth_user_id,v_actor_person,
  CASE WHEN p_disposition='declined' THEN v_g.id ELSE NULL END,
  p_decision_key,v_p.envelope_digest,p_reason)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('proposal_id',v_p.id::text,
  'decision_id',v_id::text,'state',p_disposition,'replayed',false,
  'event_created',false,'full_case_visible',false);
END $fn$;

-- Owner-selected Case queue: page only that owner's submitted originals.
-- Deliberately no payload, financial lines, roster, count or bulk action.
CREATE FUNCTION us.carry_owner_ordinary_queue_v3(
 p_verified_owner_auth_user_id uuid,p_stream_id uuid,
 p_after_proposal_id uuid DEFAULT NULL,p_page_size integer DEFAULT 20
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_person uuid;v_items jsonb;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_stream_id IS NULL
  OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 20
 THEN RAISE EXCEPTION 'Owner-selected bounded queue required'
  USING ERRCODE='22023'; END IF;
 v_person:=us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id);
 IF v_person IS NULL OR NOT EXISTS (
  SELECT 1 FROM us.carry_case_streams_v1 s
  JOIN us.carry_primary_open_approval_decisions_v3 d
   ON d.canonical_stream_id=s.id
  WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_verified_owner_auth_user_id
   AND d.owner_auth_user_id=p_verified_owner_auth_user_id
   AND d.owner_person_entity_id=v_person
 )
 THEN RAISE EXCEPTION 'Owner financial Case unavailable' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'proposal_id',q.id::text,'event_type',q.event_type,
  'expected_sequence',q.expected_sequence,'envelope_digest',q.envelope_digest,
  'state',q.state) ORDER BY q.id),'[]'::jsonb)
 INTO v_items FROM (
  SELECT p.id,p.event_type,p.expected_sequence,p.envelope_digest,
   CASE WHEN d.id IS NOT NULL THEN 'approved'
    WHEN x.id IS NOT NULL THEN x.disposition
    ELSE 'pending_review' END AS state
  FROM us.carry_ordinary_proposals_v3 p
  LEFT JOIN us.carry_ordinary_approved_decisions_v3 d ON d.proposal_id=p.id
  LEFT JOIN us.carry_ordinary_dispositions_v3 x ON x.proposal_id=p.id
  WHERE p.stream_id=p_stream_id AND p.owner_auth_user_id=p_verified_owner_auth_user_id
   AND p.owner_person_entity_id=v_person
   AND (p_after_proposal_id IS NULL OR p.id>p_after_proposal_id)
  ORDER BY p.id LIMIT p_page_size
 ) q;
 RETURN jsonb_build_object('scope','owner_selected_case_proposals_only',
  'items',v_items,'page_size',p_page_size,'full_case_visible',false,
  'next_after',CASE WHEN jsonb_array_length(v_items)=0 THEN NULL
    ELSE v_items->(jsonb_array_length(v_items)-1)->>'proposal_id' END);
END $fn$;

-- Reviewer sees only currently granted, unresolved proposals; selecting
-- one requires the independent exact packet read from P1A.
CREATE FUNCTION us.carry_reviewer_ordinary_queue_v3(
 p_verified_reviewer_auth_user_id uuid,p_after_proposal_id uuid DEFAULT NULL,
 p_page_size integer DEFAULT 20
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_person uuid;v_items jsonb;
BEGIN
 IF p_verified_reviewer_auth_user_id IS NULL OR p_page_size IS NULL
  OR p_page_size NOT BETWEEN 1 AND 20
 THEN RAISE EXCEPTION 'Current reviewer and bounded page required'
  USING ERRCODE='22023'; END IF;
 v_person:=us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id);
 IF v_person IS NULL THEN RAISE EXCEPTION 'Reviewer unavailable'
  USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'proposal_id',q.id::text,'event_type',q.event_type,
  'envelope_digest',q.envelope_digest,'expires_at',q.expires_at,
  'scope','this_proposal_only') ORDER BY q.id),'[]'::jsonb)
 INTO v_items FROM (
  SELECT p.id,p.event_type,p.envelope_digest,g.expires_at
  FROM us.carry_ordinary_review_grants_v3 g
  JOIN us.carry_ordinary_proposals_v3 p ON p.id=g.proposal_id
  WHERE g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
   AND g.reviewer_person_entity_id=v_person
   AND g.expires_at>clock_timestamp()
   AND p.owner_person_entity_id<>v_person
   AND us.carry_live_canonical_person_v3(p.owner_auth_user_id)
      IS NOT DISTINCT FROM p.owner_person_entity_id
   AND EXISTS(SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
     WHERE d.canonical_stream_id=p.stream_id
      AND d.owner_auth_user_id=p.owner_auth_user_id
      AND d.owner_person_entity_id=p.owner_person_entity_id)
   AND NOT EXISTS (SELECT 1 FROM us.carry_ordinary_review_revocations_v3 r
      WHERE r.grant_id=g.id)
   AND NOT EXISTS (SELECT 1 FROM us.carry_ordinary_approved_decisions_v3 d
      WHERE d.proposal_id=p.id)
   AND NOT EXISTS (SELECT 1 FROM us.carry_ordinary_dispositions_v3 x
      WHERE x.proposal_id=p.id)
   AND (p_after_proposal_id IS NULL OR p.id>p_after_proposal_id)
  ORDER BY p.id LIMIT p_page_size
 ) q;
 RETURN jsonb_build_object('scope','only_current_individually_granted_proposals',
  'items',v_items,'page_size',p_page_size,'full_case_visible',false,
  'next_after',CASE WHEN jsonb_array_length(v_items)=0 THEN NULL
    ELSE v_items->(jsonb_array_length(v_items)-1)->>'proposal_id' END);
END $fn$;

-- Amend P1A entrypoints to respect terminal status under their existing
-- proposal lock. Neither P1A nor the canonical event writer gains rights.
CREATE OR REPLACE FUNCTION us.carry_propose_ordinary_event_v3(
 p_verified_owner_auth_user_id uuid,p_stream_id uuid,p_proposal_key text,
 p_event_type text,p_effective_on date,p_epistemic_class text,
 p_source_ref text,p_payload jsonb
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_person uuid;v_stream us.carry_case_streams_v1%ROWTYPE;
 v_old us.carry_ordinary_proposals_v3%ROWTYPE;
 v_expected bigint;v_digest text;v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_stream_id IS NULL
  OR p_proposal_key IS NULL OR length(btrim(p_proposal_key)) NOT BETWEEN 8 AND 160
  OR p_event_type NOT IN
   ('FACT_ASSERTED','EVIDENCE_REFERENCED','FORECAST_LINE_PROPOSED',
    'FORECAST_LINE_REPLACED','FORECAST_LINE_RELEASED',
    'SCENARIO_CREATED','SCENARIO_OVERRIDE_RECORDED','DECISION_RECORDED')
  OR p_epistemic_class NOT IN ('USER_ASSERTED','PROJECTED','UNKNOWN')
  OR p_source_ref IS NULL OR length(btrim(p_source_ref)) NOT BETWEEN 8 AND 250
  OR p_source_ref NOT LIKE 'us:self:%'
  OR p_payload IS NULL OR jsonb_typeof(p_payload)<>'object'
  OR length(p_payload::text)>8000
  OR jsonb_typeof(p_payload->'reason')<>'string'
  OR length(btrim(p_payload->>'reason')) NOT BETWEEN 3 AND 1000
  OR NOT (p_payload ? 'value')
  OR (p_payload-'reason'-'value')<>'{}'::jsonb
 THEN RAISE EXCEPTION 'Bounded owner-asserted proposal required'
  USING ERRCODE='22023'; END IF;
 IF p_event_type IN ('FORECAST_LINE_PROPOSED','FORECAST_LINE_REPLACED',
  'FORECAST_LINE_RELEASED','SCENARIO_CREATED','SCENARIO_OVERRIDE_RECORDED')
  AND jsonb_typeof(p_payload->'value')<>'object'
 THEN RAISE EXCEPTION 'Structured projection value required' USING ERRCODE='22023'; END IF;
 v_person:=us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id);
 IF v_person IS NULL THEN RAISE EXCEPTION 'Owner Person unavailable'
  USING ERRCODE='42501'; END IF;
 -- Protect against a historical/legacy opened stream without G3 approval.
 SELECT * INTO v_stream FROM us.carry_case_streams_v1 s
 WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_verified_owner_auth_user_id
  AND s.subject_kind='financial_expectation' FOR UPDATE;
 IF v_stream.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
  WHERE d.canonical_stream_id=v_stream.id
   AND d.owner_auth_user_id=p_verified_owner_auth_user_id
   AND d.owner_person_entity_id=v_person)
 THEN RAISE EXCEPTION 'Independently opened financial Case unavailable'
  USING ERRCODE='42501'; END IF;
 SELECT coalesce(max(e.stream_sequence),0)+1 INTO v_expected
 FROM us.carry_case_events_v1 e WHERE e.stream_id=p_stream_id;
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(p_event_type,p_effective_on,p_epistemic_class,
   p_source_ref,p_payload,v_expected)::text,'UTF8'),'sha256'),'hex');
 SELECT * INTO v_old FROM us.carry_ordinary_proposals_v3 p
 WHERE p.stream_id=v_stream.id AND p.proposal_key=p_proposal_key;
 IF v_old.id IS NOT NULL THEN
  IF EXISTS (SELECT 1 FROM us.carry_ordinary_dispositions_v3 x WHERE x.proposal_id=v_old.id)
  THEN RAISE EXCEPTION 'Terminal proposal cannot be resubmitted' USING ERRCODE='42501'; END IF;
  IF v_old.owner_person_entity_id IS DISTINCT FROM v_person
   OR v_old.owner_auth_user_id IS DISTINCT FROM p_verified_owner_auth_user_id
   OR v_old.envelope_digest IS DISTINCT FROM
      pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
       jsonb_build_array(p_event_type,p_effective_on,p_epistemic_class,
        p_source_ref,p_payload,v_old.expected_sequence)::text,'UTF8'),
       'sha256'),'hex')
  THEN RAISE EXCEPTION 'Conflicting or stale proposal key'
   USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  INSERT INTO us.carry_ordinary_proposals_v3(
   stream_id,owner_auth_user_id,owner_person_entity_id,proposal_key,
   event_type,effective_on,epistemic_class,source_ref,payload,
   expected_sequence,envelope_digest)
  VALUES(v_stream.id,p_verified_owner_auth_user_id,v_person,p_proposal_key,
   p_event_type,p_effective_on,p_epistemic_class,p_source_ref,p_payload,
   v_expected,v_digest) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('proposal_id',v_id::text,
  'stream_id',v_stream.id::text,'state','pending_separate_review',
  'event_created',false,'financial_access_granted',false,
  'replayed',v_old.id IS NOT NULL);
END $fn$;

CREATE OR REPLACE FUNCTION us.carry_grant_ordinary_review_v3(
 p_verified_owner_auth_user_id uuid,p_proposal_id uuid,
 p_reviewer_person_id uuid,p_grant_key text,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_ordinary_proposals_v3%ROWTYPE;
 v_reviewer uuid;v_old us.carry_ordinary_review_grants_v3%ROWTYPE;
 v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_proposal_id IS NULL
  OR p_reviewer_person_id IS NULL OR p_grant_key IS NULL
  OR length(btrim(p_grant_key)) NOT BETWEEN 8 AND 160 OR p_expires_at IS NULL
 THEN RAISE EXCEPTION 'Exact individual reviewer grant required'
  USING ERRCODE='22023'; END IF;
 SELECT * INTO v_p FROM us.carry_ordinary_proposals_v3 p
 WHERE p.id=p_proposal_id AND p.owner_auth_user_id=p_verified_owner_auth_user_id
 FOR UPDATE;
 IF v_p.id IS NULL
  OR us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id)
    IS DISTINCT FROM v_p.owner_person_entity_id
  OR EXISTS(SELECT 1 FROM us.carry_ordinary_approved_decisions_v3 d
   WHERE d.proposal_id=v_p.id)
  OR EXISTS(SELECT 1 FROM us.carry_ordinary_dispositions_v3 x
   WHERE x.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'Owner proposal unavailable for reviewer grant'
  USING ERRCODE='42501'; END IF;
 -- Active canonical binding unique both by Person and by verified Auth.
 SELECT b.auth_user_id INTO v_reviewer FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
 JOIN auth.users u ON u.id=b.auth_user_id
 WHERE b.person_entity_id=p_reviewer_person_id
  AND b.binding_state='active' AND b.retired_at IS NULL
  AND e.entity_kind='person' AND e.identity_state='canonical'
  AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
  AND (u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
 FOR SHARE OF b,e,u;
 IF v_reviewer IS NULL OR p_reviewer_person_id=v_p.owner_person_entity_id
  OR v_reviewer=p_verified_owner_auth_user_id
  OR us.carry_live_canonical_person_v3(v_reviewer)
     IS DISTINCT FROM p_reviewer_person_id
 THEN RAISE EXCEPTION 'Distinct currently canonical Person required'
  USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_ordinary_review_grants_v3 g
 WHERE g.proposal_id=v_p.id AND g.reviewer_person_entity_id=p_reviewer_person_id
 FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.grant_key IS DISTINCT FROM p_grant_key
   OR v_old.expires_at IS DISTINCT FROM p_expires_at
   OR v_old.reviewer_auth_user_id IS DISTINCT FROM v_reviewer
  THEN RAISE EXCEPTION 'Conflicting reviewer grant' USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  IF p_expires_at<=clock_timestamp()+interval '5 minutes'
   OR p_expires_at>clock_timestamp()+interval '7 days'
  THEN RAISE EXCEPTION 'Reviewer grant expiry outside accepted bounds'
   USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_ordinary_review_grants_v3(
    proposal_id,owner_auth_user_id,reviewer_person_entity_id,
    reviewer_auth_user_id,grant_key,expires_at)
   VALUES(v_p.id,p_verified_owner_auth_user_id,p_reviewer_person_id,
    v_reviewer,p_grant_key,p_expires_at) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('grant_id',v_id::text,
  'proposal_id',v_p.id::text,'scope','this_proposal_only',
  'event_approved',false,'case_reader_granted',false,
  'expires_at',p_expires_at,'replayed',v_old.id IS NOT NULL);
END $fn$;

CREATE OR REPLACE FUNCTION us.carry_read_ordinary_review_packet_v3(
 p_verified_reviewer_auth_user_id uuid,p_proposal_id uuid
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_ordinary_proposals_v3%ROWTYPE;
 v_g us.carry_ordinary_review_grants_v3%ROWTYPE;
BEGIN
 SELECT * INTO v_p FROM us.carry_ordinary_proposals_v3 p
 WHERE p.id=p_proposal_id FOR SHARE;
 IF v_p.id IS NULL OR us.carry_live_canonical_person_v3(v_p.owner_auth_user_id)
  IS DISTINCT FROM v_p.owner_person_entity_id
 THEN RAISE EXCEPTION 'Review proposal unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_g FROM us.carry_ordinary_review_grants_v3 g
 WHERE g.proposal_id=v_p.id
  AND g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
  AND g.expires_at>clock_timestamp()
 FOR SHARE;
 IF v_g.id IS NULL
  OR us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id)
     IS DISTINCT FROM v_g.reviewer_person_entity_id
  OR v_g.reviewer_person_entity_id=v_p.owner_person_entity_id
  OR EXISTS(SELECT 1 FROM us.carry_ordinary_review_revocations_v3 x
   WHERE x.grant_id=v_g.id)
  OR EXISTS(SELECT 1 FROM us.carry_ordinary_approved_decisions_v3 d
   WHERE d.proposal_id=v_p.id)
  OR EXISTS(SELECT 1 FROM us.carry_ordinary_dispositions_v3 x
   WHERE x.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'This reviewer has no current exact proposal grant'
  USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'proposal_id',v_p.id::text,'stream_id',v_p.stream_id::text,
  'event_type',v_p.event_type,'effective_on',v_p.effective_on,
  'epistemic_class',v_p.epistemic_class,'source_ref',v_p.source_ref,
  'payload',v_p.payload,'expected_sequence',v_p.expected_sequence,
  'envelope_digest',v_p.envelope_digest,'expires_at',v_g.expires_at,
  'scope','this_proposal_only','full_case_visible',false,
  'event_approved',false);
END $fn$;

CREATE OR REPLACE FUNCTION us.carry_approve_ordinary_event_v3(
 p_verified_reviewer_auth_user_id uuid,p_proposal_id uuid,p_decision_key text,
 p_expected_envelope_digest text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_p us.carry_ordinary_proposals_v3%ROWTYPE;
 v_g us.carry_ordinary_review_grants_v3%ROWTYPE;
 v_prior us.carry_ordinary_approved_decisions_v3%ROWTYPE;
 v_id uuid;v_event uuid;v_sequence bigint;v_digest text;
BEGIN
 IF p_verified_reviewer_auth_user_id IS NULL OR p_proposal_id IS NULL
  OR p_decision_key IS NULL OR length(btrim(p_decision_key)) NOT BETWEEN 8 AND 160
  OR p_expected_envelope_digest !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Exact signed reviewer and source digest required'
  USING ERRCODE='22023'; END IF;
 -- Serialize rival reviewers and later grant/withdrawal decisions for this
 -- one proposal. No batch can implicitly authorize sibling events.
 SELECT * INTO v_p FROM us.carry_ordinary_proposals_v3 p
 WHERE p.id=p_proposal_id FOR UPDATE;
 IF v_p.id IS NULL OR v_p.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
 THEN RAISE EXCEPTION 'Exact review envelope unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_prior FROM us.carry_ordinary_approved_decisions_v3 d
 WHERE d.proposal_id=v_p.id FOR SHARE;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.approver_auth_user_id IS DISTINCT FROM p_verified_reviewer_auth_user_id
   OR v_prior.decision_key IS DISTINCT FROM p_decision_key
   OR v_prior.envelope_digest IS DISTINCT FROM p_expected_envelope_digest
  THEN RAISE EXCEPTION 'Independent decision already recorded' USING ERRCODE='23505'; END IF;
  RETURN jsonb_build_object('decision_id',v_prior.id::text,
   'event_id',v_prior.event_id::text,'event_sequence',v_prior.event_sequence,
   'state','approved_event_recorded','replayed',true);
 END IF;
 IF EXISTS(SELECT 1 FROM us.carry_ordinary_dispositions_v3 x
  WHERE x.proposal_id=v_p.id)
 THEN RAISE EXCEPTION 'Proposal already declined or withdrawn' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_g FROM us.carry_ordinary_review_grants_v3 g
 WHERE g.proposal_id=v_p.id AND g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
 AND g.expires_at>clock_timestamp() FOR SHARE;
 IF v_g.id IS NULL OR EXISTS(SELECT 1 FROM us.carry_ordinary_review_revocations_v3 r
   WHERE r.grant_id=v_g.id)
  OR us.carry_live_canonical_person_v3(v_p.owner_auth_user_id)
   IS DISTINCT FROM v_p.owner_person_entity_id
  OR us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id)
   IS DISTINCT FROM v_g.reviewer_person_entity_id
  OR v_p.owner_person_entity_id=v_g.reviewer_person_entity_id
 THEN RAISE EXCEPTION 'Distinct currently authorized reviewer required'
  USING ERRCODE='42501'; END IF;
 -- Immutable source envelope, reviewer supplied only its digest, never new
 -- amount, event payload, owner ID, stream or expected sequence.
 v_digest:=pg_catalog.encode(extensions.digest(pg_catalog.convert_to(
  jsonb_build_array(v_p.event_type,v_p.effective_on,v_p.epistemic_class,
   v_p.source_ref,v_p.payload,v_p.expected_sequence)::text,'UTF8'),
   'sha256'),'hex');
 IF v_digest IS DISTINCT FROM v_p.envelope_digest
 THEN RAISE EXCEPTION 'Review source digest changed' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS (SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
  WHERE d.canonical_stream_id=v_p.stream_id
   AND d.owner_auth_user_id=v_p.owner_auth_user_id
   AND d.owner_person_entity_id=v_p.owner_person_entity_id)
 THEN RAISE EXCEPTION 'Unapproved or legacy financial Case'
  USING ERRCODE='42501'; END IF;
 -- Source v1 event writer serializes this Case and requires the exact
 -- proposed sequence. A stale competing ordinary proposal fails closed.
 SELECT ev.event_id,ev.event_sequence
 INTO v_event,v_sequence FROM us.carry_append_event_v1(
   v_p.stream_id,'approved-ordinary:'||v_p.id::text,
   v_p.event_type,v_p.effective_on,v_p.epistemic_class,
   v_p.source_ref,v_p.payload,v_p.expected_sequence) ev;
 IF v_event IS NULL OR v_sequence<>v_p.expected_sequence
 THEN RAISE EXCEPTION 'No canonical event committed' USING ERRCODE='42501'; END IF;
 INSERT INTO us.carry_ordinary_approved_decisions_v3(
  proposal_id,grant_id,owner_auth_user_id,owner_person_entity_id,
  approver_auth_user_id,approver_person_entity_id,
  decision_key,event_id,event_sequence,envelope_digest)
 VALUES(v_p.id,v_g.id,v_p.owner_auth_user_id,v_p.owner_person_entity_id,
  p_verified_reviewer_auth_user_id,v_g.reviewer_person_entity_id,
  p_decision_key,v_event,v_sequence,v_p.envelope_digest)
 RETURNING id INTO v_id;
 RETURN jsonb_build_object('decision_id',v_id::text,
   'event_id',v_event::text,'event_sequence',v_sequence,
   'state','approved_event_recorded','replayed',false);
END $fn$;

REVOKE ALL ON FUNCTION
 us.carry_dispose_ordinary_proposal_v3(uuid,uuid,text,text,text,text),
 us.carry_owner_ordinary_queue_v3(uuid,uuid,uuid,integer),
 us.carry_reviewer_ordinary_queue_v3(uuid,uuid,integer)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION
 us.carry_dispose_ordinary_proposal_v3(uuid,uuid,text,text,text,text),
 us.carry_owner_ordinary_queue_v3(uuid,uuid,uuid,integer),
 us.carry_reviewer_ordinary_queue_v3(uuid,uuid,integer)
 TO us_carry_backend;
COMMIT;
