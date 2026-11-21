-- UNI-OPS-01 U2C/P3: one CANONICAL ORIGINAL INSERT enforcement boundary.
-- HELD, do not install without exact R01/U1A/U1B/U2A/U2C source.
--
-- Scope is narrow: existing atlas.work_items rows rooted in an original
-- Organization rhythm_state already covered by a U1A exact Subject or U1B
-- native farm rule decision. It does not alter Household, Event, Company
-- communications, conversion, general Ledger, or ungovened old Work.
-- It is not another Work writer or another acceptance/offer implementation.
--
-- This guard runs BEFORE the canonical R01 insert is completed, when the
-- original Work's authoritative servingKey/sourceContract metadata exists.
-- The later separate U2C owner writer still must atomically link Ledger,
-- recipient, plan and fulfillment; this trigger does NOT grant them.
BEGIN;
DO $cutover_dependencies$
BEGIN
 IF pg_catalog.to_regprocedure(
  'atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(uuid)'
 ) IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.uni_ops_accepted_first_original_source_receipt_held_v1(uuid)'
 ) IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.require_accepted_prework_standing_original_v1(uuid,uuid,uuid,uuid,text,date,date,smallint[],uuid)'
 ) IS NULL
 OR pg_catalog.to_regclass('atlas.governed_prework_candidate_offers_v1')
    IS NULL
 OR pg_catalog.to_regprocedure(
  'atlas.establish_continuing_original_work_internal_v1(text,uuid,uuid,text,uuid,text,text,text,uuid,text,text,text)'
 ) IS NULL
 THEN RAISE EXCEPTION
  'Original R01 + original U1/U2C source, exact accepted-first receipt and governed clock guard are required';
 END IF;
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_trigger
  WHERE tgrelid='atlas.work_items'::regclass
    AND tgname='c_uni_ops_governed_care_original_acceptance_v1'
    AND NOT tgisinternal
 ) THEN
  RAISE EXCEPTION 'Guard already exists; do not replace without source-owner review';
 END IF;
END;
$cutover_dependencies$;

CREATE FUNCTION atlas.guard_uni_ops_governed_care_original_acceptance_v1()
RETURNS trigger
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $governed_original$
DECLARE
 v_need atlas.rhythm_state%ROWTYPE;
 v_offer atlas.governed_prework_candidate_offers_v1%ROWTYPE;
 v_serving text;
 v_receipt jsonb;
 v_expected_stable text;
