-- Atlas State Progression: promote Requirement Evaluation to the single
-- task-execution-readiness authority.
--
-- Domain providers remain unchanged and domain-owned. This migration removes
-- the temporary parity loop in which Requirement Evaluation called the legacy
-- readiness calculation. The legacy task_execution_readiness_v1 contract is
-- retained only as a compatibility projection for existing callers.

create or replace function atlas.task_execution_requirement_evaluation_v1(
  p_task_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_requirements jsonb;
  v_evaluation jsonb;
  v_satisfied boolean;
begin
  v_requirements := atlas.task_execution_requirement_inputs_v1(p_task_id);
  v_evaluation := atlas.requirement_set_evaluate_v1(v_requirements);
  v_satisfied := coalesce((v_evaluation->>'satisfied')::boolean, false);

  return jsonb_build_object(
    'contractVersion','task_execution_requirement_evaluation_v1',
    'contractRole','canonical_execution_requirement_evaluation',
    'taskId',p_task_id,
    'satisfied',v_satisfied,
    'executionReady',v_satisfied,
    'requirements',v_requirements,
    'evaluation',v_evaluation,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'executionReadinessAuthority',true,
      'providerResultsRemainDomainOwned',true,
      'doesNotMutateTask',true,
      'doesNotReleaseWork',true,
      'doesNotWriteBoundaryLedger',true,
      'doesNotNotify',true,
      'doesNotArbitrateClock',true
    )
  );
end;
$function$;

create or replace function atlas.task_execution_readiness_v1(
  p_task_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_canonical jsonb;
  v_requirements jsonb;
  v_ready boolean := false;
  v_prereq boolean := false;
  v_resources boolean := false;
  v_destination_ready boolean := false;
  v_seed_ready boolean := false;
  v_state_gate_clear boolean := false;
  v_destination jsonb := '{}'::jsonb;
  v_seed jsonb := '{}'::jsonb;
  v_state_gate jsonb := '{}'::jsonb;
begin
  v_canonical := atlas.task_execution_requirement_evaluation_v1(p_task_id);
  v_requirements := coalesce(v_canonical->'requirements', '[]'::jsonb);
  v_ready := coalesce((v_canonical->>'executionReady')::boolean, false);

  select coalesce((node->>'satisfied')::boolean, false)
  into v_prereq
  from jsonb_array_elements(v_requirements) node
  where node->>'requirementKey' = 'prerequisites'
  limit 1;

  select coalesce((node->>'satisfied')::boolean, false)
  into v_resources
  from jsonb_array_elements(v_requirements) node
  where node->>'requirementKey' = 'resources'
  limit 1;

  select
    coalesce((node->>'satisfied')::boolean, false),
    coalesce(node->'evidence', '{}'::jsonb)
  into v_destination_ready, v_destination
  from jsonb_array_elements(v_requirements) node
  where node->>'requirementKey' = 'destination'
  limit 1;

  select
    coalesce((node->>'satisfied')::boolean, false),
    coalesce(node->'evidence', '{}'::jsonb)
  into v_seed_ready, v_seed
  from jsonb_array_elements(v_requirements) node
  where node->>'requirementKey' = 'seed'
  limit 1;

  select
    coalesce((node->>'satisfied')::boolean, false),
    coalesce(node->'evidence', '{}'::jsonb)
  into v_state_gate_clear, v_state_gate
  from jsonb_array_elements(v_requirements) node
  where node->>'requirementKey' = 'state_consequence'
  limit 1;

  v_prereq := coalesce(v_prereq, false);
  v_resources := coalesce(v_resources, false);
  v_destination_ready := coalesce(v_destination_ready, false);
  v_seed_ready := coalesce(v_seed_ready, false);
  v_state_gate_clear := coalesce(v_state_gate_clear, false);
  v_destination := coalesce(v_destination, '{}'::jsonb);
  v_seed := coalesce(v_seed, '{}'::jsonb);
  v_state_gate := coalesce(v_state_gate, '{}'::jsonb);

  return jsonb_build_object(
    'contractVersion','task_execution_warrant_v1',
    'contractRole','execution_warrant',
    'taskId',p_task_id,
    'ready',v_ready,
    'executionReady',v_ready,
    'prerequisitesReady',v_prereq,
    'resourcesReady',v_resources,
    'destinationReady',v_destination_ready,
    'seedReady',v_seed_ready,
    'stateConsequenceClear',v_state_gate_clear,
    'preparationRequired',coalesce((v_state_gate->>'preparationRequired')::boolean,false),
    'destination',v_destination,
    'seed',v_seed,
    'stateConsequenceGate',v_state_gate,
    'truthBoundary',jsonb_build_object(
      'requirementAuthority',false,
      'compatibilityProjection',true,
      'canonicalEvaluation','task_execution_requirement_evaluation_v1',
      'requirementExistenceNotInferredFromReady',true,
      'notReadyDoesNotMeanNotRequired',true,
      'thisContractOnlyAnswersWhetherRepresentedTaskMayExecuteNow',true
    )
  );
end;
$function$;

revoke execute on function atlas.task_execution_requirement_evaluation_v1(uuid)
from public, anon, authenticated;
grant execute on function atlas.task_execution_requirement_evaluation_v1(uuid)
to service_role;

revoke execute on function atlas.task_execution_readiness_v1(uuid)
from public, anon, authenticated;
grant execute on function atlas.task_execution_readiness_v1(uuid)
to service_role;

comment on function atlas.task_execution_requirement_evaluation_v1(uuid) is
  'Canonical read-only State Progression evaluation for whether the represented task may execute now. Domain evidence remains owned by its prerequisite/resource/destination/seed/state-consequence providers.';

comment on function atlas.task_execution_readiness_v1(uuid) is
  'Compatibility projection of atlas.task_execution_requirement_evaluation_v1. It preserves the legacy execution-warrant JSON shape without independently recomputing readiness.';
