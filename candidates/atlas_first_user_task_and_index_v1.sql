BEGIN;

-- Atlas one-time first-use authority release. Protected source generation and
-- production-schema validation are still mandatory before production execution.
-- Do not retire existing farm/project task storage or prior Index RPCs here.

-- REVIEW CANDIDATE ONLY: not a production migration.
-- Atlas's first universal-shaped task entry is exactly one sentence + one due date.
-- Owners are authenticated established Principals; no inferred project or farm relation.
-- Release path: generate an atlas_-prefixed canonical migration through the
-- reviewed noel-core-db migration workflow, test in disposable clone, promote manually.
-- Does NOT mutate or copy legacy atlas.tasks records.

create table atlas.task_entries (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  principal_id uuid not null references atlas.principals(id) on delete restrict,
  sentence text not null check (length(btrim(sentence)) between 1 and 500),
  due_date date not null,
  status text not null default 'open' check (status in ('open','done')),
  source_action_id text not null check (length(btrim(source_action_id)) between 1 and 128),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint task_entries_completion_consistency check (
    (status='open' and completed_at is null)
    or (status='done' and completed_at is not null)
  ),
  constraint task_entries_authoring_idempotency unique (owner_user_id,source_action_id)
);
create index task_entries_day_owner_idx on atlas.task_entries(owner_user_id,due_date,created_at,id);
alter table atlas.task_entries enable row level security;
-- No direct Data API exposure. Authenticated access is only via verified RPCs.
revoke all on table atlas.task_entries from public,anon,authenticated;

create or replace function atlas.require_active_task_principal_v1()
returns uuid
language plpgsql stable security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_user uuid := auth.uid();
  v_principal uuid;
  v_access jsonb;
begin
  if v_user is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  v_access := atlas.personal_atlas_access_status_self_api_v1();
  if not coalesce((v_access->>'eligible')::boolean,false)
     or coalesce(v_access->>'accessState','locked')='locked' then
    raise exception 'Active Personal Atlas access required.' using errcode='42501';
  end if;
  select p.id into v_principal
  from atlas.principals p
  where p.user_id=v_user and p.status='active'
  order by p.id limit 1;
  if v_principal is null then
    raise exception 'Established Principal required.' using errcode='42501';
  end if;
  return v_principal;
end;
$$;

create or replace function atlas.atlas_task_day_self_api_v1(p_date date)
returns jsonb
language plpgsql stable security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_rows jsonb;
begin
  if p_date is null then raise exception 'Date is required.' using errcode='22023'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id,
    'sentence', t.sentence,
    'dueDate', t.due_date,
    'status', t.status
  ) order by case when t.status='open' then 0 else 1 end, t.created_at, t.id),'[]'::jsonb)
  into v_rows
  from atlas.task_entries t
  where t.owner_user_id=auth.uid()
    and t.principal_id=v_principal
    and t.due_date=p_date;
  return jsonb_build_object('ok',true,'date',p_date,'items',v_rows);
end;
$$;

create or replace function atlas.create_atlas_task_self_api_v1(
  p_sentence text, p_due_date date, p_source_action_id text
)
returns jsonb
language plpgsql volatile security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_user uuid := auth.uid();
  v_sentence text := btrim(coalesce(p_sentence,''));
  v_key text := btrim(coalesce(p_source_action_id,''));
  v_task atlas.task_entries%rowtype;
begin
  if length(v_sentence) not between 1 and 500 then
    raise exception 'Enter one sentence (1-500 characters).' using errcode='22023';
  end if;
  if p_due_date is null then raise exception 'Choose a date.' using errcode='22023'; end if;
  if length(v_key) not between 1 and 128 then
    raise exception 'Source action ID is required.' using errcode='22023';
  end if;

  insert into atlas.task_entries(owner_user_id,principal_id,sentence,due_date,source_action_id)
  values (v_user,v_principal,v_sentence,p_due_date,v_key)
  on conflict (owner_user_id,source_action_id) do nothing
  returning * into v_task;

  if v_task.id is null then
    select * into v_task from atlas.task_entries
      where owner_user_id=v_user and source_action_id=v_key;
    if v_task.id is null or v_task.principal_id<>v_principal
       or v_task.sentence<>v_sentence or v_task.due_date<>p_due_date then
      raise exception 'The submission key belongs to a different task.' using errcode='23505';
    end if;
  end if;

  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
