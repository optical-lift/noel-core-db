begin;

create table instrument.state_recovery_trials (
  state_recovery_trial_id bigint generated always as identity primary key,
  trial_key text not null unique,
  instrument_run_id bigint not null references instrument.runs(instrument_run_id),
  corpus_snapshot_key text null references instrument.corpus_snapshots(snapshot_key),
  target_component_id bigint not null references mark.components(component_id),
  target_instance_id bigint not null references mark.instances(instance_id),
  target_sequence_zone_id bigint null references mark.sequence_zones(sequence_zone_id),
  masked_feature_family text not null,
  mask_spec jsonb not null default '{}'::jsonb,
  benchmark_tier smallint not null,
  exclusion_policy jsonb not null default '{}'::jsonb,
  training_query_digest text null,
  training_evidence jsonb not null default '[]'::jsonb,
  predicted_state jsonb null,
  prediction_confidence numeric null,
  prediction_support jsonb not null default '{}'::jsonb,
  prediction_frozen_at timestamptz null,
  observed_state jsonb null,
  revealed_at timestamptz null,
  reveal_result text null,
  is_correct boolean null,
  baseline_payload jsonb not null default '{}'::jsonb,
  score_payload jsonb not null default '{}'::jsonb,
  leakage_audit jsonb not null default '{}'::jsonb,
  trial_status text not null default 'planned',
  invalidation_reason text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(trial_key) <> ''),
  check (btrim(masked_feature_family) <> ''),
  check (benchmark_tier between 0 and 5),
  check (prediction_confidence is null or (prediction_confidence >= 0 and prediction_confidence <= 1)),
  check (training_query_digest is null or training_query_digest ~ '^[0-9a-f]{64}$'),
  check (trial_status in ('planned','masked','predicted_frozen','revealed','scored','invalidated')),
  check (reveal_result is null or reveal_result in ('correct','incorrect','unscorable','invalidated')),
  check (prediction_frozen_at is null or predicted_state is not null),
  check (revealed_at is null or (prediction_frozen_at is not null and observed_state is not null)),
  check (revealed_at is null or revealed_at > prediction_frozen_at),
  check ((reveal_result = 'correct') is not true or is_correct is true),
  check ((reveal_result = 'incorrect') is not true or is_correct is false),
  check ((reveal_result in ('unscorable','invalidated')) is not true or is_correct is null)
);

comment on table instrument.state_recovery_trials is
  'Preregistered masked-state recovery trials. Prediction fields become immutable at prediction_frozen_at; reveal fields are written only afterward. The physical source truth remains owned by mark.*.';

create table instrument.state_recovery_trial_exclusions (
  state_recovery_trial_exclusion_id bigint generated always as identity primary key,
  state_recovery_trial_id bigint not null references instrument.state_recovery_trials(state_recovery_trial_id) on delete cascade,
  excluded_object_type text not null,
  excluded_object_key text not null,
  exclusion_reason text not null,
  evidence_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(state_recovery_trial_id, excluded_object_type, excluded_object_key, exclusion_reason),
  check (excluded_object_type in ('capture','surface','sequence_zone','instance','routine','region')),
  check (exclusion_reason in ('same_physical_occurrence','same_row','overlapping_routine','exact_duplicate_capture','viewer_duplicate_capture','derivative_capture','same_physical_capture','manual_leakage_control','other_declared')),
  check (btrim(excluded_object_key) <> '')
);

comment on table instrument.state_recovery_trial_exclusions is
  'Explicit leakage exclusions for masked recovery trials. Same-row, overlapping-routine, duplicate, and derivative evidence must be represented here rather than silently filtered.';

