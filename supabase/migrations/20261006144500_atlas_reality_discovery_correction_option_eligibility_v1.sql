begin;

-- Reality Discovery correction + option eligibility.
--
-- This migration tightens first-establishment ordering, makes answer choices
-- conditional on already-established context, and adds explicit self-service
-- correction commands. Corrections remain append-only Discovery evidence and
-- owning-domain projections are updated only through their existing writers.

-- Household topology is foundational during first establishment. Connected
-- source coverage may still inform it, but must not push it behind downstream
-- questions that need the household shape in order to speak truthfully.
update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb)
      || jsonb_build_object('sourceCoveragePenalty',0,'foundationalTopology',true),
    updated_at = now()
where question_key='household.people_shape';

-- Repair responsibility should not be asked until Atlas knows both the home
-- arrangement and enough household topology to avoid presuming relationships.
insert into atlas.reality_discovery_edges(
  question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text
)
select
  'home.major_repairs','home.tenure','exists',null,'require',0,
  'Repair responsibility is asked only after the home arrangement is known.'
where exists (
  select 1 from atlas.reality_discovery_questions
  where question_key='home.major_repairs'
)
and not exists (
  select 1 from atlas.reality_discovery_edges
  where question_key='home.major_repairs'
    and signal_key='home.tenure'
    and effect_kind='require'
);

insert into atlas.reality_discovery_edges(
  question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text
)
select
  'home.major_repairs','household.people_shape','exists',null,'require',0,
  'Repair responsibility is asked only after household topology is known.'
where exists (
  select 1 from atlas.reality_discovery_questions
  where question_key='home.major_repairs'
)
and not exists (
  select 1 from atlas.reality_discovery_edges
  where question_key='home.major_repairs'
    and signal_key='household.people_shape'
    and effect_kind='require'
);

-- Option eligibility is presentation law, not truth. An option may appear only
-- when already-established context makes the option coherent.
update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'optionEligibility',
      jsonb_build_object(
        'shared',jsonb_build_array(
          jsonb_build_object(
            'signalKey','household.people_shape',
            'operator','in',
            'compareValue',jsonb_build_array('partner','partner_children','roommates','other')
          )
        ),
        'landlord',jsonb_build_array(
          jsonb_build_object(
            'signalKey','home.tenure',
            'operator','in',
            'compareValue',jsonb_build_array('rent','family_provided','other')
          )
        )
      )
    ),
    updated_at = now()
where question_key='home.major_repairs';

create or replace function atlas.reality_discovery_apply_option_eligibility_v1(
  p_question jsonb,
  p_context jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
declare
  v_question_key text;
  v_rules jsonb;
  v_signals jsonb;
  v_option jsonb;
  v_option_rules jsonb;
  v_rule jsonb;
  v_allowed boolean;
  v_filtered jsonb := '[]'::jsonb;
begin
  if p_question is null or jsonb_typeof(p_question)<>'object' then
    return p_question;
  end if;

  v_question_key:=nullif(trim(p_question->>'questionKey'),'');
  if v_question_key is null then return p_question; end if;

  select coalesce(q.metadata->'optionEligibility','{}'::jsonb)
  into v_rules
  from atlas.reality_discovery_questions q
  where q.question_key=v_question_key;

  if coalesce(jsonb_typeof(v_rules),'null')<>'object' or v_rules='{}'::jsonb then
    return p_question;
  end if;

  v_signals:=coalesce(p_context->'signals','{}'::jsonb);

  for v_option in
    select value from jsonb_array_elements(coalesce(p_question->'options','[]'::jsonb))
  loop
    v_option_rules:=v_rules->(v_option->>'key');
    v_allowed:=true;

    if jsonb_typeof(v_option_rules)='array' then
      for v_rule in select value from jsonb_array_elements(v_option_rules)
      loop
        if not atlas.reality_discovery_edge_matches_v1(
          v_signals->(v_rule->>'signalKey'),
          v_rule->>'operator',
          v_rule->'compareValue'
        ) then
          v_allowed:=false;
          exit;
        end if;
      end loop;
    end if;

    if v_allowed then
      v_filtered:=v_filtered||jsonb_build_array(v_option);
    end if;
  end loop;

  return p_question||jsonb_build_object('options',v_filtered);
end;
$function$;

revoke all on function atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb) to service_role;

