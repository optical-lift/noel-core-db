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

  -- Card family is presentation grammar, not operation identity. This remains a
  -- crop-clear operation even though the Weed family renders it.
  new.task_type := 'crop_clear';
  -- Transitional router compatibility: farm-atlas currently recognizes the Weed
  -- family through action_key. The operation class and task_type remain clear.
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

drop trigger if exists zzzzzzzzzz_normalize_selected_crop_turnover_card_v1 on atlas.tasks;
create trigger zzzzzzzzzz_normalize_selected_crop_turnover_card_v1
before insert or update on atlas.tasks
for each row execute function atlas.normalize_selected_crop_turnover_card_v1();

-- Repair the owner-confirmed Muncher cucumber turnover that was incorrectly
-- absorbed into Anna's serial Weed queue. Resolve the target by durable owner
-- and crop-profile metadata rather than generated identifiers.
with target as (
  select t.id,t.planned_occurrence_id,t.due_date
  from atlas.tasks t
  join atlas.farms f on f.id=t.farm_id
  where f.stable_key='elm_farm'
    and t.metadata->>'owner_instruction_source'='owner_report_with_photo_20260826'
    and t.metadata->>'crop_profile_stable_key'='muncher_cucumber'
    and t.metadata->>'source_management_disposition'='clear_and_compost'
  order by t.created_at desc
  limit 1
)
delete from atlas.task_release_queue_items qi
using target t
where qi.task_id=t.id
   or (t.planned_occurrence_id is not null and qi.planned_occurrence_id=t.planned_occurrence_id);

with target as (
  select t.id,t.planned_occurrence_id,t.due_date
  from atlas.tasks t
  join atlas.farms f on f.id=t.farm_id
  where f.stable_key='elm_farm'
    and t.metadata->>'owner_instruction_source'='owner_report_with_photo_20260826'
    and t.metadata->>'crop_profile_stable_key'='muncher_cucumber'
    and t.metadata->>'source_management_disposition'='clear_and_compost'
  order by t.created_at desc
  limit 1
)
update atlas.planned_work_occurrences pwo
set state='released',
    planned_due_date=coalesce(pwo.planned_due_date,t.due_date),
    released_at=coalesce(pwo.released_at,now()),
    released_task_id=t.id,
    commitment_kind='floating',
    metadata=(
      coalesce(pwo.metadata,'{}'::jsonb)
        - 'terminal_at'
        - 'terminal_task_id'
        - 'terminal_task_status'
        - 'serialWeedingQueued'
        - 'serialWeedingQueueKey'
        - 'serialWeedingQueuedAt'
        - 'calendar_commitment_kind'
        - 'queue_original_planned_due_date'
    ) || jsonb_build_object(
      'selectedCropTurnover',true,
      'canonicalCardFamily','weed'
    ),
    task_payload=jsonb_set(
      coalesce(pwo.task_payload,'{}'::jsonb),
      '{metadata}',
      (
        coalesce(pwo.task_payload->'metadata','{}'::jsonb)
          - 'serial_queue_state'
          - 'persistent_weed_card'
          - 'weed_card_managed'
      ) || jsonb_build_object(
        'canonical_card_family','weed',
        'weed_management_mode','clear_selected_crop',
        'turnover_task_title','Clear finished Muncher cucumber — Curve Garden Arches 1 + 2',
        'turnover_collection_label','Curve Garden Arches 1 + 2',
        'selected_crop_label','Muncher Cucumber',
        'display_action','Clear + compost',
        'display_subject','Muncher cucumber vines',
        'display_location','Curve Garden Arches 1 + 2',
        'work_route','crop_cycle',
        'whole_bed_turnover',false,
        'object_vacancy_not_inferred',true,
        'other_crop_bodies_preserved',true
      ),
      true
    ),
    updated_at=now()
from target t
where pwo.id=t.planned_occurrence_id;

with target as (
  select t.id
  from atlas.tasks t
  join atlas.farms f on f.id=t.farm_id
  where f.stable_key='elm_farm'
    and t.metadata->>'owner_instruction_source'='owner_report_with_photo_20260826'
    and t.metadata->>'crop_profile_stable_key'='muncher_cucumber'
    and t.metadata->>'source_management_disposition'='clear_and_compost'
  order by t.created_at desc
  limit 1
)
update atlas.tasks t
set status='open',
    completed_at=null,
    title='Clear finished Muncher cucumber — Curve Garden Arches 1 + 2',
    task_type='crop_clear',
    action_key='weed',
    operation_class='remove_uproot',
    operation_class_source='manual',
    released_at=coalesce(t.released_at,now()),
    metadata=(
      coalesce(t.metadata,'{}'::jsonb)
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
      'turnover_task_title','Clear finished Muncher cucumber — Curve Garden Arches 1 + 2',
      'turnover_collection_label','Curve Garden Arches 1 + 2',
      'selected_crop_label','Muncher Cucumber',
      'display_action','Clear + compost',
      'display_subject','Muncher cucumber vines',
      'display_location','Curve Garden Arches 1 + 2',
      'work_route','crop_cycle',
      'whole_bed_turnover',false,
      'object_vacancy_not_inferred',true,
      'other_crop_bodies_preserved',true
    ),
    updated_at=now()
from target x
where t.id=x.id;