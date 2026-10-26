BEGIN;
-- Gate 0 deep legacy-read adapter: source-enforced governor-only full-farm disclosure.
-- Preserve each live function signature/implementation; insert a single early gate.

-- Legacy source-owned function object_workbench_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.object_workbench_v1(p_farm_id uuid, p_object_key text, p_history_days integer DEFAULT 14, p_future_days integer DEFAULT 365)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_farm_key text;
  v_object atlas.v_object_workbench%rowtype;
  v_result jsonb;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  if v_role is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select f.stable_key into v_farm_key
  from atlas.farms f
  where f.id = p_farm_id;

  if v_farm_key is null then
    raise exception 'Farm was not found.' using errcode = 'P0002';
  end if;

  select workbench.* into v_object
  from atlas.v_object_workbench workbench
  where workbench.farm_id = p_farm_id
    and workbench.object_key = nullif(btrim(p_object_key), '');

  if v_object.object_id is null then
    raise exception 'Farm object was not found.' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'object', to_jsonb(v_object),
    'cropCycles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cc.id,
        'crop_cycle_key', cc.crop_cycle_key,
        'crop_label', cc.crop_label,
        'variety', cc.variety,
        'cycle_state', cc.cycle_state,
        'lifecycle_status', cc.lifecycle_status,
        'sown_date', cc.sown_date,
        'planted_date', cc.planted_date,
        'germination_checked_date', cc.germination_checked_date,
        'harvest_started_date', cc.harvest_started_date,
        'last_harvest_date', cc.last_harvest_date,
        'expected_germination_start', cc.expected_germination_start,
        'expected_germination_end', cc.expected_germination_end,
        'expected_harvest_watch_start', cc.expected_harvest_watch_start,
        'expected_harvest_watch_end', cc.expected_harvest_watch_end,
        'expected_clear_date', cc.expected_clear_date,
        'note', cc.note
      ) order by cc.created_at)
      from atlas.crop_cycles cc
      where cc.farm_id = p_farm_id
        and cc.object_id = v_object.object_id
        and cc.lifecycle_status = 'active'
    ), '[]'::jsonb),
    'plantInstances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', pi.id,
        'lineage_id', pi.lineage_id,
        'stable_key', pi.stable_key,
        'label', pi.label,
        'quantity', pi.quantity,
        'unit', pi.unit,
        'generation', pi.generation,
        'status', pi.status,
        'acquired_date', pi.acquired_date,
        'planted_date', pi.planted_date,
        'note', pi.note,
        'lineage', case when pl.id is null then null else jsonb_build_object(
          'id', pl.id,
          'stable_key', pl.stable_key,
          'lineage_name', pl.lineage_name,
          'common_name', pl.common_name,
          'botanical_name', pl.botanical_name,
          'source_name', pl.source_name,
          'source_type', pl.source_type,
          'origin_year', pl.origin_year,
          'origin_detail', pl.origin_detail,
          'propagation_goal', pl.propagation_goal
        ) end
      ) order by pi.created_at)
      from atlas.plant_instances pi
      left join atlas.plant_lineages pl on pl.id = pi.lineage_id
      where pi.farm_id = p_farm_id
        and pi.object_id = v_object.object_id
        and pi.status not in ('dead', 'removed', 'archived')
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_id', timeline.event_id,
        'object_id', timeline.object_id,
        'object_key', timeline.object_key,
        'object_label', timeline.object_label,
        'field_log_id', timeline.field_log_id,
        'crop_cycle_id', timeline.crop_cycle_id,
        'plant_instance_id', timeline.plant_instance_id,
        'entity_label', timeline.entity_label,
        'entity_kind', timeline.entity_kind,
        'event_type', timeline.event_type,
        'event_date', timeline.event_date,
        'note', timeline.note,
        'quantity', timeline.quantity,
        'unit', timeline.unit,
        'source', timeline.source,
        'created_at', timeline.created_at
      ) order by timeline.event_date desc, timeline.created_at desc)
      from (
        select *
        from atlas.v_object_event_timeline event_row
        where event_row.farm_id = p_farm_id
          and event_row.object_id = v_object.object_id
        order by event_row.event_date desc, event_row.created_at desc
        limit 40
      ) timeline
    ), '[]'::jsonb),
    'operationalTimeline', atlas.get_object_operational_timeline_v1(
      v_farm_key,
      v_object.object_key,
      greatest(coalesce(p_history_days, 14), 0),
      greatest(coalesce(p_future_days, 365), 0)
    )
  ) into v_result;

  return v_result;
end;
$function$;

