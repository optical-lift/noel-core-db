-- Source-only combined release package, NOT a live migration.
-- Exact editor SHA: 915ca04d99ed38c54194cce3de2afd58e1b65cda
-- Exact scheduling/status SHA: bff45f66086c2d6457455fba855efbe149ee67b8
-- Protected test fixture HEAD after offer repair: 94df8b5fe492eaaaa64c6483794534d9aff8937a
-- Same single original Work + real signed source guards; no production DML.
BEGIN;
-- ATLAS candidate: same-original native Work text amendments and own Result
-- narrative readback. DRAFT ONLY; do not apply directly to production.
-- Owner governance is proved by the EXISTING native/institutional root.
-- A native Ledger seat alone is not sufficient. Result payload disclosure
-- is STRICTLY limited to exact signed reporter, not any other worker.
CREATE TABLE atlas.native_work_text_revision_events_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  ledger_id uuid NOT NULL,
  work_item_id uuid NOT NULL,
  actor_user_id uuid NOT NULL,
  actor_person_id uuid NOT NULL,
  before_title text NOT NULL,
  after_title text NOT NULL,
  before_instructions text,
  after_instructions text,
  old_updated_at timestamptz NOT NULL,
  new_updated_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT native_work_text_revision_exact_original_fk
    FOREIGN KEY(organization_id,work_item_id)
    REFERENCES atlas.work_items(organization_id,id) ON DELETE RESTRICT,
  CONSTRAINT native_work_text_revision_actual_change
    CHECK(before_title IS DISTINCT FROM after_title OR
      before_instructions IS DISTINCT FROM after_instructions)
);
CREATE INDEX native_work_text_revision_original_order_v1
  ON atlas.native_work_text_revision_events_v1(work_item_id,recorded_at,id);
ALTER TABLE atlas.native_work_text_revision_events_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON atlas.native_work_text_revision_events_v1 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION atlas.guard_native_work_text_revision_immutable_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Native Work amendment history is immutable'
    USING ERRCODE='42501';
END
$function$;
CREATE TRIGGER native_work_text_revision_append_only_v1
  BEFORE UPDATE OR DELETE ON atlas.native_work_text_revision_events_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.guard_native_work_text_revision_immutable_v1();

-- Fail-closed, shared source precondition: BOTH roots, exact native
-- Ledger provenance, institutional owner membership and original Work.
-- Does not infer authorization from Event/Today page or title.
CREATE FUNCTION atlas.require_native_original_work_text_owner_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS atlas.work_items
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_membership uuid;
  v_work atlas.work_items%ROWTYPE;
BEGIN
  IF p_organization_id IS NULL OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Exact Organization, Ledger and original Work required'
      USING ERRCODE='22023';
  END IF;
  v_person:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  v_membership:=atlas.current_effective_organization_membership_v1(
    p_organization_id);
  IF NOT EXISTS(
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.id=v_membership AND m.organization_id=p_organization_id
      AND m.person_id=v_person AND m.user_id=auth.uid()
      AND m.role='owner' AND m.active
  ) THEN
    RAISE EXCEPTION 'Exact signed institutional owner required'
      USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
      AND w.household_id IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original native Company Work unavailable'
      USING ERRCODE='42501';
  END IF;
  -- Only Work natively authored into Ledger/Event Work by Atlas, not
  -- derived production/medical/legacy sources with their own edit laws.
  IF v_work.source_object_type IS NULL OR
     v_work.source_object_type NOT IN
     ('ledger_occurrence_shared_work','ledger_connected_direct_task') THEN
    RAISE EXCEPTION 'This source-managed Work requires its own edit authority'
      USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id
      AND r.work_item_id=p_work_item_id
      AND r.ledger_id=p_ledger_id
      AND r.attribution_state='active'
      AND (
        r.evidence_kind IN ('owner_attested','participant_attested')
        OR (r.evidence_kind='source_verified' AND EXISTS(
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            p_work_item_id,p_ledger_id) proof
          WHERE proof.source_schema=r.source_schema
            AND proof.source_table=r.source_table
            AND proof.source_id=r.source_id))
      )
  ) THEN
    RAISE EXCEPTION 'Exact native Work/Ledger relevance is not established'
      USING ERRCODE='42501';
  END IF;
  RETURN v_work;
END
$function$;

CREATE FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
BEGIN
  v_work:=atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_text_owner_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',v_work.id,'title',v_work.title,
    'instructions',v_work.instructions,'workState',v_work.work_state,
    'updatedAt',v_work.updated_at,
    'canEdit',v_work.work_state='open',
    'oneOriginalWorkId',true);
END
$function$;

