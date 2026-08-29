do $migration$
declare
  v_def text;
  v_old text := $old$    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_2,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)),
      (v_farm.id,v_lot_id,v_requirement_id,v_bed_3,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true))
    returning id into v_assignment_2;
    select id into v_assignment_3 from atlas.production_bed_assignments
      where production_lot_id=v_lot_id and object_id=v_bed_3 and id<>v_assignment_2 order by created_at desc limit 1;
    if v_assignment_2 is null or v_assignment_3 is null then
      select id into v_assignment_2 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_2 order by created_at desc limit 1;
      select id into v_assignment_3 from atlas.production_bed_assignments where production_lot_id=v_lot_id and object_id=v_bed_3 order by created_at desc limit 1;
    end if;
$old$;
  v_new text := $new$    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,v_requirement_id,v_bed_2,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_assignment_2;
    insert into atlas.production_bed_assignments(
      farm_id,production_lot_id,requirement_id,object_id,quantity_assigned,unit,planned_transplant_date,assignment_status,source,metadata
    ) values(
      v_farm.id,v_lot_id,v_requirement_id,v_bed_3,20,'bed_ft',v_transplant_date,'assigned','reference_company_runner',
      jsonb_build_object('system_fixture',true,'reference_run_id',v_run_id,'synthetic_truth',true)
    ) returning id into v_assignment_3;
$new$;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='atlas' and p.proname='run_reference_company_transplant_dependency_block_v1';

  if v_def is null or position(v_old in v_def)=0 then
    raise exception 'Expected transplant dependency runner v1 bed-assignment source block was not found.' using errcode='23514';
  end if;

  execute replace(v_def,v_old,v_new);
end;
$migration$;

update atlas.reference_company_scenarios
set metadata=metadata||jsonb_build_object('runner_version',2,'runner_repair','separate_bed_assignment_returning_ids'),updated_at=now()
where stable_key='transplant_dependency_block_v1';