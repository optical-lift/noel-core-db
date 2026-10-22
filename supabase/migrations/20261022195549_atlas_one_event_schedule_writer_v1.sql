-- ONE Calendar, ONE canonical Event schedule writer.
-- Source adapter: Ledger-bound canonical Occurrence with exactly one farm_shared
-- Organization operational carrier. No new Calendar table or Event identity.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.set_ledger_occurrence_schedule_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_proposed_starts_at timestamptz,
  p_proposed_ends_at timestamptz,
  p_expected_canonical_updated_at timestamptz,
  p_expected_operational_updated_at timestamptz,
  p_decision_reason text,
  p_source_action_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_actor uuid;
  v_principal uuid;
  v_occ local_intel.occurrences%rowtype;
  v_overlay atlas.community_events%rowtype;
  v_existing atlas.evidence_records%rowtype;
  v_receipt_id uuid;
  v_count integer;
  v_claims integer;
  v_booking_count integer;
  v_request_count integer;
  v_cross_count integer;
  v_local_start timestamp;
  v_local_end timestamp;
  v_new_label text;
  v_prior_label text;
  v_outreach_review boolean;
  v_response jsonb;
  v_reason text := btrim(coalesce(p_decision_reason,''));
  v_action text := btrim(coalesce(p_source_action_id,''));
