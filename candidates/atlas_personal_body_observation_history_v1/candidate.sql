-- Source-only Atlas candidate: person-scoped longitudinal body observations.
-- Depends on the released Personal Reality capture -> human-confirmed Claim path.
-- NO private health records, author-specific rows, or Noel practice.* access.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.personal_body_observation_history_self_api_v1(
  p_days integer DEFAULT 30,
  p_timezone text DEFAULT 'UTC',
  p_region_key text DEFAULT NULL,
  p_side text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $body$
DECLARE
  v_user uuid := auth.uid();
  v_principal uuid;
  v_start date;
  v_total bigint := 0;
  v_dates bigint := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Signed-in Person required.' USING errcode = '42501';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 365 THEN
    RAISE EXCEPTION 'Window must be 1 to 365 calendar days.' USING errcode = '22023';
  END IF;
  IF p_timezone IS NULL OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone
  ) THEN
    RAISE EXCEPTION 'Recognized display timezone required.' USING errcode = '22023';
  END IF;
  IF p_side IS NOT NULL AND p_side NOT IN (
    'left','right','bilateral','midline','unspecified'
  ) THEN
    RAISE EXCEPTION 'Unsupported side filter.' USING errcode = '22023';
  END IF;
  SELECT p.id INTO v_principal
  FROM atlas.principals p
  WHERE p.user_id = v_user AND p.status = 'active'
  ORDER BY p.created_at, p.id LIMIT 1;
  IF v_principal IS NULL THEN
    RAISE EXCEPTION 'Active personal Atlas required.' USING errcode = '42501';
  END IF;

  -- The observation's day is based on report time, not an inferred onset.
  v_start := (pg_catalog.now() AT TIME ZONE p_timezone)::date - (p_days - 1);

  WITH candidates AS MATERIALIZED (
    SELECT
      c.id AS claim_id, cap.id AS capture_id,
      cap.testimony AS original_text,
      cap.captured_at AS reported_at,
      (cap.captured_at AT TIME ZONE p_timezone)::date AS report_date,
      c.value->>'regionKey' AS region_key,
      c.value->>'side' AS side,
      c.value->>'symptomKey' AS symptom_key,
      c.value->>'reportedState' AS reported_state,
      c.valid_from AS claimed_effective_from,
      c.valid_until AS claimed_effective_until,
      c.recorded_at AS interpretation_recorded_at
    FROM atlas.claim_records c
    JOIN atlas.personal_reality_captures cap
      ON cap.evidence_id = (
        CASE WHEN c.metadata->>'sourceEvidenceId' ~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        THEN (c.metadata->>'sourceEvidenceId')::uuid END
      )
      AND cap.owner_user_id = v_user
      AND cap.principal_id = v_principal
    WHERE c.scope_kind = 'person' AND c.scope_id = v_user
      AND c.subject_domain = 'health'
      AND c.subject_kind = 'body_region'
      AND c.claim_type = 'self_reported_symptom'
      AND c.source_kind = 'personal_reality_claim'
      AND c.lifecycle_state IN ('reported','observed','accepted')
      AND c.superseded_at IS NULL
      AND pg_catalog.jsonb_typeof(c.value) = 'object'
      AND NULLIF(pg_catalog.btrim(c.value->>'regionKey'),'') IS NOT NULL
      AND NULLIF(pg_catalog.btrim(c.value->>'symptomKey'),'') IS NOT NULL
      AND c.value->>'side' IN (
        'left','right','bilateral','midline','unspecified'
      )
      AND (p_region_key IS NULL OR c.value->>'regionKey' = p_region_key)
      AND (p_side IS NULL OR c.value->>'side' = p_side)
      AND (cap.captured_at AT TIME ZONE p_timezone)::date >= v_start
      AND (cap.captured_at AT TIME ZONE p_timezone)::date
          <= (pg_catalog.now() AT TIME ZONE p_timezone)::date
  ), deduplicated AS (
    -- One report per raw capture / exact anatomical-symptom key.
    -- A subsequent corrected claim does not manufacture a second report.
    SELECT DISTINCT ON (capture_id,region_key,side,symptom_key)
      *
    FROM candidates
    ORDER BY capture_id,region_key,side,symptom_key,
      interpretation_recorded_at DESC,claim_id DESC
  ), numbered AS (
    SELECT d.*, row_number() OVER (
      ORDER BY reported_at DESC,capture_id DESC,claim_id DESC
    ) AS seq
    FROM deduplicated d
  )
  SELECT count(*),
    count(DISTINCT report_date),
    coalesce(pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'claimId',claim_id,
        'captureId',capture_id,
        'originalText',original_text,
        'reportedAt',reported_at,
        'reportDate',report_date,
        'regionKey',region_key,
        'side',side,
        'symptomKey',symptom_key,
        'reportedState',reported_state,
        'claimedEffectiveFrom',claimed_effective_from,
        'claimedEffectiveUntil',claimed_effective_until,
        'timeBoundary','reported_at_is_not_symptom_onset'
      ) ORDER BY seq
    ) FILTER (WHERE seq <= 100), '[]'::jsonb)
  INTO v_total,v_dates,v_items
  FROM numbered;

  RETURN pg_catalog.jsonb_build_object(
    'ok',true,
    'contractVersion','personal_body_observation_history_self_v1',
    'windowDays',p_days,
    'displayTimezone',p_timezone,
    'fromReportDate',v_start,
    'throughReportDate',(pg_catalog.now() AT TIME ZONE p_timezone)::date,
    'filters',pg_catalog.jsonb_build_object(
      'regionKey',p_region_key,'side',p_side
    ),
    'reportCount',v_total,
    'distinctReportDates',v_dates,
    'items',v_items,
    'truncated',v_total > 100,
    'episodeCount',null,
    'truthBoundary',pg_catalog.jsonb_build_object(
      'personOnly',true,
      'humanConfirmedClaimsOnly',true,
      'reportedAtDoesNotEstablishOnset',true,
      'reportCountIsNotEpisodeCount',true,
      'noCausalOrDiagnosticInference',true,
      'noNoelPracticeRecords',true
    )
  );
END;
$body$;

-- Preserve a narrow browser RPC membrane; never expose Atlas source tables.
CREATE OR REPLACE FUNCTION public.personal_body_observation_history_self_api_v1(
  p_days integer DEFAULT 30,
  p_timezone text DEFAULT 'UTC',
  p_region_key text DEFAULT NULL,
  p_side text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $bridge$
  SELECT atlas.personal_body_observation_history_self_api_v1(
    p_days,p_timezone,p_region_key,p_side
  );
$bridge$;

REVOKE ALL ON FUNCTION atlas.personal_body_observation_history_self_api_v1(integer,text,text,text)
  FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.personal_body_observation_history_self_api_v1(integer,text,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.personal_body_observation_history_self_api_v1(integer,text,text,text)
  TO authenticated;

COMMIT;
