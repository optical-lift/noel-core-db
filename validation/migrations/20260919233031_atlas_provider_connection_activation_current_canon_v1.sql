do $validation$
declare
  v_personal_user uuid:=gen_random_uuid();
  v_owner_user uuid:=gen_random_uuid();
  v_member_user uuid:=gen_random_uuid();
  v_consultant_user uuid:=gen_random_uuid();
  v_setup_user uuid:=gen_random_uuid();
  v_org uuid:=gen_random_uuid();

  v_result jsonb;
  v_session_personal uuid;
  v_session_personal_retry uuid;
  v_session_expired uuid;
  v_session_capability uuid;
  v_session_scope uuid;
  v_session_revoked_a uuid;
  v_session_revoked_b uuid;
  v_session_org_owner uuid;
  v_session_org_setup uuid;

  v_source_personal uuid;
  v_source_personal_retry uuid;
  v_source_revoked uuid;
  v_source_org_owner uuid;
  v_source_org_setup uuid;

  v_purchase uuid;
  v_case uuid;
  v_case_source uuid;

  v_begin_oid oid;
  v_complete_oid oid;
  v_activate_oid oid;
  v_bind_oid oid;
  v_def text;
  v_config text[];
  v_count integer;
begin
  if to_regclass('atlas.provider_connection_sessions') is null then
    raise exception 'Provider connection session table is missing.';
  end if;

  if not exists(
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='atlas' and c.relname='provider_connection_sessions'
      and c.relrowsecurity
  ) then
    raise exception 'Provider connection session table must have RLS enabled.';
  end if;

  if has_table_privilege('anon','atlas.provider_connection_sessions','select')
     or has_table_privilege('authenticated','atlas.provider_connection_sessions','select')
     or has_table_privilege('authenticated','atlas.provider_connection_sessions','insert')
     or has_table_privilege('authenticated','atlas.provider_connection_sessions','update')
     or has_table_privilege('authenticated','atlas.provider_connection_sessions','delete') then
    raise exception 'Browser roles must not have direct provider connection session table access.';
  end if;

  v_begin_oid:=to_regprocedure(
    'atlas.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb)'
  );
  v_complete_oid:=to_regprocedure(
    'atlas.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb)'
  );
  v_activate_oid:=to_regprocedure(
    'atlas.activate_provider_connection_service_v1(uuid,text,jsonb)'
  );
  v_bind_oid:=to_regprocedure(
    'atlas.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)'
  );

  if v_begin_oid is null or v_complete_oid is null or v_activate_oid is null or v_bind_oid is null then
    raise exception 'Provider connection activation functions are incomplete.';
  end if;

  if has_function_privilege('anon',v_begin_oid,'execute')
     or not has_function_privilege('authenticated',v_begin_oid,'execute')
     or not has_function_privilege('service_role',v_begin_oid,'execute') then
    raise exception 'Begin provider connection ACL is incorrect.';
  end if;

  if has_function_privilege('anon',v_complete_oid,'execute')
     or has_function_privilege('authenticated',v_complete_oid,'execute')
     or not has_function_privilege('service_role',v_complete_oid,'execute') then
    raise exception 'Provider identity completion must remain service-only.';
  end if;

  if has_function_privilege('anon',v_activate_oid,'execute')
     or has_function_privilege('authenticated',v_activate_oid,'execute')
     or not has_function_privilege('service_role',v_activate_oid,'execute') then
    raise exception 'Provider activation must remain service-only.';
  end if;

  if has_function_privilege('anon',v_bind_oid,'execute')
     or not has_function_privilege('authenticated',v_bind_oid,'execute')
     or not has_function_privilege('service_role',v_bind_oid,'execute') then
    raise exception 'Implementation source binding ACL is incorrect.';
  end if;

  select pg_get_functiondef(p.oid),p.proconfig
    into v_def,v_config
  from pg_proc p
  where p.oid=v_begin_oid;

  if position('SECURITY DEFINER' in upper(v_def))=0
     or not ('search_path=pg_catalog, atlas, auth'=any(coalesce(v_config,'{}'::text[]))) then
    raise exception 'Begin provider connection authority must remain SECURITY DEFINER with pinned search_path.';
  end if;

  if to_regprocedure(
       'public.begin_provider_connection_self_api_v1(text,uuid,text,text[],jsonb,text,text,text,integer,jsonb)'
     ) is null
     or to_regprocedure(
       'public.bind_implementation_case_connected_source_self_api_v1(uuid,uuid)'
     ) is null then
    raise exception 'Browser RPC membranes are missing.';
  end if;

  insert into auth.users(id,email,created_at,updated_at)
  values
    (v_personal_user,'provider-personal-'||substr(v_personal_user::text,1,8)||'@example.test',now(),now()),
    (v_owner_user,'provider-owner-'||substr(v_owner_user::text,1,8)||'@example.test',now(),now()),
    (v_member_user,'provider-member-'||substr(v_member_user::text,1,8)||'@example.test',now(),now()),
    (v_consultant_user,'provider-consultant-'||substr(v_consultant_user::text,1,8)||'@example.test',now(),now()),
    (v_setup_user,'provider-setup-'||substr(v_setup_user::text,1,8)||'@example.test',now(),now());

  insert into atlas.principals(user_id,stable_key,name)
  values
    (v_personal_user,'provider-proof-personal-'||substr(v_personal_user::text,1,8),'Provider Proof Personal'),
    (v_owner_user,'provider-proof-owner-'||substr(v_owner_user::text,1,8),'Provider Proof Owner'),
    (v_member_user,'provider-proof-member-'||substr(v_member_user::text,1,8),'Provider Proof Member'),
    (v_consultant_user,'provider-proof-consultant-'||substr(v_consultant_user::text,1,8),'Provider Proof Consultant'),
    (v_setup_user,'provider-proof-setup-'||substr(v_setup_user::text,1,8),'Provider Proof Setup');

  insert into atlas.organizations(id,stable_key,name)
  values(v_org,'provider-proof-org-'||substr(v_org::text,1,8),'Provider Proof Organization');

  insert into atlas.organization_memberships(organization_id,user_id,role,active)
  values
    (v_org,v_owner_user,'owner',true),
    (v_org,v_member_user,'member',true),
    (v_org,v_consultant_user,'consultant',true);

  insert into atlas.organization_onboarding_actors(
    organization_id,human_user_id,actor_kind,active
  ) values(v_org,v_setup_user,'setup_actor',true);

  -- Signed-out callers fail closed.
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform atlas.begin_provider_connection_self_api_v1(
      'human',null,'fixture_provider',array['read'],
      '{"communicationCapture":true}'::jsonb,repeat('0',64),
      null,null,600,'{}'::jsonb
    );
    raise exception 'Signed-out provider connection unexpectedly succeeded.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Human custody is bound to the authenticated active Principal.
  perform set_config('request.jwt.claim.sub',v_personal_user::text,true);
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read','write'],
    '{"communicationCapture":true}'::jsonb,repeat('1',64),
    'pkce-challenge-personal','https://example.test/callback',600,
    '{"proof":"personal"}'::jsonb
  );
  v_session_personal:=(v_result->>'sessionId')::uuid;

  if not exists(
    select 1 from atlas.provider_connection_sessions s
    where s.id=v_session_personal
      and s.actor_user_id=v_personal_user
      and s.custodian_kind='human'
      and s.custodian_user_id=v_personal_user
      and s.custodian_organization_id is null
      and s.provider_key='fixture_provider'
      and s.session_state='pending'
  ) then
    raise exception 'Human provider session did not preserve intended custody.';
  end if;

  begin
    perform atlas.begin_provider_connection_self_api_v1(
      'human',v_org,'fixture_provider',array['read'],
      '{"communicationCapture":true}'::jsonb,repeat('2',64),
      null,null,600,'{}'::jsonb
    );
    raise exception 'Human provider session accepted Organization custody.';
  exception when sqlstate '22023' then
    null;
  end;

  begin
    perform atlas.begin_provider_connection_self_api_v1(
      'human',null,'fixture_provider',array['read'],
      '{"communicationCapture":true}'::jsonb,repeat('3',64),
      null,null,600,'{"refresh_token":"forbidden"}'::jsonb
    );
    raise exception 'Provider connection metadata accepted a reusable secret.';
  exception when sqlstate '22023' then
    null;
  end;

  -- Ordinary member and consultant cannot administer Organization provider custody.
  perform set_config('request.jwt.claim.sub',v_member_user::text,true);
  begin
    perform atlas.begin_provider_connection_self_api_v1(
      'organization',v_org,'fixture_provider',array['read'],
      '{"communicationCapture":true}'::jsonb,repeat('4',64),
      null,null,600,'{}'::jsonb
    );
    raise exception 'Ordinary member received provider connection authority.';
  exception when sqlstate '42501' then
    null;
  end;

  perform set_config('request.jwt.claim.sub',v_consultant_user::text,true);
  begin
    perform atlas.begin_provider_connection_self_api_v1(
      'organization',v_org,'fixture_provider',array['read'],
      '{"communicationCapture":true}'::jsonb,repeat('5',64),
      null,null,600,'{}'::jsonb
    );
    raise exception 'Consultant membership received provider connection authority.';
  exception when sqlstate '42501' then
    null;
  end;

  -- Owner may begin Organization connection.
  perform set_config('request.jwt.claim.sub',v_owner_user::text,true);
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'organization',v_org,'fixture_provider',array['read','write'],
    '{"communicationCapture":true}'::jsonb,repeat('6',64),
    null,null,600,'{"proof":"owner"}'::jsonb
  );
  v_session_org_owner:=(v_result->>'sessionId')::uuid;

  -- Active setup actor may begin the same Organization connection without becoming its custodian.
  perform set_config('request.jwt.claim.sub',v_setup_user::text,true);
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'organization',v_org,'fixture_provider',array['read','write'],
    '{"communicationCapture":true}'::jsonb,repeat('7',64),
    null,null,600,'{"proof":"setup"}'::jsonb
  );
  v_session_org_setup:=(v_result->>'sessionId')::uuid;

  -- Expired session cannot establish source identity.
  perform set_config('request.jwt.claim.sub',v_personal_user::text,true);
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('8',64),
    null,null,60,'{}'::jsonb
  );
  v_session_expired:=(v_result->>'sessionId')::uuid;
  update atlas.provider_connection_sessions
  set expires_at=now()-interval '1 second'
  where id=v_session_expired;

  begin
    perform atlas.complete_provider_connection_identity_service_v1(
      v_session_expired,'expired-account',null,null,
      array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
    );
    raise exception 'Expired provider session established provider identity.';
  exception when sqlstate '55000' then
    null;
  end;

  if exists(
    select 1 from atlas.connected_sources
    where provider_key='fixture_provider'
      and provider_account_key='expired-account'
  ) then
    raise exception 'Expired session created a Connected Source.';
  end if;

  -- Capabilities and provider scopes cannot expand beyond the bounded session.
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('9',64),
    null,null,600,'{}'::jsonb
  );
  v_session_capability:=(v_result->>'sessionId')::uuid;

  begin
    perform atlas.complete_provider_connection_identity_service_v1(
      v_session_capability,'capability-escalation',null,null,
      array['read'],'{"moneyCollection":true}'::jsonb,'{}'::jsonb
    );
    raise exception 'Provider callback expanded Atlas capabilities.';
  exception when sqlstate '22023' then
    null;
  end;

  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('a',64),
    null,null,600,'{}'::jsonb
  );
  v_session_scope:=(v_result->>'sessionId')::uuid;

  begin
    perform atlas.complete_provider_connection_identity_service_v1(
      v_session_scope,'scope-escalation',null,null,
      array['read','write'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
    );
    raise exception 'Provider callback expanded provider scopes.';
  exception when sqlstate '22023' then
    null;
  end;

  -- Personal source: provider identity creates/reuses pending source only.
  v_result:=atlas.complete_provider_connection_identity_service_v1(
    v_session_personal,'personal-account','Personal Fixture','personal@example.test',
    array['read'],'{"communicationCapture":true}'::jsonb,
    '{"providerEvidence":"verified"}'::jsonb
  );
  v_source_personal:=(v_result->>'connectedSourceId')::uuid;

  if not exists(
    select 1 from atlas.connected_sources s
    where s.id=v_source_personal
      and s.custodian_user_id=v_personal_user
      and s.custodian_organization_id is null
      and s.provider_key='fixture_provider'
      and s.provider_account_key='personal-account'
      and s.authorization_state='pending'
  ) then
    raise exception 'Provider identity completion did not create pending human-custodied source.';
  end if;

  begin
    perform atlas.activate_provider_connection_service_v1(
      v_session_personal,'oauth_refresh_token','{}'::jsonb
    );
    raise exception 'Source activated before credential custody existed.';
  exception when sqlstate '55000' then
    null;
  end;

  perform atlas.store_connected_source_secret_service_v1(
    v_source_personal,'oauth_refresh_token','fixture-secret-value','provider activation proof'
  );
  v_result:=atlas.activate_provider_connection_service_v1(
    v_session_personal,'oauth_refresh_token','{"proof":"activated"}'::jsonb
  );

  if v_result->>'authorizationState'<>'connected'
     or not exists(
       select 1 from atlas.connected_sources
       where id=v_source_personal and authorization_state='connected'
     ) then
    raise exception 'Credential-backed provider activation failed.';
  end if;

  if exists(
    select 1
    from atlas.provider_connection_sessions s
    join atlas.connected_sources cs on cs.id=v_source_personal
    where s.id=v_session_personal
      and (s.metadata::text ilike '%fixture-secret-value%'
           or cs.metadata::text ilike '%fixture-secret-value%')
  ) then
    raise exception 'Reusable provider secret leaked into ordinary metadata.';
  end if;

  -- Retry with the same truthful custody/provider/account must reuse source identity.
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('b',64),
    null,null,600,'{}'::jsonb
  );
  v_session_personal_retry:=(v_result->>'sessionId')::uuid;

  v_result:=atlas.complete_provider_connection_identity_service_v1(
    v_session_personal_retry,'personal-account','Personal Fixture Retry',null,
    array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
  );
  v_source_personal_retry:=(v_result->>'connectedSourceId')::uuid;

  if v_source_personal_retry<>v_source_personal then
    raise exception 'Provider connection retry minted duplicate Connected Source identity.';
  end if;
  if not exists(
    select 1 from atlas.connected_sources
    where id=v_source_personal and authorization_state='connected'
  ) then
    raise exception 'Identity retry downgraded an already-connected source.';
  end if;

  select count(*) into v_count
  from atlas.connected_sources
  where custodian_user_id=v_personal_user
    and provider_key='fixture_provider'
    and provider_account_key='personal-account';
  if v_count<>1 then
    raise exception 'Personal Connected Source identity is not idempotent.';
  end if;

  -- Revoked source cannot be silently revived by a fresh provider callback.
  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('c',64),
    null,null,600,'{}'::jsonb
  );
  v_session_revoked_a:=(v_result->>'sessionId')::uuid;
  v_result:=atlas.complete_provider_connection_identity_service_v1(
    v_session_revoked_a,'revoked-account',null,null,
    array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
  );
  v_source_revoked:=(v_result->>'connectedSourceId')::uuid;

  update atlas.connected_sources
  set authorization_state='revoked',revoked_at=now(),updated_at=now()
  where id=v_source_revoked;

  v_result:=atlas.begin_provider_connection_self_api_v1(
    'human',null,'fixture_provider',array['read'],
    '{"communicationCapture":true}'::jsonb,repeat('d',64),
    null,null,600,'{}'::jsonb
  );
  v_session_revoked_b:=(v_result->>'sessionId')::uuid;

  begin
    perform atlas.complete_provider_connection_identity_service_v1(
      v_session_revoked_b,'revoked-account',null,null,
      array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
    );
    raise exception 'Fresh callback silently revived revoked Connected Source.';
  exception when sqlstate '55000' then
    null;
  end;

  if not exists(
    select 1 from atlas.connected_sources
    where id=v_source_revoked and authorization_state='revoked' and revoked_at is not null
  ) then
    raise exception 'Revoked Connected Source history was cleared.';
  end if;

  -- Organization source created by owner.
  perform set_config('request.jwt.claim.sub',v_owner_user::text,true);
  v_result:=atlas.complete_provider_connection_identity_service_v1(
    v_session_org_owner,'organization-account','Organization Fixture','org@example.test',
    array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
  );
  v_source_org_owner:=(v_result->>'connectedSourceId')::uuid;

  if not exists(
    select 1 from atlas.connected_sources s
    where s.id=v_source_org_owner
      and s.custodian_user_id is null
      and s.custodian_organization_id=v_org
      and s.authorization_state='pending'
  ) then
    raise exception 'Organization provider identity completion created wrong custody.';
  end if;

  -- Setup actor resolves the same external account to the same Organization source.
  perform set_config('request.jwt.claim.sub',v_setup_user::text,true);
  v_result:=atlas.complete_provider_connection_identity_service_v1(
    v_session_org_setup,'organization-account','Organization Fixture Setup',null,
    array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
  );
  v_source_org_setup:=(v_result->>'connectedSourceId')::uuid;

  if v_source_org_setup<>v_source_org_owner then
    raise exception 'Setup actor produced duplicate Organization Connected Source.';
  end if;
  if exists(
    select 1 from atlas.connected_sources
    where id=v_source_org_setup and custodian_user_id=v_setup_user
  ) then
    raise exception 'Setup actor became provider-account custodian.';
  end if;

  perform atlas.store_connected_source_secret_service_v1(
    v_source_org_setup,'oauth_refresh_token','organization-secret-value','organization provider proof'
  );
  perform atlas.activate_provider_connection_service_v1(
    v_session_org_setup,'oauth_refresh_token','{}'::jsonb
  );

  if not exists(
    select 1 from atlas.connected_sources
    where id=v_source_org_setup
      and custodian_organization_id=v_org
      and custodian_user_id is null
      and authorization_state='connected'
  ) then
    raise exception 'Organization source did not activate under Organization custody.';
  end if;

  -- Implementation Case Source is requirement/admission context only.
  insert into atlas.implementation_purchases(
    provider_checkout_session_id,offer_key,starting_label,payment_option,
    setup_contract_amount_cents,monthly_ledger_unit_price_cents
  ) values (
    'cs_test_provider_'||substr(replace(gen_random_uuid()::text,'-',''),1,12),
    'provider_connection_proof','Provider Connection Proof','pay_in_full',0,0
  ) returning id into v_purchase;

  insert into atlas.implementation_cases(implementation_purchase_id,state)
  values(v_purchase,'in_implementation')
  returning id into v_case;

  insert into atlas.implementation_case_participants(
    implementation_case_id,human_user_id,relationship_kind,verified_at
  ) values(v_case,v_setup_user,'setup_sponsor',now());

  insert into atlas.implementation_case_sources(
    implementation_case_id,provider_key,display_label,identified_by_user_id,requirement_state
  ) values(
    v_case,'fixture_provider','Organization Provider Requirement',v_setup_user,'required'
  ) returning id into v_case_source;

  v_result:=atlas.bind_implementation_case_connected_source_self_api_v1(
    v_case_source,v_source_org_setup
  );

  if v_result->>'sourceOwnershipChanged'<>'false'
     or not exists(
       select 1
       from atlas.implementation_case_sources cs
       where cs.id=v_case_source
         and cs.connected_source_id=v_source_org_setup
         and cs.source_state='connected'
         and cs.usable_at is not null
     )
     or not exists(
       select 1
       from atlas.connected_sources s
       where s.id=v_source_org_setup
         and s.custodian_organization_id=v_org
         and s.custodian_user_id is null
     ) then
    raise exception 'Implementation binding changed or misrepresented provider ownership.';
  end if;

  -- Retired implementation registration cannot create provider custody.
  begin
    perform atlas.register_implementation_connected_source_self_api_v1(
      v_case_source,'fixture_provider','forbidden-direct-account',
      'Forbidden','forbidden@example.test','connected',
      array['read'],'{"communicationCapture":true}'::jsonb,'{}'::jsonb
    );
    raise exception 'Retired implementation registration still creates Connected Sources.';
  exception when sqlstate '0A000' then
    null;
  end;

  if exists(
    select 1 from atlas.connected_sources
    where provider_key='fixture_provider'
      and provider_account_key='forbidden-direct-account'
  ) then
    raise exception 'Retired implementation registration created provider custody.';
  end if;

  -- Retired implementation transition cannot mutate Connected Source authorization.
  begin
    perform atlas.transition_implementation_connected_source_authorization_self_a(
      v_case_source,v_source_org_setup,'error','{"reason":"forbidden"}'::jsonb
    );
    raise exception 'Retired implementation transition still mutates Connected Source authorization.';
  exception when sqlstate '0A000' then
    null;
  end;

  if not exists(
    select 1 from atlas.connected_sources
    where id=v_source_org_setup and authorization_state='connected'
  ) then
    raise exception 'Retired implementation transition changed provider authorization.';
  end if;

  -- New authenticated RPCs are present in the custody registry.
  if not exists(
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.begin_provider_connection_self_api_v1(text, uuid, text, text[], jsonb, text, text, text, integer, jsonb)'
      and classification='app_endpoint'
      and authenticated_execute_expected
      and service_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Begin provider connection RPC registry entry is missing.';
  end if;

  if not exists(
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.complete_provider_connection_identity_service_v1(uuid,text,text,text,text[],jsonb,jsonb)'
      and classification='service_internal'
      and not authenticated_execute_expected
      and service_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Provider identity completion registry entry is missing.';
  end if;

  if not exists(
    select 1 from atlas.authenticated_rpc_registry
    where signature='atlas.activate_provider_connection_service_v1(uuid,text,jsonb)'
      and classification='service_internal'
      and not authenticated_execute_expected
      and service_execute_expected
      and not anonymous_execute_expected
  ) then
    raise exception 'Provider activation registry entry is missing.';
  end if;
end;
$validation$;
