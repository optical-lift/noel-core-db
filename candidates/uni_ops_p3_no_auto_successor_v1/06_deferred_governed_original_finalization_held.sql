-- UNI-OPS-01 / U2C: ONE governed ORIGINAL means one atomic finalized offer,
-- accepted Person, Ledger relevance and scheduled service-day plan at COMMIT.
-- HELD source candidate (NO production migration, SQL execution or release).
--
-- Pair with 04 BEFORE INSERT guard; this AFTER INSERT CONSTRAINT TRIGGER is
-- DEFERRABLE INITIALLY DEFERRED so the existing U2B signed root finalizer can
-- create the original, establish scope/plan/Person, and mark its offer fulfilled
-- in the SAME transaction. It checks the final committed original; it does not
-- independently issue, repair, accept, allocate, schedule, or close any Work.
-- All other native Households, Events and non-governed original Work unchanged.
BEGIN;
DO $prerequisites$
BEGIN
 IF pg_catalog.to_regprocedure(
  'atlas.guard_uni_ops_governed_care_original_acceptance_v1()'
 ) IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.resolve_governed_canonical_farm_rule_authority_v1(uuid,uuid,uuid,uuid,uuid)'
 ) IS NULL
 OR pg_catalog.to_regclass(
  'atlas.governed_prework_candidate_offers_v1'
 ) IS NULL
 OR pg_catalog.to_regclass(
  'atlas.company_work_native_ledger_relevance'
 ) IS NULL
 OR pg_catalog.to_regclass('atlas.work_allocations') IS NULL
 OR pg_catalog.to_regclass('atlas.work_execution_plans') IS NULL
 THEN RAISE EXCEPTION
   'Exact reviewed U2C governed original and native allocation/plan sources required';
 END IF;
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger
  WHERE tgrelid='atlas.work_items'::regclass
    AND tgname='z_uni_ops_governed_original_finalization_v1'
    AND NOT tgisinternal
 ) THEN
  RAISE EXCEPTION 'Deferred original finalization already exists; source review required';
 END IF;
END;
$prerequisites$;

CREATE FUNCTION atlas.require_uni_ops_original_finalize_on_commit_v1()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $final_commit$
DECLARE
 v_state atlas.rhythm_state%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_work atlas.work_items%ROWTYPE;
 v_authority jsonb;
 v_allocation uuid;
 v_serving text;
