-- SOURCE CANDIDATE ONLY: canonical Work -> physical growing-object link.
-- Does NOT confer access, authorise editing, read crop data, or create a task.
-- All subject values are data-driven; no Elm/Anna-specific keys in executable SQL.
BEGIN;

ALTER TABLE atlas.work_item_context_links
  DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
  ADD CONSTRAINT work_item_context_links_subject_pair_v1 CHECK (
    (subject_domain='spatial'
      AND subject_kind IN ('zone','place','growing_object'))
    OR (subject_domain='identity'
      AND subject_kind IN ('identity_subject','external_relationship'))
    OR (subject_domain='temporal' AND subject_kind='occurrence')
  );

CREATE FUNCTION atlas.guard_work_growing_object_context_v1()
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

CREATE TRIGGER work_growing_object_context_guard_v1
BEFORE INSERT OR UPDATE OF
  organization_id,work_item_id,subject_domain,subject_kind,subject_id,
  relation_kind,provenance,metadata
ON atlas.work_item_context_links
FOR EACH ROW EXECUTE FUNCTION atlas.guard_work_growing_object_context_v1();

CREATE FUNCTION atlas.establish_work_growing_object_context_self_api_v1(
  p_ledger_id uuid,
  p_work_item_id uuid,
  p_object_id uuid,
  p_review jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_obj atlas.growing_objects%ROWTYPE;
  v_source_task atlas.tasks%ROWTYPE;
  v_context_id uuid;
  v_created boolean := false;
BEGIN
  IF auth.uid() IS NULL
    OR atlas.current_principal_id_v1() IS NULL
    OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
         atlas.current_principal_id_v1(),p_ledger_id),false)
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;
  IF p_review IS NULL OR jsonb_typeof(p_review)<>'object'
    OR p_review->>'humanConfirmed'<>'true'
    OR p_review->>'reviewedWorkStableKey' IS NULL
    OR p_review->>'reviewedObjectKey' IS NULL
  THEN
    RETURN jsonb_build_object('ok',false,'code','review_required');
  END IF;
  SELECT * INTO v_work
    FROM atlas.work_items WHERE id=p_work_item_id;
  SELECT * INTO v_obj
    FROM atlas.growing_objects WHERE id=p_object_id;
  IF v_work.id IS NULL OR v_obj.id IS NULL
     OR v_work.source_object_type NOT IN ('legacy_task','legacy_task_slice')
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;
  SELECT * INTO v_source_task
    FROM atlas.tasks WHERE id=v_work.source_object_id;
  IF v_source_task.id IS NULL
     OR p_review->>'reviewedWorkStableKey' IS DISTINCT FROM
        v_work.stable_key
     OR p_review->>'reviewedObjectKey' IS DISTINCT FROM
        v_obj.stable_key
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  -- The trigger independently enforces actual source, farm, active Work,
  -- current governor, same-zone physical object and Ledger participation.
  -- Client-supplied review is only an explicit governor attestation; it is
  -- never a proof of source identity or a content-disclosure entitlement.
  INSERT INTO atlas.work_item_context_links(
    organization_id,work_item_id,subject_domain,subject_kind,subject_id,
    relation_kind,provenance,metadata
  ) VALUES (
    v_work.organization_id,v_work.id,'spatial','growing_object',v_obj.id,
    'acts_on',
    jsonb_build_object(
      'humanConfirmed',true,
      'nativeLedgerId',p_ledger_id,
      'originalTaskId',v_source_task.id,
      'reviewedObjectKey',v_obj.stable_key,
      'reviewedWorkStableKey',v_work.stable_key,
      'decisionKind','signed_governor_physical_source_review_v1',
      'reviewedByPrincipalId',atlas.current_principal_id_v1()
    ),
    jsonb_build_object(
      'contractVersion','work_growing_object_context_v1',
      'confersAccess',false,'createsWork',false
    )
  )
  ON CONFLICT ON CONSTRAINT work_item_context_links_unique_v1
  DO NOTHING
  RETURNING id INTO v_context_id;
  v_created := v_context_id IS NOT NULL;
  IF NOT v_created THEN
    SELECT id INTO v_context_id FROM atlas.work_item_context_links
    WHERE work_item_id=v_work.id
      AND subject_domain='spatial'
      AND subject_kind='growing_object'
      AND subject_id=v_obj.id
      AND relation_kind='acts_on';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','work_growing_object_context_v1',
    'contextId',v_context_id,'workItemId',v_work.id,
    'created',v_created,'confersAccess',false
  );
