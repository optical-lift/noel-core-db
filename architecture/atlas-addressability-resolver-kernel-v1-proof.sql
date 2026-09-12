-- Atlas Addressability + Resolver Kernel v1 — rollback proof
-- PRE-MIGRATION PROOF ONLY.
-- Run only against a disposable/production-schema-clone database after applying:
--   1. architecture/atlas-addressability-resolver-kernel-v1.sql
--   2. architecture/atlas-addressability-resolver-kernel-v1-hardening.sql
-- The whole proof rolls back.

BEGIN;

DO $proof$
declare
  v_org uuid;
  v_unit uuid;
  v_endpoint uuid;
  v_subject uuid;
  v_interface uuid;
  v_external_subject uuid;
  v_external_interface uuid;
  v_evidence uuid;
  v_local_context uuid;
  v_local_entity uuid;
  v_result jsonb;
  v_count int;
begin
  -- Real released Elm institutional anchors.
  select id into v_org from atlas.organizations where stable_key='feast_guild' and status='active';
  if v_org is null then raise exception 'Proof requires active Feast Guild organization.'; end if;

  select id into v_unit from atlas.organization_units
  where organization_id=v_org and stable_key='elm' and status='active';
  if v_unit is null then raise exception 'Proof requires active Elm organization unit.'; end if;

  select id into v_endpoint from atlas.communication_endpoints
  where organization_id=v_org
    and organization_unit_id=v_unit
    and endpoint_state='active'
    and endpoint_kind='email'
    and address_normalized=atlas.normalize_communication_endpoint_address_v1('email','hello@elmfarm.co')
  order by created_at limit 1;
  if v_endpoint is null then raise exception 'Proof requires active Elm institutional email endpoint.'; end if;

  -- Establish Elm network identity through service seam.
  v_result:=atlas.establish_addressable_subject_for_institution_service_v1(
    v_org,v_unit,'institution',jsonb_build_object('proof','elm_contact_v1')
  );
  v_subject:=(v_result->>'addressableSubjectId')::uuid;
  if v_subject is null then raise exception 'Elm Addressable Subject was not established.'; end if;

  -- Idempotent second establishment resolves the same subject.
  v_result:=atlas.establish_addressable_subject_for_institution_service_v1(
    v_org,v_unit,'institution',jsonb_build_object('proof','elm_contact_v1_repeat')
  );
  if (v_result->>'addressableSubjectId')::uuid <> v_subject then
    raise exception 'Institution establishment created duplicate Addressable Subject.';
  end if;

  -- One institution cannot gain a second active network identity.
  select count(*) into v_count
  from atlas.addressable_subject_institution_bindings
  where organization_id=v_org and organization_unit_id=v_unit and binding_state='active';
  if v_count<>1 then raise exception 'Expected exactly one active Elm institution binding, got %.',v_count; end if;

  -- Publish contact only. visit/events/availability remain absent by design.
  v_result:=atlas.publish_addressable_interface_service_v1(
    v_subject,'contact','Contact','authenticated_exact','institutional_communication_endpoint','{}'::jsonb,
    jsonb_build_object('proof','entity_authorized_elm_contact')
  );
  v_interface:=(v_result->>'addressableInterfaceId')::uuid;
  if v_interface is null then raise exception 'Elm contact interface was not established.'; end if;

  if exists(
    select 1 from atlas.addressable_interfaces
    where addressable_subject_id=v_subject and stable_key in ('visit','events','wholesale_availability')
  ) then
    raise exception 'Proof must not fabricate unadmitted Elm interfaces.';
  end if;

  -- Verify the Resolver function still requires an authenticated Atlas actor by
  -- inspecting its grant surface; the full auth.uid human path belongs in the
  -- production-schema clone harness where an authenticated fixture can be set up.
  if has_function_privilege('anon','atlas.resolve_addressable_subject_exact_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Anon must not execute exact Addressable Subject resolution.';
  end if;
  if has_function_privilege('anon','atlas.resolve_addressable_interface_self_api_v1(uuid,text)','EXECUTE') then
    raise exception 'Anon must not execute Addressable Interface resolution.';
  end if;
  if not has_function_privilege('authenticated','atlas.resolve_addressable_subject_exact_self_api_v1(uuid)','EXECUTE') then
    raise exception 'Authenticated role must have exact resolution execute privilege.';
  end if;

  -- External non-controlled proof uses a synthetic organization identity. It
  -- has no Atlas Organization/Unit binding and route truth lives in Evidence.
  v_result:=atlas.establish_external_addressable_subject_service_v1(
    'organization',jsonb_build_object('proof','synthetic_external_noncontrolled')
  );
  v_external_subject:=(v_result->>'addressableSubjectId')::uuid;

  v_result:=atlas.publish_addressable_interface_service_v1(
    v_external_subject,'contact','Contact','authenticated_exact','source_attributed_external_route','{}'::jsonb,
    jsonb_build_object('proof','externally_observed_only')
  );
  v_external_interface:=(v_result->>'addressableInterfaceId')::uuid;

  if exists(
    select 1 from atlas.addressable_subject_institution_bindings
    where addressable_subject_id=v_external_subject and binding_state='active'
  ) then
    raise exception 'Externally observed subject must not receive institution authority by implication.';
  end if;

  insert into atlas.evidence_records(
    scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,
    source_kind,source_key,value,confidence,observed_at,provenance,metadata
  ) values (
    'organization',v_org,
    'addressability','addressable_subject',v_external_subject::text,'external_route',
    'proof_fixture','external_route_1',
    jsonb_build_object('routeKind','website','address','https://example.invalid/'),
    1,now(),jsonb_build_object('proof',true),'{}'::jsonb
  ) returning id into v_evidence;

  insert into atlas.addressable_interface_evidence(addressable_interface_id,evidence_id,relation_kind)
  values(v_external_interface,v_evidence,'route_evidence');

  if not exists(
    select 1
    from atlas.addressable_interface_evidence b
    join atlas.evidence_records e on e.id=b.evidence_id
    where b.addressable_interface_id=v_external_interface
      and e.subject_id=v_external_subject::text
      and e.evidence_kind='external_route'
  ) then
    raise exception 'External route evidence did not bind correctly.';
  end if;

  -- Prove Local reconciliation remains a relation, not globalized Local state.
  select e.local_context_id,e.id into v_local_context,v_local_entity
  from local_intel.entities e
  where lower(e.name)=lower('Elm Farm')
  order by e.created_at
  limit 1;

  if v_local_entity is not null then
    insert into atlas.addressable_subject_local_assertions(
      local_context_id,local_entity_id,addressable_subject_id,assertion_kind,confidence,basis,adjudication_state
    ) values (
      v_local_context,v_local_entity,v_subject,'supports',1,
      jsonb_build_object('proof','local_to_addressable_relation_only'),'accepted'
    );

    if not exists(
      select 1 from atlas.addressable_subject_local_assertions
      where local_context_id=v_local_context and local_entity_id=v_local_entity and addressable_subject_id=v_subject
    ) then
      raise exception 'Local-to-Addressable assertion missing.';
    end if;
  end if;

  -- Direct browser roles must not read/write canonical tables.
  if has_table_privilege('authenticated','atlas.addressable_subjects','SELECT')
     or has_table_privilege('authenticated','atlas.addressable_interfaces','SELECT')
     or has_table_privilege('authenticated','atlas.addressable_subject_institution_bindings','SELECT')
     or has_table_privilege('authenticated','atlas.addressable_interface_evidence','SELECT') then
    raise exception 'Authenticated browser role received direct addressability table read authority.';
  end if;

  raise notice 'Atlas Addressability + Resolver Kernel v1 rollback proof passed.';
end;
$proof$;

ROLLBACK;
