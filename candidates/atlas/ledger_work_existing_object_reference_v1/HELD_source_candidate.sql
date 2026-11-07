-- HELD / SOURCE REVIEW ONLY. NOT A MIGRATION; NEVER APPLY TO PRODUCTION.
-- Owner decision (2026-11-07): one physical Object can be referenced by Work
-- owned by multiple independent native Ledgers. Creating a reference is NOT
-- permission to mutate the physical Object or read its sensitive source data.
-- This first source adapter admits existing Beds in the SAME Organization.
-- It supersedes the dual-governor venue_bed_shared_use offer for mere reference.
-- Never replace the original Flower growing-object Work-context guard.
BEGIN;

CREATE TABLE atlas.ledger_work_existing_bed_references_v1 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES atlas.organizations(id) ON DELETE RESTRICT,
  ledger_id uuid NOT NULL REFERENCES ledger.ledgers(id) ON DELETE RESTRICT,
  work_item_id uuid NOT NULL REFERENCES atlas.work_items(id) ON DELETE RESTRICT,
  bed_id uuid NOT NULL REFERENCES atlas.growing_objects(id) ON DELETE RESTRICT,
  recorded_by_person_id uuid NOT NULL REFERENCES reality.entities(id) ON DELETE RESTRICT,
  source_action_id text NOT NULL CHECK (
    length(btrim(source_action_id)) BETWEEN 1 AND 128
  ),
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ledger_work_existing_bed_one_reference_v1
    UNIQUE (ledger_id, work_item_id, bed_id),
  CONSTRAINT ledger_work_existing_bed_action_idempotent_v1
    UNIQUE (ledger_id, source_action_id)
);

-- Private source relation. No authenticated table reads, no new generic
-- Work/context permissions, and no Bed identity catalogue are exposed.
ALTER TABLE atlas.ledger_work_existing_bed_references_v1 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE atlas.ledger_work_existing_bed_references_v1
  FROM PUBLIC, anon, authenticated;

-- Attach an ALREADY EXISTING original Work to the SAME original physical Bed.
-- Source authoring is verified exclusively in the TARGET Ledger. Neither the
-- Bed custodian's Principal nor the compatibility-primary Organization root
-- has to participate in a mere reference.
CREATE FUNCTION atlas.establish_ledger_work_existing_bed_reference_self_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_work_item_id uuid,
  p_bed_id uuid,
  p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_actor uuid;
  v_principal uuid;
  v_work atlas.work_items%ROWTYPE;
  v_existing atlas.ledger_work_existing_bed_references_v1%ROWTYPE;
  v_ledger_root boolean;
