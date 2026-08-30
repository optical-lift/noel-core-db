-- WNPH The Virginia House-Wife bounded existing-recovery audit and condition assessment v1.
-- Advances only from RECOVERY_AUDIT to CONDITION_ASSESSED.

insert into wnph.evidence_sources(canonical_key,source_type,title,repository_name,url,external_identifier,retrieved_at,provenance_note,metadata)
values
('uscpress:virginia-house-wife:2025','publisher_catalog','The Virginia House-wife, 200th Anniversary Edition','University of South Carolina Press','https://uscpress.com/book-post/The-Virginia-House-wife-updated-edition','9781643365510',now(),'Publisher record for the 2025 200th Anniversary Edition with Karen Hess commentary and Debra Freeman foreword. USC Press describes it as Karen Hess''s authoritative collated text of the first three editions and says it includes a complete facsimile of the original book plus additional recipes from the 1825 and 1828 editions. An open-access ebook is offered.',jsonb_build_object('publication_year',2025,'role','modern_scholarly_reading_edition','open_access_ebook',true)),
('andrews-mcmeel:virginia-housewife:2013','publisher_catalog','The Virginia Housewife: Or, Methodical Cook','Andrews McMeel Publishing','https://publishing.andrewsmcmeel.com/book/the-virginia-housewife/','9781449427467',now(),'Publisher record for a 2013 facsimile edition reproduced from a volume in the American Antiquarian Society collection. The publisher also offers a commercial ebook edition.',jsonb_build_object('publication_year',2013,'role','modern_facsimile_and_ebook','ebook_available',true))
on conflict(canonical_key) do nothing;

with old_audit as (
  select a.id
  from wnph.existing_recovery_audits a
  join wnph.recovery_cases c on c.id=a.recovery_case_id
  where c.canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
    and not exists(select 1 from wnph.existing_recovery_audits n where n.supersedes_audit_id=a.id)
), case_row as (
  select id from wnph.recovery_cases where canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
)
insert into wnph.existing_recovery_audits(recovery_case_id,audit_status,scope_note,supersedes_audit_id)
select case_row.id,'complete','Bounded audit completed 2026-08-30 across the LOC 1824 first-edition facsimile, Project Gutenberg later-edition text, current commercial facsimile/ebook, the 2025 University of South Carolina Press scholarly/open-access edition, and exact-title Standard Ebooks/LibriVox searches. The audit establishes that strong modern recovery already exists.',old_audit.id
from case_row,old_audit;

insert into wnph.existing_recovery_findings(audit_id,channel,availability_status,manifestation_type,competence_state,competing_identifier,notes)
select a.id,x.channel,x.availability,x.mtype,x.competence,x.identifier,x.notes
from wnph.existing_recovery_audits a
join wnph.recovery_cases c on c.id=a.recovery_case_id
cross join (values
('library_of_congress'::text,'present'::text,'FACSIMILE'::text,'raw'::text,'LCCN 73217897'::text,'The 1824 Washington first-edition exemplar survives with 244 page images/PDF access and exact copy-level identification.'::text),
('project_gutenberg','present','REFLOWABLE_EBOOK','partial','Project Gutenberg 12519','A public-domain reflowable text exists, but its rendered title page is the 1860 edition, so it cannot substitute for the governed 1824 first-edition witness.'),
('scholarly_or_critical_editions','present','CRITICAL_EDITION','competent','USC Press 200th Anniversary Edition (2025)','University of South Carolina Press describes the edition as Karen Hess''s authoritative collated text of the first three editions, with a complete facsimile of the original book and historical commentary.'),
('modern_commercial_ebook','present','REFLOWABLE_EBOOK','competent','Andrews McMeel ISBN 9781449427467 / ebook','A commercial ebook and facsimile edition has been available since 2013 from Andrews McMeel, sourced from an American Antiquarian Society volume.'),
('modern_print','present','RESTORED_EDITION','competent','USC Press ISBN 9781643365510','The 2025 200th Anniversary Edition provides a current scholarly print edition plus an open-access ebook, substantially closing ordinary modern-reading and contextual-recovery gaps.'),
('standard_ebooks','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching Standard Ebooks result; this is not an absence claim.'),
('librivox','uncertain',null,'unknown',null,'Bounded exact-title search on 2026-08-30 produced no matching LibriVox result; this is not an absence claim.')
) as x(channel,availability,mtype,competence,identifier,notes)
where c.canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and a.scope_note like 'Bounded audit completed 2026-08-30 across the LOC 1824 first-edition facsimile%';

insert into wnph.evidence_links(source_id,existing_recovery_finding_id,confidence,note)
select s.id,f.id,'high','Evidence supporting bounded existing-recovery audit finding.'
from wnph.existing_recovery_findings f
join wnph.existing_recovery_audits a on a.id=f.audit_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.evidence_sources s on s.canonical_key = case f.competing_identifier
  when 'LCCN 73217897' then 'loc:item:73217897'
  when 'Project Gutenberg 12519' then 'project-gutenberg:12519'
  when 'USC Press 200th Anniversary Edition (2025)' then 'uscpress:virginia-house-wife:2025'
  when 'Andrews McMeel ISBN 9781449427467 / ebook' then 'andrews-mcmeel:virginia-housewife:2013'
  when 'USC Press ISBN 9781643365510' then 'uscpress:virginia-house-wife:2025'
