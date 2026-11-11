-- ACCESS-01: restrict unrelated Ledger Work search and personnel roster behind
-- the currently signed exact-Ledger root authority, independently of Event identity.
-- Candidate source only. NOT a migration and NOT permission to apply production DDL.
-- Canonical originals, Event identity disclosures, existing function signatures,
-- result shape, existing grants, and permission to read one's disclosed Event remain unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.event_existing_work_choices_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_query text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid;v_items jsonb;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
   p_organization_id,p_ledger_id,p_occurrence_id);
 -- Event identity disclosure does not authorize a whole-Ledger Work search
 -- or personnel roster. Admit only the current exact-Ledger root governor.
 PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Exact Ledger root required for cross-Work or personnel choices.' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'workItemId',x.id,'title',x.title,'workState',x.work_state)
   ORDER BY x.title,x.id),'[]'::jsonb) INTO v_items
 FROM (
   SELECT w.id,w.title,w.work_state
   FROM atlas.work_items w
   JOIN atlas.company_work_native_ledger_relevance r
    ON r.work_item_id=w.id AND r.organization_id=w.organization_id
      AND r.ledger_id=p_ledger_id AND r.attribution_state='active'
   WHERE w.organization_id=p_organization_id AND w.work_state='open'
     AND (nullif(btrim(coalesce(p_query,'')),'') IS NULL
       OR w.title ILIKE '%' || replace(replace(btrim(p_query),'%','\%'),'_','\_') || '%' ESCAPE '\')
     AND NOT EXISTS (SELECT 1 FROM atlas.work_item_context_links c
       WHERE c.work_item_id=w.id AND c.subject_domain='temporal'
       AND c.subject_kind='occurrence' AND c.subject_id=p_occurrence_id)
   ORDER BY w.title,w.id LIMIT 40
 ) x;
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
   'occurrenceId',p_occurrence_id,'choices',v_items,
   'sourceContract','existing_canonical_ledger_work');
END
$function$;

CREATE OR REPLACE FUNCTION atlas.ledger_event_attention_people_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid;v_people jsonb;
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 -- Event identity disclosure does not authorize a whole-Ledger Work search
 -- or personnel roster. Admit only the current exact-Ledger root governor.
 PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);
 IF NOT FOUND THEN
   RAISE EXCEPTION 'Exact Ledger root required for cross-Work or personnel choices.' USING ERRCODE='42501';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'personEntityId',x.id,'displayName',x.display_name)
   ORDER BY x.display_name,x.id),'[]'::jsonb) INTO v_people
 FROM (SELECT DISTINCT e.id,e.display_name
   FROM ledger.seats s JOIN reality.entities e ON e.id=s.person_entity_id
   WHERE s.ledger_id=p_ledger_id AND s.seat_state='active' AND s.ended_at IS NULL
     AND e.entity_kind='person' AND e.identity_state='canonical'
 ) x;
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
   'occurrenceId',p_occurrence_id,'people',v_people);
END
$function$;

COMMIT;
