create or replace function public.composition_shadow_local_context_v1(
  p_organization_key text,
  p_lens_key text,
  p_request_envelope jsonb,
  p_query text,
  p_retrieval_expansions text[],
  p_city text default null,
  p_date_start date default null,
  p_date_end date default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v_org_id uuid;
  v_validation jsonb;
  v_envelope_result jsonb;
  v_shadow_run_id uuid;
  v_signals jsonb;
  v_derivation jsonb;
  v_signal_envelope jsonb;
  v_explicit jsonb := '{}'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_fact jsonb;
  v_inference jsonb;
  v_delegated boolean := false;
  v_start timestamptz;
  v_end timestamptz;
begin
  select id into v_org_id from atlas.organizations where stable_key=p_organization_key and status='active' limit 1;
  if v_org_id is null then raise exception 'active organization not found'; end if;

  v_validation:=atlas.validate_composition_request_envelope_v1(p_request_envelope);
  v_envelope_result:=atlas.submit_composition_request_envelope_v1(
    v_org_id,'elm_local','shadow_runtime', 'gateway_structured_interpreter','v1',p_request_envelope
  );
  if v_validation->>'validation_state'<>'passed' then
    return jsonb_build_object('ok',false,'stage','request_envelope','validation',v_validation,'request_envelope_result',v_envelope_result);
  end if;

  for v_fact in select value from jsonb_array_elements(coalesce(p_request_envelope->'fact_items','[]'::jsonb)) loop
    v_explicit:=v_explicit||jsonb_build_object(v_fact->>'key',v_fact->'value');
    v_constraints:=v_constraints||jsonb_build_array(jsonb_build_object('key',v_fact->>'key','value',v_fact->'value','source','validated_request_envelope'));
  end loop;
  for v_inference in select value from jsonb_array_elements(coalesce(p_request_envelope->'inferred_items','[]'::jsonb)) loop
    if v_inference->>'key'='delegated_composition' and v_inference->'value'='true'::jsonb then v_delegated:=true; end if;
  end loop;
  v_explicit:=v_explicit||jsonb_build_object('constraints',v_constraints);
  v_signal_envelope:=jsonb_build_object(
    'literal_request',p_request_envelope->>'literal_request',
    'request_mode',p_request_envelope->>'request_mode',
    'delegated_composition',v_delegated,
    'parser_version','validated_request_envelope_v1',
    'explicit_facts',v_explicit
  );

  if p_date_start is not null then v_start:=(p_date_start::timestamp at time zone 'America/Chicago'); end if;
  if p_date_end is not null then v_end:=((p_date_end+1)::timestamp at time zone 'America/Chicago'); end if;

  v_shadow_run_id:=local_intel.start_recommendation_shadow_run_v2(
    v_org_id,p_lens_key,coalesce(nullif(p_query,''),p_request_envelope->>'literal_request'),
    jsonb_build_object('request_envelope_id',v_envelope_result->>'request_envelope_id','authority','retrieval_context_only'),
    coalesce(p_retrieval_expansions,array[]::text[]),array['entity','offering','occurrence']::text[],p_city,
    v_start,v_end,15,60
  );
  if v_start is not null and v_end is not null then
    perform local_intel.add_recommendation_shadow_time_window_candidates_v1(v_shadow_run_id,p_city,v_start,v_end,60);
  end if;

  v_signals:=local_intel.get_composition_signals_v2(v_shadow_run_id,v_signal_envelope);
  v_derivation:=atlas.start_shadow_composition_derivation_v1(
    v_org_id,'elm_local','recommendation_shadow_run:'||v_shadow_run_id::text,
    v_signal_envelope,v_signals,'real_life_composition_v1',1
  );

  return jsonb_build_object(
    'ok',true,'organization_id',v_org_id,'request_envelope_result',v_envelope_result,
    'recommendation_shadow_run_id',v_shadow_run_id,'signals',v_signals,'derivation',v_derivation
  );
end;
$$;

create or replace function public.composition_shadow_worker_context_v1(
  p_organization_key text,
  p_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v_org_id uuid;
  v_signals jsonb;
  v_envelope jsonb;
  v_derivation jsonb;
begin
  select id into v_org_id from atlas.organizations where stable_key=p_organization_key and status='active' limit 1;
  if v_org_id is null then raise exception 'active organization not found'; end if;
  v_signals:=atlas.get_worker_day_composition_signals_v4(p_membership_id,p_service_date);
  v_envelope:=jsonb_build_object(
    'request_key','worker_day:'||p_membership_id::text||':'||p_service_date::text,
    'literal_request','Compose worker day from Atlas truth for '||p_service_date::text||'.',
    'request_mode','operational_day_composition','delegated_composition',false,
    'parser_version','system_operational_request_v1',
    'explicit_facts',jsonb_build_object('service_date',p_service_date)
  );
  v_derivation:=atlas.start_shadow_composition_derivation_v1(
    v_org_id,'atlas_worker_day','membership:'||p_membership_id::text||':date:'||p_service_date::text,
    v_envelope,v_signals,'real_life_composition_v1',1
  );
  return jsonb_build_object('ok',true,'organization_id',v_org_id,'signals',v_signals,'derivation',v_derivation);
end;
$$;

create or replace function public.composition_shadow_submit_proposal_v1(
  p_derivation_id uuid,
  p_proposal_key text,
  p_generator_kind text,
  p_generator_version text,
  p_proposal jsonb
) returns jsonb
language sql
security definer
set search_path=pg_catalog
as $$
  select atlas.submit_shadow_composition_proposal_v2(p_derivation_id,p_proposal_key,p_generator_kind,p_generator_version,p_proposal)
$$;

revoke all on function public.composition_shadow_local_context_v1(text,text,jsonb,text,text[],text,date,date) from public,anon,authenticated;
revoke all on function public.composition_shadow_worker_context_v1(text,uuid,date) from public,anon,authenticated;
revoke all on function public.composition_shadow_submit_proposal_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.composition_shadow_local_context_v1(text,text,jsonb,text,text[],text,date,date) to service_role;
grant execute on function public.composition_shadow_worker_context_v1(text,uuid,date) to service_role;
grant execute on function public.composition_shadow_submit_proposal_v1(uuid,text,text,text,jsonb) to service_role;