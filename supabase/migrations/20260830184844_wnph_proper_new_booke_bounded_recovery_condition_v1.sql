-- WNPH A Proper New Booke of Cookery bounded existing-recovery audit and condition assessment v1.
-- Advances only from RECOVERY_AUDIT to CONDITION_ASSESSED.

insert into wnph.evidence_sources(canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,provenance_note,metadata)
values
('folger:proper-newe-booke-frere:1913','library_catalog','A Proper newe booke of cokerye','Folger Shakespeare Library','https://catalog.folger.edu/record/2199','TX705 .P7 1913',now(),'Catalog record for Catherine Frances Frere''s 1913 edited edition with notes, introduction, glossary, bibliography, and facsimile title-page material. It is a scholarly recovery of the work tradition, not proof of exact identity with the governed 1575 witness.',jsonb_build_object('publication_year',1913,'editor','Catherine Frances Frere','role','scholarly_edition'))
on conflict(canonical_key) do nothing;

with old_audit as (
  select a.id
  from wnph.existing_recovery_audits a
  join wnph.recovery_cases c on c.id=a.recovery_case_id
  where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
    and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id)
), case_row as (
  select id from wnph.recovery_cases where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
)
insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note,supersedes_audit_id)
select case_row.id,'complete','Bounded audit completed 2026-08-30 across the 1575 facsimile, source-linked public transcription, known scholarly edition history, and exact-title Standard Ebooks/LibriVox searches. The audit distinguishes the governed 1575 witness from other sixteenth-century states and modern editions.',old_audit.id
from case_row,old_audit;

insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
select a.id,x.channel,x.availability,x.mtype,x.competence,x.identifier,x.notes
from wnph.existing_recovery_audits a
join wnph.recovery_cases c on c.id=a.recovery_case_id
cross join (values
('internet_archive'::text,'present'::text,'FACSIMILE'::text,'raw'::text,'bim_early-english-books-1475-1640_a-proper-new-booke-of-co_1575'::text,'A 33-page mechanical scan of the 1575 edition survives via Internet Archive/Commons. Page order and transcription still require WNPH verification.'::text),
('other','present','SEARCHABLE_TEXT','partial','Wikisource: A Proper New Booke of Cookery','A source-linked public transcription exists; proofread pages may still require validation, so it is comparison evidence rather than automatically canonical text.'),
('scholarly_or_critical_editions','present','CRITICAL_EDITION','competent','Catherine Frances Frere, 1913','Frere''s edited edition supplies notes, introduction, glossary, bibliography, and facsimile material. It is a competent historical recovery of the work tradition, but bounded evidence does not establish exact equivalence to the governed 1575 witness.'),
('standard_ebooks','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching Standard Ebooks result; uncertainty is retained rather than declaring absence.'),
('librivox','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching LibriVox result; uncertainty is retained rather than declaring absence.')
) as x(channel,availability,mtype,competence,identifier,notes)
where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and a.scope_note like 'Bounded audit completed 2026-08-30 across the 1575 facsimile%';

insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
select s.id,f.id,'high','Evidence supporting bounded existing-recovery audit finding.'
from wnph.existing_recovery_findings f
join wnph.existing_recovery_audits a on a.id=f.audit_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.evidence_sources s on s.canonical_key = case f.competing_identifier
  when 'bim_early-english-books-1475-1640_a-proper-new-booke-of-co_1575' then 'wikimedia-commons:proper-new-booke-cookery-1575'
  when 'Wikisource: A Proper New Booke of Cookery' then 'wikisource:proper-new-booke-of-cookery-1575'
  when 'Catherine Frances Frere, 1913' then 'folger:proper-newe-booke-frere:1913'
end
where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and f.competing_identifier is not null;

insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
select id,'bounded_complete','Factual modern-recovery condition for the governed 1575 witness, explicitly separated from earlier/later sixteenth-century states and from Frere''s later scholarly edition.','high'
from wnph.recovery_cases where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1';

insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
select a.id,t.id,x.state,x.epistemic,w.id,x.text,x.confidence
from wnph.recovery_condition_assessments a
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.historical_works w on w.id=c.work_id
cross join (values
('digital_facsimile_survival'::text,'adequate'::text,'evidence'::text,'The governed 1575 edition survives as a 33-page mechanical digital scan with identified IA/Commons provenance.'::text,'high'::text),
('identified_surviving_witness','adequate','evidence','The catalog/scan lineage identifies a specific 1575 edition tied to the British Library reproduction tradition and STC 3367.','high'),
('modern_reading_edition','limited','evidence','A modern scholarly edition exists and a public Wikisource text exists, but the bounded audit does not establish a fully validated modern reading edition of this exact 1575 witness.','high'),
('reflowable_ebook_availability','limited','evidence','Readable web transcription is available, but source validation remains incomplete and no bounded evidence established a polished exact-witness reflowable edition comparable to a modern editorial ebook.','medium'),
('text_integrity','unverified','evidence','The public transcription is not fully validated against the governed 1575 scan, so exact-witness text integrity remains unverified despite strong material access.','high'),
('edition_relationship_clarity','conflicted','interpretation','Multiple sixteenth-century states and later scholarly editions coexist. A recovery that silently mixes 1545/1550s/1575/1576 readings would erase historically meaningful edition differences.','high'),
('accessibility','limited','interpretation','The source is discoverable and readable online, but the exact 1575 witness does not yet have a boundedly verified accessible reading layer with source locators.','high'),
('modern_recovery_adequacy','limited','interpretation','The Work is not lost and has received scholarly attention, but the exact 1575 witness remains incompletely recovered as a verified, source-linked, accessible modern reading object.','high')
) as x(type_key,state,epistemic,text,confidence)
join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active'
where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
  and a.assessment_status='bounded_complete'
  and a.scope_note like 'Factual modern-recovery condition for the governed 1575 witness%';

insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
select s.id,o.id,o.confidence,'Evidence supporting bounded recovery-condition observation.'
from wnph.recovery_condition_observations o
join wnph.recovery_condition_assessments a on a.id=o.assessment_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.recovery_condition_types t on t.id=o.condition_type_id
join wnph.evidence_sources s on s.canonical_key = case t.canonical_key
  when 'digital_facsimile_survival' then 'wikimedia-commons:proper-new-booke-cookery-1575'
  when 'identified_surviving_witness' then 'heidelberg:1055289360'
  when 'modern_reading_edition' then 'folger:proper-newe-booke-frere:1913'
  when 'reflowable_ebook_availability' then 'wikisource:proper-new-booke-of-cookery-1575'
  when 'text_integrity' then 'wikisource:proper-new-booke-of-cookery-1575'
end
where c.canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'
  and o.epistemic_status='evidence';

with case_row as (select id from wnph.recovery_cases where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1'),
leaf as (
  select e.id,e.to_state from wnph.recovery_case_events e,case_row c
  where e.recovery_case_id=c.id and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
)
insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
select c.id,l.id,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition','Bounded audit is complete and identifies a narrow exact-witness recovery condition rather than a generic claim that the Work is unavailable.','wnph:proper-new-booke-condition-v1'
from case_row c,leaf l
where l.to_state='RECOVERY_AUDIT';