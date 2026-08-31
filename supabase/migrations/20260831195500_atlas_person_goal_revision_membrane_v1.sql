-- Atlas Person Goal Revision Membrane v1
--
-- Turns an explicitly accepted first-party Goal requirement claim into a new,
-- immutable Goal definition version. The prior Goal definition is retired rather
-- than rewritten, and a durable receipt preserves the exact claim/evidence that
-- authorized the revision.
--
-- This membrane does not infer requirements from Goal prose, customary domain
-- practice, observations, or model output. It creates no Task, carrier, readiness
-- state, consequence, Journal entry, or Clock placement.

begin;

create table atlas.person_life_definition_revisions (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  source_key text not null check (btrim(source_key) <> ''),
  previous_definition_id uuid not null references atlas.person_life_definitions(id) on delete restrict,
  revised_definition_id uuid not null references atlas.person_life_definitions(id) on delete restrict,
  authorization_claim_id uuid not null references atlas.claim_records(id) on delete restrict,
  authorization_evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  requirement_key text not null check (btrim(requirement_key) <> ''),
  claimed_requirement jsonb not null,
  applied_requirement jsonb not null,
  authorization_basis text not null check (btrim(authorization_basis) <> ''),
  authorization_reason text not null check (btrim(authorization_reason) <> ''),
  created_at timestamptz not null default now(),
  check (previous_definition_id <> revised_definition_id),
  unique (owner_user_id, source_key),
  unique (previous_definition_id),
  unique (revised_definition_id)
);

comment on table atlas.person_life_definition_revisions is
  'Immutable lineage receipt for person-owned Life definition revisions. v1 admits only Goal requirement revisions authorized by a current person-accepted goal_requirement claim.';

create index person_life_definition_revisions_owner_time_idx
  on atlas.person_life_definition_revisions(owner_user_id, created_at desc, id);
create index person_life_definition_revisions_claim_idx
  on atlas.person_life_definition_revisions(authorization_claim_id, revised_definition_id);

create or replace function atlas.guard_person_life_definition_revision_custody_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, atlas
as $$
declare
  v_previous_owner uuid;
  v_previous_kind text;
  v_previous_status text;
  v_previous_domain text;
  v_previous_subject_kind text;
  v_previous_subject_id text;
  v_revised_owner uuid;
  v_revised_kind text;
  v_revised_status text;
  v_revised_domain text;
  v_revised_subject_kind text;
  v_revised_subject_id text;
  v_claim_scope_kind text;
  v_claim_scope_id uuid;
  v_claim_domain text;
  v_claim_subject_kind text;
  v_claim_subject_id text;
  v_claim_type text;
  v_claim_state text;
  v_claim_authority text;
  v_claim_value jsonb;
  v_claim_evidence_id uuid;
  v_evidence_scope_kind text;
  v_evidence_scope_id uuid;
