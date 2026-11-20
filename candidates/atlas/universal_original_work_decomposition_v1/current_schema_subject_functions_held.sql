BEGIN;
-- HELD current-schema function-only candidate; NOT a migration or release authorization.
-- Source from exact reviewed PR #2887 head 79ae66223efaa23a87d7638842794d9b8be93a01.
-- Existing signatures, wrapper functions, permissions, triggers and relations stay intact.
-- Require existing source identity; never replay the historical table-creation bundle.
DO $current_source$
BEGIN
  IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('atlas.owner_original_subject_choices_for_work_self_api_v1(uuid,uuid,uuid,integer,uuid)'))
      IS DISTINCT FROM '0a966d596481d1bc58bf9f63fcc1b639'
  THEN
    RAISE EXCEPTION 'Current source drift: owner_original_subject_choices_for_work_self_api_v1';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('atlas.split_original_canonical_work_owner_self_api_v1(uuid,uuid,uuid,jsonb,uuid,text)'))
      IS DISTINCT FROM 'fe2d6c24c997b3f462c6eda5fae5a2bf'
  THEN
    RAISE EXCEPTION 'Current source drift: split_original_canonical_work_owner_self_api_v1';
  END IF;
  IF (SELECT md5(p.prosrc) FROM pg_catalog.pg_proc p
      WHERE p.oid=pg_catalog.to_regprocedure('atlas.guard_work_growing_object_context_v1()'))
      IS DISTINCT FROM '0278360920a2d26a301ceda4591b9994'
  THEN
    RAISE EXCEPTION 'Current source drift: guard_work_growing_object_context_v1';
  END IF;
END;
$current_source$;

