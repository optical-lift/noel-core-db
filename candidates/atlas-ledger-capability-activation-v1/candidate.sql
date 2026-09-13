-- Atlas Ledger Capability Activation v1 candidate.
-- Gate A runtime seam for governed, Ledger-bound capabilities.
-- Candidate source only. Promote to supabase/migrations only with a Supabase-generated migration identity.

begin;

create table atlas.capability_definitions (
  capability_key text not null check (btrim(capability_key)<>''),
  capability_version integer not null check (capability_version>0),
  status text not null default 'active' check (status in ('active','retired')),
  eligible_subject_kinds text[] not null check (cardinality(eligible_subject_kinds)>0),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  primary key (capability_key,capability_version),
  check ((status='active' and retired_at is null) or (status='retired' and retired_at is not null))
);
alter table atlas.capability_definitions enable row level security;
revoke all on atlas.capability_definitions from public,anon,authenticated;
comment on table atlas.capability_definitions is 'Migration-governed capability registry. Definitions identify governed capability contracts and supported subject kinds; they are not customer-authored domain schema.';

insert into atlas.capability_definitions(capability_key,capability_version,status,eligible_subject_kinds)
values ('teaching',1,'active',array['ledger']::text[]);

create table atlas.capability_activations (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  capability_key text not null,
  capability_version integer not null,
  subject_ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  subject_kind text not null check (btrim(subject_kind)<>''),
  subject_id uuid,
  subject_key text,
  subject_path text,
  state text not null default 'draft' check (state in ('draft','active','paused','retired')),
  created_by_person_id uuid not null references atlas.people(id) on delete restrict,
  created_by_principal_id uuid not null references atlas.principals(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  retired_at timestamptz,
  foreign key (capability_key,capability_version)
    references atlas.capability_definitions(capability_key,capability_version) on delete restrict,
  check (subject_id is not null or nullif(btrim(subject_key),'') is not null),
  check (subject_key is null or btrim(subject_key)<>''),
  check (subject_path is null or btrim(subject_path)<>''),
  check ((state in ('draft','active','paused') and retired_at is null) or (state='retired' and retired_at is not null))
);
create unique index capability_activations_one_live_semantic_uq
  on atlas.capability_activations(
    ledger_id,capability_key,capability_version,subject_ledger_id,subject_kind,
    coalesce(subject_id,'00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(subject_key,''),coalesce(subject_path,'')
  ) where state<>'retired';
create index capability_activations_ledger_state_idx
  on atlas.capability_activations(ledger_id,state,capability_key,capability_version);
alter table atlas.capability_activations enable row level security;
revoke all on atlas.capability_activations from public,anon,authenticated;
create trigger capability_activations_set_updated_at before update on atlas.capability_activations
for each row execute function atlas.set_updated_at();
comment on table atlas.capability_activations is 'Durable Ledger-bound capability activation. Attaches a governed capability to a typed subject address without copying or converting that subject.';

create table atlas.capability_activation_events (
  id uuid primary key default gen_random_uuid(),
  capability_activation_id uuid not null references atlas.capability_activations(id) on delete restrict,
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  actor_person_id uuid not null references atlas.people(id) on delete restrict,
  actor_principal_id uuid not null references atlas.principals(id) on delete restrict,
  principal_ledger_authority_id uuid not null references atlas.principal_ledger_authorities(id) on delete restrict,
  from_state text check (from_state is null or from_state in ('draft','active','paused','retired')),
  to_state text not null check (to_state in ('draft','active','paused','retired')),
  event_kind text not null check (event_kind in ('created','activated','paused','resumed','retired')),
  reason text,
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (
    (event_kind='created' and from_state is null and to_state='draft') or
    (event_kind='activated' and from_state='draft' and to_state='active') or
    (event_kind='paused' and from_state='active' and to_state='paused') or
    (event_kind='resumed' and from_state='paused' and to_state='active') or
    (event_kind='retired' and from_state in ('draft','active','paused') and to_state='retired')
  )
);
create index capability_activation_events_activation_time_idx
  on atlas.capability_activation_events(capability_activation_id,occurred_at,created_at);
alter table atlas.capability_activation_events enable row level security;
revoke all on atlas.capability_activation_events from public,anon,authenticated;
comment on table atlas.capability_activation_events is 'Append-only capability lifecycle evidence with exact Person, Principal, and root Principal/Ledger authority used at transition time.';

create table atlas.capability_entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  ledger_id uuid not null references atlas.ledgers(id) on delete restrict,
  ledger_entitlement_binding_id uuid not null references atlas.ledger_entitlement_bindings(id) on delete restrict,
  capability_key text not null,
  capability_version integer not null,
  state text not null default 'active' check (state in ('active','ended')),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  established_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (capability_key,capability_version)
    references atlas.capability_definitions(capability_key,capability_version) on delete restrict,
  check ((state='active' and ended_at is null) or (state='ended' and ended_at is not null))
);
create unique index capability_entitlement_grants_one_live_uq
  on atlas.capability_entitlement_grants(ledger_id,ledger_entitlement_binding_id,capability_key,capability_version)
  where state='active';
create index capability_entitlement_grants_ledger_capability_idx
  on atlas.capability_entitlement_grants(ledger_id,capability_key,capability_version,state);
alter table atlas.capability_entitlement_grants enable row level security;
revoke all on atlas.capability_entitlement_grants from public,anon,authenticated;
create trigger capability_entitlement_grants_set_updated_at before update on atlas.capability_entitlement_grants
for each row execute function atlas.set_updated_at();
comment on table atlas.capability_entitlement_grants is 'Commercial mapping from an existing Ledger entitlement binding to a governed capability. Paid availability never confers activation authority.';

create or replace function atlas.capability_definition_active_v1(p_capability_key text,p_capability_version integer)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1 from atlas.capability_definitions d
    where d.capability_key=btrim(coalesce(p_capability_key,''))
      and d.capability_version=p_capability_version and d.status='active'
  );
