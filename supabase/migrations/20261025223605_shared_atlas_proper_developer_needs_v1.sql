-- Shared Atlas Proper developer work: a real implementation record without inventing
-- a paid institutional case or granting access to original Foundry source.
-- Depends on the signed, metadata-only existing discovery inventory RPC.
BEGIN;

CREATE TABLE atlas.implementation_discovery_needs_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_entity_id uuid NOT NULL REFERENCES reality.entities(id),
  author_user_id uuid NOT NULL REFERENCES auth.users(id),
  request_id uuid NOT NULL,
  title text NOT NULL CHECK (length(btrim(title)) BETWEEN 3 AND 140),
  detail text NOT NULL CHECK (length(btrim(detail)) BETWEEN 10 AND 4000),
  state text NOT NULL DEFAULT 'identified' CHECK (
    state IN ('identified','scoping','building','blocked','ready_for_test','test_observed')
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (author_user_id,request_id)
);
CREATE INDEX implementation_discovery_needs_subject_state_idx
  ON atlas.implementation_discovery_needs_v1(subject_entity_id,state,created_at,id);

CREATE TABLE atlas.implementation_discovery_need_activity_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  need_id uuid NOT NULL REFERENCES atlas.implementation_discovery_needs_v1(id),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  action_kind text NOT NULL CHECK(action_kind IN ('opened','note','state_changed')),
  prior_state text,
  next_state text,
  note text NOT NULL CHECK (length(btrim(note)) BETWEEN 3 AND 4000),
  recorded_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX implementation_discovery_need_activity_need_time_idx
  ON atlas.implementation_discovery_need_activity_v1(need_id,recorded_at,id);
ALTER TABLE atlas.implementation_discovery_needs_v1 ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.implementation_discovery_need_activity_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.implementation_discovery_needs_v1 FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON atlas.implementation_discovery_need_activity_v1 FROM PUBLIC,anon,authenticated,service_role;

