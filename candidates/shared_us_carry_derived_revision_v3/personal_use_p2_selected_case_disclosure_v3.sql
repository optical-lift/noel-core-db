-- HELD P2: exact owner-selected full financial Case disclosure.
-- Apply after G3/P0/P1A/P1B/P1C. No automatic rights from connection.
BEGIN;
CREATE TABLE us.carry_case_read_grants_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 stream_id uuid NOT NULL REFERENCES us.carry_case_streams_v1(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 reviewer_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 reviewer_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 grant_key text NOT NULL CHECK(length(btrim(grant_key)) BETWEEN 8 AND 160),
 purpose text NOT NULL CHECK(length(btrim(purpose)) BETWEEN 8 AND 160),
 granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL,
 UNIQUE(owner_auth_user_id,grant_key),
 CHECK(owner_auth_user_id<>reviewer_auth_user_id),
 CHECK(owner_person_entity_id<>reviewer_person_entity_id),
 CHECK(expires_at>granted_at AND expires_at<=granted_at+interval '7 days')
);
CREATE TABLE us.carry_case_read_revocations_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 grant_id uuid NOT NULL UNIQUE REFERENCES us.carry_case_read_grants_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 revoke_key text NOT NULL CHECK(length(btrim(revoke_key)) BETWEEN 8 AND 160),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 400),
 revoked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(owner_auth_user_id,revoke_key)
);
CREATE TRIGGER carry_case_read_grant_immutable_v3 BEFORE UPDATE OR DELETE
 ON us.carry_case_read_grants_v3 FOR EACH ROW
 EXECUTE FUNCTION us.carry_case_immutable_v1();
CREATE TRIGGER carry_case_read_revocation_immutable_v3 BEFORE UPDATE OR DELETE
 ON us.carry_case_read_revocations_v3 FOR EACH ROW
 EXECUTE FUNCTION us.carry_case_immutable_v1();
ALTER TABLE us.carry_case_read_grants_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_read_grants_v3 FORCE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_read_revocations_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_case_read_revocations_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_case_read_grants_v3,us.carry_case_read_revocations_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_grant_selected_case_read_v3(
 p_verified_owner_auth_user_id uuid,p_stream_id uuid,p_reviewer_person_id uuid,
 p_grant_key text,p_purpose text,p_expires_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_owner uuid;v_reviewer uuid;v_stream us.carry_case_streams_v1%ROWTYPE;
 v_old us.carry_case_read_grants_v3%ROWTYPE;v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_stream_id IS NULL
  OR p_reviewer_person_id IS NULL OR p_grant_key IS NULL
  OR length(btrim(p_grant_key)) NOT BETWEEN 8 AND 160
  OR p_purpose IS NULL OR length(btrim(p_purpose)) NOT BETWEEN 8 AND 160
  OR p_expires_at IS NULL
 THEN RAISE EXCEPTION 'Exact selected Case disclosure required' USING ERRCODE='22023'; END IF;
 v_owner:=us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id);
 SELECT * INTO v_stream FROM us.carry_case_streams_v1 s
  WHERE s.id=p_stream_id AND s.owner_auth_user_id=p_verified_owner_auth_user_id
   AND s.subject_kind='financial_expectation' FOR SHARE;
 IF v_owner IS NULL OR v_stream.id IS NULL OR NOT EXISTS(
  SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
   WHERE d.canonical_stream_id=v_stream.id
    AND d.owner_auth_user_id=p_verified_owner_auth_user_id
    AND d.owner_person_entity_id=v_owner)
 THEN RAISE EXCEPTION 'Approved selected Case unavailable' USING ERRCODE='42501'; END IF;
 SELECT b.auth_user_id INTO v_reviewer FROM reality.auth_person_bindings b
  WHERE b.person_entity_id=p_reviewer_person_id AND b.binding_state='active'
   AND b.retired_at IS NULL FOR SHARE;
 IF v_reviewer IS NULL OR p_reviewer_person_id=v_owner
  OR v_reviewer=p_verified_owner_auth_user_id
  OR us.carry_live_canonical_person_v3(v_reviewer) IS DISTINCT FROM p_reviewer_person_id
 THEN RAISE EXCEPTION 'Distinct current reviewer Person required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_case_read_grants_v3 g
  WHERE g.owner_auth_user_id=p_verified_owner_auth_user_id AND g.grant_key=p_grant_key
  FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.stream_id IS DISTINCT FROM p_stream_id
   OR v_old.owner_person_entity_id IS DISTINCT FROM v_owner
   OR v_old.reviewer_auth_user_id IS DISTINCT FROM v_reviewer
   OR v_old.reviewer_person_entity_id IS DISTINCT FROM p_reviewer_person_id
   OR v_old.purpose IS DISTINCT FROM p_purpose
   OR v_old.expires_at IS DISTINCT FROM p_expires_at
  THEN RAISE EXCEPTION 'Conflicting selected Case grant' USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  IF p_expires_at<=clock_timestamp()+interval '5 minutes'
   OR p_expires_at>clock_timestamp()+interval '7 days'
  THEN RAISE EXCEPTION 'Case read expiry outside accepted bounds' USING ERRCODE='22023'; END IF;
  INSERT INTO us.carry_case_read_grants_v3(stream_id,owner_auth_user_id,
   owner_person_entity_id,reviewer_auth_user_id,reviewer_person_entity_id,
   grant_key,purpose,expires_at)
  VALUES(p_stream_id,p_verified_owner_auth_user_id,v_owner,v_reviewer,
   p_reviewer_person_id,p_grant_key,p_purpose,p_expires_at) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('grant_id',v_id::text,'stream_id',p_stream_id::text,
  'scope','full_selected_case_read','purpose',p_purpose,'expires_at',p_expires_at,
  'replayed',v_old.id IS NOT NULL);