create or replace function atlas.reality_discovery_question_set_for_encounter_self_api_v1(
  p_session_kind text,
  p_limit integer default 4
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
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
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_kind:=coalesce(nullif(trim(p_session_kind),''),'first_day');
  if v_kind not in ('first_day','manual','micro') then
    raise exception 'Unsupported discovery encounter kind.' using errcode='22023';
  end if;

  v_limit:=least(5,greatest(1,coalesce(p_limit,4)));
  v_ranked:=atlas.reality_discovery_ranked_questions_self_api_v1();
  v_context:=v_ranked->'context';
  v_has_eligible:=jsonb_array_length(coalesce(v_ranked->'items','[]'::jsonb))>0;
  v_household_shape_known:=coalesce(v_context#>>'{signals,household.people_shape}','')<>'';

  -- During first establishment, household topology gets the floor before
  -- unrelated downstream clusters. This is encounter ordering, not a claim
  -- that every later question semantically depends on household shape.
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
      'contractVersion','reality_discovery_question_set_v2',
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
        'setIsPresentationGroupingNotTruth',true,
        'setRecomputesAfterEveryAnswer',true,
        'foundationalTopologyMayOrderFirstEstablishment',true,
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

    v_admitted:=case
      when v_kind='manual' then true
      when v_kind='first_day' then v_policy.question_key is not null and v_policy.first_day_disposition='admit'
      else false
    end;

    if not v_admitted then continue; end if;
    if coalesce(nullif(v_metadata->>'encounterCluster',''),'general') is distinct from v_anchor_cluster then
      continue;
    end if;

    v_question:=atlas.reality_discovery_apply_option_eligibility_v1(v_question,v_context);

    v_items:=v_items||jsonb_build_array(
      v_question||jsonb_build_object(
        'admissionClass',coalesce(v_policy.admission_class,'unclassified'),
        'admissionReason',coalesce(v_policy.reason_text,'The human explicitly opened broader Discovery.'),
        'encounterCluster',v_anchor_cluster,
        'encounterClusterLabel',v_cluster_label
      )
    );
    v_count:=v_count+1;
    exit when v_count>=v_limit;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_question_set_v2',
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
      'setIsPresentationGroupingNotTruth',true,
      'setRecomputesAfterEveryAnswer',true,
      'answeringOneItemMayRemoveOrReplaceOthers',true,
      'optionEligibilityUsesEstablishedContextOnly',true,
      'foundationalTopologyMayOrderFirstEstablishment',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

create or replace function atlas.reality_discovery_editable_answer_self_api_v1(
  p_question_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_question atlas.reality_discovery_questions%rowtype;
  v_context jsonb;
  v_answers jsonb;
  v_signals jsonb;
  v_question_json jsonb;
  v_key text;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_key:=nullif(trim(p_question_key),'');
  if v_key is null then raise exception 'questionKey required.' using errcode='22023'; end if;

  select * into v_question
  from atlas.reality_discovery_questions
  where question_key=v_key and active;
  if v_question.question_key is null then raise exception 'Active discovery question not found.' using errcode='22023'; end if;

  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_answers:=coalesce(v_context->'answers','{}'::jsonb);
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);

  if not (v_answers ? v_key) then
    raise exception 'Discovery answer does not exist yet.' using errcode='22023';
  end if;

  if v_key='home.confirm_purchase_address' then
    raise exception 'Home address confirmation correction requires residence replacement workflow.' using errcode='0A000';
  end if;

  v_question_json:=jsonb_build_object(
    'questionKey',v_question.question_key,
    'sectionKey',v_question.section_key,
    'prompt',v_question.prompt,
    'helpText',v_question.help_text,
    'answerKind',v_question.answer_kind,
    'options',v_question.options,
    'reason',v_question.reason_text,
    'candidateValue',case
      when coalesce((v_question.metadata->>'requiresCandidate')::boolean,false)
      then v_signals->(v_question.metadata->>'candidateSignalKey')
      else null
    end
  );

  v_question_json:=atlas.reality_discovery_apply_option_eligibility_v1(v_question_json,v_context);

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_editable_answer_self_api_v1',
    'currentAnswer',v_answers->v_key,
    'question',v_question_json,
    'truthBoundary',jsonb_build_object(
      'editingDoesNotDeletePriorEvidence',true,
      'correctionRequiresExplicitCommand',true,
      'optionsRespectCurrentEstablishedContext',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_editable_answer_self_api_v1(text) from public,anon,authenticated;
grant execute on function atlas.reality_discovery_editable_answer_self_api_v1(text) to service_role;

create or replace function public.reality_discovery_editable_answer_self_api_v1(p_question_key text)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_editable_answer_self_api_v1(p_question_key);
$function$;

revoke all on function public.reality_discovery_editable_answer_self_api_v1(text) from public,anon;
grant execute on function public.reality_discovery_editable_answer_self_api_v1(text) to authenticated,service_role;

-- Preserve the normal answer command while validating choice keys against the
-- context-filtered question returned by the current governed set.
create or replace function atlas.answer_reality_discovery_question_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_question atlas.reality_discovery_questions%rowtype;
  v_question_key text;
  v_source_action_id text;
  v_answer jsonb;
  v_answer_scalar text;
  v_existing atlas.reality_discovery_answer_events%rowtype;
  v_event atlas.reality_discovery_answer_events%rowtype;
  v_signal_key text;
  v_set jsonb;
  v_set_question jsonb;
  v_candidate_address jsonb;
  v_residence jsonb;
  v_promotion jsonb;
  v_promoted boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Discovery answer input must be an object.' using errcode='22023'; end if;

  v_question_key:=nullif(trim(p_input->>'questionKey'),'');
  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_answer:=p_input->'answer';
  if v_question_key is null or v_source_action_id is null or v_answer is null then
    raise exception 'questionKey, sourceActionId, and answer are required.' using errcode='22023';
  end if;

  select * into v_question from atlas.reality_discovery_questions where question_key=v_question_key and active;
  if v_question.question_key is null then raise exception 'Active discovery question not found.' using errcode='22023'; end if;

  if v_question.answer_kind in ('single_choice','yes_no') then
    if jsonb_typeof(v_answer)<>'string' then raise exception 'This discovery answer must be a choice key.' using errcode='22023'; end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
  elsif v_question.answer_kind='short_text' then
    if jsonb_typeof(v_answer)<>'string' or length(trim(both '"' from v_answer::text))=0 then
      raise exception 'A non-empty answer is required.' using errcode='22023';
    end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
  end if;

  select * into v_existing from atlas.reality_discovery_answer_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;
  if v_existing.id is not null then
    if v_existing.question_key is distinct from v_question_key or v_existing.answer_value is distinct from v_answer then
      raise exception 'sourceActionId already belongs to a different discovery answer.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,
      'idempotentReplay',true,
      'eventId',v_existing.id,
      'next',atlas.reality_discovery_next_question_self_api_v1(),
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  v_set:=atlas.reality_discovery_question_set_self_api_v1(5);
  select value into v_set_question
  from jsonb_array_elements(coalesce(v_set->'items','[]'::jsonb))
  where value->>'questionKey'=v_question_key
  limit 1;

  if v_set_question is null then
    raise exception 'Discovery question is no longer in the current eligible encounter set.' using errcode='40001';
  end if;

  if v_question.answer_kind in ('single_choice','yes_no')
     and not exists(
       select 1 from jsonb_array_elements(coalesce(v_set_question->'options','[]'::jsonb)) o
       where o->>'key'=v_answer_scalar
     ) then
    raise exception 'Answer option is not eligible in the current reality context.' using errcode='22023';
  end if;

  if v_question_key='home.confirm_purchase_address' then
    v_candidate_address:=v_set_question->'candidateValue';
  end if;

  insert into atlas.reality_discovery_answer_events(principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata)
  values(v_principal.id,v_user_id,v_question_key,v_source_action_id,v_answer,
    jsonb_build_object('source','reality_discovery_v1','reason',v_question.reason_text))
  returning * into v_event;

  v_signal_key:=v_question.resolved_signal_key;
  if v_signal_key is not null then
    insert into atlas.reality_discovery_evidence_candidates(
      principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation,metadata
    ) values(
      v_principal.id,v_user_id,v_signal_key,v_answer,'human_confirmed','discovery_answer',v_event.id::text,1,
      'Human answer captured through Reality Discovery.',jsonb_build_object('questionKey',v_question_key)
    );
  end if;

  if v_question_key='home.confirm_purchase_address' then
    insert into atlas.reality_discovery_evidence_candidates(
      principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation,metadata
    ) values(
      v_principal.id,v_user_id,'home.address_confirmed',to_jsonb(v_answer_scalar='yes'),
      'human_confirmed','discovery_answer',v_event.id::text,1,
      case when v_answer_scalar='yes' then 'The human confirmed the purchase address is home.' else 'The human rejected the purchase address as home.' end,
      jsonb_build_object('questionKey',v_question_key)
    );

    if v_candidate_address is not null and v_candidate_address<>'null'::jsonb then
      insert into atlas.reality_discovery_evidence_candidates(
        principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation,metadata
      ) values(
        v_principal.id,v_user_id,'purchase.billing_address',v_candidate_address,
        case when v_answer_scalar='yes' then 'human_confirmed' else 'human_rejected' end,
        'stripe_purchase_confirmation',v_event.id::text,1,
        case when v_answer_scalar='yes'
          then 'The human confirmed the Stripe purchase address as their home address candidate.'
          else 'The human explicitly rejected the Stripe purchase address as their home address.' end,
        jsonb_build_object('questionKey',v_question_key)
      );
    end if;

    if v_answer_scalar='yes' and v_candidate_address is not null and v_candidate_address<>'null'::jsonb then
      v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
        'stableKey','primary-home','address',v_candidate_address,
        'sourceKind','reality_discovery','sourceRef',v_event.id::text
      ));
      v_promoted:=true;
    end if;
  elsif v_question_key in ('home.tenure','home.major_repairs') then
    v_residence:=atlas.personal_residence_arrangement_self_api_v1();
    if v_residence#>'{residence,address}' is not null and v_residence#>'{residence,address}'<>'null'::jsonb then
      if v_question_key='home.tenure' then
        v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
          'stableKey','primary-home','tenureKind',v_answer_scalar,
          'sourceKind','reality_discovery','sourceRef',v_event.id::text
        ));
      else
        v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
          'stableKey','primary-home','majorRepairsResponsibility',v_answer_scalar,
          'sourceKind','reality_discovery','sourceRef',v_event.id::text
        ));
      end if;
      v_promoted:=true;
    end if;
  end if;

  if v_promoted and v_signal_key is not null then
    update atlas.reality_discovery_evidence_candidates
    set epistemic_state='promoted',updated_at=now(),metadata=metadata||jsonb_build_object('promotion','household_residence_arrangement')
    where principal_id=v_principal.id and source_ref=v_event.id::text and signal_key=v_signal_key;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','answer_reality_discovery_question_self_api_v1',
    'idempotentReplay',false,
    'eventId',v_event.id,
    'promoted',v_promoted,
    'promotion',v_promotion,
    'next',atlas.reality_discovery_next_question_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'answerIsEvidence',true,
      'answerDoesNotBypassOwningDomain',true,
      'optionMustBeEligibleInCurrentContext',true,
      'residencePromotionRequiresConfirmedResidenceIdentity',true,
      'residencePromotionUsesResidenceAuthority',true,
      'inferenceMayRerankButNotEstablishTruth',true,
      'setMembershipDoesNotCreateTruth',true,
      'staleQuestionSubmissionRejected',true
    )
  );
