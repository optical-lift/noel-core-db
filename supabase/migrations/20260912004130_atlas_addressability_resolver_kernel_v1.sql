-- Atlas Addressability + Resolver Kernel v1
-- Network identity + governed reachability. Existing domains keep their truth.
BEGIN;

create table atlas.addressable_subjects (
  id uuid primary key default gen_random_uuid(),
  subject_kind text not null check (subject_kind in ('organization','institution')),
  lifecycle_state text not null default 'active' check (lifecycle_state in ('active','retired')),
  creation_authority text not null check (creation_authority in ('externally_observed','atlas_institution')),
  resolution_scope text not null default 'private' check (resolution_scope in ('private','authenticated_exact','authenticated_discovery')),
  creation_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(creation_basis)='object'),
  resolution_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_basis)='object'),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), retired_at timestamptz null,
  check (retired_at is null or lifecycle_state='retired')
);
comment on table atlas.addressable_subjects is 'Thin network-level Atlas identity anchor. Names, routes, providers, places, Local research and operating truth remain in owning domains.';
create index addressable_subjects_kind_scope_idx on atlas.addressable_subjects(subject_kind,lifecycle_state,resolution_scope,created_at);

create table atlas.addressable_subject_institution_bindings (
  id uuid primary key default gen_random_uuid(),
  addressable_subject_id uuid not null references atlas.addressable_subjects(id) on delete restrict,
  organization_id uuid not null references atlas.organizations(id) on delete restrict,
  organization_unit_id uuid null references atlas.organization_units(id) on delete restrict,
  binding_state text not null default 'active' check (binding_state in ('active','revoked','superseded')),
  publication_authority text not null default 'entity_authorized' check (publication_authority='entity_authorized'),
  basis jsonb not null default '{}'::jsonb check (jsonb_typeof(basis)='object'),
  established_at timestamptz not null default now(), ended_at timestamptz null,
  check (ended_at is null or binding_state in ('revoked','superseded'))
);
create unique index addressable_subject_active_binding_uidx on atlas.addressable_subject_institution_bindings(addressable_subject_id) where binding_state='active';
create unique index addressable_subject_active_org_binding_uidx on atlas.addressable_subject_institution_bindings(organization_id) where binding_state='active' and organization_unit_id is null;
create unique index addressable_subject_active_org_unit_binding_uidx on atlas.addressable_subject_institution_bindings(organization_id,organization_unit_id) where binding_state='active' and organization_unit_id is not null;
comment on table atlas.addressable_subject_institution_bindings is 'Explicit Atlas institutional publication authority. Binding does not merge tenant Core Identity or Local entities and does not imply provider transport custody.';

