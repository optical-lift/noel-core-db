create or replace function atlas.task_external_readiness_state_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_gate atlas.task_external_readiness_gates%rowtype;
begin
  select * into v_gate
  from atlas.task_external_readiness_gates g
  where g.task_id=p_task_id and g.gate_state<>'retired'
  order by g.updated_at desc
  limit 1;

  if v_gate.id is null then
    return jsonb_build_object(
      'ready',true,'state','not_required','gateId',null,
      'holdDimensions','[]'::jsonb,'blocker',null
    );
  end if;

  return jsonb_build_object(
    'ready',v_gate.gate_state='ready',
    'state',v_gate.gate_state,
    'gateId',v_gate.id,
    'readinessKey',v_gate.readiness_key,
    'readinessLabel',v_gate.readiness_label,
    'blocker',v_gate.blocker_text,
    'holdDimensions',coalesce(v_gate.metadata->'hold_dimensions','[]'::jsonb),
    'readyAt',v_gate.ready_at
  );
end;
$function$;

create or replace function atlas.task_execution_requirement_inputs_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_prereq boolean;
  v_resources boolean;
  v_destination jsonb;
  v_seed jsonb;
  v_state_gate jsonb;
  v_state_clear boolean;
  v_bed_readiness jsonb;
  v_external jsonb;
begin
  if not exists(select 1 from atlas.tasks where id=p_task_id) then
    raise exception 'Task not found.' using errcode='P0002';
  end if;

  v_prereq:=atlas.task_prerequisites_ready_v1(p_task_id);
  v_resources:=atlas.task_required_resources_available_v1(p_task_id);
  v_destination:=atlas.task_execution_destination_readiness_v1(p_task_id);
  v_seed:=atlas.task_seed_readiness_v1(p_task_id);
  v_state_gate:=atlas.task_state_consequence_gate_v1(p_task_id);
  v_state_clear:=not coalesce((v_state_gate->>'blocking')::boolean,false);
  v_bed_readiness:=atlas.task_bed_weeding_readiness_v1(p_task_id);
  v_external:=atlas.task_external_readiness_state_v1(p_task_id);

  return jsonb_build_array(
    jsonb_build_object(
      'requirementKey','prerequisites','satisfied',v_prereq,
      'provider','task_prerequisites_ready_v1','providerState',case when v_prereq then 'satisfied' else 'open' end,
      'evidence',jsonb_build_object('ready',v_prereq)
    ),
    jsonb_build_object(
      'requirementKey','resources','satisfied',v_resources,
      'provider','task_required_resources_available_v1','providerState',case when v_resources then 'satisfied' else 'open' end,
      'evidence',jsonb_build_object('ready',v_resources)
    ),
    jsonb_build_object(
      'requirementKey','external_readiness','satisfied',coalesce((v_external->>'ready')::boolean,true),
      'provider','task_external_readiness_state_v1','providerState',coalesce(v_external->>'state','not_required'),
      'evidence',v_external
    ),
    jsonb_build_object(
      'requirementKey','destination','satisfied',coalesce((v_destination->>'ready')::boolean,false),
      'provider','task_execution_destination_readiness_v1','providerState',coalesce(v_destination->>'state','unknown'),
      'evidence',v_destination
    ),
    jsonb_build_object(
      'requirementKey','seed','satisfied',coalesce((v_seed->>'ready')::boolean,false),
      'provider','task_seed_readiness_v1','providerState',coalesce(v_seed->>'state','unknown'),
      'evidence',v_seed
    ),
    jsonb_build_object(
      'requirementKey','state_consequence','satisfied',v_state_clear,
      'provider','task_state_consequence_gate_v1','providerState',coalesce(v_state_gate->>'state','unknown'),
      'evidence',v_state_gate
    ),
    jsonb_build_object(
      'requirementKey','bed_readiness','satisfied',coalesce((v_bed_readiness->>'ready')::boolean,false),
      'provider','task_bed_weeding_readiness_v1',
      'providerState',case when coalesce((v_bed_readiness->>'ready')::boolean,false) then 'satisfied' else 'open' end,
      'evidence',v_bed_readiness
    )
  );
