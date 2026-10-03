-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: refresh must preserve paired geography dispatch.

create or replace function atlas.refresh_contact_set_execution_after_acquisition_service_v1(
  p_execution_run_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  v_run atlas.contact_set_execution_runs%rowtype;
  v_request atlas.contact_set_intent_requests%rowtype;
  v_directory jsonb;
  v_gaps jsonb;
  v_gap jsonb;
  v_desired integer;
  v_selected integer;
  v_population_gap boolean;
  v_unattempted integer:=0;
  v_state text;
  v_attach boolean;
  v_role_key text;
  v_item jsonb;
  v_attach_result jsonb;
  v_ledger_results jsonb:='[]'::jsonb;
  v_geography_mode text;
  v_resolved_geography jsonb;
begin
  select * into v_run
  from atlas.contact_set_execution_runs r
  where r.id=p_execution_run_id
  for update;
  if v_run.id is null then raise exception 'Contact-set execution run not found.' using errcode='P0002'; end if;

  select * into v_request
  from atlas.contact_set_intent_requests r
  where r.id=v_run.request_id;
  if v_request.id is null or v_request.request_state<>'ready' then
    raise exception 'Ready contact-set intent request is required.' using errcode='23514';
  end if;

  v_geography_mode:=nullif(btrim(v_request.interpretation#>>'{geography,mode}'),'');
  if v_geography_mode='paired_operating_presence' then
    v_resolved_geography:=atlas.resolve_paired_operating_geography_service_v1(v_request.interpretation->'geography');
    if v_resolved_geography->>'state'='resolved' then
      v_directory:=atlas.shared_directory_paired_operating_presence_search_service_v1(
        v_run.organization_id,v_request.interpretation->'target',v_resolved_geography,
        v_run.required_fields,least(200,greatest(50,coalesce(v_run.desired_count,20)*5))
      );
    else
      v_directory:=jsonb_build_object(
        'contractVersion','shared_directory_paired_operating_presence_pending_geography_v1',
        'organizationId',v_run.organization_id,'target',v_request.interpretation->'target',
        'geography',v_resolved_geography,'requiredFields',to_jsonb(v_run.required_fields),
        'candidateCount',0,'completeCandidateCount',0,'items','[]'::jsonb,
        'researchTargets',coalesce(v_resolved_geography->'researchTargets','[]'::jsonb),
        'qualificationStage','organization','retrievalPolicy','canonical_paired_operating_presence_first',
        'communicationAuthorized',false
      );
    end if;
  else
    v_directory:=atlas.shared_directory_target_search_service_v1(
      v_run.organization_id,v_request.interpretation->'target',v_request.interpretation->'geography',
      v_run.required_fields,least(200,greatest(50,coalesce(v_run.desired_count,20)*5))
    );
  end if;

  v_selected:=coalesce((v_directory->>'candidateCount')::integer,0);
  v_desired:=v_run.desired_count;
  v_population_gap:=v_desired is not null and v_selected<v_desired;
  v_gaps:=coalesce(v_directory->'researchTargets','[]'::jsonb);

  if v_population_gap then
    if v_geography_mode='paired_operating_presence' and v_resolved_geography->>'state'='resolved' then
      v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object(
        'gapKind','paired_operating_presence_gap','desiredCount',v_desired,'supportedCount',v_selected,
        'missingCount',v_desired-v_selected,'geography',v_resolved_geography,
        'target',v_request.interpretation->'target',
        'reason','Canonical Reality does not yet establish enough same-root operating/spatial proofs across both Place sets.'
      ));
    elsif v_geography_mode is distinct from 'paired_operating_presence' then
      v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object(
        'gapKind','population_gap','desiredCount',v_desired,'supportedCount',v_selected,
        'missingCount',v_desired-v_selected,
        'reason','The existing canonical directory does not yet support the requested population size.'
      ));
    end if;
  end if;

  for v_gap in select value from jsonb_array_elements(v_gaps)
  loop
    if not exists(
      select 1 from atlas.contact_set_acquisition_attempts a
      where a.execution_run_id=v_run.id
        and a.gap_fingerprint=md5(v_gap::text)
        and a.status='complete'
    ) then
      v_unattempted:=v_unattempted+1;
    end if;
  end loop;

  v_attach:=lower(coalesce(v_request.interpretation#>>'{ledgerEffect,attachToLedger}','false')) in ('true','1','yes');
  v_role_key:=coalesce(nullif(lower(btrim(v_request.interpretation#>>'{ledgerEffect,roleKey}')),''),'contact');
  if v_attach then
    for v_item in select value from jsonb_array_elements(coalesce(v_directory->'items','[]'::jsonb))
    loop
      v_attach_result:=atlas.attach_shared_directory_entity_service_v1(
        v_run.organization_id,(v_item->>'entityId')::uuid,v_role_key,v_run.organization_unit_id
      );
      v_ledger_results:=v_ledger_results||jsonb_build_array(jsonb_build_object(
        'entityId',v_item->>'entityId','roleKey',v_role_key,'result',v_attach_result
      ));
    end loop;
  end if;

  v_state:=case
    when jsonb_array_length(v_gaps)=0 then 'ready'
    when v_unattempted>0 then 'needs_acquisition'
    else 'partial'
  end;

  update atlas.contact_set_execution_runs
  set execution_state=v_state,
      selected_count=v_selected,
      directory_snapshot=v_directory,
      gap_snapshot=jsonb_build_object(
        'contractVersion','contact_set_gap_snapshot_v1','researchTargets',v_gaps,
        'gapCount',jsonb_array_length(v_gaps),'populationGap',v_population_gap,
        'unattemptedGapCount',v_unattempted,'geographyMode',v_geography_mode
      ),
      ledger_effect_snapshot=jsonb_build_object(
        'attachToLedger',v_attach,'roleKey',case when v_attach then v_role_key else null end,
        'results',v_ledger_results,'communicationAuthorized',false
      ),
      updated_at=now()
  where id=v_run.id
  returning * into v_run;

  return jsonb_build_object(
    'ok',true,'contractVersion','contact_set_execution_refresh_v2',
    'runId',v_run.id,'requestId',v_run.request_id,'executionState',v_run.execution_state,
    'selectedCount',v_run.selected_count,'directory',v_run.directory_snapshot,
    'gaps',v_run.gap_snapshot,'ledgerEffects',v_run.ledger_effect_snapshot,
    'truthBoundary',jsonb_build_object(
      'sharedIntelligenceMutation',false,'externalResearchExecuted',false,'communicationAuthorized',false,
      'pairedQualificationUsesCanonicalReality',v_geography_mode='paired_operating_presence'
    )
  );
end
$function$;

revoke all on function atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.refresh_contact_set_execution_after_acquisition_service_v1(uuid) to service_role;
