-- WNPH Transmission Act kernel + Dewy proven lineage v1
--
-- Distinction:
--   transmission_claims = historical/research assertions about continuity.
--   transmission_acts   = append-only custody events recording how governed inputs became governed outputs.
--
-- A Transmission Act is not an IFLA LRM bibliographic entity. It is provenance/event machinery
-- spanning Items, Surrogates, Expressions, WNPH Publication Source Packages and later Manifestations.

comment on table wnph.transmission_claims is
  'Historical/research assertions about transmission or continuity. These describe transmission; wnph.transmission_acts records actual governed transmission/custody events.';

create table wnph.transmission_agents (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  agent_type text not null check (btrim(agent_type) <> ''),
  canonical_label text not null check (btrim(canonical_label) <> ''),
  external_identifier text,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_agent_id uuid references wnph.transmission_agents(id),
  created_at timestamptz not null default now(),
  constraint transmission_agents_supersedes_not_self check (supersedes_agent_id is null or supersedes_agent_id <> id)
);

comment on table wnph.transmission_agents is
  'People, institutions, systems or processes that perform Transmission Acts. Open agent_type vocabulary supports ancient scribes, libraries, scanners, OCR systems, editors and future automated processes.';

create table wnph.transmission_acts (
  id uuid primary key default gen_random_uuid(),
  canonical_key text not null unique check (btrim(canonical_key) <> ''),
  recovery_case_id uuid references wnph.recovery_cases(id),
  work_id uuid references wnph.historical_works(id),
  operation_type text not null check (btrim(operation_type) <> ''),
  purpose text,
  method_note text,
  epistemic_status text not null check (btrim(epistemic_status) <> ''),
  confidence text,
  occurred_at timestamptz,
  date_note text,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_act_id uuid references wnph.transmission_acts(id),
  created_at timestamptz not null default now(),
  constraint transmission_acts_supersedes_not_self check (supersedes_act_id is null or supersedes_act_id <> id)
);

comment on table wnph.transmission_acts is
  'Append-only provenance events: a governed actor/process performs an operation using governed inputs and produces governed outputs. operation_type and epistemic_status are open vocabularies so ancient and modern transmission practices can share one event model without forcing false precision.';

create table wnph.transmission_act_agents (
  id uuid primary key default gen_random_uuid(),
  transmission_act_id uuid not null references wnph.transmission_acts(id),
  agent_id uuid not null references wnph.transmission_agents(id),
  agent_role text not null check (btrim(agent_role) <> ''),
  notes text,
  supersedes_act_agent_id uuid references wnph.transmission_act_agents(id),
  created_at timestamptz not null default now(),
  constraint transmission_act_agents_supersedes_not_self check (supersedes_act_agent_id is null or supersedes_act_agent_id <> id)
);

comment on table wnph.transmission_act_agents is
  'Many-to-many actor participation in a Transmission Act: scribe, institution, editor, scanner, OCR system, renderer, reviewer, or other role.';

create table wnph.transmission_act_objects (
  id uuid primary key default gen_random_uuid(),
  transmission_act_id uuid not null references wnph.transmission_acts(id),
  direction text not null check (direction in ('input','output','context')),
  object_role text not null check (btrim(object_role) <> ''),
  expression_id uuid references wnph.expressions(id),
  manifestation_id uuid references wnph.manifestations(id),
  item_id uuid references wnph.items(id),
  surrogate_id uuid references wnph.surrogates(id),
  evidence_source_id uuid references wnph.evidence_sources(id),
  publication_source_package_id uuid references wnph.publication_source_packages(id),
  publication_source_block_id uuid references wnph.publication_source_blocks(id),
  publication_source_asset_id uuid references wnph.publication_source_assets(id),
  publication_manifestation_derivation_id uuid references wnph.publication_manifestation_derivations(id),
  recovery_decision_id uuid references wnph.recovery_decisions(id),
  recovery_case_event_id uuid references wnph.recovery_case_events(id),
  locator jsonb not null default '{}'::jsonb,
  notes text,
  supersedes_act_object_id uuid references wnph.transmission_act_objects(id),
  created_at timestamptz not null default now(),
  constraint transmission_act_objects_one_object check (
    num_nonnulls(
      expression_id,
      manifestation_id,
      item_id,
      surrogate_id,
      evidence_source_id,
      publication_source_package_id,
      publication_source_block_id,
      publication_source_asset_id,
      publication_manifestation_derivation_id,
      recovery_decision_id,
      recovery_case_event_id
    ) = 1
  ),
  constraint transmission_act_objects_supersedes_not_self check (supersedes_act_object_id is null or supersedes_act_object_id <> id)
);

comment on table wnph.transmission_act_objects is
  'Typed governed inputs, outputs and contextual objects for a Transmission Act. locator preserves page, region, paragraph, asset or other source coordinates without making historical pagination the canonical content structure.';

