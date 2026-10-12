-- SOURCE CANDIDATE ONLY. Preserve first-use orientation and Index as distinct evidence.
-- The notebook may begin Foundry without a standalone Index-selection screen.
BEGIN;

CREATE OR REPLACE FUNCTION atlas.reality_discovery_orientation_profile_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_event
  from atlas.reality_discovery_orientation_events
  where principal_id=v_principal_id
    and owner_user_id=v_user_id
    and orientation_version in (4,3)
  order by occurred_at desc,id desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_orientation_profile_self_api_v1',
    'model',case when v_event.orientation_version=4 then 'index_categories' else 'field_position_scale' end,
    'captured',v_event.id is not null,
    'worldDomains',coalesce(v_event.world_domains,'[]'::jsonb),
    'positionMap',case when v_event.orientation_version=4 then '{}'::jsonb else coalesce(v_event.position_map,'{}'::jsonb) end,
    'scaleMap',case when v_event.orientation_version=4 then '{}'::jsonb else coalesce(v_event.scale_map,'{}'::jsonb) end,
    'occurredAt',v_event.occurred_at,
    'truthBoundary',jsonb_build_object(
      'orientationIsColdStartEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'indexSelectionOrganizesNotebook',v_event.orientation_version=4,
      'indexSelectionMayConstrainAndReorderDiscovery',v_event.orientation_version=4,
      'positionAndScaleAreNotRequiredOnboarding',v_event.orientation_version=4,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION atlas.reality_discovery_first_day_status_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_session atlas.reality_discovery_sessions%rowtype;
  v_answer_count integer:=0;
  v_bookplate jsonb;
  v_index jsonb;
  v_bookplate_captured boolean:=false;
  v_index_captured boolean:=false;
  v_orientation jsonb;
  v_orientation_captured boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select * into v_session
  from atlas.reality_discovery_sessions
  where principal_id=v_principal_id and session_kind='first_day';

  select count(*)::integer into v_answer_count
  from atlas.reality_discovery_answer_events
  where principal_id=v_principal_id;

  v_bookplate:=atlas.personal_atlas_bookplate_self_api_v1();
  v_index:=atlas.personal_atlas_index_selection_self_api_v1();
  v_orientation:=atlas.reality_discovery_orientation_profile_self_api_v1();
  v_bookplate_captured:=coalesce((v_bookplate->>'captured')::boolean,false);
  v_index_captured:=coalesce((v_index->>'captured')::boolean,false);
  v_orientation_captured:=coalesce((v_orientation->>'captured')::boolean,false);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_first_day_status_self_api_v2',
    'hasStarted',v_session.id is not null,
    'session',case when v_session.id is null then null else jsonb_build_object(
      'id',v_session.id,'state',v_session.state,'startedAt',v_session.started_at,
      'lastOpenedAt',v_session.last_opened_at,'pausedAt',v_session.paused_at,
      'quietAt',v_session.quiet_at,'closedAt',v_session.closed_at
    ) end,
    'answerCount',v_answer_count,
    'bookplateCaptured',v_bookplate_captured,
    'indexCaptured',v_index_captured,
    'orientationCaptured',v_orientation_captured,
    'entranceCaptured',v_bookplate_captured and v_orientation_captured,
    'shouldAutoOpen',not v_bookplate_captured or not v_orientation_captured or v_session.id is null,
    'truthBoundary',jsonb_build_object(
      'shouldAutoOpenIsEncounterRouting',true,
      'missingBookplateOrOrientationKeepsEntranceOpen',true,
      'IndexIsNotMandatoryOnboarding',true,
      'priorSessionDoesNotBypassMissingNotebookEntrance',true,
      'pausedIsNotComplete',true,
      'answerCountIsNotCompletionScore',true
    )
  );
end;
$function$
;

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
  v_selection jsonb;
  v_selected_categories jsonb := '[]'::jsonb;
  v_index_captured boolean := false;
  v_domain_filter_captured boolean := false;
  v_orientation jsonb;
  v_domain_filter_source text := 'none';
  v_subject_domain text;
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

  v_selection:=atlas.personal_atlas_index_selection_self_api_v1();
  v_index_captured:=coalesce((v_selection->>'captured')::boolean,false);
  v_orientation:=atlas.reality_discovery_orientation_profile_self_api_v1();
  -- A real field selected by the human is enough to scope the first encounter.
  -- An explicitly selected Index remains independently preserved when one exists.
  if v_index_captured then
    v_selected_categories:=coalesce(v_selection->'selectedCategories','[]'::jsonb);
    v_domain_filter_source:='intentional_index';
  else
    v_selected_categories:=coalesce(v_orientation->'worldDomains','[]'::jsonb);
    v_domain_filter_source:='human_field_orientation';
  end if;
  v_domain_filter_captured:=jsonb_typeof(v_selected_categories)='array'
    and jsonb_array_length(v_selected_categories)>0;

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if v_kind='first_day'
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
      when v_kind='manual' then true
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
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    select coalesce(metadata,'{}'::jsonb) into v_metadata
    from atlas.reality_discovery_questions
    where question_key=v_question_key;

    if v_kind='first_day'
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
      when v_kind='manual' then true
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
$function$
;

COMMIT;
