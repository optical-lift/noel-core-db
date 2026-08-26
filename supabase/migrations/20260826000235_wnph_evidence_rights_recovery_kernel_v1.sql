-- WNPH Evidence / Rights / Recovery Kernel v1
-- Private, append-only Recovery Work custody downstream of stable bibliographic identity.
-- A Historical Work is not a Recovery Case, and only governed state events can advance a case.

create table wnph.recovery_cases (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique,
  work_id uuid not null references wnph.historical_works(id),
  case_scope text not null,
  why_recover text,
  proposed_expression_type text,
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  supersedes_case_id uuid references wnph.recovery_cases(id),
  created_by text,
  created_at timestamptz not null default now(),
  constraint recovery_cases_key_nonblank check (btrim(canonical_key) <> ''),
  constraint recovery_cases_scope_nonblank check (btrim(case_scope) <> ''),
  constraint recovery_cases_supersedes_not_self check (supersedes_case_id is null or supersedes_case_id <> id)
);

create table wnph.recovery_case_targets (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  target_role text not null check (target_role in ('candidate','primary_source','preferred_source','publication_model','comparison','reference')),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  rationale text,
  supersedes_target_id uuid references wnph.recovery_case_targets(id),
  created_at timestamptz not null default now(),
  constraint recovery_case_targets_one_target check (num_nonnulls(expression_id, manifestation_id, item_id, surrogate_id) = 1),
  constraint recovery_case_targets_supersedes_not_self check (supersedes_target_id is null or supersedes_target_id <> id)
);

create table wnph.recovery_case_modes (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  recovery_mode text not null check (recovery_mode in ('material','text','illustration','accessibility','ebook','audio','witness','transcription','translation','functional_translation','other')),
  intent_status text not null default 'proposed' check (intent_status in ('proposed','committed','withdrawn')),
  rationale text,
  supersedes_mode_id uuid references wnph.recovery_case_modes(id),
  created_at timestamptz not null default now(),
  constraint recovery_case_modes_supersedes_not_self check (supersedes_mode_id is null or supersedes_mode_id <> id)
);

create table wnph.recovery_case_outputs (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  manifestation_type text not null check (manifestation_type in ('web','epub','fixed_layout_epub','audiobook','paperback','hardcover','print_pdf','other')),
  plan_role text not null default 'planned' check (plan_role in ('first_target','planned','optional')),
  notes text,
  supersedes_output_id uuid references wnph.recovery_case_outputs(id),
  created_at timestamptz not null default now(),
  constraint recovery_case_outputs_supersedes_not_self check (supersedes_output_id is null or supersedes_output_id <> id)
);

create table wnph.source_sufficiency_assessments (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  result text not null check (result in ('unknown','insufficient','provisionally_sufficient','sufficient')),
  confidence text check (confidence in ('high','medium','low','unknown')),
  rationale text not null,
  recorded_by text,
  supersedes_assessment_id uuid references wnph.source_sufficiency_assessments(id),
  created_at timestamptz not null default now(),
  constraint source_sufficiency_rationale_nonblank check (btrim(rationale) <> ''),
  constraint source_sufficiency_supersedes_not_self check (supersedes_assessment_id is null or supersedes_assessment_id <> id)
);

