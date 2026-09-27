-- Atlas Implementation Workbench v1
--
-- Universal manual/assisted sentence custody and deterministic routing.
-- Workbench owns no Foundry truth, canonical Reality authority, domain execution
-- warrant, or effects. It routes typed intent to an explicitly registered membrane.

create table atlas.workbench_operation_registry (
  operation_key text primary key check (btrim(operation_key)<>''),
  route_class text not null check (route_class in ('DISCOVER','ESTABLISH','ACT')),
  destination_membrane text not null check (btrim(destination_membrane)<>''),
  destination_operation text not null check (btrim(destination_operation)<>''),
  requires_destination_input boolean not null default true,
  requires_operation_contract boolean not null default false,
  human_route_confirmation_required boolean not null default true
    check (human_route_confirmation_required),
  truth_boundary jsonb not null default '{}'::jsonb
    check (jsonb_typeof(truth_boundary)='object'),
  registry_state text not null default 'active'
    check (registry_state in ('active','retired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((route_class='ACT') = requires_operation_contract)
);

insert into atlas.workbench_operation_registry(
  operation_key,route_class,destination_membrane,destination_operation,
  requires_destination_input,requires_operation_contract,truth_boundary
) values
(
  'discover.record_testimony','DISCOVER','foundry.service','record_testimony',
  true,false,
  '{"foundryOnly":true,"canonicalAtlasWrite":false,"destinationOwnsAdjudication":true}'::jsonb
),
(
  'discover.submit_candidate_assertions','DISCOVER','foundry.service','submit_candidate_assertions',
  true,false,
  '{"foundryOnly":true,"candidateIsNotEstablishedReality":true,"canonicalAtlasWrite":false}'::jsonb
),
(
  'discover.open_case','DISCOVER','foundry.service','open_case',
  true,false,
  '{"foundryOnly":true,"caseDoesNotEstablishTruth":true,"canonicalAtlasWrite":false}'::jsonb
),
(
  'discover.request_case_adjudication','DISCOVER','foundry.service','request_case_adjudication',
  true,false,
  '{"foundryOnly":true,"carrierCannotDictateAdjudication":true,"canonicalAtlasWrite":false}'::jsonb
),
(
  'establish.foundry_admission_plan','ESTABLISH','atlas.foundry_admission','plan',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"workbenchAuthorityDoesNotGrantAdmissionAuthority":true,"ledgerActivation":false}'::jsonb
),
(
  'establish.foundry_admission_handoff','ESTABLISH','atlas.foundry_admission','handoff',
  true,false,
  '{"canonicalTruthMayChangeOnlyInDestination":true,"workbenchAuthorityDoesNotGrantAdmissionAuthority":true,"ledgerActivation":false}'::jsonb
),
(
  'establish.reality_identity_merge_proposal','ESTABLISH','reality.entity_reconciliation','propose',
  true,false,
  '{"canonicalMergeExecution":false,"proposalIsNotConfirmation":true,"destinationOwnsMergeAuthority":true}'::jsonb
),
(
  'establish.reality_identity_merge_confirmation','ESTABLISH','reality.entity_reconciliation','confirm',
  true,false,
  '{"canonicalMergeMayOccurOnlyInDestination":true,"workbenchAuthorityDoesNotGrantMergeAuthority":true,"destinationOwnsAtomicExecution":true}'::jsonb
),
(
  'act.governed_operation','ACT','atlas.operation_contract','registered_domain_command',
  true,true,
  '{"workbenchExecutesEffects":false,"operationContractIsPreviewNotWarrant":true,"destinationCommandOwnsAuthorityAndEffects":true}'::jsonb
);

alter table atlas.workbench_operation_registry enable row level security;
revoke all on table atlas.workbench_operation_registry
  from public,anon,authenticated,service_role;


create table atlas.workbench_intents (
  id uuid primary key default gen_random_uuid(),
  composed_by_person_entity_id uuid not null
    references reality.entities(id) on delete restrict,
  idempotency_key text not null check (btrim(idempotency_key)<>''),
  literal_request text not null check (btrim(literal_request)<>''),
  normalized_sentence jsonb not null check (jsonb_typeof(normalized_sentence)='object'),
  operation_key text not null
    references atlas.workbench_operation_registry(operation_key) on delete restrict,
  route_class text not null check (route_class in ('DISCOVER','ESTABLISH','ACT')),
  intent_state text not null default 'COMPOSED'
    check (intent_state in ('COMPOSED','PREVIEWED','ROUTED','CANCELLED')),
  carrier_metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(carrier_metadata)='object'),
  preview_snapshot jsonb not null default '{}'::jsonb
    check (jsonb_typeof(preview_snapshot)='object'),
  route_receipt jsonb not null default '{}'::jsonb
    check (jsonb_typeof(route_receipt)='object'),
  supersedes_intent_id uuid null
    references atlas.workbench_intents(id) on delete restrict,
  routed_by_person_entity_id uuid null
    references reality.entities(id) on delete restrict,
  route_confirmation_basis text null,
  previewed_at timestamptz null,
  routed_at timestamptz null,
  cancelled_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(composed_by_person_entity_id,idempotency_key),
  check (supersedes_intent_id is null or supersedes_intent_id<>id),
  check (
    (intent_state='COMPOSED'
      and routed_at is null and cancelled_at is null)
    or
    (intent_state='PREVIEWED'
      and previewed_at is not null and routed_at is null and cancelled_at is null)
    or
    (intent_state='ROUTED'
      and previewed_at is not null and routed_at is not null
      and routed_by_person_entity_id is not null
      and route_confirmation_basis is not null
      and btrim(route_confirmation_basis)<>''
      and route_receipt<>'{}'::jsonb
      and cancelled_at is null)
    or
    (intent_state='CANCELLED'
      and cancelled_at is not null and routed_at is null)
  )
);