create table instrument.state_recovery_run_metrics (
  state_recovery_run_metric_id bigint generated always as identity primary key,
  instrument_run_id bigint not null references instrument.runs(instrument_run_id),
  benchmark_tier smallint not null,
  metric_scope text not null,
  sample_count integer not null,
  correct_count integer null,
  accuracy numeric null,
  balanced_accuracy numeric null,
  log_loss numeric null,
  entropy_before_bits numeric null,
  entropy_after_bits numeric null,
  information_gain_bits numeric null,
  baseline_payload jsonb not null default '{}'::jsonb,
  state_distribution jsonb not null default '{}'::jsonb,
  leakage_summary jsonb not null default '{}'::jsonb,
  metric_status text not null default 'provisional',
  created_at timestamptz not null default now(),
  unique(instrument_run_id, benchmark_tier, metric_scope),
  check (benchmark_tier between 0 and 5),
  check (sample_count >= 0),
  check (correct_count is null or (correct_count >= 0 and correct_count <= sample_count)),
  check (accuracy is null or (accuracy >= 0 and accuracy <= 1)),
  check (balanced_accuracy is null or (balanced_accuracy >= 0 and balanced_accuracy <= 1)),
  check (entropy_before_bits is null or entropy_before_bits >= 0),
  check (entropy_after_bits is null or entropy_after_bits >= 0),
  check (metric_status in ('provisional','frozen','invalidated'))
);

comment on table instrument.state_recovery_run_metrics is
  'Aggregate recovery metrics by benchmark tier, including entropy reduction/information gain and explicit leakage summary.';

create index state_recovery_trials_run_idx on instrument.state_recovery_trials(instrument_run_id);
create index state_recovery_trials_target_component_idx on instrument.state_recovery_trials(target_component_id);
create index state_recovery_trials_target_instance_idx on instrument.state_recovery_trials(target_instance_id);
create index state_recovery_trials_zone_idx on instrument.state_recovery_trials(target_sequence_zone_id);
create index state_recovery_trial_exclusions_trial_idx on instrument.state_recovery_trial_exclusions(state_recovery_trial_id);
create index state_recovery_run_metrics_run_idx on instrument.state_recovery_run_metrics(instrument_run_id);

create or replace function instrument.guard_state_recovery_trial_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument, mark
as $$
begin
  if old.prediction_frozen_at is not null then
    if new.predicted_state is distinct from old.predicted_state
       or new.prediction_confidence is distinct from old.prediction_confidence
       or new.prediction_support is distinct from old.prediction_support
       or new.training_query_digest is distinct from old.training_query_digest
       or new.training_evidence is distinct from old.training_evidence
       or new.mask_spec is distinct from old.mask_spec
       or new.exclusion_policy is distinct from old.exclusion_policy
       or new.benchmark_tier is distinct from old.benchmark_tier then
      raise exception 'STATE_RECOVERY_PREDICTION_IMMUTABLE: trial % prediction was frozen at %', old.trial_key, old.prediction_frozen_at;
    end if;
  end if;

  if old.revealed_at is not null then
    if new.observed_state is distinct from old.observed_state
       or new.reveal_result is distinct from old.reveal_result
       or new.is_correct is distinct from old.is_correct
       or new.revealed_at is distinct from old.revealed_at then
      raise exception 'STATE_RECOVERY_REVEAL_IMMUTABLE: trial % reveal is already fixed', old.trial_key;
    end if;
  end if;

  if new.prediction_frozen_at is not null and new.predicted_state is null then
    raise exception 'STATE_RECOVERY_FREEZE_REQUIRES_PREDICTION: trial %', new.trial_key;
  end if;

  if new.revealed_at is not null and (new.prediction_frozen_at is null or new.observed_state is null) then
    raise exception 'STATE_RECOVERY_REVEAL_REQUIRES_FROZEN_PREDICTION: trial %', new.trial_key;
  end if;

  if new.revealed_at is not null and new.revealed_at <= new.prediction_frozen_at then
    raise exception 'STATE_RECOVERY_REVEAL_ORDER_VIOLATION: trial %', new.trial_key;
  end if;

  new.updated_at := now();
  return new;
end
$$;

create trigger guard_state_recovery_trial_v1
before update on instrument.state_recovery_trials
for each row execute function instrument.guard_state_recovery_trial_v1();

