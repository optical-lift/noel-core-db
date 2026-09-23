-- Behavioral postconditions for Atlas Notebook Exposure Reconciliation v1.
-- Requires production-live Person Position, Domain Exposure, and Notebook
-- Exposure Admission. Validation DML occurs only inside the ephemeral clone.

do $validation$
declare
  v_life_user constant uuid := 'c1111111-1111-4111-8111-111111111111'::uuid;
  v_ledger_user constant uuid := 'c2222222-2222-4222-8222-222222222222'::uuid;
  v_bootstrap jsonb;
  v_signal jsonb;
  v_create jsonb;
  v_definition_id uuid;
  v_life_key text;
  v_life_spread_id uuid;
  v_life_spread_id_after uuid;
  v_connections_id uuid;
  v_connections_id_after uuid;
  v_org jsonb;
  v_org_id uuid;
  v_membership_id uuid;
  v_ledger_key text;
  v_ledger_spread_id uuid;
  v_ledger_spread_id_after uuid;
  v_plan jsonb;
  v_result jsonb;
  v_index jsonb;
  v_address jsonb;
  v_def text;
  v_count integer;
  v_binding_count integer;
  v_failed_closed boolean := false;
begin
  if to_regprocedure('atlas.person_position_self_api_v1()') is null
     or to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null
     or to_regprocedure('atlas.notebook_index_admitted_self_api_v1()') is null
     or to_regprocedure('atlas.notebook_address_admitted_self_api_v1(text)') is null then
    raise exception 'Notebook Exposure reconciliation proof requires the production-live read chain.';
  end if;

  if to_regprocedure('atlas.notebook_exposure_reconciliation_plan_self_api_v1()') is null
     or to_regprocedure('atlas.reconcile_notebook_exposure_self_api_v1()') is null then
    raise exception 'Notebook Exposure reconciliation candidate functions are missing.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.notebook_exposure_reconciliation_plan_self_api_v1()',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.reconcile_notebook_exposure_self_api_v1()',
       'EXECUTE'
     ) then
    raise exception 'Anonymous role may execute Notebook Exposure reconciliation.';
  end if;

  select pg_get_functiondef(
    'atlas.notebook_exposure_reconciliation_plan_self_api_v1()'::regprocedure
  ) || E'\n' || pg_get_functiondef(
    'atlas.reconcile_notebook_exposure_self_api_v1()'::regprocedure
  ) || E'\n' || pg_get_functiondef(
    'atlas.notebook_exposure_carrier_spec_self_v1(jsonb)'::regprocedure
  )
  into v_def;

  if position('domain_exposure_evaluations_self_api_v1' in v_def)=0 then
    raise exception 'Notebook Exposure reconciliation does not consume Domain Exposure.';
  end if;

  if position('from atlas.organization_memberships' in lower(v_def))>0
     or position('from atlas.person_life_definitions' in lower(v_def))>0
     or position('from atlas.principal_ledger_authorities' in lower(v_def))>0 then
    raise exception 'Notebook reconciler re-derived upstream authority from raw domain tables.';
  end if;

  if position('delete from' in lower(v_def))>0 then
    raise exception 'Notebook reconciler contains a destructive delete path.';
  end if;

  -- Person Life gain -> retirement -> restoration.
  perform set_config('request.jwt.claim.sub',v_life_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_life_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Notebook Reconcile Life',
    'America/Chicago'
  );

  if (v_bootstrap->>'principalId') is null then
    raise exception 'Person Life reconciliation proof did not establish Principal.';
  end if;

  select s.id
    into v_connections_id
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key='connections'
  limit 1;

  if v_connections_id is null then
    raise exception 'Personal Atlas bootstrap did not establish the existing Connections carrier.';
  end if;

  v_signal := jsonb_build_object(
    'contractVersion','atlas_life_signal_v1',
    'scope',jsonb_build_object('kind','person','id',v_life_user::text),
    'subject',jsonb_build_object(
      'domain','proof',
      'kind','goal',
      'id','notebook-reconcile-goal'
    ),
    'signalKind','goal',
    'state',jsonb_build_object(
      'explicitUserEnd','Prove durable carrier reconciliation'
    ),
    'timing','{}'::jsonb,
    'requirements',jsonb_build_array(
      jsonb_build_object('label','preserve durable identity')
    ),
    'constraints','[]'::jsonb,
    'ambiguities','[]'::jsonb,
    'relations','[]'::jsonb,
    'source',jsonb_build_object(
      'domain','proof',
      'kind','goal_definition',
      'id','notebook-reconcile-goal'
    ),
    'epistemic',jsonb_build_object(
      'factClass','explicit_goal',
      'interpretationAuthority','person'
    )
  );

  v_create := atlas.create_person_life_definition_api_v1(
    jsonb_build_object(
      'sourceKey','notebook-reconcile-goal',
      'signal',v_signal
    )
  );
  v_definition_id := (v_create->>'definitionId')::uuid;
  v_life_key := 'life:'||v_definition_id::text;

  if exists (
    select 1
    from atlas.notebook_spread_instances s
    where s.principal_id=(v_bootstrap->>'principalId')::uuid
      and s.spread_key=v_life_key
  ) then
    raise exception 'Person Life source establishment unexpectedly manufactured a notebook carrier before reconciliation.';
  end if;

  v_plan := atlas.notebook_exposure_reconciliation_plan_self_api_v1();

  if not exists (
    select 1
    from jsonb_array_elements(v_plan->'items') i(value)
    where i.value->>'durabilityKey'=v_life_key
      and i.value->>'action'='ensure_place'
      and i.value->>'bindingDirective'='ensure_active'
  ) then
    raise exception 'Person Life gain did not plan one governed carrier ensure: %',v_plan;
  end if;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_life_spread_id
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_life_key
  limit 1;

  if v_life_spread_id is null then
    raise exception 'Person Life gain did not establish a durable carrier: %',v_result;
  end if;

  select count(*)::integer
    into v_count
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_life_key;

  if v_count<>1 then
    raise exception 'Person Life gain minted duplicate durable carriers.';
  end if;

  select count(*)::integer
    into v_binding_count
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_life_spread_id
    and b.binding_state='active'
    and b.retired_at is null
    and b.source_domain='person'
    and b.source_kind='life_definition_v1'
    and b.source_id=v_definition_id::text
    and b.relationship_kind='progress';

  if v_binding_count<>1 then
    raise exception 'Person Life gain did not establish exactly one active governed binding.';
  end if;

  select s.id
    into v_connections_id_after
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key='connections'
  limit 1;

  if v_connections_id_after is distinct from v_connections_id then
    raise exception 'Connections reconciliation replaced the permanent carrier instead of preserving it.';
  end if;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();
  if coalesce((v_result->>'changedCount')::integer,-1)<>0 then
    raise exception 'Repeated Person Life/Connections reconciliation was not idempotent: %',v_result;
  end if;

  update atlas.person_life_definitions
  set status='retired',
      updated_at=now()
  where id=v_definition_id
    and owner_user_id=v_life_user;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_life_spread_id_after
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_life_key
    and s.spread_state='closed'
  limit 1;

  if v_life_spread_id_after is distinct from v_life_spread_id then
    raise exception 'Retired Person Life did not close the same durable carrier.';
  end if;

  select count(*)::integer
    into v_binding_count
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_life_spread_id
    and b.binding_state='active'
    and b.retired_at is null
    and b.source_domain='person'
    and b.source_id=v_definition_id::text;

  if v_binding_count<>1 then
    raise exception 'Retired Person Life lost its owner-retrievable historical source binding.';
  end if;

  update atlas.person_life_definitions
  set status='active',
      updated_at=now()
  where id=v_definition_id
    and owner_user_id=v_life_user;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_life_spread_id_after
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_life_key
    and s.spread_state='open'
  limit 1;

  if v_life_spread_id_after is distinct from v_life_spread_id then
    raise exception 'Restored Person Life did not reopen the same durable carrier.';
  end if;

  -- Organization Ledger gain -> exposure loss -> restoration.
  perform set_config('request.jwt.claim.sub',v_ledger_user::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub',v_ledger_user::text,'role','authenticated')::text,
    true
  );

  v_bootstrap := atlas.begin_personal_atlas_self_api_v1(
    'Notebook Reconcile Ledger',
    'America/Chicago'
  );

  v_org := atlas.establish_organization_ledger_self_api_v1(
    'Notebook Reconcile Organization',
    true,
    false
  );
  v_org_id := (v_org->'organization'->>'id')::uuid;
  v_membership_id := (v_org->'membership'->>'id')::uuid;
  v_ledger_key := 'ledger:'||v_org_id::text;

  if exists (
    select 1
    from atlas.notebook_spread_instances s
    where s.principal_id=(v_bootstrap->>'principalId')::uuid
      and s.spread_key=v_ledger_key
  ) then
    raise exception 'Organization establishment unexpectedly manufactured a Ledger notebook carrier before reconciliation.';
  end if;

  v_plan := atlas.notebook_exposure_reconciliation_plan_self_api_v1();

  if not exists (
    select 1
    from jsonb_array_elements(v_plan->'items') i(value)
    where i.value->>'durabilityKey'=v_ledger_key
      and i.value->>'action'='ensure_place'
      and i.value->>'bindingDirective'='ensure_active'
  ) then
    raise exception 'Owner Ledger gain did not plan one governed carrier ensure: %',v_plan;
  end if;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_ledger_spread_id
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_ledger_key
    and s.spread_state='open'
  limit 1;

  if v_ledger_spread_id is null then
    raise exception 'Owner Ledger gain did not establish its durable carrier: %',v_result;
  end if;

  select count(*)::integer
    into v_binding_count
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_ledger_spread_id
    and b.binding_state='active'
    and b.retired_at is null
    and b.source_domain='organization'
    and b.source_kind='ledger_recent_v1'
    and b.source_id=v_org_id::text
    and b.relationship_kind='evidence';

  if v_binding_count<>1 then
    raise exception 'Owner Ledger gain did not establish its exact governed binding.';
  end if;

  update atlas.organization_memberships
  set role='member',
      updated_at=now()
  where id=v_membership_id
    and organization_id=v_org_id;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_ledger_spread_id_after
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_ledger_key
    and s.spread_state='closed'
  limit 1;

  if v_ledger_spread_id_after is distinct from v_ledger_spread_id then
    raise exception 'Ledger exposure loss did not close the same durable carrier.';
  end if;

  select count(*)::integer
    into v_binding_count
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_ledger_spread_id
    and b.binding_state='active'
    and b.retired_at is null;

  if v_binding_count<>0 then
    raise exception 'Ledger exposure loss left an active source binding.';
  end if;

  v_index := atlas.notebook_index_admitted_self_api_v1();

  if exists (
    select 1
    from jsonb_array_elements(v_index->'items') i(value)
    where i.value->>'spreadKey'=v_ledger_key
  ) then
    raise exception 'Closed historical Ledger remained advertised after exposure loss.';
  end if;

  v_failed_closed := false;
  begin
    perform atlas.notebook_address_admitted_self_api_v1(v_ledger_key);
  exception
    when sqlstate 'P0002' then
      v_failed_closed := true;
  end;

  if not v_failed_closed then
    raise exception 'Closed historical Ledger remained directly resolvable after exposure loss.';
  end if;

  update atlas.organization_memberships
  set role='owner',
      updated_at=now()
  where id=v_membership_id
    and organization_id=v_org_id;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();

  select s.id
    into v_ledger_spread_id_after
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_ledger_key
    and s.spread_state='open'
  limit 1;

  if v_ledger_spread_id_after is distinct from v_ledger_spread_id then
    raise exception 'Restored Ledger exposure did not reopen the same durable carrier.';
  end if;

  select count(*)::integer
    into v_count
  from atlas.notebook_spread_instances s
  where s.principal_id=(v_bootstrap->>'principalId')::uuid
    and s.spread_key=v_ledger_key;

  if v_count<>1 then
    raise exception 'Ledger restoration minted duplicate durable identity.';
  end if;

  select count(*)::integer
    into v_binding_count
  from atlas.notebook_spread_source_bindings b
  where b.spread_instance_id=v_ledger_spread_id
    and b.binding_state='active'
    and b.retired_at is null
    and b.source_domain='organization'
    and b.source_kind='ledger_recent_v1'
    and b.source_id=v_org_id::text
    and b.relationship_kind='evidence';

  if v_binding_count<>1 then
    raise exception 'Ledger restoration did not reactivate exactly one governed binding.';
  end if;

  v_address := atlas.notebook_address_admitted_self_api_v1(v_ledger_key);
  if v_address->>'state'<>'listed'
     or v_address->'spread'->>'spreadKey'<>v_ledger_key then
    raise exception 'Restored Ledger did not re-enter admitted NotebookAddress resolution: %',v_address;
  end if;

  v_result := atlas.reconcile_notebook_exposure_self_api_v1();
  if coalesce((v_result->>'changedCount')::integer,-1)<>0 then
    raise exception 'Repeated restored-Ledger reconciliation was not idempotent: %',v_result;
  end if;

  if coalesce((v_result->'truthBoundary'->>'domainTruthCreated')::boolean,true)
     or coalesce((v_result->'truthBoundary'->>'sourceReadAuthorityGranted')::boolean,true)
     or coalesce((v_result->'truthBoundary'->>'todayPlacementAuthorized')::boolean,true)
     or coalesce((v_result->'truthBoundary'->>'actionAuthorityGranted')::boolean,true)
     or coalesce((v_result->'truthBoundary'->>'executionAuthorityGranted')::boolean,true) then
    raise exception 'Notebook reconciliation widened authority beyond carrier/source-binding maintenance.';
  end if;
end;
$validation$;
