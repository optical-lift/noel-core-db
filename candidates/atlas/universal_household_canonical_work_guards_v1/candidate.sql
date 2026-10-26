BEGIN;
-- Must follow universal_household_canonical_work_custody_v1.
-- These exact source guards apply ONLY to household-owned original canonical
-- work rows. Existing Organization/Event source guards remain unchanged.
CREATE OR REPLACE FUNCTION atlas.household_work_actor_v1(p_household_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 IF auth.uid() IS NULL OR
   (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready' THEN
   RAISE EXCEPTION 'Signed canonical Household Person required.' USING ERRCODE='42501';
 END IF;
 v_person:=atlas.current_person_id_v1();
 IF v_person IS NULL OR p_household_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM atlas.households h
   JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=p_household_id AND h.status='active' AND (
       (p.status='active' AND p.user_id=auth.uid() AND p.person_id=v_person)
     OR EXISTS(
       SELECT 1 FROM atlas.household_members hm
       WHERE hm.household_id=h.id AND hm.active AND hm.person_id=v_person
         AND hm.user_id=auth.uid()
     )
   )
 ) THEN
   RAISE EXCEPTION 'Household identity unavailable.' USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.household_work_actor_v1(uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.require_household_governor_self_v1(p_household_id uuid)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 v_person:=atlas.household_work_actor_v1(p_household_id);
 IF NOT EXISTS(
   SELECT 1 FROM atlas.households h
   JOIN atlas.principals p ON p.id=h.principal_id
   WHERE h.id=p_household_id AND h.status='active' AND
     p.status='active' AND p.user_id=auth.uid() AND p.person_id=v_person
 ) THEN
   RAISE EXCEPTION 'Household governor required.' USING ERRCODE='42501';
 END IF;
 RETURN v_person;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.require_household_governor_self_v1(uuid)
 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION atlas.guard_original_household_work_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR NEW.organization_unit_id IS NOT NULL
    OR NEW.work_definition_id IS NOT NULL
    OR NEW.source_object_type<>'household_need_occurrence'
    OR NEW.source_object_id IS NULL
    OR NEW.result_contract_key<>'household_laundry_begin_cycle_v1' THEN
  RAISE EXCEPTION 'Household Work must remain an original protected Need-bound Work.'
    USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' THEN
  IF OLD.household_id IS DISTINCT FROM NEW.household_id
     OR OLD.organization_id IS DISTINCT FROM NEW.organization_id
     OR OLD.source_object_type IS DISTINCT FROM NEW.source_object_type
     OR OLD.source_object_id IS DISTINCT FROM NEW.source_object_id
     OR OLD.result_contract_key IS DISTINCT FROM NEW.result_contract_key THEN
    RAISE EXCEPTION 'Canonical Work custody and source cannot be reassigned.'
     USING ERRCODE='23514';
  END IF;
  IF NEW.work_state='completed' AND OLD.work_state IS DISTINCT FROM 'completed'
   AND NOT EXISTS(
     SELECT 1 FROM atlas.work_result_acceptances a
     JOIN atlas.work_execution_results r ON r.id=a.execution_result_id
     WHERE a.household_id=NEW.household_id
       AND a.work_item_id=NEW.id AND a.decision='accepted'
       AND r.household_id=NEW.household_id AND r.work_item_id=NEW.id
       AND r.result_kind='completed'
       AND r.result_contract_key='household_laundry_begin_cycle_v1'
   ) THEN
    RAISE EXCEPTION 'Household Work cannot complete without accepted physical Actual.'
     USING ERRCODE='23514';
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER b_guard_original_household_work_v1
 BEFORE INSERT OR UPDATE ON atlas.work_items
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_original_household_work_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_allocation_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_person uuid;
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 v_person:=atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR NEW.assignee_membership_id IS NOT NULL
   OR NEW.assigned_by_membership_id IS NOT NULL
   OR NEW.allocation_role<>'responsible'
   OR NEW.establishment_basis_kind<>'household_explicit_carrier_v1'
   OR jsonb_typeof(NEW.establishment_basis) IS DISTINCT FROM 'object'
   OR NEW.establishment_basis->>'householdId' IS DISTINCT FROM NEW.household_id::text
   OR NEW.establishment_basis->>'workItemId' IS DISTINCT FROM NEW.work_item_id::text
   OR NEW.establishment_basis->>'senderPersonId' IS DISTINCT FROM v_person::text
   OR NULLIF(btrim(NEW.establishment_basis->>'decisionReason'),'') IS NULL
   OR length(btrim(NEW.establishment_basis->>'decisionReason'))<12
   OR NOT EXISTS(
      SELECT 1 FROM atlas.work_items w
      WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
        AND w.work_state='open'
   ) THEN
  RAISE EXCEPTION 'Household responsibility lacks exact original and explicit carrier.'
    USING ERRCODE='23514';
 END IF;
 IF NEW.assignee_household_member_id IS NOT NULL THEN
   IF NOT EXISTS (
     SELECT 1 FROM atlas.household_members m
     WHERE m.id=NEW.assignee_household_member_id
       AND m.household_id=NEW.household_id AND m.active
       AND (NEW.assignee_canonical_person_id IS NULL
         OR m.person_id=NEW.assignee_canonical_person_id)
   ) THEN
     RAISE EXCEPTION 'Household carrier is not an actual active member.'
       USING ERRCODE='23514';
   END IF;
 ELSIF NEW.assignee_canonical_person_id IS NOT NULL THEN
   IF NOT EXISTS(
     SELECT 1 FROM atlas.households h
     JOIN atlas.principals p ON p.id=h.principal_id
     WHERE h.id=NEW.household_id AND p.status='active'
       AND p.person_id=NEW.assignee_canonical_person_id
   ) AND NOT EXISTS(
     SELECT 1 FROM atlas.household_members m
     WHERE m.household_id=NEW.household_id AND m.active
       AND m.person_id=NEW.assignee_canonical_person_id
   ) THEN
     RAISE EXCEPTION 'Signed Person must belong to this Household.'
       USING ERRCODE='23514';
   END IF;
 ELSE
   RAISE EXCEPTION 'Unresolved carrier is not an allocation.'
    USING ERRCODE='23514';
 END IF;
 IF TG_OP='UPDATE' THEN
   IF OLD.household_id IS DISTINCT FROM NEW.household_id
      OR OLD.work_item_id IS DISTINCT FROM NEW.work_item_id
      OR OLD.assignee_household_member_id IS DISTINCT FROM NEW.assignee_household_member_id
      OR OLD.establishment_basis IS DISTINCT FROM NEW.establishment_basis THEN
     RAISE EXCEPTION 'Household Work allocation source is immutable.'
       USING ERRCODE='23514';
   END IF;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_allocation_v1
 BEFORE INSERT OR UPDATE ON atlas.work_allocations
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_allocation_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_plan_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR
   NOT EXISTS(
     SELECT 1 FROM atlas.work_items w
     JOIN atlas.work_allocations a ON a.work_item_id=w.id
       AND a.household_id=w.household_id AND a.id=NEW.responsible_allocation_id
     WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
       AND w.work_state='open' AND a.state='active'
       AND a.allocation_role='responsible'
       AND a.assignee_membership_id IS NULL
       AND NEW.assignee_membership_id IS NULL
   ) THEN
    RAISE EXCEPTION 'Household Work plan requires its own active original allocation.'
      USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_plan_v1
 BEFORE INSERT OR UPDATE ON atlas.work_execution_plans
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_plan_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_subject_link_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.require_household_governor_self_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL OR NEW.subject_domain<>'household'
   OR NEW.subject_kind<>'kernel_instance' OR NEW.relation_kind<>'acts_on'
   OR NOT EXISTS (
     SELECT 1 FROM atlas.work_items w
     JOIN atlas.household_need_occurrences_v1 need
       ON need.id=w.source_object_id AND need.household_id=w.household_id
     JOIN atlas.household_kernel_instances inst ON inst.id=need.instance_id
     WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
       AND inst.id=NEW.subject_id AND inst.household_id=NEW.household_id
   ) THEN
    RAISE EXCEPTION 'Household Work link must be its actual original Laundry Subject.'
      USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_subject_link_v1
 BEFORE INSERT OR UPDATE ON atlas.work_item_context_links
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_subject_link_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_actual_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
    OR NEW.result_kind<>'completed'
    OR NEW.result_contract_key<>'household_laundry_begin_cycle_v1'
    OR NEW.reported_by_user_id IS DISTINCT FROM auth.uid()
    OR NOT EXISTS (
      SELECT 1 FROM atlas.work_items w
      JOIN atlas.household_need_occurrences_v1 need
        ON need.id=w.source_object_id AND need.household_id=w.household_id
      JOIN atlas.care_result_events r
        ON r.id=(NEW.payload->>'careResultId')::uuid
        AND r.scope_id=w.household_id AND r.scope_kind='household'
        AND r.subject_domain='household'
        AND r.subject_kind='household_kernel_instance'
        AND r.subject_id=need.instance_id::text
        AND r.actor_user_id=auth.uid()
        AND r.condition_after='washing'
        AND r.result_kind='improved_more_remains'
      WHERE w.id=NEW.work_item_id AND w.household_id=NEW.household_id
        AND w.result_contract_key=NEW.result_contract_key
        AND need.state='open'
    ) THEN
  RAISE EXCEPTION 'Work Result needs real accepted Laundry step evidence.'
    USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_actual_v1
 BEFORE INSERT ON atlas.work_execution_results
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_actual_v1();

CREATE OR REPLACE FUNCTION atlas.guard_household_work_acceptance_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.household_id IS NULL THEN RETURN NEW; END IF;
 PERFORM atlas.household_work_actor_v1(NEW.household_id);
 IF NEW.organization_id IS NOT NULL
   OR NEW.decision<>'accepted'
   OR NEW.accepted_by_domain<>'household_laundry_actual'
   OR NOT EXISTS(
     SELECT 1 FROM atlas.work_execution_results r
     WHERE r.id=NEW.execution_result_id
       AND r.household_id=NEW.household_id
       AND r.work_item_id=NEW.work_item_id
       AND r.result_kind='completed'
       AND r.result_contract_key='household_laundry_begin_cycle_v1'
   ) THEN
   RAISE EXCEPTION 'Household acceptance requires the original physical Work Result.'
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER z_guard_household_work_acceptance_v1
 BEFORE INSERT ON atlas.work_result_acceptances
 FOR EACH ROW WHEN (NEW.household_id IS NOT NULL)
 EXECUTE FUNCTION atlas.guard_household_work_acceptance_v1();

-- Keep original append-only acceptance and Actual guards; no new Household
-- reader or writer accepts farm_id, Organization Membership or employee seat.
COMMIT;
