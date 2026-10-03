-- ATLAS_REALITY_ENTITY_TOPOLOGY_V1
-- Universal topology semantics and bounded traversal over canonical Reality relationships.

create table if not exists reality.topology_axes (
  topology_axis text primary key check (btrim(topology_axis) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  description text not null default '',
  allows_multiple_parents boolean not null default true,
  cycle_policy text not null default 'acyclic' check (cycle_policy in ('acyclic','cycles_permitted')),
  axis_state text not null default 'active' check (axis_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

create table if not exists reality.presence_classes (
  presence_class text primary key check (btrim(presence_class) <> ''),
  display_name text not null check (btrim(display_name) <> ''),
  description text not null default '',
  presence_effect text not null check (presence_effect in ('direct','conditional','contextual')),
  class_state text not null default 'active' check (class_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz
);

create table if not exists reality.relationship_topology_semantics (
  relationship_kind text primary key references reality.relationship_kinds(relationship_kind) on delete restrict,
  topology_axis text references reality.topology_axes(topology_axis) on delete restrict,
  is_structural boolean not null default false,
  parent_direction text not null default 'none' check (parent_direction in ('none','subject_to_object','object_to_subject')),
  is_transitive boolean not null default false,
  propagates_presence boolean not null default false,
  default_presence_class text references reality.presence_classes(presence_class) on delete restrict,
  semantics_state text not null default 'active' check (semantics_state in ('active','retired')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  check ((not is_structural and topology_axis is null and parent_direction='none' and not is_transitive and not propagates_presence and default_presence_class is null)
      or (is_structural and topology_axis is not null and parent_direction<>'none')),
  check (not is_transitive or is_structural),
  check ((not propagates_presence and default_presence_class is null)
      or (propagates_presence and is_structural and default_presence_class is not null))
);

alter table reality.topology_axes enable row level security;
alter table reality.presence_classes enable row level security;
alter table reality.relationship_topology_semantics enable row level security;

revoke all on reality.topology_axes from public, anon, authenticated;
revoke all on reality.presence_classes from public, anon, authenticated;
revoke all on reality.relationship_topology_semantics from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on reality.topology_axes from service_role;
revoke insert, update, delete, truncate, references, trigger on reality.presence_classes from service_role;
revoke insert, update, delete, truncate, references, trigger on reality.relationship_topology_semantics from service_role;
grant select on reality.topology_axes to service_role;
grant select on reality.presence_classes to service_role;
grant select on reality.relationship_topology_semantics to service_role;

create or replace function reality.register_topology_axis_service_v1(
  p_topology_axis text,
  p_display_name text,
  p_description text default '',
  p_allows_multiple_parents boolean default true,
  p_cycle_policy text default 'acyclic',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_key text:=nullif(btrim(p_topology_axis),'');
  v_existing reality.topology_axes%rowtype;
begin
  if v_key is null or nullif(btrim(p_display_name),'') is null then
    raise exception 'Topology axis key and display name are required.' using errcode='22023';
  end if;
  if p_cycle_policy not in ('acyclic','cycles_permitted') then
    raise exception 'cycle_policy must be acyclic or cycles_permitted.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Topology axis metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_existing from reality.topology_axes where topology_axis=v_key;
  if v_existing.topology_axis is not null then
    if v_existing.axis_state='active'
       and v_existing.display_name=btrim(p_display_name)
       and v_existing.description=coalesce(p_description,'')
       and v_existing.allows_multiple_parents=p_allows_multiple_parents
       and v_existing.cycle_policy=p_cycle_policy
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_topology_axis_registration_v1','topologyAxis',v_key,'state','existing');
    end if;
    raise exception 'Topology axis % already exists with different semantics or state.',v_key using errcode='23505';
  end if;

  insert into reality.topology_axes(topology_axis,display_name,description,allows_multiple_parents,cycle_policy,metadata)
  values(v_key,btrim(p_display_name),coalesce(p_description,''),p_allows_multiple_parents,p_cycle_policy,p_metadata);

  return jsonb_build_object('contractVersion','reality_topology_axis_registration_v1','topologyAxis',v_key,'state','registered');
end
$function$;

create or replace function reality.register_presence_class_service_v1(
  p_presence_class text,
  p_display_name text,
  p_description text default '',
  p_presence_effect text default 'conditional',
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_key text:=nullif(btrim(p_presence_class),'');
  v_existing reality.presence_classes%rowtype;
begin
  if v_key is null or nullif(btrim(p_display_name),'') is null then
    raise exception 'Presence class key and display name are required.' using errcode='22023';
  end if;
  if p_presence_effect not in ('direct','conditional','contextual') then
    raise exception 'presence_effect must be direct, conditional, or contextual.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Presence class metadata must be a JSON object.' using errcode='22023';
  end if;

  select * into v_existing from reality.presence_classes where presence_class=v_key;
  if v_existing.presence_class is not null then
    if v_existing.class_state='active'
       and v_existing.display_name=btrim(p_display_name)
       and v_existing.description=coalesce(p_description,'')
       and v_existing.presence_effect=p_presence_effect
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_presence_class_registration_v1','presenceClass',v_key,'state','existing');
    end if;
    raise exception 'Presence class % already exists with different semantics or state.',v_key using errcode='23505';
  end if;

  insert into reality.presence_classes(presence_class,display_name,description,presence_effect,metadata)
  values(v_key,btrim(p_display_name),coalesce(p_description,''),p_presence_effect,p_metadata);

  return jsonb_build_object('contractVersion','reality_presence_class_registration_v1','presenceClass',v_key,'state','registered');
end
$function$;

create or replace function reality.register_relationship_topology_semantics_service_v1(
  p_relationship_kind text,
  p_topology_axis text default null,
  p_is_structural boolean default false,
  p_parent_direction text default 'none',
  p_is_transitive boolean default false,
  p_propagates_presence boolean default false,
  p_default_presence_class text default null,
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_kind text:=nullif(btrim(p_relationship_kind),'');
  v_axis text:=nullif(btrim(p_topology_axis),'');
  v_presence text:=nullif(btrim(p_default_presence_class),'');
  v_existing reality.relationship_topology_semantics%rowtype;
begin
  if v_kind is null or not exists(select 1 from reality.relationship_kinds k where k.relationship_kind=v_kind and k.kind_state='active') then
    raise exception 'Active governed relationship kind required.' using errcode='23514';
  end if;
  if p_parent_direction not in ('none','subject_to_object','object_to_subject') then
    raise exception 'parent_direction is invalid.' using errcode='22023';
  end if;
  if p_metadata is null or jsonb_typeof(p_metadata)<>'object' then
    raise exception 'Topology semantics metadata must be a JSON object.' using errcode='22023';
  end if;
  if p_is_structural then
    if v_axis is null or not exists(select 1 from reality.topology_axes a where a.topology_axis=v_axis and a.axis_state='active') then
      raise exception 'Structural relationship topology requires an active topology axis.' using errcode='23514';
    end if;
    if p_parent_direction='none' then
      raise exception 'Structural relationship topology requires a parent direction.' using errcode='23514';
    end if;
  else
    if v_axis is not null or p_parent_direction<>'none' or p_is_transitive or p_propagates_presence or v_presence is not null then
      raise exception 'Non-structural relationship topology cannot declare structural semantics.' using errcode='23514';
    end if;
  end if;
  if p_is_transitive and not p_is_structural then
    raise exception 'Transitivity requires structural topology.' using errcode='23514';
  end if;
  if p_propagates_presence then
    if not p_is_structural or v_presence is null then
      raise exception 'Presence propagation requires structural topology and a presence class.' using errcode='23514';
    end if;
    if not exists(select 1 from reality.presence_classes c where c.presence_class=v_presence and c.class_state='active') then
      raise exception 'Active governed presence class required.' using errcode='23514';
    end if;
  elsif v_presence is not null then
    raise exception 'Presence class requires presence propagation.' using errcode='23514';
  end if;

  select * into v_existing from reality.relationship_topology_semantics where relationship_kind=v_kind;
  if v_existing.relationship_kind is not null then
    if v_existing.semantics_state='active'
       and v_existing.topology_axis is not distinct from v_axis
       and v_existing.is_structural=p_is_structural
       and v_existing.parent_direction=p_parent_direction
       and v_existing.is_transitive=p_is_transitive
       and v_existing.propagates_presence=p_propagates_presence
       and v_existing.default_presence_class is not distinct from v_presence
       and v_existing.metadata=p_metadata then
      return jsonb_build_object('contractVersion','reality_relationship_topology_semantics_registration_v1','relationshipKind',v_kind,'state','existing');
    end if;
    raise exception 'Relationship topology semantics for % already exist with different semantics or state.',v_kind using errcode='23505';
  end if;

  insert into reality.relationship_topology_semantics(
    relationship_kind,topology_axis,is_structural,parent_direction,is_transitive,propagates_presence,default_presence_class,metadata
  ) values (
    v_kind,v_axis,p_is_structural,p_parent_direction,p_is_transitive,p_propagates_presence,v_presence,p_metadata
  );

  return jsonb_build_object('contractVersion','reality_relationship_topology_semantics_registration_v1','relationshipKind',v_kind,'state','registered');
end
$function$;

create or replace function reality.entity_topology_paths_service_v1(
  p_entity_id uuid,
  p_topology_axis text default null,
  p_direction text default 'ancestors',
  p_max_depth integer default 8,
  p_as_of timestamptz default now(),
  p_presence_only boolean default false
) returns table(
  start_entity_id uuid,
  related_entity_id uuid,
  depth integer,
  path_entity_ids uuid[],
  path_relationship_ids uuid[],
  path_relationship_kinds text[],
  path_topology_axes text[],
  path_relationship_states text[],
  path_presence_classes text[]
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if p_entity_id is null or not exists(select 1 from reality.entities e where e.id=p_entity_id and e.identity_state<>'retired') then
    raise exception 'Active canonical start Entity required.' using errcode='P0002';
  end if;
  if p_direction not in ('ancestors','descendants') then
    raise exception 'Topology direction must be ancestors or descendants.' using errcode='22023';
  end if;
  if p_max_depth is null or p_max_depth<1 or p_max_depth>16 then
    raise exception 'Topology max depth must be between 1 and 16.' using errcode='22023';
  end if;
  if p_as_of is null then
    raise exception 'Topology as_of is required.' using errcode='22023';
  end if;
  if p_topology_axis is not null and not exists(
    select 1 from reality.topology_axes a where a.topology_axis=p_topology_axis and a.axis_state='active'
  ) then
    raise exception 'Active topology axis required when supplied.' using errcode='23514';
  end if;

  return query
  with recursive edges as (
    select
      r.id as relationship_id,
      r.relationship_kind,
      r.relationship_state,
      s.topology_axis,
      s.is_transitive,
      s.propagates_presence,
      s.default_presence_class,
      case when s.parent_direction='subject_to_object' then r.subject_entity_id else r.object_entity_id end as child_entity_id,
      case when s.parent_direction='subject_to_object' then r.object_entity_id else r.subject_entity_id end as parent_entity_id
    from reality.entity_relationships r
    join reality.relationship_topology_semantics s
      on s.relationship_kind=r.relationship_kind
     and s.semantics_state='active'
     and s.is_structural
    where r.relationship_state in ('observed','established')
      and (r.valid_from is null or r.valid_from<=p_as_of)
      and (r.valid_until is null or r.valid_until>p_as_of)
      and (p_topology_axis is null or s.topology_axis=p_topology_axis)
      and (not p_presence_only or s.propagates_presence)
  ), walk as (
    select
      p_entity_id as start_entity_id,
      case when p_direction='ancestors' then e.parent_entity_id else e.child_entity_id end as related_entity_id,
      1 as depth,
      array[p_entity_id,case when p_direction='ancestors' then e.parent_entity_id else e.child_entity_id end]::uuid[] as path_entity_ids,
      array[e.relationship_id]::uuid[] as path_relationship_ids,
      array[e.relationship_kind]::text[] as path_relationship_kinds,
      array[e.topology_axis]::text[] as path_topology_axes,
      array[e.relationship_state]::text[] as path_relationship_states,
      array[e.default_presence_class]::text[] as path_presence_classes,
      e.is_transitive as can_continue
    from edges e
    where (p_direction='ancestors' and e.child_entity_id=p_entity_id)
       or (p_direction='descendants' and e.parent_entity_id=p_entity_id)

    union all

    select
      w.start_entity_id,
      case when p_direction='ancestors' then e.parent_entity_id else e.child_entity_id end,
      w.depth+1,
      w.path_entity_ids || case when p_direction='ancestors' then e.parent_entity_id else e.child_entity_id end,
      w.path_relationship_ids || e.relationship_id,
      w.path_relationship_kinds || e.relationship_kind,
      w.path_topology_axes || e.topology_axis,
      w.path_relationship_states || e.relationship_state,
      w.path_presence_classes || e.default_presence_class,
      e.is_transitive
    from walk w
    join edges e
      on w.can_continue
     and (
       (p_direction='ancestors' and e.child_entity_id=w.related_entity_id)
       or
       (p_direction='descendants' and e.parent_entity_id=w.related_entity_id)
     )
    where w.depth<p_max_depth
      and not (case when p_direction='ancestors' then e.parent_entity_id else e.child_entity_id end = any(w.path_entity_ids))
  )
  select
    w.start_entity_id,w.related_entity_id,w.depth,w.path_entity_ids,w.path_relationship_ids,
    w.path_relationship_kinds,w.path_topology_axes,w.path_relationship_states,w.path_presence_classes
  from walk w
  order by w.depth,w.related_entity_id,w.path_relationship_ids;
end
$function$;

create or replace function reality.entity_presence_paths_service_v1(
  p_root_entity_id uuid,
  p_topology_axis text default null,
  p_max_depth integer default 8,
  p_as_of timestamptz default now()
) returns table(
  root_entity_id uuid,
  presence_entity_id uuid,
  depth integer,
  effective_presence_effect text,
  terminal_presence_class text,
  path_entity_ids uuid[],
  path_relationship_ids uuid[],
  path_relationship_kinds text[],
  path_topology_axes text[],
  path_relationship_states text[],
  path_presence_classes text[]
)
language sql
stable
security definer
set search_path to ''
as $function$
  select
    p.start_entity_id,
    p.related_entity_id,
    p.depth,
    case
      when exists(
        select 1
        from unnest(p.path_presence_classes) pc
        join reality.presence_classes c on c.presence_class=pc
        where c.presence_effect='contextual'
      ) then 'contextual'
      when exists(
        select 1
        from unnest(p.path_presence_classes) pc
        join reality.presence_classes c on c.presence_class=pc
        where c.presence_effect='conditional'
      ) then 'conditional'
      else 'direct'
    end as effective_presence_effect,
    p.path_presence_classes[array_length(p.path_presence_classes,1)] as terminal_presence_class,
    p.path_entity_ids,p.path_relationship_ids,p.path_relationship_kinds,p.path_topology_axes,p.path_relationship_states,p.path_presence_classes
  from reality.entity_topology_paths_service_v1(
    p_root_entity_id,p_topology_axis,'descendants',p_max_depth,p_as_of,true
  ) p
$function$;

create or replace function reality.relationship_would_create_topology_cycle_v1(
  p_subject_entity_id uuid,
  p_relationship_kind text,
  p_object_entity_id uuid,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null
) returns boolean
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_sem reality.relationship_topology_semantics%rowtype;
  v_axis reality.topology_axes%rowtype;
  v_child uuid;
  v_parent uuid;
  v_cycle boolean:=false;
begin
  select * into v_sem
  from reality.relationship_topology_semantics
  where relationship_kind=p_relationship_kind and semantics_state='active';

  if v_sem.relationship_kind is null or not v_sem.is_structural then
    return false;
  end if;

  select * into v_axis from reality.topology_axes where topology_axis=v_sem.topology_axis and axis_state='active';
  if v_axis.topology_axis is null or v_axis.cycle_policy='cycles_permitted' then
    return false;
  end if;

  v_child:=case when v_sem.parent_direction='subject_to_object' then p_subject_entity_id else p_object_entity_id end;
  v_parent:=case when v_sem.parent_direction='subject_to_object' then p_object_entity_id else p_subject_entity_id end;

  with recursive edges as (
    select
      case when s.parent_direction='subject_to_object' then r.subject_entity_id else r.object_entity_id end as child_entity_id,
      case when s.parent_direction='subject_to_object' then r.object_entity_id else r.subject_entity_id end as parent_entity_id
    from reality.entity_relationships r
    join reality.relationship_topology_semantics s
      on s.relationship_kind=r.relationship_kind
     and s.semantics_state='active'
     and s.is_structural
     and s.topology_axis=v_sem.topology_axis
    where r.relationship_state in ('observed','established')
      and tstzrange(coalesce(r.valid_from,'-infinity'::timestamptz),coalesce(r.valid_until,'infinity'::timestamptz),'[)')
          && tstzrange(coalesce(p_valid_from,'-infinity'::timestamptz),coalesce(p_valid_until,'infinity'::timestamptz),'[)')
  ), walk as (
    select e.parent_entity_id as entity_id,array[v_parent,e.parent_entity_id]::uuid[] as path
    from edges e where e.child_entity_id=v_parent
    union all
    select e.parent_entity_id,w.path||e.parent_entity_id
    from walk w
    join edges e on e.child_entity_id=w.entity_id
    where not (e.parent_entity_id=any(w.path))
  )
  select exists(select 1 from walk where entity_id=v_child) into v_cycle;

  return v_cycle;
end
$function$;

create or replace function reality.entity_topology_roots_service_v1(
  p_entity_id uuid,
  p_topology_axis text,
  p_max_depth integer default 8,
  p_as_of timestamptz default now()
) returns table(
  root_entity_id uuid,
  depth integer,
  path_entity_ids uuid[],
  path_relationship_ids uuid[],
  path_relationship_kinds text[]
)
language sql
stable
security definer
set search_path to ''
as $function$
  with paths as (
    select * from reality.entity_topology_paths_service_v1(p_entity_id,p_topology_axis,'ancestors',p_max_depth,p_as_of,false)
  ), candidates as (
    select p.related_entity_id as entity_id,p.depth,p.path_entity_ids,p.path_relationship_ids,p.path_relationship_kinds
    from paths p
    union all
    select p_entity_id,0,array[p_entity_id]::uuid[],'{}'::uuid[],'{}'::text[]
    where not exists(select 1 from paths)
  )
  select c.entity_id,c.depth,c.path_entity_ids,c.path_relationship_ids,c.path_relationship_kinds
  from candidates c
  where not exists(
    select 1
    from reality.entity_topology_paths_service_v1(c.entity_id,p_topology_axis,'ancestors',1,p_as_of,false) next_path
  )
  order by c.depth desc,c.entity_id
$function$;

-- Extend relationship validation with topology cycle/cardinality laws.
create or replace function reality.validate_relationship_proposition_v1(
  p_subject_entity_id uuid,
  p_relationship_kind text,
  p_object_entity_id uuid,
  p_valid_from timestamptz default null,
  p_valid_until timestamptz default null
) returns void
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_subject reality.entities%rowtype;
  v_object reality.entities%rowtype;
  v_kind reality.relationship_kinds%rowtype;
  v_sem reality.relationship_topology_semantics%rowtype;
  v_axis reality.topology_axes%rowtype;
  v_child uuid;
  v_parent uuid;
begin
  if p_subject_entity_id is null or p_object_entity_id is null then raise exception 'Relationship subject and object Entities are required.' using errcode='22023'; end if;
  if p_subject_entity_id=p_object_entity_id then raise exception 'Self relationship is not permitted in v1.' using errcode='23514'; end if;
  if nullif(btrim(p_relationship_kind),'') is null then raise exception 'Relationship kind is required.' using errcode='22023'; end if;
  if p_valid_until is not null and p_valid_from is not null and p_valid_until<=p_valid_from then raise exception 'Relationship valid_until must be greater than valid_from.' using errcode='22023'; end if;

  select * into v_subject from reality.entities where id=p_subject_entity_id and identity_state<>'retired';
  if v_subject.id is null then raise exception 'Active canonical subject Entity required.' using errcode='P0002'; end if;
  select * into v_object from reality.entities where id=p_object_entity_id and identity_state<>'retired';
  if v_object.id is null then raise exception 'Active canonical object Entity required.' using errcode='P0002'; end if;
  select * into v_kind from reality.relationship_kinds where relationship_kind=btrim(p_relationship_kind) and kind_state='active';
  if v_kind.relationship_kind is null then raise exception 'Active governed relationship kind required: %',p_relationship_kind using errcode='23514'; end if;
  if v_kind.allowed_subject_kinds is not null and not (v_subject.entity_kind=any(v_kind.allowed_subject_kinds)) then raise exception 'Subject Entity kind % is not permitted for relationship kind %.',v_subject.entity_kind,v_kind.relationship_kind using errcode='23514'; end if;
  if v_kind.allowed_object_kinds is not null and not (v_object.entity_kind=any(v_kind.allowed_object_kinds)) then raise exception 'Object Entity kind % is not permitted for relationship kind %.',v_object.entity_kind,v_kind.relationship_kind using errcode='23514'; end if;

  select * into v_sem from reality.relationship_topology_semantics where relationship_kind=v_kind.relationship_kind and semantics_state='active';
  if v_sem.relationship_kind is null or not v_sem.is_structural then return; end if;

  select * into v_axis from reality.topology_axes where topology_axis=v_sem.topology_axis and axis_state='active';
  if v_axis.topology_axis is null then raise exception 'Active topology axis required by relationship semantics.' using errcode='23514'; end if;

  v_child:=case when v_sem.parent_direction='subject_to_object' then p_subject_entity_id else p_object_entity_id end;
  v_parent:=case when v_sem.parent_direction='subject_to_object' then p_object_entity_id else p_subject_entity_id end;

  if reality.relationship_would_create_topology_cycle_v1(p_subject_entity_id,v_kind.relationship_kind,p_object_entity_id,p_valid_from,p_valid_until) then
    raise exception 'Relationship would create an illegal cycle on topology axis %.',v_sem.topology_axis using errcode='23514';
  end if;

  if not v_axis.allows_multiple_parents and exists(
    select 1
    from reality.entity_relationships r
    join reality.relationship_topology_semantics s
      on s.relationship_kind=r.relationship_kind
     and s.semantics_state='active'
     and s.is_structural
     and s.topology_axis=v_sem.topology_axis
    where r.relationship_state in ('observed','established')
      and (case when s.parent_direction='subject_to_object' then r.subject_entity_id else r.object_entity_id end)=v_child
      and (case when s.parent_direction='subject_to_object' then r.object_entity_id else r.subject_entity_id end)<>v_parent
      and tstzrange(coalesce(r.valid_from,'-infinity'::timestamptz),coalesce(r.valid_until,'infinity'::timestamptz),'[)')
          && tstzrange(coalesce(p_valid_from,'-infinity'::timestamptz),coalesce(p_valid_until,'infinity'::timestamptz),'[)')
  ) then
    raise exception 'Topology axis % permits only one simultaneous parent.',v_sem.topology_axis using errcode='23514';
  end if;
end
$function$;

-- Target predicate grammar extension: AT_LEAST_N and topology_path_exists.
create or replace function ledger.validate_target_predicate_v1(p_predicate jsonb,p_depth integer default 0)
returns void
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_op text;
  v_child jsonb;
  v_entity_id uuid;
  v_counterparty_id uuid;
  v_minimum integer;
  v_max_depth integer;
  v_all_axes boolean;
begin
  if p_depth<0 or p_depth>12 then raise exception 'Target predicate nesting exceeds v1 limit.' using errcode='22023'; end if;
  if p_predicate is null or jsonb_typeof(p_predicate)<>'object' then raise exception 'Target predicate must be a JSON object.' using errcode='22023'; end if;
  v_op:=nullif(btrim(p_predicate->>'op'),'');
  if v_op is null then raise exception 'Target predicate op is required.' using errcode='22023'; end if;

  if v_op in ('all','any') then
    if p_predicate-'op'-'predicates'<>'{}'::jsonb then raise exception 'Target % predicate contains unsupported fields.',v_op using errcode='22023'; end if;
    if jsonb_typeof(p_predicate->'predicates')<>'array' or jsonb_array_length(p_predicate->'predicates')=0 then raise exception 'Target % predicate requires a non-empty predicates array.',v_op using errcode='22023'; end if;
    for v_child in select value from jsonb_array_elements(p_predicate->'predicates') loop perform ledger.validate_target_predicate_v1(v_child,p_depth+1); end loop;
    return;
  end if;

  if v_op='at_least_n' then
    if p_predicate-'op'-'minimum'-'predicates'<>'{}'::jsonb then raise exception 'at_least_n contains unsupported fields.' using errcode='22023'; end if;
    if jsonb_typeof(p_predicate->'predicates')<>'array' or jsonb_array_length(p_predicate->'predicates')=0 then raise exception 'at_least_n requires a non-empty predicates array.' using errcode='22023'; end if;
    begin v_minimum:=(p_predicate->>'minimum')::integer; exception when others then raise exception 'at_least_n minimum must be an integer.' using errcode='22023'; end;
    if v_minimum<1 or v_minimum>jsonb_array_length(p_predicate->'predicates') then raise exception 'at_least_n minimum must be between 1 and predicate count.' using errcode='22023'; end if;
    for v_child in select value from jsonb_array_elements(p_predicate->'predicates') loop perform ledger.validate_target_predicate_v1(v_child,p_depth+1); end loop;
    return;
  end if;

  if v_op='not' then
    if p_predicate-'op'-'predicate'<>'{}'::jsonb then raise exception 'Target not predicate contains unsupported fields.' using errcode='22023'; end if;
    if jsonb_typeof(p_predicate->'predicate')<>'object' then raise exception 'Target not predicate requires one nested predicate.' using errcode='22023'; end if;
    perform ledger.validate_target_predicate_v1(p_predicate->'predicate',p_depth+1);
    return;
  end if;

  if v_op='entity_kind_is' then
    if p_predicate-'op'-'entityKind'<>'{}'::jsonb then raise exception 'entity_kind_is contains unsupported fields.' using errcode='22023'; end if;
    if nullif(btrim(p_predicate->>'entityKind'),'') is null then raise exception 'entity_kind_is requires entityKind.' using errcode='22023'; end if;
    return;
  end if;

  if v_op='entity_id_is' then
    if p_predicate-'op'-'entityId'<>'{}'::jsonb then raise exception 'entity_id_is contains unsupported fields.' using errcode='22023'; end if;
    if nullif(btrim(p_predicate->>'entityId'),'') is null then raise exception 'entity_id_is requires entityId.' using errcode='22023'; end if;
    begin v_entity_id:=(p_predicate->>'entityId')::uuid; exception when invalid_text_representation then raise exception 'entity_id_is requires a valid UUID.' using errcode='22023'; end;
    return;
  end if;

  if v_op='relationship_exists' then
    if p_predicate-'op'-'relationshipKind'-'direction'-'counterpartyEntityId'<>'{}'::jsonb then raise exception 'relationship_exists contains unsupported fields.' using errcode='22023'; end if;
    if nullif(btrim(p_predicate->>'relationshipKind'),'') is null then raise exception 'relationship_exists requires relationshipKind.' using errcode='22023'; end if;
    if coalesce(p_predicate->>'direction','') not in ('outbound','inbound') then raise exception 'relationship_exists direction must be outbound or inbound.' using errcode='22023'; end if;
    if nullif(btrim(p_predicate->>'counterpartyEntityId'),'') is null then raise exception 'relationship_exists requires counterpartyEntityId.' using errcode='22023'; end if;
    begin v_counterparty_id:=(p_predicate->>'counterpartyEntityId')::uuid; exception when invalid_text_representation then raise exception 'relationship_exists requires a valid counterpartyEntityId UUID.' using errcode='22023'; end;
    return;
  end if;

  if v_op='topology_path_exists' then
    if p_predicate-'op'-'topologyAxis'-'allAxes'-'direction'-'maxDepth'-'presenceOnly'-'endpointPredicate'<>'{}'::jsonb then raise exception 'topology_path_exists contains unsupported fields.' using errcode='22023'; end if;
    v_all_axes:=coalesce((p_predicate->>'allAxes')::boolean,false);
    if (nullif(btrim(p_predicate->>'topologyAxis'),'') is null)=not v_all_axes then
      raise exception 'topology_path_exists requires exactly one of topologyAxis or allAxes=true.' using errcode='22023';
    end if;
    if coalesce(p_predicate->>'direction','') not in ('ancestors','descendants') then raise exception 'topology_path_exists direction must be ancestors or descendants.' using errcode='22023'; end if;
    begin v_max_depth:=coalesce((p_predicate->>'maxDepth')::integer,8); exception when others then raise exception 'topology_path_exists maxDepth must be an integer.' using errcode='22023'; end;
    if v_max_depth<1 or v_max_depth>16 then raise exception 'topology_path_exists maxDepth must be between 1 and 16.' using errcode='22023'; end if;
    if p_predicate ? 'presenceOnly' and jsonb_typeof(p_predicate->'presenceOnly')<>'boolean' then raise exception 'topology_path_exists presenceOnly must be boolean.' using errcode='22023'; end if;
    if jsonb_typeof(p_predicate->'endpointPredicate')<>'object' then raise exception 'topology_path_exists requires endpointPredicate.' using errcode='22023'; end if;
    perform ledger.validate_target_predicate_v1(p_predicate->'endpointPredicate',p_depth+1);
    return;
  end if;

  raise exception 'Unsupported Target predicate op: %',v_op using errcode='22023';
end
$function$;

create or replace function ledger.evaluate_target_predicate_v1(p_subject_entity_id uuid,p_predicate jsonb,p_path text default '$',p_depth integer default 0)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_op text; v_subject reality.entities%rowtype; v_child jsonb; v_child_result jsonb; v_children jsonb:='[]'::jsonb; v_obligations jsonb:='[]'::jsonb; v_state text; v_child_state text; v_idx bigint;
  v_true_count integer:=0; v_false_count integer:=0; v_unknown_count integer:=0; v_entity_id uuid; v_counterparty_id uuid; v_counterparty reality.entities%rowtype; v_relationship_kind text; v_direction text; v_subject_side uuid; v_object_side uuid; v_relationship_ids jsonb:='[]'::jsonb; v_disputed boolean:=false;
  v_minimum integer; v_topology_axis text; v_max_depth integer; v_presence_only boolean; v_path_record record; v_path_result jsonb; v_path_results jsonb:='[]'::jsonb; v_endpoint_result jsonb; v_endpoint_idx integer:=0;
begin
  perform ledger.validate_target_predicate_v1(p_predicate,p_depth);
  select * into v_subject from reality.entities where id=p_subject_entity_id and identity_state<>'retired';
  if v_subject.id is null then raise exception 'Active Reality subject Entity required.' using errcode='P0002'; end if;
  v_op:=p_predicate->>'op';

  if v_op in ('all','any','at_least_n') then
    if v_op='at_least_n' then v_minimum:=(p_predicate->>'minimum')::integer; end if;
    for v_child,v_idx in select value,ordinality from jsonb_array_elements(p_predicate->'predicates') with ordinality loop
      v_child_result:=ledger.evaluate_target_predicate_v1(p_subject_entity_id,v_child,p_path||'.predicates['||(v_idx-1)::text||']',p_depth+1);
      v_children:=v_children||jsonb_build_array(v_child_result);
      v_obligations:=v_obligations||coalesce(v_child_result->'obligations','[]'::jsonb);
      v_child_state:=v_child_result->>'state';
      if v_child_state='true' then v_true_count:=v_true_count+1; elsif v_child_state='false' then v_false_count:=v_false_count+1; else v_unknown_count:=v_unknown_count+1; end if;
    end loop;

    if v_op='all' then
      if v_false_count>0 then v_state:='false'; v_obligations:='[]'::jsonb;
      elsif v_unknown_count>0 then v_state:='unknown';
      else v_state:='true'; v_obligations:='[]'::jsonb; end if;
    elsif v_op='any' then
      if v_true_count>0 then v_state:='true'; v_obligations:='[]'::jsonb;
      elsif v_unknown_count>0 then v_state:='unknown';
      else v_state:='false'; v_obligations:='[]'::jsonb; end if;
    else
      if v_true_count>=v_minimum then v_state:='true'; v_obligations:='[]'::jsonb;
      elsif v_true_count+v_unknown_count<v_minimum then v_state:='false'; v_obligations:='[]'::jsonb;
      else v_state:='unknown'; end if;
    end if;

    return jsonb_build_object('path',p_path,'op',v_op,'state',v_state,'children',v_children,'obligations',v_obligations)
      || case when v_op='at_least_n' then jsonb_build_object('minimum',v_minimum) else '{}'::jsonb end;
  end if;

  if v_op='not' then
    v_child_result:=ledger.evaluate_target_predicate_v1(p_subject_entity_id,p_predicate->'predicate',p_path||'.predicate',p_depth+1);
    v_child_state:=v_child_result->>'state';
    v_state:=case v_child_state when 'true' then 'false' when 'false' then 'true' else 'unknown' end;
    return jsonb_build_object('path',p_path,'op',v_op,'state',v_state,'child',v_child_result,'obligations',case when v_state='unknown' then coalesce(v_child_result->'obligations','[]'::jsonb) else '[]'::jsonb end);
  end if;

  if v_op='entity_kind_is' then
    v_state:=case when v_subject.entity_kind=p_predicate->>'entityKind' then 'true' else 'false' end;
    return jsonb_build_object('path',p_path,'op',v_op,'state',v_state,'expectedEntityKind',p_predicate->>'entityKind','actualEntityKind',v_subject.entity_kind,'obligations','[]'::jsonb);
  end if;

  if v_op='entity_id_is' then
    v_entity_id:=(p_predicate->>'entityId')::uuid;
    v_state:=case when p_subject_entity_id=v_entity_id then 'true' else 'false' end;
    return jsonb_build_object('path',p_path,'op',v_op,'state',v_state,'expectedEntityId',v_entity_id,'actualEntityId',p_subject_entity_id,'obligations','[]'::jsonb);
  end if;

  if v_op='relationship_exists' then
    v_counterparty_id:=(p_predicate->>'counterpartyEntityId')::uuid; v_relationship_kind:=p_predicate->>'relationshipKind'; v_direction:=p_predicate->>'direction';
    select * into v_counterparty from reality.entities where id=v_counterparty_id and identity_state<>'retired';
    if v_counterparty.id is null then raise exception 'Target predicate counterparty Reality Entity is absent or retired.' using errcode='23514'; end if;
    if v_direction='outbound' then v_subject_side:=p_subject_entity_id; v_object_side:=v_counterparty_id; else v_subject_side:=v_counterparty_id; v_object_side:=p_subject_entity_id; end if;
    select coalesce(jsonb_agg(r.id order by r.created_at,r.id),'[]'::jsonb) into v_relationship_ids
    from reality.entity_relationships r
    where r.subject_entity_id=v_subject_side and r.object_entity_id=v_object_side and r.relationship_kind=v_relationship_kind
      and r.relationship_state in ('observed','established') and (r.valid_from is null or r.valid_from<=now()) and (r.valid_until is null or r.valid_until>now());
    if jsonb_array_length(v_relationship_ids)>0 then
      return jsonb_build_object('path',p_path,'op',v_op,'state','true','relationshipKind',v_relationship_kind,'direction',v_direction,'counterpartyEntityId',v_counterparty_id,'relationshipIds',v_relationship_ids,'obligations','[]'::jsonb);
    end if;
    select exists(select 1 from reality.entity_relationships r where r.subject_entity_id=v_subject_side and r.object_entity_id=v_object_side and r.relationship_kind=v_relationship_kind and r.relationship_state='disputed' and (r.valid_from is null or r.valid_from<=now()) and (r.valid_until is null or r.valid_until>now())) into v_disputed;
    v_obligations:=jsonb_build_array(jsonb_build_object('kind','resolve_relationship_proposition','predicatePath',p_path,'proposition',jsonb_build_object('subjectEntityId',p_subject_entity_id,'relationshipKind',v_relationship_kind,'direction',v_direction,'counterpartyEntityId',v_counterparty_id),'reason',case when v_disputed then 'relationship_disputed' else 'relationship_not_established' end));
    return jsonb_build_object('path',p_path,'op',v_op,'state','unknown','relationshipKind',v_relationship_kind,'direction',v_direction,'counterpartyEntityId',v_counterparty_id,'reason',case when v_disputed then 'relationship_disputed' else 'relationship_not_established' end,'obligations',v_obligations);
  end if;

  if v_op='topology_path_exists' then
    v_topology_axis:=case when coalesce((p_predicate->>'allAxes')::boolean,false) then null else p_predicate->>'topologyAxis' end;
    v_direction:=p_predicate->>'direction';
    v_max_depth:=coalesce((p_predicate->>'maxDepth')::integer,8);
    v_presence_only:=coalesce((p_predicate->>'presenceOnly')::boolean,false);

    for v_path_record in
      select * from reality.entity_topology_paths_service_v1(p_subject_entity_id,v_topology_axis,v_direction,v_max_depth,now(),v_presence_only)
    loop
      v_endpoint_idx:=v_endpoint_idx+1;
      v_endpoint_result:=ledger.evaluate_target_predicate_v1(v_path_record.related_entity_id,p_predicate->'endpointPredicate',p_path||'.endpoints['||(v_endpoint_idx-1)::text||']',p_depth+1);
      v_path_result:=jsonb_build_object(
        'endpointEntityId',v_path_record.related_entity_id,
        'depth',v_path_record.depth,
        'proof',jsonb_build_object(
          'entityIds',to_jsonb(v_path_record.path_entity_ids),
          'relationshipIds',to_jsonb(v_path_record.path_relationship_ids),
          'relationshipKinds',to_jsonb(v_path_record.path_relationship_kinds),
          'topologyAxes',to_jsonb(v_path_record.path_topology_axes),
          'relationshipStates',to_jsonb(v_path_record.path_relationship_states),
          'presenceClasses',to_jsonb(v_path_record.path_presence_classes)
        ),
        'endpointResult',v_endpoint_result
      );
      v_path_results:=v_path_results||jsonb_build_array(v_path_result);
      v_child_state:=v_endpoint_result->>'state';
      if v_child_state='true' then v_true_count:=v_true_count+1; elsif v_child_state='false' then v_false_count:=v_false_count+1; else v_unknown_count:=v_unknown_count+1; v_obligations:=v_obligations||coalesce(v_endpoint_result->'obligations','[]'::jsonb); end if;
    end loop;

    if v_true_count>0 then
      v_state:='true'; v_obligations:='[]'::jsonb;
    else
      v_state:='unknown';
      v_obligations:=v_obligations||jsonb_build_array(jsonb_build_object(
        'kind','resolve_topology_path',
        'predicatePath',p_path,
        'proposition',jsonb_strip_nulls(jsonb_build_object(
          'rootEntityId',p_subject_entity_id,
          'topologyAxis',v_topology_axis,
          'allAxes',coalesce((p_predicate->>'allAxes')::boolean,false),
          'direction',v_direction,
          'maxDepth',v_max_depth,
          'presenceOnly',v_presence_only,
          'endpointPredicate',p_predicate->'endpointPredicate'
        )),
        'reason','matching_topology_path_not_established'
      ));
    end if;

    return jsonb_build_object(
      'path',p_path,'op',v_op,'state',v_state,'topologyAxis',v_topology_axis,'allAxes',coalesce((p_predicate->>'allAxes')::boolean,false),
      'direction',v_direction,'maxDepth',v_max_depth,'presenceOnly',v_presence_only,'knownPaths',v_path_results,'obligations',v_obligations
    );
  end if;

  raise exception 'Unsupported Target predicate op at evaluation: %',v_op using errcode='22023';
end
$function$;

revoke all on function reality.register_topology_axis_service_v1(text,text,text,boolean,text,jsonb) from public, anon, authenticated;
revoke all on function reality.register_presence_class_service_v1(text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function reality.register_relationship_topology_semantics_service_v1(text,text,boolean,text,boolean,boolean,text,jsonb) from public, anon, authenticated;
revoke all on function reality.entity_topology_paths_service_v1(uuid,text,text,integer,timestamptz,boolean) from public, anon, authenticated;
revoke all on function reality.entity_presence_paths_service_v1(uuid,text,integer,timestamptz) from public, anon, authenticated;
revoke all on function reality.entity_topology_roots_service_v1(uuid,text,integer,timestamptz) from public, anon, authenticated;
revoke all on function reality.relationship_would_create_topology_cycle_v1(uuid,text,uuid,timestamptz,timestamptz) from public, anon, authenticated;

grant execute on function reality.register_topology_axis_service_v1(text,text,text,boolean,text,jsonb) to service_role;
grant execute on function reality.register_presence_class_service_v1(text,text,text,text,jsonb) to service_role;
grant execute on function reality.register_relationship_topology_semantics_service_v1(text,text,boolean,text,boolean,boolean,text,jsonb) to service_role;
grant execute on function reality.entity_topology_paths_service_v1(uuid,text,text,integer,timestamptz,boolean) to service_role;
grant execute on function reality.entity_presence_paths_service_v1(uuid,text,integer,timestamptz) to service_role;
grant execute on function reality.entity_topology_roots_service_v1(uuid,text,integer,timestamptz) to service_role;
grant execute on function reality.relationship_would_create_topology_cycle_v1(uuid,text,uuid,timestamptz,timestamptz) to service_role;
