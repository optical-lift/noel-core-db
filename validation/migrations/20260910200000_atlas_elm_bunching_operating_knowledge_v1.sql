-- Postconditions for Elm Farm bunching Company Operating Knowledge.
-- Runs in the governed disposable production-schema clone.

DO $$
DECLARE
  v_organization_id uuid;
  v_organization_unit_id uuid;
  v_count integer;
BEGIN
  SELECT f.organization_id, f.organization_unit_id
    INTO v_organization_id, v_organization_unit_id
  FROM atlas.farms f
  WHERE f.stable_key='elm_farm' AND f.status='active';

  IF v_organization_id IS NULL OR v_organization_unit_id IS NULL THEN
    RAISE EXCEPTION 'Elm Farm canonical organization binding missing.';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.company_operating_knowledge k
  WHERE k.organization_id=v_organization_id
    AND k.organization_unit_id=v_organization_unit_id
    AND k.family_key='cut_flower_bunch_size'
    AND k.status='established'
    AND k.stable_key IN (
      'elm.cut_flower.bunch.default',
      'elm.cut_flower.bunch.goldenrod',
      'elm.cut_flower.bunch.sunflower'
    );
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected exactly 3 established Elm bunching standards; found %', v_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_operating_knowledge k
    WHERE k.organization_id=v_organization_id
      AND k.organization_unit_id=v_organization_unit_id
      AND k.stable_key='elm.cut_flower.bunch.default'
      AND k.scope_match=jsonb_build_object('operation','bunch','category','cut_flower')
      AND k.effect @> jsonb_build_object('sales_unit','bunch','quantity_per_unit',10,'quantity_unit','stem')
  ) THEN
    RAISE EXCEPTION 'Elm default 10-stem bunch standard missing or malformed.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_operating_knowledge k
    WHERE k.organization_id=v_organization_id
      AND k.organization_unit_id=v_organization_unit_id
      AND k.stable_key='elm.cut_flower.bunch.goldenrod'
      AND k.scope_match=jsonb_build_object('operation','bunch','category','cut_flower','product','goldenrod')
      AND k.effect @> jsonb_build_object('sales_unit','bunch','quantity_per_unit',5,'quantity_unit','stem')
  ) THEN
    RAISE EXCEPTION 'Elm goldenrod 5-stem bunch exception missing or malformed.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM atlas.company_operating_knowledge k
    WHERE k.organization_id=v_organization_id
      AND k.organization_unit_id=v_organization_unit_id
      AND k.stable_key='elm.cut_flower.bunch.sunflower'
      AND k.scope_match=jsonb_build_object('operation','bunch','category','cut_flower','product','sunflower')
      AND k.effect @> jsonb_build_object('sales_unit','bunch','quantity_per_unit',5,'quantity_unit','stem')
  ) THEN
    RAISE EXCEPTION 'Elm sunflower 5-stem bunch exception missing or malformed.';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.company_operating_knowledge_evidence e
  JOIN atlas.company_operating_knowledge k ON k.id=e.knowledge_id
  WHERE k.organization_id=v_organization_id
    AND k.organization_unit_id=v_organization_unit_id
    AND k.stable_key IN (
      'elm.cut_flower.bunch.default',
      'elm.cut_flower.bunch.goldenrod',
      'elm.cut_flower.bunch.sunflower'
    )
    AND e.interpretation_kind='originates';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected one originating evidence row per Elm bunching standard; found %', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.company_operating_knowledge_adjudications a
  JOIN atlas.company_operating_knowledge k ON k.id=a.knowledge_id
  WHERE k.organization_id=v_organization_id
    AND k.organization_unit_id=v_organization_unit_id
    AND k.stable_key IN (
      'elm.cut_flower.bunch.default',
      'elm.cut_flower.bunch.goldenrod',
      'elm.cut_flower.bunch.sunflower'
    )
    AND a.decision_kind='establish';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected one establishment adjudication per Elm bunching standard; found %', v_count;
  END IF;
END;
$$;