insert into instrument.feature_registry(
  feature_key, prior_load_level, feature_family, feature_name, description,
  source_relation, source_column, interpretation_class, allowed_in_strict_blind
)
values
  ('mark_capture_pixels', 0, 'mark_physical', 'Mark capture pixels', 'Verified source image pixels and immutable byte identity.', 'mark.captures', 'sha256', 'observed', true),
  ('mark_source_coordinate', 0, 'mark_physical', 'Mark source coordinate', 'Physical region coordinates in a registered capture/surface.', 'mark.regions', 'geometry_payload', 'observed', true),
  ('mark_physical_channel', 0, 'mark_physical', 'Physical mark channel', 'Observed pigment/incision/damage channel without semantic naming.', 'mark.components', 'channel_key', 'observed', true),
  ('mark_component_geometry', 0, 'mark_physical', 'Mark component geometry', 'Observed component region geometry.', 'mark.components', 'region_id', 'observed', true),
  ('mark_damage_state', 0, 'mark_physical', 'Mark damage state', 'Observed visibility/damage/uncertainty state.', 'mark.components', 'observation_status', 'observed', true),
  ('mark_junction_relation', 1, 'mark_mechanical_topology', 'Mark junction relation', 'Mechanically or human-observed topology such as touch, cross, contain, above, or below.', 'mark.component_relations', 'relation_key', 'derived_mechanical', true),
  ('mark_sequence_position', 1, 'mark_mechanical_topology', 'Anonymous physical sequence position', 'Physical ordering inside an anonymous row/zone without word or character identity.', 'mark.sequence_members', 'ordinal_position', 'derived_mechanical', true),
  ('mark_capture_equivalence', 1, 'mark_source_control', 'Capture duplicate/derivative relation', 'Adjudicated capture identity relation used to prevent duplicate evidence.', 'mark.capture_equivalences', 'equivalence_kind', 'derived_mechanical', true),
  ('mark_unicode_identity', 3, 'mark_conventional_semantics', 'Unicode/conventional sign identity', 'Conventional character identity or normalized encoded sign.', null, null, 'conventional_semantic', false),
  ('mark_lexical_reading', 3, 'mark_conventional_semantics', 'Lexical reading', 'Conventional lexical or phonetic reading assigned to a mark.', null, null, 'conventional_semantic', false),
  ('mark_translation', 3, 'mark_conventional_semantics', 'Translation', 'Translated language attached to a mark or sequence.', null, null, 'conventional_semantic', false),
  ('mark_culture_label', 3, 'mark_conventional_semantics', 'Culture/script label', 'Cultural, script, or civilization category when used as an interpretive discovery feature.', null, null, 'conventional_semantic', false),
  ('mark_scholarly_interpretation', 4, 'mark_interpretive_prior', 'Scholarly mark interpretation', 'Inherited scholarly function/meaning claims; benchmark-only after blind discovery freeze.', null, null, 'external_interpretation', false)
on conflict (feature_key) do nothing;

insert into instrument.engine_registry(
  engine_key, engine_family, engine_name, description, implementation_ref,
  maximum_prior_load_level, uses_pretrained_semantic_model, independence_group, status
)
values
  ('mark_sequence_miner_v0', 'sequence_mining', 'Mark Sequence Miner v0', 'Anonymous physical recurrence/sequence engine over mark geometry, channels, junctions, and sequence position. No conventional mark identity is permitted in strict-blind runs.', null, 1, false, 'mark_physical_topology_sequence', 'experimental'),
  ('mark_state_recovery_v0', 'state_recovery', 'Mark State Recovery v0', 'Masked-state recovery benchmark engine. Predicts held-out physical state from permitted non-target recurrence context under explicit leakage exclusions.', null, 1, false, 'mark_physical_state_recovery', 'experimental')
on conflict (engine_key) do nothing;

insert into instrument.calibration_corpora(corpus_key, corpus_name, calibration_kind, public_description, discovery_visibility)
values
  ('mark_recovery_redundant_v1', 'Mark recovery redundant synthetic control v1', 'synthetic_hidden_structure', 'Synthetic anonymous mark sequences with a deliberately recoverable hidden state rule.', 'events_only'),
  ('mark_recovery_random_v1', 'Mark recovery random negative control v1', 'negative_control', 'Synthetic anonymous mark sequences whose target states are intentionally independent of context.', 'events_only'),
  ('mark_recovery_row_confounded_v1', 'Mark recovery row-confounded control v1', 'synthetic_hidden_structure', 'Synthetic sequences where row identity predicts state but cross-row routine context does not; detects same-row leakage.', 'events_only'),
  ('mark_recovery_duplicate_leakage_v1', 'Mark recovery duplicate-leakage control v1', 'synthetic_hidden_structure', 'Synthetic sequences containing duplicated/derived observations that create false recovery unless duplicate exclusion works.', 'events_only'),
  ('mark_recovery_damage_v1', 'Mark recovery damage/uncertainty control v1', 'known_structure', 'Synthetic sequences with controlled occlusion, damage, and uncertainty to test abstention and recoverability behavior.', 'events_only')
