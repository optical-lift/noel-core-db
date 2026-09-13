begin;

-- Connections is durable notebook orientation, not source authority. Connected
-- source coverage may change question priority, but it never resolves a life
-- signal or becomes canonical truth merely because a source exists.

update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'sourceCoverageKeys', jsonb_build_array('communication_capture'),
      'sourceCoveragePenalty', 45
    ),
    updated_at = now()
where question_key='household.people_shape';

create or replace function atlas.reality_discovery_source_coverage_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_sources jsonb := '[]'::jsonb;
  v_keys jsonb := '[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  with eligible_sources as (
    select source_id,provider_key,display_label,account_hint,authorization_state,
           capabilities,last_sync_at
    from atlas.connected_sources_self_api_v1()
    where authorization_state='connected'
      and last_sync_at is not null
  )
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'sourceId',source_id,
           'providerKey',provider_key,
           'displayLabel',display_label,
           'accountHint',account_hint,
           'authorizationState',authorization_state,
           'capabilities',capabilities,
           'lastSyncAt',last_sync_at
         )) order by provider_key,source_id),'[]'::jsonb)
  into v_sources
  from eligible_sources;

  with eligible_sources as (
    select capabilities
    from atlas.connected_sources_self_api_v1()
    where authorization_state='connected'
      and last_sync_at is not null
  ), coverage_keys as (
    select 'communication_capture'::text as coverage_key
    from eligible_sources
    where coalesce(capabilities->>'communicationCapture','false')='true'
    group by 1
  )
  select coalesce(jsonb_agg(coverage_key order by coverage_key),'[]'::jsonb)
  into v_keys
  from coverage_keys;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_source_coverage_self_api_v1',
    'principalId',v_principal_id,
    'keys',v_keys,
    'sources',v_sources,
    'truthBoundary',jsonb_build_object(
      'connectionIsNotLifeFact',true,
      'coverageMayReorderQuestions',true,
      'coverageDoesNotResolveSignals',true,
      'sourceEvidenceStillRequiresAdjudication',true,
      'pendingOrUnsyncedSourcesDoNotAffectRanking',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_source_coverage_self_api_v1() from public,anon;
grant execute on function atlas.reality_discovery_source_coverage_self_api_v1() to authenticated,service_role;

create or replace function atlas.reality_discovery_next_question_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_source_coverage jsonb;
  v_signals jsonb;
  v_answers jsonb;
  v_question record;
begin
  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_source_coverage:=atlas.reality_discovery_source_coverage_self_api_v1();
  v_context:=v_context||jsonb_build_object('sourceCoverage',v_source_coverage);
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);
  v_answers:=coalesce(v_context->'answers','{}'::jsonb);

  with edge_eval as (
    select q.question_key,e.effect_kind,e.weight,
      atlas.reality_discovery_edge_matches_v1(v_signals->e.signal_key,e.operator,e.compare_value) as matched,
      e.reason_text
    from atlas.reality_discovery_questions q
    left join atlas.reality_discovery_edges e on e.question_key=q.question_key
    where q.active
  ), scored as (
    select q.*,
      case
        when jsonb_typeof(q.metadata->'sourceCoverageKeys')='array'
         and exists (
           select 1
           from jsonb_array_elements_text(q.metadata->'sourceCoverageKeys') requested(coverage_key)
           where coalesce(v_source_coverage->'keys','[]'::jsonb) ? requested.coverage_key
         )
         and (
           q.resolved_signal_key is null
           or not (coalesce(v_context->'candidateEvidence','{}'::jsonb) ? q.resolved_signal_key)
         )
        then greatest(0,coalesce(nullif(q.metadata->>'sourceCoveragePenalty','')::integer,0))
        else 0
      end as source_coverage_penalty,
      (q.base_score+q.consequence_value+q.information_gain-q.friction
       +coalesce(sum(e.weight) filter(where e.effect_kind='boost' and e.matched),0)
       -case
          when jsonb_typeof(q.metadata->'sourceCoverageKeys')='array'
           and exists (
             select 1
             from jsonb_array_elements_text(q.metadata->'sourceCoverageKeys') requested(coverage_key)
             where coalesce(v_source_coverage->'keys','[]'::jsonb) ? requested.coverage_key
           )
           and (
             q.resolved_signal_key is null
             or not (coalesce(v_context->'candidateEvidence','{}'::jsonb) ? q.resolved_signal_key)
           )
          then greatest(0,coalesce(nullif(q.metadata->>'sourceCoveragePenalty','')::integer,0))
          else 0
        end)::integer as score,
      coalesce(bool_and(e.matched) filter(where e.effect_kind='require'),true) as requirements_met,
      coalesce(bool_or(e.matched) filter(where e.effect_kind='suppress'),false) as suppressed,
      coalesce(jsonb_agg(e.reason_text) filter(where e.effect_kind='boost' and e.matched and e.reason_text is not null),'[]'::jsonb) as matched_reasons
    from atlas.reality_discovery_questions q
    left join edge_eval e on e.question_key=q.question_key
    where q.active
    group by q.question_key
  )
  select * into v_question
  from scored s
  where s.requirements_met
    and not s.suppressed
    and not (v_answers ? s.question_key)
    and not (
      coalesce((s.metadata->>'requiresCandidate')::boolean,false)
      and coalesce(v_signals->(s.metadata->>'candidateSignalKey'),'null'::jsonb)='null'::jsonb
    )
  order by s.score desc,s.question_key
  limit 1;

  if v_question.question_key is null then
    return jsonb_build_object(
      'ok',true,'contractVersion','reality_discovery_next_question_self_api_v1',
      'question',null,'quiet',true,'message','I know enough here for now.','context',v_context
    );
  end if;

  return jsonb_build_object(
    'ok',true,'contractVersion','reality_discovery_next_question_self_api_v1','quiet',false,
    'question',jsonb_build_object(
      'questionKey',v_question.question_key,'sectionKey',v_question.section_key,
      'prompt',v_question.prompt,'helpText',v_question.help_text,
      'answerKind',v_question.answer_kind,'options',v_question.options,
      'score',v_question.score,'reason',v_question.reason_text,
      'matchedReasons',case
        when v_question.source_coverage_penalty>0
        then v_question.matched_reasons||jsonb_build_array('Atlas has an authorized, recently synced source that may provide evidence here, so this question was moved later rather than suppressed.')
        else v_question.matched_reasons
      end,
      'candidateValue',case when coalesce((v_question.metadata->>'requiresCandidate')::boolean,false)
        then v_signals->(v_question.metadata->>'candidateSignalKey') else null end
    ),
    'context',v_context
  );
