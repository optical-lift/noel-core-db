-- Atlas source candidate only; no production execution.
-- Five-zone Household care is an attention opportunity, not a 168-hour time reservation.
-- All other already-admitted capacity blocks and timed Household events are unchanged.
begin;

create or replace view atlas.principal_capacity_blocks_v1
with (security_invoker=true)
as
select
  b.principal_id,
  'principal_capacity_block'::text as source_type,
  b.id as source_id,
  b.title,
  b.starts_at,
  b.ends_at,
  b.block_kind,
  b.floor_class,
  b.protection_level,
  b.interruptibility,
  b.reason_for_floor,
  b.consequence,
  b.metadata
from atlas.principal_capacity_blocks b
where b.blocks_capacity

union all
select
  h.principal_id,
  'household_event'::text as source_type,
  e.id as source_id,
  e.title,
  e.starts_at,
  e.ends_at,
  e.event_kind as block_kind,
  e.floor_class,
  e.protection_level,
  e.interruptibility,
  e.reason_for_floor,
  e.consequence,
  e.metadata
from atlas.household_events e
join atlas.households h on h.id=e.household_id
where e.blocks_capacity

union all
select
  h.principal_id,
  'household_rhythm'::text as source_type,
  r.id as source_id,
  r.title,
  r.next_window_start as starts_at,
  r.next_window_end as ends_at,
  'household_rhythm'::text as block_kind,
  r.floor_class,
  r.protection_level,
  r.interruptibility,
  r.reason_for_floor,
  r.consequence,
  r.metadata
from atlas.household_rhythms r
join atlas.households h on h.id=r.household_id
where r.active and r.blocks_capacity
  and r.next_window_start is not null and r.next_window_end is not null
  -- Bootstrap five-zone attention occupies a *week in which fifteen minutes
  -- are due*, not each instant of that whole week. It has not generated an
  -- execution interval and must not consume all of Principal Capacity.
  -- The rhythm/Clock source row remains intact and must still be addressed.
  and not (
    r.metadata @> '{"policyKey":"atlas_household_five_zone_attention","releaseKind":"protected_attention","executionGenerated":false}'::jsonb
  );

commit;
