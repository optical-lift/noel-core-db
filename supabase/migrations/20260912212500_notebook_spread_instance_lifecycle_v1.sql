begin;

create table atlas.notebook_spread_instances (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  spread_key text not null check (length(btrim(spread_key)) > 0),
  scope_kind text not null check (length(btrim(scope_kind)) > 0),
  scope_id text not null check (length(btrim(scope_id)) > 0),
  subject_kind text not null check (length(btrim(subject_kind)) > 0),
  subject_id text not null check (length(btrim(subject_id)) > 0),
  purpose_key text not null check (length(btrim(purpose_key)) > 0),
  horizon_key text not null check (length(btrim(horizon_key)) > 0),
  thread_key text not null check (length(btrim(thread_key)) > 0),
  recipe_key text,
  creation_mode text not null check (creation_mode in ('explicit','resolved','continuation')),
  spread_state text not null check (spread_state in ('open','closed')),
  composition_contract jsonb not null default '{}'::jsonb,
  basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notebook_spread_instances_state_time_ck check (
    (spread_state='open' and closed_at is null)
    or (spread_state='closed' and closed_at is not null)
  ),
  constraint notebook_spread_instances_principal_spread_key_uk unique (principal_id,spread_key),
  constraint notebook_spread_instances_semantic_identity_uk unique (
    principal_id,scope_kind,scope_id,subject_kind,subject_id,purpose_key,horizon_key
  )
);

comment on table atlas.notebook_spread_instances is
  'Notebook-owned durable spread instances. A row means the page exists. It does not mean the page deserves current attention, and it does not own source-domain truth.';
comment on column atlas.notebook_spread_instances.creation_mode is
  'Why the durable page was born: explicit human instruction, resolver-recognized durable retrieval need, or continuation of an already-established thread.';
comment on column atlas.notebook_spread_instances.spread_state is
  'Page/thread state only: open while the bounded page is still accumulating, closed when that page is complete. Closed pages remain durable and retrievable.';
comment on column atlas.notebook_spread_instances.composition_contract is
  'Notebook presentation contract preserving stable spatial meaning. It may reference source reality but never becomes canonical source-domain truth.';
comment on column atlas.notebook_spread_instances.thread_key is
  'Stable notebook thread identity shared by continuation pages. Threading preserves subject continuity without overwriting prior bounded pages.';

revoke all on atlas.notebook_spread_instances from public, anon, authenticated;
grant select, insert, update on atlas.notebook_spread_instances to service_role;

create index notebook_spread_instances_scope_idx
  on atlas.notebook_spread_instances(principal_id,scope_kind,scope_id,spread_state);
create index notebook_spread_instances_thread_idx
  on atlas.notebook_spread_instances(principal_id,thread_key,opened_at,id);

create or replace function atlas.set_notebook_spread_instance_v1(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
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
     or nullif(btrim(p_subject_kind),'') is null
     or nullif(btrim(p_subject_id),'') is null
     or nullif(btrim(p_purpose_key),'') is null
     or nullif(btrim(p_horizon_key),'') is null
     or nullif(btrim(p_thread_key),'') is null then
    raise exception 'principal, spread, scope, subject, purpose, horizon, and thread are required' using errcode='22023';
  end if;

  if p_creation_mode not in ('explicit','resolved','continuation') then
    raise exception 'invalid creation mode' using errcode='22023';
  end if;

  if p_spread_state not in ('open','closed') then
    raise exception 'invalid spread state' using errcode='22023';
  end if;

  if not exists (
    select 1 from atlas.principals p where p.id=p_principal_id and p.status='active'
  ) then
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
       or v_existing.subject_kind <> btrim(p_subject_kind)
       or v_existing.subject_id <> btrim(p_subject_id)
       or v_existing.purpose_key <> btrim(p_purpose_key)
       or v_existing.horizon_key <> btrim(p_horizon_key)
       or v_existing.thread_key <> btrim(p_thread_key) then
      raise exception 'spread key already belongs to a different spread identity' using errcode='23505';
    end if;

    v_closed_at := case
      when p_spread_state='closed' then coalesce(v_existing.closed_at,now())
      else null
    end;

    update atlas.notebook_spread_instances
    set recipe_key=coalesce(nullif(btrim(p_recipe_key),''),recipe_key),
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
    principal_id,spread_key,scope_kind,scope_id,subject_kind,subject_id,
    purpose_key,horizon_key,thread_key,recipe_key,creation_mode,spread_state,
    composition_contract,basis,metadata,closed_at
  ) values (
    p_principal_id,btrim(p_spread_key),btrim(p_scope_kind),btrim(p_scope_id),
    btrim(p_subject_kind),btrim(p_subject_id),btrim(p_purpose_key),btrim(p_horizon_key),
    btrim(p_thread_key),nullif(btrim(p_recipe_key),''),p_creation_mode,p_spread_state,
    coalesce(p_composition_contract,'{}'::jsonb),coalesce(p_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb),v_closed_at
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.set_notebook_spread_instance_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated, service_role;

create or replace function public.set_notebook_spread_instance_service_v1(
  p_principal_id uuid,
  p_spread_key text,
  p_scope_kind text,
  p_scope_id text,
  p_subject_kind text,
  p_subject_id text,
  p_purpose_key text,
  p_horizon_key text,
  p_thread_key text,
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
  select atlas.set_notebook_spread_instance_v1(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_recipe_key,p_creation_mode,p_spread_state,
    p_composition_contract,p_basis,p_metadata
  );
$function$;

revoke all on function public.set_notebook_spread_instance_service_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function public.set_notebook_spread_instance_service_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) to service_role;

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
    select 20,row_number() over(order by s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread',
        'spreadKey',s.spread_key,
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
        'subject',jsonb_build_object('kind',d.signal_kind,'id',d.id),
        'spreadInstanceId',s.id,
        'spreadState',s.spread_state,
        'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,
        'purposeKey',s.purpose_key,
        'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    join atlas.person_life_definitions d
      on s.principal_id=v_principal_id
     and s.scope_kind='person'
     and s.scope_id=v_user_id::text
     and s.subject_kind='person_life_definition'
     and s.subject_id=d.id::text
    where s.spread_state in ('open','closed')
      and d.owner_user_id=v_user_id
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
      'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,
      'closedSpreadsRemainRetrievable',true,
      'ledgerDescriptorMatchesReadAuthority',true
    )
  );
end;
$function$;

-- The v1 admission experiment has no rows in production. Refuse to erase data
-- if that assumption changes between review and application.
do $migration$
begin
  if exists (select 1 from atlas.notebook_spread_admissions limit 1) then
    raise exception 'notebook_spread_admissions is no longer empty; reconcile rows before retiring the v1 admission model';
  end if;
end;
$migration$;

drop function if exists public.set_person_life_spread_admission_self_v1(uuid,text,jsonb);
drop function if exists public.set_notebook_spread_admission_service_v1(uuid,text,text,text,text,text,text,jsonb);
drop function if exists atlas.set_notebook_spread_admission_v1(uuid,text,text,text,text,text,text,jsonb);
drop table atlas.notebook_spread_admissions;

commit;
