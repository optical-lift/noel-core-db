-- Atlas crop lifecycle continuity contract v1.
--
-- This layer is deliberately read-first. It compiles existing crop-profile biology,
-- explicit stage rules, live crop-cycle evidence, production lots, and future-work
-- custody into one continuity audit without auto-authoring worker-facing tasks.

create table if not exists atlas.crop_lifecycle_stage_rules (
  id uuid primary key default gen_random_uuid(),
  crop_profile_id uuid not null references atlas.crop_profiles(id) on delete cascade,
  stage_key text not null check (stage_key = any (array[
    'source_input'::text,
    'start'::text,
    'germinate'::text,
    'seedling_care'::text,
    'pot_up'::text,
    'grow_out'::text,
    'harden'::text,
    'destination'::text,
    'transplant'::text,
    'establish'::text,
    'care_loop'::text,
    'pinch'::text,
    'harvest_watch'::text,
    'harvest_or_service'::text,
    'decline'::text,
    'terminal_disposition'::text,
    'winter'::text,
    'spring_return'::text,
    'successor'::text
  ])),
  disposition text not null check (disposition = any (array[
    'required'::text,
    'optional'::text,
    'conditional'::text,
    'prohibited'::text,
    'not_applicable'::text
  ])),
  timing_min_days integer check (timing_min_days is null or timing_min_days >= 0),
  timing_max_days integer check (timing_max_days is null or timing_max_days >= 0),
  trigger_spec jsonb not null default '{}'::jsonb check (jsonb_typeof(trigger_spec) = 'object'),
  rule_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(rule_payload) = 'object'),
  confidence text not null default 'explicit'::text,
  source text not null,
  note text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crop_lifecycle_stage_rules_timing_order_check
    check (timing_min_days is null or timing_max_days is null or timing_max_days >= timing_min_days),
  constraint crop_lifecycle_stage_rules_profile_stage_key
    unique (crop_profile_id, stage_key)
);

create index if not exists crop_lifecycle_stage_rules_profile_active_idx
  on atlas.crop_lifecycle_stage_rules (crop_profile_id, active, stage_key);

alter table atlas.crop_lifecycle_stage_rules enable row level security;

revoke all on table atlas.crop_lifecycle_stage_rules from anon, authenticated;
grant all on table atlas.crop_lifecycle_stage_rules to service_role;

drop trigger if exists crop_lifecycle_stage_rules_set_updated_at on atlas.crop_lifecycle_stage_rules;
create trigger crop_lifecycle_stage_rules_set_updated_at
before update on atlas.crop_lifecycle_stage_rules
for each row execute function atlas.set_updated_at();

