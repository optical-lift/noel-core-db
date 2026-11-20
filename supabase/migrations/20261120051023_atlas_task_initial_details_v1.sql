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
   'title',work.title,'reviewState',intake.review_state,
   'attentionDateProposal',intake.attention_date_proposal)
 || CASE WHEN work.id=intake.work_item_id AND work.organization_id=intake.organization_id
   AND work.source_object_type='ledger_work_intake' AND work.source_object_id=intake.id
   AND work.created_by_user_id=auth.uid() AND work.household_id IS NULL
   AND intake.source_action_id LIKE 'composer:%'
   AND work.work_state='open'
   AND NOT EXISTS(SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=work.organization_id AND c.work_item_id=work.id
      AND NOT (c.subject_domain='temporal' AND c.subject_kind='occurrence'))
   THEN jsonb_build_object('instructions',work.instructions)
   ELSE '{}'::jsonb END;
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
-- Existing native Ledger projection: precise readback of the signed author's
-- own ordinary composer originals only. Do not confer editing authority or
-- include instructions on a different author's, broader organization, or
-- additional Subject context projection. Preserve all existing fields/ACLs.
-- Reviewed installed source preimage; halt on any concurrent source drift.
DO $projection_preimage$ BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)')) IS DISTINCT FROM '5b93345622732e0c3f48eeb1eae1795d'
 THEN RAISE EXCEPTION 'Native Ledger accountability source changed; reconcile before release'; END IF;
END $projection_preimage$;
CREATE OR REPLACE FUNCTION atlas.company_work_accountability_native_ledger_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_scope text DEFAULT 'native_ledger'::text, p_limit integer DEFAULT 200, p_after_work_item_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor_person_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_last_id uuid;
  v_without_proof bigint;
