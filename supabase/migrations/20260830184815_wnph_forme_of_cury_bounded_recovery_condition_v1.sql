-- WNPH Forme of Cury bounded existing-recovery audit and condition assessment v1.
-- Advances only from RECOVERY_AUDIT to CONDITION_ASSESSED.

insert into wnph.evidence_sources(canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,provenance_note,metadata)
values
('cambridge:9781108076203','publisher_catalog','The Forme of Cury, a Roll of Ancient English Cookery','Cambridge University Press','https://www.cambridge.org/9781108076203','9781108076203',now(),'Cambridge Library Collection digitally printed reproduction of Samuel Pegge''s 1780 edition; Cambridge states the 2015 printing reproduces the text of the original edition without updating its content or language.',jsonb_build_object('publication_year',2015,'historical_edition_year',1780,'role','modern_reprint')),
('folger:curye-on-inglysch:1985','library_catalog','Curye on Inglysch: English culinary manuscripts of the fourteenth century (including the Forme of cury)','Folger Shakespeare Library','https://catalog.folger.edu/record/44798','PR1119 .S8 no.08',now(),'Catalog record for the Constance B. Hieatt and Sharon Butler critical edition, published for the Early English Text Society by Oxford University Press in 1985; includes The Forme of Cury and multiple fourteenth-century culinary manuscript witnesses.',jsonb_build_object('publication_year',1985,'publisher','Oxford University Press for EETS','isbn','0197224091','role','critical_edition'))
on conflict(canonical_key) do nothing;

with old_audit as (
  select a.id
  from wnph.existing_recovery_audits a
  join wnph.recovery_cases c on c.id=a.recovery_case_id
  where c.canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
    and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id)
), case_row as (
  select id from wnph.recovery_cases where canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
)
insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note,supersedes_audit_id)
select case_row.id,'complete','Bounded audit completed 2026-08-30 across the governed facsimile, public transcription/reflow channels, modern scholarly/critical editions, current print reprints, and exact-title searches of Standard Ebooks and LibriVox. No exact Standard Ebooks or LibriVox match was found in the bounded search; those channels are recorded uncertain rather than absent.',old_audit.id
from case_row,old_audit;

insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
select a.id,x.channel,x.availability,x.mtype,x.competence,x.identifier,x.notes
from wnph.existing_recovery_audits a
join wnph.recovery_cases c on c.id=a.recovery_case_id
cross join (values
('library_of_congress'::text,'present'::text,'FACSIMILE'::text,'raw'::text,'LCCN 44031282'::text,'244-image/PDF digitization of Pegge''s 1780 editorial witness; material access is strong, but it is not a direct medieval manuscript surrogate.'::text),
('project_gutenberg','present','REFLOWABLE_EBOOK','partial','Project Gutenberg 8102','Free reflowable transcription of Pegge''s editorial text exists; it does not replace manuscript-level textual criticism or WNPH page-image verification.'),
('scholarly_or_critical_editions','present','CRITICAL_EDITION','competent','Curye on Inglysch, EETS SS 8 (1985)','Hieatt and Butler provide a modern critical edition drawing on multiple medieval culinary manuscripts, including The Forme of Cury. A competent scholarly recovery exists.'),
('modern_print','present','PRINT_REPRINT','competent','Cambridge ISBN 9781108076203','Cambridge keeps Pegge''s 1780 edition available as a modern digitally printed reproduction without updating its language or content.'),
('standard_ebooks','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching Standard Ebooks catalog result. This is not an absence claim.'),
('librivox','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching LibriVox catalog result. This is not an absence claim.')
) as x(channel,availability,mtype,competence,identifier,notes)
where c.canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and a.scope_note like 'Bounded audit completed 2026-08-30 across the governed facsimile%';

insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
select s.id,f.id,'high','Evidence supporting bounded existing-recovery audit finding.'
from wnph.existing_recovery_findings f
join wnph.existing_recovery_audits a on a.id=f.audit_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.evidence_sources s on s.canonical_key = case f.competing_identifier
  when 'LCCN 44031282' then 'loc:item:44031282'
  when 'Project Gutenberg 8102' then 'project-gutenberg:8102'
  when 'Curye on Inglysch, EETS SS 8 (1985)' then 'folger:curye-on-inglysch:1985'
  when 'Cambridge ISBN 9781108076203' then 'cambridge:9781108076203'