-- Reuse the already signed-practitioner guarded institutional discovery list,
-- including active session revocation check, canonical subject and active Ledger
-- reconciliation, rather than implementing a second broad access exception.
CREATE FUNCTION atlas.implementation_discovery_subject_guard_self_v1(p_subject_entity_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','reality','auth','pg_temp'
AS $function$
DECLARE v_catalog jsonb;
BEGIN
 IF p_subject_entity_id IS NULL THEN
   RAISE EXCEPTION 'An established institutional subject is required' USING ERRCODE='22023';
 END IF;
 v_catalog:=atlas.implementation_foundry_discovery_inventory_self_api_v1();
 IF NOT EXISTS (
   SELECT 1 FROM jsonb_array_elements(v_catalog->'items') x
   WHERE x->>'subjectEntityId'=p_subject_entity_id::text
 ) THEN
   RAISE EXCEPTION 'Institution not in verified operator discovery scope' USING ERRCODE='42501';
 END IF;
 RETURN v_catalog;
END;
$function$;

CREATE FUNCTION atlas.implementation_discovery_subject_work_self_api_v1(p_subject_entity_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','reality','pg_temp'
AS $function$
DECLARE v_catalog jsonb; v_result jsonb;
BEGIN
 v_catalog:=atlas.implementation_discovery_subject_guard_self_v1(p_subject_entity_id);
 SELECT jsonb_build_object(
   'ok',true,'contractVersion','atlas_proper_developer_work_v1',
   'subjectEntityId',p_subject_entity_id,
   'subjectLabel',e.display_name,
   'caseCreated',false,'sourceReadAuthorized',false,
   'operatingRealityMutated',false,'originalTestimonyIncluded',false,
   'items',coalesce((
     SELECT jsonb_agg(jsonb_build_object(
       'id',w.id,'title',w.title,'detail',w.detail,'state',w.state,
       'createdAt',w.created_at,'updatedAt',w.updated_at,
       'authorUserId',w.author_user_id,
       'activity',coalesce((
         SELECT jsonb_agg(jsonb_build_object(
          'id',a.id,'kind',a.action_kind,'priorState',a.prior_state,
          'nextState',a.next_state,'note',a.note,
          'recordedAt',a.recorded_at,'actorUserId',a.actor_user_id
         ) ORDER BY a.recorded_at,a.id)
         FROM atlas.implementation_discovery_need_activity_v1 a WHERE a.need_id=w.id
       ),'[]'::jsonb)
     ) ORDER BY w.created_at,w.id)
     FROM atlas.implementation_discovery_needs_v1 w
     WHERE w.subject_entity_id=p_subject_entity_id
   ),'[]'::jsonb)
 ) INTO v_result
 FROM reality.entities e WHERE e.id=p_subject_entity_id;
 RETURN v_result;
END;
$function$;

CREATE FUNCTION atlas.create_implementation_discovery_need_self_api_v1(
 p_subject_entity_id uuid,p_request_id uuid,p_title text,p_detail text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','pg_temp'
AS $function$
DECLARE v_user uuid:=auth.uid(); v_existing atlas.implementation_discovery_needs_v1%rowtype;
        v_id uuid; v_inserted boolean:=false;
BEGIN
 PERFORM atlas.implementation_discovery_subject_guard_self_v1(p_subject_entity_id);
 IF p_request_id IS NULL OR p_title IS NULL OR p_detail IS NULL
   OR length(btrim(p_title)) NOT BETWEEN 3 AND 140
   OR length(btrim(p_detail)) NOT BETWEEN 10 AND 4000
 THEN RAISE EXCEPTION 'A stable request, concise title, and concrete need are required' USING ERRCODE='22023';
 END IF;

 INSERT INTO atlas.implementation_discovery_needs_v1(
   subject_entity_id,author_user_id,request_id,title,detail)
 VALUES(p_subject_entity_id,v_user,p_request_id,btrim(p_title),btrim(p_detail))
 ON CONFLICT(author_user_id,request_id) DO NOTHING
 RETURNING id INTO v_id;
 IF v_id IS NOT NULL THEN
   v_inserted:=true;
   INSERT INTO atlas.implementation_discovery_need_activity_v1(
     need_id,actor_user_id,action_kind,next_state,note)
   VALUES(v_id,v_user,'opened','identified','Developer-staged implementation need; not original source testimony or approved client requirement.');
 END IF;
 SELECT * INTO v_existing FROM atlas.implementation_discovery_needs_v1
 WHERE author_user_id=v_user AND request_id=p_request_id;
 IF v_existing.subject_entity_id<>p_subject_entity_id
    OR v_existing.title<>btrim(p_title) OR v_existing.detail<>btrim(p_detail)
 THEN RAISE EXCEPTION 'Request identity already used with different contents' USING ERRCODE='22023';
 END IF;
 RETURN jsonb_build_object('ok',true,'needId',v_existing.id,'created',v_inserted,
     'state',v_existing.state,'caseCreated',false,'sourceReadAuthorized',false);
END;
$function$;

CREATE FUNCTION atlas.record_implementation_discovery_activity_self_api_v1(
 p_need_id uuid,p_request_id uuid,p_action text,p_note text,p_next_state text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','auth','pg_temp'
AS $function$
DECLARE v_user uuid:=auth.uid();v_need atlas.implementation_discovery_needs_v1%rowtype;
        v_seen uuid;v_id uuid;
BEGIN
 IF p_need_id IS NULL OR p_request_id IS NULL OR p_action NOT IN ('note','state_changed')
    OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 10 AND 4000
 THEN RAISE EXCEPTION 'Stable request, note, and valid action required' USING ERRCODE='22023'; END IF;

 SELECT * INTO v_need FROM atlas.implementation_discovery_needs_v1 WHERE id=p_need_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Need not found' USING ERRCODE='42501'; END IF;
 PERFORM atlas.implementation_discovery_subject_guard_self_v1(v_need.subject_entity_id);
 IF p_action='state_changed' THEN
   IF p_next_state IS NULL OR p_next_state NOT IN (
      'identified','scoping','building','blocked','ready_for_test','test_observed')
   THEN RAISE EXCEPTION 'Invalid developer work state' USING ERRCODE='22023'; END IF;
 ELSE
   IF p_next_state IS NOT NULL THEN RAISE EXCEPTION 'Note cannot change work state' USING ERRCODE='22023'; END IF;
 END IF;
 -- Request UUID is carried in append-only event, and duplicate retries only
 -- return the same event. A conflicting repeat is rejected.
 SELECT a.id INTO v_seen FROM atlas.implementation_discovery_need_activity_v1 a
 WHERE a.actor_user_id=v_user AND a.need_id=p_need_id AND a.id=p_request_id
   AND a.action_kind=p_action AND a.note=btrim(p_note)
   AND a.next_state IS NOT DISTINCT FROM p_next_state;
 IF v_seen IS NOT NULL THEN
   RETURN jsonb_build_object('ok',true,'activityId',v_seen,'replayed',true);
 END IF;
 IF EXISTS (SELECT 1 FROM atlas.implementation_discovery_need_activity_v1
    WHERE id=p_request_id) THEN
   RAISE EXCEPTION 'A previously used activity request cannot be changed' USING ERRCODE='22023';
 END IF;
 IF p_action='state_changed' AND v_need.state=p_next_state THEN
   RAISE EXCEPTION 'State is unchanged; use a note instead' USING ERRCODE='22023';
 END IF;
 INSERT INTO atlas.implementation_discovery_need_activity_v1(
  id,need_id,actor_user_id,action_kind,prior_state,next_state,note)
 VALUES(p_request_id,p_need_id,v_user,p_action,
  CASE WHEN p_action='state_changed' THEN v_need.state ELSE NULL END,
  p_next_state,btrim(p_note)) RETURNING id INTO v_id;
 IF p_action='state_changed' THEN
   UPDATE atlas.implementation_discovery_needs_v1 SET state=p_next_state,updated_at=now()
    WHERE id=p_need_id;
 END IF;
 RETURN jsonb_build_object('ok',true,'activityId',v_id,'replayed',false,
   'sourceReadAuthorized',false,'caseClosed',false,'customerApprovalInferred',false);
END;
$function$;

CREATE FUNCTION public.implementation_discovery_subject_work_self_api_v1(p_subject_entity_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $function$ SELECT atlas.implementation_discovery_subject_work_self_api_v1(p_subject_entity_id); $function$;
CREATE FUNCTION public.create_implementation_discovery_need_self_api_v1(
 p_subject_entity_id uuid,p_request_id uuid,p_title text,p_detail text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $function$ SELECT atlas.create_implementation_discovery_need_self_api_v1(p_subject_entity_id,p_request_id,p_title,p_detail); $function$;
CREATE FUNCTION public.record_implementation_discovery_activity_self_api_v1(
 p_need_id uuid,p_request_id uuid,p_action text,p_note text,p_next_state text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas'
AS $function$ SELECT atlas.record_implementation_discovery_activity_self_api_v1(p_need_id,p_request_id,p_action,p_note,p_next_state); $function$;

REVOKE ALL ON FUNCTION atlas.implementation_discovery_subject_guard_self_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.implementation_discovery_subject_work_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.record_implementation_discovery_activity_self_api_v1(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.implementation_discovery_subject_work_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.record_implementation_discovery_activity_self_api_v1(uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.implementation_discovery_subject_guard_self_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.implementation_discovery_subject_work_self_api_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.record_implementation_discovery_activity_self_api_v1(uuid,uuid,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.implementation_discovery_subject_work_self_api_v1(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_implementation_discovery_need_self_api_v1(uuid,uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_implementation_discovery_activity_self_api_v1(uuid,uuid,text,text,text) TO authenticated;
COMMIT;
