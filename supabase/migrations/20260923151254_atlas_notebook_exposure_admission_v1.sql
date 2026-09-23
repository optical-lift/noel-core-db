-- Atlas Notebook Exposure Admission v1 candidate.
-- Read-only Index + direct NotebookAddress admission over Domain Exposure.
-- Candidate only: no migration identity and no production authority.

begin;

create or replace function atlas.notebook_index_admitted_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_exposure jsonb;
  v_spreads jsonb;
  v_items jsonb := '[]'::jsonb;
  v_spread jsonb;
  v_eval jsonb;
  v_key text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_index_admitted_self_v1',
      'state','domain_exposure_dependency_unavailable',
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'carrierExistenceDoesNotGrantEncounter',true,
        'indexDoesNotGrantSourceAuthority',true,
        'hiddenCarrierEnumerationSuppressed',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  execute 'select atlas.domain_exposure_evaluations_self_api_v1()'
    into v_exposure;

  if coalesce(v_exposure->>'state','') <> 'ready' then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_index_admitted_self_v1',
      'state',coalesce(v_exposure->>'state','unresolved'),
      'items','[]'::jsonb,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'carrierExistenceDoesNotGrantEncounter',true,
        'indexDoesNotGrantSourceAuthority',true,
        'hiddenCarrierEnumerationSuppressed',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  v_spreads := atlas.notebook_spread_instances_self_api_v1();

  v_items := jsonb_build_array(
    jsonb_build_object(
      'addressKind','today',
      'spreadKey','today',
      'templateKey','today',
      'title','Today',
      'section','Notebook'
    ),
    jsonb_build_object(
      'addressKind','index',
      'spreadKey','index',
      'templateKey','index',
      'title','Index',
      'section','Notebook'
    )
  );

  for v_spread in
    select value
    from jsonb_array_elements(coalesce(v_spreads->'items','[]'::jsonb))
  loop
    v_key := nullif(v_spread->>'spreadKey','');
    if v_key is null then
      continue;
    end if;

    select value
      into v_eval
    from jsonb_array_elements(coalesce(v_exposure->'items','[]'::jsonb))
    where value->'place'->>'durabilityKey'=v_key
    limit 1;

    if v_eval is null then
      continue;
    end if;

    if v_eval->'encounter'->>'state' <> 'eligible'
       or v_eval->'place'->>'disposition' not in ('stable','transient')
       or v_eval->'index'->>'disposition' <> 'listed'
       or jsonb_typeof(v_eval->'sourceBinding') <> 'object'
       or nullif(v_eval->'sourceBinding'->>'governedRead','') is null then
      continue;
    end if;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'addressKind','spread',
      'spreadKey',v_key,
      'templateKey','composed',
      'title',v_spread->>'title',
      'section',v_spread->>'sectionKey',
      'scope',v_spread->'scope',
      'subject',v_spread->'subject',
      'spreadInstanceId',v_spread->>'spreadInstanceId',
      'spreadState',v_spread->>'spreadState',
      'threadKey',v_spread->>'threadKey',
      'recipeKey',v_spread->>'recipeKey',
      'purposeKey',v_spread->>'purposeKey',
      'horizonKey',v_spread->>'horizonKey',
      'exposureContractKey',v_eval->>'contractKey'
    ));
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_index_admitted_self_v1',
    'state','ready',
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'indexIsRetrievalProjection',true,
      'carrierExistenceDoesNotGrantEncounter',true,
      'indexDispositionComesFromDomainExposure',true,
      'quietIsNotAdvertised',true,
      'absentAndUnresolvedAreNotEnumerated',true,
      'indexDoesNotGrantSourceAuthority',true,
      'hiddenCarrierEnumerationSuppressed',true,
      'notebookMutationAuthorized',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

comment on function atlas.notebook_index_admitted_self_api_v1() is
  'Person-relative notebook Index read governed by Domain Exposure. Returns only system addresses plus listed durable places; quiet/absent/unresolved carriers are not enumerated and source authority remains separate.';

