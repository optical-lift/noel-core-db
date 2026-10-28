-- SOURCE-ONLY DRAFT | Universal Ledger Subject disclosure with the farm
-- current-inventory adapter. This is not a role, employee seat, or task store.
-- Do not grant client EXECUTE or install in production before signed tests.
--
-- Existing append-only subject decisions are the authority. Add an exact
-- farm collection decision kind, independent of Work allocations.
ALTER TABLE atlas.subject_disclosure_decision_events_v1
  DROP CONSTRAINT subject_disclosure_supported_subject_v1;
ALTER TABLE atlas.subject_disclosure_decision_events_v1
  DROP CONSTRAINT subject_disclosure_decision_events_v1_disclosure_class_check;
ALTER TABLE atlas.subject_disclosure_decision_events_v1
  ADD CONSTRAINT subject_disclosure_decision_events_v1_disclosure_class_check
    CHECK (disclosure_class IN ('identity','condition','current_inventory'));
ALTER TABLE atlas.subject_disclosure_decision_events_v1
  ADD CONSTRAINT subject_disclosure_supported_subject_v1
    CHECK (
      (subject_domain='spatial' AND subject_kind='growing_object'
        AND disclosure_class IN ('identity','condition'))
      OR (subject_domain='event' AND subject_kind='occurrence'
        AND disclosure_class='identity')
      OR (subject_domain='spatial' AND subject_kind='farm'
        AND disclosure_class='current_inventory')
    );

-- A root-admin's explicit collection view/withhold decision. This grants
-- ONLY safe, current physical inventory via the source projection below;
-- it does not grant farm-wide old reader access, future projections, rates
-- or personal/finance notes. Each decision is an append-only original event.
CREATE OR REPLACE FUNCTION atlas.governor_set_farm_current_inventory_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_target_person_id uuid,
  p_farm_id uuid,p_decision_kind text,p_source_action_id uuid,p_reason text
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO ''
AS $grant$
DECLARE
  v_owner uuid;
  v_existing atlas.subject_disclosure_decision_events_v1%ROWTYPE;
  v_created atlas.subject_disclosure_decision_events_v1%ROWTYPE;
  v_reason text:=btrim(coalesce(p_reason,''));
BEGIN
  IF auth.uid() IS NULL OR p_organization_id IS NULL
    OR p_ledger_id IS NULL OR p_target_person_id IS NULL
    OR p_farm_id IS NULL OR p_source_action_id IS NULL
    OR p_decision_kind NOT IN ('grant','withhold')
    OR length(v_reason) NOT BETWEEN 12 AND 1600 THEN
    RAISE EXCEPTION 'Exact Ledger, farm, Person and signed inventory decision required'
      USING ERRCODE='22023';
  END IF;
  v_owner:=atlas.company_work_native_ledger_owner_self_v1(
    p_organization_id,p_ledger_id);
  IF NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,p_target_person_id)
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f
      WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
        AND f.status='active') THEN
    RAISE EXCEPTION 'A current native Ledger connection and farm are required'
      USING ERRCODE='42501';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.subject_disclosure:'||p_ledger_id::text||':'||
    p_target_person_id::text||':spatial:farm:'||p_farm_id::text||
    ':current_inventory',0));
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    'atlas.subject_action:'||p_ledger_id::text||':'||
    p_source_action_id::text,0));
  SELECT * INTO v_existing FROM atlas.subject_disclosure_decision_events_v1
  WHERE ledger_id=p_ledger_id AND source_action_id=p_source_action_id;
  IF v_existing.id IS NOT NULL THEN
    IF v_existing.organization_id IS DISTINCT FROM p_organization_id
      OR v_existing.target_person_id IS DISTINCT FROM p_target_person_id
      OR v_existing.subject_domain IS DISTINCT FROM 'spatial'
      OR v_existing.subject_kind IS DISTINCT FROM 'farm'
      OR v_existing.subject_id IS DISTINCT FROM p_farm_id
      OR v_existing.disclosure_class IS DISTINCT FROM 'current_inventory'
      OR v_existing.decision_kind IS DISTINCT FROM p_decision_kind
      OR v_existing.reason IS DISTINCT FROM v_reason
    THEN RAISE EXCEPTION 'Inventory action already used for another decision'
      USING ERRCODE='23505'; END IF;
    v_created:=v_existing;
  ELSE
    INSERT INTO atlas.subject_disclosure_decision_events_v1(
      organization_id,ledger_id,target_person_id,subject_domain,subject_kind,
      subject_id,disclosure_class,decision_kind,source_action_id,reason,
      decided_by_person_id,recorded_at)
    VALUES(p_organization_id,p_ledger_id,p_target_person_id,
      'spatial','farm',p_farm_id,'current_inventory',
      p_decision_kind,p_source_action_id,v_reason,
      v_owner,clock_timestamp())
    RETURNING * INTO v_created;
  END IF;
  RETURN jsonb_build_object('ok',true,
    'contractVersion','governed_current_subject_collection_v1',
    'decisionId',v_created.id,'sourceActionId',p_source_action_id,
    'farmId',p_farm_id,'ledgerId',p_ledger_id,
    'targetPersonId',p_target_person_id,'decisionKind',p_decision_kind,
    'currentlyGranted',atlas.has_current_subject_disclosure_v1(
      p_ledger_id,p_target_person_id,'spatial','farm',
      p_farm_id,'current_inventory'));
