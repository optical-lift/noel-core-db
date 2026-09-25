revoke all on function atlas.claim_institutional_conversation_self_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.claim_institutional_conversation_self_api_v1(uuid,text)
  to authenticated;

revoke all on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)
  from public,anon,service_role;
grant execute on function atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)
  to authenticated;

revoke all on function atlas.claim_communication_conversation_self_api_v1(uuid,text)
  from public,anon,service_role;
grant execute on function atlas.claim_communication_conversation_self_api_v1(uuid,text)
  to authenticated;

revoke all on function atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)
  from public,anon,service_role;
grant execute on function atlas.remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)
  to authenticated;

revoke all on function atlas.set_communication_conversation_response_state_self_api_v1(uuid,text,text)
  from public,anon,service_role;
grant execute on function atlas.set_communication_conversation_response_state_self_api_v1(uuid,text,text)
  to authenticated;

insert into atlas.authenticated_rpc_registry(
  signature,classification,confidence,review_status,
  authenticated_execute_expected,security_definer_expected,service_execute_expected,
  caller_count,policy_reference_count,evidence,reviewed_at,anonymous_execute_expected
) values
(
  'atlas.claim_communication_conversation_self_api_v1(uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'compatibilityWrapperFor','atlas.claim_institutional_conversation_self_api_v1(uuid,text)',
    'authoritySource','institutional_communication_response_work',
    'truthBoundary','Common-conversation routing wrapper. Does not establish authority independently.'
  ),now(),false
),
(
  'atlas.handoff_communication_conversation_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'compatibilityWrapperFor','atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)',
    'state','receiver_uptake_required',
    'truthBoundary','Direct transfer remains fail-closed.'
  ),now(),false
),
(
  'atlas.add_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'compatibilityWrapperFor','atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)',
    'state','receiver_uptake_required',
    'truthBoundary','Direct collaborator assignment remains fail-closed.'
  ),now(),false
),
(
  'atlas.remove_communication_conversation_collaborator_self_api_v1(uuid,uuid,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'compatibilityWrapperFor','atlas.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)',
    'authoritySource','self_release_or_exact_work_responsibility'
  ),now(),false
),
(
  'atlas.set_communication_conversation_response_state_self_api_v1(uuid,text,text)',
  'app_endpoint','verified','active',true,true,false,0,0,
  jsonb_build_object(
    'compatibilityWrapperFor','atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)',
    'authoritySource','exact_work_responsibility'
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
set service_execute_expected=false,
    authenticated_execute_expected=true,
    anonymous_execute_expected=false,
    reviewed_at=now()
where signature in (
  'atlas.claim_institutional_conversation_self_api_v1(uuid,text)',
  'atlas.handoff_institutional_conversation_self_api_v1(uuid,uuid,text)',
  'atlas.add_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)',
  'atlas.remove_institutional_conversation_collaborator_self_api_v1(uuid,uuid,text)',
  'atlas.set_institutional_conversation_response_state_self_api_v1(uuid,text,text)'
);

do $validation$
declare
  v_oid oid;
begin
  for v_oid in
    select p.oid
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='atlas'
      and p.proname in (
        'claim_institutional_conversation_self_api_v1',
        'handoff_institutional_conversation_self_api_v1',
        'add_institutional_conversation_collaborator_self_api_v1',
        'remove_institutional_conversation_collaborator_self_api_v1',
        'set_institutional_conversation_response_state_self_api_v1',
        'claim_communication_conversation_self_api_v1',
        'handoff_communication_conversation_self_api_v1',
        'add_communication_conversation_collaborator_self_api_v1',
        'remove_communication_conversation_collaborator_self_api_v1',
        'set_communication_conversation_response_state_self_api_v1'
      )
  loop
    if has_function_privilege('anon',v_oid,'EXECUTE')
       or not has_function_privilege('authenticated',v_oid,'EXECUTE')
       or has_function_privilege('service_role',v_oid,'EXECUTE') then
      raise exception 'Response-work self RPC privilege surface is not authenticated-only.';
    end if;
  end loop;
end
$validation$;
