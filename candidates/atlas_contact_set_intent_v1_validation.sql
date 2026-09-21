begin;

do $validation$
declare
  v_ready jsonb;
  v_clarify jsonb;
  v_invalid jsonb;
  v_plan jsonb;
  v_state text;
  v_direct_grants bigint;
begin
  if to_regclass('atlas.contact_set_intent_requests') is null then
    raise exception 'contact_set_intent_requests table is missing';
  end if;
  if to_regprocedure('atlas.validate_contact_set_intent_v1(text,jsonb)') is null then
    raise exception 'contact-set validator is missing';
  end if;
  if to_regprocedure('atlas.plan_contact_set_intent_v1(jsonb)') is null then
    raise exception 'contact-set planner is missing';
  end if;
  if to_regprocedure('atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text)') is null then
    raise exception 'contact-set interpretation service is missing';
  end if;

  v_ready:=jsonb_build_object(
    'intentFamily','build_target_contact_set',
    'objective','mixed',
    'target',jsonb_build_object(
      'description','decision-adjacent people at banks',
      'organizationKinds',jsonb_build_array('bank'),
      'personFunctions',jsonb_build_array('decision_adjacent')
    ),
    'geography',jsonb_build_object(
      'mode','contextual',
      'placeLabels',jsonb_build_array('Marshfield','Lebanon','Springfield'),
      'basis',jsonb_build_object('captureContextRef','town-set:marshfield-lebanon-springfield')
    ),
    'fields',jsonb_build_object(
      'required',jsonb_build_array('email'),
      'optional',jsonb_build_array('name','title','phone','organization')
    ),
    'population',jsonb_build_object('desiredCount',null,'mode','best_supported'),
    'ledgerEffect',jsonb_build_object('attachToLedger',true,'effortTag','contact_discovery'),
    'resolvedReferences',jsonb_build_array(
      jsonb_build_object('phrase','those towns','resolution',jsonb_build_array('Marshfield','Lebanon','Springfield'))
    ),
    'unresolvedReferences','[]'::jsonb,
    'clarificationQuestion',null
  );

  v_invalid:=atlas.validate_contact_set_intent_v1(
    'Find emails.',
    '{"intentFamily":"build_target_contact_set","objective":"mixed","target":{},"fields":{"required":[]}}'::jsonb
  );
  if coalesce((v_invalid->>'valid')::boolean,true) then
    raise exception 'Structurally incomplete interpretation unexpectedly validated';
  end if;

  v_plan:=atlas.plan_contact_set_intent_v1(v_ready);
  if v_plan#>>'{steps,0,operation}'<>'shared_directory_search' then
    raise exception 'Contact plan does not begin with Shared Directory';
  end if;
  if v_plan#>>'{policy,externalAcquisition}'<>'gap_only' then
    raise exception 'External acquisition is not fixed as gap_only';
  end if;
  if v_plan#>>'{steps,3,operation}'<>'acquire_missing_truth'
     or v_plan#>>'{steps,3,condition}'<>'missing_or_stale_or_conflicting_required_fact' then
    raise exception 'Gap-only acquisition step is missing or misordered';
  end if;

  perform atlas.interpret_contact_set_intent_service_v1(
    'f1000000-0000-4000-8000-000000000102'::uuid,
    v_ready,
    'ai',
    'validation-interpreter-v1'
  );
  select request_state into v_state
  from atlas.contact_set_intent_requests
  where id='f1000000-0000-4000-8000-000000000102'::uuid;
  if v_state<>'ready' then
    raise exception 'Resolved contextual interpretation did not become ready';
  end if;

  v_clarify:=jsonb_build_object(
    'intentFamily','build_target_contact_set',
    'objective','mixed',
    'target',jsonb_build_object('description','decision-adjacent people at banks'),
    'geography',jsonb_build_object('mode','contextual'),
    'fields',jsonb_build_object('required',jsonb_build_array('email')),
    'resolvedReferences','[]'::jsonb,
    'unresolvedReferences',jsonb_build_array(
      jsonb_build_object('phrase','those towns','kind','geography')
    ),
    'clarificationQuestion','Which towns do you mean?'
  );

  perform atlas.interpret_contact_set_intent_service_v1(
    'f1000000-0000-4000-8000-000000000104'::uuid,
    v_clarify,
    'ai',
    'validation-interpreter-v1'
  );
  select request_state into v_state
  from atlas.contact_set_intent_requests
  where id='f1000000-0000-4000-8000-000000000104'::uuid;
  if v_state<>'needs_clarification' then
    raise exception 'Unresolved contextual reference did not require clarification';
  end if;

  if not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='contact_set_intent_requests' and c.relrowsecurity
  ) then
    raise exception 'Contact-set intent table RLS is not enabled';
  end if;

  select count(*) into v_direct_grants
  from information_schema.role_table_grants
  where table_schema='atlas'
    and table_name='contact_set_intent_requests'
    and grantee in ('anon','authenticated','service_role');
  if v_direct_grants<>0 then
    raise exception 'Contact-set intent table has direct application-role grants';
  end if;

  if not has_function_privilege('authenticated','atlas.capture_contact_set_intent_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Authenticated role lacks contact-set capture self API';
  end if;
  if has_function_privilege('anon','atlas.capture_contact_set_intent_self_api_v1(jsonb)','EXECUTE') then
    raise exception 'Anon unexpectedly has contact-set capture self API';
  end if;
  if has_function_privilege('authenticated','atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text)','EXECUTE') then
    raise exception 'Authenticated role unexpectedly has direct interpretation service access';
  end if;
  if not has_function_privilege('service_role','atlas.interpret_contact_set_intent_service_v1(uuid,jsonb,text,text)','EXECUTE') then
    raise exception 'Service role lacks contact-set interpretation service access';
  end if;
end;
$validation$;

rollback;
