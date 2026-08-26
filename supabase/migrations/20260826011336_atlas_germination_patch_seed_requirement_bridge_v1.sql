create or replace function atlas.normalize_germination_next_stage_task()
returns trigger
language plpgsql
security definer
set search_path = atlas, public
as $function$
declare
  profile atlas.crop_profiles%rowtype;
  source_task atlas.tasks%rowtype;
  anchor_date date;
  window_min integer;
  window_max integer;
  workflow_kind text;
  crop_name text;
  crop_display_name text;
  canonical_crop_cycle_id uuid;
  canonical_crop_label text;
  canonical_variety text;
  patch_profile_id uuid;
  patch_object_id uuid;
  patch_seed_lot_id uuid;
  patch_seed_lot_count integer := 0;
  patch_seed_binding_state text;
begin
  if new.generated_from = 'germination_patch' then
    patch_profile_id := atlas.rhythm_safe_uuid_v1(new.metadata->>'crop_profile_id');

    select tro.object_id
    into patch_object_id
    from atlas.task_objects tro
    where tro.task_id = new.generated_from_id
    order by case when tro.role in ('primary_location','target') then 0 else 1 end, tro.created_at, tro.object_id
    limit 1;

    if patch_profile_id is not null then
      select count(*)::integer, min(sl.id)
      into patch_seed_lot_count, patch_seed_lot_id
      from atlas.seed_lots sl
      where sl.farm_id = new.farm_id
        and sl.crop_profile_id = patch_profile_id
        and sl.status not in ('retired','depleted');

      if patch_seed_lot_count = 0 then
        select count(*)::integer, min(sl.id)
        into patch_seed_lot_count, patch_seed_lot_id
        from atlas.seed_lots sl
        where sl.farm_id = new.farm_id
          and sl.crop_profile_id = patch_profile_id
          and sl.status <> 'retired';
      end if;
    end if;

    patch_seed_binding_state := case
      when patch_profile_id is null then 'seed_profile_missing'
      when patch_seed_lot_count = 0 then 'seed_source_unbound'
      when patch_seed_lot_count = 1 then 'seed_source_bound'
      else 'seed_source_ambiguous'
    end;

    new.metadata := coalesce(new.metadata,'{}'::jsonb)
      || jsonb_strip_nulls(jsonb_build_object(
        'seed_governance_required', true,
        'seed_inventory_report_required', true,
        'seed_requirement_source', 'germination_patch_seed_requirement_bridge_v1',
        'seed_source_binding_state', patch_seed_binding_state,
        'seed_lot_id', case when patch_seed_lot_count = 1 then patch_seed_lot_id else null end,
        'target_object_id', patch_object_id
      ));

    return new;
  end if;

  if new.generated_from is distinct from 'germination_harvest_watch' then
    return new;
  end if;

  select * into source_task from atlas.tasks where id = new.generated_from_id;
  select * into profile
  from atlas.crop_profiles
  where id = nullif(new.metadata->>'crop_profile_id','')::uuid;

  select
    cc.id,
    coalesce(nullif(cc.crop_label,''), nullif(oc.content_label,'')),
    coalesce(nullif(cc.variety,''), nullif(oc.variety,''))
  into canonical_crop_cycle_id, canonical_crop_label, canonical_variety
  from atlas.task_crop_cycles tcc
  join atlas.crop_cycles cc on cc.id = tcc.crop_cycle_id
  left join atlas.object_contents oc on oc.id = cc.object_content_id
  where tcc.task_id = source_task.id
  order by
    case tcc.role when 'creates' then 0 when 'affects' then 1 when 'observes' then 2 else 3 end,
    case tcc.confidence when 'confirmed' then 0 else 1 end,
    tcc.created_at
  limit 1;

  anchor_date := coalesce(
    nullif(source_task.metadata->>'actual_sow_date','')::date,
    nullif(source_task.metadata->>'source_sown_date','')::date,
    nullif(new.metadata->>'source_sown_date','')::date,
    source_task.due_date,
    current_date
  );

  workflow_kind := coalesce(profile.metadata->>'workflow_kind','');
  crop_name := coalesce(
    canonical_variety,
    nullif(source_task.metadata->>'crop_variety',''),
    nullif(source_task.metadata->>'variety',''),
    nullif(new.metadata->>'variety',''),
    nullif(profile.variety,''),
    canonical_crop_label,
    profile.crop_label,
    'Crop'
  );

  if lower(crop_name) like '%' || lower(coalesce(canonical_crop_label, profile.crop_label, '')) || '%' then
    crop_display_name := crop_name;
  elsif coalesce(canonical_crop_label, profile.crop_label, '') <> '' then
    crop_display_name := crop_name || ' ' || lower(coalesce(canonical_crop_label, profile.crop_label));
  else
    crop_display_name := crop_name;
  end if;

  new.metadata := coalesce(new.metadata,'{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object(
      'crop_cycle_id', canonical_crop_cycle_id,
      'crop', coalesce(canonical_crop_label, profile.crop_label),
      'variety', canonical_variety,
      'crop_variety', canonical_variety
    ));

  if workflow_kind = 'transplant_start' then
    window_min := coalesce(nullif(profile.metadata->>'transplant_ready_days_min','')::integer, 25);
    window_max := coalesce(nullif(profile.metadata->>'transplant_ready_days_max','')::integer, window_min + 10);

    new.task_type := 'transplant_readiness';
    new.title := 'Open transplant readiness window — ' || crop_display_name || ' — ' || coalesce(new.metadata->>'display_detail','Elm Farm');
    new.due_date := anchor_date + window_min;
    new.metadata := jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(coalesce(new.metadata,'{}'::jsonb), '{task_style}', '"transplant_readiness"'::jsonb, true),
            '{display_subject}', to_jsonb(crop_display_name || ' transplant readiness'), true),
          '{source_sown_date}', to_jsonb(anchor_date::text), true),
        '{window_start}', to_jsonb((anchor_date + window_min)::text), true),
      '{window_end}', to_jsonb((anchor_date + window_max)::text), true
    );
  elsif profile.days_to_harvest_watch_min is not null then
    window_min := profile.days_to_harvest_watch_min;
    window_max := coalesce(profile.days_to_harvest_watch_max, window_min);

    new.task_type := 'harvest_window';
    new.title := 'Open harvest window — ' || crop_display_name || ' — ' || coalesce(new.metadata->>'display_detail','Elm Farm');
    new.due_date := anchor_date + window_min;
    new.metadata := jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(coalesce(new.metadata,'{}'::jsonb), '{task_style}', '"harvest_window"'::jsonb, true),
            '{display_subject}', to_jsonb(crop_display_name || ' harvest window'), true),
          '{source_sown_date}', to_jsonb(anchor_date::text), true),
        '{window_start}', to_jsonb((anchor_date + window_min)::text), true),
      '{window_end}', to_jsonb((anchor_date + window_max)::text), true
    );
  else
    new.status := 'archived';
    new.due_date := null;
    new.metadata := jsonb_set(coalesce(new.metadata,'{}'::jsonb), '{archived_reason}', '"No valid next-stage window exists on crop profile"'::jsonb, true);
  end if;

  return new;
end;
$function$;

comment on function atlas.normalize_germination_next_stage_task() is
  'Normalizes germination-generated next-stage tasks. Germination patch consequences now enter the canonical seed-governance/readiness path and bind a unique profile-matched seed lot when one canonical source exists; missing, ambiguous, depleted, or insufficient inventory remains non-executable through the existing Requirement Evaluation providers.';