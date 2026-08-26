alter table wnph.recovery_gap_assessments rename to legacy_recovery_gap_assessments;
alter table wnph.recovery_gap_dimensions rename to legacy_recovery_gap_dimensions;
alter table wnph.evidence_links rename column recovery_gap_dimension_id to legacy_recovery_gap_dimension_id;
alter table wnph.evidence_links rename constraint evidence_links_recovery_gap_dimension_id_fkey to evidence_links_legacy_recovery_gap_dimension_id_fkey;
alter index wnph.evidence_links_recovery_gap_dimension_idx rename to evidence_links_legacy_recovery_gap_dimension_idx;
comment on table wnph.legacy_recovery_gap_assessments is 'Legacy evidence retained from Recovery Gap v1. Non-authoritative for current recovery progression; preserved append-only for historical custody.';
comment on table wnph.legacy_recovery_gap_dimensions is 'Legacy dimension evidence retained from Recovery Gap v1. Non-authoritative for current recovery progression; preserved append-only for historical custody.';
comment on column wnph.evidence_links.legacy_recovery_gap_dimension_id is 'Historical evidence link target for retired Recovery Gap v1 rows only.';

create table wnph.recovery_condition_types (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique,
  label text not null,
  description text not null,
  status text not null default 'active' check (status in ('provisional','active','retired')),
  created_at timestamptz not null default now(),
  constraint recovery_condition_types_key_nonblank check (btrim(canonical_key) <> ''),
  constraint recovery_condition_types_label_nonblank check (btrim(label) <> ''),
  constraint recovery_condition_types_description_nonblank check (btrim(description) <> '')
);

create table wnph.recovery_condition_assessments (
  id uuid primary key default gen_random_uuid(),
  recovery_case_id uuid not null references wnph.recovery_cases(id),
  assessment_status text not null check (assessment_status in ('preliminary','bounded_complete')),
  scope_note text not null,
  confidence text check (confidence in ('high','medium','low','unknown')),
  supersedes_assessment_id uuid references wnph.recovery_condition_assessments(id),
  created_at timestamptz not null default now(),
  constraint recovery_condition_assessments_scope_nonblank check (btrim(scope_note) <> ''),
  constraint recovery_condition_assessments_supersedes_not_self check (supersedes_assessment_id is null or supersedes_assessment_id <> id)
);

create table wnph.recovery_condition_observations (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references wnph.recovery_condition_assessments(id),
  condition_type_id uuid not null references wnph.recovery_condition_types(id),
  condition_state text not null check (condition_state in ('present','absent','degraded','limited','conflicted','unverified','adequate','fragmentary','unknown','not_applicable')),
  epistemic_status text not null check (epistemic_status in ('evidence','inference','interpretation','bounded_unknown')),
  creator_corpus_id uuid references wnph.creator_corpora(id),
  series_id uuid references wnph.series(id),
  work_id uuid references wnph.historical_works(id),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  observation_text text not null,
  confidence text check (confidence in ('high','medium','low','unknown')),
  supersedes_observation_id uuid references wnph.recovery_condition_observations(id),
  created_at timestamptz not null default now(),
  constraint recovery_condition_observations_at_most_one_target check (num_nonnulls(creator_corpus_id,series_id,work_id,expression_id,manifestation_id,item_id,surrogate_id) <= 1),
  constraint recovery_condition_observations_text_nonblank check (btrim(observation_text) <> ''),
  constraint recovery_condition_observations_supersedes_not_self check (supersedes_observation_id is null or supersedes_observation_id <> id)
);

create index recovery_condition_assessments_case_idx on wnph.recovery_condition_assessments(recovery_case_id);
create index recovery_condition_assessments_supersedes_idx on wnph.recovery_condition_assessments(supersedes_assessment_id);
create index recovery_condition_observations_assessment_idx on wnph.recovery_condition_observations(assessment_id);
create index recovery_condition_observations_type_idx on wnph.recovery_condition_observations(condition_type_id);
create index recovery_condition_observations_corpus_idx on wnph.recovery_condition_observations(creator_corpus_id);
create index recovery_condition_observations_series_idx on wnph.recovery_condition_observations(series_id);
create index recovery_condition_observations_work_idx on wnph.recovery_condition_observations(work_id);
create index recovery_condition_observations_expression_idx on wnph.recovery_condition_observations(expression_id);
create index recovery_condition_observations_manifestation_idx on wnph.recovery_condition_observations(manifestation_id);
create index recovery_condition_observations_item_idx on wnph.recovery_condition_observations(item_id);
create index recovery_condition_observations_surrogate_idx on wnph.recovery_condition_observations(surrogate_id);
create index recovery_condition_observations_supersedes_idx on wnph.recovery_condition_observations(supersedes_observation_id);

