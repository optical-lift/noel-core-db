begin;

do $guard$
begin
  if exists (select 1 from atlas.notebook_spread_intent_requests limit 1) then
    raise exception 'notebook_spread_intent_requests is no longer empty; reconcile existing v1 interpretations before installing creation policy v2';
  end if;
end;
$guard$;

alter table atlas.notebook_spread_intent_requests
  add column policy_decision jsonb;

alter table atlas.notebook_spread_intent_requests
  add constraint notebook_spread_intent_requests_policy_decision_ck check (
    (request_state='captured' and policy_decision is null)
    or (request_state<>'captured' and policy_decision is not null and jsonb_typeof(policy_decision)='object')
  );

comment on column atlas.notebook_spread_intent_requests.policy_decision is
  'Deterministic notebook policy decision. Interpreter output may describe intent but cannot grant spread-creation or source-binding authority.';

drop function if exists public.interpret_notebook_spread_intent_service_v1(uuid,jsonb,text,text);
drop function if exists atlas.interpret_notebook_spread_intent_serv_v1(uuid,jsonb,text,text);

create or replace function atlas.notebook_spread_interpreter_spec_v2()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select jsonb_build_object(
    'contractVersion','notebook_spread_intent_v2',
    'objective','Extract the notebook-shaped meaning of the literal human request without deciding whether a durable spread is created and without establishing external source authority.',
    'utteranceModes',jsonb_build_array('point_lookup','broad_retrieval','fact_statement','sustained_intent','explicit_persistence','continuation','unclear'),
    'retrievalNeedKinds',jsonb_build_array('point_lookup','history','pattern','progress','cadence','collection','sequence','comparison','coordination','reference','monitoring'),
    'retrievalRecurrence',jsonb_build_array('once','repeated','ongoing'),
    'basisKinds',jsonb_build_array('literal_span','existing_reality','conversation_context','derived_notebook_identity','calendar_resolution','established_thread'),
    'rules',jsonb_build_array(
      'Preserve literal wording through literal_span basis whenever the person actually said the thing.',
      'Use calendar_resolution for relative expressions such as this month; include an explanation of the resolved boundary.',
      'Use existing_reality, conversation_context, or established_thread only when a concrete ref is supplied by trusted context.',
      'Do not emit resolutionAction or creationAuthority; deterministic notebook policy owns those decisions.',
      'Do not claim that Finance, Calendar, Oura, email, or any other source is bound or authoritative. Emit sourceCandidates only.',
      'point_lookup means one narrow answer such as a single balance, merchant total, or yesterday lookup.',
      'broad_retrieval means a view across history, pattern, collection, comparison, sequence, or other notebook-shaped retrieval.',
      'sustained_intent means the person is trying to maintain, reach, prepare for, collect, monitor, or repeatedly manage something.',
      'explicit_persistence means the person directly says keep, track, watch, remember, collect, or equivalent persistent language.',
      'A recipeCandidate is only a notebook composition hint. It is never source truth or persistence authority.'
    ),
    'truthBoundary',jsonb_build_object('interpreterDoesNotDecidePersistence',true,'interpreterDoesNotEstablishSourceAuthority',true,'interpreterDoesNotCreateSourceTruth',true)
  );
$function$;

revoke all on function atlas.notebook_spread_interpreter_spec_v2() from public, anon, authenticated;

create or replace function public.notebook_spread_interpreter_spec_service_v2()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_interpreter_spec_v2();
$function$;

revoke all on function public.notebook_spread_interpreter_spec_service_v2() from public, anon, authenticated;
grant execute on function public.notebook_spread_interpreter_spec_service_v2() to service_role;

