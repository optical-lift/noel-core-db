-- UNI-OPS-01 / Actual-first P1: HELD, not a migration or production grant.
-- Source-only, one first-party farm activity log -> one pre-existing assigned
-- original -> the existing qualified physical care Actual. P2 retrospective
-- governor recognition and P3 successor cutover are NOT implemented here.

CREATE TABLE atlas.assigned_care_activity_recognition_links_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  activity_log_id uuid NOT NULL UNIQUE
    REFERENCES atlas.field_logs(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  execution_result_id uuid NOT NULL UNIQUE
    REFERENCES atlas.work_execution_results(id) ON DELETE RESTRICT,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_person_id uuid NOT NULL,
  source_farm_id uuid NOT NULL REFERENCES atlas.farms(id) ON DELETE RESTRICT,
  source_activity_sentence text NOT NULL
    CHECK (pg_catalog.char_length(source_activity_sentence) BETWEEN 3 AND 500),
  recognized_actual_kind text NOT NULL,
  recognized_condition_after text NOT NULL,
  recognition_mode text NOT NULL DEFAULT 'preexisting_assigned_original'
    CHECK (recognition_mode='preexisting_assigned_original'),
  recognized_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
  UNIQUE (work_item_id,activity_log_id)
);
COMMENT ON TABLE atlas.assigned_care_activity_recognition_links_v1 IS
  'Append-only provenance link between ordinary inert worker activity evidence and a source-qualified Result on one preexisting assigned original; not a new Work or Actual store.';
ALTER TABLE atlas.assigned_care_activity_recognition_links_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.assigned_care_activity_recognition_links_v1
  FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION atlas.block_assigned_care_activity_recognition_rewrite_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $immutable$
BEGIN
  RAISE EXCEPTION 'Activity-Actual recognition history is immutable'
    USING ERRCODE='55000';
END;
$immutable$;
REVOKE ALL ON FUNCTION atlas.block_assigned_care_activity_recognition_rewrite_v1()
  FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER assigned_care_activity_recognition_append_only_v1
  BEFORE UPDATE OR DELETE ON atlas.assigned_care_activity_recognition_links_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.block_assigned_care_activity_recognition_rewrite_v1();

