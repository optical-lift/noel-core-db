-- WNPH Maria Rundell / A New System of Domestic Cookery bounded existing-recovery audit and condition assessment v1.
-- Advances only from RECOVERY_AUDIT to CONDITION_ASSESSED.

insert into wnph.evidence_sources(canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,provenance_note,metadata)
values
('google-books:rundell-creative-media-partners-2018','publisher_catalog_aggregation','A New System of Domestic Cookery: Formed Upon Principles of Economy and Adapted to the Use of Private Families','Google Books','https://books.google.com/books?id=EgrRswEACAAJ','9781297600623',now(),'Google Books metadata for a 2018 Creative Media Partners reproduction marketed as a historical-artifact reprint; the publisher warns that reproduced artifacts may contain missing or blurred pages, poor pictures, and errant marks.',jsonb_build_object('publication_year',2018,'publisher','Creative Media Partners, LLC','role','modern_facsimile_reprint'))
on conflict(canonical_key) do nothing;

with old_audit as (
  select a.id
  from wnph.existing_recovery_audits a
  join wnph.recovery_cases c on c.id=a.recovery_case_id
  where c.canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
    and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id)
), case_row as (
  select id from wnph.recovery_cases where canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
)
insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note,supersedes_audit_id)
select case_row.id,'complete','Bounded audit completed 2026-08-30 across the exact 1807 IA/LOC-derived facsimile, Project Gutenberg reflowable edition, modern artifact-reprint market, later historical editions, and exact-title Standard Ebooks/LibriVox searches. This audit is sufficient to reject any simplistic claim that no modern ebook/text access exists.',old_audit.id
from case_row,old_audit;

insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
select a.id,x.channel,x.availability,x.mtype,x.competence,x.identifier,x.notes
from wnph.existing_recovery_audits a
join wnph.recovery_cases c on c.id=a.recovery_case_id
cross join (values
('internet_archive'::text,'present'::text,'FACSIMILE'::text,'raw'::text,'newsystemofdomes01rund'::text,'The exact 1807 Boston exemplar is available with PDF, page-image derivatives, OCR, full text and related formats; WNPH has not yet completed page-level collation.'::text),
('project_gutenberg','present','REFLOWABLE_EBOOK','competent','Project Gutenberg 69519','A modern free EPUB3/plain-text/HTML reading edition of the 1807 Boston publication exists. The transcriber explicitly made silent corrections, so it is competent for reading but not automatically a diplomatic source text.'),
('modern_print','present','PRINT_REPRINT','partial','Creative Media Partners ISBN 9781297600623','Modern print-on-demand artifact reproduction exists, but the publisher warns that reproduced artifacts may contain missing or blurred pages and errant marks.'),
('scholarly_or_critical_editions','uncertain',null,'unknown',null,'Bounded search found abundant historical editions and modern reproductions but did not establish a dedicated current critical edition of the exact 1807 American witness. This is recorded as uncertain, not absent.'),
('standard_ebooks','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching Standard Ebooks result; no absence claim is made.'),
('librivox','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching LibriVox result; no absence claim is made.')
) as x(channel,availability,mtype,competence,identifier,notes)
where c.canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and a.scope_note like 'Bounded audit completed 2026-08-30 across the exact 1807 IA/LOC-derived facsimile%';

insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
select s.id,f.id,case when f.competing_identifier='Creative Media Partners ISBN 9781297600623' then 'medium' else 'high' end,'Evidence supporting bounded existing-recovery audit finding.'
from wnph.existing_recovery_findings f
join wnph.existing_recovery_audits a on a.id=f.audit_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.evidence_sources s on s.canonical_key = case f.competing_identifier
  when 'newsystemofdomes01rund' then 'internet-archive:newsystemofdomes01rund'
  when 'Project Gutenberg 69519' then 'project-gutenberg:69519'
  when 'Creative Media Partners ISBN 9781297600623' then 'google-books:rundell-creative-media-partners-2018'
end
where c.canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and f.competing_identifier is not null;

insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
select id,'bounded_complete','Factual condition of modern access to the exact 1807 Boston witness. The assessment expressly distinguishes strong modern reading access from source-image verification and from later edition changes.','high'
from wnph.recovery_cases where canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1';

insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
select a.id,t.id,x.state,x.epistemic,w.id,x.text,x.confidence
from wnph.recovery_condition_assessments a
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.historical_works w on w.id=c.work_id
cross join (values
('digital_facsimile_survival'::text,'adequate'::text,'evidence'::text,'The exact 1807 Boston witness survives in a richly downloadable Internet Archive/LOC-derived digital surrogate.'::text,'high'::text),
('identified_surviving_witness','adequate','evidence','The IA identifier newsystemofdomes01rund and matching library metadata identify the specific 1807 recovery witness.','high'),
('modern_reading_edition','adequate','evidence','Project Gutenberg 69519 is a competent modern reading edition explicitly produced from Internet Archive images of the 1807 publication.','high'),
('reflowable_ebook_availability','adequate','evidence','Project Gutenberg provides EPUB3, plain text, HTML and older-reader formats for the 1807 text. A basic reflowable-ebook gap therefore does not exist.','high'),
('text_integrity','limited','evidence','The modern transcription is highly usable but includes documented silent corrections, and WNPH has not yet collated every reading back to the page images. Exact diplomatic integrity is therefore more limited than general reading quality.','high'),
('edition_relationship_clarity','limited','interpretation','Rundell''s book proliferated through many revised editions. The exact 1807 American witness is identifiable, but later digital and print copies cannot be treated as interchangeable without edition-level adjudication.','high'),
('accessibility','adequate','evidence','Plain text and EPUB3 are readily available for the 1807 text, giving strong basic digital accessibility.','high'),
('modern_recovery_adequacy','adequate','interpretation','For ordinary reading and ebook access, modern recovery is already adequate. Any WNPH work would need a narrower value proposition such as explicit source verification, edition provenance, or functional historical translation; basic text recovery alone is not a demonstrated gap.','high')
) as x(type_key,state,epistemic,text,confidence)
join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active'
where c.canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
  and a.assessment_status='bounded_complete'
  and a.scope_note like 'Factual condition of modern access to the exact 1807 Boston witness%';

insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
select s.id,o.id,o.confidence,'Evidence supporting bounded recovery-condition observation.'
from wnph.recovery_condition_observations o
join wnph.recovery_condition_assessments a on a.id=o.assessment_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.recovery_condition_types t on t.id=o.condition_type_id
join wnph.evidence_sources s on s.canonical_key = case t.canonical_key
  when 'digital_facsimile_survival' then 'internet-archive:newsystemofdomes01rund'
  when 'identified_surviving_witness' then 'internet-archive:newsystemofdomes01rund'
  when 'modern_reading_edition' then 'project-gutenberg:69519'
  when 'reflowable_ebook_availability' then 'project-gutenberg:69519'
  when 'text_integrity' then 'project-gutenberg:69519'
  when 'accessibility' then 'project-gutenberg:69519'
end
where c.canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'
  and o.epistemic_status='evidence';

with case_row as (select id from wnph.recovery_cases where canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1'),
leaf as (
  select e.id,e.to_state from wnph.recovery_case_events e,case_row c
  where e.recovery_case_id=c.id and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
)
insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
select c.id,l.id,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition','Bounded audit is complete and demonstrates strong existing modern reading recovery; any WNPH recovery decision must therefore justify a narrower source/provenance/functional need.','wnph:rundell-condition-v1'
from case_row c,leaf l
where l.to_state='RECOVERY_AUDIT';