BEGIN;
-- A Person's exact Work responsibility and a native Ledger seat never grant
-- broad Subject discovery. Governor decisions are append-only and field-bounded.
CREATE TABLE atlas.subject_disclosure_decision_events_v1 (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
 ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
 target_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 subject_domain text NOT NULL,
 subject_kind text NOT NULL,
 subject_id uuid NOT NULL,
 disclosure_class text NOT NULL CHECK(disclosure_class IN ('identity','condition')),
 decision_kind text NOT NULL CHECK(decision_kind IN ('grant','withhold')),
 source_action_id uuid NOT NULL,
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 12 AND 1600),
 decided_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT subject_disclosure_action_identity_v1 UNIQUE(ledger_id,source_action_id),
 CONSTRAINT subject_disclosure_supported_subject_v1 CHECK(
   subject_domain='spatial' AND subject_kind='growing_object'
 )
);
CREATE OR REPLACE FUNCTION atlas.block_subject_disclosure_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 RAISE EXCEPTION 'Original Subject disclosure decisions are append-only.'
 USING ERRCODE='42501';
END;
$function$;
REVOKE ALL ON FUNCTION atlas.block_subject_disclosure_mutation_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER subject_disclosure_append_only_v1
 BEFORE UPDATE OR DELETE ON atlas.subject_disclosure_decision_events_v1
 FOR EACH ROW EXECUTE FUNCTION atlas.block_subject_disclosure_mutation_v1();

CREATE INDEX subject_disclosure_current_lookup_v1
 ON atlas.subject_disclosure_decision_events_v1(
 ledger_id,target_person_id,subject_domain,subject_kind,subject_id,
 disclosure_class,recorded_at DESC,id DESC);
ALTER TABLE atlas.subject_disclosure_decision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.subject_disclosure_decision_events_v1 FROM PUBLIC,anon,authenticated;

-- Deliberately not accessible from the browser or authenticated RPC directly.
-- Strict current decision, not 'an old grant somewhere in history'.
CREATE OR REPLACE FUNCTION atlas.has_current_subject_disclosure_v1(
 p_ledger_id uuid,p_person_id uuid,p_subject_domain text,p_subject_kind text,
 p_subject_id uuid,p_disclosure_class text
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT coalesce((
  SELECT e.decision_kind='grant'
  FROM atlas.subject_disclosure_decision_events_v1 e
  WHERE e.ledger_id=p_ledger_id AND e.target_person_id=p_person_id
   AND e.subject_domain=p_subject_domain AND e.subject_kind=p_subject_kind
   AND e.subject_id=p_subject_id AND e.disclosure_class=p_disclosure_class
  ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1
 ),false);
$function$;
REVOKE ALL ON FUNCTION atlas.has_current_subject_disclosure_v1(
 uuid,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid,
 p_disclosure_class text,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_existing atlas.subject_disclosure_decision_events_v1%rowtype;
 v_created atlas.subject_disclosure_decision_events_v1%rowtype;
BEGIN
 IF p_target_person_id IS NULL OR p_subject_id IS NULL OR p_source_action_id IS NULL
   OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object'
   OR p_disclosure_class NOT IN ('identity','condition')
   OR p_decision_kind NOT IN ('grant','withhold')
   OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 12 AND 1600 THEN
   RAISE EXCEPTION 'Exact bounded original Subject disclosure decision required.'
     USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,p_target_person_id) THEN
   RAISE EXCEPTION 'Connected Person or Ledger unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.growing_objects o
   JOIN atlas.farms f ON f.id=o.farm_id
   WHERE o.id=p_subject_id AND f.organization_id=p_organization_id
 ) THEN
   RAISE EXCEPTION 'Original Subject unavailable on governed Ledger.'
     USING ERRCODE='42501';
 END IF;
 -- Serialize all competing grants/withholds on this exact Person + Subject
 -- + field class, not just retries with the same idempotency key.
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_disclosure:'||p_ledger_id::text||':'||
  p_target_person_id::text||':'||p_subject_domain||':'||
  p_subject_kind||':'||p_subject_id::text||':'||p_disclosure_class,0));
 PERFORM pg_advisory_xact_lock(hashtextextended(
  'atlas.subject_action:'||p_ledger_id::text||':'||p_source_action_id::text,0));
 SELECT * INTO v_existing
 FROM atlas.subject_disclosure_decision_events_v1
 WHERE ledger_id=p_ledger_id AND source_action_id=p_source_action_id;
 IF v_existing.id IS NOT NULL THEN
   IF v_existing.organization_id IS DISTINCT FROM p_organization_id
    OR v_existing.target_person_id IS DISTINCT FROM p_target_person_id
    OR v_existing.subject_domain IS DISTINCT FROM p_subject_domain
    OR v_existing.subject_kind IS DISTINCT FROM p_subject_kind
    OR v_existing.subject_id IS DISTINCT FROM p_subject_id
    OR v_existing.disclosure_class IS DISTINCT FROM p_disclosure_class
    OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
    OR v_existing.reason IS DISTINCT FROM btrim(p_reason) THEN
    RAISE EXCEPTION 'Decision action ID already used for different disclosure.'
      USING ERRCODE='23505';
   END IF;
   v_created:=v_existing;
 ELSE
   INSERT INTO atlas.subject_disclosure_decision_events_v1(
     organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
     subject_id,disclosure_class,decision_kind,source_action_id,reason,decided_by_person_id,recorded_at
   ) VALUES(
     p_organization_id,p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class,p_decision_kind,p_source_action_id,btrim(p_reason),v_owner,clock_timestamp()
   ) RETURNING * INTO v_created;
 END IF;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','bounded_original_subject_disclosure_v1',
   'decisionId',v_created.id,'sourceActionId',p_source_action_id,
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'targetPersonId',p_target_person_id,'subjectDomain',p_subject_domain,
   'subjectKind',p_subject_kind,'subjectId',p_subject_id,
   'disclosureClass',p_disclosure_class,'decisionKind',p_decision_kind,
   'currentlyGranted',atlas.has_current_subject_disclosure_v1(
     p_ledger_id,p_target_person_id,p_subject_domain,p_subject_kind,
     p_subject_id,p_disclosure_class),
   'historicalDecisionPreserved',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid,
 p_disclosure_class text,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.governor_set_subject_disclosure_self_api_v1(
 p_organization_id,p_ledger_id,p_target_person_id,
 p_subject_domain,p_subject_kind,p_subject_id,
 p_disclosure_class,p_decision_kind,p_source_action_id,p_reason);
