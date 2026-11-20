-- HELD. Depends on signed optional-date source release. Initial instructions, not a progress report.
BEGIN;
ALTER TABLE atlas.task_entries ADD COLUMN details text CHECK (details IS NULL OR char_length(btrim(details)) BETWEEN 1 AND 10000);
CREATE FUNCTION atlas.create_atlas_task_initial_details_internal_v1(p_sentence text, p_due_date date, p_source_action_id text,p_details text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_user uuid := auth.uid();
  v_sentence text := btrim(coalesce(p_sentence,''));
  v_key text := btrim(coalesce(p_source_action_id,''));
  v_task atlas.task_entries%rowtype;
  v_details text:=nullif(btrim(coalesce(p_details,'')),'');
begin
  if length(v_sentence) not between 1 and 500 then
    raise exception 'Enter one sentence (1-500 characters).' using errcode='22023';
  end if;
  if char_length(v_details)>10000 then raise exception 'Details too long' using errcode='22023'; end if;
  if length(v_key) not between 1 and 128 then
    raise exception 'Source action ID is required.' using errcode='22023';
  end if;

  insert into atlas.task_entries(owner_user_id,principal_id,sentence,due_date,source_action_id,details)
  values (v_user,v_principal,v_sentence,p_due_date,v_key,v_details)
  on conflict (owner_user_id,source_action_id) do nothing
  returning * into v_task;

  if v_task.id is null then
    select * into v_task from atlas.task_entries
      where owner_user_id=v_user and source_action_id=v_key;
    if v_task.id is null or v_task.principal_id<>v_principal
       or v_task.sentence<>v_sentence or v_task.due_date IS DISTINCT FROM p_due_date OR v_task.details IS DISTINCT FROM v_details then
      raise exception 'The submission key belongs to a different task.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status,'details',v_task.details));
end;
$function$;
REVOKE ALL ON FUNCTION atlas.create_atlas_task_initial_details_internal_v1(text,date,text,text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION atlas.create_atlas_task_self_api_v1(p_sentence text,p_due_date date,p_source_action_id text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.create_atlas_task_initial_details_internal_v1($1,$2,$3,NULL) #- '{task,details}'; $fn$;
CREATE FUNCTION atlas.create_personal_task_initial_details_self_api_v1(p_sentence text,p_due_date date,p_source_action_id text,p_details text)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.create_atlas_task_initial_details_internal_v1($1,$2,$3,$4); $fn$;

CREATE FUNCTION atlas.create_connected_personal_task_initial_details_self_api_v1(
 p_sentence text,p_due_date date,p_recipient_person_id uuid,p_source_action_id uuid,p_details text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_principal uuid:=atlas.require_active_task_principal_v1();
 v_actor uuid:=atlas.personal_task_ready_person_v1(auth.uid());
 v_created jsonb;v_assignment jsonb;v_id uuid;
BEGIN
 IF v_principal IS NULL OR v_actor IS NULL OR p_recipient_person_id IS NULL
  OR p_recipient_person_id=v_actor OR p_source_action_id IS NULL THEN
  RAISE EXCEPTION 'Exact connected Person and action required' USING ERRCODE='22023'; END IF;
 -- Both existing writers participate in this single SQL transaction. A failed
 -- connection/assignment rolls back creation; exact retries retain both identities.
 v_created:=atlas.create_atlas_task_initial_details_internal_v1(p_sentence,p_due_date,
  'daily:connected:'||p_source_action_id::text,p_details);
 v_id:=(v_created->'task'->>'id')::uuid;
 IF v_created->>'ok' IS DISTINCT FROM 'true' OR v_id IS NULL THEN
  RAISE EXCEPTION 'Original creation unconfirmed' USING ERRCODE='PT409'; END IF;
 v_assignment:=atlas.change_personal_task_assignment_self_api_v1(v_id,0,
  p_recipient_person_id,'{}'::uuid[],p_source_action_id);
 IF v_assignment->>'ok' IS DISTINCT FROM 'true' OR
  v_assignment->>'taskId' IS DISTINCT FROM v_id::text OR
  v_assignment->>'primaryPersonId' IS DISTINCT FROM p_recipient_person_id::text OR
  v_assignment->>'revision' IS DISTINCT FROM '1' THEN
  RAISE EXCEPTION 'Original assignment unconfirmed' USING ERRCODE='PT409'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','connected_personal_task_creation_v1',
  'task',v_created->'task','assignment',v_assignment,'oneOriginalTaskId',true,
  'acceptanceRequired',false,'institutionalWorkChanged',false);
END
$fn$;
CREATE FUNCTION atlas.create_contextual_ledger_work_initial_details_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_sentence text,
 p_recipient_person_id uuid,p_execution_date date,p_unassigned boolean,p_source_action_id uuid,p_details text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE actor uuid:=atlas.current_person_id_v1(); action text:='composer:'||p_source_action_id::text;
 requested text:=nullif(btrim(coalesce(p_details,'')),''); prior boolean; receipt jsonb; original uuid; found_work atlas.work_items%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR actor IS NULL OR p_source_action_id IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
 OR requested IS NULL OR length(requested)>10000 THEN RAISE EXCEPTION 'Exact original and 1–10000 character details required' USING ERRCODE='22023'; END IF;
 -- Same lock and action namespace as the existing contextual writer. No second Work or partial write.
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.contextual-composer:'||actor::text||':'||action,0));
 SELECT EXISTS(SELECT 1 FROM atlas.ledger_work_intakes i WHERE i.submitted_by_person_id=actor AND i.source_action_id=action)
    OR EXISTS(SELECT 1 FROM atlas.work_items w WHERE w.stable_key='ledger-direct:'||auth.uid()::text||':'||md5(action)) INTO prior;
 receipt:=atlas.create_contextual_ledger_work_self_api_v1(p_organization_id,p_ledger_id,p_occurrence_id,p_sentence,p_recipient_person_id,p_execution_date,p_unassigned,p_source_action_id);
 original:=(receipt->>'workItemId')::uuid;
 IF receipt->>'ok' IS DISTINCT FROM 'true' OR original IS NULL THEN RAISE EXCEPTION 'Original not confirmed' USING ERRCODE='PT409'; END IF;
 SELECT * INTO found_work FROM atlas.work_items WHERE id=original AND organization_id=p_organization_id AND created_by_user_id=auth.uid() AND work_state='open' FOR UPDATE;
 IF found_work.id IS NULL THEN RAISE EXCEPTION 'Original initial instructions unavailable' USING ERRCODE='42501'; END IF;
 IF prior THEN
   IF found_work.instructions IS DISTINCT FROM requested THEN RAISE EXCEPTION 'Original details changed; inspect original' USING ERRCODE='23505'; END IF;
 ELSE
   IF found_work.instructions IS NOT NULL THEN RAISE EXCEPTION 'Initial details already established' USING ERRCODE='PT409'; END IF;
   UPDATE atlas.work_items SET instructions=requested WHERE id=original RETURNING * INTO found_work;
 END IF;
 IF found_work.instructions IS DISTINCT FROM requested THEN RAISE EXCEPTION 'Initial details not confirmed' USING ERRCODE='PT409'; END IF;
 RETURN receipt||jsonb_build_object('instructions',found_work.instructions);
END
$fn$;

CREATE OR REPLACE FUNCTION atlas.read_personal_task_assignment_self_api_v1(p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 'dueDate',v_task.due_date,'status',v_task.status,'details',v_task.details),
 'assignedToSelf',(v_actor=v_primary OR v_actor=ANY(coalesce(v_assignment.participant_person_ids,'{}'::uuid[])))
  AND (v_is_owner OR atlas.personal_task_assignment_recipient_current_v1(v_task.id,auth.uid())),
 'canWriteNotes',v_task.status='open' AND v_task.archived_at IS NULL,
 'canComplete',v_task.status='open' AND v_task.archived_at IS NULL
   AND (v_actor=v_primary OR v_actor=ANY(coalesce(v_assignment.participant_person_ids,'{}'::uuid[]))),
 'canReopen',v_task.status='done' AND v_task.archived_at IS NULL
   AND (v_actor=v_primary OR v_actor=ANY(coalesce(v_assignment.participant_person_ids,'{}'::uuid[])))
   AND (v_is_owner OR EXISTS(SELECT 1 FROM
      (SELECT e.* FROM atlas.personal_task_shared_completion_events_v1 e WHERE e.task_id=v_task.id
        ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1) last_event
      WHERE last_event.after_status='done' AND last_event.actor_person_id=v_actor)),
 'canRetirePrivate',v_is_owner AND v_assignment.id IS NULL,
 'ownerName',(SELECT e.display_name FROM reality.entities e WHERE e.id=v_owner),
 'archived',v_task.archived_at IS NOT NULL);
END
$function$;

CREATE OR REPLACE FUNCTION atlas.ledger_work_submission_status_self_api_v1(p_intake_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE who uuid;intake atlas.ledger_work_intakes%rowtype;work atlas.work_items%rowtype;
BEGIN
 IF auth.uid() IS NULL OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
 THEN RAISE EXCEPTION 'Signed Person required' USING errcode='42501';END IF;
 who:=atlas.current_person_id_v1();
 SELECT * INTO intake FROM atlas.ledger_work_intakes i
 WHERE i.id=p_intake_id AND i.submitted_by_person_id=who;
 IF intake.id IS NULL OR NOT(
   atlas.person_has_native_ledger_connection_v1(intake.organization_id,intake.ledger_id,who)
   OR atlas.principal_has_ledger_authority_v1(atlas.current_principal_id_v1(),intake.ledger_id))
 THEN RAISE EXCEPTION 'Original submission undisclosed' USING errcode='42501';END IF;
 SELECT * INTO work FROM atlas.work_items WHERE id=intake.work_item_id;
 RETURN jsonb_build_object('ok',true,'contractVersion','ledger_work_submission_status_v1',
   'intakeId',intake.id,'workItemId',work.id,'ledgerId',intake.ledger_id,
   'title',work.title,'instructions',work.instructions,'reviewState',intake.review_state,
   'attentionDateProposal',intake.attention_date_proposal);
END;
$function$;

REVOKE ALL ON FUNCTION atlas.create_personal_task_initial_details_self_api_v1(text,date,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.create_personal_task_initial_details_self_api_v1(text,date,text,text) TO authenticated;
CREATE FUNCTION public.create_personal_task_initial_details_self_api_v1(p_sentence text,p_due_date date,p_source_action_id text,p_details text) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO '' AS $fn$ SELECT atlas.create_personal_task_initial_details_self_api_v1($1,$2,$3,$4); $fn$;
REVOKE ALL ON FUNCTION public.create_personal_task_initial_details_self_api_v1(text,date,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_personal_task_initial_details_self_api_v1(text,date,text,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text) TO authenticated;
CREATE FUNCTION public.create_connected_personal_task_initial_details_self_api_v1(p_sentence text,p_due_date date,p_recipient_person_id uuid,p_source_action_id uuid,p_details text) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO '' AS $fn$ SELECT atlas.create_connected_personal_task_initial_details_self_api_v1($1,$2,$3,$4,$5); $fn$;
REVOKE ALL ON FUNCTION public.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_connected_personal_task_initial_details_self_api_v1(text,date,uuid,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION atlas.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text) TO authenticated;
CREATE FUNCTION public.create_contextual_ledger_work_initial_details_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_occurrence_id uuid,p_sentence text,p_recipient_person_id uuid,p_execution_date date,p_unassigned boolean,p_source_action_id uuid,p_details text) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO '' AS $fn$ SELECT atlas.create_contextual_ledger_work_initial_details_self_api_v1($1,$2,$3,$4,$5,$6,$7,$8,$9); $fn$;
REVOKE ALL ON FUNCTION public.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.create_contextual_ledger_work_initial_details_self_api_v1(uuid,uuid,uuid,text,uuid,date,boolean,uuid,text) TO authenticated;
COMMIT;