begin
  select d.owner_user_id,d.signal_kind,d.status,d.subject_domain,d.subject_kind,d.subject_id
  into v_previous_owner,v_previous_kind,v_previous_status,v_previous_domain,v_previous_subject_kind,v_previous_subject_id
  from atlas.person_life_definitions d
  where d.id=new.previous_definition_id;

  select d.owner_user_id,d.signal_kind,d.status,d.subject_domain,d.subject_kind,d.subject_id
  into v_revised_owner,v_revised_kind,v_revised_status,v_revised_domain,v_revised_subject_kind,v_revised_subject_id
  from atlas.person_life_definitions d
  where d.id=new.revised_definition_id;

  if v_previous_owner is null or v_revised_owner is null
     or v_previous_owner is distinct from new.owner_user_id
     or v_revised_owner is distinct from new.owner_user_id then
    raise exception 'Life definition revision custody must remain with one owner.' using errcode='23514';
  end if;

  if v_previous_kind <> 'goal' or v_revised_kind <> 'goal' then
    raise exception 'Person Life revision v1 supports Goal definitions only.' using errcode='23514';
  end if;

  if v_previous_status <> 'retired' or v_revised_status <> 'active' then
    raise exception 'A Goal revision receipt requires retired previous and active revised definitions.' using errcode='23514';
  end if;

  if v_previous_domain is distinct from v_revised_domain
     or v_previous_subject_kind is distinct from v_revised_subject_kind
     or v_previous_subject_id is distinct from v_revised_subject_id then
    raise exception 'Goal revision cannot change the Goal subject.' using errcode='23514';
  end if;

  select c.scope_kind,c.scope_id,c.subject_domain,c.subject_kind,c.subject_id,
         c.claim_type,c.lifecycle_state,c.authority_kind,c.value,c.primary_evidence_id
  into v_claim_scope_kind,v_claim_scope_id,v_claim_domain,v_claim_subject_kind,v_claim_subject_id,
       v_claim_type,v_claim_state,v_claim_authority,v_claim_value,v_claim_evidence_id
  from atlas.claim_records c
  where c.id=new.authorization_claim_id;

  if v_claim_scope_kind <> 'person'
     or v_claim_scope_id is distinct from new.owner_user_id
     or v_claim_domain is distinct from v_previous_domain
     or v_claim_subject_kind is distinct from v_previous_subject_kind
     or v_claim_subject_id is distinct from v_previous_subject_id then
    raise exception 'Goal revision authorization claim must share person custody and Goal subject.' using errcode='23514';
  end if;

  if v_claim_type <> 'goal_requirement'
     or v_claim_state <> 'accepted'
     or v_claim_authority <> 'person_acceptance' then
    raise exception 'Goal revision requires a current person-accepted goal_requirement claim.' using errcode='23514';
  end if;

  if v_claim_value is distinct from new.claimed_requirement then
    raise exception 'Revision receipt must preserve the exact accepted requirement claim value.' using errcode='23514';
  end if;

  if v_claim_evidence_id is distinct from new.authorization_evidence_id then
    raise exception 'Revision authorization evidence must be the claim primary evidence.' using errcode='23514';
  end if;

  select e.scope_kind,e.scope_id
  into v_evidence_scope_kind,v_evidence_scope_id
  from atlas.evidence_records e
  where e.id=new.authorization_evidence_id;

  if v_evidence_scope_kind <> 'person' or v_evidence_scope_id is distinct from new.owner_user_id then
    raise exception 'Goal revision authorization evidence must remain in person custody.' using errcode='23514';
  end if;

  if new.authorization_basis <> 'person_accepted_goal_requirement_claim' then
    raise exception 'Unsupported Goal revision authorization basis.' using errcode='23514';
  end if;

  return new;
end;
$$;

comment on function atlas.guard_person_life_definition_revision_custody_v1() is
  'Custody guard for immutable Goal revision receipts: same owner/subject, retired-to-active lineage, exact accepted claim value, and primary evidence authority are required.';

revoke all on function atlas.guard_person_life_definition_revision_custody_v1() from public, anon, authenticated;
grant execute on function atlas.guard_person_life_definition_revision_custody_v1() to service_role;

create trigger person_life_definition_revisions_custody_guard_v1
before insert on atlas.person_life_definition_revisions
for each row execute function atlas.guard_person_life_definition_revision_custody_v1();

alter table atlas.person_life_definition_revisions enable row level security;

create policy person_life_definition_revisions_self_read
on atlas.person_life_definition_revisions for select to authenticated
using (owner_user_id=auth.uid());

grant select on atlas.person_life_definition_revisions to authenticated;
grant select,insert on atlas.person_life_definition_revisions to service_role;