END $fn$;

CREATE FUNCTION us.carry_revoke_selected_case_read_v3(
 p_verified_owner_auth_user_id uuid,p_grant_id uuid,p_revoke_key text,p_reason text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_g us.carry_case_read_grants_v3%ROWTYPE;
 v_old us.carry_case_read_revocations_v3%ROWTYPE;v_id uuid;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL OR p_grant_id IS NULL
  OR p_revoke_key IS NULL OR length(btrim(p_revoke_key)) NOT BETWEEN 8 AND 160
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 400
 THEN RAISE EXCEPTION 'Exact owner revocation required' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_g FROM us.carry_case_read_grants_v3 g
  WHERE g.id=p_grant_id AND g.owner_auth_user_id=p_verified_owner_auth_user_id
  FOR UPDATE;
 IF v_g.id IS NULL OR us.carry_live_canonical_person_v3(p_verified_owner_auth_user_id)
  IS DISTINCT FROM v_g.owner_person_entity_id
 THEN RAISE EXCEPTION 'Owner Case grant unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_old FROM us.carry_case_read_revocations_v3 x
  WHERE x.grant_id=v_g.id FOR UPDATE;
 IF v_old.id IS NOT NULL THEN
  IF v_old.revoke_key IS DISTINCT FROM p_revoke_key
   OR v_old.reason IS DISTINCT FROM p_reason
  THEN RAISE EXCEPTION 'Conflicting Case revocation' USING ERRCODE='23505'; END IF;
  v_id:=v_old.id;
 ELSE
  INSERT INTO us.carry_case_read_revocations_v3(grant_id,owner_auth_user_id,revoke_key,reason)
  VALUES(v_g.id,p_verified_owner_auth_user_id,p_revoke_key,p_reason) RETURNING id INTO v_id;
 END IF;
 RETURN jsonb_build_object('grant_id',v_g.id::text,'revocation_id',v_id::text,
  'state','revoked','replayed',v_old.id IS NOT NULL);
END $fn$;

-- Internal authority check. No direct backend EXECUTE: readers call it as
-- source owner. A grant ID alone never authenticates a caller.
CREATE FUNCTION us.carry_selected_case_read_stream_v3(
 p_verified_reviewer_auth_user_id uuid,p_grant_id uuid
) RETURNS uuid LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_g us.carry_case_read_grants_v3%ROWTYPE;
BEGIN
 SELECT * INTO v_g FROM us.carry_case_read_grants_v3 g
  WHERE g.id=p_grant_id AND g.reviewer_auth_user_id=p_verified_reviewer_auth_user_id
   AND g.expires_at>clock_timestamp() FOR SHARE;
 IF v_g.id IS NULL OR v_g.owner_auth_user_id=p_verified_reviewer_auth_user_id
  OR v_g.owner_person_entity_id=v_g.reviewer_person_entity_id
  OR us.carry_live_canonical_person_v3(p_verified_reviewer_auth_user_id)
    IS DISTINCT FROM v_g.reviewer_person_entity_id
  OR us.carry_live_canonical_person_v3(v_g.owner_auth_user_id)
    IS DISTINCT FROM v_g.owner_person_entity_id
  OR EXISTS(SELECT 1 FROM us.carry_case_read_revocations_v3 r WHERE r.grant_id=v_g.id)
  OR NOT EXISTS(SELECT 1 FROM us.carry_primary_open_approval_decisions_v3 d
   WHERE d.canonical_stream_id=v_g.stream_id
    AND d.owner_auth_user_id=v_g.owner_auth_user_id
    AND d.owner_person_entity_id=v_g.owner_person_entity_id)
 THEN RAISE EXCEPTION 'Current selected Case permission unavailable' USING ERRCODE='42501'; END IF;
 RETURN v_g.stream_id;
END $fn$;
REVOKE ALL ON FUNCTION us.carry_selected_case_read_stream_v3(uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_read_selected_case_events_v3(
 p_verified_reviewer_auth_user_id uuid,p_grant_id uuid,
 p_after_sequence bigint DEFAULT 0,p_page_size integer DEFAULT 20
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_stream uuid;v_events jsonb;v_last bigint;v_more boolean;
BEGIN
 IF p_after_sequence IS NULL OR p_after_sequence<0
  OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50
 THEN RAISE EXCEPTION 'Bounded event page required' USING ERRCODE='22023'; END IF;
 v_stream:=us.carry_selected_case_read_stream_v3(p_verified_reviewer_auth_user_id,p_grant_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'event_id',e.id::text,'stream_sequence',e.stream_sequence,
  'event_schema_version',e.event_schema_version,'event_type',e.event_type,
  'payload',e.payload,'source_ref',e.source_ref,'epistemic_class',e.epistemic_class,
  'effective_on',e.effective_on,'recorded_at',e.recorded_at,
  'previous_event_digest',e.previous_event_digest,'event_digest',e.event_digest)
  ORDER BY e.stream_sequence),'[]'::jsonb),max(e.stream_sequence)
 INTO v_events,v_last FROM (
  SELECT * FROM us.carry_case_events_v1
   WHERE stream_id=v_stream AND stream_sequence>p_after_sequence
   ORDER BY stream_sequence LIMIT p_page_size) e;
 v_last:=coalesce(v_last,p_after_sequence);
 SELECT EXISTS(SELECT 1 FROM us.carry_case_events_v1
  WHERE stream_id=v_stream AND stream_sequence>v_last) INTO v_more;
 RETURN jsonb_build_object('grant_id',p_grant_id::text,'stream_id',v_stream::text,
  'scope','full_selected_case_read','events',v_events,
  'next_after_sequence',v_last,'has_more',v_more);
END $fn$;

CREATE FUNCTION us.carry_read_selected_case_revisions_v3(
 p_verified_reviewer_auth_user_id uuid,p_grant_id uuid,
 p_after_revision integer DEFAULT 0,p_page_size integer DEFAULT 10
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_stream uuid;v_plan us.financial_expectation_plans%ROWTYPE;
 v_items jsonb;v_last integer;v_more boolean;
BEGIN
 IF p_after_revision IS NULL OR p_after_revision<0
  OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 10
 THEN RAISE EXCEPTION 'Bounded revision page required' USING ERRCODE='22023'; END IF;
 v_stream:=us.carry_selected_case_read_stream_v3(p_verified_reviewer_auth_user_id,p_grant_id);
 SELECT p.* INTO v_plan FROM us.financial_expectation_plans p
 JOIN us.carry_case_streams_v1 s ON s.financial_plan_id=p.id
 WHERE s.id=v_stream AND s.owner_auth_user_id=p.owner_auth_user_id;
 IF v_plan.id IS NULL THEN RAISE EXCEPTION 'Case plan unavailable' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'revision_id',r.id::text,'revision',r.revision,'standing',r.standing,
  'source_ref',r.source_ref,'narrative',r.narrative)
  ORDER BY r.revision),'[]'::jsonb),max(r.revision)
 INTO v_items,v_last FROM (
  SELECT * FROM us.financial_expectation_revisions
   WHERE plan_id=v_plan.id AND owner_auth_user_id=v_plan.owner_auth_user_id
    AND revision>p_after_revision ORDER BY revision LIMIT p_page_size) r;
 v_last:=coalesce(v_last,p_after_revision);
 SELECT EXISTS(SELECT 1 FROM us.financial_expectation_revisions
  WHERE plan_id=v_plan.id AND owner_auth_user_id=v_plan.owner_auth_user_id
   AND revision>v_last) INTO v_more;
 RETURN jsonb_build_object('grant_id',p_grant_id::text,'stream_id',v_stream::text,
  'scope','full_selected_case_read',
  'plan',jsonb_build_object('plan_key',v_plan.plan_key,'title',v_plan.title,
   'period_start',v_plan.period_start,'period_end',v_plan.period_end,
   'source_ref',v_plan.source_ref),
  'revisions',v_items,'next_after_revision',v_last,'has_more',v_more);
