begin;

do $validation$
declare
  v_lex constant uuid:='f5100000-0000-4000-8000-000000000001'::uuid;
  v_venue constant uuid:='f5100000-0000-4000-8000-000000000011'::uuid;
  v_flower constant uuid:='f5100000-0000-4000-8000-000000000014'::uuid;
  v_external constant uuid:='f5100000-0000-4000-8000-000000000030'::uuid;
  v_result jsonb;
  v_repeat jsonb;
  v_action jsonb;
  v_read jsonb;
  v_context_count integer;
  v_establishment_count integer;
  v_route_count integer;
  v_denied boolean:=false;
begin
  perform set_config('request.jwt.claim.sub',v_lex::text,true);

  if reality.resolve_responsibility_relation_v1(
       v_lex,
       'institutional_external_entity_engagement',
       'ledger_entity_attach',
       'entity',
       'f5100000-0000-4000-8000-000000000002'::uuid,
       null,
       jsonb_build_object('ledgerIds',jsonb_build_array(v_venue::text))
     ) is null then
    raise exception 'Elm Venue external-Entity responsibility did not resolve.';
  end if;

  if reality.resolve_responsibility_relation_v1(
       v_lex,
       'institutional_external_entity_engagement',
       'ledger_entity_attach',
       'entity',
       'f5100000-0000-4000-8000-000000000002'::uuid,
       null,
       jsonb_build_object('ledgerIds',jsonb_build_array(v_flower::text))
     ) is not null then
    raise exception 'Elm Venue external-Entity responsibility leaked into Flower Ledger.';
  end if;

  v_result:=atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
    v_venue,
    v_external,
    'prospect',
    jsonb_build_object(
      'selectionReason','Potential recurring Marshfield branch-office user.',
      'validationFixture',true
    ),
    jsonb_build_object('validationFixture',true)
  );

  if (v_result#>>'{admission,entityId}')::uuid<>v_external
     or not coalesce((v_result#>>'{admission,inserted}')::boolean,false)
     or v_result#>>'{context,contextKind}'<>'prospect'
     or v_result#>>'{context,contextState}'<>'active'
     or v_result#>>'{action,actionKind}'<>'entity_context_established' then
    raise exception 'Initial external Entity attachment failed: %',v_result;
  end if;

  if not exists (
    select 1
    from reality.entities e
    where e.id=v_external
      and e.stable_key='validation-springfield-firm'
      and e.entity_kind='business'
      and e.identity_state='canonical'
  ) then
    raise exception 'Shared Intelligence Entity was not admitted with its original UUID.';
  end if;

  if (
    select count(*)
    from reality.entities e
    where e.stable_key='validation-springfield-firm'
  )<>1 then
    raise exception 'Admission created or tolerated duplicate canonical identity.';
  end if;

  select count(*) into v_route_count
  from reality.contact_routes r
  where r.entity_id=v_external
    and r.route_kind='email'
    and r.normalized_value='hello@validation.example'
    and r.public_disclosure
    and r.route_state='observed';

  if v_route_count<>1 then
    raise exception 'Public Shared Intelligence contact route did not cross admission membrane correctly.';
  end if;

  v_repeat:=atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
    v_venue,
    v_external,
    'prospect',
    jsonb_build_object('validationRepeat',true),
    jsonb_build_object('validationRepeat',true)
  );

  if coalesce((v_repeat#>>'{admission,inserted}')::boolean,true)
     or not coalesce((v_repeat#>>'{admission,reusedExistingRealityEntity}')::boolean,false) then
    raise exception 'Repeated admission was not idempotent: %',v_repeat;
  end if;

  select count(*) into v_context_count
  from ledger.entity_contexts c
  where c.ledger_id=v_venue
    and c.entity_id=v_external
    and c.context_kind='prospect';

  if v_context_count<>1 then
    raise exception 'Repeated attachment duplicated Ledger Entity context.';
  end if;

  select count(*) into v_establishment_count
  from ledger.actions a
  where a.ledger_id=v_venue
    and a.object_entity_id=v_external
    and a.action_kind='entity_context_established';

  if v_establishment_count<>1 then
    raise exception 'Repeated attachment duplicated context establishment action.';
  end if;

  v_action:=atlas.record_ledger_entity_action_self_api_v1(
    v_venue,
    v_external,
    'outreach_attempted',
    now(),
    jsonb_build_object(
      'channel','phone',
      'outcome','no_answer',
      'followUp','try_again_next_week'
    ),
    jsonb_build_object('validationFixture',true),
    'validation-outreach-attempt-1'
  );

  if (v_action->>'entityId')::uuid<>v_external
     or v_action->>'actionKind'<>'outreach_attempted'
     or (v_action->>'performedByEntityId')::uuid<>v_lex then
    raise exception 'Entity-targeted Ledger action was not recorded correctly: %',v_action;
  end if;

  v_read:=atlas.ledger_entity_contexts_self_api_v1(v_venue,'prospect');

  if jsonb_array_length(v_read->'items')<>1
     or v_read#>>'{items,0,entity,id}'<>v_external::text
     or v_read#>>'{items,0,lastAction,actionKind}'<>'outreach_attempted'
     or v_read#>>'{items,0,contactRoutes,0,routeValue}'<>'hello@validation.example' then
    raise exception 'Ledger Entity context read projection is incorrect: %',v_read;
  end if;

  begin
    perform atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(
      v_flower,
      v_external,
      'prospect',
      '{"validationCrossLedger":true}'::jsonb,
      '{}'::jsonb
    );
  exception
    when insufficient_privilege then
      v_denied:=true;
  end;

  if not v_denied then
    raise exception 'Venue external-Entity authority was not bounded to the Venue Ledger.';
  end if;

  if exists (
    select 1
    from ledger.entity_contexts c
    where c.ledger_id=v_flower
      and c.entity_id=v_external
  ) then
    raise exception 'Denied cross-Ledger attachment still wrote Entity context.';
  end if;

  if has_table_privilege('authenticated','ledger.entity_contexts','SELECT')
     or has_table_privilege('authenticated','ledger.entity_contexts','INSERT')
     or has_function_privilege(
       'authenticated',
       'atlas.admit_shared_intelligence_entity_to_reality_service_v1(uuid,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'ledger.record_entity_action_service_v1(uuid,uuid,text,uuid,timestamp with time zone,jsonb,jsonb,text)',
       'EXECUTE'
     ) then
    raise exception 'External Entity bridge leaked direct authenticated mutation authority.';
  end if;

  if has_function_privilege(
       'anon',
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.record_ledger_entity_action_self_api_v1(uuid,uuid,text,timestamp with time zone,jsonb,jsonb,text)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'atlas.ledger_entity_contexts_self_api_v1(uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'Anonymous authority leaked into external Entity bridge.';
  end if;

  if not has_function_privilege(
       'authenticated',
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.record_ledger_entity_action_self_api_v1(uuid,uuid,text,timestamp with time zone,jsonb,jsonb,text)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'atlas.ledger_entity_contexts_self_api_v1(uuid,text)',
       'EXECUTE'
     ) then
    raise exception 'Authenticated bridge contract is incomplete.';
  end if;

  if pg_get_functiondef(
       'ledger.upsert_entity_context_service_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%local_intel%' then
    raise exception 'Ledger core Entity-context service depends directly on Shared Intelligence.';
  end if;

  if pg_get_functiondef(
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.attach_shared_intelligence_entity_to_ledger_self_api_v1(uuid,uuid,text,jsonb,jsonb)'::regprocedure
     ) ilike '%principal_ledger_authorities%'
     or pg_get_functiondef(
       'atlas.record_ledger_entity_action_self_api_v1(uuid,uuid,text,timestamp with time zone,jsonb,jsonb,text)'::regprocedure
     ) ilike '%organization_memberships%'
     or pg_get_functiondef(
       'atlas.record_ledger_entity_action_self_api_v1(uuid,uuid,text,timestamp with time zone,jsonb,jsonb,text)'::regprocedure
     ) ilike '%principal_ledger_authorities%' then
    raise exception 'External Entity bridge revived retired Organization authority.';
  end if;
end
$validation$;

rollback;