end;
$function$;

create or replace function atlas.correct_reality_discovery_answer_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_question atlas.reality_discovery_questions%rowtype;
  v_question_key text;
  v_source_action_id text;
  v_answer jsonb;
  v_answer_scalar text;
  v_context jsonb;
  v_previous_answer jsonb;
  v_editable jsonb;
  v_edit_question jsonb;
  v_existing atlas.reality_discovery_answer_events%rowtype;
  v_event atlas.reality_discovery_answer_events%rowtype;
  v_signal_key text;
  v_residence jsonb;
  v_promotion jsonb;
  v_promoted boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  if p_input is null or jsonb_typeof(p_input)<>'object' then raise exception 'Discovery correction input must be an object.' using errcode='22023'; end if;

  v_question_key:=nullif(trim(p_input->>'questionKey'),'');
  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  v_answer:=p_input->'answer';
  if v_question_key is null or v_source_action_id is null or v_answer is null then
    raise exception 'questionKey, sourceActionId, and answer are required.' using errcode='22023';
  end if;

  select * into v_existing from atlas.reality_discovery_answer_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;
  if v_existing.id is not null then
    if v_existing.question_key is distinct from v_question_key or v_existing.answer_value is distinct from v_answer then
      raise exception 'sourceActionId already belongs to a different discovery answer.' using errcode='23505';
    end if;
    return jsonb_build_object(
      'ok',true,
      'idempotentReplay',true,
      'eventId',v_existing.id,
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  select * into v_question
  from atlas.reality_discovery_questions
  where question_key=v_question_key and active;
  if v_question.question_key is null then raise exception 'Active discovery question not found.' using errcode='22023'; end if;

  v_editable:=atlas.reality_discovery_editable_answer_self_api_v1(v_question_key);
  v_edit_question:=v_editable->'question';
  v_previous_answer:=v_editable->'currentAnswer';

  if v_question.answer_kind in ('single_choice','yes_no') then
    if jsonb_typeof(v_answer)<>'string' then raise exception 'This discovery correction must be a choice key.' using errcode='22023'; end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
    if not exists(
      select 1 from jsonb_array_elements(coalesce(v_edit_question->'options','[]'::jsonb)) o
      where o->>'key'=v_answer_scalar
    ) then
      raise exception 'Correction option is not eligible in the current reality context.' using errcode='22023';
    end if;
  elsif v_question.answer_kind='short_text' then
    if jsonb_typeof(v_answer)<>'string' or length(trim(both '"' from v_answer::text))=0 then
      raise exception 'A non-empty correction is required.' using errcode='22023';
    end if;
    v_answer_scalar:=trim(both '"' from v_answer::text);
  end if;

  if v_previous_answer is not distinct from v_answer then
    return jsonb_build_object(
      'ok',true,
      'unchanged',true,
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  insert into atlas.reality_discovery_answer_events(
    principal_id,owner_user_id,question_key,source_action_id,answer_value,metadata
  ) values(
    v_principal.id,v_user_id,v_question_key,v_source_action_id,v_answer,
    jsonb_build_object(
      'source','reality_discovery_correction_v1',
      'reason',v_question.reason_text,
      'correction',true,
      'previousAnswer',v_previous_answer
    )
  )
  returning * into v_event;

  v_signal_key:=v_question.resolved_signal_key;
  if v_signal_key is not null then
    insert into atlas.reality_discovery_evidence_candidates(
      principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation,metadata
    ) values(
      v_principal.id,v_user_id,v_signal_key,v_answer,'human_confirmed','discovery_answer_correction',v_event.id::text,1,
      'Human correction captured through Reality Discovery.',
      jsonb_build_object('questionKey',v_question_key,'previousAnswer',v_previous_answer)
    );
  end if;

  if v_question_key in ('home.tenure','home.major_repairs') then
    v_residence:=atlas.personal_residence_arrangement_self_api_v1();
    if v_residence#>'{residence,address}' is not null and v_residence#>'{residence,address}'<>'null'::jsonb then
      if v_question_key='home.tenure' then
        v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
          'stableKey','primary-home','tenureKind',v_answer_scalar,
          'sourceKind','reality_discovery_correction','sourceRef',v_event.id::text
        ));
      else
        v_promotion:=atlas.upsert_personal_residence_arrangement_self_api_v1(jsonb_build_object(
          'stableKey','primary-home','majorRepairsResponsibility',v_answer_scalar,
          'sourceKind','reality_discovery_correction','sourceRef',v_event.id::text
        ));
      end if;
      v_promoted:=true;
    end if;
  end if;

  if v_promoted and v_signal_key is not null then
    update atlas.reality_discovery_evidence_candidates
    set epistemic_state='promoted',updated_at=now(),metadata=metadata||jsonb_build_object('promotion','household_residence_arrangement')
    where principal_id=v_principal.id and source_ref=v_event.id::text and signal_key=v_signal_key;
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','correct_reality_discovery_answer_self_api_v1',
    'eventId',v_event.id,
    'previousAnswer',v_previous_answer,
    'promoted',v_promoted,
    'promotion',v_promotion,
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'correctionIsAppendOnlyEvidence',true,
      'priorAnswerIsPreserved',true,
      'latestAnswerDrivesDiscoveryContext',true,
      'optionMustBeEligibleInCurrentContext',true,
      'owningDomainPromotionStillRequired',true,
      'downstreamQuestionsRecomputeAfterCorrection',true
    )
  );
