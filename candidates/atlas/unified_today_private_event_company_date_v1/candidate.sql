BEGIN;
-- Held P0 source candidate, based on live original functions Oct 27, 2026.
-- The exact current PostgreSQL functions are preserved except explicit
-- identity disclosure and Company schedule source enforcement.

ALTER TABLE atlas.subject_disclosure_decision_events_v1
 DROP CONSTRAINT subject_disclosure_supported_subject_v1;
ALTER TABLE atlas.subject_disclosure_decision_events_v1
 ADD CONSTRAINT subject_disclosure_supported_subject_v1 CHECK (
   (subject_domain='spatial' AND subject_kind='growing_object')
   OR (subject_domain='event' AND subject_kind='occurrence'
       AND disclosure_class='identity')
 );

-- Reuse the same governor-only, append-only, withdrawable disclosure
-- decision engine for one exact Event and Person.
CREATE OR REPLACE FUNCTION atlas.governor_set_subject_disclosure_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_target_person_id uuid, p_subject_domain text, p_subject_kind text, p_subject_id uuid, p_disclosure_class text, p_decision_kind text, p_source_action_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_owner uuid;v_existing atlas.subject_disclosure_decision_events_v1%rowtype;
 v_created atlas.subject_disclosure_decision_events_v1%rowtype;
BEGIN
 IF p_target_person_id IS NULL OR p_subject_id IS NULL OR p_source_action_id IS NULL
   OR NOT ((
     p_subject_domain='spatial' AND p_subject_kind='growing_object'
     AND p_disclosure_class IN ('identity','condition')
   ) OR (
     p_subject_domain='event' AND p_subject_kind='occurrence'
     AND p_disclosure_class='identity'
   ))
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
 IF p_subject_domain='spatial' THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.growing_objects o
     JOIN atlas.farms f ON f.id=o.farm_id
     WHERE o.id=p_subject_id AND f.organization_id=p_organization_id
   ) THEN
     RAISE EXCEPTION 'Original Subject unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
 ELSE
   -- Bind the exact Event to both the governed Ledger and its one
   -- organization. An ambiguous or inactive binding is not shareable.
   IF NOT EXISTS(
     SELECT 1
     FROM ledger.occurrence_calendar_bindings cb
     JOIN local_intel.occurrences o ON o.id=cb.occurrence_id
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=o.id AND ob.organization_id=p_organization_id
       AND ob.binding_state='active'
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id
       AND lop.organization_id=p_organization_id
       AND lop.status='active' AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   ) OR (
     SELECT count(DISTINCT lop.organization_id)
     FROM ledger.occurrence_calendar_bindings cb
     JOIN atlas.ledger_organization_participations lop
       ON lop.ledger_id=cb.ledger_id AND lop.status='active'
       AND lop.ended_at IS NULL
       AND lop.participation_kind IN ('governing','operating')
     JOIN atlas.organization_occurrence_bindings ob
       ON ob.occurrence_id=cb.occurrence_id
       AND ob.organization_id=lop.organization_id
       AND ob.binding_state='active'
     WHERE cb.ledger_id=p_ledger_id AND cb.occurrence_id=p_subject_id
       AND cb.binding_state='active'
   )<>1 THEN
     RAISE EXCEPTION 'Original Event unavailable on governed Ledger.'
       USING ERRCODE='42501';
   END IF;
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
$function$