-- Legacy source-owned function farm_continuity_audit_v6, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v6(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_day date:=coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_base jsonb;
  v_old_family jsonb:='{}'::jsonb;
  v_old_count integer:=0;
  v_remaining_items jsonb:='[]'::jsonb;
  v_dwell_items jsonb:='[]'::jsonb;
  v_remaining_count integer:=0;
  v_dwell_count integer:=0;
  v_old_high integer:=0;
  v_old_combined_high integer:=0;
  v_new_high integer:=0;
  v_new_combined_high integer:=0;
  v_combined_medium integer:=0;
  v_families jsonb:='[]'::jsonb;
  v_state text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then raise exception 'A farm is required.' using errcode='22023'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  v_base:=atlas.farm_continuity_audit_v5(p_farm_id,v_day);
  select coalesce(f,'{}'::jsonb) into v_old_family
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) f
  where f->>'key'='no_lawful_next_state'
  limit 1;
  v_old_count:=coalesce((v_old_family->>'count')::integer,0);

  with evaluated as (
    select item,atlas.crop_cycle_reality_expression_v5((item->>'cropCycleId')::uuid) packet
    from jsonb_array_elements(coalesce(v_old_family->'items','[]'::jsonb)) item
  ), remaining as (
    select item
    from evaluated
    where coalesce((packet#>>'{continuity,silentNothing}')::boolean,false)=true
  ), dwell as (
    select jsonb_strip_nulls(jsonb_build_object(
      'cropCycleId',item->>'cropCycleId',
      'cropCycleKey',item->>'cropCycleKey',
      'cropLabel',item->>'cropLabel',
      'variety',item->>'variety',
      'cycleState',item->>'cycleState',
      'lifecycleStatus',item->>'lifecycleStatus',
      'continuity',packet->'continuity',
      'fittingOperation',packet->'fittingOperation',
      'lawfulDwell',packet->'lawfulDwell',
      'repairOwner',null,
      'reason','Canonical lifecycle evidence establishes stable perennial occupancy as a lawful continuation state. No task is required merely to prove that the perennial continues to exist.'
    )) item
    from evaluated
    where coalesce((packet#>>'{continuity,silentNothing}')::boolean,false)=false
      and coalesce((packet#>>'{lawfulDwell,applicable}')::boolean,false)=true
  )
  select
    (select count(*)::integer from remaining),
    (select coalesce(jsonb_agg(item order by item->>'cropLabel',item->>'cropCycleId'),'[]'::jsonb) from remaining),
    (select count(*)::integer from dwell),
    (select coalesce(jsonb_agg(item order by item->>'cropLabel',item->>'cropCycleId'),'[]'::jsonb) from dwell)
  into v_remaining_count,v_remaining_items,v_dwell_count,v_dwell_items;

  select coalesce(jsonb_agg(f order by ord),'[]'::jsonb)
  into v_families
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) with ordinality x(f,ord)
  where f->>'key'<>'no_lawful_next_state';

  v_families:=v_families||jsonb_build_array(
    jsonb_build_object(
      'key','no_lawful_next_state','severity','high','count',v_remaining_count,'items',v_remaining_items
    ),
    jsonb_build_object(
      'key','perennial_lawful_dwell','severity','context','count',v_dwell_count,'items',v_dwell_items,
      'meaning','Stable profile-backed perennial bodies may lawfully inhabit their current place without a transition task until a seasonal boundary, care rhythm, explicit claim, observed condition change, or management reclassification requires a new operation.'
    )
  );

  v_old_high:=coalesce((v_base#>>'{summary,highPriorityIssueCount}')::integer,0);
  v_old_combined_high:=coalesce((v_base#>>'{summary,combinedHighPriorityIssueCount}')::integer,v_old_high);
  v_combined_medium:=coalesce((v_base#>>'{summary,combinedMediumPriorityIssueCount}')::integer,coalesce((v_base#>>'{summary,mediumPriorityIssueCount}')::integer,0));
  v_new_high:=greatest(0,v_old_high-(v_old_count-v_remaining_count));
  v_new_combined_high:=greatest(0,v_old_combined_high-(v_old_count-v_remaining_count));
  v_state:=case
    when v_new_combined_high>0 then 'high_priority_continuity_attention'
    when v_combined_medium>0 then 'continuity_attention'
    else 'no_actionable_continuity_gap_detected'
  end;

  return v_base||jsonb_build_object(
    'contractVersion','farm_continuity_audit_v6',
    'state',v_state,
    'summary',(v_base->'summary')||jsonb_build_object(
      'highPriorityIssueCount',v_new_high,
      'combinedHighPriorityIssueCount',v_new_combined_high,
      'noLawfulNextStateCount',v_remaining_count,
      'perennialLawfulDwellCount',v_dwell_count
    ),
    'issueFamilies',v_families,
    'auditCoverage',(v_base->'auditCoverage')||jsonb_build_object(
      'perennialLawfulDwell','audited_from_crop_cycle_lawful_dwell_state_v1_and_crop_cycle_reality_expression_v5'
    ),
    'truthBoundary',(v_base->'truthBoundary')||jsonb_build_object(
      'stablePerennialDwellIsLawfulContinuation',true,
      'lawfulDwellDoesNotGenerateTask',true,
      'profilelessPlantsAreNotInferredPerennial',true,
      'tenderPerennialsAreNotAutoDwell',true,
      'transitionStressReproductiveAndDeclineStatesRemainAuditable',true
    ),
    'principalEscalationCreated',false
  );
end;
$function$;

-- Legacy source-owned function farm_continuity_audit_v7, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v7(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_day date:=coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_base jsonb;
  v_old_family jsonb:='{}'::jsonb;
  v_old_count integer:=0;
  v_remaining_items jsonb:='[]'::jsonb;
  v_remaining_count integer:=0;
  v_wait_items jsonb:='[]'::jsonb;
  v_wait_count integer:=0;
  v_harvest_items jsonb:='[]'::jsonb;
  v_harvest_count integer:=0;
  v_anchor_items jsonb:='[]'::jsonb;
  v_anchor_count integer:=0;
  v_timing_items jsonb:='[]'::jsonb;
  v_timing_count integer:=0;
  v_forecast_items jsonb:='[]'::jsonb;
  v_forecast_count integer:=0;
  v_families jsonb:='[]'::jsonb;
  v_old_high integer:=0;
  v_old_medium integer:=0;
  v_old_combined_high integer:=0;
  v_old_combined_medium integer:=0;
  v_new_high integer:=0;
  v_new_medium integer:=0;
  v_new_combined_high integer:=0;
  v_new_combined_medium integer:=0;
  v_reclassified integer:=0;
  v_state text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then raise exception 'A farm is required.' using errcode='22023'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  v_base:=atlas.farm_continuity_audit_v6(p_farm_id,v_day);

  select coalesce(f,'{}'::jsonb) into v_old_family
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) f
  where f->>'key'='no_lawful_next_state' limit 1;
  v_old_count:=coalesce((v_old_family->>'count')::integer,0);

  with evaluated as (
    select item,
           atlas.crop_cycle_reality_expression_v6((item->>'cropCycleId')::uuid) packet,
           atlas.crop_cycle_biological_progression_state_v1((item->>'cropCycleId')::uuid,v_day) progression
    from jsonb_array_elements(coalesce(v_old_family->'items','[]'::jsonb)) item
  ), normalized as (
    select item,packet,progression,
           coalesce((packet#>>'{continuity,silentNothing}')::boolean,false) silent,
           progression->>'state' progression_state,
           progression->>'issueKey' issue_key
    from evaluated
  )
  select
    (select count(*)::integer from normalized where silent),
    (select coalesce(jsonb_agg(item order by item->>'cropLabel',item->>'cropCycleId'),'[]'::jsonb) from normalized where silent),
    (select count(*)::integer from normalized where not silent and progression_state='lawful_biological_wait'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('biologicalProgression',progression,'continuity',packet->'continuity') order by item->>'cropLabel'),'[]'::jsonb) from normalized where not silent and progression_state='lawful_biological_wait'),
    (select count(*)::integer from normalized where not silent and issue_key='harvest_watch_due_uncovered'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('biologicalProgression',progression,'continuity',packet->'continuity') order by item->>'cropLabel'),'[]'::jsonb) from normalized where not silent and issue_key='harvest_watch_due_uncovered'),
    (select count(*)::integer from normalized where not silent and issue_key='biological_anchor_source_required'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('biologicalProgression',progression,'continuity',packet->'continuity') order by item->>'cropLabel'),'[]'::jsonb) from normalized where not silent and issue_key='biological_anchor_source_required'),
    (select count(*)::integer from normalized where not silent and issue_key='crop_timing_model_source_required'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('biologicalProgression',progression,'continuity',packet->'continuity') order by item->>'cropLabel'),'[]'::jsonb) from normalized where not silent and issue_key='crop_timing_model_source_required'),
    (select count(*)::integer from normalized where not silent and issue_key='biological_forecast_reconciliation_required'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('biologicalProgression',progression,'continuity',packet->'continuity') order by item->>'cropLabel'),'[]'::jsonb) from normalized where not silent and issue_key='biological_forecast_reconciliation_required')
  into v_remaining_count,v_remaining_items,v_wait_count,v_wait_items,
       v_harvest_count,v_harvest_items,v_anchor_count,v_anchor_items,
       v_timing_count,v_timing_items,v_forecast_count,v_forecast_items;

  select coalesce(jsonb_agg(f order by ord),'[]'::jsonb) into v_families
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) with ordinality x(f,ord)
  where f->>'key'<>'no_lawful_next_state';

  v_families:=v_families||jsonb_build_array(
    jsonb_build_object('key','no_lawful_next_state','severity','high','count',v_remaining_count,'items',v_remaining_items),
    jsonb_build_object('key','annual_biological_wait','severity','context','count',v_wait_count,'items',v_wait_items,
      'meaning','A growing annual with a witnessed biological anchor and a future canonical harvest-watch boundary is lawfully progressing biologically until that boundary or observed-condition change.'),
    jsonb_build_object('key','harvest_watch_due_uncovered','severity','high','count',v_harvest_count,'items',v_harvest_items),
    jsonb_build_object('key','biological_anchor_source_required','severity','medium','count',v_anchor_count,'items',v_anchor_items),
    jsonb_build_object('key','crop_timing_model_source_required','severity','medium','count',v_timing_count,'items',v_timing_items),
    jsonb_build_object('key','biological_forecast_reconciliation_required','severity','medium','count',v_forecast_count,'items',v_forecast_items)
  );

  v_reclassified:=greatest(0,v_old_count-v_remaining_count);
  v_old_high:=coalesce((v_base#>>'{summary,highPriorityIssueCount}')::integer,0);
  v_old_medium:=coalesce((v_base#>>'{summary,mediumPriorityIssueCount}')::integer,0);
  v_old_combined_high:=coalesce((v_base#>>'{summary,combinedHighPriorityIssueCount}')::integer,v_old_high);
  v_old_combined_medium:=coalesce((v_base#>>'{summary,combinedMediumPriorityIssueCount}')::integer,v_old_medium);
  v_new_high:=greatest(0,v_old_high-v_reclassified+v_harvest_count);
  v_new_medium:=v_old_medium+v_anchor_count+v_timing_count+v_forecast_count;
  v_new_combined_high:=greatest(0,v_old_combined_high-v_reclassified+v_harvest_count);
  v_new_combined_medium:=v_old_combined_medium+v_anchor_count+v_timing_count+v_forecast_count;
  v_state:=case when v_new_combined_high>0 then 'high_priority_continuity_attention' when v_new_combined_medium>0 then 'continuity_attention' else 'no_actionable_continuity_gap_detected' end;

  return v_base||jsonb_build_object(
    'contractVersion','farm_continuity_audit_v7','state',v_state,
    'summary',(v_base->'summary')||jsonb_build_object(
      'highPriorityIssueCount',v_new_high,'mediumPriorityIssueCount',v_new_medium,
      'combinedHighPriorityIssueCount',v_new_combined_high,'combinedMediumPriorityIssueCount',v_new_combined_medium,
      'noLawfulNextStateCount',v_remaining_count,'annualBiologicalWaitCount',v_wait_count,
      'harvestWatchDueUncoveredCount',v_harvest_count,'biologicalAnchorSourceRequiredCount',v_anchor_count,
      'cropTimingModelSourceRequiredCount',v_timing_count,'biologicalForecastReconciliationRequiredCount',v_forecast_count
    ),
    'issueFamilies',v_families,
    'auditCoverage',(v_base->'auditCoverage')||jsonb_build_object('annualBiologicalProgression','audited_from_crop_cycle_biological_progression_state_v1_and_crop_cycle_reality_expression_v6'),
    'truthBoundary',(v_base->'truthBoundary')||jsonb_build_object(
      'futureBiologicalBoundaryCanBeLawfulWait',true,
      'crossedHarvestWatchBoundaryBecomesInspectionNotSilentNothing',true,
      'missingBiologicalAnchorBecomesSourceRepairNotSilentNothing',true,
      'missingTimingModelBecomesSourceRepairNotSilentNothing',true,
      'noEarlyTaskGeneratedForFutureBiologicalWait',true
    ),
    'principalEscalationCreated',false
  );
end;
$function$;

-- Legacy source-owned function farm_continuity_audit_v8, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.farm_continuity_audit_v8(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_day date:=coalesce(p_as_of_date,(now() at time zone 'America/Chicago')::date);
  v_base jsonb;
  v_old_family jsonb:='{}'::jsonb;
  v_old_count integer:=0;
  v_remaining_count integer:=0;
  v_remaining_items jsonb:='[]'::jsonb;
  v_profile_count integer:=0;
  v_profile_items jsonb:='[]'::jsonb;
  v_families jsonb:='[]'::jsonb;
  v_old_high integer:=0;
  v_old_medium integer:=0;
  v_old_combined_high integer:=0;
  v_old_combined_medium integer:=0;
  v_new_high integer:=0;
  v_new_medium integer:=0;
  v_new_combined_high integer:=0;
  v_new_combined_medium integer:=0;
  v_reclassified integer:=0;
  v_state text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if p_farm_id is null then raise exception 'A farm is required.' using errcode='22023'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  v_base:=atlas.farm_continuity_audit_v7(p_farm_id,v_day);
  select coalesce(f,'{}'::jsonb) into v_old_family
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) f
  where f->>'key'='no_lawful_next_state'
  limit 1;
  v_old_count:=coalesce((v_old_family->>'count')::integer,0);

  with evaluated as (
    select item,
           atlas.crop_cycle_reality_expression_v7((item->>'cropCycleId')::uuid) packet,
           atlas.crop_cycle_profile_source_state_v1((item->>'cropCycleId')::uuid,v_day) profile_source
    from jsonb_array_elements(coalesce(v_old_family->'items','[]'::jsonb)) item
  ), normalized as (
    select item,packet,profile_source,
           coalesce((packet#>>'{continuity,silentNothing}')::boolean,false) silent
    from evaluated
  )
  select
    (select count(*)::integer from normalized where silent),
    (select coalesce(jsonb_agg(item order by item->>'cropLabel',item->>'cropCycleId'),'[]'::jsonb) from normalized where silent),
    (select count(*)::integer from normalized where not silent and profile_source->>'state'='crop_profile_source_required'),
    (select coalesce(jsonb_agg(item||jsonb_build_object('profileSource',profile_source,'continuity',packet->'continuity') order by item->>'cropLabel',item->>'cropCycleId'),'[]'::jsonb)
       from normalized where not silent and profile_source->>'state'='crop_profile_source_required')
  into v_remaining_count,v_remaining_items,v_profile_count,v_profile_items;

  select coalesce(jsonb_agg(f order by ord),'[]'::jsonb) into v_families
  from jsonb_array_elements(coalesce(v_base->'issueFamilies','[]'::jsonb)) with ordinality x(f,ord)
  where f->>'key'<>'no_lawful_next_state';

  v_families:=v_families||jsonb_build_array(
    jsonb_build_object('key','no_lawful_next_state','severity','high','count',v_remaining_count,'items',v_remaining_items),
    jsonb_build_object(
      'key','crop_profile_source_required','severity','medium','count',v_profile_count,'items',v_profile_items,
      'meaning','The crop body is real, but Atlas lacks the canonical crop-profile/lifecycle source needed to classify lawful dwell, biological timing, harvest pattern, frost behavior, or stage-specific continuation. The repair is source classification, not a guessed worker task.'
    )
  );

  v_reclassified:=greatest(0,v_old_count-v_remaining_count);
  v_old_high:=coalesce((v_base#>>'{summary,highPriorityIssueCount}')::integer,0);
  v_old_medium:=coalesce((v_base#>>'{summary,mediumPriorityIssueCount}')::integer,0);
  v_old_combined_high:=coalesce((v_base#>>'{summary,combinedHighPriorityIssueCount}')::integer,v_old_high);
  v_old_combined_medium:=coalesce((v_base#>>'{summary,combinedMediumPriorityIssueCount}')::integer,v_old_medium);

  v_new_high:=greatest(0,v_old_high-v_reclassified);
  v_new_medium:=v_old_medium+v_profile_count;
  v_new_combined_high:=greatest(0,v_old_combined_high-v_reclassified);
  v_new_combined_medium:=v_old_combined_medium+v_profile_count;
  v_state:=case
    when v_new_combined_high>0 then 'high_priority_continuity_attention'
    when v_new_combined_medium>0 then 'continuity_attention'
    else 'no_actionable_continuity_gap_detected'
  end;

  return v_base||jsonb_build_object(
    'contractVersion','farm_continuity_audit_v8',
    'state',v_state,
    'summary',(v_base->'summary')||jsonb_build_object(
      'highPriorityIssueCount',v_new_high,
      'mediumPriorityIssueCount',v_new_medium,
      'combinedHighPriorityIssueCount',v_new_combined_high,
      'combinedMediumPriorityIssueCount',v_new_combined_medium,
      'noLawfulNextStateCount',v_remaining_count,
      'cropProfileSourceRequiredCount',v_profile_count
    ),
    'issueFamilies',v_families,
    'auditCoverage',(v_base->'auditCoverage')||jsonb_build_object(
      'cropProfileSource','audited_from_crop_cycle_profile_source_state_v1_and_crop_cycle_reality_expression_v7'
    ),
    'truthBoundary',(v_base->'truthBoundary')||jsonb_build_object(
      'profilelessLivingCropIsNotSilentNothing',true,
      'profilelessLivingCropRequiresSourceClassification',true,
      'cropNameAndVarietyDoNotAuthorizeLifecycleInference',true,
      'sourceRepairDoesNotGenerateWorkerTask',true
    ),
    'principalEscalationCreated',false
  );
end;
$function$;

-- Legacy source-owned function crop_cycle_profile_source_state_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.crop_cycle_profile_source_state_v1(p_crop_cycle_id uuid, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_open_task_count integer:=0;
  v_state text;
  v_reason text;
  v_applicable boolean:=false;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT c.farm_id FROM atlas.crop_cycles c WHERE c.id=p_crop_cycle_id));
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  select count(*)::integer into v_open_task_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and t.status in ('open','blocked');

  v_applicable:=
    v_cycle.crop_profile_id is null
    and coalesce(v_cycle.lifecycle_status,'active')='active'
    and v_cycle.cycle_state not in ('finished','finished_harvest','cleared','terminated','failed','cancelled','archived','dead')
    and v_open_task_count=0;

  if v_applicable then
    v_state:='crop_profile_source_required';
    v_reason:='The living crop body is established as real crop-cycle truth, but no canonical crop profile currently supplies lifecycle, timing, harvest-pattern, or frost-behavior semantics. Atlas must resolve the profile/lifecycle source before it can infer a lawful passive dwell, biological wait, or stage-specific continuation.';
  elsif v_cycle.crop_profile_id is not null then
    v_state:='source_present';
    v_reason:='A canonical crop profile is already linked.';
  elsif coalesce(v_cycle.lifecycle_status,'active')<>'active' then
    v_state:='not_applicable';
    v_reason:='The crop cycle is not lifecycle-active.';
  elsif v_open_task_count>0 then
    v_state:='operation_present';
    v_reason:='An open crop-linked operation already expresses current continuation; profile-source repair may still be useful but is not required to prevent silent nothing.';
  else
    v_state:='not_applicable';
    v_reason:='The narrow profile-source continuity rule does not apply to this crop state.';
  end if;

  return jsonb_build_object(
    'contractVersion','crop_cycle_profile_source_state_v1',
    'cropCycleId',v_cycle.id,
    'farmId',v_cycle.farm_id,
    'asOfDate',coalesce(p_as_of_date,current_date),
    'applicable',v_applicable,
    'state',v_state,
    'reason',v_reason,
    'fittingOperation',case when v_applicable then 'resolve_crop_profile_and_lifecycle_source' else null end,
    'issueKey',case when v_applicable then 'crop_profile_source_required' else null end,
    'severity',case when v_applicable then 'medium' else null end,
    'sourceEvidence',jsonb_strip_nulls(jsonb_build_object(
      'cropCycleKey',v_cycle.crop_cycle_key,
      'cropLabel',v_cycle.crop_label,
      'variety',v_cycle.variety,
      'cycleState',v_cycle.cycle_state,
      'lifecycleStatus',v_cycle.lifecycle_status,
      'sownDate',v_cycle.sown_date,
      'plantedDate',v_cycle.planted_date,
      'sourceEventId',v_cycle.source_event_id,
      'metadataSource',v_cycle.metadata->>'canonical_source'
    )),
    'epistemicClass',case when v_applicable then 'unresolved' else 'established' end,
    'truthBoundary',jsonb_build_object(
      'cropLabelDoesNotEstablishProfile',true,
      'varietyTextDoesNotEstablishLifecycle',true,
      'profilelessDoesNotMeanNoCropExists',true,
      'profilelessDoesNotAuthorizePerennialOrAnnualInference',true,
      'sourceRepairIsContinuationNotWorkerTask',true,
      'sourceRepairDoesNotCreatePrincipalWork',true
    )
  );
end;
$function$;

-- Legacy source-owned function crop_cycle_stage_continuity_state_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.crop_cycle_stage_continuity_state_v1(p_crop_cycle_id uuid, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_day date:=coalesce(p_as_of_date,current_date);
  v_open_task_count integer:=0;
  v_issue_key text;
  v_state text;
  v_operation text;
  v_reason text;
  v_severity text;
  v_repair_owner text;
  v_applicable boolean:=false;
  v_boundary_passed boolean:=false;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT c.farm_id FROM atlas.crop_cycles c WHERE c.id=p_crop_cycle_id));
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;
  if v_cycle.crop_profile_id is not null then select * into v_profile from atlas.crop_profiles where id=v_cycle.crop_profile_id; end if;

  select count(*)::integer into v_open_task_count
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and t.status in ('open','blocked');

  if v_profile.id is null or coalesce(v_cycle.lifecycle_status,'active')<>'active' or v_open_task_count>0 then
    return jsonb_build_object(
      'contractVersion','crop_cycle_stage_continuity_state_v1','cropCycleId',v_cycle.id,'farmId',v_cycle.farm_id,
      'asOfDate',v_day,'applicable',false,'state',case when v_profile.id is null then 'profile_source_required_elsewhere' when v_open_task_count>0 then 'operation_present' else 'not_applicable' end,
      'issueKey',null,'severity',null,'fittingOperation',null,'repairOwner',null,
      'truthBoundary',jsonb_build_object('profileBackedStateRequired',true,'openOperationRemainsCanonical',true)
    );
  end if;

  v_boundary_passed:=v_cycle.expected_harvest_watch_start is not null and v_cycle.expected_harvest_watch_start<=v_day;

  if v_cycle.cycle_state in ('compromised','stressed') then
    v_issue_key:='condition_reassessment_required';
    v_state:='condition_reassessment_required';
    v_operation:='inspect_condition_and_reclassify';
    v_reason:='The crop is explicitly recorded in a compromised or stressed condition. A current observation must determine recovery, continued production, harvestability, or termination; the condition itself is not a lawful passive wait.';
    v_severity:='high'; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state in ('browsed_alive','partial_stand') then
    v_issue_key:='condition_reassessment_required';
    v_state:='condition_reassessment_required';
    v_operation:='inspect_condition_yield_and_reclassify';
    v_reason:='The crop remains alive but its physical stand has been materially altered. Atlas needs a current condition/yield observation before it can claim recovery, harvest readiness, continued growth, or termination.';
    v_severity:=case when v_boundary_passed then 'high' else 'medium' end; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='cut_back' then
    v_issue_key:='regrowth_or_termination_observation_required';
    v_state:='regrowth_or_termination_observation_required';
    v_operation:='inspect_regrowth_or_close_cycle';
    v_reason:='Cut-back is a transition state. The next lawful move is to observe whether the body is regrowing, should remain for another productive interval, or should be terminated/cleared.';
    v_severity:=case when v_boundary_passed then 'high' else 'medium' end; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='declining' then
    v_issue_key:='decline_disposition_required';
    v_state:='decline_disposition_required';
    v_operation:='inspect_remaining_yield_and_choose_disposition';
    v_reason:='Declining is not a terminal classification. Management needs evidence of remaining usable yield and a disposition: continue harvest, recover/regrow, clear, or terminate.';
    v_severity:='high'; v_repair_owner:='farm_operations_harvest';
  elsif v_cycle.cycle_state in ('flowering','fruiting','budding') then
    v_issue_key:='reproductive_stage_observation_required';
    v_state:='reproductive_stage_observation_required';
    v_operation:='inspect_reproductive_or_harvest_readiness';
    v_reason:='The crop has entered an observed reproductive state. Atlas must observe readiness and reclassify the next lawful production/harvest state rather than infer harvestability from the label alone.';
    v_severity:=case when v_boundary_passed then 'high' else 'medium' end; v_repair_owner:='farm_operations_harvest';
  elsif v_cycle.cycle_state in ('planned','planned_gap_fill') and coalesce(v_cycle.planted_date,v_cycle.sown_date) is not null then
    v_issue_key:='lifecycle_state_reconciliation_required';
    v_state:='lifecycle_state_reconciliation_required';
    v_operation:='reconcile_planned_state_with_physical_entry_evidence';
    v_reason:='The crop cycle is still classified as planned even though sowing or planting evidence records physical entry. Planning state and physical reality must be reconciled before downstream timing is trusted.';
    v_severity:='medium'; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='planted' and v_profile.life_cycle='annual'
        and v_cycle.expected_germination_start is not null and v_cycle.expected_germination_start<=v_day then
    v_issue_key:='emergence_observation_due';
    v_state:='emergence_observation_due';
    v_operation:='inspect_emergence_and_reclassify';
    v_reason:='The crop remains classified as planted after its canonical expected germination/emergence boundary. A current emergence observation is required before Atlas can continue the lifecycle.';
    v_severity:='high'; v_repair_owner:='farm_operations_propagation';
  elsif v_cycle.cycle_state='planted' then
    v_issue_key:='establishment_observation_required';
    v_state:='establishment_observation_required';
    v_operation:='inspect_establishment_and_reclassify';
    v_reason:='The crop is physically planted but has no current transition carrier. A current establishment observation must confirm living/establishing/growing condition or expose a problem.';
    v_severity:='medium'; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='seedling' and coalesce(v_cycle.planted_date,v_cycle.sown_date) is null then
    v_issue_key:='seedling_biological_anchor_source_required';
    v_state:='seedling_biological_anchor_source_required';
    v_operation:='establish_seedling_biological_anchor';
    v_reason:='A real seedling is recorded, but Atlas lacks the sow/plant anchor needed to evaluate its lawful biological progression and future harvest boundary.';
    v_severity:='medium'; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='seedling' then
    v_issue_key:='seedling_progression_observation_required';
    v_state:='seedling_progression_observation_required';
    v_operation:='inspect_seedling_progression_and_reclassify';
    v_reason:='The crop remains in seedling state with no current transition carrier. A current observation must establish continued seedling growth, transplant/establishment readiness, or a problem state.';
    v_severity:='medium'; v_repair_owner:='farm_operations_propagation';
  elsif v_cycle.cycle_state='germinated'
        and v_profile.default_planting_method='direct_sow' then
    v_issue_key:='field_care_observation_required';
    v_state:='field_care_observation_required';
    v_operation:='inspect_field_care_and_growth';
    v_reason:='A direct-sown crop has physically germinated and has no current operation carrier. Germination establishes biological presence, not continued crop condition or harvestability; a current field-care/growth observation must preserve continuity until a later physical stage or readiness observation supersedes it.';
    v_severity:=case when v_boundary_passed then 'high' else 'medium' end;
    v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='establishing' then
    v_issue_key:='establishment_observation_required';
    v_state:='establishment_observation_required';
    v_operation:='inspect_establishment_and_reclassify';
    v_reason:='Establishing is a transition state rather than durable dwell. A current observation must confirm that establishment has completed, remains in progress under a governed wait, or has diverged.';
    v_severity:='medium'; v_repair_owner:='farm_operations_continuity';
  elsif v_cycle.cycle_state='sown_awaiting_emergence' then
    v_issue_key:='emergence_reconciliation_required';
    v_state:='emergence_reconciliation_required';
    v_operation:='recheck_emergence_and_reconcile_state';
    v_reason:='The crop remains sown-awaiting-emergence without a current emergence rhythm/task. Existing sowing and any germination-check evidence must be reconciled into emerged, continue-waiting, failed, or recheck state.';
    v_severity:='medium'; v_repair_owner:='farm_operations_propagation';
  else
    v_issue_key:=null;
  end if;

  v_applicable:=v_issue_key is not null;

  return jsonb_build_object(
    'contractVersion','crop_cycle_stage_continuity_state_v1',
    'cropCycleId',v_cycle.id,'farmId',v_cycle.farm_id,'asOfDate',v_day,
    'applicable',v_applicable,'state',coalesce(v_state,'unclassified_stage'),
    'issueKey',v_issue_key,'severity',v_severity,'fittingOperation',v_operation,'repairOwner',v_repair_owner,'reason',v_reason,
    'source',jsonb_build_object(
      'cropProfileId',v_profile.id,'cropProfileStableKey',v_profile.stable_key,'lifeCycle',v_profile.life_cycle,
      'harvestPattern',v_profile.harvest_pattern,'cycleState',v_cycle.cycle_state,
      'sownDate',v_cycle.sown_date,'plantedDate',v_cycle.planted_date,'germinationCheckedDate',v_cycle.germination_checked_date,
      'expectedGerminationStart',v_cycle.expected_germination_start,'expectedHarvestWatchStart',v_cycle.expected_harvest_watch_start,
      'harvestBoundaryPassed',v_boundary_passed
    ),
    'epistemicClass',case when v_applicable then 'derived' else 'unresolved' end,
    'truthBoundary',jsonb_build_object(
      'stateNameDoesNotProveResult',true,
      'reproductiveStateDoesNotAutomaticallyMeanHarvestable',true,
      'damageStateRequiresReobservation',true,
      'establishingIsNotDurableDwellUntilConfirmed',true,
      'plannedWithPhysicalEntryEvidenceRequiresReconciliation',true,
      'inspectionContinuationDoesNotCreateWorkerTaskAutomatically',true
    )
  );
end;
$function$;

-- Legacy source-owned function crop_cycle_biological_progression_state_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.crop_cycle_biological_progression_state_v1(p_crop_cycle_id uuid, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_day date:=coalesce(p_as_of_date,current_date);
  v_open_task_count integer:=0;
  v_anchor_date date;
  v_state text;
  v_operation text;
  v_reason text;
  v_epistemic text;
  v_issue_key text;
  v_severity text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT c.farm_id FROM atlas.crop_cycles c WHERE c.id=p_crop_cycle_id));
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  if v_cycle.crop_profile_id is not null then select * into v_profile from atlas.crop_profiles where id=v_cycle.crop_profile_id; end if;
  select count(*)::integer into v_open_task_count
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and t.status in ('open','blocked');
  v_anchor_date:=coalesce(v_cycle.planted_date,v_cycle.sown_date);

  if v_profile.id is null or coalesce(v_profile.life_cycle,'')<>'annual' or v_cycle.cycle_state<>'growing' then
    v_state:='not_applicable';
    v_operation:=null;
    v_reason:='The narrow annual-growing biological progression rule does not apply to this crop body.';
    v_epistemic:='established';
  elsif v_open_task_count>0 then
    v_state:='operation_present';
    v_operation:='follow_current_operation';
    v_reason:='An open crop-linked operation already expresses current continuation.';
    v_epistemic:='established';
  elsif v_cycle.expected_harvest_watch_start is not null and v_cycle.expected_harvest_watch_start>v_day then
    v_state:='lawful_biological_wait';
    v_operation:='grow_until_harvest_watch_boundary';
    v_reason:='The annual crop is in normal growth and its canonical expected harvest-watch boundary remains in the future. Biological progression is the lawful continuation until that boundary or an observed condition change.';
    v_epistemic:='derived';
  elsif v_cycle.expected_harvest_watch_start is not null and v_cycle.expected_harvest_watch_start<=v_day then
    v_state:='harvest_readiness_inspection_required';
    v_operation:='inspect_harvest_readiness';
    v_reason:='The canonical expected harvest-watch boundary has arrived or passed while the crop remains in growing state with no open crop-linked operation. A harvest-readiness observation is now the fitting continuation.';
    v_epistemic:='derived';
    v_issue_key:='harvest_watch_due_uncovered';
    v_severity:='high';
  elsif v_anchor_date is not null and (v_profile.days_to_harvest_watch_min is not null or v_profile.days_to_harvest_watch_max is not null) then
    v_state:='biological_forecast_reconciliation_required';
    v_operation:='reconcile_expected_harvest_watch_boundary';
    v_reason:='A witnessed sow/plant anchor and crop-profile timing model exist, but the crop cycle has no canonical expected harvest-watch boundary. The forecast needs reconciliation before Atlas can claim lawful timing.';
    v_epistemic:='derived';
    v_issue_key:='biological_forecast_reconciliation_required';
    v_severity:='medium';
  elsif v_anchor_date is null then
    v_state:='biological_anchor_source_required';
    v_operation:='establish_sow_or_plant_anchor';
    v_reason:='The annual crop is growing, but Atlas lacks a witnessed sow/plant date from which a lawful biological boundary can be evaluated.';
    v_epistemic:='unresolved';
    v_issue_key:='biological_anchor_source_required';
    v_severity:='medium';
  else
    v_state:='crop_timing_model_source_required';
    v_operation:='establish_crop_timing_model';
    v_reason:='The annual crop has a biological anchor but no canonical harvest-watch timing model or expected boundary.';
    v_epistemic:='unresolved';
    v_issue_key:='crop_timing_model_source_required';
    v_severity:='medium';
  end if;

  return jsonb_build_object(
    'contractVersion','crop_cycle_biological_progression_state_v1',
    'cropCycleId',v_cycle.id,'farmId',v_cycle.farm_id,'asOfDate',v_day,
    'applicable',v_state<>'not_applicable',
    'state',v_state,
    'fittingOperation',v_operation,
    'reason',v_reason,
    'issueKey',v_issue_key,
    'severity',v_severity,
    'source',jsonb_strip_nulls(jsonb_build_object(
      'cropProfileId',v_profile.id,
      'cropProfileStableKey',v_profile.stable_key,
      'lifeCycle',v_profile.life_cycle,
      'daysToHarvestWatchMin',v_profile.days_to_harvest_watch_min,
      'daysToHarvestWatchMax',v_profile.days_to_harvest_watch_max,
      'sownDate',v_cycle.sown_date,
      'plantedDate',v_cycle.planted_date,
      'biologicalAnchorDate',v_anchor_date,
      'expectedHarvestWatchStart',v_cycle.expected_harvest_watch_start
    )),
    'nextBoundary',case
      when v_state='lawful_biological_wait' then jsonb_build_object('kind','expected_harvest_watch_start','date',v_cycle.expected_harvest_watch_start,'precision','date')
      when v_state='harvest_readiness_inspection_required' then jsonb_build_object('kind','harvest_watch_boundary_crossed','date',v_cycle.expected_harvest_watch_start,'daysPast',v_day-v_cycle.expected_harvest_watch_start)
      else null end,
    'epistemicClass',v_epistemic,
    'truthBoundary',jsonb_build_object(
      'createdAtIsNotBiologicalAnchor',true,
      'profileTimingDoesNotReplaceWitnessedPlantingOrSowing',true,
      'futureExpectedBoundaryCanSupportLawfulWait',true,
      'crossedExpectedBoundaryRequiresObservationNotAutomaticHarvestClaim',true,
      'missingForecastIsRepairableSourceGapNotSilentNothing',true,
      'biologicalWaitDoesNotCreateTaskBeforeBoundary',true
    )
  );
end;
$function$;

-- Legacy source-owned function crop_cycle_postproduction_state_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.crop_cycle_postproduction_state_v1(p_crop_cycle_id uuid, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_management atlas.crop_cycle_management_events%rowtype;
  v_observation atlas.crop_observations%rowtype;
  v_open_clear_task uuid;
  v_state text;
  v_operation text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT c.farm_id FROM atlas.crop_cycles c WHERE c.id=p_crop_cycle_id));
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select * into v_management
  from atlas.crop_cycle_management_events
  where crop_cycle_id=v_cycle.id and event_date<=coalesce(p_as_of_date,current_date)
  order by event_date desc,created_at desc limit 1;

  select * into v_observation
  from atlas.crop_observations
  where crop_cycle_id=v_cycle.id and coalesce(observed_date,created_at::date)<=coalesce(p_as_of_date,current_date)
  order by coalesce(observed_date,created_at::date) desc,created_at desc limit 1;

  select t.id into v_open_clear_task
  from atlas.task_crop_cycles tc join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and tc.role='clears'
    and t.task_type='crop_clear' and t.status in ('open','blocked')
  order by t.created_at desc limit 1;

  if v_cycle.lifecycle_status in ('complete','archived') or v_cycle.cycle_state='cleared' then
    v_state:='cleared_complete';
    v_operation:=null;
  elsif v_management.disposition in ('clear','clear_and_compost') and v_open_clear_task is not null then
    v_state:='clearance_operation_present';
    v_operation:='clear_crop';
  elsif v_management.disposition in ('clear','clear_and_compost') then
    v_state:='clearance_carrier_required';
    v_operation:='create_clear_operation';
  elsif v_cycle.cycle_state in ('finished','finished_harvest','declining') then
    v_state:='management_disposition_required';
    v_operation:='choose_continue_retain_or_clear';
  else
    v_state:='not_postproduction';
    v_operation:=null;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','crop_cycle_postproduction_state_v1',
    'cropCycleId',v_cycle.id,
    'asOfDate',coalesce(p_as_of_date,current_date),
    'state',v_state,
    'fittingOperation',v_operation,
    'biologicalState',jsonb_build_object(
      'cycleState',v_cycle.cycle_state,
      'lifecycleStatus',v_cycle.lifecycle_status,
      'clearedDate',v_cycle.cleared_date
    ),
    'physicalObservation',case when v_observation.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'observedDate',v_observation.observed_date,
      'stage',v_observation.stage,
      'condition',v_observation.condition,
      'confidence',v_observation.confidence
    )) end,
    'managementState',case when v_management.id is null then null else jsonb_strip_nulls(jsonb_build_object(
      'eventDate',v_management.event_date,
      'managementPurpose',v_management.management_purpose,
      'disposition',v_management.disposition,
      'biomassDestination',v_management.biomass_destination,
      'confidence',v_management.confidence
    )) end,
    'clearTaskId',v_open_clear_task,
    'truthBoundary',jsonb_build_object(
      'biologicalStageIsNotPhysicalCondition',true,
      'physicalConditionIsNotManagementDisposition',true,
      'cropCompletionDoesNotImplyObjectVacancy',true,
      'clearanceDoesNotTerminateOtherCropBodiesOnSameObject',true,
      'compostIsBiomassDispositionNotAPlantBiologicalStage',true
    )
  ));
end;
$function$;

-- Legacy source-owned function crop_cycle_lawful_dwell_state_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.crop_cycle_lawful_dwell_state_v1(p_crop_cycle_id uuid, p_as_of_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_open_task_count integer:=0;
  v_active_lot_count integer:=0;
  v_months jsonb:='[]'::jsonb;
  v_applicable boolean:=false;
  v_reason text;
  v_state text;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT c.farm_id FROM atlas.crop_cycles c WHERE c.id=p_crop_cycle_id));
  if p_crop_cycle_id is null then raise exception 'Crop cycle is required.' using errcode='22023'; end if;
  select * into v_cycle from atlas.crop_cycles where id=p_crop_cycle_id;
  if v_cycle.id is null then raise exception 'Crop cycle not found.' using errcode='P0002'; end if;
  if auth.uid() is not null and not atlas.is_farm_member(v_cycle.farm_id) then raise exception 'Active farm membership required.' using errcode='42501'; end if;

  if v_cycle.crop_profile_id is not null then
    select * into v_profile from atlas.crop_profiles where id=v_cycle.crop_profile_id;
  end if;

  select count(*)::integer into v_open_task_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id=tc.task_id
  where tc.crop_cycle_id=v_cycle.id and t.status in ('open','blocked');

  select count(distinct plc.production_lot_id)::integer into v_active_lot_count
  from atlas.production_lot_crop_cycles plc
  join atlas.production_lots pl on pl.id=plc.production_lot_id
  where plc.crop_cycle_id=v_cycle.id
    and coalesce(pl.lifecycle_status,'') not in ('cancelled','failed','complete','completed','archived','terminated');

  if jsonb_typeof(coalesce(v_profile.metadata->'seasonal_harvest_months','[]'::jsonb))='array' then
    v_months:=coalesce(v_profile.metadata->'seasonal_harvest_months','[]'::jsonb);
  end if;

  v_applicable :=
    coalesce(v_cycle.lifecycle_status,'active')='active'
    and v_profile.id is not null
    and v_profile.life_cycle in ('perennial','perennial_bulb')
    and v_cycle.cycle_state in ('established','established_division','growing','living')
    and v_open_task_count=0
    and v_active_lot_count=0;

  if v_applicable then
    v_state:='lawful_dwell';
    v_reason:='Canonical crop-profile lifecycle marks this body as a durable perennial, its current state is stable living occupancy, and no active Production lot or open crop-linked operation currently requires transition. Continued inhabitation is therefore a lawful state until a seasonal boundary, governed care rhythm, explicit claim, or observed condition changes.';
  elsif v_profile.id is null then
    v_state:='source_required';
    v_reason:='No crop profile establishes a durable lifecycle class; Atlas may not infer perennial dwell from the crop name.';
  elsif coalesce(v_profile.life_cycle,'') not in ('perennial','perennial_bulb') then
    v_state:='not_applicable';
    v_reason:='The canonical crop profile does not establish a perennial or perennial-bulb lifecycle eligible for passive lawful dwell.';
  elsif v_cycle.cycle_state not in ('established','established_division','growing','living') then
    v_state:='transition_state_requires_separate_continuity';
    v_reason:='The current crop state is not classified as stable perennial dwell; transition, stress, reproductive, decline, or establishment states require their own continuity evidence.';
  elsif v_active_lot_count>0 then
    v_state:='production_continuity_controls';
    v_reason:='An active Production lot carries this crop body, so Production obligations and claims—not generic perennial dwell—govern continuation.';
  elsif v_open_task_count>0 then
    v_state:='operation_present';
    v_reason:='An open crop-linked operation already expresses current continuation.';
  else
    v_state:='unresolved';
    v_reason:='The body is not currently eligible for the narrow perennial lawful-dwell rule.';
  end if;

  return jsonb_build_object(
    'contractVersion','crop_cycle_lawful_dwell_state_v1',
    'cropCycleId',v_cycle.id,
    'farmId',v_cycle.farm_id,
    'asOfDate',coalesce(p_as_of_date,current_date),
    'applicable',v_applicable,
    'state',v_state,
    'reason',v_reason,
    'source',case when v_profile.id is null then null else jsonb_build_object(
      'kind','crop_profile',
      'id',v_profile.id,
      'stableKey',v_profile.stable_key,
      'lifeCycle',v_profile.life_cycle,
      'harvestPattern',v_profile.harvest_pattern,
      'frostBehavior',v_profile.frost_behavior,
      'projectionMode',v_profile.metadata->>'projection_mode',
      'seasonalHarvestMonths',v_months
    ) end,
    'witness',jsonb_build_object(
      'cycleState',v_cycle.cycle_state,
      'lifecycleStatus',v_cycle.lifecycle_status,
      'openCropLinkedTaskCount',v_open_task_count,
      'activeProductionLotCount',v_active_lot_count
    ),
    'nextBoundary',case when v_applicable then jsonb_build_object(
      'kind','seasonal_or_observed_condition_change',
      'seasonalHarvestMonths',v_months,
      'datePrecision',case when jsonb_array_length(v_months)>0 then 'month_only' else 'unresolved' end,
      'exactDate',null,
      'otherTriggers',jsonb_build_array('governed_care_rhythm','explicit_destination_or_harvest_claim','observed_condition_change','management_reclassification')
    ) else null end,
    'epistemicClass',case when v_applicable then 'derived' when v_profile.id is null then 'unresolved' else 'established' end,
    'truthBoundary',jsonb_build_object(
      'cropNameDoesNotEstablishPerennialLifecycle',true,
      'tenderPerennialIsNotAutoDwell',true,
      'establishingStressDeclineAndReproductiveStatesAreNotAutoDwell',true,
      'activeProductionLotOverridesGenericDwell',true,
      'lawfulDwellDoesNotMeanNoCareEver',true,
      'lawfulDwellIsAContinuationStateNotATask',true
    )
  );
end;
$function$;

-- Legacy source-owned function farm_goal_list_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.farm_goal_list_v1(p_farm_id uuid, p_as_of_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare v_result jsonb;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null or not atlas.is_farm_member(p_farm_id) then raise exception 'Active farm membership is required to read goals.' using errcode='42501'; end if;
  select coalesce(jsonb_agg(atlas.resolve_goal_state_v1(goal.id,p_as_of_date) order by goal.priority desc,goal.created_at),'[]'::jsonb) into v_result from atlas.goals goal where goal.farm_id=p_farm_id and goal.active;
  return v_result;
end;
$function$;

-- Legacy source-owned function flower_sale_buyer_options_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.flower_sale_buyer_options_v1(p_farm_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_role text;
  v_rows jsonb;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_role:=atlas.current_farm_role(p_farm_id);
  if v_role not in ('owner','manager','farm_hand') then
    raise exception 'Active farm membership required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',buyer.id,
    'businessName',buyer.business_name,
    'buyerType',buyer.buyer_type,
    'relationshipStatus',buyer.relationship_status,
    'priorityRank',buyer.priority_rank
  ) order by buyer.priority_rank nulls last,buyer.business_name),'[]'::jsonb)
  into v_rows
  from atlas.buyer_relationship_reconstruction buyer
  where buyer.farm_id=p_farm_id;

  return v_rows;
end;
$function$;

-- Legacy source-owned function home_task_cards_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.home_task_cards_v1(p_farm_id uuid, p_worker_key text DEFAULT NULL::text, p_due_through date DEFAULT NULL::date, p_done_date date DEFAULT NULL::date)
 RETURNS SETOF atlas.v_task_cards
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_role text;
  v_current_membership_id uuid;
  v_current_worker_key text;
  v_requested_worker_key text := nullif(lower(btrim(p_worker_key)), '');
  v_task_ids uuid[] := '{}'::uuid[];
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1(p_farm_id);
  v_role := atlas.current_farm_role(p_farm_id);
  v_current_membership_id := atlas.current_membership_id(p_farm_id);

  if v_role is null or v_current_membership_id is null then
    raise exception 'Active farm membership required.' using errcode = '42501';
  end if;

  select nullif(lower(btrim(fm.worker_key)), '')
  into v_current_worker_key
  from atlas.farm_memberships fm
  where fm.id = v_current_membership_id
    and fm.farm_id = p_farm_id
    and fm.active = true;

  if v_current_worker_key is null then
    raise exception 'Current Atlas worker identity was not found.' using errcode = 'P0002';
  end if;

  if v_requested_worker_key is not null
     and v_requested_worker_key is distinct from v_current_worker_key
  then
    raise exception 'The home reader may only load the signed-in membership.' using errcode = '42501';
  end if;

  select coalesce(array_agg(task.id), '{}'::uuid[])
  into v_task_ids
  from atlas.tasks task
  where task.farm_id = p_farm_id
    and task.status <> 'archived'
    and (
      task.visibility_scope = 'farm_shared'
      or (
        task.visibility_scope = 'assigned_worker'
        and task.assigned_membership_id = v_current_membership_id
      )
      or (
        v_role = 'owner'
        and task.visibility_scope = 'owner'
        and (
          task.assigned_membership_id is null
          or task.assigned_membership_id = v_current_membership_id
        )
      )
    )
    and (
      (
        task.status in ('open', 'blocked')
        and (p_due_through is null or task.due_date is null or task.due_date <= p_due_through)
      )
      or (
        task.status = 'done'
        and p_done_date is not null
        and task.due_date = p_done_date
      )
    );

  if cardinality(v_task_ids) = 0 then
    return;
  end if;

  return query
  select card.*
  from atlas.v_task_cards card
  where card.task_id = any(v_task_ids)
  order by card.due_date nulls last, card.priority, card.created_at;
end;
$function$;

-- Legacy source-owned function task_plant_contents_v1, protected before prior role/record lookups.
CREATE OR REPLACE FUNCTION atlas.task_plant_contents_v1(p_task_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas'
AS $function$
declare
  v_task atlas.tasks%rowtype;
  v_contents jsonb;
BEGIN
  PERFORM atlas.require_governed_farm_full_disclosure_self_v1((SELECT t.farm_id FROM atlas.tasks t WHERE t.id=p_task_id));
  select t.* into v_task
  from atlas.tasks t
  where t.id = p_task_id;

  if v_task.id is null then
    raise exception 'Task not found.' using errcode = 'P0002';
  end if;

  if not atlas.can_read_task_in_journal_v1(p_task_id) then
    raise exception 'This task is not available to the signed-in farm member.' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'contentId', row.content_id,
      'objectId', row.object_id,
      'objectKey', row.object_key,
      'objectLabel', row.object_label,
      'contentLabel', row.content_label,
      'displayLabel', row.display_label,
      'variety', row.variety,
      'contentType', row.content_type,
      'status', row.status,
      'displayOrder', row.display_order
    ) order by row.display_order, row.display_label
  ), '[]'::jsonb)
  into v_contents
  from (
    select distinct on (oc.id)
      oc.id as content_id,
      go.id as object_id,
      go.stable_key as object_key,
      go.label as object_label,
      oc.content_label,
      case
        when lower(oc.content_label) = 'sunflower'
          and nullif(btrim(coalesce(oc.variety, '')), '') is not null
          then btrim(oc.variety) || ' sunflower'
        when lower(oc.content_label) in ('bearded iris', 'iris') then 'Iris'
        else oc.content_label
      end as display_label,
      oc.variety,
      oc.content_type,
      oc.status,
      case
        when coalesce(oc.metadata ->> 'display_order', '') ~ '^\d+$'
          then (oc.metadata ->> 'display_order')::integer
        else 999
      end as display_order
    from atlas.task_objects task_object
    join atlas.growing_objects go on go.id = task_object.object_id
    join atlas.object_contents oc on oc.object_id = go.id
    where task_object.task_id = p_task_id
      and lower(coalesce(oc.status, '')) not in ('cleared', 'archived', 'removed', 'failed')
    order by oc.id
  ) row;

  return jsonb_build_object('taskId', p_task_id, 'contents', v_contents);
end;
$function$;

COMMIT;
