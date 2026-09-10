-- Adaptive Reality Discovery for Personal Atlas.
--
-- This subsystem owns discovery questions, answer evidence, candidate evidence, ranking, and routing metadata.
-- It does NOT own Person, Household, Home, Vehicle, Animal, Money, Health, Calendar, Organization, or kernel truth.
-- Inference may rank/suppress questions. It never silently establishes downstream reality.

create table if not exists atlas.reality_discovery_questions (
  question_key text primary key,
  section_key text not null,
  prompt text not null,
  help_text text,
  answer_kind text not null check (answer_kind in ('single_choice','yes_no','short_text')),
  options jsonb not null default '[]'::jsonb,
  base_score integer not null default 0,
  friction integer not null default 1 check (friction between 0 and 100),
  consequence_value integer not null default 0,
  information_gain integer not null default 0,
  resolved_signal_key text,
  reason_text text not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists atlas.reality_discovery_edges (
  id uuid primary key default gen_random_uuid(),
  question_key text not null references atlas.reality_discovery_questions(question_key) on delete cascade,
  signal_key text not null,
  operator text not null check (operator in ('exists','eq','neq','in','not_in')),
  compare_value jsonb,
  effect_kind text not null check (effect_kind in ('require','boost','suppress')),
  weight integer not null default 0,
  reason_text text,
  created_at timestamptz not null default now()
);

create index if not exists reality_discovery_edges_question_idx on atlas.reality_discovery_edges(question_key,effect_kind);
create index if not exists reality_discovery_edges_signal_idx on atlas.reality_discovery_edges(signal_key);

create table if not exists atlas.reality_discovery_answer_events (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  question_key text not null references atlas.reality_discovery_questions(question_key),
  source_action_id text not null,
  answer_value jsonb not null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(owner_user_id,source_action_id)
);

create index if not exists reality_discovery_answer_events_principal_question_idx
  on atlas.reality_discovery_answer_events(principal_id,question_key,occurred_at desc);

create table if not exists atlas.reality_discovery_evidence_candidates (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid not null references atlas.principals(id) on delete cascade,
  owner_user_id uuid not null,
  signal_key text not null,
  candidate_value jsonb not null,
  epistemic_state text not null check (epistemic_state in ('source_candidate','inferred_candidate','human_confirmed','human_rejected','promoted','superseded')),
  source_kind text not null,
  source_ref text,
  confidence numeric(5,4) check (confidence is null or (confidence>=0 and confidence<=1)),
  explanation text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reality_discovery_candidates_principal_signal_idx
  on atlas.reality_discovery_evidence_candidates(principal_id,signal_key,epistemic_state,updated_at desc);

alter table atlas.reality_discovery_questions enable row level security;
alter table atlas.reality_discovery_edges enable row level security;
alter table atlas.reality_discovery_answer_events enable row level security;
alter table atlas.reality_discovery_evidence_candidates enable row level security;
revoke all on atlas.reality_discovery_questions from public,anon,authenticated;
revoke all on atlas.reality_discovery_edges from public,anon,authenticated;
revoke all on atlas.reality_discovery_answer_events from public,anon,authenticated;
revoke all on atlas.reality_discovery_evidence_candidates from public,anon,authenticated;

-- Seed only broad, high-information questions plus enough downstream questions to prove adaptive branching.
insert into atlas.reality_discovery_questions(
  question_key,section_key,prompt,help_text,answer_kind,options,base_score,friction,consequence_value,information_gain,resolved_signal_key,reason_text,metadata
) values
('home.confirm_purchase_address','home','Is this where you live?','Atlas may have an address from your purchase. It will not treat it as home until you confirm it.','yes_no',
 '[{"key":"yes","label":"yes"},{"key":"no","label":"no"}]'::jsonb,80,1,55,90,'home.purchase_address_confirmed','Confirming an address Atlas already has can establish jurisdiction context without making you retype it.',
 '{"candidateSignalKey":"purchase.billing_address","requiresCandidate":true}'::jsonb),
('home.tenure','home','Do you own this home, rent it, or is it another arrangement?',null,'single_choice',
 '[{"key":"own","label":"own"},{"key":"rent","label":"rent"},{"key":"family_provided","label":"family provides it"},{"key":"other","label":"something else"}]'::jsonb,75,1,80,95,'home.tenure','This answer changes which home systems and obligations are likely to be yours.', '{}'::jsonb),
('home.major_repairs','home','When something major breaks here, who normally handles it?',null,'single_choice',
 '[{"key":"me","label":"I do"},{"key":"shared","label":"we share it"},{"key":"landlord","label":"landlord / management"},{"key":"depends","label":"it depends"}]'::jsonb,55,1,80,85,'home.major_repairs_responsibility','Responsibility matters more than simply knowing a home system exists.', '{}'::jsonb),
('grounds.responsibility','home','Are you responsible for any yard or land where you live?',null,'single_choice',
 '[{"key":"yes","label":"yes"},{"key":"shared","label":"shared"},{"key":"service","label":"someone else handles it"},{"key":"none","label":"no"}]'::jsonb,40,1,55,75,'grounds.responsibility','Grounds responsibility determines whether outdoor maintenance and equipment belong in your world.', '{}'::jsonb),
('grounds.mowing_method','home','How does mowing usually get handled?',null,'single_choice',
 '[{"key":"push","label":"push mower"},{"key":"riding","label":"riding mower"},{"key":"tractor","label":"tractor"},{"key":"service","label":"lawn service"},{"key":"other","label":"something else"},{"key":"none","label":"we do not mow"}]'::jsonb,30,1,45,70,'grounds.mowing_method','How mowing happens determines whether Atlas should learn about maintainable equipment.', '{}'::jsonb),
('equipment.riding_mower_identity','home','What riding mower is it?','Pick a common brand or tell Atlas later; the maintenance kernel can become more specific once the actual machine is known.','single_choice',
 '[{"key":"john_deere","label":"John Deere"},{"key":"cub_cadet","label":"Cub Cadet"},{"key":"husqvarna","label":"Husqvarna"},{"key":"other","label":"other"},{"key":"not_sure","label":"not sure"}]'::jsonb,20,1,45,55,'equipment.riding_mower_brand','The actual equipment changes the maintenance information Atlas should use.', '{}'::jsonb),
('transport.vehicle_count','transport','Are you responsible for any vehicles?',null,'single_choice',
 '[{"key":"none","label":"none"},{"key":"one","label":"one"},{"key":"two_plus","label":"two or more"},{"key":"other","label":"something else"}]'::jsonb,65,1,85,90,'transport.vehicle_count','Vehicles create predictable registration, insurance, tax, and maintenance obligations.', '{}'::jsonb),
('animals.responsibility','animals','Are there animals you are responsible for?',null,'single_choice',
 '[{"key":"none","label":"none"},{"key":"dog","label":"dog"},{"key":"cat","label":"cat"},{"key":"livestock","label":"livestock"},{"key":"other","label":"other"}]'::jsonb,35,1,45,60,'animals.responsibility','Animals can create recurring care, supplies, veterinary, medication, and licensing obligations.', '{}'::jsonb),
('children.school_calendar','people','Do any of the kids use a school, preschool, or daycare calendar?',null,'yes_no',
 '[{"key":"yes","label":"yes"},{"key":"no","label":"no"}]'::jsonb,45,1,65,75,'children.school_calendar','Known children make school/calendar structure a potentially high-value branch.', '{}'::jsonb),
('life.weekday_anchor','time','What sets most of your ordinary weekday schedule?',null,'single_choice',
 '[{"key":"job","label":"a job"},{"key":"business","label":"my business"},{"key":"school","label":"school"},{"key":"caregiving","label":"caregiving"},{"key":"home","label":"home life"},{"key":"mixed","label":"a mix"}]'::jsonb,50,1,75,80,'life.weekday_anchor','The main weekday anchor helps Atlas understand what kinds of recurring time structure to discover next.', '{}'::jsonb),
('laundry.location','home','How does laundry work where you live?',null,'single_choice',
 '[{"key":"home","label":"machines in my home"},{"key":"building","label":"shared building machines"},{"key":"laundromat","label":"laundromat"},{"key":"service","label":"service / someone else"},{"key":"other","label":"other"}]'::jsonb,25,1,35,55,'laundry.location','Housing arrangement changes which ordinary laundry model is likely to fit.', '{}'::jsonb)
on conflict(question_key) do update set
  section_key=excluded.section_key,prompt=excluded.prompt,help_text=excluded.help_text,answer_kind=excluded.answer_kind,
  options=excluded.options,base_score=excluded.base_score,friction=excluded.friction,consequence_value=excluded.consequence_value,
  information_gain=excluded.information_gain,resolved_signal_key=excluded.resolved_signal_key,reason_text=excluded.reason_text,
  active=true,metadata=excluded.metadata,updated_at=now();

-- Graph rules. Require edges are ANDed. Any matching suppress edge removes a question. Boost edges add weight.
insert into atlas.reality_discovery_edges(question_key,signal_key,operator,compare_value,effect_kind,weight,reason_text) values
('home.confirm_purchase_address','purchase.billing_address','exists',null,'require',0,'Only ask when Atlas actually has an address candidate.'),
('home.tenure','home.address_confirmed','eq','true'::jsonb,'boost',35,'Confirmed residence makes tenure immediately useful.'),
('home.major_repairs','home.tenure','in','["rent","family_provided","other"]'::jsonb,'boost',45,'Non-owner housing makes repair responsibility especially important.'),
('grounds.responsibility','home.tenure','eq','"own"'::jsonb,'boost',45,'Ownership raises the value of asking about grounds responsibility.'),
('grounds.responsibility','home.major_repairs_responsibility','eq','"landlord"'::jsonb,'suppress',0,'Management-owned major maintenance makes grounds responsibility lower-value in ordinary apartment-like cases.'),
('grounds.mowing_method','grounds.responsibility','in','["yes","shared"]'::jsonb,'require',0,'Mowing method matters only after grounds responsibility exists.'),
('equipment.riding_mower_identity','grounds.mowing_method','eq','"riding"'::jsonb,'require',0,'Do not ask about a riding mower unless the user said mowing uses one.'),
('transport.vehicle_count','household.member_count','gte'::jsonb->>0,'boost',0,'placeholder'),
('transport.vehicle_count','home.tenure','eq','"own"'::jsonb,'boost',10,'Owner households often benefit from early vehicle/admin mapping.'),
('transport.vehicle_count','context.dense_urban_renter','eq','true'::jsonb,'boost',-15,'Dense urban renter context lowers but does not suppress vehicle responsibility.'),
('animals.responsibility','household.has_children','eq','true'::jsonb,'boost',10,'Known children modestly raise the value of checking animal responsibility.'),
('animals.responsibility','context.low_density_owner_household','eq','true'::jsonb,'boost',15,'Low-density owner household context modestly raises animal-care applicability.'),
('children.school_calendar','household.has_children','eq','true'::jsonb,'require',0,'Do not ask about children school calendars when no children are known.'),
('laundry.location','home.tenure','eq','"rent"'::jsonb,'boost',15,'Rental housing makes laundry location especially useful.'),
('laundry.location','household.member_count_bucket','eq','"one"'::jsonb,'boost',10,'One-person housing can often resolve laundry structure with one tap.')
on conflict do nothing;

-- Remove the deliberately unsupported placeholder edge if present; numeric comparison is not part of V1 operators.
delete from atlas.reality_discovery_edges
where question_key='transport.vehicle_count' and signal_key='household.member_count' and reason_text='placeholder';

create or replace function atlas.reality_discovery_latest_answers_v1(p_principal_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,atlas
as $function$
  with ranked as (
    select distinct on (question_key)
      question_key,answer_value,occurred_at
    from atlas.reality_discovery_answer_events
    where principal_id=p_principal_id
    order by question_key,occurred_at desc,id desc
  )
  select coalesce(jsonb_object_agg(question_key,answer_value),'{}'::jsonb) from ranked;
$function$;

create or replace function atlas.reality_discovery_context_self_api_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user_id uuid;
  v_principal atlas.principals%rowtype;
  v_household atlas.households%rowtype;
  v_member_count integer:=0;
  v_child_count integer:=0;
  v_answers jsonb:='{}'::jsonb;
  v_candidates jsonb:='{}'::jsonb;
  v_signals jsonb:='{}'::jsonb;
  v_tenure text;
  v_repairs text;
  v_grounds text;
  v_mowing text;
  v_vehicle_count text;
  v_address_confirmed boolean:=false;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select * into v_principal from atlas.principals where user_id=v_user_id and status='active' limit 1;
  if v_principal.id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;
  select * into v_household from atlas.households where id=v_principal.active_household_id and status='active';

  select count(*)::integer,
         count(*) filter(where lower(coalesce(relationship,'')) in ('child','son','daughter'))::integer
  into v_member_count,v_child_count
  from atlas.household_members
  where household_id=v_household.id and active;

  v_answers:=atlas.reality_discovery_latest_answers_v1(v_principal.id);

  select coalesce(jsonb_object_agg(signal_key,candidate_value),'{}'::jsonb)
  into v_candidates
  from (
    select distinct on(signal_key) signal_key,candidate_value
    from atlas.reality_discovery_evidence_candidates
    where principal_id=v_principal.id and epistemic_state in ('source_candidate','human_confirmed','promoted')
    order by signal_key,
      case epistemic_state when 'promoted' then 1 when 'human_confirmed' then 2 else 3 end,
      updated_at desc,id desc
  ) c;

  v_address_confirmed:=coalesce(v_answers#>>'{home.confirm_purchase_address}','')='yes';
  v_tenure:=v_answers#>>'{home.tenure}';
  v_repairs:=v_answers#>>'{home.major_repairs}';
  v_grounds:=v_answers#>>'{grounds.responsibility}';
  v_mowing:=v_answers#>>'{grounds.mowing_method}';
  v_vehicle_count:=v_answers#>>'{transport.vehicle_count}';

  v_signals:=jsonb_build_object(
    'principal.exists',true,
    'household.exists',v_household.id is not null,
    'household.member_count',v_member_count,
    'household.member_count_bucket',case when v_member_count<=1 then 'one' when v_member_count<=3 then 'small' else 'large' end,
    'household.has_children',v_child_count>0,
    'household.child_count',v_child_count,
    'purchase.billing_address',v_candidates->'purchase.billing_address',
    'home.address_confirmed',v_address_confirmed,
    'home.tenure',v_tenure,
    'home.major_repairs_responsibility',v_repairs,
    'grounds.responsibility',v_grounds,
    'grounds.mowing_method',v_mowing,
    'transport.vehicle_count',v_vehicle_count,
    'context.low_density_owner_household',false,
    'context.dense_urban_renter',false
  );

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_context_self_api_v1',
    'principalId',v_principal.id,
    'householdId',v_household.id,
    'signals',v_signals,
    'answers',v_answers,
    'candidateEvidence',v_candidates,
    'truthBoundary',jsonb_build_object(
      'signalsAreDiscoveryContext',true,
      'inferenceIsNotDomainTruth',true,
      'candidateEvidenceRequiresConfirmationOrPromotion',true,
      'sensitiveTraitsNotInferred',true
    )
  );
end;
$function$;

create or replace function atlas.reality_discovery_edge_matches_v1(p_signal jsonb,p_operator text,p_compare jsonb)
returns boolean
language sql
immutable
set search_path=pg_catalog
as $function$
  select case p_operator
    when 'exists' then p_signal is not null and p_signal <> 'null'::jsonb
    when 'eq' then p_signal=p_compare
    when 'neq' then p_signal is distinct from p_compare
    when 'in' then jsonb_typeof(p_compare)='array' and exists(select 1 from jsonb_array_elements(p_compare) x where x=p_signal)
    when 'not_in' then jsonb_typeof(p_compare)='array' and not exists(select 1 from jsonb_array_elements(p_compare) x where x=p_signal)
    else false
  end;
$function$;

create or replace function atlas.reality_discovery_next_question_self_api_v1()
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
  v_question record;
begin
  v_context:=atlas.reality_discovery_context_self_api_v1();
  v_signals:=coalesce(v_context->'signals','{}'::jsonb);
  v_answers:=coalesce(v_context->'answers','{}'::jsonb);

  with edge_eval as (
    select
      q.question_key,
      e.effect_kind,
      e.weight,
      atlas.reality_discovery_edge_matches_v1(v_signals->e.signal_key,e.operator,e.compare_value) as matched,
      e.reason_text
    from atlas.reality_discovery_questions q
    left join atlas.reality_discovery_edges e on e.question_key=q.question_key
    where q.active
  ), scored as (
    select
      q.*,
      (q.base_score+q.consequence_value+q.information_gain-q.friction
       +coalesce(sum(e.weight) filter(where e.effect_kind='boost' and e.matched),0))::integer as score,
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
      and not (v_signals ? coalesce(s.metadata->>'candidateSignalKey',''))
    )
  order by s.score desc,s.question_key
  limit 1;

  if v_question.question_key is null then
    return jsonb_build_object(
      'ok',true,
      'contractVersion','reality_discovery_next_question_self_api_v1',
      'question',null,
      'quiet',true,
      'message','I know enough here for now.',
      'context',v_context
    );
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','reality_discovery_next_question_self_api_v1',
    'quiet',false,
    'question',jsonb_build_object(
      'questionKey',v_question.question_key,
      'sectionKey',v_question.section_key,
      'prompt',v_question.prompt,
      'helpText',v_question.help_text,
      'answerKind',v_question.answer_kind,
      'options',v_question.options,
      'score',v_question.score,
      'reason',v_question.reason_text,
      'matchedReasons',v_question.matched_reasons,
      'candidateValue',case
        when coalesce((v_question.metadata->>'requiresCandidate')::boolean,false)
          then v_signals->(v_question.metadata->>'candidateSignalKey')
        else null
      end
    ),
    'context',v_context
  );
end;
$function$;

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
  v_existing atlas.reality_discovery_answer_events%rowtype;
  v_event atlas.reality_discovery_answer_events%rowtype;
  v_signal_key text;
  v_answer_scalar text;
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
  end if;

  select * into v_existing
  from atlas.reality_discovery_answer_events
  where owner_user_id=v_user_id and source_action_id=v_source_action_id;
  if v_existing.id is not null then
    if v_existing.question_key is distinct from v_question_key or v_existing.answer_value is distinct from v_answer then
      raise exception 'sourceActionId already belongs to a different discovery answer.' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'idempotentReplay',true,'eventId',v_existing.id,'next',atlas.reality_discovery_next_question_self_api_v1());
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

  -- Special derived discovery signals. These are graph context only, not domain truth.
  if v_question_key='home.confirm_purchase_address' and v_answer='"yes"'::jsonb then
    insert into atlas.reality_discovery_evidence_candidates(principal_id,owner_user_id,signal_key,candidate_value,epistemic_state,source_kind,source_ref,confidence,explanation)
    values(v_principal.id,v_user_id,'home.address_confirmed','true'::jsonb,'human_confirmed','discovery_answer',v_event.id::text,1,'The human confirmed the purchase address is home.');
  end if;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','answer_reality_discovery_question_self_api_v1',
    'idempotentReplay',false,
    'eventId',v_event.id,
    'next',atlas.reality_discovery_next_question_self_api_v1(),
    'truthBoundary',jsonb_build_object(
      'answerIsEvidence',true,
      'answerDoesNotBypassOwningDomain',true,
      'inferenceMayRerankButNotEstablishTruth',true
    )
  );
