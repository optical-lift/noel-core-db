-- Reviewed-candidate stage only. Source-first, no direct production execution.
-- Exact canonical migration generation and protected clone validation are separate gates.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_date_evidence_self_api_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer DEFAULT 150
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_access jsonb;
  v_timezone text := nullif(btrim(coalesce(p_timezone_name,'')),'');
  v_limit integer := greatest(1,least(coalesce(p_limit,150),250));
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF auth.uid() IS NULL OR p_ledger_id IS NULL THEN
    RAISE EXCEPTION 'Authenticated exact Ledger required'
      USING ERRCODE='42501';
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL OR p_end_date < p_start_date
     OR p_end_date - p_start_date > 45 THEN
    RAISE EXCEPTION 'Bounded valid date interval required'
      USING ERRCODE='22023';
  END IF;
  IF v_timezone IS NULL OR NOT EXISTS(
    SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name=v_timezone
  ) THEN
    RAISE EXCEPTION 'Valid civil timezone required'
      USING ERRCODE='22023';
  END IF;

  -- Match the existing Ledger Event Index's authenticated human entry boundary.
  -- A Ledger connection is NOT generic Organization or private-custody authority.
  v_access := atlas.reality_access_self_api_v1();
  IF v_access->>'state' IS DISTINCT FROM 'ready'
     OR v_access->>'authenticated' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'Personal Atlas identity access required'
      USING ERRCODE='42501';
  END IF;
  PERFORM atlas.current_active_ledger_seat_v1(p_ledger_id);
  IF NOT EXISTS(
    SELECT 1
    FROM ledger.ledgers l
    JOIN atlas.ledgers al ON al.id=l.id AND al.status='active'
    JOIN atlas.ledger_organization_participations lop
      ON lop.ledger_id=l.id AND lop.status='active'
     AND lop.ended_at IS NULL
     AND lop.participation_kind IN ('governing','operating')
    WHERE l.id=p_ledger_id AND l.ledger_state='active'
      AND l.retired_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Source-bound active Ledger participation required'
      USING ERRCODE='42501';
  END IF;

  -- Ledger-bound canonical Occurrences are the ONLY admission authority here.
  -- Two linked assertions are two perspectives, never two Occurrence identities.
  WITH admitted AS (
    SELECT DISTINCT ON (o.id)
      o.id, o.title, o.status, o.start_at, o.end_at,
      o.last_verified_at, o.updated_at,
      cb.id AS calendar_binding_id
    FROM ledger.occurrence_calendar_bindings cb
    JOIN local_intel.occurrences o ON o.id=cb.occurrence_id
    WHERE cb.ledger_id=p_ledger_id AND cb.binding_state='active'
      AND (
        (
          (o.start_at AT TIME ZONE v_timezone)::date <= p_end_date
          AND (coalesce(o.end_at,o.start_at) AT TIME ZONE v_timezone)::date >= p_start_date
        )
        OR EXISTS(
          SELECT 1
          FROM atlas.ledger_organization_participations lop
          JOIN atlas.organization_occurrence_bindings ob
            ON ob.organization_id=lop.organization_id
           AND ob.occurrence_id=o.id AND ob.binding_state='active'
          JOIN atlas.community_events ce
            ON ce.occurrence_binding_id=ob.id
           AND ce.visibility_scope='farm_shared'
          WHERE lop.ledger_id=p_ledger_id
            AND lop.status='active' AND lop.ended_at IS NULL
            AND lop.participation_kind IN ('governing','operating')
            AND ce.event_date BETWEEN p_start_date AND p_end_date
        )
      )
    ORDER BY o.id,cb.updated_at DESC,cb.id
  ), bounded AS (
    SELECT a.* FROM admitted a ORDER BY a.start_at,a.id LIMIT v_limit
  ), scoped AS (
    SELECT b.*, org.organization_id,org.organization_count
    FROM bounded b
    CROSS JOIN LATERAL (
      SELECT min(lop.organization_id::text)::uuid AS organization_id,
             count(DISTINCT lop.organization_id)::integer AS organization_count
      FROM atlas.ledger_organization_participations lop
      JOIN atlas.organization_occurrence_bindings ob
        ON ob.organization_id=lop.organization_id
       AND ob.occurrence_id=b.id AND ob.binding_state='active'
      WHERE lop.ledger_id=p_ledger_id AND lop.status='active'
        AND lop.ended_at IS NULL
        AND lop.participation_kind IN ('governing','operating')
    ) org
  ), projected AS (
    SELECT s.*,
      coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'sourceRef',jsonb_build_object(
              'authority','atlas','kind','community_event','id',ce.id),
            'bindingId',ob.id,
            'title',ce.title,'sourceStatus',ce.status,
            'eventDate',ce.event_date,
            'startLocalTime',ce.start_local_time,
            'endLocalTime',ce.end_local_time,
            'timezoneName',ce.timezone_name,
            'sourceUpdatedAt',ce.updated_at,
            'timezoneRecognized',EXISTS(
              SELECT 1 FROM pg_catalog.pg_timezone_names z
              WHERE z.name=ce.timezone_name),
            'differenceCandidates',jsonb_build_object(
              'title',ce.title IS DISTINCT FROM s.title,
              'sourceStatus',ce.status IS DISTINCT FROM s.status,
              'date',CASE WHEN EXISTS(
                SELECT 1 FROM pg_catalog.pg_timezone_names z
                WHERE z.name=ce.timezone_name)
                THEN ce.event_date IS DISTINCT FROM
                  (s.start_at AT TIME ZONE ce.timezone_name)::date
                ELSE NULL END,
              'startLocalTime',CASE WHEN EXISTS(
                SELECT 1 FROM pg_catalog.pg_timezone_names z
                WHERE z.name=ce.timezone_name)
                THEN ce.start_local_time IS DISTINCT FROM
                  (s.start_at AT TIME ZONE ce.timezone_name)::time
                ELSE NULL END,
              'endLocalTime',CASE WHEN s.end_at IS NULL THEN NULL
                WHEN EXISTS(
                  SELECT 1 FROM pg_catalog.pg_timezone_names z
                  WHERE z.name=ce.timezone_name)
                THEN ce.end_local_time IS DISTINCT FROM
                  (s.end_at AT TIME ZONE ce.timezone_name)::time
                ELSE NULL END
            ),
            'disposition','not_adjudicated'
          ) ORDER BY ce.id
        )
        FROM atlas.organization_occurrence_bindings ob
        JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
        WHERE ce.visibility_scope='farm_shared'
          AND s.organization_count=1
          AND ob.organization_id=s.organization_id
          AND ob.occurrence_id=s.id
          AND ob.binding_state='active'
      ),'[]'::jsonb) AS community_overlays
    FROM scoped s
  )
  SELECT (SELECT count(*)::integer FROM admitted),
    coalesce(jsonb_agg(
      jsonb_build_object(
        'projectionKey','canonical_occurrence:'||pr.id::text,
        'sourceRef',jsonb_build_object(
          'authority','local_intel','kind','occurrence','id',pr.id),
        'ledgerCalendarBindingId',pr.calendar_binding_id,
        'canonicalAssertion',jsonb_build_object(
          'title',pr.title,'sourceStatus',pr.status,
          'startsAt',pr.start_at,'endsAt',pr.end_at,
          'civilDate',(pr.start_at AT TIME ZONE v_timezone)::date,
          'requestedTimezoneName',v_timezone,
          'sourceLastVerifiedAt',pr.last_verified_at,
          'sourceUpdatedAt',pr.updated_at
        ),
        'communityEventAssertions',pr.community_overlays,
        'organizationBindingAmbiguous',pr.organization_count>1,
        'organizationBindingMissing',pr.organization_count=0,
        'sourceFieldDifferencesNotAutoAdjudicated',true,
        'subjectEncounter',jsonb_build_object(
          'kind','canonical_occurrence','id',pr.id)
      ) ORDER BY pr.start_at,pr.id
    ),'[]'::jsonb)
  INTO v_total,v_items
  FROM projected pr;

  RETURN jsonb_build_object(
    'contractVersion','ledger_occurrence_date_evidence_v1',
    'scope',jsonb_build_object('kind','ledger','id',p_ledger_id),
    'window',jsonb_build_object(
      'startDate',p_start_date,'endDate',p_end_date,
      'timezoneName',v_timezone),
    'occurrences',v_items,
    'coverage',jsonb_build_object(
      'sourceFamiliesEvaluated',jsonb_build_array(
        'active_ledger_bound_canonical_occurrences',
        'linked_farm_shared_operational_event_assertions'),
      'returnedOccurrenceCount',jsonb_array_length(v_items),
      'eligibleOccurrenceCount',v_total,
      'truncated',v_total>v_limit,
      'wholeTemporalFieldComplete',false,
      'nonIntegratedSourceFamiliesNotDeniedOrEmpty',true,
      'occurrencesWithoutLedgerBindingNotEvaluated',true,
      'operationalSourceLocalDatesNotUniversalTimezoneCoverage',true,
      'restrictedOperationalViewsAreNotIncluded',true
    ),
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'oneCanonicalOccurrencePerIdentity',true,
      'differentAssertionsAreNotIndependentEvents',true,
      'differencesAreReviewCandidatesNotResolvedContradictions',true,
      'noneOfTheseRowsProvesMessageSentOrResourceBooked',true,
      'noSourceStateChanged',true
    )
  );
END
$function$;

REVOKE ALL ON FUNCTION atlas.ledger_occurrence_date_evidence_self_api_v1(
  uuid,date,date,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.ledger_occurrence_date_evidence_self_api_v1(
  uuid,date,date,text,integer) TO authenticated;

-- Data API delegate only. Does not bypass source checks or own time truth.
CREATE OR REPLACE FUNCTION public.ledger_occurrence_date_evidence_self_api_v1(
  p_ledger_id uuid,
  p_start_date date,
  p_end_date date,
  p_timezone_name text,
  p_limit integer DEFAULT 150
) RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT atlas.ledger_occurrence_date_evidence_self_api_v1(
    p_ledger_id,p_start_date,p_end_date,p_timezone_name,p_limit)
$function$;

REVOKE ALL ON FUNCTION public.ledger_occurrence_date_evidence_self_api_v1(
  uuid,date,date,text,integer) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ledger_occurrence_date_evidence_self_api_v1(
  uuid,date,date,text,integer) TO authenticated;

COMMIT;