create or replace view atlas.v_crop_lifecycle_contract_v1
with (security_invoker = true)
as
with stage_catalog(stage_key, stage_order, stage_label) as (
  values
    ('source_input'::text, 10, 'Source / obtain input'::text),
    ('start'::text, 20, 'Start / sow / divide / receive'::text),
    ('germinate'::text, 30, 'Germinate / root / emerge'::text),
    ('seedling_care'::text, 40, 'Seedling care'::text),
    ('pot_up'::text, 50, 'Pot up / thin'::text),
    ('grow_out'::text, 60, 'Grow out'::text),
    ('harden'::text, 70, 'Harden'::text),
    ('destination'::text, 80, 'Destination / bed readiness'::text),
    ('transplant'::text, 90, 'Transplant / plant out'::text),
    ('establish'::text, 100, 'Establishment check'::text),
    ('care_loop'::text, 110, 'Field / stand care loop'::text),
    ('pinch'::text, 120, 'Pinch / train / cut-back rule'::text),
    ('harvest_watch'::text, 130, 'Harvest / display readiness watch'::text),
    ('harvest_or_service'::text, 140, 'Harvest / seed-save / display service'::text),
    ('decline'::text, 150, 'Condition-driven decline'::text),
    ('terminal_disposition'::text, 160, 'Clear or persist decision'::text),
    ('winter'::text, 170, 'Fall care / dormancy / overwinter'::text),
    ('spring_return'::text, 180, 'Spring return / survival / gap fill'::text),
    ('successor'::text, 190, 'Successor / next seasonal cycle'::text)
), base as (
  select
    cp.id as crop_profile_id,
    cp.stable_key as crop_profile_stable_key,
    cp.crop_label,
    cp.variety,
    cp.life_cycle,
    cp.default_planting_method,
    cp.harvest_pattern,
    cp.days_to_germination_min,
    cp.days_to_germination_max,
    cp.days_to_harvest_watch_min,
    cp.days_to_harvest_watch_max,
    cp.clear_offset_days,
    cp.frost_behavior,
    cp.decline_signal,
    coalesce(cp.metadata, '{}'::jsonb) as profile_metadata,
    s.stage_key,
    s.stage_order,
    s.stage_label,
    r.id as explicit_rule_id,
    r.disposition as explicit_disposition,
    r.timing_min_days as explicit_timing_min_days,
    r.timing_max_days as explicit_timing_max_days,
    r.trigger_spec as explicit_trigger_spec,
    r.rule_payload as explicit_rule_payload,
    r.confidence as explicit_confidence,
    r.source as explicit_source,
    r.note as explicit_note
  from atlas.crop_profiles cp
  cross join stage_catalog s
  left join atlas.crop_lifecycle_stage_rules r
    on r.crop_profile_id = cp.id
   and r.stage_key = s.stage_key
   and r.active
), inferred as (
  select b.*,
    lower(coalesce(b.default_planting_method, '')) as method_lc,
    lower(coalesce(b.life_cycle, '')) as life_cycle_lc,
    lower(coalesce(b.frost_behavior, '')) as frost_lc,
    (
      b.profile_metadata ? 'germination_workflow_enabled'
      or b.profile_metadata ? 'germination_check_mode'
      or lower(coalesce(b.default_planting_method, '')) like '%seed%'
      or lower(coalesce(b.default_planting_method, '')) like '%sow%'
    ) as has_germination_signal,
    (
      b.profile_metadata ? 'pot_up_days_min'
      or b.profile_metadata ? 'pot_up_days_max'
      or b.profile_metadata ? 'pot_up_readiness_cue'
    ) as has_pot_up_signal,
    (
      b.profile_metadata ? 'hardening_start_days_min'
      or b.profile_metadata ? 'hardening_start_days_max'
      or b.profile_metadata ? 'hardening_duration_days_min'
      or b.profile_metadata ? 'hardening_duration_days_max'
      or b.profile_metadata ? 'hardening_start_date'
    ) as has_hardening_signal,
    (
      b.profile_metadata ? 'transplant_ready_days_min'
      or b.profile_metadata ? 'transplant_ready_days_max'
      or b.profile_metadata ? 'transplant_readiness_cue'
      or b.profile_metadata ? 'target_transplant_date'
      or b.profile_metadata ? 'target_transplant_window_end'
      or b.profile_metadata ? 'spring_planting_date'
    ) as has_transplant_signal,
    (
      b.profile_metadata ? 'pinch_days_min'
      or b.profile_metadata ? 'pinch_days_max'
      or b.profile_metadata ? 'pinch'
      or exists (
        select 1
        from jsonb_array_elements(
          case
            when jsonb_typeof(b.profile_metadata -> 'tending_gate_template') = 'array'
              then b.profile_metadata -> 'tending_gate_template'
            else '[]'::jsonb
          end
        ) gate
        where lower(coalesce(gate ->> 'key', '')) = 'pinch'
      )
    ) as has_pinch_signal,
    (
      b.harvest_pattern is not null
      or b.days_to_harvest_watch_min is not null
      or b.days_to_harvest_watch_max is not null
      or b.profile_metadata ? 'harvest_start_month_day'
      or b.profile_metadata ? 'harvest_end_month_day'
      or b.profile_metadata ? 'seasonal_harvest_months'
      or b.profile_metadata ? 'harvest_cut_stage'
      or b.profile_metadata ? 'harvest_stage'
      or b.profile_metadata ? 'mature_harvest'
    ) as has_harvest_signal,
    (
      b.clear_offset_days is not null
      or b.profile_metadata ? 'clear_bed_month_day'
      or b.profile_metadata ? 'clear_bed_timing_basis'
      or b.profile_metadata ? 'annual_landscape_clear_rule'
      or b.profile_metadata ? 'working_frost_clear_date'
    ) as has_clear_signal,
    (
      b.decline_signal is not null
      or b.clear_offset_days is not null
      or b.profile_metadata ? 'working_frost_clear_date'
      or b.profile_metadata ? 'clear_bed_month_day'
    ) as has_decline_signal,
    (
      lower(coalesce(b.frost_behavior, '')) like '%winter%'
      or lower(coalesce(b.frost_behavior, '')) like '%overwinter%'
      or lower(coalesce(b.life_cycle, '')) = 'overwintered annual'
    ) as has_winter_signal,
    (
      lower(coalesce(b.default_planting_method, '')) like '%grow_room%'
      or lower(coalesce(b.default_planting_method, '')) like '%indoor%'
      or lower(coalesce(b.default_planting_method, '')) like '%container%'
    ) as controlled_start,
    (
      lower(coalesce(b.default_planting_method, '')) = 'direct_sow'
      or lower(coalesce(b.default_planting_method, '')) = 'direct sow'
    ) as pure_direct_sow,
    (
      lower(coalesce(b.default_planting_method, '')) like '% or %'
      or lower(coalesce(b.default_planting_method, '')) like '%/%'
    ) as mixed_method
  from base b
), compiled as (
  select i.*,
    case i.stage_key
      when 'source_input' then 'required'
      when 'start' then 'required'
      when 'germinate' then
        case
          when i.has_germination_signal then 'required'
          when i.method_lc in ('division','clump','bulb_or_transplant','transplant','start') then 'not_applicable'
          when i.mixed_method then 'conditional'
          else 'unknown'
        end
      when 'seedling_care' then
        case
          when i.controlled_start and i.has_germination_signal then 'required'
          when i.pure_direct_sow then 'not_applicable'
          when i.has_germination_signal then 'conditional'
          when i.method_lc in ('division','clump','bulb_or_transplant','transplant','start') then 'not_applicable'
          else 'unknown'
        end
      when 'pot_up' then
        case
          when i.has_pot_up_signal and i.controlled_start then 'required'
          when i.has_pot_up_signal then 'conditional'
          when i.pure_direct_sow then 'not_applicable'
          when i.controlled_start then 'unknown'
          when i.method_lc in ('division','clump','bulb_or_transplant','transplant','start') then 'not_applicable'
          else 'unknown'
        end
      when 'grow_out' then
        case
          when i.has_pot_up_signal and i.controlled_start then 'required'
          when i.has_pot_up_signal or i.has_transplant_signal then 'conditional'
          when i.pure_direct_sow then 'not_applicable'
          when i.controlled_start then 'unknown'
          else 'not_applicable'
        end
      when 'harden' then
        case
          when i.has_hardening_signal and i.controlled_start then 'required'
          when i.has_hardening_signal then 'conditional'
          when i.pure_direct_sow then 'not_applicable'
          when i.controlled_start or i.method_lc = 'transplant' then 'unknown'
          else 'not_applicable'
        end
      when 'destination' then 'required'
      when 'transplant' then
        case
          when i.controlled_start or i.method_lc = 'transplant' then 'required'
          when i.mixed_method then 'conditional'
          when i.pure_direct_sow then 'not_applicable'
          when i.has_transplant_signal then 'conditional'
          else 'unknown'
        end
      when 'establish' then 'required'
      when 'care_loop' then 'required'
      when 'pinch' then case when i.has_pinch_signal then 'required' else 'unknown' end
      when 'harvest_watch' then case when i.has_harvest_signal then 'required' else 'unknown' end
      when 'harvest_or_service' then case when i.has_harvest_signal then 'required' else 'unknown' end
      when 'decline' then case when i.has_decline_signal then 'required' else 'unknown' end
      when 'terminal_disposition' then case when i.has_clear_signal then 'required' else 'unknown' end
      when 'winter' then
        case
          when i.has_winter_signal then 'required'
          when i.frost_lc = 'killed_by_frost' then 'not_applicable'
          when i.life_cycle_lc like '%perennial%' or i.life_cycle_lc = 'biennial' then 'unknown'
          else 'not_applicable'
        end
      when 'spring_return' then
        case
          when i.has_winter_signal then 'required'
          when i.frost_lc = 'killed_by_frost' then 'not_applicable'
          when i.life_cycle_lc like '%perennial%' or i.life_cycle_lc = 'biennial' then 'unknown'
          else 'not_applicable'
        end
      when 'successor' then 'conditional'
      else 'unknown'
    end as inferred_disposition,
    case i.stage_key
      when 'germinate' then i.days_to_germination_min
      when 'pot_up' then nullif(i.profile_metadata ->> 'pot_up_days_min','')::integer
      when 'harden' then nullif(i.profile_metadata ->> 'hardening_start_days_min','')::integer
      when 'transplant' then nullif(i.profile_metadata ->> 'transplant_ready_days_min','')::integer
      when 'pinch' then nullif(i.profile_metadata ->> 'pinch_days_min','')::integer
      when 'harvest_watch' then i.days_to_harvest_watch_min
      else null
    end as inferred_timing_min_days,
    case i.stage_key
      when 'germinate' then i.days_to_germination_max
      when 'pot_up' then nullif(i.profile_metadata ->> 'pot_up_days_max','')::integer
      when 'harden' then nullif(i.profile_metadata ->> 'hardening_start_days_max','')::integer
      when 'transplant' then nullif(i.profile_metadata ->> 'transplant_ready_days_max','')::integer
      when 'pinch' then nullif(i.profile_metadata ->> 'pinch_days_max','')::integer
      when 'harvest_watch' then i.days_to_harvest_watch_max
      else null
    end as inferred_timing_max_days
  from inferred i
)
select
  c.crop_profile_id,
  c.crop_profile_stable_key,
  c.crop_label,
  c.variety,
  c.life_cycle,
  c.default_planting_method,
  c.stage_key,
  c.stage_order,
  c.stage_label,
  coalesce(c.explicit_disposition, c.inferred_disposition) as disposition,
  coalesce(c.explicit_timing_min_days, c.inferred_timing_min_days) as timing_min_days,
  coalesce(c.explicit_timing_max_days, c.inferred_timing_max_days) as timing_max_days,
  coalesce(c.explicit_trigger_spec, '{}'::jsonb) as trigger_spec,
  coalesce(c.explicit_rule_payload, '{}'::jsonb) as rule_payload,
  case
    when c.explicit_rule_id is not null then 'explicit_rule'
    when c.inferred_disposition = 'unknown' then 'unknown'
    when c.stage_key = 'pinch' and c.has_pinch_signal then 'profile_metadata'
    when c.stage_key in ('pot_up','harden','transplant','harvest_watch','harvest_or_service','decline','terminal_disposition','winter','spring_return')
      and (
        c.has_pot_up_signal or c.has_hardening_signal or c.has_transplant_signal or c.has_harvest_signal
        or c.has_decline_signal or c.has_clear_signal or c.has_winter_signal
      ) then 'profile_metadata'
    else 'profile_shape'
  end as contract_source,
  case when c.explicit_rule_id is not null then c.explicit_confidence else null end as confidence,
  case when c.explicit_rule_id is not null then c.explicit_source else null end as explicit_source,
  case when c.explicit_rule_id is not null then c.explicit_note else null end as note
