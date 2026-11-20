BEGIN;
-- The user chooses exact existing Subjects; no title-matching or farm-task import.
-- This generic Work-subject choice seam may gain further source adapters in
-- reviewed migrations. Current spatial choice is scoped to exact current
-- Work/Ledger/crop custody and existing physical beds; no old Task needed.
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
REVOKE ALL ON FUNCTION atlas.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,authenticated,anon;
CREATE OR REPLACE FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 80,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_original_subject_choices_for_work_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_limit,p_after_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.owner_original_subject_choices_for_work_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
COMMIT;
