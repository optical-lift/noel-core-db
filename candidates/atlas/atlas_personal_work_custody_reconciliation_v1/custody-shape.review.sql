-- HELD structural review, NOT a migration or independently releasable candidate.
-- No new writer, caller, grant, production record, or alternate engine.
-- Review in a disposable production-shaped clone only after the normal protected admission.
-- Deliberate ROLLBACK: a partial custody shape must never become the live contract.
BEGIN;

-- Exact existing binary-custody constraints are the source of this correction.
DO $preflight$
DECLARE relation_name text; actual text;
BEGIN
 FOREACH relation_name IN ARRAY ARRAY['work_items','work_allocations','work_execution_plans','work_execution_plan_events','work_execution_results','work_result_acceptances','work_item_context_links','work_time_contracts'] LOOP
   SELECT pg_get_constraintdef(c.oid) INTO actual
   FROM pg_constraint c WHERE c.conrelid=to_regclass('atlas.'||relation_name)
      AND c.conname=relation_name||'_one_native_custody_v1';
   IF actual IS DISTINCT FROM 'CHECK (((organization_id IS NULL) <> (household_id IS NULL)))' THEN
     RAISE EXCEPTION 'Existing custody contract changed: %',relation_name;
   END IF;
 END LOOP;
END;
$preflight$;

-- Existing Principal, no invented Household, Organization, membership or Ledger.
-- Existing Organization/Household rows retain their exact original source fields.
ALTER TABLE atlas.work_items
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_items_one_native_custody_v1,
 ADD CONSTRAINT work_items_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_allocations
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_allocations_one_native_custody_v1,
 ADD CONSTRAINT work_allocations_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_execution_plans
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_execution_plans_one_native_custody_v1,
 ADD CONSTRAINT work_execution_plans_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_execution_plan_events
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_execution_plan_events_one_native_custody_v1,
 ADD CONSTRAINT work_execution_plan_events_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_execution_results
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_execution_results_one_native_custody_v1,
 ADD CONSTRAINT work_execution_results_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_result_acceptances
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_result_acceptances_one_native_custody_v1,
 ADD CONSTRAINT work_result_acceptances_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_item_context_links
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_item_context_links_one_native_custody_v1,
 ADD CONSTRAINT work_item_context_links_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);
ALTER TABLE atlas.work_time_contracts
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 DROP CONSTRAINT work_time_contracts_one_native_custody_v1,
 ADD CONSTRAINT work_time_contracts_one_native_custody_v1 CHECK (num_nonnulls(organization_id,household_id,personal_principal_id)=1);

ALTER TABLE atlas.work_items ADD CONSTRAINT work_items_personal_original_key_v1 UNIQUE(personal_principal_id,id);
ALTER TABLE atlas.work_allocations ADD CONSTRAINT work_allocations_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans ADD CONSTRAINT work_execution_plans_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events ADD CONSTRAINT work_execution_plan_events_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results ADD CONSTRAINT work_execution_results_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances ADD CONSTRAINT work_result_acceptances_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_item_context_links ADD CONSTRAINT work_item_context_links_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_time_contracts ADD CONSTRAINT work_time_contracts_personal_original_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id) REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;

-- Existing shared immutability function already serves all eight tables.
CREATE OR REPLACE FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $body$
BEGIN
 IF NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
    NEW.household_id IS DISTINCT FROM OLD.household_id OR
    NEW.personal_principal_id IS DISTINCT FROM OLD.personal_principal_id THEN
   RAISE EXCEPTION 'Original Work custody cannot be rewritten.' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$body$;

