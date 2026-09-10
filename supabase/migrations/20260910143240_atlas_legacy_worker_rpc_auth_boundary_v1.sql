begin;

-- Gate 2 closure: these directly-authenticated Worker Day RPCs are legacy/internal
-- surfaces. Current employee execution goes through the employee-seat boundary.
-- Keep service-role/internal composition available, but remove browser-authenticated
-- execution so an active farm membership alone can never bypass seat/credential state.
revoke execute on function atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) from authenticated;
revoke execute on function atlas.worker_day_choreography_api_v1(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_day_choreography_bundle_api_v2(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_day_execution_lease_action_v2(uuid,uuid,date,uuid,text,text,text) from authenticated;
revoke execute on function atlas.worker_day_placed_task_cards_v1(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_day_state_transition_cards_v2(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_dismiss_day_cue_api_v1(uuid) from authenticated;
revoke execute on function atlas.worker_record_farm_round_member_done_v1(uuid,text,text,jsonb) from authenticated;
revoke execute on function atlas.worker_record_state_transition_result_v1(uuid,uuid,uuid,date,text,integer,text,numeric,text,text,text,jsonb) from authenticated;
revoke execute on function atlas.worker_resolve_day_cue_api_v1(uuid,jsonb) from authenticated;
revoke execute on function atlas.worker_self_day_bundle_api_v1(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_self_next_up_api_v1(uuid,uuid,date) from authenticated;
revoke execute on function atlas.worker_task_execution_readiness_api_v1(uuid) from authenticated;
revoke execute on function atlas.worker_task_execution_structure_api_v1(uuid) from authenticated;

-- These were already internal-only, but assert the same boundary explicitly.
revoke execute on function atlas.worker_self_day_plan_api_v1(uuid,uuid,date) from authenticated;
revoke execute on function atlas.prepare_company_work_task_result_v1(uuid,uuid,text,text,jsonb) from authenticated;

-- Anonymous/public execution is never allowed on these legacy/internal worker surfaces.
revoke execute on function atlas.record_worker_activity_log_v1(uuid,date,text,text,uuid,timestamptz,timestamptz,text) from public,anon;
revoke execute on function atlas.worker_day_choreography_api_v1(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_day_choreography_bundle_api_v2(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_day_execution_lease_action_v2(uuid,uuid,date,uuid,text,text,text) from public,anon;
revoke execute on function atlas.worker_day_placed_task_cards_v1(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_day_state_transition_cards_v2(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_dismiss_day_cue_api_v1(uuid) from public,anon;
revoke execute on function atlas.worker_record_farm_round_member_done_v1(uuid,text,text,jsonb) from public,anon;
revoke execute on function atlas.worker_record_state_transition_result_v1(uuid,uuid,uuid,date,text,integer,text,numeric,text,text,text,jsonb) from public,anon;
revoke execute on function atlas.worker_resolve_day_cue_api_v1(uuid,jsonb) from public,anon;
revoke execute on function atlas.worker_self_day_bundle_api_v1(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_self_next_up_api_v1(uuid,uuid,date) from public,anon;
revoke execute on function atlas.worker_task_execution_readiness_api_v1(uuid) from public,anon;
revoke execute on function atlas.worker_task_execution_structure_api_v1(uuid) from public,anon;
revoke execute on function atlas.worker_self_day_plan_api_v1(uuid,uuid,date) from public,anon;
revoke execute on function atlas.prepare_company_work_task_result_v1(uuid,uuid,text,text,jsonb) from public,anon;

commit;