BEGIN
 IF NEW.organization_id IS NULL THEN
  RETURN NEW;
 END IF;

 -- The existing C1 physical Result contract is specific to one original
 -- native rhythm source. An unknown source kind is not a safe migration
 -- or an authorization bypass even before Rulebook lookups.
 IF NEW.result_contract_key='continuing_care_actual_v1'
   AND (NEW.source_object_type IS DISTINCT FROM 'rhythm_state'
        OR NEW.source_object_id IS NULL)
 THEN RAISE EXCEPTION
   'Care original must preserve its exact native rhythm source'
   USING ERRCODE='42501';
 END IF;

 IF NEW.source_object_type IS DISTINCT FROM 'rhythm_state'
   OR NEW.source_object_id IS NULL
 THEN RETURN NEW; END IF;

 -- First party native Need identity, never a title, metadata label or
 -- client supplied farm alias.
 SELECT * INTO v_need FROM atlas.rhythm_state s
 WHERE s.id=NEW.source_object_id AND s.organization_id=NEW.organization_id;
 IF v_need.id IS NULL THEN
  IF NEW.result_contract_key='continuing_care_actual_v1' THEN
   RAISE EXCEPTION 'Care original requires a real native rhythm Need'
     USING ERRCODE='42501';
  END IF;
  RETURN NEW;
 END IF;

 -- No new U1A/U1B source decision: preserve existing original Work paths.
 -- The helper uses real original source tables, not claims in NEW.metadata.
 IF NOT atlas.uni_ops_legacy_rhythm_under_governed_rulebook_held_v1(
   v_need.id
 ) THEN RETURN NEW; END IF;

 IF TG_OP='UPDATE' THEN
   -- A previously valid Work is not reissued by an edit, Done, or a
   -- later Rulebook pause/review. But its source, original idempotency
   -- key and physical Result contract are immutable after governance.
   IF OLD.organization_id IS DISTINCT FROM NEW.organization_id
      OR OLD.source_object_type IS DISTINCT FROM NEW.source_object_type
      OR OLD.source_object_id IS DISTINCT FROM NEW.source_object_id
      OR OLD.result_contract_key IS DISTINCT FROM NEW.result_contract_key
      OR OLD.stable_key IS DISTINCT FROM NEW.stable_key
      OR OLD.metadata->>'servingKey' IS DISTINCT FROM
         NEW.metadata->>'servingKey'
      OR OLD.metadata->>'sourceContract' IS DISTINCT FROM
         NEW.metadata->>'sourceContract'
   THEN
     RAISE EXCEPTION 'Governed care original source is immutable'
       USING ERRCODE='42501';
   END IF;
   RETURN NEW;
 END IF;

 -- This transaction cannot borrow an existing offer for another
 -- Organization, Need, native Subject, serving or current Person.
 IF NEW.household_id IS NOT NULL OR NEW.work_state<>'open'
    OR NEW.result_contract_key IS DISTINCT FROM
      'continuing_care_actual_v1'
    OR NEW.metadata->>'sourceContract' IS DISTINCT FROM
      'continuing_original_work_v1'
    OR NEW.metadata->>'needKind' IS DISTINCT FROM 'rhythm_state'
    OR NEW.metadata->>'needId' IS DISTINCT FROM v_need.id::text
    OR NEW.metadata->>'sourceConfirmedBy' IS DISTINCT FROM
      'governed_domain_writer'
    OR NEW.metadata->>'noCalendarDateInferred' IS DISTINCT FROM 'true'
    OR NEW.metadata->>'noClockAdmissionInferred' IS DISTINCT FROM 'true'
    OR auth.uid() IS NULL
    OR NEW.created_by_user_id IS DISTINCT FROM auth.uid()
 THEN
  RAISE EXCEPTION
    'Governed original requires exact R01 Need/Work contract and signed source'
    USING ERRCODE='42501';
 END IF;

 v_serving:=NULLIF(pg_catalog.btrim(NEW.metadata->>'servingKey'),'');
 IF v_serving IS NULL OR v_serving !~
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
 THEN
  RAISE EXCEPTION 'Original must use exact independently accepted offer UUID'
    USING ERRCODE='42501';
 END IF;

 -- Original native R01 idempotency is source-owned, not metadata-only.
 v_expected_stable:='continuing:v1:'||pg_catalog.md5(
  'organization:'||NEW.organization_id::text||
  ':rhythm_state:'||v_need.id::text||':'||v_serving);
 IF NEW.stable_key IS DISTINCT FROM v_expected_stable THEN
  RAISE EXCEPTION 'Canonical original idempotency must match its source offer'
    USING ERRCODE='42501';
 END IF;

 SELECT * INTO v_offer
 FROM atlas.governed_prework_candidate_offers_v1 o
 WHERE o.id=v_serving::uuid FOR SHARE;
 IF v_offer.id IS NULL OR v_offer.offer_state<>'accepted'
    OR v_offer.original_work_item_id IS NOT NULL
    OR v_offer.organization_id IS DISTINCT FROM NEW.organization_id
    OR v_offer.source_candidate_id IS DISTINCT FROM v_need.id
    OR v_offer.farm_id IS DISTINCT FROM v_need.farm_id
    OR v_offer.subject_id IS DISTINCT FROM v_need.subject_id
    OR v_offer.source_rule_id IS DISTINCT FROM v_need.rhythm_rule_id
 THEN
  RAISE EXCEPTION 'Original Work needs one current accepted original source offer'
    USING ERRCODE='42501';
 END IF;

 -- Reuses the U2C guard, current real native owner, immutable frozen policy
 -- versions, independent accepted worker and capacity. Reads only.
 v_receipt:=atlas.uni_ops_accepted_first_original_source_receipt_held_v1(
   v_offer.id
 );
 IF v_receipt->>'state' IS DISTINCT FROM
    'accepted_source_checks_current_for_review_only'
    OR v_receipt->>'sourceOfferId' IS DISTINCT FROM v_offer.id::text
    OR v_receipt->>'sourceSubjectId' IS DISTINCT FROM v_need.subject_id::text
    OR v_receipt->>'effectiveApprovedRulebookVersionId'
       IS DISTINCT FROM v_offer.rule_version_id::text
    OR v_receipt->>'sourcePreflightIsNotAnIssuanceReservation'
       IS DISTINCT FROM 'true'
 THEN
  RAISE EXCEPTION 'A current single Rulebook and acceptance receipt is required'
    USING ERRCODE='42501';
 END IF;

 -- The original R01 U2C writer still must prove, in the SAME transaction,
 -- exact Ledger relevance, responsible accepted Person, dated execution
 -- plan and source-consistent offer fulfillment. This guard only closes
 -- the alternative INSERT route; it creates no Work by itself.
 RETURN NEW;
END;
$governed_original$;

CREATE TRIGGER c_uni_ops_governed_care_original_acceptance_v1
BEFORE INSERT OR UPDATE OF
 source_object_type,source_object_id,result_contract_key,metadata
ON atlas.work_items
FOR EACH ROW
EXECUTE FUNCTION atlas.guard_uni_ops_governed_care_original_acceptance_v1();

REVOKE ALL ON FUNCTION
 atlas.guard_uni_ops_governed_care_original_acceptance_v1()
 FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