$function$;
REVOKE ALL ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.governor_set_subject_disclosure_self_api_v1(
 uuid,uuid,uuid,text,text,uuid,text,text,uuid,text) TO authenticated;

-- Read ONE named original Subject via ONE actual admitted original Work.
-- A disclosed label/condition never implies authority over other children,
-- crop cycles, history, other Work, or full-farm aggregate views.
CREATE OR REPLACE FUNCTION atlas.connected_person_original_work_subject_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_owner boolean:=false;v_identity boolean:=false;
 v_condition boolean:=false;v_object atlas.growing_objects%rowtype;
 v_condition_state atlas.object_state%rowtype;
BEGIN
 IF auth.uid() IS NULL OR
   (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
   OR p_subject_domain<>'spatial' OR p_subject_kind<>'growing_object'
   OR p_work_item_id IS NULL OR p_subject_id IS NULL THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
   p_organization_id,p_ledger_id,v_person) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
   SELECT 1 FROM atlas.work_items w
   JOIN atlas.company_work_native_ledger_relevance rel
     ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
   JOIN atlas.work_item_context_links link
     ON link.work_item_id=w.id AND link.organization_id=w.organization_id
      AND link.subject_domain=p_subject_domain
      AND link.subject_kind=p_subject_kind AND link.subject_id=p_subject_id
   WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
 ) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 -- The relevant Work also must be the signed Person's own accepted responsibility
 -- unless they actually govern this native Ledger.
 BEGIN
   PERFORM atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
   v_owner:=true;
 EXCEPTION WHEN OTHERS THEN v_owner:=false;
 END;
 IF NOT v_owner AND NOT EXISTS(
    SELECT 1 FROM atlas.work_allocations a
    WHERE a.work_item_id=p_work_item_id
      AND a.organization_id=p_organization_id
      AND a.assignee_canonical_person_id=v_person
      AND a.allocation_role='responsible' AND a.state='active'
   ) THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_identity:=v_owner OR atlas.has_current_subject_disclosure_v1(
   p_ledger_id,v_person,p_subject_domain,p_subject_kind,p_subject_id,'identity');
 IF NOT v_identity THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 v_condition:=v_owner OR atlas.has_current_subject_disclosure_v1(
   p_ledger_id,v_person,p_subject_domain,p_subject_kind,p_subject_id,'condition');
 SELECT o.* INTO v_object FROM atlas.growing_objects o
 JOIN atlas.farms f ON f.id=o.farm_id
 WHERE o.id=p_subject_id AND f.organization_id=p_organization_id;
 IF v_object.id IS NULL THEN
   RAISE EXCEPTION 'Original Work Subject unavailable.' USING ERRCODE='42501';
 END IF;
 IF v_condition THEN
   SELECT * INTO v_condition_state FROM atlas.object_state
    WHERE object_id=v_object.id;
 END IF;
 RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_original_work_subject_v1',
    'workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'subjectDomain',p_subject_domain,'subjectKind',p_subject_kind,
    'subjectId',v_object.id,'subjectLabel',v_object.label,
    'subjectType',v_object.object_type,
    'conditionDisclosed',v_condition,
    'condition',CASE WHEN v_condition THEN jsonb_strip_nulls(jsonb_build_object(
       'lifeStatus',v_condition_state.life_status,
       'careState',v_condition_state.care_state,
       'careObservedAt',v_condition_state.care_observed_at,
       'careFreshness',v_condition_state.care_freshness
    )) ELSE NULL END,
    'cropPlacementDetailsDisclosed',false,
    'notesAndMetadataDisclosed',false,
    'fullFarmReaderAccessGranted',false
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.connected_person_original_work_subject_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_subject_domain text,p_subject_kind text,p_subject_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_original_work_subject_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,
 p_subject_domain,p_subject_kind,p_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_original_work_subject_self_api_v1(
 uuid,uuid,uuid,text,text,uuid) TO authenticated;
