-- Atlas Build 5: owner-reviewed legacy Company Work recovery, first surfaced by source zone.
-- Source Task remains unchanged; archived means no recorded completion, not proof the work is still needed.
-- Authority: native Ledger + Organization governing roots, never a legacy employee/worker-day seat.
CREATE TABLE IF NOT EXISTS atlas.company_work_legacy_task_reviews_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  native_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  source_task_id uuid NOT NULL REFERENCES atlas.tasks(id) ON DELETE RESTRICT,
  decision_kind text NOT NULL CHECK (decision_kind IN ('recovered_new_work','matched_existing_work','not_current')),
  target_work_item_id uuid REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  source_title_snapshot text NOT NULL,
  source_status_snapshot text NOT NULL,
  source_metadata_snapshot jsonb NOT NULL,
  source_note_snapshot text,
  original_executor_label text,
  original_assignee_canonical_person_id uuid REFERENCES reality.entities(id) ON DELETE RESTRICT,
  owner_reason text NOT NULL CHECK (length(btrim(owner_reason)) BETWEEN 12 AND 1200),
  decided_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT company_work_legacy_task_reviews_one_decision_v1 UNIQUE (organization_id,source_task_id),
  CONSTRAINT company_work_legacy_task_reviews_target_v1 CHECK (
    (decision_kind='not_current' AND target_work_item_id IS NULL) OR
    (decision_kind IN ('recovered_new_work','matched_existing_work') AND target_work_item_id IS NOT NULL)
  )
);
CREATE INDEX IF NOT EXISTS company_work_legacy_task_reviews_ledger_v1
  ON atlas.company_work_legacy_task_reviews_v1(organization_id,native_ledger_id,decided_at);
ALTER TABLE atlas.company_work_legacy_task_reviews_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.company_work_legacy_task_reviews_v1 FROM PUBLIC, anon, authenticated;
-- Exact legacy source identity must have at most one canonical Work, including under parallel owner requests.
CREATE UNIQUE INDEX IF NOT EXISTS work_items_one_legacy_source_per_org_v1
  ON atlas.work_items(organization_id,source_object_id)
  WHERE source_object_type='legacy_task' AND source_object_id IS NOT NULL;

CREATE OR REPLACE FUNCTION atlas.company_work_legacy_backlog_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_source_zone text DEFAULT 'Venue',
  p_limit integer DEFAULT 100, p_after_task_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_actor uuid;
  v_rows jsonb := '[]'::jsonb;
  v_cursor uuid;
  v_has_more boolean := false;
BEGIN
  v_actor := atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  IF p_source_zone IS NULL OR btrim(p_source_zone)='' OR length(p_source_zone)>100
     OR p_limit IS NULL OR p_limit<1 OR p_limit>200 THEN
    RAISE EXCEPTION 'Valid source-zone and limit (1..200) required' USING ERRCODE='22023';
  END IF;

  WITH source_rows AS (
    SELECT t.*, d.decision_kind,d.target_work_item_id,d.decided_at,d.owner_reason,
      (SELECT w.id FROM atlas.work_items w
        WHERE w.organization_id=p_organization_id
          AND w.source_object_type='legacy_task' AND w.source_object_id=t.id
        LIMIT 1) AS direct_work_item_id,
      (SELECT pp.id FROM atlas.project_pull_items pp
        WHERE pp.source_task_id=t.id ORDER BY pp.created_at LIMIT 1) AS old_pool_item_id,
      (SELECT pp.status FROM atlas.project_pull_items pp
        WHERE pp.source_task_id=t.id ORDER BY pp.created_at LIMIT 1) AS old_pool_status,
      (SELECT atlas.organization_person_canonical_reality_v1(p_organization_id,m.person_id)
        FROM atlas.organization_memberships m
        WHERE m.organization_id=p_organization_id AND m.user_id=t.assigned_user_id
          AND m.person_id IS NOT NULL
        ORDER BY m.created_at LIMIT 1) AS reconciled_person_id
    FROM atlas.tasks t
    LEFT JOIN atlas.company_work_legacy_task_reviews_v1 d
      ON d.organization_id=t.organization_id AND d.source_task_id=t.id
    WHERE t.organization_id=p_organization_id
      AND t.status='archived' AND t.completed_at IS NULL
      AND t.metadata->>'collection_zone'=p_source_zone
      AND (p_after_task_id IS NULL OR t.id>p_after_task_id)
    ORDER BY t.id LIMIT p_limit+1
  ), numbered AS (
    SELECT s.*, row_number() OVER (ORDER BY s.id) AS row_number
    FROM source_rows s
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'sourceTaskId',id,'sourceTitle',title,'sourceStatus',status,
    'sourceCreatedAt',created_at,'sourceUpdatedAt',updated_at,
    'sourceDueDateHistoricalOnly',due_date,
    'sourceNote',note,'sourceCollectionZone',metadata->>'collection_zone',
    'sourceCollectionLabel',metadata->>'collection_label',
    'sourceDisplayLocation',metadata->>'display_location',
    'originalExecutorLabel',coalesce(metadata->>'executor_label',metadata->>'assigned_to'),
    'reconciledOriginalAssigneePersonId',reconciled_person_id,
    'originalAssigneeEvidence',CASE WHEN reconciled_person_id IS NOT NULL
      THEN 'historical_user_membership_to_reconciled_person'
      ELSE 'unverified_legacy_executor_label' END,
    'oldPoolItemId',old_pool_item_id,'oldPoolStatus',old_pool_status,
    'sourceLinkedCanonicalWorkId',direct_work_item_id,
    'recoveryDecision',decision_kind,
    'recoveryTargetWorkItemId',target_work_item_id,
    'recoveryDecidedAt',decided_at,'recoveryOwnerReason',owner_reason
  ) ORDER BY id),'[]'::jsonb),
  max(id::text)::uuid
  INTO v_rows,v_cursor
  FROM numbered WHERE row_number<=p_limit;
  SELECT count(*)>p_limit INTO v_has_more FROM (
    SELECT 1 FROM atlas.tasks t
    WHERE t.organization_id=p_organization_id
      AND t.status='archived' AND t.completed_at IS NULL
      AND t.metadata->>'collection_zone'=p_source_zone
      AND (p_after_task_id IS NULL OR t.id>p_after_task_id)
    ORDER BY t.id LIMIT p_limit+1
  ) x;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','company_work_legacy_backlog_owner_v1',
    'organizationId',p_organization_id,'nativeLedgerId',p_ledger_id,
    'sourceZone',p_source_zone,'sourceStatusMeaning','historical_archive_without_recorded_completion',
    'noCanonicalWorkCreated',true,'noResponsibilityEstablished',true,
    'items',v_rows,'hasMore',v_has_more,
    'nextAfterTaskId',CASE WHEN v_has_more THEN v_cursor ELSE NULL END);
