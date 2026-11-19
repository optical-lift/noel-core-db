BEGIN;
-- HELD, NOT RELEASED: first ordinary native Work self-participation.
-- Source baseline Noel main 6f1559c2a445ef90f23e5c53ddb68b9788ae9310; exact trigger body drift refuses installation.
DO $check$
BEGIN
 IF (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='atlas.validate_active_work_allocation_membership_v1()'::regprocedure)
    IS DISTINCT FROM $membership$
begin
  if new.state='active' then
    if new.allocation_role='responsible'
      and new.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and new.assignee_canonical_person_id is not null then
      if new.assignee_membership_id is not null
        or new.assignee_canonical_person_id is null
        or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Person-native responsibility requires an exact active Ledger connection'
          using errcode='23514';
      end if;
    elsif not exists (
      select 1 from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id and om.active
    ) then
      raise exception 'Legacy active Work allocation requires active Organization Membership'
        using errcode='23514';
    end if;
    if new.assigned_by_membership_id is not null
      and (tg_op='INSERT'
        or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
        or old.state is distinct from new.state
        or old.organization_id is distinct from new.organization_id)
      and not exists (
        select 1 from atlas.organization_memberships om
        where om.id=new.assigned_by_membership_id
          and om.organization_id=new.organization_id and om.active
      ) then
      raise exception 'Active Work allocation cannot name an inactive assigning membership'
        using errcode='23514';
    end if;
  end if;
  return new;
end
$membership$
 OR (SELECT prosrc FROM pg_catalog.pg_proc WHERE oid='atlas.guard_work_allocation_participation_establishment_v1()'::regprocedure)
    IS DISTINCT FROM $participation$
declare
  v_offer_id uuid;
