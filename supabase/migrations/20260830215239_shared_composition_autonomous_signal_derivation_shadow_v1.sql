create table if not exists atlas.composition_derivation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  mode text not null default 'shadow' check (mode='shadow'),
  source_domain text not null,
  source_ref text,
  canon_pack_key text not null,
  canon_pack_version integer not null,
  request_envelope jsonb not null default '{}'::jsonb,
  domain_signals jsonb not null default '{}'::jsonb,
  derived_packet jsonb not null default '{}'::jsonb,
  derivation_state text not null check (derivation_state in ('derived','unresolved','failed')),
  composition_run_id uuid references atlas.composition_runs(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table atlas.composition_derivation_runs enable row level security;
revoke all on atlas.composition_derivation_runs from public, anon, authenticated;

create or replace function atlas.get_worker_day_composition_signals_v1(
  p_membership_id uuid,
  p_service_date date
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_facts jsonb;
  v_item jsonb;
  v_active jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_ambiguities jsonb := '[]'::jsonb;
  v_due date;
  v_commitment text;
  v_lane text;
  v_status text;
  v_visibility text;
  v_operation text;
  v_claim_strength text;
  v_actual_only integer := 0;
  v_snapshot_only integer := 0;
  v_blocked integer := 0;
begin
  v_facts := atlas.get_worker_day_composition_facts_v1(p_membership_id,p_service_date);

  if v_facts is null then
    raise exception 'worker-day facts unavailable';
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(v_facts->'candidate_affordance_carriers','[]'::jsonb)) loop
    v_due := nullif(v_item->>'due_date','')::date;
    v_commitment := coalesce(v_item->>'commitment_kind','');
    v_lane := coalesce(v_item->>'work_lane','');
    v_status := coalesce(v_item->>'current_status','');
    v_visibility := coalesce(v_item->>'visibility_scope','');
    v_operation := coalesce(nullif(v_item->>'declared_operation_class',''), nullif(v_item->>'action_key',''), nullif(v_item->>'task_type',''));

    if coalesce((v_item->'provenance'->>'appeared_in_actual_placement')::boolean,false)
       and not coalesce((v_item->'provenance'->>'appeared_in_latest_day_plan_snapshot')::boolean,false) then
      v_actual_only := v_actual_only + 1;
    elsif coalesce((v_item->'provenance'->>'appeared_in_latest_day_plan_snapshot')::boolean,false)
       and not coalesce((v_item->'provenance'->>'appeared_in_actual_placement')::boolean,false) then
      v_snapshot_only := v_snapshot_only + 1;
    end if;

    if v_status <> 'archived'
       and v_visibility <> 'system_internal'
       and (v_due is null or v_due <= p_service_date)
       and (
         v_commitment in ('hard_date','dependency','persistent')
         or v_lane in ('required','rhythm','process_continuation')
         or coalesce((v_item->'source_metadata'->>'calendar_day_obligation')::boolean,false)
         or coalesce(v_item->>'release_reason','') in ('committed_window','rhythm_serving')
       ) then

      v_claim_strength := case
        when v_commitment='hard_date' then 'hard'
        when v_commitment in ('dependency','persistent') or v_lane='process_continuation' then 'protected'
        else 'required'
      end;

      if nullif(v_item->>'blocker_text','') is not null then
        v_blocked := v_blocked + 1;
      end if;

      v_active := v_active || jsonb_build_array(jsonb_build_object(
        'claim_key', v_item->>'carrier_ref',
        'claim_type', coalesce(nullif(v_commitment,''),nullif(v_lane,''),'operational_claim'),
        'claim_strength', v_claim_strength,
        'carrier_ref', v_item->>'carrier_ref',
        'operation_hint', v_operation,
        'before_state', jsonb_build_object('service_date',p_service_date,'task_status_now',v_status,'due_date',v_due),
        'expected_after_state', jsonb_build_object('task_contract_satisfied',true),
        'entry_condition', 'claim is active for the service date and assigned carrier is eligible',
        'exit_condition', coalesce(v_item->'source_metadata'->>'execution_done_when',v_item->'source_metadata'->>'execution_checklist_completion_label','task completion contract satisfied'),
        'blocker', nullif(v_item->>'blocker_text',''),
        'timing_hint', coalesce(v_item->'source_metadata'->>'window_key',v_item->'source_metadata'->>'time_of_day'),
        'evidence', jsonb_build_object(
          'due_date',v_due,
          'commitment_kind',v_commitment,
          'work_lane',v_lane,
          'release_reason',v_item->>'release_reason',
          'provenance',v_item->'provenance',
          'operation_hint_source',v_item->>'operation_class_source'
        )
      ));
    end if;
  end loop;

  if v_actual_only > 0 or v_snapshot_only > 0 then
    v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object(
      'key','prior_plan_and_actual_placement_disagree',
      'actual_only_count',v_actual_only,
      'latest_snapshot_only_count',v_snapshot_only,
      'effect','prior ordering may not be reused as autonomous composition truth'
    ));
  end if;

  if v_blocked > 0 then
    v_ambiguities := v_ambiguities || jsonb_build_array(jsonb_build_object(
      'key','active_claims_have_blockers',
      'count',v_blocked
    ));
  end if;

  if v_facts->'available_time_policy' is not null then
    v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
      'key','worker_day_window',
      'local_start',v_facts->'available_time_policy'->>'local_start',
      'local_end',v_facts->'available_time_policy'->>'local_end',
      'source','worker_day_shape_policy'
    ));
  end if;

  return jsonb_build_object(
    'signal_contract_version','composition_signals_v1',
    'source_domain','atlas_worker_day',
    'subject',v_facts->'subject',
    'present_state',jsonb_build_object('service_date',p_service_date,'day_state',v_facts->'day_state'),
    'active_claims',v_active,
    'explicit_user_end',null,
    'composition_delegated',false,
    'constraints',v_constraints,
    'candidate_evidence',jsonb_build_object(
      'candidate_count',jsonb_array_length(coalesce(v_facts->'candidate_affordance_carriers','[]'::jsonb)),
      'resolved_affordance_count',jsonb_array_length(v_active),
      'missing_affordance_count',0
    ),
    'ambiguities',v_ambiguities,
    'sequence_authority',jsonb_build_object(
      'prior_placements_may_be_reused_as_truth',false,
      'fixed_reservations',coalesce(v_facts->'fixed_reservations','[]'::jsonb)
    ),
    'provenance',jsonb_build_object(
      'adapter','atlas.get_worker_day_composition_facts_v1',
      'signal_adapter','atlas.get_worker_day_composition_signals_v1',
      'epistemic_contract',v_facts->'epistemic_contract'
    )
  );
