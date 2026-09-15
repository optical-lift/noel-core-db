begin;

-- Notebook composition is compiled from semantic retrieval/relationship needs.
-- There is no domain template registry. Forms are reusable notebook grammar;
-- subjects are bound only after the durable spread already exists.

do $guard$
begin
  if exists (select 1 from atlas.notebook_spread_intent_requests limit 1)
     or exists (select 1 from atlas.notebook_spread_instances limit 1) then
    raise exception 'notebook spread rows now exist; reconcile v2 intent/composition semantics before installing composer grammar v1';
  end if;
end;
$guard$;

comment on column atlas.notebook_spread_instances.recipe_key is
  'Optional legacy/internal composition-family provenance only. Composer v1 does not select domain recipes or templates.';

create table atlas.notebook_form_registry (
  form_family text primary key check (form_family in ('field','log','ledger','timeline','path','count','relational','free-field')),
  description text not null,
  supported_relationships text[] not null,
  allowed_roles text[] not null,
  default_empty_behavior text not null check (default_empty_behavior in ('omit','show-quiet-geometry','show-established-future-space')),
  phone_rule text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table atlas.notebook_form_registry is
  'Small reusable notebook-form vocabulary. These are semantic presentation instruments, never domain templates and never source truth owners.';

insert into atlas.notebook_form_registry(form_family,description,supported_relationships,allowed_roles,default_empty_behavior,phone_rule) values
('field','Bounded repeated reality against a stable axis.',array['cadence','sequence','comparison','state','evidence','window'],array['anchor','supporting'],'show-established-future-space','Preserve axis and mark identity; reduce visible horizon before horizontal scrolling.'),
('log','Ordered occurrences, kept items, evidence, actions, or memory.',array['sequence','memory','evidence','action','plan','exception'],array['anchor','supporting','margin'],'show-established-future-space','Preserve line identity and order; continue vertically.'),
('ledger','Repeated entities aligned across meaningful comparable attributes.',array['comparison','accumulation','state','requirement','evidence','action'],array['anchor','supporting'],'show-established-future-space','Preserve row identity; collapse lower-value attributes into secondary inline ink.'),
('timeline','Beginnings, endings, overlap, movement, or bounded windows.',array['window','sequence','constraint','plan','evidence','exception'],array['anchor','supporting'],'show-quiet-geometry','Linearize lanes on narrow viewports without changing event identity.'),
('path','Meaningful checkpoints between current state and an established endpoint.',array['progress','threshold','requirement','sequence','state'],array['anchor','supporting'],'show-established-future-space','Preserve checkpoint order; do not invent stages.'),
('count','Accumulation or progress against a meaningful amount or threshold.',array['accumulation','threshold','progress','evidence'],array['anchor','supporting'],'show-quiet-geometry','Keep exact amount/mark legible and compact.'),
('relational','Sparse field showing only relationships worth noticing.',array['relationship','evidence','constraint','action'],array['anchor','supporting'],'omit','Linearize subject groups with inline relationship notes.'),
('free-field','Human notes, observations, exceptions, or not-yet-stable structure.',array['memory','exception','evidence','action','constraint'],array['anchor','supporting','margin'],'omit','Continue as ordinary notebook text/marks.');

revoke all on atlas.notebook_form_registry from public,anon,authenticated;
grant select on atlas.notebook_form_registry to service_role;

create table atlas.notebook_composition_pattern_registry (
  pattern_key text primary key check (pattern_key in (
    'dominant-margin','dominant-supporting-pair','reference-working-field',
    'orientation-pattern-field','paired-comparison','sparse-relational','single-form-continuation'
  )),
  description text not null,
  max_forms integer not null check (max_forms between 1 and 5),
  created_at timestamptz not null default now()
);

comment on table atlas.notebook_composition_pattern_registry is
  'Reusable arrangements of notebook forms. Patterns do not name domains or subjects.';

insert into atlas.notebook_composition_pattern_registry(pattern_key,description,max_forms) values
('dominant-margin','One dominant form with quiet exception/provenance/human margin ink.',2),
('dominant-supporting-pair','One dominant form with one or two materially different supporting forms.',3),
('reference-working-field','Small stable reference/goal area plus a larger accumulating working field.',3),
('orientation-pattern-field','One orientation form plus a bounded field that reveals pattern.',3),
('paired-comparison','Two aligned forms sharing a meaningful axis or identity.',2),
('sparse-relational','Several quiet zones with only a few meaningful connectors.',3),
('single-form-continuation','One form fills the page and continues rather than adding unrelated support.',1);

revoke all on atlas.notebook_composition_pattern_registry from public,anon,authenticated;
grant select on atlas.notebook_composition_pattern_registry to service_role;

create table atlas.notebook_spread_composition_revisions (
  id uuid primary key default gen_random_uuid(),
  spread_instance_id uuid not null references atlas.notebook_spread_instances(id) on delete cascade,
  intent_request_id uuid references atlas.notebook_spread_intent_requests(id) on delete set null,
  revision_no integer not null check (revision_no > 0),
  compiler_version text not null,
  reason text not null,
  contract_hash text not null,
  composition_contract jsonb not null check (jsonb_typeof(composition_contract)='object'),
  created_at timestamptz not null default now(),
  unique(spread_instance_id,revision_no),
  unique(spread_instance_id,contract_hash)
);

comment on table atlas.notebook_spread_composition_revisions is
  'History-preserving notebook composition contracts. Source facts stay in their source domains; this table preserves page meaning and spatial continuity.';

revoke all on atlas.notebook_spread_composition_revisions from public,anon,authenticated;
grant select,insert on atlas.notebook_spread_composition_revisions to service_role;

create index notebook_spread_composition_revisions_spread_idx
  on atlas.notebook_spread_composition_revisions(spread_instance_id,revision_no desc);

drop function if exists public.notebook_spread_interpreter_spec_service_v2();
drop function if exists public.notebook_spread_creation_policy_service_v1(text,jsonb);
drop function if exists public.interpret_notebook_spread_intent_service_v2(uuid,jsonb,text,text);
drop function if exists atlas.interpret_notebook_spread_intent_serv_v2(uuid,jsonb,text,text);

create or replace function atlas.notebook_spread_interpreter_spec_v3()
returns jsonb
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select jsonb_build_object(
    'contractVersion','notebook_spread_intent_v3',
    'objective','Extract subject, purpose, horizon, retrieval needs, relationship needs, source candidates, and ambiguity. Do not decide persistence, source authority, notebook forms, or layout.',
    'utteranceModes',jsonb_build_array('point_lookup','broad_retrieval','fact_statement','sustained_intent','explicit_persistence','continuation','unclear'),
    'retrievalNeedKinds',jsonb_build_array('point_lookup','history','pattern','progress','cadence','collection','sequence','comparison','coordination','reference','monitoring'),
    'relationshipKinds',jsonb_build_array('state','plan','progress','requirement','constraint','window','threshold','sequence','cadence','accumulation','comparison','relationship','place','evidence','exception','memory','action'),
    'rules',jsonb_build_array(
      'Preserve literal evidence with literal_span basis whenever possible.',
      'Resolve relative time with calendar_resolution basis.',
      'relationshipNeeds describe why information matters; they do not select a renderer.',
      'Do not emit recipeCandidate, formFamily, patternKey, resolutionAction, or creationAuthority.',
      'Do not mark any external source established; emit sourceCandidates only.'
    ),
    'truthBoundary',jsonb_build_object(
      'interpreterDoesNotDecidePersistence',true,
      'interpreterDoesNotEstablishSourceAuthority',true,
      'interpreterDoesNotChooseNotebookForms',true,
      'interpreterDoesNotChooseCompositionPattern',true
    )
  );
$function$;

revoke all on function atlas.notebook_spread_interpreter_spec_v3() from public,anon,authenticated;

create or replace function public.notebook_spread_interpreter_spec_service_v3()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_interpreter_spec_v3();
$function$;
revoke all on function public.notebook_spread_interpreter_spec_service_v3() from public,anon,authenticated;
grant execute on function public.notebook_spread_interpreter_spec_service_v3() to service_role;

create or replace function atlas.validate_notebook_spread_intent_v3(p_literal text,p_interpretation jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_base jsonb;
  v_base_validation jsonb;
  v_violations jsonb;
  v_warnings jsonb;
  v_item jsonb;
  v_check jsonb;
  v_kind text;
  v_blocking integer;
begin
  if p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then
    return jsonb_build_object('validationState','rejected','violations',jsonb_build_array(jsonb_build_object('key','interpretation_object_required')),'warnings','[]'::jsonb,'blockingAmbiguityCount',0);
  end if;

  v_base := (p_interpretation - 'relationshipNeeds' - 'recipeCandidate') || jsonb_build_object('contractVersion','notebook_spread_intent_v2');
  v_base_validation := atlas.validate_notebook_spread_intent_v2(p_literal,v_base);
  v_violations := coalesce(v_base_validation->'violations','[]'::jsonb);
  v_warnings := coalesce(v_base_validation->'warnings','[]'::jsonb);
  v_blocking := coalesce((v_base_validation->>'blockingAmbiguityCount')::integer,0);

  if p_interpretation->>'contractVersion'<>'notebook_spread_intent_v3' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','unsupported_contract_version','value',p_interpretation->>'contractVersion'));
  end if;
  if p_interpretation ? 'recipeCandidate' or p_interpretation ? 'formFamily' or p_interpretation ? 'patternKey' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','interpreter_may_not_choose_composition'));
  end if;
  if not (p_interpretation ? 'relationshipNeeds') or jsonb_typeof(p_interpretation->'relationshipNeeds')<>'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','relationship_needs_array_required'));
  else
    for v_item in select value from jsonb_array_elements(p_interpretation->'relationshipNeeds') loop
      v_kind := v_item->>'kind';
      if jsonb_typeof(v_item)<>'object' or v_kind is null or v_kind not in (
        'state','plan','progress','requirement','constraint','window','threshold','sequence','cadence','accumulation','comparison','relationship','place','evidence','exception','memory','action'
      ) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_relationship_need','item',v_item));
      else
        v_check := atlas.notebook_spread_intent_basis_validation_v1(p_literal,v_item->'basis');
        if not coalesce((v_check->>'ok')::boolean,false) then
          v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','invalid_relationship_need_basis','item',v_item,'detail',v_check));
        end if;
      end if;
    end loop;
  end if;

  return jsonb_build_object(
    'validationState',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'violations',v_violations,'warnings',v_warnings,'blockingAmbiguityCount',v_blocking,
    'truthBoundary',jsonb_build_object(
      'interpreterDoesNotDecidePersistence',true,
      'interpreterDoesNotChooseComposition',true,
      'interpreterDoesNotEstablishSourceAuthority',true
    )
  );
