-- Atlas Person Consequence Evidence Authority v1
--
-- Closes the person-owned State Consequence authority leak. A caller may no
-- longer submit arbitrary snapshot + policy JSON and thereby establish a
-- consequence. Person Consequence definitions must be sourced by an accepted
-- consequence_policy Claim/Evidence envelope, and evaluations consume a real
-- current Evidence record by id. The database reconstructs both the snapshot
-- and the authorized policy set before any consequence instance can open.
--
-- This migration does not diagnose, prescribe, create Tasks, choose a Clock
-- placement, or silently turn an observation into a rule.

begin;

-- This seam has not yet carried production person data. If another writer starts
-- using it before this release lands, adjudicate those rows instead of silently
-- blessing their previous caller-supplied policy authority.
do $$
begin
  if exists (
    select 1 from atlas.person_life_definitions d where d.signal_kind='consequence'
  ) or exists (
    select 1
    from atlas.person_life_state_events e
    join atlas.person_life_definitions d on d.id=e.definition_id
    where d.signal_kind='consequence'
  ) or exists (
    select 1 from atlas.person_life_consequence_instances
  ) then
    raise exception 'Person Consequence rows appeared before evidence-authority cutover; adjudicate them explicitly before release.';
  end if;
end
$$;

-- Compile explicit consequence policies from consequence requirements. Missing
-- policy objects remain visible as unresolved policy authority; this adapter
-- never invents a rule from labels, entryCondition prose, or operation names.
create or replace function atlas.life_signal_to_consequence_packet_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_validation jsonb;
  v_requirement jsonb;
  v_requirements jsonb;
  v_packets jsonb := '[]'::jsonb;
  v_policies jsonb := '[]'::jsonb;
  v_policy_gaps jsonb := '[]'::jsonb;
  v_policy jsonb;
  v_selector jsonb;
  v_state_match jsonb;
  v_action_spec jsonb;
  v_role text;
  v_policy_role text;
  v_key text;
  v_policy_key text;
  v_operation text;
  v_carrier text;
  v_index integer := 0;
  v_subject_ref text;
  v_priority integer;