$function$;
revoke all on function atlas.capability_definition_active_v1(text,integer) from public,anon,authenticated;
grant execute on function atlas.capability_definition_active_v1(text,integer) to service_role;

create or replace function atlas.capability_subject_valid_v1(
  p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text,p_subject_path text
)
returns boolean language plpgsql stable security definer set search_path=pg_catalog,atlas as $function$
declare v_key text:=btrim(coalesce(p_capability_key,'')); v_kind text:=btrim(coalesce(p_subject_kind,''));
begin
  if not exists(
    select 1 from atlas.capability_definitions d
    where d.capability_key=v_key and d.capability_version=p_capability_version
      and d.status='active' and v_kind=any(d.eligible_subject_kinds)
  ) then return false; end if;
  if v_key='teaching' and p_capability_version=1 then
    return v_kind='ledger' and p_subject_ledger_id is not null and p_subject_id=p_subject_ledger_id
      and p_subject_key is null and p_subject_path is null
      and exists(select 1 from atlas.ledgers l where l.id=p_subject_ledger_id and l.status='active');
  end if;
  return false;
end;
$function$;
revoke all on function atlas.capability_subject_valid_v1(text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.capability_subject_valid_v1(text,integer,uuid,text,uuid,text,text) to service_role;

create or replace function atlas.capability_activation_transition_allowed_v1(p_from_state text,p_to_state text)
returns boolean language sql immutable security definer set search_path=pg_catalog as $function$
  select coalesce((p_from_state,p_to_state) in (
    ('draft','active'),('draft','retired'),('active','paused'),('active','retired'),
    ('paused','active'),('paused','retired')
  ),false);
$function$;
revoke all on function atlas.capability_activation_transition_allowed_v1(text,text) from public,anon,authenticated;
grant execute on function atlas.capability_activation_transition_allowed_v1(text,text) to service_role;

create or replace function atlas.capability_root_authority_context_self_v1(p_ledger_id uuid)
returns table(person_id uuid,principal_id uuid,principal_ledger_authority_id uuid)
language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_person uuid; v_principal uuid; v_authority uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  v_person:=atlas.current_person_id_v1();
  v_principal:=atlas.current_principal_id_v1();
  if v_person is null or v_principal is null then raise exception 'Canonical Person and Principal required.' using errcode='42501'; end if;
  if not exists(select 1 from atlas.principals p where p.id=v_principal and p.person_id=v_person and p.status='active') then
    raise exception 'Principal / Person identity contradiction.' using errcode='23514';
  end if;
  select a.id into v_authority from atlas.principal_ledger_authorities a
  join atlas.ledgers l on l.id=a.ledger_id and l.status='active'
  where a.principal_id=v_principal and a.ledger_id=p_ledger_id and a.authority_kind='root_governing' and a.status='active'
  order by a.established_at,a.id limit 1;
  if v_authority is null or not atlas.principal_has_ledger_authority_v1(v_principal,p_ledger_id) then
    raise exception 'Root governing authority over Ledger required.' using errcode='42501';
  end if;
  return query select v_person,v_principal,v_authority;
end;
$function$;
revoke all on function atlas.capability_root_authority_context_self_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.capability_root_authority_context_self_v1(uuid) to authenticated;

create or replace function atlas.guard_capability_activation_event_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_activation atlas.capability_activations%rowtype; v_principal atlas.principals%rowtype; v_authority atlas.principal_ledger_authorities%rowtype;
begin
  select * into v_activation from atlas.capability_activations where id=new.capability_activation_id;
  select * into v_principal from atlas.principals where id=new.actor_principal_id;
  select * into v_authority from atlas.principal_ledger_authorities where id=new.principal_ledger_authority_id;
  if v_activation.id is null or v_activation.ledger_id<>new.ledger_id then raise exception 'Capability event Ledger contradiction.' using errcode='23514'; end if;
  if v_activation.state<>new.to_state then raise exception 'Capability event must describe current activation state.' using errcode='23514'; end if;
  if v_principal.id is null or v_principal.person_id is distinct from new.actor_person_id then raise exception 'Capability event Principal / Person contradiction.' using errcode='23514'; end if;
  if v_authority.id is null or v_authority.principal_id<>new.actor_principal_id or v_authority.ledger_id<>new.ledger_id
     or v_authority.authority_kind<>'root_governing' or v_authority.status<>'active' then
    raise exception 'Capability event requires the exact active root Ledger authority.' using errcode='23514';
  end if;
  return new;
end;
$function$;
revoke all on function atlas.guard_capability_activation_event_v1() from public,anon,authenticated;
create trigger capability_activation_events_guard_v1 before insert on atlas.capability_activation_events
for each row execute function atlas.guard_capability_activation_event_v1();

create or replace function atlas.reject_capability_activation_event_mutation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $function$
begin raise exception 'Capability activation events are append-only.' using errcode='55000'; end;
$function$;
revoke all on function atlas.reject_capability_activation_event_mutation_v1() from public,anon,authenticated;
create trigger capability_activation_events_immutable_v1 before update or delete on atlas.capability_activation_events
for each row execute function atlas.reject_capability_activation_event_mutation_v1();

create or replace function atlas.create_capability_activation_self_api_v1(
  p_ledger_id uuid,p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text default null,p_subject_path text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_person uuid; v_principal uuid; v_authority uuid; v_key text:=btrim(coalesce(p_capability_key,''));
  v_kind text:=btrim(coalesce(p_subject_kind,'')); v_existing atlas.capability_activations%rowtype; v_created atlas.capability_activations%rowtype;
begin
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  if not atlas.capability_definition_active_v1(v_key,p_capability_version) then raise exception 'Active governed capability definition required.' using errcode='23514'; end if;
  if not atlas.capability_subject_valid_v1(v_key,p_capability_version,p_subject_ledger_id,v_kind,p_subject_id,p_subject_key,p_subject_path) then
    raise exception 'Capability subject is invalid for this governed definition.' using errcode='23514';
  end if;
  select * into v_existing from atlas.capability_activations a
  where a.ledger_id=p_ledger_id and a.capability_key=v_key and a.capability_version=p_capability_version
    and a.subject_ledger_id=p_subject_ledger_id and a.subject_kind=v_kind
    and a.subject_id is not distinct from p_subject_id and a.subject_key is not distinct from p_subject_key
    and a.subject_path is not distinct from p_subject_path and a.state<>'retired' limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('contractVersion','capability_activation_create_self_v1','state','ready','alreadyExists',true,
      'activationId',v_existing.id,'activationState',v_existing.state,'ledgerId',v_existing.ledger_id);
  end if;
  insert into atlas.capability_activations(
    ledger_id,capability_key,capability_version,subject_ledger_id,subject_kind,subject_id,subject_key,subject_path,
    state,created_by_person_id,created_by_principal_id
  ) values (
    p_ledger_id,v_key,p_capability_version,p_subject_ledger_id,v_kind,p_subject_id,p_subject_key,p_subject_path,
    'draft',v_person,v_principal
  ) returning * into v_created;
  insert into atlas.capability_activation_events(
    capability_activation_id,ledger_id,actor_person_id,actor_principal_id,principal_ledger_authority_id,
    from_state,to_state,event_kind,basis
  ) values (v_created.id,p_ledger_id,v_person,v_principal,v_authority,null,'draft','created',jsonb_build_object('source','create_capability_activation_self_api_v1'));
  return jsonb_build_object('contractVersion','capability_activation_create_self_v1','state','ready','alreadyExists',false,
    'activationId',v_created.id,'activationState','draft','ledgerId',p_ledger_id);
end;
$function$;
revoke all on function atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.create_capability_activation_self_api_v1(uuid,text,integer,uuid,text,uuid,text,text) to authenticated;

create or replace function atlas.transition_capability_activation_self_api_v1(
  p_capability_activation_id uuid,p_to_state text,p_reason text default null
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $function$
declare
  v_activation atlas.capability_activations%rowtype; v_target text:=btrim(coalesce(p_to_state,''));
  v_person uuid; v_principal uuid; v_authority uuid; v_event text;
begin
  if p_capability_activation_id is null then raise exception 'Capability activation required.' using errcode='22023'; end if;
  select * into v_activation from atlas.capability_activations where id=p_capability_activation_id for update;
  if v_activation.id is null then raise exception 'Capability activation not found.' using errcode='P0002'; end if;
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(v_activation.ledger_id) c;
  if v_target=v_activation.state then
    return jsonb_build_object('contractVersion','capability_activation_transition_self_v1','state','ready','alreadyInState',true,
      'activationId',v_activation.id,'activationState',v_activation.state,'ledgerId',v_activation.ledger_id);
  end if;
  if not atlas.capability_activation_transition_allowed_v1(v_activation.state,v_target) then raise exception 'Illegal capability activation transition.' using errcode='23514'; end if;
  if v_target<>'retired' and not atlas.capability_subject_valid_v1(
      v_activation.capability_key,v_activation.capability_version,v_activation.subject_ledger_id,
      v_activation.subject_kind,v_activation.subject_id,v_activation.subject_key,v_activation.subject_path
    ) then raise exception 'Capability definition or subject is no longer valid for active behavior.' using errcode='23514'; end if;
  v_event:=case when v_activation.state='draft' and v_target='active' then 'activated'
    when v_activation.state='active' and v_target='paused' then 'paused'
    when v_activation.state='paused' and v_target='active' then 'resumed'
    when v_target='retired' then 'retired' else null end;
  if v_event is null then raise exception 'Unsupported capability transition event.' using errcode='23514'; end if;
  update atlas.capability_activations set state=v_target,retired_at=case when v_target='retired' then now() else null end where id=v_activation.id;
  insert into atlas.capability_activation_events(
    capability_activation_id,ledger_id,actor_person_id,actor_principal_id,principal_ledger_authority_id,
    from_state,to_state,event_kind,reason,basis
  ) values (
    v_activation.id,v_activation.ledger_id,v_person,v_principal,v_authority,v_activation.state,v_target,v_event,
    nullif(btrim(coalesce(p_reason,'')),''),jsonb_build_object('source','transition_capability_activation_self_api_v1')
  );
  return jsonb_build_object('contractVersion','capability_activation_transition_self_v1','state','ready','alreadyInState',false,
    'activationId',v_activation.id,'fromState',v_activation.state,'activationState',v_target,'ledgerId',v_activation.ledger_id,'eventKind',v_event);
end;
$function$;
revoke all on function atlas.transition_capability_activation_self_api_v1(uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.transition_capability_activation_self_api_v1(uuid,text,text) to authenticated;

create or replace function atlas.capability_activations_self_api_v1(p_ledger_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,atlas,auth as $function$
declare v_person uuid; v_principal uuid; v_authority uuid; v_items jsonb;
begin
  select c.person_id,c.principal_id,c.principal_ledger_authority_id into v_person,v_principal,v_authority
  from atlas.capability_root_authority_context_self_v1(p_ledger_id) c;
  select coalesce(jsonb_agg(jsonb_build_object(
    'activationId',a.id,'ledgerId',a.ledger_id,'capabilityKey',a.capability_key,'capabilityVersion',a.capability_version,
    'activationState',a.state,'subjectLedgerId',a.subject_ledger_id,'subjectKind',a.subject_kind,'subjectId',a.subject_id,
    'subjectKey',a.subject_key,'subjectPath',a.subject_path,'createdAt',a.created_at,'retiredAt',a.retired_at
  ) order by a.created_at,a.id),'[]'::jsonb) into v_items
  from atlas.capability_activations a where a.ledger_id=p_ledger_id;
  return jsonb_build_object('contractVersion','capability_activations_self_v1','state','ready','ledgerId',p_ledger_id,'principalId',v_principal,'items',v_items);
end;
$function$;
revoke all on function atlas.capability_activations_self_api_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.capability_activations_self_api_v1(uuid) to authenticated;

create or replace function atlas.capability_active_for_subject_v1(
  p_ledger_id uuid,p_capability_key text,p_capability_version integer,p_subject_ledger_id uuid,
  p_subject_kind text,p_subject_id uuid,p_subject_key text,p_subject_path text
)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1 from atlas.capability_activations a
    join atlas.capability_definitions d on d.capability_key=a.capability_key and d.capability_version=a.capability_version
    join atlas.ledgers gl on gl.id=a.ledger_id and gl.status='active'
    join atlas.ledgers sl on sl.id=a.subject_ledger_id and sl.status='active'
    where a.ledger_id=p_ledger_id and a.capability_key=btrim(coalesce(p_capability_key,'')) and a.capability_version=p_capability_version
      and a.subject_ledger_id=p_subject_ledger_id and a.subject_kind=btrim(coalesce(p_subject_kind,''))
      and a.subject_id is not distinct from p_subject_id and a.subject_key is not distinct from p_subject_key
      and a.subject_path is not distinct from p_subject_path and a.state='active' and d.status='active'
  );
$function$;
revoke all on function atlas.capability_active_for_subject_v1(uuid,text,integer,uuid,text,uuid,text,text) from public,anon,authenticated;
grant execute on function atlas.capability_active_for_subject_v1(uuid,text,integer,uuid,text,uuid,text,text) to service_role;

create or replace function atlas.establish_capability_entitlement_grant_serv_v1(
  p_ledger_id uuid,p_ledger_entitlement_binding_id uuid,p_capability_key text,p_capability_version integer,p_basis jsonb
)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_key text:=btrim(coalesce(p_capability_key,'')); v_binding atlas.ledger_entitlement_bindings%rowtype;
  v_existing atlas.capability_entitlement_grants%rowtype; v_created atlas.capability_entitlement_grants%rowtype;
begin
  if p_ledger_id is null or p_ledger_entitlement_binding_id is null then raise exception 'Ledger and entitlement binding are required.' using errcode='22023'; end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' then raise exception 'Capability entitlement basis must be an object.' using errcode='22023'; end if;
  if not atlas.capability_definition_active_v1(v_key,p_capability_version) then raise exception 'Active governed capability definition required.' using errcode='23514'; end if;
  select * into v_binding from atlas.ledger_entitlement_bindings where id=p_ledger_entitlement_binding_id for key share;
  if v_binding.id is null or v_binding.ledger_id<>p_ledger_id or v_binding.state='ended' then
    raise exception 'Live entitlement binding for the same Ledger required.' using errcode='23514';
  end if;
  select * into v_existing from atlas.capability_entitlement_grants g
  where g.ledger_id=p_ledger_id and g.ledger_entitlement_binding_id=p_ledger_entitlement_binding_id
    and g.capability_key=v_key and g.capability_version=p_capability_version and g.state='active' limit 1;
  if v_existing.id is not null then
    return jsonb_build_object('ok',true,'alreadyEstablished',true,'grantId',v_existing.id,'ledgerId',v_existing.ledger_id,
      'capabilityKey',v_existing.capability_key,'capabilityVersion',v_existing.capability_version,'grantState',v_existing.state);
  end if;
  insert into atlas.capability_entitlement_grants(ledger_id,ledger_entitlement_binding_id,capability_key,capability_version,state,basis)
  values(p_ledger_id,p_ledger_entitlement_binding_id,v_key,p_capability_version,'active',p_basis) returning * into v_created;
  return jsonb_build_object('ok',true,'alreadyEstablished',false,'grantId',v_created.id,'ledgerId',v_created.ledger_id,
    'capabilityKey',v_created.capability_key,'capabilityVersion',v_created.capability_version,'grantState',v_created.state);
end;
$function$;
revoke all on function atlas.establish_capability_entitlement_grant_serv_v1(uuid,uuid,text,integer,jsonb) from public,anon,authenticated;
grant execute on function atlas.establish_capability_entitlement_grant_serv_v1(uuid,uuid,text,integer,jsonb) to service_role;

create or replace function atlas.end_capability_entitlement_grant_serv_v1(p_grant_id uuid,p_basis jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $function$
declare v_grant atlas.capability_entitlement_grants%rowtype;
begin
  if p_grant_id is null then raise exception 'Capability entitlement grant required.' using errcode='22023'; end if;
  if p_basis is null or jsonb_typeof(p_basis)<>'object' then raise exception 'Capability entitlement end basis must be an object.' using errcode='22023'; end if;
  select * into v_grant from atlas.capability_entitlement_grants where id=p_grant_id for update;
  if v_grant.id is null then raise exception 'Capability entitlement grant not found.' using errcode='P0002'; end if;
  if v_grant.state='ended' then return jsonb_build_object('ok',true,'alreadyEnded',true,'grantId',v_grant.id,'grantState','ended'); end if;
  update atlas.capability_entitlement_grants g set state='ended',ended_at=now(),basis=g.basis||jsonb_build_object('endBasis',p_basis) where g.id=v_grant.id;
  return jsonb_build_object('ok',true,'alreadyEnded',false,'grantId',v_grant.id,'ledgerId',v_grant.ledger_id,
    'capabilityKey',v_grant.capability_key,'capabilityVersion',v_grant.capability_version,'grantState','ended');
end;
$function$;
revoke all on function atlas.end_capability_entitlement_grant_serv_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function atlas.end_capability_entitlement_grant_serv_v1(uuid,jsonb) to service_role;

create or replace function atlas.capability_entitlement_grant_live_v1(p_ledger_id uuid,p_capability_key text,p_capability_version integer)
returns boolean language sql stable security definer set search_path=pg_catalog,atlas as $function$
  select exists(
    select 1 from atlas.capability_entitlement_grants g
    join atlas.ledger_entitlement_bindings b on b.id=g.ledger_entitlement_binding_id and b.ledger_id=g.ledger_id
    join atlas.capability_definitions d on d.capability_key=g.capability_key and d.capability_version=g.capability_version
    where g.ledger_id=p_ledger_id and g.capability_key=btrim(coalesce(p_capability_key,'')) and g.capability_version=p_capability_version
      and g.state='active' and g.ended_at is null and b.state<>'ended' and d.status='active'
  );
$function$;
revoke all on function atlas.capability_entitlement_grant_live_v1(uuid,text,integer) from public,anon,authenticated;
grant execute on function atlas.capability_entitlement_grant_live_v1(uuid,text,integer) to service_role;

commit;