create or replace function atlas.validate_notebook_spread_intent_v2(p_literal text,p_interpretation jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_violations jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_mode text;
  v_check jsonb;
  v_subject jsonb;
  v_purpose jsonb;
  v_horizon jsonb;
  v_item jsonb;
  v_binding jsonb;
  v_ambiguity jsonb;
  v_blocking integer := 0;
  v_relationship text;
  v_recurrence text;
  v_kind text;
  v_basis jsonb;
begin
  if nullif(btrim(p_literal),'') is null then
    return jsonb_build_object('validationState','rejected','violations',jsonb_build_array(jsonb_build_object('key','literal_request_required')),'warnings','[]'::jsonb,'blockingAmbiguityCount',0);
  end if;
  if p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    return jsonb_build_object('validationState','rejected','violations',jsonb_build_array(jsonb_build_object('key','interpretation_object_required')),'warnings','[]'::jsonb,'blockingAmbiguityCount',0);
  end if;

  if p_interpretation->>'contractVersion'<>'notebook_spread_intent_v2' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','unsupported_contract_version','value',p_interpretation->>'contractVersion'));
  end if;

  v_mode := p_interpretation->>'utteranceMode';
  if v_mode is null or v_mode not in ('point_lookup','broad_retrieval','fact_statement','sustained_intent','explicit_persistence','continuation','unclear') then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_utterance_mode','value',v_mode));
  end if;

  v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,p_interpretation->'utteranceBasis');
  if not coalesce((v_check->>'ok')::boolean,false) then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_utterance_basis','detail',v_check));
  end if;

  v_subject := p_interpretation->'subject';
  if v_subject is not null then
    if jsonb_typeof(v_subject)<>'object' or nullif(btrim(v_subject->>'domain'),'') is null or nullif(btrim(v_subject->>'kind'),'') is null or nullif(btrim(v_subject->>'id'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_subject_identity'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_subject->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_subject_basis','detail',v_check));
      end if;
    end if;
  end if;

  v_purpose := p_interpretation->'purpose';
  if v_purpose is not null then
    if jsonb_typeof(v_purpose)<>'object' or nullif(btrim(v_purpose->>'key'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_purpose'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_purpose->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_purpose_basis','detail',v_check));
      end if;
    end if;
  end if;

  v_horizon := p_interpretation->'horizon';
  if v_horizon is not null then
    if jsonb_typeof(v_horizon)<>'object' or nullif(btrim(v_horizon->>'key'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_horizon'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_horizon->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_horizon_basis','detail',v_check));
      end if;
    end if;
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','retrieval_needs_must_be_array'));
  else
    for v_item in select value from jsonb_array_elements(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb)) loop
      v_kind := v_item->>'kind';
      v_recurrence := v_item->>'recurrence';
      v_basis := v_item->'basis';
      if jsonb_typeof(v_item)<>'object' or v_kind is null or v_kind not in ('point_lookup','history','pattern','progress','cadence','collection','sequence','comparison','coordination','reference','monitoring') or v_recurrence is null or v_recurrence not in ('once','repeated','ongoing') then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_retrieval_need','item',v_item));
      else
        v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_basis);
        if not coalesce((v_check->>'ok')::boolean,false) then
          v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_retrieval_need_basis','item',v_item,'detail',v_check));
        end if;
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'sourceCandidates','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','source_candidates_must_be_array'));
  else
    for v_binding in select value from jsonb_array_elements(coalesce(p_interpretation->'sourceCandidates','[]'::jsonb)) loop
      v_relationship := v_binding->>'relationshipKind';
      if jsonb_typeof(v_binding)<>'object' or nullif(btrim(v_binding->>'sourceDomain'),'') is null or nullif(btrim(v_binding->>'sourceKind'),'') is null or v_relationship is null or v_relationship not in ('state','plan','progress','requirement','constraint','window','threshold','sequence','cadence','accumulation','comparison','relationship','place','evidence','exception','memory','action') then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_source_candidate','item',v_binding));
      else
        v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_binding->'basis');
        if not coalesce((v_check->>'ok')::boolean,false) then
          v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_source_candidate_basis','item',v_binding,'detail',v_check));
        end if;
      end if;
      if v_binding ? 'bindingState' or v_binding ? 'established' then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','interpreter_may_not_establish_source_binding','item',v_binding));
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'ambiguities','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','ambiguities_must_be_array'));
  else
    for v_ambiguity in select value from jsonb_array_elements(coalesce(p_interpretation->'ambiguities','[]'::jsonb)) loop
      if jsonb_typeof(v_ambiguity)<>'object' or nullif(btrim(v_ambiguity->>'key'),'') is null then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_ambiguity','item',v_ambiguity));
      elsif coalesce((v_ambiguity->>'blocksCreation')::boolean,false) then
        v_blocking := v_blocking + 1;
      end if;
    end loop;
  end if;

  if v_mode='continuation' then
    if jsonb_typeof(p_interpretation->'continuation')<>'object' or nullif(btrim(p_interpretation#>>'{continuation,threadKey}'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','continuation_thread_required'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,p_interpretation#>'{continuation,basis}');
      if not coalesce((v_check->>'ok')::boolean,false) or v_check->>'kind'<>'established_thread' then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_continuation_basis','detail',v_check));
      end if;
    end if;
  end if;

  if p_interpretation ? 'resolutionAction' or p_interpretation ? 'creationAuthority' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','interpreter_may_not_decide_persistence'));
  end if;

  return jsonb_build_object('validationState',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,'violations',v_violations,'warnings',v_warnings,'blockingAmbiguityCount',v_blocking,'truthBoundary',jsonb_build_object('interpreterDoesNotDecidePersistence',true,'interpreterDoesNotEstablishSourceAuthority',true,'literalBasisMustMatchLiteralRequest',true,'existingRealityRequiresReference',true));
end;
$function$;

revoke all on function atlas.validate_notebook_spread_intent_v2(text,jsonb) from public, anon, authenticated;

create or replace function atlas.notebook_spread_creation_policy_v1(p_literal text,p_interpretation jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_validation jsonb;
  v_mode text;
  v_blocking integer;
  v_durable_count integer := 0;
  v_need jsonb;
  v_missing jsonb := '[]'::jsonb;
  v_action text;
  v_authority text;
  v_reason text;
begin
  v_validation := atlas.validate_notebook_spread_intent_v2(p_literal,p_interpretation);
  if v_validation->>'validationState'<>'passed' then
    return jsonb_build_object('policyVersion','notebook_spread_creation_policy_v1','resolutionAction','rejected','creationAuthority','none','reason','invalid_interpretation','validation',v_validation);
  end if;

  v_mode := p_interpretation->>'utteranceMode';
  v_blocking := coalesce((v_validation->>'blockingAmbiguityCount')::integer,0);

  for v_need in select value from jsonb_array_elements(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb)) loop
    if (v_need->>'recurrence') in ('repeated','ongoing') and (v_need->>'kind') in ('history','pattern','progress','cadence','collection','sequence','comparison','coordination','reference','monitoring') then
      v_durable_count := v_durable_count + 1;
    end if;
  end loop;

  if v_blocking>0 or v_mode='unclear' then
    v_action := 'needs_clarification'; v_authority := 'none'; v_reason := case when v_blocking>0 then 'blocking_ambiguity' else 'unclear_utterance' end;
  elsif v_mode='continuation' then
    v_action := 'resolve_or_create'; v_authority := 'established_continuation'; v_reason := 'existing_spread_thread';
  elsif v_mode='explicit_persistence' then
    v_action := 'resolve_or_create'; v_authority := 'explicit_persistence'; v_reason := 'human_explicitly_requested_persistence';
  elsif v_mode in ('sustained_intent','broad_retrieval') and v_durable_count>0 then
    v_action := 'resolve_or_create'; v_authority := 'durable_retrieval_need'; v_reason := 'repeated_or_ongoing_notebook_retrieval';
  else
    v_action := 'no_spread'; v_authority := 'none';
    v_reason := case when v_mode='point_lookup' then 'narrow_point_lookup' when v_mode='fact_statement' then 'fact_without_durable_retrieval_need' when v_mode in ('sustained_intent','broad_retrieval') then 'no_durable_retrieval_need_extracted' else 'no_persistence_authority' end;
  end if;

  if v_action='resolve_or_create' then
    if jsonb_typeof(p_interpretation->'subject')<>'object' then v_missing:=v_missing||'"subject"'::jsonb; end if;
    if jsonb_typeof(p_interpretation->'purpose')<>'object' then v_missing:=v_missing||'"purpose"'::jsonb; end if;
    if jsonb_typeof(p_interpretation->'horizon')<>'object' then v_missing:=v_missing||'"horizon"'::jsonb; end if;
    if nullif(btrim(p_interpretation->>'proposedTitle'),'') is null then v_missing:=v_missing||'"proposedTitle"'::jsonb; end if;
    if nullif(btrim(p_interpretation->>'sectionKey'),'') is null then v_missing:=v_missing||'"sectionKey"'::jsonb; end if;
    if jsonb_array_length(v_missing)>0 then v_action := 'needs_clarification'; v_authority := 'none'; v_reason := 'durable_page_identity_incomplete'; end if;
  end if;

  return jsonb_build_object('policyVersion','notebook_spread_creation_policy_v1','resolutionAction',v_action,'creationAuthority',v_authority,'reason',v_reason,'durableRetrievalNeedCount',v_durable_count,'missingFields',v_missing,'validation',v_validation,'truthBoundary',jsonb_build_object('policyNotModelDecidesPersistence',true,'pointLookupDoesNotCreateSpread',true,'durableRetrievalNeedCanCreateSpread',true,'sourceAuthorityResolvedSeparately',true));
end;
$function$;

revoke all on function atlas.notebook_spread_creation_policy_v1(text,jsonb) from public, anon, authenticated;

create or replace function public.notebook_spread_creation_policy_service_v1(p_literal text,p_interpretation jsonb)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_creation_policy_v1(p_literal,p_interpretation);
$function$;

revoke all on function public.notebook_spread_creation_policy_service_v1(text,jsonb) from public, anon, authenticated;
grant execute on function public.notebook_spread_creation_policy_service_v1(text,jsonb) to service_role;

create or replace function atlas.interpret_notebook_spread_intent_serv_v2(p_request_id uuid,p_interpretation jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_request atlas.notebook_spread_intent_requests%rowtype;
  v_policy jsonb;
  v_action text;
  v_subject jsonb;
  v_purpose jsonb;
  v_horizon jsonb;
  v_recipe_key text;
  v_creation_mode text;
  v_spread_key text;
  v_thread_key text;
  v_result jsonb;
  v_spread_id uuid;
begin
  if p_request_id is null or p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then raise exception 'request id and interpretation object are required' using errcode='22023'; end if;
  if p_interpreter_kind not in ('ai','rule','self_authenticated','import') or nullif(btrim(p_interpreter_ref),'') is null then raise exception 'trusted interpreter provenance is required' using errcode='22023'; end if;

  select * into v_request from atlas.notebook_spread_intent_requests r where r.id=p_request_id for update;
  if v_request.id is null then raise exception 'Notebook spread intent request not found.' using errcode='P0002'; end if;
  if not exists (select 1 from atlas.principals p where p.id=v_request.principal_id and p.user_id=v_request.owner_user_id and p.status='active') then raise exception 'Active Principal required.' using errcode='42501'; end if;

  if v_request.request_state<>'captured' then
    if v_request.interpretation is distinct from p_interpretation or v_request.interpreter_kind is distinct from p_interpreter_kind or v_request.interpreter_ref is distinct from p_interpreter_ref then raise exception 'Interpretation retry does not match resolved notebook spread intent request.' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','notebook_spread_intent_resolution_v2','requestId',v_request.id,'requestState',v_request.request_state,'spreadInstanceId',v_request.spread_instance_id,'policyDecision',v_request.policy_decision,'validation',v_request.validation);
  end if;

  v_policy := atlas.notebook_spread_creation_policy_v1(v_request.literal_request,p_interpretation);
  v_action := v_policy->>'resolutionAction';

  if v_action in ('rejected','no_spread','needs_clarification') then
    update atlas.notebook_spread_intent_requests
    set request_state=case v_action when 'rejected' then 'rejected' when 'no_spread' then 'no_spread' else 'needs_clarification' end,
        interpretation=p_interpretation,validation=v_policy->'validation',policy_decision=v_policy,
        interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),updated_at=now()
    where id=v_request.id returning * into v_request;
    return jsonb_build_object('ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v2','requestId',v_request.id,'requestState',v_request.request_state,'spreadInstanceId',null,'policyDecision',v_policy,'validation',v_request.validation,'truthBoundary',jsonb_build_object('noSourceBindingCreatedByInterpreter',true,'sourceTruthUnchanged',true));
  end if;

  v_subject := p_interpretation->'subject'; v_purpose := p_interpretation->'purpose'; v_horizon := p_interpretation->'horizon';
  v_recipe_key := nullif(btrim(p_interpretation#>>'{recipeCandidate,key}'),'');
  v_creation_mode := case v_policy->>'creationAuthority' when 'explicit_persistence' then 'explicit' when 'established_continuation' then 'continuation' else 'resolved' end;
  v_spread_key := 'spread:'||gen_random_uuid()::text;
  v_thread_key := case when v_creation_mode='continuation' then p_interpretation#>>'{continuation,threadKey}' else 'thread:'||gen_random_uuid()::text end;

  v_result := atlas.resolve_notebook_spread_instance_v2(
    v_request.principal_id,v_spread_key,'person',v_request.owner_user_id::text,
    v_subject->>'domain',v_subject->>'kind',v_subject->>'id',v_purpose->>'key',v_horizon->>'key',v_thread_key,
    p_interpretation->>'proposedTitle',p_interpretation->>'sectionKey',v_recipe_key,v_creation_mode,
    '{}'::jsonb,
    jsonb_build_object('notebookSpreadIntentRequestId',v_request.id,'creationAuthority',v_policy->>'creationAuthority','subjectBasis',v_subject->'basis','purposeBasis',v_purpose->'basis','horizonBasis',v_horizon->'basis'),
    jsonb_build_object('retrievalNeeds',coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb),'recipeCandidate',p_interpretation->'recipeCandidate','unresolvedSourceCandidates',coalesce(p_interpretation->'sourceCandidates','[]'::jsonb))
  );
  v_spread_id := (v_result->>'spreadInstanceId')::uuid;

  update atlas.notebook_spread_intent_requests
  set request_state='resolved',interpretation=p_interpretation,validation=v_policy->'validation',policy_decision=v_policy,
      interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),spread_instance_id=v_spread_id,updated_at=now()
  where id=v_request.id returning * into v_request;

  return jsonb_build_object('ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v2','requestId',v_request.id,'requestState','resolved','spreadInstanceId',v_spread_id,'spread',v_result,'policyDecision',v_policy,'validation',v_request.validation,'sourceCandidates',coalesce(p_interpretation->'sourceCandidates','[]'::jsonb),'truthBoundary',jsonb_build_object('policyNotInterpreterGrantedCreationAuthority',true,'interpreterCreatedNoSourceBindings',true,'sourceCandidatesRequireSeparateDomainResolution',true,'recipeCandidateIsNotSourceAuthority',true));
end;
$function$;

revoke all on function atlas.interpret_notebook_spread_intent_serv_v2(uuid,jsonb,text,text) from public, anon, authenticated, service_role;

create or replace function public.interpret_notebook_spread_intent_service_v2(p_request_id uuid,p_interpretation jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.interpret_notebook_spread_intent_serv_v2(p_request_id,p_interpretation,p_interpreter_kind,p_interpreter_ref);
$function$;

revoke all on function public.interpret_notebook_spread_intent_service_v2(uuid,jsonb,text,text) from public, anon, authenticated;
grant execute on function public.interpret_notebook_spread_intent_service_v2(uuid,jsonb,text,text) to service_role;

create or replace function atlas.notebook_spread_intent_request_self_api_v1(p_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
  select jsonb_build_object('ok',true,'contractVersion','notebook_spread_intent_request_self_api_v1','requestId',r.id,'literalRequest',r.literal_request,'requestState',r.request_state,'interpretation',r.interpretation,'validation',r.validation,'policyDecision',r.policy_decision,'spreadInstanceId',r.spread_instance_id,'createdAt',r.created_at,'updatedAt',r.updated_at)
  from atlas.notebook_spread_intent_requests r
  where r.id=p_request_id and r.owner_user_id=auth.uid();
$function$;

commit;