BEGIN
  -- Build-1 root gate proves current auth session, canonical Person/Principal,
  -- current native seat, exact Organization participation and BOTH roots.
  -- No position title, employee seat or generic membership extends this grant.
  v_actor_person_id := atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id, p_ledger_id
  );

  IF p_scope IS NULL OR p_scope NOT IN ('native_ledger','organization') THEN
    RAISE EXCEPTION 'Scope must be native_ledger or organization.' USING ERRCODE='22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 500 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 500.' USING ERRCODE='22023';
  END IF;

  SELECT COALESCE(jsonb_agg(x.item ORDER BY x.work_item_id),'[]'::jsonb),
         max(x.work_item_id::text)::uuid
    INTO v_items,v_last_id
  FROM (
    SELECT w.id AS work_item_id,
      jsonb_build_object(
        'workItemId',w.id,
        'organizationId',w.organization_id,
        'organizationUnitId',w.organization_unit_id,
        'title',w.title,
        'operationClass',w.operation_class,
        'workState',w.work_state,
        'sourceObjectType',w.source_object_type,
        'resultContractKey',w.result_contract_key,
        'selectedNativeLedgerId',p_ledger_id,
        'nativeLedgerRelevance',CASE WHEN w.has_exact_ledger_evidence
           THEN 'established_for_selected_ledger'
           ELSE 'not_established_for_selected_ledger' END,
        'otherLedgerEvidenceDoesNotProveExclusion',true,
        'responsibility',jsonb_build_object(
           'allocationId',wa.id,
           'state',CASE WHEN wa.id IS NULL THEN 'no_active_responsible_allocation'
                        ELSE 'active_responsible_allocation_observed' END,
           'establishmentBasisKind',wa.establishment_basis_kind,
           'assigneeMembershipId',wa.assignee_membership_id,
           'assigneeInstitutionalPersonRecordId',
              coalesce(wa.assignee_institutional_person_record_id,
                       om_assignee.institutional_person_record_id),
           'assigneePersonId',coalesce(wa.assignee_canonical_person_id,ipr.person_id,om_assignee.person_id),
           'personProvenance',CASE
             WHEN wa.assignee_canonical_person_id IS NOT NULL
               THEN 'person_native_ledger_connection_receiver_uptake'
             WHEN wa.assignee_institutional_person_record_id IS NOT NULL
               THEN 'exact_allocation_institutional_person'
             WHEN om_assignee.institutional_person_record_id IS NOT NULL
               THEN 'active_allocation_to_membership_institutional_person'
             WHEN om_assignee.person_id IS NOT NULL
               THEN 'active_allocation_to_membership_person'
             ELSE 'no_source_person_resolution'
           END,
           'offeredResponsibilityCount',offers.offered_count
        ),
        'lastResponsibleAllocation',CASE WHEN wa_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'allocationId',wa_hist.id,
            'allocationState',wa_hist.state,
            'establishmentBasisKind',wa_hist.establishment_basis_kind,
            'assigneeMembershipId',wa_hist.assignee_membership_id,
            'assigneeInstitutionalPersonRecordId',
               coalesce(wa_hist.assignee_institutional_person_record_id,
                        om_hist.institutional_person_record_id),
            'assigneePersonId',coalesce(wa_hist.assignee_canonical_person_id,ipr_hist.person_id,om_hist.person_id),
            'allocatedAt',wa_hist.allocated_at,
            'completedAt',wa_hist.completed_at,
            'releasedAt',wa_hist.released_at,
            'historicalNotCurrent',true
          ) END,
        'lastExecutionPlan',CASE WHEN ep_hist.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'planId',ep_hist.id,
            'planState',ep_hist.plan_state,
            'firstPlannedServiceDate',ep_hist.first_planned_service_date,
            'plannedServiceDate',ep_hist.planned_service_date,
            'exposureServiceDate',ep_hist.exposure_service_date,
            'rolloverCount',ep_hist.rollover_count,
            'historicalNotCurrent',true
          ) END,
        'planning',jsonb_build_object(
           'planId',ep.id,
           'planState',coalesce(ep.plan_state,'no_current_plan'),
           'plannedServiceDate',ep.planned_service_date,
           'firstPlannedServiceDate',ep.first_planned_service_date,
           'exposureServiceDate',ep.exposure_service_date,
           'rolloverCount',coalesce(ep.rollover_count,0),
           'sourceWindowEarliestAt',tc.earliest_lawful_at,
           'sourceWindowHardFinishAt',tc.hard_finish_at,
           'sourceWindowLatestLawfulAt',tc.latest_lawful_at,
           'planHistoryEventCount',coalesce(events.event_count,0),
           'openConflictCount',coalesce(conflicts.open_count,0)
        ),
        'workerProjection',jsonb_build_object(
           'state',CASE
             WHEN coalesce(wp.canonical_count,0)>0
               THEN 'governed_plan_projection_observed'
             WHEN coalesce(wp.related_count,0)>0
               THEN 'legacy_or_unverified_projection_observed'
             ELSE 'no_matching_worker_projection_observed' END,
           'canonicalProjectionCount',coalesce(wp.canonical_count,0),
           'otherRelatedProjectionCount',
             coalesce(wp.related_count,0)-coalesce(wp.canonical_count,0),
           'workerViewedReceipt','not_proven',
           'currentExecutionWarrant','not_proven_by_projection',
           'employeePrivateContextRead',false
        ),
        'latestWorkerReport',CASE WHEN lr.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',lr.id,'resultKind',lr.result_kind,
            'reportedAt',lr.reported_at,
            'reportedByInstitutionalPersonRecordId',lr.reported_by_institutional_person_record_id,
            'decision',coalesce(ra.decision,'no_acceptance_for_this_result'),
            'decisionAt',ra.accepted_at,
            'reportsSharingLatestTimestamp',lr.timestamp_tie_count,
            'exactOrderWithinTimestampProven',lr.timestamp_tie_count=1
          ) END,
        'latestAcceptedResult',CASE WHEN ar.id IS NULL THEN NULL ELSE
          jsonb_build_object(
            'resultId',ar.id,'resultKind',ar.result_kind,
            'reportedAt',ar.reported_at,
            'decision',ar.decision,'acceptedAt',ar.accepted_at,
            'acceptanceKind',ar.acceptance_kind
          ) END,
        'reportedResultCount',reports.total_count,
        'acceptedResultIsDistinctFromReport',true
      ) || CASE WHEN p_scope='native_ledger'
        AND w.has_exact_ledger_evidence
        AND w.created_by_user_id=auth.uid()
        AND w.household_id IS NULL
        AND w.work_state='open'
        AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
        AND atlas.person_has_native_ledger_connection_v1(w.organization_id,p_ledger_id,v_actor_person_id)
        AND NOT EXISTS(SELECT 1 FROM atlas.work_item_context_links c
          WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
          AND NOT (c.subject_domain='temporal' AND c.subject_kind='occurrence'))
        AND (
          (w.source_object_type='ledger_connected_direct_task'
           AND w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           AND w.metadata->>'createdByPersonId'=v_actor_person_id::text
           AND w.metadata->>'nativeLedgerId'=p_ledger_id::text
           AND w.metadata->>'sourceActionId' LIKE 'composer:%'
           AND w.stable_key='ledger-direct:'||auth.uid()::text||':'||md5(w.metadata->>'sourceActionId'))
          OR (w.source_object_type='ledger_work_intake' AND EXISTS(
            SELECT 1 FROM atlas.ledger_work_intakes i
            WHERE i.id=w.source_object_id AND i.work_item_id=w.id
              AND i.organization_id=w.organization_id AND i.ledger_id=p_ledger_id
              AND i.submitted_by_person_id=v_actor_person_id
              AND i.source_action_id LIKE 'composer:%'
              AND i.review_state='accepted_for_ledger'))
        )
        THEN jsonb_build_object('authoredInstructions',w.instructions)
        ELSE '{}'::jsonb END AS item
    FROM (
      SELECT wi.*,
        EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
          WHERE rel.organization_id=wi.organization_id
            AND rel.work_item_id=wi.id
            AND rel.ledger_id=p_ledger_id
            AND rel.attribution_state='active'
            AND (
              rel.evidence_kind in ('owner_attested','participant_attested')
              OR (rel.evidence_kind='source_verified' AND EXISTS (
                SELECT 1
                FROM atlas.company_work_native_ledger_exact_source_v1(
                  rel.work_item_id,rel.ledger_id
                ) proof
                WHERE proof.source_schema=rel.source_schema
                  AND proof.source_table=rel.source_table
                  AND proof.source_id=rel.source_id
              ))
            )
        ) AS has_exact_ledger_evidence
      FROM atlas.work_items wi
      WHERE wi.organization_id=p_organization_id
        AND (p_after_work_item_id IS NULL OR wi.id>p_after_work_item_id)
      ORDER BY wi.id
    ) w
    LEFT JOIN LATERAL (
      SELECT a.id,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state='active'
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa ON true
    LEFT JOIN atlas.organization_memberships om_assignee
      ON om_assignee.id=wa.assignee_membership_id
     AND om_assignee.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr
      ON ipr.id=coalesce(wa.assignee_institutional_person_record_id,
                         om_assignee.institutional_person_record_id)
     AND ipr.organization_id=w.organization_id
    -- Preserve the latest non-active responsible allocation as provenance:
    -- never advertise completed or released responsibility as current.
    LEFT JOIN LATERAL (
      SELECT a.id,a.state,a.establishment_basis_kind,a.assignee_membership_id,
             a.assignee_canonical_person_id,a.assignee_institutional_person_record_id,
             a.allocated_at,a.completed_at,a.released_at
      FROM atlas.work_allocations a
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id
        AND a.allocation_role='responsible' AND a.state IN ('completed','released')
      ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1
    ) wa_hist ON true
    LEFT JOIN atlas.organization_memberships om_hist
      ON om_hist.id=wa_hist.assignee_membership_id
     AND om_hist.organization_id=w.organization_id
    LEFT JOIN atlas.institutional_person_records ipr_hist
      ON ipr_hist.id=coalesce(wa_hist.assignee_institutional_person_record_id,
                            om_hist.institutional_person_record_id)
     AND ipr_hist.organization_id=w.organization_id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS offered_count
      FROM atlas.company_work_responsibility_transfer_offers o
      WHERE o.organization_id=w.organization_id
        AND o.work_item_id=w.id AND o.offer_state='offered'
    ) offers ON true
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.responsible_allocation_id,
             p.assignee_membership_id,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id
        AND p.work_item_id=w.id AND p.plan_state IN ('active','needs_replan')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep ON true
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,
             p.first_planned_service_date,p.exposure_service_date,p.rollover_count
      FROM atlas.work_execution_plans p
      WHERE p.organization_id=w.organization_id AND p.work_item_id=w.id
        AND p.plan_state IN ('completed','withdrawn')
      ORDER BY p.updated_at DESC,p.id DESC LIMIT 1
    ) ep_hist ON true
    LEFT JOIN LATERAL (
      SELECT t.earliest_lawful_at,t.hard_finish_at,t.latest_lawful_at
      FROM atlas.work_time_contracts t
      WHERE t.organization_id=w.organization_id AND t.work_item_id=w.id
        AND t.contract_state='active'
      ORDER BY t.created_at DESC,t.id DESC LIMIT 1
    ) tc ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS event_count
      FROM atlas.work_execution_plan_events e
      WHERE e.organization_id=w.organization_id AND e.work_item_id=w.id
    ) events ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS open_count
      FROM atlas.work_planning_conflicts c
      WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
        AND c.state='open'
    ) conflicts ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS related_count,
        count(*) FILTER (
          WHERE ep.id IS NOT NULL
            AND ep.plan_state='active'
            AND ep.responsible_allocation_id=wa.id
            AND ep.assignee_membership_id=wa.assignee_membership_id
            AND p.source_kind='work_item'
            AND p.source_id=w.id
            AND p.planned_date=ep.exposure_service_date
            AND p.delivery_payload->>'projectionAuthority'='work_execution_plans'
            AND p.delivery_payload->>'managerPlanId'=ep.id::text
            AND p.delivery_payload->>'source'='company_work_employee_plan_projection_v1'
            AND p.delivery_payload->>'canonicalCompanyWorkProjection'='true'
        )::integer AS canonical_count
      FROM atlas.worker_week_projection_sources s
      JOIN atlas.worker_week_projection p ON p.id=s.projection_id
      WHERE s.work_item_id=w.id AND s.source_role='required'
        AND p.organization_id=w.organization_id
        AND wa.id IS NOT NULL
        AND p.organization_membership_id=wa.assignee_membership_id
    ) wp ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,
             r.reported_by_institutional_person_record_id,
             (SELECT count(*)::integer FROM atlas.work_execution_results tied
              WHERE tied.organization_id=r.organization_id
                AND tied.work_item_id=r.work_item_id
                AND tied.reported_at=r.reported_at) AS timestamp_tie_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
      -- A transaction timestamp may tie across multiple worker reports;
      -- UUID sorting is deterministic, never proof of report chronology.
      ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
    ) lr ON true
    LEFT JOIN atlas.work_result_acceptances ra
      ON ra.execution_result_id=lr.id
     AND ra.organization_id=w.organization_id
     AND ra.work_item_id=w.id
    LEFT JOIN LATERAL (
      SELECT count(*)::integer AS total_count
      FROM atlas.work_execution_results r
      WHERE r.organization_id=w.organization_id AND r.work_item_id=w.id
    ) reports ON true
    LEFT JOIN LATERAL (
      SELECT r.id,r.result_kind,r.reported_at,a.decision,
             a.accepted_at,a.acceptance_kind
      FROM atlas.work_result_acceptances a
      JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
       AND r.organization_id=a.organization_id
       AND r.work_item_id=a.work_item_id
      WHERE a.organization_id=w.organization_id
        AND a.work_item_id=w.id AND a.decision='accepted'
      ORDER BY a.accepted_at DESC,a.id DESC LIMIT 1
    ) ar ON true
    WHERE p_scope='organization' OR w.has_exact_ledger_evidence
    ORDER BY w.id
    LIMIT p_limit
  ) x;

  -- This count is diagnostic for institution-owned work with no CURRENT
  -- native Ledger evidence at all. It does not authorize showing those
  -- Work rows in the selected native Ledger.
  SELECT count(*) INTO v_without_proof
  FROM atlas.work_items wi
  WHERE wi.organization_id=p_organization_id
    AND NOT EXISTS (
      SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
      WHERE rel.organization_id=wi.organization_id
        AND rel.work_item_id=wi.id
        AND rel.attribution_state='active'
        AND (rel.evidence_kind in ('owner_attested','participant_attested')
          OR (rel.evidence_kind='source_verified' AND EXISTS (
            SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
              rel.work_item_id,rel.ledger_id
            ) proof
            WHERE proof.source_schema=rel.source_schema
              AND proof.source_table=rel.source_table
              AND proof.source_id=rel.source_id
          )))
    );

  RETURN jsonb_build_object(
    'contractVersion','company_work_accountability_native_ledger_v1',
    'organizationId',p_organization_id,
    'selectedNativeLedgerId',p_ledger_id,
    'scopeMode',p_scope,
    'scopeRule',CASE WHEN p_scope='native_ledger'
      THEN 'only_currently_proven_exact_native_ledger_relevance'
      ELSE 'explicit_organization_accountability_not_ledger_attribution' END,
    'items',v_items,
    'pageLimit',p_limit,
    'nextAfterWorkItemId',v_last_id,
    'organizationWorkWithoutAnyCurrentNativeLedgerEvidenceCount',v_without_proof,
    'facts',jsonb_build_object(
      'workOwnedByOrganization',true,
      'reportIsNotAcceptance',true,
      'managerDoesNotImpersonateWorker',true,
      'projectionIsNotProofWorkerViewed',true,
      'projectionIsNotExecutionLease',true,
      'principalClockEscalationNotRequired',true,
      'privatePersonalAtlasNotRead',true,
      'noNewResponsibilityOrPlanCreated',true,
      'sortPriorityNotInvented',true
    )
  );
END
$function$;

COMMIT;
