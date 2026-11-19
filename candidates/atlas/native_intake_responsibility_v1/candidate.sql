BEGIN;
-- HELD source only. Abort on drift rather than overwrite any later allocation guard.
DO $check$ BEGIN
 IF md5(pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure)) <> '34df2d47eadfe04f02fe9beadd5a4d30'
 THEN RAISE EXCEPTION 'Current allocation guard differs from reviewed baseline';END IF;
 IF to_regprocedure('public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid)') IS NOT NULL
 OR to_regprocedure('public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid)') IS NOT NULL
 THEN RAISE EXCEPTION 'Responsibility contract already exists; reconcile first';END IF;
END $check$;
CREATE OR REPLACE FUNCTION atlas.native_intake_responsibility_owner_context_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_owner uuid;
BEGIN
 v_owner:=atlas.company_work_native_ledger_owner_self_v1(p_organization_id,p_ledger_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,v_owner)
 OR NOT EXISTS(
   SELECT 1 FROM atlas.work_items w
   JOIN atlas.ledger_work_intakes i ON i.id=w.source_object_id
    AND i.work_item_id=w.id AND i.organization_id=w.organization_id
    AND i.ledger_id=p_ledger_id AND i.review_state='accepted_for_ledger'
   JOIN atlas.company_work_native_ledger_relevance rel
    ON rel.work_item_id=w.id AND rel.organization_id=w.organization_id
    AND rel.ledger_id=i.ledger_id AND rel.attribution_state='active'
    AND rel.evidence_kind='participant_attested'
    AND rel.established_by_person_id=i.submitted_by_person_id
   WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
    AND w.work_state='open' AND w.source_object_type='ledger_work_intake'
    AND w.metadata->>'sourceContract'='ledger_work_intake_v1'
    AND w.result_contract_key='ordinary_company_work_worker_attestation_v1'
    AND EXISTS(SELECT 1 FROM atlas.work_result_contract_policies policy
      WHERE policy.contract_key=w.result_contract_key AND policy.active
      AND policy.source_domain='organization' AND policy.acceptance_mode='worker_attestation')
 ) THEN RAISE EXCEPTION 'Exact accepted ordinary native Ledger intake required' USING ERRCODE='42501';END IF;
 RETURN v_owner;
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.native_intake_responsibility_owner_context_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_source text:=coalesce(new.metadata->>'source','');
  v_requires_basis boolean:=false;
  v_kind text:=lower(btrim(coalesce(new.establishment_basis_kind,'')));
  v_basis jsonb:=new.establishment_basis;