begin
  if new.allocation_role not in ('participant','approver') then
    return new;
  end if;

  if tg_op='UPDATE'
     and (
       new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis
     ) then
    raise exception 'Company Work participation establishment provenance is immutable.'
      using errcode='23514';
  end if;

  if new.state<>'active' then
    return new;
  end if;

  if new.establishment_basis_kind<>'receiver_acceptance'
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active Company Work participation requires governed receiver acceptance.'
      using errcode='23514';
  end if;

  if coalesce(new.establishment_basis->>'contractVersion','')<>'company_work_participation_establishment_v1'
     or coalesce(new.establishment_basis->>'basisKind','')<>'receiver_acceptance'
     or coalesce(new.establishment_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(new.establishment_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(new.establishment_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'allocationRole','')<>new.allocation_role
     or coalesce(new.establishment_basis->>'sourceKind','')<>'company_work_participation_offer'
     or nullif(btrim(coalesce(new.establishment_basis->>'sourceId','')),'') is null then
    raise exception 'Company Work participation establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if new.assigned_by_membership_id is null
     or new.assigned_by_membership_id<>new.assignee_membership_id then
    raise exception 'Receiver-accepted participation must be established by the receiver carrier itself.'
      using errcode='23514';
  end if;

  begin
    v_offer_id:=(new.establishment_basis->>'sourceId')::uuid;
  exception when others then
    raise exception 'Participation sourceId must identify a valid participation offer.'
      using errcode='23514';
  end;

  if not exists(
    select 1
    from atlas.company_work_participation_offers o
    join atlas.organization_memberships m
      on m.organization_id=o.organization_id
     and m.person_id=o.target_person_entity_id
     and m.id=new.assignee_membership_id
    where o.id=v_offer_id
      and o.organization_id=new.organization_id
      and o.work_item_id=new.work_item_id
      and o.allocation_role=new.allocation_role
      and o.offer_state in ('offered','accepted')
  ) then
    raise exception 'Receiver-accepted participation must derive from the exact matching participation offer.'
      using errcode='23514';
  end if;

  return new;
end
$participation$
 THEN RAISE EXCEPTION 'Allocation guard baseline drift; reconcile before installation'; END IF;
END
$check$;
ALTER TABLE atlas.work_allocations DROP CONSTRAINT work_allocations_exact_assignee_carrier_v1;
ALTER TABLE atlas.work_allocations ADD CONSTRAINT work_allocations_exact_assignee_carrier_v1 CHECK (
  (organization_id IS NOT NULL AND
   (assignee_membership_id IS NOT NULL OR
    (assignee_canonical_person_id IS NOT NULL AND
     establishment_basis_kind IN(
       'person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment',
       'original_subject_direct_assignment_v1',
       'native_person_self_participation_v1','native_person_direct_participation_v1'
     ))) AND assignee_household_member_id IS NULL)
  OR
  (household_id IS NOT NULL
   AND assignee_membership_id IS NULL
   AND assigned_by_membership_id IS NULL
   AND establishment_basis_kind='household_explicit_carrier_v1'
   AND (assignee_household_member_id IS NOT NULL
        OR assignee_canonical_person_id IS NOT NULL))
 );
CREATE UNIQUE INDEX native_self_participation_active_v1 ON atlas.work_allocations(work_item_id,assignee_canonical_person_id)
 WHERE state='active' AND allocation_role='participant' AND assignee_membership_id IS NULL
   AND establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1');
CREATE UNIQUE INDEX native_self_participation_action_v1 ON atlas.work_allocations
 (work_item_id,assignee_canonical_person_id,(establishment_basis->>'sourceActionId'))
 WHERE establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1');
CREATE OR REPLACE FUNCTION atlas.validate_active_work_allocation_membership_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
begin
  if new.state='active' then
    if new.allocation_role='responsible'
      and new.establishment_basis_kind in ('person_connection_receiver_uptake','delegated_under_standing_scope','ledger_connection_direct_assignment','original_subject_direct_assignment_v1')
      and new.assignee_canonical_person_id is not null then
      if new.assignee_membership_id is not null
        or new.assignee_canonical_person_id is null
        or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Person-native responsibility requires an exact active Ledger connection'
          using errcode='23514';
      end if;
    elsif new.allocation_role='participant'
      and new.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1') then
      if new.assignee_membership_id is not null
        or new.assigned_by_membership_id is not null
        or new.assignee_canonical_person_id is null
        or NOT atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
          new.assignee_canonical_person_id) then
        raise exception 'Native participant requires current exact Ledger connection'
          using errcode='23514';
      end if;
    elsif not exists (
      select 1 from atlas.organization_memberships om
      where om.id=new.assignee_membership_id
        and om.organization_id=new.organization_id and om.active
    ) then
      raise exception 'Legacy active Work allocation requires active Organization Membership'
        using errcode='23514';
    end if;
    if new.assigned_by_membership_id is not null
      and (tg_op='INSERT'
        or old.assigned_by_membership_id is distinct from new.assigned_by_membership_id
        or old.state is distinct from new.state
        or old.organization_id is distinct from new.organization_id)
      and not exists (
        select 1 from atlas.organization_memberships om
        where om.id=new.assigned_by_membership_id
          and om.organization_id=new.organization_id and om.active
      ) then
      raise exception 'Active Work allocation cannot name an inactive assigning membership'
        using errcode='23514';
    end if;
  end if;
  return new;
end
$function$;
create or replace function atlas.guard_work_allocation_participation_establishment_v1()
returns trigger
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_offer_id uuid;
begin
  if new.allocation_role not in ('participant','approver') then
    return new;
  end if;

  if tg_op='UPDATE'
     and (
       new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis
     ) then
    raise exception 'Company Work participation establishment provenance is immutable.'
      using errcode='23514';
  end if;

  if new.state<>'active' then
    return new;
  end if;

  if new.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1') then
    if new.allocation_role<>'participant'
      or new.assignee_membership_id is not null
      or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or jsonb_typeof(new.establishment_basis) is distinct from 'object'
      or new.establishment_basis->>'contractVersion' is distinct from new.establishment_basis_kind
      or new.establishment_basis->>'workItemId' is distinct from new.work_item_id::text
      or new.establishment_basis->>'organizationId' is distinct from new.organization_id::text
      or (new.establishment_basis_kind='native_person_self_participation_v1' AND new.establishment_basis->>'actorPersonId' is distinct from new.assignee_canonical_person_id::text)
      or (new.establishment_basis_kind='native_person_direct_participation_v1' AND
          (new.establishment_basis->>'targetPersonId' is distinct from new.assignee_canonical_person_id::text
           OR new.establishment_basis->>'actorPersonId'=new.assignee_canonical_person_id::text
           OR NOT atlas.person_has_native_ledger_connection_v1(new.organization_id,
              (new.establishment_basis->>'nativeLedgerId')::uuid,new.assignee_canonical_person_id)))
      or coalesce(new.establishment_basis->>'sourceActionId','') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(new.establishment_basis->>'primaryAllocationId','') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(new.establishment_basis->>'nativeLedgerId','') !~ '^[0-9a-fA-F-]{36}$'
      or atlas.native_intake_responsibility_owner_context_v1(
        new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
        new.work_item_id)::text is distinct from new.establishment_basis->>'actorPersonId'
      or not exists(select 1 from atlas.work_allocations a
        where a.id=(new.establishment_basis->>'primaryAllocationId')::uuid
          and a.organization_id=new.organization_id and a.work_item_id=new.work_item_id
          and a.allocation_role='responsible' and a.state='active'
          and a.assignee_canonical_person_id is not null
          and a.assignee_canonical_person_id<>new.assignee_canonical_person_id
          and a.assignee_membership_id is null
          and a.establishment_basis->>'nativeLedgerId'=new.establishment_basis->>'nativeLedgerId') then
      raise exception 'Exact signed native self-participation required' using errcode='23514';
    end if;
    return new;
  end if;

  if new.establishment_basis_kind<>'receiver_acceptance'
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active Company Work participation requires governed receiver acceptance.'
      using errcode='23514';
  end if;

  if coalesce(new.establishment_basis->>'contractVersion','')<>'company_work_participation_establishment_v1'
     or coalesce(new.establishment_basis->>'basisKind','')<>'receiver_acceptance'
     or coalesce(new.establishment_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(new.establishment_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(new.establishment_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
     or coalesce(new.establishment_basis->>'allocationRole','')<>new.allocation_role
     or coalesce(new.establishment_basis->>'sourceKind','')<>'company_work_participation_offer'
     or nullif(btrim(coalesce(new.establishment_basis->>'sourceId','')),'') is null then
    raise exception 'Company Work participation establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if new.assigned_by_membership_id is null
     or new.assigned_by_membership_id<>new.assignee_membership_id then
    raise exception 'Receiver-accepted participation must be established by the receiver carrier itself.'
      using errcode='23514';
  end if;

  begin
    v_offer_id:=(new.establishment_basis->>'sourceId')::uuid;
  exception when others then
    raise exception 'Participation sourceId must identify a valid participation offer.'
      using errcode='23514';
  end;

  if not exists(
    select 1
    from atlas.company_work_participation_offers o
    join atlas.organization_memberships m
      on m.organization_id=o.organization_id
     and m.person_id=o.target_person_entity_id
     and m.id=new.assignee_membership_id
    where o.id=v_offer_id
      and o.organization_id=new.organization_id
      and o.work_item_id=new.work_item_id
      and o.allocation_role=new.allocation_role
      and o.offer_state in ('offered','accepted')
  ) then
    raise exception 'Receiver-accepted participation must derive from the exact matching participation offer.'
      using errcode='23514';
  end if;

  return new;
end
$function$;

-- Signed governor elects to participate THEMSELF, never assigns an
-- additional Person. Existing Work and primary allocation remain untouched.
CREATE OR REPLACE FUNCTION atlas.join_native_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_source_action_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_part atlas.work_allocations%rowtype;
 v_replay boolean:=false;
BEGIN
 IF p_source_action_id IS NULL THEN RAISE EXCEPTION 'Stable action ID required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 SELECT * INTO v_part FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
   AND a.assignee_canonical_person_id=v_actor AND a.establishment_basis_kind='native_person_self_participation_v1'
   AND a.establishment_basis->>'sourceActionId'=p_source_action_id::text;
 IF v_part.id IS NOT NULL THEN
   IF v_part.establishment_basis->>'nativeLedgerId' IS DISTINCT FROM p_ledger_id::text
   THEN RAISE EXCEPTION 'Action scope changed' USING ERRCODE='23505'; END IF;
   v_replay:=true;
 ELSE
   SELECT * INTO v_primary FROM atlas.work_allocations a
   WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
     AND a.allocation_role='responsible' AND a.state='active'
     AND a.assignee_membership_id IS NULL
     AND a.assignee_canonical_person_id IS NOT NULL
     AND a.assignee_canonical_person_id<>v_actor
     AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text;
   IF v_primary.id IS NULL OR NOT atlas.person_has_native_ledger_connection_v1(
     p_organization_id,p_ledger_id,v_primary.assignee_canonical_person_id)
   THEN RAISE EXCEPTION 'Existing native primary responsibility required' USING ERRCODE='42501';END IF;
   IF EXISTS(SELECT 1 FROM atlas.work_allocations a
     WHERE a.work_item_id=p_work_item_id AND a.state='active'
       AND a.assignee_canonical_person_id=v_actor)
   THEN RAISE EXCEPTION 'Person already carries this original' USING ERRCODE='23505';END IF;
   INSERT INTO atlas.work_allocations(organization_id,work_item_id,
     assignee_canonical_person_id,allocation_role,state,establishment_basis_kind,establishment_basis,metadata)
   VALUES(p_organization_id,p_work_item_id,v_actor,'participant','active','native_person_self_participation_v1',
     jsonb_build_object('contractVersion','native_person_self_participation_v1','organizationId',p_organization_id,
       'nativeLedgerId',p_ledger_id,'workItemId',p_work_item_id,'actorPersonId',v_actor,
       'primaryAllocationId',v_primary.id,'sourceActionId',p_source_action_id),
     jsonb_build_object('source','join_native_original_work_self_api_v1')) RETURNING * INTO v_part;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_person_self_participation_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
   'personId',v_actor,'allocationId',v_part.id,'allocationRole',v_part.allocation_role,
   'allocationState',v_part.state,'idempotent',v_replay,
   'primaryResponsibilityChanged',false,'workCopied',false,'resultRecorded',false);
END
$function$;

-- Native participant mutations must never enter the older primary
-- responsibility/plan and legacy carrier synchronization consumers.
-- Those historical consumers remain retirement debt for other allocation kinds.
DROP TRIGGER work_allocations_reconcile_execution_plan_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_reconcile_execution_plan_v1
 AFTER INSERT OR UPDATE OF state,assignee_membership_id ON atlas.work_allocations
 FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL AND
 (NEW.establishment_basis_kind IS NULL OR NEW.establishment_basis_kind NOT IN ('native_person_self_participation_v1','native_person_direct_participation_v1')))
 EXECUTE FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_trigger_v1();
DROP TRIGGER work_allocations_sync_production_carrier_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_sync_production_carrier_v1
 AFTER INSERT OR UPDATE OF state,assignee_membership_id,allocation_role ON atlas.work_allocations
 FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL AND
 (NEW.establishment_basis_kind IS NULL OR NEW.establishment_basis_kind NOT IN ('native_person_self_participation_v1','native_person_direct_participation_v1')))
 EXECUTE FUNCTION atlas.sync_production_company_work_responsibility_carrier_trigger_v1();

-- Self-participation is scoped to the exact active primary allocation observed
-- when joining. A terminal original or changed primary releases this
-- relationship, not the Person's performance. Rejoining is a new decision.
CREATE OR REPLACE FUNCTION atlas.end_native_self_participation_on_work_terminal_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 UPDATE atlas.work_allocations SET state='released',released_at=now(),updated_at=now(),
   release_reason='Original Work ended; participation closed without performer attestation.'
 WHERE work_item_id=NEW.id AND organization_id=NEW.organization_id
   AND state='active' AND allocation_role='participant'
   AND establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1');
 RETURN NEW;
END
$function$;
CREATE TRIGGER native_self_participation_work_terminal_v1
 AFTER UPDATE OF work_state ON atlas.work_items
 FOR EACH ROW WHEN (OLD.work_state='open' AND NEW.work_state<>'open' AND NEW.organization_id IS NOT NULL)
 EXECUTE FUNCTION atlas.end_native_self_participation_on_work_terminal_v1();

CREATE OR REPLACE FUNCTION atlas.end_native_self_participation_on_primary_release_v1()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 UPDATE atlas.work_allocations SET state='released',released_at=now(),updated_at=now(),
   release_reason='Original primary allocation ended; shared participation needs a new decision.'
 WHERE work_item_id=NEW.work_item_id AND organization_id=NEW.organization_id
   AND state='active' AND allocation_role='participant'
   AND establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
   AND establishment_basis->>'primaryAllocationId'=NEW.id::text;
 RETURN NEW;
END
$function$;
CREATE TRIGGER native_self_participation_primary_release_v1
 AFTER UPDATE OF state ON atlas.work_allocations
 FOR EACH ROW WHEN (OLD.state='active' AND NEW.state<>'active'
 AND NEW.allocation_role='responsible' AND NEW.organization_id IS NOT NULL)
 EXECUTE FUNCTION atlas.end_native_self_participation_on_primary_release_v1();

-- Read-only eligibility for the existing Work page. Not a roster grant.
CREATE OR REPLACE FUNCTION atlas.native_original_work_self_participation_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_part atlas.work_allocations%rowtype;
BEGIN
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 SELECT * INTO v_primary FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
   AND a.allocation_role='responsible' AND a.state='active'
   AND a.assignee_membership_id IS NULL AND a.assignee_canonical_person_id IS NOT NULL
   AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text;
 SELECT * INTO v_part FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
   AND a.allocation_role='participant' AND a.state='active'
   AND a.assignee_canonical_person_id=v_actor AND a.assignee_membership_id IS NULL
   AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
   AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_original_work_self_participation_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,'personId',v_actor,
   'participantAllocationId',v_part.id,'primaryAllocationId',v_primary.id,
   'canJoin',v_primary.id IS NOT NULL AND v_primary.assignee_canonical_person_id<>v_actor
      AND atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,v_primary.assignee_canonical_person_id)
      AND NOT EXISTS (SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=p_work_item_id
         AND a.state='active' AND a.assignee_canonical_person_id=v_actor),
   'canLeave',v_part.id IS NOT NULL);