end;
$function$;

create or replace function atlas.task_execution_readiness_v1(p_task_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_canonical jsonb;
  v_requirements jsonb;
  v_ready boolean := false;
  v_prereq boolean := false;
  v_resources boolean := false;
  v_external_ready boolean := true;
  v_external jsonb := '{}'::jsonb;
  v_destination_ready boolean := false;
  v_seed_ready boolean := false;
  v_state_gate_clear boolean := false;
  v_bed_ready boolean := false;
  v_destination jsonb := '{}'::jsonb;
  v_seed jsonb := '{}'::jsonb;
  v_state_gate jsonb := '{}'::jsonb;
  v_bed_readiness jsonb := '{}'::jsonb;
begin
  v_canonical:=atlas.task_execution_requirement_evaluation_v1(p_task_id);
  v_requirements:=coalesce(v_canonical->'requirements','[]'::jsonb);
  v_ready:=coalesce((v_canonical->>'executionReady')::boolean,false);

  select coalesce((node->>'satisfied')::boolean,false) into v_prereq
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='prerequisites' limit 1;
  select coalesce((node->>'satisfied')::boolean,false) into v_resources
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='resources' limit 1;
  select coalesce((node->>'satisfied')::boolean,true),coalesce(node->'evidence','{}'::jsonb)
  into v_external_ready,v_external
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='external_readiness' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_destination_ready,v_destination
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='destination' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_seed_ready,v_seed
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='seed' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_state_gate_clear,v_state_gate
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='state_consequence' limit 1;
  select coalesce((node->>'satisfied')::boolean,false),coalesce(node->'evidence','{}'::jsonb)
  into v_bed_ready,v_bed_readiness
  from jsonb_array_elements(v_requirements) node where node->>'requirementKey'='bed_readiness' limit 1;

  return jsonb_build_object(
    'contractVersion','task_execution_warrant_v2',
    'contractRole','execution_warrant',
    'taskId',p_task_id,
    'ready',v_ready,
    'executionReady',v_ready,
    'prerequisitesReady',coalesce(v_prereq,false),
    'resourcesReady',coalesce(v_resources,false),
    'externalReadinessReady',coalesce(v_external_ready,true),
    'externalReadiness',coalesce(v_external,'{}'::jsonb),
    'destinationReady',coalesce(v_destination_ready,false),
    'seedReady',coalesce(v_seed_ready,false),
    'stateConsequenceClear',coalesce(v_state_gate_clear,false),
    'bedReadinessReady',coalesce(v_bed_ready,false),
    'bedReadiness',coalesce(v_bed_readiness,'{}'::jsonb),
    'preparationRequired',coalesce((v_state_gate->>'preparationRequired')::boolean,false),
    'destination',coalesce(v_destination,'{}'::jsonb),
    'seed',coalesce(v_seed,'{}'::jsonb),
    'stateConsequenceGate',coalesce(v_state_gate,'{}'::jsonb),
    'truthBoundary',jsonb_build_object(
      'requirementAuthority',false,
      'compatibilityProjection',true,
      'canonicalEvaluation','task_execution_requirement_evaluation_v1',
      'requirementExistenceNotInferredFromReady',true,
      'notReadyDoesNotMeanNotRequired',true,
      'capabilityHoldBlocksExecutionWithoutDeletingObligation',true,
      'thisContractOnlyAnswersWhetherRepresentedTaskMayExecuteNow',true
    )
  );
end;
$function$;

create or replace function atlas.refresh_task_external_readiness_gate_v1(p_gate_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_gate atlas.task_external_readiness_gates%rowtype;
  v_task atlas.tasks%rowtype;
  v_occurrence_id uuid;
  v_restore_due date;
  v_payload_metadata jsonb;
begin
  select * into v_gate
  from atlas.task_external_readiness_gates gate_row
  where gate_row.id=p_gate_id
  for update;

  if v_gate.id is null then
    raise exception 'External readiness gate not found.' using errcode='P0002';
  end if;

  select * into v_task
  from atlas.tasks task
  where task.id=v_gate.task_id
  for update;

  if v_task.id is null then
    update atlas.task_external_readiness_gates
    set gate_state='retired',updated_at=now(),metadata=metadata||jsonb_build_object('retired_reason','task_missing')
    where id=v_gate.id;
    return jsonb_build_object('gateId',v_gate.id,'state','retired','changed',true);
  end if;

  if v_task.status in ('done','skipped','archived') then
    update atlas.task_external_readiness_gates
    set gate_state='retired',updated_at=now(),metadata=metadata||jsonb_build_object('retired_reason','task_terminal')
    where id=v_gate.id;
    return jsonb_build_object('gateId',v_gate.id,'state','retired','changed',true,'taskId',v_task.id);
  end if;

  v_occurrence_id:=v_task.planned_occurrence_id;

  if v_gate.gate_state='waiting' then
    update atlas.tasks task
    set status='blocked',
        visibility_scope='system_internal',
        blocker_text=v_gate.blocker_text,
        metadata=coalesce(task.metadata,'{}'::jsonb)||jsonb_build_object(
          'external_readiness_required',true,
          'external_readiness_gate_id',v_gate.id,
          'external_readiness_key',v_gate.readiness_key,
          'external_readiness_label',v_gate.readiness_label,
          'external_readiness_state','waiting',
          'capability_hold_active',coalesce((v_gate.metadata->>'capability_hold')::boolean,false),
          'external_readiness_checked_at',now()
        ),
        updated_at=now()
    where task.id=v_task.id;

    if v_occurrence_id is not null then
      update atlas.planned_work_occurrences occurrence
      set state=case when occurrence.state in ('completed','cancelled') then occurrence.state else 'planned' end,
          gate_satisfied_at=case when occurrence.state in ('completed','cancelled') then occurrence.gate_satisfied_at else null end,
          released_at=case when occurrence.state in ('completed','cancelled') then occurrence.released_at else null end,
          released_task_id=case when occurrence.state in ('completed','cancelled') then occurrence.released_task_id else null end,
          task_payload=jsonb_set(
            jsonb_set(
              coalesce(occurrence.task_payload,'{}'::jsonb),
              '{metadata}',
              coalesce(occurrence.task_payload->'metadata','{}'::jsonb)||jsonb_build_object(
                'external_readiness_required',true,
                'external_readiness_gate_id',v_gate.id,
                'external_readiness_key',v_gate.readiness_key,
                'external_readiness_label',v_gate.readiness_label,
                'external_readiness_state','waiting'
              ),true
            ),
            '{status}',to_jsonb('open'::text),true
          ),
          metadata=coalesce(occurrence.metadata,'{}'::jsonb)||jsonb_build_object(
            'externalReadinessGateId',v_gate.id,
            'externalReadinessState','waiting',
            'externalReadinessHeldAt',now()
          ),
          updated_at=now()
      where occurrence.id=v_occurrence_id;
    end if;

    return jsonb_build_object(
      'gateId',v_gate.id,'state','waiting','changed',true,'taskId',v_task.id,'occurrenceId',v_occurrence_id,
      'dueDatePreserved',v_task.due_date,
      'truthBoundary',jsonb_build_object('holdDoesNotRewriteDueDate',true,'holdDoesNotDeleteObligation',true,'workerDaySuppressedByVisibility',true)
    );
  end if;

  if v_gate.gate_state='ready' then
    v_restore_due:=coalesce(v_task.due_date,v_gate.restore_due_date);

    update atlas.tasks task
    set status=v_gate.restore_status,
        due_date=v_restore_due,
        visibility_scope=v_gate.restore_visibility_scope,
        blocker_text=null,
        released_at=coalesce(task.released_at,now()),
        release_reason='external_readiness_satisfied',
        metadata=coalesce(task.metadata,'{}'::jsonb)||jsonb_build_object(
          'external_readiness_required',true,
          'external_readiness_gate_id',v_gate.id,
          'external_readiness_key',v_gate.readiness_key,
          'external_readiness_label',v_gate.readiness_label,
          'external_readiness_state','ready',
          'capability_hold_active',false,
          'external_readiness_satisfied_at',coalesce(v_gate.ready_at,now())
        ),
        updated_at=now()
    where task.id=v_task.id;

    if v_occurrence_id is not null then
      v_payload_metadata:=coalesce((select occurrence.task_payload->'metadata' from atlas.planned_work_occurrences occurrence where occurrence.id=v_occurrence_id),'{}'::jsonb)
        ||jsonb_build_object(
          'external_readiness_required',true,
          'external_readiness_gate_id',v_gate.id,
          'external_readiness_key',v_gate.readiness_key,
          'external_readiness_label',v_gate.readiness_label,
          'external_readiness_state','ready'
        );

      update atlas.planned_work_occurrences occurrence
      set state=case when occurrence.state in ('completed','cancelled') then occurrence.state else 'released' end,
          planned_due_date=coalesce(occurrence.planned_due_date,v_restore_due),
          gate_satisfied_at=case when occurrence.state in ('completed','cancelled') then occurrence.gate_satisfied_at else coalesce(v_gate.ready_at,now()) end,
          released_at=case when occurrence.state in ('completed','cancelled') then occurrence.released_at else now() end,
          released_task_id=case when occurrence.state in ('completed','cancelled') then occurrence.released_task_id else v_task.id end,
          task_payload=jsonb_set(
            jsonb_set(coalesce(occurrence.task_payload,'{}'::jsonb),'{metadata}',v_payload_metadata,true),
            '{status}',to_jsonb('open'::text),true
          ),
          metadata=coalesce(occurrence.metadata,'{}'::jsonb)||jsonb_build_object(
            'externalReadinessGateId',v_gate.id,
            'externalReadinessState','ready',
            'externalReadinessSatisfiedAt',coalesce(v_gate.ready_at,now())
          ),
          updated_at=now()
      where occurrence.id=v_occurrence_id;
    end if;

    return jsonb_build_object(
      'gateId',v_gate.id,'state','ready','changed',true,'taskId',v_task.id,'occurrenceId',v_occurrence_id,'dueDate',v_restore_due,
      'truthBoundary',jsonb_build_object('releaseDoesNotMoveOriginalDueDateForward',true,'workerDayEligibilityRestored',true)
    );
  end if;

  return jsonb_build_object('gateId',v_gate.id,'state',v_gate.gate_state,'changed',false,'taskId',v_task.id);
end;
$function$;

create or replace function atlas.set_task_capability_hold_internal_v1(
  p_task_id uuid,
  p_state text,
  p_dimensions text[],
  p_blocker_text text,
  p_note text default null,
  p_source text default 'atlas_capability_hold'
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_task atlas.tasks%rowtype;
  v_gate_id uuid;
  v_state text:=lower(btrim(coalesce(p_state,'')));
  v_dimensions text[]:=coalesce(p_dimensions,'{}'::text[]);
  v_invalid text;
  v_result jsonb;
begin
  if v_state not in ('waiting','ready') then
    raise exception 'Capability hold state must be waiting or ready.' using errcode='22023';
  end if;

  select d into v_invalid
  from unnest(v_dimensions) d
  where d not in ('person','capability','tool','material','travel','location','time','information','other')
  limit 1;
  if v_invalid is not null then
    raise exception 'Unsupported capability hold dimension: %',v_invalid using errcode='22023';
  end if;

  select * into v_task from atlas.tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;
  if v_task.status in ('done','skipped','archived') then
    raise exception 'Terminal task cannot enter capability hold.' using errcode='22023';
  end if;

  update atlas.tasks t
  set blocker_text=case when v_state='waiting' then coalesce(nullif(btrim(p_blocker_text),''),'Waiting for capability or resource availability.') else t.blocker_text end,
      metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
        'external_readiness_required',true,
        'external_readiness_state',v_state,
        'external_readiness_key',coalesce(nullif(t.metadata->>'external_readiness_key',''),coalesce(nullif(t.metadata->>'task_key',''),t.id::text)||':capability-hold'),
        'external_readiness_label',coalesce(nullif(t.metadata->>'external_readiness_label',''),'Capability/resources available'),
        'capability_hold',true,
        'capability_hold_state',v_state,
        'capability_hold_dimensions',to_jsonb(v_dimensions),
        'capability_hold_source',coalesce(nullif(p_source,''),'atlas_capability_hold'),
        'capability_hold_note',nullif(btrim(coalesce(p_note,'')),''),
        'capability_hold_changed_at',now()
      ),
      updated_at=now()
  where t.id=p_task_id;

  select g.id into v_gate_id
  from atlas.task_external_readiness_gates g
  where g.task_id=p_task_id
  for update;
  if v_gate_id is null then raise exception 'Capability hold gate was not created.' using errcode='55000'; end if;

  update atlas.task_external_readiness_gates g
  set gate_state=v_state,
      blocker_text=case when v_state='waiting' then coalesce(nullif(btrim(p_blocker_text),''),g.blocker_text) else g.blocker_text end,
      ready_at=case when v_state='ready' then coalesce(g.ready_at,now()) else null end,
      evidence_note=nullif(btrim(coalesce(p_note,'')),''),
      metadata=coalesce(g.metadata,'{}'::jsonb)||jsonb_build_object(
        'capability_hold',true,
        'hold_dimensions',to_jsonb(v_dimensions),
        'hold_source',coalesce(nullif(p_source,''),'atlas_capability_hold'),
        'hold_changed_at',now()
      ),
      updated_at=now()
  where g.id=v_gate_id;

  v_result:=atlas.refresh_task_external_readiness_gate_v1(v_gate_id);
  return v_result||jsonb_build_object(
    'contractVersion','task_capability_hold_v1',
    'poolState',case when v_state='waiting' then 'waiting_for_capability' else 'released_from_capability_hold' end,
    'dimensions',to_jsonb(v_dimensions)
  );
end;
$function$;

create or replace function atlas.owner_set_task_capability_hold_v1(
  p_task_id uuid,
  p_state text,
  p_dimensions text[],
  p_blocker_text text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_farm_id uuid;
begin
  select farm_id into v_farm_id from atlas.tasks where id=p_task_id;
  if v_farm_id is null then raise exception 'Task not found.' using errcode='P0002'; end if;
  if auth.uid() is null or not atlas.is_farm_owner(v_farm_id) then
    raise exception 'Owner membership required.' using errcode='42501';
  end if;
  return atlas.set_task_capability_hold_internal_v1(p_task_id,p_state,p_dimensions,p_blocker_text,p_note,'owner');
end;
$function$;

grant execute on function atlas.owner_set_task_capability_hold_v1(uuid,text,text[],text,text) to authenticated;
revoke all on function atlas.set_task_capability_hold_internal_v1(uuid,text,text[],text,text,text) from public,anon,authenticated;

create or replace function atlas.capability_hold_pool_v1(p_farm_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to pg_catalog, atlas, auth
as $function$
declare
  v_items jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  if auth.uid() is not null and not exists(
    select 1 from atlas.farm_memberships fm
    where fm.farm_id=p_farm_id and fm.active=true and fm.user_id=auth.uid() and fm.role in ('owner','manager')
  ) then
    raise exception 'Owner or manager membership required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'taskId',t.id,
      'title',t.title,
      'taskType',t.task_type,
      'actionKey',t.action_key,
      'status',t.status,
      'dueDate',t.due_date,
      'assignedMembershipId',t.assigned_membership_id,
      'assignedWorkerKey',fm.worker_key,
      'assignedRole',fm.role,
      'poolState','waiting_for_capability',
      'readinessKey',g.readiness_key,
      'readinessLabel',g.readiness_label,
      'blocker',g.blocker_text,
      'holdDimensions',coalesce(g.metadata->'hold_dimensions',t.metadata->'capability_hold_dimensions','[]'::jsonb),
      'heldSince',g.created_at,
      'lastChangedAt',g.updated_at,
      'restoreVisibilityScope',g.restore_visibility_scope,
      'originalDueDate',coalesce(g.restore_due_date,t.due_date)
    ) order by g.created_at,t.title),'[]'::jsonb),count(*)::integer
  into v_items,v_count
  from atlas.task_external_readiness_gates g
  join atlas.tasks t on t.id=g.task_id
  left join atlas.farm_memberships fm on fm.id=t.assigned_membership_id
  where g.farm_id=p_farm_id
    and g.gate_state='waiting'
    and coalesce((g.metadata->>'capability_hold')::boolean,(t.metadata->>'capability_hold')::boolean,false)=true
    and t.status not in ('done','skipped','archived');

  return jsonb_build_object(
    'contractVersion','capability_hold_pool_v1',
    'farmId',p_farm_id,
    'poolState','waiting_for_capability',
    'count',v_count,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'obligationRetained',true,
      'assignmentRetained',true,
      'dueTruthRetained',true,
      'workerDaySuppressedUntilReady',true
    )
  );