create table wnph.transmission_act_evidence (
  id uuid primary key default gen_random_uuid(),
  transmission_act_id uuid not null references wnph.transmission_acts(id),
  source_id uuid not null references wnph.evidence_sources(id),
  support_role text not null check (support_role in ('supports','contradicts','context')),
  confidence text,
  note text,
  supersedes_act_evidence_id uuid references wnph.transmission_act_evidence(id),
  created_at timestamptz not null default now(),
  constraint transmission_act_evidence_supersedes_not_self check (supersedes_act_evidence_id is null or supersedes_act_evidence_id <> id)
);

comment on table wnph.transmission_act_evidence is
  'Evidence apparatus for Transmission Acts. Evidence remains separate from the event record and separate from reader-facing recovered text.';

create table wnph.transmission_interventions (
  id uuid primary key default gen_random_uuid(),
  transmission_act_id uuid not null references wnph.transmission_acts(id),
  intervention_key text not null check (btrim(intervention_key) <> ''),
  intervention_type text not null check (btrim(intervention_type) <> ''),
  subject_locator jsonb not null default '{}'::jsonb,
  before_value text,
  after_value text,
  rationale text not null check (btrim(rationale) <> ''),
  certainty text,
  decision_status text not null check (btrim(decision_status) <> ''),
  reader_facing_effect boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  supersedes_intervention_id uuid references wnph.transmission_interventions(id),
  created_at timestamptz not null default now(),
  constraint transmission_interventions_supersedes_not_self check (supersedes_intervention_id is null or supersedes_intervention_id <> id)
);

comment on table wnph.transmission_interventions is
  'Critical/editorial apparatus at intervention granularity. A correction, normalization, reconstruction, retained reading, relocation or other decision may be recorded here while the clean canonical reading remains in publication_source_blocks/assets.';

create index transmission_agents_supersedes_idx on wnph.transmission_agents(supersedes_agent_id) where supersedes_agent_id is not null;
create index transmission_acts_case_idx on wnph.transmission_acts(recovery_case_id) where recovery_case_id is not null;
create index transmission_acts_work_idx on wnph.transmission_acts(work_id) where work_id is not null;
create index transmission_acts_supersedes_idx on wnph.transmission_acts(supersedes_act_id) where supersedes_act_id is not null;
create index transmission_act_agents_act_idx on wnph.transmission_act_agents(transmission_act_id);
create index transmission_act_agents_agent_idx on wnph.transmission_act_agents(agent_id);
create index transmission_act_agents_supersedes_idx on wnph.transmission_act_agents(supersedes_act_agent_id) where supersedes_act_agent_id is not null;
create index transmission_act_objects_act_idx on wnph.transmission_act_objects(transmission_act_id);
create index transmission_act_objects_expression_idx on wnph.transmission_act_objects(expression_id) where expression_id is not null;
create index transmission_act_objects_manifestation_idx on wnph.transmission_act_objects(manifestation_id) where manifestation_id is not null;
create index transmission_act_objects_item_idx on wnph.transmission_act_objects(item_id) where item_id is not null;
create index transmission_act_objects_surrogate_idx on wnph.transmission_act_objects(surrogate_id) where surrogate_id is not null;
create index transmission_act_objects_evidence_source_idx on wnph.transmission_act_objects(evidence_source_id) where evidence_source_id is not null;
create index transmission_act_objects_package_idx on wnph.transmission_act_objects(publication_source_package_id) where publication_source_package_id is not null;
create index transmission_act_objects_block_idx on wnph.transmission_act_objects(publication_source_block_id) where publication_source_block_id is not null;
create index transmission_act_objects_asset_idx on wnph.transmission_act_objects(publication_source_asset_id) where publication_source_asset_id is not null;
create index transmission_act_objects_derivation_idx on wnph.transmission_act_objects(publication_manifestation_derivation_id) where publication_manifestation_derivation_id is not null;
create index transmission_act_objects_decision_idx on wnph.transmission_act_objects(recovery_decision_id) where recovery_decision_id is not null;
create index transmission_act_objects_case_event_idx on wnph.transmission_act_objects(recovery_case_event_id) where recovery_case_event_id is not null;
create index transmission_act_objects_supersedes_idx on wnph.transmission_act_objects(supersedes_act_object_id) where supersedes_act_object_id is not null;
create index transmission_act_evidence_act_idx on wnph.transmission_act_evidence(transmission_act_id);
create index transmission_act_evidence_source_idx on wnph.transmission_act_evidence(source_id);
create index transmission_act_evidence_supersedes_idx on wnph.transmission_act_evidence(supersedes_act_evidence_id) where supersedes_act_evidence_id is not null;
create index transmission_interventions_act_idx on wnph.transmission_interventions(transmission_act_id);
create index transmission_interventions_supersedes_idx on wnph.transmission_interventions(supersedes_intervention_id) where supersedes_intervention_id is not null;

