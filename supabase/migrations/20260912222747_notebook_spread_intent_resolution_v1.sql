begin;

do $guard$
begin
  if exists (select 1 from atlas.notebook_spread_instances limit 1) then
    raise exception 'notebook_spread_instances is no longer empty; reconcile existing rows before widening spread identity';
  end if;
end;
$guard$;

drop function if exists public.resolve_notebook_spread_instance_service_v1(uuid,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb);
drop function if exists public.set_notebook_spread_instance_service_v1(uuid,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb);
drop function if exists atlas.resolve_notebook_spread_instance_v1(uuid,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb);
drop function if exists atlas.set_notebook_spread_instance_v1(uuid,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb);

alter table atlas.notebook_spread_instances
  add column subject_domain text,
  add column title text,
  add column section_key text;

alter table atlas.notebook_spread_instances
  alter column subject_domain set not null,
  alter column title set not null,
  alter column section_key set not null,
  add constraint notebook_spread_instances_subject_domain_ck check (length(btrim(subject_domain)) > 0),
  add constraint notebook_spread_instances_title_ck check (length(btrim(title)) > 0),
  add constraint notebook_spread_instances_section_key_ck check (length(btrim(section_key)) > 0);

alter table atlas.notebook_spread_instances
  drop constraint notebook_spread_instances_semantic_identity_uk;

alter table atlas.notebook_spread_instances
  add constraint notebook_spread_instances_semantic_identity_uk unique (
    principal_id,scope_kind,scope_id,subject_domain,subject_kind,subject_id,purpose_key,horizon_key
  );

comment on column atlas.notebook_spread_instances.subject_domain is
  'Notebook subject namespace. This disambiguates identical subject kinds/ids owned by different source domains without claiming source-domain truth.';
comment on column atlas.notebook_spread_instances.title is
  'Human-facing notebook title. Presentation metadata, not source-domain truth.';
comment on column atlas.notebook_spread_instances.section_key is
  'Notebook Index grouping key. Presentation metadata, not a domain taxonomy authority.';

