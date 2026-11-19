BEGIN;
-- Held native participant reader; existing v1 remains unchanged until paired app release.
CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v2(p_limit integer DEFAULT 50, p_after_allocation_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_self uuid := atlas.current_person_id_v1();
  v_items jsonb := '[]'::jsonb;
  v_more boolean := false;
  v_next uuid := NULL;
BEGIN
  IF auth.uid() IS NULL OR v_self IS NULL THEN
    RAISE EXCEPTION 'Signed-in canonical Person required' USING errcode='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Limit must be between 1 and 100' USING errcode='22023';
  END IF;

  WITH eligible AS MATERIALIZED (
    SELECT
      a.id allocation_id,a.allocation_role,w.id work_id,w.organization_id,
      (a.establishment_basis->>'nativeLedgerId')::uuid ledger_id,
      w.title,w.instructions,w.result_contract_key,
      latest_result.result_kind AS latest_result_kind,
      a.establishment_basis_kind,a.allocated_at,
      plan.id plan_id,plan.plan_state,
      plan.planned_service_date,plan.exposure_service_date,
      CASE WHEN plan.plan_state='active'
        AND plan.first_planned_service_date IS NOT NULL
        AND plan.first_planned_service_date IS DISTINCT FROM plan.planned_service_date
        AND last_plan_event.event_kind='rescheduled'
        AND last_plan_event.to_planned_service_date=plan.planned_service_date
        THEN plan.first_planned_service_date ELSE NULL
      END verified_moved_from_date,
      coalesce(plan_counts.current_plan_count,0) current_plan_count,
      coalesce(relevance.has_relevance,false) has_relevance
    FROM atlas.work_allocations a
    JOIN atlas.work_items w ON w.id=a.work_item_id
      AND w.organization_id=a.organization_id
    LEFT JOIN atlas.work_allocations primary_carrier ON a.allocation_role='participant'
      AND primary_carrier.id::text=a.establishment_basis->>'primaryAllocationId'
      AND primary_carrier.work_item_id=w.id AND primary_carrier.organization_id=w.organization_id
      AND primary_carrier.allocation_role='responsible' AND primary_carrier.state='active'
      AND primary_carrier.assignee_membership_id IS NULL
      AND primary_carrier.assignee_canonical_person_id IS NOT NULL
      AND primary_carrier.establishment_basis->>'nativeLedgerId'=a.establishment_basis->>'nativeLedgerId'
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,p.exposure_service_date,
        p.first_planned_service_date
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.responsible_allocation_id=CASE WHEN a.allocation_role='participant'
          THEN primary_carrier.id ELSE a.id END
        AND p.plan_state IN ('active','needs_replan')
      ORDER BY CASE WHEN p.plan_state='active' THEN 0 ELSE 1 END,
        p.updated_at DESC,p.id DESC LIMIT 1
    ) plan ON true
    -- Only the assigned person's latest result classification, never its private note.
    LEFT JOIN LATERAL (
      SELECT r.result_kind
      FROM atlas.work_execution_results r
      WHERE a.allocation_role='responsible' AND r.work_item_id=w.id AND r.responsible_allocation_id=a.id
      ORDER BY r.reported_at DESC,r.id DESC LIMIT 1
    ) latest_result ON true
    -- The last plan event, not a changed creation date or rollover count,
    -- proves a deliberate reschedule. No plan event => no migration claim.
    LEFT JOIN LATERAL (
      SELECT e.event_kind,e.to_planned_service_date
      FROM atlas.work_execution_plan_events e
      WHERE e.organization_id=w.organization_id
        AND e.work_item_id=w.id AND e.plan_id=plan.id
      ORDER BY e.created_at DESC,e.id DESC LIMIT 1
    ) last_plan_event ON true
    LEFT JOIN LATERAL (
      SELECT count(*)::integer current_plan_count
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.plan_state IN ('active','needs_replan')
    ) plan_counts ON true
    LEFT JOIN LATERAL (
      SELECT EXISTS (
        SELECT 1 FROM atlas.company_work_native_ledger_relevance x
        WHERE x.work_item_id=w.id AND x.organization_id=w.organization_id
          AND x.ledger_id=(a.establishment_basis->>'nativeLedgerId')::uuid
          AND x.attribution_state='active'
          AND (
            x.evidence_kind IN ('owner_attested','participant_attested')
            OR (x.evidence_kind='source_verified' AND EXISTS (
              SELECT 1
              FROM atlas.company_work_native_ledger_exact_source_v1(
                x.work_item_id,x.ledger_id
              ) verified
              WHERE verified.source_schema=x.source_schema
                AND verified.source_table=x.source_table
                AND verified.source_id=x.source_id
            ))
          )
      ) has_relevance
    ) relevance ON true
    WHERE a.state='active'
      AND a.assignee_canonical_person_id=v_self
      AND a.assignee_membership_id IS NULL
      AND ((a.allocation_role='responsible' AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
      )) OR (a.allocation_role='participant'
        AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
        AND a.assigned_by_membership_id IS NULL
        AND primary_carrier.id IS NOT NULL
        AND primary_carrier.assignee_canonical_person_id<>v_self
        AND relevance.has_relevance
        AND atlas.person_has_native_ledger_connection_v1(w.organization_id,
          (a.establishment_basis->>'nativeLedgerId')::uuid,primary_carrier.assignee_canonical_person_id)
        AND NOT EXISTS(SELECT 1 FROM atlas.work_item_context_links c
          WHERE c.organization_id=w.organization_id AND c.work_item_id=w.id
            AND NOT (
              (c.subject_domain='spatial' AND c.subject_kind='growing_object')
              OR (c.subject_domain='temporal' AND c.subject_kind='occurrence'
                AND atlas.has_current_subject_disclosure_v1((a.establishment_basis->>'nativeLedgerId')::uuid,
                    v_self,'event','occurrence',c.subject_id,'identity'))
            ))
        AND NOT EXISTS(SELECT 1 FROM atlas.work_allocations other
          WHERE other.work_item_id=w.id AND other.state='active'
            AND other.assignee_canonical_person_id=v_self AND other.id<>a.id)
      ))
      AND w.work_state='open'
      -- Preserve November 12 ACCESS-02 for EVERY allocation role before projection.
      AND coalesce(relevance.has_relevance,false)
      AND atlas.person_original_work_identity_disclosed_self_v1(w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,w.id,v_self)
      AND (p_after_allocation_id IS NULL OR a.id>p_after_allocation_id)
      AND atlas.person_has_native_ledger_connection_v1(
        w.organization_id,(a.establishment_basis->>'nativeLedgerId')::uuid,v_self
      )
    ORDER BY a.id
    LIMIT p_limit+1
  ), numbered AS (
    SELECT e.*,row_number() OVER (ORDER BY e.allocation_id) rn
    FROM eligible e
  )
  SELECT
    coalesce(jsonb_agg(
      jsonb_build_object(
        'workItemId',r.work_id,'allocationId',r.allocation_id,
        'allocationRole',r.allocation_role,
        'organizationId',r.organization_id,'ledgerId',r.ledger_id,
        'title',r.title,'instructions',r.instructions,
        'resultContractKey',r.result_contract_key,
        'latestResultKind',r.latest_result_kind,
        'establishmentBasisKind',r.establishment_basis_kind,
        'allocatedAt',r.allocated_at,'planId',r.plan_id,
        'planState',r.plan_state,'workOn',r.planned_service_date,
        'exposureDate',r.exposure_service_date,
        'verifiedMovedFromDate',r.verified_moved_from_date,
        'workRelevanceVerified',r.has_relevance,
        'canPlace',false,
        'scheduleState',CASE
          WHEN r.current_plan_count>1 THEN 'conflict'
          WHEN r.plan_id IS NULL AND r.current_plan_count>0 THEN 'unverified_plan'
          WHEN r.plan_id IS NULL THEN 'unscheduled'
          WHEN r.plan_state='needs_replan' THEN 'needs_replan'
          WHEN r.plan_state='active' AND
            r.planned_service_date IS NOT NULL AND
            r.exposure_service_date IS NOT NULL THEN 'scheduled'
          ELSE 'unverified_plan'
        END
      ) ORDER BY r.allocation_id
    ) FILTER(WHERE r.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,
    (array_agg(r.allocation_id ORDER BY r.rn) FILTER (WHERE r.rn=p_limit))[1]
  INTO v_items,v_more,v_next
  FROM numbered r;

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_my_work_v2',
    'personId',v_self,'items',v_items,
    'hasMore',v_more,'nextAllocationId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'sourceScope','active_responsible_or_participating_person_native_ledger_work',
    'scheduleReadAcrossAllDates',true,
    'optionalRequestsExcluded',true,'noPersonalTaskCreated',true
  );
END
$function$;
REVOKE ALL ON FUNCTION atlas.connected_person_my_work_self_api_v2(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
-- Held in-place correction of existing owner plan writer, not a competing plan.
DO $guard$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_catalog.pg_proc WHERE oid='atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)'::regprocedure)
 IS DISTINCT FROM '2e3a52a41b954b1a841cafc84105ad4b' THEN
   RAISE EXCEPTION 'Current native plan writer differs from reviewed October 30 source; reconcile before install';
 END IF;
END
$guard$;
CREATE OR REPLACE FUNCTION atlas.owner_set_connected_person_work_day_self_api_v1(p_work_item_id uuid, p_ledger_id uuid, p_service_date date, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_work atlas.work_items%rowtype;
  v_allocation atlas.work_allocations%rowtype;
  v_plan atlas.work_execution_plans%rowtype;
  v_old atlas.work_execution_plans%rowtype;
  v_owner uuid;
  v_owner_member uuid;
  v_native_intake boolean:=false;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  v_window jsonb;
  v_event text;
begin
  if auth.uid() is null or p_work_item_id is null or p_ledger_id is null
    or v_reason is null or length(v_reason) not between 12 and 1200 then
    raise exception 'Exact owner Work, Ledger and meaningful planning reason required.'
      using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.responsibility:'||p_work_item_id::text,0));
  perform pg_advisory_xact_lock(hashtextextended(
    'atlas.company_work.plan:'||p_work_item_id::text,0));
  select * into v_work from atlas.work_items
    where id=p_work_item_id and work_state='open' for update;
  if v_work.id is null then raise exception 'Open Work required for date changes.'
    using errcode='23514'; end if;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    v_work.organization_id,p_ledger_id);
  -- Reuse the released exact accepted-intake governing authority. Do not
  -- manufacture a membership merely to place the original on a civil day.
  if v_work.source_object_type='ledger_work_intake' then
    v_owner:=atlas.native_intake_responsibility_owner_context_v1(v_work.organization_id,p_ledger_id,v_work.id);
    v_native_intake:=true;
    v_owner_member:=null;
  else
    v_owner_member:=atlas.current_effective_organization_membership_v1(
      v_work.organization_id);
    if not exists (
      select 1 from atlas.organization_memberships m
      where m.id=v_owner_member and m.organization_id=v_work.organization_id
        and m.person_id=v_owner and m.role='owner' and m.active
    ) then raise exception 'Current authenticated owner membership required.'
      using errcode='42501'; end if;
  end if;
  if not exists (
    select 1 from atlas.company_work_native_ledger_relevance rel
    where rel.organization_id=v_work.organization_id
      and rel.work_item_id=v_work.id
      and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
      and (rel.evidence_kind in ('owner_attested','participant_attested') or
        (rel.evidence_kind='source_verified' and exists (
          select 1 from atlas.company_work_native_ledger_exact_source_v1(
            v_work.id,p_ledger_id) proof
          where proof.source_schema=rel.source_schema
            and proof.source_table=rel.source_table
            and proof.source_id=rel.source_id
        )))
  ) then raise exception 'Exact Ledger relevance required.' using errcode='42501'; end if;
  select * into v_allocation from atlas.work_allocations a
    where a.work_item_id=v_work.id and a.organization_id=v_work.organization_id
      and a.allocation_role='responsible' and a.state='active'
      and a.assignee_membership_id is null
      and a.assignee_canonical_person_id is not null
      and a.establishment_basis_kind in (
        'delegated_under_standing_scope','person_connection_receiver_uptake','original_subject_direct_assignment_v1','ledger_connection_direct_assignment')
      and a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    limit 1;
  if v_allocation.id is null or not atlas.person_has_native_ledger_connection_v1(
    v_work.organization_id,p_ledger_id,v_allocation.assignee_canonical_person_id) then
    raise exception 'Active connected Person responsibility required.'
      using errcode='23514';
  end if;
  select * into v_old from atlas.work_execution_plans
    where work_item_id=v_work.id and plan_state in ('active','needs_replan')
    for update;
  if v_old.id is not null and
    v_old.responsible_allocation_id<>v_allocation.id then
    raise exception 'Current plan belongs to different responsibility.'
      using errcode='23514';
  end if;

  if p_service_date is null then
    if v_old.id is null then
      return jsonb_build_object('ok',true,
        'contractVersion','native_person_work_plan_v1',
        'state','already_unplanned','workItemId',v_work.id,
        'ledgerId',p_ledger_id,'responsiblePersonId',
        v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
    end if;
    update atlas.work_execution_plans
      set plan_state='withdrawn',plan_reason=v_reason,
      metadata=metadata||jsonb_build_object(
        'sourceChange','native_person_owner_unplan_v1','actorPersonId',v_owner,
        'withdrawalReason',v_reason)
    where id=v_old.id and plan_state in ('active','needs_replan');
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (v_work.organization_id,v_work.id,v_old.id,'withdrawn',
      v_old.planned_service_date,v_old.exposure_service_date,
      v_owner_member,v_reason,
      jsonb_build_object('source','native_person_owner_unplan_v1','actorPersonId',v_owner));
    return jsonb_build_object('ok',true,
      'contractVersion','native_person_work_plan_v1',
      'state','unplanned','workItemId',v_work.id,'ledgerId',p_ledger_id,
      'planId',v_old.id,'responsiblePersonId',
      v_allocation.assignee_canonical_person_id,'newWorkCreated',false);
  end if;
  v_window:=atlas.company_work_execution_plan_window_check_v1(
    v_work.id,p_service_date);
  if not coalesce((v_window->>'allowed')::boolean,false) then
    raise exception 'Selected date conflicts with source-owned Work window (%).',
      v_window->>'state' using errcode='23514';
  end if;
  if v_old.id is null then
    insert into atlas.work_execution_plans(
      organization_id,work_item_id,responsible_allocation_id,
      assignee_membership_id,planned_by_membership_id,
      plan_state,first_planned_service_date,planned_service_date,
      exposure_service_date,plan_reason,metadata)
    values (v_work.organization_id,v_work.id,v_allocation.id,null,
      v_owner_member,'active',p_service_date,p_service_date,
      p_service_date,v_reason,
      jsonb_build_object('source','native_person_owner_plan_v1','actorPersonId',v_owner))
    returning * into v_plan;
    v_event:='planned';
  else
    update atlas.work_execution_plans
      set planned_service_date=p_service_date,exposure_service_date=p_service_date,
        plan_state='active',plan_reason=v_reason,
        planned_by_membership_id=v_owner_member,
        metadata=metadata||jsonb_build_object(
          'sourceChange','native_person_owner_plan_v1','actorPersonId',v_owner),
        rollover_count=0
      where id=v_old.id returning * into v_plan;
    v_event:=case when v_old.planned_service_date is distinct from p_service_date
      then 'rescheduled' else 'planned' end;
  end if;
  insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
  values (v_work.organization_id,v_work.id,v_plan.id,v_event,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    v_owner_member,v_reason,
    jsonb_build_object('source','native_person_owner_plan_v1','actorPersonId',v_owner));
  return jsonb_build_object('ok',true,
    'contractVersion','native_person_work_plan_v1',
    'state','planned','workItemId',v_work.id,
    'ledgerId',p_ledger_id,'planId',v_plan.id,
    'plannedServiceDate',v_plan.planned_service_date,
    'responsiblePersonId',v_allocation.assignee_canonical_person_id,
    'newWorkCreated',false,'workerReadProven',false);
end
$function$;

-- Release-candidate REST wrappers. Exact source admitted ONLY in disposable clone
-- until explicit migration authorization. Internal functions remain private.
CREATE FUNCTION public.connected_person_my_work_self_api_v2(p_limit integer DEFAULT 50,p_after_allocation_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.connected_person_my_work_self_api_v2($1,$2) $api$;
REVOKE ALL ON FUNCTION public.connected_person_my_work_self_api_v2(integer,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.connected_person_my_work_self_api_v2(integer,uuid) TO authenticated;
CREATE FUNCTION public.owner_native_work_participation_roster_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.owner_native_work_participation_roster_self_api_v1($1,$2,$3) $api$;
REVOKE ALL ON FUNCTION public.owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid) TO authenticated;
CREATE FUNCTION public.owner_change_native_work_participation_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_target_person_id uuid,p_expected_primary_allocation_id uuid,p_action text,p_source_action_id uuid,p_expected_participant_allocation_id uuid DEFAULT NULL)
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.owner_change_native_work_participation_self_api_v1($1,$2,$3,$4,$5,$6,$7,$8) $api$;
REVOKE ALL ON FUNCTION public.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid) TO authenticated;
CREATE FUNCTION public.native_original_work_self_participation_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.native_original_work_self_participation_self_api_v1($1,$2,$3) $api$;
REVOKE ALL ON FUNCTION public.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid) TO authenticated;
CREATE FUNCTION public.join_native_original_work_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_source_action_id uuid)
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.join_native_original_work_self_api_v1($1,$2,$3,$4) $api$;
REVOKE ALL ON FUNCTION public.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid) TO authenticated;
CREATE FUNCTION public.leave_native_original_work_self_api_v1(p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_participant_allocation_id uuid)
 RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
 AS $api$ SELECT atlas.leave_native_original_work_self_api_v1($1,$2,$3,$4) $api$;
REVOKE ALL ON FUNCTION public.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid) TO authenticated;
COMMIT;