begin
  if tg_op='UPDATE' then
    if new.establishment_basis_kind is distinct from old.establishment_basis_kind
       or new.establishment_basis is distinct from old.establishment_basis then
      raise exception 'Exact Work responsibility establishment provenance is immutable once the allocation exists.'
        using errcode='23514';
    end if;
  end if;

  if new.allocation_role<>'responsible' or new.state<>'active' then
    return new;
  end if;

  if tg_op='INSERT' then
    v_requires_basis:=true;
  elsif old.allocation_role is distinct from new.allocation_role
        or old.state is distinct from new.state
        or old.assignee_membership_id is distinct from new.assignee_membership_id then
    v_requires_basis:=true;
  end if;

  -- Existing historical active responsibility can be updated/released without
  -- fabricating a retrospective establishment basis.
  if not v_requires_basis
     and new.establishment_basis_kind is null
     and new.establishment_basis is null then
    return new;
  end if;

  -- Two transitional farm adapters remain live. New rows created by exactly
  -- those named carriers are normalized as governed legacy reconstruction
  -- without changing the adapters or backfilling historical rows.
  if new.establishment_basis_kind is null
     and v_source in (
       'legacy_weekly_harvest_occurrence_assignment',
       'explicit_worker_task_company_work_adoption_v2'
     ) then
    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         nullif(btrim(coalesce(new.metadata->>'plannedOccurrenceId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(new.metadata->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Weekly-harvest reconstruction requires the exact planned-occurrence Work source.'
        using errcode='23514';
    end if;
    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         nullif(btrim(coalesce(new.metadata->>'legacyTaskId','')),'') is null
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(new.metadata->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy-task reconstruction requires the exact legacy-task Work source.'
        using errcode='23514';
    end if;

    new.establishment_basis_kind:='legacy_governed_reconstruction';
    new.establishment_basis:=jsonb_strip_nulls(jsonb_build_object(
      'contractVersion','exact_work_responsibility_establishment_v2',
      'basisKind','legacy_governed_reconstruction',
      'organizationId',new.organization_id,
      'workItemId',new.work_item_id,
      'assigneeMembershipId',new.assignee_membership_id,
      'legacySource',v_source,
      'legacyTaskId',new.metadata->>'legacyTaskId',
      'plannedOccurrenceId',new.metadata->>'plannedOccurrenceId',
      'normalizedAt',now()
    ));
    v_kind:=new.establishment_basis_kind;
    v_basis:=new.establishment_basis;
  end if;

  if new.establishment_basis_kind is null
     or new.establishment_basis is null
     or jsonb_typeof(new.establishment_basis)<>'object' then
    raise exception 'Active exact Work responsibility requires a governed establishment basis.'
      using errcode='23514';
  end if;

  v_kind:=lower(btrim(new.establishment_basis_kind));
  v_basis:=new.establishment_basis;

  if v_kind not in (
    'self_claim',
    'self_adoption',
    'self_initiated_outbound',
    'delegated_under_standing_scope',
    'legacy_governed_reconstruction',
    'person_connection_receiver_uptake',
    'ledger_connection_direct_assignment',
    'original_subject_direct_assignment_v1'
  ) then
    raise exception 'Unsupported exact Work responsibility establishment basis: %.',v_kind
      using errcode='23514';
  end if;

  -- A Person-native receipt uses the same one-responsible-allocation table.
  -- Its source is an offered exact Work item, with receiver or witnessed
  -- uptake; no Organization Membership or employee classification is invented.

  -- A rooted native Ledger owner may issue an existing, source-bound Event
  -- obligation to another actual Person connected to the same Ledger.
  -- Unlike the legacy Event checklist, this uses the ORIGINAL Company Work ID.
  -- No employee membership, impersonation or synthetic worker assent.
  -- This is direct responsibility for an EXISTING original Work ID, not
  -- ledger_direct_create_work and not a new Company/farm task.
  if v_kind='original_subject_direct_assignment_v1' then
    if v_source<>'original_subject_direct_assignment_v1'
       or new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'decompositionId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_exact_existing_original_work'
    then
      raise exception 'Exact original Work direct responsibility source fields missing'
        using errcode='23514';
    end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
          is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
       or not exists(
         select 1 from atlas.work_decomposition_members m
         join atlas.work_decomposition_groups g on g.id=m.group_id
         join atlas.work_items w on w.id=m.child_work_item_id
         join atlas.company_work_native_ledger_relevance r
           on r.work_item_id=w.id and r.organization_id=w.organization_id
          and r.ledger_id=g.authorized_ledger_id and r.attribution_state='active'
         where m.child_work_item_id=new.work_item_id
           and g.id=(v_basis->>'decompositionId')::uuid
           and g.authorized_ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and w.organization_id=new.organization_id
           and w.work_state='open' and w.source_object_type='work_decomposition'
           and w.metadata->>'originalParentWorkItemId'=g.parent_work_item_id::text
       ) then
       raise exception 'Exact original Work, connection or governing authority unavailable'
         using errcode='23514';
    end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment'
     and v_source='existing_event_work_connected_direct_assignment_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'occurrenceId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>
          'governing_principal_and_active_mutual_ledger_connections'
    then raise exception 'Existing Event obligation lacks exact governing Person, Work, Ledger and Event basis'
      using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.company_work_native_ledger_owner_self_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid)
           is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
           new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
           new.assignee_canonical_person_id)
       or not exists(select 1 from atlas.work_items w
          join atlas.work_item_context_links ctx on ctx.work_item_id=w.id
           and ctx.organization_id=w.organization_id
           and ctx.subject_domain='temporal' and ctx.subject_kind='occurrence'
           and ctx.subject_id=(v_basis->>'occurrenceId')::uuid
          join atlas.company_work_native_ledger_relevance rel
           on rel.work_item_id=w.id and rel.organization_id=w.organization_id
           and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
           and rel.attribution_state='active'
          where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.result_contract_key='ordinary_company_work_worker_attestation_v1'
           and not exists(select 1 from atlas.ledger_occurrence_work_actions_v1 a
            where a.ledger_id=rel.ledger_id
             and a.occurrence_id=ctx.subject_id
             and a.work_item_id=w.id and a.action_kind='removed'))
    then raise exception 'Original Event Work or lawful owner/Person Ledger relationship is unavailable'
      using errcode='23514';end if;
    return new;
  end if;

  -- A reviewed native intake is an existing original, not a direct-create task
  -- or a decomposed Subject. The same canonical Person-native basis is reused.
  if v_kind='ledger_connection_direct_assignment'
     and v_source='native_ledger_intake_responsibility_v1' then
    if new.assignee_membership_id is not null
       or new.assigned_by_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
       or nullif(v_basis->>'nativeLedgerId','') is null
       or nullif(v_basis->>'senderPersonId','') is null
       or nullif(v_basis->>'sourceActionId','') is null
       or coalesce(v_basis->>'authorizationBasis','')<>'governor_accepted_native_intake'
    then raise exception 'Exact accepted-native-intake responsibility provenance required'
      using errcode='23514';end if;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
       or atlas.native_intake_responsibility_owner_context_v1(
          new.organization_id,(v_basis->>'nativeLedgerId')::uuid,new.work_item_id)
          is distinct from (v_basis->>'senderPersonId')::uuid
       or not atlas.person_has_native_ledger_connection_v1(
          new.organization_id,(v_basis->>'nativeLedgerId')::uuid,new.assignee_canonical_person_id)
    then raise exception 'Current exact intake authority and connected recipient required'
      using errcode='42501';end if;
    return new;
  end if;

  if v_kind='ledger_connection_direct_assignment' then
    if new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
      or new.assignee_canonical_person_id is null
      or coalesce(new.metadata->>'source','')<>'ledger_connected_direct_assignment_v1'
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'nativeLedgerId','') is null
      or nullif(v_basis->>'senderPersonId','') is null
      or coalesce(v_basis->>'authorizationBasis','')<>'active_mutual_native_ledger_connections'
    then raise exception 'Connected direct assignment requires exact original Person and Ledger source' using errcode='23514';end if;
    IF NOT EXISTS (SELECT 1 FROM atlas.capability_root_authority_context_self_v1((v_basis->>'nativeLedgerId')::uuid))
    THEN RAISE EXCEPTION 'Exact Ledger root required for connection-direct responsibility' USING errcode='42501';END IF;
    if atlas.current_person_id_v1() is distinct from (v_basis->>'senderPersonId')::uuid
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         (v_basis->>'senderPersonId')::uuid)
      or not atlas.person_has_native_ledger_connection_v1(
         new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
         new.assignee_canonical_person_id)
      or not exists(select 1 from atlas.work_items w
         join atlas.company_work_native_ledger_relevance rel
          on rel.work_item_id=w.id and rel.organization_id=w.organization_id
          and rel.ledger_id=(v_basis->>'nativeLedgerId')::uuid
          and rel.attribution_state='active' and rel.evidence_kind='participant_attested'
         where w.id=new.work_item_id and w.organization_id=new.organization_id
           and w.work_state='open'
           and w.metadata->>'sourceContract'='ledger_connected_direct_assignment_v1'
           and w.metadata->>'createdByPersonId'=v_basis->>'senderPersonId'
           and w.metadata->>'recipientPersonId'=new.assignee_canonical_person_id::text)
    then raise exception 'Connection-direct responsibility has no verified original Person and Ledger' using errcode='23514';end if;
    return new;
  end if;

  if v_kind='person_connection_receiver_uptake' then
    if new.assignee_membership_id is not null
       or new.assignee_canonical_person_id is null
       or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
       or coalesce(v_basis->>'basisKind','')<>v_kind
       or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
       or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
       or coalesce(v_basis->>'targetPersonId','')<>new.assignee_canonical_person_id::text
       or coalesce(v_basis->>'nativeLedgerId','')=''
       or coalesce(v_basis->>'offerId','')=''
       or coalesce(v_basis->>'uptakeKind','') not in ('recipient_self_accepted','owner_witnessed_acceptance')
    then raise exception 'Exact Person-native receiver uptake provenance required' using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_initial_responsibility_offers o
      where o.id::text=v_basis->>'offerId'
        and o.work_item_id=new.work_item_id
        and o.organization_id=new.organization_id
        and o.target_person_id=new.assignee_canonical_person_id
        and o.ledger_id::text=v_basis->>'nativeLedgerId'
        and o.target_membership_id is null
        and o.offer_state in ('offered','accepted')
        and o.offered_by_membership_id is not distinct from new.assigned_by_membership_id
    ) then raise exception 'Person-native responsibility must trace to the exact accepted offer' using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
       new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
       new.assignee_canonical_person_id) then
      raise exception 'Responsible Person native Ledger connection no longer present' using errcode='23514';
    end if;
    if coalesce(v_basis->>'uptakeKind','')='owner_witnessed_acceptance'
      and (length(btrim(coalesce(v_basis->>'receiverConsentEvidence','')))<16
         or coalesce(v_basis->>'witnessPersonId','')='') then
      raise exception 'Owner-witnessed uptake must preserve specific external consent evidence' using errcode='23514';
    end if;
    return new;
  end if;

  -- Native Ledger standing agreement: canonical Person is the assignee,
  -- without invented Organization/employee membership. The original
  -- membership-based delegated branch below remains unchanged.
  if v_kind='delegated_under_standing_scope'
     and new.assignee_canonical_person_id is not null then
    if new.assignee_membership_id is not null
      or (tg_op='INSERT' and new.assigned_by_membership_id is not null)
      or coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
      or coalesce(v_basis->>'basisKind','')<>v_kind
      or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
      or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
      or coalesce(v_basis->>'assigneePersonId','')<>new.assignee_canonical_person_id::text
      or nullif(v_basis->>'scopeId','') is null
      or nullif(v_basis->>'nativeLedgerId','') is null then
       raise exception 'Exact canonical Person standing-scope provenance required'
         using errcode='23514';
    end if;
    if not exists(
      select 1 from atlas.company_work_standing_assignment_scopes s
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=s.organization_id
      -- Native governing authority belongs to the verified Principal,
      -- not an Organization Membership/role label.
      join atlas.principals issuer
        on issuer.person_id=s.proposed_by_person_id
        and issuer.status='active'
      join atlas.principal_ledger_authorities grantor
        on grantor.principal_id=issuer.id and grantor.ledger_id=s.ledger_id
        and grantor.authority_kind='root_governing'
        and grantor.status='active'
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id
        and relevance.organization_id=s.organization_id
        and relevance.ledger_id=s.ledger_id
      where s.id::text=v_basis->>'scopeId'
        and s.proposed_by_person_id=atlas.current_person_id_v1()
        and s.organization_id=new.organization_id
        and s.ledger_id::text=v_basis->>'nativeLedgerId'
        and s.worker_person_id=new.assignee_canonical_person_id
        and s.worker_membership_id is null
        and s.scope_state='active' and s.accepted_at is not null
        and s.accepted_by_person_id=new.assignee_canonical_person_id
        and (s.valid_until is null or s.valid_until>now())
        and (s.coverage_mode='ledger_all_work' OR
          (s.coverage_mode='operation_class' AND
           work.organization_unit_id=s.organization_unit_id AND
           work.operation_class=s.covered_operation_class) OR
          -- Exact-Work is a third source-bound match, never a class/text grant.
          (s.coverage_mode='exact_work' AND
           s.covered_work_item_id IS NOT NULL AND
           s.covered_work_item_id=work.id))
        and work.work_state='open'
        and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(
              work.id,s.ledger_id) proof
            where proof.source_schema=relevance.source_schema
              and proof.source_table=relevance.source_table
              and proof.source_id=relevance.source_id)))
    ) then
      raise exception 'Accepted canonical Person standing scope is not current for exact Work'
         using errcode='23514';
    end if;
    if not atlas.person_has_native_ledger_connection_v1(
      new.organization_id,(v_basis->>'nativeLedgerId')::uuid,
      new.assignee_canonical_person_id) then
      raise exception 'Canonical responsible Person no longer connected to this Ledger'
        using errcode='23514';
    end if;
    return new;
  end if;

  if coalesce(v_basis->>'contractVersion','')<>'exact_work_responsibility_establishment_v2'
     or coalesce(v_basis->>'basisKind','')<>v_kind
     or coalesce(v_basis->>'organizationId','')<>new.organization_id::text
     or coalesce(v_basis->>'workItemId','')<>new.work_item_id::text
     or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
    raise exception 'Responsibility establishment basis does not match the exact allocation.'
      using errcode='23514';
  end if;

  if v_kind in ('self_claim','self_adoption','self_initiated_outbound') then
    if new.assigned_by_membership_id is null
       or new.assigned_by_membership_id is distinct from new.assignee_membership_id then
      raise exception 'Self-established Work responsibility requires actor and assignee to be the same membership.'
        using errcode='23514';
    end if;
    if coalesce(v_basis->>'actorMembershipId','')<>new.assignee_membership_id::text
       or coalesce(v_basis->>'assigneeMembershipId','')<>new.assignee_membership_id::text then
      raise exception 'Self-establishment basis membership provenance does not match the allocation.'
        using errcode='23514';
    end if;
  end if;

  if v_kind='self_claim'
     and (
       nullif(btrim(coalesce(v_basis->>'institutionalConversationId','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'responseCaseId','')),'') is null
     ) then
    raise exception 'Self-claim responsibility requires conversation and response-case provenance.'
      using errcode='23514';
  end if;

  if v_kind='self_adoption'
     and (
       nullif(btrim(coalesce(v_basis->>'sourceKind','')),'') is null
       or nullif(btrim(coalesce(v_basis->>'sourceId','')),'') is null
     ) then
    raise exception 'Self-adopted responsibility requires an exact source kind and source id.'
      using errcode='23514';
  end if;

  if v_kind='self_initiated_outbound'
     and nullif(btrim(coalesce(v_basis->>'outboundOperationId','')),'') is null then
    raise exception 'Self-initiated outbound responsibility requires outbound-operation provenance.'
      using errcode='23514';
  end if;


  if v_kind='delegated_under_standing_scope' then
    if new.assigned_by_membership_id is null
      or new.assigned_by_membership_id=new.assignee_membership_id
      or coalesce(v_basis->>'scopeId','')=''
      or coalesce(v_basis->>'nativeLedgerId','')=''
      or coalesce(v_basis->>'positionId','')=''
      or coalesce(v_basis->>'actorMembershipId','')<>new.assigned_by_membership_id::text
    then
      raise exception 'Delegated assignment requires exact accepted scope and distinct owner authority'
        using errcode='23514';
    end if;
    -- Never retroactively claim a worker consented. Validate the
    -- captured source and current authority when creating responsibility.
    if v_requires_basis and not exists(
      select 1 from atlas.company_work_standing_assignment_scopes scope
      join atlas.organization_memberships worker
        on worker.id=scope.worker_membership_id and worker.organization_id=scope.organization_id
      join atlas.organization_position_appointments appointment
        on appointment.id=scope.position_appointment_id and appointment.organization_membership_id=worker.id
      join atlas.organization_positions pos
        on pos.id=scope.position_id and pos.organization_id=scope.organization_id
      join atlas.work_items work
        on work.id=new.work_item_id and work.organization_id=scope.organization_id
      join atlas.company_work_native_ledger_relevance relevance
        on relevance.work_item_id=work.id and relevance.organization_id=scope.organization_id
      where scope.id::text=v_basis->>'scopeId'
        and scope.scope_state='active' and scope.accepted_at is not null
        and scope.revoked_at is null
        and (scope.valid_until is null or scope.valid_until>now())
        and scope.organization_id=new.organization_id
        and scope.worker_membership_id=new.assignee_membership_id
        and scope.ledger_id::text=v_basis->>'nativeLedgerId'
        and scope.position_id::text=v_basis->>'positionId'
        and scope.position_appointment_id=appointment.id
        and scope.accepted_by_person_id=worker.person_id
        and worker.active
        and atlas.organization_membership_present_effective_at_v1(worker.id,worker.organization_id,now())
        and appointment.status='active' and appointment.ends_at is null
        and pos.status='active' and pos.organization_unit_id=work.organization_unit_id
        and pos.organization_unit_id=scope.organization_unit_id
        and relevance.ledger_id=scope.ledger_id and relevance.attribution_state='active'
        and (relevance.evidence_kind='owner_attested' or
          (relevance.evidence_kind='source_verified' and exists(
            select 1 from atlas.company_work_native_ledger_exact_source_v1(work.id,scope.ledger_id) proof
             where proof.source_schema=relevance.source_schema
               and proof.source_table=relevance.source_table and proof.source_id=relevance.source_id
          )))
        and exists(select 1 from atlas.organization_memberships manager
          where manager.id=new.assigned_by_membership_id
            and manager.organization_id=new.organization_id and manager.active and manager.role='owner')
    ) then
      raise exception 'Accepted exact-Ledger connection agreement cannot be proved for this Work'
        using errcode='23514';
    end if;
  end if;

  if v_kind='legacy_governed_reconstruction' then
    if v_source not in (
         'legacy_weekly_harvest_occurrence_assignment',
         'explicit_worker_task_company_work_adoption_v2'
       )
       or coalesce(v_basis->>'legacySource','')<>v_source then
      raise exception 'Legacy reconstruction basis is limited to the two named transitional carriers.'
        using errcode='23514';
    end if;

    if v_source='legacy_weekly_harvest_occurrence_assignment'
       and (
         coalesce(v_basis->>'plannedOccurrenceId','')<>coalesce(new.metadata->>'plannedOccurrenceId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='planned_work_occurrence'
             and work.source_object_id::text=(v_basis->>'plannedOccurrenceId')
         )
       ) then
      raise exception 'Legacy weekly-harvest responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;

    if v_source='explicit_worker_task_company_work_adoption_v2'
       and (
         coalesce(v_basis->>'legacyTaskId','')<>coalesce(new.metadata->>'legacyTaskId','')
         or not exists(
           select 1
           from atlas.work_items work
           where work.id=new.work_item_id
             and work.organization_id=new.organization_id
             and work.source_object_type='legacy_task'
             and work.source_object_id::text=(v_basis->>'legacyTaskId')
         )
       ) then
      raise exception 'Legacy task responsibility basis does not match the exact Work source.'
        using errcode='23514';
    end if;
  end if;

  new.establishment_basis_kind:=v_kind;
  return new;
end;
$function$;
-- One source-gated preflight and one action; null expected allocation means
-- initial assignment, otherwise compare-and-swap transfer of an existing original.
-- This increment deliberately holds transfers with plans, results or pending offers.
CREATE OR REPLACE FUNCTION atlas.work_focus_owner_reassignment_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_owner uuid; v_old atlas.work_allocations%rowtype; n integer;
BEGIN
 v_owner:=atlas.native_intake_responsibility_owner_context_v1(
   p_organization_id,p_ledger_id,p_work_item_id);
 SELECT count(*) INTO n FROM atlas.work_allocations
  WHERE work_item_id=p_work_item_id AND allocation_role='responsible' AND state='active';
 SELECT * INTO v_old FROM atlas.work_allocations
  WHERE work_item_id=p_work_item_id AND allocation_role='responsible' AND state='active'
  ORDER BY id LIMIT 1;
 IF n>1 OR (n=1 AND (v_old.assignee_canonical_person_id IS NULL
       OR v_old.assignee_membership_id IS NOT NULL
       OR v_old.establishment_basis_kind NOT IN ('person_connection_receiver_uptake','ledger_connection_direct_assignment')
       OR v_old.establishment_basis->>'nativeLedgerId' IS DISTINCT FROM p_ledger_id::text))
 OR EXISTS(SELECT 1 FROM atlas.work_execution_plans WHERE work_item_id=p_work_item_id
      AND plan_state IN ('active','needs_replan'))
 OR EXISTS(SELECT 1 FROM atlas.work_execution_results WHERE work_item_id=p_work_item_id)
 OR EXISTS(SELECT 1 FROM atlas.work_result_acceptances WHERE work_item_id=p_work_item_id)
 OR EXISTS(SELECT 1 FROM atlas.company_work_initial_responsibility_offers
      WHERE work_item_id=p_work_item_id AND offer_state='offered')
 THEN RAISE EXCEPTION 'Existing responsibility, plan, result or offer requires separate reconciliation' USING ERRCODE='23514';END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','canonical_work_direct_reassignment_preflight_v1',
   'organizationId',p_organization_id,'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
   'currentAllocationId',v_old.id,'currentPersonId',v_old.assignee_canonical_person_id,
   'canAssign',n=0,'canReassign',n=1,'governingPersonId',v_owner);
END;
$fn$;
CREATE OR REPLACE FUNCTION atlas.work_focus_owner_reassign_direct_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_expected_allocation_id uuid,
 p_target_person_id uuid,p_reason text,p_source_action_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE v_owner uuid; v_old_id uuid; v_new atlas.work_allocations%rowtype;
 v_check jsonb; v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
BEGIN
 IF p_target_person_id IS NULL OR p_source_action_id IS NULL
 OR v_reason IS NULL OR length(v_reason)>1200
 THEN RAISE EXCEPTION 'Exact target, action and reason required' USING ERRCODE='22023';END IF;
 v_owner:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 IF NOT atlas.person_has_native_ledger_connection_v1(p_organization_id,p_ledger_id,p_target_person_id)
 THEN RAISE EXCEPTION 'Target Person not connected to the exact Ledger' USING ERRCODE='42501';END IF;
 -- Same lock order used by original assignment; retain original row and all historical allocations.
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.company_work.responsibility:'||p_work_item_id::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('atlas.company_work.plan:'||p_work_item_id::text,0));
 PERFORM 1 FROM atlas.work_items WHERE id=p_work_item_id AND organization_id=p_organization_id FOR UPDATE;
 v_owner:=atlas.native_intake_responsibility_owner_context_v1(p_organization_id,p_ledger_id,p_work_item_id);
 SELECT * INTO v_new FROM atlas.work_allocations WHERE work_item_id=p_work_item_id
   AND establishment_basis_kind='ledger_connection_direct_assignment'
   AND metadata->>'source'='native_ledger_intake_responsibility_v1'
   AND establishment_basis->>'sourceActionId'=p_source_action_id::text;
 IF v_new.id IS NOT NULL THEN
   IF v_new.state<>'active' OR v_new.assignee_canonical_person_id IS DISTINCT FROM p_target_person_id
    OR v_new.establishment_basis->>'nativeLedgerId' IS DISTINCT FROM p_ledger_id::text
    OR v_new.establishment_basis->>'senderPersonId' IS DISTINCT FROM v_owner::text
    OR v_new.establishment_basis->>'previousAllocationId' IS DISTINCT FROM p_expected_allocation_id::text
    OR v_new.establishment_basis->>'decisionReason' IS DISTINCT FROM v_reason
   THEN RAISE EXCEPTION 'Action no longer matches current original responsibility' USING ERRCODE='23505';END IF;
 ELSE
   v_check:=atlas.work_focus_owner_reassignment_preflight_self_api_v1(p_organization_id,p_ledger_id,p_work_item_id);
   v_old_id:=(v_check->>'currentAllocationId')::uuid;
   IF v_old_id IS DISTINCT FROM p_expected_allocation_id
   THEN RAISE EXCEPTION 'Responsibility changed; reread the original' USING ERRCODE='40001';END IF;
   IF v_check->>'currentPersonId'=p_target_person_id::text
   THEN RAISE EXCEPTION 'Person already responsible' USING ERRCODE='22023';END IF;
   IF v_old_id IS NOT NULL THEN
     UPDATE atlas.work_allocations SET state='released',released_at=now(),updated_at=now(),release_reason=v_reason
       WHERE id=v_old_id AND state='active' AND work_item_id=p_work_item_id;
     IF NOT FOUND THEN RAISE EXCEPTION 'Stale responsibility' USING ERRCODE='40001';END IF;
   END IF;
   INSERT INTO atlas.work_allocations(organization_id,work_item_id,assignee_canonical_person_id,
       allocation_role,state,allocated_at,establishment_basis_kind,establishment_basis,metadata)
     VALUES(p_organization_id,p_work_item_id,p_target_person_id,'responsible','active',now(),
       'ledger_connection_direct_assignment',
       jsonb_build_object('contractVersion','exact_work_responsibility_establishment_v2',
         'basisKind','ledger_connection_direct_assignment','organizationId',p_organization_id,
         'nativeLedgerId',p_ledger_id,'workItemId',p_work_item_id,'assigneePersonId',p_target_person_id,
         'senderPersonId',v_owner,'sourceActionId',p_source_action_id,'decisionReason',v_reason,
         'previousAllocationId',p_expected_allocation_id,'authorizationBasis','governor_accepted_native_intake'),
       jsonb_build_object('source','native_ledger_intake_responsibility_v1','workerAttestedAsSelf',false))
       RETURNING * INTO v_new;
 END IF;
 RETURN jsonb_build_object('ok',true,'contractVersion','canonical_work_direct_reassignment_v1',
   'workItemId',p_work_item_id,'organizationId',p_organization_id,'ledgerId',p_ledger_id,
   'previousAllocationId',p_expected_allocation_id,'newAllocationId',v_new.id,
   'currentResponsiblePersonId',p_target_person_id,'newWorkCreated',false,'originalWorkPreserved',true,
   'newTaskCreated',false,'workerAttestedAsSelf',false,'planCreated',false);
END;
$fn$;
REVOKE ALL ON FUNCTION atlas.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION atlas.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon,authenticated;
CREATE OR REPLACE FUNCTION public.work_focus_owner_reassignment_preflight_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.work_focus_owner_reassignment_preflight_self_api_v1($1,$2,$3); $fn$;
CREATE OR REPLACE FUNCTION public.work_focus_owner_reassign_direct_self_api_v1(
 p_organization_id uuid,p_ledger_id uuid,p_work_item_id uuid,p_expected_allocation_id uuid,
 p_target_person_id uuid,p_reason text,p_source_action_id uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO ''
AS $fn$ SELECT atlas.work_focus_owner_reassign_direct_self_api_v1($1,$2,$3,$4,$5,$6,$7); $fn$;
REVOKE ALL ON FUNCTION public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.work_focus_owner_reassignment_preflight_self_api_v1(uuid,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.work_focus_owner_reassign_direct_self_api_v1(uuid,uuid,uuid,uuid,uuid,text,uuid) TO authenticated;
COMMIT;