on conflict (corpus_key) do nothing;

insert into instrument.calibration_truth(corpus_key, latent_structure, evaluation_rule)
values
  ('mark_recovery_redundant_v1',
    '{"target":"secondary_state","rule":"context_determines_state","expected_signal":"cross_row_and_cross_surface_recovery"}'::jsonb,
    '{"must_exceed_carrier_baseline":true,"must_exceed_global_majority":true,"cross_row_required":true,"expected_verdict":"pass"}'::jsonb),
  ('mark_recovery_random_v1',
    '{"target":"secondary_state","rule":"state_independent_of_context","expected_signal":"none"}'::jsonb,
    '{"context_must_not_materially_exceed_baseline":true,"false_positive_is_failure":true,"expected_verdict":"negative_control_pass"}'::jsonb),
  ('mark_recovery_row_confounded_v1',
    '{"target":"secondary_state","rule":"row_identity_only","expected_signal":"same_row_only"}'::jsonb,
    '{"same_row_model_may_score":true,"cross_row_model_must_collapse_to_baseline":true,"false_cross_row_recovery_is_failure":true}'::jsonb),
  ('mark_recovery_duplicate_leakage_v1',
    '{"target":"secondary_state","rule":"duplicate_copy_leakage_only","expected_signal":"duplicate_only"}'::jsonb,
    '{"unfiltered_model_may_score":true,"duplicate_excluded_model_must_collapse":true,"duplicate_control_required":true}'::jsonb),
  ('mark_recovery_damage_v1',
    '{"target":"secondary_state","rule":"recoverable_with_declared_uncertainty","expected_signal":"partial_recovery_with_abstention"}'::jsonb,
    '{"damage_status_must_remain_source_truth":true,"prediction_must_not_overwrite_observation":true,"abstention_allowed":true}'::jsonb)
on conflict (corpus_key) do update
set latent_structure=excluded.latent_structure,
    evaluation_rule=excluded.evaluation_rule;

create or replace function instrument.validate_state_recovery_target_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument, mark
as $$
declare
  actual_instance_id bigint;
begin
  select c.instance_id into actual_instance_id
  from mark.components c
  where c.component_id = new.target_component_id;

  if actual_instance_id is null then
    raise exception 'STATE_RECOVERY_TARGET_COMPONENT_NOT_FOUND: %', new.target_component_id;
  end if;

  if actual_instance_id <> new.target_instance_id then
    raise exception 'STATE_RECOVERY_TARGET_INSTANCE_MISMATCH: component % belongs to instance %, not %', new.target_component_id, actual_instance_id, new.target_instance_id;
  end if;

  return new;
end
$$;

create trigger validate_state_recovery_target_v1
before insert or update of target_component_id, target_instance_id
on instrument.state_recovery_trials
for each row execute function instrument.validate_state_recovery_target_v1();

revoke all on instrument.state_recovery_trials from public, anon, authenticated, service_role;
revoke all on instrument.state_recovery_trial_exclusions from public, anon, authenticated, service_role;
revoke all on instrument.state_recovery_run_metrics from public, anon, authenticated, service_role;
revoke all on sequence instrument.state_recovery_trials_state_recovery_trial_id_seq from public, anon, authenticated, service_role;
revoke all on sequence instrument.state_recovery_trial_exclusions_state_recovery_trial_exclusion_id_seq from public, anon, authenticated, service_role;
revoke all on sequence instrument.state_recovery_run_metrics_state_recovery_run_metric_id_seq from public, anon, authenticated, service_role;

alter table instrument.state_recovery_trials enable row level security;
alter table instrument.state_recovery_trial_exclusions enable row level security;
alter table instrument.state_recovery_run_metrics enable row level security;

commit;