create unique index atlas_workbench_intents_one_successor_idx
  on atlas.workbench_intents(supersedes_intent_id)
  where supersedes_intent_id is not null;
create index atlas_workbench_intents_person_state_idx
  on atlas.workbench_intents(composed_by_person_entity_id,intent_state,created_at desc);
create index atlas_workbench_intents_operation_idx
  on atlas.workbench_intents(operation_key,created_at desc);

alter table atlas.workbench_intents enable row level security;
revoke all on table atlas.workbench_intents
  from public,anon,authenticated,service_role;


create or replace function atlas.guard_workbench_operation_registry_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    if old.operation_key is distinct from new.operation_key
       or old.route_class is distinct from new.route_class
       or old.destination_membrane is distinct from new.destination_membrane
       or old.destination_operation is distinct from new.destination_operation
       or old.requires_destination_input is distinct from new.requires_destination_input
       or old.requires_operation_contract is distinct from new.requires_operation_contract
       or old.human_route_confirmation_required is distinct from new.human_route_confirmation_required
       or old.truth_boundary is distinct from new.truth_boundary then
      raise exception 'Workbench operation contract is immutable; retire and add a new operation key.'
        using errcode='23514';
    end if;
    new.updated_at:=now();
  end if;
  return new;
end
$function$;

create trigger atlas_workbench_operation_registry_guard_v1
before update on atlas.workbench_operation_registry
for each row execute function atlas.guard_workbench_operation_registry_v1();


create or replace function atlas.guard_workbench_intent_v1()
returns trigger
language plpgsql
set search_path=''
as $function$
begin
  if tg_op='UPDATE' then
    if old.composed_by_person_entity_id is distinct from new.composed_by_person_entity_id
       or old.idempotency_key is distinct from new.idempotency_key
       or old.literal_request is distinct from new.literal_request
       or old.normalized_sentence is distinct from new.normalized_sentence
       or old.operation_key is distinct from new.operation_key
       or old.route_class is distinct from new.route_class
       or old.carrier_metadata is distinct from new.carrier_metadata
       or old.supersedes_intent_id is distinct from new.supersedes_intent_id then
      raise exception 'Workbench sentence custody is immutable; create a superseding intent.'
        using errcode='23514';
    end if;

    if old.intent_state in ('ROUTED','CANCELLED') then
      raise exception 'Terminal Workbench intent is immutable.' using errcode='23514';
    end if;

    if old.intent_state='COMPOSED'
       and new.intent_state not in ('COMPOSED','PREVIEWED','CANCELLED') then
      raise exception 'Invalid Workbench intent transition.' using errcode='23514';
    end if;

    if old.intent_state='PREVIEWED'
       and new.intent_state not in ('PREVIEWED','ROUTED','CANCELLED') then
      raise exception 'Invalid Workbench intent transition.' using errcode='23514';
    end if;
  end if;

  new.updated_at:=now();
  return new;
end
$function$;

