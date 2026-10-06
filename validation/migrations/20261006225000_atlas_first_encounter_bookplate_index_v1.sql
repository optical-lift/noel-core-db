begin;

do $validation$
declare
  v_def text;
begin
  if to_regclass('atlas.personal_atlas_bookplate_events') is null then
    raise exception 'Personal Atlas Bookplate event store is missing.';
  end if;

  if to_regprocedure('public.personal_atlas_bookplate_self_api_v1()') is null
     or to_regprocedure('public.set_personal_atlas_bookplate_self_api_v1(jsonb)') is null
     or to_regprocedure('public.personal_atlas_index_selection_self_api_v1()') is null
     or to_regprocedure('public.set_personal_atlas_index_selection_self_api_v1(jsonb)') is null
     or to_regprocedure('public.personal_atlas_section_root_self_api_v1(text)') is null then
    raise exception 'Bookplate / Index public RPC surface is incomplete.';
  end if;

  if has_function_privilege('anon','public.personal_atlas_bookplate_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.set_personal_atlas_bookplate_self_api_v1(jsonb)','EXECUTE')
     or has_function_privilege('anon','public.personal_atlas_index_selection_self_api_v1()','EXECUTE')
     or has_function_privilege('anon','public.set_personal_atlas_index_selection_self_api_v1(jsonb)','EXECUTE')
     or has_function_privilege('anon','public.personal_atlas_section_root_self_api_v1(text)','EXECUTE') then
    raise exception 'Anonymous role must not execute Bookplate / Index RPCs.';
  end if;

  if not has_function_privilege('authenticated','public.personal_atlas_bookplate_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.set_personal_atlas_bookplate_self_api_v1(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.personal_atlas_index_selection_self_api_v1()','EXECUTE')
     or not has_function_privilege('authenticated','public.set_personal_atlas_index_selection_self_api_v1(jsonb)','EXECUTE')
     or not has_function_privilege('authenticated','public.personal_atlas_section_root_self_api_v1(text)','EXECUTE') then
    raise exception 'Authenticated role must execute Bookplate / Index RPCs.';
  end if;

  if has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','SELECT')
     or has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','INSERT')
     or has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','UPDATE')
     or has_table_privilege('authenticated','atlas.personal_atlas_bookplate_events','DELETE') then
    raise exception 'Bookplate event custody must remain behind RPC authority.';
  end if;

  select pg_get_functiondef('atlas.personal_atlas_bookplate_self_api_v1()'::regprocedure)
  into v_def;
  if position('sourceEvidence' in v_def)=0
     or position('purchaseNameDoesNotBecomePreferredNameWithoutHumanAcceptance' in v_def)=0
     or position('contactAddressDoesNotEstablishResidence' in v_def)=0
     or position('auth.users' in v_def)=0
     or position('personal_atlas_purchases' in v_def)=0 then
    raise exception 'Bookplate reader does not preserve source-evidence / human-presentation boundaries.';
  end if;

  select pg_get_functiondef('atlas.set_personal_atlas_bookplate_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('begin_personal_atlas_self_api_v1' in v_def)=0
     or position('update atlas.principals' in lower(v_def))=0
     or position('update atlas.household_members' in lower(v_def))=0
     or position('personal_atlas_bookplate_events' in v_def)=0
     or position('bookplateCorrectionDoesNotRewritePurchaseEvidence' in v_def)=0
     or position('contactAddressDoesNotCreateResidence' in v_def)=0 then
    raise exception 'Bookplate writer does not establish/correct Personal Atlas through the governed boundary.';
  end if;

  if position('update auth.users' in lower(v_def))>0
     or position('update atlas.personal_atlas_purchases' in lower(v_def))>0
     or position('insert into atlas.household_residence_arrangements' in lower(v_def))>0
     or position('upsert_personal_residence_arrangement' in lower(v_def))>0 then
    raise exception 'Bookplate writer may not rewrite auth, purchase evidence, or residence truth.';
  end if;

  select pg_get_functiondef('atlas.set_personal_atlas_index_selection_self_api_v1(jsonb)'::regprocedure)
  into v_def;
  if position('orientation_version' in v_def)=0
     or position('first_encounter_index_selection_v1' in v_def)=0
     or position('index_categories' in v_def)=0
     or position('''{}''::jsonb' in v_def)=0
     or position('selectionDoesNotEstablishDomainTruth' in v_def)=0
     or position('selectionDoesNotEstablishRoleOrScale' in v_def)=0 then
    raise exception 'Index writer does not preserve intentional-structure-only semantics.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_orientation_profile_self_api_v1()'::regprocedure)
  into v_def;
  if position('orientation_version in (4,3)' in replace(v_def,'  ',' '))=0
     and position('orientation_versionin(4,3)' in replace(replace(v_def,' ',''),E'\n',''))=0 then
    raise exception 'Discovery orientation reader does not prefer Index v4 with v3 fallback.';
  end if;
  if position('index_categories' in v_def)=0
     or position('positionAndScaleAreNotRequiredOnboarding' in v_def)=0 then
    raise exception 'Discovery orientation reader still models Position / Scale as required first encounter state.';
  end if;

  if not exists(
    select 1
    from atlas.reality_discovery_questions
    where question_key='family.children_stage'
      and active
      and options @> '[{"key":"none"},{"key":"minor"},{"key":"adult"},{"key":"both"}]'::jsonb
  ) then
    raise exception 'Family child-stage question does not permit NONE / minor / adult / both.';
  end if;

  if exists(
    select 1
    from atlas.reality_discovery_edges
    where question_key='family.children_stage'
      and signal_key='orientation.family_parent'
      and effect_kind='require'
  ) then
    raise exception 'Family child-stage question still depends on mandatory PARENT onboarding position.';
  end if;

  select pg_get_functiondef('atlas.reality_discovery_question_set_for_encounter_self_api_v1(text,integer)'::regprocedure)
  into v_def;
  if position('personal_atlas_index_selection_self_api_v1' in v_def)=0
     or position('v_selected_categories' in v_def)=0
     or position('subjectDomain' in v_def)=0
     or position('indexSelectionConstrainsFirstDayQuestions' in v_def)=0 then
    raise exception 'First-day Discovery is not constrained/routed by the real Index.';
  end if;

  select pg_get_functiondef('atlas.personal_atlas_section_root_self_api_v1(text)'::regprocedure)
  into v_def;
  if position('reality_discovery_answer_events' in v_def)=0
     or position('orientationWorldDomains' in v_def)=0
     or position('factsComeFromEstablishedHumanDiscoveryEvidence' in v_def)=0
     or position('sectionSelectionDoesNotCreateFacts' in v_def)=0 then
    raise exception 'Section-root projection is not grounded in established discovery evidence.';
  end if;

  select pg_get_functiondef('atlas.atlas_notebook_index_self_api_v1()'::regprocedure)
  into v_def;
  if position('''addressKind'',''bookplate''' in v_def)=0
     or position('''addressKind'',''section''' in v_def)=0
     or position('''spreadKey'',''section:''||d.category' in v_def)=0
     or position('intentionalSectionRoot' in v_def)=0
     or position('selectedSectionRootsAreIntentionalOrganizationNotDomainTruth' in v_def)=0 then
    raise exception 'Notebook Index does not expose Bookplate plus intentional blank section roots.';
  end if;

  if not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.personal_atlas_bookplate_self_api_v1()'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  )
  or not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.set_personal_atlas_bookplate_self_api_v1(p_input jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  )
  or not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.personal_atlas_index_selection_self_api_v1()'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  )
  or not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.set_personal_atlas_index_selection_self_api_v1(p_input jsonb)'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  )
  or not exists(
    select 1
    from atlas.authenticated_rpc_registry
    where signature='atlas.personal_atlas_section_root_self_api_v1(p_category text)'
      and review_status='active'
      and authenticated_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Bookplate / Index RPC custody registry is incomplete.';
  end if;
end;
$validation$;

rollback;
