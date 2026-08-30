create or replace function atlas.validate_shadow_composition_proposal_v1(
  p_derivation_id uuid,
  p_proposal jsonb
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog
as $$
declare
  v_der record;
  v_steps jsonb;
  v_step jsonb;
  v_carriers jsonb;
  v_carrier jsonb;
  v_required jsonb;
  v_mode text;
  v_violations jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_step_count integer;
  v_carrier_ref text;
  v_operation text;
  v_authority text;
  v_evidence_state text;
  v_expected_minutes integer;
  v_total_minutes integer := 0;
  v_capacity_max integer;
  v_budget numeric;
  v_total_cost numeric := 0;
  v_cost numeric;
  v_budget_steps integer := 0;
  v_missing_cost_steps integer := 0;
  v_protected jsonb;
  v_claim_key text;
  v_ambiguity jsonb;
  v_ambiguity_key text;
begin
  select * into v_der from atlas.composition_derivation_runs where id=p_derivation_id;
  if not found then raise exception 'derivation not found'; end if;
  if p_proposal is null or p_proposal->>'proposal_version' <> 'composition_proposal_v1' then raise exception 'composition_proposal_v1 required'; end if;
  v_steps:=coalesce(p_proposal->'steps','[]'::jsonb);
  if jsonb_typeof(v_steps)<>'array' then raise exception 'proposal steps must be array'; end if;
  v_step_count:=jsonb_array_length(v_steps);
  v_carriers:=coalesce(v_der.domain_signals->'available_carriers','[]'::jsonb);
  v_required:=coalesce(v_der.derived_packet->'required_operations','[]'::jsonb);
  v_protected:=coalesce(v_der.derived_packet->'protected_claims','[]'::jsonb);
  v_mode:=v_der.derived_packet->'intended_fruit'->>'mode';

  if v_mode='bounded_discretion' and coalesce((p_proposal->>'not_unique_moral_route')::boolean,false) is not true then
    v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','bounded_discretion_moral_uniqueness','message','bounded-discretion proposal must declare not_unique_moral_route=true'));
  end if;
  if v_step_count=0 then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','empty_proposal','message','concrete proposal contains no steps')); end if;

  for v_ambiguity in select value from jsonb_array_elements(coalesce(v_der.domain_signals->'ambiguities','[]'::jsonb)) loop
    if coalesce((v_ambiguity->>'blocking')::boolean,true) then
      v_ambiguity_key:=v_ambiguity->>'key';
      if not exists (
        select 1 from jsonb_array_elements(coalesce(p_proposal->'resolved_ambiguities','[]'::jsonb)) r
        where r->>'key'=v_ambiguity_key and jsonb_array_length(coalesce(r->'evidence_refs','[]'::jsonb))>0
      ) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object(
          'key','blocking_ambiguity_unresolved','ambiguity_key',v_ambiguity_key,
          'message','proposal may not silently choose through a blocking ambiguity without explicit evidence-backed resolution'
        ));
      end if;
    end if;
  end loop;

  for v_step in select value from jsonb_array_elements(v_steps) loop
    v_carrier_ref:=nullif(v_step->>'carrier_ref',''); v_operation:=nullif(v_step->>'operation_key','');
    v_authority:=coalesce(nullif(v_step->>'operation_authority',''),'domain_affordance');
    if v_carrier_ref is null or v_operation is null then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','step_missing_identity','step',v_step)); continue; end if;
    select x into v_carrier from jsonb_array_elements(v_carriers) x where x->>'carrier_ref'=v_carrier_ref limit 1;
    if v_carrier is null then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','carrier_not_in_signal_packet','carrier_ref',v_carrier_ref)); continue; end if;
    v_evidence_state:=coalesce(v_carrier->>'evidence_state','missing');
    if v_evidence_state<>'resolved' then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','carrier_affordance_unresolved','carrier_ref',v_carrier_ref,'evidence_state',v_evidence_state,'message','creative proposal may not convert missing carrier affordance evidence into a factual route')); end if;
    if v_authority='canon_required' and not exists(select 1 from jsonb_array_elements_text(v_required) x where x=v_operation) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','invented_canon_required_operation','operation_key',v_operation,'carrier_ref',v_carrier_ref));
    elsif v_authority='domain_affordance' and jsonb_array_length(coalesce(v_carrier->'operation_hints','[]'::jsonb))>0
      and not exists(select 1 from jsonb_array_elements_text(v_carrier->'operation_hints') x where x=v_operation) then
      v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','operation_not_supported_by_carrier_facts','operation_key',v_operation,'carrier_ref',v_carrier_ref));
    end if;
    v_expected_minutes:=nullif(v_carrier->>'expected_active_minutes','')::integer;
    if v_expected_minutes is not null then v_total_minutes:=v_total_minutes+v_expected_minutes; end if;
    if v_step ? 'expected_cost' then v_budget_steps:=v_budget_steps+1; v_cost:=nullif(v_step->>'expected_cost','')::numeric; if v_cost is null then v_missing_cost_steps:=v_missing_cost_steps+1; else v_total_cost:=v_total_cost+v_cost; end if; end if;
  end loop;

  select nullif(c->>'value','')::numeric into v_budget from jsonb_array_elements(coalesce(v_der.derived_packet->'constraints','[]'::jsonb)) c where c->>'key'='budget_max' limit 1;
  if v_budget is not null then
    if v_missing_cost_steps>0 or v_budget_steps<v_step_count then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','budget_evidence_incomplete','budget_max',v_budget,'step_count',v_step_count,'costed_steps',v_budget_steps));
    elsif v_total_cost>v_budget then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','budget_exceeded','budget_max',v_budget,'proposal_cost',v_total_cost)); end if;
  end if;
  v_capacity_max:=nullif(v_der.domain_signals->'capacity_summary'->>'maximum_planned_minutes','')::integer;
  if v_capacity_max is not null and v_total_minutes>v_capacity_max then v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','capacity_exceeded','maximum_planned_minutes',v_capacity_max,'proposal_minutes',v_total_minutes)); end if;

  if jsonb_array_length(v_protected)>0 then
    for v_claim_key in select value from jsonb_array_elements_text(v_protected) loop
      if not exists(select 1 from jsonb_array_elements(v_steps) s where s->>'carrier_ref'=v_claim_key)
        and not exists(select 1 from jsonb_array_elements(coalesce(p_proposal->'deferred_claims','[]'::jsonb)) d where d->>'claim_key'=v_claim_key) then
        v_violations:=v_violations||jsonb_build_array(jsonb_build_object('key','protected_claim_dropped','claim_key',v_claim_key));
      end if;
    end loop;
  end if;
  if jsonb_array_length(v_violations)=0 and v_step_count>0 then
    return jsonb_build_object('validation_state','passed','violations',v_violations,'warnings',v_warnings,'metrics',jsonb_build_object('step_count',v_step_count,'proposal_minutes',v_total_minutes,'proposal_cost',v_total_cost));
  end if;
  return jsonb_build_object('validation_state','rejected','violations',v_violations,'warnings',v_warnings,'metrics',jsonb_build_object('step_count',v_step_count,'proposal_minutes',v_total_minutes,'proposal_cost',v_total_cost));
end;
$$;
revoke all on function atlas.validate_shadow_composition_proposal_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function atlas.validate_shadow_composition_proposal_v1(uuid,jsonb) to postgres;