create trigger recovery_condition_types_append_only before update or delete on wnph.recovery_condition_types for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_condition_assessments_append_only before update or delete on wnph.recovery_condition_assessments for each row execute function wnph.reject_append_only_mutation();
create trigger recovery_condition_observations_append_only before update or delete on wnph.recovery_condition_observations for each row execute function wnph.reject_append_only_mutation();

alter table wnph.recovery_condition_types enable row level security;
alter table wnph.recovery_condition_assessments enable row level security;
alter table wnph.recovery_condition_observations enable row level security;
revoke all on wnph.recovery_condition_types, wnph.recovery_condition_assessments, wnph.recovery_condition_observations from public, anon, authenticated, service_role;

alter table wnph.evidence_links add column recovery_condition_observation_id uuid references wnph.recovery_condition_observations(id);
create index evidence_links_recovery_condition_observation_idx on wnph.evidence_links(recovery_condition_observation_id);
alter table wnph.evidence_links drop constraint evidence_links_one_target_check;
alter table wnph.evidence_links add constraint evidence_links_one_target_check check (
  num_nonnulls(creator_id, corpus_id, work_creator_credit_id, appellation_attestation_id, work_identity_adjudication_id, corpus_membership_id, series_membership_id, expression_id, expression_adjudication_id, expression_manifestation_id, work_manifestation_id, manifestation_id, item_id, surrogate_id, date_claim_id, date_adjudication_id, identifier_id, source_circle_id, source_circle_membership_id, authorship_claim_id, transmission_claim_id, transmission_claim_continuity_id, recovery_case_id, source_sufficiency_assessment_id, source_sufficiency_member_id, rights_component_id, existing_recovery_finding_id, legacy_recovery_gap_dimension_id, recovery_condition_observation_id, recovery_case_event_id) = 1
);