end;
$function$;

revoke all on function atlas.reality_discovery_next_question_self_api_v1() from public,anon;
grant execute on function atlas.reality_discovery_next_question_self_api_v1() to authenticated,service_role;

create or replace function atlas.ensure_connections_spread_self_api_v1()
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_spread_id uuid;
  v_contract jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select p.id into v_principal_id
  from atlas.principals p
  where p.user_id=v_user_id and p.status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_contract:=jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger',
      'role','anchor',
      'order',1,
      'supportedRelationships',jsonb_build_array('evidence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep outlet identity and source authorization state visible; collapse provider detail before hiding state.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateSourceTruth',true,'connectionStateDoesNotGrantAuthority',true),
    'compilerBasis',jsonb_build_object('screenId','CFG-07','systemSpread','connections')
  );

  v_spread_id:=atlas.set_notebook_spread_instance_v2(
    v_principal_id,
    'connections',
    'person',v_principal_id::text,
    'principal','connections',v_principal_id::text,
    'source-coverage-orientation','current','connections',
    'Connections','Connections',null,'resolved','open',
    v_contract,
    jsonb_build_object('screenId','CFG-07','establishedBy','ensure_connections_spread_self_api_v1'),
    jsonb_build_object('permanent',true,'truthOwner',false)
  );

  perform atlas.bind_notebook_spread_source_v1(
    v_spread_id,
    'principal','connected_sources_v1',v_principal_id::text,
    'evidence','active',
    jsonb_build_object('screenId','CFG-07','authority','connected_sources_self_api_v1'),
    jsonb_build_object('projection','connections-ledger-v1')
  );

  return atlas.notebook_spread_instance_self_api_v1('connections');
end;
$function$;

revoke all on function atlas.ensure_connections_spread_self_api_v1() from public,anon;
grant execute on function atlas.ensure_connections_spread_self_api_v1() to authenticated,service_role;

-- Existing Principals receive the same durable page identity that future
-- Principals obtain through the authenticated ensure command.
do $do$
declare
  r record;
  v_spread_id uuid;
  v_contract jsonb;
begin
  v_contract:=jsonb_build_object(
    'contractVersion','notebook_spread_composition_v1',
    'patternKey','single-form-continuation',
    'forms',jsonb_build_array(jsonb_build_object(
      'formFamily','ledger','role','anchor','order',1,
      'supportedRelationships',jsonb_build_array('evidence','state'),
      'emptyBehavior','show-established-future-space',
      'phoneRule','Keep outlet identity and source authorization state visible; collapse provider detail before hiding state.'
    )),
    'surfaceBudget',jsonb_build_object('anchorCount',1,'supportingCount',0,'marginCount',0,'latentIsDefault',true),
    'phoneLinearization',jsonb_build_array('ledger'),
    'stability',jsonb_build_object('meaningPositionsAreStable',true,'recomposeOnlyForMeaningfulPhaseChange',true,'historyPreservedByRevision',true),
    'sourceBindingPolicy',jsonb_build_object('sourceTruthExternal',true,'missingSourceDoesNotCreateSourceTruth',true,'connectionStateDoesNotGrantAuthority',true),
    'compilerBasis',jsonb_build_object('screenId','CFG-07','systemSpread','connections','migration','connections-reality-discovery-source-coverage-v1')
  );

  for r in select p.id from atlas.principals p where p.status='active' loop
    v_spread_id:=atlas.set_notebook_spread_instance_v2(
      r.id,'connections','person',r.id::text,
      'principal','connections',r.id::text,
      'source-coverage-orientation','current','connections',
      'Connections','Connections',null,'resolved','open',
      v_contract,
      jsonb_build_object('screenId','CFG-07','establishedBy','connections-reality-discovery-source-coverage-v1'),
      jsonb_build_object('permanent',true,'truthOwner',false)
    );

    perform atlas.bind_notebook_spread_source_v1(
      v_spread_id,'principal','connected_sources_v1',r.id::text,'evidence','active',
      jsonb_build_object('screenId','CFG-07','authority','connected_sources_self_api_v1'),
      jsonb_build_object('projection','connections-ledger-v1')
    );
  end loop;
end;
$do$;

commit;