CREATE OR REPLACE FUNCTION atlas.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 80,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_person uuid;
 v_rows jsonb:='[]'::jsonb;
 v_next uuid;
 v_more boolean:=false;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_work_item_id IS NULL THEN
  RAISE EXCEPTION 'Exact Work and bounded page required' USING ERRCODE='22023';
 END IF;
 v_person:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
      AND atlas.work_prerequisite_ledger_scope_v1(
        w.organization_id,p_ledger_id,w.id
      )
 ) THEN
  RAISE EXCEPTION 'Original Work not admitted on this Ledger' USING ERRCODE='42501';
 END IF;
 WITH page AS(
  SELECT o.id, o.label, o.object_type,
   row_number() OVER(ORDER BY o.id) rn
  FROM atlas.growing_objects o
  JOIN atlas.farms f ON f.id=o.farm_id
  JOIN atlas.work_items w ON w.id=p_work_item_id
    AND w.organization_id=f.organization_id
    AND w.organization_unit_id=f.organization_unit_id
  JOIN atlas.farm_crop_ledger_custody_v1 cu ON cu.farm_id=f.id
    AND cu.ledger_id=p_ledger_id AND cu.custody_state='active'
    AND cu.ended_at IS NULL
  JOIN atlas.ledger_organization_participations lp
    ON lp.organization_id=f.organization_id AND lp.ledger_id=cu.ledger_id
    AND lp.status='active' AND lp.ended_at IS NULL
    AND lp.participation_kind IN ('governing','operating')
  JOIN ledger.ledgers nl ON nl.id=cu.ledger_id
    AND nl.ledger_state='active' AND nl.retired_at IS NULL
  WHERE f.organization_id=p_organization_id AND o.object_type='bed'
    AND (p_after_subject_id IS NULL OR o.id>p_after_subject_id)
  ORDER BY o.id LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'subjectDomain','spatial','subjectKind','growing_object',
    'subjectId',q.id,'label',q.label,'kindLabel',q.object_type)
    ORDER BY q.id) FILTER(WHERE q.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,(array_agg(q.id ORDER BY q.rn) FILTER(WHERE q.rn=p_limit))[1]
 INTO v_rows,v_more,v_next FROM page q;
 RETURN jsonb_build_object('ok',true,
   'contractVersion','owner_original_subject_choices_for_work_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'workItemId',p_work_item_id,'choices',v_rows,'hasMore',v_more,
   'nextAfterSubjectId',CASE WHEN v_more THEN v_next ELSE NULL END,
   'choicesAreNotResponsibilities',true);
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.split_original_canonical_work_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_parent_work_item_id uuid,
 p_parts jsonb,p_action_id uuid,p_decision_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid;
 v_parent atlas.work_items%rowtype;
 v_group atlas.work_decomposition_groups%rowtype;
 v_part jsonb;
 v_subject_domain text;
 v_subject_kind text;
 v_subject_id uuid;
 v_subject_stable_key text;
 v_child_stable_key text;
 v_title text;
 v_instructions text;
 v_result_contract text;
 v_child uuid;
 v_ordinal integer:=0;
 v_fingerprint text;
 v_children jsonb:='[]'::jsonb;
 v_count integer;
BEGIN
 IF p_organization_id IS NULL OR p_ledger_id IS NULL OR
    p_parent_work_item_id IS NULL OR p_action_id IS NULL OR
    jsonb_typeof(p_parts) IS DISTINCT FROM 'array' OR
    jsonb_array_length(p_parts) NOT BETWEEN 2 AND 12 OR
    length(btrim(coalesce(p_decision_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact original Work, parts, action and decision required.' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 -- Serializes retries and competing decompositions of the SAME original ID.
 PERFORM pg_advisory_xact_lock(hashtextextended(
   'atlas.work.decomposition:'||p_parent_work_item_id::text,0));
 SELECT * INTO v_parent FROM atlas.work_items
  WHERE id=p_parent_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 IF v_parent.id IS NULL THEN
   RAISE EXCEPTION 'Original Work unavailable on governed Ledger.' USING ERRCODE='42501';
 END IF;
 IF NOT atlas.work_prerequisite_ledger_scope_v1(
   p_organization_id,p_ledger_id,v_parent.id
 ) THEN
   RAISE EXCEPTION 'Work lacks established relevance to governed Ledger.' USING ERRCODE='42501';
 END IF;
 v_fingerprint:=md5(p_parts::text||'|'||btrim(p_decision_reason));
 SELECT * INTO v_group FROM atlas.work_decomposition_groups
  WHERE parent_work_item_id=v_parent.id;
 IF v_group.id IS NOT NULL THEN
   IF v_group.authorized_ledger_id IS DISTINCT FROM p_ledger_id OR
      v_group.action_id IS DISTINCT FROM p_action_id OR
      v_group.source_fingerprint IS DISTINCT FROM v_fingerprint THEN
     RAISE EXCEPTION 'Work was already decomposed by a different decision.' USING ERRCODE='23505';
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'workItemId',m.child_work_item_id,'resultContractKey',(
         SELECT w.result_contract_key FROM atlas.work_items w WHERE w.id=m.child_work_item_id
       ),'subjectDomain',m.subject_domain,
      'subjectKind',m.subject_kind,'subjectId',m.subject_id)
     ORDER BY m.part_ordinal),'[]'::jsonb) INTO v_children
     FROM atlas.work_decomposition_members m WHERE m.group_id=v_group.id;
   RETURN jsonb_build_object('ok',true,'contractVersion','original_canonical_work_decomposition_v1',
     'parentWorkItemId',v_parent.id,'decompositionId',v_group.id,'children',v_children,
     'idempotent',true,'parentHistoryPreserved',true,'childrenUnassigned',true);
 END IF;
 IF v_parent.work_state<>'open' THEN
   RAISE EXCEPTION 'Original Work must be open and current before decomposition.' USING ERRCODE='23514';
 END IF;
 -- No copies from old task rows; each part must be a different independently
 -- actionable original Subject with an admitted exact source.
 FOR v_part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
   v_ordinal:=v_ordinal+1;
   IF jsonb_typeof(v_part) IS DISTINCT FROM 'object' THEN
     RAISE EXCEPTION 'Each Work part must be a typed original Subject.' USING ERRCODE='22023';
   END IF;
   v_subject_domain:=nullif(btrim(v_part->>'subjectDomain'),'');
   v_subject_kind:=nullif(btrim(v_part->>'subjectKind'),'');
   v_title:=nullif(btrim(v_part->>'title'),'');
   v_instructions:=nullif(btrim(v_part->>'instructions'),'');
   v_result_contract:=coalesce(nullif(btrim(v_part->>'resultContractKey'),''),
     v_parent.result_contract_key);
   -- Preserving existing manager acceptance is the default. Changing it
   -- for one independently actionable part requires the governor's explicit
   -- physical worker-attestation decision, not an inferred old task setting.
   IF v_result_contract IS DISTINCT FROM v_parent.result_contract_key THEN
     IF v_parent.result_contract_key<>'ordinary_company_work_manager_acceptance_v1'
       OR v_result_contract<>'ordinary_company_work_worker_attestation_v1'
       OR coalesce(v_part->>'confirmWorkerAttestationAuthority','')<>'true'
       OR NOT EXISTS(
          SELECT 1 FROM atlas.work_result_contract_policies p
          WHERE p.contract_key=v_result_contract AND p.active
            AND p.source_domain='organization'
            AND p.acceptance_mode='worker_attestation'
       ) THEN
       RAISE EXCEPTION 'Original Work result authority change requires explicit authorized worker-attestation selection.'
         USING ERRCODE='23514';
     END IF;
   END IF;
   IF v_title IS NULL OR length(v_title)>300 OR
      length(coalesce(v_instructions,''))>3000 OR
      nullif(v_part->>'subjectId','') IS NULL THEN
     RAISE EXCEPTION 'Each part needs a meaningful bounded title and subject.' USING ERRCODE='22023';
   END IF;
   BEGIN v_subject_id:=(v_part->>'subjectId')::uuid;
   EXCEPTION WHEN others THEN
     RAISE EXCEPTION 'Invalid original Subject identifier.' USING ERRCODE='22023';
   END;
   IF v_subject_domain='spatial' AND v_subject_kind='growing_object' THEN
     IF NOT EXISTS(
       SELECT 1 FROM atlas.growing_objects obj
       JOIN atlas.farms f ON f.id=obj.farm_id
       JOIN atlas.farm_crop_ledger_custody_v1 cu ON cu.farm_id=f.id
         AND cu.ledger_id=p_ledger_id AND cu.custody_state='active'
         AND cu.ended_at IS NULL
       JOIN atlas.ledger_organization_participations lp
         ON lp.organization_id=f.organization_id AND lp.ledger_id=cu.ledger_id
         AND lp.status='active' AND lp.ended_at IS NULL
         AND lp.participation_kind IN ('governing','operating')
       JOIN ledger.ledgers nl ON nl.id=cu.ledger_id
         AND nl.ledger_state='active' AND nl.retired_at IS NULL
       WHERE obj.id=v_subject_id AND obj.object_type='bed'
         AND f.organization_id=p_organization_id
         AND f.organization_unit_id=v_parent.organization_unit_id
     ) THEN
       RAISE EXCEPTION 'Original Subject lacks exact Work/Ledger custody.'
         USING ERRCODE='42501';
     END IF;
   ELSIF v_subject_domain='temporal' AND v_subject_kind='occurrence' THEN
     IF NOT EXISTS(
       SELECT 1 FROM atlas.work_item_context_links c
       WHERE c.work_item_id=v_parent.id AND c.organization_id=p_organization_id
         AND c.subject_domain='temporal' AND c.subject_kind='occurrence'
         AND c.subject_id=v_subject_id
     ) THEN
       RAISE EXCEPTION 'Event part must retain its existing original Event link.'
         USING ERRCODE='42501';
     END IF;
   ELSE
     RAISE EXCEPTION 'Unverified Subject adapter; split is not authorized.'
       USING ERRCODE='42501';
   END IF;
   IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_parts) q
     WHERE q.value<>v_part
       AND q.value->>'subjectDomain'=v_subject_domain
       AND q.value->>'subjectKind'=v_subject_kind
       AND q.value->>'subjectId'=v_subject_id::text) THEN
     RAISE EXCEPTION 'Each part must have a distinct original Subject.'
       USING ERRCODE='23505';
   END IF;
 END LOOP;
 INSERT INTO atlas.work_decomposition_groups(
   parent_work_item_id,authorized_ledger_id,action_id,
   source_fingerprint,decision_reason,decided_by_person_id)
 VALUES (v_parent.id,p_ledger_id,p_action_id,v_fingerprint,
   btrim(p_decision_reason),v_owner) RETURNING * INTO v_group;
 v_ordinal:=0;
 FOR v_part IN SELECT value FROM jsonb_array_elements(p_parts) LOOP
   v_ordinal:=v_ordinal+1;
   v_subject_domain:=btrim(v_part->>'subjectDomain');
   v_subject_kind:=btrim(v_part->>'subjectKind');
   v_subject_id:=(v_part->>'subjectId')::uuid;
   v_title:=btrim(v_part->>'title');
   v_instructions:=nullif(btrim(v_part->>'instructions'),'');
   v_result_contract:=coalesce(nullif(btrim(v_part->>'resultContractKey'),''),
     v_parent.result_contract_key);
   INSERT INTO atlas.work_items(
      organization_id,organization_unit_id,title,instructions,work_state,source_object_type,
      source_object_id,result_contract_key,created_by_user_id,stable_key,metadata)
   VALUES (
      p_organization_id,v_parent.organization_unit_id,v_title,v_instructions,'open','work_decomposition',
      v_parent.id,v_result_contract,auth.uid(),
      'decomposition:'||v_parent.id::text||':'||v_ordinal::text,
      jsonb_build_object(
        'canonicalWorkDecompositionGroupId',v_group.id,
        'originalParentWorkItemId',v_parent.id,
        'originalParentSourceType',v_parent.source_object_type,
        'originalParentSourceId',v_parent.source_object_id,
        'partOrdinal',v_ordinal,'notAnAssignment',true,
        'originalResultContractRetained',v_result_contract IS NOT DISTINCT FROM v_parent.result_contract_key,
        'resultAuthoritySelectedByGovernor',v_result_contract,
        'workerAttestationExplicit',v_result_contract='ordinary_company_work_worker_attestation_v1'
          AND v_result_contract IS DISTINCT FROM v_parent.result_contract_key
      )
   ) RETURNING id,stable_key INTO v_child,v_child_stable_key;
   INSERT INTO atlas.work_decomposition_members(
     group_id,child_work_item_id,part_ordinal,subject_domain,subject_kind,subject_id)
   VALUES (v_group.id,v_child,v_ordinal,v_subject_domain,v_subject_kind,v_subject_id);
   -- Establish the child's exact Ledger relevance before its Subject link.
   INSERT INTO atlas.company_work_native_ledger_relevance(
     organization_id,work_item_id,ledger_id,evidence_kind,
     attestation_source_ref,attestation_reason,established_by_person_id)
   VALUES (p_organization_id,v_child,p_ledger_id,'owner_attested',
      'original-canonical-work:'||v_parent.id::text,
      btrim(p_decision_reason),v_owner);
   -- Spatial context carries the actual source keys of the signed decision.
   -- The independent context trigger verifies the group/member, current
   -- governor and exact Ledger scope, not a client-supplied association.
   v_subject_stable_key:=NULL;
   IF v_subject_domain='spatial' AND v_subject_kind='growing_object' THEN
     SELECT g.stable_key INTO v_subject_stable_key
     FROM atlas.growing_objects g WHERE g.id=v_subject_id;
   END IF;
   INSERT INTO atlas.work_item_context_links(
     organization_id,work_item_id,subject_domain,subject_kind,subject_id,
     relation_kind,provenance,metadata)
   VALUES (p_organization_id,v_child,v_subject_domain,v_subject_kind,v_subject_id,
     'acts_on',jsonb_build_object('source','original_work_decomposition',
       'parentWorkItemId',v_parent.id,'decisionId',v_group.id) ||
       CASE WHEN v_subject_domain='spatial' AND v_subject_kind='growing_object'
       THEN jsonb_build_object(
         'humanConfirmed',true,'nativeLedgerId',p_ledger_id,
         'decisionKind','signed_original_work_decomposition_subject_v1',
         'reviewedByPrincipalId',atlas.current_principal_id_v1(),
         'reviewedObjectKey',v_subject_stable_key,
         'reviewedWorkStableKey',v_child_stable_key)
       ELSE '{}'::jsonb END,
     CASE WHEN v_subject_domain='spatial' AND v_subject_kind='growing_object'
       THEN jsonb_build_object('confersAccess',false,'createsWork',false)
       ELSE '{}'::jsonb END);
   v_children:=v_children||jsonb_build_array(jsonb_build_object(
      'workItemId',v_child,'resultContractKey',v_result_contract,
      'subjectDomain',v_subject_domain,
      'subjectKind',v_subject_kind,'subjectId',v_subject_id));
 END LOOP;
 -- Stop the old combined Work from remaining an executable duplicate.
 -- Withdraw, do not rewrite or delete original plans, allocation or history.
 UPDATE atlas.work_execution_plans SET plan_state='withdrawn',
   plan_reason='Original Work decomposed into distinct current subjects.'
 WHERE work_item_id=v_parent.id AND plan_state IN ('active','needs_replan');
 UPDATE atlas.work_allocations SET state='released',
   released_at=now(),release_reason='Original Work decomposed; owner must establish distinct current responsibility.'
 WHERE work_item_id=v_parent.id AND state='active';
 UPDATE atlas.work_items SET work_state='superseded',
   metadata=metadata||jsonb_build_object('decomposedIntoWorkGroupId',v_group.id)
 WHERE id=v_parent.id AND work_state='open';
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count<>1 THEN RAISE EXCEPTION 'Original Work was not retired atomically.' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','original_canonical_work_decomposition_v1',
   'parentWorkItemId',v_parent.id,'decompositionId',v_group.id,'children',v_children,
   'idempotent',false,'parentHistoryPreserved',true,'childrenUnassigned',true,
   'originalResultContractKey',v_parent.result_contract_key);