end
where c.canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and f.competing_identifier is not null;

insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
select id,'bounded_complete','Factual condition of modern recovery for the governed 1780 Pegge witness and the broader Forme of Cury textual tradition. The assessment distinguishes general scholarly adequacy from open, source-linked, accessible reflow and from direct medieval manuscript custody.','high'
from wnph.recovery_cases where canonical_key='forme-of-cury:foundational-cookbook-recovery-1';

insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
select a.id,t.id,x.state,x.epistemic,w.id,x.text,x.confidence
from wnph.recovery_condition_assessments a
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.historical_works w on w.id=c.work_id
cross join (values
('digital_facsimile_survival'::text,'adequate'::text,'evidence'::text,'A specifically identified 1780 Pegge exemplar survives digitally at LOC with 244 page images/PDF access.'::text,'high'::text),
('identified_surviving_witness','adequate','evidence','The LOC item gives a specifically identified surviving historical publication witness for Pegge''s 1780 editorial manifestation.','high'),
('modern_reading_edition','adequate','evidence','A competent modern scholarly reading/critical edition exists in Hieatt and Butler''s Curye on Inglysch, while Cambridge also keeps the 1780 Pegge edition in print.','high'),
('reflowable_ebook_availability','limited','evidence','Project Gutenberg supplies a reflowable Pegge-lineage text, but the strongest modern critical recovery is not equivalent to that freely reflowable transcription and the manuscript relationship is not carried through as a source-linked reading layer.','high'),
('text_integrity','conflicted','interpretation','The recovery problem is not simple absence of text: Pegge''s 1780 transcription, later reflowable derivatives, and the multi-manuscript Hieatt/Butler critical edition represent materially different textual bases. WNPH must choose and name its witness/expression before claiming textual recovery.','high'),
('edition_relationship_clarity','limited','evidence','Modern scholarship explicitly treats The Forme of Cury within a multi-manuscript fourteenth-century culinary tradition; the 1780 Pegge publication is therefore an editorial witness, not the whole textual tradition.','high'),
('accessibility','limited','interpretation','Open reflowable access exists, but a source-linked modern reading layer that simultaneously preserves witness identity, critical variants, and reader accessibility is not established by the bounded audit.','medium'),
('modern_recovery_adequacy','limited','interpretation','Modern scholarly recovery is competent, so WNPH cannot claim the Work is simply unrecovered. The remaining condition is narrower: source-linked open reading/accessibility and explicit witness-to-reading provenance are limited.','high')
) as x(type_key,state,epistemic,text,confidence)
join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active'
where c.canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
  and a.assessment_status='bounded_complete'
  and a.scope_note like 'Factual condition of modern recovery for the governed 1780 Pegge witness%';

insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
select s.id,o.id,o.confidence,'Evidence supporting bounded recovery-condition observation.'
from wnph.recovery_condition_observations o
join wnph.recovery_condition_assessments a on a.id=o.assessment_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.recovery_condition_types t on t.id=o.condition_type_id
join wnph.evidence_sources s on s.canonical_key = case t.canonical_key
  when 'digital_facsimile_survival' then 'loc:item:44031282'
  when 'identified_surviving_witness' then 'loc:item:44031282'
  when 'modern_reading_edition' then 'folger:curye-on-inglysch:1985'
  when 'reflowable_ebook_availability' then 'project-gutenberg:8102'
  when 'edition_relationship_clarity' then 'folger:curye-on-inglysch:1985'
end
where c.canonical_key='forme-of-cury:foundational-cookbook-recovery-1'
  and o.epistemic_status='evidence';

with case_row as (select id from wnph.recovery_cases where canonical_key='forme-of-cury:foundational-cookbook-recovery-1'),
leaf as (
  select e.id,e.to_state from wnph.recovery_case_events e,case_row c
  where e.recovery_case_id=c.id and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
)
insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
select c.id,l.id,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition','Bounded recovery audit is complete and the remaining factual conditions are recorded without presuming that a new WNPH edition is warranted.','wnph:forme-of-cury-condition-v1'
from case_row c,leaf l
where l.to_state='RECOVERY_AUDIT';