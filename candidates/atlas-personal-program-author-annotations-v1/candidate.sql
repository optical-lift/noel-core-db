-- Atlas Program margin annotations v1: reviewed source candidate only.
-- No original Program/version changes, recipient relationship or clinical evidence.
-- Generated version and deployment must use the governed noel-core-db release path.
BEGIN;

CREATE TABLE atlas.personal_program_author_note_events (
 event_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 note_id uuid NOT NULL,
 revision integer NOT NULL CHECK (revision > 0),
 program_id uuid NOT NULL REFERENCES atlas.personal_training_programs(id) ON DELETE RESTRICT,
 component_key text,
 anchor_version_id uuid NOT NULL REFERENCES atlas.personal_training_program_versions(id) ON DELETE RESTRICT,
 anchor_excerpt text,
 body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 6000),
 standing text NOT NULL CHECK (standing IN ('open','resolved','superseded')),
 visibility text NOT NULL DEFAULT 'author_private' CHECK (visibility = 'author_private'),
 actor_auth_user_id uuid NOT NULL,
 request_key text NOT NULL CHECK (length(request_key) BETWEEN 8 AND 160),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT program_note_component_key_bound CHECK
    (component_key IS NULL OR length(btrim(component_key)) BETWEEN 1 AND 120),
 CONSTRAINT program_note_excerpt_bound CHECK
    (anchor_excerpt IS NULL OR (component_key IS NOT NULL AND length(btrim(anchor_excerpt)) BETWEEN 1 AND 500)),
 CONSTRAINT program_note_revision_unique UNIQUE(note_id,revision),
 CONSTRAINT program_note_request_unique UNIQUE(program_id,request_key)
);
CREATE INDEX personal_program_author_note_events_program_idx
 ON atlas.personal_program_author_note_events(program_id,note_id,revision DESC);

ALTER TABLE atlas.personal_program_author_note_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.personal_program_author_note_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_program_author_note_events FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.personal_program_author_note_guard_v1(p_program_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO '' AS $fn$
DECLARE v_principal uuid; v_owner uuid;
BEGIN
 v_principal := atlas.personal_training_author_guard_v1();
 SELECT p.owner_principal_id INTO v_owner
 FROM atlas.personal_training_programs p
 WHERE p.id=p_program_id AND p.owner_principal_id=v_principal
  AND p.draft_packet->>'contract'='personal_program_author_source_v2';
 IF v_owner IS NULL THEN RAISE EXCEPTION 'Author Program unavailable'
   USING ERRCODE='42501'; END IF;
 RETURN v_owner;
END;
$fn$;

-- Notes attach to a real previously approved Program version and component key.
-- The component may move or disappear from later drafts; its original anchor remains.
CREATE FUNCTION atlas.personal_program_author_note_create_self_v1(
 p_program_id uuid, p_anchor_version_id uuid, p_component_key text,
 p_anchor_excerpt text, p_body text, p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO '' AS $fn$
DECLARE v_packet jsonb; v_component jsonb;
 v_existing atlas.personal_program_author_note_events%ROWTYPE; v_id uuid;
BEGIN
 PERFORM atlas.personal_program_author_note_guard_v1(p_program_id);
 IF length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
  OR length(btrim(coalesce(p_body,''))) NOT BETWEEN 1 AND 6000
  OR (p_component_key IS NOT NULL AND length(btrim(p_component_key)) NOT BETWEEN 1 AND 120)
  OR (p_anchor_excerpt IS NOT NULL AND (p_component_key IS NULL
   OR length(btrim(p_anchor_excerpt)) NOT BETWEEN 1 AND 500))
 THEN RAISE EXCEPTION 'Invalid author annotation' USING ERRCODE='22023'; END IF;
 SELECT v.approved_packet INTO v_packet FROM atlas.personal_training_program_versions v
 WHERE v.id=p_anchor_version_id AND v.program_id=p_program_id;
 IF v_packet IS NULL OR v_packet->>'contract'<>'personal_program_author_source_v2'
 THEN RAISE EXCEPTION 'Approved source version unavailable' USING ERRCODE='42501'; END IF;
 IF p_component_key IS NOT NULL THEN
  SELECT item.value INTO v_component FROM
   pg_catalog.jsonb_array_elements(v_packet->'components') item
  WHERE item.value->>'key'=p_component_key LIMIT 1;
  IF v_component IS NULL
  THEN RAISE EXCEPTION 'Component anchor unavailable' USING ERRCODE='22023'; END IF;
  IF p_anchor_excerpt IS NOT NULL AND
   pg_catalog.strpos(coalesce(v_component->>'instructions',''),p_anchor_excerpt)=0
   AND pg_catalog.strpos(coalesce(v_component->>'sourceExcerpt',''),p_anchor_excerpt)=0
  THEN RAISE EXCEPTION 'Passage does not occur in approved component'
    USING ERRCODE='22023'; END IF;
 END IF;
 -- Two retries with one request key must serialize before inspecting receipts.
 PERFORM pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtextextended(p_program_id::text||':'||p_request_key,0));
 SELECT * INTO v_existing FROM atlas.personal_program_author_note_events
 WHERE program_id=p_program_id AND request_key=p_request_key;
 IF v_existing.event_id IS NOT NULL THEN
  IF v_existing.revision<>1 OR v_existing.anchor_version_id<>p_anchor_version_id
   OR v_existing.component_key IS DISTINCT FROM p_component_key
   OR v_existing.anchor_excerpt IS DISTINCT FROM p_anchor_excerpt
   OR v_existing.body<>btrim(p_body) THEN
   RAISE EXCEPTION 'Annotation request conflict' USING ERRCODE='23505';
  END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,'noteId',v_existing.note_id,
    'revision',1,'standing','open','replay',true);
 END IF;
 v_id:=pg_catalog.gen_random_uuid();
 INSERT INTO atlas.personal_program_author_note_events
 (note_id,revision,program_id,component_key,anchor_version_id,anchor_excerpt,
  body,standing,actor_auth_user_id,request_key)
 VALUES(v_id,1,p_program_id,p_component_key,p_anchor_version_id,p_anchor_excerpt,
 btrim(p_body),'open',auth.uid(),p_request_key);
 RETURN pg_catalog.jsonb_build_object('ok',true,'noteId',v_id,'revision',1,
   'standing','open','visibility','author_private');
