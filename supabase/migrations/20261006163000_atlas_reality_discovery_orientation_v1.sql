begin;

-- Cold-start Reality Discovery orientation.
--
-- Orientation is not ontology and does not establish domain truth. It records
-- where the human says their world has weight so first-day Discovery can spend
-- attention there sooner. Its ranking influence decays as real answers accrue.

create table if not exists atlas.reality_discovery_orientation_events (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  source_action_id text not null,
  world_domains jsonb not null default '[]'::jsonb,
  carry_domains jsonb not null default '[]'::jsonb,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint reality_discovery_orientation_events_action_key unique(owner_user_id,source_action_id),
  constraint reality_discovery_orientation_world_array check(jsonb_typeof(world_domains)='array'),
  constraint reality_discovery_orientation_carry_array check(jsonb_typeof(carry_domains)='array')
);

create index if not exists reality_discovery_orientation_principal_latest_idx
  on atlas.reality_discovery_orientation_events(principal_id,occurred_at desc,id desc);

revoke all on table atlas.reality_discovery_orientation_events from public,anon,authenticated;
grant select,insert on table atlas.reality_discovery_orientation_events to service_role;

create or replace function atlas.reality_discovery_orientation_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  select * into v_event
  from atlas.reality_discovery_orientation_events
  where principal_id=v_principal_id and owner_user_id=v_user_id
  order by occurred_at desc,id desc
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_orientation_self_api_v1',
    'captured',v_event.id is not null,
    'worldDomains',coalesce(v_event.world_domains,'[]'::jsonb),
    'carryDomains',coalesce(v_event.carry_domains,'[]'::jsonb),
    'occurredAt',v_event.occurred_at,
    'truthBoundary',jsonb_build_object(
      'orientationIsColdStartEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'orientationMayReorderDiscovery',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_orientation_self_api_v1() from public,anon,authenticated;
grant execute on function atlas.reality_discovery_orientation_self_api_v1() to service_role;

create or replace function public.reality_discovery_orientation_self_api_v1()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog
as $function$
  select atlas.reality_discovery_orientation_self_api_v1();
$function$;

revoke all on function public.reality_discovery_orientation_self_api_v1() from public,anon;
grant execute on function public.reality_discovery_orientation_self_api_v1() to authenticated,service_role;

create or replace function atlas.set_reality_discovery_orientation_self_api_v1(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_source_action_id text;
  v_world jsonb;
  v_carry jsonb;
  v_existing atlas.reality_discovery_orientation_events%rowtype;
  v_event atlas.reality_discovery_orientation_events%rowtype;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;

  if v_principal_id is null then
    raise exception 'Active Principal required.' using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Orientation input must be an object.' using errcode='22023';
  end if;

  v_source_action_id:=nullif(trim(p_input->>'sourceActionId'),'');
  if v_source_action_id is null then
    raise exception 'sourceActionId required.' using errcode='22023';
  end if;

  if coalesce(jsonb_typeof(p_input->'worldDomains'),'array')<>'array'
     or coalesce(jsonb_typeof(p_input->'carryDomains'),'array')<>'array' then
    raise exception 'Orientation domains must be arrays.' using errcode='22023';
  end if;

  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
  into v_world
  from (
    select distinct trim(value) as domain
    from jsonb_array_elements_text(coalesce(p_input->'worldDomains','[]'::jsonb))
    where nullif(trim(value),'') is not null
  ) s;

  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
  into v_carry
  from (
    select distinct trim(value) as domain
    from jsonb_array_elements_text(coalesce(p_input->'carryDomains','[]'::jsonb))
    where nullif(trim(value),'') is not null
  ) s;

  if exists(
    select 1 from jsonb_array_elements_text(v_world) d(value)
    where d.value not in ('home','family','work','business','property','money','projects','school','community','care')
  ) then
    raise exception 'Unsupported world orientation domain.' using errcode='22023';
  end if;

  if exists(
    select 1 from jsonb_array_elements_text(v_carry) d(value)
    where d.value not in ('family','clients','employees','property','money','projects','care','community')
  ) then
    raise exception 'Unsupported responsibility orientation domain.' using errcode='22023';
  end if;

  if jsonb_array_length(v_world)+jsonb_array_length(v_carry)=0 then
    raise exception 'Choose at least one part of your world.' using errcode='22023';
  end if;

  select * into v_existing
  from atlas.reality_discovery_orientation_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;

  if v_existing.id is not null then
    if v_existing.world_domains is distinct from v_world
       or v_existing.carry_domains is distinct from v_carry then
      raise exception 'sourceActionId already belongs to different orientation evidence.' using errcode='23505';
    end if;

    return jsonb_build_object(
      'ok',true,
      'idempotentReplay',true,
      'orientation',atlas.reality_discovery_orientation_self_api_v1(),
      'set',atlas.reality_discovery_question_set_self_api_v1(4)
    );
  end if;

  insert into atlas.reality_discovery_orientation_events(
    principal_id,owner_user_id,source_action_id,world_domains,carry_domains,metadata
  ) values(
    v_principal_id,v_user_id,v_source_action_id,v_world,v_carry,
    jsonb_build_object('source','first_day_orientation_v1')
  )
  returning * into v_event;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','set_reality_discovery_orientation_self_api_v1',
    'eventId',v_event.id,
    'orientation',atlas.reality_discovery_orientation_self_api_v1(),
    'set',atlas.reality_discovery_question_set_self_api_v1(4),
    'truthBoundary',jsonb_build_object(
      'orientationIsHumanProvidedEvidence',true,
      'orientationDoesNotEstablishDomainTruth',true,
      'orientationOnlyChangesAttentionOrder',true,
      'orientationInfluenceDecaysAsAnswersAccrue',true
    )
  );
end;
$function$;

revoke all on function atlas.set_reality_discovery_orientation_self_api_v1(jsonb) from public,anon,authenticated;
grant execute on function atlas.set_reality_discovery_orientation_self_api_v1(jsonb) to service_role;

create or replace function public.set_reality_discovery_orientation_self_api_v1(p_input jsonb)
returns jsonb
language sql
security definer
set search_path=pg_catalog
as $function$
  select atlas.set_reality_discovery_orientation_self_api_v1(p_input);
$function$;

revoke all on function public.set_reality_discovery_orientation_self_api_v1(jsonb) from public,anon;
grant execute on function public.set_reality_discovery_orientation_self_api_v1(jsonb) to authenticated,service_role;

-- Existing first-day questions receive cold-start domains. These are ranking
-- hints only and do not change the meaning or ownership of their answers.
update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('home','family'),
      'orientationCarryDomains',jsonb_build_array('family','care')
    ),
    updated_at=now()
