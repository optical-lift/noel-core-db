-- HELD source candidate. No credential, grant, Person, Course or proposal seeded.
-- Register only after separate source release review. One Atlas invocation is
-- the proposal, confirmation, carrier provenance, and atomic execution receipt.
BEGIN;
ALTER TABLE atlas.teaching_course_units ADD COLUMN created_by_agent_invocation_id uuid
 REFERENCES atlas.agent_command_invocations(id) ON DELETE RESTRICT;
ALTER TABLE atlas.teaching_course_unit_revisions ADD COLUMN recorded_by_agent_invocation_id uuid
 REFERENCES atlas.agent_command_invocations(id) ON DELETE RESTRICT;
CREATE INDEX teaching_course_units_agent_invocation_v1
 ON atlas.teaching_course_units(created_by_agent_invocation_id) WHERE created_by_agent_invocation_id IS NOT NULL;
CREATE INDEX teaching_course_revisions_agent_invocation_v1
 ON atlas.teaching_course_unit_revisions(recorded_by_agent_invocation_id) WHERE recorded_by_agent_invocation_id IS NOT NULL;

-- Strict versioned packet. No ship/publish, move, delete, title change or arbitrary SQL.
CREATE FUNCTION atlas.validate_course_authoring_proposal_v1(p jsonb,p_course uuid)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path TO pg_catalog AS $validate$
DECLARE i jsonb;b jsonb;req uuid;uid uuid;seen uuid[];units uuid[]:='{}';total int:=0;
BEGIN
 IF p_course IS NULL OR jsonb_typeof(p) IS DISTINCT FROM 'object'
  OR NOT (p ?& ARRAY['contractVersion','courseId','proposalId','items'])
  OR (SELECT count(*) FROM jsonb_object_keys(p))<>4
  OR p->>'contractVersion' IS DISTINCT FROM 'titus_course_authoring_proposal_v1'
  OR jsonb_typeof(p->'courseId') IS DISTINCT FROM 'string'
  OR lower(p->>'courseId') IS DISTINCT FROM p_course::text
  OR jsonb_typeof(p->'proposalId') IS DISTINCT FROM 'string'
  OR NOT coalesce(p->>'proposalId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false)
  OR jsonb_typeof(p->'items') IS DISTINCT FROM 'array'
  OR octet_length(p::text)>1000000 THEN
  RAISE EXCEPTION 'invalid Course proposal' USING ERRCODE='22023';
 END IF;
 IF jsonb_array_length(p->'items') NOT BETWEEN 1 AND 12 THEN
  RAISE EXCEPTION 'invalid batch size' USING ERRCODE='22023'; END IF;
 seen:=ARRAY[(p->>'proposalId')::uuid];
 FOR i IN SELECT value FROM jsonb_array_elements(p->'items') LOOP
  IF jsonb_typeof(i) IS DISTINCT FROM 'object' OR
   NOT (i ?& ARRAY['operation','requestId','kind','title','text','basis']) OR
   coalesce(i->>'operation','') NOT IN ('append_unit','revise_unit') OR
   coalesce(i->>'kind','') NOT IN ('lesson','assignment') OR
   jsonb_typeof(i->'requestId') IS DISTINCT FROM 'string' OR
   NOT coalesce(i->>'requestId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false) OR
   jsonb_typeof(i->'title') IS DISTINCT FROM 'string' OR
   char_length(i->>'title') NOT BETWEEN 1 AND 150 OR
   btrim(i->>'title') IS DISTINCT FROM i->>'title' OR
   (i->>'title') !~ '[^[:space:]]' OR
   jsonb_typeof(i->'text') IS DISTINCT FROM 'string' OR
   char_length(i->>'text') NOT BETWEEN 1 AND 20000 OR
   (i->>'text') !~ '[^[:space:]]' OR
   jsonb_typeof(i->'basis') IS DISTINCT FROM 'array' THEN
   RAISE EXCEPTION 'invalid proposal item' USING ERRCODE='22023'; END IF;
  req:=(i->>'requestId')::uuid;
  IF req=ANY(seen) THEN RAISE EXCEPTION 'duplicate request' USING ERRCODE='22023'; END IF;
  seen:=array_append(seen,req);total:=total+char_length(i->>'text');
  IF total>80000 OR jsonb_array_length(i->'basis') NOT BETWEEN 1 AND 12 THEN
   RAISE EXCEPTION 'invalid source basis or batch text' USING ERRCODE='22023'; END IF;
  FOR b IN SELECT value FROM jsonb_array_elements(i->'basis') LOOP
   IF jsonb_typeof(b) IS DISTINCT FROM 'object' OR NOT (b ?& ARRAY['reference','description'])
    OR (SELECT count(*) FROM jsonb_object_keys(b))<>2
    OR jsonb_typeof(b->'reference') IS DISTINCT FROM 'string'
    OR jsonb_typeof(b->'description') IS DISTINCT FROM 'string'
    OR char_length(b->>'reference') NOT BETWEEN 1 AND 500
    OR char_length(b->>'description') NOT BETWEEN 1 AND 1000
    OR (b->>'reference') !~ '[^[:space:]]' OR (b->>'description') !~ '[^[:space:]]' THEN
    RAISE EXCEPTION 'invalid source basis' USING ERRCODE='22023'; END IF;
  END LOOP;
  IF i->>'operation'='append_unit' THEN
   IF (SELECT count(*) FROM jsonb_object_keys(i))<>6 THEN
    RAISE EXCEPTION 'unexpected append fields' USING ERRCODE='22023'; END IF;
  ELSE
   IF (SELECT count(*) FROM jsonb_object_keys(i))<>8 OR NOT (i ?& ARRAY['unitId','expectedRevision'])
    OR jsonb_typeof(i->'unitId') IS DISTINCT FROM 'string'
    OR NOT coalesce(i->>'unitId' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',false)
    OR jsonb_typeof(i->'expectedRevision') IS DISTINCT FROM 'number'
    OR NOT coalesce(i->>'expectedRevision' ~ '^(0|[1-9][0-9]{0,3})$',false) THEN
    RAISE EXCEPTION 'invalid revision target' USING ERRCODE='22023'; END IF;
   uid:=(i->>'unitId')::uuid;
   IF uid=ANY(units) THEN RAISE EXCEPTION 'duplicate Unit' USING ERRCODE='22023'; END IF;
   units:=array_append(units,uid);
  END IF;
 END LOOP;
END $validate$;
REVOKE ALL ON FUNCTION atlas.validate_course_authoring_proposal_v1(jsonb,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Source-derived receipt. A generic command completion alone cannot claim
-- Course authoring success. Exact revision and Unit IDs are recovered by provenance.
CREATE FUNCTION atlas.course_authoring_receipt_v1(p_invocation uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SET search_path TO pg_catalog AS $receipt$
DECLARE v atlas.agent_command_invocations%ROWTYPE;i jsonb;u uuid;r uuid;n int;expected int;
 results jsonb:='[]';cid uuid;expected_appends int;
BEGIN
 SELECT * INTO STRICT v FROM atlas.agent_command_invocations WHERE id=p_invocation;
 IF v.command_key<>'teaching.course.authoring.apply_proposal' OR v.command_version<>1 THEN
  RAISE EXCEPTION 'wrong command receipt' USING ERRCODE='22023'; END IF;
 cid:=(v.target->>'id')::uuid;
 PERFORM atlas.validate_course_authoring_proposal_v1(v.input,cid);
 SELECT count(*) INTO expected_appends FROM jsonb_array_elements(v.input->'items') i0 WHERE i0->>'operation'='append_unit';
 IF (SELECT count(*) FROM atlas.teaching_course_unit_revisions WHERE recorded_by_agent_invocation_id=v.id)
   <>jsonb_array_length(v.input->'items') OR
  (SELECT count(*) FROM atlas.teaching_course_units WHERE created_by_agent_invocation_id=v.id)<>expected_appends THEN
  RAISE EXCEPTION 'incomplete Course receipt' USING ERRCODE='55000'; END IF;
 FOR i IN SELECT value FROM jsonb_array_elements(v.input->'items') LOOP
  expected:=CASE WHEN i->>'operation'='append_unit' THEN 0 ELSE (i->>'expectedRevision')::int END;
  SELECT un.unit_id,rr.revision_id,rr.revision_number INTO STRICT u,r,n
   FROM atlas.teaching_course_unit_revisions rr JOIN atlas.teaching_course_units un ON un.unit_id=rr.unit_id
   WHERE rr.recorded_by_agent_invocation_id=v.id AND rr.edit_request_id=(i->>'requestId')::uuid
    AND un.course_id=cid AND rr.body_text=i->>'text' AND rr.based_on_revision=expected
    AND rr.recorded_by_auth_user_id=v.confirmed_by_user_id
    AND rr.recorded_by_person_entity_id=(SELECT created_by_person_entity_id FROM atlas.teaching_courses WHERE id=cid)
    AND rr.revision_number=expected+1 AND
    ((i->>'operation'='append_unit' AND un.created_by_agent_invocation_id=v.id AND un.create_request_id=(i->>'requestId')::uuid)
      OR (i->>'operation'='revise_unit' AND un.unit_id=(i->>'unitId')::uuid));
  results:=results||jsonb_build_array(jsonb_build_object('requestId',i->>'requestId','operation',i->>'operation',
   'unitId',u,'revisionId',r,'revisionNumber',n));
 END LOOP;
 RETURN jsonb_build_object('contractVersion','shared_course_authoring_applied_v1','courseId',cid,
  'proposalId',v.input->>'proposalId','invocationId',v.id,'items',results);
END $receipt$;
REVOKE ALL ON FUNCTION atlas.course_authoring_receipt_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Make the existing command's reviewed packet immutable, without changing
-- unrelated Atlas command behavior. Completion must be backed by real revisions.
CREATE FUNCTION atlas.guard_course_authoring_invocation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $guard$
BEGIN
 IF OLD.command_key='teaching.course.authoring.apply_proposal' THEN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'Course invocation history is immutable' USING ERRCODE='55000'; END IF;
  IF ROW(OLD.id,OLD.authorization_id,OLD.credential_id,OLD.carrier_id,OLD.principal_id,OLD.ledger_id,
    OLD.delegating_seat_id,OLD.command_key,OLD.command_version,OLD.idempotency_key,OLD.target,OLD.input,OLD.confirmation_required)
   IS DISTINCT FROM ROW(NEW.id,NEW.authorization_id,NEW.credential_id,NEW.carrier_id,NEW.principal_id,NEW.ledger_id,
    NEW.delegating_seat_id,NEW.command_key,NEW.command_version,NEW.idempotency_key,NEW.target,NEW.input,NEW.confirmation_required)
   OR (OLD.confirmed_at IS NOT NULL AND
       ROW(OLD.confirmed_at,OLD.confirmed_by_user_id) IS DISTINCT FROM ROW(NEW.confirmed_at,NEW.confirmed_by_user_id))
   OR (OLD.invocation_state IN ('succeeded','failed','cancelled','rejected') AND OLD IS DISTINCT FROM NEW) THEN
   RAISE EXCEPTION 'Course invocation identity or final receipt is immutable' USING ERRCODE='55000'; END IF;
  IF NEW.invocation_state='succeeded' AND OLD.invocation_state<>'succeeded' THEN
   IF OLD.invocation_state<>'executing' OR NEW.confirmed_at IS NULL OR
    NEW.result IS DISTINCT FROM atlas.course_authoring_receipt_v1(OLD.id) THEN
    RAISE EXCEPTION 'Course success requires source receipt' USING ERRCODE='55000'; END IF;
  END IF;
 ELSIF TG_OP='UPDATE' AND NEW.command_key='teaching.course.authoring.apply_proposal' THEN
  RAISE EXCEPTION 'cannot reclassify an invocation' USING ERRCODE='55000';
 END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
END $guard$;
REVOKE ALL ON FUNCTION atlas.guard_course_authoring_invocation_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER course_authoring_invocation_guard_v1 BEFORE UPDATE OR DELETE ON atlas.agent_command_invocations
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_course_authoring_invocation_v1();

CREATE FUNCTION atlas.guard_course_agent_provenance_v1()
RETURNS trigger LANGUAGE plpgsql SET search_path TO pg_catalog AS $origin$
BEGIN
 IF TG_TABLE_NAME='teaching_course_units' THEN
  IF TG_OP='DELETE' THEN
   IF OLD.created_by_agent_invocation_id IS NOT NULL THEN
    RAISE EXCEPTION 'delegated Unit origin cannot be deleted' USING ERRCODE='55000';END IF;
   RETURN OLD;
  END IF;
  IF OLD.created_by_agent_invocation_id IS DISTINCT FROM NEW.created_by_agent_invocation_id OR
   (OLD.created_by_agent_invocation_id IS NOT NULL AND
    ROW(OLD.unit_id,OLD.course_id,OLD.create_request_id,OLD.created_by_person_entity_id,OLD.created_by_auth_user_id,OLD.created_at)
    IS DISTINCT FROM ROW(NEW.unit_id,NEW.course_id,NEW.create_request_id,NEW.created_by_person_entity_id,NEW.created_by_auth_user_id,NEW.created_at)) THEN
   RAISE EXCEPTION 'delegated Unit origin is immutable' USING ERRCODE='55000';END IF;
 ELSE
  IF TG_OP='DELETE' THEN
   IF OLD.recorded_by_agent_invocation_id IS NOT NULL THEN
    RAISE EXCEPTION 'delegated revision cannot be deleted' USING ERRCODE='55000';END IF;
   RETURN OLD;
  END IF;
  IF OLD.recorded_by_agent_invocation_id IS DISTINCT FROM NEW.recorded_by_agent_invocation_id OR
    (OLD.recorded_by_agent_invocation_id IS NOT NULL AND OLD IS DISTINCT FROM NEW) THEN
   RAISE EXCEPTION 'delegated revision is immutable' USING ERRCODE='55000';END IF;
 END IF;
 RETURN NEW;
END $origin$;
REVOKE ALL ON FUNCTION atlas.guard_course_agent_provenance_v1() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER course_unit_agent_provenance_v1 BEFORE UPDATE OR DELETE ON atlas.teaching_course_units
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_course_agent_provenance_v1();
CREATE TRIGGER course_revision_agent_provenance_v1 BEFORE UPDATE OR DELETE ON atlas.teaching_course_unit_revisions
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_course_agent_provenance_v1();

-- Only the existing service command carrier may submit; kernel owns the
-- invocation and pending-principal confirmation. Exact replay must match.
CREATE FUNCTION atlas.prepare_course_authoring_proposal_service_v1(p_token_hash text,p_course uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $prepare$
DECLARE j jsonb;v atlas.agent_command_invocations%ROWTYPE;t jsonb;v_auth uuid;
BEGIN
 PERFORM atlas.validate_course_authoring_proposal_v1(p_proposal,p_course);
 t:=jsonb_build_object('kind','teaching_course','id',p_course::text);
 -- The legacy principals.person_id points to atlas.people. Resolve the
 -- canonical Person through the current Auth binding, not UUID coincidence.
 SELECT a.id INTO v_auth FROM atlas.delegated_agent_credentials c
 JOIN atlas.delegated_agent_authorizations a ON a.id=c.authorization_id
 JOIN atlas.principals pr ON pr.id=a.principal_id AND pr.status='active'
 JOIN reality.auth_person_bindings b ON b.auth_user_id=pr.user_id
  AND b.binding_state='active' AND b.retired_at IS NULL
 JOIN reality.entities e ON e.id=b.person_entity_id AND e.entity_kind='person' AND e.identity_state='canonical'
 JOIN atlas.teaching_courses tc ON tc.id=p_course AND tc.created_by_person_entity_id=e.id
  AND tc.status='active' AND tc.ledger_id IS NULL
 WHERE c.token_hash=lower(p_token_hash) AND c.credential_state='active'
  AND c.begins_at<=clock_timestamp() AND (c.expires_at IS NULL OR c.expires_at>clock_timestamp())
  AND a.authorization_state='active' AND a.ledger_id IS NULL AND a.delegating_seat_id IS NULL
  AND a.scope->'targetIds'=jsonb_build_array(p_course::text)
  AND a.scope->'targetKinds'=jsonb_build_array('teaching_course')
  AND titus.authoring_grant_current_active_v1(e.id);
 IF v_auth IS NULL
  OR NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(v_auth,
       'teaching.course.authoring.apply_proposal',1,t)->>'allowed')::boolean,false) THEN
  RAISE EXCEPTION 'exact authorized draft required' USING ERRCODE='42501'; END IF;
 j:=atlas.begin_delegated_agent_command_service_v1(p_token_hash,'teaching.course.authoring.apply_proposal',1,
  t,p_proposal,lower(p_proposal->>'proposalId'));
 SELECT * INTO STRICT v FROM atlas.agent_command_invocations WHERE id=(j->>'invocationId')::uuid;
 IF v.command_key<>'teaching.course.authoring.apply_proposal' OR v.command_version<>1
  OR v.target IS DISTINCT FROM t OR v.input IS DISTINCT FROM p_proposal OR
  NOT EXISTS(SELECT 1 FROM atlas.delegated_agent_credentials c WHERE c.id=v.credential_id
    AND c.token_hash=lower(p_token_hash) AND c.credential_state='active'
    AND c.begins_at<=clock_timestamp() AND (c.expires_at IS NULL OR c.expires_at>clock_timestamp())) THEN
  RAISE EXCEPTION 'proposal replay or credential mismatch' USING ERRCODE='42501'; END IF;
 -- Do not return manuscript, authority details, or result to a stale replay.
 IF NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(v.authorization_id,v.command_key,1,t)->>'allowed')::boolean,false)
 THEN RAISE EXCEPTION 'proposal scope unavailable' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('invocationId',v.id,'state',v.invocation_state,'replayed',j->'replayed',
  'confirmationRequired',v.confirmation_required);
END $prepare$;

-- Atomic apply: no forged auth.uid(), no arbitrary target, no separate Course store.
-- Human fields are the confirming principal; carrier and source basis are retained
-- through the immutable invocation. The same Course row lock as signed self writes
-- serializes every Unit edit or reorder. Any exception rolls back ALL writes.
CREATE FUNCTION atlas.apply_course_authoring_proposal_service_v1(p_token_hash text,p_invocation uuid,p_proposal jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO pg_catalog AS $apply$
DECLARE v atlas.agent_command_invocations%ROWTYPE;a atlas.delegated_agent_authorizations%ROWTYPE;
 c atlas.delegated_agent_credentials%ROWTYPE;pr atlas.principals%ROWTYPE;
 cid uuid;person uuid;u uuid;req uuid;i jsonb;j jsonb;latest int;expected int;pos int;
 n int;new_count int;binding_ids uuid[];
BEGIN
 SELECT * INTO v FROM atlas.agent_command_invocations WHERE id=p_invocation FOR UPDATE;
 IF NOT FOUND OR v.command_key<>'teaching.course.authoring.apply_proposal' OR v.command_version<>1
  OR v.input IS DISTINCT FROM p_proposal OR v.target IS NULL THEN
  RAISE EXCEPTION 'exact invocation required' USING ERRCODE='42501'; END IF;
 cid:=(v.target->>'id')::uuid;
 IF v.target IS DISTINCT FROM jsonb_build_object('kind','teaching_course','id',cid::text)
  OR v.idempotency_key IS DISTINCT FROM lower(p_proposal->>'proposalId') THEN
  RAISE EXCEPTION 'exact Course target required' USING ERRCODE='42501'; END IF;
 PERFORM atlas.validate_course_authoring_proposal_v1(p_proposal,cid);
 SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=v.authorization_id FOR SHARE;
 SELECT * INTO STRICT c FROM atlas.delegated_agent_credentials WHERE id=v.credential_id FOR SHARE;
 SELECT * INTO STRICT pr FROM atlas.principals WHERE id=v.principal_id FOR SHARE;
 PERFORM 1 FROM atlas.delegated_agent_carriers WHERE id=v.carrier_id AND status='active' FOR SHARE;
 IF NOT FOUND OR c.token_hash IS DISTINCT FROM lower(p_token_hash) OR c.authorization_id<>a.id
  OR a.carrier_id<>v.carrier_id OR a.principal_id<>pr.id OR a.ledger_id IS NOT NULL OR v.ledger_id IS NOT NULL
  OR a.delegating_seat_id IS NOT NULL OR v.delegating_seat_id IS NOT NULL
  OR a.authorization_state<>'active' OR a.begins_at>clock_timestamp()
  OR (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp()) OR c.credential_state<>'active'
  OR c.begins_at>clock_timestamp() OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR pr.status<>'active' OR NOT v.confirmation_required
  OR v.confirmed_at IS NULL OR v.confirmed_by_user_id IS DISTINCT FROM pr.user_id
  OR NOT (v.command_key=ANY(a.allowed_command_keys)) OR v.command_key=ANY(a.denied_command_keys)
  OR a.scope->'targetIds' IS DISTINCT FROM jsonb_build_array(cid::text)
  OR a.scope->'targetKinds' IS DISTINCT FROM jsonb_build_array('teaching_course')
  OR NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,v.command_key,1,v.target)->>'allowed')::boolean,false) THEN
  RAISE EXCEPTION 'current confirmed and exact scoped delegation required' USING ERRCODE='42501'; END IF;
 -- Resolve from the authenticated principal's canonical source binding.
 SELECT array_agg(b.person_entity_id) INTO binding_ids FROM (
  SELECT person_entity_id FROM reality.auth_person_bindings
  WHERE auth_user_id=pr.user_id AND binding_state='active' AND retired_at IS NULL FOR SHARE
 ) b;
 IF coalesce(cardinality(binding_ids),0)<>1 THEN
  RAISE EXCEPTION 'unique current Person binding required' USING ERRCODE='42501'; END IF;
 person:=binding_ids[1];
 PERFORM 1 FROM reality.entities WHERE id=person AND entity_kind='person' AND identity_state='canonical' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'canonical Person required' USING ERRCODE='42501'; END IF;
 -- Lock the grant or founding-owner relation which the released product gate reads.
 PERFORM 1 FROM titus.course_authoring_access_grants WHERE person_entity_id=person FOR SHARE;
 PERFORM 1 FROM reality.responsibility_relations WHERE carrier_person_entity_id=person
  AND responsibility_key='titus_private_pilot_issuance' AND jurisdiction_kind='domain'
  AND jurisdiction_domain='titus' FOR SHARE;
 IF NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'current Titus access required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM atlas.teaching_courses WHERE id=cid AND created_by_person_entity_id=person
  AND status='active' AND ledger_id IS NULL FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active original Course required' USING ERRCODE='42501'; END IF;
 -- Wall-clock validity can change while awaiting the Course lock.
 IF (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp())
  OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'delegation expired before Course write' USING ERRCODE='42501'; END IF;
 IF v.invocation_state='succeeded' THEN
  j:=atlas.course_authoring_receipt_v1(v.id);
  IF v.result IS DISTINCT FROM j THEN RAISE EXCEPTION 'unverified completion' USING ERRCODE='55000'; END IF;
  RETURN j;
 END IF;
 IF v.invocation_state<>'authorized' THEN RAISE EXCEPTION 'confirmed unexecuted invocation required' USING ERRCODE='42501'; END IF;
 SELECT count(*),coalesce(max(display_position),0) INTO n,pos FROM atlas.teaching_course_units WHERE course_id=cid;
 SELECT count(*) INTO new_count FROM jsonb_array_elements(p_proposal->'items') el WHERE el->>'operation'='append_unit';
 IF n+new_count>100 THEN RAISE EXCEPTION 'Course Unit limit' USING ERRCODE='22023'; END IF;
 PERFORM atlas.mark_delegated_agent_command_executing_service_v1(v.id);
 FOR i IN SELECT value FROM jsonb_array_elements(p_proposal->'items') LOOP
  req:=(i->>'requestId')::uuid;
  IF EXISTS(SELECT 1 FROM atlas.teaching_course_units WHERE course_id=cid AND create_request_id=req)
   OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions rr JOIN atlas.teaching_course_units un ON un.unit_id=rr.unit_id
       WHERE un.course_id=cid AND rr.edit_request_id=req) THEN
   RAISE EXCEPTION 'request already used by another write' USING ERRCODE='23505'; END IF;
  IF i->>'operation'='append_unit' THEN
   pos:=pos+1024;expected:=0;
   INSERT INTO atlas.teaching_course_units(course_id,create_request_id,kind,title,display_position,
     created_by_person_entity_id,created_by_auth_user_id,created_by_agent_invocation_id)
    VALUES(cid,req,i->>'kind',i->>'title',pos,person,pr.user_id,v.id) RETURNING unit_id INTO u;
  ELSE
   u:=(i->>'unitId')::uuid;expected:=(i->>'expectedRevision')::integer;
   PERFORM 1 FROM atlas.teaching_course_units WHERE unit_id=u AND course_id=cid AND kind=i->>'kind' AND title=i->>'title';
   IF NOT FOUND THEN RAISE EXCEPTION 'exact Unit required' USING ERRCODE='42501'; END IF;
  END IF;
  SELECT coalesce(max(revision_number),0) INTO latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=u;
  IF latest<>expected THEN RAISE EXCEPTION 'stale Unit revision' USING ERRCODE='40001'; END IF;
  INSERT INTO atlas.teaching_course_unit_revisions(unit_id,edit_request_id,based_on_revision,revision_number,body_text,
    recorded_by_person_entity_id,recorded_by_auth_user_id,recorded_by_agent_invocation_id)
   VALUES(u,req,expected,expected+1,i->>'text',person,pr.user_id,v.id);
 END LOOP;
 IF (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp())
  OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
  OR NOT titus.authoring_grant_current_active_v1(person) THEN
  RAISE EXCEPTION 'delegation expired during Course write' USING ERRCODE='42501'; END IF;
 j:=atlas.course_authoring_receipt_v1(v.id);
 PERFORM atlas.complete_delegated_agent_command_service_v1(v.id,true,j,'{}'::jsonb);
 RETURN j;