BEGIN
  -- Actor guard validates a real Auth session, Person, active native Ledger
  -- connection and exact Ledger/Organization/Occurrence identity.
  v_actor := atlas.ledger_occurrence_shared_work_actor_self_v1(
    p_organization_id,p_ledger_id,p_occurrence_id);
  v_principal := atlas.current_principal_id_v1();
  IF v_principal IS NULL OR NOT atlas.principal_has_ledger_authority_v1(
      v_principal,p_ledger_id) THEN
    RAISE EXCEPTION 'Exact Ledger root-governing schedule authority required.'
      USING ERRCODE='42501';
  END IF;

  IF p_expected_canonical_updated_at IS NULL
     OR p_expected_operational_updated_at IS NULL
     OR p_proposed_starts_at IS NULL OR p_proposed_ends_at IS NULL
     OR NOT isfinite(p_proposed_starts_at)
     OR NOT isfinite(p_proposed_ends_at)
     OR p_proposed_ends_at<=p_proposed_starts_at
     OR p_proposed_ends_at-p_proposed_starts_at>interval '18 hours'
     OR length(v_reason)<12 OR length(v_reason)>1200
     OR length(v_action)<8 OR length(v_action)>160 THEN
    RAISE EXCEPTION 'Finite interval, observed versions, meaningful reason and action key required.'
      USING ERRCODE='22023';
  END IF;

  -- Serialize writers to this ONE canonical identity, including replay.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('atlas:occurrence:schedule:'||p_occurrence_id::text,0));

  SELECT * INTO v_existing
  FROM atlas.evidence_records e
  WHERE e.scope_kind='ledger' AND e.scope_id=p_ledger_id
    AND e.source_kind='ledger_occurrence_schedule_decision_v1'
    AND e.source_key=v_action
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.subject_domain<>'local_intel'
       OR v_existing.subject_kind<>'occurrence'
       OR v_existing.subject_id<>p_occurrence_id::text
       OR v_existing.value#>>'{request,startsAt}'<>p_proposed_starts_at::text
       OR v_existing.value#>>'{request,endsAt}'<>p_proposed_ends_at::text
       OR v_existing.value#>>'{request,reason}'<>v_reason
       OR v_existing.actor_user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'Schedule action key reused for a different decision.'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'ok',true,'contractVersion','ledger_occurrence_schedule_write_v1',
      'idempotentReplay',true,'receiptId',v_existing.id,
      'occurrenceId',p_occurrence_id,
      'startsAt',p_proposed_starts_at,'endsAt',p_proposed_ends_at);
  END IF;

  -- Fail closed on ambiguous Organization source authority.
  SELECT count(DISTINCT lop.organization_id)::integer INTO v_count
  FROM atlas.ledger_organization_participations lop
  JOIN atlas.organization_occurrence_bindings ob
    ON ob.organization_id=lop.organization_id
   AND ob.occurrence_id=p_occurrence_id AND ob.binding_state='active'
  WHERE lop.ledger_id=p_ledger_id
    AND lop.status='active' AND lop.ended_at IS NULL
    AND lop.participation_kind IN ('governing','operating');
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Ambiguous Organization source authority for this Event.'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_occ FROM local_intel.occurrences
  WHERE id=p_occurrence_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Canonical Event unavailable.' USING ERRCODE='P0002';
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.organization_id=p_organization_id
    AND ob.occurrence_id=p_occurrence_id
    AND ob.binding_state='active' AND ce.visibility_scope='farm_shared';
  IF v_count<>1 THEN
    RAISE EXCEPTION 'Exactly one shared operational carrier required.'
      USING ERRCODE='23514';
  END IF;

  SELECT ce.* INTO v_overlay
  FROM atlas.organization_occurrence_bindings ob
  JOIN atlas.community_events ce ON ce.occurrence_binding_id=ob.id
  WHERE ob.organization_id=p_organization_id
    AND ob.occurrence_id=p_occurrence_id
    AND ob.binding_state='active' AND ce.visibility_scope='farm_shared'
  FOR UPDATE OF ce;

  -- This adapter must not usurp other existing source-owned writer lanes.
  IF coalesce(v_occ.metadata->>'atlasWriterAuthority','') IN
     ('network_outreach','system_fixture') THEN
    RAISE EXCEPTION 'Source-specific Event writer must handle this source lane.'
      USING ERRCODE='23514';
  END IF;

  IF v_occ.updated_at IS DISTINCT FROM p_expected_canonical_updated_at
     OR v_overlay.updated_at IS DISTINCT FROM p_expected_operational_updated_at THEN
    RAISE EXCEPTION 'Event source version changed; reread one canonical Event.'
      USING ERRCODE='40001';
  END IF;
  IF NOT EXISTS(
      SELECT 1 FROM pg_catalog.pg_timezone_names tz
      WHERE tz.name=v_overlay.timezone_name) THEN
    RAISE EXCEPTION 'Operational timezone unavailable.' USING ERRCODE='22023';
  END IF;

  v_local_start := p_proposed_starts_at AT TIME ZONE v_overlay.timezone_name;
  v_local_end := p_proposed_ends_at AT TIME ZONE v_overlay.timezone_name;
  IF v_local_start::date IS DISTINCT FROM v_local_end::date
    OR v_local_end::time<=v_local_start::time
    OR (v_local_start AT TIME ZONE v_overlay.timezone_name)
       IS DISTINCT FROM p_proposed_starts_at
    OR (v_local_end AT TIME ZONE v_overlay.timezone_name)
       IS DISTINCT FROM p_proposed_ends_at THEN
    RAISE EXCEPTION 'Civil schedule requires a single unambiguous local Event date.'
      USING ERRCODE='22023';
  END IF;

  -- Committed bookings and unconverted booking requests are source-owned
  -- dependencies; no edit silently changes or cancels them.
  SELECT count(*)::integer INTO v_booking_count
  FROM ledger.bookings b WHERE b.occurrence_id=p_occurrence_id
    AND b.booking_state<>'cancelled';
  SELECT count(*)::integer INTO v_request_count
  FROM ledger.booking_requests r WHERE r.occurrence_id=p_occurrence_id
    AND r.request_state NOT IN ('withdrawn','rejected');
  SELECT count(*)::integer INTO v_cross_count
  FROM ledger.occurrence_calendar_bindings cb
  WHERE cb.occurrence_id=p_occurrence_id
    AND cb.ledger_id<>p_ledger_id AND cb.binding_state='active';

  IF v_booking_count>0 OR v_request_count>0 OR v_cross_count>0 THEN
    RAISE EXCEPTION 'Booking, pending request, or another Ledger requires source-owned review.'
      USING ERRCODE='23514';
  END IF;

  -- A PUBLIC Event can be retimed without retiming any Resource claim only
  -- when every proposed instant remains inside an existing CONFIRMED
  -- site/space hold, if there are claims on this Event.
  SELECT count(*)::integer INTO v_claims
  FROM ledger.occurrence_resource_claims c
  WHERE c.occurrence_id=p_occurrence_id
    AND c.claim_state IN ('confirmed','tentative');

  IF v_claims>0 AND NOT EXISTS(
    SELECT 1 FROM ledger.occurrence_resource_claims c
    JOIN reality.resources r ON r.id=c.resource_id
    WHERE c.occurrence_id=p_occurrence_id
      AND c.ledger_id=p_ledger_id
      AND c.claim_state='confirmed'
      AND r.resource_kind IN ('site','space')
      AND c.starts_at<=p_proposed_starts_at
      AND c.ends_at>=p_proposed_ends_at
  ) THEN
    RAISE EXCEPTION 'New Event time is outside confirmed site availability; Resource source review required.'
      USING ERRCODE='23514';
  END IF;

  -- No source data overwritten beyond the canonical interval and a clearly
  -- obsolete human-readable schedule field. Preserve ALL other metadata.
  v_prior_label := v_occ.metadata->>'publicEventLocalTime';
  v_new_label := to_char(v_local_start,'FMHH12:MI AM')||'–'||
                 to_char(v_local_end,'FMHH12:MI AM');
  v_outreach_review := coalesce(v_occ.metadata ? 'outreachStatus',false)
    OR coalesce(v_occ.metadata ? 'vendorInvitationScope',false);

  UPDATE local_intel.occurrences o SET
    start_at=p_proposed_starts_at,
    end_at=p_proposed_ends_at,
    metadata=CASE WHEN o.metadata ? 'publicEventLocalTime'
      THEN jsonb_set(o.metadata,'{publicEventLocalTime}',to_jsonb(v_new_label),true)
      ELSE o.metadata END,
    updated_at=pg_catalog.clock_timestamp()
  WHERE o.id=p_occurrence_id;

  -- The existing operational row is a backward-compatible program carrier.
  -- If already synchronized (as October 30 is), do not touch its version.
  IF v_overlay.event_date IS DISTINCT FROM v_local_start::date
    OR v_overlay.start_local_time IS DISTINCT FROM v_local_start::time
    OR v_overlay.end_local_time IS DISTINCT FROM v_local_end::time THEN
    UPDATE atlas.community_events ce SET
      event_date=v_local_start::date,
      start_local_time=v_local_start::time,
      end_local_time=v_local_end::time,
      updated_at=pg_catalog.clock_timestamp()
    WHERE ce.id=v_overlay.id;
  END IF;

  INSERT INTO atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    evidence_kind,source_kind,source_key,actor_user_id,value,
    observed_at,provenance,metadata
  ) VALUES (
    'ledger',p_ledger_id,'local_intel','occurrence',p_occurrence_id::text,
    'source_schedule_correction',
    'ledger_occurrence_schedule_decision_v1',v_action,auth.uid(),
    jsonb_build_object(
      'request',jsonb_build_object(
        'startsAt',p_proposed_starts_at::text,
        'endsAt',p_proposed_ends_at::text,
        'reason',v_reason),
      'canonicalBefore',jsonb_build_object(
        'startsAt',v_occ.start_at,'endsAt',v_occ.end_at,
        'updatedAt',v_occ.updated_at,'publicEventLocalTime',v_prior_label),
      'operationalBefore',jsonb_build_object(
        'id',v_overlay.id,'eventDate',v_overlay.event_date,
        'startsLocal',v_overlay.start_local_time,'endsLocal',v_overlay.end_local_time,
        'updatedAt',v_overlay.updated_at,'timezoneName',v_overlay.timezone_name),
      'canonicalAfter',jsonb_build_object(
        'startsAt',p_proposed_starts_at,'endsAt',p_proposed_ends_at,
        'publicEventLocalTime',v_new_label),
      'actorPersonId',v_actor,
      'resourceClaimCountPreserved',v_claims,
      'communicationImpactRequiresHumanReview',v_outreach_review),
    pg_catalog.clock_timestamp(),
    jsonb_build_object('source','signed_ledger_owner_schedule_decision',
      'canonicalOccurrenceId',p_occurrence_id,
      'operationalCarrierId',v_overlay.id),
    jsonb_build_object('oneCalendarSourceWriterVersion',1)
  ) RETURNING id INTO v_receipt_id;

  v_response:=jsonb_build_object(
    'ok',true,'contractVersion','ledger_occurrence_schedule_write_v1',
    'idempotentReplay',false,'receiptId',v_receipt_id,
    'occurrenceId',p_occurrence_id,'actorPersonId',v_actor,
    'startsAt',p_proposed_starts_at,'endsAt',p_proposed_ends_at,
    'resourceClaimsUntouched',true,
    'communicationImpactRequiresHumanReview',v_outreach_review,
    'notAnotherCalendar',true);
  RETURN v_response;
