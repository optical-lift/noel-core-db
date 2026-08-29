create table if not exists atlas.operational_routes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  stable_key text not null,
  route_date date not null,
  route_label text not null,
  route_kind text not null,
  state text not null default 'planned',
  assigned_organization_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  external_custodian_label text,
  source_authority text not null default 'atlas',
  source_system_key text,
  source_record_key text,
  source_observed_at timestamptz,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_routes_stable_key_unique unique (organization_id, stable_key),
  constraint operational_routes_idempotency_unique unique (organization_id, idempotency_key),
  constraint operational_routes_kind_check check (route_kind in ('delivery','pickup','service','mixed','handoff')),
  constraint operational_routes_state_check check (state in ('planned','active','completed','cancelled')),
  constraint operational_routes_assignment_check check (((assigned_organization_membership_id is not null)::int + (nullif(btrim(external_custodian_label),'') is not null)::int) <= 1),
  constraint operational_routes_source_authority_check check (source_authority in ('atlas','external')),
  constraint operational_routes_external_source_check check (source_authority <> 'external' or (nullif(btrim(source_system_key),'') is not null and nullif(btrim(source_record_key),'') is not null))
);

create index if not exists operational_routes_org_date_idx on atlas.operational_routes(organization_id, route_date, state);
create index if not exists operational_routes_assignee_idx on atlas.operational_routes(assigned_organization_membership_id, route_date, state) where assigned_organization_membership_id is not null;

create table if not exists atlas.operational_route_stops (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  operational_route_id uuid not null references atlas.operational_routes(id) on delete cascade,
  stable_key text not null,
  sequence_number integer not null,
  stop_kind text not null,
  state text not null default 'planned',
  destination_label text not null,
  address_text text,
  contact_name text,
  contact_detail text,
  service_window_start timestamptz,
  service_window_end timestamptz,
  assigned_organization_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  source_authority text not null default 'atlas',
  source_system_key text,
  source_record_key text,
  source_observed_at timestamptz,
  worker_instruction text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint operational_route_stops_route_key_unique unique (operational_route_id, stable_key),
  constraint operational_route_stops_route_sequence_unique unique (operational_route_id, sequence_number),
  constraint operational_route_stops_sequence_positive check (sequence_number > 0),
  constraint operational_route_stops_kind_check check (stop_kind in ('product_delivery','product_pickup','service_visit','handoff','mixed')),
  constraint operational_route_stops_state_check check (state in ('planned','ready','en_route','arrived','completed','failed','cancelled')),
  constraint operational_route_stops_window_check check (service_window_end is null or service_window_start is null or service_window_end >= service_window_start),
  constraint operational_route_stops_source_authority_check check (source_authority in ('atlas','external')),
  constraint operational_route_stops_external_source_check check (source_authority <> 'external' or (nullif(btrim(source_system_key),'') is not null and nullif(btrim(source_record_key),'') is not null))
);

create index if not exists operational_route_stops_org_route_idx on atlas.operational_route_stops(organization_id, operational_route_id, sequence_number);
create index if not exists operational_route_stops_assignee_idx on atlas.operational_route_stops(assigned_organization_membership_id, state) where assigned_organization_membership_id is not null;

create table if not exists atlas.operational_route_bindings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  operational_route_stop_id uuid not null references atlas.operational_route_stops(id) on delete cascade,
  stable_key text not null,
  obligation_kind text not null,
  domain_key text not null,
  source_record_id uuid,
  source_record_key text,
  quantity numeric,
  unit text,
  worker_description text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint operational_route_bindings_stop_key_unique unique (operational_route_stop_id, stable_key),
  constraint operational_route_bindings_quantity_positive check (quantity is null or quantity > 0),
  constraint operational_route_bindings_obligation_kind_check check (obligation_kind in ('product','service','handoff','mixed'))
);

create index if not exists operational_route_bindings_org_stop_idx on atlas.operational_route_bindings(organization_id, operational_route_stop_id);

