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
$function$;


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
$function$;


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
end$function$;


-- Protect alternate source readers, including direct signed RPC calls.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_work_actor_self_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid; v_access jsonb;
begin
  if auth.uid() is null or p_organization_id is null
     or p_ledger_id is null or p_occurrence_id is null then
    raise exception 'Authenticated exact Ledger and Occurrence required.' using errcode='42501';
  end if;
  v_access:=atlas.reality_access_self_api_v1();
  if v_access->>'state' is distinct from 'ready'
     or v_access->>'authenticated' is distinct from 'true' then
    raise exception 'Current Personal Atlas access required.' using errcode='42501';
  end if;
  v_actor:=atlas.current_person_id_v1();
  if v_actor is null or not atlas.person_has_native_ledger_connection_v1(
    p_organization_id,p_ledger_id,v_actor
  ) then
    raise exception 'Current canonical Person Ledger connection required.' using errcode='42501';
  end if;
  if not exists (
    select 1 from ledger.occurrence_calendar_bindings cb
    join local_intel.occurrences o on o.id=cb.occurrence_id
    join atlas.organization_occurrence_bindings ob
      on ob.occurrence_id=o.id and ob.organization_id=p_organization_id
        and ob.binding_state='active'
    where cb.ledger_id=p_ledger_id and cb.occurrence_id=p_occurrence_id
      and cb.binding_state='active'
  ) then
    raise exception 'Exact Event is not an active Occurrence of this Ledger and Organization.'
      using errcode='42501';
  end if;
  -- Exact native connection does not authorize discovering private Event identity.
  if not (coalesce(
    exists(select 1 from atlas.principal_ledger_authorities authz
      join atlas.principals principal on principal.id=authz.principal_id
        and principal.status='active' and principal.person_id=v_actor
      where authz.ledger_id=p_ledger_id
        and authz.principal_id=atlas.current_principal_id_v1()
        and authz.authority_kind='root_governing' and authz.status='active')
    and atlas.principal_has_ledger_authority_v1(
      atlas.current_principal_id_v1(),p_ledger_id),false)
    or atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_actor,'event','occurrence',p_occurrence_id,'identity')) then
    raise exception 'Exact Event identity is not disclosed to this Person.' using errcode='42501';
  end if;
  return v_actor;
end
$function$;


CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_date_evidence_self_api_v1(p_ledger_id uuid, p_start_date date, p_end_date date, p_timezone_name text, p_limit integer DEFAULT 150)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_access jsonb;
  v_actor uuid;
  v_is_root boolean:=false;
  v_timezone text := nullif(btrim(coalesce(p_timezone_name,'')),'');
  v_limit integer := greatest(1,least(coalesce(p_limit,150),250));
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated exact Ledger required'
      USING ERRCODE='42501';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date
     OR p_end_date - p_start_date > 45 THEN
    RAISE EXCEPTION 'Bounded valid date interval required'
      USING ERRCODE='22023';
  END IF;
  IF v_timezone IS NULL OR NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=v_timezone
  ) THEN
    RAISE EXCEPTION 'Valid civil timezone required'
      USING ERRCODE='22023';
  END IF;

  -- Match the existing Ledger Event Index's authenticated human entry boundary.
  -- A Ledger connection is NOT generic Organization or private-custody authority.
  v_access := atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Personal Atlas identity access required'
      USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
  IF NOT EXISTS(
    SELECT 1
    FROM ledger.ledgers l
    JOIN atlas.ledgers al ON al.id=l.id AND al.status='active'
    JOIN atlas.ledger_organization_participations lop
      ON lop.ledger_id=l.id AND lop.status='active'
     AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
    WHERE l.id=p_ledger_id AND l.ledger_state='active'
      AND l.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Source-bound active Ledger participation required'
      USING ERRCODE='42501';
  END IF;

  v_actor:=atlas.current_person_id_v1();
  v_is_root:=coalesce(
    exists(select 1 from atlas.principal_ledger_authorities authz
      join atlas.principals principal on principal.id=authz.principal_id
        and principal.status='active' and principal.person_id=v_actor
      where authz.ledger_id=p_ledger_id
        and authz.principal_id=atlas.current_principal_id_v1()
        and authz.authority_kind='root_governing' and authz.status='active')
    and atlas.principal_has_ledger_authority_v1(
      atlas.current_principal_id_v1(),p_ledger_id),false);

  -- Ledger-bound canonical Occurrences are the ONLY admission authority here.
  -- Two linked assertions are two perspectives, never two Occurrence identities.
  WITH admitted AS (
    SELECT DISTINCT ON (o.id)
      o.id, o.title, o.status, o.start_at, o.end_at,
      o.last_verified_at, o.updated_at,
      cb.id AS calendar_binding_id
    FROM ledger.occurrence_calendar_bindings cb
    JOIN local_intel.occurrences o ON o.id=cb.occurrence_id
    WHERE cb.ledger_id=p_ledger_id AND cb.binding_state='active'
      AND (v_is_root OR atlas.has_current_subject_disclosure_v1(
        p_ledger_id,v_actor,'event','occurrence',o.id,'identity'))
      AND (
        (
          (o.start_at AT TIME ZONE v_timezone)::date <= p_end_date
          AND (coalesce(o.end_at,o.start_at) AT TIME ZONE v_timezone)::date >= p_start_date
        )
        OR EXISTS(
          SELECT 1
          FROM atlas.ledger_organization_participations lop
          JOIN atlas.organization_occurrence_bindings ob
            ON ob.organization_id=lop.organization_id
           AND ob.occurrence_id=o.id AND ob.binding_state='active'
          JOIN atlas.community_events ce
            ON ce.occurrence_binding_id=ob.id
           AND ce.visibility_scope='farm_shared'
          WHERE lop.ledger_id=p_ledger_id
            AND lop.status='active' AND lop.ended_at IS NULL
            AND lop.participation_kind IN ('governing','operating')
            AND ce.event_date BETWEEN p_start_date AND p_end_date
        )
      )
    ORDER BY o.id,cb.updated_at DESC,cb.id
  ), bounded AS (
    SELECT a.* FROM admitted a ORDER BY a.start_at,a.id LIMIT v_limit
  ), scoped AS (
    SELECT b.*, org.organization_id,org.organization_count
    FROM bounded b
    CROSS JOIN LATERAL (
      SELECT min(lop.organization_id::text)::uuid AS organization_id,
             count(DISTINCT lop.organization_id)::integer AS organization_count
      FROM atlas.ledger_organization_participations lop
      JOIN atlas.organization_occurrence_bindings ob
        ON ob.organization_id=lop.organization_id
       AND ob.occurrence_id=b.id AND ob.binding_state='active'
      WHERE lop.ledger_id=p_ledger_id AND lop.status='active'
        AND lop.ended_at IS NULL
        AND lop.participation_kind IN ('governing','operating')
    ) org
  ), projected AS (
    SELECT s.*,
      coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'sourceRef',jsonb_build_object(
              'authority','atlas','kind','community_event','id',ce.id),
            'bindingId',ob.id,
            'title',ce.title,'sourceStatus',ce.status,
            'eventDate',ce.event_date,
            'startLocalTime',ce.start_local_time,
            'endLocalTime',ce.end_local_time,
            'timezoneName',ce.timezone_name,
            'sourceUpdatedAt',ce.updated_at,
            'timezoneRecognized',EXISTS(
              SELECT 1 FROM pg_catalog.pg_timezone_names z
              WHERE z.name=ce.timezone_name),
            'differenceCandidates',jsonb_build_object(
              'title',ce.title IS DISTINCT FROM s.title,
              'sourceStatus',ce.status IS DISTINCT FROM s.status,
              'date',CASE WHEN EXISTS(
                SELECT 1 FROM pg_catalog.pg_timezone_names z
                WHERE z.name=ce.timezone_name)
                THEN ce.event_date IS DISTINCT FROM
                  (s.start_at AT TIME ZONE ce.timezone_name)::date
                ELSE NULL END,
              'startLocalTime',CASE WHEN EXISTS(
                SELECT 1 FROM pg_catalog.pg_timezone_names z
                WHERE z.name=ce.timezone_name)
                THEN ce.start_local_time IS DISTINCT FROM
                  (s.start_at AT TIME ZONE ce.timezone_name)::time
                ELSE NULL END,
              'endLocalTime',CASE WHEN s.end_at IS NULL THEN NULL
                WHEN EXISTS(
                  SELECT 1 FROM pg_catalog.pg_timezone_names z
                  WHERE z.name=ce.timezone_name)
                THEN ce.end_local_time IS DISTINCT FROM
                  (s.end_at AT TIME ZONE ce.timezone_name)::time
                ELSE NULL END
            ),
            'disposition','not_adjudicated'
          ) ORDER BY ce.id
        )
        FROM atlas.organization_occurrence_bindings ob
        JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
        WHERE ce.visibility_scope='farm_shared'
          AND s.organization_count=1
          AND ob.organization_id=s.organization_id
          AND ob.occurrence_id=s.id
          AND ob.binding_state='active'
      ),'[]'::jsonb) AS community_overlays
    FROM scoped s
  )
  SELECT (SELECT count(*)::integer FROM admitted),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'projectionKey','canonical_occurrence:'||pr.id::text,
        'sourceRef',jsonb_build_object(
          'authority','local_intel','kind','occurrence','id',pr.id),
        'ledgerCalendarBindingId',pr.calendar_binding_id,
        'canonicalAssertion',jsonb_build_object(
          'title',pr.title,'sourceStatus',pr.status,
          'startsAt',pr.start_at,'endsAt',pr.end_at,
          'civilDate',(pr.start_at AT TIME ZONE v_timezone)::date,
          'requestedTimezoneName',v_timezone,
          'sourceLastVerifiedAt',pr.last_verified_at,
          'sourceUpdatedAt',pr.updated_at
        ),
        'communityEventAssertions',pr.community_overlays,
        'organizationBindingAmbiguous',pr.organization_count>1,
        'organizationBindingMissing',pr.organization_count=0,
        'sourceFieldDifferencesNotAutoAdjudicated',true,
        'subjectEncounter',jsonb_build_object(
          'kind','canonical_occurrence','id',pr.id)
      ) ORDER BY pr.start_at,pr.id
    ),'[]'::jsonb)
  INTO v_total,v_items
  FROM projected pr;

  RETURN jsonb_build_object(
    'contractVersion','ledger_occurrence_date_evidence_v1',
    'scope',jsonb_build_object('kind','ledger','id',p_ledger_id),
    'window',jsonb_build_object(
      'startDate',p_start_date,'endDate',p_end_date,
      'timezoneName',v_timezone),
    'occurrences',v_items,
    'coverage',jsonb_build_object(
      'sourceFamiliesEvaluated',jsonb_build_array(
        'active_ledger_bound_canonical_occurrences',
        'linked_farm_shared_operational_event_assertions'),
      'returnedOccurrenceCount',jsonb_array_length(v_items),
      'eligibleOccurrenceCount',v_total,
      'truncated',v_total>v_limit,
      'wholeTemporalFieldComplete',false,
      'nonIntegratedSourceFamiliesNotDeniedOrEmpty',true,
      'occurrencesWithoutLedgerBindingNotEvaluated',true,
      'operationalSourceLocalDatesNotUniversalTimezoneCoverage',true,
      'restrictedOperationalViewsAreNotIncluded',true
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'oneCanonicalOccurrencePerIdentity',true,
      'differentAssertionsAreNotIndependentEvents',true,
      'differencesAreReviewCandidatesNotResolvedContradictions',true,
      'noneOfTheseRowsProvesMessageSentOrResourceBooked',true,
      'noSourceStateChanged',true
    )
  );