END
$function$;

-- Release only one's own exact participant allocation. Repeating an already
-- released exact allocation is safe and never releases a subsequent join.
CREATE OR REPLACE FUNCTION atlas.leave_native_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_participant_allocation_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_part atlas.work_allocations%rowtype; v_replay boolean;
BEGIN
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 SELECT * INTO v_part FROM atlas.work_allocations a WHERE a.id=p_participant_allocation_id
   AND a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
   AND a.assignee_canonical_person_id=v_actor AND a.assignee_membership_id IS NULL
   AND a.allocation_role='participant' AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
   AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text AND a.state IN ('active','released') FOR UPDATE;
 IF v_part.id IS NULL THEN RAISE EXCEPTION 'Exact own participant allocation required' USING ERRCODE='42501';END IF;
 v_replay:=v_part.state='released';
 IF NOT v_replay THEN
   UPDATE atlas.work_allocations SET state='released',released_at=now(),updated_at=now(),
     release_reason='Signed Person withdrew their own participation.'
    WHERE id=v_part.id AND state='active' RETURNING * INTO v_part;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_original_work_self_participation_leave_v1',
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
  'personId',v_actor,'allocationId',v_part.id,'allocationRole','participant',
  'allocationState',v_part.state,'idempotent',v_replay,
  'primaryResponsibilityChanged',false,'workCopied',false,'resultRecorded',false);