where question_key in ('household.people_shape','household.child_count','children.school_calendar');

update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('home','property'),
      'orientationCarryDomains',jsonb_build_array('property','money')
    ),
    updated_at=now()
where question_key in ('home.tenure','home.confirm_purchase_address','home.setting','home.dwelling_kind','home.major_repairs');

update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('home','projects'),
      'orientationCarryDomains',jsonb_build_array('projects')
    ),
    updated_at=now()
where question_key in ('grounds.responsibility','grounds.scale','grounds.mowing_method','equipment.riding_mower_identity','laundry.location');

update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('work','business','school','care'),
      'orientationCarryDomains',jsonb_build_array('clients','employees','projects','care','money')
    ),
    updated_at=now()
where question_key='life.weekday_anchor';

update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('home','work','business'),
      'orientationCarryDomains',jsonb_build_array('clients','projects')
    ),
    updated_at=now()
where question_key='transport.vehicle_count';

update atlas.reality_discovery_questions
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
      'orientationWorldDomains',jsonb_build_array('home','family','care'),
      'orientationCarryDomains',jsonb_build_array('care')
    ),
    updated_at=now()
where question_key='animals.responsibility';

-- Compact labels belong to the Encounter presentation contract rather than
-- the canonical question catalog. Keep stored answer keys and underlying
-- question definitions intact; return terse labels only when a question is
-- rendered to the human.
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
  v_label text;
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

  v_rules:=coalesce(v_rules,'{}'::jsonb);
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
      v_label:=case v_question_key
        when 'household.people_shape' then case v_option->>'key'
          when 'just_me' then 'me'
          when 'partner' then 'partner'
          when 'partner_children' then 'partner + kids'
          when 'children' then 'kids'
          when 'roommates' then 'others'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'home.tenure' then case v_option->>'key'
          when 'family_provided' then 'family'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'home.major_repairs' then case v_option->>'key'
          when 'me' then 'me'
          when 'shared' then 'shared'
          when 'landlord' then 'landlord'
          when 'depends' then 'depends'
          else v_option->>'label' end
        when 'grounds.responsibility' then case v_option->>'key'
          when 'yes' then 'me'
          when 'shared' then 'shared'
          when 'service' then 'other'
          when 'none' then 'none'
          else v_option->>'label' end
        when 'home.setting' then case v_option->>'key'
          when 'small_town' then 'town'
          when 'rural' then 'country'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'home.dwelling_kind' then case v_option->>'key'
          when 'manufactured' then 'mobile'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'laundry.location' then case v_option->>'key'
          when 'home' then 'home'
          when 'building' then 'shared'
          when 'service' then 'service'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'grounds.mowing_method' then case v_option->>'key'
          when 'push' then 'push'
          when 'riding' then 'riding'
          when 'service' then 'service'
          when 'other' then 'other'
          when 'none' then 'none'
          else v_option->>'label' end
        when 'transport.vehicle_count' then case v_option->>'key'
          when 'two_plus' then '2+'
          when 'other' then 'other'
          else v_option->>'label' end
        when 'life.weekday_anchor' then case v_option->>'key'
          when 'job' then 'job'
          when 'business' then 'business'
          when 'caregiving' then 'care'
          when 'home' then 'home'
          when 'mixed' then 'mixed'
          else v_option->>'label' end
        else v_option->>'label'
      end;

      if v_label is not null then
        v_option:=jsonb_set(v_option,'{label}',to_jsonb(v_label),true);
      end if;
      v_filtered:=v_filtered||jsonb_build_array(v_option);
    end if;
  end loop;

  return p_question||jsonb_build_object('options',v_filtered);