create table if not exists atlas.operational_route_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  operational_route_id uuid not null references atlas.operational_routes(id) on delete cascade,
  operational_route_stop_id uuid references atlas.operational_route_stops(id) on delete cascade,
  event_kind text not null,
  occurred_at timestamptz not null default now(),
  recorded_by_organization_membership_id uuid references atlas.organization_memberships(id) on delete set null,
  note text,
  idempotency_key text not null,
  source_authority text not null default 'atlas',
  source_system_key text,
  source_record_key text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint operational_route_events_idempotency_unique unique (organization_id, idempotency_key),
  constraint operational_route_events_kind_check check (event_kind in ('loaded','departed','arrived','handoff_complete','service_complete','failed','returned','cancelled','note')),
  constraint operational_route_events_source_authority_check check (source_authority in ('atlas','external'))
);

create index if not exists operational_route_events_route_time_idx on atlas.operational_route_events(operational_route_id, occurred_at);
create index if not exists operational_route_events_stop_time_idx on atlas.operational_route_events(operational_route_stop_id, occurred_at) where operational_route_stop_id is not null;

comment on table atlas.operational_routes is 'Organization-scoped platform route/run truth. Domain modules bind their obligations into routes without moving commercial, inventory, or service authority into this table.';
comment on table atlas.operational_route_stops is 'Worker-executable route stops for product delivery/pickup, service visits, handoffs, or mixed obligations. Worker visibility is assignment-scoped.';
comment on table atlas.operational_route_bindings is 'References from a route stop to domain-owned product, service, or handoff obligations. payload is extension metadata; worker_description is the governed worker-safe projection.';
comment on table atlas.operational_route_events is 'Append-only route execution facts. Events do not by themselves create domain sale, inventory, or service-completion truth unless a domain adapter explicitly does so.';

alter table atlas.operational_routes enable row level security;
alter table atlas.operational_route_stops enable row level security;
alter table atlas.operational_route_bindings enable row level security;
alter table atlas.operational_route_events enable row level security;
revoke all on atlas.operational_routes from anon, authenticated;
revoke all on atlas.operational_route_stops from anon, authenticated;
revoke all on atlas.operational_route_bindings from anon, authenticated;
revoke all on atlas.operational_route_events from anon, authenticated;
grant select,insert,update,delete on atlas.operational_routes to service_role;
grant select,insert,update,delete on atlas.operational_route_stops to service_role;
grant select,insert,update,delete on atlas.operational_route_bindings to service_role;
grant select,insert,update,delete on atlas.operational_route_events to service_role;

create or replace function atlas.current_organization_membership_v1(p_organization_id uuid)
returns uuid language sql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
  select om.id from atlas.organization_memberships om
  where om.organization_id=p_organization_id and om.user_id=auth.uid() and om.active
  order by case om.role when 'owner' then 1 when 'consultant' then 2 else 3 end, om.created_at limit 1;
$function$;

create or replace function atlas.require_operational_route_owner_v1(p_organization_id uuid)
returns uuid language plpgsql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_membership atlas.organization_memberships%rowtype;
begin
  select * into v_membership from atlas.organization_memberships
  where organization_id=p_organization_id and user_id=auth.uid() and active
  order by case role when 'owner' then 1 when 'consultant' then 2 else 3 end, created_at limit 1;
  if v_membership.id is null or v_membership.role not in ('owner','consultant') then
    raise exception 'Organization route management requires Owner or Consultant authority.' using errcode='42501';
  end if;
  return v_membership.id;
end;
$function$;

create or replace function atlas.resolve_route_org_membership_from_farm_membership_v1(p_organization_id uuid,p_farm_membership_id uuid)
returns uuid language sql stable security definer set search_path to 'pg_catalog','atlas' as $function$
  select om.id from atlas.farm_memberships fm join atlas.farms f on f.id=fm.farm_id
  join atlas.organization_memberships om on om.organization_id=f.organization_id and om.user_id=fm.user_id and om.active
  where fm.id=p_farm_membership_id and fm.active and f.organization_id=p_organization_id limit 1;
$function$;