END
$function$;
REVOKE ALL ON FUNCTION atlas.end_native_self_participation_on_work_terminal_v1(),
 atlas.end_native_self_participation_on_primary_release_v1(),
 atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid),
 atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Internal source only until complete signed clone + participant readback,
-- terminal lifecycle and retired legacy consumer proof. NO public wrapper/grant.
REVOKE ALL ON FUNCTION atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
-- Direct governor assignment follows the existing native intake authority.
-- It establishes a relationship, NOT recipient testimony or acceptance.
CREATE OR REPLACE FUNCTION atlas.owner_change_native_work_participation_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
 p_target_person_id uuid,p_expected_primary_allocation_id uuid,
 p_action text,p_source_action_id uuid,p_expected_participant_allocation_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype;
 v_part atlas.work_allocations%rowtype; v_replay boolean:=false;
BEGIN
 IF p_target_person_id IS NULL OR p_source_action_id IS NULL OR
 p_expected_primary_allocation_id IS NULL OR p_action IS NULL OR p_action NOT IN ('add','remove')
 OR (p_action='add' AND p_expected_participant_allocation_id IS NOT NULL)
 OR (p_action='remove' AND p_expected_participant_allocation_id IS NULL)
 THEN RAISE EXCEPTION 'Exact participation action required' USING ERRCODE='22023';END IF;
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('atlas.company_work.plan:'||p_work_item_id::text,0));
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 IF v_actor=p_target_person_id THEN RAISE EXCEPTION 'Use explicit self participation' USING ERRCODE='22023';END IF;
 SELECT * INTO v_primary FROM atlas.work_allocations a
 WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
 AND a.id=p_expected_primary_allocation_id AND a.state='active' AND a.allocation_role='responsible'
 AND a.assignee_membership_id IS NULL AND a.assignee_canonical_person_id IS NOT NULL
 AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text;
 IF v_primary.id IS NULL OR v_primary.assignee_canonical_person_id=p_target_person_id
 THEN RAISE EXCEPTION 'Exact current primary required; not a replacement' USING ERRCODE='40001';END IF;
 IF p_action='add' THEN
   IF NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,p_target_person_id)
   OR NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,v_primary.assignee_canonical_person_id)
   THEN RAISE EXCEPTION 'Current exact native Ledger connections required' USING ERRCODE='42501';END IF;
   SELECT * INTO v_part FROM atlas.work_allocations a
    WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
      AND a.establishment_basis_kind='native_person_direct_participation_v1'
      AND a.establishment_basis->>'actorPersonId'=v_actor::text
      AND a.establishment_basis->>'sourceActionId'=p_source_action_id::text;
   IF v_part.id IS NOT NULL THEN
     IF v_part.state<>'active' OR v_part.assignee_canonical_person_id<>p_target_person_id
       OR v_part.establishment_basis->>'nativeLedgerId' IS DISTINCT FROM p_ledger_id::text
       OR v_part.establishment_basis->>'primaryAllocationId' IS DISTINCT FROM v_primary.id::text
     THEN RAISE EXCEPTION 'Action no longer matches exact current participation' USING ERRCODE='23505';END IF;
     v_replay:=true;
   ELSE
     IF EXISTS(SELECT 1 FROM atlas.work_allocations a WHERE a.work_item_id=p_work_item_id
       AND a.state='active' AND a.assignee_canonical_person_id=p_target_person_id)
     THEN RAISE EXCEPTION 'Person already carries this original' USING ERRCODE='23505';END IF;
     INSERT INTO atlas.work_allocations(organization_id,work_item_id,assignee_canonical_person_id,
       allocation_role,state,establishment_basis_kind,establishment_basis,metadata)
     VALUES(p_organization_id,p_work_item_id,p_target_person_id,'participant','active','native_person_direct_participation_v1',
       jsonb_build_object('contractVersion','native_person_direct_participation_v1','organizationId',p_organization_id,
       'nativeLedgerId',p_ledger_id,'workItemId',p_work_item_id,'actorPersonId',v_actor,
       'targetPersonId',p_target_person_id,'primaryAllocationId',v_primary.id,'sourceActionId',p_source_action_id),
       jsonb_build_object('source','owner_change_native_work_participation_self_api_v1',
       'recipientAttested',false)) RETURNING * INTO v_part;
   END IF;
 ELSE
   SELECT * INTO v_part FROM atlas.work_allocations a WHERE a.id=p_expected_participant_allocation_id
    AND a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
    AND a.assignee_canonical_person_id=p_target_person_id AND a.assignee_membership_id IS NULL
    AND a.allocation_role='participant' AND a.state IN ('active','released')
    AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
    AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
    AND a.establishment_basis->>'primaryAllocationId'=v_primary.id::text FOR UPDATE;
   IF v_part.id IS NULL THEN RAISE EXCEPTION 'Exact participant allocation required' USING ERRCODE='42501';END IF;
   v_replay:=v_part.state='released';
   IF NOT v_replay THEN
     UPDATE atlas.work_allocations SET state='released',released_at=now(),updated_at=now(),
       release_reason='Ledger governor removed this participation.',
       metadata=metadata||jsonb_build_object('releasedByPersonId',v_actor,'releaseActionId',p_source_action_id)
       WHERE id=v_part.id AND state='active' RETURNING * INTO v_part;
   END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_work_participation_change_v1',
  'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
  'actorPersonId',v_actor,'targetPersonId',p_target_person_id,'primaryAllocationId',v_primary.id,
  'allocationId',v_part.id,'allocationRole','participant','allocationState',v_part.state,
  'action',p_action,'idempotent',v_replay,'recipientAttested',false,'primaryResponsibilityChanged',false,
  'workCopied',false,'resultRecorded',false);
