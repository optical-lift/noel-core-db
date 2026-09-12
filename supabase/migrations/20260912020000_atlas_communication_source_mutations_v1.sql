begin;

create table atlas.communication_event_source_mutations (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid references atlas.principals(id) on delete cascade,
  organization_id uuid references atlas.organizations(id) on delete cascade,
  organization_unit_id uuid,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  event_id uuid not null references atlas.communication_events(id) on delete restrict,
  source_event_ref text not null check (btrim(source_event_ref)<>''),
  provider_mutation_ref text,
  mutation_kind text not null check (mutation_kind in ('edited','deleted','unsent')),
  provider_occurred_at timestamptz,
  observed_at timestamptz not null default now(),
  mutation_evidence_sha256 text not null check (mutation_evidence_sha256 ~ '^[0-9a-f]{64}$'),
  observed_state jsonb not null check (jsonb_typeof(observed_state)='object'),
  source_authority text not null default 'evidence_only' check (source_authority='evidence_only'),
  governing_state_changed boolean not null default false check (governing_state_changed=false),
  created_at timestamptz not null default now(),
  check (((principal_id is not null)::int + (organization_id is not null)::int)=1),
  constraint communication_event_source_mutations_unit_org_fk
    foreign key (organization_id,organization_unit_id)
    references atlas.organization_units(organization_id,id) on delete restrict,
  unique(event_id,mutation_kind,mutation_evidence_sha256)
);

create index communication_event_source_mutations_provider_ref_idx
  on atlas.communication_event_source_mutations(connected_source_id,provider_mutation_ref,observed_at,id)
  where provider_mutation_ref is not null;
create index communication_event_source_mutations_event_idx
  on atlas.communication_event_source_mutations(event_id,coalesce(provider_occurred_at,observed_at),id);
create index communication_event_source_mutations_org_idx
  on atlas.communication_event_source_mutations(organization_id,organization_unit_id,observed_at desc,id)
  where organization_id is not null;
create index communication_event_source_mutations_principal_idx
  on atlas.communication_event_source_mutations(principal_id,observed_at desc,id)
  where principal_id is not null;

revoke all on table atlas.communication_event_source_mutations from public,anon,authenticated;
alter table atlas.communication_event_source_mutations enable row level security;

comment on table atlas.communication_event_source_mutations is
  'Append-only provider-attributed evidence that a previously admitted communication event was later reported edited, deleted, or unsent. The original communication event remains immutable; mutation evidence does not itself create response responsibility or rewrite institutional history.';

create or replace function atlas.guard_communication_event_source_mutation_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare v_event atlas.communication_events%rowtype;
begin
  select * into v_event from atlas.communication_events where id=new.event_id;
  if v_event.id is null
     or v_event.principal_id is distinct from new.principal_id
     or v_event.organization_id is distinct from new.organization_id
     or v_event.organization_unit_id is distinct from new.organization_unit_id
     or v_event.connected_source_id is distinct from new.connected_source_id
     or v_event.source_event_ref is distinct from new.source_event_ref then
    raise exception 'Communication source mutation does not match its immutable parent event.' using errcode='42501';
  end if;
  return new;
end;
$function$;

create trigger communication_event_source_mutation_parent_guard
before insert on atlas.communication_event_source_mutations
for each row execute function atlas.guard_communication_event_source_mutation_v1();

create or replace function atlas.reject_communication_event_source_mutation_history_change_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
begin
  raise exception 'Communication source mutation history is append-only.' using errcode='55000';
end;
$function$;

create trigger communication_event_source_mutation_history_immutable
before update or delete on atlas.communication_event_source_mutations
for each row execute function atlas.reject_communication_event_source_mutation_history_change_v1();