begin
  v_validation := atlas.validate_life_signal_v1(p_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  if p_signal->>'signalKind' <> 'consequence' then
    raise exception 'Consequence packet requires signalKind=consequence.' using errcode='22023';
  end if;

  v_requirements := coalesce(p_signal->'requirements','[]'::jsonb);
  if jsonb_typeof(v_requirements)<>'array' then
    raise exception 'Consequence requirements must be an array.' using errcode='22023';
  end if;

  v_subject_ref := concat_ws(':',
    p_signal->'subject'->>'domain',
    p_signal->'subject'->>'kind',
    p_signal->'subject'->>'id'
  );

  for v_requirement in
    select value from jsonb_array_elements(v_requirements)
  loop
    v_index := v_index + 1;
    v_role := coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind');

    if v_role <> all(array['operation_requirement','truth_acquisition','repair','preparation']) then
      raise exception 'Unsupported consequence requirement role: %', v_role using errcode='22023';
    end if;

    v_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');
    if v_key is null then
      v_key := v_subject_ref || ':consequence:' || v_index::text;
    end if;

    v_operation := nullif(btrim(coalesce(v_requirement->>'operationKey',v_requirement->>'operation_key','')),'');
    v_carrier := nullif(btrim(coalesce(v_requirement->>'carrierRef',v_requirement->>'carrier_ref','')),'');

    v_packets := v_packets || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'requirementKey',v_key,
      'consequenceRole',v_role,
      'requirementState','established',
      'operationKey',v_operation,
      'operationState',case when v_operation is null then 'unresolved' else 'established' end,
      'carrierRef',v_carrier,
      'carrierState',case when v_carrier is null then 'unresolved' else 'established' end,
      'placementState','unresolved',
      'executionReadiness','not_evaluated',
      'entryCondition',nullif(v_requirement->>'entryCondition',''),
      'exitCondition',nullif(v_requirement->>'exitCondition',''),
      'expectedAfterState',coalesce(v_requirement->'expectedAfterState',v_requirement->'expected_after_state'),
      'blocker',nullif(v_requirement->>'blocker',''),
      'policyState',case when jsonb_typeof(v_requirement->'policy')='object' then 'explicit' else 'unresolved' end,
      'sourceRequirement',v_requirement
    )));

    v_policy := v_requirement->'policy';
    if v_policy is null or jsonb_typeof(v_policy)<>'object' then
      v_policy_gaps := v_policy_gaps || jsonb_build_array(jsonb_build_object(
        'requirementKey',v_key,
        'reason','explicit_policy_missing'
      ));
      continue;
    end if;

    v_selector := coalesce(v_policy->'subjectSelector',v_policy->'subject_selector');
    v_state_match := coalesce(v_policy->'stateMatch',v_policy->'state_match');
    v_action_spec := coalesce(v_policy->'actionSpec',v_policy->'action_spec','{}'::jsonb);
    if jsonb_typeof(v_selector)<>'object' or jsonb_typeof(v_state_match)<>'object' then
      raise exception 'Consequence requirement % policy requires object subjectSelector and stateMatch.',v_key using errcode='22023';
    end if;
    if jsonb_typeof(v_action_spec)<>'object' then
      raise exception 'Consequence requirement % policy actionSpec must be an object.',v_key using errcode='22023';
    end if;

    v_policy_key := coalesce(
      nullif(btrim(v_policy->>'stableKey'),''),
      nullif(btrim(v_policy->>'stable_key'),''),
      v_key
    );
    v_policy_role := coalesce(
      nullif(btrim(v_policy->>'consequenceRole'),''),
      nullif(btrim(v_policy->>'consequence_role'),''),
      v_role
    );
    if v_policy_role is distinct from v_role then
      raise exception 'Consequence requirement % policy role must match requirementKind.',v_key using errcode='22023';
    end if;

    begin
      v_priority := coalesce(nullif(v_policy->>'priority','')::integer,100);
    exception when invalid_text_representation then
      raise exception 'Consequence requirement % policy priority must be an integer.',v_key using errcode='22023';
    end;

    v_policies := v_policies || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'stableKey',v_policy_key,
      'active',case when v_policy ? 'active' then v_policy->'active' else 'true'::jsonb end,
      'subjectSelector',v_selector,
      'stateMatch',v_state_match,
      'consequenceRole',v_role,
      'consequenceKind',coalesce(v_policy->>'consequenceKind',v_policy->>'consequence_kind'),
      'actionKey',coalesce(v_policy->>'actionKey',v_policy->>'action_key',v_operation),
      'priority',v_priority,
      'actionSpec',v_action_spec,
      'metadata',coalesce(v_policy->'metadata','{}'::jsonb) || jsonb_build_object('requirementKey',v_key)
    )));
  end loop;

  return jsonb_build_object(
    'contractVersion','life_consequence_packet_v1',
    'scope',p_signal->'scope',
    'subject',p_signal->'subject',
    'source',p_signal->'source',
    'epistemic',p_signal->'epistemic',
    'presentState',coalesce(p_signal->'state','{}'::jsonb),
    'timing',coalesce(p_signal->'timing','{}'::jsonb),
    'requirements',v_packets,
    'policies',v_policies,
    'policyState',case when jsonb_array_length(v_policy_gaps)=0 and jsonb_array_length(v_policies)>0 then 'explicit' else 'unresolved' end,
    'policyGaps',v_policy_gaps,
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'requirementAuthority','supplied_domain_evidence_only',
      'policyAuthority','explicit_policy_objects_only',
      'missingPolicyIsNotInferred',true,
      'requirementExistenceNotInferredFromReadiness',true,
      'notReadyDoesNotMeanNotRequired',true,
      'requirementDoesNotSelectCarrier',true,
      'carrierDoesNotSelectPlacement',true,
      'capabilityHoldMayBlockExecutionWithoutDeletingObligation',true,
      'taskGenerationAuthority',false,
      'executionReadinessAuthority',false,
      'clockPlacementAuthority',false,
      'domainEvidenceRemainsAuthoritative',true
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.life_signal_to_consequence_packet_v1',
      'lifeSignalContract','atlas_life_signal_v1',
      'taskExecutionAuthorityPrecedent','atlas.task_execution_requirement_evaluation_v1'
    )
  );
