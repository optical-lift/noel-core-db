create or replace function atlas.normalize_selected_crop_turnover_card_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_collection text;
  v_crop text;
  v_destination text;
begin
  if coalesce(new.metadata->>'weed_management_mode','') <> 'clear_selected_crop' then
    return new;
  end if;

  v_collection := coalesce(
    nullif(new.metadata->>'turnover_collection_label',''),
    nullif(new.metadata->>'display_location',''),
    nullif(new.metadata->>'display_detail',''),
    'Bed turnover'
  );
  v_crop := coalesce(
    nullif(new.metadata->>'selected_crop_label',''),
    nullif(new.metadata->>'display_subject',''),
    'selected crop'
  );
  v_destination := coalesce(nullif(new.metadata->>'biomass_destination',''),'compost');

  new.task_type := 'crop_clear';
  new.action_key := 'weed';
  new.operation_class := 'remove_uproot';
  new.operation_class_source := 'manual';
  new.title := coalesce(
    nullif(new.metadata->>'turnover_task_title',''),
    'Clear '||v_crop||' — '||v_collection
  );

  new.metadata := (
    coalesce(new.metadata,'{}'::jsonb)
      - 'persistent_weed_card'
      - 'weed_card_managed'
      - 'canonical_weed_title'
      - 'serial_weeding_queue_key'
      - 'serial_weeding_retracted'
      - 'serial_weeding_retracted_at'
      - 'release_queue_key'
      - 'release_queue_position'
      - 'release_queue_policy'
      - 'weed_serial_gate'
      - 'archived_reason'
  ) || jsonb_build_object(
    'canonical_card_family','weed',
    'weed_management_mode','clear_selected_crop',
    'work_route','crop_cycle',
    'display_action','Clear + '||v_destination,
    'display_subject',v_crop,
    'display_location',v_collection,
    'turnover_collection_label',v_collection,
    'selected_crop_label',v_crop,
    'biomass_destination',v_destination,
    'whole_bed_turnover',false,
    'object_vacancy_not_inferred',true,
    'other_crop_bodies_preserved',true,
    'operation_class','remove_uproot',
    'operation_class_manual','remove_uproot',
    'operation_class_source','manual'
  );

  return new;
end;
$function$;

update atlas.tasks t
set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
      'display_subject',coalesce(nullif(t.metadata->>'selected_crop_label',''),'Selected crop')
    ),
    updated_at=now()
where t.metadata->>'weed_management_mode'='clear_selected_crop';
