do $do$
declare
  v_def text;
  v_marker text := E'  elsif v_lot.current_stage=''seedling_care'' and v_batch.id is not null then\n';
  v_insert text := E'  elsif v_lot.current_stage=''seedling_failure_decision'' and v_batch.id is not null then\n    v_due:=coalesce(v_event.event_date,v_today);\n    v_next:=atlas.author_production_work_occurrence_v1(\n      v_lot.farm_id,''owner-seedling-recovery'',''production:owner-seedling-recovery:''||v_batch.id::text,\n      ''Owner — Decide recovery for ''||v_lot.lot_label,v_due,v_due,\n      ''production_tray_batch'',v_batch.id,''owner_decision'',''decide'',''owner_decision'',''high'',''owner'',null,null,v_org,\n      ''This counted seedling cohort has zero surviving seedlings. Decide whether to reseed, replace, buy plugs, or cancel this production lot.'',\n      jsonb_build_object(''task_key'',''production_seedling_recovery_''||v_batch.id::text,''owner_task'',true,''anna_task'',false,''production_lot_id'',v_lot.id,''production_lot_key'',v_lot.stable_key,''production_tray_batch_id'',v_batch.id,''crop_cycle_id'',v_batch.crop_cycle_id,''surviving_seedlings'',0,''display_action'',''Decide'',''display_subject'',v_lot.lot_label||'' recovery'',''display_detail'',''0 surviving seedlings'',''collection_zone'',''Owner'',''assigned_to'',''Owner'',''next_action_authority'',''production_reconciler''),\n      jsonb_build_object(''task_objects'',jsonb_build_array(),''task_crop_cycles'',jsonb_build_array(jsonb_build_object(''crop_cycle_id'',v_batch.crop_cycle_id,''role'',''observes'',''confidence'',''confirmed'',''source'',''production_reconciler'',''metadata'',jsonb_build_object(''tray_batch_id'',v_batch.id))),''production_lot_tasks'',jsonb_build_array(jsonb_build_object(''production_lot_id'',v_lot.id,''link_role'',''seedling_failure_decision'',''source'',''production_reconciler'',''metadata'',jsonb_build_object(''tray_batch_id'',v_batch.id))),''task_resource_requirements'',jsonb_build_array(),''production_harvest_lot_tasks'',jsonb_build_array()),\n      ''required'',''dependency'',null,jsonb_build_object(''kind'',''crop_loss'',''effect'',''Production recovery decision remains unresolved.''),true\n    );\n    v_work:=v_work||jsonb_build_array(jsonb_build_object(''workKey'',''owner-seedling-recovery'',''occurrenceId'',v_next->>''occurrenceId''));\n    v_next_action:=''owner_seedling_recovery'';\n';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='reconcile_production_propagation_work_v1';
  if v_def is null then raise exception 'Target reconciler not found'; end if;
  if position(E'elsif v_lot.current_stage=''seedling_failure_decision'' and v_batch.id is not null then' in v_def)>0 then
    return;
  end if;
  if position(v_marker in v_def)=0 then raise exception 'Expected seedling-care marker not found'; end if;
  execute replace(v_def,v_marker,v_insert||v_marker);
end
$do$;