create trigger atlas_workbench_intent_guard_v1
before update on atlas.workbench_intents
for each row execute function atlas.guard_workbench_intent_v1();


create or replace function atlas.workbench_sentence_normalize_v1(p_sentence jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path=''
as $function$
declare
  v_operator jsonb;
  v_operation_key text;
  v_field text;
begin
  if p_sentence is null or jsonb_typeof(p_sentence)<>'object' then
    raise exception 'Workbench sentence must be a JSON object.' using errcode='22023';
  end if;

  if jsonb_typeof(p_sentence->'subject')<>'object' then
    raise exception 'Workbench sentence requires object subject.' using errcode='22023';
  end if;

  v_operator:=p_sentence->'operator';
  if jsonb_typeof(v_operator)<>'object' then
    raise exception 'Workbench sentence requires object operator.' using errcode='22023';
  end if;

  v_operation_key:=nullif(btrim(v_operator->>'operationKey'),'');
  if v_operation_key is null then
    raise exception 'Workbench operator.operationKey is required.' using errcode='22023';
  end if;

  foreach v_field in array array['source','object','scope','time','qualifiers','destinationInput','operationContract'] loop
    if p_sentence ? v_field
       and p_sentence->v_field is not null
       and p_sentence->v_field<>'null'::jsonb
       and jsonb_typeof(p_sentence->v_field)<>'object' then
      raise exception 'Workbench sentence %. must be a JSON object when supplied.',v_field
        using errcode='22023';
    end if;
  end loop;

  if p_sentence ? 'basis'
     and p_sentence->'basis' is not null
     and p_sentence->'basis'<>'null'::jsonb
     and jsonb_typeof(p_sentence->'basis') not in ('object','array') then
    raise exception 'Workbench sentence basis must be an object or array when supplied.'
      using errcode='22023';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'contractVersion','atlas_workbench_sentence_v1',
    'source',p_sentence->'source',
    'subject',p_sentence->'subject',
    'operator',jsonb_set(v_operator,'{operationKey}',to_jsonb(v_operation_key),true),
    'object',p_sentence->'object',
    'scope',p_sentence->'scope',
    'time',p_sentence->'time',
    'qualifiers',p_sentence->'qualifiers',
    'basis',p_sentence->'basis',
    'destinationInput',p_sentence->'destinationInput',
    'operationContract',p_sentence->'operationContract'
  ));
end
$function$;

revoke all on function atlas.workbench_sentence_normalize_v1(jsonb)
  from public,anon,authenticated,service_role;


create or replace function atlas.workbench_operation_catalog_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_items jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null or not exists(
    select 1 from reality.entities e
    where e.id=v_person_id and e.entity_kind='person' and e.identity_state='canonical'
  ) then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'operationKey',r.operation_key,
    'route',r.route_class,
    'destinationMembrane',r.destination_membrane,
    'destinationOperation',r.destination_operation,
    'requiresDestinationInput',r.requires_destination_input,
    'requiresOperationContract',r.requires_operation_contract,
    'humanRouteConfirmationRequired',r.human_route_confirmation_required,
    'truthBoundary',r.truth_boundary
  ) order by r.route_class,r.operation_key),'[]'::jsonb)
  into v_items
  from atlas.workbench_operation_registry r
  where r.registry_state='active';

  return jsonb_build_object(
    'contractVersion','atlas_implementation_workbench_v1',
    'state','ready',
    'personEntityId',v_person_id,
    'operations',v_items,
    'truthBoundary',jsonb_build_object(
      'catalogDoesNotGrantDestinationAuthority',true,
      'unknownOperationKeysFailClosed',true,
      'genericCrudExposed',false
    )
  );
end
$function$;

revoke all on function atlas.workbench_operation_catalog_api_v1()
  from public,anon,service_role;
grant execute on function atlas.workbench_operation_catalog_api_v1()
  to authenticated;


