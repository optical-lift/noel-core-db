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
  check ((reveal_result in ('unscorable','invalidated')) is not true or is_correct is null),
  check (trial_status <> 'predicted_frozen' or prediction_frozen_at is not null),
  check (trial_status not in ('revealed','scored') or revealed_at is not null),
  check (trial_status <> 'invalidated' or invalidation_reason is not null)
);

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
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(instrument_run_id, benchmark_tier, metric_scope),
  check (benchmark_tier between 0 and 5),
  check (sample_count >= 0),
  check (correct_count is null or (correct_count >= 0 and correct_count <= sample_count)),
  check (accuracy is null or (accuracy >= 0 and accuracy <= 1)),
  check (balanced_accuracy is null or (balanced_accuracy >= 0 and balanced_accuracy <= 1)),
  check (log_loss is null or log_loss >= 0),
  check (entropy_before_bits is null or entropy_before_bits >= 0),
  check (entropy_after_bits is null or entropy_after_bits >= 0),
  check (metric_status in ('provisional','frozen','invalidated')),
  check ((metric_status='frozen') = (frozen_at is not null))
);

comment on table instrument.state_recovery_trials is 'Preregistered masked-state recovery trials. Physical source truth remains in mark.*; this table owns only mask, prediction, reveal, scoring, and leakage-audit state.';
comment on table instrument.state_recovery_trial_exclusions is 'Explicit leakage exclusions for masked recovery trials. Same-row, overlapping-routine, duplicate, and derivative evidence is recorded rather than silently filtered.';
comment on table instrument.state_recovery_run_metrics is 'Aggregate recovery metrics by benchmark tier, including entropy reduction/information gain and explicit leakage summaries.';

create index state_recovery_trials_run_idx on instrument.state_recovery_trials(instrument_run_id);
create index state_recovery_trials_target_component_idx on instrument.state_recovery_trials(target_component_id);
create index state_recovery_trials_target_instance_idx on instrument.state_recovery_trials(target_instance_id);
create index state_recovery_trials_zone_idx on instrument.state_recovery_trials(target_sequence_zone_id);
create index state_recovery_trial_exclusions_trial_idx on instrument.state_recovery_trial_exclusions(state_recovery_trial_id);
create index state_recovery_run_metrics_run_idx on instrument.state_recovery_run_metrics(instrument_run_id);

create or replace function instrument.validate_state_recovery_target_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument, mark
as $$
declare actual_instance_id bigint;
begin
  select c.instance_id into actual_instance_id from mark.components c where c.component_id = new.target_component_id;
  if actual_instance_id is null then
    raise exception 'STATE_RECOVERY_TARGET_COMPONENT_NOT_FOUND: %', new.target_component_id;
  end if;
  if actual_instance_id <> new.target_instance_id then
    raise exception 'STATE_RECOVERY_TARGET_INSTANCE_MISMATCH: component % belongs to instance %, not %', new.target_component_id, actual_instance_id, new.target_instance_id;
  end if;
  return new;
end
$$;

create or replace function instrument.guard_state_recovery_trial_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument, mark
as $$
begin
  if old.trial_status in ('scored','invalidated') then
    raise exception 'STATE_RECOVERY_FINAL_TRIAL_IMMUTABLE: trial % is %', old.trial_key, old.trial_status;
  end if;
  if old.prediction_frozen_at is not null and (
       new.instrument_run_id is distinct from old.instrument_run_id
    or new.corpus_snapshot_key is distinct from old.corpus_snapshot_key
    or new.target_component_id is distinct from old.target_component_id
    or new.target_instance_id is distinct from old.target_instance_id
    or new.target_sequence_zone_id is distinct from old.target_sequence_zone_id
    or new.masked_feature_family is distinct from old.masked_feature_family
    or new.mask_spec is distinct from old.mask_spec
    or new.benchmark_tier is distinct from old.benchmark_tier
    or new.exclusion_policy is distinct from old.exclusion_policy
    or new.training_query_digest is distinct from old.training_query_digest
    or new.training_evidence is distinct from old.training_evidence
    or new.predicted_state is distinct from old.predicted_state
    or new.prediction_confidence is distinct from old.prediction_confidence
    or new.prediction_support is distinct from old.prediction_support
    or new.prediction_frozen_at is distinct from old.prediction_frozen_at
    or new.leakage_audit is distinct from old.leakage_audit
  ) then
    raise exception 'STATE_RECOVERY_PREDICTION_IMMUTABLE: trial % prediction contract was frozen at %', old.trial_key, old.prediction_frozen_at;
  end if;
  if old.revealed_at is not null and (
       new.observed_state is distinct from old.observed_state
    or new.revealed_at is distinct from old.revealed_at
    or new.reveal_result is distinct from old.reveal_result
    or new.is_correct is distinct from old.is_correct
  ) then
    raise exception 'STATE_RECOVERY_REVEAL_IMMUTABLE: trial % reveal is already fixed', old.trial_key;
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

create or replace function instrument.guard_state_recovery_exclusion_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument
as $$
declare parent_frozen_at timestamptz; trial_id bigint;
begin
  trial_id := case when tg_op='DELETE' then old.state_recovery_trial_id else new.state_recovery_trial_id end;
  select t.prediction_frozen_at into parent_frozen_at from instrument.state_recovery_trials t where t.state_recovery_trial_id = trial_id;
  if parent_frozen_at is not null then
    raise exception 'STATE_RECOVERY_EXCLUSIONS_IMMUTABLE: trial % prediction was frozen at %', trial_id, parent_frozen_at;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

create or replace function instrument.guard_state_recovery_metric_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, instrument
as $$
begin
  if old.metric_status in ('frozen','invalidated') then
    raise exception 'STATE_RECOVERY_METRIC_IMMUTABLE: metric % is %', old.state_recovery_run_metric_id, old.metric_status;
  end if;
  if new.metric_status='frozen' and new.frozen_at is null then new.frozen_at := now(); end if;
  new.updated_at := now();
  return new;
end
$$;

create trigger validate_state_recovery_target_v1 before insert or update of target_component_id, target_instance_id on instrument.state_recovery_trials for each row execute function instrument.validate_state_recovery_target_v1();
create trigger guard_state_recovery_trial_v1 before update on instrument.state_recovery_trials for each row execute function instrument.guard_state_recovery_trial_v1();
create trigger guard_state_recovery_exclusion_v1 before insert or update or delete on instrument.state_recovery_trial_exclusions for each row execute function instrument.guard_state_recovery_exclusion_v1();
create trigger guard_state_recovery_metric_v1 before update on instrument.state_recovery_run_metrics for each row execute function instrument.guard_state_recovery_metric_v1();

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