end;
$function$;

revoke all on function atlas.correct_reality_discovery_answer_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.correct_reality_discovery_answer_self_api_v1(jsonb) to service_role;

create or replace function public.correct_reality_discovery_answer_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.correct_reality_discovery_answer_self_api_v1(p_input);
$function$;

revoke all on function public.correct_reality_discovery_answer_self_api_v1(jsonb) from public,anon;
grant execute on function public.correct_reality_discovery_answer_self_api_v1(jsonb) to authenticated,service_role;

create or replace function atlas.update_personal_atlas_identity_name_self_api_v1(p_name text)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_name text;
  v_principal atlas.principals%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_name:=nullif(trim(p_name),'');
  if v_name is null then raise exception 'Name required.' using errcode='22023'; end if;
  if length(v_name)>160 then raise exception 'Name is too long.' using errcode='22023'; end if;

  select * into v_principal
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1
  for update;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  if v_principal.name is not distinct from v_name then
    return jsonb_build_object('ok',true,'unchanged',true,'name',v_name);
  end if;

  update atlas.people
  set display_name=v_name,updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('lastSelfNameCorrectionAt',now())
  where id=v_principal.person_id;

  update atlas.principals
  set name=v_name,updated_at=now(),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('lastSelfNameCorrectionAt',now())
  where id=v_principal.id;

  update atlas.household_members hm
  set display_name=v_name,
      metadata=coalesce(hm.metadata,'{}'::jsonb)||jsonb_build_object('lastSelfNameCorrectionAt',now())
  where hm.user_id=v_user_id
    and hm.active
    and exists(
      select 1 from atlas.households h
      where h.id=hm.household_id and h.principal_id=v_principal.id
    );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','update_personal_atlas_identity_name_self_api_v1',
    'name',v_name,
    'truthBoundary',jsonb_build_object(
      'authenticatedPrincipalOnly',true,
      'personProjectionUpdated',true,
      'principalProjectionUpdated',true,
      'ownedHouseholdSelfProjectionUpdated',true
    )
  );
