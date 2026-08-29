create or replace function atlas.author_production_work_occurrence_v1(
  p_farm_id uuid,
  p_work_key text,
  p_occurrence_key text,
  p_title text,
  p_due_date date,
  p_not_before_date date,
  p_source_kind text,
  p_source_id uuid,
  p_task_type text,
  p_action_key text,
  p_work_class text,
  p_priority text,
  p_visibility_scope text,
  p_assigned_membership_id uuid,
  p_assigned_user_id uuid,
  p_organization_id uuid,
  p_note text,
  p_metadata jsonb default '{}'::jsonb,
  p_relation_payload jsonb default '{}'::jsonb,
  p_work_lane text default 'process_continuation',
  p_commitment_kind text default 'dependency',
  p_latest_lawful_date date default null,
  p_miss_consequence jsonb default '{}'::jsonb,
  p_release_if_due boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_definition_id uuid;
  v_policy_id uuid;
  v_occurrence_id uuid;
  v_task_id uuid;
  v_today date := (now() at time zone 'America/Chicago')::date;
  v_materialized jsonb;
  v_definition_key text;
  v_policy_key text;
  v_existing_state text;
begin
  if p_farm_id is null or nullif(btrim(p_work_key),'') is null or nullif(btrim(p_occurrence_key),'') is null
     or nullif(btrim(p_title),'') is null or nullif(btrim(p_task_type),'') is null then
    raise exception 'Production occurrence requires farm, work key, occurrence key, title, and task type.' using errcode='22023';
  end if;

  v_definition_key := left('production:'||regexp_replace(lower(btrim(p_work_key)),'[^a-z0-9]+','_','g')||':v1',120);
  v_policy_key := left(v_definition_key||':time-window',120);

  insert into atlas.work_definitions(
    farm_id,stable_key,title_template,task_type,source_kind,action_key,work_class,
    default_priority,default_visibility_scope,active,metadata
  ) values (
    p_farm_id,v_definition_key,p_title,p_task_type,p_source_kind,p_action_key,p_work_class,
    coalesce(nullif(p_priority,''),'normal'),coalesce(nullif(p_visibility_scope,''),'assigned_worker'),true,
    jsonb_build_object('created_by','production_work_authoring_membrane_v1','production_work_key',p_work_key)
  )
  on conflict(farm_id,stable_key) do update set
    title_template=excluded.title_template,
    task_type=excluded.task_type,
    source_kind=coalesce(excluded.source_kind,atlas.work_definitions.source_kind),
    action_key=coalesce(excluded.action_key,atlas.work_definitions.action_key),
    work_class=coalesce(excluded.work_class,atlas.work_definitions.work_class),
    default_priority=excluded.default_priority,
    default_visibility_scope=excluded.default_visibility_scope,
    active=true,
    metadata=atlas.work_definitions.metadata||excluded.metadata,
    updated_at=now()
  returning id into v_definition_id;

  insert into atlas.work_release_policies(
    farm_id,work_definition_id,stable_key,gate_type,horizon_days,maximum_active_instances,gate_config,active,metadata
  ) values (
    p_farm_id,v_definition_id,v_policy_key,'time_window',45,50,
    jsonb_build_object('production_stage',true,'not_before_is_authoritative',true),true,
    jsonb_build_object('created_by','production_work_authoring_membrane_v1')
  )
  on conflict(farm_id,stable_key) do update set
    work_definition_id=excluded.work_definition_id,
    gate_type='time_window',
    horizon_days=greatest(atlas.work_release_policies.horizon_days,45),
    active=true,
    gate_config=atlas.work_release_policies.gate_config||excluded.gate_config,
    metadata=atlas.work_release_policies.metadata||excluded.metadata,
    updated_at=now()
  returning id into v_policy_id;

  select state,released_task_id into v_existing_state,v_task_id
  from atlas.planned_work_occurrences
  where farm_id=p_farm_id and work_definition_id=v_definition_id and occurrence_key=p_occurrence_key
  limit 1;

  insert into atlas.planned_work_occurrences(
    farm_id,work_definition_id,release_policy_id,occurrence_key,source_kind,source_id,title,
    planned_due_date,not_before_date,state,task_payload,relation_payload,metadata,
    work_lane,commitment_kind,effort_units,
    earliest_lawful_date,preferred_start_date,preferred_end_date,latest_lawful_date,hard_finish_date,
    miss_consequence,temporal_contract_source
  ) values (
    p_farm_id,v_definition_id,v_policy_id,p_occurrence_key,p_source_kind,p_source_id,p_title,
    p_due_date,coalesce(p_not_before_date,p_due_date),'planned',
    jsonb_strip_nulls(jsonb_build_object(
      'title',p_title,
      'task_type',p_task_type,
      'priority',coalesce(nullif(p_priority,''),'normal'),
      'note',p_note,
      'action_key',p_action_key,
      'work_class',p_work_class,
      'visibility_scope',coalesce(nullif(p_visibility_scope,''),'assigned_worker'),
      'assigned_membership_id',p_assigned_membership_id,
      'assigned_user_id',p_assigned_user_id,
      'organization_id',p_organization_id,
      'origin_kind','generated',
      'task_scope','farm_operation',
      'metadata',coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
        'work_lane',coalesce(nullif(p_work_lane,''),'process_continuation'),
        'commitment_kind',coalesce(nullif(p_commitment_kind,''),'dependency'),
        'production_occurrence_key',p_occurrence_key,
        'production_work_key',p_work_key,
        'authored_by','production_work_authoring_membrane_v1'
      )
    )),
    coalesce(p_relation_payload,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'production_work_key',p_work_key,
      'authored_by','production_work_authoring_membrane_v1'
    ),
    coalesce(nullif(p_work_lane,''),'process_continuation'),
    coalesce(nullif(p_commitment_kind,''),'dependency'),1,
    coalesce(p_not_before_date,p_due_date),p_due_date,p_latest_lawful_date,p_latest_lawful_date,p_latest_lawful_date,
    coalesce(p_miss_consequence,'{}'::jsonb),'production_work_authoring_membrane_v1'
  )
  on conflict(farm_id,work_definition_id,occurrence_key) do update set
    release_policy_id=excluded.release_policy_id,
    source_kind=excluded.source_kind,
    source_id=excluded.source_id,
    title=excluded.title,
    planned_due_date=excluded.planned_due_date,
    not_before_date=excluded.not_before_date,
    task_payload=excluded.task_payload,
    relation_payload=excluded.relation_payload,
    metadata=atlas.planned_work_occurrences.metadata||excluded.metadata,
    work_lane=excluded.work_lane,
    commitment_kind=excluded.commitment_kind,
    earliest_lawful_date=excluded.earliest_lawful_date,
    preferred_start_date=excluded.preferred_start_date,
    preferred_end_date=excluded.preferred_end_date,
    latest_lawful_date=excluded.latest_lawful_date,
    hard_finish_date=excluded.hard_finish_date,
    miss_consequence=excluded.miss_consequence,
    temporal_contract_source=excluded.temporal_contract_source,
    state=case when atlas.planned_work_occurrences.state in ('released','completed','cancelled') then atlas.planned_work_occurrences.state else 'planned' end,
    updated_at=now()
  returning id,released_task_id into v_occurrence_id,v_task_id;

  if p_release_if_due and coalesce(p_not_before_date,p_due_date,v_today)<=v_today then
    v_materialized:=atlas.materialize_specific_work_occurrence_v1(v_occurrence_id,v_today);
    v_task_id:=nullif(v_materialized->>'taskId','')::uuid;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','author_production_work_occurrence_v1',
    'occurrenceId',v_occurrence_id,
    'taskId',v_task_id,
    'state',(select state from atlas.planned_work_occurrences where id=v_occurrence_id),
    'workKey',p_work_key,
    'dueDate',p_due_date,
    'notBeforeDate',coalesce(p_not_before_date,p_due_date)
  ));
end;
$function$;

revoke all on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) from public;
grant execute on function atlas.author_production_work_occurrence_v1(uuid,text,text,text,date,date,text,uuid,text,text,text,text,text,uuid,uuid,uuid,text,jsonb,jsonb,text,text,date,jsonb,boolean) to service_role;