end;
$function$;

revoke all on function atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function atlas.reality_discovery_apply_option_eligibility_v1(jsonb,jsonb) to service_role;

-- New first-day questions let orientation open real work/property discovery
-- instead of forcing every person through household detail first.
insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,
  base_score,friction,consequence_value,information_gain,resolved_signal_key,
  reason_text,active,metadata
) values
(
  'work.structure','work','How does work fit your life?',null,'single_choice',
  '[{"key":"job","label":"job"},{"key":"business","label":"business"},{"key":"both","label":"both"},{"key":"other","label":"other"}]'::jsonb,
  82,1,85,96,'work.structure',
  'Work structure decides whether employee, owner, client, payroll, and operating branches deserve attention.',
  true,
  jsonb_build_object(
    'encounterCluster','work_business',
    'encounterClusterLabel','WORK + BUSINESS',
    'orientationWorldDomains',jsonb_build_array('work','business'),
    'orientationCarryDomains',jsonb_build_array('clients','employees','projects','money')
  )
),
(
  'business.count','work','Businesses?',null,'single_choice',
  '[{"key":"one","label":"one"},{"key":"several","label":"several"}]'::jsonb,
  78,1,90,92,'business.count',
  'Business count changes whether Atlas should discover one operating system or a portfolio of distinct responsibilities.',
  true,
  jsonb_build_object(
    'encounterCluster','work_business',
    'encounterClusterLabel','WORK + BUSINESS',
    'orientationWorldDomains',jsonb_build_array('business'),
    'orientationCarryDomains',jsonb_build_array('employees','clients','money','projects')
  )
),
(
  'work.client_responsibility','work','Clients?',null,'yes_no',
  '[{"key":"yes","label":"yes"},{"key":"no","label":"no"}]'::jsonb,
  60,1,78,82,'work.has_clients',
  'Client responsibility activates recurring relationship, deadline, correspondence, and money branches.',
  true,
  jsonb_build_object(
    'encounterCluster','work_business',
    'encounterClusterLabel','WORK + BUSINESS',
    'orientationWorldDomains',jsonb_build_array('work','business'),
    'orientationCarryDomains',jsonb_build_array('clients')
  )
),
(
  'property.relationship','property','Property?',null,'single_choice',
  '[{"key":"home","label":"home"},{"key":"rentals","label":"rentals"},{"key":"client","label":"clients"},{"key":"mixed","label":"mixed"}]'::jsonb,
  84,1,90,96,'property.relationship',
  'Property relationship distinguishes personal residence, rental portfolio, and client-facing property responsibility.',
  true,
  jsonb_build_object(
    'encounterCluster','property',
    'encounterClusterLabel','PROPERTY',
    'orientationWorldDomains',jsonb_build_array('property'),
    'orientationCarryDomains',jsonb_build_array('property','money','clients','projects')
  )
),
(
  'property.portfolio_size','property','Rental properties?',null,'single_choice',
  '[{"key":"one","label":"1"},{"key":"two_five","label":"2–5"},{"key":"six_plus","label":"6+"}]'::jsonb,
  72,1,86,90,'property.portfolio_size',
  'Rental portfolio size changes the scale of maintenance, tenant, insurance, tax, financing, and recurring operational responsibility.',
  true,
  jsonb_build_object(
    'encounterCluster','property',
    'encounterClusterLabel','PROPERTY',
    'orientationWorldDomains',jsonb_build_array('property'),
    'orientationCarryDomains',jsonb_build_array('property','money','projects')
  )
)
on conflict(question_key) do update set
  section_key=excluded.section_key,
  prompt=excluded.prompt,
  help_text=excluded.help_text,
  answer_kind=excluded.answer_kind,
  options=excluded.options,
  base_score=excluded.base_score,
  friction=excluded.friction,
  consequence_value=excluded.consequence_value,
  information_gain=excluded.information_gain,
  resolved_signal_key=excluded.resolved_signal_key,
  reason_text=excluded.reason_text,
  active=excluded.active,
  metadata=excluded.metadata,
  updated_at=now();

