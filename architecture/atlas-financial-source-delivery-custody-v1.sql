-- Atlas Financial Source Delivery Custody v1 — executable architecture source.
--
-- Provider deliveries/webhooks are transport evidence, not canonical financial
-- truth. They are deduplicated independently from provider objects because a
-- provider can legitimately send multiple events about one changing object.

create table atlas.financial_source_delivery_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  connected_source_id uuid not null references atlas.connected_sources(id) on delete restrict,
  provider_event_id text not null check (btrim(provider_event_id) <> ''),
  provider_event_kind text not null check (btrim(provider_event_kind) <> ''),
  payload_sha256 text not null check (btrim(payload_sha256) <> ''),
  provider_created_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  constraint financial_source_delivery_event_uq unique(connected_source_id,provider_event_id),
  check (jsonb_typeof(metadata)='object')
);

comment on table atlas.financial_source_delivery_events is
  'Immutable provider delivery identity/replay evidence. Recording a delivery does not establish any economic event by itself.';

create index financial_source_delivery_received_idx
  on atlas.financial_source_delivery_events(organization_id,received_at desc,id desc);

create table atlas.financial_source_delivery_processing_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  delivery_event_id uuid not null references atlas.financial_source_delivery_events(id) on delete restrict,
  processing_kind text not null check (processing_kind in ('succeeded','failed','ignored')),
  processor_contract text not null check (btrim(processor_contract) <> ''),
  detail jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default now(),
  check (jsonb_typeof(detail)='object')
);

comment on table atlas.financial_source_delivery_processing_events is
  'Append-only processing outcomes for provider delivery evidence. A failed delivery remains retryable; idempotent observation/event commands make concurrent retries safe.';

create index financial_source_delivery_processing_idx
  on atlas.financial_source_delivery_processing_events(delivery_event_id,processed_at desc,id desc);

create trigger financial_source_delivery_events_append_only_v1
before update or delete on atlas.financial_source_delivery_events
for each row execute function atlas.reject_financial_history_mutation_v1();
create trigger financial_source_delivery_processing_events_append_only_v1
before update or delete on atlas.financial_source_delivery_processing_events
for each row execute function atlas.reject_financial_history_mutation_v1();

create or replace function atlas.guard_financial_source_delivery_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source_org uuid;
begin
  select s.custodian_organization_id into v_source_org
  from atlas.connected_sources s
  where s.id=new.connected_source_id
    and s.custodian_user_id is null;
  if v_source_org is null or v_source_org is distinct from new.organization_id then
    raise exception 'Financial provider delivery is outside organization source custody.' using errcode='42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_source_delivery_custody_v1()
  from public,anon,authenticated,service_role;

create trigger financial_source_delivery_custody_guard_v1
before insert on atlas.financial_source_delivery_events
for each row execute function atlas.guard_financial_source_delivery_custody_v1();

create or replace function atlas.guard_financial_source_delivery_processing_custody_v1()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_delivery_org uuid;
begin
  select d.organization_id into v_delivery_org
  from atlas.financial_source_delivery_events d where d.id=new.delivery_event_id;
  if v_delivery_org is null or v_delivery_org is distinct from new.organization_id then
    raise exception 'Financial delivery processing event crosses organization custody.' using errcode='42501';
  end if;
  return new;
end;
$function$;

revoke all on function atlas.guard_financial_source_delivery_processing_custody_v1()
  from public,anon,authenticated,service_role;

create trigger financial_source_delivery_processing_custody_guard_v1
before insert on atlas.financial_source_delivery_processing_events
for each row execute function atlas.guard_financial_source_delivery_processing_custody_v1();