-- No Ledger-seat-only Event names, ambiguous-org counts or suggestion titles.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_index_self_api_v1(p_ledger_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid;v_access jsonb;v_events jsonb;v_unresolved integer;
 v_principal uuid;v_is_root boolean:=false;
begin
  if auth.uid() is null or p_ledger_id is null then
    raise exception 'Authenticated exact Ledger required.' using errcode='42501';
  end if;
  v_access:=atlas.reality_access_self_api_v1();
  if v_access->>'state' is distinct from 'ready'
    or v_access->>'authenticated' is distinct from 'true' then
    raise exception 'Personal Atlas identity access required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  perform atlas.current_active_ledger_seat_v1(p_ledger_id);
  if v_actor is null or not exists (
    select 1 from atlas.ledger_organization_participations lop
    join atlas.ledgers al on al.id=lop.ledger_id and al.status='active'
    join ledger.ledgers l on l.id=al.id
      and l.ledger_state='active' and l.retired_at is null
    where lop.ledger_id=p_ledger_id and lop.status='active'
      and lop.ended_at is null and lop.participation_kind in ('governing','operating')
  ) then
    raise exception 'Current source-bound native Ledger participation required.'
      using errcode='42501';
  end if;

  -- The native Ledger seat is not permission to discover each Event.
  -- A root governor can inspect planning; everyone else needs explicit
  -- original Event identity disclosure on this very Ledger.
  v_principal:=atlas.current_principal_id_v1();
  v_is_root:=coalesce(
    exists(select 1 from atlas.principal_ledger_authorities a
      join atlas.principals p on p.id=a.principal_id
       and p.status='active' and p.person_id=v_actor
      where a.ledger_id=p_ledger_id and a.principal_id=v_principal
        and a.authority_kind='root_governing' and a.status='active')
    and atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id),false);

  -- A generic Ledger need not have the legacy Organization compatibility
  -- field. Resolve the exact Organization by canonical live participation
  -- and its own active Occurrence binding. Ambiguous multi-Organization
  -- cases are disclosed as unresolved rather than silently choosing one.
  with source_events as (
    select o.id,o.title,o.status,o.start_at,o.end_at,
      min(lop.organization_id::text)::uuid as organization_id,
      count(distinct lop.organization_id) as organization_count
    from ledger.occurrence_calendar_bindings cb
    join local_intel.occurrences o on o.id=cb.occurrence_id
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=cb.ledger_id and lop.status='active'
        and lop.ended_at is null
        and lop.participation_kind in ('governing','operating')
    join atlas.organization_occurrence_bindings ob
      on ob.occurrence_id=o.id and ob.organization_id=lop.organization_id
        and ob.binding_state='active'
    where cb.ledger_id=p_ledger_id and cb.binding_state='active'
    group by o.id,o.title,o.status,o.start_at,o.end_at
  )
  select case when v_is_root
    then count(*) filter (where organization_count<>1)::integer else 0 end
    into v_unresolved from source_events;

  with source_events as (
    select o.id,o.title,o.status,o.start_at,o.end_at,
      min(lop.organization_id::text)::uuid as organization_id,
      count(distinct lop.organization_id) as organization_count
    from ledger.occurrence_calendar_bindings cb
    join local_intel.occurrences o on o.id=cb.occurrence_id
    join atlas.ledger_organization_participations lop
      on lop.ledger_id=cb.ledger_id and lop.status='active'
        and lop.ended_at is null
        and lop.participation_kind in ('governing','operating')
    join atlas.organization_occurrence_bindings ob
      on ob.occurrence_id=o.id and ob.organization_id=lop.organization_id
        and ob.binding_state='active'
    where cb.ledger_id=p_ledger_id and cb.binding_state='active'
    group by o.id,o.title,o.status,o.start_at,o.end_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',q.id,'title',q.title,'status',q.status,
    'organizationId',q.organization_id,
    'startsAt',q.start_at,'endsAt',q.end_at
  ) order by q.start_at desc,q.id),'[]'::jsonb) into v_events
  from (
    select se.* from source_events se
    where se.organization_count=1
      and (v_is_root or atlas.has_current_subject_disclosure_v1(
        p_ledger_id,v_actor,'event','occurrence',se.id,'identity'))
    order by se.start_at desc,se.id limit 150
  ) q;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_shared_index_v1',
    'ledgerId',p_ledger_id,'unresolvedOrganizationBindings',coalesce(v_unresolved,0),
    'events',v_events,'truthBoundary',jsonb_build_object(
      'onlyBoundOccurrences',true,'organizationDerivedFromSource',true,
      'ambiguousOrganizationBindingsNotSelected',true,
      'noCustomerData',true,'noGeneralLedgerHistory',true,
      'notGrantingWorkExecution',true));
end
$function$


