-- HELD Personal Task source increment; not a migration and not releasable alone.
-- One original task_entries row; relationship revisions only, never a second task.
BEGIN;

DO $preimage$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.require_active_task_principal_v1()')) IS DISTINCT FROM '7956e4775c8ea16c9b88a8cf200f339c'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.household_identity_invite_accept_self_v1(text)')) IS DISTINCT FROM '73f68ea5325d628002cacbdcd8840b83'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.household_identity_link_disconnect_self_v1(uuid)')) IS DISTINCT FROM '1489e8acbb2657e426d887811946ed08'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.atlas_task_day_self_api_v1(date)')) IS DISTINCT FROM 'fff53d7ab6b2ffe9f16ffa0f9ad254d7'
 OR (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.set_atlas_task_done_self_api_v1(uuid,boolean)')) IS DISTINCT FROM 'f8a71cba0656b0d6a6fbfad29744a3ac'
 THEN RAISE EXCEPTION 'Personal original/connection source has changed; reconcile before proceeding'; END IF;
END
$preimage$;

-- Signed Person readiness uses the same canonical identity and active
-- personal Atlas evidence as the accepted identity-only connection source.
CREATE FUNCTION atlas.personal_task_ready_person_v1(p_user_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT p.person_id
 FROM atlas.principals p
 JOIN atlas.people a ON a.id=p.person_id AND a.status='active'
 JOIN reality.entities e ON e.id=p.person_id AND e.entity_kind='person' AND e.identity_state='canonical'
 JOIN auth.users u ON u.id=p.user_id AND u.email_confirmed_at IS NOT NULL
   AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now())
 WHERE p.user_id=p_user_id AND p.status='active'
 AND EXISTS (SELECT 1 FROM atlas.person_auth_credentials c
   WHERE c.auth_user_id=p.user_id AND c.person_id=p.person_id
   AND c.status='active' AND c.retired_at IS NULL)
 AND EXISTS (SELECT 1 FROM reality.auth_person_bindings b
   WHERE b.auth_user_id=p.user_id AND b.person_entity_id=p.person_id
   AND b.binding_state='active' AND b.retired_at IS NULL)
 AND EXISTS (SELECT 1 FROM personal.atlases pa WHERE pa.person_entity_id=p.person_id
   AND pa.native AND pa.atlas_state='active');
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_ready_person_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Exact bilateral invitation evidence, not inferred from relationship labels,
-- same family name, employee seats, or household membership alone.
-- Stored Person link permits a direct *target choice*, not broad notebook access.
CREATE FUNCTION atlas.personal_task_connection_peers_v1(p_user_id uuid)
RETURNS TABLE(peer_person_id uuid,peer_user_id uuid,peer_name text,connection_id uuid)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 WITH valid_links AS (
  SELECT l.id,l.linked_at,l.target_auth_user_id,l.target_person_id,
    p.user_id AS origin_user_id,p.person_id AS origin_person_id
  FROM atlas.household_member_identity_links l
  JOIN atlas.households h ON h.id=l.household_id AND h.status='active'
  JOIN atlas.household_members m ON m.id=l.household_member_id
    AND m.household_id=h.id AND m.active AND m.user_id IS NULL
    AND m.person_id IS NULL AND m.household_role IS DISTINCT FROM 'principal'
  JOIN atlas.principals p ON p.id=h.principal_id AND p.status='active'
  JOIN atlas.household_identity_link_invitations i ON i.id=l.accepted_invitation_id
    AND i.household_id=h.id AND i.household_member_id=m.id
    AND i.invited_by_user_id=p.user_id AND i.accepted_by_user_id=l.target_auth_user_id
    AND i.invitation_state='accepted' AND i.accepted_at IS NOT NULL
  WHERE l.link_state='active' AND l.revoked_at IS NULL
    AND p.user_id<>l.target_auth_user_id
    AND (p.user_id=p_user_id OR l.target_auth_user_id=p_user_id)
    AND atlas.personal_task_ready_person_v1(p.user_id)=p.person_id
    AND atlas.personal_task_ready_person_v1(l.target_auth_user_id)=l.target_person_id
 ), both_directions AS (
  SELECT id,linked_at,
    CASE WHEN origin_user_id=p_user_id THEN target_person_id ELSE origin_person_id END AS peer,
    CASE WHEN origin_user_id=p_user_id THEN target_auth_user_id ELSE origin_user_id END AS peer_user
  FROM valid_links
 )
 SELECT b.peer,b.peer_user,e.display_name,b.id
 FROM both_directions b JOIN reality.entities e ON e.id=b.peer
 WHERE e.entity_kind='person' AND e.identity_state='canonical'
   AND nullif(btrim(e.display_name),'') IS NOT NULL;
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_connection_peers_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Revisions record responsibility/participation and exact accepted link for
-- every non-owner. No Work, task copy, invitation or institutional Ledger.
-- Restrict source deletion once explicitly shared; the former private-only
-- deletion path cannot silently erase another Person's shared history.
CREATE TABLE atlas.personal_task_assignment_revisions_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 task_id uuid NOT NULL REFERENCES atlas.task_entries(id) ON DELETE RESTRICT,
 revision bigint NOT NULL CHECK(revision>0),
 actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 actor_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 actor_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 action_id uuid NOT NULL,
 primary_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 participant_person_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
 connection_evidence jsonb NOT NULL CHECK(jsonb_typeof(connection_evidence)='object'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(cardinality(participant_person_ids)<=100),
 CHECK(array_position(participant_person_ids,NULL) IS NULL),
 CHECK(NOT (primary_person_id=ANY(participant_person_ids))),
 UNIQUE(task_id,revision), UNIQUE(actor_user_id,action_id)
);
ALTER TABLE atlas.personal_task_assignment_revisions_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_task_assignment_revisions_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION atlas.reject_personal_task_assignment_rewrite_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $fn$
BEGIN
 RAISE EXCEPTION 'Personal assignment history is immutable' USING ERRCODE='42501';
END
$fn$;
CREATE TRIGGER personal_task_assignment_immutable_v1 BEFORE UPDATE OR DELETE
 ON atlas.personal_task_assignment_revisions_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.reject_personal_task_assignment_rewrite_v1();
REVOKE ALL ON FUNCTION atlas.reject_personal_task_assignment_rewrite_v1() FROM PUBLIC,anon,authenticated,service_role;

-- Exact recipient membership is checked against the original owner's recorded
-- link, not a new/reconnected link. Revocation cannot resurrect old live access.
CREATE FUNCTION atlas.personal_task_assignment_recipient_current_v1(
 p_task_id uuid,p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT EXISTS(
  SELECT 1 FROM atlas.task_entries t
  JOIN LATERAL (
   SELECT a.* FROM atlas.personal_task_assignment_revisions_v1 a
   WHERE a.task_id=t.id ORDER BY a.revision DESC LIMIT 1
  ) a ON true
  JOIN LATERAL atlas.personal_task_connection_peers_v1(t.owner_user_id) peer
   ON peer.peer_user_id=p_user_id
   AND peer.connection_id::text=a.connection_evidence->>peer.peer_person_id::text
  WHERE t.id=p_task_id AND p_user_id<>t.owner_user_id
   AND (a.primary_person_id=peer.peer_person_id OR peer.peer_person_id=ANY(a.participant_person_ids))
   AND NOT EXISTS(SELECT 1 FROM atlas.work_items w WHERE
    w.source_object_type='personal_dated_task' AND w.source_object_id=t.id)
 );
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_assignment_recipient_current_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Owner's exact-original assignment editor: choices are scoped to active
-- accepted reciprocal connections; no browsing another Person's tasks.
CREATE FUNCTION atlas.read_personal_task_assignment_self_api_v1(p_task_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_actor uuid:=atlas.personal_task_ready_person_v1(auth.uid());
 v_task atlas.task_entries%ROWTYPE;
 v_assignment atlas.personal_task_assignment_revisions_v1%ROWTYPE;
 v_owner uuid;v_is_owner boolean;v_choices jsonb;v_items jsonb;v_primary uuid;
BEGIN
 IF v_actor IS NULL OR p_task_id IS NULL THEN
  RAISE EXCEPTION 'Exact signed Person and original required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_task FROM atlas.task_entries t WHERE t.id=p_task_id
 AND ((t.owner_user_id=auth.uid() AND t.principal_id=v_principal)
   OR atlas.personal_task_assignment_recipient_current_v1(t.id,auth.uid()));
 IF v_task.id IS NULL OR EXISTS(SELECT 1 FROM atlas.work_items w
   WHERE w.source_object_type='personal_dated_task' AND w.source_object_id=v_task.id)
 THEN RAISE EXCEPTION 'Personal original unavailable' USING ERRCODE='42501'; END IF;
 v_is_owner:=v_task.owner_user_id=auth.uid() AND v_task.principal_id=v_principal;
 v_owner:=atlas.personal_task_ready_person_v1(v_task.owner_user_id);
 IF v_owner IS NULL THEN RAISE EXCEPTION 'Original owner identity unavailable' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_assignment FROM atlas.personal_task_assignment_revisions_v1
 WHERE task_id=v_task.id ORDER BY revision DESC LIMIT 1;
 v_primary:=coalesce(v_assignment.primary_person_id,v_owner);
 -- Only names previously admitted on this exact original, or current
 -- owner-side choices; never expand a recipient into the owner's contacts.
 SELECT coalesce(jsonb_agg(jsonb_build_object('personId',e.id,'name',e.display_name,
   'role',CASE WHEN e.id=v_primary THEN 'responsible' ELSE 'participant' END)
   ORDER BY CASE WHEN e.id=v_primary THEN 0 ELSE 1 END,e.id),'[]'::jsonb)
 INTO v_items FROM reality.entities e
 WHERE e.entity_kind='person' AND e.identity_state='canonical'
 AND (e.id=v_primary OR e.id=ANY(coalesce(v_assignment.participant_person_ids,'{}'::uuid[])));
 IF v_is_owner THEN
  SELECT coalesce(jsonb_agg(jsonb_build_object('personId',peer_person_id,'name',peer_name)
   ORDER BY peer_name,peer_person_id),'[]'::jsonb) INTO v_choices
  FROM (SELECT DISTINCT ON(peer_person_id) peer_person_id,peer_name
    FROM atlas.personal_task_connection_peers_v1(auth.uid())
    ORDER BY peer_person_id,connection_id) q;
 ELSE v_choices:='[]'::jsonb; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','personal_task_assignment_read_v1',
 'taskId',v_task.id,'actorPersonId',v_actor,'ownerPersonId',v_owner,
 'revision',coalesce(v_assignment.revision,0),'primaryPersonId',v_primary,
 'items',v_items,'choices',v_choices,'isOriginalOwner',v_is_owner,
 'canAssign',v_is_owner AND v_task.status='open' AND v_task.archived_at IS NULL,
 'oneOriginalTaskId',true,'acceptanceRequired',false,
 'task',jsonb_build_object('id',v_task.id,'sentence',v_task.sentence,
 'dueDate',v_task.due_date,'status',v_task.status),
 'assignedToSelf',(v_actor=v_primary OR v_actor=ANY(coalesce(v_assignment.participant_person_ids,'{}'::uuid[])))
  AND (v_is_owner OR atlas.personal_task_assignment_recipient_current_v1(v_task.id,auth.uid())),
 'canWriteNotes',v_task.status='open' AND v_task.archived_at IS NULL,
 'archived',v_task.archived_at IS NOT NULL);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.read_personal_task_assignment_self_api_v1(uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Owner explicitly chooses the complete intended roster, with expected
-- current revision and stable source action. No arbitrary recipient IDs.
-- A connected peer may receive directly, never as an accepted-by-peer claim.
CREATE FUNCTION atlas.change_personal_task_assignment_self_api_v1(
 p_task_id uuid,p_expected_revision bigint,p_primary_person_id uuid,
 p_participant_person_ids uuid[],p_source_action_id uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_actor uuid:=atlas.personal_task_ready_person_v1(auth.uid());
 v_task atlas.task_entries%ROWTYPE;
 v_latest atlas.personal_task_assignment_revisions_v1%ROWTYPE;
 v_prior atlas.personal_task_assignment_revisions_v1%ROWTYPE;
 v_participants uuid[];v_person uuid;v_link uuid;v_connections jsonb:='{}'::jsonb;
 v_revision bigint;v_event uuid;v_idempotent boolean:=false;
BEGIN
 IF v_actor IS NULL OR p_task_id IS NULL OR p_source_action_id IS NULL
  OR p_expected_revision IS NULL OR p_expected_revision<0
  OR p_primary_person_id IS NULL OR p_participant_person_ids IS NULL
  OR cardinality(p_participant_person_ids)>100
  OR array_position(p_participant_person_ids,NULL) IS NOT NULL
  OR p_primary_person_id=ANY(p_participant_person_ids)
  OR (SELECT count(DISTINCT x) FROM unnest(p_participant_person_ids) x)<>cardinality(p_participant_person_ids)
 THEN RAISE EXCEPTION 'Exact original, expected revision, action and distinct roster required' USING ERRCODE='22023'; END IF;
 SELECT coalesce(array_agg(x ORDER BY x),'{}'::uuid[]) INTO v_participants
 FROM unnest(p_participant_person_ids) x;
 SELECT * INTO v_task FROM atlas.task_entries t WHERE t.id=p_task_id
   AND t.owner_user_id=auth.uid() AND t.principal_id=v_principal FOR UPDATE;
 IF v_task.id IS NULL THEN RAISE EXCEPTION 'Owned original unavailable' USING ERRCODE='42501'; END IF;
 IF v_task.status<>'open' OR v_task.archived_at IS NOT NULL
 OR EXISTS(SELECT 1 FROM atlas.work_items w WHERE w.source_object_type='personal_dated_task'
  AND w.source_object_id=v_task.id)
 THEN RAISE EXCEPTION 'Open untransferred original required' USING ERRCODE='23514'; END IF;
 SELECT * INTO v_latest FROM atlas.personal_task_assignment_revisions_v1
 WHERE task_id=v_task.id ORDER BY revision DESC LIMIT 1;
 v_revision:=coalesce(v_latest.revision,0);
 -- Lock each selected, accepted identity-link row, in deterministic order,
 -- and recheck after lock; disconnect uses a conflicting row update.
 FOR v_person IN SELECT DISTINCT x FROM unnest(array_prepend(p_primary_person_id,v_participants)) x
 WHERE x<>v_actor ORDER BY x
 LOOP
  SELECT q.connection_id INTO v_link FROM atlas.personal_task_connection_peers_v1(auth.uid()) q
   WHERE q.peer_person_id=v_person ORDER BY q.connection_id LIMIT 1;
  IF v_link IS NULL THEN RAISE EXCEPTION 'Current connection required' USING ERRCODE='42501'; END IF;
  PERFORM 1 FROM atlas.household_member_identity_links l
   WHERE l.id=v_link AND l.link_state='active' AND l.revoked_at IS NULL FOR SHARE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM atlas.personal_task_connection_peers_v1(auth.uid()) q
    WHERE q.peer_person_id=v_person AND q.connection_id=v_link)
  THEN RAISE EXCEPTION 'Current connection required' USING ERRCODE='42501'; END IF;
  v_connections:=v_connections||jsonb_build_object(v_person::text,v_link::text);
 END LOOP;
 SELECT * INTO v_prior FROM atlas.personal_task_assignment_revisions_v1
 WHERE actor_user_id=auth.uid() AND action_id=p_source_action_id;
 IF v_prior.id IS NOT NULL THEN
  IF v_prior.task_id<>v_task.id OR v_prior.actor_person_id<>v_actor
   OR v_prior.actor_principal_id<>v_principal OR v_prior.revision<>p_expected_revision+1
   OR v_prior.revision<>v_revision OR v_prior.primary_person_id<>p_primary_person_id
   OR v_prior.participant_person_ids<>v_participants OR v_prior.connection_evidence<>v_connections
  THEN RAISE EXCEPTION 'Stale or conflicting assignment action' USING ERRCODE='PT409'; END IF;
  v_event:=v_prior.id;v_idempotent:=true;
 ELSE
  IF v_revision<>p_expected_revision THEN RAISE EXCEPTION 'Assignment changed; reopen original' USING ERRCODE='PT409'; END IF;
  IF coalesce(v_latest.primary_person_id,v_actor)=p_primary_person_id
   AND coalesce(v_latest.participant_person_ids,'{}'::uuid[])=v_participants
   AND coalesce(v_latest.connection_evidence,'{}'::jsonb)=v_connections
  THEN RAISE EXCEPTION 'No assignment change requested' USING ERRCODE='22023'; END IF;
  INSERT INTO atlas.personal_task_assignment_revisions_v1(
   task_id,revision,actor_user_id,actor_person_id,actor_principal_id,action_id,
   primary_person_id,participant_person_ids,connection_evidence)
  VALUES(v_task.id,v_revision+1,auth.uid(),v_actor,v_principal,p_source_action_id,
   p_primary_person_id,v_participants,v_connections)
  RETURNING id INTO v_event;
  v_revision:=v_revision+1;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','personal_task_assignment_change_v1',
 'taskId',v_task.id,'assignmentEventId',v_event,'revision',v_revision,
 'primaryPersonId',p_primary_person_id,'participantPersonIds',to_jsonb(v_participants),
 'idempotent',v_idempotent,'oneOriginalTaskId',true,'newTaskCreated',false,
 'acceptanceRequired',false,'recipientAttested',false,'institutionalWorkChanged',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.change_personal_task_assignment_self_api_v1(uuid,bigint,uuid,uuid[],uuid) FROM PUBLIC,anon,authenticated,service_role;

-- INTEGRATED original lifecycle; still HELD, no public new command grants.
DO $consumer_preimages$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.atlas_task_day_self_api_v1(date)')) IS DISTINCT FROM 'fff53d7ab6b2ffe9f16ffa0f9ad254d7' THEN RAISE EXCEPTION 'Exact Personal consumer changed: atlas_task_day_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.person_open_task_backlog_self_api_v1(date,integer)')) IS DISTINCT FROM '0f6a0145b4ed04f676f3909c646d2bd7' THEN RAISE EXCEPTION 'Exact Personal consumer changed: person_open_task_backlog_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.set_atlas_task_done_self_api_v1(uuid,boolean)')) IS DISTINCT FROM 'f8a71cba0656b0d6a6fbfad29744a3ac' THEN RAISE EXCEPTION 'Exact Personal consumer changed: set_atlas_task_done_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.append_personal_task_progress_self_api_v1(uuid,uuid,text)')) IS DISTINCT FROM '83901d47f5fdef191ff168be98085b11' THEN RAISE EXCEPTION 'Exact Personal consumer changed: append_personal_task_progress_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.read_personal_task_progress_self_api_v1(uuid,integer,timestamp with time zone,uuid)')) IS DISTINCT FROM '0d45098eb4239b076f07b6bb9fa6a8bc' THEN RAISE EXCEPTION 'Exact Personal consumer changed: read_personal_task_progress_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.set_personal_task_archive_self_api_v1(uuid,boolean)')) IS DISTINCT FROM 'f6bc5221f8999b121fca5fd08e7fc565' THEN RAISE EXCEPTION 'Exact Personal consumer changed: set_personal_task_archive_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.delete_unlinked_personal_task_self_api_v1(uuid)')) IS DISTINCT FROM 'fe814870812274c13639b0e2f0a3e353' THEN RAISE EXCEPTION 'Exact Personal consumer changed: delete_unlinked_personal_task_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.promote_personal_dated_task_to_company_work_self_api_v1(uuid,uuid,uuid,text)')) IS DISTINCT FROM '4c3a46eff458fef32da5f1b7ee4bdee4' THEN RAISE EXCEPTION 'Exact Personal consumer changed: promote_personal_dated_task_to_company_work_self_api_v1'; END IF;
END
$consumer_preimages$;

-- Owner provenance is not responsibility. Default private original stays
-- owned-and-assigned; an explicit send removes owner from active responsibility.
CREATE FUNCTION atlas.personal_task_assigned_actor_v1(p_task_id uuid,p_user_id uuid,p_principal_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $fn$
 SELECT EXISTS(SELECT 1 FROM atlas.task_entries t
 LEFT JOIN LATERAL (
  SELECT a.* FROM atlas.personal_task_assignment_revisions_v1 a
  WHERE a.task_id=t.id ORDER BY a.revision DESC LIMIT 1
 ) a ON true
 WHERE t.id=p_task_id AND (
  (t.owner_user_id=p_user_id AND t.principal_id=p_principal_id AND
   (a.id IS NULL OR atlas.personal_task_ready_person_v1(p_user_id)=a.primary_person_id
     OR atlas.personal_task_ready_person_v1(p_user_id)=ANY(a.participant_person_ids)))
  OR atlas.personal_task_assignment_recipient_current_v1(t.id,p_user_id)
 ));
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_assigned_actor_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Call only after locking the exact original row. Lock the exact stored
-- relationship while a recipient writes; disconnect conflicts on same row.
CREATE FUNCTION atlas.personal_task_lock_recipient_v1(p_task_id uuid,p_user_id uuid)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $fn$
DECLARE v_link uuid;
BEGIN
 SELECT peer.connection_id INTO v_link FROM atlas.task_entries t
 JOIN LATERAL (SELECT a.* FROM atlas.personal_task_assignment_revisions_v1 a
  WHERE a.task_id=t.id ORDER BY a.revision DESC LIMIT 1) a ON true
 JOIN LATERAL atlas.personal_task_connection_peers_v1(t.owner_user_id) peer
  ON peer.peer_user_id=p_user_id
  AND peer.connection_id::text=a.connection_evidence->>peer.peer_person_id::text
 WHERE t.id=p_task_id AND t.owner_user_id<>p_user_id
 AND (peer.peer_person_id=a.primary_person_id OR peer.peer_person_id=ANY(a.participant_person_ids));
 IF v_link IS NULL THEN RETURN false; END IF;
 PERFORM 1 FROM atlas.household_member_identity_links l
 WHERE l.id=v_link AND l.link_state='active' AND l.revoked_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RETURN false; END IF;
 RETURN atlas.personal_task_assignment_recipient_current_v1(p_task_id,p_user_id);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_task_lock_recipient_v1(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

-- Shared completion is an actual actor-attributed event on the original,
-- not a second task status or a claim that the other actor performed Work.
CREATE TABLE atlas.personal_task_shared_completion_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 task_id uuid NOT NULL REFERENCES atlas.task_entries(id) ON DELETE RESTRICT,
 assignment_revision bigint NOT NULL,
 actor_person_id uuid NOT NULL REFERENCES atlas.people(id) ON DELETE RESTRICT,
 actor_principal_id uuid NOT NULL REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
 before_status text NOT NULL CHECK(before_status IN ('open','done')),
 after_status text NOT NULL CHECK(after_status IN ('open','done')),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(task_id,assignment_revision) REFERENCES atlas.personal_task_assignment_revisions_v1(task_id,revision) ON DELETE RESTRICT,
 CHECK(before_status<>after_status)
);
CREATE INDEX personal_task_shared_completion_original_v1 ON atlas.personal_task_shared_completion_events_v1(task_id,recorded_at DESC,id DESC);
ALTER TABLE atlas.personal_task_shared_completion_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.personal_task_shared_completion_events_v1 FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER personal_task_shared_completion_immutable_v1 BEFORE UPDATE OR DELETE
 ON atlas.personal_task_shared_completion_events_v1 FOR EACH ROW EXECUTE FUNCTION atlas.reject_personal_task_assignment_rewrite_v1();

-- Original owner's sent history is separately bounded and never counted as
-- their active Work. No new correspondence authority or duplicated record.
CREATE FUNCTION atlas.personal_sent_original_tasks_self_api_v1(p_limit integer DEFAULT 50,p_before_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_principal uuid:=atlas.require_active_task_principal_v1();v_rows jsonb;v_more boolean;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
  RAISE EXCEPTION 'Bounded original history page required' USING ERRCODE='22023'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',q.id,'sentence',q.sentence,
  'dueDate',q.due_date,'status',q.status,'assignedToSelf',false,
  'isOriginalOwner',true) ORDER BY q.id DESC),'[]'::jsonb) INTO v_rows
 FROM (
 SELECT t.id,t.sentence,t.due_date,t.status FROM atlas.task_entries t
 WHERE t.owner_user_id=auth.uid() AND t.principal_id=v_principal
 AND t.archived_at IS NULL
 AND EXISTS(SELECT 1 FROM atlas.personal_task_assignment_revisions_v1 a WHERE a.task_id=t.id)
 AND NOT atlas.personal_task_assigned_actor_v1(t.id,auth.uid(),v_principal)
 AND (p_before_id IS NULL OR t.id<p_before_id)
 ORDER BY t.id DESC LIMIT p_limit+1) q;
 v_more:=jsonb_array_length(v_rows)>p_limit;
 IF v_more THEN v_rows:=v_rows-p_limit; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','personal_sent_original_tasks_v1',
 'items',v_rows,'hasMore',v_more,'nextBeforeId',CASE WHEN v_more THEN
 v_rows->(jsonb_array_length(v_rows)-1)->>'id' ELSE NULL END,'activeResponsibility',false);
END
$fn$;
REVOKE ALL ON FUNCTION atlas.personal_sent_original_tasks_self_api_v1(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;


CREATE OR REPLACE FUNCTION atlas.atlas_task_day_self_api_v1(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_rows jsonb;
begin
  if p_date is null then
    raise exception 'Date required.' using errcode='22023';
  end if;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id',t.id,'sentence',t.sentence,'dueDate',t.due_date,'status',t.status,
    'institutionalWorkItemId',wi.id,
    'institutionalWorkState',wi.work_state,
    'institutionalTransfer',wi.id is not null,
    'isOriginalOwner',t.owner_user_id=auth.uid() AND t.principal_id=v_principal,
    'assignedToSelf',true
  )) order by case when t.status='open' then 0 else 1 end,
    t.created_at,t.id),'[]'::jsonb)
  into v_rows
  from atlas.task_entries t
  left join lateral (
    select w.id,w.work_state from atlas.work_items w
    where w.source_object_type='personal_dated_task' and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
  ) wi on true
  where atlas.personal_task_assigned_actor_v1(t.id,auth.uid(),v_principal)
    and t.due_date=p_date
    and t.archived_at is null;
  return jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.person_open_task_backlog_self_api_v1(p_date date, p_limit integer DEFAULT 150)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_principal uuid; v_rows jsonb; v_count integer;