END
$function$;
CREATE UNIQUE INDEX native_direct_participation_actor_action_v1 ON atlas.work_allocations
 (work_item_id,(establishment_basis->>'actorPersonId'),(establishment_basis->>'sourceActionId'))
 WHERE establishment_basis_kind='native_person_direct_participation_v1';

CREATE OR REPLACE FUNCTION atlas.owner_native_work_participation_roster_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_items jsonb;
BEGIN
 v_actor:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 SELECT * INTO v_primary FROM atlas.work_allocations a WHERE a.organization_id=p_organization_id
 AND a.work_item_id=p_work_item_id AND a.state='active' AND a.allocation_role='responsible'
 AND a.assignee_membership_id IS NULL AND a.assignee_canonical_person_id IS NOT NULL
 AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text;
 IF v_primary.id IS NULL THEN RAISE EXCEPTION 'Native primary required' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('personId',a.assignee_canonical_person_id,
  'allocationId',a.id) ORDER BY a.id),'[]'::jsonb) INTO v_items
 FROM atlas.work_allocations a WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
 AND a.state='active' AND a.allocation_role='participant' AND a.assignee_membership_id IS NULL
 AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
 AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
 AND a.establishment_basis->>'primaryAllocationId'=v_primary.id::text;
 RETURN jsonb_build_object('ok',true,'contractVersion','native_work_participation_roster_v1',
 'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
 'actorPersonId',v_actor,'primaryAllocationId',v_primary.id,'primaryPersonId',v_primary.assignee_canonical_person_id,
 'items',v_items);