create table atlas.addressable_interfaces (
  id uuid primary key default gen_random_uuid(),
  addressable_subject_id uuid not null references atlas.addressable_subjects(id) on delete restrict,
  stable_key text not null check (stable_key ~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$'),
  display_name text null check (display_name is null or btrim(display_name)<>''),
  interface_state text not null default 'active' check (interface_state in ('active','inactive','retired')),
  visibility_scope text not null default 'authenticated_exact' check (visibility_scope in ('authenticated_exact','authenticated_discovery')),
  resolver_kind text not null check (resolver_kind in ('institutional_communication_endpoint','source_attributed_external_route')),
  publication_basis jsonb not null default '{}'::jsonb check (jsonb_typeof(publication_basis)='object'),
  established_at timestamptz not null default now(), updated_at timestamptz not null default now(), retired_at timestamptz null,
  check (retired_at is null or interface_state='retired'), unique(addressable_subject_id,stable_key)
);
create index addressable_interfaces_subject_state_idx on atlas.addressable_interfaces(addressable_subject_id,interface_state,visibility_scope,stable_key);
comment on table atlas.addressable_interfaces is 'Subject-specific governed interfaces. Endpoint, route, event, place and commerce truth remain in owning domains.';

create table atlas.addressable_interface_evidence (
  addressable_interface_id uuid not null references atlas.addressable_interfaces(id) on delete cascade,
  evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  relation_kind text not null default 'route_evidence' check (relation_kind in ('route_evidence','publication_evidence')),
  created_at timestamptz not null default now(), primary key(addressable_interface_id,evidence_id,relation_kind)
);
comment on table atlas.addressable_interface_evidence is 'Typed Evidence binding; external routes remain atlas.evidence_records truth rather than Resolver profile state.';

create or replace function atlas.block_addressable_subject_delete_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $f$
begin raise exception 'Addressable Subjects are retired or superseded; they are not deleted.' using errcode='55000'; end;$f$;
create trigger addressable_subjects_no_delete before delete on atlas.addressable_subjects for each row execute function atlas.block_addressable_subject_delete_v1();

create or replace function atlas.guard_addressable_subject_institution_binding_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $f$
begin
  if new.organization_unit_id is not null and not exists(select 1 from atlas.organization_units u where u.id=new.organization_unit_id and u.organization_id=new.organization_id) then
    raise exception 'Addressable Subject institution binding organization unit is outside organization.' using errcode='23514';
  end if; return new;
end;$f$;
create trigger addressable_subject_institution_binding_guard before insert or update on atlas.addressable_subject_institution_bindings for each row execute function atlas.guard_addressable_subject_institution_binding_v1();

create or replace function atlas.guard_addressable_interface_evidence_v1() returns trigger language plpgsql set search_path=pg_catalog,atlas as $f$
declare v_subject uuid; v_e atlas.evidence_records%rowtype; v_extra jsonb;
begin
  select addressable_subject_id into v_subject from atlas.addressable_interfaces where id=new.addressable_interface_id;
  select * into v_e from atlas.evidence_records where id=new.evidence_id;
  if v_subject is null or v_e.id is null then raise exception 'Addressable Interface and Evidence are required.' using errcode='23503'; end if;
  if v_e.scope_kind<>'addressable_subject' or v_e.scope_id<>v_subject or v_e.subject_domain<>'addressability' or v_e.subject_kind<>'addressable_subject' or v_e.subject_id<>v_subject::text then
    raise exception 'Addressability Evidence subject does not match Addressable Subject.' using errcode='23514'; end if;
  if new.relation_kind='route_evidence' then
    if v_e.evidence_kind<>'external_route' or jsonb_typeof(v_e.value)<>'object' or not(v_e.value?'routeKind') or not(v_e.value?'address') or btrim(coalesce(v_e.value->>'address',''))='' or coalesce(v_e.value->>'routeKind','') not in ('website','email','phone','social','web_form') then
      raise exception 'External route Evidence must contain an admitted routeKind and nonblank address.' using errcode='23514'; end if;
    v_extra:=v_e.value-array['routeKind','address','label']::text[];
    if v_extra<>'{}'::jsonb then raise exception 'External route Evidence contains unsupported public route fields.' using errcode='23514'; end if;
  end if; return new;
end;$f$;
create trigger addressable_interface_evidence_guard before insert or update on atlas.addressable_interface_evidence for each row execute function atlas.guard_addressable_interface_evidence_v1();

create or replace function atlas.establish_addressable_subject_for_institution_service_v1(p_organization_id uuid,p_organization_unit_id uuid,p_subject_kind text,p_creation_basis jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
declare v_subject uuid; v_binding uuid;
begin
  if p_subject_kind not in ('organization','institution') or jsonb_typeof(coalesce(p_creation_basis,'{}'::jsonb))<>'object' then raise exception 'Valid subject kind and creation basis required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.organizations where id=p_organization_id and status='active') then raise exception 'Active organization required.' using errcode='23503'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units where id=p_organization_unit_id and organization_id=p_organization_id and status='active') then raise exception 'Active organization unit required.' using errcode='23503'; end if;
  select b.addressable_subject_id,b.id into v_subject,v_binding from atlas.addressable_subject_institution_bindings b join atlas.addressable_subjects s on s.id=b.addressable_subject_id where b.organization_id=p_organization_id and b.organization_unit_id is not distinct from p_organization_unit_id and b.binding_state='active' and s.lifecycle_state='active' limit 1;
  if v_subject is not null then return jsonb_build_object('contractVersion','addressable_subject_v1','addressableSubjectId',v_subject,'state','existing'); end if;
  insert into atlas.addressable_subjects(subject_kind,creation_authority,creation_basis) values(p_subject_kind,'atlas_institution',coalesce(p_creation_basis,'{}'::jsonb)) returning id into v_subject;
  insert into atlas.addressable_subject_institution_bindings(addressable_subject_id,organization_id,organization_unit_id,basis) values(v_subject,p_organization_id,p_organization_unit_id,coalesce(p_creation_basis,'{}'::jsonb)) returning id into v_binding;
  return jsonb_build_object('contractVersion','addressable_subject_v1','addressableSubjectId',v_subject,'bindingId',v_binding,'state','established');
end;$f$;

create or replace function atlas.establish_external_addressable_subject_service_v1(p_subject_kind text,p_creation_basis jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
declare v_subject uuid;
begin
  if p_subject_kind not in ('organization','institution') or jsonb_typeof(coalesce(p_creation_basis,'{}'::jsonb))<>'object' then raise exception 'Valid subject kind and creation basis required.' using errcode='22023'; end if;
  insert into atlas.addressable_subjects(subject_kind,creation_authority,creation_basis) values(p_subject_kind,'externally_observed',coalesce(p_creation_basis,'{}'::jsonb)) returning id into v_subject;
  return jsonb_build_object('contractVersion','addressable_subject_v1','addressableSubjectId',v_subject,'state','established');
end;$f$;

create or replace function atlas.bind_addressable_subject_to_institution_service_v1(p_addressable_subject_id uuid,p_organization_id uuid,p_organization_unit_id uuid,p_basis jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
declare v_binding uuid;
begin
  if jsonb_typeof(coalesce(p_basis,'{}'::jsonb))<>'object' then raise exception 'Binding basis must be an object.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.addressable_subjects where id=p_addressable_subject_id and lifecycle_state='active') then raise exception 'Active Addressable Subject required.' using errcode='23503'; end if;
  if not exists(select 1 from atlas.organizations where id=p_organization_id and status='active') then raise exception 'Active organization required.' using errcode='23503'; end if;
  if p_organization_unit_id is not null and not exists(select 1 from atlas.organization_units where id=p_organization_unit_id and organization_id=p_organization_id and status='active') then raise exception 'Active organization unit required.' using errcode='23503'; end if;
  select id into v_binding from atlas.addressable_subject_institution_bindings where addressable_subject_id=p_addressable_subject_id and organization_id=p_organization_id and organization_unit_id is not distinct from p_organization_unit_id and binding_state='active' limit 1;
  if v_binding is null then insert into atlas.addressable_subject_institution_bindings(addressable_subject_id,organization_id,organization_unit_id,basis) values(p_addressable_subject_id,p_organization_id,p_organization_unit_id,coalesce(p_basis,'{}'::jsonb)) returning id into v_binding; end if;
  return jsonb_build_object('contractVersion','addressable_subject_binding_v1','addressableSubjectId',p_addressable_subject_id,'bindingId',v_binding,'state','established');
end;$f$;

create or replace function atlas.publish_addressable_subject_service_v1(p_addressable_subject_id uuid,p_resolution_scope text,p_publication_basis jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
declare v_authorized boolean; v_sourced boolean;
begin
  if p_resolution_scope not in ('private','authenticated_exact','authenticated_discovery') or jsonb_typeof(coalesce(p_publication_basis,'{}'::jsonb))<>'object' then raise exception 'Valid resolution scope and publication basis required.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.addressable_subjects where id=p_addressable_subject_id and lifecycle_state='active') then raise exception 'Active Addressable Subject required.' using errcode='23503'; end if;
  if p_resolution_scope<>'private' then
    select exists(select 1 from atlas.addressable_subject_institution_bindings where addressable_subject_id=p_addressable_subject_id and binding_state='active' and publication_authority='entity_authorized') into v_authorized;
    select exists(select 1 from atlas.evidence_records e where e.scope_kind='addressable_subject' and e.scope_id=p_addressable_subject_id and e.subject_domain='addressability' and e.subject_kind='addressable_subject' and e.subject_id=p_addressable_subject_id::text and e.evidence_kind='external_route' and (e.effective_from is null or e.effective_from<=now()) and (e.effective_until is null or e.effective_until>=now())) into v_sourced;
    if not v_authorized and not v_sourced then raise exception 'Published Addressable Subject requires entity authority or current external-route Evidence.' using errcode='23514'; end if;
  end if;
  update atlas.addressable_subjects set resolution_scope=p_resolution_scope,resolution_basis=coalesce(p_publication_basis,'{}'::jsonb),updated_at=now() where id=p_addressable_subject_id;
  return jsonb_build_object('contractVersion','addressable_subject_publication_v1','addressableSubjectId',p_addressable_subject_id,'resolutionScope',p_resolution_scope,'state','published');
end;$f$;

create or replace function atlas.publish_addressable_interface_service_v1(p_addressable_subject_id uuid,p_stable_key text,p_display_name text,p_visibility_scope text,p_resolver_kind text,p_publication_basis jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
declare v_id uuid;
begin
  if not exists(select 1 from atlas.addressable_subjects where id=p_addressable_subject_id and lifecycle_state='active') then raise exception 'Active Addressable Subject required.' using errcode='23503'; end if;
  if p_visibility_scope not in ('authenticated_exact','authenticated_discovery') or p_resolver_kind not in ('institutional_communication_endpoint','source_attributed_external_route') or jsonb_typeof(coalesce(p_publication_basis,'{}'::jsonb))<>'object' then raise exception 'Valid interface publication contract required.' using errcode='22023'; end if;
  if p_resolver_kind='institutional_communication_endpoint' and not exists(select 1 from atlas.addressable_subject_institution_bindings where addressable_subject_id=p_addressable_subject_id and binding_state='active' and publication_authority='entity_authorized') then raise exception 'Institutional communication interface requires entity-authorized institution binding.' using errcode='23514'; end if;
  insert into atlas.addressable_interfaces(addressable_subject_id,stable_key,display_name,visibility_scope,resolver_kind,publication_basis) values(p_addressable_subject_id,btrim(p_stable_key),nullif(btrim(p_display_name),''),p_visibility_scope,p_resolver_kind,coalesce(p_publication_basis,'{}'::jsonb)) on conflict(addressable_subject_id,stable_key) do update set display_name=excluded.display_name,interface_state='active',visibility_scope=excluded.visibility_scope,resolver_kind=excluded.resolver_kind,publication_basis=excluded.publication_basis,updated_at=now(),retired_at=null returning id into v_id;
  return jsonb_build_object('contractVersion','addressable_interface_v1','addressableInterfaceId',v_id,'addressableSubjectId',p_addressable_subject_id,'stableKey',btrim(p_stable_key),'resolverKind',p_resolver_kind,'state','active');
end;$f$;

create or replace function atlas.bind_addressable_interface_evidence_service_v1(p_addressable_interface_id uuid,p_evidence_id uuid,p_relation_kind text default 'route_evidence') returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas as $f$
begin
  if p_relation_kind not in ('route_evidence','publication_evidence') then raise exception 'Unsupported interface Evidence relation kind.' using errcode='22023'; end if;
  if not exists(select 1 from atlas.addressable_interfaces where id=p_addressable_interface_id and interface_state='active') then raise exception 'Active Addressable Interface required.' using errcode='23503'; end if;
  insert into atlas.addressable_interface_evidence(addressable_interface_id,evidence_id,relation_kind) values(p_addressable_interface_id,p_evidence_id,p_relation_kind) on conflict do nothing;
  return jsonb_build_object('contractVersion','addressable_interface_evidence_v1','addressableInterfaceId',p_addressable_interface_id,'relationKind',p_relation_kind,'state','bound');
end;$f$;

create or replace function atlas.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id uuid) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $f$
declare v_kind text; v_authorized boolean; v_interfaces jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select subject_kind into v_kind from atlas.addressable_subjects where id=p_addressable_subject_id and lifecycle_state='active' and resolution_scope in ('authenticated_exact','authenticated_discovery');
  if v_kind is null then return jsonb_build_object('contractVersion','addressable_resolution_v1','state','not_found'); end if;
  select exists(select 1 from atlas.addressable_subject_institution_bindings where addressable_subject_id=p_addressable_subject_id and binding_state='active' and publication_authority='entity_authorized') into v_authorized;
  select coalesce(jsonb_agg(jsonb_build_object('stableKey',stable_key,'displayName',display_name,'resolverKind',resolver_kind) order by stable_key),'[]'::jsonb) into v_interfaces from atlas.addressable_interfaces where addressable_subject_id=p_addressable_subject_id and interface_state='active' and visibility_scope in ('authenticated_exact','authenticated_discovery');
  return jsonb_build_object('contractVersion','addressable_resolution_v1','state','resolved','addressableSubjectId',p_addressable_subject_id,'subjectKind',v_kind,'authorityPosition',case when v_authorized then 'entity_authorized' else 'externally_observed' end,'interfaces',v_interfaces);
end;$f$;

create or replace function atlas.resolve_addressable_interface_self_api_v1(p_addressable_subject_id uuid,p_interface_key text) returns jsonb language plpgsql security definer set search_path=pg_catalog,atlas,auth as $f$
declare v_kind text; v_i atlas.addressable_interfaces%rowtype; v_b atlas.addressable_subject_institution_bindings%rowtype; v_ep atlas.communication_endpoints%rowtype; v_routes jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select subject_kind into v_kind from atlas.addressable_subjects where id=p_addressable_subject_id and lifecycle_state='active' and resolution_scope in ('authenticated_exact','authenticated_discovery');
  if v_kind is null then return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','not_found'); end if;
  select * into v_i from atlas.addressable_interfaces where addressable_subject_id=p_addressable_subject_id and stable_key=btrim(p_interface_key) and interface_state='active' and visibility_scope in ('authenticated_exact','authenticated_discovery');
  if v_i.id is null then return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','interface_not_established'); end if;
  if v_i.resolver_kind='institutional_communication_endpoint' then
    select * into v_b from atlas.addressable_subject_institution_bindings where addressable_subject_id=p_addressable_subject_id and binding_state='active' and publication_authority='entity_authorized' limit 1;
    if v_b.id is null then return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_entity_authorized_binding'); end if;
    select * into v_ep from atlas.communication_endpoints ep where ep.organization_id=v_b.organization_id and ep.organization_unit_id is not distinct from v_b.organization_unit_id and ep.endpoint_state='active' and ep.endpoint_kind in ('email','phone','sms','voice','web_form','social','atlas_native') order by case ep.endpoint_kind when 'atlas_native' then 1 when 'email' then 2 when 'web_form' then 3 when 'phone' then 4 else 5 end,ep.created_at,ep.id limit 1;
    if v_ep.id is null then return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_active_communication_endpoint'); end if;
    return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','resolved','addressableSubjectId',p_addressable_subject_id,'interfaceKey',v_i.stable_key,'resolverKind',v_i.resolver_kind,'target',jsonb_strip_nulls(jsonb_build_object('endpointKind',v_ep.endpoint_kind,'address',v_ep.address,'displayName',v_ep.display_name)),'authorityPosition','entity_authorized');
  end if;
  if v_i.resolver_kind='source_attributed_external_route' then
    select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('routeKind',e.value->>'routeKind','address',e.value->>'address','label',e.value->>'label','sourceKind',e.source_kind,'observedAt',e.observed_at,'confidence',e.confidence)) order by coalesce(e.observed_at,e.learned_at) desc,e.id),'[]'::jsonb) into v_routes from atlas.addressable_interface_evidence b join atlas.evidence_records e on e.id=b.evidence_id where b.addressable_interface_id=v_i.id and b.relation_kind='route_evidence' and e.scope_kind='addressable_subject' and e.scope_id=p_addressable_subject_id and e.subject_domain='addressability' and e.subject_kind='addressable_subject' and e.subject_id=p_addressable_subject_id::text and e.evidence_kind='external_route' and (e.effective_from is null or e.effective_from<=now()) and (e.effective_until is null or e.effective_until>=now());
    if jsonb_array_length(v_routes)=0 then return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','no_source_attributed_route'); end if;
    return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','resolved','addressableSubjectId',p_addressable_subject_id,'interfaceKey',v_i.stable_key,'resolverKind',v_i.resolver_kind,'target',jsonb_build_object('routes',v_routes),'authorityPosition','source_attributed_external');
  end if;
  return jsonb_build_object('contractVersion','addressable_interface_resolution_v1','state','unavailable','reason','unsupported_resolver_kind');
end;$f$;

create or replace function public.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id uuid) returns jsonb language sql security invoker set search_path=pg_catalog,atlas,public as $f$ select atlas.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id); $f$;
create or replace function public.resolve_addressable_interface_self_api_v1(p_addressable_subject_id uuid,p_interface_key text) returns jsonb language sql security invoker set search_path=pg_catalog,atlas,public as $f$ select atlas.resolve_addressable_interface_self_api_v1(p_addressable_subject_id,p_interface_key); $f$;

