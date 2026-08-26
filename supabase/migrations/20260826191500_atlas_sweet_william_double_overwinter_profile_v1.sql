-- Atlas Double Sweet William overwinter crop profile v1
--
-- Creates a season-specific, source-bounded profile for the Elm Farm 2026
-- Double Sweet William cohort and attaches the two canonical July 11 seed-start
-- crop cycles that feed the current consolidated Sweet William pot-up task.
--
-- Timing basis:
--   * Dianthus barbatus germination: 7-14 days.
--   * Traditional biennial Double Sweet William flowers the year after summer sowing.
--   * Missouri outdoor bloom expectation: May-June.
--   * This 2026 cohort was sown 2026-07-11, so its harvest-watch window is
--     modeled as 2027-05-01 through 2027-06-30 (294-354 days from sowing).
--
-- This is a harvest WATCH window, not a promise that stems are physically ready.
-- Physical harvest readiness remains observation-governed by Atlas harvest logic.

insert into atlas.crop_profiles (
  stable_key,
  crop_label,
  variety,
  crop_family,
  life_cycle,
  default_planting_method,
  days_to_germination_min,
  days_to_germination_max,
  days_to_harvest_watch_min,
  days_to_harvest_watch_max,
  rows_per_3ft_bed,
  in_row_spacing_in,
  harvest_pattern,
  frost_behavior,
  plants_per_sqft,
  metadata
)
values (
  'sweet_william_double_overwinter_2026',
  'Sweet William',
  'Double Sweet William',
  'Caryophyllaceae',
  'biennial',
  'grow_room_seed_start',
  7,
  14,
  294,
  354,
  6,
  6,
  'seasonal_single_flush',
  'winter_dormant',
  4,
  jsonb_build_object(
    'botanical_name', 'Dianthus barbatus',
    'profile_scope', 'Elm Farm 2026 overwintered Double Sweet William cohort',
    'production_role', 'spring cut flower',
    'sowing_season', 'July 2026',
    'workflow_kind', 'transplant_start',
    'harvest_year_offset', 1,
    'harvest_start_month_day', '05-01',
    'harvest_end_month_day', '06-30',
    'harvest_cut_stage', '10-20% of flowers in cluster or spray open',
    'timing_confidence', 'medium',
    'projection_basis', 'Missouri May-June Sweet William bloom season plus owner-confirmed 2026 fall-overwinter production plan',
    'source_basis', jsonb_build_array(
      jsonb_build_object(
        'source', 'Missouri Extension',
        'claim', 'Dianthus barbatus is a biennial with May-June bloom in Missouri and can be planted in late summer/fall for flowering the following season',
        'url', 'https://extension.missouri.edu/publications/g6629'
      ),
      jsonb_build_object(
        'source', 'Johnny''s Selected Seeds',
        'claim', 'Dianthus germinates in 7-14 days, is spaced at 6 inches, and is harvested with 10-20% of flowers in the cluster or spray open',
        'url', 'https://www.johnnyseeds.com/growers-library/flowers/dianthus-sweet-william/dianthus-sweet-william-key-growing-information.html'
      ),
      jsonb_build_object(
        'source', 'Double Sweet William reference',
        'claim', 'Dianthus barbatus Double Mix is a biennial double-flowered cut flower that blooms the following year after summer sowing',
        'url', 'https://trueleafmarket.com/products/sweet-william-double-mixture-flower-seeds'
      )
    )
  )
)
on conflict (stable_key) do update
set crop_label = excluded.crop_label,
    variety = excluded.variety,
    crop_family = excluded.crop_family,
    life_cycle = excluded.life_cycle,
    default_planting_method = excluded.default_planting_method,
    days_to_germination_min = excluded.days_to_germination_min,
    days_to_germination_max = excluded.days_to_germination_max,
    days_to_harvest_watch_min = excluded.days_to_harvest_watch_min,
    days_to_harvest_watch_max = excluded.days_to_harvest_watch_max,
    rows_per_3ft_bed = excluded.rows_per_3ft_bed,
    in_row_spacing_in = excluded.in_row_spacing_in,
    harvest_pattern = excluded.harvest_pattern,
    frost_behavior = excluded.frost_behavior,
    plants_per_sqft = excluded.plants_per_sqft,
    metadata = coalesce(atlas.crop_profiles.metadata, '{}'::jsonb) || excluded.metadata,
    updated_at = now();

-- Resolver aliases are deliberately specific to Double Sweet William. Do not add a
-- generic Sweet William fallback that could silently capture a future F1/non-biennial type.
insert into atlas.crop_profile_aliases (crop_profile_id, alias_label, alias_variety, priority, active, note)
select p.id, a.alias_label, a.alias_variety, 10, true, 'Owner-confirmed Double Sweet William identity'
from atlas.crop_profiles p
cross join (values
  ('Double Sweet William'::text, null::text),
  ('Sweet William Double Mix'::text, null::text),
  ('Sweet William'::text, 'Double Sweet William'::text),
  ('Sweet William'::text, 'Double Mix'::text)
) as a(alias_label, alias_variety)
where p.stable_key = 'sweet_william_double_overwinter_2026'
  and not exists (
    select 1
    from atlas.crop_profile_aliases existing
    where existing.crop_profile_id = p.id
      and atlas.identity_token(existing.alias_label) = atlas.identity_token(a.alias_label)
      and atlas.identity_token(coalesce(existing.alias_variety, '')) = atlas.identity_token(coalesce(a.alias_variety, ''))
  );

-- The current pot-up task is already canonically linked to BOTH July 11 Sweet William
-- source cycles. Their old variety values (Box 1 / Box 2) were container labels, not
-- botanical variety identity, so preserve those labels in metadata and normalize variety.
update atlas.crop_cycles cc
set crop_profile_id = p.id,
    variety = 'Double Sweet William',
    metadata = coalesce(cc.metadata, '{}'::jsonb) || jsonb_build_object(
      'source_container_label', cc.variety,
      'canonical_variety', 'Double Sweet William',
      'variety_identity_source', 'owner_instruction_20260826',
      'crop_profile_link_source', 'owner_instruction_20260826'
    ),
    updated_at = now()
from atlas.crop_profiles p
where p.stable_key = 'sweet_william_double_overwinter_2026'
  and cc.crop_cycle_key in (
    'grow_room_sweet_william_box_1_20260711',
    'grow_room_sweet_william_box_2_20260711'
  );
