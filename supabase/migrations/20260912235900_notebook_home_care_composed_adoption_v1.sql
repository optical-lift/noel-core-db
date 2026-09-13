begin;

do $body$
declare
  r record;
  v_spread_id uuid;
  v_contract jsonb:=jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('state','evidence'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Preserve row identity; collapse lower-value attributes into secondary inline ink.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateEmptyIntegrationTile',true,'sourceConnectionShouldPopulateExistingFormsBeforeRecomposition',true),
    'compilerBasis',jsonb_build_object('migration','legacy-home-care-to-durable-composed-v1')
  );
begin
  for r in
    select p.id as principal_id,p.active_household_id
    from atlas.principals p
    where p.status='active' and p.active_household_id is not null
  loop
    v_spread_id:=atlas.set_notebook_spread_instance_v2(
      r.principal_id,
      'home-care',
      'household',
      r.active_household_id::text,
      'household',
      'household_care',
      r.active_household_id::text,
      'current-care-orientation',
      'current',
      'thread:home-care:'||r.active_household_id::text,
      'Home care',
      'Home',
      null,
      'resolved',
      'open',
      v_contract,
      jsonb_build_object('kind','product_migration','from','legacy-home-care-runtime','to','durable-composed-spread-v1'),
      jsonb_build_object('migration','legacy-home-care-to-durable-composed-v1')
    );

    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,
      'household',
      'care_snapshot_v1',
      r.active_household_id::text,
      'state',
      'active',
      jsonb_build_object('kind','governed_projection','readSeam','principal_household_care_snapshot_v1'),
      '{}'::jsonb
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
    select 10,0,jsonb_build_object('addressKind','spread','spreadKey','household-rhythm','templateKey','rhythm','title','Household rhythm','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household','id',h.id)) from atlas.households h where h.id=v_household_id
    union all
    select 10,1,jsonb_build_object('addressKind','spread','spreadKey','laundry','templateKey','rhythm','title','Laundry','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','world_kernel','id','household.laundry')) from atlas.households h where h.id=v_household_id
    union all
    select 10,2,jsonb_build_object('addressKind','spread','spreadKey','home-care','templateKey','occurrence','title','Home care','section','Home','scope',jsonb_build_object('kind','household','id',h.id),'subject',jsonb_build_object('kind','household_care','id',h.id))
    from atlas.households h
    where h.id=v_household_id
      and not exists (
        select 1 from atlas.notebook_spread_instances s
        where s.principal_id=v_principal_id and s.spread_key='home-care'
      )
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
