-- Atlas platform primitive: company-neutral Operation Contract membrane.
-- Domain modules/adapters supply evidence; this membrane does not create truth,
-- execution warrant, responsibility, placement, Clock decisions, or effects.

create or replace function atlas.operation_contract_normalize_v1(p_input jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = 'pg_catalog', 'atlas'
as $fn$
declare
  v_input jsonb := coalesce(p_input,'{}'::jsonb);
  v_subject jsonb;
  v_requirement jsonb;
  v_operation jsonb;
  v_responsibility jsonb;
  v_conditions jsonb;
  v_routing jsonb;
  v_result jsonb;
  v_continuation jsonb;
  v_provenance jsonb;
  v_ready boolean;
  v_disposition text;
begin
  if jsonb_typeof(v_input) <> 'object' then raise exception 'Operation Contract input must be a JSON object.' using errcode='22023'; end if;
  v_subject := v_input->'subject';
  v_requirement := v_input->'requirement';
  v_operation := v_input->'operation';
  v_responsibility := v_input->'responsibility';
  v_conditions := v_input->'executionConditions';
  v_routing := coalesce(v_input->'routing','{}'::jsonb);
  v_result := v_input->'resultContract';
  v_continuation := coalesce(v_input->'continuation','{}'::jsonb);
  v_provenance := coalesce(v_input->'provenance','{}'::jsonb);

  if jsonb_typeof(v_subject) <> 'object' then raise exception 'Operation Contract requires object subject.' using errcode='22023'; end if;
  if jsonb_typeof(v_requirement) <> 'object' then raise exception 'Operation Contract requires object requirement.' using errcode='22023'; end if;
  if jsonb_typeof(v_operation) <> 'object' then raise exception 'Operation Contract requires object operation.' using errcode='22023'; end if;
  if jsonb_typeof(v_responsibility) <> 'object' then raise exception 'Operation Contract requires object responsibility.' using errcode='22023'; end if;
  if jsonb_typeof(v_conditions) <> 'object' then raise exception 'Operation Contract requires object executionConditions.' using errcode='22023'; end if;
  if jsonb_typeof(v_routing) <> 'object' then raise exception 'Operation Contract routing must be an object when supplied.' using errcode='22023'; end if;
  if jsonb_typeof(v_result) <> 'object' then raise exception 'Operation Contract requires object resultContract.' using errcode='22023'; end if;
  if jsonb_typeof(v_continuation) <> 'object' then raise exception 'Operation Contract continuation must be an object when supplied.' using errcode='22023'; end if;
  if jsonb_typeof(v_provenance) <> 'object' then raise exception 'Operation Contract provenance must be an object when supplied.' using errcode='22023'; end if;
  if nullif(v_subject->>'kind','') is null then raise exception 'Operation Contract subject.kind is required.' using errcode='22023'; end if;
  if nullif(v_operation->>'actionKey','') is null
     and nullif(v_operation->>'operationClass','') is null
     and nullif(v_operation->>'instruction','') is null then
    raise exception 'Operation Contract operation must identify an action, operation class, or instruction.' using errcode='22023';
  end if;
  if jsonb_typeof(v_conditions->'executionReady') <> 'boolean' then
    raise exception 'Operation Contract executionConditions.executionReady must be boolean.' using errcode='22023';
  end if;

  v_ready := (v_conditions->>'executionReady')::boolean;
  v_disposition := case
    when coalesce(v_operation->>'state','') in ('closed','completed','cancelled') then 'closed'
    when coalesce(v_requirement->>'state','') in ('awaiting_truth','truth_required','unknown') then 'awaiting_truth'
    when v_ready then 'warranted'
    else 'blocked'
  end;

  return jsonb_build_object(
    'contractVersion','operation_contract_v1',
    'contractRole','platform_operation_contract_membrane',
    'subject',v_subject,
    'requirement',v_requirement,
    'operation',v_operation,
    'responsibility',v_responsibility,
    'executionConditions',v_conditions,
    'routing',v_routing,
    'resultContract',v_result,
    'continuation',v_continuation,
    'provenance',v_provenance,
    'executionDisposition',v_disposition,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'doesNotOwnDomainTruth',true,
      'doesNotCreateRequirement',true,
      'doesNotCreateExecutionWarrant',true,
      'doesNotAssignResponsibility',true,
      'doesNotArbitrateClock',true,
      'doesNotCreatePlacement',true,
      'doesNotExecuteEffects',true,
      'doesNotInterpretResultMeaning',true,
      'domainModulesSupplyDomainEvidence',true,
      'tenantConfigurationRemainsData',true
    )
  );
end;
$fn$;

revoke execute on function atlas.operation_contract_normalize_v1(jsonb) from public, anon, authenticated;

comment on function atlas.operation_contract_normalize_v1(jsonb) is
  'Company-neutral Atlas platform Operation Contract membrane. Normalizes supplied subject, requirement, operation, responsibility, execution-condition, routing, result, continuation, and provenance contracts without owning domain truth or performing scheduling/effects.';