CREATE FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_expected_updated_at timestamptz,p_new_title text,p_new_instructions text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_new atlas.work_items%ROWTYPE;
  v_title text:=btrim(coalesce(p_new_title,''));
  v_instructions text:=nullif(btrim(coalesce(p_new_instructions,'')),'');
  v_event_id uuid;
BEGIN
  -- Before locking, the original signed source must prove all privileges.
  PERFORM atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  IF p_expected_updated_at IS NULL OR length(v_title) NOT BETWEEN 1 AND 240
     OR v_instructions IS NOT NULL AND length(v_instructions)>10000 THEN
    RAISE EXCEPTION 'Exact expected revision and bounded Work text required'
      USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
    FOR UPDATE;
  IF v_work.id IS NULL OR v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Only open original Work may be edited' USING ERRCODE='23514';
  END IF;
  IF v_work.updated_at IS DISTINCT FROM p_expected_updated_at THEN
    RAISE EXCEPTION 'Original Work changed since the editor opened; reload before editing'
      USING ERRCODE='40001';
  END IF;
  IF v_work.title IS NOT DISTINCT FROM v_title AND
     v_work.instructions IS NOT DISTINCT FROM v_instructions THEN
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_text_revision_v1',
      'workItemId',v_work.id,'title',v_work.title,
      'instructions',v_work.instructions,'updatedAt',v_work.updated_at,
      'changed',false,'oneOriginalWorkId',true);
  END IF;
  UPDATE atlas.work_items w
    SET title=v_title,instructions=v_instructions,updated_at=clock_timestamp()
    WHERE w.id=v_work.id AND w.organization_id=v_work.organization_id
    RETURNING * INTO v_new;
  INSERT INTO atlas.native_work_text_revision_events_v1(
    organization_id,ledger_id,work_item_id,actor_user_id,actor_person_id,
    before_title,after_title,before_instructions,after_instructions,
    old_updated_at,new_updated_at
  ) VALUES(
    p_organization_id,p_ledger_id,p_work_item_id,auth.uid(),
    atlas.current_person_id_v1(),v_work.title,v_new.title,
    v_work.instructions,v_new.instructions,v_work.updated_at,v_new.updated_at
  ) RETURNING id INTO v_event_id;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_text_revision_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',v_work.id,'title',v_new.title,
    'instructions',v_new.instructions,'updatedAt',v_new.updated_at,
    'changed',true,'revisionEventId',v_event_id,
    'oneOriginalWorkId',true,'changedNoResultOrAllocation',true);
END
$function$;

-- Own authored Result narrative only, under STILL-CURRENT exact
-- native owner access. A governor's title does NOT grant all workers'
-- private payloads. No comments/notifications are inferred.
CREATE FUNCTION atlas.read_native_original_work_own_results_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 30
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_work atlas.work_items%ROWTYPE;
  v_items jsonb:='[]'::jsonb;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Result history page limit 1 to 100 required'
      USING ERRCODE='22023';
  END IF;
  v_work:=atlas.require_native_original_work_text_owner_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'resultId',x.id,'workItemId',x.work_item_id,
    'resultKind',x.result_kind,'reportedAt',x.reported_at,
    'note',x.payload->>'note','isOwnSignedReport',true
  ) ORDER BY x.reported_at DESC,x.id DESC),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT r.id,r.work_item_id,r.result_kind,r.reported_at,r.payload
    FROM atlas.work_execution_results r
    WHERE r.work_item_id=v_work.id
      AND r.organization_id=p_organization_id
      AND r.reported_by_user_id=auth.uid()
    ORDER BY r.reported_at DESC,r.id DESC LIMIT p_limit
  ) x;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_own_results_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'items',v_items,
    'ownReporterOnly',true,'otherPeopleReportsDisclosed',false,
    'oneOriginalWorkId',true);
END
$function$;

-- Public REST membrane, signed role only; internal source tables never
-- receive grants to browser roles. Mirror established Atlas RPC contracts.
CREATE FUNCTION public.read_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.read_native_original_work_text_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id);
$function$;
CREATE FUNCTION public.revise_native_original_work_text_owner_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_expected_updated_at timestamptz,p_new_title text,p_new_instructions text
) RETURNS jsonb LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.revise_native_original_work_text_owner_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,
    p_expected_updated_at,p_new_title,p_new_instructions);
$function$;
CREATE FUNCTION public.read_native_original_work_own_results_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 30
) RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
  SELECT atlas.read_native_original_work_own_results_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_limit);
$function$;

REVOKE ALL ON FUNCTION atlas.require_native_original_work_text_owner_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.guard_native_work_text_revision_immutable_v1()
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION atlas.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  TO authenticated;

REVOKE ALL ON FUNCTION public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.revise_native_original_work_text_owner_self_api_v1(uuid,uuid,uuid,timestamptz,text,text)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_own_results_self_api_v1(uuid,uuid,uuid,integer)
  TO authenticated;
