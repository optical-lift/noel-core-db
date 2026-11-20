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

-- The existing actor-carrier check is not yet changed here. Personal allocations
-- cannot become functional merely through this shape. Full candidate must reconcile
-- current reciprocal connection/revision admission before permitting any write.

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
