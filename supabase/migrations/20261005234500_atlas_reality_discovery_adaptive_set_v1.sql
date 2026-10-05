begin;

-- Adaptive Reality Discovery question sets.
--
-- Presentation may expose a small coherent set of admitted questions at once,
-- but every answer remains append-only Discovery evidence and downstream truth
-- still belongs to its owning domain. The set is recomputed after every answer
-- or evidence change; it is not a fixed wizard page.

update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'encounterCluster','you_home',
      'encounterClusterLabel','YOU + HOME'
    ),
    updated_at = now()
where question_key in (
  'home.confirm_purchase_address',
  'household.people_shape',
  'home.tenure',
  'home.major_repairs',
  'household.child_count'
);

update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'encounterCluster','home_place',
      'encounterClusterLabel','HOME + PLACE'
    ),
    updated_at = now()
where question_key in (
  'home.setting',
  'home.dwelling_kind',
  'grounds.responsibility',
  'laundry.location'
);

update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'encounterCluster','your_world',
      'encounterClusterLabel','YOUR WORLD'
    ),
    updated_at = now()
where question_key in (
  'life.weekday_anchor',
  'transport.vehicle_count',
  'animals.responsibility',
  'children.school_calendar'
);

update atlas.reality_discovery_questions
set metadata = coalesce(metadata,'{}'::jsonb) || jsonb_build_object(
      'encounterCluster','grounds',
      'encounterClusterLabel','GROUNDS'
    ),
    updated_at = now()
where question_key in (
  'grounds.scale',
  'grounds.mowing_method',
  'equipment.riding_mower_identity'
);

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

  -- The first admitted question anchors a coherent presentation cluster.
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
      'contractVersion','reality_discovery_question_set_v1',
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
        'microAdmissionRequiresSeparateWarrant',true
      )
    );
  end if;

  -- Keep the visible set coherent. Do not fill a sparse cluster with unrelated
  -- questions merely to reach a visual target.
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
    'contractVersion','reality_discovery_question_set_v1',
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
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

create or replace function atlas.reality_discovery_question_set_self_api_v1(
  p_limit integer default 4
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
  v_kind text := 'first_day';
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select s.session_kind into v_kind
  from atlas.reality_discovery_sessions s
  where s.principal_id=v_principal_id
    and s.owner_user_id=v_user_id
    and s.state='active'
  order by s.last_opened_at desc,s.started_at desc,s.id
  limit 1;

  return atlas.reality_discovery_question_set_for_encounter_self_api_v1(coalesce(v_kind,'first_day'),p_limit);
end;
$function$;

revoke all on function atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer) from public,anon,authenticated;
grant execute on function atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer) to service_role;

revoke all on function atlas.reality_discovery_question_set_self_api_v1(integer) from public,anon;
grant execute on function atlas.reality_discovery_question_set_self_api_v1(integer) to authenticated,service_role;

create or replace function public.reality_discovery_question_set_self_api_v1(p_limit integer default 4)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_question_set_self_api_v1(p_limit);
$function$;

revoke all on function public.reality_discovery_question_set_self_api_v1(integer) from public,anon;
grant execute on function public.reality_discovery_question_set_self_api_v1(integer) to authenticated,service_role;

-- Preserve the existing answer command and its promotion rules, but allow a
-- human to answer any question that is still a member of the current governed
-- Encounter set. A stale/replaced question is still rejected.
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
    if not exists(select 1 from jsonb_array_elements(v_question.options) o where o->>'key'=v_answer_scalar) then
      raise exception 'Unsupported answer option.' using errcode='22023';
    end if;
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
      'residencePromotionRequiresConfirmedResidenceIdentity',true,
      'residencePromotionUsesResidenceAuthority',true,
      'inferenceMayRerankButNotEstablishTruth',true,
      'setMembershipDoesNotCreateTruth',true,
      'staleQuestionSubmissionRejected',true
    )
  );
end;
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
(
  'atlas.reality_discovery_question_set_self_api_v1(p_limit integer)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Return a small coherent adaptive set of currently admitted Reality Discovery questions for the authenticated Principal.',
    'truthBoundary','Set membership governs presentation only; it does not answer or establish downstream truth.'
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
