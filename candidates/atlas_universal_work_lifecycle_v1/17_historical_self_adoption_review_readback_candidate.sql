-- HELD source-only readback; exact governor Ledger authority, no worker leak.
-- Readback is bounded; any omission is explicit. No raw table permission.
CREATE OR REPLACE FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $history$
DECLARE a uuid; v_rows jsonb:='[]'::jsonb; v_more boolean:=false;
BEGIN
 a:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF p_work_item_id IS NULL OR NOT EXISTS (
 SELECT 1 FROM atlas.work_items w
 JOIN atlas.company_work_native_ledger_relevance r ON r.work_item_id=w.id
 WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
   AND r.organization_id=p_organization_id AND r.ledger_id=p_ledger_id
   AND r.attribution_state='active') THEN
 RAISE EXCEPTION 'Exact authorized historical source required' USING ERRCODE='42501';
 END IF;
 WITH ordered AS (
 SELECT e.*,row_number() OVER (ORDER BY e.recorded_at,e.id) AS seq
 FROM atlas.historical_self_adoption_review_events_v1 e
 WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id
 AND e.work_item_id=p_work_item_id
 ORDER BY e.recorded_at,e.id LIMIT 51
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
 'id',id,'kind',event_kind,'historicalWorkId',work_item_id,
 'allocationId',allocation_id,'actorPersonId',actor_person_id,
 'linkedPersonId',linked_person_id,'parentId',parent_event_id,
 'evidenceId',evidence_event_id,'outcome',outcome,
 'evidenceText',evidence_text,'recordedAt',recorded_at)
 ORDER BY seq) FILTER(WHERE seq<=50),'[]'::jsonb),
 coalesce(bool_or(seq>50),false)
 INTO v_rows,v_more FROM ordered;
 RETURN jsonb_build_object('ok',true,'contractVersion','historical_self_adoption_history_v1',
 'sourceWorkItemId',p_work_item_id,'items',v_rows,'hasMore',v_more,
 'bounded',true,'authoritativeWorkStateChanged',false,'historicalOnly',true);
END; $history$;
REVOKE ALL ON FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION atlas.governor_historical_self_adoption_history_self_api_v1(uuid,uuid,uuid)
 TO authenticated;
