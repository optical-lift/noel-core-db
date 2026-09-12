begin;

create table atlas.notebook_spread_source_bindings (
  id uuid primary key default gen_random_uuid(),
  spread_instance_id uuid not null references atlas.notebook_spread_instances(id) on delete cascade,
  source_domain text not null check (length(btrim(source_domain)) > 0),
  source_kind text not null check (length(btrim(source_kind)) > 0),
  source_id text not null check (length(btrim(source_id)) > 0),
  relationship_kind text not null check (relationship_kind in (
    'state','plan','progress','requirement','constraint','window','threshold',
    'sequence','cadence','accumulation','comparison','relationship','place',
    'evidence','exception','memory','action'
  )),
  binding_state text not null default 'active' check (binding_state in ('active','retired')),
  basis jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint notebook_spread_source_bindings_state_time_ck check (
    (binding_state='active' and retired_at is null)
    or (binding_state='retired' and retired_at is not null)
  ),
  constraint notebook_spread_source_binding_identity_uk unique (
    spread_instance_id,source_domain,source_kind,source_id,relationship_kind
  )
);

comment on table atlas.notebook_spread_source_bindings is
  'Notebook-owned references from a durable Spread to source-owned reality. Bindings explain what the page may read; they never copy or become authority for the source fact.';
comment on column atlas.notebook_spread_source_bindings.relationship_kind is
  'Why this source matters to the spread, using the selected Composer relationship grammar.';

revoke all on atlas.notebook_spread_source_bindings from public, anon, authenticated;
grant select, insert, update on atlas.notebook_spread_source_bindings to service_role;

create index notebook_spread_source_bindings_spread_idx
  on atlas.notebook_spread_source_bindings(spread_instance_id,binding_state,relationship_kind);
create index notebook_spread_source_bindings_source_idx
  on atlas.notebook_spread_source_bindings(source_domain,source_kind,source_id,binding_state);