END;
$fn$;

REVOKE ALL ON FUNCTION
  atlas.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.guard_work_growing_object_context_v1()
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.establish_work_growing_object_context_self_api_v1(
  p_ledger_id uuid,p_work_item_id uuid,p_object_id uuid,p_review jsonb
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path='pg_catalog'
AS $wrapper$
  SELECT atlas.establish_work_growing_object_context_self_api_v1(
    p_ledger_id,p_work_item_id,p_object_id,p_review
  );
$wrapper$;
REVOKE ALL ON FUNCTION
  public.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
  public.establish_work_growing_object_context_self_api_v1(uuid,uuid,uuid,jsonb)
  TO authenticated;


-- Owner-only review of existing physical candidates; no candidate is a grant.
CREATE FUNCTION atlas.work_growing_object_context_review_self_api_v1(
  p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $review$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_legacy atlas.tasks%ROWTYPE;
  v_candidate_rows jsonb;
BEGIN
  IF auth.uid() IS NULL OR atlas.current_principal_id_v1() IS NULL
     OR NOT coalesce(atlas.principal_has_ledger_authority_v1(
           atlas.current_principal_id_v1(),p_ledger_id),false)
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;
  SELECT * INTO v_work FROM atlas.work_items
    WHERE id=p_work_item_id;
  IF v_work.id IS NULL
     OR v_work.source_object_type NOT IN ('legacy_task','legacy_task_slice')
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;
  SELECT * INTO v_legacy FROM atlas.tasks
    WHERE id=v_work.source_object_id;
  IF v_legacy.id IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM atlas.farms f
      JOIN atlas.ledger_organization_participations lop
        ON lop.organization_id=f.organization_id
       AND lop.ledger_id=p_ledger_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
      JOIN ledger.ledgers nl ON nl.id=lop.ledger_id
       AND nl.ledger_state='active' AND nl.retired_at IS NULL
      WHERE f.id=v_legacy.farm_id
        AND f.organization_id=v_work.organization_id
        AND f.organization_unit_id=v_work.organization_unit_id
    )
  THEN
    RETURN jsonb_build_object('ok',false,'code','not_found');
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'objectId',g.id,'stableKey',g.stable_key,'label',g.label,
    'existingLink',EXISTS (
      SELECT 1 FROM atlas.work_item_context_links l
      WHERE l.work_item_id=v_work.id AND l.subject_domain='spatial'
        AND l.subject_kind='growing_object' AND l.subject_id=g.id
        AND l.relation_kind='acts_on'
    )) ORDER BY g.stable_key),'[]'::jsonb)
  INTO v_candidate_rows
  FROM atlas.growing_objects g
  WHERE g.farm_id=v_legacy.farm_id
    AND g.zone_id=v_legacy.zone_id
    AND g.object_type='bed';

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','work_growing_object_context_review_v1',
    'workItemId',v_work.id,'workStableKey',v_work.stable_key,
    'originalTaskId',v_legacy.id,
    'candidates',v_candidate_rows,
    'confersAccess',false
  );
END;
$review$;

REVOKE ALL ON FUNCTION
  atlas.work_growing_object_context_review_self_api_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.work_growing_object_context_review_self_api_v1(
  p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='pg_catalog'
AS $read_wrapper$
  SELECT atlas.work_growing_object_context_review_self_api_v1(
    p_ledger_id,p_work_item_id
  );
$read_wrapper$;
REVOKE ALL ON FUNCTION
  public.work_growing_object_context_review_self_api_v1(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
  public.work_growing_object_context_review_self_api_v1(uuid,uuid)
  TO authenticated;

COMMIT;
