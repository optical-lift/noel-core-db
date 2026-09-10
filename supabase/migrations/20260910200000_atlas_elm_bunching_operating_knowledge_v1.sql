-- Elm Farm bunching standards as established Company Operating Knowledge.
-- Resolves Elm from canonical farm identity; no generated production IDs are hardcoded.

BEGIN;

DO $$
DECLARE
  v_organization_id uuid;
  v_organization_unit_id uuid;
  v_default_id uuid;
  v_goldenrod_id uuid;
  v_sunflower_id uuid;
  v_match_count integer;
BEGIN
  SELECT count(*)::integer
    INTO v_match_count
  FROM atlas.farms f
  WHERE f.stable_key = 'elm_farm'
    AND f.status = 'active';

  IF v_match_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one active canonical farm with stable_key=elm_farm; found %', v_match_count;
  END IF;

  SELECT f.organization_id, f.organization_unit_id
    INTO v_organization_id, v_organization_unit_id
  FROM atlas.farms f
  WHERE f.stable_key = 'elm_farm'
    AND f.status = 'active';

  IF v_organization_id IS NULL OR v_organization_unit_id IS NULL THEN
    RAISE EXCEPTION 'Elm Farm must have both organization_id and organization_unit_id before operating knowledge can be established.';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM atlas.company_operating_knowledge k
    WHERE k.organization_id = v_organization_id
      AND k.organization_unit_id = v_organization_unit_id
      AND k.stable_key IN (
        'elm.cut_flower.bunch.default',
        'elm.cut_flower.bunch.goldenrod',
        'elm.cut_flower.bunch.sunflower'
      )
  ) THEN
    RAISE EXCEPTION 'One or more Elm bunching operating-knowledge stable keys already exist; adjudicate/version rather than duplicate.';
  END IF;

  INSERT INTO atlas.company_operating_knowledge (
    organization_id, organization_unit_id, family_key, stable_key, version,
    knowledge_kind, title, statement, scope_match, effect, precedence,
    status, confidence, effective_from, established_by_label, established_at,
    provenance, metadata
  ) VALUES (
    v_organization_id,
    v_organization_unit_id,
    'cut_flower_bunch_size',
    'elm.cut_flower.bunch.default',
    1,
    'standard',
    'Elm cut-flower bunch default',
    'At Elm Farm, cut flowers are normally bunched in 10 stems unless a more-specific established product rule applies.',
    jsonb_build_object('operation','bunch','category','cut_flower'),
    jsonb_build_object('sales_unit','bunch','quantity_per_unit',10,'quantity_unit','stem'),
    0,
    'established',
    1.0000,
    '2026-09-10 00:00:00-05'::timestamptz,
    'Elm Farm owner',
    now(),
    jsonb_build_object('source_kind','owner_declared_operating_standard','confirmed_on','2026-09-10','implementation_context','Atlas Company Operating Knowledge v1'),
    jsonb_build_object('farm_stable_key','elm_farm')
  ) RETURNING id INTO v_default_id;

  INSERT INTO atlas.company_operating_knowledge (
    organization_id, organization_unit_id, family_key, stable_key, version,
    knowledge_kind, title, statement, scope_match, effect, precedence,
    status, confidence, effective_from, established_by_label, established_at,
    provenance, metadata
  ) VALUES (
    v_organization_id,
    v_organization_unit_id,
    'cut_flower_bunch_size',
    'elm.cut_flower.bunch.goldenrod',
    1,
    'standard',
    'Elm goldenrod bunch size',
    'At Elm Farm, goldenrod is bunched in 5 stems.',
    jsonb_build_object('operation','bunch','category','cut_flower','product','goldenrod'),
    jsonb_build_object('sales_unit','bunch','quantity_per_unit',5,'quantity_unit','stem'),
    0,
    'established',
    1.0000,
    '2026-09-10 00:00:00-05'::timestamptz,
    'Elm Farm owner',
    now(),
    jsonb_build_object('source_kind','owner_declared_operating_standard','confirmed_on','2026-09-10','implementation_context','Atlas Company Operating Knowledge v1'),
    jsonb_build_object('farm_stable_key','elm_farm')
  ) RETURNING id INTO v_goldenrod_id;

  INSERT INTO atlas.company_operating_knowledge (
    organization_id, organization_unit_id, family_key, stable_key, version,
    knowledge_kind, title, statement, scope_match, effect, precedence,
    status, confidence, effective_from, established_by_label, established_at,
    provenance, metadata
  ) VALUES (
    v_organization_id,
    v_organization_unit_id,
    'cut_flower_bunch_size',
    'elm.cut_flower.bunch.sunflower',
    1,
    'standard',
    'Elm sunflower bunch size',
    'At Elm Farm, sunflowers are bunched in 5 stems.',
    jsonb_build_object('operation','bunch','category','cut_flower','product','sunflower'),
    jsonb_build_object('sales_unit','bunch','quantity_per_unit',5,'quantity_unit','stem'),
    0,
    'established',
    1.0000,
    '2026-09-10 00:00:00-05'::timestamptz,
    'Elm Farm owner',
    now(),
    jsonb_build_object('source_kind','owner_declared_operating_standard','confirmed_on','2026-09-10','implementation_context','Atlas Company Operating Knowledge v1'),
    jsonb_build_object('farm_stable_key','elm_farm')
  ) RETURNING id INTO v_sunflower_id;

  INSERT INTO atlas.company_operating_knowledge_evidence (
    organization_id, knowledge_id, evidence_kind, interpretation_kind,
    source_locator, evidence_snapshot, note, observed_at
  )
  SELECT
    v_organization_id,
    x.knowledge_id,
    'other',
    'originates',
    jsonb_build_object('kind','owner_declaration','context','Atlas implementation'),
    jsonb_build_object('statement',x.statement),
    'Owner-established Elm Farm operating standard.',
    now()
  FROM (VALUES
    (v_default_id, 'Cut flowers normally bunch in 10 stems unless a product exception applies.'),
    (v_goldenrod_id, 'Goldenrod bunches in 5 stems.'),
    (v_sunflower_id, 'Sunflowers bunch in 5 stems.')
  ) AS x(knowledge_id, statement);

  INSERT INTO atlas.company_operating_knowledge_adjudications (
    organization_id, knowledge_id, decision_kind, basis,
    evidence_snapshot, adjudicated_by_label
  )
  SELECT
    v_organization_id,
    x.knowledge_id,
    'establish',
    'Elm Farm owner established this as current operating truth for bunch preparation.',
    jsonb_build_object('effective_date','2026-09-10','farm_stable_key','elm_farm'),
    'Elm Farm owner'
  FROM (VALUES (v_default_id), (v_goldenrod_id), (v_sunflower_id)) AS x(knowledge_id);
END;
$$;

COMMIT;
