-- HELD Carry Gate G1: source-authorized nomination of a distinct canonical
-- Person to review a pending primary financial Case opening request.
-- A nomination confers NO financial disclosure, access, approval or event
-- authority. It does not create a Person, Ledger, membership or alternative
-- financial history. Must follow G0 reality identities and F opening request.
-- Never run as a production migration without protected source/custody release.
BEGIN;

CREATE TABLE us.carry_primary_reviewer_nominations_v3 (
 id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 open_request_id uuid NOT NULL UNIQUE
   REFERENCES us.carry_financial_open_requests_v3(id) ON DELETE RESTRICT,
 owner_auth_user_id uuid NOT NULL,
 owner_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 nominee_person_entity_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 nominee_auth_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 nominee_binding_id uuid NOT NULL REFERENCES reality.auth_person_bindings(id) ON DELETE RESTRICT,
 nomination_key text NOT NULL CHECK (length(btrim(nomination_key)) BETWEEN 8 AND 160),
 nomination_state text NOT NULL DEFAULT 'pending_nominee_acceptance'
   CHECK (nomination_state='pending_nominee_acceptance'),
 nominated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CONSTRAINT carry_reviewer_nominee_distinct_person_v3
   CHECK (nominee_person_entity_id<>owner_person_entity_id),
 CONSTRAINT carry_reviewer_nominee_distinct_auth_v3
   CHECK (nominee_auth_user_id<>owner_auth_user_id),
 CONSTRAINT carry_reviewer_unique_owner_key_v3 UNIQUE(owner_auth_user_id,nomination_key)
);
CREATE TRIGGER carry_reviewer_nominations_immutable_v3
 BEFORE UPDATE OR DELETE ON us.carry_primary_reviewer_nominations_v3
 FOR EACH ROW EXECUTE FUNCTION us.carry_case_immutable_v1();
ALTER TABLE us.carry_primary_reviewer_nominations_v3 ENABLE ROW LEVEL SECURITY;
ALTER TABLE us.carry_primary_reviewer_nominations_v3 FORCE ROW LEVEL SECURITY;
REVOKE ALL ON us.carry_primary_reviewer_nominations_v3
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;

