create or replace function atlas.guard_worker_task_authoring_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_violations text[];
  v_packet jsonb;
  v_method_required boolean := false;
  v_execution_how_present boolean := false;
  v_method_contract_key text := '';
  v_method_contract_present boolean := false;
  v_method_resource_present boolean := false;
  v_worker_surface text := '';
begin
  v_packet := coalesce(new.metadata,'{}'::jsonb)
    || jsonb_strip_nulls(jsonb_build_object('operation_class',new.operation_class));

  v_violations := atlas.worker_task_authoring_violations_v1(
    new.title,
    v_packet,
    new.visibility_scope
  );

  if new.visibility_scope = 'assigned_worker'
     and coalesce(new.status,'open') not in ('done','archived','cancelled') then
    if lower(coalesce(new.metadata->>'owner_definition_required','false')) = 'true'
       or lower(coalesce(new.metadata->>'worker_packet_hold','false')) = 'true'
       or lower(coalesce(new.metadata->>'truth_acquisition_required','false')) = 'true' then
      v_violations := array_append(v_violations,'unresolved_execution_truth_hold');
    end if;

    v_worker_surface := lower(concat_ws(' ',
      coalesce(new.title,''),
      coalesce(new.note,''),
      coalesce(new.blocker_text,''),
      coalesce(new.metadata->>'execution_do',''),
      coalesce(new.metadata->>'execution_how',''),
      coalesce(new.metadata->>'execution_done_when',''),
      coalesce(new.metadata->>'display_detail',''),
      coalesce(new.metadata->>'method_constraints','')
    ));

    if v_worker_surface ~ 'method resource not attached|do not infer product|owner must define|to be determined|(^|[^a-z])tbd([^a-z]|$)' then
      v_violations := array_append(v_violations,'unresolved_execution_placeholder');
    end if;

    v_method_required := lower(coalesce(new.operation_class,'')) = 'apply_treatment'
      or lower(coalesce(new.metadata->>'worker_method_required','false')) = 'true';

    if v_method_required then
      v_execution_how_present := case jsonb_typeof(new.metadata->'execution_how')
        when 'array' then jsonb_array_length(new.metadata->'execution_how') > 0
        when 'string' then btrim(coalesce(new.metadata->>'execution_how','')) <> ''
        else false
      end;

      v_method_contract_key := btrim(coalesce(
        new.metadata->>'method_contract_key',
        new.metadata->>'action_requirement_template_key',
        ''
      ));

      v_method_contract_present := v_method_contract_key <> ''
        and exists (
          select 1
          from atlas.action_requirement_templates art
          where art.farm_id = new.farm_id
            and art.stable_key = v_method_contract_key
            and art.action_type = new.action_key
        );

      v_method_resource_present :=
        (jsonb_typeof(new.metadata->'required_resource_keys') = 'array'
         and jsonb_array_length(new.metadata->'required_resource_keys') > 0)
        or btrim(coalesce(new.metadata->>'method_resource_key','')) <> ''
        or exists (
          select 1
          from atlas.action_requirement_templates art
          where art.farm_id = new.farm_id
            and art.stable_key = v_method_contract_key
            and art.action_type = new.action_key
            and coalesce(array_length(art.required_resource_keys,1),0) > 0
        );

      if v_execution_how_present then
        v_violations := array_append(v_violations,'worker_free_prose_execution_how_forbidden');
      end if;
      if not v_method_contract_present then
        v_violations := array_append(v_violations,'missing_required_method_contract');
      end if;
      if not v_method_resource_present then
        v_violations := array_append(v_violations,'missing_required_method_resource');
      end if;
    end if;
  end if;

  if coalesce(array_length(v_violations,1),0) > 0 then
    raise exception 'Worker task execution contract rejected: %. Resolve required execution facts or route the unknown back to Owner/truth acquisition; worker-facing placeholders are forbidden.',
      array_to_string(v_violations,', ')
      using errcode='23514';
  end if;

  return new;
end;
$function$;

comment on function atlas.guard_worker_task_authoring_v1() is
  'Fail-closed worker authoring membrane. Treatment tasks resolve method custody through canonical action requirement templates; copied execution_how prose is forbidden on assigned-worker treatment packets.';

update atlas.tasks
set metadata = metadata - 'execution_how' - 'required_resource_keys',
    updated_at = now()
where lower(coalesce(operation_class,'')) = 'apply_treatment'
  and metadata->>'method_contract_key' = 'bb10_bermuda_spray_method_v1'
  and (metadata ? 'execution_how' or metadata ? 'required_resource_keys');

update atlas.task_resource_requirements tr
set note = null,
    updated_at = now()
from atlas.tasks t,
     atlas.resources r
where tr.task_id = t.id
  and tr.resource_id = r.id
  and t.metadata->>'method_contract_key' = 'bb10_bermuda_spray_method_v1'
  and r.stable_key = 'black_jug_electric_sprayer'
  and tr.note is not null;