end;
$$;

create or replace function local_intel.get_composition_signals_v1(
  p_shadow_run_id uuid,
  p_request_envelope jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_facts jsonb;
  v_explicit jsonb;
  v_constraints jsonb;
  v_delegated boolean;
  v_stats jsonb;
begin
  if p_request_envelope is null
     or not (p_request_envelope ?& array['literal_request','explicit_facts','request_mode']) then
    raise exception 'request envelope requires literal_request, explicit_facts, request_mode';
  end if;

  v_facts := local_intel.get_composition_affordance_facts_v1(p_shadow_run_id);
  if v_facts is null then
    raise exception 'local composition facts unavailable';
  end if;

  v_explicit := coalesce(p_request_envelope->'explicit_facts','{}'::jsonb);
  v_constraints := coalesce(v_explicit->'constraints','[]'::jsonb);
  if jsonb_typeof(v_constraints) <> 'array' then
    raise exception 'explicit_facts.constraints must be array when supplied';
  end if;

  v_delegated := (p_request_envelope->>'request_mode'='open_composition')
    and coalesce((p_request_envelope->>'delegated_composition')::boolean,false);
  v_stats := coalesce(v_facts->'candidate_stats','{}'::jsonb);

  return jsonb_build_object(
    'signal_contract_version','composition_signals_v1',
    'source_domain','elm_local',
    'present_state',v_explicit,
    'active_claims','[]'::jsonb,
    'explicit_user_end',v_explicit->'user_stated_end',
    'composition_delegated',v_delegated,
    'constraints',v_constraints,
    'candidate_evidence',jsonb_build_object(
      'candidate_count',coalesce((v_stats->>'candidate_count')::integer,0),
      'resolved_affordance_count',coalesce((v_stats->>'candidates_with_resolved_attributes')::integer,0),
      'missing_affordance_count',coalesce((v_stats->>'missing_affordance_state_count')::integer,0)
    ),
    'ambiguities',case when coalesce((v_stats->>'missing_affordance_state_count')::integer,0)>0
      then jsonb_build_array(jsonb_build_object(
        'key','human_use_affordance_evidence_missing',
        'count',coalesce((v_stats->>'missing_affordance_state_count')::integer,0),
        'effect','do not invent shade, bathroom, seating, heat-fit, supervision, price, or availability functions'
      ))
      else '[]'::jsonb end,
    'candidate_affordance_carriers',v_facts->'candidate_affordance_carriers',
    'quarantined_prior_interpretation',jsonb_build_object(
      'query_state',v_facts->'query_state',
      'authority','not_input_authority_for_canon_derivation'
    ),
    'provenance',jsonb_build_object(
      'literal_request',p_request_envelope->>'literal_request',
      'request_mode',p_request_envelope->>'request_mode',
      'request_parser_version',p_request_envelope->>'parser_version',
      'source_shadow_run_id',p_shadow_run_id,
      'adapter','local_intel.get_composition_affordance_facts_v1',
      'signal_adapter','local_intel.get_composition_signals_v1',
      'epistemic_contract',v_facts->'epistemic_contract'
    )
  );
end;
$$;

create or replace function atlas.derive_composition_packet_from_signals_v1(
  p_request_envelope jsonb,
  p_domain_signals jsonb,
  p_pack_key text default 'real_life_composition_v1',
  p_pack_version integer default 1
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_pack_id uuid;
  v_member_count integer;
  v_valid_count integer;
  v_claims jsonb;
  v_claim jsonb;
  v_claim_count integer;
  v_ambiguities jsonb;
  v_ambiguity_count integer;
  v_delegated boolean;
  v_explicit_end jsonb;
  v_missing integer;
  v_resolved integer;
  v_ops jsonb := '[]'::jsonb;
  v_protected jsonb := '[]'::jsonb;
  v_steps jsonb := '[]'::jsonb;
  v_branches jsonb := '[]'::jsonb;
  v_constraints jsonb;
  v_fruit jsonb;
  v_terminal jsonb;
  v_op text;
  v_claim_key text;
  v_blocker text;
  v_single_claim jsonb;
  v_reason text;
begin
  if p_domain_signals is null or p_domain_signals->>'signal_contract_version' <> 'composition_signals_v1' then
    raise exception 'composition_signals_v1 required';
  end if;

  select id into v_pack_id
  from draft.canon_runtime_packs
  where pack_key=p_pack_key and version=p_pack_version and status='shadow'
    and contract_version='recursive_condition_bound_composition_v2';
  if v_pack_id is null then
    raise exception 'shadow canon runtime pack not found';
  end if;

  select count(*), count(*) filter (
    where a.adjudication_status=m.required_adjudication_status
      and a.canon_support_state=m.required_canon_support_state
      and m.adjudication_sha256=encode(extensions.digest(jsonb_build_object(
        'adjudication_key',a.adjudication_key,
        'canonical_question',a.canonical_question,
        'operation',a.operation,
        'intended_fruit',a.intended_fruit,
        'does_not_establish',a.does_not_establish,
        'confidence',a.confidence,
        'reviewed_at',a.reviewed_at
      )::text,'sha256'),'hex')
  ) into v_member_count,v_valid_count
  from draft.canon_runtime_pack_members m
  join draft.reality_song_adjudications a on a.song_adjudication_id=m.song_adjudication_id
  where m.pack_id=v_pack_id;
  if v_member_count<4 or v_member_count<>v_valid_count then
    raise exception 'canon runtime pack custody failed';
  end if;

  v_claims := coalesce(p_domain_signals->'active_claims','[]'::jsonb);
  v_claim_count := jsonb_array_length(v_claims);
  v_ambiguities := coalesce(p_domain_signals->'ambiguities','[]'::jsonb);
  v_ambiguity_count := jsonb_array_length(v_ambiguities);
  v_delegated := coalesce((p_domain_signals->>'composition_delegated')::boolean,false);
  v_explicit_end := p_domain_signals->'explicit_user_end';
  v_missing := coalesce((p_domain_signals->'candidate_evidence'->>'missing_affordance_count')::integer,0);
  v_resolved := coalesce((p_domain_signals->'candidate_evidence'->>'resolved_affordance_count')::integer,0);
  v_constraints := coalesce(p_domain_signals->'constraints','[]'::jsonb);

  if v_claim_count>0 or (v_explicit_end is not null and v_explicit_end <> 'null'::jsonb) then
    for v_claim in select value from jsonb_array_elements(v_claims) loop
      v_op := nullif(v_claim->>'operation_hint','');
      v_claim_key := coalesce(nullif(v_claim->>'claim_key',''),nullif(v_claim->>'carrier_ref',''),'active_claim');
      if v_op is not null and not exists (select 1 from jsonb_array_elements_text(v_ops) x where x=v_op) then
        v_ops := v_ops || jsonb_build_array(v_op);
      end if;
      if not exists (select 1 from jsonb_array_elements_text(v_protected) x where x=v_claim_key) then
        v_protected := v_protected || jsonb_build_array(v_claim_key);
      end if;
      v_blocker := nullif(v_claim->>'blocker','');
      if v_blocker is not null then
        v_branches := v_branches || jsonb_build_array(jsonb_build_object(
          'condition',v_blocker,
          'action','inspect, wait, hand off, or reroute according to the blocker; do not erase the active claim',
          'preserves_fruit',true,
          'basis','adjudications 18-19'
        ));
      end if;
    end loop;

    if v_explicit_end is not null and v_explicit_end <> 'null'::jsonb then
      v_fruit := jsonb_build_object(
        'mode','controlling',
        'description',case when jsonb_typeof(v_explicit_end)='string' then trim(both '"' from v_explicit_end::text) else v_explicit_end::text end,
        'basis','explicit_user_end_subject_to_stronger_claims'
      );
    else
      v_fruit := jsonb_build_object(
        'mode','controlling',
        'description','Resolve the active condition-bound claims truthfully under their supplied timing, custody, capability, and readiness boundaries.',
        'basis','active_claims'
      );
    end if;

    if v_claim_count=1 and v_ambiguity_count=0 then
      v_single_claim := v_claims->0;
      v_op := nullif(v_single_claim->>'operation_hint','');
      v_blocker := nullif(v_single_claim->>'blocker','');
      if v_op is not null and nullif(v_single_claim->>'carrier_ref','') is not null and v_blocker is null then
        v_steps := jsonb_build_array(jsonb_build_object(
          'sequence',10,
          'operation_key',v_op,
          'carrier_ref',v_single_claim->>'carrier_ref',
          'before_state',coalesce(v_single_claim->'before_state','{}'::jsonb),
          'expected_after_state',coalesce(v_single_claim->'expected_after_state','{}'::jsonb),
          'entry_condition',coalesce(v_single_claim->>'entry_condition','active claim established'),
          'exit_condition',coalesce(v_single_claim->>'exit_condition','claim truthfully resolved'),
          'evidence',jsonb_build_array(coalesce(v_single_claim->'evidence','{}'::jsonb))
        ));
      end if;
    end if;

    v_reason := case
      when v_ambiguity_count>0 then 'Active claims are established, but unresolved evidence prevents autonomous sequence commitment.'
      when v_claim_count>1 and jsonb_array_length(v_steps)=0 then 'Multiple active claims are established without enough independent sequencing authority; prior placements are not reused as the answer.'
      else 'A controlling claim is established; execution/fruit remains unobserved.'
    end;
    v_terminal := jsonb_build_object('status','unresolved','evidence',v_reason);

  elsif v_delegated then
    v_fruit := jsonb_build_object(
      'mode','bounded_discretion',
      'description','No stronger condition in the supplied signals selects one mandatory route. Compose only inside the explicit constraints and evidenced affordance field.',
      'selection_authority','delegated_composition',
      'lawful_field_basis',jsonb_build_array('real_world_constraints','neutral_preference_within_boundaries'),
      'not_unique_moral_route',true
    );

    if v_missing>0 or v_resolved=0 then
      v_ops := jsonb_build_array('inspect_gather_evidence');
      v_branches := jsonb_build_array(jsonb_build_object(
        'condition','enough current human-use affordance evidence becomes available',
        'action','rederive composition from current facts; do not preserve an earlier guessed itinerary',
        'preserves_fruit',true,
        'basis','adjudications 18-19-21'
      ));
      v_terminal := jsonb_build_object(
        'status','unresolved',
        'evidence','Bounded discretion is established, but current carrier facts do not warrant a concrete journey.'
      );
    else
      v_terminal := jsonb_build_object(
        'status','unresolved',
        'evidence','Bounded discretion and candidate affordances are available; creative proposal generation remains a separate step and must be canon-validated before selection.'
      );
    end if;

  else
    v_fruit := jsonb_build_object(
      'mode','controlling',
      'description','Preserve the current lawful state without inventing a purpose or route when neither an active claim nor delegated composition warrant is established.',
      'basis','insufficient_warrant'
    );
    v_ops := jsonb_build_array('no_action');
    v_terminal := jsonb_build_object('status','unresolved','evidence','No sufficient warrant to compose or advance.');
  end if;

  return jsonb_build_object(
    'contract_version','recursive_condition_bound_composition_v2',
    'canon_runtime_pack',jsonb_build_object('pack_key',p_pack_key,'version',p_pack_version),
    'request_class',coalesce(p_request_envelope->>'request_mode',p_domain_signals->>'source_domain','unknown'),
    'present_state',coalesce(p_domain_signals->'present_state','{}'::jsonb),
    'intended_fruit',v_fruit,
    'protected_claims',v_protected,
    'constraints',v_constraints,
    'required_operations',v_ops,
    'journey_steps',v_steps,
    'branches',v_branches,
    'excluded_candidates','[]'::jsonb,
    'terminal',v_terminal,
    'fact_class','autonomous_signal_derivation',
    'fixture_key',coalesce(p_request_envelope->>'request_key',p_domain_signals->>'source_domain','derived'),
    'derivation_metadata',jsonb_build_object(
      'signal_contract_version','composition_signals_v1',
      'active_claim_count',v_claim_count,
      'ambiguity_count',v_ambiguity_count,
      'resolved_affordance_count',v_resolved,
      'missing_affordance_count',v_missing,
      'natural_language_semantics_not_inferred_by_core',true,
      'prior_local_query_state_quarantined',p_domain_signals ? 'quarantined_prior_interpretation'
    )
  );
end;
$$;

create or replace function atlas.start_shadow_composition_derivation_v1(
  p_organization_id uuid,
  p_source_domain text,
  p_source_ref text,
  p_request_envelope jsonb,
  p_domain_signals jsonb,
  p_pack_key text default 'real_life_composition_v1',
  p_pack_version integer default 1
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  v_packet jsonb;
  v_composition_run_id uuid;
  v_derivation_id uuid;
  v_state text;
begin
  v_packet := atlas.derive_composition_packet_from_signals_v1(p_request_envelope,p_domain_signals,p_pack_key,p_pack_version);
  v_composition_run_id := atlas.create_shadow_composition_run_v2(
    p_organization_id,
    p_source_domain,
    p_source_ref,
    v_packet,
    array['adjudication:18','adjudication:19','adjudication:20','adjudication:21']
  );
  v_state := case when v_packet->'terminal'->>'status'='unresolved' then 'unresolved' else 'derived' end;

  insert into atlas.composition_derivation_runs(
    organization_id,source_domain,source_ref,canon_pack_key,canon_pack_version,
    request_envelope,domain_signals,derived_packet,derivation_state,composition_run_id,metadata
  ) values (
    p_organization_id,p_source_domain,p_source_ref,p_pack_key,p_pack_version,
    p_request_envelope,p_domain_signals,v_packet,v_state,v_composition_run_id,
    jsonb_build_object(
      'autonomous_scope','normalized-signals-to-composition-packet',
      'does_not_prove','natural-language parsing or creative journey proposal generation',
      'runtime_pack_content_custody','sha256_verified'
    )
  ) returning id into v_derivation_id;

  return jsonb_build_object(
    'derivation_id',v_derivation_id,
    'composition_run_id',v_composition_run_id,
    'derivation_state',v_state,
    'derived_packet',v_packet
  );
end;
$$;

revoke all on function atlas.get_worker_day_composition_signals_v1(uuid,date) from public, anon, authenticated;
revoke all on function local_intel.get_composition_signals_v1(uuid,jsonb) from public, anon, authenticated;
revoke all on function atlas.derive_composition_packet_from_signals_v1(jsonb,jsonb,text,integer) from public, anon, authenticated;
revoke all on function atlas.start_shadow_composition_derivation_v1(uuid,text,text,jsonb,jsonb,text,integer) from public, anon, authenticated;
grant execute on function atlas.get_worker_day_composition_signals_v1(uuid,date) to postgres;
grant execute on function local_intel.get_composition_signals_v1(uuid,jsonb) to postgres;
grant execute on function atlas.derive_composition_packet_from_signals_v1(jsonb,jsonb,text,integer) to postgres;
grant execute on function atlas.start_shadow_composition_derivation_v1(uuid,text,text,jsonb,jsonb,text,integer) to postgres;