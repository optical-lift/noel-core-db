begin;

do $validation$
declare
  v_org uuid:='f0000000-0000-4000-8000-000000000101'::uuid;
  v_entity uuid:='f0000000-0000-4000-8000-000000000103'::uuid;
  v_search jsonb;
  v_attach jsonb;
  v_related jsonb;
  v_rel uuid;
  v_interaction jsonb;
  v_after jsonb;
  v_duplicate_count bigint;
begin
  if to_regprocedure('atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer)') is null then
    raise exception 'shared_directory_search_service_v1 is missing';
  end if;
  if to_regprocedure('atlas.attach_shared_directory_entity_service_v1(uuid,uuid,text,uuid)') is null then
    raise exception 'attach_shared_directory_entity_service_v1 is missing';
  end if;
  if to_regprocedure('atlas.record_shared_directory_interaction_service_v1(uuid,uuid,text,timestamptz,text,text,text,text,text,jsonb)') is null then
    raise exception 'record_shared_directory_interaction_service_v1 is missing';
  end if;

  if not exists(
    select 1 from pg_indexes
    where schemaname='atlas'
      and indexname='identity_subject_external_identifiers_local_intel_entity_org_uq'
      and indexdef ilike '%provider_key = ''local_intel''%'
  ) then
    raise exception 'Shared Intelligence Organization/entity uniqueness index is missing';
  end if;

  select count(*) into v_duplicate_count
  from (
    select organization_id,identifier_normalized
    from atlas.identity_subject_external_identifiers
    where is_current and provider_key='local_intel' and identifier_type='entity_id'
    group by organization_id,identifier_normalized
    having count(distinct subject_id)>1
  ) q;
  if v_duplicate_count<>0 then
    raise exception 'Duplicate Organization bindings exist for canonical Shared Intelligence entities';
  end if;

  v_search:=atlas.shared_directory_search_service_v1(v_org,'Validation Shared Directory Buyer',false,null,10);
  if jsonb_array_length(v_search->'items')<>1 then
    raise exception 'Universal Shared Directory search did not find the canonical fixture entity';
  end if;
  if (v_search#>>'{items,0,entityId}')::uuid<>v_entity then
    raise exception 'Shared Directory returned the wrong canonical entity id';
  end if;
  if coalesce((v_search#>>'{items,0,overlay,isRelated}')::boolean,false) then
    raise exception 'Fixture entity should not begin related to validation Organization';
  end if;

  v_attach:=atlas.attach_shared_directory_entity_service_v1(v_org,v_entity,'buyer',null);
  if (v_attach->>'state') not in ('resolved','resolved_with_identifier_conflict') then
    raise exception 'Attach did not resolve canonical entity into Organization relationship: %',v_attach;
  end if;
  if (v_attach->>'sharedEntityId')::uuid<>v_entity then
    raise exception 'Attach changed canonical Shared Intelligence entity identity';
  end if;
  v_rel:=(v_attach->>'externalRelationshipId')::uuid;
  if v_rel is null then
    raise exception 'Attach did not create or resolve an Atlas external relationship';
  end if;

  v_related:=atlas.shared_directory_search_service_v1(v_org,null,true,'buyer',10);
  if not exists(
    select 1
    from jsonb_array_elements(v_related->'items') item
    where (item->>'entityId')::uuid=v_entity
      and coalesce((item#>>'{overlay,isRelated}')::boolean,false)
      and (item#>'{overlay,roleKeys}') ? 'buyer'
  ) then
    raise exception 'Related-only buyer projection did not compose canonical identity with private Organization role';
  end if;

  v_interaction:=atlas.record_shared_directory_interaction_service_v1(
    v_org,v_rel,'call',now(),'phone','receptive','Validation Contact','Call next week',
    'Organization-private validation note','{"validationFixture":true}'::jsonb
  );
  if (v_interaction->>'externalRelationshipId')::uuid<>v_rel then
    raise exception 'Interaction writer returned wrong relationship';
  end if;

  v_after:=atlas.shared_directory_search_service_v1(v_org,'Validation Shared Directory Buyer',true,'buyer',10);
  if v_after#>>'{items,0,overlay,relationships,0,latestInteraction,note}'<>'Organization-private validation note' then
    raise exception 'Private Organization interaction note did not project through Ledger overlay';
  end if;

  if not has_function_privilege('authenticated','atlas.shared_directory_search_self_api_v1(uuid,text,boolean,text,integer)','EXECUTE') then
    raise exception 'Authenticated role cannot execute Shared Directory self read';
  end if;
  if has_function_privilege('anon','atlas.shared_directory_search_self_api_v1(uuid,text,boolean,text,integer)','EXECUTE') then
    raise exception 'Anon unexpectedly has Shared Directory self read execution';
  end if;
  if has_function_privilege('authenticated','atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer)','EXECUTE') then
    raise exception 'Authenticated role unexpectedly has direct Shared Directory service execution';
  end if;
  if not has_function_privilege('service_role','atlas.shared_directory_search_service_v1(uuid,text,boolean,text,integer)','EXECUTE') then
    raise exception 'Service role lacks Shared Directory service execution';
  end if;
end;
$validation$;

rollback;
