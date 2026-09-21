begin;

create table if not exists atlas.contact_set_intent_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid null,
  requested_by_user_id uuid not null,
  source_action_id text not null,
  source_surface text not null default 'atlas_intelligence',
  literal_request text not null,
  capture_context jsonb not null default '{}'::jsonb,
  request_state text not null default 'captured',
  interpretation jsonb null,
  validation jsonb null,
  execution_plan jsonb null,
  interpreter_kind text null,
  interpreter_ref text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contact_set_intent_requests_source_action_check check (btrim(source_action_id) <> ''),
  constraint contact_set_intent_requests_source_surface_check check (btrim(source_surface) <> ''),
  constraint contact_set_intent_requests_literal_check check (btrim(literal_request) <> ''),
  constraint contact_set_intent_requests_capture_context_check check (jsonb_typeof(capture_context)='object'),
  constraint contact_set_intent_requests_state_check check (
    request_state in ('captured','ready','needs_clarification','closed','cancelled')
  ),
  constraint contact_set_intent_requests_interpretation_check check (
    interpretation is null or jsonb_typeof(interpretation)='object'
  ),
  constraint contact_set_intent_requests_validation_check check (
    validation is null or jsonb_typeof(validation)='object'
  ),
  constraint contact_set_intent_requests_execution_plan_check check (
    execution_plan is null or jsonb_typeof(execution_plan)='object'
  ),
  constraint contact_set_intent_requests_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  unique(organization_id,requested_by_user_id,source_action_id)
);

create index if not exists contact_set_intent_requests_org_state_idx
  on atlas.contact_set_intent_requests(organization_id,request_state,created_at desc);

alter table atlas.contact_set_intent_requests enable row level security;
revoke all on table atlas.contact_set_intent_requests from public,anon,authenticated,service_role;

comment on table atlas.contact_set_intent_requests is
'Organization-private Atlas Intelligence carrier for literal human contact-set requests, typed interpretation, validation and deterministic plan. It is working state, not canonical external-world truth.';
comment on column atlas.contact_set_intent_requests.literal_request is
'Exact human request preserved before model interpretation.';
comment on column atlas.contact_set_intent_requests.capture_context is
'Lawfully assembled context references used to resolve phrases such as those towns or these companies; context is not truth authority.';
comment on column atlas.contact_set_intent_requests.execution_plan is
'Deterministic Atlas operation order. External acquisition is gap-only and never precedes Shared Directory retrieval.';

create or replace function atlas.validate_contact_set_intent_v1(
  p_literal text,
  p_interpretation jsonb
)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_errors jsonb := '[]'::jsonb;
  v_unresolved jsonb := '[]'::jsonb;
  v_family text;
  v_objective text;
  v_target jsonb;
  v_fields jsonb;
  v_required jsonb;
  v_clarification text;
  v_ready boolean;