create or replace function atlas.revise_person_goal_from_accepted_requirement_api_v1(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user_id uuid;
  v_source_key text;
  v_previous_definition_id uuid;
  v_authorization_claim_id uuid;
  v_authorization_reason text;
  v_existing_revision_id uuid;
  v_existing_previous_definition_id uuid;
  v_existing_revised_definition_id uuid;
  v_existing_claim_id uuid;
  v_existing_reason text;
  v_existing_claimed_requirement jsonb;
  v_existing_applied_requirement jsonb;
  v_principal_id uuid;
  v_old_status text;
  v_old_signal jsonb;
  v_old_packet jsonb;
  v_old_metadata jsonb;
  v_subject_domain text;
  v_subject_kind text;
  v_subject_id text;
  v_source_domain text;
  v_source_kind text;
  v_source_id text;
  v_claim_type text;
  v_claim_state text;
  v_claim_authority text;
  v_claim_value jsonb;
  v_claim_evidence_id uuid;
  v_claim_recorded_at timestamptz;
  v_requirement_key text;
  v_requirement_kind text;
  v_requirement_phase text;
  v_requirements jsonb;
  v_applied_requirement jsonb;
  v_new_signal jsonb;
  v_validation jsonb;
  v_new_packet jsonb;
  v_initial_evaluation jsonb;
  v_new_metadata jsonb;
  v_new_definition_id uuid;
  v_revision_id uuid;
  v_retired integer;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'payload must be an object.' using errcode='22023';
  end if;

  v_source_key := btrim(coalesce(p_payload->>'sourceKey',''));
  v_previous_definition_id := nullif(p_payload->>'definitionId','')::uuid;
  v_authorization_claim_id := nullif(p_payload->>'acceptedRequirementClaimId','')::uuid;
  v_authorization_reason := btrim(coalesce(p_payload->>'reason',''));

  if v_source_key='' then raise exception 'sourceKey is required.' using errcode='22023'; end if;
  if v_previous_definition_id is null then raise exception 'definitionId is required.' using errcode='22023'; end if;
  if v_authorization_claim_id is null then raise exception 'acceptedRequirementClaimId is required.' using errcode='22023'; end if;
  if v_authorization_reason='' then raise exception 'reason is required.' using errcode='22023'; end if;

  select r.id,r.previous_definition_id,r.revised_definition_id,r.authorization_claim_id,
         r.authorization_reason,r.claimed_requirement,r.applied_requirement
  into v_existing_revision_id,v_existing_previous_definition_id,v_existing_revised_definition_id,v_existing_claim_id,
       v_existing_reason,v_existing_claimed_requirement,v_existing_applied_requirement
  from atlas.person_life_definition_revisions r
  where r.owner_user_id=v_user_id and r.source_key=v_source_key;

  if v_existing_revision_id is not null then
    if v_existing_previous_definition_id is distinct from v_previous_definition_id
       or v_existing_claim_id is distinct from v_authorization_claim_id
       or v_existing_reason is distinct from v_authorization_reason then
      raise exception 'sourceKey retry does not match existing Goal revision.' using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'created',false,
      'revisionId',v_existing_revision_id,
      'previousDefinitionId',v_existing_previous_definition_id,
      'definitionId',v_existing_revised_definition_id,
      'acceptedRequirementClaimId',v_existing_claim_id,
      'claimedRequirement',v_existing_claimed_requirement,
      'appliedRequirement',v_existing_applied_requirement,
      'authorizationBasis','person_accepted_goal_requirement_claim',
      'authorizationReason',v_existing_reason,
      'truthBoundary',jsonb_build_object(
        'historyPreserved',true,
        'requirementAuthorityComesFromAcceptedClaim',true,
        'goalLabelDoesNotInventRequirements',true,
        'doesNotEvaluateRequirementSatisfaction',true,
        'doesNotCreateTask',true,
        'doesNotSelectCarrier',true,
        'doesNotCreateClockPlacement',true
      )
    );
  end if;

  select d.principal_id,d.status,d.life_signal,d.engine_packet,d.metadata,
         d.subject_domain,d.subject_kind,d.subject_id,
         d.source_domain,d.source_kind,d.source_id
  into v_principal_id,v_old_status,v_old_signal,v_old_packet,v_old_metadata,
       v_subject_domain,v_subject_kind,v_subject_id,
       v_source_domain,v_source_kind,v_source_id
  from atlas.person_life_definitions d
  where d.id=v_previous_definition_id
    and d.owner_user_id=v_user_id
    and d.signal_kind='goal'
  for update;

  if v_principal_id is null then
    raise exception 'definitionId must identify this person own Goal definition.' using errcode='42501';
  end if;
  if v_old_status <> 'active' then
    raise exception 'Only the active Goal definition may be revised.' using errcode='23505';
  end if;

  if exists (
    select 1 from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id
      and d.signal_kind='goal'
      and d.source_key=v_source_key
  ) then
    raise exception 'sourceKey is already used by another person Goal definition.' using errcode='23505';
  end if;

  select c.claim_type,c.lifecycle_state,c.authority_kind,c.value,c.primary_evidence_id,c.recorded_at
  into v_claim_type,v_claim_state,v_claim_authority,v_claim_value,v_claim_evidence_id,v_claim_recorded_at
  from atlas.claim_records c
  where c.id=v_authorization_claim_id
    and c.scope_kind='person'
    and c.scope_id=v_user_id
    and c.subject_domain=v_subject_domain
    and c.subject_kind=v_subject_kind
    and c.subject_id=v_subject_id;

  if v_claim_type is null then
    raise exception 'acceptedRequirementClaimId must identify this person own claim for the Goal subject.' using errcode='42501';
  end if;
  if v_claim_type <> 'goal_requirement' then
    raise exception 'Goal revision requires claimType=goal_requirement.' using errcode='22023';
  end if;
  if v_claim_state <> 'accepted' or v_claim_authority <> 'person_acceptance' then
    raise exception 'Goal revision requires a current person-accepted requirement claim.' using errcode='22023';
  end if;
  if jsonb_typeof(v_claim_value)<>'object' then
    raise exception 'Accepted goal_requirement claim value must be a canonical requirement object.' using errcode='22023';
  end if;

  v_requirement_key := btrim(coalesce(v_claim_value->>'requirementKey',''));
  v_requirement_kind := btrim(coalesce(v_claim_value->>'requirementKind',v_claim_value->>'requirement_kind',''));
  v_requirement_phase := coalesce(nullif(btrim(v_claim_value->>'phase'),''),'gate');

  if v_requirement_key='' then
    raise exception 'Accepted goal_requirement requires requirementKey.' using errcode='22023';
  end if;
  if v_requirement_kind='' then
    raise exception 'Accepted goal_requirement requires requirementKind.' using errcode='22023';
  end if;
  if v_requirement_phase not in ('gate','progress','realize') then
    raise exception 'Accepted goal_requirement phase must be gate, progress, or realize.' using errcode='22023';
  end if;
  if v_claim_value ? 'required' and jsonb_typeof(v_claim_value->'required')<>'boolean' then
    raise exception 'Accepted goal_requirement required must be boolean when supplied.' using errcode='22023';
  end if;

  v_requirements := coalesce(v_old_signal->'requirements','[]'::jsonb);
  if jsonb_typeof(v_requirements)<>'array' then
    raise exception 'Stored Goal requirements are invalid.' using errcode='23514';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_requirements) requirement
    where requirement->>'requirementKey'=v_requirement_key
  ) then
    raise exception 'Goal already contains requirementKey %.',v_requirement_key using errcode='23505';
  end if;

  v_applied_requirement := (v_claim_value - 'authorization') || jsonb_build_object(
    'authorization',jsonb_build_object(
      'basis','person_accepted_goal_requirement_claim',
      'claimId',v_authorization_claim_id,
      'evidenceId',v_claim_evidence_id,
      'authorityKind',v_claim_authority,
      'acceptedAt',v_claim_recorded_at
    )
  );

  v_new_signal := jsonb_set(
    v_old_signal,
    '{requirements}',
    v_requirements || jsonb_build_array(v_applied_requirement),
    true
  );

  v_validation := atlas.validate_life_signal_v1(v_new_signal);
  if v_validation->>'validation_state'<>'passed' then
    raise exception 'Revised Goal Life Signal is invalid: %',v_validation->'violations' using errcode='22023';
  end if;

  v_new_packet := atlas.life_signal_to_goal_packet_v1(v_new_signal);
  v_initial_evaluation := atlas.evaluate_life_goal_state_v1(v_new_packet,'[]'::jsonb);
  v_new_metadata := coalesce(v_old_metadata,'{}'::jsonb) || jsonb_build_object(
    'revision',jsonb_build_object(
      'sourceKey',v_source_key,
      'previousDefinitionId',v_previous_definition_id,
      'acceptedRequirementClaimId',v_authorization_claim_id,
      'authorizationEvidenceId',v_claim_evidence_id,
      'authorizationBasis','person_accepted_goal_requirement_claim',
      'authorizationReason',v_authorization_reason
    )
  );

  insert into atlas.person_life_definitions(
    principal_id,owner_user_id,signal_kind,source_key,
    subject_domain,subject_kind,subject_id,
    source_domain,source_kind,source_id,
    life_signal,engine_packet,status,metadata
  ) values (
    v_principal_id,v_user_id,'goal',v_source_key,
    v_subject_domain,v_subject_kind,v_subject_id,
    v_source_domain,v_source_kind,v_source_id,
    v_new_signal,v_new_packet,'active',v_new_metadata
  )
  returning id into v_new_definition_id;

  insert into atlas.person_life_relations(
    definition_id,owner_user_id,relation_kind,target_domain,target_kind,target_id,
    relation_basis,relation_status,provenance
  )
  select v_new_definition_id,r.owner_user_id,r.relation_kind,r.target_domain,r.target_kind,r.target_id,
         r.relation_basis,r.relation_status,r.provenance || jsonb_build_object(
           'copiedByGoalRevision',true,
           'previousDefinitionId',v_previous_definition_id
         )
  from atlas.person_life_relations r
  where r.definition_id=v_previous_definition_id and r.owner_user_id=v_user_id
  on conflict do nothing;

  update atlas.person_life_definitions d
  set status='retired',retired_at=now()
  where d.id=v_previous_definition_id and d.owner_user_id=v_user_id and d.status='active';
  get diagnostics v_retired=row_count;
  if v_retired<>1 then
    raise exception 'Goal definition changed before revision could retire it.' using errcode='40001';
  end if;

  insert into atlas.person_life_definition_revisions(
    owner_user_id,source_key,previous_definition_id,revised_definition_id,
    authorization_claim_id,authorization_evidence_id,requirement_key,
    claimed_requirement,applied_requirement,authorization_basis,authorization_reason
  ) values (
    v_user_id,v_source_key,v_previous_definition_id,v_new_definition_id,
    v_authorization_claim_id,v_claim_evidence_id,v_requirement_key,
    v_claim_value,v_applied_requirement,'person_accepted_goal_requirement_claim',v_authorization_reason
  ) returning id into v_revision_id;

  return jsonb_build_object(
    'ok',true,
    'created',true,
    'revisionId',v_revision_id,
    'previousDefinitionId',v_previous_definition_id,
    'definitionId',v_new_definition_id,
    'acceptedRequirementClaimId',v_authorization_claim_id,
    'authorizationEvidenceId',v_claim_evidence_id,
    'claimedRequirement',v_claim_value,
    'appliedRequirement',v_applied_requirement,
    'enginePacket',v_new_packet,
    'initialEvaluation',v_initial_evaluation,
    'authorizationBasis','person_accepted_goal_requirement_claim',
    'authorizationReason',v_authorization_reason,
    'truthBoundary',jsonb_build_object(
      'historyPreserved',true,
      'priorDefinitionRetiredNotRewritten',true,
      'requirementAuthorityComesFromAcceptedClaim',true,
      'goalLabelDoesNotInventRequirements',true,
      'doesNotEvaluateRequirementSatisfaction',true,
      'doesNotCreateTask',true,
      'doesNotSelectCarrier',true,
      'doesNotCreateClockPlacement',true
    )
  );
