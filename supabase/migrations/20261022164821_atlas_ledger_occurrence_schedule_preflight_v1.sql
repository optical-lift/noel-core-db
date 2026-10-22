-- Atlas source-specific schedule correction: READ-ONLY preflight stage.
-- No Event, resource, booking, communication or calendar write is authorized here.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_proposed_starts_at timestamptz DEFAULT NULL,
  p_proposed_ends_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_principal uuid;
  v_root boolean := false;
  v_canonical local_intel.occurrences%rowtype;
  v_overlay atlas.community_events%rowtype;
  v_community_count integer;
  v_zone_ok boolean;
  v_proposed boolean;
  v_claim_count integer;
  v_booking_count integer;
  v_other_ledger_count integer;
  v_summary jsonb := '{}'::jsonb;
  v_claims jsonb := '{}'::jsonb;
  v_reasons jsonb := '[]'::jsonb;
BEGIN
  -- Native Person -> exact Ledger -> Organization -> Occurrence source-bound
  -- identity (this same guard underlies ordinary Event Work, NOT schedule writes).
  v_actor := atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);

  IF (p_proposed_starts_at IS NULL) IS DISTINCT FROM
     (p_proposed_ends_at IS NULL) THEN
    RAISE EXCEPTION 'Proposed interval requires both endpoints.'
      USING ERRCODE='22023';
  END IF;
  v_proposed := p_proposed_starts_at IS NOT NULL;
  IF v_proposed AND (
      NOT isfinite(p_proposed_starts_at) OR
      NOT isfinite(p_proposed_ends_at) OR
      p_proposed_ends_at <= p_proposed_starts_at OR
      p_proposed_ends_at - p_proposed_starts_at > interval '7 days') THEN
    RAISE EXCEPTION 'Proposed absolute interval must be finite and ordered.'
      USING ERRCODE='22023';
  END IF;

  SELECT * INTO STRICT v_canonical
  FROM local_intel.occurrences o WHERE o.id=p_occurrence_id;

  -- Preserve the Event Index's no-silent-selection rule when the same
  -- canonical Occurrence is linked to multiple active Organizations within
  -- one Ledger. A requested Organization ID is not a tie-break authority.
  IF (
    SELECT count(DISTINCT lop.organization_id)
    FROM atlas.ledger_organization_participations lop
    JOIN atlas.organization_occurrence_bindings ob
      ON ob.organization_id=lop.organization_id
     AND ob.occurrence_id=p_occurrence_id
     AND ob.binding_state='active'
    WHERE lop.ledger_id=p_ledger_id
      AND lop.status='active' AND lop.ended_at IS NULL
      AND lop.participation_kind IN ('governing','operating')
  ) <> 1 THEN
    RAISE EXCEPTION 'Unresolved multi-Organization Occurrence; source adjudication required.'
      USING ERRCODE='23514';
  END IF;

  -- A one-to-many overlay is a genuine source ambiguity, never choose the
  -- newest or first row as the source of authority.
  SELECT count(*)::integer INTO v_community_count
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.occurrence_id=p_occurrence_id
    AND ob.organization_id=p_organization_id
    AND ob.binding_state='active'
    AND ce.visibility_scope='farm_shared';

  IF v_community_count<>1 THEN
    RAISE EXCEPTION 'Exactly one admitted shared operational assertion is required for this source adapter.'
      USING ERRCODE='23514';
  END IF;

  SELECT ce.* INTO STRICT v_overlay
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.occurrence_id=p_occurrence_id
    AND ob.organization_id=p_organization_id
    AND ob.binding_state='active'
    AND ce.visibility_scope='farm_shared';

  SELECT EXISTS(
    SELECT 1 FROM pg_catalog.pg_timezone_names tz
    WHERE tz.name=v_overlay.timezone_name
  ) INTO v_zone_ok;

  -- Independent Ledger root governance is only a *candidate* ability to
  -- request a source-owned correction. It does NOT itself authorize writes
  -- to Shared Intelligence, resource claims or third-party commitments.
  v_principal:=atlas.current_principal_id_v1();
  v_root:=coalesce(
    v_principal IS NOT NULL AND
    atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id),false);

  v_summary:=jsonb_build_object(
    'title',v_overlay.title IS DISTINCT FROM v_canonical.title,
    'sourceStatus',v_overlay.status IS DISTINCT FROM v_canonical.status,
    'startLocalTime',CASE WHEN v_zone_ok THEN
      v_overlay.start_local_time IS DISTINCT FROM
        (v_canonical.start_at AT TIME ZONE v_overlay.timezone_name)::time
      ELSE NULL END,
    'date',CASE WHEN v_zone_ok THEN
      v_overlay.event_date IS DISTINCT FROM
        (v_canonical.start_at AT TIME ZONE v_overlay.timezone_name)::date
      ELSE NULL END,
    'endLocalTime',CASE WHEN v_canonical.end_at IS NOT NULL AND v_zone_ok THEN
      v_overlay.end_local_time IS DISTINCT FROM
        (v_canonical.end_at AT TIME ZONE v_overlay.timezone_name)::time
      ELSE NULL END
  );

  -- Booking/resource counts are not exposed to all ordinary Event viewers.
  -- A Ledger seat can see an admitted Event; that is NOT a right to inspect
  -- a venue's booking and resource utilization.
  IF v_root THEN
    SELECT count(*)::integer INTO v_claim_count
      FROM ledger.occurrence_resource_claims c
      WHERE c.ledger_id=p_ledger_id
        AND c.occurrence_id=p_occurrence_id
        AND c.claim_state IN ('confirmed','tentative');
    SELECT count(*)::integer INTO v_booking_count
      FROM ledger.bookings b
      WHERE b.ledger_id=p_ledger_id
        AND b.occurrence_id=p_occurrence_id
        AND b.booking_state NOT IN ('cancelled');
    SELECT count(*)::integer INTO v_other_ledger_count
      FROM ledger.occurrence_calendar_bindings cb
      WHERE cb.occurrence_id=p_occurrence_id
        AND cb.ledger_id<>p_ledger_id
        AND cb.binding_state='active';
    v_claims:=jsonb_build_object(
      'evaluation','root_governing_scoped_summary',
      'activeResourceClaimCount',v_claim_count,
      'nonCancelledBookingCount',v_booking_count,
      'otherActiveLedgerBindingCount',v_other_ledger_count,
      'actualClaimIntervalsOrAvailabilityNotDisclosed',true);
    IF v_claim_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'resource_claims_need_source_owned_retime_review');
    END IF;
    IF v_booking_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'bookings_need_source_owned_commitment_review');
    END IF;
    IF v_other_ledger_count>0 THEN
      v_reasons:=v_reasons||jsonb_build_array(
        'canonical_occurrence_used_by_other_ledgers');
    END IF;
  ELSE
    v_claims:=jsonb_build_object(
      'evaluation','not_authorized',
      'activeResourceClaimCount',null,
      'nonCancelledBookingCount',null,
      'otherActiveLedgerBindingCount',null,
      'notEvaluatedIsNotZero',true);
    v_reasons:=v_reasons||jsonb_build_array(
      'governing_source_review_required');
  END IF;
  IF NOT v_zone_ok THEN
    v_reasons:=v_reasons||jsonb_build_array(
      'operational_timezone_not_recognized');
  END IF;
  IF NOT v_proposed THEN
    v_reasons:=v_reasons||jsonb_build_array(
      'exact_proposed_interval_not_submitted');
  END IF;

  -- These are hard non-negotiable unintegrated dependencies at this stage:
  -- communications/public assertions and independent booking collision
  -- preflight must be run by their own sources at actual write time.
  v_reasons:=v_reasons||jsonb_build_array(
    'source_owned_schedule_writer_not_released',
    'communication_and_publication_impact_not_evaluated',
    'resource_capacity_collision_preflight_not_completed');

  RETURN jsonb_build_object(
    'ok',true,
    'contractVersion','ledger_occurrence_schedule_preflight_v1',
    'scope',jsonb_build_object(
      'ledgerId',p_ledger_id,'organizationId',p_organization_id,
      'occurrenceId',p_occurrence_id),
    'actorPersonId',v_actor,
    'rootGoverningCandidate',v_root,
    'canonicalSource',jsonb_build_object(
      'ref',jsonb_build_object(
        'authority','local_intel','kind','occurrence','id',v_canonical.id),
      'title',v_canonical.title,'status',v_canonical.status,
      'startsAt',v_canonical.start_at,'endsAt',v_canonical.end_at,
      'updatedAt',v_canonical.updated_at),
    'operationalSource',jsonb_build_object(
      'ref',jsonb_build_object(
        'authority','atlas','kind','community_event','id',v_overlay.id),
      'title',v_overlay.title,'status',v_overlay.status,
      'eventDate',v_overlay.event_date,
      'startLocalTime',v_overlay.start_local_time,
      'endLocalTime',v_overlay.end_local_time,
      'timezoneName',v_overlay.timezone_name,
      'updatedAt',v_overlay.updated_at),
    'sourceComparisons',v_summary,
    'sourceComparisonIsNotAdjudication',true,
    'proposedInterval',CASE WHEN v_proposed THEN
      jsonb_build_object(
        'startsAt',p_proposed_starts_at,'endsAt',p_proposed_ends_at,
        'changesCanonicalInterval',
          (p_proposed_starts_at IS DISTINCT FROM v_canonical.start_at OR
           p_proposed_ends_at IS DISTINCT FROM v_canonical.end_at),
        'operationalWallClockComparison',CASE WHEN v_zone_ok THEN
          jsonb_build_object(
            'proposedLocalDate',
              (p_proposed_starts_at AT TIME ZONE v_overlay.timezone_name)::date,
            'proposedLocalStart',
              (p_proposed_starts_at AT TIME ZONE v_overlay.timezone_name)::time,
            'proposedLocalEnd',
              (p_proposed_ends_at AT TIME ZONE v_overlay.timezone_name)::time)
          ELSE null END)
      ELSE null END,
    'dependentSourceImpact',v_claims,
    'commitBlockedReasons',v_reasons,
    'approvedToCommit',false,
    'readOnly',true,
    'coverage',jsonb_build_object(
      'sourceFamiliesEvaluated',jsonb_build_array(
        'canonical_occurrence','one_farm_shared_community_event',
        'native_ledger_occurrence_binding'),
      'sensitiveResourceSummaryEvaluatedOnlyForRoot',v_root,
      'communicationImpactComplete',false,
      'crossOrganizationSourceWritersVerified',false,
      'allBookingsAndResourceCapacityProvedAvailable',false,
      'personalTemporalFieldComplete',false)
  );
END
$function$;

REVOKE ALL ON FUNCTION atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz) TO authenticated;

CREATE OR REPLACE FUNCTION public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_proposed_starts_at timestamptz DEFAULT NULL,
  p_proposed_ends_at timestamptz DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path TO ''
AS $function$
  SELECT atlas.ledger_occurrence_schedule_correction_preflight_self_api_v1(
    p_organization_id,p_ledger_id,p_occurrence_id,
    p_proposed_starts_at,p_proposed_ends_at)
$function$;

REVOKE ALL ON FUNCTION public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ledger_occurrence_schedule_correction_preflight_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz) TO authenticated;

COMMIT;
