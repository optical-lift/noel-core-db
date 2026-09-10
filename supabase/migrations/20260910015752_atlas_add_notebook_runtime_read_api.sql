-- Canonical custody for the Atlas notebook runtime read membrane.
-- Presentation reads governed projections only; this migration does not move source-domain truth.

create or replace function atlas.atlas_notebook_index_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog,atlas,auth
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
      jsonb_build_object(
        'addressKind','today','spreadKey','today','templateKey','today',
        'title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','day','id',current_date::text)
      ) as item

    union all

    select 0, 1,
      jsonb_build_object(
        'addressKind','index','spreadKey','index','templateKey','index',
        'title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','notebook','id',v_user_id)
      )

    union all

    select 10, 0,
      jsonb_build_object(
        'addressKind','spread','spreadKey','household-rhythm','templateKey','rhythm',
        'title','Household rhythm','section','Home','scope',jsonb_build_object('kind','household','id',h.id),
        'subject',jsonb_build_object('kind','household','id',h.id)
      )
    from atlas.households h
    where h.id=v_household_id

    union all

    select 10, 1,
      jsonb_build_object(
        'addressKind','spread','spreadKey','laundry','templateKey','rhythm',
        'title','Laundry','section','Home','scope',jsonb_build_object('kind','household','id',h.id),
        'subject',jsonb_build_object('kind','world_kernel','id','household.laundry')
      )
    from atlas.households h
    where h.id=v_household_id

    union all

    select 10, 2,
      jsonb_build_object(
        'addressKind','spread','spreadKey','home-care','templateKey','occurrence',
        'title','Home care','section','Home','scope',jsonb_build_object('kind','household','id',h.id),
        'subject',jsonb_build_object('kind','household_care','id',h.id)
      )
    from atlas.households h
    where h.id=v_household_id

    union all

    select 20, row_number() over(order by d.created_at,d.id)::integer,
      jsonb_build_object(
        'addressKind','spread',
        'spreadKey','life:'||d.id::text,
        'templateKey',case when d.signal_kind ilike '%goal%' then 'progress' else 'log' end,
        'title',coalesce(nullif(d.life_signal->>'title',''),nullif(d.life_signal->>'label',''),initcap(replace(d.signal_kind,'_',' '))),
        'section','Life',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind',d.signal_kind,'id',d.id)
      )
    from atlas.person_life_definitions d
    where d.owner_user_id=v_user_id and d.status<>'retired'

    union all

    select 30, row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object(
        'addressKind','spread',
        'spreadKey','ledger:'||o.id::text,
        'templateKey','organization-ledger',
        'title',o.name,
        'subtitle','Ledger',
        'section','Organizations',
        'scope',jsonb_build_object('kind','organization','id',o.id),
        'subject',jsonb_build_object('kind','organization_ledger','id',o.id)
      )
    from atlas.organizations o
    where exists (
      select 1 from atlas.organization_memberships m
      where m.organization_id=o.id and m.user_id=v_user_id
    )
       or atlas.is_organization_owner(o.id)
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
      'spreadDescriptorsDoNotOwnSourceTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.atlas_notebook_index_self_api_v1() from public,anon;
grant execute on function atlas.atlas_notebook_index_self_api_v1() to authenticated,service_role;

create or replace function public.atlas_notebook_index_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$ select atlas.atlas_notebook_index_self_api_v1(); $function$;

create or replace function public.organization_ledger_owner_window_api_v1(
  p_organization_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_after_revision bigint default 0,
  p_limit integer default 200
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$
  select atlas.organization_ledger_owner_window_api_v1(p_organization_id,p_start_at,p_end_at,p_after_revision,p_limit);
$function$;

create or replace function public.person_life_state_api_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$ select atlas.person_life_state_api_v1(); $function$;

create or replace function public.principal_household_care_snapshot_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $function$ select atlas.principal_household_care_snapshot_v1(); $function$;

revoke all on function public.atlas_notebook_index_self_api_v1() from public,anon;
revoke all on function public.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer) from public,anon;
revoke all on function public.person_life_state_api_v1() from public,anon;
revoke all on function public.principal_household_care_snapshot_v1() from public,anon;
grant execute on function public.atlas_notebook_index_self_api_v1() to authenticated,service_role;
grant execute on function public.organization_ledger_owner_window_api_v1(uuid,timestamptz,timestamptz,bigint,integer) to authenticated,service_role;
grant execute on function public.person_life_state_api_v1() to authenticated,service_role;
grant execute on function public.principal_household_care_snapshot_v1() to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,
  service_execute_expected,anonymous_execute_expected,caller_count,policy_reference_count,evidence,registered_at
)
values
  ('atlas.atlas_notebook_index_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Authenticated notebook retrieval projection; grants no authority.'),now()),
  ('atlas.person_life_state_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Private person-life state projection used by notebook adapters.'),now()),
  ('atlas.principal_household_care_snapshot_v1()','app_endpoint','verified','active',true,true,true,false,1,0,jsonb_build_object('purpose','Principal household-care projection used by notebook adapters.'),now())
on conflict (signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence || excluded.evidence,
  reviewed_at=now();
