begin;

-- A Ledger member may need one bounded institutional viewport without receiving
-- owner chronology authority. Communications therefore enters the notebook as
-- its own organization-scoped spread and remains endpoint-capability gated.
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
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select p.id, p.active_household_id
    into v_principal_id, v_household_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;

  with descriptors as (
    select 0 as section_order, 0 as item_order,
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
    select 20,row_number() over(order by d.created_at,d.id)::integer,
      jsonb_build_object(
        'addressKind','spread',
        'spreadKey','life:'||d.id::text,
        'templateKey',case
          when d.signal_kind ilike '%goal%'
            or d.signal_kind ilike '%training%'
            or d.life_signal ? 'goal'
            or d.life_signal ? 'target'
            or d.life_signal ? 'milestones'
            then 'progress'
          when d.signal_kind ilike '%maintenance%'
            or d.signal_kind ilike '%rhythm%'
            or d.signal_kind ilike '%recurr%'
            or d.life_signal ? 'cadence'
            or d.life_signal ? 'interval'
            or d.life_signal ? 'nextDue'
            then 'occurrence'
          else 'log'
        end,
        'title',coalesce(nullif(d.life_signal->>'title',''),nullif(d.life_signal->>'label',''),initcap(replace(d.signal_kind,'_',' '))),
        'section','Life',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind',d.signal_kind,'id',d.id)
      )
    from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id and d.status<>'retired'
    union all
    select 30,row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object('addressKind','spread','spreadKey','ledger:'||o.id::text,'templateKey','organization-ledger','title',o.name,'subtitle','Ledger','section','Organizations','scope',jsonb_build_object('kind','organization','id',o.id),'subject',jsonb_build_object('kind','organization_ledger','id',o.id))
    from atlas.organizations o
    where atlas.is_organization_owner(o.id)
    union all
    select 31,row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object('addressKind','spread','spreadKey','communications:'||o.id::text,'templateKey','organization-communications','title',o.name,'subtitle','Communications','section','Organizations','scope',jsonb_build_object('kind','organization','id',o.id),'subject',jsonb_build_object('kind','organization_communications','id',o.id))
    from atlas.organizations o
    where exists (
      select 1
      from atlas.organization_memberships om
      join atlas.communication_endpoints ep
        on ep.organization_id=om.organization_id
       and ep.endpoint_state='active'
      where om.organization_id=o.id
        and om.user_id=v_user_id
        and om.active
        and atlas.communication_endpoint_membership_has_capability_v1(ep.id,om.id,'view')
    )
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb)
    into v_items
  from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,
      'indexDoesNotGrantAccess',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,
      'ledgerDescriptorMatchesReadAuthority',true,
      'communicationsDescriptorRequiresEndpointViewAuthority',true,
      'communicationsDescriptorDoesNotGrantOwnerLedgerChronology',true
    )
  );
end;
$function$;

comment on function atlas.atlas_notebook_index_self_api_v1() is
'Notebook retrieval projection. Organization Ledger chronology remains owner-only; an organization Communications spread is separately discoverable only when the signed-in membership has view authority on at least one active communication endpoint.';

create or replace function atlas.institutional_communications_organization_self_api_v1(
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
  v_home jsonb;
  v_items jsonb := '[]'::jsonb;
  v_organization_name text;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_organization_id is null then
    raise exception 'Organization is required.' using errcode='22023';
  end if;
  if p_limit<1 or p_limit>1000 then
    raise exception 'Limit must be between 1 and 1000.' using errcode='22023';
  end if;

  v_home := atlas.institutional_communications_home_self_api_v1();

  select
    coalesce(jsonb_agg(
      item || jsonb_build_object(
        'inbox',coalesce(
          atlas.institutional_shared_inbox_self_v1((item->>'communicationEndpointId')::uuid,p_limit)->'items',
          '[]'::jsonb
        )
      )
      order by item->>'displayName',item->>'address'
    ),'[]'::jsonb),
    max(item->>'organizationName')
  into v_items,v_organization_name
  from jsonb_array_elements(coalesce(v_home->'items','[]'::jsonb)) item
  where item->>'organizationId'=p_organization_id::text;

  if jsonb_array_length(v_items)=0 then
    raise exception 'Organization communication view authority required.' using errcode='42501';
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','institutional_communications_organization_v1',
    'organizationId',p_organization_id,
    'organizationName',v_organization_name,
    'endpoints',v_items,
    'truthBoundary',jsonb_build_object(
      'endpointCapabilityGoverned',true,
      'readingDoesNotClaimResponsibility',true,
      'handoffUsesCompanyWorkResponsibility',true,
      'providerIsTransportNotAuthority',true,
      'ownerLedgerChronologyNotIncluded',true
    )
  );
end;
$function$;

comment on function atlas.institutional_communications_organization_self_api_v1(uuid,integer) is
'Organization-scoped communications projection for a signed-in Ledger member. It composes only endpoint-capability-governed home and shared-inbox projections; it does not expose owner Ledger chronology or create a second responsibility model.';

revoke all on function atlas.institutional_communications_organization_self_api_v1(uuid,integer) from public,anon;
grant execute on function atlas.institutional_communications_organization_self_api_v1(uuid,integer) to authenticated,service_role;

commit;
