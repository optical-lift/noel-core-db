-- HELD SOURCE CANDIDATE ONLY. NOT A PRODUCTION MIGRATION OR RELEASE.
-- Purpose: remove only the Sept 14, 2026 clean-room Feast Guild TEST
-- Organization / old Atlas Ledger / participation / root authority, once
-- separately signed current-schema clone and exact owner release are approved.
-- Do not delete any Person, Work, Elm, historical audit or native Ledger.
-- NO CASCADE; no direct production execution. This script is one transaction.
DO $feast_test_retire$
DECLARE
  v_organization_id uuid;
  v_ledger_id uuid;
  v_root_id uuid;
  v_participation_id uuid;
  v_fk record;
  v_column record;
  v_target uuid;
  v_count bigint;
  v_row_count bigint;
  v_org_count_before bigint;
  v_ledger_count_before bigint;
BEGIN
  -- Recognize the SOURCE-ESTABLISHED September 14 clean-room institution.
  -- Stable keys alone are insufficient; every source/identity guard must agree.
  SELECT id INTO STRICT v_organization_id
  FROM atlas.organizations
  WHERE stable_key='feast_guild'
    AND name='Feast Guild'
    AND status='active'
    AND onboarding_state='new'
    AND created_at >= timestamptz '2026-09-14 00:00:00+00'
    AND created_at < timestamptz '2026-09-15 00:00:00+00'
    AND metadata->>'canonicalInstitution'='Feast Guild'
  FOR UPDATE;

  SELECT id INTO STRICT v_ledger_id
  FROM atlas.ledgers
  WHERE stable_key='feast_guild'
    AND name='Feast Guild'
    AND status='active'
    AND ledger_kind='governed_reality'
    AND created_at >= timestamptz '2026-09-14 00:00:00+00'
    AND created_at < timestamptz '2026-09-15 00:00:00+00'
    AND metadata->>'canonicalEndeavor'='Feast Guild'
  FOR UPDATE;

  IF EXISTS (SELECT 1 FROM atlas.ledgers
             WHERE id=v_ledger_id AND organization_id IS NOT NULL)
  THEN
    RAISE EXCEPTION 'Retirement withheld: Ledger has separately owned Organization custody.';
  END IF;

  SELECT count(*) INTO v_org_count_before FROM atlas.organizations;
  SELECT count(*) INTO v_ledger_count_before FROM atlas.ledgers;

  -- Exactly one governed participation and one root; no third-party occupants.
  IF (SELECT count(*) FROM atlas.ledger_organization_participations
      WHERE ledger_id=v_ledger_id OR organization_id=v_organization_id) <> 1
  THEN RAISE EXCEPTION 'Retirement withheld: unexpected Ledger participation graph.'; END IF;

  SELECT id INTO STRICT v_participation_id
  FROM atlas.ledger_organization_participations
  WHERE ledger_id=v_ledger_id AND organization_id=v_organization_id
    AND participation_kind='governing'
    AND is_compatibility_primary IS TRUE
    AND status='active' AND ended_at IS NULL
  FOR UPDATE;

  IF (SELECT count(*) FROM atlas.principal_ledger_authorities
      WHERE ledger_id=v_ledger_id) <> 1
  THEN RAISE EXCEPTION 'Retirement withheld: unexpected root authority graph.'; END IF;

  SELECT id INTO STRICT v_root_id
  FROM atlas.principal_ledger_authorities
  WHERE ledger_id=v_ledger_id
    AND authority_kind='root_governing'
    AND status='active' AND ended_at IS NULL
  FOR UPDATE;

  -- Native source not activated: deletion must never retire genuine native seats.
  IF EXISTS (SELECT 1 FROM ledger.ledgers WHERE id=v_ledger_id)
     OR EXISTS (SELECT 1 FROM ledger.onboarding_cases
        WHERE onboarding_basis->>'legacyLedgerId'=v_ledger_id::text)
  THEN RAISE EXCEPTION 'Retirement withheld: native Ledger/onboarding source exists.'; END IF;

  -- Every direct FK, across all schemas, must either be empty or be precisely
  -- the two expected intra-target relationships. No guessed table allowlists.
  FOR v_fk IN
    SELECT con.conrelid::regclass AS dependent_rel,
           con.confrelid::regclass AS target_rel,
           att.attname AS fk_column,
           cardinality(con.conkey) AS fk_width
    FROM pg_constraint con
    JOIN pg_attribute att
      ON att.attrelid=con.conrelid AND att.attnum=con.conkey[1]
    WHERE con.contype='f'
      AND con.confrelid IN ('atlas.organizations'::regclass,
                            'atlas.ledgers'::regclass,
                            'atlas.principal_ledger_authorities'::regclass)
  LOOP
    IF v_fk.fk_width<>1 THEN
      RAISE EXCEPTION 'Retirement withheld: composite FK requires independent review.';
    END IF;
    v_target := CASE v_fk.target_rel
      WHEN 'atlas.organizations'::regclass THEN v_organization_id
      WHEN 'atlas.ledgers'::regclass THEN v_ledger_id
      ELSE v_root_id END;
    EXECUTE format('SELECT count(*) FROM %s WHERE %I=$1',
                   v_fk.dependent_rel,v_fk.fk_column)
    INTO v_count USING v_target;

    IF v_count>0 AND NOT (
       v_count=1
       AND (
         (v_fk.dependent_rel='atlas.ledger_organization_participations'::regclass
          AND v_fk.target_rel IN ('atlas.organizations'::regclass,'atlas.ledgers'::regclass)
          AND v_fk.fk_column IN ('organization_id','ledger_id'))
         OR
         (v_fk.dependent_rel='atlas.principal_ledger_authorities'::regclass
          AND v_fk.target_rel='atlas.ledgers'::regclass
          AND v_fk.fk_column='ledger_id')
       )
    ) THEN
      RAISE EXCEPTION 'Retirement withheld: additional FK-dependent state in %.',
        v_fk.dependent_rel;
    END IF;
  END LOOP;

  -- Refuse unconstrained UUID pointers into this identity, too.
  FOR v_column IN
    SELECT co.table_schema,co.table_name,co.column_name
    FROM information_schema.columns co
    JOIN information_schema.tables t
      ON t.table_schema=co.table_schema AND t.table_name=co.table_name
     AND t.table_type='BASE TABLE'
    WHERE co.table_schema IN ('atlas','ledger','reality','public')
      AND co.data_type='uuid'
      AND co.column_name IN ('organization_id','ledger_id',
                             'principal_ledger_authority_id','institution_id')
      AND NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=ANY(c.conkey)
        WHERE c.contype='f'
          AND c.conrelid=to_regclass(format('%I.%I',co.table_schema,co.table_name))
          AND a.attname=co.column_name
          AND c.confrelid IN ('atlas.organizations'::regclass,
                              'atlas.ledgers'::regclass,
                              'atlas.principal_ledger_authorities'::regclass)
      )
  LOOP
    v_target := CASE
       WHEN v_column.column_name IN ('organization_id','institution_id')
       THEN v_organization_id
       WHEN v_column.column_name='ledger_id' THEN v_ledger_id
       ELSE v_root_id END;
    EXECUTE format('SELECT count(*) FROM %I.%I WHERE %I=$1',
                   v_column.table_schema,v_column.table_name,v_column.column_name)
    INTO v_count USING v_target;
    IF v_count<>0 THEN
      RAISE EXCEPTION 'Retirement withheld: unguarded UUID reference in %.%',
        v_column.table_schema,v_column.table_name;
    END IF;
  END LOOP;

  -- Preserve text-subject provenance and audit records without rewriting them.
  IF EXISTS (SELECT 1 FROM atlas.organization_ledger_subjects
             WHERE subject_id IN (v_organization_id::text,v_ledger_id::text))
  THEN RAISE EXCEPTION 'Retirement withheld: text Subject reference exists.'; END IF;

  -- Exact four deletes, all in this DO statement transaction.
  DELETE FROM atlas.principal_ledger_authorities WHERE id=v_root_id;
  GET DIAGNOSTICS v_row_count=ROW_COUNT;
  IF v_row_count<>1 THEN RAISE EXCEPTION 'Root delete count mismatch.'; END IF;

  DELETE FROM atlas.ledger_organization_participations WHERE id=v_participation_id;
  GET DIAGNOSTICS v_row_count=ROW_COUNT;
  IF v_row_count<>1 THEN RAISE EXCEPTION 'Participation delete count mismatch.'; END IF;

  DELETE FROM atlas.ledgers WHERE id=v_ledger_id;
  GET DIAGNOSTICS v_row_count=ROW_COUNT;
  IF v_row_count<>1 THEN RAISE EXCEPTION 'Ledger delete count mismatch.'; END IF;

  DELETE FROM atlas.organizations WHERE id=v_organization_id;
  GET DIAGNOSTICS v_row_count=ROW_COUNT;
  IF v_row_count<>1 THEN RAISE EXCEPTION 'Organization delete count mismatch.'; END IF;

  IF (SELECT count(*) FROM atlas.organizations) <> v_org_count_before-1
     OR (SELECT count(*) FROM atlas.ledgers) <> v_ledger_count_before-1
  THEN RAISE EXCEPTION 'Postcondition mismatch: protected institutions changed.'; END IF;
END
$feast_test_retire$;