end;
$function$;

grant execute on function atlas.capability_hold_pool_v1(uuid) to authenticated;

create or replace function atlas.reconcile_expired_event_bound_tasks_v1(p_farm_id uuid,p_as_of_date date default null)
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  v_as_of date:=coalesce(p_as_of_date,(now() at time zone coalesce((select nullif(f.metadata->>'timezone','') from atlas.farms f where f.id=p_farm_id),'America/Chicago'))::date);
  r record;
  v_transition jsonb;
  v_results jsonb:='[]'::jsonb;
  v_count integer:=0;
begin
  for r in
    select t.id as task_id,t.title,t.due_date,t.planned_occurrence_id,ce.id as event_id,ce.stable_key as event_key,ce.title as event_title,ce.event_date
    from atlas.tasks t
    join atlas.community_events ce
      on ce.farm_id=t.farm_id
     and (
       (coalesce(t.metadata->>'community_event_id','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' and ce.id=(t.metadata->>'community_event_id')::uuid)
       or (nullif(t.metadata->>'community_event_key','') is not null and ce.stable_key=t.metadata->>'community_event_key')
     )
    where t.farm_id=p_farm_id
      and t.status in ('open','blocked')
      and coalesce((t.metadata->>'one_off_event_task')::boolean,false)=true
      and ce.event_date<v_as_of
    order by ce.event_date,t.id
  loop
    v_transition:=atlas.record_task_transition_v1_internal(
      r.task_id,'not_relevant',
      left('event-expired:'||r.task_id::text||':'||r.event_date::text,160),
      null,
      'Expired with '||r.event_title||' on '||to_char(r.event_date,'Mon FMDD')||'.',
      'One-off event work no longer has an executable purpose after its event ends.',
      'lifecycle','event_bound_expiry',
      jsonb_build_object(
        'completion_source','event_lifecycle_expiry',
        'lifetime_kind','event_bound',
        'expired_with_event',true,
        'community_event_id',r.event_id,
        'community_event_key',r.event_key,
        'event_date',r.event_date,
        'original_due_date',r.due_date
      ),null
    );

    update atlas.tasks t
    set metadata=coalesce(t.metadata,'{}'::jsonb)||jsonb_build_object(
          'lifetime_kind','event_bound',
          'event_expired',true,
          'event_expired_at',now(),
          'event_expired_date',r.event_date,
          'event_expiry_source','reconcile_expired_event_bound_tasks_v1'
        ),
        updated_at=now()
    where t.id=r.task_id;

    if r.planned_occurrence_id is not null then
      update atlas.planned_work_occurrences o
      set state=case when o.state='completed' then o.state else 'cancelled' end,
          hard_finish_date=coalesce(o.hard_finish_date,r.event_date),
          miss_consequence=coalesce(o.miss_consequence,'{}'::jsonb)||jsonb_build_object(
            'kind','event_expired','eventDate',r.event_date,'eventId',r.event_id,'taskRetired',true
          ),
          metadata=coalesce(o.metadata,'{}'::jsonb)||jsonb_build_object(
            'eventBoundLifetime',true,'eventExpiredAt',now(),'eventDate',r.event_date
          ),
          updated_at=now()
      where o.id=r.planned_occurrence_id;
    end if;

    v_count:=v_count+1;
    v_results:=v_results||jsonb_build_array(jsonb_build_object(
      'taskId',r.task_id,'title',r.title,'eventId',r.event_id,'eventDate',r.event_date,'status','archived','transition',v_transition
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','event_bound_task_lifetime_v1',
    'farmId',p_farm_id,'asOfDate',v_as_of,'retiredCount',v_count,'tasks',v_results,
    'truthBoundary',jsonb_build_object(
      'onlyExplicitOneOffEventTasksExpire',true,
      'eventExpiryDoesNotClaimWorkWasCompleted',true,
      'durableTasksAreUnaffected',true
    )
  );
end;
$function$;

revoke all on function atlas.reconcile_expired_event_bound_tasks_v1(uuid,date) from public,anon,authenticated;

create or replace function atlas.roll_expired_farm_worker_tasks_v1()
returns jsonb
language plpgsql
security definer
set search_path to pg_catalog, atlas
as $function$
declare
  r record;
  f record;
  v_results jsonb:='[]'::jsonb;
  v_event_results jsonb:='[]'::jsonb;
begin
  for f in
    select distinct t.farm_id
    from atlas.tasks t
    where t.status in ('open','blocked')
      and coalesce((t.metadata->>'one_off_event_task')::boolean,false)=true
  loop
    v_event_results:=v_event_results||jsonb_build_array(atlas.reconcile_expired_event_bound_tasks_v1(f.farm_id,null));
  end loop;

  for r in
    select fm.farm_id,fm.id as membership_id
    from atlas.farm_memberships fm
    where fm.active=true
      and (
        exists(
          select 1 from atlas.tasks t
          where t.farm_id=fm.farm_id
            and t.assigned_membership_id=fm.id
            and t.task_scope='farm_operation'
            and t.status in ('open','blocked')
        )
        or exists(
          select 1 from atlas.worker_day_task_placements p
          join atlas.tasks t on t.id=p.task_id
          where p.farm_id=fm.farm_id
            and p.membership_id=fm.id
            and p.state='placed'
            and t.status in ('open','blocked')
        )
      )
    order by fm.farm_id,fm.id
  loop
    v_results:=v_results||jsonb_build_array(atlas.roll_expired_worker_tasks_v1(r.farm_id,r.membership_id,null));
  end loop;

  return jsonb_build_object(
    'contractVersion','worker_calendar_rollover_v3',
    'ranAt',now(),
    'eventBoundReconciliation',v_event_results,
    'workers',v_results,
    'truthBoundary',jsonb_build_object(
      'custodyIsRoleIndependent',true,
      'activeMembershipWithOperationalWorkIsReconciled',true,
      'eventBoundWorkExpiresByLifecycleNotByRollover',true,
      'capabilityHeldWorkRemainsInAtlasButOutsideWorkerDay',true
    )
  );
end;
$function$;