BEGIN
 IF NEW.organization_id IS NULL
    OR NEW.source_object_type IS DISTINCT FROM 'rhythm_state'
    OR NEW.source_object_id IS NULL
 THEN RETURN NULL; END IF;

 -- Only the exact original Need governed by an actual U1A/U1B source.
 IF NOT atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(
  NEW.source_object_id
 ) THEN RETURN NULL; END IF;

 SELECT * INTO v_state FROM atlas.rhythm_state s
 WHERE s.id=NEW.source_object_id
   AND s.organization_id=NEW.organization_id;
 IF v_state.id IS NULL THEN
  RAISE EXCEPTION 'Governed original cannot commit without native Need'
    USING ERRCODE='42501';
 END IF;

 -- Read what the transaction finally committed; OLD source and metadata
 -- must not change between R01 insert and U2B fulfilled offer.
 SELECT * INTO v_work FROM atlas.work_items w WHERE w.id=NEW.id;
 v_serving:=NULLIF(pg_catalog.btrim(v_work.metadata->>'servingKey'),'');
 IF v_work.id IS NULL
    OR v_work.organization_id IS DISTINCT FROM NEW.organization_id
    OR v_work.source_object_type IS DISTINCT FROM 'rhythm_state'
    OR v_work.source_object_id IS DISTINCT FROM v_state.id
    OR v_work.result_contract_key IS DISTINCT FROM
       'continuing_care_actual_v1'
    OR v_work.metadata->>'sourceContract'
       IS DISTINCT FROM 'continuing_original_work_v1'
    OR v_serving IS NULL
    OR v_serving !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
 THEN
  RAISE EXCEPTION 'Governed original source changed before commit'
    USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_offer
 FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.id=v_serving::uuid;
 IF v_offer.id IS NULL OR v_offer.offer_state<>'fulfilled'
    OR v_offer.original_work_item_id IS DISTINCT FROM v_work.id
    OR v_offer.response_action_id IS NULL
    OR v_offer.responded_at IS NULL
    OR v_offer.responding_principal_id IS NULL
    OR v_offer.organization_id IS DISTINCT FROM v_work.organization_id
    OR v_offer.source_candidate_id IS DISTINCT FROM v_state.id
    OR v_offer.farm_id IS DISTINCT FROM v_state.farm_id
    OR v_offer.subject_id IS DISTINCT FROM v_state.subject_id
    OR v_offer.source_rule_id IS DISTINCT FROM v_state.rhythm_rule_id
 THEN
  RAISE EXCEPTION
    'A governed original cannot commit without the one fulfilled accepted offer'
    USING ERRCODE='42501';
 END IF;

 -- U1A/U1B version source may change while the transaction is running;
 -- no stale approved scope can be substituted for the frozen versions.
 v_authority:=atlas.resolve_governed_canonical_farm_rule_authority_v1(
  v_offer.organization_id,v_offer.ledger_id,v_offer.farm_id,
  v_offer.source_rule_id,v_offer.subject_id
 );
 IF v_authority->>'state' IS DISTINCT FROM
     'native_source_admitted_for_offer'
    OR v_authority->>'candidateOfferAdmissible' IS DISTINCT FROM 'true'
    OR v_authority->>'crossSourceUncontested' IS DISTINCT FROM 'true'
    OR v_authority->>'propertyRuleVersionId'
      IS DISTINCT FROM v_offer.property_rule_version_id::text
    OR v_authority->>'effectiveRuleVersionId'
      IS DISTINCT FROM v_offer.rule_version_id::text
 THEN
  RAISE EXCEPTION 'Governed original cannot commit under changed Rulebook source'
    USING ERRCODE='42501';
 END IF;

 -- Reuse the exact U2B source's own original allocation/one Workday proof.
 -- This is an independent final-state check, not a new scheduling writer.
 SELECT a.id INTO v_allocation FROM atlas.work_allocations a
 JOIN atlas.company_work_native_ledger_relevance rel
   ON rel.organization_id=v_work.organization_id
  AND rel.work_item_id=v_work.id
  AND rel.ledger_id=v_offer.ledger_id
  AND rel.attribution_state='active'
 WHERE a.work_item_id=v_work.id AND a.organization_id=v_work.organization_id
   AND a.assignee_canonical_person_id=v_offer.target_person_id
   AND a.allocation_role='responsible' AND a.state='active'
 LIMIT 1;
 IF v_allocation IS NULL
    OR NOT EXISTS (
     SELECT 1 FROM atlas.work_execution_plans p
     WHERE p.work_item_id=v_work.id
       AND p.organization_id=v_work.organization_id
       AND p.responsible_allocation_id=v_allocation
       AND p.plan_state='active'
       AND p.planned_service_date=v_offer.first_service_day
    )
 THEN
  RAISE EXCEPTION
    'Governed original cannot commit without its accepted responsible Person and exact workday'
    USING ERRCODE='42501';
 END IF;

 -- A BEGIN/COMMIT transaction either retains all independently accepted
 -- source proofs or rolls back the whole canonical original Work.
 RETURN NULL;
END;
$final_commit$;

CREATE CONSTRAINT TRIGGER z_uni_ops_governed_original_finalization_v1
AFTER INSERT ON atlas.work_items
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
WHEN (NEW.organization_id IS NOT NULL
      AND NEW.source_object_type='rhythm_state')
EXECUTE FUNCTION atlas.require_uni_ops_original_finalize_on_commit_v1();

REVOKE ALL ON FUNCTION
 atlas.require_uni_ops_original_finalize_on_commit_v1()
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