end;
$$;

create or replace function atlas.set_atlas_task_done_self_api_v1(
  p_task_id uuid, p_done boolean
)
returns jsonb
language plpgsql volatile security definer
set search_path = pg_catalog, atlas, auth
as $$
declare
  v_principal uuid := atlas.require_active_task_principal_v1();
  v_task atlas.task_entries%rowtype;
begin
  if p_task_id is null or p_done is null then
    raise exception 'Task and completion state are required.' using errcode='22023';
  end if;
  update atlas.task_entries
     set status=case when p_done then 'done' else 'open' end,
         completed_at=case when p_done then now() else null end
   where id=p_task_id and owner_user_id=auth.uid() and principal_id=v_principal
   returning * into v_task;
  if v_task.id is null then
    raise exception 'Task not found.' using errcode='42501';
  end if;
  return jsonb_build_object('ok',true,'task',jsonb_build_object(
    'id',v_task.id,'sentence',v_task.sentence,'dueDate',v_task.due_date,
    'status',v_task.status));
end;
$$;

-- The Atlas schema remains private. Public functions expose only authenticated
-- self-scoped commands and never accept an owner_user_id/principal_id argument.
create or replace function public.atlas_task_day_self_api_v1(p_date date)
returns jsonb language sql stable security definer
set search_path = pg_catalog
as $$ select atlas.atlas_task_day_self_api_v1(p_date); $$;

