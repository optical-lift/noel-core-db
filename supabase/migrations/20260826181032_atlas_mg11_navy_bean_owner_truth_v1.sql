-- Elm Farm MG11 navy-bean owner truth v1
-- Canonicalize the witnessed sowing anchor and current condition without turning
-- an expected biological clear date into an automatic management instruction.
do $$
declare
  v_farm uuid;
  v_object uuid;
  v_profile uuid;
  v_content uuid;
  v_cycle uuid;
  v_field_anchor date;
  v_anchor date;
  v_germ_min integer;
  v_germ_max integer;
  v_harvest_min integer;
  v_harvest_max integer;
  v_clear_offset integer;
begin
  select id into strict v_farm from atlas.farms where stable_key='elm_farm';
  select id into strict v_object from atlas.growing_objects where farm_id=v_farm and stable_key='mg11';
  select id,days_to_germination_min,days_to_germination_max,days_to_harvest_watch_min,days_to_harvest_watch_max,clear_offset_days
    into strict v_profile,v_germ_min,v_germ_max,v_harvest_min,v_harvest_max,v_clear_offset
  from atlas.crop_profiles where stable_key='bush_bean';

  select min(coalesce(cc.sown_date,cc.planted_date)) into v_field_anchor
  from atlas.crop_cycles cc
  join atlas.growing_objects go on go.id=cc.object_id
  where cc.farm_id=v_farm
    and cc.crop_profile_id=v_profile
    and go.label like 'Field Row %'
    and cc.lifecycle_status='active'
    and coalesce(cc.sown_date,cc.planted_date) is not null;

  if v_field_anchor is distinct from date '2026-06-07' then
    raise exception 'Unexpected canonical Field Row navy-bean anchor: %',v_field_anchor;
  end if;
  v_anchor:=v_field_anchor+14;

  select oc.id into strict v_content
  from atlas.object_contents oc
  where oc.farm_id=v_farm and oc.object_id=v_object and lower(oc.content_label)='beans';

  select cc.id into strict v_cycle
  from atlas.crop_cycles cc
  where cc.farm_id=v_farm and cc.object_id=v_object and cc.object_content_id=v_content and cc.lifecycle_status='active';

  update atlas.object_contents
  set crop_profile_id=v_profile,
      start_method='direct_sow',
      planted_date=v_anchor,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'owner_truth_recorded_at','2026-08-26',
        'sowing_anchor_basis','owner_confirmed_two_weeks_after_field_rows',
        'management_purpose','soil_fixing',
        'production_expected',false,
        'deer_browsed_nonproductive',true
      ),
      updated_at=now()
  where id=v_content;

  update atlas.crop_cycles
  set crop_label='Navy beans',
      variety=coalesce(variety,'navy bean'),
      crop_profile_id=v_profile,
      sown_date=v_anchor,
      planted_date=v_anchor,
      expected_germination_start=case when v_germ_min is null then null else v_anchor+v_germ_min end,
      expected_germination_end=case when v_germ_max is null then null else v_anchor+v_germ_max end,
      expected_harvest_watch_start=case when v_harvest_min is null then null else v_anchor+v_harvest_min end,
      expected_harvest_watch_end=case when v_harvest_max is null then null else v_anchor+v_harvest_max end,
      expected_clear_date=case when v_clear_offset is null then null else v_anchor+v_clear_offset end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'owner_truth_recorded_at','2026-08-26',
        'sowing_anchor_basis','owner_confirmed_two_weeks_after_field_rows',
        'management_purpose','soil_fixing',
        'production_expected',false,
        'current_condition','deer_browsed_nonproductive',
        'retention_policy','retain_while_alive_for_soil_fixing',
        'expected_clear_is_not_auto_clear',true
      ),
      updated_at=now()
  where id=v_cycle;

  insert into atlas.crop_observations(
    id,farm_id,object_id,crop_cycle_id,object_content_id,observed_date,stage,condition,
    confidence,source_kind,source_id,note,idempotency_key,metadata,created_at,updated_at
  ) values (
    gen_random_uuid(),v_farm,v_object,v_cycle,v_content,date '2026-08-26','vegetative','deer_browsed_nonproductive',
    'owner_confirmed','owner_report','owner_report_20260826_mg11_navy_beans',
    'Owner reports MG11 navy beans were direct-sown two weeks after the Field Row navy beans. Deer browsing has prevented production; the plants remain alive and are being retained for soil fixing.',
    'owner_report_20260826_mg11_navy_beans',
    jsonb_build_object(
      'managementPurpose','soil_fixing',
      'productionExpected',false,
      'retainWhileAlive',true,
      'biologicalExpectationDoesNotImplyClearance',true
    ),
    now(),now()
  )
  on conflict(farm_id,idempotency_key) do update set
    observed_date=excluded.observed_date,
    stage=excluded.stage,
    condition=excluded.condition,
    confidence=excluded.confidence,
    source_kind=excluded.source_kind,
    source_id=excluded.source_id,
    note=excluded.note,
    metadata=excluded.metadata,
    updated_at=now();
end $$;