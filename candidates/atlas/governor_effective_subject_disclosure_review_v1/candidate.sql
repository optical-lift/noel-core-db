BEGIN;
-- Governor-only disclosure observation. Original source grants remain authority.
-- Never infer the target actor's successful signed call from a review projection.
CREATE OR REPLACE FUNCTION atlas.owner_effective_subject_disclosure_review_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid,
 p_limit integer DEFAULT 50, p_after_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
 v_owner uuid; v_primary uuid;
 v_target_governs boolean:=false;
 v_farms jsonb:='[]'::jsonb;
 v_work jsonb:='[]'::jsonb;
 v_more boolean:=false;
 v_next uuid;
BEGIN
 IF p_target_person_id IS NULL OR p_organization_id IS NULL OR p_ledger_id IS NULL
    OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
   RAISE EXCEPTION 'Exact Ledger, Person and bounded page required.' USING ERRCODE='22023';
 END IF;
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT EXISTS (
   SELECT 1 FROM ledger.seats s
   JOIN reality.entities e ON e.id=s.person_entity_id
    AND e.entity_kind='person' AND e.identity_state='canonical'
   WHERE s.ledger_id=p_ledger_id AND s.person_entity_id=p_target_person_id
    AND s.seat_state='active' AND s.ended_at IS NULL
 ) THEN
   RAISE EXCEPTION 'Connected Person unavailable on governed Ledger.' USING ERRCODE='42501';
 END IF;
 SELECT lop.ledger_id INTO v_primary FROM atlas.ledger_organization_participations lop
 WHERE lop.organization_id=p_organization_id AND lop.status='active' AND lop.ended_at IS NULL
   AND lop.is_compatibility_primary AND lop.participation_kind='governing' LIMIT 1;
 -- The target's own independent authority must still be signed-tested.
 SELECT EXISTS(
   SELECT 1 FROM atlas.principals p
   JOIN atlas.principal_ledger_authorities a ON a.principal_id=p.id
    AND a.ledger_id=p_ledger_id AND a.status='active'
    AND a.authority_kind='root_governing' AND a.ended_at IS NULL
   JOIN atlas.principal_ledger_authorities g ON g.principal_id=p.id
    AND g.ledger_id=v_primary AND g.status='active'
    AND g.authority_kind='root_governing' AND g.ended_at IS NULL
   WHERE p.person_id=p_target_person_id AND p.status='active'
 ) INTO v_target_governs;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'farmId',q.farm_id,
    'legacyFarmMembershipPresent',q.legacy_count>0,
    'legacyRoles',q.legacy_roles,
    'oldMembershipConfersCurrentDisclosure',false,
    'wideReaderRule','governing_ledger_authority_only',
    'governorSourceEstimate',v_target_governs,
    'directSignedCallStillRequired',true
 ) ORDER BY q.farm_id),'[]'::jsonb) INTO v_farms
 FROM (
   SELECT f.id farm_id,count(fm.id) legacy_count,
     coalesce(jsonb_agg(DISTINCT fm.role) FILTER(WHERE fm.id IS NOT NULL),'[]'::jsonb) legacy_roles
   FROM atlas.farms f
   LEFT JOIN atlas.farm_memberships fm ON fm.farm_id=f.id AND fm.active
     AND EXISTS (
       SELECT 1 FROM reality.auth_person_bindings b
       WHERE b.auth_user_id=fm.user_id AND b.person_entity_id=p_target_person_id
          AND b.binding_state='active' AND b.retired_at IS NULL
     )
   WHERE f.organization_id=p_organization_id
   GROUP BY f.id
 ) q;
 WITH selected AS (
    SELECT w.id,w.title,w.work_state,a.id allocation_id
    FROM atlas.work_items w
    JOIN atlas.work_allocations a ON a.work_item_id=w.id
      AND a.organization_id=w.organization_id
      AND a.assignee_canonical_person_id=p_target_person_id
      AND a.state='active' AND a.allocation_role='responsible'
    JOIN atlas.company_work_native_ledger_relevance rel
      ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
      AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
    WHERE w.organization_id=p_organization_id AND w.work_state='open'
      AND (p_after_work_item_id IS NULL OR w.id>p_after_work_item_id)
    ORDER BY w.id
    LIMIT p_limit+1
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
     'workItemId',b.id,'title',b.title,'workState',b.work_state,
     'allocationId',b.allocation_id,
     'linkedSubjectDisclosure',b.linked_subject_disclosure
   ) ORDER BY b.id) FILTER(WHERE b.rn<=p_limit),'[]'::jsonb),
   count(*)>p_limit,
   (array_agg(b.id ORDER BY b.rn) FILTER(WHERE b.rn=p_limit))[1]
 INTO v_work,v_more,v_next
 FROM (
 SELECT selected.*,row_number() OVER(ORDER BY id) rn,
 (SELECT jsonb_build_object(
   'items',coalesce(jsonb_agg(jsonb_build_object(
     'subjectId',s.subject_id,'subjectLabel',s.label,
     'subjectDomain','spatial','subjectKind','growing_object',
     'identityDecision',coalesce((SELECT e.decision_kind FROM atlas.subject_disclosure_decision_events_v1 e WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id AND e.target_person_id=p_target_person_id AND e.subject_domain='spatial' AND e.subject_kind='growing_object' AND e.subject_id=s.subject_id AND e.disclosure_class='identity' ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1),'not_decided'),
     'conditionDecision',coalesce((SELECT e.decision_kind FROM atlas.subject_disclosure_decision_events_v1 e WHERE e.organization_id=p_organization_id AND e.ledger_id=p_ledger_id AND e.target_person_id=p_target_person_id AND e.subject_domain='spatial' AND e.subject_kind='growing_object' AND e.subject_id=s.subject_id AND e.disclosure_class='condition' ORDER BY e.recorded_at DESC,e.id DESC LIMIT 1),'not_decided'),
     'identityDecisionCurrentlyGrants',atlas.has_current_subject_disclosure_v1(p_ledger_id,p_target_person_id,'spatial','growing_object',s.subject_id,'identity'),
     'conditionDecisionCurrentlyGrants',atlas.has_current_subject_disclosure_v1(p_ledger_id,p_target_person_id,'spatial','growing_object',s.subject_id,'condition')
   ) ORDER BY s.subject_id) FILTER(WHERE s.rn<=20),'[]'::jsonb),
   'hasMore',count(*)>20,'independentlySignedTargetProof',false)
  FROM (SELECT q.*,row_number() OVER(ORDER BY q.subject_id) rn
    FROM (SELECT DISTINCT ON(l.subject_id) l.subject_id,o.label
      FROM atlas.work_item_context_links l
      JOIN atlas.growing_objects o ON o.id=l.subject_id
      JOIN atlas.farms f ON f.id=o.farm_id AND f.organization_id=p_organization_id
      WHERE l.organization_id=p_organization_id AND l.work_item_id=selected.id
        AND l.subject_domain='spatial' AND l.subject_kind='growing_object'
      ORDER BY l.subject_id LIMIT 21) q
   ) s
 ) AS linked_subject_disclosure
 FROM selected
 ) b;
 RETURN jsonb_build_object(
   'ok',true,'contractVersion','governor_effective_subject_disclosure_review_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'reviewedPersonId',p_target_person_id,'governorPersonId',v_owner,
   'governorOnly',true,'isSignedTargetAccessProof',false,
   'targetActiveNativeLedgerConnectionConfirmed',true,
   'legacyFarmSources',v_farms,
   'broadLegacyFarmReaderPaths',jsonb_build_array(
      'zone_registry_source_v1','object_crop_bed_map_v1','farm_care_zone_v1',
      'farm_care_object_v1','farm_care_summary_v1','farm_snapshot_for_member_v1',
      'bed_components_state_v1',
      'farm_continuity_audit_v1',
      'farm_continuity_audit_v2',
      'farm_continuity_audit_v3',
      'grow_room_state_v1',
      'mowing_rhythm_dashboard_v1',
      'real_operation_explanation_v1',
      'tending_board_v1',
      'walkway_cards_v1',
      'weed_card_task_focus_v1',
      'weeding_cycle_v1',
      'weeding_rhythm_pilot_v1',
      'maintenance_directive_context_v1',
      'manual_task_context_v1',
      'resolve_effective_rhythm_rule_v1',
      'task_schedule_v1',
      'tending_bed_v1',
      'weed_selected_crop_turnover_focus_v1',
      'worker_day_operational_task_cards_v1',
      'worker_hand_context_v1',
      'object_workbench_v1','farm_continuity_audit_v6',
      'farm_continuity_audit_v7','farm_continuity_audit_v8',
      'crop_cycle_profile_source_state_v1','crop_cycle_stage_continuity_state_v1',
      'crop_cycle_biological_progression_state_v1','crop_cycle_postproduction_state_v1',
      'crop_cycle_lawful_dwell_state_v1','farm_goal_list_v1',
      'flower_sale_buyer_options_v1','home_task_cards_v1',
      'task_plant_contents_v1',
      'farm_day_task_cards_v1','home_task_cards_v2','seed_inventory_dashboard_v1','task_cards_v1','tending_task_context_v1','tending_task_context_v2','worker_day_state_transition_cards_v1','worker_future_day_projection_source_v1'),
   'broadReadersRequireCurrentGoverningAuthority',true,
   'signedAlternativeReaderCoverageComplete',false,
   'canonicalWork',v_work,'hasMore',v_more,
   'nextAfterWorkItemId',CASE WHEN v_more THEN v_next ELSE NULL END,
   'directSignedOwnerWorkerOutsiderAndAnonymousTestsRequired',true
 );
END;
$function$;
REVOKE ALL ON FUNCTION atlas.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid,
 p_limit integer DEFAULT 50, p_after_work_item_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT atlas.owner_effective_subject_disclosure_review_self_api_v1(
  p_organization_id,p_ledger_id,p_target_person_id,p_limit,p_after_work_item_id);
$function$;
REVOKE ALL ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_effective_subject_disclosure_review_self_api_v1(
 uuid,uuid,uuid,integer,uuid) TO authenticated;
COMMIT;