END
$function$;
REVOKE ALL ON FUNCTION atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid),
 atlas.owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;

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

-- SOURCE CANDIDATE ONLY. Not an authorized Production migration.
-- One original Work; ordinary coordination ink is not Work Result,
-- delivery, assignment, acceptance, or a second Work item.

CREATE TABLE IF NOT EXISTS atlas.native_original_work_comments_v1 (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  organization_id uuid NOT NULL,
  ledger_id uuid NOT NULL,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  author_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  source_action_id uuid NOT NULL,
  body text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT native_original_work_comment_replay_v1
    UNIQUE (organization_id, work_item_id, author_person_id, source_action_id)
);
CREATE INDEX IF NOT EXISTS native_original_work_comments_scope_order_v1
  ON atlas.native_original_work_comments_v1 (
    organization_id, ledger_id, work_item_id, recorded_at, id
  );
ALTER TABLE atlas.native_original_work_comments_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.native_original_work_comments_v1
  FROM PUBLIC, anon, authenticated, service_role;

-- This is not a membership/seat grant. It admits an exact original Work
-- only after independent current native Ledger relevance, auth identity
-- and the Person's own Work or true native Ledger root responsibility.
CREATE OR REPLACE FUNCTION atlas.native_original_work_comment_actor_v1(
  p_organization_id uuid, p_ledger_id uuid, p_work_item_id uuid,
  p_write boolean
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_person uuid;
  v_access jsonb;
  v_work atlas.work_items%rowtype;
  v_root boolean := false;
  v_person_work boolean := false;
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL
     OR p_ledger_id IS NULL OR p_work_item_id IS NULL THEN
    RAISE EXCEPTION 'Signed exact original Work required' USING ERRCODE='42501';
  END IF;
  v_access := atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Current signed Personal Atlas required' USING ERRCODE='42501';
  END IF;
  v_person := atlas.current_person_id_v1();
  IF v_person IS NULL THEN
    RAISE EXCEPTION 'Current canonical Person required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_work FROM atlas.work_items w
  WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id;
  IF v_work.id IS NULL OR v_work.household_id IS NOT NULL
     OR v_work.work_state NOT IN ('open','completed')
     OR (p_write AND v_work.work_state<>'open') THEN
    RAISE EXCEPTION 'Active source Work unavailable' USING ERRCODE='42501';
  END IF;
  -- Work may be displayed in several notebooks, but only one exact native
  -- Ledger source may admit THIS request; avoid a title/date-derived guess.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance r
    WHERE r.organization_id=p_organization_id
      AND r.ledger_id=p_ledger_id AND r.work_item_id=p_work_item_id
      AND r.attribution_state='active'
      AND (
        r.evidence_kind IN ('owner_attested','participant_attested')
        OR (r.evidence_kind='source_verified' AND EXISTS (
          SELECT 1 FROM atlas.company_work_native_ledger_exact_source_v1(
            r.work_item_id,r.ledger_id
          ) e
          WHERE e.source_schema=r.source_schema
            AND e.source_table=r.source_table AND e.source_id=r.source_id
        ))
      )
  ) THEN
    RAISE EXCEPTION 'Source-bound Ledger Work required' USING ERRCODE='42501';
  END IF;

  BEGIN
    v_root := coalesce(atlas.company_work_native_ledger_owner_self_v1(
      p_organization_id,p_ledger_id
    ) = v_person,false);
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_root := false;
  END;
  IF v_root IS NOT TRUE THEN
    IF atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_person
    ) IS NOT TRUE OR atlas.person_original_work_identity_disclosed_self_v1(
      p_organization_id,p_ledger_id,p_work_item_id,v_person
    ) IS NOT TRUE THEN
      RAISE EXCEPTION 'Work identity not disclosed to current Person'
        USING ERRCODE='42501';
    END IF;
    -- A Work-linked Event's identity must independently be disclosed.
    -- A Work assignment alone does not disclose an unrelated Event.
    IF EXISTS (
      SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=p_organization_id
        AND c.work_item_id=p_work_item_id
        AND c.subject_domain='temporal' AND c.subject_kind='occurrence'
        AND atlas.has_current_subject_disclosure_v1(
          p_ledger_id,v_person,'event','occurrence',c.subject_id,'identity'
        ) IS DISTINCT FROM TRUE
    ) THEN
      RAISE EXCEPTION 'Event identity not disclosed to current Person'
        USING ERRCODE='42501';
    END IF;
    -- Other subject-context families are not classified for comment-body
    -- disclosure in this v1. Deny instead of extrapolating from a Work title.
    IF EXISTS (
      SELECT 1 FROM atlas.work_item_context_links c
      WHERE c.organization_id=p_organization_id
        AND c.work_item_id=p_work_item_id
        AND NOT (
          (c.subject_domain='spatial' AND c.subject_kind='growing_object')
          OR (c.subject_domain='temporal' AND c.subject_kind='occurrence')
        )
    ) THEN
      RAISE EXCEPTION 'Additional subject disclosure still held'
        USING ERRCODE='42501';
    END IF;
    SELECT EXISTS (
      SELECT 1 FROM atlas.work_allocations a
      WHERE a.organization_id=p_organization_id
        AND a.work_item_id=p_work_item_id
        AND a.allocation_role='responsible'
        AND a.assignee_canonical_person_id=v_person
        AND a.assignee_membership_id IS NULL
        AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
        AND a.establishment_basis_kind IN (
          'person_connection_receiver_uptake',
          'delegated_under_standing_scope',
          'ledger_connection_direct_assignment',
          'original_subject_direct_assignment_v1'
        )
        AND (a.state='active'
          OR (NOT p_write AND a.state='completed'
              AND v_work.work_state='completed'))
    ) INTO v_person_work;
    -- Current canonical allocated participation, never an employee requirement.
    IF NOT v_person_work THEN
      SELECT EXISTS(
        SELECT 1 FROM atlas.work_allocations a
        JOIN atlas.work_allocations primary_carrier ON primary_carrier.id::text=a.establishment_basis->>'primaryAllocationId'
          AND primary_carrier.organization_id=a.organization_id AND primary_carrier.work_item_id=a.work_item_id
          AND primary_carrier.state='active' AND primary_carrier.allocation_role='responsible'
          AND primary_carrier.assignee_membership_id IS NULL
          AND primary_carrier.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
        WHERE a.organization_id=p_organization_id AND a.work_item_id=p_work_item_id
          AND a.state='active' AND a.allocation_role='participant'
          AND a.assignee_canonical_person_id=v_person AND a.assignee_membership_id IS NULL
          AND a.establishment_basis_kind IN ('native_person_self_participation_v1','native_person_direct_participation_v1')
          AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
          AND primary_carrier.assignee_canonical_person_id<>v_person
          AND atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,primary_carrier.assignee_canonical_person_id)
      ) INTO v_person_work;
    END IF;
    -- Historical membership or receiver-acceptance rows confer no new comment access.
    IF NOT v_person_work THEN
      RAISE EXCEPTION 'Exact Work responsibility or accepted participation required'
        USING ERRCODE='42501';
    END IF;
  END IF;
  RETURN v_person;
