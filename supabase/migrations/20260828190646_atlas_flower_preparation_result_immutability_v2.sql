do $do$
declare
  v_definition text;
  v_old text := '  update atlas.flower_preparation_directive_results set metadata=metadata||jsonb_build_object(''readyInventoryLotsCreated'',v_ready_count,''preparationBatchId'',v_batch.id) where id=v_result.id;' || chr(10);
begin
  select pg_get_functiondef('atlas.record_flower_preparation_directive_result_for_member_v2(uuid,jsonb,jsonb,jsonb,text)'::regprocedure) into v_definition;
  if position(v_old in v_definition)=0 then raise exception 'Expected directed flower final-tally metadata update was not found.'; end if;
  v_definition := replace(v_definition,v_old,'');
  execute v_definition;
end;
$do$;