end;
$function$;
revoke all on function atlas.validate_notebook_spread_intent_v3(text,jsonb) from public,anon,authenticated;

create or replace function atlas.notebook_spread_creation_policy_v2(p_literal text,p_interpretation jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas'
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
  v_validation := atlas.validate_notebook_spread_intent_v3(p_literal,p_interpretation);
  if v_validation->>'validationState'<>'passed' then
    return jsonb_build_object('policyVersion','notebook_spread_creation_policy_v2','resolutionAction','rejected','creationAuthority','none','reason','invalid_interpretation','validation',v_validation);
  end if;

  v_mode := p_interpretation->>'utteranceMode';
  v_blocking := coalesce((v_validation->>'blockingAmbiguityCount')::integer,0);
  for v_need in select value from jsonb_array_elements(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb)) loop
    if (v_need->>'recurrence') in ('repeated','ongoing')
       and (v_need->>'kind') in ('history','pattern','progress','cadence','collection','sequence','comparison','coordination','reference','monitoring') then
      v_durable_count := v_durable_count + 1;
    end if;
  end loop;

  if v_blocking>0 or v_mode='unclear' then
    v_action:='needs_clarification'; v_authority:='none'; v_reason:=case when v_blocking>0 then 'blocking_ambiguity' else 'unclear_utterance' end;
  elsif v_mode='continuation' then
    v_action:='resolve_or_create'; v_authority:='established_continuation'; v_reason:='existing_spread_thread';
  elsif v_mode='explicit_persistence' then
    v_action:='resolve_or_create'; v_authority:='explicit_persistence'; v_reason:='human_explicitly_requested_persistence';
  elsif v_mode in ('sustained_intent','broad_retrieval') and v_durable_count>0 then
    v_action:='resolve_or_create'; v_authority:='durable_retrieval_need'; v_reason:='repeated_or_ongoing_notebook_retrieval';
  else
    v_action:='no_spread'; v_authority:='none';
    v_reason:=case when v_mode='point_lookup' then 'narrow_point_lookup' when v_mode='fact_statement' then 'fact_without_durable_retrieval_need' else 'no_persistence_authority' end;
  end if;

  if v_action='resolve_or_create' then
    if jsonb_typeof(p_interpretation->'subject')<>'object' then v_missing:=v_missing||'"subject"'::jsonb; end if;
    if jsonb_typeof(p_interpretation->'purpose')<>'object' then v_missing:=v_missing||'"purpose"'::jsonb; end if;
    if jsonb_typeof(p_interpretation->'horizon')<>'object' then v_missing:=v_missing||'"horizon"'::jsonb; end if;
    if nullif(btrim(p_interpretation->>'proposedTitle'),'') is null then v_missing:=v_missing||'"proposedTitle"'::jsonb; end if;
    if nullif(btrim(p_interpretation->>'sectionKey'),'') is null then v_missing:=v_missing||'"sectionKey"'::jsonb; end if;
    if jsonb_array_length(coalesce(p_interpretation->'relationshipNeeds','[]'::jsonb))=0 then v_missing:=v_missing||'"relationshipNeeds"'::jsonb; end if;
    if jsonb_array_length(v_missing)>0 then v_action:='needs_clarification'; v_authority:='none'; v_reason:='durable_page_identity_incomplete'; end if;
  end if;

  return jsonb_build_object(
    'policyVersion','notebook_spread_creation_policy_v2','resolutionAction',v_action,'creationAuthority',v_authority,'reason',v_reason,
    'durableRetrievalNeedCount',v_durable_count,'missingFields',v_missing,'validation',v_validation,
    'truthBoundary',jsonb_build_object('policyNotModelDecidesPersistence',true,'composerNotModelChoosesForms',true,'sourceAuthorityResolvedSeparately',true)
  );