begin
 v_principal:=atlas.require_active_task_principal_v1();
 if auth.uid() is null or p_date is null or p_limit not between 1 and 200 then
   raise exception 'Valid signed-in Person, day and bounded limit required' using errcode='22023';
 end if;
 with eligible as (
   select t.id,t.sentence,t.due_date,t.status,t.created_at,
     (t.owner_user_id=auth.uid() AND t.principal_id=v_principal) as original_owner,
     transfer.id as institutional_id,transfer.work_state as institutional_state
   from atlas.task_entries t
   left join lateral (
    select w.id,w.work_state from atlas.work_items w
    where w.source_object_type='personal_dated_task' and w.source_object_id=t.id
    order by w.created_at,w.id limit 1
   ) transfer on true
   where atlas.personal_task_assigned_actor_v1(t.id,auth.uid(),v_principal)
     and t.status='open' and t.due_date<p_date and t.archived_at is null
   order by t.due_date desc,t.created_at desc,t.id desc
   limit p_limit+1
 ), counted as (select count(*) n from eligible)
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',id,'sentence',sentence,'dueDate',due_date,'status',status,
   'institutionalWorkItemId',institutional_id,'institutionalWorkState',institutional_state,
   'isOriginalOwner',original_owner,'assignedToSelf',true
  ) order by due_date desc,created_at desc,id desc)
  filter (where rn<=p_limit),'[]'::jsonb), (select n from counted)
 into v_rows,v_count
 from (select *,row_number() over(order by due_date desc,created_at desc,id desc) rn from eligible) numbered;
 return jsonb_build_object('ok',true,'contractVersion','person_open_task_backlog_v1',
  'beforeDate',p_date,'items',v_rows,'hasMore',v_count>p_limit,
  'source','original_personal_tasks','authorization','signed_principal_original_or_current_assignment');