create or replace function atlas.workbench_compose_intent_api_v1(
  p_literal_request text,
  p_sentence jsonb,
  p_idempotency_key text,
  p_carrier_metadata jsonb default '{}'::jsonb,
  p_supersedes_intent_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_sentence jsonb;
  v_operation_key text;
  v_registry atlas.workbench_operation_registry%rowtype;
  v_existing atlas.workbench_intents%rowtype;
  v_prior atlas.workbench_intents%rowtype;
  v_row atlas.workbench_intents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null or not exists(
    select 1 from reality.entities e
    where e.id=v_person_id and e.entity_kind='person' and e.identity_state='canonical'
  ) then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_literal_request,'')),'') is null then
    raise exception 'Literal request is required.' using errcode='22023';
  end if;
  if length(p_literal_request)>16000 then
    raise exception 'Literal request is too long.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_idempotency_key,'')),'') is null then
    raise exception 'Workbench idempotency key is required.' using errcode='22023';
  end if;
  if p_carrier_metadata is null or jsonb_typeof(p_carrier_metadata)<>'object' then
    raise exception 'Carrier metadata must be a JSON object.' using errcode='22023';
  end if;

  v_sentence:=atlas.workbench_sentence_normalize_v1(p_sentence);
  v_operation_key:=v_sentence#>>'{operator,operationKey}';

  select * into v_registry
  from atlas.workbench_operation_registry r
  where r.operation_key=v_operation_key and r.registry_state='active';

  if not found then
    raise exception 'Workbench operation key is not registered: %',v_operation_key
      using errcode='22023';
  end if;

  select * into v_existing
  from atlas.workbench_intents i
  where i.composed_by_person_entity_id=v_person_id
    and i.idempotency_key=btrim(p_idempotency_key);

  if found then
    if v_existing.literal_request<>p_literal_request
       or v_existing.normalized_sentence<>v_sentence
       or v_existing.carrier_metadata<>p_carrier_metadata
       or v_existing.supersedes_intent_id is distinct from p_supersedes_intent_id then
      raise exception 'Workbench idempotency key was reused for different content.'
        using errcode='23505';
    end if;

    return jsonb_build_object(
      'contractVersion','atlas_implementation_workbench_v1',
      'state','already_composed',
      'intentId',v_existing.id,
      'intentState',v_existing.intent_state,
      'operationKey',v_existing.operation_key,
      'route',v_existing.route_class,
      'canonicalTruthChanged',false,
      'effectExecuted',false
    );
  end if;

  if p_supersedes_intent_id is not null then
    select * into v_prior
    from atlas.workbench_intents
    where id=p_supersedes_intent_id;

    if not found or v_prior.composed_by_person_entity_id<>v_person_id then
      raise exception 'Superseded Workbench intent must belong to the same canonical Person.'
        using errcode='42501';
    end if;
  end if;

  insert into atlas.workbench_intents(
    composed_by_person_entity_id,idempotency_key,literal_request,
    normalized_sentence,operation_key,route_class,carrier_metadata,supersedes_intent_id
  ) values (
    v_person_id,btrim(p_idempotency_key),p_literal_request,
    v_sentence,v_registry.operation_key,v_registry.route_class,p_carrier_metadata,p_supersedes_intent_id
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','atlas_implementation_workbench_v1',
    'state','composed',
    'intentId',v_row.id,
    'intentState',v_row.intent_state,
    'operationKey',v_row.operation_key,
    'route',v_row.route_class,
    'canonicalTruthChanged',false,
    'effectExecuted',false
  );
end
$function$;

revoke all on function atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)
  from public,anon,service_role;
grant execute on function atlas.workbench_compose_intent_api_v1(text,jsonb,text,jsonb,uuid)
  to authenticated;