revoke all on function atlas.notebook_index_admitted_self_api_v1()
  from public, anon;
grant execute on function atlas.notebook_index_admitted_self_api_v1()
  to authenticated;

create or replace function atlas.notebook_address_admitted_self_api_v1(
  p_spread_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, atlas, auth
as $function$
declare
  v_uid uuid := auth.uid();
  v_key text := nullif(btrim(p_spread_key),'');
  v_exposure jsonb;
  v_eval jsonb;
  v_raw jsonb;
  v_index_disposition text;
  v_source_read text;
begin
  if v_uid is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  if v_key is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  if v_key in ('today','index') then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','notebook_address_admitted_self_v1',
      'state','system',
      'spreadKey',v_key,
      'indexDisposition','listed',
      'spread',null,
      'sourceRead',null,
      'truthBoundary',jsonb_build_object(
        'readOnly',true,
        'systemAddress',true,
        'addressAdmissionDoesNotGrantSourceAuthority',true,
        'notebookMutationAuthorized',false
      )
    );
  end if;

  if to_regprocedure('atlas.domain_exposure_evaluations_self_api_v1()') is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  execute 'select atlas.domain_exposure_evaluations_self_api_v1()'
    into v_exposure;

  if coalesce(v_exposure->>'state','') <> 'ready' then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  select value
    into v_eval
  from jsonb_array_elements(coalesce(v_exposure->'items','[]'::jsonb))
  where value->'place'->>'durabilityKey'=v_key
  limit 1;

  if v_eval is null
     or v_eval->'encounter'->>'state' <> 'eligible'
     or v_eval->'place'->>'disposition' not in ('stable','transient')
     or v_eval->'index'->>'disposition' not in ('listed','quiet')
     or jsonb_typeof(v_eval->'sourceBinding') <> 'object'
     or nullif(v_eval->'sourceBinding'->>'governedRead','') is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  v_index_disposition := v_eval->'index'->>'disposition';
  v_source_read := v_eval->'sourceBinding'->>'governedRead';

  begin
    v_raw := atlas.notebook_spread_instance_self_api_v1(v_key);
  exception
    when no_data_found then
      raise exception 'Notebook address not found.' using errcode='P0002';
  end;

  if v_raw is null or v_raw->'spread' is null then
    raise exception 'Notebook address not found.' using errcode='P0002';
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','notebook_address_admitted_self_v1',
    'state',case when v_index_disposition='quiet' then 'quiet' else 'listed' end,
    'spreadKey',v_key,
    'indexDisposition',v_index_disposition,
    'spread',v_raw->'spread',
    'sourceBindings',v_raw->'sourceBindings',
    'latestCompositionRevision',v_raw->'latestCompositionRevision',
    'sourceRead',v_source_read,
    'exposureContractKey',v_eval->>'contractKey',
    'truthBoundary',jsonb_build_object(
      'readOnly',true,
      'carrierExistenceDoesNotGrantEncounter',true,
      'listedAndQuietMayResolveDirectly',true,
      'quietDoesNotAuthorizeIndexAdvertisement',true,
      'absentAndUnresolvedAreIndistinguishableFromNotFound',true,
      'addressAdmissionDoesNotGrantSourceAuthority',true,
      'sourceReadMustAuthorizeSeparately',true,
      'rawSpreadReaderIsTransitionalDependency',true,
      'notebookMutationAuthorized',false,
      'todayPlacementAuthorized',false,
      'actionAuthorityGranted',false
    )
  );
end;
$function$;

comment on function atlas.notebook_address_admitted_self_api_v1(text) is
  'Person-relative durable NotebookAddress resolver governed by Domain Exposure. Listed and quiet addresses may resolve; absent/unresolved/unmapped carriers fail closed as not-found. Source read authority remains separate.';

revoke all on function atlas.notebook_address_admitted_self_api_v1(text)
  from public, anon;
grant execute on function atlas.notebook_address_admitted_self_api_v1(text)
  to authenticated;

commit;