END;
$fn$;

-- Each edit, resolution, reopening or supersession is append-only.
-- Advisory locking serializes concurrent writers; stale revisions fail closed.
CREATE FUNCTION atlas.personal_program_author_note_revise_self_v1(
 p_program_id uuid, p_note_id uuid, p_expected_revision integer,
 p_body text, p_standing text, p_request_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO '' AS $fn$
DECLARE v_latest atlas.personal_program_author_note_events%ROWTYPE;
 v_replay atlas.personal_program_author_note_events%ROWTYPE;
BEGIN
 PERFORM atlas.personal_program_author_note_guard_v1(p_program_id);
 IF p_note_id IS NULL OR p_expected_revision IS NULL OR p_expected_revision<1
  OR length(btrim(coalesce(p_body,''))) NOT BETWEEN 1 AND 6000
  OR coalesce(p_standing,'') NOT IN ('open','resolved','superseded')
  OR length(coalesce(p_request_key,'')) NOT BETWEEN 8 AND 160
 THEN RAISE EXCEPTION 'Invalid annotation revision' USING ERRCODE='22023'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_note_id::text,0));
 SELECT * INTO v_latest FROM atlas.personal_program_author_note_events
  WHERE note_id=p_note_id AND program_id=p_program_id ORDER BY revision DESC LIMIT 1;
 IF v_latest.event_id IS NULL
 THEN RAISE EXCEPTION 'Author annotation unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_replay FROM atlas.personal_program_author_note_events
 WHERE program_id=p_program_id AND request_key=p_request_key;
 IF v_replay.event_id IS NOT NULL THEN
  IF v_replay.note_id<>p_note_id OR v_replay.revision<>p_expected_revision+1
   OR v_replay.body<>btrim(p_body) OR v_replay.standing<>p_standing
  THEN RAISE EXCEPTION 'Annotation request conflict' USING ERRCODE='23505'; END IF;
  IF v_latest.revision<>v_replay.revision
  THEN RAISE EXCEPTION 'Historical annotation replay is stale' USING ERRCODE='40001'; END IF;
  RETURN pg_catalog.jsonb_build_object('ok',true,'noteId',p_note_id,
    'revision',v_replay.revision,'standing',v_replay.standing,'replay',true);
 END IF;
 IF v_latest.revision<>p_expected_revision
 THEN RAISE EXCEPTION 'Stale annotation revision' USING ERRCODE='40001'; END IF;
 INSERT INTO atlas.personal_program_author_note_events
 (note_id,revision,program_id,component_key,anchor_version_id,anchor_excerpt,
 body,standing,actor_auth_user_id,request_key)
 VALUES(p_note_id,p_expected_revision+1,p_program_id,
 v_latest.component_key,v_latest.anchor_version_id,v_latest.anchor_excerpt,
 btrim(p_body),p_standing,auth.uid(),p_request_key);
 RETURN pg_catalog.jsonb_build_object('ok',true,'noteId',p_note_id,
   'revision',p_expected_revision+1,'standing',p_standing,'visibility','author_private');