begin
  if nullif(btrim(coalesce(p_literal,'')),'') is null then
    v_errors:=v_errors||jsonb_build_array('literal_request_required');
  end if;

  if p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    return jsonb_build_object(
      'valid',false,
      'executionReady',false,
      'needsClarification',false,
      'errors',v_errors||jsonb_build_array('interpretation_object_required'),
      'unresolvedReferences','[]'::jsonb
    );
  end if;

  v_family:=nullif(btrim(p_interpretation->>'intentFamily'),'');
  if v_family is distinct from 'build_target_contact_set' then
    v_errors:=v_errors||jsonb_build_array('intent_family_must_be_build_target_contact_set');
  end if;

  v_objective:=nullif(btrim(p_interpretation->>'objective'),'');
  if v_objective is null or v_objective not in ('retrieve','enrich','discover','mixed') then
    v_errors:=v_errors||jsonb_build_array('objective_invalid');
  end if;

  v_target:=p_interpretation->'target';
  if v_target is null or jsonb_typeof(v_target)<>'object'
     or nullif(btrim(coalesce(v_target->>'description','')),'') is null then
    v_errors:=v_errors||jsonb_build_array('target_description_required');
  end if;

  v_fields:=p_interpretation->'fields';
  if v_fields is null or jsonb_typeof(v_fields)<>'object' then
    v_errors:=v_errors||jsonb_build_array('fields_object_required');
  else
    v_required:=v_fields->'required';
    if v_required is null or jsonb_typeof(v_required)<>'array'
       or jsonb_array_length(v_required)=0 then
      v_errors:=v_errors||jsonb_build_array('at_least_one_required_field_required');
    elsif exists (
      select 1
      from jsonb_array_elements(v_required) x
      where jsonb_typeof(x)<>'string' or nullif(btrim(x#>>'{}'),'') is null
    ) then
      v_errors:=v_errors||jsonb_build_array('required_fields_must_be_nonempty_strings');
    end if;
  end if;

  if p_interpretation ? 'unresolvedReferences' then
    if jsonb_typeof(p_interpretation->'unresolvedReferences')<>'array' then
      v_errors:=v_errors||jsonb_build_array('unresolved_references_must_be_array');
    else
      v_unresolved:=p_interpretation->'unresolvedReferences';
    end if;
  end if;

  if p_interpretation ? 'resolvedReferences'
     and jsonb_typeof(p_interpretation->'resolvedReferences')<>'array' then
    v_errors:=v_errors||jsonb_build_array('resolved_references_must_be_array');
  end if;

  if p_interpretation ? 'geography'
     and p_interpretation->'geography' is not null
     and jsonb_typeof(p_interpretation->'geography')<>'object' then
    v_errors:=v_errors||jsonb_build_array('geography_must_be_object_or_null');
  end if;

  if p_interpretation ? 'population'
     and p_interpretation->'population' is not null
     and jsonb_typeof(p_interpretation->'population')<>'object' then
    v_errors:=v_errors||jsonb_build_array('population_must_be_object_or_null');
  end if;

  if p_interpretation ? 'ledgerEffect'
     and p_interpretation->'ledgerEffect' is not null
     and jsonb_typeof(p_interpretation->'ledgerEffect')<>'object' then
    v_errors:=v_errors||jsonb_build_array('ledger_effect_must_be_object_or_null');
  end if;

  v_clarification:=nullif(btrim(coalesce(p_interpretation->>'clarificationQuestion','')),'');
  if jsonb_array_length(v_unresolved)>0 and v_clarification is null then
    v_errors:=v_errors||jsonb_build_array('clarification_question_required_for_unresolved_references');
  end if;

  v_ready:=jsonb_array_length(v_errors)=0 and jsonb_array_length(v_unresolved)=0;

  return jsonb_build_object(
    'valid',jsonb_array_length(v_errors)=0,
    'executionReady',v_ready,
    'needsClarification',jsonb_array_length(v_errors)=0 and jsonb_array_length(v_unresolved)>0,
    'errors',v_errors,
    'unresolvedReferences',v_unresolved,
    'clarificationQuestion',v_clarification,
    'contractVersion','contact_set_intent_validation_v1'
  );
end;
$function$;

revoke all on function atlas.validate_contact_set_intent_v1(text,jsonb) from public,anon,authenticated;
grant execute on function atlas.validate_contact_set_intent_v1(text,jsonb) to service_role;

create or replace function atlas.plan_contact_set_intent_v1(
  p_interpretation jsonb
)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_validation jsonb;
begin
  v_validation:=atlas.validate_contact_set_intent_v1('plan-validation-placeholder',p_interpretation);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'Contact-set interpretation is structurally invalid.' using errcode='22023';
  end if;
  if not coalesce((v_validation->>'executionReady')::boolean,false) then
    raise exception 'Contact-set interpretation requires clarification before planning.' using errcode='22023';
  end if;

  return jsonb_build_object(
    'contractVersion','contact_set_execution_plan_v1',
    'skillKey','build_target_contact_set',
    'policy',jsonb_build_object(
      'existingRealityFirst',true,
      'externalAcquisition','gap_only',
      'canonicalIdentityBeforeNewAdmission',true,
      'privateLedgerEffectsStayPrivate',true,
      'contactDiscoveryDoesNotAuthorizeCommunication',true
    ),
    'steps',jsonb_build_array(
      jsonb_build_object(
        'order',1,'operation','shared_directory_search','mutation',false,
        'purpose','Reuse canonical Shared Intelligence identities and public contact routes before external acquisition.'
      ),
      jsonb_build_object(
        'order',2,'operation','requesting_ledger_overlay_read','mutation',false,
        'purpose','Compose exactly the requesting Organization private relationship/domain context.'
      ),
      jsonb_build_object(
        'order',3,'operation','contact_gap_analysis','mutation',false,
        'purpose','Classify requested facts as known/current, stale, missing, conflicting, or identity-unresolved.'
      ),
      jsonb_build_object(
        'order',4,'operation','acquire_missing_truth','mutation','evidence_only','condition','missing_or_stale_or_conflicting_required_fact',
        'purpose','Use external sources only for unresolved gaps; preserve source evidence and never fabricate missing values.'
      ),
      jsonb_build_object(
        'order',5,'operation','canonical_identity_resolution','mutation','governed_shared_intelligence','condition','new_or_unresolved_source_subject',
        'purpose','Resolve acquired subjects against the universal canonical corpus before any new identity admission.'
      ),
      jsonb_build_object(
        'order',6,'operation','requesting_ledger_relationship_effect','mutation','organization_private','condition','ledger_effect_authorized_by_interpretation',
        'purpose','Attach relevance/relationship/effort only to the requesting Ledger; never write another Organization overlay.'
      ),
      jsonb_build_object(
        'order',7,'operation','return_contact_set','mutation',false,
        'purpose','Return a practical contact set with qualification and evidence/gap status.'
      )
    )
  );
end;
$function$;

revoke all on function atlas.plan_contact_set_intent_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.plan_contact_set_intent_v1(jsonb) to service_role;

create or replace function atlas.capture_contact_set_intent_self_api_v1(
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_org_id uuid;
  v_unit_id uuid;
  v_source_action_id text;
  v_surface text;
  v_literal text;
  v_context jsonb;
  v_row atlas.contact_set_intent_requests%rowtype;
  v_old atlas.contact_set_intent_requests%rowtype;
  v_created boolean:=false;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Contact-set intent input must be an object.' using errcode='22023';
  end if;

  begin
    v_org_id:=nullif(p_input->>'organizationId','')::uuid;
    v_unit_id:=nullif(p_input->>'organizationUnitId','')::uuid;
  exception when invalid_text_representation then
    raise exception 'organizationId and organizationUnitId must be UUIDs.' using errcode='22023';
  end;

  if v_org_id is null then
    raise exception 'organizationId is required.' using errcode='22023';
  end if;
  if atlas.current_effective_organization_membership_v1(v_org_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;
  if not exists(select 1 from atlas.organizations o where o.id=v_org_id and o.status='active') then
    raise exception 'Active Organization required.' using errcode='P0002';
  end if;
  if v_unit_id is not null and not exists(
    select 1 from atlas.organization_units u
    where u.id=v_unit_id and u.organization_id=v_org_id and u.status<>'archived'
  ) then
    raise exception 'Organization Unit is outside Organization or archived.' using errcode='42501';
  end if;

  v_source_action_id:=nullif(btrim(p_input->>'sourceActionId'),'');
  v_surface:=coalesce(nullif(btrim(p_input->>'sourceSurface'),''),'atlas_intelligence');
  v_literal:=nullif(btrim(p_input->>'literalRequest'),'');
  v_context:=coalesce(
    case when jsonb_typeof(p_input->'captureContext')='object' then p_input->'captureContext' end,
    '{}'::jsonb
  );

  if v_source_action_id is null or v_literal is null then
    raise exception 'sourceActionId and literalRequest are required.' using errcode='22023';
  end if;

  insert into atlas.contact_set_intent_requests(
    organization_id,organization_unit_id,requested_by_user_id,
    source_action_id,source_surface,literal_request,capture_context
  ) values (
    v_org_id,v_unit_id,v_user_id,
    v_source_action_id,v_surface,v_literal,v_context
  )
  on conflict(organization_id,requested_by_user_id,source_action_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_old
    from atlas.contact_set_intent_requests r
    where r.organization_id=v_org_id
      and r.requested_by_user_id=v_user_id
      and r.source_action_id=v_source_action_id;

    if v_old.id is null
       or v_old.organization_unit_id is distinct from v_unit_id
       or v_old.source_surface is distinct from v_surface
       or v_old.literal_request is distinct from v_literal
       or v_old.capture_context is distinct from v_context then
      raise exception 'sourceActionId retry does not match existing contact-set intent.' using errcode='23505';
    end if;
    v_row:=v_old;
  else
    v_created:=true;
  end if;

  return jsonb_build_object(
    'ok',true,
    'created',v_created,
    'contractVersion','contact_set_intent_capture_v1',
    'requestId',v_row.id,
    'organizationId',v_row.organization_id,
    'requestState',v_row.request_state,
    'literalRequest',v_row.literal_request,
    'truthBoundary',jsonb_build_object(
      'literalRequestPreservedBeforeInterpretation',true,
      'captureCreatesNoSharedIntelligenceTruth',true,
      'captureCreatesNoLedgerRelationship',true,
      'captureAuthorizesNoCommunication',true
    )
  );
end;
$function$;

revoke all on function atlas.capture_contact_set_intent_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.capture_contact_set_intent_self_api_v1(jsonb) to authenticated;

create or replace function atlas.interpret_contact_set_intent_service_v1(
  p_request_id uuid,
  p_interpretation jsonb,
  p_interpreter_kind text,
  p_interpreter_ref text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  r atlas.contact_set_intent_requests%rowtype;
  v_validation jsonb;
  v_plan jsonb;
  v_state text;
begin
  if p_request_id is null or p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    raise exception 'request id and interpretation object are required.' using errcode='22023';
  end if;
  if p_interpreter_kind not in ('ai','rule','self_authenticated','import')
     or nullif(btrim(coalesce(p_interpreter_ref,'')),'') is null then
    raise exception 'trusted interpreter provenance is required.' using errcode='22023';
  end if;

  select * into r
  from atlas.contact_set_intent_requests x
  where x.id=p_request_id
  for update;

  if r.id is null then
    raise exception 'Contact-set intent request not found.' using errcode='P0002';
  end if;

  if r.request_state<>'captured' then
    if r.interpretation is distinct from p_interpretation
       or r.interpreter_kind is distinct from p_interpreter_kind
       or r.interpreter_ref is distinct from btrim(p_interpreter_ref) then
      raise exception 'Interpretation retry does not match resolved contact-set intent request.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'changed',false,'requestId',r.id,'requestState',r.request_state,
      'validation',r.validation,'executionPlan',r.execution_plan
    );
  end if;

  v_validation:=atlas.validate_contact_set_intent_v1(r.literal_request,p_interpretation);
  if not coalesce((v_validation->>'valid')::boolean,false) then
    raise exception 'Contact-set interpretation failed structural validation: %',v_validation using errcode='22023';
  end if;

  if coalesce((v_validation->>'executionReady')::boolean,false) then
    v_state:='ready';
    v_plan:=atlas.plan_contact_set_intent_v1(p_interpretation);
  else
    v_state:='needs_clarification';
    v_plan:=null;
  end if;

  update atlas.contact_set_intent_requests
  set request_state=v_state,
      interpretation=p_interpretation,
      validation=v_validation,
      execution_plan=v_plan,
      interpreter_kind=p_interpreter_kind,
      interpreter_ref=btrim(p_interpreter_ref),
      updated_at=now()
  where id=r.id
  returning * into r;

  return jsonb_build_object(
    'ok',true,
    'changed',true,
    'contractVersion','contact_set_intent_resolution_v1',
    'requestId',r.id,
    'requestState',r.request_state,
    'validation',r.validation,
    'executionPlan',r.execution_plan,
    'truthBoundary',jsonb_build_object(
      'interpreterOwnsNoCanonicalTruth',true,
      'planDoesNotExecuteResearch',true,
      'planDoesNotCreateLedgerRelationship',true,
      'planDoesNotAuthorizeCommunication',true
    )
  );
end;
$function$;

revoke all on function atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text) to service_role;

create or replace function atlas.contact_set_intent_request_self_api_v1(
  p_request_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_user_id uuid:=auth.uid();
  r atlas.contact_set_intent_requests%rowtype;
begin
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into r
  from atlas.contact_set_intent_requests x
  where x.id=p_request_id;

  if r.id is null then
    raise exception 'Contact-set intent request not found.' using errcode='P0002';
  end if;
  if atlas.current_effective_organization_membership_v1(r.organization_id) is null then
    raise exception 'Organization access denied.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','contact_set_intent_request_v1',
    'requestId',r.id,
    'organizationId',r.organization_id,
    'organizationUnitId',r.organization_unit_id,
    'sourceSurface',r.source_surface,
    'literalRequest',r.literal_request,
    'captureContext',r.capture_context,
    'requestState',r.request_state,
    'interpretation',r.interpretation,
    'validation',r.validation,
    'executionPlan',r.execution_plan,
    'interpreterKind',r.interpreter_kind,
    'interpreterRef',r.interpreter_ref,
    'createdAt',r.created_at,
    'updatedAt',r.updated_at
  );
end;
$function$;

revoke all on function atlas.contact_set_intent_request_self_api_v1(uuid) from public,anon;
grant execute on function atlas.contact_set_intent_request_self_api_v1(uuid) to authenticated;

comment on function atlas.validate_contact_set_intent_v1(text,jsonb) is
'Pure structural validator for build_target_contact_set interpretations. Unresolved contextual references produce needsClarification rather than guessed meaning.';
comment on function atlas.plan_contact_set_intent_v1(jsonb) is
'Deterministic build_target_contact_set operation ordering: Shared Directory and requesting Ledger first; external acquisition gap-only; communication never implied.';
comment on function atlas.capture_contact_set_intent_self_api_v1(jsonb) is
'Authenticated Organization-scoped capture of literal contact-set intent before interpretation. Creates no canonical external truth or relationship.';
comment on function atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text) is
'Service-only interpretation recorder. Validates typed contact-set intent and fixes a deterministic execution plan; performs no research or relationship mutation.';

commit;