-- SOURCE ONLY: Atlas #480 / #487. Not a production migration.
-- Repair existing authenticated owner date writer to admit legitimate direct
-- connected Person Work, reusing the same original Work and native Ledger.
-- All owner, signed actor, current native Ledger, date window, action history,
-- and responsibility guards remain. No new role or table grants.
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
  v_owner_member:=atlas.current_effective_organization_membership_v1(
    v_work.organization_id);
  if not exists (
    select 1 from atlas.organization_memberships m
    where m.id=v_owner_member and m.organization_id=v_work.organization_id
      and m.person_id=v_owner and m.role='owner' and m.active
  ) then raise exception 'Current authenticated owner membership required.'
    using errcode='42501'; end if;
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
        'sourceChange','native_person_owner_unplan_v1',
        'withdrawalReason',v_reason)
    where id=v_old.id and plan_state in ('active','needs_replan');
    insert into atlas.work_execution_plan_events(
      organization_id,work_item_id,plan_id,event_kind,
      from_planned_service_date,from_exposure_service_date,
      actor_membership_id,reason,metadata)
    values (v_work.organization_id,v_work.id,v_old.id,'withdrawn',
      v_old.planned_service_date,v_old.exposure_service_date,
      v_owner_member,v_reason,
      jsonb_build_object('source','native_person_owner_unplan_v1'));
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
      jsonb_build_object('source','native_person_owner_plan_v1'))
    returning * into v_plan;
    v_event:='planned';
  else
    update atlas.work_execution_plans
      set planned_service_date=p_service_date,exposure_service_date=p_service_date,
        plan_state='active',plan_reason=v_reason,
        planned_by_membership_id=v_owner_member,
        metadata=metadata||jsonb_build_object(
          'sourceChange','native_person_owner_plan_v1'),
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
    jsonb_build_object('source','native_person_owner_plan_v1'));
  return jsonb_build_object('ok',true,
    'contractVersion','native_person_work_plan_v1',
    'state','planned','workItemId',v_work.id,
    'ledgerId',p_ledger_id,'planId',v_plan.id,
    'plannedServiceDate',v_plan.planned_service_date,
    'responsiblePersonId',v_allocation.assignee_canonical_person_id,
    'newWorkCreated',false,'workerReadProven',false);
end
$function$;

-- DRAFT SOURCE-ONLY. Requires protected clone and real signed proof.
-- Add an assigned person's latest Result KIND to the existing all-date native
-- Work reader, without leaking note/body or changing original Work identity.
-- Blocked/Waiting UI must only use explicit signed status, not inferred text.
-- Waiting remains unclassified until a source-defined waiting result exists.
CREATE OR REPLACE FUNCTION atlas.connected_person_my_work_self_api_v1(p_limit integer DEFAULT 50, p_after_allocation_id uuid DEFAULT NULL::uuid)
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
      a.id allocation_id,w.id work_id,w.organization_id,
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
    LEFT JOIN LATERAL (
      SELECT p.id,p.plan_state,p.planned_service_date,p.exposure_service_date,
        p.first_planned_service_date
      FROM atlas.work_execution_plans p
      WHERE p.work_item_id=w.id AND p.organization_id=w.organization_id
        AND p.responsible_allocation_id=a.id
        AND p.plan_state IN ('active','needs_replan')
      ORDER BY CASE WHEN p.plan_state='active' THEN 0 ELSE 1 END,
        p.updated_at DESC,p.id DESC LIMIT 1
    ) plan ON true
    -- Only the assigned person's latest result classification, never its private note.
    LEFT JOIN LATERAL (
      SELECT r.result_kind
      FROM atlas.work_execution_results r
      WHERE r.work_item_id=w.id AND r.responsible_allocation_id=a.id
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
    WHERE a.allocation_role='responsible' AND a.state='active'
      AND a.assignee_canonical_person_id=v_self
      AND a.assignee_membership_id IS NULL
      AND a.establishment_basis_kind IN (
        'person_connection_receiver_uptake','delegated_under_standing_scope',
        'ledger_connection_direct_assignment','original_subject_direct_assignment_v1'
      )
      AND w.work_state='open'
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
    'ok',true,'contractVersion','connected_person_my_work_v1',
    'personId',v_self,'items',v_items,
    'hasMore',v_more,'nextAllocationId',CASE WHEN v_more THEN v_next ELSE NULL END,
    'sourceScope','active_responsible_person_native_ledger_work',
    'scheduleReadAcrossAllDates',true,
    'optionalRequestsExcluded',true,'noPersonalTaskCreated',true
  );
END
$function$;

COMMIT;