end;
$$;

comment on function atlas.life_signal_to_consequence_packet_v1(jsonb) is
  'Pure State Consequence compatibility packet. Explicit requirement.policy objects compile to matcher policies; missing policy authority remains unresolved. Requirement, carrier, execution readiness, and Clock placement remain separate authorities.';

revoke all on function atlas.life_signal_to_consequence_packet_v1(jsonb) from public, anon, authenticated;
grant execute on function atlas.life_signal_to_consequence_packet_v1(jsonb) to postgres;

-- Person-owned consequence definitions require an exact accepted policy Claim.
-- The claim value is the policy-bearing portion of the Life Signal, so a caller
-- cannot accept one rule and persist a different executable rule.
create or replace function atlas.guard_person_consequence_definition_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_claim_id uuid;
  v_claim_scope_kind text;
  v_claim_scope_id uuid;
  v_claim_domain text;
  v_claim_subject_kind text;
  v_claim_subject_id text;
  v_claim_type text;
  v_claim_state text;
  v_claim_authority text;
  v_claim_value jsonb;
  v_primary_evidence_id uuid;
  v_evidence_scope_kind text;
  v_evidence_scope_id uuid;
  v_expected_claim_value jsonb;
begin
  if new.signal_kind<>'consequence' then
    return new;
  end if;

  if new.source_domain<>'claim_evidence' or new.source_kind<>'claim' then
    raise exception 'Person Consequence definitions must be sourced by an accepted consequence_policy Claim.' using errcode='23514';
  end if;
  begin
    v_claim_id := new.source_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Person Consequence source.id must be the authorizing claim UUID.' using errcode='22023';
  end;

  select c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id,
         c.claim_type,c.lifecycle_state,c.authority_kind,c.value,c.primary_evidence_id
  into v_claim_scope_kind,v_claim_scope_id,v_claim_domain,v_claim_subject_kind,v_claim_subject_id,
       v_claim_type,v_claim_state,v_claim_authority,v_claim_value,v_primary_evidence_id
  from atlas.claim_records c
  where c.id=v_claim_id;

  if v_claim_scope_kind is null
     or v_claim_scope_kind<>'person'
     or v_claim_scope_id is distinct from new.owner_user_id then
    raise exception 'Consequence policy Claim must remain in the same person custody.' using errcode='23514';
  end if;
  if v_claim_domain is distinct from new.subject_domain
     or v_claim_subject_kind is distinct from new.subject_kind
     or v_claim_subject_id is distinct from new.subject_id then
    raise exception 'Consequence policy Claim must describe the Consequence definition subject.' using errcode='23514';
  end if;
  if v_claim_type<>'consequence_policy'
     or v_claim_state<>'accepted'
     or v_claim_authority<>'person_acceptance' then
    raise exception 'Person Consequence definitions require a current person-accepted consequence_policy Claim.' using errcode='23514';
  end if;

  select e.scope_kind,e.scope_id
  into v_evidence_scope_kind,v_evidence_scope_id
  from atlas.evidence_records e
  where e.id=v_primary_evidence_id;
  if v_evidence_scope_kind<>'person' or v_evidence_scope_id is distinct from new.owner_user_id then
    raise exception 'Consequence policy primary Evidence must remain in the same person custody.' using errcode='23514';
  end if;

  v_expected_claim_value := jsonb_build_object(
    'signalKind','consequence',
    'subject',new.life_signal->'subject',
    'requirements',coalesce(new.life_signal->'requirements','[]'::jsonb)
  );
  if v_claim_value is distinct from v_expected_claim_value then
    raise exception 'Accepted consequence_policy Claim must exactly preserve this definition subject and requirements.' using errcode='23514';
  end if;

  if new.engine_packet->>'policyState'<>'explicit'
     or jsonb_typeof(new.engine_packet->'policies')<>'array'
     or jsonb_array_length(new.engine_packet->'policies')=0
     or jsonb_array_length(new.engine_packet->'policyGaps')<>0 then
    raise exception 'Person Consequence definition requires a complete explicit policy set; missing rules remain unresolved rather than inferred.' using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_person_consequence_definition_authority_v1() is
  'Requires each person Consequence definition to reproduce an exact current accepted consequence_policy Claim/Evidence source and a complete explicit policy set.';

