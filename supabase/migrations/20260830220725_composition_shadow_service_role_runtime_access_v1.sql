revoke execute on function local_intel.start_recommendation_shadow_run_v2(uuid,text,text,jsonb,text[],text[],text,timestamptz,timestamptz,integer,integer) from public,anon,authenticated;
revoke execute on function local_intel.add_recommendation_shadow_time_window_candidates_v1(uuid,text,timestamptz,timestamptz,integer) from public,anon,authenticated;
grant execute on function local_intel.start_recommendation_shadow_run_v2(uuid,text,text,jsonb,text[],text[],text,timestamptz,timestamptz,integer,integer) to service_role;
grant execute on function local_intel.add_recommendation_shadow_time_window_candidates_v1(uuid,text,timestamptz,timestamptz,integer) to service_role;

grant execute on function atlas.submit_composition_request_envelope_v1(uuid,text,text,text,text,jsonb) to service_role;
grant execute on function local_intel.get_composition_signals_v2(uuid,jsonb) to service_role;
grant execute on function atlas.start_shadow_composition_derivation_v1(uuid,text,text,jsonb,jsonb,text,integer) to service_role;
grant execute on function atlas.submit_shadow_composition_proposal_v2(uuid,text,text,text,jsonb) to service_role;

revoke execute on function atlas.submit_composition_request_envelope_v1(uuid,text,text,text,text,jsonb) from anon,authenticated;
revoke execute on function local_intel.get_composition_signals_v2(uuid,jsonb) from anon,authenticated;
revoke execute on function atlas.start_shadow_composition_derivation_v1(uuid,text,text,jsonb,jsonb,text,integer) from anon,authenticated;
revoke execute on function atlas.submit_shadow_composition_proposal_v2(uuid,text,text,text,jsonb) from anon,authenticated;