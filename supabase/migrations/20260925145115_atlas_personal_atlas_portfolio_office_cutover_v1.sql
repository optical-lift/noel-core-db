create or replace function atlas.personal_portfolio_office_author_self_api_v1(
  p_kind text,
  p_input jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth','personal'
as $function$
declare
  v_user_id uuid:=auth.uid();
  v_person_id uuid;
  v_personal_atlas_id uuid;
  v_compat_principal_id uuid;
  v_principal atlas.principals%rowtype;
  v_kind text:=nullif(btrim(p_kind),'');
  v_unit atlas.portfolio_units%rowtype;
  v_function atlas.operating_functions%rowtype;
  v_obligation atlas.owner_obligations%rowtype;
  v_thesis atlas.portfolio_theses%rowtype;
  v_subject atlas.attention_subjects%rowtype;
  v_policy atlas.attention_policies%rowtype;
  v_operating atlas.operating_functions%rowtype;
  v_scorecard atlas.great_game_scorecards%rowtype;
  v_capital atlas.capital_requests%rowtype;
  v_opportunity atlas.investment_opportunities%rowtype;
  v_stable_key text;
  v_title text;
  v_expected integer;
  v_statement text;
  v_subject_key text;
  v_subject_title text;
  v_subject_type text;
  v_policy_key text;
  v_name text;
  v_charter text;
  v_unit_id uuid;
  v_result jsonb;
  v_common_metadata jsonb;
begin
  if v_user_id is null then
    raise exception 'Authenticated user required.' using errcode='42501';
  end if;

  v_person_id:=atlas.current_person_id_v1();
  if v_person_id is null then
    raise exception 'Canonical Reality Person required.' using errcode='42501';
  end if;

  select pa.id into v_personal_atlas_id
  from personal.atlases pa
  where pa.person_entity_id=v_person_id
    and pa.atlas_state='active'
    and pa.native;

  if v_personal_atlas_id is null then
    raise exception 'Active Personal Atlas required.' using errcode='42501';
  end if;

  v_compat_principal_id:=atlas.personal_atlas_compatibility_principal_id_v1(v_person_id);
  if v_compat_principal_id is null then
    raise exception 'Personal portfolio compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  select * into v_principal
  from atlas.principals p
  where p.id=v_compat_principal_id
    and p.status='active';

  if v_principal.id is null then
    raise exception 'Personal portfolio compatibility carrier unavailable.'
      using errcode='42501';
  end if;

  if p_input is null or jsonb_typeof(p_input)<>'object' then
    raise exception 'Portfolio Office authoring input must be an object.'
      using errcode='22023';
  end if;

  if v_kind not in (
    'owner_obligation','portfolio_thesis','attention_policy','operating_function',
    'great_game_scorecard','capital_request','investment_opportunity'
  ) then
    raise exception 'Unsupported Personal Atlas portfolio-office authoring kind.'
      using errcode='22023';
  end if;

  v_common_metadata:=jsonb_build_object(
    'authoringContract','personal_portfolio_office_author_self_api_v1',
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'legacyPrincipalStorageOnly',true,
    'projectionBoundary','personal_atlas_not_canonical_reality'
  );

  if v_kind='owner_obligation' then
    v_stable_key:=nullif(trim(p_input->>'stableKey'),'');
    v_title:=nullif(trim(p_input->>'title'),'');
    begin
      v_expected:=(p_input->>'expectedMinutes')::integer;
    exception when others then
      raise exception 'expectedMinutes must be an integer.' using errcode='22023';
    end;

    if v_stable_key is null or v_title is null
       or nullif(trim(p_input->>'domain'),'') is null
       or v_expected is null or v_expected<=0 then
      raise exception 'stableKey, domain, title, and positive expectedMinutes are required.'
        using errcode='22023';
    end if;

    v_unit_id:=null;
    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select u.id into v_unit_id
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit_id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    elsif nullif(p_input->>'portfolioUnitId','') is not null then
      select u.id into v_unit_id
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.id=(p_input->>'portfolioUnitId')::uuid
        and u.archived_at is null;
      if v_unit_id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    insert into atlas.owner_obligations(
      principal_id,stable_key,domain,portfolio_unit_id,project_id,team_id,
      title,description,horizon,becomes_relevant_at,must_begin_by,must_finish_by,
      fixed_at,expires_at,preferred_window,expected_minutes,protection_level,
      floor_class,owner_capability,interruptibility,delegable,owner_required,
      consequence_of_delay,reason_for_floor,status,source,metadata
    ) values (
      v_compat_principal_id,v_stable_key,p_input->>'domain',v_unit_id,
      case when nullif(p_input->>'projectId','') is null then null else (p_input->>'projectId')::uuid end,
      case when nullif(p_input->>'teamId','') is null then null else (p_input->>'teamId')::uuid end,
      v_title,nullif(p_input->>'description',''),nullif(p_input->>'horizon',''),
      case when nullif(p_input->>'becomesRelevantAt','') is null then null else (p_input->>'becomesRelevantAt')::timestamptz end,
      case when nullif(p_input->>'mustBeginBy','') is null then null else (p_input->>'mustBeginBy')::timestamptz end,
      case when nullif(p_input->>'mustFinishBy','') is null then null else (p_input->>'mustFinishBy')::timestamptz end,
      case when nullif(p_input->>'fixedAt','') is null then null else (p_input->>'fixedAt')::timestamptz end,
      case when nullif(p_input->>'expiresAt','') is null then null else (p_input->>'expiresAt')::timestamptz end,
      case
        when nullif(p_input->>'preferredWindowStart','') is null
          or nullif(p_input->>'preferredWindowEnd','') is null then null
        else tstzrange(
          (p_input->>'preferredWindowStart')::timestamptz,
          (p_input->>'preferredWindowEnd')::timestamptz,'[)'
        )
      end,
      v_expected,p_input->>'protectionLevel',(p_input->>'floorClass')::smallint,
      p_input->>'ownerCapability',
      coalesce(nullif(p_input->>'interruptibility',''),'low_interruptibility'),
      coalesce((p_input->>'delegable')::boolean,false),
      coalesce((p_input->>'ownerRequired')::boolean,true),
      p_input->>'consequenceOfDelay',p_input->>'reasonForFloor',
      coalesce(nullif(p_input->>'status',''),'open'),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(principal_id,stable_key) do update set
      domain=excluded.domain,portfolio_unit_id=excluded.portfolio_unit_id,
      project_id=excluded.project_id,team_id=excluded.team_id,
      title=excluded.title,description=excluded.description,horizon=excluded.horizon,
      becomes_relevant_at=excluded.becomes_relevant_at,
      must_begin_by=excluded.must_begin_by,must_finish_by=excluded.must_finish_by,
      fixed_at=excluded.fixed_at,expires_at=excluded.expires_at,
      preferred_window=excluded.preferred_window,
      expected_minutes=excluded.expected_minutes,
      protection_level=excluded.protection_level,floor_class=excluded.floor_class,
      owner_capability=excluded.owner_capability,
      interruptibility=excluded.interruptibility,delegable=excluded.delegable,
      owner_required=excluded.owner_required,
      consequence_of_delay=excluded.consequence_of_delay,
      reason_for_floor=excluded.reason_for_floor,status=excluded.status,
      source=excluded.source,
      metadata=atlas.owner_obligations.metadata||excluded.metadata
    returning * into v_obligation;

    v_result:=jsonb_build_object(
      'obligation',to_jsonb(v_obligation),
      'candidate',(
        select to_jsonb(c)
        from atlas.principal_clock_candidates_v1 c
        where c.source_type='owner_obligation' and c.source_id=v_obligation.id
      )
    );

  elsif v_kind='portfolio_thesis' then
    v_stable_key:=nullif(btrim(p_input->>'stableKey'),'');
    v_statement:=nullif(btrim(p_input->>'thesisStatement'),'');
    if v_stable_key is null or v_statement is null
       or nullif(btrim(p_input->>'portfolioUnitStableKey'),'') is null then
      raise exception 'portfolioUnitStableKey, stableKey, and thesisStatement are required.'
        using errcode='22023';
    end if;

    select * into v_unit
    from atlas.portfolio_units u
    where u.owner_id=v_compat_principal_id
      and u.stable_key=p_input->>'portfolioUnitStableKey'
      and u.archived_at is null;
    if v_unit.id is null then
      raise exception 'Portfolio unit not found for this Personal Atlas.'
        using errcode='P0002';
    end if;

    insert into atlas.portfolio_theses(
      principal_id,portfolio_unit_id,stable_key,thesis_statement,value_creation_logic,
      must_become_true,capital_required,next_value_milestone,assumptions,
      reconsideration_conditions,review_cadence_days,next_review_at,status,source,metadata
    ) values (
      v_compat_principal_id,v_unit.id,v_stable_key,v_statement,
      nullif(p_input->>'valueCreationLogic',''),
      case when jsonb_typeof(p_input->'mustBecomeTrue')='array'
        then p_input->'mustBecomeTrue' else '[]'::jsonb end,
      case when jsonb_typeof(p_input->'capitalRequired')='object'
        then p_input->'capitalRequired' else '{}'::jsonb end,
      nullif(p_input->>'nextValueMilestone',''),
      case when jsonb_typeof(p_input->'assumptions')='array'
        then p_input->'assumptions' else '[]'::jsonb end,
      case when jsonb_typeof(p_input->'reconsiderationConditions')='array'
        then p_input->'reconsiderationConditions' else '[]'::jsonb end,
      case when nullif(p_input->>'reviewCadenceDays','') is null
        then null else (p_input->>'reviewCadenceDays')::integer end,
      case when nullif(p_input->>'nextReviewAt','') is null
        then null else (p_input->>'nextReviewAt')::timestamptz end,
      coalesce(nullif(p_input->>'status',''),'draft'),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(portfolio_unit_id,stable_key) do update set
      thesis_statement=excluded.thesis_statement,
      value_creation_logic=excluded.value_creation_logic,
      must_become_true=excluded.must_become_true,
      capital_required=excluded.capital_required,
      next_value_milestone=excluded.next_value_milestone,
      assumptions=excluded.assumptions,
      reconsideration_conditions=excluded.reconsideration_conditions,
      review_cadence_days=excluded.review_cadence_days,
      next_review_at=excluded.next_review_at,status=excluded.status,
      source=excluded.source,
      metadata=atlas.portfolio_theses.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_thesis;

    v_result:=jsonb_build_object(
      'portfolioUnit',jsonb_build_object(
        'id',v_unit.id,'stableKey',v_unit.stable_key,'name',v_unit.name,'horizon',v_unit.horizon
      ),
      'thesis',to_jsonb(v_thesis)
    );

  elsif v_kind='attention_policy' then
    v_subject_key:=nullif(btrim(p_input->>'subjectStableKey'),'');
    v_subject_title:=nullif(btrim(p_input->>'subjectTitle'),'');
    v_subject_type:=nullif(btrim(p_input->>'subjectType'),'');
    v_policy_key:=nullif(btrim(p_input->>'policyStableKey'),'');
    if v_subject_key is null or v_subject_title is null
       or v_subject_type is null or v_policy_key is null then
      raise exception 'subjectStableKey, subjectTitle, subjectType, and policyStableKey are required.'
        using errcode='22023';
    end if;
    if nullif(p_input->>'cadenceDays','') is null
       or nullif(p_input->>'firstDueAt','') is null
       or nullif(p_input->>'protectedOwnerMinutes','') is null
       or nullif(p_input->>'floorClass','') is null
       or nullif(p_input->>'protectionLevel','') is null
       or nullif(btrim(p_input->>'consequence'),'') is null
       or nullif(btrim(p_input->>'reasonForFloor'),'') is null then
      raise exception 'cadenceDays, firstDueAt, protectedOwnerMinutes, floorClass, protectionLevel, consequence, and reasonForFloor are required.'
        using errcode='22023';
    end if;

    v_unit.id:=null;
    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select * into v_unit
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit.id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    elsif v_subject_type='portfolio_unit' then
      raise exception 'portfolioUnitStableKey is required for a portfolio_unit attention subject.'
        using errcode='22023';
    end if;

    insert into atlas.attention_subjects(
      principal_id,portfolio_unit_id,stable_key,subject_type,title,active,source,metadata
    ) values (
      v_compat_principal_id,v_unit.id,v_subject_key,v_subject_type,v_subject_title,true,
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'subjectMetadata')='object'
        then p_input->'subjectMetadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(principal_id,stable_key) do update set
      portfolio_unit_id=excluded.portfolio_unit_id,
      subject_type=excluded.subject_type,title=excluded.title,active=true,
      source=excluded.source,
      metadata=atlas.attention_subjects.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_subject;

    insert into atlas.attention_policies(
      subject_id,stable_key,cadence_days,first_due_at,protected_owner_minutes,
      floor_class,protection_level,interruptibility,consequence,reason_for_floor,
      effective_from,effective_through,active,source,metadata
    ) values (
      v_subject.id,v_policy_key,(p_input->>'cadenceDays')::integer,
      (p_input->>'firstDueAt')::timestamptz,
      (p_input->>'protectedOwnerMinutes')::integer,
      (p_input->>'floorClass')::smallint,p_input->>'protectionLevel',
      coalesce(nullif(p_input->>'interruptibility',''),'low_interruptibility'),
      p_input->>'consequence',p_input->>'reasonForFloor',
      coalesce(nullif(p_input->>'effectiveFrom','')::timestamptz,now()),
      case when nullif(p_input->>'effectiveThrough','') is null
        then null else (p_input->>'effectiveThrough')::timestamptz end,
      true,coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'policyMetadata')='object'
        then p_input->'policyMetadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(subject_id,stable_key) do update set
      cadence_days=excluded.cadence_days,first_due_at=excluded.first_due_at,
      protected_owner_minutes=excluded.protected_owner_minutes,
      floor_class=excluded.floor_class,protection_level=excluded.protection_level,
      interruptibility=excluded.interruptibility,consequence=excluded.consequence,
      reason_for_floor=excluded.reason_for_floor,effective_from=excluded.effective_from,
      effective_through=excluded.effective_through,active=true,source=excluded.source,
      metadata=atlas.attention_policies.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_policy;

    v_result:=jsonb_build_object(
      'subject',to_jsonb(v_subject),'policy',to_jsonb(v_policy),
      'attentionState',(
        select to_jsonb(a) from atlas.attention_debt_v1 a where a.policy_id=v_policy.id
      )
    );

  elsif v_kind='operating_function' then
    v_stable_key:=nullif(btrim(p_input->>'stableKey'),'');
    v_name:=nullif(btrim(p_input->>'name'),'');
    v_charter:=nullif(btrim(p_input->>'charter'),'');
    if v_stable_key is null or v_name is null or v_charter is null then
      raise exception 'stableKey, name, and charter are required.' using errcode='22023';
    end if;

    v_unit.id:=null;
    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select * into v_unit
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit.id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    insert into atlas.operating_functions(
      principal_id,organization_id,portfolio_unit_id,stable_key,name,charter,
      accountable_person_id,capacity_state,review_cadence_days,active,source,metadata
    ) values (
      v_compat_principal_id,v_principal.organization_id,v_unit.id,
      v_stable_key,v_name,v_charter,
      case when nullif(p_input->>'accountablePersonId','') is null
        then null else (p_input->>'accountablePersonId')::uuid end,
      nullif(p_input->>'capacityState',''),
      case when nullif(p_input->>'reviewCadenceDays','') is null
        then null else (p_input->>'reviewCadenceDays')::integer end,
      coalesce((p_input->>'active')::boolean,true),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)
        ||v_common_metadata
        ||jsonb_build_object('legacyOrganizationProjectionOnly',true)
    )
    on conflict(principal_id,stable_key) do update set
      portfolio_unit_id=excluded.portfolio_unit_id,
      name=excluded.name,charter=excluded.charter,
      accountable_person_id=excluded.accountable_person_id,
      capacity_state=excluded.capacity_state,
      review_cadence_days=excluded.review_cadence_days,
      active=excluded.active,source=excluded.source,
      metadata=atlas.operating_functions.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_operating;

    v_result:=jsonb_build_object('operatingFunction',to_jsonb(v_operating));

  elsif v_kind='great_game_scorecard' then
    v_stable_key:=nullif(btrim(p_input->>'stableKey'),'');
    v_name:=nullif(btrim(p_input->>'name'),'');
    if v_stable_key is null or v_name is null
       or nullif(btrim(p_input->>'criticalNumber'),'') is null then
      raise exception 'stableKey, name, and criticalNumber are required.'
        using errcode='22023';
    end if;

    v_function.id:=null;
    v_unit.id:=null;
    if nullif(p_input->>'operatingFunctionStableKey','') is not null then
      select * into v_function
      from atlas.operating_functions f
      where f.principal_id=v_compat_principal_id
        and f.stable_key=p_input->>'operatingFunctionStableKey'
        and f.active;
      if v_function.id is null then
        raise exception 'Operating function not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select * into v_unit
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit.id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    if v_function.id is null and v_unit.id is null then
      raise exception 'operatingFunctionStableKey or portfolioUnitStableKey is required.'
        using errcode='22023';
    end if;

    insert into atlas.great_game_scorecards(
      principal_id,operating_function_id,portfolio_unit_id,stable_key,name,
      critical_number,drivers,accountable_operator_id,active,source,metadata
    ) values (
      v_compat_principal_id,v_function.id,v_unit.id,v_stable_key,v_name,
      p_input->>'criticalNumber',
      case when jsonb_typeof(p_input->'drivers')='array'
        then p_input->'drivers' else '[]'::jsonb end,
      case when nullif(p_input->>'accountableOperatorId','') is null
        then null else (p_input->>'accountableOperatorId')::uuid end,
      coalesce((p_input->>'active')::boolean,true),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(principal_id,stable_key) do update set
      operating_function_id=excluded.operating_function_id,
      portfolio_unit_id=excluded.portfolio_unit_id,name=excluded.name,
      critical_number=excluded.critical_number,drivers=excluded.drivers,
      accountable_operator_id=excluded.accountable_operator_id,
      active=excluded.active,source=excluded.source,
      metadata=atlas.great_game_scorecards.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_scorecard;

    v_result:=jsonb_build_object('scorecard',to_jsonb(v_scorecard));

  elsif v_kind='capital_request' then
    v_stable_key:=nullif(btrim(p_input->>'stableKey'),'');
    v_title:=nullif(btrim(p_input->>'title'),'');
    if v_stable_key is null or v_title is null
       or nullif(p_input->>'amount','') is null
       or nullif(btrim(p_input->>'currency'),'') is null
       or nullif(btrim(p_input->>'reason'),'') is null then
      raise exception 'stableKey, title, amount, currency, and reason are required.'
        using errcode='22023';
    end if;

    v_unit_id:=null;
    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select u.id into v_unit_id
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit_id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    insert into atlas.capital_requests(
      principal_id,portfolio_unit_id,stable_key,title,amount,currency,
      needed_by,reason,status,source,metadata
    ) values (
      v_compat_principal_id,v_unit_id,v_stable_key,v_title,
      (p_input->>'amount')::numeric,p_input->>'currency',
      case when nullif(p_input->>'neededBy','') is null
        then null else (p_input->>'neededBy')::timestamptz end,
      p_input->>'reason',coalesce(nullif(p_input->>'status',''),'requested'),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(principal_id,stable_key) do update set
      portfolio_unit_id=excluded.portfolio_unit_id,title=excluded.title,
      amount=excluded.amount,currency=excluded.currency,
      needed_by=excluded.needed_by,reason=excluded.reason,status=excluded.status,
      source=excluded.source,
      metadata=atlas.capital_requests.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_capital;

    v_result:=jsonb_build_object('capitalRequest',to_jsonb(v_capital));

  elsif v_kind='investment_opportunity' then
    v_stable_key:=nullif(btrim(p_input->>'stableKey'),'');
    v_title:=nullif(btrim(p_input->>'title'),'');
    if v_stable_key is null or v_title is null
       or nullif(p_input->>'readinessState','') is null then
      raise exception 'stableKey, title, and readinessState are required.'
        using errcode='22023';
    end if;
    if nullif(p_input->>'capitalRequired','') is not null
       and nullif(btrim(p_input->>'currency'),'') is null then
      raise exception 'currency is required when capitalRequired is supplied.'
        using errcode='22023';
    end if;

    v_unit_id:=null;
    if nullif(p_input->>'portfolioUnitStableKey','') is not null then
      select u.id into v_unit_id
      from atlas.portfolio_units u
      where u.owner_id=v_compat_principal_id
        and u.stable_key=p_input->>'portfolioUnitStableKey'
        and u.archived_at is null;
      if v_unit_id is null then
        raise exception 'Portfolio unit not found for this Personal Atlas.'
          using errcode='P0002';
      end if;
    end if;

    insert into atlas.investment_opportunities(
      principal_id,portfolio_unit_id,stable_key,title,capital_required,currency,
      readiness_state,next_value_milestone,status,source,metadata
    ) values (
      v_compat_principal_id,v_unit_id,v_stable_key,v_title,
      case when nullif(p_input->>'capitalRequired','') is null
        then null else (p_input->>'capitalRequired')::numeric end,
      nullif(p_input->>'currency',''),p_input->>'readinessState',
      nullif(p_input->>'nextValueMilestone',''),
      coalesce(nullif(p_input->>'status',''),'active'),
      coalesce(nullif(p_input->>'source',''),'personal_portfolio_authoring'),
      (case when jsonb_typeof(p_input->'metadata')='object'
        then p_input->'metadata' else '{}'::jsonb end)||v_common_metadata
    )
    on conflict(principal_id,stable_key) do update set
      portfolio_unit_id=excluded.portfolio_unit_id,title=excluded.title,
      capital_required=excluded.capital_required,currency=excluded.currency,
      readiness_state=excluded.readiness_state,
      next_value_milestone=excluded.next_value_milestone,
      status=excluded.status,source=excluded.source,
      metadata=atlas.investment_opportunities.metadata||excluded.metadata,
      updated_at=now()
    returning * into v_opportunity;

    v_result:=jsonb_build_object('investmentOpportunity',to_jsonb(v_opportunity));
  end if;

  return jsonb_build_object(
    'contractVersion','personal_portfolio_office_authoring_v1',
    'kind',v_kind,
    'personEntityId',v_person_id,
    'personalAtlasId',v_personal_atlas_id,
    'compatibilityBoundary',jsonb_build_object(
      'legacyPrincipalStorageOnly',true,
      'personalAtlasProjectionNotCanonicalReality',true,
      'doesNotGrantInstitutionalAuthority',true,
      'doesNotExecuteMoney',true,
      'doesNotAssignCompanyWork',true,
      'canonicalPromotionRequiresSeparateGovernedOperation',true
    )
  )||v_result;
end
$function$;

revoke all on function atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)
  from public,anon;
grant execute on function atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)
  to authenticated;

create or replace function atlas.principal_upsert_owner_obligation_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('owner_obligation',p_input)
    ||jsonb_build_object('contractVersion','principal_owner_obligation_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_portfolio_thesis_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('portfolio_thesis',p_input)
    ||jsonb_build_object('contractVersion','principal_portfolio_thesis_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_attention_policy_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('attention_policy',p_input)
    ||jsonb_build_object('contractVersion','principal_attention_policy_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_operating_function_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('operating_function',p_input)
    ||jsonb_build_object('contractVersion','principal_operating_function_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_great_game_scorecard_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('great_game_scorecard',p_input)
    ||jsonb_build_object('contractVersion','principal_great_game_scorecard_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_capital_request_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('capital_request',p_input)
    ||jsonb_build_object('contractVersion','principal_capital_request_authoring_v1');
$function$;

create or replace function atlas.principal_upsert_investment_opportunity_api_v1(p_input jsonb)
returns jsonb language sql security definer set search_path=''
as $function$
  select atlas.personal_portfolio_office_author_self_api_v1('investment_opportunity',p_input)
    ||jsonb_build_object('contractVersion','principal_investment_opportunity_authoring_v1');
$function$;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.personal_portfolio_office_author_self_api_v1(text, jsonb)',
  'app_endpoint','verified','active',true,true,false,1,0,
  jsonb_build_object(
    'purpose','Author Personal Atlas portfolio-office projection records for the signed-in Reality Person.',
    'projectionBoundary','These records are personal governance/planning projections and do not establish canonical institutional Reality.',
    'externalEffectBoundary','Does not execute money, assign Company Work, or create institutional authority.',
    'storageCompatibility','Legacy Principal Office tables remain physical storage during migration.'
  ),now(),false
)
on conflict(signature) do update set
  classification=excluded.classification,
  confidence=excluded.confidence,
  review_status=excluded.review_status,
  authenticated_execute_expected=excluded.authenticated_execute_expected,
  security_definer_expected=excluded.security_definer_expected,
  service_execute_expected=excluded.service_execute_expected,
  caller_count=excluded.caller_count,
  policy_reference_count=excluded.policy_reference_count,
  evidence=excluded.evidence,
  reviewed_at=excluded.reviewed_at,
  anonymous_execute_expected=excluded.anonymous_execute_expected;

update atlas.authenticated_rpc_registry
set evidence=evidence||jsonb_build_object(
      'compatibilityAliasTo','atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)',
      'identityRoot','Reality Person + native Personal Atlas',
      'legacyPrincipalStorageOnly',true,
      'projectionBoundary','personal_atlas_not_canonical_reality'
    ),
    reviewed_at=now()
where signature like 'atlas.principal_upsert_owner_obligation_api_v1(%'
   or signature like 'atlas.principal_upsert_portfolio_thesis_api_v1(%'
   or signature like 'atlas.principal_upsert_attention_policy_api_v1(%'
   or signature like 'atlas.principal_upsert_operating_function_api_v1(%'
   or signature like 'atlas.principal_upsert_great_game_scorecard_api_v1(%'
   or signature like 'atlas.principal_upsert_capital_request_api_v1(%'
   or signature like 'atlas.principal_upsert_investment_opportunity_api_v1(%';

comment on function atlas.personal_portfolio_office_author_self_api_v1(text,jsonb) is
  'Reality Person + Personal Atlas authoring membrane for personal portfolio-office projections. These rows may guide the Person''s planning and clock but do not establish canonical institutional Reality, authority, Company Work, or financial execution.';

comment on function atlas.principal_upsert_owner_obligation_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office authoring; the legacy Owner/Principal labels are storage vocabulary only.';
comment on function atlas.principal_upsert_portfolio_thesis_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office authoring; does not establish a canonical institutional thesis.';
comment on function atlas.principal_upsert_attention_policy_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office authoring.';
comment on function atlas.principal_upsert_operating_function_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office modeling; does not establish a canonical institutional function.';
comment on function atlas.principal_upsert_great_game_scorecard_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office modeling; does not establish a canonical institutional scorecard.';
comment on function atlas.principal_upsert_capital_request_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office modeling; a request is not a spend or approval.';
comment on function atlas.principal_upsert_investment_opportunity_api_v1(jsonb) is
  'Compatibility alias to Personal Atlas portfolio-office modeling; an opportunity record is not a capital allocation.';

do $validation$
begin
  if pg_get_functiondef(
       'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)'::regprocedure
     ) ilike '%is_farm_owner%' then
    raise exception 'Personal Portfolio Office authoring retained legacy authority identity.';
  end if;

  if pg_get_functiondef(
       'atlas.principal_upsert_owner_obligation_api_v1(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.principal_upsert_operating_function_api_v1(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%'
     or pg_get_functiondef(
       'atlas.principal_upsert_capital_request_api_v1(jsonb)'::regprocedure
     ) ilike '%current_principal_id_v1%' then
    raise exception 'A Principal Portfolio Office compatibility alias still establishes identity.';
  end if;
end
$validation$;
