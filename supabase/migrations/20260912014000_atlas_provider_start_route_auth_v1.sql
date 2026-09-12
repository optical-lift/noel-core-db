begin;

create or replace function atlas.provider_connection_start_context_self_api_v1(
  p_session_id uuid,
  p_provider_key text,
  p_state_nonce_digest text
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,atlas,auth
as $function$
declare
  v_user uuid:=auth.uid();
  v_provider text:=lower(btrim(coalesce(p_provider_key,'')));
  v_digest text:=lower(btrim(coalesce(p_state_nonce_digest,'')));
  v_session atlas.provider_connection_sessions%rowtype;
begin
  if v_user is null then
    raise exception 'Sign in required.' using errcode='42501';
  end if;
  if p_session_id is null or v_provider='' or v_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'Provider start session, provider, and state digest are required.' using errcode='22023';
  end if;

  select * into v_session
  from atlas.provider_connection_sessions
  where id=p_session_id
    and actor_user_id=v_user
  for update;

  if v_session.id is null then
    raise exception 'Provider connection session is not available to this actor.' using errcode='42501';
  end if;
  if v_session.provider_key is distinct from v_provider then
    raise exception 'Provider connection session does not match the requested provider.' using errcode='42501';
  end if;
  if v_session.state_nonce_digest is distinct from v_digest then
    raise exception 'Provider authorization state does not match this Atlas session.' using errcode='42501';
  end if;
  if v_session.session_state<>'pending' then
    raise exception 'Provider connection session is not pending.' using errcode='55000';
  end if;
  if now()>v_session.expires_at then
    update atlas.provider_connection_sessions
    set session_state='expired',updated_at=now()
    where id=v_session.id and session_state='pending';
    raise exception 'Provider connection session expired.' using errcode='55000';
  end if;

  return jsonb_build_object(
    'contractVersion','provider_connection_start_context_v1',
    'sessionId',v_session.id,
    'providerKey',v_session.provider_key,
    'custodianKind',v_session.custodian_kind,
    'organizationId',v_session.custodian_organization_id,
    'sessionState',v_session.session_state,
    'expiresAt',v_session.expires_at,
    'actorMatched',true,
    'stateMatched',true
  );
end;
$function$;

revoke all on function atlas.provider_connection_start_context_self_api_v1(uuid,text,text) from public,anon;
grant execute on function atlas.provider_connection_start_context_self_api_v1(uuid,text,text) to authenticated;

create or replace function public.provider_connection_start_context_self_api_v1(
  p_session_id uuid,
  p_provider_key text,
  p_state_nonce_digest text
) returns jsonb
language sql
set search_path=pg_catalog,atlas,public
as $function$
  select atlas.provider_connection_start_context_self_api_v1(p_session_id,p_provider_key,p_state_nonce_digest);
$function$;

revoke all on function public.provider_connection_start_context_self_api_v1(uuid,text,text) from public,anon;
grant execute on function public.provider_connection_start_context_self_api_v1(uuid,text,text) to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,authenticated_execute_expected,security_definer_expected,service_execute_expected,caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values (
  'atlas.provider_connection_start_context_self_api_v1(uuid, text, text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'source','atlas_provider_start_route_auth_v1',
    'purpose','Authorize opening a provider OAuth start URL only for the signed-in actor who created the pending Atlas provider connection session.',
    'boundary','Requires auth.uid() to equal provider_connection_sessions.actor_user_id, exact provider match, exact stored state digest match, pending state, and unexpired session.',
    'truthBoundary','Authorizes transport initiation only; creates no Connected Source, provider credential, communication evidence, responsibility, or business truth.',
    'classificationRuleVersion',3,
    'directSignedInEndpoint',true
  ),now(),false
) on conflict (signature) do update
set classification=excluded.classification,
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

commit;