alter table atlas.addressable_subjects enable row level security;
alter table atlas.addressable_subject_institution_bindings enable row level security;
alter table atlas.addressable_interfaces enable row level security;
alter table atlas.addressable_interface_evidence enable row level security;
revoke all on atlas.addressable_subjects,atlas.addressable_subject_institution_bindings,atlas.addressable_interfaces,atlas.addressable_interface_evidence from public,anon,authenticated;

revoke all on function atlas.establish_addressable_subject_for_institution_service_v1(uuid,uuid,text,jsonb),atlas.establish_external_addressable_subject_service_v1(text,jsonb),atlas.bind_addressable_subject_to_institution_service_v1(uuid,uuid,uuid,jsonb),atlas.publish_addressable_subject_service_v1(uuid,text,jsonb),atlas.publish_addressable_interface_service_v1(uuid,text,text,text,text,jsonb),atlas.bind_addressable_interface_evidence_service_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function atlas.establish_addressable_subject_for_institution_service_v1(uuid,uuid,text,jsonb),atlas.establish_external_addressable_subject_service_v1(text,jsonb),atlas.bind_addressable_subject_to_institution_service_v1(uuid,uuid,uuid,jsonb),atlas.publish_addressable_subject_service_v1(uuid,text,jsonb),atlas.publish_addressable_interface_service_v1(uuid,text,text,text,text,jsonb),atlas.bind_addressable_interface_evidence_service_v1(uuid,uuid,text) to service_role;

