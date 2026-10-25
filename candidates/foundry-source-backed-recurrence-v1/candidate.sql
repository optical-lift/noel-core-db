-- Foundry stage 2A: a source-verified, human-confirmed weekly recurrence.
-- This is not a generic task writer or a new scheduler. It invokes the
-- existing exact Ledger recurrence command and its responsibility checks.
-- Source-only candidate: never apply directly to production.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.establish_foundry_weekly_recurrence_self_api_v1(
  p_workspace_id text,
  p_entry_id text,
  p_segment_index integer,
  p_ledger_id uuid,
  p_title text,
  p_weekday smallint,
  p_timezone_name text,
  p_effective_start_date date,
  p_all_day boolean,
  p_local_start_time time DEFAULT NULL,
  p_local_end_time time DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','atlas','foundry','ledger','auth','pg_temp'
AS $function$
DECLARE
  v_actor uuid := atlas.foundry_current_signed_principal_v1();
  v_source foundry.events%rowtype;
  v_parts jsonb;
  v_piece jsonb;
  v_literal text;
  v_stable_key text;
  v_existing ledger.recurrence_series%rowtype;
  v_saved ledger.recurrence_series%rowtype;
  v_receipt jsonb;
  v_expected_source jsonb;
BEGIN
  -- A human may inspect and establish only evidence actually saved by that
  -- human in this workspace. Neither its subject label nor a native Ledger
  -- connection is an authorization for schedule mutations.
  IF p_workspace_id IS NULL OR p_entry_id IS NULL
     OR p_segment_index IS NULL OR p_segment_index<0
     OR p_ledger_id IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM foundry.workspace_authority_registry_v1 w
       WHERE w.workspace_id=p_workspace_id AND w.owner_principal_id=v_actor
         AND w.revoked_at IS NULL AND w.suspended_at IS NULL
         AND w.custody_review_state NOT IN ('revoked','suspended')
     ) THEN
    RAISE EXCEPTION 'Foundry source not accessible' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_source FROM foundry.events e
  WHERE e.workspace_id=p_workspace_id
    AND e.event_id=p_entry_id
    AND e.event_type='foundry_reality_input_v1'
    AND e.envelope->'payload'->>'author_principal_id'=v_actor::text;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Foundry source not accessible' USING ERRCODE='42501';
  END IF;

  -- External references are not automatically licensed for establishment.
  IF v_source.envelope->'payload'->>'source_kind' NOT IN
     ('operator_statement','firsthand_observation') THEN
    RAISE EXCEPTION 'Outside-source authority must be verified separately' USING ERRCODE='42501';
  END IF;

  v_parts := v_source.envelope->'payload'->'segments';
  IF jsonb_typeof(v_parts)<>'array'
     OR p_segment_index>=jsonb_array_length(v_parts) THEN
    RAISE EXCEPTION 'Source segment unavailable' USING ERRCODE='22023';
  END IF;
  v_piece := v_parts->p_segment_index;
  v_literal := v_piece->>'text';
  IF v_piece->>'kind'<>'recurrence'
     OR v_literal IS NULL OR length(btrim(v_literal))<1
     OR strpos(v_source.envelope->'payload'->>'original_text',v_literal)=0
  THEN RAISE EXCEPTION 'An original recurrence statement is required' USING ERRCODE='22023';
  END IF;

  -- Do not infer calendar decisions from vague source language. The human
  -- must supply exact dates, weekday, timezone, and all-day/time status.
  IF p_title IS NULL OR length(btrim(p_title))<2 OR length(p_title)>220
     OR p_weekday IS NULL OR p_weekday NOT BETWEEN 0 AND 6
     OR p_effective_start_date IS NULL
     OR p_timezone_name IS NULL OR length(btrim(p_timezone_name))=0
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names
                    WHERE name=p_timezone_name)
     OR p_all_day IS NULL
     OR (p_all_day AND (p_local_start_time IS NOT NULL
                       OR p_local_end_time IS NOT NULL))
     OR (NOT p_all_day AND p_local_start_time IS NULL)
  THEN RAISE EXCEPTION 'Explicit, valid recurring schedule details required' USING ERRCODE='22023';
  END IF;

  -- This is the established governing schedule permission, not mere Ledger
  -- membership, an employee role, or the existence of a Foundry source.
  PERFORM atlas.require_ledger_schedule_responsibility_v1(
    p_ledger_id,'recurrence.write'
  );

  v_stable_key := 'foundry.weekly.'||md5(
    p_workspace_id||':'||p_entry_id||':'||p_segment_index::text||':'||p_ledger_id::text
  );
  v_expected_source := jsonb_build_object(
    'workspaceId',p_workspace_id,
    'entryId',p_entry_id,
    'segmentIndex',p_segment_index,
    'literal',v_literal,
    'contractVersion','foundry_weekly_recurrence_v1',
    'confirmedByPrincipalId',v_actor
  );

  -- Stable deterministic source identity: retry returns a canonical readback,
  -- but a new decision cannot silently overwrite an established schedule.
  PERFORM pg_advisory_xact_lock(hashtextextended(v_stable_key,0));
  SELECT * INTO v_existing FROM ledger.recurrence_series
  WHERE ledger_id=p_ledger_id AND stable_key=v_stable_key FOR UPDATE;
  IF FOUND THEN
    IF v_existing.title IS DISTINCT FROM btrim(p_title)
       OR v_existing.occurrence_type<>'event'
       OR v_existing.frequency<>'weekly'
       OR v_existing.interval_count<>1
       OR v_existing.weekdays IS DISTINCT FROM ARRAY[p_weekday]::smallint[]
       OR v_existing.timezone_name IS DISTINCT FROM p_timezone_name
       OR v_existing.effective_start_date IS DISTINCT FROM p_effective_start_date
       OR v_existing.all_day IS DISTINCT FROM p_all_day
       OR v_existing.local_start_time IS DISTINCT FROM p_local_start_time
       OR v_existing.local_end_time IS DISTINCT FROM p_local_end_time
       OR v_existing.metadata->'foundrySource' IS DISTINCT FROM v_expected_source
    THEN
      RAISE EXCEPTION 'Already established; changes require a governed revision' USING ERRCODE='23505';
    END IF;
    v_saved:=v_existing;
    RETURN jsonb_build_object(
      'ok',true,'replayed',true,
      'canonicalConsequenceKind','ledger_recurrence_series',
      'seriesId',v_saved.id,'ledgerId',p_ledger_id,
      'sourceEntryId',p_entry_id,'sourceSegmentIndex',p_segment_index,
      'title',v_saved.title,'frequency',v_saved.frequency,
      'weekdays',to_jsonb(v_saved.weekdays),
      'timezoneName',v_saved.timezone_name,
      'effectiveStartDate',v_saved.effective_start_date,
      'allDay',v_saved.all_day,
      'localStartTime',v_saved.local_start_time,
      'localEndTime',v_saved.local_end_time,
      'sequence',v_saved.sequence,'aiCarrierAccess',false
    );
  END IF;

  -- Signed Ledger domain writer enforces native active Person Seat and
  -- exact institutional_schedule_operations responsibility in its own code.
  v_receipt := atlas.upsert_ledger_recurrence_series_self_api_v1(
    p_ledger_id,v_stable_key,btrim(p_title),'event',
    'weekly',1,p_timezone_name,p_effective_start_date,
    NULL::date,ARRAY[p_weekday]::smallint[],'{}'::smallint[],
    p_all_day,p_local_start_time,p_local_end_time,
    'active',NULL::text,NULL::text,
    jsonb_build_object('kind','event','foundryEvidenceOnly',false),
    jsonb_build_object('foundrySource',v_expected_source)
  );
  SELECT * INTO v_saved FROM ledger.recurrence_series
  WHERE ledger_id=p_ledger_id AND stable_key=v_stable_key;
  IF NOT FOUND OR v_saved.id::text IS DISTINCT FROM v_receipt->>'seriesId'
     OR v_saved.metadata->'foundrySource' IS DISTINCT FROM v_expected_source THEN
    RAISE EXCEPTION 'Canonical schedule receipt could not be independently verified' USING ERRCODE='23514';
  END IF;
  RETURN jsonb_build_object(
    'ok',true,'replayed',false,
    'canonicalConsequenceKind','ledger_recurrence_series',
    'seriesId',v_saved.id,'ledgerId',p_ledger_id,
    'sourceEntryId',p_entry_id,'sourceSegmentIndex',p_segment_index,
    'title',v_saved.title,'frequency',v_saved.frequency,
    'weekdays',to_jsonb(v_saved.weekdays),
    'timezoneName',v_saved.timezone_name,
    'effectiveStartDate',v_saved.effective_start_date,
    'allDay',v_saved.all_day,
    'localStartTime',v_saved.local_start_time,
    'localEndTime',v_saved.local_end_time,
    'sequence',v_saved.sequence,'aiCarrierAccess',false
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.establish_foundry_weekly_recurrence_self_api_v1(
  p_workspace_id text,p_entry_id text,p_segment_index integer,p_ledger_id uuid,
  p_title text,p_weekday smallint,p_timezone_name text,
  p_effective_start_date date,p_all_day boolean,
  p_local_start_time time DEFAULT NULL,p_local_end_time time DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER
SET search_path TO 'pg_catalog','atlas','public'
AS $$
  SELECT atlas.establish_foundry_weekly_recurrence_self_api_v1(
    $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11
  )
$$;

REVOKE ALL ON FUNCTION atlas.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)
  FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)
  FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION atlas.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.establish_foundry_weekly_recurrence_self_api_v1(text,text,integer,uuid,text,smallint,text,date,boolean,time,time)
  TO authenticated;

COMMIT;
