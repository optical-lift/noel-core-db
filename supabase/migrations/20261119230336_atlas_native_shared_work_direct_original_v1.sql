BEGIN;
-- Refuse drift from the already released shared Work source. No legacy admission
-- changes, new tables, grants, copied originals or scope expansion of intake writers.
DO $preimage$
BEGIN
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.guard_work_allocation_participation_establishment_v1()')) IS DISTINCT FROM '03944643831d0e3bd5fc32a9685be14c' THEN RAISE EXCEPTION 'Pinned original source differs: guard_work_allocation_participation_establishment_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.join_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)')) IS DISTINCT FROM '5d661a5c45a708ee26a640fd7f885436' THEN RAISE EXCEPTION 'Pinned original source differs: join_native_original_work_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.native_original_work_self_participation_self_api_v1(uuid,uuid,uuid)')) IS DISTINCT FROM 'cf4a73412533201819a7fc2001f56612' THEN RAISE EXCEPTION 'Pinned original source differs: native_original_work_self_participation_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.leave_native_original_work_self_api_v1(uuid,uuid,uuid,uuid)')) IS DISTINCT FROM 'e97f72d27d71505b47434271fa8345e9' THEN RAISE EXCEPTION 'Pinned original source differs: leave_native_original_work_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.owner_change_native_work_participation_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid,uuid)')) IS DISTINCT FROM 'f64e26569a154476038eb93e044b1b1e' THEN RAISE EXCEPTION 'Pinned original source differs: owner_change_native_work_participation_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.owner_native_work_participation_roster_self_api_v1(uuid,uuid,uuid)')) IS DISTINCT FROM 'ce1c786a80d555b8a8660c0ea593008f' THEN RAISE EXCEPTION 'Pinned original source differs: owner_native_work_participation_roster_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.native_intake_responsibility_owner_context_v1(uuid,uuid,uuid)')) IS DISTINCT FROM '06be4722570129e02f2ba96bb07c1a21' THEN RAISE EXCEPTION 'Pinned original source differs: native_intake_responsibility_owner_context_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)')) IS DISTINCT FROM '18d75444286f5fd33aa8d28b5ae4d645' THEN RAISE EXCEPTION 'Pinned original source differs: owner_set_connected_person_work_day_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)')) IS DISTINCT FROM 'a7bc5d132c73adc927bb09bedbfb8b8f' THEN RAISE EXCEPTION 'Pinned original source differs: work_focus_owner_reassign_direct_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid)')) IS DISTINCT FROM '08cc9cfd306ecb71563ea1eab8e87695' THEN RAISE EXCEPTION 'Pinned original source differs: work_focus_owner_reassignment_preflight_self_api_v1'; END IF;
 IF (SELECT md5(prosrc) FROM pg_proc WHERE oid=to_regprocedure('atlas.guard_work_allocation_responsibility_establishment_v2()')) IS DISTINCT FROM '411b87c710cee0e49ddbae84bf95e3f2' THEN RAISE EXCEPTION 'Pinned original source differs: guard_work_allocation_responsibility_establishment_v2'; END IF;
END
$preimage$;