end;
$function$;

revoke all on function atlas.reality_discovery_context_self_api_v1() from public,anon;
revoke all on function atlas.reality_discovery_next_question_self_api_v1() from public,anon;
revoke all on function atlas.answer_reality_discovery_question_self_api_v1(jsonb) from public,anon;
grant execute on function atlas.reality_discovery_context_self_api_v1() to authenticated,service_role;
grant execute on function atlas.reality_discovery_next_question_self_api_v1() to authenticated,service_role;
grant execute on function atlas.answer_reality_discovery_question_self_api_v1(jsonb) to authenticated,service_role;

create or replace function public.reality_discovery_context_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.reality_discovery_context_self_api_v1(); $function$;
create or replace function public.reality_discovery_next_question_self_api_v1()
returns jsonb language sql stable security definer set search_path=pg_catalog
as $function$ select atlas.reality_discovery_next_question_self_api_v1(); $function$;
create or replace function public.answer_reality_discovery_question_self_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=pg_catalog
as $function$ select atlas.answer_reality_discovery_question_self_api_v1(p_input); $function$;

revoke all on function public.reality_discovery_context_self_api_v1() from public,anon;
revoke all on function public.reality_discovery_next_question_self_api_v1() from public,anon;
revoke all on function public.answer_reality_discovery_question_self_api_v1(jsonb) from public,anon;
grant execute on function public.reality_discovery_context_self_api_v1() to authenticated,service_role;
grant execute on function public.reality_discovery_next_question_self_api_v1() to authenticated,service_role;
grant execute on function public.answer_reality_discovery_question_self_api_v1(jsonb) to authenticated,service_role;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,anonymous_execute_expected,
  caller_count,policy_reference_count,evidence,registered_at
) values
('atlas.reality_discovery_context_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Build role-safe Reality Discovery context from canonical facts plus explicit discovery evidence without creating duplicate domain truth.'),now()),
('atlas.reality_discovery_next_question_self_api_v1()','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Deterministically choose the highest-value eligible Reality Discovery question after applying require/boost/suppress graph rules.'),now()),
('atlas.answer_reality_discovery_question_self_api_v1(p_input jsonb)','app_endpoint','verified','active',true,true,true,false,1,0,
 jsonb_build_object('purpose','Append idempotent human discovery evidence and immediately rerank the adaptive question graph without bypassing owning-domain authority.'),now())
on conflict(signature) do update set
  classification=excluded.classification,confidence=excluded.confidence,review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,anonymous_execute_expected=excluded.anonymous_execute_expected,
  evidence=atlas.authenticated_rpc_registry.evidence||excluded.evidence,reviewed_at=now();