create or replace function atlas.record_operational_route_v1(
  p_organization_id uuid,p_stable_key text,p_route_date date,p_route_label text,p_route_kind text,
  p_assigned_organization_membership_id uuid,p_external_custodian_label text,
  p_source_authority text,p_source_system_key text,p_source_record_key text,p_source_observed_at timestamptz,
  p_stops jsonb,p_metadata jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare
  v_actor uuid; v_route atlas.operational_routes%rowtype; v_stop jsonb; v_stop_row atlas.operational_route_stops%rowtype;
  v_binding jsonb; v_sequence integer; v_stop_assignee uuid; v_count integer:=0;
begin
  v_actor:=atlas.require_operational_route_owner_v1(p_organization_id);
  if nullif(btrim(p_stable_key),'') is null or nullif(btrim(p_route_label),'') is null then raise exception 'Route key and label are required.' using errcode='22023'; end if;
  if p_route_date is null then raise exception 'Route date is required.' using errcode='22023'; end if;
  if p_route_kind not in ('delivery','pickup','service','mixed','handoff') then raise exception 'Route kind is invalid.' using errcode='22023'; end if;
  if p_source_authority not in ('atlas','external') then raise exception 'Source authority is invalid.' using errcode='22023'; end if;
  if p_source_authority='external' and (nullif(btrim(p_source_system_key),'') is null or nullif(btrim(p_source_record_key),'') is null) then raise exception 'External route truth requires source system and source record identity.' using errcode='23514'; end if;
  if p_assigned_organization_membership_id is not null and nullif(btrim(p_external_custodian_label),'') is not null then raise exception 'Choose an internal assignee or an external custodian, not both.' using errcode='23514'; end if;
  if p_assigned_organization_membership_id is not null and not exists (select 1 from atlas.organization_memberships where id=p_assigned_organization_membership_id and organization_id=p_organization_id and active) then raise exception 'Route assignee is not active in this organization.' using errcode='23514'; end if;
  if p_stops is null or jsonb_typeof(p_stops)<>'array' or jsonb_array_length(p_stops)=0 or jsonb_array_length(p_stops)>100 then raise exception 'A route requires 1 to 100 stops.' using errcode='22023'; end if;
  if nullif(btrim(p_idempotency_key),'') is null then raise exception 'An idempotency key is required.' using errcode='22023'; end if;
  select * into v_route from atlas.operational_routes where organization_id=p_organization_id and idempotency_key=p_idempotency_key;
  if v_route.id is not null then return jsonb_build_object('contractVersion','operational_route_v1','routeId',v_route.id,'idempotentReplay',true); end if;

  insert into atlas.operational_routes(organization_id,stable_key,route_date,route_label,route_kind,state,assigned_organization_membership_id,external_custodian_label,source_authority,source_system_key,source_record_key,source_observed_at,idempotency_key,metadata,created_by_user_id)
  values(p_organization_id,btrim(p_stable_key),p_route_date,btrim(p_route_label),p_route_kind,'planned',p_assigned_organization_membership_id,nullif(btrim(p_external_custodian_label),''),p_source_authority,nullif(btrim(p_source_system_key),''),nullif(btrim(p_source_record_key),''),p_source_observed_at,p_idempotency_key,coalesce(p_metadata,'{}'::jsonb),auth.uid()) returning * into v_route;

  for v_stop in select value from jsonb_array_elements(p_stops) loop
    v_sequence:=coalesce(nullif(v_stop->>'sequence','')::integer,v_count+1);
    v_stop_assignee:=nullif(v_stop->>'assignedOrganizationMembershipId','')::uuid;
    if v_stop_assignee is not null and not exists(select 1 from atlas.organization_memberships where id=v_stop_assignee and organization_id=p_organization_id and active) then raise exception 'Stop assignee is not active in this organization.' using errcode='23514'; end if;
    insert into atlas.operational_route_stops(organization_id,operational_route_id,stable_key,sequence_number,stop_kind,state,destination_label,address_text,contact_name,contact_detail,service_window_start,service_window_end,assigned_organization_membership_id,source_authority,source_system_key,source_record_key,source_observed_at,worker_instruction,metadata)
    values(p_organization_id,v_route.id,coalesce(nullif(btrim(v_stop->>'stableKey'),''),'stop-'||v_sequence::text),v_sequence,coalesce(nullif(v_stop->>'stopKind',''),'handoff'),'planned',coalesce(nullif(btrim(v_stop->>'destinationLabel'),''),'Route stop '||v_sequence::text),nullif(btrim(v_stop->>'addressText'),''),nullif(btrim(v_stop->>'contactName'),''),nullif(btrim(v_stop->>'contactDetail'),''),nullif(v_stop->>'windowStart','')::timestamptz,nullif(v_stop->>'windowEnd','')::timestamptz,v_stop_assignee,coalesce(nullif(v_stop->>'sourceAuthority',''),p_source_authority),coalesce(nullif(v_stop->>'sourceSystemKey',''),nullif(btrim(p_source_system_key),'')),coalesce(nullif(v_stop->>'sourceRecordKey',''),nullif(btrim(p_source_record_key),'')),coalesce(nullif(v_stop->>'sourceObservedAt','')::timestamptz,p_source_observed_at),nullif(btrim(v_stop->>'workerInstruction'),''),coalesce(v_stop->'metadata','{}'::jsonb)) returning * into v_stop_row;
    if v_stop ? 'bindings' and jsonb_typeof(v_stop->'bindings')='array' then
      for v_binding in select value from jsonb_array_elements(v_stop->'bindings') loop
        insert into atlas.operational_route_bindings(organization_id,operational_route_stop_id,stable_key,obligation_kind,domain_key,source_record_id,source_record_key,quantity,unit,worker_description,payload)
        values(p_organization_id,v_stop_row.id,coalesce(nullif(btrim(v_binding->>'stableKey'),''),'binding-'||substr(md5(v_binding::text),1,12)),coalesce(nullif(v_binding->>'obligationKind',''),'handoff'),coalesce(nullif(btrim(v_binding->>'domainKey'),''),'generic'),nullif(v_binding->>'sourceRecordId','')::uuid,nullif(btrim(v_binding->>'sourceRecordKey'),''),nullif(v_binding->>'quantity','')::numeric,nullif(btrim(v_binding->>'unit'),''),coalesce(nullif(btrim(v_binding->>'workerDescription'),''),'Complete the assigned route obligation.'),coalesce(v_binding->'payload','{}'::jsonb));
      end loop;
    end if;
    v_count:=v_count+1;
  end loop;
  return jsonb_build_object('contractVersion','operational_route_v1','routeId',v_route.id,'stopCount',v_count,'idempotentReplay',false);
end;
$function$;

create or replace function atlas.worker_operational_route_stops_v1(p_organization_id uuid,p_for_date date default ((now() at time zone 'America/Chicago')::date))
returns table(route_id uuid,route_label text,route_kind text,route_date date,route_state text,stop_id uuid,sequence_number integer,stop_kind text,stop_state text,destination_label text,address_text text,contact_name text,contact_detail text,service_window_start timestamptz,service_window_end timestamptz,worker_instruction text,obligations jsonb)
language plpgsql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_membership_id uuid;
begin
  v_membership_id:=atlas.current_organization_membership_v1(p_organization_id);
  if v_membership_id is null then raise exception 'No active organization membership.' using errcode='42501'; end if;
  return query
  select r.id,r.route_label,r.route_kind,r.route_date,r.state,s.id,s.sequence_number,s.stop_kind,s.state,s.destination_label,s.address_text,s.contact_name,s.contact_detail,s.service_window_start,s.service_window_end,s.worker_instruction,
    coalesce((select jsonb_agg(jsonb_build_object('bindingId',b.id,'obligationKind',b.obligation_kind,'domainKey',b.domain_key,'quantity',b.quantity,'unit',b.unit,'description',b.worker_description) order by b.created_at,b.id) from atlas.operational_route_bindings b where b.operational_route_stop_id=s.id),'[]'::jsonb)
  from atlas.operational_routes r join atlas.operational_route_stops s on s.operational_route_id=r.id
  where r.organization_id=p_organization_id and r.route_date=p_for_date and r.state not in ('completed','cancelled') and s.state not in ('completed','cancelled')
    and coalesce(s.assigned_organization_membership_id,r.assigned_organization_membership_id)=v_membership_id
  order by r.route_date,r.created_at,s.sequence_number,s.created_at;
end;
$function$;

create or replace function atlas.owner_operational_route_board_v1(p_organization_id uuid,p_from_date date,p_through_date date)
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_actor uuid; v_result jsonb;
begin
  v_actor:=atlas.require_operational_route_owner_v1(p_organization_id);
  if p_from_date is null or p_through_date is null or p_through_date<p_from_date or p_through_date-p_from_date>60 then raise exception 'Choose a route window of 60 days or less.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(route_row order by (route_row->>'routeDate'),(route_row->>'routeLabel')),'[]'::jsonb) into v_result from (
    select jsonb_build_object('routeId',r.id,'routeLabel',r.route_label,'routeKind',r.route_kind,'routeDate',r.route_date,'state',r.state,'assignedOrganizationMembershipId',r.assigned_organization_membership_id,'externalCustodianLabel',r.external_custodian_label,'sourceAuthority',r.source_authority,'sourceSystemKey',r.source_system_key,'sourceRecordKey',r.source_record_key,'stops',coalesce((select jsonb_agg(jsonb_build_object('stopId',s.id,'sequence',s.sequence_number,'stopKind',s.stop_kind,'state',s.state,'destinationLabel',s.destination_label,'addressText',s.address_text,'contactName',s.contact_name,'contactDetail',s.contact_detail,'windowStart',s.service_window_start,'windowEnd',s.service_window_end,'assignedOrganizationMembershipId',s.assigned_organization_membership_id,'workerInstruction',s.worker_instruction,'bindings',coalesce((select jsonb_agg(jsonb_build_object('bindingId',b.id,'obligationKind',b.obligation_kind,'domainKey',b.domain_key,'sourceRecordId',b.source_record_id,'sourceRecordKey',b.source_record_key,'quantity',b.quantity,'unit',b.unit,'workerDescription',b.worker_description,'payload',b.payload) order by b.created_at,b.id) from atlas.operational_route_bindings b where b.operational_route_stop_id=s.id),'[]'::jsonb)) order by s.sequence_number,s.created_at) from atlas.operational_route_stops s where s.operational_route_id=r.id),'[]'::jsonb)) route_row
    from atlas.operational_routes r where r.organization_id=p_organization_id and r.route_date between p_from_date and p_through_date
  ) q;
  return jsonb_build_object('contractVersion','operational_route_board_v1','routes',v_result);
