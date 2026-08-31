-- Atlas Life Signal -> Shared Composition adapter v1
--
-- This migration deliberately does not touch Rhythm, Goal, or State Consequence
-- persistence. Their generic production foundations are not yet source-custodied
-- on the current main ledger. It adds a pure JSON contract membrane into the
-- already source-custodied shared Composition signal contract.

begin;

create or replace function atlas.validate_life_signal_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_violations jsonb := '[]'::jsonb;
  v_relation jsonb;
  v_requirement jsonb;
  v_kind text;
  v_index integer := 0;
begin
  if p_signal is null or jsonb_typeof(p_signal) <> 'object' then
    return jsonb_build_object(
      'validation_state','rejected',
      'violations',jsonb_build_array(jsonb_build_object('key','signal_must_be_object')),
      'normalized',null
    );
  end if;

  if p_signal->>'contractVersion' <> 'atlas_life_signal_v1' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','unsupported_contract_version',
      'value',p_signal->>'contractVersion'
    ));
  end if;

  if jsonb_typeof(p_signal->'scope') <> 'object'
     or nullif(btrim(p_signal->'scope'->>'kind'),'') is null
     or nullif(btrim(p_signal->'scope'->>'id'),'') is null then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','invalid_scope',
      'message','scope.kind and scope.id are required'
    ));
  end if;

  if jsonb_typeof(p_signal->'subject') <> 'object'
     or nullif(btrim(p_signal->'subject'->>'domain'),'') is null
     or nullif(btrim(p_signal->'subject'->>'kind'),'') is null
     or nullif(btrim(p_signal->'subject'->>'id'),'') is null then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','invalid_subject',
      'message','subject.domain, subject.kind, and subject.id are required'
    ));
  end if;

  v_kind := p_signal->>'signalKind';
  if v_kind is null or v_kind <> all(array[
    'observation','condition','rhythm','goal','consequence','composition','clock_claim'
  ]) then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','invalid_signal_kind',
      'value',v_kind
    ));
  end if;

  if jsonb_typeof(coalesce(p_signal->'state','{}'::jsonb)) <> 'object' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','state_must_be_object'));
  end if;

  if jsonb_typeof(coalesce(p_signal->'timing','{}'::jsonb)) <> 'object' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','timing_must_be_object'));
  end if;

  if jsonb_typeof(coalesce(p_signal->'requirements','[]'::jsonb)) <> 'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','requirements_must_be_array'));
  else
    for v_requirement in
      select value from jsonb_array_elements(coalesce(p_signal->'requirements','[]'::jsonb))
    loop
      v_index := v_index + 1;
      if jsonb_typeof(v_requirement) <> 'object'
         or nullif(btrim(coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind','')),'') is null then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object(
          'key','invalid_requirement',
          'index',v_index,
          'message','each requirement must be an object with requirementKind'
        ));
      end if;
    end loop;
  end if;

  if jsonb_typeof(coalesce(p_signal->'constraints','[]'::jsonb)) <> 'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','constraints_must_be_array'));
  end if;

  if jsonb_typeof(coalesce(p_signal->'ambiguities','[]'::jsonb)) <> 'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','ambiguities_must_be_array'));
  end if;

  if jsonb_typeof(coalesce(p_signal->'relations','[]'::jsonb)) <> 'array' then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object('key','relations_must_be_array'));
  else
    for v_relation in
      select value from jsonb_array_elements(coalesce(p_signal->'relations','[]'::jsonb))
    loop
      if jsonb_typeof(v_relation) <> 'object'
         or nullif(btrim(coalesce(v_relation->>'relationKind',v_relation->>'relation_kind','')),'') is null then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object(
          'key','invalid_relation',
          'message','each relation must be an object with relationKind'
        ));
      elsif v_relation ? 'causal' and jsonb_typeof(v_relation->'causal') <> 'boolean' then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object(
          'key','invalid_relation_causal_flag',
          'relation',v_relation,
          'message','relation.causal must be boolean when supplied'
        ));
      elsif coalesce((v_relation->>'causal')::boolean,false) then
        v_violations := v_violations || jsonb_build_array(jsonb_build_object(
          'key','causal_promotion_not_allowed_in_generic_relation',
          'relation',v_relation,
          'message','the generic relation graph may carry relevance/context but cannot establish causation'
        ));
      end if;
    end loop;
  end if;

  if jsonb_typeof(p_signal->'source') <> 'object'
     or nullif(btrim(p_signal->'source'->>'domain'),'') is null
     or nullif(btrim(p_signal->'source'->>'kind'),'') is null
     or nullif(btrim(p_signal->'source'->>'id'),'') is null then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','invalid_source',
      'message','source.domain, source.kind, and source.id are required'
    ));
  end if;

  if jsonb_typeof(p_signal->'epistemic') <> 'object'
     or nullif(btrim(p_signal->'epistemic'->>'factClass'),'') is null then
    v_violations := v_violations || jsonb_build_array(jsonb_build_object(
      'key','invalid_epistemic_basis',
      'message','epistemic.factClass is required'
    ));
  end if;

  return jsonb_build_object(
    'validation_state',case when jsonb_array_length(v_violations)=0 then 'passed' else 'rejected' end,
    'violations',v_violations,
    'normalized',case when jsonb_array_length(v_violations)=0 then p_signal else null end
  );
end;
$$;