create or replace function atlas.task_operation_contract_v1(
  p_task_id uuid,
  p_membership_id uuid default null,
  p_service_date date default null
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'pg_catalog', 'atlas'
as $fn$
declare
  v_task atlas.tasks%rowtype;
  v_org uuid;
  v_eval jsonb;
  v_subjects jsonb := '[]'::jsonb;
  v_subject jsonb;
  v_capacity jsonb := null;
  v_temporal boolean := null;
  v_placement jsonb := '{}'::jsonb;
  v_assignment_matches boolean := null;
  v_structured boolean := false;
  v_input jsonb;
  v_contract jsonb;
begin
  select * into v_task from atlas.tasks where id=p_task_id;
  if v_task.id is null then raise exception 'Task not found.' using errcode='P0002'; end if;

  select f.organization_id into v_org from atlas.farms f where f.id=v_task.farm_id;
  v_eval := atlas.task_execution_requirement_evaluation_v1(v_task.id);

  select coalesce(jsonb_agg(s.subject order by s.subject->>'kind',s.subject->>'id'),'[]'::jsonb)
  into v_subjects
  from (
    select jsonb_strip_nulls(jsonb_build_object(
      'kind','crop_cycle','id',c.id,'stableKey',c.crop_cycle_key,
      'state',c.cycle_state,'lifecycleStatus',c.lifecycle_status
    )) as subject
    from atlas.task_crop_cycles link
    join atlas.crop_cycles c on c.id=link.crop_cycle_id
    where link.task_id=v_task.id
    union all
    select jsonb_strip_nulls(jsonb_build_object(
      'kind','production_lot','id',l.id,'stableKey',l.stable_key,
      'state',l.current_stage,'lifecycleStatus',l.lifecycle_status
    ))
    from atlas.production_lot_tasks link
    join atlas.production_lots l on l.id=link.production_lot_id
    where link.task_id=v_task.id
    union all
    select jsonb_strip_nulls(jsonb_build_object(
      'kind',r.subject_kind,'id',r.subject_id,'rhythmStateId',r.id,
      'stableKey',r.rhythm_key,'state',r.state
    ))
    from atlas.rhythm_state r
    where r.current_task_id=v_task.id
  ) s;

  v_subject := case
    when jsonb_array_length(v_subjects)>0 then jsonb_build_object(
      'kind','domain_subject_set',
      'identityState','canonical_domain_subjects',
      'subjects',v_subjects
    )
    else jsonb_build_object(
      'kind','institutional_obligation',
      'identityState','carrier_only',
      'carrier',jsonb_build_object('type','task','id',v_task.id)
    )
  end;

  if p_service_date is not null then
    v_temporal := atlas.task_temporally_eligible_v1(v_task.id,p_service_date);
    select to_jsonb(cp) into v_capacity from atlas.task_capacity_plan_v1(v_task,p_service_date) cp;
  end if;

  if p_membership_id is not null then
    v_assignment_matches := v_task.assigned_membership_id is not distinct from p_membership_id
      or v_task.metadata->>'executor_membership_id'=p_membership_id::text;
    if p_service_date is not null then
      select coalesce(jsonb_build_object(
        'state',p.state,'placementId',p.id,'serviceDate',p.service_date,
        'dayWindow',p.day_window,'sortOrder',p.sort_order,'source',p.placement_source
      ),'{}'::jsonb)
      into v_placement
      from atlas.worker_day_task_placements p
      where p.farm_id=v_task.farm_id
        and p.membership_id=p_membership_id
        and p.task_id=v_task.id
        and p.service_date=p_service_date
      order by p.updated_at desc,p.created_at desc
      limit 1;
      v_placement := coalesce(v_placement,'{}'::jsonb);
    end if;
  end if;

  v_structured := atlas.worker_task_requires_structured_result_v1(v_task.id);

  v_input := jsonb_build_object(
    'subject',v_subject,
    'requirement',jsonb_build_object(
      'state',case when v_task.status in ('done','archived','cancelled') then 'closed' else 'active' end,
      'representationState','execution_requirement_evaluated',
      'evaluation',v_eval
    ),
    'operation',jsonb_strip_nulls(jsonb_build_object(
      'state',case when v_task.status in ('done','archived','cancelled') then 'closed' else 'proposed' end,
      'actionKey',v_task.action_key,
      'operationClass',v_task.operation_class,
      'instruction',coalesce(nullif(v_task.metadata->>'execution_do',''),v_task.title),
      'doneWhen',nullif(v_task.metadata->>'execution_done_when',''),
      'carrierTaskId',v_task.id,
      'taskType',v_task.task_type
    )),
    'responsibility',jsonb_strip_nulls(jsonb_build_object(
      'organizationId',v_org,
      'operatingUnit',jsonb_build_object('kind','farm','id',v_task.farm_id),
      'assignedMembershipId',v_task.assigned_membership_id,
      'assignedUserId',v_task.assigned_user_id,
      'visibilityScope',v_task.visibility_scope
    )),
    'executionConditions',jsonb_strip_nulls(jsonb_build_object(
      'executionReady',coalesce((v_eval->>'executionReady')::boolean,false),
      'requirements',coalesce(v_eval->'requirements','[]'::jsonb),
      'serviceDate',p_service_date,
      'temporallyEligible',v_temporal,
      'capacity',v_capacity
    )),
    'routing',jsonb_strip_nulls(jsonb_build_object(
      'requestedMembershipId',p_membership_id,
      'assignmentMatches',v_assignment_matches,
      'placement',v_placement
    )),
    'resultContract',jsonb_strip_nulls(jsonb_build_object(
      'structuredResultRequired',v_structured,
      'executionChecklistTemplateKey',nullif(v_task.metadata->>'execution_checklist_template_key',''),
      'authority','existing_operation_result_state_transition'
    )),
    'continuation',jsonb_build_object(
      'authority','existing_domain_continuation',
      'recomputeAfterResult',jsonb_build_array('canonical_state','requirement','execution_warrant','clock_candidacy')
    ),
    'provenance',jsonb_build_object(
      'adapter','task_operation_contract_v1',
      'carrier','atlas.tasks',
      'requirementEvaluation','task_execution_requirement_evaluation_v1',
      'domainSubjectsRemainDomainOwned',true
    )
  );

  v_contract := atlas.operation_contract_normalize_v1(v_input);
  return v_contract || jsonb_build_object(
    'adapterContractVersion','task_operation_contract_v1',
    'carrierTaskId',v_task.id
  );
end;
$fn$;

revoke execute on function atlas.task_operation_contract_v1(uuid,uuid,date) from public, anon, authenticated;

comment on function atlas.task_operation_contract_v1(uuid,uuid,date) is
  'Atlas task/domain adapter into operation_contract_v1. Existing task, domain-subject, Requirement Evaluation, temporal, capacity, routing, and result-contract providers remain authoritative; this adapter only projects them into the company-neutral platform grammar.';

-- Productization assertions: the platform membrane itself must remain free of
-- farm-domain ontology, while a deliberately non-farm operation must fit it.
do $assert$
declare
  v_def text;
  v_adapter text;
  v_fixture jsonb;
begin
  select pg_get_functiondef('atlas.operation_contract_normalize_v1(jsonb)'::regprocedure) into v_def;
  select pg_get_functiondef('atlas.task_operation_contract_v1(uuid,uuid,date)'::regprocedure) into v_adapter;

  if lower(v_def) ~ '(farm|crop|mow|harvest|bed|seed|grow_room)' then
    raise exception 'Platform Operation Contract membrane contains farm-domain vocabulary';
  end if;
  if position('task_execution_requirement_evaluation_v1' in v_adapter)=0 then
    raise exception 'Task Operation Contract adapter must consume canonical Requirement Evaluation';
  end if;
  if v_def not like '%doesNotCreateExecutionWarrant%'
     or v_def not like '%doesNotArbitrateClock%'
     or v_def not like '%doesNotExecuteEffects%' then
    raise exception 'Platform Operation Contract truth boundary is incomplete';
  end if;

  v_fixture := atlas.operation_contract_normalize_v1(jsonb_build_object(
    'subject',jsonb_build_object('kind','equipment','stableKey','northstar:hvac:unit-17','state','service_due'),
    'requirement',jsonb_build_object('kind','recurring_inspection','state','active','reason','Quarterly inspection due'),
    'operation',jsonb_build_object('state','proposed','actionKey','inspect','operationClass','inspect_assess','instruction','Inspect HVAC unit'),
    'responsibility',jsonb_build_object(
      'organizationId','synthetic:northstar',
      'operatingUnit',jsonb_build_object('kind','service_team','stableKey','field-service'),
      'responsibleRole','technician',
      'executor',jsonb_build_object('stableKey','tech-1')
    ),
    'executionConditions',jsonb_build_object(
      'executionReady',true,
      'requirements',jsonb_build_array(jsonb_build_object('requirementKey','equipment_access','satisfied',true)),
      'serviceDate','2026-08-26'
    ),
    'routing',jsonb_build_object('serviceDate','2026-08-26','placementState','candidate'),
    'resultContract',jsonb_build_object(
      'state','structured_result',
      'allowedResults',jsonb_build_array('pass','repair_required'),
      'requiredObservations',jsonb_build_array('condition')
    ),
    'continuation',jsonb_build_object('onResult','recompute_subject_state'),
    'provenance',jsonb_build_object('fixture','northstar_property_services')
  ));

  if v_fixture->>'contractVersion' <> 'operation_contract_v1'
     or v_fixture->>'executionDisposition' <> 'warranted'
     or v_fixture#>>'{subject,kind}' <> 'equipment' then
    raise exception 'Synthetic non-farm Operation Contract acceptance fixture failed';
  end if;
end
$assert$;