end;
$function$;

create or replace function atlas.record_operational_route_stop_event_v1(p_stop_id uuid,p_event_kind text,p_note text,p_payload jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','atlas','auth' as $function$
declare v_stop atlas.operational_route_stops%rowtype; v_route atlas.operational_routes%rowtype; v_actor atlas.organization_memberships%rowtype; v_effective_assignee uuid; v_new_stop_state text; v_event atlas.operational_route_events%rowtype; v_open_count integer;
begin
  select * into v_stop from atlas.operational_route_stops where id=p_stop_id for update;
  if v_stop.id is null then raise exception 'Route stop was not found.' using errcode='P0002'; end if;
  select * into v_route from atlas.operational_routes where id=v_stop.operational_route_id for update;
  select * into v_actor from atlas.organization_memberships where organization_id=v_stop.organization_id and user_id=auth.uid() and active order by case role when 'owner' then 1 when 'consultant' then 2 else 3 end,created_at limit 1;
  if v_actor.id is null then raise exception 'No active organization membership.' using errcode='42501'; end if;
  v_effective_assignee:=coalesce(v_stop.assigned_organization_membership_id,v_route.assigned_organization_membership_id);
  if v_actor.role not in ('owner','consultant') and v_effective_assignee is distinct from v_actor.id then raise exception 'This route stop is not assigned to you.' using errcode='42501'; end if;
  if p_event_kind not in ('loaded','departed','arrived','handoff_complete','service_complete','failed','returned','cancelled','note') then raise exception 'Route event kind is invalid.' using errcode='22023'; end if;
  if nullif(btrim(p_idempotency_key),'') is null then raise exception 'An idempotency key is required.' using errcode='22023'; end if;
  select * into v_event from atlas.operational_route_events where organization_id=v_stop.organization_id and idempotency_key=p_idempotency_key;
  if v_event.id is not null then return jsonb_build_object('contractVersion','operational_route_event_v1','eventId',v_event.id,'stopId',v_stop.id,'idempotentReplay',true); end if;
  v_new_stop_state:=case p_event_kind when 'loaded' then 'ready' when 'departed' then 'en_route' when 'arrived' then 'arrived' when 'handoff_complete' then 'completed' when 'service_complete' then 'completed' when 'failed' then 'failed' when 'returned' then 'completed' when 'cancelled' then 'cancelled' else v_stop.state end;
  insert into atlas.operational_route_events(organization_id,operational_route_id,operational_route_stop_id,event_kind,recorded_by_organization_membership_id,note,idempotency_key,source_authority,payload)
  values(v_stop.organization_id,v_route.id,v_stop.id,p_event_kind,v_actor.id,nullif(btrim(p_note),''),p_idempotency_key,'atlas',coalesce(p_payload,'{}'::jsonb)) returning * into v_event;
  update atlas.operational_route_stops set state=v_new_stop_state,updated_at=now() where id=v_stop.id;
  if v_route.state='planned' and p_event_kind in ('loaded','departed','arrived') then update atlas.operational_routes set state='active',updated_at=now() where id=v_route.id; end if;
  select count(*) into v_open_count from atlas.operational_route_stops where operational_route_id=v_route.id and state not in ('completed','cancelled','failed');
  if v_open_count=0 then update atlas.operational_routes set state=case when exists(select 1 from atlas.operational_route_stops where operational_route_id=v_route.id and state='failed') then 'active' else 'completed' end,updated_at=now() where id=v_route.id; end if;
  return jsonb_build_object('contractVersion','operational_route_event_v1','eventId',v_event.id,'routeId',v_route.id,'stopId',v_stop.id,'stopState',v_new_stop_state,'idempotentReplay',false);
end;
$function$;

revoke all on function atlas.current_organization_membership_v1(uuid) from public,anon;
revoke all on function atlas.require_operational_route_owner_v1(uuid) from public,anon;
revoke all on function atlas.resolve_route_org_membership_from_farm_membership_v1(uuid,uuid) from public,anon,authenticated;
revoke all on function atlas.record_operational_route_v1(uuid,text,date,text,text,uuid,text,text,text,text,timestamptz,jsonb,jsonb,text) from public,anon;
revoke all on function atlas.worker_operational_route_stops_v1(uuid,date) from public,anon;
revoke all on function atlas.owner_operational_route_board_v1(uuid,date,date) from public,anon;
revoke all on function atlas.record_operational_route_stop_event_v1(uuid,text,text,jsonb,text) from public,anon;
grant execute on function atlas.current_organization_membership_v1(uuid) to authenticated,service_role;
grant execute on function atlas.require_operational_route_owner_v1(uuid) to authenticated,service_role;
grant execute on function atlas.resolve_route_org_membership_from_farm_membership_v1(uuid,uuid) to service_role;
grant execute on function atlas.record_operational_route_v1(uuid,text,date,text,text,uuid,text,text,text,text,timestamptz,jsonb,jsonb,text) to authenticated,service_role;
grant execute on function atlas.worker_operational_route_stops_v1(uuid,date) to authenticated,service_role;
grant execute on function atlas.owner_operational_route_board_v1(uuid,date,date) to authenticated,service_role;
grant execute on function atlas.record_operational_route_stop_event_v1(uuid,text,text,jsonb,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected) values
('atlas.record_operational_route_v1(uuid, text, date, text, text, uuid, text, text, text, text, timestamp with time zone, jsonb, jsonb, text)','owner_admin_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('source','atlas_operational_routes_platform_v1','scope','organization','purpose','Create product, service, pickup, delivery, handoff, or mixed routes without taking domain commercial authority.'),now(),false),
('atlas.worker_operational_route_stops_v1(uuid, date)','app_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('source','atlas_operational_routes_platform_v1','scope','assigned_worker_only','workerBoundary','Returns only worker-safe assigned stop context and never returns binding payload/commercial totals.'),now(),false),
('atlas.owner_operational_route_board_v1(uuid, date, date)','owner_admin_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('source','atlas_operational_routes_platform_v1','scope','organization','purpose','Owner/Consultant organization-wide route board.'),now(),false),
('atlas.record_operational_route_stop_event_v1(uuid, text, text, jsonb, text)','app_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('source','atlas_operational_routes_platform_v1','scope','assigned_worker_or_owner','truthBoundary','Operational event does not silently create domain sale, inventory, or service truth.'),now(),false)
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,reviewed_at=excluded.reviewed_at,anonymous_execute_expected=excluded.anonymous_execute_expected;

comment on function atlas.worker_operational_route_stops_v1(uuid,date) is 'Worker-scoped operational route projection. Returns only assigned active stops and worker-safe obligation descriptions; no commercial totals or unassigned route state.';
comment on function atlas.record_operational_route_stop_event_v1(uuid,text,text,jsonb,text) is 'Records assigned route execution. Route completion is operational truth only; domain adapters remain responsible for sale, inventory, or service completion semantics.';