from compiled c;

revoke all on atlas.v_crop_lifecycle_contract_v1 from anon, authenticated;
grant select on atlas.v_crop_lifecycle_contract_v1 to service_role;

create or replace function atlas.compile_crop_lifecycle_v1(p_crop_profile_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, atlas
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'stageKey', c.stage_key,
        'stageOrder', c.stage_order,
        'stageLabel', c.stage_label,
        'disposition', c.disposition,
        'timingMinDays', c.timing_min_days,
        'timingMaxDays', c.timing_max_days,
        'contractSource', c.contract_source,
        'triggerSpec', c.trigger_spec,
        'rulePayload', c.rule_payload
      ) order by c.stage_order
    ),
    '[]'::jsonb
  )
  from atlas.v_crop_lifecycle_contract_v1 c
  where c.crop_profile_id = p_crop_profile_id;
$$;

revoke all on function atlas.compile_crop_lifecycle_v1(uuid) from public, anon, authenticated;
grant execute on function atlas.compile_crop_lifecycle_v1(uuid) to service_role;

create or replace view atlas.v_crop_lifecycle_continuity_audit_v1
with (security_invoker = true)
as
with contract_summary as (
  select
    crop_profile_id,
    array_agg(stage_key order by stage_order) filter (where disposition = 'unknown') as unknown_stages,
    array_agg(stage_key order by stage_order) filter (where disposition = 'required') as required_stages,
    bool_or(stage_key = 'transplant' and disposition = 'required') as transplant_required,
    bool_or(stage_key = 'pinch' and disposition = 'unknown') as pinch_unknown,
    bool_or(stage_key in ('harvest_watch','harvest_or_service') and disposition = 'unknown') as harvest_unknown,
    bool_or(stage_key = 'terminal_disposition' and disposition = 'unknown') as terminal_unknown,
    bool_or(stage_key = 'winter' and disposition = 'unknown') as winter_unknown,
    bool_or(stage_key = 'spring_return' and disposition = 'unknown') as spring_return_unknown
  from atlas.v_crop_lifecycle_contract_v1
  group by crop_profile_id
), live_cycle_tasks as (
  select tc.crop_cycle_id,
    count(*) filter (where t.status not in ('done','cancelled'))::integer as live_task_count
  from atlas.task_crop_cycles tc
  join atlas.tasks t on t.id = tc.task_id
  group by tc.crop_cycle_id
), cycle_lot_links as (
  select crop_cycle_id, count(*)::integer as production_lot_count
  from atlas.production_lot_crop_cycles
  group by crop_cycle_id
), cycle_occurrences as (
  select cc.id as crop_cycle_id,
    count(pwo.id) filter (where pwo.state in ('planned','eligible','releasing','released'))::integer as live_occurrence_count
  from atlas.crop_cycles cc
  left join atlas.planned_work_occurrences pwo
    on pwo.id = case
      when (cc.metadata ->> 'next_action_occurrence_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        then (cc.metadata ->> 'next_action_occurrence_id')::uuid
      else null
    end
  group by cc.id
), seed_allocations as (
  select production_lot_id,
    count(*) filter (where allocation_status in ('reserved','allocated','consumed'))::integer as allocation_count,
    coalesce(sum(allocated_quantity) filter (where allocation_status in ('reserved','allocated','consumed')),0)::numeric as allocated_quantity
  from atlas.seed_lot_allocations
  group by production_lot_id
), lot_cycle_links as (
  select production_lot_id, count(*)::integer as crop_cycle_count
  from atlas.production_lot_crop_cycles
  group by production_lot_id
), lot_beds as (
  select production_lot_id,
    count(*) filter (where assignment_status not in ('cancelled','released'))::integer as bed_assignment_count
  from atlas.production_bed_assignments
  group by production_lot_id
), lot_harvest as (
  select pl.id as production_lot_id,
    (hr.id is not null) as has_harvest_rule,
    (hg.id is not null) as has_harvest_gate
  from atlas.production_lots pl
  left join atlas.production_harvest_rules hr on hr.production_lot_id = pl.id
  left join atlas.production_harvest_gates hg on hg.production_lot_id = pl.id
), lot_future_work as (
  select
    (item ->> 'production_lot_id')::uuid as production_lot_id,
    count(*) filter (where pwo.state in ('planned','eligible','releasing','released'))::integer as live_occurrence_count,
    count(*) filter (
      where pwo.state in ('planned','eligible','releasing','released')
        and (
          lower(coalesce(pwo.task_payload ->> 'action_key','')) in ('seed','sow')
          or lower(pwo.title) like '%sow%'
          or lower(pwo.title) like '%seed sowing%'
        )
    )::integer as sow_occurrence_count
  from atlas.planned_work_occurrences pwo
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(pwo.relation_payload -> 'production_lot_tasks') = 'array'
        then pwo.relation_payload -> 'production_lot_tasks'
      else '[]'::jsonb
    end
  ) item
  where (item ->> 'production_lot_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  group by (item ->> 'production_lot_id')::uuid
), cycle_rows as (
  select
    'crop_cycle'::text as subject_kind,
    cc.id as subject_id,
    cc.farm_id,
    cc.crop_profile_id,
    cp.stable_key as crop_profile_stable_key,
    cc.crop_label,
    cc.variety,
    cc.lifecycle_status,
    cc.cycle_state as current_stage,
    coalesce(cc.sown_date, cc.planted_date, cc.created_at::date) as anchor_date,
    coalesce(cs.unknown_stages, array[]::text[]) as unknown_contract_stages,
    coalesce(cs.required_stages, array[]::text[]) as required_contract_stages,
    coalesce(cl.production_lot_count,0) > 0 as has_production_lineage,
    null::boolean as has_input_custody,
    (coalesce(lct.live_task_count,0) > 0 or coalesce(co.live_occurrence_count,0) > 0) as has_next_work,
    (
      cc.metadata ? 'future_destination'
      or cc.metadata ? 'future_destination_object_id'
      or cc.metadata ? 'future_destination_program'
      or cc.metadata ? 'future_destination_program_object_ids'
      or cc.metadata ? 'batch_destination_plan'
      or (cc.planted_date is not null and go.object_type is distinct from 'seed_room')
    ) as has_destination_truth,
    (
      cc.expected_harvest_watch_start is not null
      or cc.expected_harvest_watch_end is not null
      or (cs.harvest_unknown is false)
    ) as has_harvest_plan,
    (
      cc.expected_clear_date is not null
      or cc.cleared_date is not null
      or cc.turnover_date is not null
      or (cs.terminal_unknown is false)
    ) as has_terminal_contract,
    cs.transplant_required,
    cs.pinch_unknown,
    cs.harvest_unknown,
    cs.terminal_unknown,
    cs.winter_unknown,
    cs.spring_return_unknown,
    array_remove(array[
      case when cc.crop_profile_id is null then 'missing_crop_profile' end,
      case when cc.crop_profile_id is not null and cs.pinch_unknown then 'pinch_rule_unknown' end,
      case when cc.crop_profile_id is not null and cs.harvest_unknown then 'harvest_or_service_unknown' end,
      case when cc.crop_profile_id is not null and cs.terminal_unknown then 'terminal_behavior_unknown' end,
      case when cc.crop_profile_id is not null and cs.winter_unknown then 'winter_behavior_unknown' end,
      case when cc.crop_profile_id is not null and cs.spring_return_unknown then 'spring_return_unknown' end,
      case when coalesce(cs.transplant_required,false)
        and not (
          cc.metadata ? 'future_destination'
          or cc.metadata ? 'future_destination_object_id'
          or cc.metadata ? 'future_destination_program'
          or cc.metadata ? 'future_destination_program_object_ids'
          or cc.metadata ? 'batch_destination_plan'
        )
        and go.object_type = 'seed_room'
        then 'transplant_destination_missing' end,
      case when cc.cycle_state in ('sown','germinated','seedling','seedling_care','transplant_ready','hardening_off')
        and coalesce(lct.live_task_count,0) = 0
        and coalesce(co.live_occurrence_count,0) = 0
        then 'next_operation_missing' end,
      case when go.object_type = 'seed_room' and coalesce(cl.production_lot_count,0) = 0
        then 'production_lineage_missing' end
    ], null)::text[] as gap_types
  from atlas.crop_cycles cc
  left join atlas.crop_profiles cp on cp.id = cc.crop_profile_id
  left join contract_summary cs on cs.crop_profile_id = cc.crop_profile_id
  left join atlas.growing_objects go on go.id = cc.object_id
  left join live_cycle_tasks lct on lct.crop_cycle_id = cc.id
  left join cycle_lot_links cl on cl.crop_cycle_id = cc.id
  left join cycle_occurrences co on co.crop_cycle_id = cc.id
  where cc.lifecycle_status = 'active'
), lot_rows as (
  select
    'production_lot'::text as subject_kind,
    pl.id as subject_id,
    pl.farm_id,
    pl.crop_profile_id,
    cp.stable_key as crop_profile_stable_key,
    cp.crop_label,
    cp.variety,
    pl.lifecycle_status,
    pl.current_stage,
    coalesce(pl.actual_sow_date, pl.planned_sow_date, pl.created_at::date) as anchor_date,
    coalesce(cs.unknown_stages, array[]::text[]) as unknown_contract_stages,
    coalesce(cs.required_stages, array[]::text[]) as required_contract_stages,
    true as has_production_lineage,
    case
      when lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
        or lower(coalesce(cp.default_planting_method,'')) like '%seed%'
        or lower(coalesce(cp.default_planting_method,'')) like '%sow%'
      then coalesce(sa.allocation_count,0) > 0
      else true
    end as has_input_custody,
    coalesce(lfw.live_occurrence_count,0) > 0 as has_next_work,
    coalesce(lb.bed_assignment_count,0) > 0 as has_destination_truth,
    (
      pl.expected_harvest_start is not null
      or pl.expected_harvest_end is not null
      or coalesce(lh.has_harvest_rule,false)
    ) as has_harvest_plan,
    (cs.terminal_unknown is false) as has_terminal_contract,
    cs.transplant_required,
    cs.pinch_unknown,
    cs.harvest_unknown,
    cs.terminal_unknown,
    cs.winter_unknown,
    cs.spring_return_unknown,
    array_remove(array[
      case when pl.crop_profile_id is null then 'missing_crop_profile' end,
      case when pl.crop_profile_id is not null and cs.pinch_unknown then 'pinch_rule_unknown' end,
      case when pl.crop_profile_id is not null and cs.harvest_unknown then 'harvest_or_service_unknown' end,
      case when pl.crop_profile_id is not null and cs.terminal_unknown then 'terminal_behavior_unknown' end,
      case when pl.crop_profile_id is not null and cs.winter_unknown then 'winter_behavior_unknown' end,
      case when pl.crop_profile_id is not null and cs.spring_return_unknown then 'spring_return_unknown' end,
      case when (
          lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
          or lower(coalesce(cp.default_planting_method,'')) like '%seed%'
          or lower(coalesce(cp.default_planting_method,'')) like '%sow%'
        ) and coalesce(sa.allocation_count,0) = 0
        then 'input_custody_missing' end,
      case when lower(coalesce(pl.planned_input_unit,'')) like '%seed%'
        and pl.planned_input_quantity is null
        then 'input_quantity_unknown' end,
      case when pl.planned_sow_date is not null and coalesce(lfw.sow_occurrence_count,0) = 0
        then 'sow_occurrence_missing' end,
      case when coalesce(lcl.crop_cycle_count,0) = 0 then 'crop_cycle_lineage_missing' end,
      case when coalesce(cs.transplant_required,false) and coalesce(lb.bed_assignment_count,0) = 0
        then 'destination_assignment_missing' end,
      case when pl.crop_profile_id is not null and not (
          pl.expected_harvest_start is not null
          or pl.expected_harvest_end is not null
          or coalesce(lh.has_harvest_rule,false)
        ) then 'harvest_plan_missing' end
    ], null)::text[] as gap_types
  from atlas.production_lots pl
  left join atlas.crop_profiles cp on cp.id = pl.crop_profile_id
  left join contract_summary cs on cs.crop_profile_id = pl.crop_profile_id
  left join seed_allocations sa on sa.production_lot_id = pl.id
  left join lot_cycle_links lcl on lcl.production_lot_id = pl.id
  left join lot_beds lb on lb.production_lot_id = pl.id
  left join lot_harvest lh on lh.production_lot_id = pl.id
  left join lot_future_work lfw on lfw.production_lot_id = pl.id
  where pl.lifecycle_status in ('planned','active')
)
select *,
  cardinality(gap_types) as gap_count,
  case
    when cardinality(gap_types) = 0 then 'pass'
    when 'missing_crop_profile' = any(gap_types) then 'identity_blocked'
    when 'next_operation_missing' = any(gap_types) or 'sow_occurrence_missing' = any(gap_types) then 'continuity_broken'
    when 'input_custody_missing' = any(gap_types) or 'transplant_destination_missing' = any(gap_types) or 'destination_assignment_missing' = any(gap_types) then 'execution_blocked'
    else 'contract_incomplete'
  end as audit_status
from cycle_rows
union all
select *,
  cardinality(gap_types) as gap_count,
  case
    when cardinality(gap_types) = 0 then 'pass'
    when 'missing_crop_profile' = any(gap_types) then 'identity_blocked'
    when 'next_operation_missing' = any(gap_types) or 'sow_occurrence_missing' = any(gap_types) then 'continuity_broken'
    when 'input_custody_missing' = any(gap_types) or 'transplant_destination_missing' = any(gap_types) or 'destination_assignment_missing' = any(gap_types) then 'execution_blocked'
    else 'contract_incomplete'
  end as audit_status
from lot_rows;

revoke all on atlas.v_crop_lifecycle_continuity_audit_v1 from anon, authenticated;
grant select on atlas.v_crop_lifecycle_continuity_audit_v1 to service_role;

-- Exact alias repair: these Aug. 8 living transplants are generic mixed zinnias.
insert into atlas.crop_profile_aliases (
  crop_profile_id,
  alias_label,
  alias_variety,
  priority,
  active,
  note
)
select
  cp.id,
  'Zinnia transplants · Aug 8',
  'zinnia',
  20,
  true,
  'Exact living-crop label repair from Elm continuity reconciliation 2026-08-28.'
from atlas.crop_profiles cp
where cp.stable_key = 'zinnia_cut_flower_generic'
  and not exists (
    select 1
    from atlas.crop_profile_aliases a
    where a.crop_profile_id = cp.id
      and lower(a.alias_label) = lower('Zinnia transplants · Aug 8')
      and lower(coalesce(a.alias_variety,'')) = lower('zinnia')
  );

-- Correct the crossed Rocket/Madame Butterfly payload while keeping the future
-- occurrence planned. Seed custody is still allowed to block release later.
update atlas.planned_work_occurrences
set task_payload = jsonb_set(
      task_payload,
      '{note}',
      to_jsonb('Start the Rocket spring succession in 3/4-inch soil blocks. Keep Rocket separate from the other snapdragon series and record the actual seed/block count at sowing.'::text),
      true
    ),
    metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'continuity_reconciled_at', now(),
      'continuity_reconciliation', 'corrected_cross_crop_instruction_identity',
      'continuity_reconciliation_source', 'owner_approved_property_plan_20260828'
    ),
    updated_at = now()
where farm_id = '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and occurrence_key = 'legacy-task:40e14d01-faa1-4843-a2a6-4e96ef1805a6'
  and state = 'planned';

-- Quarantine obsolete 2027 directions without deleting history. These six
-- occurrences predate and conflict with the current owner-approved property plan.
update atlas.planned_work_occurrences
set state = 'cancelled',
    metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'quarantined_at', now(),
      'quarantined_by', 'crop_lifecycle_reconciliation_20260828',
      'quarantine_reason', 'superseded_by_owner_approved_property_plan_20260828',
      'pre_quarantine_state', state
    ),
    updated_at = now()
where farm_id = '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'::uuid
  and id = any (array[
    '414e097f-01b2-4005-81c2-c60ba84e4754'::uuid,
    'de14da78-854c-4c2f-b0e7-2c2806772100'::uuid,
    'b8902867-f771-46d2-932c-31311ba119ee'::uuid,
    '26e59efa-26c3-43d9-b9c8-32c6563c525e'::uuid,
    '10bd235c-39ea-418e-b719-e709901f064e'::uuid,
    'adb7e325-293c-4415-bff0-cc2ab8431d60'::uuid
  ])
  and state in ('planned','eligible');