revoke all on function atlas.resolve_addressable_subject_exact_self_api_v1(uuid),atlas.resolve_addressable_interface_self_api_v1(uuid,text),public.resolve_addressable_subject_exact_self_api_v1(uuid),public.resolve_addressable_interface_self_api_v1(uuid,text) from public,anon;
grant execute on function atlas.resolve_addressable_subject_exact_self_api_v1(uuid),atlas.resolve_addressable_interface_self_api_v1(uuid,text),public.resolve_addressable_subject_exact_self_api_v1(uuid),public.resolve_addressable_interface_self_api_v1(uuid,text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,anonymous_execute_expected) values
('atlas.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id uuid)','app_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('purpose','Resolve one already-known Addressable Subject through the governed authenticated membrane.','anonymousResolution',false,'directCanonicalTableRead',false,'localIntelAuthority',false,'subjectDefaultPrivate',true),false),
('atlas.resolve_addressable_interface_self_api_v1(p_addressable_subject_id uuid, p_interface_key text)','app_endpoint','verified','active',true,true,true,1,0,jsonb_build_object('purpose','Resolve one admitted Addressable Interface through its bounded owning-domain resolver.','anonymousResolution',false,'directCanonicalTableRead',false,'providerCredentialExposure',false,'boundedResolverKinds',true),false)
on conflict(signature) do update set classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,service_execute_expected=excluded.service_execute_expected,caller_count=excluded.caller_count,policy_reference_count=excluded.policy_reference_count,evidence=excluded.evidence,anonymous_execute_expected=excluded.anonymous_execute_expected;

COMMIT;