-- Enumerate only the signed Person's admitted original Subject links for one
-- exact authorized Work; never publish undisclosed subjects or their counts.
CREATE OR REPLACE FUNCTION atlas.connected_person_work_subject_links_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 30,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_owner boolean:=false;v_rows jsonb:='[]'::jsonb;
 v_more boolean:=false;v_next uuid;
BEGIN
 IF auth.uid() IS NULL OR
    (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR p_work_item_id IS NULL THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_person) THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    JOIN atlas.company_work_native_ledger_relevance r
     ON r.work_item_id=w.id AND r.organization_id=w.organization_id
       AND r.ledger_id=p_ledger_id AND r.attribution_state='active'
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
 ) THEN
  RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 BEGIN
   PERFORM atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
   v_owner:=true;
 EXCEPTION WHEN OTHERS THEN v_owner:=false;
 END;
 IF NOT v_owner AND NOT EXISTS(
    SELECT 1 FROM atlas.work_items w
    JOIN atlas.work_allocations a ON a.work_item_id=w.id
      AND a.organization_id=w.organization_id
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.work_state='open'
      AND a.assignee_canonical_person_id=v_person
      AND a.allocation_role='responsible' AND a.state='active'
 ) THEN
    RAISE EXCEPTION 'Original Work Subjects unavailable.' USING ERRCODE='42501';
 END IF;
 WITH allowed AS (
   SELECT DISTINCT ON(c.subject_id)
     c.subject_id,c.subject_domain,c.subject_kind,o.label
   FROM atlas.work_item_context_links c
   JOIN atlas.growing_objects o ON o.id=c.subject_id
   JOIN atlas.farms f ON f.id=o.farm_id AND f.organization_id=p_organization_id
   WHERE c.organization_id=p_organization_id
      AND c.work_item_id=p_work_item_id
      AND c.subject_domain='spatial' AND c.subject_kind='growing_object'
      AND (p_after_subject_id IS NULL OR c.subject_id>p_after_subject_id)
      AND (v_owner OR atlas.has_current_subject_disclosure_v1(
         p_ledger_id,v_person,c.subject_domain,c.subject_kind,c.subject_id,'identity'))
   ORDER BY c.subject_id
 ), page AS (
    SELECT *,row_number() OVER(ORDER BY subject_id) rn
    FROM allowed ORDER BY subject_id LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'subjectDomain',q.subject_domain,'subjectKind',q.subject_kind,
     'subjectId',q.subject_id,'subjectLabel',q.label
    ) ORDER BY q.subject_id) FILTER(WHERE q.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,(array_agg(q.subject_id ORDER BY q.rn) FILTER(WHERE q.rn=p_limit))[1]
 INTO v_rows,v_more,v_next FROM page q;
 RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_work_subject_links_v1',
    'workItemId',p_work_item_id,'ledgerId',p_ledger_id,
    'items',v_rows,'hasMore',v_more,
    'nextAfterSubjectId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'undisclosedSubjectsOmitted',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.connected_person_work_subject_links_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_limit integer DEFAULT 30,p_after_subject_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.connected_person_work_subject_links_self_api_v1(
 p_organization_id,p_ledger_id,p_work_item_id,p_limit,p_after_subject_id);
$function$;
REVOKE ALL ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.connected_person_work_subject_links_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;

COMMIT;