-- Do not let being a responsible connected Person confer execution-date edits.
CREATE OR REPLACE FUNCTION atlas.connected_person_place_work_self_api_v1(p_work_item_id uuid, p_service_date date, p_reason text DEFAULT 'Recipient selected the work day for their accepted Ledger responsibility.'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_person uuid;v_w atlas.work_items%rowtype;v_a atlas.work_allocations%rowtype;
 v_ledger uuid;v_old atlas.work_execution_plans%rowtype;
 v_plan atlas.work_execution_plans%rowtype;v_window jsonb;v_kind text;
 v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
 if auth.uid() is null or (atlas.reality_access_self_api_v1()->>'state') is distinct from 'ready'
 then raise exception 'Signed-in canonical Person required' using errcode='42501';end if;
 v_person:=atlas.current_person_id_v1();
 if p_work_item_id is null or v_reason is null or length(v_reason) not between 12 and 1200
 then raise exception 'Exact Work and meaningful placement reason required' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.responsibility:'||p_work_item_id::text,0));
 perform pg_advisory_xact_lock(hashtextextended(
   'atlas.company_work.plan:'||p_work_item_id::text,0));
 select * into v_w from atlas.work_items where id=p_work_item_id and work_state='open' for update;
 if v_w.id is null then raise exception 'Open Company Work required' using errcode='23514';end if;
 select * into v_a from atlas.work_allocations a
  where a.work_item_id=v_w.id and a.organization_id=v_w.organization_id
   and a.allocation_role='responsible' and a.state='active'
   and a.assignee_membership_id is null
   and a.assignee_canonical_person_id=v_person
   and a.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
  order by a.allocated_at desc,a.id desc limit 1;
 if v_a.id is null then raise exception 'Only the active responsible Person may place their accepted Work' using errcode='42501';end if;
 v_ledger:=(v_a.establishment_basis->>'nativeLedgerId')::uuid;
 if v_ledger is null
   or not atlas.person_has_native_ledger_connection_v1(v_w.organization_id,v_ledger,v_person)
   or not exists(select 1 from atlas.company_work_native_ledger_relevance r
     where r.organization_id=v_w.organization_id and r.work_item_id=v_w.id
      and r.ledger_id=v_ledger and r.attribution_state='active')
 then raise exception 'Exact current Ledger connection and Work relevance required' using errcode='42501';end if;

 if not atlas.person_original_work_identity_disclosed_self_v1(v_w.organization_id,v_ledger,v_w.id,v_person)
 then raise exception 'Undisclosed original Work Subject unavailable' using errcode='42501';end if;
 -- Responsibility is not scheduling authority. Company execution plans
 -- may be placed/withdrawn only by actual native Ledger governors through
 -- this legacy endpoint until a separately delegated scheduler exists.
 perform atlas.company_work_native_ledger_owner_self_v1(v_w.organization_id,v_ledger);
 select * into v_old from atlas.work_execution_plans
   where work_item_id=v_w.id and organization_id=v_w.organization_id
     and plan_state in ('active','needs_replan') for update;
 if v_old.id is not null and v_old.responsible_allocation_id<>v_a.id
 then raise exception 'Existing plan belongs to another responsibility' using errcode='23514';end if;
 if v_old.id is not null and v_old.plan_state='active'
  and v_old.planned_service_date is not distinct from p_service_date
  and v_old.exposure_service_date is not distinct from p_service_date then
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','already_placed','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',p_service_date,
    'newWorkCreated',false,'idempotent',true);
 end if;
 if p_service_date is null then
   if v_old.id is null then
    return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
     'state','already_unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
     'responsiblePersonId',v_person,'executionDate',null,'newWorkCreated',false);
   end if;
   update atlas.work_execution_plans set plan_state='withdrawn',plan_reason=v_reason,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1')
    where id=v_old.id;
   insert into atlas.work_execution_plan_events(
     organization_id,work_item_id,plan_id,event_kind,
     from_planned_service_date,from_exposure_service_date,actor_membership_id,reason,metadata)
   values(v_w.organization_id,v_w.id,v_old.id,'withdrawn',
     v_old.planned_service_date,v_old.exposure_service_date,null,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_unplan_v1'));
   return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
    'state','unplanned','workItemId',v_w.id,'ledgerId',v_ledger,
    'responsiblePersonId',v_person,'planId',v_old.id,'executionDate',null,'newWorkCreated',false);
 end if;
 v_window:=atlas.company_work_execution_plan_window_check_v1(v_w.id,p_service_date);
 if not coalesce((v_window->>'allowed')::boolean,false) then
  raise exception 'Requested work-on day conflicts with source Work window' using errcode='23514';end if;
 if v_old.id is null then
   insert into atlas.work_execution_plans(
    organization_id,work_item_id,responsible_allocation_id,assignee_membership_id,
    planned_by_membership_id,plan_state,first_planned_service_date,planned_service_date,
    exposure_service_date,plan_reason,metadata)
   values(v_w.organization_id,v_w.id,v_a.id,null,null,'active',
     p_service_date,p_service_date,p_service_date,v_reason,
     jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1',
      'personNative',true))
   returning * into v_plan;
   v_kind:='planned';
 else
   update atlas.work_execution_plans set
    planned_service_date=p_service_date,exposure_service_date=p_service_date,
    plan_state='active',plan_reason=v_reason,planned_by_membership_id=null,
    rollover_count=0,
    metadata=metadata||jsonb_build_object('actorPersonId',v_person,'sourceChange','person_self_place_v1')
    where id=v_old.id returning * into v_plan;
   v_kind:=case when v_old.planned_service_date is distinct from p_service_date
     then 'rescheduled' else 'planned' end;
 end if;
 insert into atlas.work_execution_plan_events(
    organization_id,work_item_id,plan_id,event_kind,
    from_planned_service_date,to_planned_service_date,
    from_exposure_service_date,to_exposure_service_date,
    actor_membership_id,reason,metadata)
 values(v_w.organization_id,v_w.id,v_plan.id,v_kind,
    v_old.planned_service_date,v_plan.planned_service_date,
    v_old.exposure_service_date,v_plan.exposure_service_date,
    null,v_reason,jsonb_build_object('actorPersonId',v_person,'source','person_self_place_v1'));
 return jsonb_build_object('ok',true,'contractVersion','connected_person_work_placement_v1',
   'state','placed','workItemId',v_w.id,'ledgerId',v_ledger,
   'responsiblePersonId',v_person,'planId',v_plan.id,'executionDate',p_service_date,
   'newWorkCreated',false,'workerReadProven',false);
end$function$


COMMIT;