END
$function$;
REVOKE ALL ON FUNCTION atlas.native_original_work_comment_actor_v1(
  uuid,uuid,uuid,boolean
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.append_native_original_work_comment_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_source_action_id uuid,p_body text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_body text := btrim(coalesce(p_body,''));
  v_comment atlas.native_original_work_comments_v1%rowtype;
BEGIN
  IF p_source_action_id IS NULL OR length(v_body) NOT BETWEEN 1 AND 2000 THEN
    RAISE EXCEPTION 'Bounded body and stable action ID required'
      USING ERRCODE='22023';
  END IF;
  -- A genuine same-action replay remains verifiable after an unrelated
  -- actor completes Work. Read access remains independently authorized;
  -- a new write still requires the Work to be open at its own locked point.
  v_actor := atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,false
  );
  SELECT * INTO v_comment FROM atlas.native_original_work_comments_v1 c
  WHERE c.organization_id=p_organization_id
    AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
    AND c.author_person_id=v_actor AND c.source_action_id=p_source_action_id;
  IF v_comment.id IS NOT NULL THEN
    IF v_comment.body<>v_body THEN
      RAISE EXCEPTION 'Idempotency action cannot change authored body'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_comment_write_v1',
      'organizationId',p_organization_id,'ledgerId',p_ledger_id,
      'workItemId',p_work_item_id,'commentId',v_comment.id,
      'recordedAt',v_comment.recorded_at,'body',v_comment.body,
      'idempotent',true,'originalWorkStateUnchanged',true,
      'isWorkResult',false,'notificationDelivered',false
    );
  END IF;
  -- The original must still be open. Never append new ink using historical
  -- permission from a completed or retired responsibility allocation.
  PERFORM 1 FROM atlas.work_items w WHERE w.id=p_work_item_id
    AND w.organization_id=p_organization_id AND w.work_state='open'
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Original Work no longer open' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,true
  );
  INSERT INTO atlas.native_original_work_comments_v1(
    organization_id,ledger_id,work_item_id,author_person_id,source_action_id,body
  ) VALUES(
    p_organization_id,p_ledger_id,p_work_item_id,v_actor,p_source_action_id,v_body
  )
  ON CONFLICT ON CONSTRAINT native_original_work_comment_replay_v1 DO NOTHING
  RETURNING * INTO v_comment;
  IF v_comment.id IS NULL THEN
    SELECT * INTO v_comment FROM atlas.native_original_work_comments_v1 c
    WHERE c.organization_id=p_organization_id
      AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
      AND c.author_person_id=v_actor AND c.source_action_id=p_source_action_id;
    IF v_comment.id IS NULL OR v_comment.body<>v_body THEN
      RAISE EXCEPTION 'Concurrent idempotency identity collision'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','native_original_work_comment_write_v1',
      'organizationId',p_organization_id,'ledgerId',p_ledger_id,
      'workItemId',p_work_item_id,'commentId',v_comment.id,
      'recordedAt',v_comment.recorded_at,'body',v_comment.body,
      'idempotent',true,'originalWorkStateUnchanged',true,
      'isWorkResult',false,'notificationDelivered',false
    );
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_comment_write_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'commentId',v_comment.id,
    'recordedAt',v_comment.recorded_at,'body',v_comment.body,
    'idempotent',false,'originalWorkStateUnchanged',true,
    'isWorkResult',false,'notificationDelivered',false
  );
