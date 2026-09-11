-- Architecture candidate only. Not a canonical migration.
--
-- Purpose: separate Reality Discovery question ranking from encounter admission.
-- Ranking answers "which eligible unresolved question is best?".
-- Admission answers "has any question earned attention in this encounter?".
--
-- This file is intentionally not under supabase/migrations/. A canonical migration
-- must be generated through the repository's pinned Supabase migration workflow.

begin;

create table if not exists atlas.reality_discovery_encounter_admission (
  question_key text primary key references atlas.reality_discovery_questions(question_key) on delete cascade,
  admission_class text not null check (
    admission_class in (
      'foundation',
      'near_consequence',
      'high_leverage',
      'specialization',
      'nice_to_know',
      'just_in_time'
    )
  ),
  first_day_disposition text not null check (
    first_day_disposition in ('admit','conditional','defer')
  ),
  reason_text text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table atlas.reality_discovery_encounter_admission enable row level security;
revoke all on atlas.reality_discovery_encounter_admission from public,anon,authenticated;

insert into atlas.reality_discovery_encounter_admission(
  question_key,admission_class,first_day_disposition,reason_text,metadata
) values
('home.confirm_purchase_address','foundation','admit',
 'Confirming an already-supplied residence candidate establishes broad jurisdiction/place context without forcing the human to recreate evidence.',
 '{"candidateBound":true}'::jsonb),
('household.people_shape','foundation','admit',
 'Household shape eliminates or raises multiple downstream caregiving, calendar, food, laundry, vehicle, and responsibility branches.',
 '{}'::jsonb),
('home.tenure','foundation','admit',
 'Residence tenure changes the responsibility model for many home and administrative consequences.',
 '{}'::jsonb),
('home.major_repairs','foundation','admit',
 'Major-repair responsibility distinguishes household work from landlord or management responsibility.',
 '{}'::jsonb),
('home.setting','foundation','admit',
 'Broad physical setting materially changes the plausibility of transportation, grounds, shared-building, and equipment branches.',
 '{}'::jsonb),
('home.dwelling_kind','foundation','admit',
 'Dwelling form changes which home systems and shared-building boundaries are worth discovering.',
 '{}'::jsonb),
('grounds.responsibility','foundation','admit',
 'Grounds responsibility establishes whether outdoor maintenance belongs in the household world at all.',
 '{}'::jsonb),
('transport.vehicle_count','foundation','admit',
 'Vehicle responsibility activates or eliminates multiple registration, insurance, tax, and maintenance branches.',
 '{}'::jsonb),
('household.child_count','high_leverage','admit',
 'Child-count scale materially changes school, transport, laundry, food, care, and coordination discovery.',
 '{}'::jsonb),
('children.school_calendar','high_leverage','admit',
 'School-calendar applicability can replace repeated future questioning with one durable source relationship.',
 '{}'::jsonb),
('animals.responsibility','high_leverage','admit',
 'Animal responsibility determines whether recurring care, supply, veterinary, medication, and licensing branches belong here.',
 '{}'::jsonb),
('life.weekday_anchor','foundation','admit',
 'The ordinary weekday anchor establishes broad recurring time structure that changes later discovery and planning.',
 '{}'::jsonb),
('laundry.location','high_leverage','admit',
 'Laundry location selects among materially different household operating models, especially for rental/shared-building contexts.',
 '{}'::jsonb),
('grounds.scale','high_leverage','admit',
 'Outdoor scale changes whether equipment and seasonal land-care discovery is worth pursuing.',
 '{}'::jsonb),
('grounds.mowing_method','specialization','defer',
 'Mowing method specializes already-established grounds responsibility and does not by itself deserve first-day attention.',
 '{}'::jsonb),
('equipment.riding_mower_identity','specialization','defer',
 'Exact mower identity is useful for later maintenance specialization but need not consume first-day attention.',
 '{}'::jsonb)
on conflict(question_key) do update set
  admission_class=excluded.admission_class,
  first_day_disposition=excluded.first_day_disposition,
  reason_text=excluded.reason_text,
  metadata=excluded.metadata,
  updated_at=now();

create or replace function atlas.reality_discovery_ranked_questions_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_signals jsonb;
  v_answers jsonb;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_context:=atlas.reality_discovery_context_self_api_v1();
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
      (q.base_score+q.consequence_value+q.information_gain-q.friction
       +coalesce(sum(e.weight) filter(where e.effect_kind='boost' and e.matched),0))::integer as score,
      coalesce(bool_and(e.matched) filter(where e.effect_kind='require'),true) as requirements_met,
      coalesce(bool_or(e.matched) filter(where e.effect_kind='suppress'),false) as suppressed,
      coalesce(jsonb_agg(e.reason_text) filter(
        where e.effect_kind='boost' and e.matched and e.reason_text is not null
      ),'[]'::jsonb) as matched_reasons
    from atlas.reality_discovery_questions q
    left join edge_eval e on e.question_key=q.question_key
    where q.active
    group by q.question_key
  ), eligible as (
    select s.*
    from scored s
    where s.requirements_met
      and not s.suppressed
      and not (v_answers ? s.question_key)
      and not (
        coalesce((s.metadata->>'requiresCandidate')::boolean,false)
        and coalesce(v_signals->(s.metadata->>'candidateSignalKey'),'null'::jsonb)='null'::jsonb
      )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'questionKey',e.question_key,
    'sectionKey',e.section_key,
    'prompt',e.prompt,
    'helpText',e.help_text,
    'answerKind',e.answer_kind,
    'options',e.options,
    'score',e.score,
    'reason',e.reason_text,
    'matchedReasons',e.matched_reasons,
    'candidateValue',case when coalesce((e.metadata->>'requiresCandidate')::boolean,false)
      then v_signals->(e.metadata->>'candidateSignalKey') else null end
  ) order by e.score desc,e.question_key),'[]'::jsonb)
  into v_items
  from eligible e;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_ranked_questions_self_api_v1',
    'items',v_items,
    'context',v_context,
    'truthBoundary',jsonb_build_object(
      'rankingOrdersEligibleQuestions',true,
      'rankingDoesNotCreateEncounterAdmission',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

create or replace function atlas.reality_discovery_next_question_for_encounter_self_api_v1(
  p_session_kind text
)
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_kind text;
  v_ranked jsonb;
  v_context jsonb;
  v_question jsonb;
  v_question_key text;
  v_policy atlas.reality_discovery_encounter_admission%rowtype;
  v_has_eligible boolean:=false;
  v_deferred_count integer:=0;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_kind:=coalesce(nullif(trim(p_session_kind),''),'first_day');
  if v_kind not in ('first_day','manual','micro') then
    raise exception 'Unsupported discovery encounter kind.' using errcode='22023';
  end if;

  v_ranked:=atlas.reality_discovery_ranked_questions_self_api_v1();
  v_context:=v_ranked->'context';
  v_has_eligible:=jsonb_array_length(coalesce(v_ranked->'items','[]'::jsonb))>0;

  for v_question in
    select value from jsonb_array_elements(coalesce(v_ranked->'items','[]'::jsonb))
  loop
    v_question_key:=v_question->>'questionKey';
    select * into v_policy
    from atlas.reality_discovery_encounter_admission
    where question_key=v_question_key;

    if v_policy.question_key is null then
      -- Fail closed: an unclassified question cannot silently acquire first-day attention.
      if v_kind='manual' then
        return jsonb_build_object(
          'ok',true,
          'contractVersion','reality_discovery_next_question_for_encounter_self_api_v1',
          'encounterKind',v_kind,
          'question',v_question || jsonb_build_object(
            'admissionClass','unclassified',
            'admissionReason','The human explicitly opened broader Discovery; this question has no first-day admission classification yet.'
          ),
          'quiet',false,
          'context',v_context
        );
      end if;
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    if v_kind='manual' then
      return jsonb_build_object(
        'ok',true,
        'contractVersion','reality_discovery_next_question_for_encounter_self_api_v1',
        'encounterKind',v_kind,
        'question',v_question || jsonb_build_object(
          'admissionClass',v_policy.admission_class,
          'admissionReason',v_policy.reason_text
        ),
        'quiet',false,
        'context',v_context
      );
    end if;

    if v_kind='micro' then
      -- V1 intentionally fails closed until a bounded micro-question warrant is supplied.
      v_deferred_count:=v_deferred_count+1;
      continue;
    end if;

    if v_policy.first_day_disposition='admit' then
      return jsonb_build_object(
        'ok',true,
        'contractVersion','reality_discovery_next_question_for_encounter_self_api_v1',
        'encounterKind',v_kind,
        'question',v_question || jsonb_build_object(
          'admissionClass',v_policy.admission_class,
          'admissionReason',v_policy.reason_text
        ),
        'quiet',false,
        'context',v_context
      );
    end if;

    -- Conditional admission exists as an explicit future seam. V1 does not convert
    -- score, probability, or generic relevance into consequence evidence.
    v_deferred_count:=v_deferred_count+1;
  end loop;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_next_question_for_encounter_self_api_v1',
    'encounterKind',v_kind,
    'question',null,
    'quiet',true,
    'message',case
      when v_has_eligible and v_deferred_count>0 then 'I know enough here for now.'
      else 'I know enough here for now.'
    end,
    'eligibleUnansweredRemain',v_has_eligible,
    'deferredCount',v_deferred_count,
    'context',v_context,
    'truthBoundary',jsonb_build_object(
      'quietMeansNoQuestionAdmittedForThisEncounter',true,
      'quietDoesNotMeanDiscoveryComplete',true,
      'deferredQuestionsRemainUnanswered',true,
      'scoreDoesNotCreateAttentionEntitlement',true,
      'microAdmissionRequiresSeparateWarrant',true
    )
  );
end;
$function$;

-- Preserve the current public/client contract. Resolve first_day unless a current
-- active session explicitly establishes another supported session kind.
create or replace function atlas.reality_discovery_next_question_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_kind text:='first_day';
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select id into v_principal_id from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  select s.session_kind into v_kind
  from atlas.reality_discovery_sessions s
  where s.principal_id=v_principal_id
    and s.owner_user_id=v_user_id
    and s.state='active'
  order by s.last_opened_at desc,s.started_at desc,s.id
  limit 1;

  v_kind:=coalesce(v_kind,'first_day');
  return atlas.reality_discovery_next_question_for_encounter_self_api_v1(v_kind);
end;
$function$;

revoke all on function atlas.reality_discovery_ranked_questions_self_api_v1() from public,anon,authenticated;
revoke all on function atlas.reality_discovery_next_question_for_encounter_self_api_v1(text) from public,anon,authenticated;
grant execute on function atlas.reality_discovery_ranked_questions_self_api_v1() to service_role;
grant execute on function atlas.reality_discovery_next_question_for_encounter_self_api_v1(text) to service_role;

-- Existing public wrapper and authenticated grant for
-- reality_discovery_next_question_self_api_v1() remain unchanged.

commit;