END;
$fn$;

CREATE FUNCTION atlas.personal_program_author_notes_read_self_v1(p_program_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO '' AS $fn$
DECLARE v_count integer; v_items jsonb;
BEGIN
 PERFORM atlas.personal_program_author_note_guard_v1(p_program_id);
 SELECT count(DISTINCT note_id) INTO v_count
 FROM atlas.personal_program_author_note_events WHERE program_id=p_program_id;
 SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'noteId',n.note_id,'componentKey',n.component_key,
    'anchorVersionId',n.anchor_version_id,'anchorExcerpt',n.anchor_excerpt,
    'revision',n.revision,'text',n.body,'standing',n.standing,
    'visibility',n.visibility,'actorAuthUserId',n.actor_auth_user_id,
    'updatedAt',n.created_at,'history',
      (SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'revision',h.revision,'text',h.body,'standing',h.standing,
        'actorAuthUserId',h.actor_auth_user_id,'at',h.created_at)
        ORDER BY h.revision),'[]'::jsonb)
       FROM (SELECT revision,body,standing,actor_auth_user_id,created_at
             FROM atlas.personal_program_author_note_events
             WHERE program_id=p_program_id AND note_id=n.note_id
             ORDER BY revision DESC LIMIT 50) h)
    ) ORDER BY n.created_at DESC,n.note_id DESC),'[]'::jsonb) INTO v_items
 FROM (SELECT * FROM
         (SELECT DISTINCT ON (note_id) *
          FROM atlas.personal_program_author_note_events
          WHERE program_id=p_program_id
          ORDER BY note_id,revision DESC) latest
       ORDER BY latest.created_at DESC,latest.note_id DESC
       LIMIT 200) n;
 RETURN pg_catalog.jsonb_build_object('ok',true,'programId',p_program_id,
  'items',v_items,'total',v_count,'truncated',v_count>pg_catalog.jsonb_array_length(v_items),
  'standing','author_private','readerOnly',true);
END;
$fn$;

CREATE FUNCTION public.personal_program_author_note_create_self_api_v1(
 p_program_id uuid,p_anchor_version_id uuid,p_component_key text,
 p_anchor_excerpt text,p_body text,p_request_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.personal_program_author_note_create_self_v1(
 p_program_id,p_anchor_version_id,p_component_key,p_anchor_excerpt,p_body,p_request_key); $fn$;
CREATE FUNCTION public.personal_program_author_note_revise_self_api_v1(
 p_program_id uuid,p_note_id uuid,p_expected_revision integer,
 p_body text,p_standing text,p_request_key text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.personal_program_author_note_revise_self_v1(
 p_program_id,p_note_id,p_expected_revision,p_body,p_standing,p_request_key); $fn$;
CREATE FUNCTION public.personal_program_author_notes_read_self_api_v1(p_program_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.personal_program_author_notes_read_self_v1(p_program_id); $fn$;

REVOKE ALL ON FUNCTION atlas.personal_program_author_note_guard_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.personal_program_author_note_create_self_v1(uuid,uuid,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.personal_program_author_note_revise_self_v1(uuid,uuid,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION atlas.personal_program_author_notes_read_self_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.personal_program_author_note_create_self_api_v1(uuid,uuid,text,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.personal_program_author_note_revise_self_api_v1(uuid,uuid,integer,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.personal_program_author_notes_read_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.personal_program_author_note_create_self_api_v1(uuid,uuid,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.personal_program_author_note_revise_self_api_v1(uuid,uuid,integer,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.personal_program_author_notes_read_self_api_v1(uuid) TO authenticated;
COMMIT;