END
$function$;


CREATE OR REPLACE FUNCTION atlas.my_ledger_event_work_attention_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_person uuid;v_access jsonb;v_rows jsonb;
BEGIN
 v_access:=atlas.reality_access_self_api_v1();
 IF v_access->>'state' IS DISTINCT FROM 'ready' OR
    v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
   RAISE EXCEPTION 'An active personal Atlas session is required' USING ERRCODE='42501';END IF;
 v_person:=atlas.current_person_id_v1();
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'ledgerId',z.ledger_id,'occurrenceId',z.occurrence_id,
  'workItemId',z.work_item_id,'title',z.title,'workState',z.work_state,
  'eventState',z.event_state,'eventTitle',z.event_title,'startsAt',z.start_at)
  ORDER BY z.start_at,z.title,z.work_item_id),'[]'::jsonb) INTO v_rows
 FROM (
  SELECT a.ledger_id,a.occurrence_id,a.work_item_id,w.title,w.work_state,
    CASE WHEN last_action.action_kind='blocked' THEN 'blocked'
      ELSE w.work_state END AS event_state,
    o.title event_title,o.start_at
  FROM atlas.ledger_occurrence_work_attention_v1 a
  JOIN atlas.work_items w ON w.id=a.work_item_id AND w.organization_id=a.organization_id AND NOT EXISTS (SELECT 1 FROM atlas.work_item_context_links g0
   WHERE g0.organization_id=w.organization_id AND g0.work_item_id=w.id
    AND g0.subject_domain='spatial' AND g0.subject_kind='growing_object')
  JOIN local_intel.occurrences o ON o.id=a.occurrence_id
  JOIN ledger.occurrence_calendar_bindings cb
   ON cb.ledger_id=a.ledger_id AND cb.occurrence_id=a.occurrence_id
      AND cb.binding_state='active'
  LEFT JOIN LATERAL (
    SELECT e.action_kind FROM atlas.ledger_occurrence_work_actions_v1 e
    WHERE e.work_item_id=a.work_item_id
      AND e.action_kind IN ('blocked','reopened')
    ORDER BY e.action_sequence DESC LIMIT 1
  ) last_action ON true
  WHERE a.person_entity_id=v_person AND a.attention_state='active'
    AND w.work_state='open'
    AND EXISTS (SELECT 1 FROM atlas.ledger_organization_participations lop
      WHERE lop.ledger_id=a.ledger_id AND lop.organization_id=a.organization_id
        AND lop.status='active' AND lop.ended_at IS NULL)
    AND EXISTS (SELECT 1 FROM atlas.organization_occurrence_bindings ob
      WHERE ob.organization_id=a.organization_id AND ob.occurrence_id=a.occurrence_id
        AND ob.binding_state='active')
    AND atlas.person_has_native_ledger_connection_v1(
     a.organization_id,a.ledger_id,v_person)
    AND (coalesce(
    exists(select 1 from atlas.principal_ledger_authorities authz
      join atlas.principals principal on principal.id=authz.principal_id
        and principal.status='active' and principal.person_id=v_person
      where authz.ledger_id=a.ledger_id
        and authz.principal_id=atlas.current_principal_id_v1()
        and authz.authority_kind='root_governing' and authz.status='active')
    and atlas.principal_has_ledger_authority_v1(
      atlas.current_principal_id_v1(),a.ledger_id),false)
      OR atlas.has_current_subject_disclosure_v1(
        a.ledger_id,v_person,'event','occurrence',a.occurrence_id,'identity'))
    AND NOT EXISTS (SELECT 1 FROM atlas.ledger_occurrence_work_actions_v1 e
      WHERE e.ledger_id=a.ledger_id AND e.occurrence_id=a.occurrence_id
        AND e.work_item_id=a.work_item_id AND e.action_kind='removed')
  ORDER BY o.start_at,w.title,w.id LIMIT 150
 ) z;
 RETURN jsonb_build_object('ok',true,'contractVersion','my_ledger_event_work_attention_v1',
  'personEntityId',v_person,'items',v_rows,'sourceOwnedNotPersonalCopies',true);