CREATE FUNCTION us.carry_nominate_primary_reviewer_v3(
 p_verified_owner_auth_user_id uuid,
 p_open_request_id uuid,
 p_nominee_canonical_person_id uuid,
 p_nomination_key text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path='' AS $fn$
DECLARE
 v_req us.carry_financial_open_requests_v3%ROWTYPE;
 v_owner_person uuid;
 v_nominee_user uuid;
 v_nominee_binding uuid;
 v_prior us.carry_primary_reviewer_nominations_v3%ROWTYPE;
 v_nomination_id uuid;
 v_conflicting integer;
BEGIN
 IF p_verified_owner_auth_user_id IS NULL
    OR p_open_request_id IS NULL OR p_nominee_canonical_person_id IS NULL
    OR p_nomination_key IS NULL
    OR length(btrim(p_nomination_key)) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Exact private nomination request required'
   USING ERRCODE='22023'; END IF;

 -- The Us private service must first independently authenticate an actual
 -- GoTrue user bearer. Neither an owner nor a candidate UUID supplied
 -- by the HTTP body may be used as the server-verified acting identity.
 SELECT * INTO v_req FROM us.carry_financial_open_requests_v3 r
 WHERE r.id=p_open_request_id
   AND r.owner_auth_user_id=p_verified_owner_auth_user_id
   AND r.requester_auth_user_id=p_verified_owner_auth_user_id
   AND r.case_kind='primary'
   AND r.disposition='pending_independent_approval'
 FOR UPDATE;
 IF v_req.id IS NULL THEN
  RAISE EXCEPTION 'Pending private Case request unavailable'
    USING ERRCODE='42501'; END IF;

 -- The exact original Case source still must not have been opened by
 -- another pathway. Nomination is not an implicit repair operation.
 IF EXISTS (SELECT 1 FROM us.carry_case_streams_v1 s
    WHERE s.financial_plan_id=v_req.plan_id) THEN
   RAISE EXCEPTION 'Already-opened Case requires a separate review'
     USING ERRCODE='42501'; END IF;

 -- Reuse native Reality Person and binding. This is NOT a new Person table.
 -- Lock current bindings and entities, so simultaneous retirement or a
 -- disputed identity cannot pass the same authorization observation.
 SELECT b.person_entity_id INTO v_owner_person
 FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
 JOIN auth.users u ON u.id=b.auth_user_id
 WHERE b.auth_user_id=p_verified_owner_auth_user_id
   AND b.binding_state='active' AND b.retired_at IS NULL
   AND e.entity_kind='person' AND e.identity_state='canonical'
   AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
   AND (u.banned_until IS NULL OR u.banned_until<=pg_catalog.now())
 FOR SHARE OF b,e,u;
 IF v_owner_person IS NULL THEN
   RAISE EXCEPTION 'Verified owner has no canonical Person'
     USING ERRCODE='42501'; END IF;

 -- Different login aliases for the SAME Person cannot count as another
 -- authorized Person, even if identity source predates unique indexes.
 SELECT count(*)::integer INTO v_conflicting
 FROM reality.auth_person_bindings b
 WHERE b.person_entity_id=v_owner_person
   AND b.binding_state='active' AND b.retired_at IS NULL;
 IF v_conflicting<>1 OR v_owner_person=p_nominee_canonical_person_id THEN
   RAISE EXCEPTION 'Independent canonical Person required'
     USING ERRCODE='42501'; END IF;

 SELECT b.id,b.auth_user_id INTO v_nominee_binding,v_nominee_user
 FROM reality.auth_person_bindings b
 JOIN reality.entities e ON e.id=b.person_entity_id
 JOIN auth.users u ON u.id=b.auth_user_id
 WHERE b.person_entity_id=p_nominee_canonical_person_id
   AND b.binding_state='active' AND b.retired_at IS NULL
   AND e.entity_kind='person' AND e.identity_state='canonical'
   AND u.deleted_at IS NULL AND NOT coalesce(u.is_anonymous,false)
   AND (u.banned_until IS NULL OR u.banned_until<=pg_catalog.now())
 FOR SHARE OF b,e,u;
 IF v_nominee_binding IS NULL OR v_nominee_user=p_verified_owner_auth_user_id THEN
   RAISE EXCEPTION 'Distinct verified nominee unavailable'
     USING ERRCODE='42501'; END IF;
 SELECT count(*)::integer INTO v_conflicting
 FROM reality.auth_person_bindings b
 WHERE b.person_entity_id=p_nominee_canonical_person_id
   AND b.binding_state='active' AND b.retired_at IS NULL;
 IF v_conflicting<>1 THEN
   RAISE EXCEPTION 'Ambiguous active Person binding'
     USING ERRCODE='42501'; END IF;

 -- Relationship or existing Ledger seat is NEVER a private-finance
 -- authorization; this nomination makes no disclosure to the nominee.
 SELECT * INTO v_prior FROM us.carry_primary_reviewer_nominations_v3 n
 WHERE n.open_request_id=v_req.id FOR UPDATE;
 IF v_prior.id IS NOT NULL THEN
   IF v_prior.owner_auth_user_id IS DISTINCT FROM p_verified_owner_auth_user_id
     OR v_prior.owner_person_entity_id IS DISTINCT FROM v_owner_person
     OR v_prior.nominee_person_entity_id IS DISTINCT FROM p_nominee_canonical_person_id
     OR v_prior.nominee_auth_user_id IS DISTINCT FROM v_nominee_user
     OR v_prior.nominee_binding_id IS DISTINCT FROM v_nominee_binding
     OR v_prior.nomination_key IS DISTINCT FROM p_nomination_key
   THEN RAISE EXCEPTION 'Conflicting independent Person nomination'
     USING ERRCODE='23505'; END IF;
   v_nomination_id:=v_prior.id;
 ELSE
   INSERT INTO us.carry_primary_reviewer_nominations_v3(
    open_request_id,owner_auth_user_id,owner_person_entity_id,
    nominee_person_entity_id,nominee_auth_user_id,nominee_binding_id,
    nomination_key)
   VALUES(v_req.id,p_verified_owner_auth_user_id,v_owner_person,
          p_nominee_canonical_person_id,v_nominee_user,v_nominee_binding,
          p_nomination_key)
   RETURNING id INTO v_nomination_id;
 END IF;
 RETURN jsonb_build_object(
   'nomination_id',v_nomination_id::text,
   'request_id',v_req.id::text,
   'status','pending_nominee_acceptance',
   'financial_access_granted',false,
   'approval_authority_granted',false,
   'case_opened',false,
   'recorded_event',false,
   'replayed',v_prior.id IS NOT NULL
 );
END $fn$;

REVOKE ALL ON FUNCTION us.carry_nominate_primary_reviewer_v3(uuid,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role,us_carry_backend;
GRANT EXECUTE ON FUNCTION us.carry_nominate_primary_reviewer_v3(uuid,uuid,uuid,text)
 TO us_carry_backend;
-- No public or nominee read; nominee acceptance + exact authority is next gate.
COMMIT;
