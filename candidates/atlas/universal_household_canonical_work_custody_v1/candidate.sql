BEGIN;
-- One canonical Work identity. Household is another protected custody context,
-- never a fabricated Organization. This release candidate MUST be applied after
-- the original growing-object Work Subject extension in PR #2265.
-- Keep old Organization/production/Event writers on their unchanged path.

ALTER TABLE atlas.work_items
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_items ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_items
 ADD CONSTRAINT work_items_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_allocations
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_allocations ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_plans
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_plan_events
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_plan_events
 ADD CONSTRAINT work_execution_plan_events_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_execution_results
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_execution_results
 ADD CONSTRAINT work_execution_results_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_result_acceptances
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_result_acceptances
 ADD CONSTRAINT work_result_acceptances_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_item_context_links
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_item_context_links ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

ALTER TABLE atlas.work_time_contracts
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_time_contracts ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.work_time_contracts
 ADD CONSTRAINT work_time_contracts_one_native_custody_v1
 CHECK ((organization_id IS NULL) <> (household_id IS NULL));

-- An original Work and its dependent receipts can never be converted from
-- Household to Institution or the reverse by editing their custody columns.
-- The protected source requires a new Work identity and explicit provenance
-- for a genuine transfer, not a rewritten original.
CREATE OR REPLACE FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
 IF NEW.organization_id IS DISTINCT FROM OLD.organization_id OR
    NEW.household_id IS DISTINCT FROM OLD.household_id THEN
   RAISE EXCEPTION 'Original Work custody cannot be rewritten.'
     USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION atlas.guard_canonical_work_custody_immutability_v1()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER work_items_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_items
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_allocations_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_allocations
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_plans_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_plans
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_plan_events_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_plan_events
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_execution_results_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_execution_results
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_result_acceptances_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_result_acceptances
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_item_context_links_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_item_context_links
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();
CREATE TRIGGER work_time_contracts_immutable_custody_v1
 BEFORE UPDATE OF organization_id,household_id ON atlas.work_time_contracts
 FOR EACH ROW EXECUTE FUNCTION atlas.guard_canonical_work_custody_immutability_v1();

-- Reference the SAME Work ID across contexts; composite foreign keys also
-- prevent cross-household Work/Plan/Result copying.
CREATE UNIQUE INDEX work_items_household_id_id_v1
 ON atlas.work_items(household_id,id);