create or replace function public.create_atlas_task_self_api_v1(
  p_sentence text,p_due_date date,p_source_action_id text
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $$ select atlas.create_atlas_task_self_api_v1(p_sentence,p_due_date,p_source_action_id); $$;

create or replace function public.set_atlas_task_done_self_api_v1(
  p_task_id uuid,p_done boolean
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog
as $$ select atlas.set_atlas_task_done_self_api_v1(p_task_id,p_done); $$;

revoke execute on function atlas.require_active_task_principal_v1() from public,anon,authenticated;
revoke execute on function atlas.atlas_task_day_self_api_v1(date) from public,anon,authenticated;
revoke execute on function atlas.create_atlas_task_self_api_v1(text,date,text) from public,anon,authenticated;
revoke execute on function atlas.set_atlas_task_done_self_api_v1(uuid,boolean) from public,anon,authenticated;
revoke execute on function public.atlas_task_day_self_api_v1(date) from public,anon;
revoke execute on function public.create_atlas_task_self_api_v1(text,date,text) from public,anon;
revoke execute on function public.set_atlas_task_done_self_api_v1(uuid,boolean) from public,anon;
grant execute on function public.atlas_task_day_self_api_v1(date) to authenticated;
grant execute on function public.create_atlas_task_self_api_v1(text,date,text) to authenticated;
grant execute on function public.set_atlas_task_done_self_api_v1(uuid,boolean) to authenticated;

-- Disposable clone acceptance, not production:
-- (1) anon denied; authenticated without Principal denied; locked Principal denied
-- (2) user A can write/read/complete only A's task; B cannot guess A's ID
-- (3) repeated source_action_id is idempotent, distinct payload conflicts
-- (4) due date retrieves exactly that date, including completed rows
-- (5) user supplied plain sentence is preserved unchanged except outer whitespace
-- (6) a reload or account switch does not lose or leak the task
-- (7) no old farm/project task or task trigger is altered or reinterpreted

-- Foundry-derived Index/Discovery canonical projection follows.

-- REVIEW CANDIDATE: replaces legacy Index-selection dependency with already
-- established Field/Position/Scale orientation. Do NOT execute on production.
-- Source-first in noel-core-db; verify with a disposable clone and governed release.
-- No customer records are mutated. Historical v4 orientation events still read.
CREATE OR REPLACE FUNCTION atlas.atlas_notebook_index_self_api_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_household_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_categories jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;
  select p.id,p.active_household_id into v_principal_id,v_household_id
  from atlas.principals p where p.user_id=v_user_id and p.status='active' limit 1;

  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  -- The most recent human orientation (v3 Field/Position/Scale or historical
  -- v4 Index categories) is a retrieval hint, not a separate onboarding gate.
  -- The latest human-selected FIELD remains an intentional notebook section.
  -- Real answers may establish further domains; there is no extra Index form.
  with latest_orientation as (
    select coalesce(e.world_domains,'[]'::jsonb) as domains
    from atlas.reality_discovery_orientation_events e
    where e.principal_id=v_principal_id and e.owner_user_id=v_user_id
      and e.orientation_version in (3,4)
    order by e.occurred_at desc,e.id desc limit 1
  ),
  domain_evidence as (
    select jsonb_array_elements_text(domains) as domain
    from latest_orientation
    union
    select jsonb_array_elements_text(
      case when jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
        then q.metadata->'orientationWorldDomains' else '[]'::jsonb end)
    from atlas.reality_discovery_answer_events a
    join atlas.reality_discovery_questions q on q.question_key=a.question_key
    where a.principal_id=v_principal_id and a.owner_user_id=v_user_id
  )
  select coalesce(jsonb_agg(to_jsonb(domain) order by domain),'[]'::jsonb)
    into v_categories
  from (select distinct domain from domain_evidence where domain in
      ('home','family','job','business','property','money','school','projects','community','hobbies')) d;

  with descriptors as (
    select -10 as section_order,0 as item_order,
      jsonb_build_object(
        'addressKind','bookplate','spreadKey','bookplate','templateKey','bookplate',
        'title','Bookplate','section','Notebook',
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('kind','person','id',v_principal_id)
      ) as item
    union all
    select 0,0,
      jsonb_build_object('addressKind','today','spreadKey','today','templateKey','today','title','Today','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','day','id',current_date::text))
    union all
    select 0,1,
      jsonb_build_object('addressKind','index','spreadKey','index','templateKey','index','title','Index','section','Notebook','scope',jsonb_build_object('kind','person','id',v_user_id),'subject',jsonb_build_object('kind','notebook','id',v_user_id))
    union all
    select 5,
      case d.category
        when 'home' then 10
        when 'family' then 20
        when 'job' then 30
        when 'business' then 40
        when 'property' then 50
        when 'money' then 60
        when 'school' then 70
        when 'projects' then 80
        when 'community' then 90
        when 'hobbies' then 100
        else 999
      end,
      jsonb_build_object(
        'addressKind','section',
        'spreadKey','section:'||d.category,
        'templateKey','section-root',
        'title',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'section',case d.category
          when 'home' then 'Home'
          when 'family' then 'Family'
          when 'job' then 'Job'
          when 'business' then 'Business'
          when 'property' then 'Property'
          when 'money' then 'Money'
          when 'school' then 'School'
          when 'projects' then 'Projects'
          when 'community' then 'Community'
          when 'hobbies' then 'Hobbies'
          else initcap(d.category)
        end,
        'scope',jsonb_build_object('kind','person','id',v_user_id),
        'subject',jsonb_build_object('domain',d.category,'kind','section','id',d.category),
        'intentionalSectionRoot',true
      )
    from jsonb_array_elements_text(v_categories) d(category)
    union all
    select 10,row_number() over(order by s.section_key,s.opened_at,s.id)::integer,
      jsonb_build_object(
        'addressKind','spread','spreadKey',s.spread_key,'templateKey','composed',
        'title',s.title,'section',s.section_key,
        'scope',jsonb_build_object('kind',s.scope_kind,'id',s.scope_id),
        'subject',jsonb_build_object('domain',s.subject_domain,'kind',s.subject_kind,'id',s.subject_id),
        'spreadInstanceId',s.id,'spreadState',s.spread_state,'threadKey',s.thread_key,
        'recipeKey',s.recipe_key,'purposeKey',s.purpose_key,'horizonKey',s.horizon_key
      )
    from atlas.notebook_spread_instances s
    where s.principal_id=v_principal_id
  )
  select coalesce(jsonb_agg(item order by section_order,item_order),'[]'::jsonb)
  into v_items
  from descriptors;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','atlas_notebook_index_self_api_v1',
    'principalId',v_principal_id,
    'householdId',v_household_id,
    'items',v_items,
    'truthBoundary',jsonb_build_object(
      'indexIsRetrievalProjection',true,
      'indexDoesNotGrantAccess',true,
      'bookplateIsHumanEditableContactPresentation',true,
      'selectedSectionRootsAreIntentionalOrganizationNotDomainTruth',true,
      'spreadDescriptorsDoNotOwnSourceTruth',true,
      'spreadExistenceDoesNotCreateSourceTruth',true,
      'encounterSelectionIsSeparateFromSpreadExistence',true,
      'closedSpreadsRemainRetrievable',true,
      'dataBearingPagesComeFromDurableSpreadRegistry',true
    )
  );
