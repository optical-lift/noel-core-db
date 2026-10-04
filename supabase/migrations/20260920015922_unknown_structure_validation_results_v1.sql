
    create table if not exists instrument.unknown_structure_validation_results (
      validation_id bigint generated always as identity primary key,
      structure_candidate_id bigint not null references instrument.structure_candidates(structure_candidate_id) on delete cascade,
      validation_key text not null unique,
      validation_family text not null,
      validation_scope text not null,
      observed_value numeric,
      null_expected numeric,
      observed_over_expected numeric,
      empirical_p_enrich numeric,
      empirical_p_deplete numeric,
      holdout_observed numeric,
      holdout_null_expected numeric,
      holdout_over_expected numeric,
      validation_status text not null
        check(validation_status in ('survives','fails','local_only','depleted','pending')),
      validation_payload jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now()
    );

    create index if not exists unknown_structure_validation_candidate_idx
      on instrument.unknown_structure_validation_results(structure_candidate_id);

    create or replace view instrument.v_unknown_structure_validated_candidates as
    select
      c.structure_candidate_id,c.candidate_key,c.anonymous_label,
      c.neutral_structure,c.discovery_support,
      v.validation_key,v.validation_family,v.validation_scope,
      v.observed_value,v.null_expected,v.observed_over_expected,
      v.empirical_p_enrich,v.empirical_p_deplete,
      v.holdout_observed,v.holdout_null_expected,v.holdout_over_expected,
      v.validation_status,v.validation_payload
    from instrument.structure_candidates c
    join instrument.unknown_structure_validation_results v
      on v.structure_candidate_id=c.structure_candidate_id;
  