create table wnph.source_sufficiency_members (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references wnph.source_sufficiency_assessments(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  source_role text not null check (source_role in ('candidate','primary','secondary','comparison','reference')),
  completeness text not null check (completeness in ('complete','substantially_complete','incomplete','fragmentary','unknown')),
  quality text not null check (quality in ('excellent','good','usable','poor','unusable','unknown')),
  provenance_status text not null check (provenance_status in ('sufficient','insufficient','unknown')),
  member_result text not null check (member_result in ('usable','not_usable','unknown')),
  missing_or_damage_note text,
  notes text,
  supersedes_member_id uuid references wnph.source_sufficiency_members(id),
  created_at timestamptz not null default now(),
  constraint source_sufficiency_members_one_source check (num_nonnulls(item_id, surrogate_id) = 1),
  constraint source_sufficiency_members_supersedes_not_self check (supersedes_member_id is null or supersedes_member_id <> id)
);

create table wnph.rights_determinations (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  jurisdiction text not null,
  overall_status text not null check (overall_status in ('unknown','researching','cleared','restricted','rejected')),
  confidence text check (confidence in ('high','medium','low','unknown')),
  rationale text not null,
  determined_by text,
  determined_at timestamptz not null default now(),
  supersedes_determination_id uuid references wnph.rights_determinations(id),
  created_at timestamptz not null default now(),
  constraint rights_determinations_jurisdiction_nonblank check (btrim(jurisdiction) <> ''),
  constraint rights_determinations_rationale_nonblank check (btrim(rationale) <> ''),
  constraint rights_determinations_supersedes_not_self check (supersedes_determination_id is null or supersedes_determination_id <> id)
);

create table wnph.rights_components (
  id uuid primary key default gen_random_uuid(),
  determination_id uuid not null references wnph.rights_determinations(id),
  component_type text not null check (component_type in ('underlying_work','historical_illustrations','source_images','prior_translation','introduction','editorial_apparatus','audio','other')),
  component_status text not null check (component_status in ('unknown','researching','public_domain','reuse_permitted','licensed','restricted','not_applicable','rejected')),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  use_scope text,
  rationale text not null,
  notes text,
  supersedes_component_id uuid references wnph.rights_components(id),
  created_at timestamptz not null default now(),
  constraint rights_components_at_most_one_target check (num_nonnulls(work_id, expression_id, manifestation_id, item_id, surrogate_id) <= 1),
  constraint rights_components_target_required_unless_na check (component_status = 'not_applicable' or num_nonnulls(work_id, expression_id, manifestation_id, item_id, surrogate_id) = 1),
  constraint rights_components_rationale_nonblank check (btrim(rationale) <> ''),
  constraint rights_components_supersedes_not_self check (supersedes_component_id is null or supersedes_component_id <> id)
);

create table wnph.existing_recovery_audits (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  audit_status text not null check (audit_status in ('not_started','in_progress','complete')),
  checked_at timestamptz not null default now(),
  scope_note text,
  supersedes_audit_id uuid references wnph.existing_recovery_audits(id),
  created_at timestamptz not null default now(),
  constraint existing_recovery_audits_supersedes_not_self check (supersedes_audit_id is null or supersedes_audit_id <> id)
);

create table wnph.existing_recovery_findings (
  id uuid primary key default gen_random_uuid(),
  audit_id uuid not null references wnph.existing_recovery_audits(id),
  channel text not null check (channel in ('project_gutenberg','standard_ebooks','librivox','modern_commercial_ebook','modern_audiobook','library_ebook','library_audiobook','modern_print','scholarly_or_critical_editions','internet_archive','library_of_congress','other')),
  availability_status text not null check (availability_status in ('absent','present','uncertain','not_applicable')),
  manifestation_type text check (manifestation_type in ('SCAN_ONLY','RAW_OCR','FACSIMILE','SEARCHABLE_TEXT','REFLOWABLE_EBOOK','RESTORED_EDITION','AUDIOBOOK','PRINT_REPRINT','CRITICAL_EDITION','TRANSLATION','DIPLOMATIC_EDITION','RAW_WITNESS_EDITION','OTHER')),
  competence_state text not null default 'unknown' check (competence_state in ('unknown','raw','partial','competent','not_applicable')),
  competing_identifier text,
  notes text,
  supersedes_finding_id uuid references wnph.existing_recovery_findings(id),
  created_at timestamptz not null default now(),
  constraint existing_recovery_findings_supersedes_not_self check (supersedes_finding_id is null or supersedes_finding_id <> id)
);

create table wnph.recovery_gap_assessments (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  assessment_status text not null check (assessment_status in ('preliminary','complete')),
  confidence text check (confidence in ('high','medium','low','unknown')),
  rationale text not null,
  supersedes_assessment_id uuid references wnph.recovery_gap_assessments(id),
  created_at timestamptz not null default now(),
  constraint recovery_gap_assessments_rationale_nonblank check (btrim(rationale) <> ''),
  constraint recovery_gap_assessments_supersedes_not_self check (supersedes_assessment_id is null or supersedes_assessment_id <> id)
);

create table wnph.recovery_gap_dimensions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references wnph.recovery_gap_assessments(id),
  dimension text not null check (dimension in ('material_recovery','text_recovery','illustration_recovery','ebook_recovery','accessibility','audiobook','witness_recovery','translation','functional_translation','library_access','other')),
  gap_state text not null check (gap_state in ('unknown','closed','partial_gap','meaningful_gap','not_applicable')),
  score integer check (score between 0 and 100),
  critical boolean not null default false,
  rationale text not null,
  supersedes_dimension_id uuid references wnph.recovery_gap_dimensions(id),
  created_at timestamptz not null default now(),
  constraint recovery_gap_dimensions_rationale_nonblank check (btrim(rationale) <> ''),
  constraint recovery_gap_dimensions_supersedes_not_self check (supersedes_dimension_id is null or supersedes_dimension_id <> id)
);

