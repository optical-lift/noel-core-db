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
       'native_person_self_participation_v1'
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
   AND establishment_basis_kind='native_person_self_participation_v1';
CREATE UNIQUE INDEX native_self_participation_action_v1 ON atlas.work_allocations
 (work_item_id,assignee_canonical_person_id,(establishment_basis->>'sourceActionId'))
 WHERE establishment_basis_kind='native_person_self_participation_v1';
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
      and new.establishment_basis_kind='native_person_self_participation_v1' then
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
$function$
;
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

  if new.establishment_basis_kind='native_person_self_participation_v1' then
    if new.allocation_role<>'participant'
      or new.assignee_membership_id is not null
      or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or jsonb_typeof(new.establishment_basis) is distinct from 'object'
      or new.establishment_basis->>'contractVersion' is distinct from 'native_person_self_participation_v1'
      or new.establishment_basis->>'workItemId' is distinct from new.work_item_id::text
      or new.establishment_basis->>'organizationId' is distinct from new.organization_id::text
      or new.establishment_basis->>'actorPersonId' is distinct from new.assignee_canonical_person_id::text
      or coalesce(new.establishment_basis->>'sourceActionId','') !~ '^[0-9a-fA-F-]{36}
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
      or coalesce(new.establishment_basis->>'primaryAllocationId','') !~ '^[0-9a-fA-F-]{36}
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
      or coalesce(new.establishment_basis->>'nativeLedgerId','') !~ '^[0-9a-fA-F-]{36}
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
      or atlas.native_intake_responsibility_owner_context_v1(
        new.organization_id,(new.establishment_basis->>'nativeLedgerId')::uuid,
        new.work_item_id) is distinct from new.assignee_canonical_person_id
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
AS $fn$
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
$fn$;

-- Internal source only until complete signed clone + participant readback,
-- terminal lifecycle and retired legacy consumer proof. NO public wrapper/grant.
REVOKE ALL ON FUNCTION atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