CREATE UNIQUE INDEX work_items_household_stable_key_v1
 ON atlas.work_items(household_id,stable_key)
 WHERE household_id IS NOT NULL AND stable_key IS NOT NULL;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_results
 ADD CONSTRAINT work_execution_results_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_result_acceptances
 ADD CONSTRAINT work_result_acceptances_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_time_contracts
 ADD CONSTRAINT work_time_contracts_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plan_events
 ADD CONSTRAINT work_execution_plan_events_household_original_work_fk_v1
 FOREIGN KEY(household_id,work_item_id)
 REFERENCES atlas.work_items(household_id,id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_execution_plans
 ADD CONSTRAINT work_execution_plans_household_allocation_fk_v1
 FOREIGN KEY (responsible_allocation_id)
 REFERENCES atlas.work_allocations(id) ON DELETE RESTRICT;

-- A real Household member can carry Work without an account; canonical
-- Person identity is never forged on behalf of a non-account household member.
ALTER TABLE atlas.work_allocations
 ADD COLUMN assignee_household_member_id uuid
 REFERENCES atlas.household_members(id) ON DELETE RESTRICT;
ALTER TABLE atlas.work_allocations
 DROP CONSTRAINT work_allocations_exact_assignee_carrier_v1;
ALTER TABLE atlas.work_allocations
 ADD CONSTRAINT work_allocations_exact_assignee_carrier_v1 CHECK (
  (organization_id IS NOT NULL AND
   (assignee_membership_id IS NOT NULL OR
    (assignee_canonical_person_id IS NOT NULL AND
     establishment_basis_kind IN(
       'person_connection_receiver_uptake','delegated_under_standing_scope',
       'ledger_connection_direct_assignment'
     ))) AND assignee_household_member_id IS NULL)
  OR
  (household_id IS NOT NULL
   AND assignee_membership_id IS NULL
   AND assigned_by_membership_id IS NULL
   AND establishment_basis_kind='household_explicit_carrier_v1'
   AND (assignee_household_member_id IS NOT NULL
        OR assignee_canonical_person_id IS NOT NULL))
 );

-- Keep the original Work-to-Subject table, not a second Household task link.
ALTER TABLE atlas.work_item_context_links
 DROP CONSTRAINT work_item_context_links_subject_pair_v1;
ALTER TABLE atlas.work_item_context_links
 ADD CONSTRAINT work_item_context_links_subject_pair_v1 CHECK (
   (subject_domain='spatial' AND subject_kind IN ('zone','place','growing_object'))
   OR (subject_domain='identity' AND subject_kind IN ('identity_subject','external_relationship'))
   OR (subject_domain='temporal' AND subject_kind='occurrence')
   OR (subject_domain='household' AND subject_kind IN ('kernel_instance','household_space'))
 );

-- The source satisfaction registry is one append-only table. Farm retains
-- its existing Rule/Binding/State FKs; Household has a genuine accepted Rhythm
-- from the protected Household source, never a synthetic farm or company.
ALTER TABLE atlas.rhythm_satisfactions
 ADD COLUMN household_id uuid REFERENCES atlas.households(id) ON DELETE RESTRICT,
 ADD COLUMN household_rhythm_id uuid REFERENCES atlas.household_rhythms(id) ON DELETE RESTRICT;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN organization_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN farm_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_state_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_binding_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions ALTER COLUMN rhythm_rule_id DROP NOT NULL;
ALTER TABLE atlas.rhythm_satisfactions
 DROP CONSTRAINT rhythm_satisfactions_subject_kind_check;
ALTER TABLE atlas.rhythm_satisfactions
 ADD CONSTRAINT rhythm_satisfactions_subject_kind_check CHECK (
   subject_kind IN ('farm','zone','growing_object','crop_cycle','project',
     'seed_lot','household_kernel_instance')
 );
ALTER TABLE atlas.rhythm_satisfactions
 ADD CONSTRAINT rhythm_satisfactions_one_native_custody_v1 CHECK (
   (farm_id IS NOT NULL AND organization_id IS NOT NULL
    AND household_id IS NULL AND household_rhythm_id IS NULL
    AND rhythm_state_id IS NOT NULL
    AND rhythm_binding_id IS NOT NULL AND rhythm_rule_id IS NOT NULL)
   OR
   (household_id IS NOT NULL AND household_rhythm_id IS NOT NULL
    AND organization_id IS NULL AND farm_id IS NULL
    AND rhythm_state_id IS NULL AND rhythm_binding_id IS NULL
    AND rhythm_rule_id IS NULL)
 );
CREATE UNIQUE INDEX rhythm_satisfactions_household_key_v1
 ON atlas.rhythm_satisfactions(household_id,satisfaction_key)
 WHERE household_id IS NOT NULL;

-- Old guarded business operations continue to execute unchanged whenever
-- organization_id is populated; they must never interpret Household Work as
-- an Organization and invent a company ledger completion or employee seat.
DROP TRIGGER work_allocations_participation_establishment_guard_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_participation_establishment_guard_v1 BEFORE INSERT OR UPDATE OF allocation_role, state, assignee_membership_id, assigned_by_membership_id, establishment_basis_kind, establishment_basis ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_work_allocation_participation_establishment_v1();

DROP TRIGGER work_allocations_reconcile_execution_plan_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_reconcile_execution_plan_v1 AFTER INSERT OR UPDATE OF state, assignee_membership_id ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.reconcile_company_work_execution_plan_responsibility_trigger_v1();

DROP TRIGGER work_allocations_responsibility_establishment_guard_v2 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_responsibility_establishment_guard_v2 BEFORE INSERT OR UPDATE OF allocation_role, state, assignee_membership_id, assigned_by_membership_id, establishment_basis_kind, establishment_basis ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_work_allocation_responsibility_establishment_v2();

DROP TRIGGER work_allocations_sync_production_carrier_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_sync_production_carrier_v1 AFTER INSERT OR UPDATE OF state, assignee_membership_id, allocation_role ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.sync_production_company_work_responsibility_carrier_trigger_v1();

DROP TRIGGER work_allocations_validate_active_membership_v1 ON atlas.work_allocations;
CREATE TRIGGER work_allocations_validate_active_membership_v1 BEFORE INSERT OR UPDATE OF state, assignee_membership_id, assigned_by_membership_id, organization_id ON atlas.work_allocations FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.validate_active_work_allocation_membership_v1();

DROP TRIGGER work_execution_plans_validate_v1 ON atlas.work_execution_plans;
CREATE TRIGGER work_execution_plans_validate_v1 BEFORE INSERT OR UPDATE ON atlas.work_execution_plans FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.validate_work_execution_plan_v1();

DROP TRIGGER a_work_items_guard_governed_completion_v1 ON atlas.work_items;
CREATE TRIGGER a_work_items_guard_governed_completion_v1 BEFORE UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.guard_governed_company_work_completion_v1();

DROP TRIGGER guard_company_work_cancel_dependencies_v1 ON atlas.work_items;
CREATE TRIGGER guard_company_work_cancel_dependencies_v1 BEFORE UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN ((NEW.organization_id IS NOT NULL) AND (((old.work_state IS DISTINCT FROM new.work_state) AND (new.work_state = 'cancelled'::text)))) EXECUTE FUNCTION atlas.guard_company_work_cancel_dependencies_v1();

DROP TRIGGER work_items_complete_bundle_members_v1 ON atlas.work_items;
CREATE TRIGGER work_items_complete_bundle_members_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.complete_company_work_bundle_members_v1();

DROP TRIGGER work_items_complete_execution_plan_v1 ON atlas.work_items;
CREATE TRIGGER work_items_complete_execution_plan_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN (NEW.organization_id IS NOT NULL) EXECUTE FUNCTION atlas.complete_company_work_execution_plan_v1();

DROP TRIGGER work_items_project_completed_company_work_to_ledger_v1 ON atlas.work_items;
CREATE TRIGGER work_items_project_completed_company_work_to_ledger_v1 AFTER UPDATE OF work_state ON atlas.work_items FOR EACH ROW WHEN ((NEW.organization_id IS NOT NULL) AND (((new.work_state = 'completed'::text) AND (old.work_state IS DISTINCT FROM new.work_state)))) EXECUTE FUNCTION atlas.project_completed_company_work_to_ledger_v1();

-- A separate source guard/writer for household rows follows in this
-- same staged release; until then, the new private household rows are inert.
COMMIT;