create trigger transmission_agents_append_only before update or delete on wnph.transmission_agents for each row execute function wnph.reject_append_only_mutation();
create trigger transmission_acts_append_only before update or delete on wnph.transmission_acts for each row execute function wnph.reject_append_only_mutation();
create trigger transmission_act_agents_append_only before update or delete on wnph.transmission_act_agents for each row execute function wnph.reject_append_only_mutation();
create trigger transmission_act_objects_append_only before update or delete on wnph.transmission_act_objects for each row execute function wnph.reject_append_only_mutation();
create trigger transmission_act_evidence_append_only before update or delete on wnph.transmission_act_evidence for each row execute function wnph.reject_append_only_mutation();
create trigger transmission_interventions_append_only before update or delete on wnph.transmission_interventions for each row execute function wnph.reject_append_only_mutation();

alter table wnph.transmission_agents enable row level security;
alter table wnph.transmission_acts enable row level security;
alter table wnph.transmission_act_agents enable row level security;
alter table wnph.transmission_act_objects enable row level security;
alter table wnph.transmission_act_evidence enable row level security;
alter table wnph.transmission_interventions enable row level security;

revoke all on wnph.transmission_agents, wnph.transmission_acts, wnph.transmission_act_agents, wnph.transmission_act_objects, wnph.transmission_act_evidence, wnph.transmission_interventions from public, anon, authenticated, service_role;

-- Seed only proven Dewy lineage events. No individual textual intervention is asserted yet.
do $$
declare
  v_case uuid;
  v_work uuid;
  v_expression uuid;
  v_item uuid;
  v_surrogate uuid;
  v_package uuid;
  v_loc_source uuid;
  v_ia_ocr_source uuid;
  v_ia_access_source uuid;
  v_commons_diagnostic_source uuid;
  v_decision uuid;
  v_selection_event uuid;
  v_loc_agent uuid;
  v_ia_agent uuid;
  v_wnph_agent uuid;
  v_digitization_act uuid;
  v_ocr_act uuid;
  v_package_act uuid;