insert into atlas.reality_discovery_encounter_admission(
  question_key,admission_class,first_day_disposition,reason_text,metadata
) values
(
  'work.structure','foundation','admit',
  'Work structure is a high-leverage first-day branch when the human says work or business carries weight.',
  '{}'::jsonb
),
(
  'business.count','high_leverage','admit',
  'Business count prevents Atlas from treating a multi-business operator like a single-job household.',
  '{}'::jsonb
),
(
  'work.client_responsibility','high_leverage','admit',
  'Client responsibility materially changes correspondence, calendar, money, and commitment discovery.',
  '{}'::jsonb
),
(
  'property.relationship','foundation','admit',
  'Property relationship is foundational when property is a meaningful part of the human world.',
  '{}'::jsonb
),
(
  'property.portfolio_size','high_leverage','admit',
  'Rental portfolio scale materially changes the operating burden Atlas should discover next.',
  '{}'::jsonb
)
on conflict(question_key) do update set
  admission_class=excluded.admission_class,
  first_day_disposition=excluded.first_day_disposition,
  reason_text=excluded.reason_text,
  metadata=excluded.metadata,
  updated_at=now();

insert into atlas.reality_discovery_edges(
  question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text
) values
(
  'business.count','work.structure','in','["business","both"]'::jsonb,'require',0,
  'Business count is relevant only after work structure establishes business responsibility.'
),
(
  'work.client_responsibility','work.structure','exists',null,'require',0,
  'Client responsibility is asked only after Atlas has a basic work structure.'
),
(
  'property.portfolio_size','property.relationship','in','["rentals","mixed"]'::jsonb,'require',0,
  'Rental portfolio size is relevant only when rentals are part of the property relationship.'
)
on conflict do nothing;