create or replace function atlas.set_notebook_spread_instance_v2(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
  p_title text,
  p_section_key text,
  p_recipe_key text,
  p_creation_mode text,
  p_spread_state text,
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_id uuid;
  v_existing atlas.notebook_spread_instances%rowtype;
  v_closed_at timestamptz;
begin
  if p_principal_id is null
     or nullif(btrim(p_spread_key),'') is null
     or nullif(btrim(p_scope_kind),'') is null
     or nullif(btrim(p_scope_id),'') is null
     or nullif(btrim(p_subject_domain),'') is null
     or nullif(btrim(p_subject_kind),'') is null
     or nullif(btrim(p_subject_id),'') is null
     or nullif(btrim(p_purpose_key),'') is null
     or nullif(btrim(p_horizon_key),'') is null
     or nullif(btrim(p_thread_key),'') is null
     or nullif(btrim(p_title),'') is null
     or nullif(btrim(p_section_key),'') is null then
    raise exception 'principal, spread, scope, subject, purpose, horizon, thread, title, and section are required' using errcode='22023';
  end if;

  if p_creation_mode not in ('explicit','resolved','continuation') then
    raise exception 'invalid creation mode' using errcode='22023';
  end if;
  if p_spread_state not in ('open','closed') then
    raise exception 'invalid spread state' using errcode='22023';
  end if;
  if not exists (select 1 from atlas.principals p where p.id=p_principal_id and p.status='active') then
    raise exception 'active principal not found' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.notebook_spread_instances s
  where s.principal_id=p_principal_id
    and s.spread_key=btrim(p_spread_key)
  limit 1;

  if v_existing.id is not null then
    if v_existing.scope_kind <> btrim(p_scope_kind)
       or v_existing.scope_id <> btrim(p_scope_id)
       or v_existing.subject_domain <> btrim(p_subject_domain)
       or v_existing.subject_kind <> btrim(p_subject_kind)
       or v_existing.subject_id <> btrim(p_subject_id)
       or v_existing.purpose_key <> btrim(p_purpose_key)
       or v_existing.horizon_key <> btrim(p_horizon_key)
       or v_existing.thread_key <> btrim(p_thread_key) then
      raise exception 'spread key already belongs to a different spread identity' using errcode='23505';
    end if;

    v_closed_at := case when p_spread_state='closed' then coalesce(v_existing.closed_at,now()) else null end;

    update atlas.notebook_spread_instances
    set title=btrim(p_title),
        section_key=btrim(p_section_key),
        recipe_key=coalesce(nullif(btrim(p_recipe_key),''),recipe_key),
        spread_state=p_spread_state,
        composition_contract=coalesce(p_composition_contract,'{}'::jsonb),
        basis=coalesce(p_basis,'{}'::jsonb),
        metadata=coalesce(p_metadata,'{}'::jsonb),
        closed_at=v_closed_at,
        updated_at=now()
    where id=v_existing.id
    returning id into v_id;

    return v_id;
  end if;

  v_closed_at := case when p_spread_state='closed' then now() else null end;

  insert into atlas.notebook_spread_instances(
    principal_id,spread_key,scope_kind,scope_id,subject_domain,subject_kind,subject_id,
    purpose_key,horizon_key,thread_key,title,section_key,recipe_key,creation_mode,spread_state,
    composition_contract,basis,metadata,closed_at
  ) values (
    p_principal_id,btrim(p_spread_key),btrim(p_scope_kind),btrim(p_scope_id),
    btrim(p_subject_domain),btrim(p_subject_kind),btrim(p_subject_id),
    btrim(p_purpose_key),btrim(p_horizon_key),btrim(p_thread_key),
    btrim(p_title),btrim(p_section_key),nullif(btrim(p_recipe_key),''),
    p_creation_mode,p_spread_state,coalesce(p_composition_contract,'{}'::jsonb),
    coalesce(p_basis,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb),v_closed_at
  ) returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.set_notebook_spread_instance_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated, service_role;

create or replace function public.set_notebook_spread_instance_service_v2(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
  p_title text,
  p_section_key text,
  p_recipe_key text,
  p_creation_mode text,
  p_spread_state text,
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.set_notebook_spread_instance_v2(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_domain,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_title,p_section_key,p_recipe_key,p_creation_mode,p_spread_state,
    p_composition_contract,p_basis,p_metadata
  );
$function$;

revoke all on function public.set_notebook_spread_instance_service_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function public.set_notebook_spread_instance_service_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) to service_role;

create or replace function atlas.resolve_notebook_spread_instance_v2(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
  p_title text,
  p_section_key text,
  p_recipe_key text,
  p_creation_mode text,
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_existing atlas.notebook_spread_instances%rowtype;
  v_id uuid;
begin
  select * into v_existing
  from atlas.notebook_spread_instances s
  where s.principal_id=p_principal_id
    and s.scope_kind=btrim(p_scope_kind)
    and s.scope_id=btrim(p_scope_id)
    and s.subject_domain=btrim(p_subject_domain)
    and s.subject_kind=btrim(p_subject_kind)
    and s.subject_id=btrim(p_subject_id)
    and s.purpose_key=btrim(p_purpose_key)
    and s.horizon_key=btrim(p_horizon_key)
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,'created',false,'spreadInstanceId',v_existing.id,
      'spreadKey',v_existing.spread_key,'spreadState',v_existing.spread_state,
      'threadKey',v_existing.thread_key,'recipeKey',v_existing.recipe_key,
      'title',v_existing.title,'sectionKey',v_existing.section_key,'match','semantic_identity'
    );
  end if;

  v_id := atlas.set_notebook_spread_instance_v2(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_domain,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_title,p_section_key,p_recipe_key,p_creation_mode,'open',
    p_composition_contract,p_basis,p_metadata
  );

  return jsonb_build_object(
    'ok',true,'created',true,'spreadInstanceId',v_id,
    'spreadKey',btrim(p_spread_key),'spreadState','open','threadKey',btrim(p_thread_key),
    'recipeKey',nullif(btrim(p_recipe_key),''),'title',btrim(p_title),
    'sectionKey',btrim(p_section_key),'match','new_instance'
  );
end;
$function$;

revoke all on function atlas.resolve_notebook_spread_instance_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated, service_role;

create or replace function public.resolve_notebook_spread_instance_service_v2(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_domain text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
  p_title text,
  p_section_key text,
  p_recipe_key text,
  p_creation_mode text,
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.resolve_notebook_spread_instance_v2(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_domain,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_title,p_section_key,p_recipe_key,p_creation_mode,
    p_composition_contract,p_basis,p_metadata
  );
$function$;

revoke all on function public.resolve_notebook_spread_instance_service_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function public.resolve_notebook_spread_instance_service_v2(
  uuid,text,text,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) to service_role;

create table atlas.notebook_spread_intent_requests (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  source_action_id text not null check (length(btrim(source_action_id)) > 0),
  source_surface text not null default 'tell_atlas' check (length(btrim(source_surface)) > 0),
  literal_request text not null check (length(btrim(literal_request)) > 0),
  capture_context jsonb not null default '{}'::jsonb check (jsonb_typeof(capture_context)='object'),
  request_state text not null default 'captured' check (request_state in ('captured','resolved','no_spread','needs_clarification','rejected')),
  interpretation jsonb,
  validation jsonb,
  interpreter_kind text,
  interpreter_ref text,
  spread_instance_id uuid references atlas.notebook_spread_instances(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id),
  check (interpretation is null or jsonb_typeof(interpretation)='object'),
  check (validation is null or jsonb_typeof(validation)='object'),
  check (
    (request_state='captured' and interpretation is null and validation is null and interpreter_kind is null and interpreter_ref is null and spread_instance_id is null)
    or (request_state in ('resolved','no_spread','needs_clarification','rejected') and interpretation is not null and validation is not null and interpreter_kind is not null and interpreter_ref is not null)
  ),
  check ((request_state='resolved')=(spread_instance_id is not null))
);

comment on table atlas.notebook_spread_intent_requests is
  'Notebook command envelope preserving the literal human request before AI/rule interpretation. The row governs notebook presentation only; it does not create source-domain truth.';
comment on column atlas.notebook_spread_intent_requests.request_state is
  'captured before interpretation; resolved only when a durable spread was reused/created; no_spread for ordinary answers; needs_clarification for blocked ambiguity; rejected for malformed interpretation.';

create index notebook_spread_intent_requests_principal_time_idx
  on atlas.notebook_spread_intent_requests(principal_id,created_at desc,id);

alter table atlas.notebook_spread_intent_requests enable row level security;
revoke all on atlas.notebook_spread_intent_requests from public, anon, authenticated;
grant select, insert, update on atlas.notebook_spread_intent_requests to service_role;

create or replace function atlas.capture_notebook_spread_intent_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_principal_id uuid;
  v_source_action_id text;
  v_literal text;
  v_surface text;
  v_context jsonb;
  v_row atlas.notebook_spread_intent_requests%rowtype;
  v_old atlas.notebook_spread_intent_requests%rowtype;
  v_created boolean := false;
begin
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Notebook spread intent input must be an object.' using errcode='22023'; end if;

  select p.id into v_principal_id from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_source_action_id := nullif(btrim(p_input->>'sourceActionId'),'');
  v_literal := nullif(btrim(p_input->>'literalRequest'),'');
  v_surface := coalesce(nullif(btrim(p_input->>'sourceSurface'),''),'tell_atlas');
  v_context := coalesce(case when jsonb_typeof(p_input->'captureContext')='object' then p_input->'captureContext' end,'{}'::jsonb);
  if v_source_action_id is null or v_literal is null then raise exception 'sourceActionId and literalRequest are required.' using errcode='22023'; end if;

  insert into atlas.notebook_spread_intent_requests(
    principal_id,owner_user_id,source_action_id,source_surface,literal_request,capture_context
  ) values (v_principal_id,v_user_id,v_source_action_id,v_surface,v_literal,v_context)
  on conflict(owner_user_id,source_action_id) do nothing
  returning * into v_row;

  if v_row.id is null then
    select * into v_old from atlas.notebook_spread_intent_requests r
    where r.owner_user_id=v_user_id and r.source_action_id=v_source_action_id;
    if v_old.id is null
       or v_old.principal_id is distinct from v_principal_id
       or v_old.source_surface is distinct from v_surface
       or v_old.literal_request is distinct from v_literal
       or v_old.capture_context is distinct from v_context then
      raise exception 'sourceActionId retry does not match existing notebook spread intent.' using errcode='23505';
    end if;
    v_row := v_old;
  else
    v_created := true;
  end if;

  return jsonb_build_object(
    'ok',true,'created',v_created,'contractVersion','notebook_spread_intent_capture_v1',
    'requestId',v_row.id,'requestState',v_row.request_state,'literalRequest',v_row.literal_request,
    'spreadInstanceId',v_row.spread_instance_id,
    'truthBoundary',jsonb_build_object(
      'literalRequestPreservedBeforeInterpretation',true,
      'captureDoesNotCreateSourceTruth',true,
      'captureDoesNotCreateSpread',true
    )
  );
end;
$function$;

revoke all on function atlas.capture_notebook_spread_intent_self_api_v1(jsonb) from public, anon, authenticated, service_role;

create or replace function public.capture_notebook_spread_intent_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.capture_notebook_spread_intent_self_api_v1(p_input);
$function$;

revoke all on function public.capture_notebook_spread_intent_self_api_v1(jsonb) from public, anon;
grant execute on function public.capture_notebook_spread_intent_self_api_v1(jsonb) to authenticated, service_role;

create or replace function atlas.notebook_spread_intent_basis_validation_v1(p_literal text,p_basis jsonb)
returns jsonb
language plpgsql
immutable
set search_path to 'pg_catalog'
as $function$
declare
  v_kind text;
  v_text text;
  v_ref text;
  v_explanation text;
begin
  if p_basis is null or jsonb_typeof(p_basis)<>'object' then
    return jsonb_build_object('ok',false,'issue','basis_object_required');
  end if;
  v_kind := nullif(btrim(p_basis->>'kind'),'');
  if v_kind is null or v_kind not in ('literal_span','existing_reality','conversation_context','derived_notebook_identity','calendar_resolution','established_thread') then
    return jsonb_build_object('ok',false,'issue','invalid_basis_kind');
  end if;
  if v_kind='literal_span' then
    v_text := nullif(btrim(p_basis->>'text'),'');
    if v_text is null or strpos(lower(coalesce(p_literal,'')),lower(v_text))=0 then
      return jsonb_build_object('ok',false,'issue','literal_span_not_found');
    end if;
  elsif v_kind in ('existing_reality','conversation_context','established_thread') then
    v_ref := nullif(btrim(p_basis->>'ref'),'');
    if v_ref is null then return jsonb_build_object('ok',false,'issue','basis_ref_required'); end if;
  else
    v_explanation := nullif(btrim(p_basis->>'explanation'),'');
    if v_explanation is null then return jsonb_build_object('ok',false,'issue','derived_basis_explanation_required'); end if;
  end if;
  return jsonb_build_object('ok',true,'kind',v_kind);
end;
$function$;

revoke all on function atlas.notebook_spread_intent_basis_validation_v1(text,jsonb) from public, anon, authenticated;

create or replace function atlas.validate_notebook_spread_intent_v1(p_literal text,p_interpretation jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_violations jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_action text;
  v_authority text;
  v_subject jsonb;
  v_purpose jsonb;
  v_horizon jsonb;
  v_check jsonb;
  v_item jsonb;
  v_blocking integer := 0;
  v_readiness text;
begin
  if nullif(btrim(p_literal),'') is null then
    return jsonb_build_object('validationState','rejected','readiness','rejected','violations',jsonb_build_array(jsonb_build_object('key','literal_request_required')),'warnings','[]'::jsonb);
  end if;
  if p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    return jsonb_build_object('validationState','rejected','readiness','rejected','violations',jsonb_build_array(jsonb_build_object('key','interpretation_object_required')),'warnings','[]'::jsonb);
  end if;
  if p_interpretation->>'contractVersion' <> 'notebook_spread_intent_v1' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','unsupported_contract_version','value',p_interpretation->>'contractVersion'));
  end if;

  v_action := p_interpretation->>'resolutionAction';
  v_authority := p_interpretation->>'creationAuthority';
  if v_action not in ('resolve_or_create','no_spread','needs_clarification') then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_resolution_action','value',v_action));
  end if;
  if v_authority not in ('explicit_persistence','durable_retrieval_need','established_continuation','none') then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_creation_authority','value',v_authority));
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','retrieval_needs_must_be_array'));
  else
    for v_item in select value from jsonb_array_elements(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb)) loop
      if jsonb_typeof(v_item)<>'object' or nullif(btrim(v_item->>'kind'),'') is null then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_retrieval_need','item',v_item));
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'sourceBindings','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','source_bindings_must_be_array'));
  else
    for v_item in select value from jsonb_array_elements(coalesce(p_interpretation->'sourceBindings','[]'::jsonb)) loop
      if jsonb_typeof(v_item)<>'object'
         or nullif(btrim(v_item->>'sourceDomain'),'') is null
         or nullif(btrim(v_item->>'sourceKind'),'') is null
         or nullif(btrim(v_item->>'sourceId'),'') is null
         or (v_item->>'relationshipKind') not in ('state','plan','progress','requirement','constraint','window','threshold','sequence','cadence','accumulation','comparison','relationship','place','evidence','exception','memory','action')
         or (v_item->>'bindingState') not in ('established','candidate','unknown') then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_source_binding','item',v_item));
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_interpretation->'ambiguities','[]'::jsonb))<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','ambiguities_must_be_array'));
  else
    for v_item in select value from jsonb_array_elements(coalesce(p_interpretation->'ambiguities','[]'::jsonb)) loop
      if jsonb_typeof(v_item)<>'object' or nullif(btrim(v_item->>'key'),'') is null then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_ambiguity','item',v_item));
      elsif coalesce((v_item->>'blocksCreation')::boolean,false) then
        v_blocking := v_blocking + 1;
      end if;
    end loop;
  end if;

  if v_action='resolve_or_create' then
    if v_authority='none' then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','creation_authority_required'));
    end if;
    v_subject := p_interpretation->'subject';
    v_purpose := p_interpretation->'purpose';
    v_horizon := p_interpretation->'horizon';

    if jsonb_typeof(v_subject)<>'object'
       or nullif(btrim(v_subject->>'domain'),'') is null
       or nullif(btrim(v_subject->>'kind'),'') is null
       or nullif(btrim(v_subject->>'id'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','subject_identity_required'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_subject->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_subject_basis','detail',v_check));
      end if;
    end if;

    if jsonb_typeof(v_purpose)<>'object' or nullif(btrim(v_purpose->>'key'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','purpose_key_required'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_purpose->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_purpose_basis','detail',v_check));
      end if;
    end if;

    if jsonb_typeof(v_horizon)<>'object' or nullif(btrim(v_horizon->>'key'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','horizon_key_required'));
    else
      v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_horizon->'basis');
      if not coalesce((v_check->>'ok')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_horizon_basis','detail',v_check));
      end if;
    end if;

    if nullif(btrim(p_interpretation->>'proposedTitle'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','proposed_title_required'));
    end if;
    if nullif(btrim(p_interpretation->>'sectionKey'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','section_key_required'));
    end if;
    if v_authority='established_continuation' and nullif(btrim(p_interpretation->>'threadKey'),'') is null then
      v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','continuation_thread_key_required'));
    end if;
  end if;

  if v_action='no_spread' and v_authority<>'none' then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('key','no_spread_ignores_creation_authority'));
  end if;

  if jsonb_array_length(v_violations)>0 then
    v_readiness := 'rejected';
  elsif v_action='no_spread' then
    v_readiness := 'no_spread';
  elsif v_action='needs_clarification' or v_blocking>0 then
    v_readiness := 'needs_clarification';
  else
    v_readiness := 'ready';
  end if;

  return jsonb_build_object(
    'validationState',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'readiness',v_readiness,'violations',v_violations,'warnings',v_warnings,
    'blockingAmbiguityCount',v_blocking,
    'truthBoundary',jsonb_build_object(
      'literalBasisMustMatchLiteralRequest',true,
      'derivedNotebookIdentityRequiresExplanation',true,
      'existingRealityRequiresReference',true,
      'interpretationDoesNotCreateSourceTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.validate_notebook_spread_intent_v1(text,jsonb) from public, anon, authenticated;

create or replace function atlas.interpret_notebook_spread_intent_serv_v1(
  p_request_id uuid,
  p_interpretation jsonb,
  p_interpreter_kind text,
  p_interpreter_ref text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_request atlas.notebook_spread_intent_requests%rowtype;
  v_validation jsonb;
  v_readiness text;
  v_subject jsonb;
  v_purpose jsonb;
  v_horizon jsonb;
  v_recipe_key text;
  v_creation_mode text;
  v_spread_key text;
  v_thread_key text;
  v_result jsonb;
  v_spread_id uuid;
  v_binding jsonb;
begin
  if p_request_id is null or p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    raise exception 'request id and interpretation object are required' using errcode='22023';
  end if;
  if p_interpreter_kind not in ('ai','rule','self_authenticated','import') or nullif(btrim(p_interpreter_ref),'') is null then
    raise exception 'trusted interpreter provenance is required' using errcode='22023';
  end if;

  select * into v_request from atlas.notebook_spread_intent_requests r where r.id=p_request_id for update;
  if v_request.id is null then raise exception 'Notebook spread intent request not found.' using errcode='P0002'; end if;
  if not exists (select 1 from atlas.principals p where p.id=v_request.principal_id and p.user_id=v_request.owner_user_id and p.status='active') then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if v_request.request_state<>'captured' then
    if v_request.interpretation is distinct from p_interpretation
       or v_request.interpreter_kind is distinct from p_interpreter_kind
       or v_request.interpreter_ref is distinct from p_interpreter_ref then
      raise exception 'Interpretation retry does not match resolved notebook spread intent request.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,'changed',false,'contractVersion','notebook_spread_intent_resolution_v1',
      'requestId',v_request.id,'requestState',v_request.request_state,
      'spreadInstanceId',v_request.spread_instance_id,'validation',v_request.validation
    );
  end if;

  v_validation := atlas.validate_notebook_spread_intent_v1(v_request.literal_request,p_interpretation);
  v_readiness := v_validation->>'readiness';

  if v_readiness in ('rejected','no_spread','needs_clarification') then
    update atlas.notebook_spread_intent_requests
    set request_state=case v_readiness when 'rejected' then 'rejected' when 'no_spread' then 'no_spread' else 'needs_clarification' end,
        interpretation=p_interpretation,validation=v_validation,
        interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),updated_at=now()
    where id=v_request.id returning * into v_request;

    return jsonb_build_object(
      'ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v1',
      'requestId',v_request.id,'requestState',v_request.request_state,'spreadInstanceId',null,
      'validation',v_validation,
      'truthBoundary',jsonb_build_object('noDurableSpreadCreated',true,'sourceTruthUnchanged',true)
    );
  end if;

  v_subject := p_interpretation->'subject';
  v_purpose := p_interpretation->'purpose';
  v_horizon := p_interpretation->'horizon';
  v_recipe_key := nullif(btrim(p_interpretation#>>'{recipeCandidate,key}'),'');
  v_creation_mode := case p_interpretation->>'creationAuthority'
    when 'explicit_persistence' then 'explicit'
    when 'established_continuation' then 'continuation'
    else 'resolved'
  end;
  v_spread_key := 'spread:'||gen_random_uuid()::text;
  v_thread_key := coalesce(nullif(btrim(p_interpretation->>'threadKey'),''),'thread:'||gen_random_uuid()::text);

  v_result := atlas.resolve_notebook_spread_instance_v2(
    v_request.principal_id,
    v_spread_key,
    'person',
    v_request.owner_user_id::text,
    v_subject->>'domain',
    v_subject->>'kind',
    v_subject->>'id',
    v_purpose->>'key',
    v_horizon->>'key',
    v_thread_key,
    p_interpretation->>'proposedTitle',
    p_interpretation->>'sectionKey',
    v_recipe_key,
    v_creation_mode,
    '{}'::jsonb,
    jsonb_build_object(
      'notebookSpreadIntentRequestId',v_request.id,
      'creationAuthority',p_interpretation->>'creationAuthority',
      'subjectBasis',v_subject->'basis','purposeBasis',v_purpose->'basis','horizonBasis',v_horizon->'basis'
    ),
    jsonb_build_object(
      'retrievalNeeds',coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb),
      'recipeCandidate',p_interpretation->'recipeCandidate'
    )
  );
  v_spread_id := (v_result->>'spreadInstanceId')::uuid;

  for v_binding in select value from jsonb_array_elements(coalesce(p_interpretation->'sourceBindings','[]'::jsonb)) loop
    if v_binding->>'bindingState'='established' then
      perform atlas.bind_notebook_spread_source_v1(
        v_spread_id,
        v_binding->>'sourceDomain',v_binding->>'sourceKind',v_binding->>'sourceId',
        v_binding->>'relationshipKind','active',
        coalesce(case when jsonb_typeof(v_binding->'basis')='object' then v_binding->'basis' end,'{}'::jsonb),
        jsonb_build_object('notebookSpreadIntentRequestId',v_request.id)
      );
    end if;
  end loop;

  update atlas.notebook_spread_intent_requests
  set request_state='resolved',interpretation=p_interpretation,validation=v_validation,
      interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),
      spread_instance_id=v_spread_id,updated_at=now()
  where id=v_request.id returning * into v_request;

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v1',
    'requestId',v_request.id,'requestState','resolved','spreadInstanceId',v_spread_id,
    'spread',v_result,'validation',v_validation,
    'truthBoundary',jsonb_build_object(
      'literalHumanRequestPreserved',true,
      'notebookResolutionDoesNotCreateSourceTruth',true,
      'onlyEstablishedSourcesBecomeBindings',true,
      'recipeCandidateIsNotSourceAuthority',true
    )
  );
end;
$function$;

revoke all on function atlas.interpret_notebook_spread_intent_serv_v1(uuid,jsonb,text,text) from public, anon, authenticated, service_role;

create or replace function public.interpret_notebook_spread_intent_service_v1(
  p_request_id uuid,
  p_interpretation jsonb,
  p_interpreter_kind text,
  p_interpreter_ref text
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.interpret_notebook_spread_intent_serv_v1(p_request_id,p_interpretation,p_interpreter_kind,p_interpreter_ref);
$function$;

revoke all on function public.interpret_notebook_spread_intent_service_v1(uuid,jsonb,text,text) from public, anon, authenticated;
grant execute on function public.interpret_notebook_spread_intent_service_v1(uuid,jsonb,text,text) to service_role;

create or replace function atlas.notebook_spread_intent_request_self_api_v1(p_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
  select jsonb_build_object(
    'ok',true,'contractVersion','notebook_spread_intent_request_self_api_v1',
    'requestId',r.id,'literalRequest',r.literal_request,'requestState',r.request_state,
    'interpretation',r.interpretation,'validation',r.validation,
    'spreadInstanceId',r.spread_instance_id,'createdAt',r.created_at,'updatedAt',r.updated_at
  )
  from atlas.notebook_spread_intent_requests r
  where r.id=p_request_id and r.owner_user_id=auth.uid();
$function$;

revoke all on function atlas.notebook_spread_intent_request_self_api_v1(uuid) from public, anon, authenticated;

create or replace function public.notebook_spread_intent_request_self_api_v1(p_request_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_intent_request_self_api_v1(p_request_id);
$function$;

revoke all on function public.notebook_spread_intent_request_self_api_v1(uuid) from public, anon;
grant execute on function public.notebook_spread_intent_request_self_api_v1(uuid) to authenticated, service_role;

create or replace function atlas.notebook_spread_instances_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
  with principal as (
    select p.id from atlas.principals p where p.user_id=auth.uid() and p.status='active' limit 1
  ), spreads as (
    select s.* from atlas.notebook_spread_instances s join principal p on p.id=s.principal_id
  )
  select jsonb_build_object(
    'ok',true,'contractVersion','notebook_spread_instances_self_api_v1',
    'items',coalesce(jsonb_agg(
      jsonb_build_object(
        'spreadInstanceId',s.id,'spreadKey',s.spread_key,'title',s.title,'sectionKey',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'purposeKey',s.purpose_key,'horizonKey',s.horizon_key,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'creationMode',s.creation_mode,'spreadState',s.spread_state,
        'compositionContract',s.composition_contract,'metadata',s.metadata,'openedAt',s.opened_at,'closedAt',s.closed_at
      ) order by s.opened_at,s.id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'spreadExistenceDoesNotGrantSourceAuthority',true,
      'closedSpreadsRemainRetrievable',true,
      'encounterSelectionIsSeparate',true
    )
  ) from spreads s;
$function$;

create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;

  with descriptors as (
    select 0 as section_order,0 as item_order,
      jsonb_build_object('addressKind','today','spreadKey','today','templateKey','today','title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','day','id',current_date::text)) as item
    union all
    select 0,1,jsonb_build_object('addressKind','index','spreadKey','index','templateKey','index','title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','notebook','id',v_user_id))
    union all
    select 10,0,jsonb_build_object('addressKind','spread','spreadKey','household-rhythm','templateKey','rhythm','title','Household rhythm','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household','id',h.id)) from atlas.households h where h.id=v_household_id
    union all
    select 10,1,jsonb_build_object('addressKind','spread','spreadKey','laundry','templateKey','rhythm','title','Laundry','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','world_kernel','id','household.laundry')) from atlas.households h where h.id=v_household_id
    union all
    select 10,2,jsonb_build_object('addressKind','spread','spreadKey','home-care','templateKey','occurrence','title','Home care','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household_care','id',h.id)) from atlas.households h where h.id=v_household_id
    union all
    select 20,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey',s.spread_key,'templateKey',coalesce(s.recipe_key,'composed'),
        'title',s.title,'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'spreadInstanceId',s.id,'spreadState',s.spread_state,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'purposeKey',s.purpose_key,'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
    union all
    select 30,row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object('addressKind','spread','spreadKey','ledger:'||o.id::text,'templateKey','organization-ledger','title',o.name,'subtitle','Ledger','section','Organizations','scope',jsonb_build_object('kind','organization','id',o.id),'subject',jsonb_build_object('kind','organization_ledger','id',o.id))
    from atlas.organizations o where atlas.is_organization_owner(o.id)
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb) into v_items from descriptors;

  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_notebook_index_self_api_v1','principalId',v_principal_id,'householdId',v_household_id,'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,'indexDoesNotGrantAccess',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,'closedSpreadsRemainRetrievable',true,
      'ledgerDescriptorMatchesReadAuthority',true
    )
  );
end;
$function$;

commit;