END
$function$;


CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid, p_proposed_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_proposed_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_principal uuid;
  v_root boolean := false;
  v_canonical local_intel.occurrences%rowtype;
  v_overlay atlas.community_events%rowtype;
  v_community_count integer;
  v_zone_ok boolean;
  v_proposed boolean;
  v_claim_count integer;
  v_booking_count integer;
  v_other_ledger_count integer;
  v_summary jsonb := '{}'::jsonb;
  v_claims jsonb := '{}'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
BEGIN
  -- Native Person -> exact Ledger -> Organization -> Occurrence source-bound
  -- identity (this same guard underlies ordinary Event Work, NOT schedule writes).
  v_actor := atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  -- A bounded Event identity grant is not broad schedule/resource disclosure.
  PERFORM 1 FROM atlas.capability_root_authority_context_self_v1(p_ledger_id);

  IF (p_proposed_starts_at IS NULL) IS DISTINCT FROM
     (p_proposed_ends_at IS NULL) THEN
    RAISE EXCEPTION 'Proposed interval requires both endpoints.'
      USING ERRCODE='22023';
  END IF;
  v_proposed := p_proposed_starts_at IS NOT NULL;
  IF v_proposed AND (
      NOT isfinite(p_proposed_starts_at) OR
      NOT isfinite(p_proposed_ends_at) OR
      p_proposed_ends_at <= p_proposed_starts_at OR
      p_proposed_ends_at - p_proposed_starts_at > interval '7 days') THEN
    RAISE EXCEPTION 'Proposed absolute interval must be finite and ordered.'
      USING ERRCODE='22023';
  END IF;

  SELECT * INTO STRICT v_canonical
  FROM local_intel.occurrences o WHERE o.id=p_occurrence_id;

  -- Preserve the Event Index's no-silent-selection rule when the same
  -- canonical Occurrence is linked to multiple active Organizations within
  -- one Ledger. A requested Organization ID is not a tie-break authority.
  IF (
    SELECT count(DISTINCT lop.organization_id)
    FROM atlas.ledger_organization_participations lop
    JOIN atlas.organization_occurrence_bindings ob
      ON ob.organization_id=lop.organization_id
     AND ob.occurrence_id=p_occurrence_id
     AND ob.binding_state='active'
    WHERE lop.ledger_id=p_ledger_id
      AND lop.status='active' AND lop.ended_at IS NULL
      AND lop.participation_kind IN ('governing','operating')
  ) <> 1 THEN
    RAISE EXCEPTION 'Unresolved multi-Organization Occurrence; source adjudication required.'
      USING ERRCODE='23514';
  END IF;

  -- A one-to-many overlay is a genuine source ambiguity, never choose the
  -- newest or first row as the source of authority.
  SELECT count(*)::integer INTO v_community_count
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.occurrence_id=p_occurrence_id
    AND ob.organization_id=p_organization_id
    AND ob.binding_state='active'
    AND ce.visibility_scope='farm_shared';

  IF v_community_count<>1 THEN
    RAISE EXCEPTION 'Exactly one admitted shared operational assertion is required for this source adapter.'
      USING ERRCODE='23514';
  END IF;

  SELECT ce.* INTO STRICT v_overlay
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.occurrence_id=p_occurrence_id
    AND ob.organization_id=p_organization_id
    AND ob.binding_state='active'
    AND ce.visibility_scope='farm_shared';

  SELECT EXISTS(
    SELECT 1 FROM pg_catalog.pg_timezone_names tz
    WHERE tz.name=v_overlay.timezone_name
  ) INTO v_zone_ok;

  -- Independent Ledger root governance is only a *candidate* ability to
  -- request a source-owned correction. It does NOT itself authorize writes
  -- to Shared Intelligence, resource claims or third-party commitments.
  v_principal:=atlas.current_principal_id_v1();
  v_root:=coalesce(
    v_principal IS NOT NULL AND
    atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id),false);

  v_summary:=jsonb_build_object(
    'title',v_overlay.title IS DISTINCT FROM v_canonical.title,
    'sourceStatus',v_overlay.status IS DISTINCT FROM v_canonical.status,
    'startLocalTime',CASE WHEN v_zone_ok THEN
      v_overlay.start_local_time IS DISTINCT FROM
        (v_canonical.start_at AT TIME ZONE v_overlay.timezone_name)::time
      ELSE NULL END,
    'date',CASE WHEN v_zone_ok THEN
      v_overlay.event_date IS DISTINCT FROM
        (v_canonical.start_at AT TIME ZONE v_overlay.timezone_name)::date
      ELSE NULL END,
    'endLocalTime',CASE WHEN v_canonical.end_at IS NOT NULL AND v_zone_ok THEN
      v_overlay.end_local_time IS DISTINCT FROM
        (v_canonical.end_at AT TIME ZONE v_overlay.timezone_name)::time
      ELSE NULL END
  );

  -- Booking/resource counts are not exposed to all ordinary Event viewers.
  -- A Ledger seat can see an admitted Event; that is NOT a right to inspect
  -- a venue's booking and resource utilization.
  IF v_root THEN
    SELECT count(*)::integer INTO v_claim_count
      FROM ledger.occurrence_resource_claims c
      WHERE c.ledger_id=p_ledger_id
        AND c.occurrence_id=p_occurrence_id
        AND c.claim_state IN ('confirmed','tentative');
    SELECT count(*)::integer INTO v_booking_count
      FROM ledger.bookings b
      WHERE b.ledger_id=p_ledger_id
        AND b.occurrence_id=p_occurrence_id
        AND b.booking_state NOT IN ('cancelled');
    SELECT count(*)::integer INTO v_other_ledger_count
      FROM ledger.occurrence_calendar_bindings cb
      WHERE cb.occurrence_id=p_occurrence_id
        AND cb.ledger_id<>p_ledger_id
        AND cb.binding_state='active';
    v_claims:=jsonb_build_object(
      'evaluation','root_governing_scoped_summary',
      'activeResourceClaimCount',v_claim_count,
      'nonCancelledBookingCount',v_booking_count,
      'otherActiveLedgerBindingCount',v_other_ledger_count,
      'actualClaimIntervalsOrAvailabilityNotDisclosed',true);
    IF v_claim_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'resource_claims_need_source_owned_retime_review');
    END IF;
    IF v_booking_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'bookings_need_source_owned_commitment_review');
    END IF;
    IF v_other_ledger_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'canonical_occurrence_used_by_other_ledgers');
    END IF;
  ELSE
    v_claims:=jsonb_build_object(
      'evaluation','not_authorized',
      'activeResourceClaimCount',null,
      'nonCancelledBookingCount',null,
      'otherActiveLedgerBindingCount',null,
      'notEvaluatedIsNotZero',true);
    v_reasons:=v_reasons||jsonb_build_array(
      'governing_source_review_required');
  END IF;
  IF NOT v_zone_ok THEN
    v_reasons:=v_reasons||jsonb_build_array(
      'operational_timezone_not_recognized');
  END IF;
  IF NOT v_proposed THEN
    v_reasons:=v_reasons||jsonb_build_array(
      'exact_proposed_interval_not_submitted');
  END IF;

  -- These are hard non-negotiable unintegrated dependencies at this stage:
  -- communications/public assertions and independent booking collision
  -- preflight must be run by their own sources at actual write time.
  v_reasons:=v_reasons||jsonb_build_array(
    'source_owned_schedule_writer_not_released',
    'communication_and_publication_impact_not_evaluated',
    'resource_capacity_collision_preflight_not_completed');

  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','ledger_occurrence_schedule_preflight_v1',
    'scope',jsonb_build_object(
      'ledgerId',p_ledger_id,'organizationId',p_organization_id,
      'occurrenceId',p_occurrence_id),
    'actorPersonId',v_actor,
    'rootGoverningCandidate',v_root,
    'canonicalSource',jsonb_build_object(
      'ref',jsonb_build_object(
        'authority','local_intel','kind','occurrence','id',v_canonical.id),
      'title',v_canonical.title,'status',v_canonical.status,
      'startsAt',v_canonical.start_at,'endsAt',v_canonical.end_at,
      'updatedAt',v_canonical.updated_at),
    'operationalSource',jsonb_build_object(
      'ref',jsonb_build_object(
        'authority','atlas','kind','community_event','id',v_overlay.id),
      'title',v_overlay.title,'status',v_overlay.status,
      'eventDate',v_overlay.event_date,
      'startLocalTime',v_overlay.start_local_time,
      'endLocalTime',v_overlay.end_local_time,
      'timezoneName',v_overlay.timezone_name,
      'updatedAt',v_overlay.updated_at),
    'sourceComparisons',v_summary,
    'sourceComparisonIsNotAdjudication',true,
    'proposedInterval',CASE WHEN v_proposed THEN
      jsonb_build_object(
        'startsAt',p_proposed_starts_at,'endsAt',p_proposed_ends_at,
        'changesCanonicalInterval',
          (p_proposed_starts_at IS DISTINCT FROM v_canonical.start_at OR
           p_proposed_ends_at IS DISTINCT FROM v_canonical.end_at),
        'operationalWallClockComparison',CASE WHEN v_zone_ok THEN
          jsonb_build_object(
            'proposedLocalDate',
              (p_proposed_starts_at AT TIME ZONE v_overlay.timezone_name)::date,
            'proposedLocalStart',
              (p_proposed_starts_at AT TIME ZONE v_overlay.timezone_name)::time,
            'proposedLocalEnd',
              (p_proposed_ends_at AT TIME ZONE v_overlay.timezone_name)::time)
          ELSE null END)
      ELSE null END,
    'dependentSourceImpact',v_claims,
    'commitBlockedReasons',v_reasons,
    'approvedToCommit',false,
    'readOnly',true,
    'coverage',jsonb_build_object(
      'sourceFamiliesEvaluated',jsonb_build_array(
        'canonical_occurrence','one_farm_shared_community_event',
        'native_ledger_occurrence_binding'),
      'sensitiveResourceSummaryEvaluatedOnlyForRoot',v_root,
      'communicationImpactComplete',false,
      'crossOrganizationSourceWritersVerified',false,
      'allBookingsAndResourceCapacityProvedAvailable',false,
      'personalTemporalFieldComplete',false)
  );