-- Extend the actual trigger column lists as well as their function. The original
-- custody guard must fire even for a personal_principal_id-only UPDATE.
DROP TRIGGER work_items_immutable_custody_v1 ON atlas.work_items;
CREATE TRIGGER work_items_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_items
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_allocations_immutable_custody_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_allocations
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_execution_plans_immutable_custody_v1 ON atlas.work_execution_plans;
CREATE TRIGGER work_execution_plans_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_execution_plans
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_execution_plan_events_immutable_custody_v1 ON atlas.work_execution_plan_events;
CREATE TRIGGER work_execution_plan_events_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_execution_plan_events
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_execution_results_immutable_custody_v1 ON atlas.work_execution_results;
CREATE TRIGGER work_execution_results_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_result_acceptances_immutable_custody_v1 ON atlas.work_result_acceptances;
CREATE TRIGGER work_result_acceptances_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_result_acceptances
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_item_context_links_immutable_custody_v1 ON atlas.work_item_context_links;
CREATE TRIGGER work_item_context_links_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_item_context_links
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
DROP TRIGGER work_time_contracts_immutable_custody_v1 ON atlas.work_time_contracts;
CREATE TRIGGER work_time_contracts_immutable_custody_v1 BEFORE UPDATE OF organization_id, household_id, personal_principal_id ON atlas.work_time_contracts
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();

-- Existing actor-carrier constraint retains the institutional and Household
-- alternatives byte-for-byte as the first branch. Personal row shape is additional,
-- and authorization remains checked by the existing guard extended below.
ALTER TABLE atlas.work_allocations DROP CONSTRAINT work_allocations_exact_assignee_carrier_v1;
ALTER TABLE atlas.work_allocations ADD CONSTRAINT work_allocations_exact_assignee_carrier_v1
 CHECK ((((organization_id IS NOT NULL) AND ((assignee_membership_id IS NOT NULL) OR ((assignee_canonical_person_id IS NOT NULL) AND (establishment_basis_kind = ANY (ARRAY['person_connection_receiver_uptake'::text, 'delegated_under_standing_scope'::text, 'ledger_connection_direct_assignment'::text, 'original_subject_direct_assignment_v1'::text, 'native_person_self_participation_v1'::text, 'native_person_direct_participation_v1'::text])))) AND (assignee_household_member_id IS NULL)) OR ((household_id IS NOT NULL) AND (assignee_membership_id IS NULL) AND (assigned_by_membership_id IS NULL) AND (establishment_basis_kind = 'household_explicit_carrier_v1'::text) AND ((assignee_household_member_id IS NOT NULL) OR (assignee_canonical_person_id IS NOT NULL))))
 OR (personal_principal_id IS NOT NULL AND organization_id IS NULL AND household_id IS NULL
 AND assignee_membership_id IS NULL AND assigned_by_membership_id IS NULL
 AND assignee_household_member_id IS NULL
 AND assignee_institutional_person_record_id IS NULL AND assigned_by_institutional_person_record_id IS NULL
 AND assignee_canonical_person_id IS NOT NULL AND allocation_role IN ('responsible','participant')
 AND (establishment_basis_kind='personal_original_direct_assignment_v1') IS TRUE
 AND establishment_basis IS NOT NULL));