end;
$function$;

revoke all on function atlas.update_personal_atlas_identity_name_self_api_v1(text) from public,anon,authenticated;
grant execute on function atlas.update_personal_atlas_identity_name_self_api_v1(text) to service_role;

create or replace function public.update_personal_atlas_identity_name_self_api_v1(p_name text)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.update_personal_atlas_identity_name_self_api_v1(p_name);
$function$;

revoke all on function public.update_personal_atlas_identity_name_self_api_v1(text) from public,anon;
grant execute on function public.update_personal_atlas_identity_name_self_api_v1(text) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
(
  'atlas.reality_discovery_editable_answer_self_api_v1(p_question_key text)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Return one previously answered Reality Discovery question in an explicit correction state.',
    'truthBoundary','Reading an editable answer does not mutate truth; correction requires the separate correction command.'
  ),
  now()
),
(
  'atlas.correct_reality_discovery_answer_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append a human correction to an existing Reality Discovery answer and recompute the governed question set.',
    'truthBoundary','Correction preserves prior evidence and still uses owning-domain writers for promoted residence facts.'
  ),
  now()
),
(
  'atlas.update_personal_atlas_identity_name_self_api_v1(p_name text)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Correct the authenticated Principal display name across the Person, Principal, and owned-household self projections.',
    'truthBoundary','Only the authenticated Principal may correct their own displayed identity.'
  ),
  now()
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,
  reviewed_at=now();

commit;