end $function$;

CREATE OR REPLACE FUNCTION atlas.set_atlas_task_done_self_api_v1(p_task_id uuid, p_done boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
DECLARE
  v_principal uuid:=atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%ROWTYPE;
  v_assignment_revision bigint;v_actor uuid;v_prior_status text;v_event uuid;
  v_original_owner boolean;
BEGIN
  IF p_task_id IS NULL OR p_done IS NULL THEN
    RAISE EXCEPTION 'Task and completion state required.' USING ERRCODE='22023';
  END IF;
  -- Serialize with the institutional promotion's SELECT FOR UPDATE:
  -- neither request can inspect a stale source state while the other acts.
  SELECT * INTO v_task FROM atlas.task_entries t
  WHERE t.id=p_task_id AND (
    (t.owner_user_id=auth.uid() AND t.principal_id=v_principal)
    OR atlas.personal_task_assignment_recipient_current_v1(t.id,auth.uid())) FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE='42501';
  END IF;

  v_original_owner:=v_task.owner_user_id=auth.uid() AND v_task.principal_id=v_principal;
  IF NOT atlas.personal_task_assigned_actor_v1(v_task.id,auth.uid(),v_principal)
    OR (NOT v_original_owner AND NOT atlas.personal_task_lock_recipient_v1(v_task.id,auth.uid()))
  THEN RAISE EXCEPTION 'Current assigned Person required' USING ERRCODE='42501'; END IF;
  SELECT max(revision) INTO v_assignment_revision FROM atlas.personal_task_assignment_revisions_v1
   WHERE task_id=v_task.id;
  IF v_assignment_revision IS NOT NULL THEN
   v_actor:=atlas.personal_task_ready_person_v1(auth.uid());
   IF v_actor IS NULL OR v_task.archived_at IS NOT NULL THEN
    RAISE EXCEPTION 'Active assigned Person and unarchived original required' USING ERRCODE='42501'; END IF;
   -- Reopening shared completed Work is limited to the actual completing
   -- actor or original owner who is still assigned. Unassigned sender cannot.
   IF NOT p_done AND v_task.status='done' AND NOT v_original_owner AND NOT EXISTS(
    SELECT 1 FROM (SELECT e.* FROM atlas.personal_task_shared_completion_events_v1 e
     WHERE e.task_id=v_task.id ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1) recent
    WHERE recent.after_status='done' AND recent.actor_person_id=v_actor
   ) THEN RAISE EXCEPTION 'Only the completing Person or assigned owner may reopen' USING ERRCODE='42501'; END IF;
  END IF;
  v_prior_status:=v_task.status;

  -- Do not permit independent success/failure state on original Person
  -- evidence once Company Work has accepted custody of execution.
  IF EXISTS (
    SELECT 1 FROM atlas.task_entries t
    JOIN atlas.work_items w ON w.source_object_type='personal_dated_task'
     AND w.source_object_id=t.id
    WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
      AND t.principal_id=v_principal
  ) THEN
    RAISE EXCEPTION 'Transferred Company Work cannot be completed as a personal dated task.'
      USING ERRCODE='23514';
  END IF;
  IF v_assignment_revision IS NOT NULL AND v_prior_status=(CASE WHEN p_done THEN 'done' ELSE 'open' END) THEN
    RETURN jsonb_build_object('ok',true,'idempotent',true,'task',jsonb_build_object(
      'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,'status',v_task.status));
  END IF;
  UPDATE atlas.task_entries
    SET status=CASE WHEN p_done THEN 'done' ELSE 'open' END,
        completed_at=CASE WHEN p_done THEN now() ELSE NULL END
  WHERE id=v_task.id
  RETURNING * INTO v_task;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Task not found.' USING ERRCODE='42501';
  END IF;
  IF v_assignment_revision IS NOT NULL THEN
   INSERT INTO atlas.personal_task_shared_completion_events_v1(task_id,assignment_revision,
     actor_person_id,actor_principal_id,actor_user_id,before_status,after_status)
   VALUES(v_task.id,v_assignment_revision,v_actor,v_principal,auth.uid(),v_prior_status,v_task.status)
   RETURNING id INTO v_event;
  END IF;
  RETURN jsonb_build_object('ok',true,'completionEventId',v_event,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
END
$function$;

CREATE OR REPLACE FUNCTION atlas.append_personal_task_progress_self_api_v1(p_task_id uuid, p_source_action_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_task atlas.task_entries%ROWTYPE;
 v_text text:=btrim(coalesce(p_note,''));
 v_prior atlas.personal_task_progress_events_v1%ROWTYPE;
 v_inserted atlas.personal_task_progress_events_v1%ROWTYPE;
BEGIN
 IF p_task_id IS NULL OR p_source_action_id IS NULL
   OR char_length(v_text) NOT BETWEEN 1 AND 2000 THEN
   RAISE EXCEPTION 'Exact original, action and 1–2000 character note required'
     USING ERRCODE='22023';
 END IF;
 -- This lock serializes progress against promotion and completion of the
 -- same original, so we never append to obsolete personal execution custody.
 SELECT * INTO v_task FROM atlas.task_entries t
 WHERE t.id=p_task_id AND ((t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal) OR atlas.personal_task_assignment_recipient_current_v1(t.id,auth.uid())) FOR UPDATE;
 IF NOT FOUND OR (v_task.owner_user_id<>auth.uid()
   AND NOT atlas.personal_task_lock_recipient_v1(v_task.id,auth.uid())) THEN
   RAISE EXCEPTION 'Authorized original personal task unavailable'
     USING ERRCODE='42501';
 END IF;
 SELECT * INTO v_prior FROM atlas.personal_task_progress_events_v1 e
 WHERE e.owner_user_id=auth.uid() AND e.source_action_id=p_source_action_id;
 IF FOUND THEN
   IF v_prior.task_id=v_task.id AND v_prior.principal_id=v_principal
     AND v_prior.note=v_text THEN
     RETURN jsonb_build_object(
       'ok',true,'contractVersion','personal_task_progress_append_v1',
       'taskId',v_task.id,'progressId',v_prior.id,'recordedAt',v_prior.recorded_at,
       'note',v_prior.note,'idempotent',true,
       'oneOriginalTaskId',true,'noInstitutionalWorkChanged',true);
   END IF;
   RAISE EXCEPTION 'Action already used for a different original or note'
     USING ERRCODE='PT409';
 END IF;
 IF v_task.status<>'open' OR v_task.archived_at IS NOT NULL THEN
   RAISE EXCEPTION 'Progress requires one open, unarchived original'
     USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM atlas.work_items w
   WHERE w.source_object_type='personal_dated_task'
     AND w.source_object_id=v_task.id) THEN
   RAISE EXCEPTION 'Company Work retains execution custody'
     USING ERRCODE='23514';
 END IF;
 INSERT INTO atlas.personal_task_progress_events_v1
   (task_id,owner_user_id,principal_id,source_action_id,note)
 VALUES (v_task.id,auth.uid(),v_principal,p_source_action_id,v_text)
 RETURNING * INTO v_inserted;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','personal_task_progress_append_v1',
   'taskId',v_task.id,'progressId',v_inserted.id,
   'recordedAt',v_inserted.recorded_at,'note',v_inserted.note,
   'idempotent',false,'oneOriginalTaskId',true,
   'noInstitutionalWorkChanged',true);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.read_personal_task_progress_self_api_v1(p_task_id uuid, p_limit integer DEFAULT 50, p_before_recorded_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_before_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_principal uuid:=atlas.require_active_task_principal_v1();
 v_task atlas.task_entries%ROWTYPE;
 v_rows jsonb;
 v_more boolean;
 v_count integer;
BEGIN
 IF p_task_id IS NULL OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
    OR ((p_before_recorded_at IS NULL)<>(p_before_id IS NULL)) THEN
    RAISE EXCEPTION 'Exact original, bounded page and complete cursor required'
      USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_task FROM atlas.task_entries t
 WHERE t.id=p_task_id AND ((t.owner_user_id=auth.uid()
   AND t.principal_id=v_principal) OR atlas.personal_task_assignment_recipient_current_v1(t.id,auth.uid()));
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Owned original personal task unavailable'
     USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'progressId',q.id,'note',q.note,'recordedAt',q.recorded_at,
   'authoredBySelf',q.owner_user_id=auth.uid(),'authorName',q.author_name
 ) ORDER BY q.recorded_at DESC,q.id DESC),'[]'::jsonb)
 INTO v_rows
 FROM (
   SELECT e.id,e.note,e.recorded_at,e.owner_user_id,
      coalesce(re.display_name,'Other author') AS author_name
   FROM atlas.personal_task_progress_events_v1 e
   LEFT JOIN atlas.principals ap ON ap.id=e.principal_id AND ap.user_id=e.owner_user_id
   LEFT JOIN reality.entities re ON re.id=ap.person_id AND re.entity_kind='person' AND re.identity_state='canonical'
   WHERE e.task_id=v_task.id
     AND ((e.owner_user_id=auth.uid() AND e.principal_id=v_principal)
       OR EXISTS(SELECT 1 FROM atlas.personal_task_assignment_revisions_v1 a WHERE a.task_id=v_task.id))
     AND (p_before_recorded_at IS NULL
       OR (e.recorded_at,e.id)<(p_before_recorded_at,p_before_id))
   ORDER BY e.recorded_at DESC,e.id DESC LIMIT p_limit+1
 ) q;
 v_count:=jsonb_array_length(v_rows);
 v_more:=v_count>p_limit;
 IF v_more THEN
   SELECT coalesce(jsonb_agg(x.value ORDER BY x.ordinality),'[]'::jsonb)
     INTO v_rows
   FROM jsonb_array_elements(v_rows) WITH ORDINALITY x(value,ordinality)
   WHERE x.ordinality<=p_limit;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','personal_task_progress_read_v1',
   'taskId',v_task.id,'items',v_rows,'hasMore',v_more,
   'nextCursor',CASE WHEN v_more THEN
      jsonb_build_object('beforeRecordedAt',
        v_rows->(jsonb_array_length(v_rows)-1)->>'recordedAt',
        'beforeId',v_rows->(jsonb_array_length(v_rows)-1)->>'progressId')
     ELSE NULL END,
   'oneOriginalTaskId',true);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.set_personal_task_archive_self_api_v1(p_task_id uuid, p_archived boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task atlas.task_entries%rowtype;
  v_principal uuid:=atlas.require_active_task_principal_v1();
begin
  if auth.uid() is null or p_task_id is null or p_archived is null then
    raise exception 'Signed-in owner, original task and archive choice required.'
      using errcode='42501';
  end if;
  select * into v_task from atlas.task_entries
    where id=p_task_id and owner_user_id=auth.uid()
      and principal_id=v_principal for update;
  if v_task.id is null then
    raise exception 'Your original task is unavailable.' using errcode='42501';
  end if;
  IF EXISTS(SELECT 1 FROM atlas.personal_task_assignment_revisions_v1 a WHERE a.task_id=v_task.id)
  THEN RAISE EXCEPTION 'Shared original retention requires explicit disposition' USING ERRCODE='23514'; END IF;
  update atlas.task_entries set
    archived_at=case when p_archived then coalesce(archived_at,now()) else null end
    where id=v_task.id;
  return jsonb_build_object(
    'ok',true,'contractVersion','personal_task_archive_v1',
    'taskId',v_task.id,'date',v_task.due_date,
    'archived',p_archived,'sourcePreserved',true);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.delete_unlinked_personal_task_self_api_v1(p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_task atlas.task_entries%rowtype;
  v_principal uuid:=atlas.require_active_task_principal_v1();
begin
  if auth.uid() is null or p_task_id is null then
    raise exception 'Signed-in Person and exact original task required.'
      using errcode='42501';
  end if;
  select * into v_task from atlas.task_entries
    where id=p_task_id and owner_user_id=auth.uid()
      and principal_id=v_principal for update;
  if v_task.id is null then
    raise exception 'Personal task was not found in your authenticated source.'
      using errcode='42501';
  end if;
  if exists (
    select 1 from atlas.work_items w
    where w.source_object_type='personal_dated_task'
      and w.source_object_id=v_task.id
  ) then
    raise exception 'Institutional Work has this source; use governed Work retirement.'
      using errcode='23514';
  end if;
  IF EXISTS(SELECT 1 FROM atlas.personal_task_assignment_revisions_v1 a WHERE a.task_id=v_task.id)
  THEN RAISE EXCEPTION 'Shared original history cannot be permanently deleted' USING ERRCODE='23514'; END IF;
  delete from atlas.task_entries
    where id=v_task.id and owner_user_id=auth.uid() and principal_id=v_principal;
  if not found then raise exception 'Original task deletion could not be confirmed.'
    using errcode='40001'; end if;
  return jsonb_build_object(
    'ok',true,'contractVersion','personal_task_permanent_delete_v1',
    'deletedTaskId',v_task.id,'previousDate',v_task.due_date,
    'noInstitutionalWorkDeleted',true,'permanentlyDeleted',true);
end
$function$;

CREATE OR REPLACE FUNCTION atlas.promote_personal_dated_task_to_company_work_self_api_v1(p_task_id uuid, p_organization_id uuid, p_ledger_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_owner_person uuid;
  v_principal uuid;
  v_task atlas.task_entries%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_attribution uuid;
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_new boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Sign in required.' USING ERRCODE='42501';
  END IF;
  IF p_task_id IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR v_reason IS NULL OR char_length(v_reason)>1200 THEN
    RAISE EXCEPTION 'Personal task, exact Organization/Ledger and reason required.'
      USING ERRCODE='22023';
  END IF;

  -- Both institutional governing roots AND the user's own Personal Atlas
  -- Principal are checked. There is no target Person/assignee input.
  v_owner_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_principal:=atlas.require_active_task_principal_v1();

  -- Serializes promotion of this exact original task, including competing
  -- attempts to place it in a different Organization or Ledger.
  SELECT * INTO v_task FROM atlas.task_entries t
  WHERE t.id=p_task_id AND t.owner_user_id=auth.uid()
    AND t.principal_id=v_principal FOR UPDATE;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'Owned original dated task unavailable.' USING ERRCODE='42501';
  END IF;
  IF v_task.status<>'open' THEN
    RAISE EXCEPTION 'Only still-open personal tasks may enter Company Work.'
      USING ERRCODE='22023';
  END IF;

  IF EXISTS(SELECT 1 FROM atlas.personal_task_assignment_revisions_v1 a WHERE a.task_id=v_task.id)
  THEN RAISE EXCEPTION 'Shared original may not acquire institutional execution custody' USING ERRCODE='23514'; END IF;
  SELECT * INTO v_work FROM atlas.work_items w
  WHERE w.source_object_type='personal_dated_task'
    AND w.source_object_id=v_task.id
  ORDER BY w.created_at,w.id LIMIT 1;

  IF v_work.id IS NULL THEN
    -- Work ID becomes the single institution-owned executable identity.
    -- The personal date is evidence only; it does NOT authorize employee
    -- scheduling, a hard finish time or Worker Day delivery.
    INSERT INTO atlas.work_items(
      organization_id,title,instructions,work_state,
      source_object_type,source_object_id,created_by_user_id,stable_key,metadata
    ) VALUES(
      p_organization_id,v_task.sentence,NULL,'open',
      'personal_dated_task',v_task.id,auth.uid(),
      'personal-dated-task-company-work:'||v_task.id::text,
      jsonb_build_object(
        'sourceContract','personal_dated_task_to_company_work_v1',
        'sourceTaskDate',v_task.due_date,
        'dateMeaning','personal_source_page_not_institutional_schedule',
        'custody','institutional_work_item',
        'ownerIntentReason',v_reason,
        'declaredByPersonId',v_owner_person
      )
    ) RETURNING * INTO v_work;
    v_new:=true;
  ELSE
    IF v_work.organization_id IS DISTINCT FROM p_organization_id THEN
      RAISE EXCEPTION 'This personal source is already held by another Organization.'
        USING ERRCODE='23514';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance l
      WHERE l.work_item_id=v_work.id AND l.organization_id=p_organization_id
        AND l.ledger_id=p_ledger_id AND l.attribution_state='active'
    ) THEN
      RAISE EXCEPTION 'This personal source already has different institutional custody.'
        USING ERRCODE='23514';
    END IF;
  END IF;

  INSERT INTO atlas.company_work_native_ledger_relevance(
    organization_id,work_item_id,ledger_id,evidence_kind,
    attestation_source_ref,attestation_reason,established_by_person_id
  ) VALUES(
    p_organization_id,v_work.id,p_ledger_id,'owner_attested',
    'atlas.task_entries:'||v_task.id::text,v_reason,v_owner_person
  )
  ON CONFLICT(work_item_id,ledger_id,evidence_kind)
    WHERE attribution_state='active'
  DO NOTHING;

  SELECT l.id INTO v_attribution
  FROM atlas.company_work_native_ledger_relevance l
  WHERE l.organization_id=p_organization_id AND l.work_item_id=v_work.id
    AND l.ledger_id=p_ledger_id AND l.evidence_kind='owner_attested'
    AND l.attribution_state='active';
  IF v_attribution IS NULL THEN
    RAISE EXCEPTION 'Exact native Ledger source receipt not established.'
      USING ERRCODE='23514';
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','personal_task_company_work_custody_v1',
    'workItemId',v_work.id,'organizationId',p_organization_id,
    'nativeLedgerId',p_ledger_id,'sourceTaskId',v_task.id,
    'sourceDate',v_task.due_date,'sourceTitle',v_task.sentence,
    'attributionId',v_attribution,'createdNow',v_new,
    'institutionalDateEstablished',false,
    'responsibleAllocationEstablished',false,
    'sourceRemainsProvenance',true
  );
END
$function$;

-- Held only: new assignment and sent-original endpoints remain without public grants.
COMMIT;