-- Existing one-active-responsible index is still authoritative. A single active
-- Person per private roster across roles prevents duplicate primary/participant.
CREATE UNIQUE INDEX work_allocations_personal_active_person_v1
 ON atlas.work_allocations(work_item_id,assignee_canonical_person_id)
 WHERE personal_principal_id IS NOT NULL AND state='active';

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
  -- Private custody reuses the released signed Principal/person and selected
  -- reciprocal connection resolver. A basis payload alone never grants access.
  -- This branch covers owner-originated current allocation and release ONLY.
  -- Historical admission and participant completion are intentionally not admitted here.
  if new.personal_principal_id is not null then
    declare
      v_owner_principal uuid:=atlas.require_active_task_principal_v1();
      v_owner_person uuid:=atlas.personal_task_ready_person_v1(auth.uid());
      v_link uuid;
    begin
      if auth.uid() is null or v_owner_person is null
        or v_owner_principal is distinct from new.personal_principal_id
        or not exists(select 1 from atlas.principals p
          where p.id=new.personal_principal_id and p.user_id=auth.uid()
            and p.person_id=v_owner_person and p.status='active')
      then raise exception 'Signed personal original owner required' using errcode='42501'; end if;
      -- Serialize current roster changes against the original; this is not a
      -- replacement for the exact expected-revision/action writer still required.
      perform 1 from atlas.work_items w where w.id=new.work_item_id
        and w.personal_principal_id=new.personal_principal_id
        and w.work_state='open' for update;
      if not found then raise exception 'Open owned original required' using errcode='42501'; end if;
      if new.organization_id is not null or new.household_id is not null
        or new.assignee_membership_id is not null or new.assigned_by_membership_id is not null
        or new.assignee_household_member_id is not null
        or new.assignee_institutional_person_record_id is not null
        or new.assigned_by_institutional_person_record_id is not null
        or new.assignee_canonical_person_id is null
        or new.allocation_role not in ('responsible','participant')
        or new.establishment_basis_kind is distinct from 'personal_original_direct_assignment_v1'
        or jsonb_typeof(new.establishment_basis) is distinct from 'object'
        or new.establishment_basis->>'contractVersion' is distinct from 'personal_original_direct_assignment_v1'
        or new.establishment_basis->>'personalPrincipalId' is distinct from new.personal_principal_id::text
        or new.establishment_basis->>'workItemId' is distinct from new.work_item_id::text
        or new.establishment_basis->>'actorPersonId' is distinct from v_owner_person::text
        or new.establishment_basis->>'assigneePersonId' is distinct from new.assignee_canonical_person_id::text
        or new.establishment_basis->>'allocationRole' is distinct from new.allocation_role
        or coalesce(new.establishment_basis->>'sourceActionId','') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      then raise exception 'Exact private allocation provenance required' using errcode='23514'; end if;
      if tg_op='UPDATE' then
        -- Release must remain possible after disconnect; require the original
        -- owner, immutable provenance, same original and a real release only.
        if old.state is distinct from 'active' or new.state is distinct from 'released'
          or new.released_at is null or nullif(btrim(new.release_reason),'') is null
          or (to_jsonb(new)-ARRAY['state','released_at','release_reason','updated_at']) is distinct from
             (to_jsonb(old)-ARRAY['state','released_at','release_reason','updated_at'])
        then raise exception 'Only exact owner release admitted in this review' using errcode='23514'; end if;
        return new;
      end if;
      if new.state is distinct from 'active' then
        raise exception 'Current active allocation required' using errcode='23514';
      end if;
      if new.assignee_canonical_person_id=v_owner_person then
        if new.establishment_basis->>'connectionId' is not null then
          raise exception 'Self assignment requires no connection' using errcode='23514';
        end if;
      else
        -- Bind the exact accepted relationship and acquire the same lock used
        -- by change_personal_task_assignment_self_api_v1. Recheck after locking.
        select peer.connection_id into v_link
          from atlas.personal_task_connection_peers_v1(auth.uid()) peer
          where peer.peer_person_id=new.assignee_canonical_person_id
            and peer.connection_id::text=new.establishment_basis->>'connectionId';
        if v_link is null then raise exception 'Current exact connection required' using errcode='42501'; end if;
        perform 1 from atlas.household_member_identity_links l
          where l.id=v_link and l.link_state='active' and l.revoked_at is null for share;
        if not found or not exists(select 1 from atlas.personal_task_connection_peers_v1(auth.uid()) peer
          where peer.peer_person_id=new.assignee_canonical_person_id and peer.connection_id=v_link)
        then raise exception 'Current exact connection required' using errcode='42501'; end if;
      end if;
      return new;
    end;
  end if;

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

-- Extend this existing guard to personal rows, preserving its original
-- institutional UPDATE column list. Include all updates for the personal
-- alternative without broadening the institutional invocation conditions.
DROP TRIGGER work_allocations_responsibility_establishment_guard_v2 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_responsibility_establishment_guard_v2
 BEFORE INSERT OR UPDATE OF allocation_role, state, assignee_membership_id, assigned_by_membership_id, establishment_basis_kind, establishment_basis
 ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2();