create or replace function atlas.workbench_preview_internal_v1(p_intent_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_intent atlas.workbench_intents%rowtype;
  v_registry atlas.workbench_operation_registry%rowtype;
  v_blockers jsonb:='[]'::jsonb;
  v_destination_input jsonb;
  v_operation_contract_input jsonb;
  v_operation_contract jsonb:=null;
  v_contract_error text:=null;
begin
  select * into v_intent
  from atlas.workbench_intents i
  where i.id=p_intent_id;
  if not found then
    raise exception 'Workbench intent not found.' using errcode='P0002';
  end if;

  select * into v_registry
  from atlas.workbench_operation_registry r
  where r.operation_key=v_intent.operation_key;
  if not found or v_registry.registry_state<>'active' then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','OPERATION_NOT_ACTIVE','message','The registered operation is not active.'
    ));
  elsif v_registry.route_class<>v_intent.route_class then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','ROUTE_REGISTRY_MISMATCH','message','Stored route no longer matches its registry contract.'
    ));
  end if;

  if v_intent.intent_state in ('ROUTED','CANCELLED') then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','INTENT_TERMINAL','message','Terminal Workbench intent cannot be routed again.'
    ));
  end if;

  v_destination_input:=v_intent.normalized_sentence->'destinationInput';
  if v_registry.requires_destination_input
     and (v_destination_input is null or jsonb_typeof(v_destination_input)<>'object') then
    v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
      'code','DESTINATION_INPUT_REQUIRED',
      'message','This registered operation requires typed destinationInput.'
    ));
  end if;

  if v_intent.route_class='ACT' then
    v_operation_contract_input:=v_intent.normalized_sentence->'operationContract';
    if v_operation_contract_input is null
       or jsonb_typeof(v_operation_contract_input)<>'object' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','OPERATION_CONTRACT_REQUIRED',
        'message','ACT routing requires an explicit Operation Contract input.'
      ));
    else
      begin
        v_operation_contract:=atlas.operation_contract_normalize_v1(v_operation_contract_input);
      exception when others then
        v_contract_error:=sqlerrm;
        v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
          'code','OPERATION_CONTRACT_INVALID',
          'message',v_contract_error
        ));
      end;
    end if;

    if v_destination_input is not null
       and jsonb_typeof(v_destination_input)='object'
       and nullif(btrim(v_destination_input->>'commandContractKey'),'') is null then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','GOVERNED_COMMAND_CONTRACT_REQUIRED',
        'message','ACT destinationInput must identify an existing governed commandContractKey.'
      ));
    end if;

    if v_destination_input ?| array['sql','query','table','schema','function','functionName','crud'] then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','GENERIC_MUTATION_SURFACE_FORBIDDEN',
        'message','Workbench ACT routing cannot accept SQL, table, function, or generic CRUD targets.'
      ));
    end if;
  else
    if v_intent.normalized_sentence ? 'operationContract' then
      v_blockers:=v_blockers||jsonb_build_array(jsonb_build_object(
        'code','OPERATION_CONTRACT_ROUTE_MISMATCH',
        'message','Operation Contract belongs only to ACT routing.'
      ));
    end if;
  end if;

  return jsonb_build_object(
    'contractVersion','atlas_implementation_workbench_v1',
    'intentId',v_intent.id,
    'intentState',v_intent.intent_state,
    'actorPersonEntityId',v_intent.composed_by_person_entity_id,
    'literalRequest',v_intent.literal_request,
    'sentence',v_intent.normalized_sentence,
    'operationKey',v_intent.operation_key,
    'route',v_intent.route_class,
    'destination',jsonb_build_object(
      'membrane',v_registry.destination_membrane,
      'operation',v_registry.destination_operation,
      'input',v_destination_input
    ),
    'operationContract',v_operation_contract,
    'destinationTruthBoundary',v_registry.truth_boundary,
    'humanRouteConfirmationRequired',v_registry.human_route_confirmation_required,
    'blockers',v_blockers,
    'canRoute',jsonb_array_length(v_blockers)=0,
    'workbenchTruthBoundary',jsonb_build_object(
      'routeConfirmationIsNotTruthConfirmation',true,
      'routeConfirmationIsNotExecutionWarrant',true,
      'workbenchDoesNotGrantDestinationAuthority',true,
      'workbenchDoesNotExecuteEffects',true,
      'canonicalAtlasWriteOccurred',false,
      'genericCrudExposed',false
    )
  );
end
$function$;

revoke all on function atlas.workbench_preview_internal_v1(uuid)
  from public,anon,authenticated,service_role;