create table wnph.recovery_clusters (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique,
  label text not null,
  rationale text not null,
  status text not null default 'proposed' check (status in ('proposed','active','retired')),
  supersedes_cluster_id uuid references wnph.recovery_clusters(id),
  created_at timestamptz not null default now(),
  constraint recovery_clusters_key_nonblank check (btrim(canonical_key) <> ''),
  constraint recovery_clusters_label_nonblank check (btrim(label) <> ''),
  constraint recovery_clusters_rationale_nonblank check (btrim(rationale) <> ''),
  constraint recovery_clusters_supersedes_not_self check (supersedes_cluster_id is null or supersedes_cluster_id <> id)
);

create table wnph.recovery_cluster_members (
  id uuid primary key default gen_random_uuid(),
  cluster_id uuid not null references wnph.recovery_clusters(id),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  membership_role text not null default 'member' check (membership_role in ('member','anchor','comparison','optional')),
  notes text,
  supersedes_membership_id uuid references wnph.recovery_cluster_members(id),
  created_at timestamptz not null default now(),
  constraint recovery_cluster_members_supersedes_not_self check (supersedes_membership_id is null or supersedes_membership_id <> id)
);

create table wnph.recovery_case_events (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  prior_event_id uuid references wnph.recovery_case_events(id),
  from_state text,
  to_state text not null,
  event_kind text not null check (event_kind in ('state_transition','reject','defer','reopen','selection')),
  rationale text not null,
  recorded_by text,
  created_at timestamptz not null default now(),
  constraint recovery_case_events_from_state_check check (from_state is null or from_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','GAP_ESTABLISHED','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED')),
  constraint recovery_case_events_to_state_check check (to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','GAP_ESTABLISHED','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED')),
  constraint recovery_case_events_rationale_nonblank check (btrim(rationale) <> '')
);

create unique index recovery_case_events_one_root_uq on wnph.recovery_case_events(recovery_case_id) where prior_event_id is null;
create unique index recovery_case_events_one_child_uq on wnph.recovery_case_events(prior_event_id) where prior_event_id is not null;

create or replace function wnph.validate_recovery_case_event()
returns trigger
language plpgsql
set search_path = 'pg_catalog'
as $$
declare
  p wnph.recovery_case_events%rowtype;
  allowed boolean := false;
begin
  if new.prior_event_id is null then
    if new.from_state is not null or new.to_state <> 'IDENTITY_ESTABLISHED' then
      raise exception 'WNPH Recovery custody: first event must establish inherited IDENTITY_ESTABLISHED state';
    end if;
    return new;
  end if;

  select * into p from wnph.recovery_case_events where id = new.prior_event_id;
  if not found then
    raise exception 'WNPH Recovery custody: prior event % does not exist', new.prior_event_id;
  end if;
  if p.recovery_case_id <> new.recovery_case_id then
    raise exception 'WNPH Recovery custody: prior event belongs to a different Recovery Case';
  end if;
  if new.from_state is distinct from p.to_state then
    raise exception 'WNPH Recovery custody: from_state % must equal prior to_state %', new.from_state, p.to_state;
  end if;
  if exists (select 1 from wnph.recovery_case_events e where e.prior_event_id = p.id) then
    raise exception 'WNPH Recovery custody: event history may not fork';
  end if;

  allowed :=
    (new.from_state = 'IDENTITY_ESTABLISHED' and new.to_state = 'SOURCE_RESEARCH') or
    (new.from_state = 'SOURCE_RESEARCH' and new.to_state in ('SOURCE_SUFFICIENT','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_RESEARCH')) or
    (new.from_state = 'SOURCE_SUFFICIENT' and new.to_state = 'RIGHTS_RESEARCH') or
    (new.from_state = 'RIGHTS_RESEARCH' and new.to_state in ('RIGHTS_CLEARED','REJECTED_RIGHTS','DEFERRED_RIGHTS','DEFERRED_RESEARCH')) or
    (new.from_state = 'RIGHTS_CLEARED' and new.to_state = 'RECOVERY_AUDIT') or
    (new.from_state = 'RECOVERY_AUDIT' and new.to_state in ('GAP_ESTABLISHED','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RESEARCH')) or
    (new.from_state = 'GAP_ESTABLISHED' and new.to_state = 'QUALIFICATION_REVIEW') or
    (new.from_state = 'QUALIFICATION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_LOW_VALUE','DEFERRED_RESEARCH')) or
    (new.from_state = 'QUALIFIED' and new.to_state in ('SELECTED_FOR_RECOVERY','DEFERRED_CAPACITY','DEFERRED_LOW_VALUE')) or
    (new.from_state in ('SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','REJECTED_ALREADY_RECOVERED','REJECTED_NO_MEANINGFUL_GAP','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH') and new.to_state = 'REOPENED') or
    (new.from_state = 'REOPENED' and new.to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','RIGHTS_RESEARCH','RECOVERY_AUDIT','QUALIFICATION_REVIEW','QUALIFIED'));

  if not allowed then
    raise exception 'WNPH Recovery custody: forbidden transition % -> %', new.from_state, new.to_state;
  end if;
  return new;
end
$$;

create trigger recovery_case_events_transition_guard
before insert on wnph.recovery_case_events
for each row execute function wnph.validate_recovery_case_event();

alter table wnph.evidence_links
  add column recovery_case_id uuid references wnph.recovery_cases(id),
  add column source_sufficiency_assessment_id uuid references wnph.source_sufficiency_assessments(id),
  add column source_sufficiency_member_id uuid references wnph.source_sufficiency_members(id),
  add column rights_component_id uuid references wnph.rights_components(id),
  add column existing_recovery_finding_id uuid references wnph.existing_recovery_findings(id),
  add column recovery_gap_dimension_id uuid references wnph.recovery_gap_dimensions(id),
  add column recovery_case_event_id uuid references wnph.recovery_case_events(id);

alter table wnph.evidence_links drop constraint evidence_links_one_target_check;
alter table wnph.evidence_links add constraint evidence_links_one_target_check check (
  num_nonnulls(
    creator_id, corpus_id, work_creator_credit_id, appellation_attestation_id,
    work_identity_adjudication_id, corpus_membership_id, series_membership_id,
    expression_id, expression_adjudication_id, expression_manifestation_id,
    work_manifestation_id, manifestation_id, item_id, surrogate_id,
    date_claim_id, date_adjudication_id, identifier_id,
    source_circle_id, source_circle_membership_id, authorship_claim_id,
    transmission_claim_id, transmission_claim_continuity_id,
    recovery_case_id, source_sufficiency_assessment_id, source_sufficiency_member_id,
    rights_component_id, existing_recovery_finding_id, recovery_gap_dimension_id,
    recovery_case_event_id
  ) = 1
);

create index recovery_cases_work_id_idx on wnph.recovery_cases(work_id);
create index recovery_cases_supersedes_idx on wnph.recovery_cases(supersedes_case_id);
create index recovery_case_targets_case_idx on wnph.recovery_case_targets(recovery_case_id);
create index recovery_case_targets_expression_idx on wnph.recovery_case_targets(expression_id);
create index recovery_case_targets_manifestation_idx on wnph.recovery_case_targets(manifestation_id);
create index recovery_case_targets_item_idx on wnph.recovery_case_targets(item_id);
create index recovery_case_targets_surrogate_idx on wnph.recovery_case_targets(surrogate_id);
create index recovery_case_targets_supersedes_idx on wnph.recovery_case_targets(supersedes_target_id);
create index recovery_case_modes_case_idx on wnph.recovery_case_modes(recovery_case_id);
create index recovery_case_modes_supersedes_idx on wnph.recovery_case_modes(supersedes_mode_id);
create index recovery_case_outputs_case_idx on wnph.recovery_case_outputs(recovery_case_id);
create index recovery_case_outputs_supersedes_idx on wnph.recovery_case_outputs(supersedes_output_id);
create index source_sufficiency_case_idx on wnph.source_sufficiency_assessments(recovery_case_id);
create index source_sufficiency_supersedes_idx on wnph.source_sufficiency_assessments(supersedes_assessment_id);
create index source_suff_members_assessment_idx on wnph.source_sufficiency_members(assessment_id);
create index source_suff_members_item_idx on wnph.source_sufficiency_members(item_id);
create index source_suff_members_surrogate_idx on wnph.source_sufficiency_members(surrogate_id);
create index source_suff_members_supersedes_idx on wnph.source_sufficiency_members(supersedes_member_id);
create index rights_determinations_case_idx on wnph.rights_determinations(recovery_case_id);
create index rights_determinations_supersedes_idx on wnph.rights_determinations(supersedes_determination_id);
create index rights_components_determination_idx on wnph.rights_components(determination_id);
create index rights_components_work_idx on wnph.rights_components(work_id);
create index rights_components_expression_idx on wnph.rights_components(expression_id);
create index rights_components_manifestation_idx on wnph.rights_components(manifestation_id);
create index rights_components_item_idx on wnph.rights_components(item_id);
create index rights_components_surrogate_idx on wnph.rights_components(surrogate_id);
create index rights_components_supersedes_idx on wnph.rights_components(supersedes_component_id);
create index existing_recovery_audits_case_idx on wnph.existing_recovery_audits(recovery_case_id);
create index existing_recovery_audits_supersedes_idx on wnph.existing_recovery_audits(supersedes_audit_id);
create index existing_recovery_findings_audit_idx on wnph.existing_recovery_findings(audit_id);
create index existing_recovery_findings_supersedes_idx on wnph.existing_recovery_findings(supersedes_finding_id);
create index recovery_gap_assessments_case_idx on wnph.recovery_gap_assessments(recovery_case_id);
create index recovery_gap_assessments_supersedes_idx on wnph.recovery_gap_assessments(supersedes_assessment_id);
create index recovery_gap_dimensions_assessment_idx on wnph.recovery_gap_dimensions(assessment_id);
create index recovery_gap_dimensions_supersedes_idx on wnph.recovery_gap_dimensions(supersedes_dimension_id);
create index recovery_clusters_supersedes_idx on wnph.recovery_clusters(supersedes_cluster_id);
create index recovery_cluster_members_cluster_idx on wnph.recovery_cluster_members(cluster_id);
create index recovery_cluster_members_case_idx on wnph.recovery_cluster_members(recovery_case_id);
create index recovery_cluster_members_supersedes_idx on wnph.recovery_cluster_members(supersedes_membership_id);
create index recovery_case_events_case_idx on wnph.recovery_case_events(recovery_case_id);
create index evidence_links_recovery_case_idx on wnph.evidence_links(recovery_case_id);
create index evidence_links_source_suff_assessment_idx on wnph.evidence_links(source_sufficiency_assessment_id);
create index evidence_links_source_suff_member_idx on wnph.evidence_links(source_sufficiency_member_id);
create index evidence_links_rights_component_idx on wnph.evidence_links(rights_component_id);
create index evidence_links_existing_recovery_finding_idx on wnph.evidence_links(existing_recovery_finding_id);
create index evidence_links_recovery_gap_dimension_idx on wnph.evidence_links(recovery_gap_dimension_id);
create index evidence_links_recovery_case_event_idx on wnph.evidence_links(recovery_case_event_id);

alter table wnph.recovery_cases enable row level security;
alter table wnph.recovery_case_targets enable row level security;
alter table wnph.recovery_case_modes enable row level security;
alter table wnph.recovery_case_outputs enable row level security;
alter table wnph.source_sufficiency_assessments enable row level security;
alter table wnph.source_sufficiency_members enable row level security;
alter table wnph.rights_determinations enable row level security;
alter table wnph.rights_components enable row level security;
alter table wnph.existing_recovery_audits enable row level security;
alter table wnph.existing_recovery_findings enable row level security;
alter table wnph.recovery_gap_assessments enable row level security;
alter table wnph.recovery_gap_dimensions enable row level security;
alter table wnph.recovery_clusters enable row level security;
alter table wnph.recovery_cluster_members enable row level security;
alter table wnph.recovery_case_events enable row level security;

revoke all on table wnph.recovery_cases from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_case_targets from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_case_modes from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_case_outputs from public, anon, authenticated, service_role;
revoke all on table wnph.source_sufficiency_assessments from public, anon, authenticated, service_role;
revoke all on table wnph.source_sufficiency_members from public, anon, authenticated, service_role;
revoke all on table wnph.rights_determinations from public, anon, authenticated, service_role;
revoke all on table wnph.rights_components from public, anon, authenticated, service_role;
revoke all on table wnph.existing_recovery_audits from public, anon, authenticated, service_role;
revoke all on table wnph.existing_recovery_findings from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_gap_assessments from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_gap_dimensions from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_clusters from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_cluster_members from public, anon, authenticated, service_role;
revoke all on table wnph.recovery_case_events from public, anon, authenticated, service_role;
revoke execute on function wnph.validate_recovery_case_event() from public, anon, authenticated, service_role;

create trigger recovery_cases_append_only before update or delete on wnph.recovery_cases for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_case_targets_append_only before update or delete on wnph.recovery_case_targets for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_case_modes_append_only before update or delete on wnph.recovery_case_modes for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_case_outputs_append_only before update or delete on wnph.recovery_case_outputs for each row execute function wnph.reject_append_only_mutation();
create trigger source_sufficiency_assessments_append_only before update or delete on wnph.source_sufficiency_assessments for each row execute function wnph.reject_append_only_mutation();
create trigger source_sufficiency_members_append_only before update or delete on wnph.source_sufficiency_members for each row execute function wnph.reject_append_only_mutation();
create trigger rights_determinations_append_only before update or delete on wnph.rights_determinations for each row execute function wnph.reject_append_only_mutation();
create trigger rights_components_append_only before update or delete on wnph.rights_components for each row execute function wnph.reject_append_only_mutation();
create trigger existing_recovery_audits_append_only before update or delete on wnph.existing_recovery_audits for each row execute function wnph.reject_append_only_mutation();
create trigger existing_recovery_findings_append_only before update or delete on wnph.existing_recovery_findings for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_gap_assessments_append_only before update or delete on wnph.recovery_gap_assessments for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_gap_dimensions_append_only before update or delete on wnph.recovery_gap_dimensions for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_clusters_append_only before update or delete on wnph.recovery_clusters for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_cluster_members_append_only before update or delete on wnph.recovery_cluster_members for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_case_events_append_only before update or delete on wnph.recovery_case_events for each row execute function wnph.reject_append_only_mutation();