-- A narrow trigger binding to the SAME function handles personal rows on
-- every UPDATE, including changes to provenance fields not in the old list.
CREATE TRIGGER work_allocations_personal_establishment_guard_v1
 BEFORE INSERT OR UPDATE ON atlas.work_allocations FOR EACH ROW
 WHEN (NEW.personal_principal_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2();

-- No public or internal callable writer is added here. Still held pending
-- full revision/action history mapping and exact signed source proof.

-- Parent/child integrity is required even when the old organization keys are NULL.
ALTER TABLE atlas.work_allocations ADD CONSTRAINT work_allocations_personal_original_allocation_key_v1 UNIQUE(personal_principal_id,work_item_id,id);
ALTER TABLE atlas.work_execution_plans ADD CONSTRAINT work_execution_plans_personal_original_plan_key_v1 UNIQUE(personal_principal_id,work_item_id,id);
ALTER TABLE atlas.work_execution_results ADD CONSTRAINT work_execution_results_personal_original_result_key_v1 UNIQUE(personal_principal_id,work_item_id,id);
ALTER TABLE atlas.work_execution_plans ADD CONSTRAINT work_execution_plans_personal_allocation_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id,responsible_allocation_id) REFERENCES atlas.work_allocations(personal_principal_id,work_item_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events ADD CONSTRAINT work_execution_plan_events_personal_plan_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id,plan_id) REFERENCES atlas.work_execution_plans(personal_principal_id,work_item_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results ADD CONSTRAINT work_execution_results_personal_allocation_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id,responsible_allocation_id) REFERENCES atlas.work_allocations(personal_principal_id,work_item_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances ADD CONSTRAINT work_result_acceptances_personal_result_fk_v1
 FOREIGN KEY(personal_principal_id,work_item_id,execution_result_id) REFERENCES atlas.work_execution_results(personal_principal_id,work_item_id,id) ON DELETE RESTRICT;

-- Existing comment/revision stores, not another note/history path.
ALTER TABLE atlas.native_original_work_comments_v1
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 ALTER COLUMN organization_id DROP NOT NULL,
 ALTER COLUMN ledger_id DROP NOT NULL,
 ADD CONSTRAINT native_original_work_comments_v1_custody_shape_v1 CHECK (
  (personal_principal_id IS NULL AND organization_id IS NOT NULL AND ledger_id IS NOT NULL)
  OR (personal_principal_id IS NOT NULL AND organization_id IS NULL AND ledger_id IS NULL)),
 ADD CONSTRAINT native_original_work_comments_v1_personal_original_fk_v1 FOREIGN KEY(personal_principal_id,work_item_id)
 REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.native_work_text_revision_events_v1
 ADD COLUMN personal_principal_id uuid REFERENCES atlas.principals(id) ON DELETE RESTRICT,
 ALTER COLUMN organization_id DROP NOT NULL,
 ALTER COLUMN ledger_id DROP NOT NULL,
 ADD CONSTRAINT native_work_text_revision_events_v1_custody_shape_v1 CHECK (
  (personal_principal_id IS NULL AND organization_id IS NOT NULL AND ledger_id IS NOT NULL)
  OR (personal_principal_id IS NOT NULL AND organization_id IS NULL AND ledger_id IS NULL)),
 ADD CONSTRAINT native_work_text_revision_events_v1_personal_original_fk_v1 FOREIGN KEY(personal_principal_id,work_item_id)
 REFERENCES atlas.work_items(personal_principal_id,id) ON DELETE RESTRICT;

-- Preserve distinct source-action replay boundaries in private custody;
-- existing Organization replay and result uniqueness are retained.
CREATE UNIQUE INDEX native_original_work_personal_comment_replay_v1
 ON atlas.native_original_work_comments_v1(personal_principal_id,work_item_id,author_person_id,source_action_id)
 WHERE personal_principal_id IS NOT NULL;
CREATE UNIQUE INDEX work_execution_results_personal_idempotency_v1
 ON atlas.work_execution_results(personal_principal_id,idempotency_key)
 WHERE personal_principal_id IS NOT NULL;

-- This is an incomplete review shape, not a security/behavior/no-loss proof.
-- No Personal Task records are moved, no public facades altered, no guards waived.
-- The complete source must reconcile ALL affected triggers, RLS/ACLs, actual
-- Principal/Person binding, direct assignment, source-action/old revision evidence,
-- optional date and genuine receipt semantics, terminal transitions, history,
-- promotion provenance, external clients and exact drop disposition before release.
ROLLBACK;