create or replace function atlas.reality_discovery_ranked_questions_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_context jsonb;
  v_source_coverage jsonb;
  v_orientation jsonb;
  v_world jsonb;
  v_carry jsonb;
  v_signals jsonb;
  v_answers jsonb;
  v_answer_count integer;
  v_orientation_factor integer;
  v_items jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_source_coverage:=atlas.reality_discovery_source_coverage_self_api_v1();
  v_orientation:=atlas.reality_discovery_orientation_self_api_v1();
  v_context:=v_context||jsonb_build_object(
    'sourceCoverage',v_source_coverage,
    'orientation',v_orientation
  );
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);
  v_answers:=coalesce(v_context->'answers','{}'::jsonb);
  v_world:=coalesce(v_orientation->'worldDomains','[]'::jsonb);
  v_carry:=coalesce(v_orientation->'carryDomains','[]'::jsonb);
  v_answer_count:=jsonb_object_length(v_answers);
  v_orientation_factor:=case
    when v_answer_count>=12 then 0
    when v_answer_count>=6 then 50
    else 100
  end;

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
      (
        (
          case
            when v_orientation_factor>0
             and jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
             and exists(
               select 1
               from jsonb_array_elements_text(q.metadata->'orientationWorldDomains') d(domain)
               where v_world ? d.domain
             )
            then 110*v_orientation_factor/100
            else 0
          end
        )
        +
        (
          case
            when v_orientation_factor>0
             and jsonb_typeof(q.metadata->'orientationCarryDomains')='array'
             and exists(
               select 1
               from jsonb_array_elements_text(q.metadata->'orientationCarryDomains') d(domain)
               where v_carry ? d.domain
             )
            then 145*v_orientation_factor/100
            else 0
          end
        )
      )::integer as orientation_boost,
      (q.base_score+q.consequence_value+q.information_gain-q.friction
       +coalesce(sum(e.weight) filter(where e.effect_kind='boost' and e.matched),0)
       +(
          case
            when v_orientation_factor>0
             and jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
             and exists(
               select 1
               from jsonb_array_elements_text(q.metadata->'orientationWorldDomains') d(domain)
               where v_world ? d.domain
             )
            then 110*v_orientation_factor/100
            else 0
          end
        )
       +(
          case
            when v_orientation_factor>0
             and jsonb_typeof(q.metadata->'orientationCarryDomains')='array'
             and exists(
               select 1
               from jsonb_array_elements_text(q.metadata->'orientationCarryDomains') d(domain)
               where v_carry ? d.domain
             )
            then 145*v_orientation_factor/100
            else 0
          end
        )
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
    'orientationBoost',e.orientation_boost,
    'reason',e.reason_text,
    'matchedReasons',case
      when e.source_coverage_penalty>0
      then e.matched_reasons||jsonb_build_array('Atlas has an authorized, recently synced source that may provide evidence here, so this question was moved later rather than suppressed.')
      else e.matched_reasons
    end,
    'sourceCoveragePenalty',e.source_coverage_penalty,
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
      'sourceCoverageMayReorderButNeverSuppress',true,
      'sourceCoverageDoesNotAnswerQuestions',true,
      'orientationMayReorderButNeverAnswer',true,
      'orientationInfluenceDecaysWithEstablishedAnswers',true,
      'rankingDoesNotEstablishDomainTruth',true
    )
  );
end;
$function$;

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
  v_orientation_captured boolean := false;
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
  v_orientation_captured:=coalesce((v_context#>>'{orientation,captured}')::boolean,false);

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

    -- Preserve the old home-first fallback only when no cold-start orientation
    -- exists. Once the human points Atlas toward their high-gravity domains,
    -- unrelated household topology no longer blocks those domains.
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
      'contractVersion','reality_discovery_question_set_v3',
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
        'orientationCanChooseFirstDayDomain',true,
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
    'contractVersion','reality_discovery_question_set_v3',
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
      'orientationMayChooseTheCurrentDiscoveryCluster',true,
      'rankingDoesNotEstablishDomainTruth',true
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
  'atlas.reality_discovery_orientation_self_api_v1()',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Read the authenticated Principal latest first-day orientation evidence.',
    'truthBoundary','Orientation affects attention order only and does not establish domain truth.'
  ),
  now()
),
(
  'atlas.set_reality_discovery_orientation_self_api_v1(p_input jsonb)',
  'app_endpoint','verified','active',true,true,true,false,1,0,
  jsonb_build_object(
    'purpose','Append human-provided cold-start orientation evidence for first-day Reality Discovery.',
    'truthBoundary','Orientation is a decaying ranking prior and never answers Discovery questions.'
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
