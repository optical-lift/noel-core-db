revoke all on function atlas.confirm_delegated_agent_command_self_api_v1(uuid) from public, anon;
revoke all on function atlas.establish_delegated_agent_authorization_self_api_v1(uuid,uuid,uuid,text,text[],text[],jsonb,jsonb,text,timestamptz) from public, anon;
revoke all on function atlas.revoke_delegated_agent_authorization_self_api_v1(uuid,text) from public, anon;
revoke all on function atlas.delegated_agent_authorizations_self_api_v1() from public, anon;

grant execute on function atlas.confirm_delegated_agent_command_self_api_v1(uuid) to authenticated;
grant execute on function atlas.establish_delegated_agent_authorization_self_api_v1(uuid,uuid,uuid,text,text[],text[],jsonb,jsonb,text,timestamptz) to authenticated;
grant execute on function atlas.revoke_delegated_agent_authorization_self_api_v1(uuid,text) to authenticated;
grant execute on function atlas.delegated_agent_authorizations_self_api_v1() to authenticated;

revoke execute on function atlas.reject_agent_command_event_mutation_v1() from public, anon, authenticated;
revoke execute on function atlas.execution_class_rank_v1(text) from public, anon, authenticated;