END
$function$;
REVOKE ALL ON FUNCTION atlas.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION atlas.read_native_original_work_comments_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 40,
  p_after_recorded_at timestamptz DEFAULT NULL,
  p_after_comment_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_items jsonb := '[]'::jsonb;
  v_more boolean := false;
  v_next_at timestamptz;
  v_next_id uuid;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 OR
    (p_after_recorded_at IS NULL)<>(p_after_comment_id IS NULL) THEN
    RAISE EXCEPTION 'Bounded page and complete cursor required'
      USING ERRCODE='22023';
  END IF;
  v_actor := atlas.native_original_work_comment_actor_v1(
    p_organization_id,p_ledger_id,p_work_item_id,false
  );
  WITH bounded AS (
    SELECT c.id,c.recorded_at,c.body,c.author_person_id
    FROM atlas.native_original_work_comments_v1 c
    WHERE c.organization_id=p_organization_id
      AND c.ledger_id=p_ledger_id AND c.work_item_id=p_work_item_id
      AND (p_after_recorded_at IS NULL OR
           (c.recorded_at,c.id)<(p_after_recorded_at,p_after_comment_id))
    ORDER BY c.recorded_at DESC,c.id DESC LIMIT p_limit+1
  ), numbered AS (
    SELECT b.*,row_number() OVER (ORDER BY b.recorded_at DESC,b.id DESC) AS rn
    FROM bounded b
  )
  SELECT
    coalesce(jsonb_agg(jsonb_build_object(
      'commentId',s.id,'workItemId',p_work_item_id,'body',s.body,
      'recordedAt',s.recorded_at,'authoredBySelf',s.author_person_id=v_actor
    ) ORDER BY s.recorded_at DESC,s.id DESC) FILTER(WHERE s.rn<=p_limit),'[]'::jsonb),
    count(*)>p_limit,
    (array_agg(s.recorded_at ORDER BY s.rn)
      FILTER(WHERE s.rn=p_limit))[1],
    (array_agg(s.id ORDER BY s.rn)
      FILTER(WHERE s.rn=p_limit))[1]
  INTO v_items,v_more,v_next_at,v_next_id FROM numbered s;
  RETURN jsonb_build_object(
    'ok',true,'contractVersion','native_original_work_comments_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'workItemId',p_work_item_id,'items',v_items,
    'hasMore',coalesce(v_more,false),
    'nextRecordedAt',CASE WHEN v_more THEN v_next_at ELSE NULL END,
    'nextCommentId',CASE WHEN v_more THEN v_next_id ELSE NULL END,
    'containsWorkResults',false,'isNotificationInbox',false,
    'authorsPreservedInCanonicalSource',true,
    'authorIdentityDisclosure','self_boolean_only'
  );
END
$function$;
REVOKE ALL ON FUNCTION atlas.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) FROM PUBLIC, anon, authenticated, service_role;

-- Public RPCs are the ONLY browser entrypoints. Browser roles cannot read
-- private table or invoke the internal authorization function directly.
CREATE OR REPLACE FUNCTION public.append_native_original_work_comment_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_source_action_id uuid,p_body text
) RETURNS jsonb
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $wrapper$
  SELECT atlas.append_native_original_work_comment_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_source_action_id,p_body);
$wrapper$;
REVOKE ALL ON FUNCTION public.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.append_native_original_work_comment_self_api_v1(
  uuid,uuid,uuid,uuid,text
) TO authenticated;

CREATE OR REPLACE FUNCTION public.read_native_original_work_comments_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,
  p_limit integer DEFAULT 40,
  p_after_recorded_at timestamptz DEFAULT NULL,
  p_after_comment_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $wrapper$
  SELECT atlas.read_native_original_work_comments_self_api_v1(
    p_organization_id,p_ledger_id,p_work_item_id,p_limit,
    p_after_recorded_at,p_after_comment_id);
$wrapper$;
REVOKE ALL ON FUNCTION public.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.read_native_original_work_comments_self_api_v1(
  uuid,uuid,uuid,integer,timestamptz,uuid
) TO authenticated;

-- Even a privileged adapter may not silently rewrite the originally
-- authored comment. Corrections require a separate explicitly governed event.
CREATE OR REPLACE FUNCTION atlas.reject_native_original_work_comment_mutation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
  RAISE EXCEPTION 'Original Work comments are immutable; append a correction'
    USING ERRCODE='42501';
END
$function$;
REVOKE ALL ON FUNCTION atlas.reject_native_original_work_comment_mutation_v1()
  FROM PUBLIC,anon,authenticated,service_role;
DROP TRIGGER IF EXISTS reject_native_original_work_comment_mutation_v1
  ON atlas.native_original_work_comments_v1;
CREATE TRIGGER reject_native_original_work_comment_mutation_v1
  BEFORE UPDATE OR DELETE ON atlas.native_original_work_comments_v1
  FOR EACH ROW EXECUTE FUNCTION atlas.reject_native_original_work_comment_mutation_v1();

COMMIT;