alter table wnph.recovery_case_events drop constraint recovery_case_events_from_state_check;
alter table wnph.recovery_case_events drop constraint recovery_case_events_to_state_check;
alter table wnph.recovery_case_events add constraint recovery_case_events_from_state_check check (from_state is null or from_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','CONDITION_ASSESSED','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED'));
alter table wnph.recovery_case_events add constraint recovery_case_events_to_state_check check (to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','SOURCE_SUFFICIENT','RIGHTS_RESEARCH','RIGHTS_CLEARED','RECOVERY_AUDIT','CONDITION_ASSESSED','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH','REOPENED'));

create or replace function wnph.validate_recovery_case_event()
returns trigger
language plpgsql
set search_path = 'pg_catalog'
as $$
declare
  p wnph.recovery_case_events%rowtype;
  allowed boolean := false;
  gate_ok boolean := false;
begin
  if new.prior_event_id is null then
    if new.from_state is not null or new.to_state <> 'IDENTITY_ESTABLISHED' or new.event_kind <> 'state_transition' then
      raise exception 'WNPH Recovery custody: first event must establish inherited IDENTITY_ESTABLISHED state';
    end if;
    select exists (
      select 1
      from wnph.recovery_cases c
      join wnph.historical_works w on w.id = c.work_id
      where c.id = new.recovery_case_id
        and w.status = 'established'
        and exists (
          select 1 from wnph.work_identity_adjudications a
          where a.result_work_id = w.id and a.result in ('ESTABLISHES_WORK','SAME_WORK')
        )
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: initial IDENTITY_ESTABLISHED requires an established Work with identity adjudication'; end if;
    return new;
  end if;

  select * into p from wnph.recovery_case_events where id = new.prior_event_id;
  if not found then raise exception 'WNPH Recovery custody: prior event % does not exist', new.prior_event_id; end if;
  if p.recovery_case_id <> new.recovery_case_id then raise exception 'WNPH Recovery custody: prior event belongs to a different Recovery Case'; end if;
  if new.from_state is distinct from p.to_state then raise exception 'WNPH Recovery custody: from_state % must equal prior to_state %', new.from_state, p.to_state; end if;
  if exists (select 1 from wnph.recovery_case_events e where e.prior_event_id = p.id) then raise exception 'WNPH Recovery custody: event history may not fork'; end if;

  allowed :=
    (new.from_state = 'IDENTITY_ESTABLISHED' and new.to_state = 'SOURCE_RESEARCH') or
    (new.from_state = 'SOURCE_RESEARCH' and new.to_state in ('SOURCE_SUFFICIENT','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_RESEARCH')) or
    (new.from_state = 'SOURCE_SUFFICIENT' and new.to_state = 'RIGHTS_RESEARCH') or
    (new.from_state = 'RIGHTS_RESEARCH' and new.to_state in ('RIGHTS_CLEARED','REJECTED_RIGHTS','DEFERRED_RIGHTS','DEFERRED_RESEARCH')) or
    (new.from_state = 'RIGHTS_CLEARED' and new.to_state = 'RECOVERY_AUDIT') or
    (new.from_state = 'RECOVERY_AUDIT' and new.to_state in ('CONDITION_ASSESSED','DEFERRED_RESEARCH')) or
    (new.from_state = 'CONDITION_ASSESSED' and new.to_state in ('QUALIFICATION_REVIEW','DEFERRED_RESEARCH')) or
    (new.from_state = 'QUALIFICATION_REVIEW' and new.to_state in ('QUALIFIED','DEFERRED_LOW_VALUE','DEFERRED_RESEARCH')) or
    (new.from_state = 'QUALIFIED' and new.to_state in ('SELECTED_FOR_RECOVERY','DEFERRED_CAPACITY','DEFERRED_LOW_VALUE')) or
    (new.from_state in ('SELECTED_FOR_RECOVERY','REJECTED_IDENTITY','REJECTED_RIGHTS','REJECTED_SOURCE_QUALITY','REJECTED_INCOMPLETE','DEFERRED_RIGHTS','DEFERRED_BETTER_SOURCE_NEEDED','DEFERRED_LOW_VALUE','DEFERRED_CAPACITY','DEFERRED_RESEARCH') and new.to_state = 'REOPENED') or
    (new.from_state = 'REOPENED' and new.to_state in ('IDENTITY_ESTABLISHED','SOURCE_RESEARCH','RIGHTS_RESEARCH','RECOVERY_AUDIT','CONDITION_ASSESSED','QUALIFICATION_REVIEW','QUALIFIED'));
  if not allowed then raise exception 'WNPH Recovery custody: forbidden transition % -> %', new.from_state, new.to_state; end if;

  if new.to_state like 'REJECTED_%' and new.event_kind <> 'reject' then raise exception 'WNPH Recovery custody: rejected states require event_kind=reject'; end if;
  if new.to_state like 'DEFERRED_%' and new.event_kind <> 'defer' then raise exception 'WNPH Recovery custody: deferred states require event_kind=defer'; end if;
  if new.to_state = 'REOPENED' and new.event_kind <> 'reopen' then raise exception 'WNPH Recovery custody: REOPENED requires event_kind=reopen'; end if;
  if new.to_state = 'SELECTED_FOR_RECOVERY' and new.event_kind <> 'selection' then raise exception 'WNPH Recovery custody: selection requires event_kind=selection'; end if;
  if new.to_state not like 'REJECTED_%' and new.to_state not like 'DEFERRED_%' and new.to_state not in ('REOPENED','SELECTED_FOR_RECOVERY') and new.event_kind <> 'state_transition' then raise exception 'WNPH Recovery custody: ordinary progression requires event_kind=state_transition'; end if;

  if new.to_state = 'SOURCE_SUFFICIENT' then
    select exists (
      select 1 from wnph.source_sufficiency_assessments a
      where a.recovery_case_id = new.recovery_case_id and a.result = 'sufficient'
        and not exists (select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id = a.id)
        and exists (select 1 from wnph.source_sufficiency_members m where m.assessment_id = a.id and m.member_result = 'usable' and not exists (select 1 from wnph.source_sufficiency_members mn where mn.supersedes_member_id = m.id))
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: SOURCE_SUFFICIENT requires a current sufficient assessment with a usable source member'; end if;
  end if;

  if new.to_state = 'RIGHTS_CLEARED' then
    select exists (
      select 1 from wnph.rights_determinations d
      where d.recovery_case_id = new.recovery_case_id and d.overall_status = 'cleared'
        and not exists (select 1 from wnph.rights_determinations n where n.supersedes_determination_id = d.id)
        and exists (select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_type='underlying_work' and c.component_status in ('public_domain','reuse_permitted','licensed'))
        and not exists (select 1 from wnph.rights_components c where c.determination_id=d.id and c.component_status not in ('public_domain','reuse_permitted','licensed','not_applicable'))
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: RIGHTS_CLEARED requires a current cleared determination with resolved components'; end if;
  end if;

  if new.to_state in ('CONDITION_ASSESSED','QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (
      select 1
      from wnph.recovery_condition_assessments a
      where a.recovery_case_id = new.recovery_case_id
        and a.assessment_status = 'bounded_complete'
        and not exists (select 1 from wnph.recovery_condition_assessments n where n.supersedes_assessment_id = a.id)
        and exists (
          select 1 from wnph.recovery_condition_observations o
          where o.assessment_id = a.id
            and not exists (select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id = o.id)
        )
        and not exists (
          select 1
          from wnph.recovery_condition_observations o
          where o.assessment_id = a.id
            and o.epistemic_status = 'evidence'
            and not exists (select 1 from wnph.recovery_condition_observations onew where onew.supersedes_observation_id = o.id)
            and not exists (
              select 1 from wnph.evidence_links el
              where el.recovery_condition_observation_id = o.id
                and el.support_role in ('supports','contradicts','context')
                and not exists (select 1 from wnph.evidence_links eln where eln.supersedes_evidence_link_id = el.id)
            )
        )
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: condition progression requires a current bounded-complete condition assessment with observations and evidence links for evidence-status observations'; end if;
  end if;

  if new.to_state in ('QUALIFICATION_REVIEW','QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (
      select 1 from wnph.recovery_case_briefs b
      where b.recovery_case_id=new.recovery_case_id
        and b.why_recover is not null and btrim(b.why_recover)<>''
        and b.proposed_expression_type is not null and btrim(b.proposed_expression_type)<>''
        and not exists (select 1 from wnph.recovery_case_briefs n where n.supersedes_brief_id=b.id)
    ) and exists (
      select 1 from wnph.recovery_case_modes m where m.recovery_case_id=new.recovery_case_id and m.intent_status in ('proposed','committed') and not exists (select 1 from wnph.recovery_case_modes n where n.supersedes_mode_id=m.id)
    ) and exists (
      select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id and not exists (select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id)
    ) into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: qualification requires current recovery rationale, proposed Expression type, recovery mode, and output plan'; end if;
  end if;

  if new.to_state in ('QUALIFIED','SELECTED_FOR_RECOVERY') then
    select exists (select 1 from wnph.source_sufficiency_assessments a where a.recovery_case_id=new.recovery_case_id and a.result='sufficient' and not exists (select 1 from wnph.source_sufficiency_assessments n where n.supersedes_assessment_id=a.id))
      and exists (select 1 from wnph.rights_determinations d where d.recovery_case_id=new.recovery_case_id and d.overall_status='cleared' and not exists (select 1 from wnph.rights_determinations n where n.supersedes_determination_id=d.id))
    into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: qualification gates are no longer currently satisfied'; end if;
  end if;

  if new.to_state = 'SELECTED_FOR_RECOVERY' then
    select new.selection_authorized
      and exists (select 1 from wnph.recovery_case_targets t where t.recovery_case_id=new.recovery_case_id and t.target_role='preferred_source' and not exists (select 1 from wnph.recovery_case_targets n where n.supersedes_target_id=t.id))
      and exists (select 1 from wnph.recovery_case_outputs o where o.recovery_case_id=new.recovery_case_id and o.plan_role='first_target' and not exists (select 1 from wnph.recovery_case_outputs n where n.supersedes_output_id=o.id))
    into gate_ok;
    if not gate_ok then raise exception 'WNPH Recovery custody: selection requires explicit authorization, a preferred source, and a first target manifestation'; end if;
  end if;

  return new;
end
$$;

insert into wnph.recovery_condition_types(canonical_key,label,description,status) values
('digital_facsimile_survival','Digital facsimile survival','Whether an identifiable digital facsimile of the historical material survives and is accessible.','active'),
('identified_surviving_witness','Identified surviving witness','Whether at least one specifically identified historical Item or witness survives.','active'),
('text_integrity','Text integrity','Observed condition of the recoverable text, including verification, corruption, incompleteness, or adequacy.','active'),
('illustration_integrity','Illustration integrity','Observed condition of historical illustrations and their recoverability or fidelity.','active'),
('modern_reading_edition','Modern reading edition','Observed condition of any usable modern reading edition rather than mere scan or raw OCR.','active'),
('reflowable_ebook_availability','Reflowable ebook availability','Observed availability and adequacy of modern reflowable ebook access.','active'),
('accessibility','Accessibility','Observed accessibility condition for modern readers and assistive technologies.','active'),
('audio_availability','Audio availability','Observed availability and adequacy of an audio realization.','active'),
('library_access','Library access','Observed modern library discovery, lending, or distribution condition.','active'),
('discoverability','Discoverability','Observed ability for readers or researchers to discover the Work and its surviving manifestations.','active'),
('corpus_context','Corpus context','Observed preservation or loss of the Work''s relationship to its creator corpus or series context.','active'),
('attribution_clarity','Attribution clarity','Observed clarity, conflict, or obscurity in creator attribution.','active'),
('edition_relationship_clarity','Edition relationship clarity','Observed clarity or conflict among Expressions, Manifestations, Items, or later editions.','active'),
('modern_recovery_adequacy','Modern recovery adequacy','Observed adequacy of existing modern recovery as a factual condition, separate from WNPH publishing judgment.','active');