END;
$$;
REVOKE ALL ON FUNCTION atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)
  FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.company_work_legacy_backlog_owner_self_api_v1(uuid,uuid,text,integer,uuid)
  TO authenticated;

CREATE OR REPLACE FUNCTION atlas.decide_company_work_legacy_backlog_owner_self_api_v1(
  p_organization_id uuid, p_ledger_id uuid, p_source_task_id uuid,
  p_source_zone text, p_expected_source_title text,
  p_decision text, p_reason text,
  p_new_work_title text DEFAULT NULL,
  p_existing_work_item_id uuid DEFAULT NULL,
  p_confirm_distinct_current_work boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_actor uuid;
  v_task atlas.tasks%rowtype;
  v_recovered uuid;
  v_target uuid;
  v_existing atlas.company_work_legacy_task_reviews_v1%rowtype;
  v_original_person uuid;
  v_executor_label text;
  v_operation text;
  v_new_title text:=nullif(btrim(coalesce(p_new_work_title,'')),'');
BEGIN
  v_actor := atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
  IF p_source_task_id IS NULL OR p_decision IS NULL OR p_decision NOT IN
      ('recovered_new_work','matched_existing_work','not_current')
    OR p_source_zone IS NULL OR btrim(p_source_zone)=''
    OR length(p_source_zone)>100
    OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 12 AND 1200
    OR p_expected_source_title IS NULL OR btrim(p_expected_source_title)='' THEN
    RAISE EXCEPTION 'Valid exact-source, decision and owner reason required' USING ERRCODE='22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.legacy_recovery:'||p_organization_id||':'||p_source_task_id,0));
  SELECT * INTO v_task FROM atlas.tasks
    WHERE id=p_source_task_id AND organization_id=p_organization_id FOR SHARE;
  IF v_task.id IS NULL OR v_task.status<>'archived' OR v_task.completed_at IS NOT NULL
     OR v_task.metadata->>'collection_zone' IS DISTINCT FROM p_source_zone
     OR v_task.title IS DISTINCT FROM p_expected_source_title THEN
    RAISE EXCEPTION 'Archived source identity/evidence changed; reload the review' USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_existing FROM atlas.company_work_legacy_task_reviews_v1
    WHERE organization_id=p_organization_id AND source_task_id=p_source_task_id;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','company_work_legacy_backlog_decision_v1',
      'state','already_reviewed','decision',v_existing.decision_kind,
      'sourceTaskId',p_source_task_id,'workItemId',v_existing.target_work_item_id,
      'newWorkCreated',false,'newAllocationCreated',false,
      'sourceHistoryPreserved',true);
  END IF;
  SELECT w.id INTO v_recovered FROM atlas.work_items w
    WHERE w.organization_id=p_organization_id
      AND w.source_object_type='legacy_task' AND w.source_object_id=p_source_task_id
    LIMIT 1;
  IF v_recovered IS NOT NULL THEN
    RAISE EXCEPTION 'Legacy source already has canonical Work; review that exact Work'
      USING ERRCODE='23505';
  END IF;

  SELECT atlas.organization_person_canonical_reality_v1(p_organization_id,m.person_id)
    INTO v_original_person FROM atlas.organization_memberships m
    WHERE m.organization_id=p_organization_id AND m.user_id=v_task.assigned_user_id
      AND m.person_id IS NOT NULL
    ORDER BY m.created_at LIMIT 1;
  v_executor_label:=coalesce(v_task.metadata->>'executor_label',v_task.metadata->>'assigned_to');
  IF p_decision='recovered_new_work' THEN
    IF v_new_title IS NULL OR length(v_new_title) NOT BETWEEN 3 AND 200
       OR p_existing_work_item_id IS NOT NULL OR p_confirm_distinct_current_work IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'New Work requires exact owner-authored title and distinct-Work attestation'
        USING ERRCODE='22023';
    END IF;
    -- Exact-title collisions are blocked; semantically similar work must still be reviewed by Owner.
    IF EXISTS (
      SELECT 1 FROM atlas.work_items w
      WHERE w.organization_id=p_organization_id AND w.work_state='open'
        AND lower(btrim(w.title))=lower(v_new_title)
    ) THEN
      RAISE EXCEPTION 'Open Work already has this title; match the existing Work or resolve duplication'
        USING ERRCODE='23505';
    END IF;
    INSERT INTO atlas.work_items(
      organization_id,title,work_state,source_object_type,source_object_id,
      stable_key,created_by_user_id,metadata
    ) VALUES (
      p_organization_id,v_new_title,'open','legacy_task',v_task.id,
      'legacy_recovery:'||v_task.id::text,auth.uid(),
      jsonb_build_object(
        'recoveryContract','company_work_legacy_backlog_owner_v1',
        'originalTaskId',v_task.id,'originalTaskTitle',v_task.title,
        'originalTaskStatus',v_task.status,
        'sourceTaskIsCurrentAuthority',false,
        'sourceTaskEvidencePreserved',true,
        'originalExecutorLabel',v_executor_label,
        'originalAssigneeCanonicalPersonId',v_original_person,
        'ownerDistinctWorkAttestation',true,
        'ownerDecisionReason',btrim(p_reason),
        'noAutomaticResponsibilityOrSchedule',true
      )
    ) RETURNING id INTO v_target;
    v_operation:='created';
  ELSIF p_decision='matched_existing_work' THEN
    IF p_existing_work_item_id IS NULL OR v_new_title IS NOT NULL THEN
      RAISE EXCEPTION 'Exact existing Work identity is required for source matching'
        USING ERRCODE='22023';
    END IF;
    SELECT w.id INTO v_target FROM atlas.work_items w
      WHERE w.id=p_existing_work_item_id AND w.organization_id=p_organization_id;
    IF v_target IS NULL THEN
      RAISE EXCEPTION 'Existing Work not in this Organization' USING ERRCODE='23514';
    END IF;
    v_operation:='matched';
  ELSE
    IF v_new_title IS NOT NULL OR p_existing_work_item_id IS NOT NULL THEN
      RAISE EXCEPTION 'No current Work decision cannot select a Work target'
        USING ERRCODE='22023';
    END IF;
    v_target:=NULL;
    v_operation:='not_current';
  END IF;

  INSERT INTO atlas.company_work_legacy_task_reviews_v1(
    organization_id,native_ledger_id,source_task_id,decision_kind,
    target_work_item_id,decided_by_person_id,source_title_snapshot,
    source_status_snapshot,source_metadata_snapshot,source_note_snapshot,
    original_executor_label,original_assignee_canonical_person_id,owner_reason
  ) VALUES (
    p_organization_id,p_ledger_id,v_task.id,p_decision,v_target,v_actor,
    v_task.title,v_task.status,v_task.metadata,v_task.note,
    v_executor_label,v_original_person,btrim(p_reason)
  );
  IF v_target IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
      AND r.work_item_id=v_target AND r.attribution_state='active'
  ) THEN
    INSERT INTO atlas.company_work_native_ledger_relevance(
      organization_id,work_item_id,ledger_id,relation_kind,evidence_kind,
      attestation_source_ref,attestation_reason,established_by_person_id
    ) VALUES (
      p_organization_id,v_target,p_ledger_id,'serves_purpose','owner_attested',
      'legacy_task:'||v_task.id::text,btrim(p_reason),v_actor
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','company_work_legacy_backlog_decision_v1',
    'state',v_operation,'decision',p_decision,'sourceTaskId',v_task.id,
    'workItemId',v_target,
    'newWorkCreated',p_decision='recovered_new_work',
    'newAllocationCreated',false,'planCreated',false,'legacyTaskChanged',false,
    'sourceHistoryPreserved',true,'sourceOriginalExecutorLabel',v_executor_label,
    'originalAssigneeCanonicalPersonId',v_original_person,
    'canonicalResponsibilityEstablished',false);
END;
$$;
REVOKE ALL ON FUNCTION atlas.decide_company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text,text,text,uuid,boolean) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.decide_company_work_legacy_backlog_owner_self_api_v1(
  uuid,uuid,uuid,text,text,text,text,text,uuid,boolean) TO authenticated;
