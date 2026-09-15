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