CREATE FUNCTION atlas.recognize_assigned_care_activity_self_api_v1(
  p_activity_log_id uuid,p_work_item_id uuid,p_actual_kind text,p_condition_after text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $recognize$
DECLARE
  v_uid uuid:=auth.uid();
  v_person uuid:=atlas.current_person_id_v1();
  v_activity atlas.field_logs%ROWTYPE;
  v_membership atlas.farm_memberships%ROWTYPE;
  v_work atlas.work_items%ROWTYPE;
  v_allocation atlas.work_allocations%ROWTYPE;
  v_state atlas.rhythm_state%ROWTYPE;
  v_link atlas.assigned_care_activity_recognition_links_v1%ROWTYPE;
  v_result atlas.work_execution_results%ROWTYPE;
  v_receipt jsonb;
  v_result_id uuid;
  v_kind text:=nullif(pg_catalog.btrim(p_actual_kind),'');
  v_after text:=nullif(pg_catalog.btrim(p_condition_after),'');
  v_replayed boolean:=false;
BEGIN
  IF v_uid IS NULL OR v_person IS NULL OR p_activity_log_id IS NULL
    OR p_work_item_id IS NULL OR v_kind IS NULL OR v_after IS NULL
    OR pg_catalog.length(v_kind)>80 OR pg_catalog.length(v_after)>120
  THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Serialize use of one physical testimony across all candidate originals.
  SELECT * INTO v_activity FROM atlas.field_logs
    WHERE id=p_activity_log_id FOR UPDATE;
  IF v_activity.id IS NULL OR v_activity.source<>'worker_manual_log'
    OR v_activity.retracted_at IS NOT NULL
    OR v_activity.actor_user_id IS DISTINCT FROM v_uid
    OR nullif(pg_catalog.btrim(v_activity.summary_sentence),'') IS NULL
  THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_membership FROM atlas.farm_memberships
    WHERE id=v_activity.actor_membership_id
      AND farm_id=v_activity.farm_id AND user_id=v_uid AND active;
  IF v_membership.id IS NULL THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id FOR UPDATE;
  IF v_work.id IS NULL OR v_work.organization_id IS NULL
    OR v_work.household_id IS NOT NULL
    OR v_work.source_object_type<>'rhythm_state'
    OR v_work.result_contract_key<>'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract' IS DISTINCT FROM 'continuing_original_work_v1'
  THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_state FROM atlas.rhythm_state
    WHERE id=v_work.source_object_id
      AND organization_id=v_work.organization_id
      AND farm_id=v_activity.farm_id AND subject_kind='growing_object';
  IF v_state.id IS NULL THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_allocation FROM atlas.work_allocations a
    WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
      AND a.allocation_role='responsible'
      AND a.assignee_canonical_person_id=v_person
      AND a.state IN ('active','completed')
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
    ORDER BY a.allocated_at DESC,a.id DESC LIMIT 1;
  IF v_allocation.id IS NULL
    OR v_work.created_at IS NULL
    OR v_activity.created_at IS NULL
    OR v_allocation.allocated_at IS NULL
    OR v_work.created_at>v_activity.created_at
    OR v_allocation.allocated_at>v_activity.created_at
    OR NOT EXISTS (
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.work_item_id=v_work.id AND l.organization_id=v_work.organization_id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
        AND l.subject_id=v_state.subject_id AND l.relation_kind='acts_on')
  THEN
    RAISE EXCEPTION 'Signed activity or original unavailable'
      USING ERRCODE='42501';
  END IF;

  -- Chronology is only a necessary guard: the first-party worker witnesses
  -- execution; the activity log itself does not supply a verified occurred_at.
  -- The held R02 Result writer still has a conditional successor issuer.
  -- Fail closed for any campaign-related original until P3 removes that path.
  IF v_work.metadata ? 'sourceStandingCampaignId'
    OR v_work.metadata->>'sourceAdmissionMode'='owner_standing_successor_v1'
  THEN
    RAISE EXCEPTION 'Campaign-linked Actual requires no-successor source cutover'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_link FROM atlas.assigned_care_activity_recognition_links_v1
    WHERE activity_log_id=v_activity.id FOR UPDATE;
  IF v_link.id IS NOT NULL AND (
    v_link.work_item_id IS DISTINCT FROM v_work.id
    OR v_link.actor_user_id IS DISTINCT FROM v_uid
    OR v_link.actor_person_id IS DISTINCT FROM v_person
    OR v_link.recognized_actual_kind IS DISTINCT FROM v_kind
    OR v_link.recognized_condition_after IS DISTINCT FROM v_after
    OR v_link.source_activity_sentence IS DISTINCT FROM v_activity.summary_sentence)
  THEN
    RAISE EXCEPTION 'One signed activity cannot become a different Actual'
      USING ERRCODE='23505';
  END IF;

  -- The original activity UUID is the immutable signed action identity.
  -- Typed kind and observed condition are explicit worker attestation,
  -- never silently extracted as physical truth from sentence text.
  v_receipt:=atlas.record_continuing_care_actual_self_api_v1(
    v_work.id,v_activity.id,v_kind,v_after,NULL,v_activity.summary_sentence,NULL);
  IF v_receipt->>'ok' IS DISTINCT FROM 'true'
    OR v_receipt->>'workItemId' IS DISTINCT FROM v_work.id::text
    OR v_receipt->>'physicalActualContractVersion'
       IS DISTINCT FROM 'continuing_care_actual_v1'
    OR v_receipt->>'noNewWorkCreated' IS DISTINCT FROM 'true'
    OR v_receipt->>'noClockAdmission' IS DISTINCT FROM 'true'
    OR nullif(v_receipt->>'workResultId','') IS NULL
  THEN
    -- Any transitive successor effect is rolled back in this transaction.
    RAISE EXCEPTION 'Native physical Result lacked the no-successor receipt'
      USING ERRCODE='23514';
  END IF;
  v_result_id:=(v_receipt->>'workResultId')::uuid;
  SELECT * INTO v_result FROM atlas.work_execution_results
    WHERE id=v_result_id AND work_item_id=v_work.id
      AND organization_id=v_work.organization_id;
  IF v_result.id IS NULL
    OR v_result.reported_by_user_id IS DISTINCT FROM v_uid
    OR v_result.result_contract_key<>'continuing_care_actual_v1'
    OR v_result.payload->>'actualKind' IS DISTINCT FROM v_kind
    OR v_result.payload->>'conditionAfter' IS DISTINCT FROM v_after
    OR v_result.payload->>'note' IS DISTINCT FROM v_activity.summary_sentence
    OR v_result.idempotency_key IS DISTINCT FROM
       ('continuing-care-actual:'||v_work.id::text||':'||v_activity.id::text)
    OR NOT EXISTS (
      SELECT 1 FROM atlas.work_result_acceptances a
      WHERE a.work_item_id=v_work.id
        AND a.execution_result_id=v_result.id
        AND a.organization_id=v_work.organization_id
        AND a.decision='accepted'
        AND a.acceptance_kind='source_qualified_physical_actual')
  THEN
    RAISE EXCEPTION 'Exact signed physical Result acceptance not confirmed'
      USING ERRCODE='23514';
  END IF;

  IF v_link.id IS NULL THEN
    INSERT INTO atlas.assigned_care_activity_recognition_links_v1(
      activity_log_id,work_item_id,execution_result_id,actor_user_id,
      actor_person_id,source_farm_id,source_activity_sentence,
      recognized_actual_kind,recognized_condition_after
    ) VALUES (
      v_activity.id,v_work.id,v_result.id,v_uid,
      v_person,v_activity.farm_id,v_activity.summary_sentence,v_kind,v_after
    ) RETURNING * INTO v_link;
  ELSIF v_link.execution_result_id IS DISTINCT FROM v_result.id THEN
    RAISE EXCEPTION 'Activity already linked to a different Result'
      USING ERRCODE='23505';
  ELSE
    v_replayed:=true;
  END IF;

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,'contractVersion','assigned_care_activity_recognition_v1',
    'recognitionMode','preexisting_assigned_original',
    'activityLogId',v_activity.id,'recognitionLinkId',v_link.id,
    'workItemId',v_work.id,'workResultId',v_result.id,
    'workState',v_receipt->>'workState',
    'recognizedActualKind',v_kind,'recognizedConditionAfter',v_after,
    'idempotent',v_replayed,'retrospectiveOriginalCreated',false,
    'noNewWorkCreated',true,'noClockAdmission',true,
    'nextCampaignAuthorized',false);
END;
$recognize$;
REVOKE ALL ON FUNCTION atlas.recognize_assigned_care_activity_self_api_v1(
  uuid,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;

-- Public adapter has no separate authorizing meaning. The private function
-- rechecks the authenticated actor, exact source and original on every call.
CREATE FUNCTION public.recognize_assigned_care_activity_self_api_v1(
  p_activity_log_id uuid,p_work_item_id uuid,
  p_actual_kind text,p_condition_after text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $rpc$
  SELECT atlas.recognize_assigned_care_activity_self_api_v1(
    p_activity_log_id,p_work_item_id,p_actual_kind,p_condition_after);
$rpc$;
REVOKE ALL ON FUNCTION public.recognize_assigned_care_activity_self_api_v1(
  uuid,uuid,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.recognize_assigned_care_activity_self_api_v1(
  uuid,uuid,text,text) TO authenticated;
