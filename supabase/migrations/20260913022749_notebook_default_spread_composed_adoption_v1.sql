begin;

create or replace function atlas.organization_ledger_owner_recent_api_v1(
  p_organization_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_end_at timestamptz := now();
  v_start_at timestamptz;
  v_limit integer;
  v_payload jsonb;
begin
  if p_organization_id is null then
    raise exception 'organization is required' using errcode='22023';
  end if;
  v_limit := greatest(1, least(coalesce(p_limit,200),500));
  v_start_at := v_end_at - interval '30 days';
  v_payload := atlas.organization_ledger_owner_window_api_v1(p_organization_id,v_start_at,v_end_at,0,v_limit);
  return coalesce(v_payload,'{}'::jsonb) || jsonb_build_object(
    'contractVersion','organization_ledger_owner_recent_api_v1',
    'windowPolicy','rolling_30_days',
    'windowDuration','P30D'
  );
end;
$function$;

create or replace function public.organization_ledger_owner_recent_api_v1(
  p_organization_id uuid,
  p_limit integer default 200
)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
  select atlas.organization_ledger_owner_recent_api_v1(p_organization_id,p_limit);
$function$;

revoke all on function public.organization_ledger_owner_recent_api_v1(uuid,integer) from public;
grant execute on function public.organization_ledger_owner_recent_api_v1(uuid,integer) to authenticated,service_role;

do $body$
declare
  r record;
  v_spread_id uuid;
  v_rhythm_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1','patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('cadence','window','sequence'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Preserve rhythm identity and keep the next established window inline.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1','page','household-rhythm')
  );
  v_laundry_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1','patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','path','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('sequence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep the source-defined laundry sequence in order without inventing a household routine.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('path'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1','page','laundry')
  );
begin
  for r in select p.id as principal_id,p.active_household_id from atlas.principals p where p.status='active' and p.active_household_id is not null
  loop
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,'household-rhythm','household',r.active_household_id::text,
      'household','household_rhythm',r.active_household_id::text,
      'cadence-orientation','current','thread:household-rhythm:'||r.active_household_id::text,
      'Household rhythm','Home',null,'resolved','open',v_rhythm_contract,
      jsonb_build_object('kind','product_migration','from','legacy-household-rhythm-runtime','to','durable-composed-spread-v1'),
      jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'household','rhythm_snapshot_v1',r.active_household_id::text,'cadence','active',
      jsonb_build_object('kind','governed_projection','readSeam','personal_setup_self_api_v1'),'{}'::jsonb
    );

    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,'laundry','household',r.active_household_id::text,
      'household','world_kernel','household.laundry',
      'laundry-orientation','current','thread:laundry:'||r.active_household_id::text,
      'Laundry','Home',null,'resolved','open',v_laundry_contract,
      jsonb_build_object('kind','product_migration','from','legacy-laundry-runtime','to','durable-composed-spread-v1'),
      jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'household','laundry_kernel_v1',r.active_household_id::text,'sequence','active',
      jsonb_build_object('kind','governed_projection','readSeam','personal_laundry_kernel_self_api_v1'),'{}'::jsonb
    );
  end loop;
end;
$body$;

do $body$
declare
  r record;
  v_spread_id uuid;
  v_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1','patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','log','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('evidence','sequence'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep Ledger occurrences chronological and collapse secondary provenance before primary evidence.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('log'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1','page','organization-ledger')
  );
begin
  for r in
    select distinct p.id as principal_id,o.id as organization_id,o.name as organization_name
    from atlas.principals p
    join atlas.organization_memberships m on m.user_id=p.user_id and m.active=true and m.role='owner'
    join atlas.organizations o on o.id=m.organization_id
    where p.status='active'
  loop
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,'ledger:'||r.organization_id::text,'organization',r.organization_id::text,
      'organization','organization_ledger',r.organization_id::text,
      'recent-ledger-orientation','rolling-30-days','thread:organization-ledger:'||r.organization_id::text,
      r.organization_name,'Organizations',null,'resolved','open',v_contract,
      jsonb_build_object('kind','product_migration','from','legacy-organization-ledger-runtime','to','durable-composed-spread-v1'),
      jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1','subtitle','Ledger')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'organization','ledger_recent_v1',r.organization_id::text,'evidence','active',
      jsonb_build_object('kind','governed_projection','readSeam','organization_ledger_owner_recent_api_v1','windowPolicy','rolling_30_days'),'{}'::jsonb
    );
  end loop;
end;
$body$;

do $body$
declare
  r record;
  v_spread_id uuid;
  v_contract jsonb := jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1','patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','log','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('sequence','state','action'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep correspondence chronological; subject and latest message remain primary ink.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('log'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1','page','correspondence')
  );
begin
  for r in
    select distinct p.id as principal_id,e.id as endpoint_id,e.organization_id,
      coalesce(nullif(e.display_name,''),e.address,'Correspondence') as endpoint_label
    from atlas.principals p
    join atlas.organization_memberships m on m.user_id=p.user_id and m.active=true
    join atlas.communication_endpoints e on e.organization_id=m.organization_id and e.endpoint_state='active'
    where p.status='active'
      and atlas.communication_endpoint_membership_has_capability_v1(e.id,m.id,'view')
  loop
    v_spread_id := atlas.set_notebook_spread_instance_v2(
      r.principal_id,'letters:'||r.endpoint_id::text,'organization',r.organization_id::text,
      'communication','institutional_correspondence',r.endpoint_id::text,
      'correspondence-journal','current','thread:correspondence:'||r.endpoint_id::text,
      'Letters · '||r.endpoint_label,'Correspondence',null,'resolved','open',v_contract,
      jsonb_build_object('kind','product_migration','from','standalone-correspondence-notebook','to','durable-composed-spread-v1'),
      jsonb_build_object('migration','legacy-default-spreads-to-durable-composed-v1')
    );
    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'communication','institutional_correspondence_v1',r.endpoint_id::text,'sequence','active',
      jsonb_build_object('kind','governed_projection','readSeam','institutional_shared_inbox_self_v1','detailSeam','institutional_conversation_detail_self_v1'),'{}'::jsonb
    );
  end loop;
end;
$body$;

create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','atlas','auth'
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
    select 10,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey',s.spread_key,'templateKey','composed',
        'title',s.title,'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'spreadInstanceId',s.id,'spreadState',s.spread_state,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'purposeKey',s.purpose_key,'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb) into v_items from descriptors;

  return jsonb_build_object(
    'ok',true,'contractVersion','atlas_notebook_index_self_api_v1','principalId',v_principal_id,'householdId',v_household_id,'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,'indexDoesNotGrantAccess',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,'closedSpreadsRemainRetrievable',true,
      'dataBearingPagesComeFromDurableSpreadRegistry',true
    )
  );
end;
$function$;

commit;