begin
  select id,work_id into v_case,v_work
  from wnph.recovery_cases
  where canonical_key='wish-fairy-and-dewy-dear:recovery-evaluation-1';
  if v_case is null then raise exception 'WNPH transmission seed: Dewy recovery case not found'; end if;

  select id into v_expression from wnph.expressions where canonical_key='wish-fairy-dewy-dear:e1';
  select id into v_item from wnph.items where canonical_key='wish-fairy-dewy-dear:loc-item';
  select id into v_surrogate from wnph.surrogates where canonical_key='wish-fairy-dewy-dear:loc-digital';
  select id into v_package from wnph.publication_source_packages where canonical_key='wish-fairy-and-dewy-dear:canonical-publication-source:v1';
  select id into v_loc_source from wnph.evidence_sources where canonical_key='loc:item:22008427';
  select id into v_ia_ocr_source from wnph.evidence_sources where canonical_key='internet-archive:ia:wishfairydewydea00colv:djvu-text';
  select id into v_ia_access_source from wnph.evidence_sources where canonical_key='internet-archive:ia:wishfairydewydea00colv:image-derivative-access';
  select id into v_commons_diagnostic_source from wnph.evidence_sources where canonical_key='wikimedia-commons:ia:wishfairydewydea00colv:interior-color-plate-diagnostic';

  if v_expression is null or v_item is null or v_surrogate is null or v_package is null or v_loc_source is null or v_ia_ocr_source is null then
    raise exception 'WNPH transmission seed: Dewy governed lineage objects incomplete';
  end if;

  select d.id into v_decision
  from wnph.recovery_decisions d
  where d.recovery_case_id=v_case and d.decision_outcome='qualify'
    and not exists(select 1 from wnph.recovery_decisions n where n.supersedes_decision_id=d.id)
  order by d.created_at desc limit 1;

  select e.id into v_selection_event
  from wnph.recovery_case_events e
  where e.recovery_case_id=v_case and e.to_state='SELECTED_FOR_RECOVERY'
    and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
  order by e.created_at desc limit 1;

  insert into wnph.transmission_agents(canonical_key,agent_type,canonical_label,notes)
  values('library-of-congress:institution','institution','Library of Congress','Custodial institution and source repository for the governed Dewy exemplar/surrogate lineage.')
  returning id into v_loc_agent;

  insert into wnph.transmission_agents(canonical_key,agent_type,canonical_label,notes)
  values('internet-archive:institution','institution','Internet Archive','Access/derivative institution for the same governed LOC-derived witness; not an independent historical witness.')
  returning id into v_ia_agent;

  insert into wnph.transmission_agents(canonical_key,agent_type,canonical_label,notes)
  values('wnph:recovery-process','process','Write Now Publishing House recovery process','Governed recovery and single-source publication process.')
  returning id into v_wnph_agent;

  insert into wnph.transmission_acts(
    canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    'wish-fairy-dewy-dear:transmission:loc-item-to-digital-surrogate:v1',v_case,v_work,'digitization',
    'Create a digital surrogate of the Library of Congress-held exemplar.',
    'Governed result is the 72-image LOC page-image surrogate already registered in WNPH custody.',
    'documented','high',jsonb_build_object('historical_witness_count_delta',0,'content_change_asserted',false)
  ) returning id into v_digitization_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role)
  values(v_digitization_act,v_loc_agent,'custodial_digitization_repository');
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,item_id)
  values(v_digitization_act,'input','physical_exemplar',v_item);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id,locator)
  values(v_digitization_act,'output','digital_surrogate',v_surrogate,jsonb_build_object('image_count',72));
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_digitization_act,v_loc_source,'supports','high','LOC item record anchors the exemplar and governed digital surrogate provenance.');

  insert into wnph.transmission_acts(
    canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    'wish-fairy-dewy-dear:transmission:loc-surrogate-to-ia-ocr:v1',v_case,v_work,'ocr_derivation',
    'Produce a machine-readable OCR derivative from the same digitized witness.',
    'The Internet Archive DjVu text is an OCR/access derivative of the LOC/IA witness. It is not publication-ready and does not create a second historical witness.',
    'documented','high',jsonb_build_object('historical_witness_count_delta',0,'publication_ready',false)
  ) returning id into v_ocr_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role)
  values(v_ocr_act,v_ia_agent,'derivative_repository');
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id)
  values(v_ocr_act,'input','source_surrogate',v_surrogate);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,evidence_source_id)
  values(v_ocr_act,'output','machine_ocr_derivative',v_ia_ocr_source);
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_ocr_act,v_ia_ocr_source,'supports','high','IA DjVu text is the governed OCR derivative used only as a machine transcription aid.');
  if v_ia_access_source is not null then
    insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
    values(v_ocr_act,v_ia_access_source,'context','high','IA item/derivative access confirms same-source derivative availability.');
  end if;

  insert into wnph.transmission_acts(
    canonical_key,recovery_case_id,work_id,operation_type,purpose,method_note,epistemic_status,confidence,metadata
  ) values(
    'wish-fairy-dewy-dear:transmission:qualified-source-to-canonical-package:v1',v_case,v_work,'canonical_source_instantiation',
    'Instantiate WNPH''s manifestation-agnostic canonical publication source for the qualified combined text-and-illustration recovery plan.',
    'This act creates the governed package shell and binds its source lineage. It does not claim that verified text blocks or recovered illustration assets have yet been populated.',
    'system_recorded','certain',jsonb_build_object('content_population_completed',false,'manifestation_created',false)
  ) returning id into v_package_act;

  insert into wnph.transmission_act_agents(transmission_act_id,agent_id,agent_role)
  values(v_package_act,v_wnph_agent,'recovery_process');
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,expression_id)
  values(v_package_act,'input','qualified_expression',v_expression);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,surrogate_id)
  values(v_package_act,'input','preferred_historical_source',v_surrogate);
  insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,publication_source_package_id)
  values(v_package_act,'output','canonical_publication_source',v_package);
  if v_decision is not null then
    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,recovery_decision_id)
    values(v_package_act,'context','qualifying_recovery_decision',v_decision);
  end if;
  if v_selection_event is not null then
    insert into wnph.transmission_act_objects(transmission_act_id,direction,object_role,recovery_case_event_id)
    values(v_package_act,'context','selection_event',v_selection_event);
  end if;
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_package_act,v_loc_source,'supports','high','LOC source is the selected historical recovery basis for the canonical package.');
  if v_commons_diagnostic_source is not null then
    insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
    values(v_package_act,v_commons_diagnostic_source,'context','high','Completed illustration-source diagnostic constrains the recoverable illustration program and color claims.');
  end if;
  insert into wnph.transmission_act_evidence(transmission_act_id,source_id,support_role,confidence,note)
  values(v_package_act,v_ia_ocr_source,'context','high','OCR may seed transcription but is not itself canonical reading text.');

  if (select count(*) from wnph.transmission_acts where recovery_case_id=v_case and canonical_key like 'wish-fairy-dewy-dear:transmission:%') <> 3 then
    raise exception 'WNPH transmission seed: expected exactly three proven Dewy transmission acts';
  end if;
  if exists(select 1 from wnph.transmission_interventions ti join wnph.transmission_acts ta on ta.id=ti.transmission_act_id where ta.recovery_case_id=v_case) then
    raise exception 'WNPH transmission seed: no textual/editorial intervention may be fabricated in this kernel step';
  end if;
end $$;