create or replace function atlas.record_communication_event_source_mutation_service_v1(
  p_connected_source_id uuid,
  p_source_event_ref text,
  p_mutation_kind text,
  p_observed_state jsonb,
  p_provider_mutation_ref text default null,
  p_provider_occurred_at timestamptz default null,
  p_observed_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,extensions
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_event atlas.communication_events%rowtype;
  v_ref text:=btrim(coalesce(p_source_event_ref,''));
  v_kind text:=lower(btrim(coalesce(p_mutation_kind,'')));
  v_provider_mutation_ref text:=nullif(btrim(coalesce(p_provider_mutation_ref,'')),'');
  v_observed_at timestamptz:=coalesce(p_observed_at,now());
  v_hash text;
  v_mutation atlas.communication_event_source_mutations%rowtype;
begin
  select * into v_source
  from atlas.connected_sources
  where id=p_connected_source_id and authorization_state='connected';
  if v_source.id is null then raise exception 'Connected communication source is required.' using errcode='42501'; end if;
  if not (v_source.capabilities @> '{"communicationCapture":true}'::jsonb) then
    raise exception 'Connected source is not authorized for communication capture.' using errcode='42501';
  end if;
  if v_ref='' then raise exception 'Original source event reference is required.' using errcode='22023'; end if;
  if v_kind not in ('edited','deleted','unsent') then raise exception 'Unsupported communication source mutation kind.' using errcode='22023'; end if;
  if p_observed_state is null or jsonb_typeof(p_observed_state)<>'object' then
    raise exception 'Mutation observed state must be a JSON object.' using errcode='22023';
  end if;
  if lower(p_observed_state::text) ~ '"(access_token|refresh_token|authorization_code|client_secret|api_key|secret_key|webhook_secret)"[[:space:]]*:' then
    raise exception 'Provider secrets are not allowed in mutation evidence.' using errcode='22023';
  end if;

  select * into v_event
  from atlas.communication_events
  where connected_source_id=v_source.id and source_event_ref=v_ref;
  if v_event.id is null then
    raise exception 'Original communication event is not in Atlas custody.' using errcode='P0002';
  end if;

  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object(
    'sourceEventRef',v_ref,
    'mutationKind',v_kind,
    'providerMutationRef',v_provider_mutation_ref,
    'providerOccurredAt',p_provider_occurred_at,
    'observedState',p_observed_state
  )::text,'UTF8'),'sha256'),'hex');

  select * into v_mutation
  from atlas.communication_event_source_mutations
  where event_id=v_event.id and mutation_kind=v_kind and mutation_evidence_sha256=v_hash;
  if v_mutation.id is not null then
    return jsonb_build_object(
      'contractVersion','communication_event_source_mutation_v1',
      'sourceMutationId',v_mutation.id,
      'communicationEventId',v_event.id,
      'mutationKind',v_mutation.mutation_kind,
      'alreadyRecorded',true,
      'originalEventRewritten',false,
      'responseWorkCreated',false,
      'governingStateChanged',false
    );
  end if;

  insert into atlas.communication_event_source_mutations(
    principal_id,organization_id,organization_unit_id,connected_source_id,event_id,
    source_event_ref,provider_mutation_ref,mutation_kind,provider_occurred_at,observed_at,
    mutation_evidence_sha256,observed_state
  ) values (
    v_event.principal_id,v_event.organization_id,v_event.organization_unit_id,v_source.id,v_event.id,
    v_ref,v_provider_mutation_ref,v_kind,p_provider_occurred_at,v_observed_at,
    v_hash,p_observed_state
  )
  returning * into v_mutation;

  return jsonb_build_object(
    'contractVersion','communication_event_source_mutation_v1',
    'sourceMutationId',v_mutation.id,
    'communicationEventId',v_event.id,
    'mutationKind',v_mutation.mutation_kind,
    'providerOccurredAt',v_mutation.provider_occurred_at,
    'observedAt',v_mutation.observed_at,
    'alreadyRecorded',false,
    'originalEventRewritten',false,
    'responseWorkCreated',false,
    'governingStateChanged',false
  );
end;
$function$;
revoke all on function atlas.record_communication_event_source_mutation_service_v1(uuid,text,text,jsonb,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function atlas.record_communication_event_source_mutation_service_v1(uuid,text,text,jsonb,text,timestamptz,timestamptz) to service_role;

create or replace function public.record_communication_event_source_mutation_service_v1(
  p_connected_source_id uuid,
  p_source_event_ref text,
  p_mutation_kind text,
  p_observed_state jsonb,
  p_provider_mutation_ref text default null,
  p_provider_occurred_at timestamptz default null,
  p_observed_at timestamptz default null
) returns jsonb
language sql
security definer
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.record_communication_event_source_mutation_service_v1(
    p_connected_source_id,p_source_event_ref,p_mutation_kind,p_observed_state,
    p_provider_mutation_ref,p_provider_occurred_at,p_observed_at
  );
$function$;
revoke all on function public.record_communication_event_source_mutation_service_v1(uuid,text,text,jsonb,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function public.record_communication_event_source_mutation_service_v1(uuid,text,text,jsonb,text,timestamptz,timestamptz) to service_role;

commit;