END $apply$;

REVOKE ALL ON FUNCTION atlas.prepare_course_authoring_proposal_service_v1(text,uuid,jsonb),
 atlas.apply_course_authoring_proposal_service_v1(text,uuid,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.prepare_course_authoring_proposal_service_v1(text,uuid,jsonb),
 atlas.apply_course_authoring_proposal_service_v1(text,uuid,jsonb) TO service_role;
INSERT INTO atlas.agent_command_definitions(command_key,command_version,label,scope_kind,execution_class,
 confirmation_requirement,handler_key,status,input_contract,target_contract)
 VALUES('teaching.course.authoring.apply_proposal',1,'Apply reviewed Course draft proposal','personal','commit',
 'principal_explicit','teaching.course.authoring.apply_proposal.v1','active',
 '{"contractVersion":"titus_course_authoring_proposal_v1","maxItems":12}'::jsonb,'{"kind":"teaching_course"}'::jsonb);

-- Signed, Course-scoped projection of Atlas's existing principal queue.
-- No new invocation store, authority issuer, or delegated executor is exposed.
CREATE FUNCTION public.shared_teaching_course_proposals_self_api_v1(p_course_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $queue$
DECLARE q record; result jsonb:='[]'::jsonb; n int:=0; more boolean:=false;
BEGIN
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,false);
 PERFORM titus.require_authoring_access_v1();
 IF NOT EXISTS(SELECT 1 FROM atlas.teaching_courses WHERE id=p_course_id AND status='active' AND ledger_id IS NULL)
 THEN RAISE EXCEPTION 'active personal Course required' USING ERRCODE='42501'; END IF;
 FOR q IN SELECT x.* FROM atlas.delegated_agent_pending_confirmations_self_api_v1() x
  WHERE x.command_key='teaching.course.authoring.apply_proposal' AND x.command_version=1
   AND x.ledger_id IS NULL AND x.target=jsonb_build_object('kind','teaching_course','id',p_course_id::text)
  ORDER BY x.created_at,x.invocation_id LIMIT 5
 LOOP
  -- Invalid requests cannot be approved. Do not disclose malformed input.
  BEGIN PERFORM atlas.validate_course_authoring_proposal_v1(q.input,p_course_id);
  EXCEPTION WHEN invalid_parameter_value OR invalid_text_representation THEN CONTINUE; END;
  IF n>=4 THEN more:=true; EXIT; END IF;
  result:=result||jsonb_build_array(jsonb_build_object('invocationId',q.invocation_id,
    'carrierName',q.carrier_name,'createdAt',q.created_at,'proposal',q.input));
  n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('contractVersion','shared_course_authoring_queue_v1','courseId',p_course_id,
  'proposals',result,'more',more);
END $queue$;

-- The reviewed invocation is immutable; the browser cannot supply new text,
-- target, carrier, or principal to a confirmation. Use the original Atlas
-- lifecycle functions. This endpoint does not execute any Course write.
CREATE FUNCTION public.shared_teaching_course_proposal_decide_self_api_v1(
 p_course_id uuid,p_invocation_id uuid,p_proposal_id uuid,p_decision text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog AS $decide$
DECLARE v atlas.agent_command_invocations%ROWTYPE;a atlas.delegated_agent_authorizations%ROWTYPE;
 c atlas.delegated_agent_credentials%ROWTYPE;i jsonb;uid uuid;latest int;j jsonb;n int;adds int;
BEGIN
 IF p_invocation_id IS NULL OR p_proposal_id IS NULL OR p_decision IS NULL
   OR p_decision NOT IN ('confirm','reject') THEN
  RAISE EXCEPTION 'exact proposal decision required' USING ERRCODE='22023'; END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,false);
 PERFORM titus.require_authoring_access_v1();
 -- Match apply's lock order (invocation before Course).
 SELECT inv.* INTO v FROM atlas.agent_command_invocations inv
 JOIN atlas.principals pr ON pr.id=inv.principal_id AND pr.user_id=auth.uid() AND pr.status='active'
 WHERE inv.id=p_invocation_id AND inv.command_key='teaching.course.authoring.apply_proposal'
  AND inv.command_version=1 AND inv.ledger_id IS NULL AND inv.delegating_seat_id IS NULL
  AND inv.target=jsonb_build_object('kind','teaching_course','id',p_course_id::text)
  AND inv.input->>'proposalId'~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  AND lower(inv.input->>'proposalId')=p_proposal_id::text
  FOR UPDATE OF inv;
 IF NOT FOUND THEN RAISE EXCEPTION 'owned Course proposal required' USING ERRCODE='42501'; END IF;
 IF p_decision='confirm' THEN
  SELECT * INTO STRICT a FROM atlas.delegated_agent_authorizations WHERE id=v.authorization_id FOR SHARE;
  SELECT * INTO STRICT c FROM atlas.delegated_agent_credentials WHERE id=v.credential_id FOR SHARE;
 END IF;
 PERFORM atlas.require_private_course_author_self_v1(p_course_id,true);
 IF p_decision='confirm' AND v.invocation_state IN ('authorized','executing','succeeded')
   AND v.confirmed_at IS NOT NULL AND v.confirmed_by_user_id=auth.uid() THEN
  RETURN jsonb_build_object('contractVersion','shared_course_authoring_decision_v1','courseId',p_course_id,
   'invocationId',v.id,'proposalId',p_proposal_id,'decision',p_decision,'state',v.invocation_state,'replayed',true);
 END IF;
 IF p_decision='reject' AND v.invocation_state='cancelled' THEN
  RETURN jsonb_build_object('contractVersion','shared_course_authoring_decision_v1','courseId',p_course_id,
   'invocationId',v.id,'proposalId',p_proposal_id,'decision',p_decision,'state','cancelled','replayed',true);
 END IF;
 IF v.invocation_state<>'needs_confirmation' THEN
  RAISE EXCEPTION 'proposal no longer awaiting confirmation' USING ERRCODE='40001'; END IF;
 IF p_decision='reject' THEN
  j:=atlas.reject_delegated_agent_command_self_api_v1(v.id,'Rejected in Course review');
 ELSE
  PERFORM atlas.validate_course_authoring_proposal_v1(v.input,p_course_id);
  IF NOT v.confirmation_required OR a.principal_id<>v.principal_id OR a.carrier_id<>v.carrier_id
   OR c.authorization_id<>a.id OR a.authorization_state<>'active' OR a.ledger_id IS NOT NULL
   OR a.delegating_seat_id IS NOT NULL OR a.scope->'targetIds' IS DISTINCT FROM jsonb_build_array(p_course_id::text)
   OR a.scope->'targetKinds' IS DISTINCT FROM jsonb_build_array('teaching_course')
   OR a.begins_at>clock_timestamp() OR (a.ends_at IS NOT NULL AND a.ends_at<=clock_timestamp())
   OR c.credential_state<>'active' OR c.begins_at>clock_timestamp()
   OR (c.expires_at IS NOT NULL AND c.expires_at<=clock_timestamp())
   OR NOT coalesce((atlas.evaluate_delegated_agent_command_target_authority_v1(a.id,v.command_key,1,v.target)->>'allowed')::boolean,false)
  THEN RAISE EXCEPTION 'delegation no longer available' USING ERRCODE='42501'; END IF;
  SELECT count(*) INTO n FROM atlas.teaching_course_units WHERE course_id=p_course_id;
  SELECT count(*) INTO adds FROM jsonb_array_elements(v.input->'items') el WHERE el->>'operation'='append_unit';
  IF n+adds>100 THEN RAISE EXCEPTION 'Course capacity changed' USING ERRCODE='40001'; END IF;
  FOR i IN SELECT value FROM jsonb_array_elements(v.input->'items') LOOP
   IF EXISTS(SELECT 1 FROM atlas.teaching_course_units WHERE course_id=p_course_id AND create_request_id=(i->>'requestId')::uuid)
    OR EXISTS(SELECT 1 FROM atlas.teaching_course_unit_revisions rr JOIN atlas.teaching_course_units un ON un.unit_id=rr.unit_id
      WHERE un.course_id=p_course_id AND rr.edit_request_id=(i->>'requestId')::uuid)
   THEN RAISE EXCEPTION 'proposal request already used' USING ERRCODE='40001'; END IF;
   IF i->>'operation'='revise_unit' THEN
    uid:=(i->>'unitId')::uuid;
    PERFORM 1 FROM atlas.teaching_course_units WHERE course_id=p_course_id AND unit_id=uid AND kind=i->>'kind' AND title=i->>'title';
    IF NOT FOUND THEN RAISE EXCEPTION 'proposal Unit changed' USING ERRCODE='40001'; END IF;
    SELECT coalesce(max(revision_number),0) INTO latest FROM atlas.teaching_course_unit_revisions WHERE unit_id=uid;
    IF latest<>(i->>'expectedRevision')::int THEN RAISE EXCEPTION 'proposal revision changed' USING ERRCODE='40001'; END IF;
   END IF;
  END LOOP;
  j:=atlas.confirm_delegated_agent_command_self_api_v1(v.id);
 END IF;
 IF j->>'invocationId' IS DISTINCT FROM v.id::text OR
   j->>'state' IS DISTINCT FROM (CASE WHEN p_decision='confirm' THEN 'authorized' ELSE 'cancelled' END)
 THEN RAISE EXCEPTION 'unexpected Atlas decision receipt' USING ERRCODE='55000'; END IF;
 RETURN jsonb_build_object('contractVersion','shared_course_authoring_decision_v1','courseId',p_course_id,
  'invocationId',v.id,'proposalId',p_proposal_id,'decision',p_decision,'state',j->>'state','replayed',false);
END $decide$;
REVOKE ALL ON FUNCTION public.shared_teaching_course_proposals_self_api_v1(uuid),
 public.shared_teaching_course_proposal_decide_self_api_v1(uuid,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shared_teaching_course_proposals_self_api_v1(uuid),
 public.shared_teaching_course_proposal_decide_self_api_v1(uuid,uuid,uuid,text) TO authenticated;

COMMIT;