END
$function$;


-- Exact Event identity admission must not expose everyone's original Work,
-- participant names or unbounded Event Work history.
CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_shared_work_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid;
  v_event local_intel.occurrences%rowtype;
  v_items jsonb;
  v_root boolean:=false;
begin
  v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  v_root:=coalesce(
    exists(select 1 from atlas.principal_ledger_authorities pa
      join atlas.principals actor_principal on actor_principal.id=pa.principal_id
        and actor_principal.status='active' and actor_principal.person_id=v_actor
      where pa.ledger_id=p_ledger_id
        and pa.principal_id=atlas.current_principal_id_v1()
        and pa.authority_kind='root_governing' and pa.status='active')
    and atlas.principal_has_ledger_authority_v1(
      atlas.current_principal_id_v1(),p_ledger_id),false);
  select * into v_event from local_intel.occurrences where id=p_occurrence_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'workItemId',q.id,'title',q.title,'state',q.work_state,
    'createdAt',q.created_at,'completedAt',q.completed_at,
    'linkedAs',q.relation_kind,'resultContractKey',q.result_contract_key,
    'canMarkDone',q.can_mark_done,'markedDoneBy',q.marked_done_by
  ) order by q.created_at,q.id),'[]'::jsonb)
  into v_items
  from (
    select distinct on (w.id) w.id,w.title,w.work_state,w.created_at,
      w.completed_at,w.result_contract_key,ctx.relation_kind,
      marker.display_name as marked_done_by,
      (w.source_object_type='ledger_occurrence_shared_work'
        and w.source_object_id=p_occurrence_id
        and w.result_contract_key='ledger_occurrence_shared_confirmation_v1'
        and w.metadata->>'ledgerId'=p_ledger_id::text
        and w.work_state='open'
        and v_root) as can_mark_done
    from atlas.work_item_context_links ctx
    join atlas.work_items w on w.id=ctx.work_item_id
      and w.organization_id=p_organization_id
    join atlas.company_work_native_ledger_relevance rel
      on rel.work_item_id=w.id and rel.organization_id=w.organization_id
        and rel.ledger_id=p_ledger_id and rel.attribution_state='active'
    left join lateral (
      select person.display_name
      from atlas.work_execution_results result
      join atlas.work_result_acceptances accepted
        on accepted.execution_result_id=result.id and accepted.decision='accepted'
      join reality.entities person
        on person.id=(result.metadata->>'actorPersonId')::uuid
          and person.entity_kind='person' and person.identity_state='canonical'
      where result.organization_id=w.organization_id
        and result.work_item_id=w.id
        and result.result_kind='completed'
        and result.result_contract_key='ledger_occurrence_shared_confirmation_v1'
        and result.metadata->>'source'=
          'mark_ledger_occurrence_shared_work_done_self_api_v1'
      order by accepted.accepted_at desc,result.id desc
      limit 1
    ) marker on true
    where ctx.organization_id=p_organization_id
      and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
      and ctx.subject_id=p_occurrence_id and ctx.relation_kind in ('for','about','supports')
      and w.work_state in ('open','completed')
      and (v_root or ((
       EXISTS (SELECT 1 FROM atlas.work_allocations alloc
         WHERE alloc.work_item_id=w.id AND alloc.organization_id=w.organization_id
           AND alloc.state='active' AND alloc.allocation_role='responsible'
           AND alloc.assignee_canonical_person_id=v_actor)
       OR EXISTS (SELECT 1 FROM atlas.ledger_occurrence_work_attention_v1 att2
         WHERE att2.work_item_id=w.id AND att2.ledger_id=p_ledger_id
           AND att2.occurrence_id=p_occurrence_id
           AND att2.person_entity_id=v_actor AND att2.attention_state='active')
     )
     AND atlas.person_original_work_identity_disclosed_self_v1(
       p_organization_id,p_ledger_id,w.id,v_actor)))
    order by w.id,ctx.created_at
  ) q;
  return jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_shared_work_v1',
    'ledgerId',p_ledger_id,'organizationId',p_organization_id,
    'occurrence',jsonb_build_object(
      'id',v_event.id,'title',v_event.title,'status',v_event.status,
      'startsAt',v_event.start_at,'endsAt',v_event.end_at),
    'work',v_items,
    'permissions',jsonb_build_object('ordinaryWorkCreate',v_root,'ordinaryWorkMarkDone',v_root),
    'truthBoundary',jsonb_build_object('scopedToExactEvent',true,
      'notGeneralLedgerHistory',true,'noCustomerOrFinanceAccess',true,
      'notProofOfEmailSending',true,'physicalPerformerNotInferred',true));
