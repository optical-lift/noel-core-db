-- Atlas Addressability + Resolver Kernel v1 — hardening layer
-- PRE-MIGRATION EXECUTABLE CANDIDATE ONLY.
-- Apply after architecture/atlas-addressability-resolver-kernel-v1.sql when
-- evaluating the pre-migration package. Canonical migration assembly remains
-- gated on the pinned Supabase CLI workflow.

BEGIN;

-- One active Addressable Subject may represent a given participating Atlas
-- institution at a time. Organization-level and Unit-level bindings require
-- separate partial indexes because NULL is semantically meaningful here.
create unique index addressable_subject_active_org_binding_uidx
  on atlas.addressable_subject_institution_bindings(organization_id)
  where binding_state='active' and organization_unit_id is null;

create unique index addressable_subject_active_org_unit_binding_uidx
  on atlas.addressable_subject_institution_bindings(organization_id,organization_unit_id)
  where binding_state='active' and organization_unit_id is not null;

-- External route truth remains source evidence. Addressability stores only the
-- fact that an interface may use admitted evidence; it does not copy URL/email/
-- phone/address truth into resolver_config.
create table atlas.addressable_interface_evidence (
  addressable_interface_id uuid not null references atlas.addressable_interfaces(id) on delete cascade,
  evidence_id uuid not null references atlas.evidence_records(id) on delete restrict,
  relation_kind text not null default 'route_evidence' check (relation_kind in ('route_evidence','publication_evidence')),
  created_at timestamptz not null default now(),
  primary key(addressable_interface_id,evidence_id,relation_kind)
);

comment on table atlas.addressable_interface_evidence is
  'Typed evidence binding for Addressable Interfaces. External routes remain atlas.evidence_records truth and are never copied into the interface row.';

create or replace function atlas.guard_addressable_interface_evidence_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, atlas
as $function$
declare
  v_subject_id uuid;
  v_evidence atlas.evidence_records%rowtype;
begin
  select i.addressable_subject_id into v_subject_id
  from atlas.addressable_interfaces i
  where i.id=new.addressable_interface_id;

  select * into v_evidence
  from atlas.evidence_records e
  where e.id=new.evidence_id;

  if v_subject_id is null or v_evidence.id is null then
    raise exception 'Addressable Interface and Evidence are required.' using errcode='23503';
  end if;

  if v_evidence.subject_domain <> 'addressability'
     or v_evidence.subject_kind <> 'addressable_subject'
     or v_evidence.subject_id <> v_subject_id::text then
    raise exception 'Addressability evidence subject does not match Addressable Subject.' using errcode='23514';
  end if;

  if new.relation_kind='route_evidence' and v_evidence.evidence_kind <> 'external_route' then
    raise exception 'Route evidence must use evidence_kind=external_route.' using errcode='23514';
  end if;

  return new;
end;
$function$;

create trigger addressable_interface_evidence_guard
before insert or update on atlas.addressable_interface_evidence
for each row execute function atlas.guard_addressable_interface_evidence_v1();

alter table atlas.addressable_interface_evidence enable row level security;
revoke all on atlas.addressable_interface_evidence from public, anon, authenticated;

-- The external-route resolver now reads only admitted Evidence bound to the
-- interface. resolver_config is not route truth.
create or replace function atlas.resolve_addressable_interface_self_api_v1(
  p_addressable_subject_id uuid,
  p_interface_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_interface atlas.addressable_interfaces%rowtype;
  v_binding atlas.addressable_subject_institution_bindings%rowtype;
  v_endpoint atlas.communication_endpoints%rowtype;
  v_routes jsonb;
begin
  if auth.uid() is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select * into v_interface
  from atlas.addressable_interfaces
  where addressable_subject_id=p_addressable_subject_id
    and stable_key=btrim(p_interface_key)
    and interface_state='active'
    and visibility_scope in ('authenticated_exact','authenticated_discovery');

  if v_interface.id is null then
    return jsonb_build_object(
      'contractVersion','addressable_interface_resolution_v1',
      'state','interface_not_established'
    );
  end if;

  if v_interface.resolver_kind='institutional_communication_endpoint' then
    select * into v_binding
    from atlas.addressable_subject_institution_bindings
    where addressable_subject_id=p_addressable_subject_id
      and binding_state='active'
    order by established_at desc
    limit 1;

    if v_binding.id is null then
      return jsonb_build_object(
        'contractVersion','addressable_interface_resolution_v1',
        'state','unavailable',
        'reason','no_entity_authorized_binding'
      );
    end if;

    select * into v_endpoint
    from atlas.communication_endpoints ep
    where ep.organization_id=v_binding.organization_id
      and ep.organization_unit_id is not distinct from v_binding.organization_unit_id
      and ep.endpoint_state='active'
      and ep.endpoint_kind in ('email','phone','sms','voice','web_form','social','atlas_native')
    order by
      case ep.endpoint_kind
        when 'atlas_native' then 1
        when 'email' then 2
        when 'web_form' then 3
        when 'phone' then 4
        else 5
      end,
      ep.created_at,
      ep.id
    limit 1;

    if v_endpoint.id is null then
      return jsonb_build_object(
        'contractVersion','addressable_interface_resolution_v1',
        'state','unavailable',
        'reason','no_active_communication_endpoint'
      );
    end if;

    return jsonb_build_object(
      'contractVersion','addressable_interface_resolution_v1',
      'state','resolved',
      'addressableSubjectId',p_addressable_subject_id,
      'interfaceKey',v_interface.stable_key,
      'resolverKind',v_interface.resolver_kind,
      'target',jsonb_build_object(
        'communicationEndpointId',v_endpoint.id,
        'endpointKind',v_endpoint.endpoint_kind,
        'address',v_endpoint.address,
        'displayName',v_endpoint.display_name
      ),
      'authorityPosition','entity_authorized'
    );
  end if;

  if v_interface.resolver_kind='source_attributed_external_route' then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'route',e.value,
        'evidenceId',e.id,
        'sourceKind',e.source_kind,
        'sourceKey',e.source_key,
        'observedAt',e.observed_at,
        'learnedAt',e.learned_at,
        'effectiveFrom',e.effective_from,
        'effectiveUntil',e.effective_until,
        'confidence',e.confidence,
        'provenance',e.provenance
      ) order by coalesce(e.observed_at,e.learned_at) desc,e.id
    ),'[]'::jsonb)
    into v_routes
    from atlas.addressable_interface_evidence b
    join atlas.evidence_records e on e.id=b.evidence_id
    where b.addressable_interface_id=v_interface.id
      and b.relation_kind='route_evidence'
      and e.subject_domain='addressability'
      and e.subject_kind='addressable_subject'
      and e.subject_id=p_addressable_subject_id::text
      and e.evidence_kind='external_route'
      and (e.effective_until is null or e.effective_until>=now());

    if jsonb_array_length(v_routes)=0 then
      return jsonb_build_object(
        'contractVersion','addressable_interface_resolution_v1',
        'state','unavailable',
        'reason','no_source_attributed_route'
      );
    end if;

    return jsonb_build_object(
      'contractVersion','addressable_interface_resolution_v1',
      'state','resolved',
      'addressableSubjectId',p_addressable_subject_id,
      'interfaceKey',v_interface.stable_key,
      'resolverKind',v_interface.resolver_kind,
      'target',jsonb_build_object('routes',v_routes),
      'authorityPosition','externally_observed'
    );
  end if;

  return jsonb_build_object(
    'contractVersion','addressable_interface_resolution_v1',
    'state','unavailable',
    'reason','unsupported_resolver_kind'
  );
end;
$function$;

COMMIT;