end;
$$;

comment on function atlas.revise_person_goal_from_accepted_requirement_api_v1(jsonb) is
  'First-party Goal revision membrane. A current person-accepted goal_requirement claim may append exactly one canonical requirement to a new Goal definition version; the prior version is retired and an immutable authorization receipt preserves lineage and evidence.';

revoke all on function atlas.revise_person_goal_from_accepted_requirement_api_v1(jsonb) from public, anon;
grant execute on function atlas.revise_person_goal_from_accepted_requirement_api_v1(jsonb) to authenticated, service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
)
values (
  'atlas.revise_person_goal_from_accepted_requirement_api_v1(jsonb)',
  'app_endpoint','verified','active',true,true,true,0,0,
  jsonb_build_object(
    'purpose','Version a person-owned Goal by appending one explicitly accepted goal_requirement claim while preserving the prior definition and authorization evidence.',
    'authorizationBoundary','SECURITY DEFINER fixes custody to auth.uid(); only a current claimType=goal_requirement with lifecycle=accepted and authority_kind=person_acceptance for the same Goal subject may revise it. No task, carrier, consequence, Journal, or Clock authority is granted.',
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

do $$
begin
  if exists (select 1 from atlas.authenticated_rpc_registry_drift_v1()) then
    raise exception 'Authenticated RPC registry remains incomplete after person Goal revision registration.';
  end if;
end
$$;

commit;
