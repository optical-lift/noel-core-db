create or replace function local_intel.get_composition_signals_v2(
  p_shadow_run_id uuid,
  p_request_envelope jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v jsonb;
  v_carriers jsonb;
begin
  v := local_intel.get_composition_signals_v1(p_shadow_run_id,p_request_envelope);
  select coalesce(jsonb_agg(jsonb_build_object(
    'carrier_ref',x->>'carrier_ref',
    'evidence_state',case
      when coalesce(x->>'affordance_evidence_state','missing')='resolved' then 'attribute_resolved_operation_unmapped'
      else coalesce(x->>'affordance_evidence_state','missing')
    end,
    'operation_hints','[]'::jsonb,
    'observed_attribute_keys',coalesce((select jsonb_agg(a->>'attribute_key') from jsonb_array_elements(coalesce(x->'current_attributes','[]'::jsonb)) a where nullif(a->>'attribute_key','') is not null),'[]'::jsonb),
    'expected_cost',null,
    'object_type',x->>'object_type',
    'factual_snapshot',x->'factual_snapshot',
    'current_attributes',coalesce(x->'current_attributes','[]'::jsonb),
    'current_availability',x->'current_availability',
    'evidence_refs',jsonb_build_array(jsonb_build_object('source','local_intel','stable_key',x->>'stable_key'))
  )),'[]'::jsonb) into v_carriers
  from jsonb_array_elements(coalesce(v->'candidate_affordance_carriers','[]'::jsonb)) x;
  return v || jsonb_build_object(
    'available_carriers',v_carriers,
    'signal_adapter_version','local_composition_signals_v2',
    'affordance_operation_contract_version',null,
    'affordance_operation_mapping_ready',false,
    'epistemic_contract',coalesce(v->'epistemic_contract','{}'::jsonb)||jsonb_build_object(
      'observed_attribute_is_not_operation',true,
      'creative_local_route_blocked_until_affordance_operation_mapping',true
    )
  );
end;
$$;
revoke all on function local_intel.get_composition_signals_v2(uuid,jsonb) from public,anon,authenticated;
grant execute on function local_intel.get_composition_signals_v2(uuid,jsonb) to service_role,postgres;