end;
$function$;


CREATE OR REPLACE FUNCTION atlas.personal_atlas_section_root_self_api_v1(p_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'atlas', 'auth'
AS $function$
declare
  v_user_id uuid;
  v_principal_id uuid;
  v_category text;
  v_selection jsonb;
  v_selected boolean:=false;
  v_facts jsonb:='[]'::jsonb;
begin
  v_user_id:=auth.uid();
  if v_user_id is null then raise exception 'Sign in required.' using errcode='42501'; end if;

  select id into v_principal_id
  from atlas.principals
  where user_id=v_user_id and status='active'
  limit 1;
  if v_principal_id is null then raise exception 'Active Principal required.' using errcode='42501'; end if;

  v_category:=nullif(lower(trim(p_category)),'');
  if v_category not in ('home','family','job','business','property','money','school','projects','community','hobbies') then
    raise exception 'Unsupported Personal Atlas section.' using errcode='22023';
  end if;

  v_selection:=atlas.reality_discovery_orientation_profile_self_api_v1();
  v_selected:=coalesce(v_selection->'worldDomains','[]'::jsonb) ? v_category;

  with latest as (
    select distinct on(e.question_key)
      e.question_key,e.answer_value,e.occurred_at
    from atlas.reality_discovery_answer_events e
    where e.principal_id=v_principal_id
      and e.owner_user_id=v_user_id
    order by e.question_key,e.occurred_at desc,e.id desc
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'questionKey',l.question_key,
    'label',coalesce(nullif(q.metadata->>'notebookLabel',''),q.prompt),
    'answer',l.answer_value,
    'options',q.options,
    'occurredAt',l.occurred_at
  ) order by l.occurred_at,l.question_key),'[]'::jsonb)
  into v_facts
  from latest l
  join atlas.reality_discovery_questions q on q.question_key=l.question_key
  where jsonb_typeof(q.metadata->'orientationWorldDomains')='array'
    and q.metadata->'orientationWorldDomains' ? v_category;
  v_selected:=v_selected or jsonb_array_length(v_facts)>0;

  return jsonb_build_object(
    'ok',true,
    'contractVersion','personal_atlas_section_root_self_api_v1',
    'category',v_category,
    'selected',v_selected,
    'facts',v_facts,
    'truthBoundary',jsonb_build_object(
      'sectionIsNotebookProjection',true,
      'factsComeFromEstablishedHumanDiscoveryEvidence',true,
      'sectionSelectionDoesNotCreateFacts',true,
      'projectionDoesNotGrantAccessOrEstablishNewTruth',true
    )
  );
end;
$function$;


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
  v_orientation:=atlas.reality_discovery_orientation_profile_self_api_v1();
  v_bookplate_captured:=coalesce((v_bookplate->>'captured')::boolean,false);
  v_orientation_captured:=coalesce((v_orientation->>'captured')::boolean,false);
  -- Keep the existing response key for earlier clients; no separate Index capture.
  v_index_captured:=v_orientation_captured;

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
$function$;


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
$function$;

COMMIT;