END $fn$;

CREATE FUNCTION us.carry_read_selected_case_lines_v3(
 p_verified_reviewer_auth_user_id uuid,p_grant_id uuid,p_revision_id uuid,
 p_after_month date DEFAULT NULL,p_after_line_key text DEFAULT NULL,
 p_page_size integer DEFAULT 50
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE v_stream uuid;v_revision us.financial_expectation_revisions%ROWTYPE;
 v_lines jsonb;v_last_month date;v_last_key text;v_more boolean;
BEGIN
 IF p_revision_id IS NULL OR p_page_size IS NULL OR p_page_size NOT BETWEEN 1 AND 50
  OR (p_after_month IS NULL)<>(p_after_line_key IS NULL)
 THEN RAISE EXCEPTION 'Exact bounded line page required' USING ERRCODE='22023'; END IF;
 v_stream:=us.carry_selected_case_read_stream_v3(p_verified_reviewer_auth_user_id,p_grant_id);
 SELECT r.* INTO v_revision FROM us.financial_expectation_revisions r
 JOIN us.carry_case_streams_v1 s ON s.financial_plan_id=r.plan_id
  AND s.owner_auth_user_id=r.owner_auth_user_id
 WHERE s.id=v_stream AND r.id=p_revision_id;
 IF v_revision.id IS NULL THEN RAISE EXCEPTION 'Selected Case revision unavailable' USING ERRCODE='42501'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'period_month',l.period_month,'line_key',l.line_key,
  'economic_scope',l.economic_scope,'subject_key',l.subject_key,
  'money_role',l.money_role,'expectation_state',l.expectation_state,
  'forecast_amount',l.forecast_amount,'currency',l.currency,
  'explanation',l.explanation) ORDER BY l.period_month,l.line_key),'[]'::jsonb),
  (array_agg(l.period_month ORDER BY l.period_month DESC,l.line_key DESC))[1],
  (array_agg(l.line_key ORDER BY l.period_month DESC,l.line_key DESC))[1]
 INTO v_lines,v_last_month,v_last_key FROM (
  SELECT * FROM us.financial_expectation_lines
   WHERE revision_id=v_revision.id AND owner_auth_user_id=v_revision.owner_auth_user_id
    AND (p_after_month IS NULL OR (period_month,line_key)>(p_after_month,p_after_line_key))
   ORDER BY period_month,line_key LIMIT p_page_size) l;
 v_last_month:=coalesce(v_last_month,p_after_month);
 v_last_key:=coalesce(v_last_key,p_after_line_key);
 SELECT EXISTS(SELECT 1 FROM us.financial_expectation_lines
  WHERE revision_id=v_revision.id AND owner_auth_user_id=v_revision.owner_auth_user_id
   AND (v_last_month IS NULL OR (period_month,line_key)>(v_last_month,v_last_key)))
 INTO v_more;
 RETURN jsonb_build_object('grant_id',p_grant_id::text,'stream_id',v_stream::text,
  'revision_id',v_revision.id::text,'scope','full_selected_case_read',
  'lines',v_lines,'next_after_month',v_last_month,
  'next_after_line_key',v_last_key,'has_more',v_more);
END $fn$;

REVOKE ALL ON FUNCTION
 us.carry_grant_selected_case_read_v3(uuid,uuid,uuid,text,text,timestamptz),
 us.carry_revoke_selected_case_read_v3(uuid,uuid,text,text),
 us.carry_read_selected_case_events_v3(uuid,uuid,bigint,integer),
 us.carry_read_selected_case_revisions_v3(uuid,uuid,integer,integer),
 us.carry_read_selected_case_lines_v3(uuid,uuid,uuid,date,text,integer)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION
 us.carry_grant_selected_case_read_v3(uuid,uuid,uuid,text,text,timestamptz),
 us.carry_revoke_selected_case_read_v3(uuid,uuid,text,text),
 us.carry_read_selected_case_events_v3(uuid,uuid,bigint,integer),
 us.carry_read_selected_case_revisions_v3(uuid,uuid,integer,integer),
 us.carry_read_selected_case_lines_v3(uuid,uuid,uuid,date,text,integer)
 TO us_carry_backend;
COMMIT;