END;
$function$;

CREATE OR REPLACE FUNCTION atlas.guard_work_growing_object_context_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $body$
DECLARE
  v_ledger uuid;
BEGIN
  IF NEW.subject_domain<>'spatial'
     OR NEW.subject_kind<>'growing_object'
  THEN
    RETURN NEW;
  END IF;

  -- An established work link does not automatically authorize reading it.
  -- This source-owned path requires a current exact-Ledger governor and
  -- separately verified real Work/farm/physical source at every creation.
  IF auth.uid() IS NULL
     OR atlas.current_principal_id_v1() IS NULL
     OR coalesce(NEW.provenance->>'humanConfirmed','false')<>'true'
     OR coalesce(NEW.provenance->>'reviewedObjectKey','')=''
     OR coalesce(NEW.provenance->>'reviewedWorkStableKey','')=''
     OR coalesce(NEW.metadata->>'confersAccess','false')='true'
     OR coalesce(NEW.metadata->>'createsWork','false')='true'
  THEN
    RAISE EXCEPTION 'governed work-context establishment required'
      USING ERRCODE='42501';
  END IF;

  BEGIN
    v_ledger := (NEW.provenance->>'nativeLedgerId')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'invalid native Ledger proof'
      USING ERRCODE='42501';
  END;
  IF v_ledger IS NULL
     OR NOT atlas.principal_has_ledger_authority_v1(
       atlas.current_principal_id_v1(), v_ledger
     )
  THEN
    RAISE EXCEPTION 'exact Ledger governor required'
      USING ERRCODE='42501';
  END IF;

  -- Only the source-owned original decomposition transaction can establish
  -- its exact child's Subject before allocation. This is not a general
  -- governor override of legacy or other Work source checks.
  IF NEW.provenance->>'source'='original_work_decomposition' THEN
    IF TG_OP<>'INSERT'
       OR NEW.relation_kind<>'acts_on'
       OR NEW.provenance->>'decisionKind' IS DISTINCT FROM
          'signed_original_work_decomposition_subject_v1'
       OR NEW.provenance->>'reviewedByPrincipalId' IS DISTINCT FROM
          atlas.current_principal_id_v1()::text
       OR NEW.metadata->>'confersAccess' IS DISTINCT FROM 'false'
       OR NEW.metadata->>'createsWork' IS DISTINCT FROM 'false'
    THEN
      RAISE EXCEPTION 'exact original decomposition Subject evidence required'
        USING ERRCODE='42501';
    END IF;

    -- Use the existing signed owner membrane (not a claim in provenance).
    -- The source group/member must already exist within this transaction.
    IF NOT EXISTS (
      SELECT 1
      FROM atlas.work_items w
      JOIN atlas.work_decomposition_members m ON m.child_work_item_id=w.id
      JOIN atlas.work_decomposition_groups d ON d.id=m.group_id
        AND d.parent_work_item_id=w.source_object_id
        AND d.authorized_ledger_id=v_ledger
      JOIN atlas.work_items parent ON parent.id=d.parent_work_item_id
        AND parent.organization_id=w.organization_id
        AND parent.organization_unit_id=w.organization_unit_id
        AND parent.work_state='open'
      JOIN atlas.growing_objects g ON g.id=m.subject_id
      JOIN atlas.farms f ON f.id=g.farm_id
        AND f.organization_id=w.organization_id
        AND f.organization_unit_id=w.organization_unit_id
      JOIN atlas.farm_crop_ledger_custody_v1 custody ON custody.farm_id=f.id
        AND custody.ledger_id=v_ledger AND custody.custody_state='active'
        AND custody.ended_at IS NULL
      JOIN atlas.ledger_organization_participations lop
        ON lop.organization_id=w.organization_id AND lop.ledger_id=v_ledger
        AND lop.status='active' AND lop.ended_at IS NULL
        AND lop.participation_kind IN ('governing','operating')
      JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
        AND nl.ledger_state='active' AND nl.retired_at IS NULL
      WHERE w.id=NEW.work_item_id AND w.organization_id=NEW.organization_id
        AND w.source_object_type='work_decomposition' AND w.work_state='open'
        AND g.object_type='bed'
        AND m.subject_domain=NEW.subject_domain
        AND m.subject_kind=NEW.subject_kind AND m.subject_id=NEW.subject_id
        AND d.id::text=NEW.provenance->>'decisionId'
        AND parent.id::text=NEW.provenance->>'parentWorkItemId'
        AND g.stable_key=NEW.provenance->>'reviewedObjectKey'
        AND w.stable_key=NEW.provenance->>'reviewedWorkStableKey'
        AND d.decided_by_person_id=atlas.company_work_native_ledger_owner_self_v1(
          w.organization_id,v_ledger)
        AND atlas.work_prerequisite_ledger_scope_v1(
          w.organization_id,v_ledger,parent.id)
        AND atlas.work_prerequisite_ledger_scope_v1(
          w.organization_id,v_ledger,w.id)
        AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_relevance r
          WHERE r.work_item_id=w.id AND r.organization_id=w.organization_id
            AND r.ledger_id=v_ledger AND r.attribution_state='active'
            AND r.evidence_kind='owner_attested'
            AND r.established_by_person_id=d.decided_by_person_id
            AND r.attestation_source_ref='original-canonical-work:'||parent.id::text
            AND r.attestation_reason=d.decision_reason
        )
    ) THEN
      RAISE EXCEPTION 'native original Work Subject and exact Ledger custody unproven'
        USING ERRCODE='42501';
    END IF;
    -- Context is neither allocation nor disclosure. The original child may
    -- still be unassigned. No change to the historical path below.
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM atlas.work_items w
    JOIN atlas.tasks t
      ON t.id=w.source_object_id
     AND w.source_object_type IN ('legacy_task','legacy_task_slice')
    JOIN atlas.growing_objects g
      ON g.id=NEW.subject_id
    JOIN atlas.farms f
      ON f.id=g.farm_id AND f.id=t.farm_id
    JOIN atlas.farm_crop_ledger_custody_v1 custody
      ON custody.farm_id=f.id
     AND custody.ledger_id=v_ledger
     AND custody.custody_state='active'
     AND custody.ended_at IS NULL
    JOIN atlas.ledger_organization_participations lop
      ON lop.organization_id=w.organization_id
     AND lop.organization_id=f.organization_id
     AND lop.ledger_id=v_ledger
     AND lop.status='active' AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
    JOIN ledger.ledgers nl
      ON nl.id=lop.ledger_id
     AND nl.ledger_state='active' AND nl.retired_at IS NULL
    WHERE w.id=NEW.work_item_id
      AND w.organization_id=NEW.organization_id
      AND f.organization_unit_id=w.organization_unit_id
      AND t.zone_id=g.zone_id
      AND g.object_type='bed'
      AND w.work_state IN ('open','in_progress')
      AND g.stable_key=NEW.provenance->>'reviewedObjectKey'
      AND w.stable_key=NEW.provenance->>'reviewedWorkStableKey'
      AND t.id::text=NEW.provenance->>'originalTaskId'
      AND EXISTS (
        SELECT 1 FROM atlas.work_allocations a
        WHERE a.work_item_id=w.id AND a.state='active'
      )
      AND (
        w.source_object_type<>'legacy_task_slice'
        OR EXISTS (
          SELECT 1
          FROM atlas.company_work_legacy_slice_contract_provenance_v1 src
          WHERE src.work_item_id=w.id AND src.source_task_id=t.id
        )
      )
  ) THEN
    RAISE EXCEPTION 'physical Work source and exact Ledger custody unproven'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$body$;

COMMIT;
