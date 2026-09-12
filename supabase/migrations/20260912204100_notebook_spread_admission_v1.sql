begin;

create table atlas.notebook_spread_admissions (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  scope_kind text not null check (length(btrim(scope_kind)) > 0),
  scope_id text not null check (length(btrim(scope_id)) > 0),
  subject_kind text not null check (length(btrim(subject_kind)) > 0),
  subject_id text not null check (length(btrim(subject_id)) > 0),
  admission_mode text not null check (admission_mode in ('automatic','suggested','explicit')),
  surface_state text not null check (surface_state in ('suggested','active','suppressed','retired')),
  basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (principal_id,scope_kind,scope_id,subject_kind,subject_id)
);

comment on table atlas.notebook_spread_admissions is
  'Notebook-owned decision about whether a reality subject receives a durable retrieval surface. Source reality remains authoritative in its own domain.';
comment on column atlas.notebook_spread_admissions.admission_mode is
  'How the notebook came to consider/admit the surface: automatic, suggested, or explicit.';
comment on column atlas.notebook_spread_admissions.surface_state is
  'Notebook surface lifecycle only. Does not create, retire, suppress, or mutate source-domain reality.';

revoke all on atlas.notebook_spread_admissions from public, anon, authenticated;
grant select, insert, update on atlas.notebook_spread_admissions to service_role;

create or replace function atlas.set_notebook_spread_admission_v1(
  p_principal_id uuid,
  p_scope_kind text,
  p_scope_id text,
  p_subject_kind text,
  p_subject_id text,
  p_admission_mode text,
  p_surface_state text,
  p_basis jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_id uuid;
begin
  if p_principal_id is null
     or nullif(btrim(p_scope_kind),'') is null
     or nullif(btrim(p_scope_id),'') is null
     or nullif(btrim(p_subject_kind),'') is null
     or nullif(btrim(p_subject_id),'') is null then
    raise exception 'principal, scope, and subject are required' using errcode='22023';
  end if;
  if p_admission_mode not in ('automatic','suggested','explicit') then
    raise exception 'invalid admission mode' using errcode='22023';
  end if;
  if p_surface_state not in ('suggested','active','suppressed','retired') then
    raise exception 'invalid surface state' using errcode='22023';
  end if;
  if not exists (
    select 1 from atlas.principals p where p.id=p_principal_id and p.status='active'
  ) then
    raise exception 'active principal not found' using errcode='P0002';
  end if;

  insert into atlas.notebook_spread_admissions(
    principal_id,scope_kind,scope_id,subject_kind,subject_id,
    admission_mode,surface_state,basis
  ) values (
    p_principal_id,btrim(p_scope_kind),btrim(p_scope_id),btrim(p_subject_kind),btrim(p_subject_id),
    p_admission_mode,p_surface_state,coalesce(p_basis,'{}'::jsonb)
  )
  on conflict (principal_id,scope_kind,scope_id,subject_kind,subject_id)
  do update set
    admission_mode=excluded.admission_mode,
    surface_state=excluded.surface_state,
    basis=excluded.basis,
    updated_at=now()
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.set_notebook_spread_admission_v1(uuid,text,text,text,text,text,text,jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.set_notebook_spread_admission_service_v1(
  p_principal_id uuid,
  p_scope_kind text,
  p_scope_id text,
  p_subject_kind text,
  p_subject_id text,
  p_admission_mode text,
  p_surface_state text,
  p_basis jsonb default '{}'::jsonb
)
returns uuid
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.set_notebook_spread_admission_v1(
    p_principal_id,p_scope_kind,p_scope_id,p_subject_kind,p_subject_id,
    p_admission_mode,p_surface_state,p_basis
  );
$function$;

revoke all on function public.set_notebook_spread_admission_service_v1(uuid,text,text,text,text,text,text,jsonb)
  from public, anon, authenticated;
grant execute on function public.set_notebook_spread_admission_service_v1(uuid,text,text,text,text,text,text,jsonb)
  to service_role;

create or replace function public.set_person_life_spread_admission_self_v1(
  p_life_definition_id uuid,
  p_surface_state text,
  p_basis jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_definition atlas.person_life_definitions%rowtype;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_surface_state not in ('active','suppressed','retired') then
    raise exception 'self admission state must be active, suppressed, or retired' using errcode='22023';
  end if;

  select * into v_definition
  from atlas.person_life_definitions d
  where d.id=p_life_definition_id
    and d.owner_user_id=v_user_id
  limit 1;

  if v_definition.id is null then
    raise exception 'life definition not found for signed-in person' using errcode='P0002';
  end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.id=v_definition.principal_id
    and p.user_id=v_user_id
    and p.status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'active principal not found' using errcode='P0002';
  end if;

  return atlas.set_notebook_spread_admission_v1(
    v_principal_id,
    'person',
    v_user_id::text,
    'person_life_definition',
    v_definition.id::text,
    'explicit',
    p_surface_state,
    coalesce(p_basis,'{}'::jsonb)
  );
end;
$function$;

revoke all on function public.set_person_life_spread_admission_self_v1(uuid,text,jsonb)
  from public, anon;
grant execute on function public.set_person_life_spread_admission_self_v1(uuid,text,jsonb)
  to authenticated, service_role;

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
    join atlas.notebook_spread_admissions a
      on a.principal_id=v_principal_id
     and a.scope_kind='person'
     and a.scope_id=v_user_id::text
     and a.subject_kind='person_life_definition'
     and a.subject_id=d.id::text
     and a.surface_state='active'
    where d.owner_user_id=v_user_id and d.status<>'retired'
    union all
    select 30,row_number() over(order by o.name,o.id)::integer,
      jsonb_build_object('addressKind','spread','spreadKey','ledger:'||o.id::text,'templateKey','organization-ledger','title',o.name,'subtitle','Ledger','section','Organizations','scope',jsonb_build_object('kind','organization','id',o.id),'subject',jsonb_build_object('kind','organization_ledger','id',o.id))
    from atlas.organizations o
    where atlas.is_organization_owner(o.id)
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
      'spreadAdmissionDoesNotMutateSourceTruth',true,
      'ledgerDescriptorMatchesReadAuthority',true
    )
  );
end;
$function$;

commit;