end
where c.canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
  and a.audit_status='complete'
  and f.competing_identifier is not null;

insert into wnph.recovery_condition_assessments(recovery_case_id,assessment_status,scope_note,confidence)
select id,'bounded_complete','Factual modern-recovery condition for the 1824 Work/first-edition target in light of strong current scholarly, facsimile, commercial ebook, and open-access recovery.','high'
from wnph.recovery_cases where canonical_key='virginia-house-wife:foundational-cookbook-recovery-1';

insert into wnph.recovery_condition_observations(assessment_id,condition_type_id,condition_state,epistemic_status,work_id,observation_text,confidence)
select a.id,t.id,x.state,x.epistemic,w.id,x.text,x.confidence
from wnph.recovery_condition_assessments a
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.historical_works w on w.id=c.work_id
cross join (values
('digital_facsimile_survival'::text,'adequate'::text,'evidence'::text,'The exact 1824 first-edition LOC exemplar survives digitally with 244 images/PDF access.'::text,'high'::text),
('identified_surviving_witness','adequate','evidence','The governed LOC first-edition item is specifically identified by LCCN 73217897 and call number TX715 .R215 1824.','high'),
('modern_reading_edition','adequate','evidence','A current scholarly modern edition exists: USC Press''s 2025 200th Anniversary Edition uses Karen Hess''s authoritative collated text of the first three editions and adds historical framing.','high'),
('reflowable_ebook_availability','adequate','evidence','Modern ebook access exists through Andrews McMeel and USC Press, including an open-access ebook pathway from USC Press.','high'),
('text_integrity','adequate','evidence','For general historical reading, the 2025 scholarly edition supplies an authoritative collated text and complete facsimile. Exact 1824-only diplomatic transcription remains a narrower different objective, not evidence of broad text-recovery failure.','high'),
('edition_relationship_clarity','adequate','evidence','The modern USC Press edition expressly collates the first three editions and distinguishes its historical components, while the bounded audit also separates the 1860 Gutenberg text from the 1824 first-edition source.','high'),
('accessibility','adequate','evidence','Current ebook/open-access availability provides strong ordinary modern digital access beyond raw facsimile scanning.','high'),
('modern_recovery_adequacy','adequate','interpretation','A basic recovery gap is not demonstrated. The Work already has strong modern scholarly, facsimile, print, ebook, and open-access recovery. Any WNPH involvement must be differentiated—such as exact first-edition provenance or functional historical semantics—rather than duplicating an already competent reading edition.','high')
) as x(type_key,state,epistemic,text,confidence)
join wnph.recovery_condition_types t on t.canonical_key=x.type_key and t.status='active'
where c.canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
  and a.assessment_status='bounded_complete'
  and a.scope_note like 'Factual modern-recovery condition for the 1824 Work/first-edition target%';

insert into wnph.evidence_links(source_id,recovery_condition_observation_id,confidence,note)
select s.id,o.id,o.confidence,'Evidence supporting bounded recovery-condition observation.'
from wnph.recovery_condition_observations o
join wnph.recovery_condition_assessments a on a.id=o.assessment_id
join wnph.recovery_cases c on c.id=a.recovery_case_id
join wnph.recovery_condition_types t on t.id=o.condition_type_id
join wnph.evidence_sources s on s.canonical_key = case t.canonical_key
  when 'digital_facsimile_survival' then 'loc:item:73217897'
  when 'identified_surviving_witness' then 'loc:item:73217897'
  when 'modern_reading_edition' then 'uscpress:virginia-house-wife:2025'
  when 'reflowable_ebook_availability' then 'uscpress:virginia-house-wife:2025'
  when 'text_integrity' then 'uscpress:virginia-house-wife:2025'
  when 'edition_relationship_clarity' then 'uscpress:virginia-house-wife:2025'
  when 'accessibility' then 'uscpress:virginia-house-wife:2025'
end
where c.canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'
  and o.epistemic_status='evidence';

with case_row as (select id from wnph.recovery_cases where canonical_key='virginia-house-wife:foundational-cookbook-recovery-1'),
leaf as (
  select e.id,e.to_state from wnph.recovery_case_events e,case_row c
  where e.recovery_case_id=c.id and not exists(select 1 from wnph.recovery_case_events n where n.prior_event_id=e.id)
)
insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
select c.id,l.id,'RECOVERY_AUDIT','CONDITION_ASSESSED','state_transition','Bounded audit is complete and establishes strong current recovery. WNPH must not manufacture a general recovery gap where a competent scholarly/open-access edition already exists.','wnph:virginia-housewife-condition-v1'
from case_row c,leaf l
where l.to_state='RECOVERY_AUDIT';