comment on function atlas.validate_life_signal_v1(jsonb) is
  'Validates the source-custodied Atlas life-signal envelope. It preserves unknowns and rejects causal promotion through generic relation links.';

create or replace function atlas.life_signal_to_composition_signals_v1(p_signal jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_validation jsonb;
  v_requirement jsonb;
  v_requirements jsonb;
  v_active_claims jsonb := '[]'::jsonb;
  v_requirement_kind text;
  v_requirement_key text;
  v_operation text;
  v_carrier text;
  v_index integer := 0;
  v_explicit_end jsonb := null;
  v_subject_ref text;
begin
  v_validation := atlas.validate_life_signal_v1(p_signal);
  if v_validation->>'validation_state' <> 'passed' then
    raise exception 'invalid atlas_life_signal_v1: %', v_validation->'violations' using errcode='22023';
  end if;

  v_requirements := coalesce(p_signal->'requirements','[]'::jsonb);
  v_subject_ref := concat_ws(':',
    p_signal->'subject'->>'domain',
    p_signal->'subject'->>'kind',
    p_signal->'subject'->>'id'
  );

  for v_requirement in
    select value from jsonb_array_elements(v_requirements)
  loop
    v_index := v_index + 1;
    v_requirement_kind := coalesce(v_requirement->>'requirementKind',v_requirement->>'requirement_kind');
    v_operation := nullif(btrim(coalesce(v_requirement->>'operationKey',v_requirement->>'operation_key','')),'');
    v_carrier := nullif(btrim(coalesce(v_requirement->>'carrierRef',v_requirement->>'carrier_ref','')),'');
    v_requirement_key := nullif(btrim(coalesce(v_requirement->>'requirementKey',v_requirement->>'requirement_key','')),'');

    if v_requirement_key is null then
      v_requirement_key := v_subject_ref || ':requirement:' || v_index::text;
    end if;

    v_active_claims := v_active_claims || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
      'claim_key',v_requirement_key,
      'claim_type',v_requirement_kind,
      'claim_strength',coalesce(nullif(v_requirement->>'claimStrength',''),'required'),
      'carrier_ref',v_carrier,
      'operation_hint',v_operation,
      'before_state',coalesce(p_signal->'state','{}'::jsonb),
      'expected_after_state',coalesce(v_requirement->'expectedAfterState',v_requirement->'expected_after_state','{}'::jsonb),
      'entry_condition',coalesce(nullif(v_requirement->>'entryCondition',''),'requirement is established by the supplied life signal'),
      'exit_condition',coalesce(nullif(v_requirement->>'exitCondition',''),'requirement satisfaction must be established by domain evidence'),
      'blocker',nullif(v_requirement->>'blocker',''),
      'timing_hint',case
        when coalesce(p_signal->'timing','{}'::jsonb) = '{}'::jsonb then null
        else p_signal->'timing'::text
      end,
      'evidence',jsonb_build_object(
        'source',p_signal->'source',
        'epistemic',p_signal->'epistemic',
        'requirement',v_requirement,
        'life_signal_contract','atlas_life_signal_v1'
      )
    )));
  end loop;

  -- A desired end enters shared Composition only when the domain adapter has
  -- explicitly marked it as such. Being a GoalSignal alone is not evidence that
  -- every field in state is an authorized end.
  if p_signal->'state' ? 'explicitUserEnd' then
    v_explicit_end := p_signal->'state'->'explicitUserEnd';
  end if;

  return jsonb_build_object(
    'signal_contract_version','composition_signals_v1',
    'source_domain','atlas_life_signal',
    'subject',p_signal->'subject',
    'present_state',coalesce(p_signal->'state','{}'::jsonb),
    'active_claims',v_active_claims,
    'explicit_user_end',v_explicit_end,
    -- Composition delegation remains owned by the existing request-envelope
    -- epistemic firewall. A life signal cannot seize that authority.
    'composition_delegated',false,
    'constraints',coalesce(p_signal->'constraints','[]'::jsonb),
    'candidate_evidence',jsonb_build_object(
      'candidate_count',0,
      'resolved_affordance_count',0,
      'missing_affordance_count',0
    ),
    'ambiguities',coalesce(p_signal->'ambiguities','[]'::jsonb),
    'relations',coalesce(p_signal->'relations','[]'::jsonb),
    'sequence_authority',jsonb_build_object(
      'prior_placements_may_be_reused_as_truth',false,
      'life_signal_may_create_sequence_authority',false
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.life_signal_to_composition_signals_v1',
      'source_scope',p_signal->'scope',
      'source',p_signal->'source',
      'epistemic',p_signal->'epistemic',
      'life_signal_contract','atlas_life_signal_v1',
      'natural_language_semantics_not_inferred_by_adapter',true
    )
  );
end;
$$;

comment on function atlas.life_signal_to_composition_signals_v1(jsonb) is
  'Pure compatibility adapter from Atlas life signals into source-custodied composition_signals_v1. Requirements become active claims without inventing carriers; observations with no requirements remain non-operative. Delegated composition authority is never created here.';

revoke all on function atlas.validate_life_signal_v1(jsonb) from public, anon, authenticated;
revoke all on function atlas.life_signal_to_composition_signals_v1(jsonb) from public, anon, authenticated;
grant execute on function atlas.validate_life_signal_v1(jsonb) to postgres;
grant execute on function atlas.life_signal_to_composition_signals_v1(jsonb) to postgres;

commit;
