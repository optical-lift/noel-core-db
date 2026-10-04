create or replace function intelligence.calculate_appointed_time_packet_v1(
  p_month1_day1 date default null,
  p_month7_day1 date default null,
  p_weeks_count_start date default null
)
returns jsonb
language sql
stable
set search_path to 'pg_catalog', 'draft'
as $function$
select jsonb_build_object(
  'engine_version','condition_first_feast_calculator_v1',
  'input_contract', jsonb_build_object(
    'month1_day1', p_month1_day1,
    'month7_day1', p_month7_day1,
    'weeks_count_start', p_weeks_count_start,
    'month1_input_status', case when p_month1_day1 is null then 'unresolved' else 'candidate_or_established_input_supplied' end,
    'month7_input_status', case when p_month7_day1 is null then 'unresolved' else 'candidate_or_established_input_supplied' end,
    'weeks_input_status', case when p_weeks_count_start is null then 'unresolved' else 'harvest_count_input_supplied' end,
    'important','Supplying a civil date does not establish the canonical physical identity of a chodesh boundary; it only permits conditional downstream arithmetic.'
  ),
  'annual_gate', jsonb_build_object(
    'packet_key','appointed_abib_month1_rank_gate_v1',
    'status', case when p_month1_day1 is null then 'blocked' else 'input_supplied' end,
    'unresolved_physical_identity', true,
    'source_boundary','Current chodesh may receive annual rank one when warranted as chodesh ha-X; exact X and exact physical month-head marker remain unresolved.',
    'prohibited_substitutions', jsonb_build_array('equinox_as_canonical_gate','first_crescent_as_canonical_gate','conjunction_as_canonical_gate','modern_crop_maturity_percentage')
  ),
  'month1_derived', jsonb_build_array(
    jsonb_build_object(
      'state_key','month1_day10',
      'canon_coordinate','Month 1 Day 10',
      'date', case when p_month1_day1 is null then null else p_month1_day1 + 9 end,
      'status', case when p_month1_day1 is null then 'blocked_by_month1_gate' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Exo 12:3'),
      'dependency','Month 1 Day 1'
    ),
    jsonb_build_object(
      'state_key','pesach_month1_day14',
      'canon_coordinate','Month 1 Day 14',
      'date', case when p_month1_day1 is null then null else p_month1_day1 + 13 end,
      'status', case when p_month1_day1 is null then 'blocked_by_month1_gate' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Exo 12:6','Lev 23:5','Num 9:3-5'),
      'dependency','Month 1 Day 1; participant/place conditions remain packet-specific'
    ),
    jsonb_build_object(
      'state_key','matzot_open_month1_day15',
      'canon_coordinate','Month 1 Day 15',
      'date', case when p_month1_day1 is null then null else p_month1_day1 + 14 end,
      'status', case when p_month1_day1 is null then 'blocked_by_month1_gate' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:6','Num 28:17'),
      'dependency','Month 1 Day 1'
    ),
    jsonb_build_object(
      'state_key','matzot_close_month1_day21',
      'canon_coordinate','Month 1 Day 21',
      'date', case when p_month1_day1 is null then null else p_month1_day1 + 20 end,
      'status', case when p_month1_day1 is null then 'blocked_by_month1_gate' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Exo 12:18','Lev 23:6-8'),
      'dependency','Month 1 Day 1'
    )
  ),
  'weeks_count_generated', jsonb_build_object(
    'packet_key','appointed_weeks_count_generated_packet',
    'count_start', p_weeks_count_start,
    'day50_date', case when p_weeks_count_start is null then null else p_weeks_count_start + 49 end,
    'status', case when p_weeks_count_start is null then 'blocked_by_harvest_count_start' else 'conditionally_derived_from_count_start' end,
    'source_refs', jsonb_build_array('Lev 23:10-16','Deut 16:9-10'),
    'guardrail','This engine does not derive Weeks from a fixed Month-1 date. The harvest/Omer/sickle start condition must be supplied independently.'
  ),
  'month7_derived', jsonb_build_array(
    jsonb_build_object(
      'state_key','month7_day1_teruah',
      'canon_coordinate','Month 7 Day 1',
      'date', p_month7_day1,
      'status', case when p_month7_day1 is null then 'blocked_by_month7_boundary' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:24-25','Num 29:1-6'),
      'dependency','Month 7 Day 1 boundary must be independently established from the running chodesh sequence'
    ),
    jsonb_build_object(
      'state_key','kippurim_month7_day10',
      'canon_coordinate','Month 7 Day 10',
      'date', case when p_month7_day1 is null then null else p_month7_day1 + 9 end,
      'status', case when p_month7_day1 is null then 'blocked_by_month7_boundary' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:27-32','Num 29:7-11'),
      'dependency','Month 7 Day 1'
    ),
    jsonb_build_object(
      'state_key','sukkot_open_month7_day15',
      'canon_coordinate','Month 7 Day 15',
      'date', case when p_month7_day1 is null then null else p_month7_day1 + 14 end,
      'status', case when p_month7_day1 is null then 'blocked_by_month7_boundary' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:34','Num 29:12'),
      'dependency','Month 7 Day 1; ingathering/material conditions remain source-relevant'
    ),
    jsonb_build_object(
      'state_key','sukkot_day7_month7_day21',
      'canon_coordinate','Month 7 Day 21',
      'date', case when p_month7_day1 is null then null else p_month7_day1 + 20 end,
      'status', case when p_month7_day1 is null then 'blocked_by_month7_boundary' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:34-36'),
      'dependency','Month 7 Day 1'
    ),
    jsonb_build_object(
      'state_key','eighth_day_month7_day22',
      'canon_coordinate','Month 7 Day 22 / eighth-day transition',
      'date', case when p_month7_day1 is null then null else p_month7_day1 + 21 end,
      'status', case when p_month7_day1 is null then 'blocked_by_month7_boundary' else 'conditionally_derived' end,
      'source_refs', jsonb_build_array('Lev 23:36,39','Num 29:35'),
      'dependency','Month 7 Day 1 and completion of seven-day Sukkot state'
    )
  ),
  'provenance', jsonb_build_object(
    'month_day_arithmetic','canon_direct_count_or_coordinate once the relevant month boundary is supplied',
    'annual_month1_gate','Run 49 working inference; exact X and month-head physical identity unresolved',
    'weeks','canon count-generated state; requires independent harvest/count start input',
    'gregorian_dates','conditional projections only; civil-date input has no independent canonical authority'
  ),
  'response_authorized', false,
  'interpretation_prohibited', true
);
$function$;