revoke all on function atlas.guard_person_consequence_definition_authority_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_consequence_definition_authority_v1() to service_role;

create trigger person_consequence_definition_authority_guard_v1
before insert or update on atlas.person_life_definitions
for each row execute function atlas.guard_person_consequence_definition_authority_v1();

-- Canonical evidence -> snapshot reconstruction. This is intentionally internal:
-- the signed-in evaluator accepts an evidence id and cannot submit snapshot JSON.
create or replace function atlas.person_consequence_evidence_snapshot_v1(
  p_owner_user_id uuid,
  p_evidence_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_evidence atlas.evidence_records%rowtype;
  v_claim atlas.claim_records%rowtype;
begin
  select * into v_evidence
  from atlas.evidence_records e
  where e.id=p_evidence_id
    and e.scope_kind='person'
    and e.scope_id=p_owner_user_id;
  if v_evidence.id is null then
    raise exception 'Evidence must belong to this person.' using errcode='42501';
  end if;

  select * into v_claim
  from atlas.claim_records c
  where c.primary_evidence_id=v_evidence.id
    and c.scope_kind='person'
    and c.scope_id=p_owner_user_id
    and c.lifecycle_state not in ('superseded','rejected','expired')
    and (c.valid_from is null or c.valid_from<=coalesce(v_evidence.observed_at,v_evidence.learned_at))
    and (c.valid_until is null or c.valid_until>=coalesce(v_evidence.observed_at,v_evidence.learned_at))
  order by c.recorded_at desc,c.id desc
  limit 1;

  if v_claim.id is null then
    raise exception 'Evidence has no current person Claim and cannot drive a Consequence.' using errcode='23514';
  end if;

  return jsonb_build_object(
    'scope',jsonb_build_object('kind','person','id',p_owner_user_id),
    'subject',jsonb_build_object('domain',v_evidence.subject_domain,'kind',v_evidence.subject_kind,'id',v_evidence.subject_id),
    'evidence',jsonb_strip_nulls(jsonb_build_object(
      'id',v_evidence.id,
      'kind',v_evidence.evidence_kind,
      'value',v_evidence.value,
      'observedAt',v_evidence.observed_at,
      'learnedAt',v_evidence.learned_at,
      'effectiveFrom',v_evidence.effective_from,
      'effectiveUntil',v_evidence.effective_until
    )),
    'claim',jsonb_strip_nulls(jsonb_build_object(
      'id',v_claim.id,
      'claimType',v_claim.claim_type,
      'lifecycleState',v_claim.lifecycle_state,
      'authorityKind',v_claim.authority_kind,
      'value',v_claim.value,
      'validFrom',v_claim.valid_from,
      'validUntil',v_claim.valid_until
    ))
  );
end;
$$;

comment on function atlas.person_consequence_evidence_snapshot_v1(uuid,uuid) is
  'Internal canonical snapshot builder for person consequences. It accepts only person-owned Evidence with a current Claim; callers cannot supply state JSON.';

revoke all on function atlas.person_consequence_evidence_snapshot_v1(uuid,uuid) from public, anon, authenticated;
grant execute on function atlas.person_consequence_evidence_snapshot_v1(uuid,uuid) to service_role;

-- Recompute and verify every consequence evaluation event. This also seals the
-- legacy generic state RPC: its old consequence branch contains snapshot/policies
-- in input_payload and will now be rejected at the persistence boundary.
create or replace function atlas.guard_person_consequence_evaluation_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_owner uuid;
  v_kind text;
  v_status text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_packet jsonb;
  v_evidence_id uuid;
  v_policy_claim_id uuid;
  v_observation_claim_id uuid;
  v_snapshot jsonb;
  v_policies jsonb;
  v_expected_evaluation jsonb;
  v_expected_evidence jsonb;
  v_evidence_time timestamptz;
  v_policy_type text;
  v_policy_state text;
  v_policy_authority text;
  v_policy_primary_evidence_id uuid;
begin
  if new.event_kind<>'consequence_evaluation' then
    return new;
  end if;

  select d.owner_user_id,d.signal_kind,d.status,d.source_domain,d.source_kind,d.source_id,d.engine_packet
  into v_owner,v_kind,v_status,v_source_domain,v_source_kind,v_source_id,v_packet
  from atlas.person_life_definitions d
  where d.id=new.definition_id;

  if v_owner is null or v_owner is distinct from new.owner_user_id or v_kind<>'consequence' or v_status<>'active' then
    raise exception 'Consequence evaluation requires the active same-owner Consequence definition.' using errcode='23514';
  end if;
  if new.input_payload ? 'snapshot' or new.input_payload ? 'policies' then
    raise exception 'Person Consequence evaluation cannot accept caller-supplied snapshot or policies; submit evidenceId instead.' using errcode='23514';
  end if;

  begin
    v_evidence_id := nullif(new.input_payload->>'evidenceId','')::uuid;
    v_policy_claim_id := nullif(new.input_payload->>'policyClaimId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'Consequence evidenceId and policyClaimId must be UUIDs.' using errcode='22023';
  end;
  if v_evidence_id is null or v_policy_claim_id is null then
    raise exception 'Consequence evaluation requires evidenceId and policyClaimId.' using errcode='22023';
  end if;
  if v_source_domain<>'claim_evidence' or v_source_kind<>'claim' or v_source_id is distinct from v_policy_claim_id::text then
    raise exception 'Consequence evaluation policyClaimId must be the definition authorizing Claim.' using errcode='23514';
  end if;

  select c.claim_type,c.lifecycle_state,c.authority_kind,c.primary_evidence_id
  into v_policy_type,v_policy_state,v_policy_authority,v_policy_primary_evidence_id
  from atlas.claim_records c
  where c.id=v_policy_claim_id
    and c.scope_kind='person'
    and c.scope_id=new.owner_user_id;
  if v_policy_type<>'consequence_policy' or v_policy_state<>'accepted' or v_policy_authority<>'person_acceptance' then
    raise exception 'Consequence policy Claim is no longer current accepted authority.' using errcode='23514';
  end if;

  select coalesce(e.observed_at,e.learned_at) into v_evidence_time
  from atlas.evidence_records e
  where e.id=v_evidence_id
    and e.scope_kind='person'
    and e.scope_id=new.owner_user_id;
  if v_evidence_time is null then
    raise exception 'Consequence Evidence must belong to this person.' using errcode='42501';
  end if;
  if new.occurred_at is distinct from v_evidence_time then
    raise exception 'Consequence evaluation occurred_at must be the canonical Evidence observation/learning time.' using errcode='23514';
  end if;

  v_snapshot := atlas.person_consequence_evidence_snapshot_v1(new.owner_user_id,v_evidence_id);
  v_observation_claim_id := (v_snapshot->'claim'->>'id')::uuid;
  v_policies := v_packet->'policies';
  if jsonb_typeof(v_policies)<>'array' or jsonb_array_length(v_policies)=0 then
    raise exception 'Consequence definition has no authorized executable policy set.' using errcode='23514';
  end if;

  v_expected_evaluation := atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
  if new.evaluation is distinct from v_expected_evaluation then
    raise exception 'Consequence evaluation must be database-recomputed from canonical Evidence and authorized policies.' using errcode='23514';
  end if;

  v_expected_evidence := jsonb_build_object(
    'evidenceId',v_evidence_id,
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'policyPrimaryEvidenceId',v_policy_primary_evidence_id,
    'snapshot',v_snapshot,
    'policySet',v_policies,
    'authority',jsonb_build_object(
      'policyAuthorityKind',v_policy_authority,
      'policyClaimType',v_policy_type,
      'policyClaimLifecycle',v_policy_state,
      'ruleIsSeparateFromObservation',true
    )
  );
  if new.evidence is distinct from v_expected_evidence then
    raise exception 'Consequence event Evidence envelope must preserve exact observation and policy provenance.' using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_person_consequence_evaluation_authority_v1() is
  'Persistence guard for person consequence evaluations. Reconstructs the Evidence snapshot, verifies accepted policy Claim authority, recomputes the evaluator output, and blocks caller-supplied policy JSON.';

revoke all on function atlas.guard_person_consequence_evaluation_authority_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_consequence_evaluation_authority_v1() to service_role;

create trigger person_consequence_evaluation_authority_guard_v1
before insert or update on atlas.person_life_state_events
for each row execute function atlas.guard_person_consequence_evaluation_authority_v1();

create or replace function atlas.guard_person_consequence_instance_authority_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_open_owner uuid;
  v_open_definition uuid;
  v_open_kind text;
  v_last_owner uuid;
  v_last_definition uuid;
  v_last_kind text;
begin
  select e.owner_user_id,e.definition_id,e.event_kind
  into v_open_owner,v_open_definition,v_open_kind
  from atlas.person_life_state_events e where e.id=new.opened_by_event_id;
  select e.owner_user_id,e.definition_id,e.event_kind
  into v_last_owner,v_last_definition,v_last_kind
  from atlas.person_life_state_events e where e.id=new.last_seen_event_id;

  if v_open_owner is distinct from new.owner_user_id
     or v_open_definition is distinct from new.definition_id
     or v_open_kind<>'consequence_evaluation'
     or v_last_owner is distinct from new.owner_user_id
     or v_last_definition is distinct from new.definition_id
     or v_last_kind<>'consequence_evaluation' then
    raise exception 'Consequence instance must be opened and refreshed by authorized same-definition consequence evaluation events.' using errcode='23514';
  end if;
  return new;
end;
$$;

revoke all on function atlas.guard_person_consequence_instance_authority_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_consequence_instance_authority_v1() to service_role;

create trigger person_consequence_instance_authority_guard_v1
before insert or update on atlas.person_life_consequence_instances
for each row execute function atlas.guard_person_consequence_instance_authority_v1();

create or replace function atlas.evaluate_person_consequence_from_evidence_api_v1(
  p_definition_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_evidence_id uuid;
  v_policy_claim_id uuid;
  v_packet jsonb;
  v_definition_source_id text;
  v_snapshot jsonb;
  v_observation_claim_id uuid;
  v_policy_type text;
  v_policy_state text;
  v_policy_authority text;
  v_policy_primary_evidence_id uuid;
  v_policies jsonb;
  v_evaluation jsonb;
  v_occurred_at timestamptz;
  v_event_evidence jsonb;
  v_event_payload jsonb;
  v_event_id uuid;
  v_existing_definition_id uuid;
  v_existing_payload jsonb;
  v_existing_evaluation jsonb;
  v_existing_evidence jsonb;
  v_existing_occurred_at timestamptz;
  v_consequence jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  begin
    v_evidence_id := nullif(p_payload->>'evidenceId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'evidenceId must be a UUID.' using errcode='22023';
  end;
  if v_source_key='' or v_evidence_id is null then
    raise exception 'sourceKey and evidenceId are required.' using errcode='22023';
  end if;
  if p_payload ? 'snapshot' or p_payload ? 'policies' then
    raise exception 'snapshot and policies are not accepted; Atlas reconstructs them from custody.' using errcode='22023';
  end if;

  select d.engine_packet,d.source_id
  into v_packet,v_definition_source_id
  from atlas.person_life_definitions d
  where d.id=p_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='consequence'
    and d.status='active'
    and d.source_domain='claim_evidence'
    and d.source_kind='claim';
  if v_packet is null then
    raise exception 'Active authorized person Consequence definition not found.' using errcode='42501';
  end if;
  begin
    v_policy_claim_id := v_definition_source_id::uuid;
  exception when invalid_text_representation then
    raise exception 'Stored Consequence definition policy Claim id is invalid.' using errcode='23514';
  end;

  select c.claim_type,c.lifecycle_state,c.authority_kind,c.primary_evidence_id
  into v_policy_type,v_policy_state,v_policy_authority,v_policy_primary_evidence_id
  from atlas.claim_records c
  where c.id=v_policy_claim_id
    and c.scope_kind='person'
    and c.scope_id=v_user_id;
  if v_policy_type<>'consequence_policy' or v_policy_state<>'accepted' or v_policy_authority<>'person_acceptance' then
    raise exception 'Consequence definition policy Claim is no longer accepted authority.' using errcode='23514';
  end if;

  v_snapshot := atlas.person_consequence_evidence_snapshot_v1(v_user_id,v_evidence_id);
  v_observation_claim_id := (v_snapshot->'claim'->>'id')::uuid;
  select coalesce(e.observed_at,e.learned_at) into v_occurred_at
  from atlas.evidence_records e where e.id=v_evidence_id;
  v_policies := v_packet->'policies';
  if jsonb_typeof(v_policies)<>'array' or jsonb_array_length(v_policies)=0 then
    raise exception 'Consequence definition has no authorized executable policy set.' using errcode='23514';
  end if;

  v_evaluation := atlas.evaluate_life_state_consequence_policies_v1(v_snapshot,v_policies);
  v_event_payload := jsonb_build_object(
    'sourceKey',v_source_key,
    'eventKind','consequence_evaluation',
    'evidenceId',v_evidence_id,
    'policyClaimId',v_policy_claim_id
  );
  v_event_evidence := jsonb_build_object(
    'evidenceId',v_evidence_id,
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'policyPrimaryEvidenceId',v_policy_primary_evidence_id,
    'snapshot',v_snapshot,
    'policySet',v_policies,
    'authority',jsonb_build_object(
      'policyAuthorityKind',v_policy_authority,
      'policyClaimType',v_policy_type,
      'policyClaimLifecycle',v_policy_state,
      'ruleIsSeparateFromObservation',true
    )
  );

  select e.id,e.definition_id,e.input_payload,e.evaluation,e.evidence,e.occurred_at
  into v_event_id,v_existing_definition_id,v_existing_payload,v_existing_evaluation,v_existing_evidence,v_existing_occurred_at
  from atlas.person_life_state_events e
  where e.owner_user_id=v_user_id and e.source_key=v_source_key;

  if v_event_id is not null then
    if v_existing_definition_id is distinct from p_definition_id
       or v_existing_payload is distinct from v_event_payload
       or v_existing_evaluation is distinct from v_evaluation
       or v_existing_evidence is distinct from v_event_evidence
       or v_existing_occurred_at is distinct from v_occurred_at then
      raise exception 'sourceKey retry does not match existing consequence evaluation.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'replayed',true,'eventId',v_event_id,'definitionId',p_definition_id,
      'evidenceId',v_evidence_id,'policyClaimId',v_policy_claim_id,
      'occurredAt',v_occurred_at,'evaluation',v_evaluation
    );
  end if;

  insert into atlas.person_life_state_events(
    definition_id,owner_user_id,event_kind,source_key,occurred_at,input_payload,evidence,evaluation
  ) values (
    p_definition_id,v_user_id,'consequence_evaluation',v_source_key,v_occurred_at,
    v_event_payload,v_event_evidence,v_evaluation
  ) returning id into v_event_id;

  for v_consequence in select value from jsonb_array_elements(coalesce(v_evaluation->'openConsequences','[]'::jsonb)) loop
    insert into atlas.person_life_consequence_instances(
      definition_id,owner_user_id,stable_key,consequence_role,consequence_kind,action_key,
      requirement_state,carrier_ref,carrier_state,placement_state,execution_readiness,
      action_spec,evidence,opened_by_event_id,last_seen_event_id,status,opened_at
    ) values (
      p_definition_id,v_user_id,v_consequence->>'stableKey',v_consequence->>'consequenceRole',
      nullif(v_consequence->>'consequenceKind',''),nullif(v_consequence->>'actionKey',''),
      coalesce(nullif(v_consequence->>'requirementState',''),'established'),nullif(v_consequence->>'carrierRef',''),
      coalesce(nullif(v_consequence->>'carrierState',''),'unresolved'),coalesce(nullif(v_consequence->>'placementState',''),'unresolved'),
      coalesce(nullif(v_consequence->>'executionReadiness',''),'not_evaluated'),
      coalesce(v_consequence->'actionSpec','{}'::jsonb),
      coalesce(v_consequence->'evidence','{}'::jsonb) || jsonb_build_object(
        'sourceEventId',v_event_id,
        'evidenceId',v_evidence_id,
        'observationClaimId',v_observation_claim_id,
        'policyClaimId',v_policy_claim_id,
        'policyPrimaryEvidenceId',v_policy_primary_evidence_id
      ),
      v_event_id,v_event_id,'open',v_occurred_at
    )
    on conflict (definition_id,stable_key) do update set
      consequence_role=excluded.consequence_role,
      consequence_kind=excluded.consequence_kind,
      action_key=excluded.action_key,
      requirement_state=excluded.requirement_state,
      carrier_ref=excluded.carrier_ref,
      carrier_state=excluded.carrier_state,
      placement_state=excluded.placement_state,
      execution_readiness=excluded.execution_readiness,
      action_spec=excluded.action_spec,
      evidence=excluded.evidence,
      opened_by_event_id=case when atlas.person_life_consequence_instances.status='resolved' then excluded.opened_by_event_id else atlas.person_life_consequence_instances.opened_by_event_id end,
      last_seen_event_id=excluded.last_seen_event_id,
      status='open',
      opened_at=case when atlas.person_life_consequence_instances.status='resolved' then excluded.opened_at else atlas.person_life_consequence_instances.opened_at end,
      resolved_by_event_id=null,
      resolved_at=null,
      updated_at=now();
  end loop;

  return jsonb_build_object(
    'ok',true,
    'replayed',false,
    'eventId',v_event_id,
    'definitionId',p_definition_id,
    'evidenceId',v_evidence_id,
    'observationClaimId',v_observation_claim_id,
    'policyClaimId',v_policy_claim_id,
    'occurredAt',v_occurred_at,
    'evaluation',v_evaluation,
    'truthBoundary',jsonb_build_object(
      'observationAndRuleRemainSeparate',true,
      'snapshotBuiltFromCanonicalEvidence',true,
      'policyLoadedFromAcceptedClaim',true,
      'callerCannotSupplyPolicy',true,
      'doesNotDiagnose',true,
      'doesNotCreateTask',true,
      'doesNotSelectCarrierUnlessPolicyExplicitlyDid',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.evaluate_person_consequence_from_evidence_api_v1(uuid,jsonb) is
  'Evaluate an active person Consequence definition from one current person Evidence record. Snapshot and policies are reconstructed under database custody; caller-supplied rule JSON is rejected.';

revoke all on function atlas.evaluate_person_consequence_from_evidence_api_v1(uuid,jsonb) from public, anon;
grant execute on function atlas.evaluate_person_consequence_from_evidence_api_v1(uuid,jsonb) to authenticated, service_role;

-- Keep the older generic state endpoint for Goal/Rhythm and explicit consequence
-- resolution, but document that consequence evaluation authority moved here.
comment on function atlas.record_person_life_state_api_v1(uuid,jsonb) is
  'First-party state writer for person Goal/Rhythm plus explicit Consequence resolution. Caller-supplied Consequence evaluation is rejected by the persistence guard; use evaluate_person_consequence_from_evidence_api_v1 for evidence-driven Consequence evaluation.';

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values (
  'atlas.evaluate_person_consequence_from_evidence_api_v1(uuid,jsonb)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Evaluate person State Consequence policies from one canonical Evidence record under an exact accepted policy Claim.',
    'authorizationBoundary','SECURITY DEFINER fixes person custody to auth.uid(); snapshot is reconstructed from current Claim/Evidence and policy set is loaded from the definition accepted consequence_policy Claim. Callers cannot submit snapshot or policy JSON.',
    'directSignedInEndpoint',true
  ),now(),false
)
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

update atlas.authenticated_rpc_registry
set evidence = coalesce(evidence,'{}'::jsonb) || jsonb_build_object(
      'consequenceEvaluationBoundary','Caller-supplied consequence snapshot/policies are rejected after 20260831213000; evidence-driven evaluation is routed through atlas.evaluate_person_consequence_from_evidence_api_v1(uuid,jsonb).'
    ),
    reviewed_at=now()
where signature='atlas.record_person_life_state_api_v1(uuid,jsonb)';

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry drifted after person Consequence evidence-authority cutover.';
  end if;
end
$$;

commit;
