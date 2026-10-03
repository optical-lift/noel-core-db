revoke all on function atlas.evaluate_delegated_agent_command_authority_v1(uuid,text,integer) from public, anon, authenticated;
revoke all on function atlas.evaluate_delegated_agent_command_target_authority_v1(uuid,text,integer,jsonb) from public, anon, authenticated;
revoke all on function atlas.resolve_delegated_agent_credential_service_v1(text) from public, anon, authenticated;
revoke all on function atlas.begin_delegated_agent_command_service_v1(text,text,integer,jsonb,jsonb,text) from public, anon, authenticated;
revoke all on function atlas.mark_delegated_agent_command_executing_service_v1(uuid) from public, anon, authenticated;
revoke all on function atlas.complete_delegated_agent_command_service_v1(uuid,boolean,jsonb,jsonb) from public, anon, authenticated;
revoke all on function atlas.delegated_agent_command_invocation_service_v1(text,uuid) from public, anon, authenticated;
revoke all on function atlas.register_delegated_agent_carrier_service_v1(text,text,text,text,jsonb) from public, anon, authenticated;
revoke all on function atlas.issue_delegated_agent_credential_service_v1(uuid,text,timestamptz,jsonb) from public, anon, authenticated;

grant execute on function atlas.evaluate_delegated_agent_command_authority_v1(uuid,text,integer) to service_role;
grant execute on function atlas.evaluate_delegated_agent_command_target_authority_v1(uuid,text,integer,jsonb) to service_role;
grant execute on function atlas.resolve_delegated_agent_credential_service_v1(text) to service_role;
grant execute on function atlas.begin_delegated_agent_command_service_v1(text,text,integer,jsonb,jsonb,text) to service_role;
grant execute on function atlas.mark_delegated_agent_command_executing_service_v1(uuid) to service_role;
grant execute on function atlas.complete_delegated_agent_command_service_v1(uuid,boolean,jsonb,jsonb) to service_role;
grant execute on function atlas.delegated_agent_command_invocation_service_v1(text,uuid) to service_role;
grant execute on function atlas.register_delegated_agent_carrier_service_v1(text,text,text,text,jsonb) to service_role;
grant execute on function atlas.issue_delegated_agent_credential_service_v1(uuid,text,timestamptz,jsonb) to service_role;