END
$function$;

REVOKE ALL ON FUNCTION atlas.set_ledger_occurrence_schedule_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION atlas.set_ledger_occurrence_schedule_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.set_ledger_occurrence_schedule_self_api_v1(
  p_organization_id uuid,
  p_ledger_id uuid,
  p_occurrence_id uuid,
  p_proposed_starts_at timestamptz,
  p_proposed_ends_at timestamptz,
  p_expected_canonical_updated_at timestamptz,
  p_expected_operational_updated_at timestamptz,
  p_decision_reason text,
  p_source_action_id text
) RETURNS jsonb
LANGUAGE sql
SET search_path TO ''
AS $function$
  SELECT atlas.set_ledger_occurrence_schedule_self_api_v1(
    p_organization_id,p_ledger_id,p_occurrence_id,
    p_proposed_starts_at,p_proposed_ends_at,
    p_expected_canonical_updated_at,p_expected_operational_updated_at,
    p_decision_reason,p_source_action_id)
$function$;

REVOKE ALL ON FUNCTION public.set_ledger_occurrence_schedule_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)
  FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_ledger_occurrence_schedule_self_api_v1(
  uuid,uuid,uuid,timestamptz,timestamptz,timestamptz,timestamptz,text,text)
  TO authenticated;

-- Block the original parallel schedule writer for operator-supplied
-- canonical Events. Other provenance-governed source lanes require their
-- own migration to this single command, not unsafe auto-conversion.
CREATE OR REPLACE FUNCTION atlas.block_unowned_operational_event_retime_v1()
RETURNS trigger LANGUAGE plpgsql
SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_occ local_intel.occurrences%rowtype;
BEGIN
  IF (NEW.event_date,NEW.start_local_time,NEW.end_local_time) IS NOT DISTINCT
     FROM (OLD.event_date,OLD.start_local_time,OLD.end_local_time) THEN
    RETURN NEW;
  END IF;
  SELECT o.* INTO v_occ
  FROM atlas.organization_occurrence_bindings ob
  JOIN local_intel.occurrences o ON o.id=ob.occurrence_id
  WHERE ob.id=NEW.occurrence_binding_id AND ob.binding_state='active';
  IF v_occ.id IS NULL THEN
    RAISE EXCEPTION 'Canonical occurrence binding required for schedule changes.'
      USING ERRCODE='23514';
  END IF;
  IF coalesce(v_occ.metadata->>'atlasWriterAuthority','') IN
     ('network_outreach','system_fixture') THEN
    RETURN NEW;
  END IF;
  IF v_occ.start_at IS DISTINCT FROM
       ((NEW.event_date+NEW.start_local_time) AT TIME ZONE NEW.timezone_name)
    OR v_occ.end_at IS DISTINCT FROM
       ((NEW.event_date+NEW.end_local_time) AT TIME ZONE NEW.timezone_name) THEN
    RAISE EXCEPTION 'Operational carrier is not a second Calendar writer; use the canonical Event schedule command.'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS aa_block_unowned_operational_event_retime_v1
  ON atlas.community_events;
CREATE TRIGGER aa_block_unowned_operational_event_retime_v1
  BEFORE UPDATE OF event_date,start_local_time,end_local_time
  ON atlas.community_events FOR EACH ROW
  EXECUTE FUNCTION atlas.block_unowned_operational_event_retime_v1();

COMMIT;