end;
$function$;
revoke all on function atlas.notebook_spread_creation_policy_v2(text,jsonb) from public,anon,authenticated;

create or replace function public.notebook_spread_creation_policy_service_v2(p_literal text,p_interpretation jsonb)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_creation_policy_v2(p_literal,p_interpretation);
$function$;
revoke all on function public.notebook_spread_creation_policy_service_v2(text,jsonb) from public,anon,authenticated;
grant execute on function public.notebook_spread_creation_policy_service_v2(text,jsonb) to service_role;

create or replace function atlas.notebook_intent_has_relationship_v1(p_interpretation jsonb,p_kind text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select exists(select 1 from jsonb_array_elements(coalesce(p_interpretation->'relationshipNeeds','[]'::jsonb)) x where x->>'kind'=p_kind);
$function$;

create or replace function atlas.notebook_intent_has_retrieval_v1(p_interpretation jsonb,p_kind text)
returns boolean
language sql
immutable
set search_path to 'pg_catalog'
as $function$
  select exists(select 1 from jsonb_array_elements(coalesce(p_interpretation->'retrievalNeeds','[]'::jsonb)) x where x->>'kind'=p_kind);
$function$;
revoke all on function atlas.notebook_intent_has_relationship_v1(jsonb,text) from public,anon,authenticated;
revoke all on function atlas.notebook_intent_has_retrieval_v1(jsonb,text) from public,anon,authenticated;

create or replace function atlas.notebook_form_fragment_v1(p_family text,p_role text,p_order integer)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas'
as $function$
  select jsonb_build_object(
    'formFamily',f.form_family,'role',p_role,'order',p_order,
    'supportedRelationships',to_jsonb(f.supported_relationships),
    'emptyBehavior',f.default_empty_behavior,'phoneRule',f.phone_rule
  ) from atlas.notebook_form_registry f where f.form_family=p_family and f.active;
$function$;
revoke all on function atlas.notebook_form_fragment_v1(text,text,integer) from public,anon,authenticated;

create or replace function atlas.compile_notebook_spread_composition_v1(p_spread_instance_id uuid,p_reason text default 'initial_compile')
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  s atlas.notebook_spread_instances%rowtype;
  r atlas.notebook_spread_intent_requests%rowtype;
  i jsonb;
  v_anchor text;
  v_forms jsonb := '[]'::jsonb;
  v_phone jsonb := '[]'::jsonb;
  v_pattern text;
  v_count integer := 0;
  v_path_need boolean;
  v_count_need boolean;
  v_ledger_need boolean;
  v_log_need boolean;
  v_timeline_need boolean;
  v_relational_need boolean;
  v_contract jsonb;
  v_hash text;
  v_prev_hash text;
  v_revision integer;
  v_validation jsonb;
begin
  select * into s from atlas.notebook_spread_instances where id=p_spread_instance_id for update;
  if s.id is null then raise exception 'spread instance not found' using errcode='P0002'; end if;

  select * into r from atlas.notebook_spread_intent_requests
  where spread_instance_id=s.id and request_state='resolved'
  order by updated_at desc,id desc limit 1;
  if r.id is null then raise exception 'resolved spread intent request not found for composition' using errcode='P0002'; end if;
  i := r.interpretation;
  v_validation := atlas.validate_notebook_spread_intent_v3(r.literal_request,i);
  if v_validation->>'validationState'<>'passed' then raise exception 'spread intent is not valid for composition' using errcode='22023'; end if;

  v_path_need := atlas.notebook_intent_has_relationship_v1(i,'progress') and (atlas.notebook_intent_has_relationship_v1(i,'requirement') or atlas.notebook_intent_has_relationship_v1(i,'sequence'));
  v_count_need := atlas.notebook_intent_has_relationship_v1(i,'threshold') or atlas.notebook_intent_has_relationship_v1(i,'accumulation') or (atlas.notebook_intent_has_retrieval_v1(i,'progress') and not v_path_need);
  v_ledger_need := atlas.notebook_intent_has_relationship_v1(i,'comparison') or atlas.notebook_intent_has_retrieval_v1(i,'collection') or atlas.notebook_intent_has_retrieval_v1(i,'comparison') or atlas.notebook_intent_has_retrieval_v1(i,'coordination');
  v_log_need := atlas.notebook_intent_has_relationship_v1(i,'sequence') or atlas.notebook_intent_has_relationship_v1(i,'memory') or atlas.notebook_intent_has_relationship_v1(i,'action') or atlas.notebook_intent_has_retrieval_v1(i,'history') or atlas.notebook_intent_has_retrieval_v1(i,'sequence');
  v_timeline_need := atlas.notebook_intent_has_relationship_v1(i,'window') and (atlas.notebook_intent_has_relationship_v1(i,'constraint') or atlas.notebook_intent_has_relationship_v1(i,'sequence') or atlas.notebook_intent_has_relationship_v1(i,'plan'));
  v_relational_need := atlas.notebook_intent_has_relationship_v1(i,'relationship');

  if atlas.notebook_intent_has_relationship_v1(i,'cadence') or atlas.notebook_intent_has_retrieval_v1(i,'pattern') or atlas.notebook_intent_has_retrieval_v1(i,'cadence') or atlas.notebook_intent_has_retrieval_v1(i,'monitoring') then v_anchor:='field';
  elsif v_ledger_need then v_anchor:='ledger';
  elsif v_relational_need then v_anchor:='relational';
  elsif v_timeline_need then v_anchor:='timeline';
  elsif v_path_need then v_anchor:='path';
  elsif v_count_need then v_anchor:='count';
  elsif v_log_need then v_anchor:='log';
  else v_anchor:='free-field';
  end if;

  v_count:=1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1(v_anchor,'anchor',v_count)); v_phone:=v_phone||jsonb_build_array(v_anchor);

  if v_path_need and v_anchor<>'path' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('path','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('path'); end if;
  if v_count_need and not v_path_need and v_anchor<>'count' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('count','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('count'); end if;
  if v_ledger_need and v_anchor<>'ledger' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('ledger','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('ledger'); end if;
  if v_log_need and v_anchor<>'log' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('log','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('log'); end if;
  if v_timeline_need and v_anchor<>'timeline' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('timeline','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('timeline'); end if;
  if v_relational_need and v_anchor<>'relational' and v_count<3 then v_count:=v_count+1; v_forms:=v_forms||jsonb_build_array(atlas.notebook_form_fragment_v1('relational','supporting',v_count)); v_phone:=v_phone||jsonb_build_array('relational'); end if;

  if v_count=1 then v_pattern:='single-form-continuation';
  elsif v_anchor='field' and (v_forms @> '[{"formFamily":"count"}]'::jsonb) then v_pattern:='reference-working-field';
  elsif v_anchor='relational' then v_pattern:='sparse-relational';
  elsif (v_forms @> '[{"formFamily":"field"}]'::jsonb) and (v_forms @> '[{"formFamily":"timeline"}]'::jsonb) then v_pattern:='orientation-pattern-field';
  elsif atlas.notebook_intent_has_retrieval_v1(i,'comparison') and v_count=2 then v_pattern:='paired-comparison';
  else v_pattern:='dominant-supporting-pair';
  end if;

  v_contract := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey',v_pattern,
    'forms',v_forms,
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',v_count-1,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',v_phone,
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('intentRequestId',r.id,'relationshipNeeds',i->'relationshipNeeds','retrievalNeeds',i->'retrievalNeeds')
  );
  v_hash:=md5(v_contract::text);
  select contract_hash into v_prev_hash from atlas.notebook_spread_composition_revisions where spread_instance_id=s.id order by revision_no desc limit 1;
  if v_prev_hash=v_hash then
    update atlas.notebook_spread_instances set composition_contract=v_contract,updated_at=now() where id=s.id;
    return jsonb_build_object('ok',true,'changed',false,'spreadInstanceId',s.id,'compositionContract',v_contract);
  end if;

  select coalesce(max(revision_no),0)+1 into v_revision from atlas.notebook_spread_composition_revisions where spread_instance_id=s.id;
  insert into atlas.notebook_spread_composition_revisions(spread_instance_id,intent_request_id,revision_no,compiler_version,reason,contract_hash,composition_contract)
  values(s.id,r.id,v_revision,'notebook_spread_composer_v1',coalesce(nullif(btrim(p_reason),''),'compile'),v_hash,v_contract);
  update atlas.notebook_spread_instances set composition_contract=v_contract,recipe_key=null,updated_at=now() where id=s.id;

  return jsonb_build_object('ok',true,'changed',true,'spreadInstanceId',s.id,'revisionNo',v_revision,'compositionContract',v_contract,
    'truthBoundary',jsonb_build_object('composerOwnsPresentationOnly',true,'noDomainTemplateSelected',true,'sourceTruthUnchanged',true));
end;
$function$;
revoke all on function atlas.compile_notebook_spread_composition_v1(uuid,text) from public,anon,authenticated,service_role;

create or replace function public.compile_notebook_spread_composition_service_v1(p_spread_instance_id uuid,p_reason text default 'manual_recompile')
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.compile_notebook_spread_composition_v1(p_spread_instance_id,p_reason);
$function$;
revoke all on function public.compile_notebook_spread_composition_service_v1(uuid,text) from public,anon,authenticated;
grant execute on function public.compile_notebook_spread_composition_service_v1(uuid,text) to service_role;

create or replace function atlas.interpret_notebook_spread_intent_serv_v3(
  p_request_id uuid,p_interpretation jsonb,p_interpreter_kind text,p_interpreter_ref text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  r atlas.notebook_spread_intent_requests%rowtype;
  policy jsonb; action text; subject jsonb; purpose jsonb; horizon jsonb;
  creation_mode text; spread_key text; thread_key text; spread_result jsonb; spread_id uuid; composition jsonb;
begin
  if p_request_id is null or p_interpretation is null or jsonb_typeof(p_interpretation)<>'object' then raise exception 'request id and interpretation object are required' using errcode='22023'; end if;
  if p_interpreter_kind not in ('ai','rule','self_authenticated','import') or nullif(btrim(p_interpreter_ref),'') is null then raise exception 'trusted interpreter provenance is required' using errcode='22023'; end if;
  select * into r from atlas.notebook_spread_intent_requests x where x.id=p_request_id for update;
  if r.id is null then raise exception 'Notebook spread intent request not found.' using errcode='P0002'; end if;
  if r.request_state<>'captured' then
    if r.interpretation is distinct from p_interpretation or r.interpreter_kind is distinct from p_interpreter_kind or r.interpreter_ref is distinct from p_interpreter_ref then raise exception 'Interpretation retry does not match resolved notebook spread intent request.' using errcode='23505'; end if;
    return jsonb_build_object('ok',true,'changed',false,'requestId',r.id,'requestState',r.request_state,'spreadInstanceId',r.spread_instance_id,'policyDecision',r.policy_decision);
  end if;

  policy:=atlas.notebook_spread_creation_policy_v2(r.literal_request,p_interpretation); action:=policy->>'resolutionAction';
  if action in ('rejected','no_spread','needs_clarification') then
    update atlas.notebook_spread_intent_requests set
      request_state=case action when 'rejected' then 'rejected' when 'no_spread' then 'no_spread' else 'needs_clarification' end,
      interpretation=p_interpretation,validation=policy->'validation',policy_decision=policy,
      interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),updated_at=now()
    where id=r.id returning * into r;
    return jsonb_build_object('ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v3','requestId',r.id,'requestState',r.request_state,'policyDecision',policy,'spreadInstanceId',null);
  end if;

  subject:=p_interpretation->'subject'; purpose:=p_interpretation->'purpose'; horizon:=p_interpretation->'horizon';
  creation_mode:=case policy->>'creationAuthority' when 'explicit_persistence' then 'explicit' when 'established_continuation' then 'continuation' else 'resolved' end;
  spread_key:='spread:'||gen_random_uuid()::text;
  thread_key:=case when creation_mode='continuation' then p_interpretation#>>'{continuation,threadKey}' else 'thread:'||gen_random_uuid()::text end;
  spread_result:=atlas.resolve_notebook_spread_instance_v2(
    r.principal_id,spread_key,'person',r.owner_user_id::text,
    subject->>'domain',subject->>'kind',subject->>'id',purpose->>'key',horizon->>'key',thread_key,
    p_interpretation->>'proposedTitle',p_interpretation->>'sectionKey',null,creation_mode,'{}'::jsonb,
    jsonb_build_object('notebookSpreadIntentRequestId',r.id,'creationAuthority',policy->>'creationAuthority','subjectBasis',subject->'basis','purposeBasis',purpose->'basis','horizonBasis',horizon->'basis'),
    jsonb_build_object('retrievalNeeds',p_interpretation->'retrievalNeeds','relationshipNeeds',p_interpretation->'relationshipNeeds','unresolvedSourceCandidates',coalesce(p_interpretation->'sourceCandidates','[]'::jsonb))
  );
  spread_id:=(spread_result->>'spreadInstanceId')::uuid;
  update atlas.notebook_spread_intent_requests set request_state='resolved',interpretation=p_interpretation,validation=policy->'validation',policy_decision=policy,interpreter_kind=p_interpreter_kind,interpreter_ref=btrim(p_interpreter_ref),spread_instance_id=spread_id,updated_at=now() where id=r.id returning * into r;
  composition:=atlas.compile_notebook_spread_composition_v1(spread_id,'spread_birth');
  return jsonb_build_object('ok',true,'changed',true,'contractVersion','notebook_spread_intent_resolution_v3','requestId',r.id,'requestState','resolved','spreadInstanceId',spread_id,'spread',spread_result,'composition',composition,'policyDecision',policy,'sourceCandidates',coalesce(p_interpretation->'sourceCandidates','[]'::jsonb),
    'truthBoundary',jsonb_build_object('policyNotInterpreterGrantedCreationAuthority',true,'composerNotInterpreterChoseForms',true,'interpreterCreatedNoSourceBindings',true,'sourceCandidatesRequireSeparateDomainResolution',true));
end;
$function$;
revoke all on function atlas.interpret_notebook_spread_intent_serv_v3(uuid,jsonb,text,text) from public,anon,authenticated,service_role;

create or replace function public.interpret_notebook_spread_intent_service_v3(p_request_id uuid,p_interpretation jsonb,p_interpreter_kind text,p_interpreter_ref text)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.interpret_notebook_spread_intent_serv_v3(p_request_id,p_interpretation,p_interpreter_kind,p_interpreter_ref);
$function$;
revoke all on function public.interpret_notebook_spread_intent_service_v3(uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.interpret_notebook_spread_intent_service_v3(uuid,jsonb,text,text) to service_role;

commit;