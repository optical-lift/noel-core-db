BEGIN;

-- A person's selected Discovery bearing is a temporary encounter intention.
-- This preserves the original Field/Position/Scale orientation event, keeps
-- ordinary ranked eligibility and answered-question suppression, and routes
-- the answer writer through the same focused question-set validation.
-- No new canonical business/person/property records and no new global tabs.

CREATE OR REPLACE FUNCTION atlas.reality_discovery_question_set_for_encounter_self_api_v1(p_session_kind text, p_limit integer DEFAULT 4)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_kind text;
  v_limit integer;
  v_ranked jsonb;
  v_context jsonb;
  v_question jsonb;
  v_question_key text;
  v_policy atlas.reality_discovery_encounter_admission%rowtype;
  v_metadata jsonb;
  v_admitted boolean;
  v_anchor_cluster text;
  v_cluster_label text;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_has_eligible boolean := false;
  v_deferred_count integer := 0;
  v_household_shape_known boolean := false;
  v_orientation_captured boolean := false;
  v_selected_categories jsonb := '[]'::jsonb;
  v_index_captured boolean := false;
  v_domain_filter_captured boolean := false;
  v_orientation jsonb;
  v_domain_filter_source text := 'none';
  v_subject_domain text;
  v_focus_domain text;
  v_skipped_question_keys jsonb := '[]'::jsonb;
  v_available_bearings jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_kind:=coalesce(nullif(trim(p_session_kind),''),'first_day');
  if v_kind not in ('first_day','manual','micro') then
    raise exception 'Unsupported discovery encounter kind.' using errcode='22023';
  end if;

  v_limit:=least(5,greatest(1,coalesce(p_limit,4)));
  v_ranked:=atlas.reality_discovery_ranked_questions_self_api_v1();
  v_context:=v_ranked->'context';
  v_household_shape_known:=coalesce(v_context#>>'{signals,household.people_shape}','')<>'';
  v_orientation_captured:=coalesce((v_context#>>'{orientation,captured}')::boolean,false);

  v_orientation:=atlas.reality_discovery_orientation_profile_self_api_v1();
  v_index_captured:=coalesce((v_orientation->>'captured')::boolean,false);
  v_selected_categories:=coalesce(v_orientation->'worldDomains','[]'::jsonb);
  v_domain_filter_source:='human_field_orientation';
  v_domain_filter_captured:=jsonb_typeof(v_selected_categories)='array'
    and jsonb_array_length(v_selected_categories)>0;

  -- An explicit human change of bearing belongs only to the active Encounter.
  -- The original Field / Position / Scale event is never rewritten.
  select nullif(trim(s.metadata->>'focusDomain'),''),
         coalesce(s.metadata->'skippedQuestionKeys','[]'::jsonb)
  into v_focus_domain,v_skipped_question_keys
  from atlas.reality_discovery_sessions s
  where s.owner_user_id=auth.uid()
    and s.principal_id=(v_context->>'principalId')::uuid
    and s.session_kind=v_kind and s.state='active'
  order by s.last_opened_at desc,s.started_at desc,s.id
  limit 1;

  if v_focus_domain is not null then
    v_selected_categories:=jsonb_build_array(v_focus_domain);
    v_domain_filter_captured:=true;
    v_domain_filter_source:='explicit_human_encounter_bearing';
  end if;
  if jsonb_typeof(v_skipped_question_keys)<>'array' then
    v_skipped_question_keys:='[]'::jsonb;
  end if;

  -- This is affordance availability, not canonical subject existence. It
  -- reflects eligible unanswered questions, never hypothetical prompts.
  select coalesce(jsonb_agg(jsonb_build_object('domain',d.domain,'questionCount',d.qty)
    order by d.qty desc,d.domain),'[]'::jsonb)
  into v_available_bearings
  from (
    select tag.domain,count(distinct item.value->>'questionKey')::integer qty
    from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb)) item(value)
    join atlas.reality_discovery_questions q on q.question_key=item.value->>'questionKey'
    cross join lateral jsonb_array_elements_text(
      case when jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
      then q.metadata->'orientationWorldDomains' else '[]'::jsonb end
    ) tag(domain)
    where not (v_skipped_question_keys ? (item.value->>'questionKey'))
      and tag.domain in ('home','family','job','business','property','money',
                         'school','projects','community','hobbies')
    group by tag.domain
  ) d;

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    if v_skipped_question_keys ? v_question_key then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if (v_kind='first_day' or v_focus_domain is not null)
       and v_domain_filter_captured
       and jsonb_typeof(v_metadata->'orientationWorldDomains')='array'
       and not exists(
         select 1
         from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') d(domain)
         where v_selected_categories ? d.domain
       ) then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    v_has_eligible:=true;

    v_admitted:=case
      when v_kind='manual' or (v_kind='first_day' and v_focus_domain is not null) then true
      when v_kind='first_day' then v_policy.question_key is not null and v_policy.first_day_disposition='admit'
      else false
    end;

    if not v_admitted then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    if v_kind='first_day'
       and not v_orientation_captured
       and not v_household_shape_known
       and coalesce(nullif(v_metadata->>'encounterCluster',''),'general')<>'you_home' then
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    v_anchor_cluster:=coalesce(nullif(v_metadata->>'encounterCluster',''),'general');
    v_cluster_label:=coalesce(
      nullif(v_metadata->>'encounterClusterLabel',''),
      upper(replace(v_anchor_cluster,'_',' '))
    );
    exit;
  end loop;

  if v_anchor_cluster is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','reality_discovery_question_set_v4',
      'encounterKind',v_kind,
      'focusDomain',v_focus_domain,
      'availableBearings',v_available_bearings,
      'clusterKey',null,
      'clusterLabel',null,
      'items','[]'::jsonb,
      'quiet',true,
      'message','I know enough here for now.',
      'eligibleUnansweredRemain',v_has_eligible,
      'deferredCount',v_deferred_count,
      'context',v_context,
      'truthBoundary',jsonb_build_object(
        'quietMeansNoQuestionSetAdmittedForThisEncounter',true,
        'quietDoesNotMeanDiscoveryComplete',true,
        'humanFieldOrIndexConstrainsFirstDayQuestions',v_domain_filter_captured,
        'domainRoutingSource',v_domain_filter_source,
        'setIsPresentationGroupingNotTruth',true,
        'setRecomputesAfterEveryAnswer',true,
        'microAdmissionRequiresSeparateWarrant',true
      )
    );
  end if;

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    if v_skipped_question_keys ? v_question_key then continue; end if;
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if (v_kind='first_day' or v_focus_domain is not null)
       and v_domain_filter_captured
       and jsonb_typeof(v_metadata->'orientationWorldDomains')='array'
       and not exists(
         select 1
         from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') d(domain)
         where v_selected_categories ? d.domain
       ) then
      continue;
    end if;

    v_admitted:=case
      when v_kind='manual' or (v_kind='first_day' and v_focus_domain is not null) then true
      when v_kind='first_day' then v_policy.question_key is not null and v_policy.first_day_disposition='admit'
      else false
    end;

    if not v_admitted then continue; end if;
    if coalesce(nullif(v_metadata->>'encounterCluster',''),'general') is distinct from v_anchor_cluster then
      continue;
    end if;

    v_subject_domain:=null;
    if v_domain_filter_captured and jsonb_typeof(v_metadata->'orientationWorldDomains')='array' then
      select d.domain into v_subject_domain
      from jsonb_array_elements_text(v_metadata->'orientationWorldDomains') with ordinality d(domain,ordinal)
      where v_selected_categories ? d.domain
      order by d.ordinal
      limit 1;
    end if;

    v_question:=atlas.reality_discovery_apply_option_eligibility_v1(v_question,v_context);

    v_items:=v_items||jsonb_build_array(
      v_question||jsonb_build_object(
        'admissionClass',coalesce(v_policy.admission_class,'unclassified'),
        'admissionReason',coalesce(v_policy.reason_text,'The human explicitly opened broader Discovery.'),
        'encounterCluster',v_anchor_cluster,
        'encounterClusterLabel',v_cluster_label,
        'subjectDomain',v_subject_domain
      )
    );
    v_count:=v_count+1;
    exit when v_count>=v_limit;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_question_set_v4',
    'encounterKind',v_kind,
    'focusDomain',v_focus_domain,
    'availableBearings',v_available_bearings,
    'clusterKey',v_anchor_cluster,
    'clusterLabel',v_cluster_label,
    'items',v_items,
    'quiet',false,
    'eligibleUnansweredRemain',v_has_eligible,
    'deferredCount',v_deferred_count,
    'context',v_context,
    'truthBoundary',jsonb_build_object(
      'setContainsOnlyCurrentlyEligibleAdmittedQuestions',true,
      'humanFieldOrIndexConstrainsFirstDayQuestions',v_domain_filter_captured,
        'domainRoutingSource',v_domain_filter_source,
      'questionCarriesNotebookSubjectDomain',true,
      'setIsPresentationGroupingNotTruth',true,
      'setRecomputesAfterEveryAnswer',true,
      'answeringOneItemMayRemoveOrReplaceOthers',true,
      'optionEligibilityUsesEstablishedContextOnly',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

create or replace function atlas.set_reality_discovery_bearing_self_api_v1(
  p_session_id uuid,
  p_focus_domain text,
  p_source_action_id text,
  p_reason text default 'change_direction',
  p_question_key text default null
) returns jsonb language plpgsql security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_uid uuid:=auth.uid();
  v_principal uuid;
  v_session atlas.reality_discovery_sessions%rowtype;
  v_domain text:=nullif(lower(trim(p_focus_domain)),'');
  v_reason text:=coalesce(nullif(trim(p_reason),''),'change_direction');
  v_action text:=nullif(trim(p_source_action_id),'');
  v_question_key text:=nullif(trim(p_question_key),'');
  v_history jsonb;
  v_prior jsonb;
  v_skipped jsonb;
  v_entry jsonb;
  v_meta jsonb;
begin
  if v_uid is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select id into v_principal from atlas.principals
  where user_id=v_uid and status='active' limit 1;
  if v_principal is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_session_id is null or v_action is null or length(v_action)>192 then
    raise exception 'Valid session and source action required.' using errcode='22023';
  end if;
  if v_domain is not null and v_domain not in
    ('home','family','job','business','property','money','school','projects','community','hobbies') then
    raise exception 'Unsupported Encounter direction.' using errcode='22023';
  end if;
  if v_reason not in ('change_direction','question_does_not_fit')
     or (v_reason='question_does_not_fit' and v_question_key is null) then
    raise exception 'Unsupported direction or missing question.' using errcode='22023';
  end if;

  select * into v_session from atlas.reality_discovery_sessions
  where id=p_session_id and owner_user_id=v_uid and principal_id=v_principal
    and state='active' and session_kind in ('first_day','manual')
  for update;
  if v_session.id is null then
    raise exception 'An active owned Discovery session is required.' using errcode='42501';
  end if;
  v_meta:=coalesce(v_session.metadata,'{}'::jsonb);
  v_history:=coalesce(v_meta->'bearingHistory','[]'::jsonb);
  if jsonb_typeof(v_history)<>'array' then v_history:='[]'::jsonb; end if;

  select value into v_prior
  from jsonb_array_elements(v_history) where value->>'actionId'=v_action limit 1;
  if v_prior is not null then
    if v_prior->>'domain' is distinct from v_domain
       or v_prior->>'reason' is distinct from v_reason
       or v_prior->>'questionKey' is distinct from v_question_key then
      raise exception 'The source action already belongs to another bearing.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotentReplay',true,
      'focusDomain',nullif(v_meta->>'focusDomain',''),
      'set',atlas.reality_discovery_question_set_self_api_v1(4));
  end if;

  -- Feedback is an Encounter observation, not a statement about the world.
  v_skipped:=coalesce(v_meta->'skippedQuestionKeys','[]'::jsonb);
  if jsonb_typeof(v_skipped)<>'array' then v_skipped:='[]'::jsonb; end if;
  if v_reason='question_does_not_fit' then
    if not exists(select 1 from jsonb_array_elements(
       coalesce(atlas.reality_discovery_question_set_self_api_v1(5)->'items','[]'::jsonb)
      ) presented where presented.value->>'questionKey'=v_question_key) then
      raise exception 'Question is not currently admitted in this Encounter.' using errcode='22023';
    end if;
    if not (v_skipped ? v_question_key) then
      v_skipped:=v_skipped||jsonb_build_array(v_question_key);
    end if;
  end if;

  v_entry:=jsonb_build_object('actionId',v_action,'domain',v_domain,
    'reason',v_reason,'questionKey',v_question_key,
    'occurredAt',now());
  v_history:=v_history||jsonb_build_array(v_entry);
  if jsonb_array_length(v_history)>48 then
    select coalesce(jsonb_agg(value order by ordinality),'[]'::jsonb)
    into v_history from jsonb_array_elements(v_history) with ordinality h(value,ordinality)
    where ordinality>jsonb_array_length(v_history)-48;
  end if;
  v_meta:=v_meta||jsonb_build_object(
    'focusDomain',v_domain,
    'explicitHumanFocus',v_domain is not null,
    'bearingHistory',v_history,
    'skippedQuestionKeys',v_skipped
  );
  update atlas.reality_discovery_sessions
  set metadata=v_meta,last_opened_at=now(),updated_at=now()
  where id=v_session.id;

  return jsonb_build_object('ok',true,'idempotentReplay',false,
    'focusDomain',v_domain,
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'bearingIsEncounterAttentionOnly',true,
      'orientationFieldPositionScaleUnchanged',true,
      'questionFitFeedbackIsNotDomainTruth',true,
      'noQuestionInventedByBearing',true
    )
  );
end;
$function$;

revoke all on function atlas.set_reality_discovery_bearing_self_api_v1(uuid,text,text,text,text) from public,anon;
grant execute on function atlas.set_reality_discovery_bearing_self_api_v1(uuid,text,text,text,text) to authenticated;

COMMIT;