end
$function$
;

CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_work_extension_self_api_v1(p_organization_id uuid, p_ledger_id uuid, p_occurrence_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor uuid;v_items jsonb;v_history jsonb;
 v_root boolean:=false;v_visible_work_ids uuid[]:=ARRAY[]::uuid[];
BEGIN
 v_actor:=atlas.ledger_occurrence_shared_work_actor_self_v1(
  p_organization_id,p_ledger_id,p_occurrence_id);
 v_root:=coalesce(
    exists(select 1 from atlas.principal_ledger_authorities pa
      join atlas.principals actor_principal on actor_principal.id=pa.principal_id
        and actor_principal.status='active' and actor_principal.person_id=v_actor
      where pa.ledger_id=p_ledger_id
        and pa.principal_id=atlas.current_principal_id_v1()
        and pa.authority_kind='root_governing' and pa.status='active')
    and atlas.principal_has_ledger_authority_v1(
      atlas.current_principal_id_v1(),p_ledger_id),false);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',z.id,'title',z.title,'state',z.display_state,
  'workState',z.work_state,'canMarkDone',z.can_mark_done,
  'directedTo',z.directed_to,'sourceOwned',true,
  'createdInsideEvent',z.created_inside_event)
  ORDER BY z.created_at,z.id),'[]'::jsonb) INTO v_items
 FROM (
  SELECT w.id,w.title,w.work_state,w.created_at,
   CASE WHEN w.work_state='open' AND action.action_kind='blocked'
     THEN 'blocked' ELSE w.work_state END display_state,
   (w.source_object_type='ledger_occurrence_shared_work'
      AND w.source_object_id=p_occurrence_id
      AND w.metadata->>'ledgerId'=p_ledger_id::text) created_inside_event,
   (w.work_state='open' AND coalesce(action.action_kind,'')<>'blocked'
     AND w.source_object_type='ledger_occurrence_shared_work'
     AND w.source_object_id=p_occurrence_id
     AND w.result_contract_key='ledger_occurrence_shared_confirmation_v1'
     AND v_root) can_mark_done,
   (SELECT coalesce(jsonb_agg(jsonb_build_object(
     'personEntityId',att.person_entity_id,'displayName',e.display_name)
     ORDER BY e.display_name),'[]'::jsonb)
    FROM atlas.ledger_occurrence_work_attention_v1 att
    JOIN reality.entities e ON e.id=att.person_entity_id
    WHERE att.work_item_id=w.id AND att.ledger_id=p_ledger_id
     AND att.occurrence_id=p_occurrence_id AND att.attention_state='active'
     AND (v_root OR att.person_entity_id=v_actor)) directed_to
  FROM atlas.work_item_context_links ctx
  JOIN atlas.work_items w ON w.id=ctx.work_item_id
   AND w.organization_id=p_organization_id
  JOIN atlas.company_work_native_ledger_relevance rel
   ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
     AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
  LEFT JOIN LATERAL (
    SELECT e.action_kind FROM atlas.ledger_occurrence_work_actions_v1 e
    WHERE e.work_item_id=w.id
      AND e.action_kind IN ('blocked','reopened')
    ORDER BY e.action_sequence DESC LIMIT 1
  ) action ON true
  WHERE ctx.organization_id=p_organization_id
    AND ctx.subject_domain='temporal' AND ctx.subject_kind='occurrence'
    AND ctx.subject_id=p_occurrence_id
    AND w.work_state IN ('open','completed')
    AND (v_root OR ((
       EXISTS (SELECT 1 FROM atlas.work_allocations alloc
         WHERE alloc.work_item_id=w.id AND alloc.organization_id=w.organization_id
           AND alloc.state='active' AND alloc.allocation_role='responsible'
           AND alloc.assignee_canonical_person_id=v_actor)
       OR EXISTS (SELECT 1 FROM atlas.ledger_occurrence_work_attention_v1 att2
         WHERE att2.work_item_id=w.id AND att2.ledger_id=p_ledger_id
           AND att2.occurrence_id=p_occurrence_id
           AND att2.person_entity_id=v_actor AND att2.attention_state='active')
     )
     AND atlas.person_original_work_identity_disclosed_self_v1(
       p_organization_id,p_ledger_id,w.id,v_actor)))
    AND NOT EXISTS (
      SELECT 1 FROM atlas.ledger_occurrence_work_actions_v1 removed
      WHERE removed.work_item_id=w.id AND removed.ledger_id=p_ledger_id
        AND removed.occurrence_id=p_occurrence_id AND removed.action_kind='removed'
    )
 ) z;
 SELECT coalesce(array_agg((j->>'workItemId')::uuid),ARRAY[]::uuid[])
 INTO v_visible_work_ids FROM jsonb_array_elements(v_items) j;
 -- History combines native Work creation and accepted completion evidence
 -- with append-only Event actions. A completed task is not falsely labelled
 -- as performed by the checker; actor/performer remains separate.
 WITH historical_events AS (
  SELECT a.work_item_id,a.action_kind,a.actor_person_id,
    a.target_person_id,a.occurred_at,a.explanation,a.id,a.action_sequence
  FROM atlas.ledger_occurrence_work_actions_v1 a
  WHERE a.organization_id=p_organization_id AND a.ledger_id=p_ledger_id
    AND a.occurrence_id=p_occurrence_id
  UNION ALL
  SELECT w.id,'created'::text,
    NULLIF(w.metadata->>'createdByPersonId','')::uuid,NULL::uuid,
    w.created_at,NULL::text,w.id,NULL::bigint
  FROM atlas.work_items w
  WHERE w.organization_id=p_organization_id
    AND w.source_object_type='ledger_occurrence_shared_work'
    AND w.source_object_id=p_occurrence_id
    AND w.metadata->>'ledgerId'=p_ledger_id::text
  UNION ALL
  SELECT r.work_item_id,'marked_done'::text,
    NULLIF(r.metadata->>'actorPersonId','')::uuid,NULL::uuid,
    r.reported_at,NULL::text,r.id,NULL::bigint
  FROM atlas.work_execution_results r
  JOIN atlas.work_result_acceptances accepted
    ON accepted.execution_result_id=r.id AND accepted.decision='accepted'
  JOIN atlas.work_items w ON w.id=r.work_item_id
  WHERE r.organization_id=p_organization_id
    AND r.result_contract_key='ledger_occurrence_shared_confirmation_v1'
    AND r.result_kind='completed'
    AND w.source_object_type='ledger_occurrence_shared_work'
    AND w.source_object_id=p_occurrence_id
    AND w.metadata->>'ledgerId'=p_ledger_id::text
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'workItemId',e.work_item_id,'actionKind',e.action_kind,
  'actorPersonId',e.actor_person_id,'actorName',person.display_name,
  'targetPersonId',e.target_person_id,'at',e.occurred_at,
  'explanation',e.explanation,'physicalPerformerNotAsserted',true)
  ORDER BY e.occurred_at,e.action_sequence NULLS LAST,e.id),'[]'::jsonb) INTO v_history
 FROM historical_events e
 LEFT JOIN reality.entities person ON person.id=e.actor_person_id
 WHERE v_root OR e.work_item_id=ANY(v_visible_work_ids);
 RETURN jsonb_build_object('ok',true,'ledgerId',p_ledger_id,
  'organizationId',p_organization_id,'occurrenceId',p_occurrence_id,
  'work',v_items,'history',v_history,
  'custody','ledger','attentionDoesNotTransferControl',true);
END
$function$
;

COMMIT;
