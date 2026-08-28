begin;

do $do$
declare
  v_definition text;
  v_anchor text := '  if p_transition=''done'' then' || chr(10);
  v_insert text :=
    '  if p_transition=''done''' || chr(10) ||
    '     and coalesce(p_payload->>''structuredResultKind'','''')=''flower_preparation_directive_final_tally_v1'' then' || chr(10) ||
    '    return atlas.record_flower_preparation_directive_result_for_member_v2(' || chr(10) ||
    '      p_task_id,' || chr(10) ||
    '      coalesce(p_payload->''lines'',''[]''::jsonb),' || chr(10) ||
    '      coalesce(p_payload->''workerAddedLines'',''[]''::jsonb),' || chr(10) ||
    '      coalesce(p_payload->''remainingStems'',''[]''::jsonb),' || chr(10) ||
    '      p_idempotency_key' || chr(10) ||
    '    );' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    v_anchor;
begin
  select pg_get_functiondef('atlas.worker_record_task_transition_v1(uuid,text,text,text,text,jsonb,date,text,text,uuid)'::regprocedure)
  into v_definition;

  if position('flower_preparation_directive_final_tally_v1' in v_definition) > 0 then
    return;
  end if;

  if position(v_anchor in v_definition) = 0 then
    raise exception 'Expected worker transition completion anchor was not found.';
  end if;

  v_definition := replace(v_definition, v_anchor, v_insert);
  execute v_definition;
end;
$do$;

commit;
