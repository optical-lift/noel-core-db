-- Addressability + Resolver v1 postconditions. Disposable production-schema clone only.
BEGIN;
DO $proof$
declare
  v_org uuid:='818b9a23-65e9-4198-b86c-9496ba548642'::uuid;
  v_unit uuid:='1b65ac99-0f00-4ca2-9488-e8539cae2a1b'::uuid;
  v_claim_org uuid:='11111111-1111-4111-8111-111111111111'::uuid;
  v_claim_unit uuid:='22222222-2222-4222-8222-222222222222'::uuid;
  v_subject uuid; v_repeat uuid; v_private uuid; v_external uuid; v_interface uuid; v_external_interface uuid; v_evidence uuid;
  v_result jsonb; v_contact jsonb; v_external_contact jsonb; v_count integer;
begin
  if not exists(select 1 from atlas.organizations where id=v_org and stable_key='feast_guild' and status='active') then raise exception 'Fixture missing Feast Guild.'; end if;
  if not exists(select 1 from atlas.organization_units where id=v_unit and organization_id=v_org and stable_key='elm' and status='active') then raise exception 'Fixture missing Elm.'; end if;
  if not exists(select 1 from atlas.communication_endpoints where organization_id=v_org and organization_unit_id=v_unit and endpoint_kind='email' and endpoint_state='active' and address_normalized='hello@elmfarm.co') then raise exception 'Fixture missing Elm endpoint.'; end if;

  v_result:=atlas.establish_addressable_subject_for_institution_service_v1(v_org,v_unit,'institution',jsonb_build_object('validation','elm_contact_v1'));
  v_subject:=(v_result->>'addressableSubjectId')::uuid;
  v_result:=atlas.establish_addressable_subject_for_institution_service_v1(v_org,v_unit,'institution',jsonb_build_object('validation','elm_contact_v1_repeat'));
  v_repeat:=(v_result->>'addressableSubjectId')::uuid;
  if v_subject is null or v_repeat<>v_subject then raise exception 'Institution establishment is not idempotent.'; end if;
  select count(*) into v_count from atlas.addressable_subject_institution_bindings where organization_id=v_org and organization_unit_id=v_unit and binding_state='active';
  if v_count<>1 then raise exception 'Expected one active Elm binding, got %.',v_count; end if;

  v_result:=atlas.establish_external_addressable_subject_service_v1('organization',jsonb_build_object('validation','private_subject'));
  v_private:=(v_result->>'addressableSubjectId')::uuid;
  perform set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);
  v_result:=public.resolve_addressable_subject_exact_self_api_v1(v_private);
  if v_result->>'state'<>'not_found' then raise exception 'Private subject leaked through exact resolution: %.',v_result; end if;

  perform atlas.publish_addressable_subject_service_v1(v_subject,'authenticated_exact',jsonb_build_object('validation','elm_published'));
  v_result:=atlas.publish_addressable_interface_service_v1(v_subject,'contact','Contact','authenticated_exact','institutional_communication_endpoint',jsonb_build_object('validation','elm_contact'));
  v_interface:=(v_result->>'addressableInterfaceId')::uuid;
  if v_interface is null then raise exception 'Elm contact interface missing.'; end if;
  if exists(select 1 from atlas.addressable_interfaces where addressable_subject_id=v_subject and stable_key in ('visit','events','wholesale_availability')) then raise exception 'Unadmitted Elm interface was fabricated.'; end if;

  v_result:=public.resolve_addressable_subject_exact_self_api_v1(v_subject);
  if v_result->>'state'<>'resolved' or v_result->>'authorityPosition'<>'entity_authorized' or v_result?'organizationId' or v_result?'organizationUnitId' then raise exception 'Elm subject resolution crossed boundary: %.',v_result; end if;
  v_contact:=public.resolve_addressable_interface_self_api_v1(v_subject,'contact');
  if v_contact->>'state'<>'resolved' or v_contact->>'authorityPosition'<>'entity_authorized' or v_contact->'target'->>'endpointKind'<>'email' or v_contact->'target'->>'address'<>'hello@elmfarm.co' or (v_contact->'target')?'communicationEndpointId' then raise exception 'Elm contact projection is wrong: %.',v_contact; end if;

  v_result:=atlas.establish_external_addressable_subject_service_v1('organization',jsonb_build_object('validation','external_bootstrap'));
  v_external:=(v_result->>'addressableSubjectId')::uuid;
  insert into atlas.evidence_records(scope_kind,scope_id,subject_domain,subject_kind,subject_id,evidence_kind,source_kind,source_key,value,confidence,observed_at,provenance,metadata)
  values('addressable_subject',v_external,'addressability','addressable_subject',v_external::text,'external_route','validation_fixture','external_route_1',jsonb_build_object('routeKind','website','address','https://example.invalid/','label','Public website'),1,now(),jsonb_build_object('validation',true),'{}'::jsonb) returning id into v_evidence;
  perform atlas.publish_addressable_subject_service_v1(v_external,'authenticated_exact',jsonb_build_object('validation','source_backed_external'));
  v_result:=atlas.publish_addressable_interface_service_v1(v_external,'contact','Contact','authenticated_exact','source_attributed_external_route',jsonb_build_object('validation','source_route_only'));
  v_external_interface:=(v_result->>'addressableInterfaceId')::uuid;
  perform atlas.bind_addressable_interface_evidence_service_v1(v_external_interface,v_evidence,'route_evidence');
  if exists(select 1 from atlas.addressable_subject_institution_bindings where addressable_subject_id=v_external and binding_state='active') then raise exception 'External subject received institutional authority by implication.'; end if;
  v_result:=public.resolve_addressable_subject_exact_self_api_v1(v_external);
  if v_result->>'state'<>'resolved' or v_result->>'authorityPosition'<>'externally_observed' then raise exception 'External authority position wrong: %.',v_result; end if;
  v_external_contact:=public.resolve_addressable_interface_self_api_v1(v_external,'contact');
  if v_external_contact->>'state'<>'resolved' or v_external_contact->>'authorityPosition'<>'source_attributed_external' or v_external_contact->'target'->'routes'->0->>'routeKind'<>'website' or v_external_contact->'target'->'routes'->0->>'address'<>'https://example.invalid/' or (v_external_contact->'target'->'routes'->0)?'evidenceId' or (v_external_contact->'target'->'routes'->0)?'sourceKey' or (v_external_contact->'target'->'routes'->0)?'provenance' then raise exception 'External route leaked custody or lost truth: %.',v_external_contact; end if;

  v_result:=atlas.bind_addressable_subject_to_institution_service_v1(v_external,v_claim_org,v_claim_unit,jsonb_build_object('validation','later_entity_claim'));
  if (v_result->>'addressableSubjectId')::uuid<>v_external then raise exception 'Later claim replaced external subject.'; end if;
  v_result:=public.resolve_addressable_subject_exact_self_api_v1(v_external);
  if v_result->>'authorityPosition'<>'entity_authorized' then raise exception 'Later claim did not strengthen same subject: %.',v_result; end if;

  if to_regclass('atlas.addressable_subject_local_assertions') is not null then raise exception 'Universal Addressability kernel acquired Local-owned reconciliation state.'; end if;
  if exists(select 1 from pg_constraint c join pg_class s on s.oid=c.conrelid join pg_namespace sn on sn.oid=s.relnamespace join pg_class d on d.oid=c.confrelid join pg_namespace dn on dn.oid=d.relnamespace where c.contype='f' and sn.nspname='atlas' and s.relname like 'addressable_%' and dn.nspname='local_intel') then raise exception 'Addressability kernel has a Local foreign-key dependency.'; end if;

  if has_table_privilege('authenticated','atlas.addressable_subjects','SELECT') or has_table_privilege('authenticated','atlas.addressable_subject_institution_bindings','SELECT') or has_table_privilege('authenticated','atlas.addressable_interfaces','SELECT') or has_table_privilege('authenticated','atlas.addressable_interface_evidence','SELECT') then raise exception 'Authenticated role received direct Addressability table read authority.'; end if;
  if has_function_privilege('anon','public.resolve_addressable_subject_exact_self_api_v1(uuid)','EXECUTE') or has_function_privilege('anon','public.resolve_addressable_interface_self_api_v1(uuid,text)','EXECUTE') then raise exception 'Anonymous role received Resolver execution authority.'; end if;
  if not has_function_privilege('authenticated','public.resolve_addressable_subject_exact_self_api_v1(uuid)','EXECUTE') or not has_function_privilege('authenticated','public.resolve_addressable_interface_self_api_v1(uuid,text)','EXECUTE') then raise exception 'Authenticated role missing Resolver RPC authority.'; end if;
  if has_function_privilege('authenticated','atlas.establish_external_addressable_subject_service_v1(text,jsonb)','EXECUTE') or has_function_privilege('authenticated','atlas.publish_addressable_subject_service_v1(uuid,text,jsonb)','EXECUTE') or has_function_privilege('authenticated','atlas.publish_addressable_interface_service_v1(uuid,text,text,text,text,jsonb)','EXECUTE') then raise exception 'Authenticated role received service-only Addressability authority.'; end if;
  if not has_function_privilege('service_role','atlas.establish_external_addressable_subject_service_v1(text,jsonb)','EXECUTE') or not has_function_privilege('service_role','atlas.publish_addressable_subject_service_v1(uuid,text,jsonb)','EXECUTE') then raise exception 'Service role missing establishment/publication authority.'; end if;

  if not exists(select 1 from atlas.authenticated_rpc_registry r where r.signature='atlas.resolve_addressable_subject_exact_self_api_v1(p_addressable_subject_id uuid)' and r.classification='app_endpoint' and r.review_status='active' and r.authenticated_execute_expected and not r.anonymous_execute_expected and r.security_definer_expected and r.service_execute_expected and coalesce((r.evidence->>'subjectDefaultPrivate')::boolean,false) and not coalesce((r.evidence->>'localIntelAuthority')::boolean,true)) then raise exception 'Exact Resolver governance registration incomplete.'; end if;
  if not exists(select 1 from atlas.authenticated_rpc_registry r where r.signature='atlas.resolve_addressable_interface_self_api_v1(p_addressable_subject_id uuid, p_interface_key text)' and r.classification='app_endpoint' and r.review_status='active' and r.authenticated_execute_expected and not r.anonymous_execute_expected and r.security_definer_expected and r.service_execute_expected and not coalesce((r.evidence->>'providerCredentialExposure')::boolean,true) and coalesce((r.evidence->>'boundedResolverKinds')::boolean,false)) then raise exception 'Interface Resolver governance registration incomplete.'; end if;

  raise notice 'Atlas Addressability + Resolver Kernel v1 postconditions passed.';
end;$proof$;
ROLLBACK;