create or replace function atlas.record_financial_source_delivery_core_v1(
  p_connected_source_id uuid,
  p_provider_event_id text,
  p_provider_event_kind text,
  p_payload_sha256 text,
  p_provider_created_at timestamptz,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_source atlas.connected_sources%rowtype;
  v_existing atlas.financial_source_delivery_events%rowtype;
  v_row atlas.financial_source_delivery_events%rowtype;
begin
  if p_connected_source_id is null
     or nullif(btrim(coalesce(p_provider_event_id,'')),'') is null
     or nullif(btrim(coalesce(p_provider_event_kind,'')),'') is null
     or nullif(btrim(coalesce(p_payload_sha256,'')),'') is null then
    raise exception 'Financial provider delivery requires source, provider event identity/kind, and payload hash.' using errcode='22023';
  end if;
  select * into v_source
  from atlas.connected_sources s
  where s.id=p_connected_source_id
    and s.custodian_organization_id is not null
    and s.custodian_user_id is null;
  if v_source.id is null then
    raise exception 'Organization-owned financial connected source not found.' using errcode='P0002';
  end if;

  select * into v_existing
  from atlas.financial_source_delivery_events d
  where d.connected_source_id=v_source.id
    and d.provider_event_id=btrim(p_provider_event_id);
  if v_existing.id is not null then
    if v_existing.provider_event_kind is distinct from btrim(p_provider_event_kind)
       or v_existing.payload_sha256 is distinct from btrim(p_payload_sha256) then
      raise exception 'Provider event id replayed with contradictory event kind or payload.' using errcode='55000';
    end if;
    return jsonb_build_object(
      'contractVersion','record_financial_source_delivery_core_v1',
      'state','duplicate','deliveryEventId',v_existing.id,
      'alreadySucceeded',exists(
        select 1 from atlas.financial_source_delivery_processing_events p
        where p.delivery_event_id=v_existing.id and p.processing_kind='succeeded'
      )
    );
  end if;

  begin
    insert into atlas.financial_source_delivery_events(
      organization_id,connected_source_id,provider_event_id,provider_event_kind,
      payload_sha256,provider_created_at,metadata
    ) values (
      v_source.custodian_organization_id,v_source.id,btrim(p_provider_event_id),
      btrim(p_provider_event_kind),btrim(p_payload_sha256),p_provider_created_at,
      coalesce(p_metadata,'{}'::jsonb)
    ) returning * into v_row;
  exception when unique_violation then
    select * into v_row
    from atlas.financial_source_delivery_events d
    where d.connected_source_id=v_source.id
      and d.provider_event_id=btrim(p_provider_event_id);
  end;

  return jsonb_build_object(
    'contractVersion','record_financial_source_delivery_core_v1',
    'state','recorded','deliveryEventId',v_row.id,'alreadySucceeded',false
  );
end;
$function$;

create or replace function atlas.record_financial_source_delivery_processing_core_v1(
  p_delivery_event_id uuid,
  p_processing_kind text,
  p_processor_contract text,
  p_detail jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_delivery atlas.financial_source_delivery_events%rowtype;
  v_row atlas.financial_source_delivery_processing_events%rowtype;
begin
  if p_delivery_event_id is null
     or p_processing_kind not in ('succeeded','failed','ignored')
     or nullif(btrim(coalesce(p_processor_contract,'')),'') is null then
    raise exception 'Financial delivery processing outcome requires delivery, supported outcome, and processor contract.' using errcode='22023';
  end if;
  select * into v_delivery from atlas.financial_source_delivery_events where id=p_delivery_event_id;
  if v_delivery.id is null then raise exception 'Financial provider delivery not found.' using errcode='P0002'; end if;

  insert into atlas.financial_source_delivery_processing_events(
    organization_id,delivery_event_id,processing_kind,processor_contract,detail
  ) values (
    v_delivery.organization_id,v_delivery.id,p_processing_kind,btrim(p_processor_contract),coalesce(p_detail,'{}'::jsonb)
  ) returning * into v_row;

  return jsonb_build_object(
    'contractVersion','record_financial_source_delivery_processing_core_v1',
    'processingEventId',v_row.id,'processingKind',v_row.processing_kind
  );
end;
$function$;

alter table atlas.financial_source_delivery_events enable row level security;
alter table atlas.financial_source_delivery_processing_events enable row level security;
revoke all on atlas.financial_source_delivery_events from public,anon,authenticated,service_role;
revoke all on atlas.financial_source_delivery_processing_events from public,anon,authenticated,service_role;
grant select,insert on atlas.financial_source_delivery_events to service_role;
grant select,insert on atlas.financial_source_delivery_processing_events to service_role;

revoke all on function atlas.record_financial_source_delivery_core_v1(uuid,text,text,text,timestamptz,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_financial_source_delivery_core_v1(uuid,text,text,text,timestamptz,jsonb)
  to service_role;
revoke all on function atlas.record_financial_source_delivery_processing_core_v1(uuid,text,text,jsonb)
  from public,anon,authenticated;
grant execute on function atlas.record_financial_source_delivery_processing_core_v1(uuid,text,text,jsonb)
  to service_role;
