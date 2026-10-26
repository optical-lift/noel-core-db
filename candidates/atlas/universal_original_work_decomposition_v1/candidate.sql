BEGIN;
-- Reuse atlas.work_items, work_allocations, plans, results and original
-- Ledger relevance; this is decomposition/provenance, NOT a new task system.
ALTER TABLE atlas.work_item_context_links
 DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_subject_pair_v1 CHECK (
   (subject_domain='spatial' AND subject_kind IN ('zone','place','growing_object'))
   OR (subject_domain='identity' AND subject_kind IN ('identity_subject','external_relationship'))
   OR (subject_domain='temporal' AND subject_kind='occurrence')
 );

CREATE TABLE atlas.work_decomposition_groups (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 parent_work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 authorized_ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 action_id uuid NOT NULL,
 source_fingerprint text NOT NULL,
 decision_reason text NOT NULL CHECK(length(btrim(decision_reason)) BETWEEN 12 AND 1600),
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT work_decomposition_once_per_parent UNIQUE(parent_work_item_id),
 CONSTRAINT work_decomposition_unique_action UNIQUE(parent_work_item_id,action_id)
);
CREATE TABLE atlas.work_decomposition_members (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 group_id uuid NOT NULL REFERENCES atlas.work_decomposition_groups(id) ON DELETE RESTRICT,
 child_work_item_id uuid NOT NULL UNIQUE REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
 part_ordinal integer NOT NULL CHECK(part_ordinal BETWEEN 1 AND 12),
 subject_domain text NOT NULL,
 subject_kind text NOT NULL,
 subject_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT work_decomposition_member_unique_ordinal UNIQUE(group_id,part_ordinal),
 CONSTRAINT work_decomposition_member_distinct_subject UNIQUE(group_id,subject_domain,subject_kind,subject_id)
);
CREATE INDEX work_decomposition_subject_lookup_v1
 ON atlas.work_decomposition_members(subject_domain,subject_kind,subject_id);
ALTER TABLE atlas.work_decomposition_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE atlas.work_decomposition_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.work_decomposition_groups,atlas.work_decomposition_members
 FROM PUBLIC,anon,authenticated;

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
 v_title text;
 v_instructions text;
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
 IF NOT EXISTS (
   SELECT 1 FROM atlas.company_work_native_ledger_relevance rel
    WHERE rel.work_item_id=v_parent.id AND rel.organization_id=p_organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
 ) THEN
   RAISE EXCEPTION 'Work lacks established relevance to governed Ledger.' USING ERRCODE='42501';
 END IF;
 v_fingerprint:=md5(p_parts::text||'|'||btrim(p_decision_reason));
 SELECT * INTO v_group FROM atlas.work_decomposition_groups
  WHERE parent_work_item_id=v_parent.id;
 IF v_group.id IS NOT NULL THEN
   IF v_group.action_id IS DISTINCT FROM p_action_id OR
      v_group.source_fingerprint IS DISTINCT FROM v_fingerprint THEN
     RAISE EXCEPTION 'Work was already decomposed by a different decision.' USING ERRCODE='23505';
   END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'workItemId',m.child_work_item_id,'subjectDomain',m.subject_domain,
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
       WHERE obj.id=v_subject_id AND f.organization_id=p_organization_id
     ) THEN
       RAISE EXCEPTION 'Original Subject not admitted to governed Organization.'
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
   INSERT INTO atlas.work_items(
      organization_id,title,instructions,work_state,source_object_type,
      source_object_id,result_contract_key,created_by_user_id,stable_key,metadata)
   VALUES (
      p_organization_id,v_title,v_instructions,'open','work_decomposition',
      v_parent.id,v_parent.result_contract_key,auth.uid(),
      'decomposition:'||v_parent.id::text||':'||v_ordinal::text,
      jsonb_build_object(
        'canonicalWorkDecompositionGroupId',v_group.id,
        'originalParentWorkItemId',v_parent.id,
        'originalParentSourceType',v_parent.source_object_type,
        'originalParentSourceId',v_parent.source_object_id,
        'partOrdinal',v_ordinal,'notAnAssignment',true,
        'originalResultContractRetained',true
      )
   ) RETURNING id INTO v_child;
   INSERT INTO atlas.work_decomposition_members(
     group_id,child_work_item_id,part_ordinal,subject_domain,subject_kind,subject_id)
   VALUES (v_group.id,v_child,v_ordinal,v_subject_domain,v_subject_kind,v_subject_id);
   INSERT INTO atlas.work_item_context_links(
     organization_id,work_item_id,subject_domain,subject_kind,subject_id,
     relation_kind,provenance,metadata)
   VALUES (p_organization_id,v_child,v_subject_domain,v_subject_kind,v_subject_id,
     'acts_on',jsonb_build_object('source','original_work_decomposition',
     'parentWorkItemId',v_parent.id,'decisionId',v_group.id),'{}'::jsonb);
   INSERT INTO atlas.company_work_native_ledger_relevance(
     organization_id,work_item_id,ledger_id,evidence_kind,
     attestation_source_ref,attestation_reason,established_by_person_id)
   VALUES (p_organization_id,v_child,p_ledger_id,'owner_attested',
      'original-canonical-work:'||v_parent.id::text,
      btrim(p_decision_reason),v_owner);
   v_children:=v_children||jsonb_build_array(jsonb_build_object(
      'workItemId',v_child,'subjectDomain',v_subject_domain,
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
REVOKE ALL ON FUNCTION atlas.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_parent_work_item_id uuid,
 p_parts jsonb,p_action_id uuid,p_decision_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.split_original_canonical_work_owner_self_api_v1(
   p_organization_id,p_ledger_id,p_parent_work_item_id,
   p_parts,p_action_id,p_decision_reason);
$function$;
REVOKE ALL ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.split_original_canonical_work_owner_self_api_v1(
 uuid,uuid,uuid,jsonb,uuid,text) TO authenticated;
COMMIT;