create or replace function atlas.bind_notebook_spread_source_v1(
  p_spread_instance_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_relationship_kind text,
  p_binding_state text default 'active',
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
  v_retired_at timestamptz;
begin
  if p_spread_instance_id is null
     or nullif(btrim(p_source_domain),'') is null
     or nullif(btrim(p_source_kind),'') is null
     or nullif(btrim(p_source_id),'') is null then
    raise exception 'spread instance and source identity are required' using errcode='22023';
  end if;

  if p_relationship_kind not in (
    'state','plan','progress','requirement','constraint','window','threshold',
    'sequence','cadence','accumulation','comparison','relationship','place',
    'evidence','exception','memory','action'
  ) then
    raise exception 'invalid relationship kind' using errcode='22023';
  end if;

  if p_binding_state not in ('active','retired') then
    raise exception 'invalid binding state' using errcode='22023';
  end if;

  if not exists (select 1 from atlas.notebook_spread_instances s where s.id=p_spread_instance_id) then
    raise exception 'spread instance not found' using errcode='P0002';
  end if;

  v_retired_at := case when p_binding_state='retired' then now() else null end;

  insert into atlas.notebook_spread_source_bindings(
    spread_instance_id,source_domain,source_kind,source_id,relationship_kind,
    binding_state,basis,metadata,retired_at
  ) values (
    p_spread_instance_id,btrim(p_source_domain),btrim(p_source_kind),btrim(p_source_id),
    p_relationship_kind,p_binding_state,coalesce(p_basis,'{}'::jsonb),
    coalesce(p_metadata,'{}'::jsonb),v_retired_at
  )
  on conflict (spread_instance_id,source_domain,source_kind,source_id,relationship_kind)
  do update set
    binding_state=excluded.binding_state,
    basis=excluded.basis,
    metadata=excluded.metadata,
    retired_at=excluded.retired_at,
    updated_at=now()
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function atlas.bind_notebook_spread_source_v1(uuid,text,text,text,text,text,jsonb,jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.bind_notebook_spread_source_service_v1(
  p_spread_instance_id uuid,
  p_source_domain text,
  p_source_kind text,
  p_source_id text,
  p_relationship_kind text,
  p_binding_state text default 'active',
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.bind_notebook_spread_source_v1(
    p_spread_instance_id,p_source_domain,p_source_kind,p_source_id,
    p_relationship_kind,p_binding_state,p_basis,p_metadata
  );
$function$;

revoke all on function public.bind_notebook_spread_source_service_v1(uuid,text,text,text,text,text,jsonb,jsonb)
  from public, anon, authenticated;
grant execute on function public.bind_notebook_spread_source_service_v1(uuid,text,text,text,text,text,jsonb,jsonb)
  to service_role;

create or replace function atlas.resolve_notebook_spread_instance_v1(
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
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_existing atlas.notebook_spread_instances%rowtype;
  v_id uuid;
begin
  select * into v_existing
  from atlas.notebook_spread_instances s
  where s.principal_id=p_principal_id
    and s.scope_kind=btrim(p_scope_kind)
    and s.scope_id=btrim(p_scope_id)
    and s.subject_kind=btrim(p_subject_kind)
    and s.subject_id=btrim(p_subject_id)
    and s.purpose_key=btrim(p_purpose_key)
    and s.horizon_key=btrim(p_horizon_key)
  limit 1;

  if v_existing.id is not null then
    return jsonb_build_object(
      'ok',true,
      'created',false,
      'spreadInstanceId',v_existing.id,
      'spreadKey',v_existing.spread_key,
      'spreadState',v_existing.spread_state,
      'threadKey',v_existing.thread_key,
      'recipeKey',v_existing.recipe_key,
      'match','semantic_identity'
    );
  end if;

  v_id := atlas.set_notebook_spread_instance_v1(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_recipe_key,p_creation_mode,'open',
    p_composition_contract,p_basis,p_metadata
  );

  return jsonb_build_object(
    'ok',true,
    'created',true,
    'spreadInstanceId',v_id,
    'spreadKey',btrim(p_spread_key),
    'spreadState','open',
    'threadKey',btrim(p_thread_key),
    'recipeKey',nullif(btrim(p_recipe_key),''),
    'match','new_instance'
  );
end;
$function$;

revoke all on function atlas.resolve_notebook_spread_instance_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated, service_role;

create or replace function public.resolve_notebook_spread_instance_service_v1(
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
  p_composition_contract jsonb default '{}'::jsonb,
  p_basis jsonb default '{}'::jsonb,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.resolve_notebook_spread_instance_v1(
    p_principal_id,p_spread_key,p_scope_kind,p_scope_id,p_subject_kind,p_subject_id,
    p_purpose_key,p_horizon_key,p_thread_key,p_recipe_key,p_creation_mode,
    p_composition_contract,p_basis,p_metadata
  );
$function$;

revoke all on function public.resolve_notebook_spread_instance_service_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) from public, anon, authenticated;
grant execute on function public.resolve_notebook_spread_instance_service_v1(
  uuid,text,text,text,text,text,text,text,text,text,text,jsonb,jsonb,jsonb
) to service_role;

create or replace function atlas.notebook_spread_instances_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'atlas', 'auth'
as $function$
  with principal as (
    select p.id
    from atlas.principals p
    where p.user_id=auth.uid() and p.status='active'
    limit 1
  ), spreads as (
    select s.*
    from atlas.notebook_spread_instances s
    join principal p on p.id=s.principal_id
  )
  select jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_spread_instances_self_api_v1',
    'items',coalesce(jsonb_agg(
      jsonb_build_object(
        'spreadInstanceId',s.id,
        'spreadKey',s.spread_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('kind',s.subject_kind,'id',s.subject_id),
        'purposeKey',s.purpose_key,
        'horizonKey',s.horizon_key,
        'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,
        'creationMode',s.creation_mode,
        'spreadState',s.spread_state,
        'compositionContract',s.composition_contract,
        'metadata',s.metadata,
        'openedAt',s.opened_at,
        'closedAt',s.closed_at
      ) order by s.opened_at,s.id
    ),'[]'::jsonb),
    'truthBoundary',jsonb_build_object(
      'spreadExistenceDoesNotGrantSourceAuthority',true,
      'closedSpreadsRemainRetrievable',true,
      'encounterSelectionIsSeparate',true
    )
  )
  from spreads s;
$function$;

revoke all on function atlas.notebook_spread_instances_self_api_v1()
  from public, anon, authenticated, service_role;

create or replace function public.notebook_spread_instances_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog'
as $function$
  select atlas.notebook_spread_instances_self_api_v1();
$function$;

revoke all on function public.notebook_spread_instances_self_api_v1() from public, anon;
grant execute on function public.notebook_spread_instances_self_api_v1() to authenticated, service_role;

commit;