create or replace function atlas.workbench_preview_intent_api_v1(p_intent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_intent atlas.workbench_intents%rowtype;
  v_preview jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_person_id:=atlas.current_person_id_v1();

  select * into v_intent
  from atlas.workbench_intents i
  where i.id=p_intent_id;
  if not found then
    raise exception 'Workbench intent not found.' using errcode='P0002';
  end if;
  if v_person_id is null or v_intent.composed_by_person_entity_id<>v_person_id then
    raise exception 'Workbench intent belongs to another Person.' using errcode='42501';
  end if;
  if v_intent.intent_state in ('ROUTED','CANCELLED') then
    raise exception 'Terminal Workbench intent cannot be previewed.' using errcode='23514';
  end if;

  v_preview:=atlas.workbench_preview_internal_v1(p_intent_id);

  update atlas.workbench_intents
  set intent_state='PREVIEWED',preview_snapshot=v_preview,previewed_at=now()
  where id=p_intent_id;

  return v_preview || jsonb_build_object('state','previewed');
end
$function$;

revoke all on function atlas.workbench_preview_intent_api_v1(uuid)
  from public,anon,service_role;
grant execute on function atlas.workbench_preview_intent_api_v1(uuid)
  to authenticated;


create or replace function atlas.workbench_route_intent_api_v1(
  p_intent_id uuid,
  p_confirmation_basis text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','reality'
as $function$
declare
  v_person_id uuid;
  v_intent atlas.workbench_intents%rowtype;
  v_preview jsonb;
  v_receipt jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  if nullif(btrim(coalesce(p_confirmation_basis,'')),'') is null then
    raise exception 'Explicit route confirmation basis is required.' using errcode='22023';
  end if;
  if length(p_confirmation_basis)>8000 then
    raise exception 'Route confirmation basis is too long.' using errcode='22023';
  end if;

  select * into v_intent
  from atlas.workbench_intents i
  where i.id=p_intent_id
  for update;
  if not found then
    raise exception 'Workbench intent not found.' using errcode='P0002';
  end if;
  if v_intent.composed_by_person_entity_id<>v_person_id then
    raise exception 'Only the composing Person may route this v1 Workbench intent.'
      using errcode='42501';
  end if;
  if v_intent.intent_state not in ('COMPOSED','PREVIEWED') then
    raise exception 'Workbench intent is terminal.' using errcode='23514';
  end if;

  v_preview:=atlas.workbench_preview_internal_v1(p_intent_id);
  if coalesce((v_preview->>'canRoute')::boolean,false) is not true then
    raise exception 'Workbench intent has routing blockers: %',v_preview->'blockers'
      using errcode='23514';
  end if;

  v_receipt:=jsonb_build_object(
    'contractVersion','atlas_workbench_route_receipt_v1',
    'intentId',v_intent.id,
    'routedAt',now(),
    'routedByPersonEntityId',v_person_id,
    'routeConfirmationBasis',p_confirmation_basis,
    'route',v_intent.route_class,
    'operationKey',v_intent.operation_key,
    'destination',v_preview->'destination',
    'sentence',v_intent.normalized_sentence,
    'operationContract',v_preview->'operationContract',
    'preview',v_preview,
    'carrierMetadata',v_intent.carrier_metadata,
    'destinationExecutionOccurred',false,
    'canonicalTruthChangedByWorkbench',false,
    'destinationAuthoritySatisfiedByRouting',false,
    'nextStep',case v_intent.route_class
      when 'DISCOVER' then 'submit_envelope_to_governed_foundry_service'
      when 'ESTABLISH' then 'submit_envelope_to_named_atlas_authority_membrane'
      when 'ACT' then 'submit_operation_contract_to_registered_governed_domain_command'
    end
  );

  update atlas.workbench_intents
  set intent_state='ROUTED',
      preview_snapshot=v_preview,
      previewed_at=coalesce(previewed_at,now()),
      route_receipt=v_receipt,
      routed_by_person_entity_id=v_person_id,
      route_confirmation_basis=p_confirmation_basis,
      routed_at=now()
  where id=p_intent_id;

  return v_receipt;
end
$function$;

revoke all on function atlas.workbench_route_intent_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.workbench_route_intent_api_v1(uuid,text)
  to authenticated;


create or replace function atlas.workbench_cancel_intent_api_v1(
  p_intent_id uuid,
  p_basis text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_person_id uuid;
  v_intent atlas.workbench_intents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_person_id:=atlas.current_person_id_v1();

  select * into v_intent
  from atlas.workbench_intents i
  where i.id=p_intent_id
  for update;
  if not found then
    raise exception 'Workbench intent not found.' using errcode='P0002';
  end if;
  if v_person_id is null or v_intent.composed_by_person_entity_id<>v_person_id then
    raise exception 'Only the composing Person may cancel this v1 Workbench intent.'
      using errcode='42501';
  end if;
  if v_intent.intent_state not in ('COMPOSED','PREVIEWED') then
    raise exception 'Terminal Workbench intent cannot be cancelled.' using errcode='23514';
  end if;

  update atlas.workbench_intents
  set intent_state='CANCELLED',
      cancelled_at=now(),
      route_receipt=jsonb_build_object(
        'contractVersion','atlas_workbench_cancel_receipt_v1',
        'intentId',p_intent_id,
        'cancelledByPersonEntityId',v_person_id,
        'basis',nullif(btrim(coalesce(p_basis,'')),''),
        'canonicalTruthChanged',false,
        'effectExecuted',false
      )
  where id=p_intent_id;

  return jsonb_build_object(
    'contractVersion','atlas_implementation_workbench_v1',
    'state','cancelled','intentId',p_intent_id,
    'canonicalTruthChanged',false,'effectExecuted',false
  );
end
$function$;

revoke all on function atlas.workbench_cancel_intent_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.workbench_cancel_intent_api_v1(uuid,text)
  to authenticated;


create or replace function atlas.workbench_intent_api_v1(p_intent_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_person_id uuid;
  v_intent atlas.workbench_intents%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;
  v_person_id:=atlas.current_person_id_v1();

  select * into v_intent
  from atlas.workbench_intents i
  where i.id=p_intent_id;
  if not found then
    raise exception 'Workbench intent not found.' using errcode='P0002';
  end if;
  if v_person_id is null or v_intent.composed_by_person_entity_id<>v_person_id then
    raise exception 'Workbench intent belongs to another Person.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'contractVersion','atlas_implementation_workbench_v1',
    'intentId',v_intent.id,
    'intentState',v_intent.intent_state,
    'literalRequest',v_intent.literal_request,
    'sentence',v_intent.normalized_sentence,
    'operationKey',v_intent.operation_key,
    'route',v_intent.route_class,
    'preview',v_intent.preview_snapshot,
    'routeReceipt',v_intent.route_receipt,
    'supersedesIntentId',v_intent.supersedes_intent_id,
    'createdAt',v_intent.created_at,
    'previewedAt',v_intent.previewed_at,
    'routedAt',v_intent.routed_at,
    'cancelledAt',v_intent.cancelled_at
  );
end
$function$;

revoke all on function atlas.workbench_intent_api_v1(uuid)
  from public,anon,service_role;
grant execute on function atlas.workbench_intent_api_v1(uuid)
  to authenticated;


comment on table atlas.workbench_operation_registry is
  'Closed constitutional routing registry for Implementation Workbench v1. Registry membership classifies a typed operation as DISCOVER, ESTABLISH, or ACT; carriers cannot add routes through the Workbench API.';
comment on table atlas.workbench_intents is
  'Append-preserving custody for literal and typed Workbench sentences. Routing records handoff only and grants no destination truth/execution authority.';
comment on function atlas.workbench_route_intent_api_v1(uuid,text) is
  'Human-confirmed Workbench route handoff. Produces an immutable destination envelope but deliberately performs no destination operation, canonical truth mutation, or domain effect.';


-- Product/constitutional assertions.
do $assert$
declare
  v_route_def text;
  v_preview_def text;
  v_count integer;
  v_act_count integer;
begin
  select count(*) into v_count
  from atlas.workbench_operation_registry
  where registry_state='active';
  if v_count<>9 then
    raise exception 'Workbench v1 must begin with exactly nine explicit active operation contracts.';
  end if;

  select count(*) into v_act_count
  from atlas.workbench_operation_registry
  where route_class='ACT'
    and requires_operation_contract
    and destination_membrane='atlas.operation_contract';
  if v_act_count<>1 then
    raise exception 'Workbench ACT route must be Operation Contract governed.';
  end if;

  if exists(
    select 1 from atlas.workbench_operation_registry
    where not human_route_confirmation_required
  ) then
    raise exception 'Workbench v1 route confirmation must remain human-required.';
  end if;

  select pg_get_functiondef('atlas.workbench_route_intent_api_v1(uuid,text)'::regprocedure)
  into v_route_def;
  select pg_get_functiondef('atlas.workbench_preview_internal_v1(uuid)'::regprocedure)
  into v_preview_def;

  if lower(v_route_def) like '%insert into reality.entities%'
     or lower(v_route_def) like '%insert into ledger.ledgers%'
     or lower(v_route_def) like '%execute %' then
    raise exception 'Workbench route function must not mutate canonical Reality/Ledger or dynamically execute SQL.';
  end if;

  if position('operation_contract_normalize_v1' in v_preview_def)=0 then
    raise exception 'Workbench ACT preview must reuse the platform Operation Contract membrane.';
  end if;

  if position('destinationExecutionOccurred' in v_route_def)=0
     or position('canonicalTruthChangedByWorkbench' in v_route_def)=0
     or position('destinationAuthoritySatisfiedByRouting' in v_route_def)=0 then
    raise exception 'Workbench route receipt truth boundary is incomplete.';
  end if;
end
$assert$;