BEGIN
  IF auth.uid() IS NULL
     OR (atlas.reality_access_self_api_v1()->>'state') IS DISTINCT FROM 'ready'
     OR p_organization_id IS NULL OR p_ledger_id IS NULL
     OR p_work_item_id IS NULL OR p_bed_id IS NULL
  THEN
    RAISE EXCEPTION 'Current authenticated target Ledger and exact Work required'
      USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_source_action_id,''))) NOT BETWEEN 1 AND 128 THEN
    RAISE EXCEPTION 'Stable action required' USING ERRCODE='22023';
  END IF;
  v_actor:=atlas.current_person_id_v1();
  v_principal:=atlas.current_principal_id_v1();
  IF v_actor IS NULL OR v_principal IS NULL
     OR NOT atlas.person_has_native_ledger_connection_v1(
       p_organization_id,p_ledger_id,v_actor)
     OR NOT EXISTS (
       SELECT 1 FROM atlas.ledger_organization_participations part
       JOIN atlas.ledgers app ON app.id=part.ledger_id
         AND app.status='active'
       JOIN ledger.ledgers native ON native.id=part.ledger_id
         AND native.ledger_state='active' AND native.retired_at IS NULL
       WHERE part.ledger_id=p_ledger_id
         AND part.organization_id=p_organization_id
         AND part.status='active' AND part.ended_at IS NULL
         AND part.participation_kind IN ('governing','operating')
     )
  THEN
    RAISE EXCEPTION 'Target Ledger Work unavailable' USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);

  -- Never read or alter an unrelated Ledger's Work. An exact, active source
  -- relevance must already bind the original Work to this target Ledger.
  SELECT * INTO v_work FROM atlas.work_items w
  WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id;
  IF v_work.id IS NULL OR NOT EXISTS (
     SELECT 1 FROM atlas.company_work_native_ledger_relevance relevance
     WHERE relevance.organization_id=p_organization_id
       AND relevance.ledger_id=p_ledger_id
       AND relevance.work_item_id=v_work.id
       AND relevance.attribution_state='active'
  ) THEN
    RAISE EXCEPTION 'Target Ledger Work unavailable' USING ERRCODE='42501';
  END IF;

  -- Two ALREADY ADMITTED authoring paths:
  -- (1) exact current native Ledger governing principal; or
  -- (2) a person whom the existing Event source allows to author shared Work
  --     for THIS Ledger's exact active Occurrence.
  -- A mere Seat without either source authority is NOT a general write grant.
  v_ledger_root:=coalesce(atlas.principal_has_ledger_authority_v1(
    v_principal,p_ledger_id),false);
  IF NOT v_ledger_root THEN
    IF v_work.source_object_type IS DISTINCT FROM 'ledger_occurrence_shared_work'
       OR v_work.source_object_id IS NULL
       OR v_work.metadata->>'ledgerId' IS DISTINCT FROM p_ledger_id::text
       OR v_work.result_contract_key IS DISTINCT FROM
         'ledger_occurrence_shared_confirmation_v1'
    THEN
      RAISE EXCEPTION 'Exact target Ledger author permission required'
        USING ERRCODE='42501';
    END IF;
    PERFORM atlas.ledger_occurrence_shared_work_actor_self_v1(
      p_organization_id,p_ledger_id,v_work.source_object_id);
  END IF;

  -- Object identity is checked against its real source, without requiring
  -- the Flower Ledger governor's offer/accept or copying Bed/condition data.
  -- This first adapter deliberately stays within one Organization: external
  -- organizations require their own evidence and disclosure review.
  IF NOT EXISTS (
    SELECT 1 FROM atlas.growing_objects bed
    JOIN atlas.farms farm ON farm.id=bed.farm_id
      AND farm.organization_id=p_organization_id AND farm.status='active'
    WHERE bed.id=p_bed_id AND bed.object_type='bed'
  ) THEN
    RAISE EXCEPTION 'Referenced physical Object unavailable'
      USING ERRCODE='42501';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.existing-bed-work-reference:'||p_ledger_id::text||':'||
      p_work_item_id::text,0));
  -- Serialize against the original Work state. Never create new Work here.
  SELECT * INTO v_work FROM atlas.work_items w
    WHERE w.id=p_work_item_id AND w.organization_id=p_organization_id
    FOR UPDATE;
  IF v_work.id IS NULL OR NOT EXISTS (
    SELECT 1 FROM atlas.company_work_native_ledger_relevance relevance
    WHERE relevance.organization_id=p_organization_id
      AND relevance.ledger_id=p_ledger_id
      AND relevance.work_item_id=v_work.id
      AND relevance.attribution_state='active'
  ) THEN
    RAISE EXCEPTION 'Target Ledger Work unavailable' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_existing
    FROM atlas.ledger_work_existing_bed_references_v1 r
    WHERE r.ledger_id=p_ledger_id
      AND r.source_action_id=p_source_action_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.organization_id<>p_organization_id
       OR v_existing.work_item_id<>p_work_item_id
       OR v_existing.bed_id<>p_bed_id
       OR v_existing.recorded_by_person_id<>v_actor
    THEN
      RAISE EXCEPTION 'Source action reused for a different reference'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'referenceId',v_existing.id,'idempotent',true,
      'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
      'bedId',p_bed_id,'newWorkCreated',false,'newObjectCreated',false,
      'physicalCustodyChanged',false,'otherLedgerReadGranted',false);
  END IF;
  IF v_work.work_state<>'open' THEN
    RAISE EXCEPTION 'Only active original Work can gain a new reference'
      USING ERRCODE='23514';
  END IF;
  IF EXISTS (
    SELECT 1 FROM atlas.ledger_work_existing_bed_references_v1 r
    WHERE r.ledger_id=p_ledger_id
      AND r.work_item_id=p_work_item_id AND r.bed_id=p_bed_id
  ) THEN
    RAISE EXCEPTION 'Original Work already references this physical Object'
      USING ERRCODE='23505';
  END IF;
  INSERT INTO atlas.ledger_work_existing_bed_references_v1(
    organization_id,ledger_id,work_item_id,bed_id,
    recorded_by_person_id,source_action_id
  ) VALUES (
    p_organization_id,p_ledger_id,p_work_item_id,p_bed_id,
    v_actor,p_source_action_id
  ) RETURNING * INTO v_existing;
  RETURN jsonb_build_object(
    'ok',true,'referenceId',v_existing.id,'idempotent',false,
    'ledgerId',p_ledger_id,'workItemId',p_work_item_id,
    'bedId',p_bed_id,'newWorkCreated',false,'newObjectCreated',false,
    'physicalCustodyChanged',false,'otherLedgerReadGranted',false);
END;
$$;

-- No public RPC wrapper; authenticated execution requires separately reviewed
-- clone-only test exposure or a later approved source API. DDL and interface
-- are held; this is not an installed/released function.
REVOKE ALL ON FUNCTION
  atlas.establish_ledger_work_existing_bed_reference_self_v1(
    uuid,uuid,uuid,uuid,text)
  FROM PUBLIC, anon, authenticated;

COMMIT;
