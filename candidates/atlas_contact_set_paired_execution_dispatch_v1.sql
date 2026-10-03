-- ATLAS_CONTACT_SET_PAIRED_GEOGRAPHY_V1: execution dispatch without changing ordinary local search semantics.

create or replace function atlas.prepare_contact_set_execution_service_v1(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path to 'pg_catalog','atlas','local_intel'
as $function$
declare
  r atlas.contact_set_intent_requests%rowtype;
  v_existing atlas.contact_set_execution_runs%rowtype;
  v_required text[];
  v_desired integer;
  v_limit integer;
  v_directory jsonb;
  v_gaps jsonb;
  v_selected integer;
  v_population_gap boolean;
  v_state text;
  v_attach boolean;
  v_role_key text;
  v_ledger_results jsonb:='[]'::jsonb;
  v_item jsonb;
  v_attach_result jsonb;
  v_run atlas.contact_set_execution_runs%rowtype;
  v_geography_mode text;
  v_resolved_geography jsonb;
begin
  select * into r from atlas.contact_set_intent_requests x where x.id=p_request_id;
  if r.id is null then raise exception 'Contact-set intent request not found.' using errcode='P0002'; end if;
  if r.request_state<>'ready' or r.interpretation is null then raise exception 'Contact-set request must be ready before execution preparation.' using errcode='22023'; end if;

  select * into v_existing from atlas.contact_set_execution_runs e where e.request_id=r.id;
  if v_existing.id is not null then
    return jsonb_build_object('ok',true,'changed',false,'contractVersion','contact_set_execution_preparation_v1','runId',v_existing.id,'requestId',v_existing.request_id,'executionState',v_existing.execution_state,'directory',v_existing.directory_snapshot,'gaps',v_existing.gap_snapshot,'ledgerEffects',v_existing.ledger_effect_snapshot);
  end if;

  select coalesce(array_agg(lower(btrim(x))) filter(where btrim(x)<>''),'{}'::text[]) into v_required from jsonb_array_elements_text(coalesce(r.interpretation#>'{fields,required}','[]'::jsonb)) x;
  if cardinality(v_required)=0 then raise exception 'Ready contact-set request has no required fields.' using errcode='23514'; end if;
  begin v_desired:=nullif(r.interpretation#>>'{population,desiredCount}','')::integer;
  exception when invalid_text_representation then raise exception 'Contact-set desired count is invalid.' using errcode='23514'; end;
  v_limit:=least(200,greatest(50,coalesce(v_desired,20)*5));
  v_geography_mode:=nullif(btrim(r.interpretation#>>'{geography,mode}'),'');

  if v_geography_mode='paired_operating_presence' then
    v_resolved_geography:=atlas.resolve_paired_operating_geography_service_v1(r.interpretation->'geography');
    if v_resolved_geography->>'state'='resolved' then
      v_directory:=atlas.shared_directory_paired_operating_presence_search_service_v1(r.organization_id,r.interpretation->'target',v_resolved_geography,v_required,v_limit);
    else
      v_directory:=jsonb_build_object(
        'contractVersion','shared_directory_paired_operating_presence_pending_geography_v1',
        'organizationId',r.organization_id,'target',r.interpretation->'target','geography',v_resolved_geography,
        'requiredFields',to_jsonb(v_required),'candidateCount',0,'completeCandidateCount',0,'items','[]'::jsonb,
        'researchTargets',coalesce(v_resolved_geography->'researchTargets','[]'::jsonb),
        'qualificationStage','organization','retrievalPolicy','canonical_paired_operating_presence_first','communicationAuthorized',false
      );
    end if;
  else
    v_directory:=atlas.shared_directory_target_search_service_v1(r.organization_id,r.interpretation->'target',r.interpretation->'geography',v_required,v_limit);
  end if;

  v_selected:=coalesce((v_directory->>'candidateCount')::integer,0);
  v_population_gap:=v_desired is not null and v_selected<v_desired;
  v_gaps:=coalesce(v_directory->'researchTargets','[]'::jsonb);

  if v_population_gap then
    if v_geography_mode='paired_operating_presence' and v_resolved_geography->>'state'='resolved' then
      v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object(
        'gapKind','paired_operating_presence_gap','desiredCount',v_desired,'supportedCount',v_selected,'missingCount',v_desired-v_selected,
        'geography',v_resolved_geography,'target',r.interpretation->'target',
        'reason','Canonical Reality does not yet establish enough same-root operating/spatial proofs across both Place sets.'
      ));
    elsif v_geography_mode is distinct from 'paired_operating_presence' then
      v_gaps:=v_gaps||jsonb_build_array(jsonb_build_object('gapKind','population_gap','desiredCount',v_desired,'supportedCount',v_selected,'missingCount',v_desired-v_selected,'reason','The existing canonical directory does not yet support the requested population size.'));
    end if;
  end if;

  v_attach:=lower(coalesce(r.interpretation#>>'{ledgerEffect,attachToLedger}','false')) in ('true','1','yes');
  v_role_key:=coalesce(nullif(lower(btrim(r.interpretation#>>'{ledgerEffect,roleKey}')),''),'contact');
  if v_role_key !~ '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$' then raise exception 'Interpreted Ledger role key is invalid.' using errcode='23514'; end if;

  if v_attach then
    for v_item in select value from jsonb_array_elements(coalesce(v_directory->'items','[]'::jsonb)) loop
      v_attach_result:=atlas.attach_shared_directory_entity_service_v1(r.organization_id,(v_item->>'entityId')::uuid,v_role_key,r.organization_unit_id);
      v_ledger_results:=v_ledger_results||jsonb_build_array(jsonb_build_object('entityId',v_item->>'entityId','roleKey',v_role_key,'result',v_attach_result));
    end loop;
  end if;

  v_state:=case when jsonb_array_length(v_gaps)>0 then 'needs_acquisition' else 'ready' end;
  insert into atlas.contact_set_execution_runs(request_id,organization_id,organization_unit_id,execution_state,required_fields,desired_count,selected_count,directory_snapshot,gap_snapshot,ledger_effect_snapshot)
  values(
    r.id,r.organization_id,r.organization_unit_id,v_state,v_required,v_desired,v_selected,v_directory,
    jsonb_build_object('contractVersion','contact_set_gap_snapshot_v1','researchTargets',v_gaps,'gapCount',jsonb_array_length(v_gaps),'populationGap',v_population_gap,'geographyMode',v_geography_mode),
    jsonb_build_object('attachToLedger',v_attach,'roleKey',case when v_attach then v_role_key else null end,'results',v_ledger_results,'communicationAuthorized',false)
  ) returning * into v_run;

  return jsonb_build_object(
    'ok',true,'changed',true,'contractVersion','contact_set_execution_preparation_v1','runId',v_run.id,'requestId',v_run.request_id,'executionState',v_run.execution_state,
    'directory',v_run.directory_snapshot,'gaps',v_run.gap_snapshot,'ledgerEffects',v_run.ledger_effect_snapshot,
    'truthBoundary',jsonb_build_object('sharedIntelligenceMutation',false,'externalResearchExecuted',false,'communicationAuthorized',false,'privateLedgerAttachmentOnly',v_attach,'pairedQualificationUsesCanonicalReality',v_geography_mode='paired_operating_presence')
  );
end
$function$;