-- An ordinary original can originate through intake OR the already released
-- canonical direct Ledger assignment. Do not generalize intake assignment/date
-- authority; this internal resolver is only for existing participation.
CREATE FUNCTION atlas.native_original_work_participation_owner_context_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS uuid LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path TO ''
AS $function$
DECLARE v_actor uuid;
BEGIN
 IF EXISTS (SELECT 1 FROM atlas.work_items w WHERE w.id=p_work_item_id
    AND w.organization_id=p_organization_id AND w.source_object_type='ledger_work_intake') THEN
   RETURN atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 END IF;

 v_actor:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF v_actor IS NULL
 OR NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,v_actor)
 OR NOT EXISTS (
   SELECT 1 FROM atlas.work_items w
   JOIN atlas.company_work_native_ledger_relevance rel
     ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
     AND rel.ledger_id=p_ledger_id AND rel.attribution_state='active'
     AND rel.evidence_kind='participant_attested'
     AND rel.established_by_person_id::text=w.metadata->>'createdByPersonId'
     AND rel.attestation_source_ref='atlas.work_items:'||w.id::text
   JOIN atlas.work_allocations a
     ON a.work_item_id=w.id AND a.organization_id=w.organization_id
     AND a.state='active' AND a.allocation_role='responsible'
     AND a.assignee_membership_id IS NULL AND a.assigned_by_membership_id IS NULL
     AND a.assignee_canonical_person_id IS NOT NULL
     AND a.establishment_basis_kind='ledger_connection_direct_assignment'
     AND a.metadata->>'source'='ledger_connected_direct_assignment_v1'
     AND a.establishment_basis->>'contractVersion'='exact_work_responsibility_establishment_v2'
     AND a.establishment_basis->>'basisKind'='ledger_connection_direct_assignment'
     AND a.establishment_basis->>'organizationId'=w.organization_id::text
     AND a.establishment_basis->>'workItemId'=w.id::text
     AND a.establishment_basis->>'nativeLedgerId'=p_ledger_id::text
     AND a.establishment_basis->>'senderPersonId'=w.metadata->>'createdByPersonId'
     AND a.establishment_basis->>'assigneePersonId'=a.assignee_canonical_person_id::text
     AND a.assignee_canonical_person_id::text=w.metadata->>'recipientPersonId'
     AND a.establishment_basis->>'authorizationBasis'='active_mutual_native_ledger_connections'
   WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
     AND w.work_state='open' AND w.source_object_type='ledger_connected_direct_task'
     AND w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
     AND w.metadata->>'nativeLedgerId'=p_ledger_id::text
     AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
     AND atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,a.assignee_canonical_person_id)
     AND EXISTS (SELECT 1 FROM atlas.company_work_result_contract_bindings_v1 b
       WHERE b.work_item_id=w.id AND b.organization_id=w.organization_id
       AND b.ledger_id=p_ledger_id AND b.actor_person_id=rel.established_by_person_id
       AND b.actor_membership_id IS NULL AND b.contract_key=w.result_contract_key)
     AND EXISTS (SELECT 1 FROM atlas.work_result_contract_policies policy
       WHERE policy.contract_key=w.result_contract_key AND policy.active
       AND policy.source_domain='organization' AND policy.acceptance_mode='worker_attestation')
 ) THEN RAISE EXCEPTION 'Exact active ordinary directly assigned original or accepted intake required' USING ERRCODE='42501'; END IF;
 RETURN v_actor;
END
$function$;
REVOKE ALL ON FUNCTION atlas.native_original_work_participation_owner_context_v1(uuid,uuid,uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Each body below is the exact released definition except for the internal
-- participation-context resolver name. ACL and existing public wrappers remain.
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
      or atlas.native_original_work_participation_owner_context_v1(
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

CREATE OR REPLACE FUNCTION atlas.join_native_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_source_action_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_part atlas.work_allocations%rowtype;
 v_replay boolean:=false;
BEGIN
 IF p_source_action_id IS NULL THEN RAISE EXCEPTION 'Stable action ID required' USING ERRCODE='22023'; END IF;
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
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

CREATE OR REPLACE FUNCTION atlas.native_original_work_self_participation_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_part atlas.work_allocations%rowtype;
BEGIN
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
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

CREATE OR REPLACE FUNCTION atlas.leave_native_original_work_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_participant_allocation_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_part atlas.work_allocations%rowtype; v_replay boolean;
BEGIN
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
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
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('atlas.company_work.plan:'||p_work_item_id::text,0));
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
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

CREATE OR REPLACE FUNCTION atlas.owner_native_work_participation_roster_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_actor uuid; v_primary atlas.work_allocations%rowtype; v_items jsonb;
BEGIN
 v_actor:=atlas.native_original_work_participation_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
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
COMMIT;
