create table if not exists draft.dss_manuscript_dating_evidence (
  dating_evidence_id bigserial primary key,
  witness_identity_key text not null,
  source_manuscript_label text not null,
  dating_method text not null check (dating_method in ('traditional_palaeography','palaeographic_reassessment','radiocarbon_raw_calibrated','radiocarbon_author_filtered','ai_style_prediction','historical_internal_date','other')),
  evidence_tier text not null check (evidence_tier in ('physical_material','geometric_style','expert_typology','historical_anchor','secondary_synthesis','other')),
  range_payload jsonb not null default '{}'::jsonb,
  source_citation text not null,
  source_key text,
  filtering_dependency text,
  is_direct_material_measurement boolean not null default false,
  is_author_filtered boolean not null default false,
  evidence_status text not null default 'working' check (evidence_status in ('working','supported','pressured','superseded','rejected','unresolved')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (witness_identity_key, dating_method, source_citation)
);
comment on table draft.dss_manuscript_dating_evidence is 'Keeps manuscript dating evidence by method without collapsing palaeography, raw radiocarbon distributions, author-filtered radiocarbon, and AI style estimates into one date. Source manuscript labels may be editorial umbrellas; witness_identity_key should use the best current physical identity.';
comment on column draft.dss_manuscript_dating_evidence.filtering_dependency is 'Records whether a reported range depends on another dating method, e.g. palaeographic rejection of a radiocarbon peak.';