END;
$grant$;
REVOKE ALL ON FUNCTION atlas.governor_set_farm_current_inventory_self_api_v1(
  uuid,uuid,uuid,uuid,text,uuid,text)
  FROM PUBLIC,anon,authenticated,service_role;

-- Read-only current reality. No event/price/rhythm/plan table is scanned.
-- No metadata or unreviewed note fields leave this source.
-- A collection grant cannot override an explicit per-bed identity WITHHOLD;
-- a per-bed condition WITHHOLD keeps the bed name but hides its occupants.
CREATE OR REPLACE FUNCTION atlas.connected_person_farm_current_inventory_self_api_v1(
  p_organization_id uuid,p_ledger_id uuid,p_farm_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $inventory$
DECLARE
  v_person uuid:=atlas.current_person_id_v1();
  v_zones jsonb;
  v_objects jsonb;
  v_crops jsonb;
  v_legacy_contents jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_person IS NULL OR p_organization_id IS NULL
    OR p_ledger_id IS NULL OR p_farm_id IS NULL
    OR NOT atlas.person_has_native_ledger_connection_v1(
      p_organization_id,p_ledger_id,v_person)
    OR NOT EXISTS (
      SELECT 1 FROM atlas.ledger_organization_participations part
      JOIN atlas.ledgers l ON l.id=part.ledger_id AND l.status='active'
      WHERE part.ledger_id=p_ledger_id AND part.organization_id=p_organization_id
        AND part.status='active' AND part.ended_at IS NULL
        AND part.participation_kind IN ('governing','operating')
    )
    OR NOT EXISTS(SELECT 1 FROM atlas.farms f
      WHERE f.id=p_farm_id AND f.organization_id=p_organization_id
        AND f.status='active')
    OR NOT atlas.has_current_subject_disclosure_v1(
      p_ledger_id,v_person,'spatial','farm',p_farm_id,'current_inventory')
  THEN RAISE EXCEPTION 'Current physical inventory unavailable to this Person'
    USING ERRCODE='42501'; END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'zoneId',z.id,'label',z.label,'zoneType',z.zone_type,
    'sortOrder',z.sort_order
  ) ORDER BY z.sort_order NULLS LAST,z.label,z.id),'[]'::jsonb)
    INTO v_zones
  FROM atlas.zones z WHERE z.farm_id=p_farm_id;

  WITH visible AS MATERIALIZED (
    SELECT o.id,o.zone_id,o.label,o.object_type,o.object_mode,
      o.length_ft,o.width_ft,o.sort_order,
      coalesce((
        SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
        WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
          AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
          AND d.subject_id=o.id AND d.disclosure_class='condition'
        ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
      ),'grant')<>'withhold' AS contents_visible
    FROM atlas.growing_objects o
    WHERE o.farm_id=p_farm_id
      AND coalesce((
        SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
        WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
          AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
          AND d.subject_id=o.id AND d.disclosure_class='identity'
        ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
      ),'grant')<>'withhold'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'objectId',v.id,'zoneId',v.zone_id,'label',v.label,
    'objectType',v.object_type,'objectMode',v.object_mode,
    'lengthFt',v.length_ft,'widthFt',v.width_ft,
    'sortOrder',v.sort_order,'cropDetailsAvailable',v.contents_visible
  ) ORDER BY v.sort_order NULLS LAST,v.label,v.id),'[]'::jsonb)
  INTO v_objects FROM visible v;

  -- Active ACTUAL cycles only. A "planned" cycle may be mislabeled active:
  -- accept recorded planted/living states even if the historical migration
  -- omitted the establishment date. Flag that uncertainty explicitly.
  -- No expected harvest, germination, stems, quantities,
  -- financial fields, future cycle, private notes or opaque metadata.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'cropCycleId',c.id,'objectId',c.object_id,'cropLabel',c.crop_label,
    'variety',c.variety,'recordedStage',c.cycle_state,
    'sownDate',c.sown_date,'plantedDate',c.planted_date,
    'germinationCheckedDate',c.germination_checked_date,
    'establishmentDateKnown',(c.sown_date IS NOT NULL OR c.planted_date IS NOT NULL),
    'lastRecordedAt',c.updated_at,'source','recorded_crop_cycle'
  ) ORDER BY c.object_id,c.crop_label,c.id),'[]'::jsonb)
  INTO v_crops
  FROM atlas.crop_cycles c JOIN atlas.growing_objects o
    ON o.id=c.object_id AND o.farm_id=p_farm_id
  WHERE c.farm_id=p_farm_id AND c.lifecycle_status='active'
    AND c.cycle_state NOT IN ('planned','cancelled','failed','superseded')
    AND (
      (c.sown_date IS NOT NULL AND c.sown_date<=current_date
        AND (c.planted_date IS NULL OR c.planted_date<=current_date))
      OR (c.planted_date IS NOT NULL AND c.planted_date<=current_date
        AND (c.sown_date IS NULL OR c.sown_date<=current_date))
      OR (c.sown_date IS NULL AND c.planted_date IS NULL)
    )
    AND coalesce((
      SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=c.object_id AND d.disclosure_class='identity'
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
    ),'grant')<>'withhold'
    AND coalesce((
      SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=c.object_id AND d.disclosure_class='condition'
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
    ),'grant')<>'withhold';

  -- Legacy recorded living contents are a separate, labeled source. Only
  -- include legacy rows on beds with no active canonical crop cycle to avoid
  -- misrepresenting overlapping historical formats as distinct inhabitants.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'contentId',oc.id,'objectId',oc.object_id,'cropLabel',oc.content_label,
    'variety',oc.variety,'recordedStage',oc.status,
    'plantedDate',oc.planted_date,
    'establishmentDateKnown',(oc.planted_date IS NOT NULL),
    'lastRecordedAt',oc.updated_at,
    'source','recorded_legacy_content'
  ) ORDER BY oc.object_id,oc.content_label,oc.id),'[]'::jsonb)
  INTO v_legacy_contents
  FROM atlas.object_contents oc
  JOIN atlas.growing_objects o ON o.id=oc.object_id AND o.farm_id=p_farm_id
  WHERE oc.farm_id=p_farm_id
    AND oc.status IN ('sown','planted','establishing','established',
      'growing','living','observed','germinated','seedling','flowering',
      'blooming','budding','fruiting','browsed_alive','cut_back','stressed')
    AND (oc.planted_date IS NULL OR oc.planted_date<=current_date)
    AND NOT EXISTS(SELECT 1 FROM atlas.crop_cycles cc
      WHERE cc.object_id=oc.object_id AND cc.farm_id=p_farm_id
        AND cc.lifecycle_status='active'
        AND cc.cycle_state NOT IN ('planned','cancelled','failed','superseded'))
    AND coalesce((
      SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=oc.object_id AND d.disclosure_class='identity'
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
    ),'grant')<>'withhold'
    AND coalesce((
      SELECT d.decision_kind FROM atlas.subject_disclosure_decision_events_v1 d
      WHERE d.ledger_id=p_ledger_id AND d.target_person_id=v_person
        AND d.subject_domain='spatial' AND d.subject_kind='growing_object'
        AND d.subject_id=oc.object_id AND d.disclosure_class='condition'
      ORDER BY d.recorded_at DESC,d.id DESC LIMIT 1
    ),'grant')<>'withhold';

  RETURN jsonb_build_object(
    'ok',true,'contractVersion','connected_person_current_physical_inventory_v1',
    'organizationId',p_organization_id,'ledgerId',p_ledger_id,
    'farmId',p_farm_id,'zones',v_zones,'objects',v_objects,
    'recordedCrops',v_crops,'legacyRecordedContents',v_legacy_contents,
    'currentOnly',true,'futurePlansIncluded',false,'financialsIncluded',false,
    'notAPhysicalObservation',true,'readOnly',true);
END;
$inventory$;
REVOKE ALL ON FUNCTION atlas.connected_person_farm_current_inventory_self_api_v1(
 uuid,uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
