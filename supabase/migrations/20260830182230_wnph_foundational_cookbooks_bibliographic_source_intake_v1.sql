-- WNPH foundational public-domain cookbook intake v1.
-- Establishes bibliographic/source custody and opens Recovery Work only through SOURCE_RESEARCH.
-- It deliberately does not normalize recipes, select a publication Expression, or expose an Atlas cookbook API.

insert into wnph.evidence_sources (
  canonical_key, source_type, title, repository_name, url, external_identifier, retrieved_at, rights_note, provenance_note, metadata
) values
(
  'loc:item:44031282', 'library_catalog_and_digital_surrogate',
  'The forme of cury', 'Library of Congress', 'https://www.loc.gov/item/44031282/', '44031282', now(),
  'Library of Congress states it is not aware of U.S. copyright or other restrictions in the documents in this collection; downstream rights determination remains component-specific.',
  'LOC catalog record and 244-image digital access for Samuel Pegge''s 1780 London edition of the medieval cookery roll.',
  jsonb_build_object('manifestation_year',1780,'image_count',244,'publisher','J. Nichols','publication_place','London')
),
(
  'wikimedia-commons:proper-new-booke-cookery-1575', 'digital_surrogate_record',
  'A Proper New Booke of Cookery (1575).djvu', 'Wikimedia Commons',
  'https://commons.wikimedia.org/wiki/File:A_Proper_New_Booke_of_Cookery_(1575).djvu',
  'bim_early-english-books-1475-1640_a-proper-new-booke-of-co_1575', now(),
  'Commons marks the file as a public-domain mechanical scan of a public-domain original and applies Public Domain Mark 1.0.',
  '33-page DjVu imported from Internet Archive source IA40313011-55; source record identifies the 1575 edition.',
  jsonb_build_object('manifestation_year',1575,'image_count',33,'internet_archive_source','IA40313011-55')
),
(
  'heidelberg:1055289360', 'library_catalog',
  'A proper new booke of cookery: 1575', 'Heidelberg University Library catalog',
  'https://katalog.ub.uni-heidelberg.de/titel/1055289360', '1055289360', now(), null,
  'Catalog record identifies the 1575 London edition, William How for Abraham Veale, [32] pages, STC 3367, as a reproduction of the original in the British Library.',
  jsonb_build_object('stc','3367','extent','[32] p','holding_institution','British Library')
),
(
  'openlibrary:OL6996342M', 'library_catalog_and_digital_surrogate',
  'A new system of domestic cookery', 'Open Library / Internet Archive',
  'https://openlibrary.org/books/OL6996342M/A_new_system_of_domestic_cookery', 'OL6996342M', now(), null,
  'Catalog record for the 1807 Boston William Andrews edition; identifies Internet Archive item newsystemofdomes01rund, LCCN 08013208, OCLC 5472310, and 296-page extent.',
  jsonb_build_object('manifestation_year',1807,'internet_archive_identifier','newsystemofdomes01rund','lccn','08013208','oclc','5472310')
),
(
  'project-gutenberg:69519', 'public_domain_transcription',
  'New system of domestic cookery, formed upon principles of economy, and adapted to the use of private families', 'Project Gutenberg',
  'https://www.gutenberg.org/ebooks/69519', '69519', now(),
  'Project Gutenberg marks eBook 69519 public domain in the USA.',
  'Public-domain transcription credited as produced from images made available by Internet Archive; original publication stated as William Andrews, Boston, 1807. It is an access derivative, not an independent historical witness.',
  jsonb_build_object('manifestation_year',1807,'derivative_role','transcription_access_derivative')
),
(
  'loc:item:73217897', 'library_catalog_and_digital_surrogate',
  'The Virginia house-wife', 'Library of Congress', 'https://www.loc.gov/item/73217897/', '73217897', now(),
  'Library of Congress states it is not aware of U.S. copyright or other restrictions in the documents in this collection; downstream rights determination remains component-specific.',
  'LOC catalog record and 244-image digital access for the 1824 Washington first-edition manifestation printed by Davis and Force.',
  jsonb_build_object('manifestation_year',1824,'image_count',244,'call_number','TX715 .R215 1824','publisher','Davis and Force','publication_place','Washington')
),
(
  'project-gutenberg:8102', 'public_domain_transcription',
  'The Forme of Cury: A Roll of Ancient English Cookery Compiled, about A.D. 1390', 'Project Gutenberg',
  'https://www.gutenberg.org/ebooks/8102', '8102', now(),
  'Project Gutenberg marks eBook 8102 public domain in the USA.',
  'Modern public-domain transcription of Samuel Pegge''s editorial presentation; retained for later recovery-audit comparison, not treated as an independent medieval witness.',
  jsonb_build_object('derivative_role','transcription_access_derivative')
),
(
  'project-gutenberg:12519', 'public_domain_transcription',
  'The Virginia Housewife; Or, Methodical Cook', 'Project Gutenberg',
  'https://www.gutenberg.org/ebooks/12519', '12519', now(),
  'Project Gutenberg marks eBook 12519 public domain in the USA.',
  'Public-domain electronic text retained for later recovery-audit comparison. It is not substituted for the LOC 1824 first-edition source image witness.',
  jsonb_build_object('derivative_role','transcription_access_derivative')
)
on conflict (canonical_key) do nothing;

do $$
declare
  v_forme_work uuid; v_proper_work uuid; v_rundell_work uuid; v_randolph_work uuid;
  v_forme_creator uuid; v_rundell_creator uuid; v_randolph_creator uuid;
  v_forme_src uuid; v_proper_src uuid; v_proper_catalog_src uuid; v_rundell_src uuid; v_rundell_pg_src uuid; v_randolph_src uuid;
  v_forme_manifest uuid; v_proper_manifest uuid; v_rundell_manifest uuid; v_randolph_manifest uuid;
  v_forme_item uuid; v_proper_item uuid; v_rundell_item uuid; v_randolph_item uuid;
  v_forme_surrogate uuid; v_proper_surrogate uuid; v_rundell_surrogate uuid; v_randolph_surrogate uuid;
  v_app uuid; v_att uuid; v_adj uuid; v_claim uuid;
  v_case_forme uuid; v_case_proper uuid; v_case_rundell uuid; v_case_randolph uuid;
  v_event uuid; v_cluster uuid;
begin
  select id into strict v_forme_src from wnph.evidence_sources where canonical_key='loc:item:44031282';
  select id into strict v_proper_src from wnph.evidence_sources where canonical_key='wikimedia-commons:proper-new-booke-cookery-1575';
  select id into strict v_proper_catalog_src from wnph.evidence_sources where canonical_key='heidelberg:1055289360';
  select id into strict v_rundell_src from wnph.evidence_sources where canonical_key='openlibrary:OL6996342M';
  select id into strict v_rundell_pg_src from wnph.evidence_sources where canonical_key='project-gutenberg:69519';
  select id into strict v_randolph_src from wnph.evidence_sources where canonical_key='loc:item:73217897';

  insert into wnph.creator_authorities(canonical_key,preferred_label,creator_type,status,identity_confidence,notes)
  values('master-cooks-of-richard-ii','Master cooks of Richard II','collective_traditional_attribution','established','medium',
    'Collective traditional attribution carried by the Forme of Cury source tradition; this authority does not imply individually identified persons.')
  on conflict (canonical_key) do nothing;
  select id into strict v_forme_creator from wnph.creator_authorities where canonical_key='master-cooks-of-richard-ii';
  select id into strict v_rundell_creator from wnph.creator_authorities where canonical_key='maria-rundell';
  select id into strict v_randolph_creator from wnph.creator_authorities where canonical_key='mary-randolph';

  insert into wnph.historical_works(canonical_key,canonical_label,work_type,language_code,status,identity_confidence,notes) values
  ('forme-of-cury','The Forme of Cury','cookery_collection','enm','established','high',
    'Historical Work is the medieval cookery collection conventionally dated about 1390. Samuel Pegge''s 1780 edition is a later editorial manifestation and is not collapsed into the medieval Work.'),
  ('proper-new-booke-of-cookery','A Proper New Booke of Cookery','cookbook','en','established','high',
    'Historical Work represented here by the early printed cookery-book tradition. The current governed source intake is the 1575 London edition; this row does not claim that 1575 is the first textual state.'),
  ('new-system-of-domestic-cookery','A New System of Domestic Cookery','cookbook','en','established','high',
    'Maria Rundell historical Work. Current source intake is the 1807 Boston William Andrews manifestation; Work-level first-publication dating remains separately adjudicable.'),
  ('virginia-house-wife','The Virginia House-Wife','cookbook','en','established','high',
    'Mary Randolph historical Work. Current source intake anchors the 1824 Washington Davis and Force manifestation.')
  on conflict (canonical_key) do nothing;

  select id into strict v_forme_work from wnph.historical_works where canonical_key='forme-of-cury';
  select id into strict v_proper_work from wnph.historical_works where canonical_key='proper-new-booke-of-cookery';
  select id into strict v_rundell_work from wnph.historical_works where canonical_key='new-system-of-domestic-cookery';
  select id into strict v_randolph_work from wnph.historical_works where canonical_key='virginia-house-wife';

  if not exists(select 1 from wnph.work_creator_credits where work_id=v_forme_work and creator_id=v_forme_creator and supersedes_credit_id is null) then
    insert into wnph.work_creator_credits(work_id,creator_id,role,credit_status,notes)
    values(v_forme_work,v_forme_creator,'compiler','traditional_attribution',
      'LOC title describes the roll as compiled about 1390 by the master-cooks of King Richard II. This is carried as a collective traditional attribution, not modern individual authorship.');
  end if;
  if not exists(select 1 from wnph.work_creator_credits where work_id=v_rundell_work and creator_id=v_rundell_creator and supersedes_credit_id is null) then
    insert into wnph.work_creator_credits(work_id,creator_id,role,credit_status,notes)
    values(v_rundell_work,v_rundell_creator,'author','established','Maria Eliza Ketelby Rundell is identified by Project Gutenberg and library catalog authority for this Work.');
  end if;
  if not exists(select 1 from wnph.work_creator_credits where work_id=v_randolph_work and creator_id=v_randolph_creator and supersedes_credit_id is null) then
    insert into wnph.work_creator_credits(work_id,creator_id,role,credit_status,notes)
    values(v_randolph_work,v_randolph_creator,'author','established','Library of Congress identifies Mary Randolph, 1762-1828, as creator of The Virginia house-wife.');
  end if;

  insert into wnph.appellations(value,kind,language_code,normalized_value) values('The forme of cury','title','en','the forme of cury') returning id into v_app;
  insert into wnph.appellation_attestations(appellation_id,source_id,observed_value,observed_context,source_locator,notes)
  values(v_app,v_forme_src,'The forme of cury','LOC item title','catalog title','1780 publication title carries the historical Work title and medieval compilation statement.') returning id into v_att;
  insert into wnph.work_identity_adjudications(left_attestation_id,result_work_id,result,rationale,confidence,recorded_by)
  values(v_att,v_forme_work,'ESTABLISHES_WORK','The LOC-attested title and description establish the bibliographic identity of the medieval cookery Work while keeping Pegge''s 1780 editorial embodiment distinct.','high','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.appellations(value,kind,language_code,normalized_value) values('A proper new booke of cookery','title','en','a proper new booke of cookery') returning id into v_app;
  insert into wnph.appellation_attestations(appellation_id,source_id,observed_value,observed_context,source_locator,notes)
  values(v_app,v_proper_catalog_src,'A proper new booke of cookery','Heidelberg/EEBO catalog title','catalog title','Catalog identifies the 1575 edition as an edition of A propre new booke of cokery.') returning id into v_att;
  insert into wnph.work_identity_adjudications(left_attestation_id,result_work_id,result,rationale,confidence,recorded_by)
  values(v_att,v_proper_work,'ESTABLISHES_WORK','The catalog-attested 1575 title establishes the Work identity for recovery intake without asserting that the 1575 state is the earliest textual state.','high','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.appellations(value,kind,language_code,normalized_value) values('New system of domestic cookery, formed upon principles of economy, and adapted to the use of private families','title','en','new system of domestic cookery formed upon principles of economy and adapted to the use of private families') returning id into v_app;
  insert into wnph.appellation_attestations(appellation_id,source_id,observed_value,observed_context,source_locator,notes)
  values(v_app,v_rundell_pg_src,'New system of domestic cookery, formed upon principles of economy, and adapted to the use of private families','Project Gutenberg title and 1807 title page','ebook/catalog title','PG identifies Maria Eliza Ketelby Rundell and the 1807 William Andrews publication.') returning id into v_att;
  insert into wnph.work_identity_adjudications(left_attestation_id,result_work_id,result,rationale,confidence,recorded_by)
  values(v_att,v_rundell_work,'ESTABLISHES_WORK','The public-domain transcription and matching library catalog establish the Work identity used for recovery intake.','high','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.appellations(value,kind,language_code,normalized_value) values('The Virginia house-wife','title','en','the virginia house-wife') returning id into v_app;
  insert into wnph.appellation_attestations(appellation_id,source_id,observed_value,observed_context,source_locator,notes)
  values(v_app,v_randolph_src,'The Virginia house-wife','LOC item title','catalog title','LOC 1824 record identifies Mary Randolph and the Washington Davis and Force publication.') returning id into v_att;
  insert into wnph.work_identity_adjudications(left_attestation_id,result_work_id,result,rationale,confidence,recorded_by)
  values(v_att,v_randolph_work,'ESTABLISHES_WORK','The LOC-attested 1824 title and creator record establish the Work identity used for recovery intake.','high','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.manifestations(canonical_key,publisher_name,publication_place,publication_statement,extent_statement,format_statement,status,notes) values
  ('forme-of-cury:pegge-london-1780','J. Nichols','London','London : Printed by J. Nichols, printer to the Society of Antiquaries, 1780',null,'printed book','established','Samuel Pegge editorial publication of the medieval roll; source basis is LOC item 44031282.'),
  ('proper-new-booke-of-cookery:london-how-veale-1575','William How for Abraham Veale','London','Imprinted at London in Fleetstreete, by William How for Abraham Veale, 1575','[32] p','printed book','established','1575 edition; Heidelberg/EEBO record says reproduction of the original in the British Library, STC 3367.'),
  ('new-system-of-domestic-cookery:boston-andrews-1807','William Andrews','Boston','Boston : Published by William Andrews, 1807','3 p. l., xx, 296 p.','printed book','established','1807 Boston manifestation matching Open Library OL6996342M / IA newsystemofdomes01rund and Project Gutenberg 69519.'),
  ('virginia-house-wife:washington-davis-force-1824','Davis and Force','Washington','Washington : Printed by Davis and Force, 1824','225 p. ; 18 cm.','printed book','established','1824 LOC manifestation, item 73217897.')
  on conflict (canonical_key) do nothing;

  select id into strict v_forme_manifest from wnph.manifestations where canonical_key='forme-of-cury:pegge-london-1780';
  select id into strict v_proper_manifest from wnph.manifestations where canonical_key='proper-new-booke-of-cookery:london-how-veale-1575';
  select id into strict v_rundell_manifest from wnph.manifestations where canonical_key='new-system-of-domestic-cookery:boston-andrews-1807';
  select id into strict v_randolph_manifest from wnph.manifestations where canonical_key='virginia-house-wife:washington-davis-force-1824';

  if not exists(select 1 from wnph.work_manifestations where work_id=v_forme_work and manifestation_id=v_forme_manifest and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes) values(v_forme_work,v_forme_manifest,'editorial_manifestation_of','established','high','1780 Pegge edition embodies an editorial presentation of the medieval Work; Expression-level equivalence is intentionally unresolved at intake.');
  end if;
  if not exists(select 1 from wnph.work_manifestations where work_id=v_proper_work and manifestation_id=v_proper_manifest and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes) values(v_proper_work,v_proper_manifest,'manifestation_of','established','high','1575 printed manifestation; relationship to earlier textual states remains available for later expression/transmission adjudication.');
  end if;
  if not exists(select 1 from wnph.work_manifestations where work_id=v_rundell_work and manifestation_id=v_rundell_manifest and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes) values(v_rundell_work,v_rundell_manifest,'manifestation_of','established','high','1807 Boston manifestation of Rundell''s Work; no claim yet that this is the preferred recovery Expression.');
  end if;
  if not exists(select 1 from wnph.work_manifestations where work_id=v_randolph_work and manifestation_id=v_randolph_manifest and supersedes_relationship_id is null) then
    insert into wnph.work_manifestations(work_id,manifestation_id,relationship_type,status,confidence,notes) values(v_randolph_work,v_randolph_manifest,'manifestation_of','established','high','1824 Washington manifestation of Randolph''s Work.');
  end if;

  insert into wnph.items(canonical_key,manifestation_id,holding_institution,call_number,external_identifier,status,copy_note,provenance_note) values
  ('forme-of-cury:loc-44031282',v_forme_manifest,'Library of Congress',null,'LCCN 44031282','surviving_item_confirmed','LOC digitized Rare Book copy used for source intake.','Specific LOC cataloged exemplar anchors the 1780 manifestation.'),
  ('proper-new-booke-of-cookery:british-library-stc3367',v_proper_manifest,'British Library',null,'STC 3367','surviving_item_confirmed','Original identified by the Heidelberg/EEBO catalog as the source of the electronic reproduction.','Physical-copy call number is not asserted in this intake because it is not present in the governed source packet.'),
  ('new-system-of-domestic-cookery:ia-newsystemofdomes01rund',v_rundell_manifest,null,null,'Internet Archive newsystemofdomes01rund','surviving_item_confirmed','Specific digitized exemplar represented by the Open Library/Internet Archive record.','Owning physical institution is intentionally left unresolved pending direct source-object custody.'),
  ('virginia-house-wife:loc-73217897',v_randolph_manifest,'Library of Congress','TX715 .R215 1824','LCCN 73217897','surviving_item_confirmed','LOC 1824 copy used for source intake.','Specific LOC cataloged exemplar anchors the 1824 manifestation.')
  on conflict (canonical_key) do nothing;

  select id into strict v_forme_item from wnph.items where canonical_key='forme-of-cury:loc-44031282';
  select id into strict v_proper_item from wnph.items where canonical_key='proper-new-booke-of-cookery:british-library-stc3367';
  select id into strict v_rundell_item from wnph.items where canonical_key='new-system-of-domestic-cookery:ia-newsystemofdomes01rund';
  select id into strict v_randolph_item from wnph.items where canonical_key='virginia-house-wife:loc-73217897';

  insert into wnph.surrogates(canonical_key,item_id,source_id,surrogate_type,image_count,formats,status,quality_note) values
  ('forme-of-cury:loc-digital-44031282',v_forme_item,v_forme_src,'repository_page_image_surrogate',244,array['pdf','page_images'],'available','LOC exposes 244 page images; page-level reconstruction QC has not yet been performed.'),
  ('proper-new-booke-of-cookery:commons-ia-1575',v_proper_item,v_proper_src,'repository_page_image_surrogate',33,array['djvu','page_images'],'available','Commons/IA 33-page mechanical scan; source-image completeness and page order still require WNPH verification.'),
  ('new-system-of-domestic-cookery:ia-newsystemofdomes01rund',v_rundell_item,v_rundell_src,'repository_digital_surrogate',null,array['pdf','plain_text','epub','mobi','daisy'],'available','Open Library exposes multiple access derivatives for the IA item; WNPH has not yet adjudicated which derivative is source-authoritative.'),
  ('virginia-house-wife:loc-digital-73217897',v_randolph_item,v_randolph_src,'repository_page_image_surrogate',244,array['pdf','page_images'],'available','LOC exposes 244 page images; page-level reconstruction QC has not yet been performed.')
  on conflict (canonical_key) do nothing;

  select id into strict v_forme_surrogate from wnph.surrogates where canonical_key='forme-of-cury:loc-digital-44031282';
  select id into strict v_proper_surrogate from wnph.surrogates where canonical_key='proper-new-booke-of-cookery:commons-ia-1575';
  select id into strict v_rundell_surrogate from wnph.surrogates where canonical_key='new-system-of-domestic-cookery:ia-newsystemofdomes01rund';
  select id into strict v_randolph_surrogate from wnph.surrogates where canonical_key='virginia-house-wife:loc-digital-73217897';

  insert into wnph.date_claims(source_id,date_kind,observed_text,year_start,year_end,precision,status,manifestation_id,notes)
  values(v_forme_src,'publication','1780',1780,1780,'year','attested',v_forme_manifest,'LOC created/published statement.') returning id into v_claim;
  insert into wnph.date_adjudications(result,manifestation_id,canonical_year_start,canonical_year_end,conclusion_text,rationale,confidence,recorded_by)
  values('CONFIRMED',v_forme_manifest,1780,1780,'Publication year 1780.','LOC catalog directly records London publication in 1780.','high','wnph:foundational-cookbooks-intake-v1') returning id into v_adj;
  insert into wnph.date_adjudication_claims(adjudication_id,date_claim_id,claim_role) values(v_adj,v_claim,'supporting');

  insert into wnph.date_claims(source_id,date_kind,observed_text,year_start,year_end,precision,status,manifestation_id,notes)
  values(v_proper_catalog_src,'publication','1575',1575,1575,'year','attested',v_proper_manifest,'Heidelberg/EEBO catalog publication year.') returning id into v_claim;
  insert into wnph.date_adjudications(result,manifestation_id,canonical_year_start,canonical_year_end,conclusion_text,rationale,confidence,recorded_by)
  values('CONFIRMED',v_proper_manifest,1575,1575,'Publication year 1575.','Catalog and scan title page agree on 1575.','high','wnph:foundational-cookbooks-intake-v1') returning id into v_adj;
  insert into wnph.date_adjudication_claims(adjudication_id,date_claim_id,claim_role) values(v_adj,v_claim,'supporting');

  insert into wnph.date_claims(source_id,date_kind,observed_text,year_start,year_end,precision,status,manifestation_id,notes)
  values(v_rundell_src,'publication','1807',1807,1807,'year','attested',v_rundell_manifest,'Open Library 1807 Boston edition record.') returning id into v_claim;
  insert into wnph.date_adjudications(result,manifestation_id,canonical_year_start,canonical_year_end,conclusion_text,rationale,confidence,recorded_by)
  values('CONFIRMED',v_rundell_manifest,1807,1807,'Publication year 1807.','Open Library and Project Gutenberg identify the William Andrews Boston publication as 1807.','high','wnph:foundational-cookbooks-intake-v1') returning id into v_adj;
  insert into wnph.date_adjudication_claims(adjudication_id,date_claim_id,claim_role) values(v_adj,v_claim,'supporting');

  insert into wnph.date_claims(source_id,date_kind,observed_text,year_start,year_end,precision,status,manifestation_id,notes)
  values(v_randolph_src,'publication','1824',1824,1824,'year','attested',v_randolph_manifest,'LOC created/published statement.') returning id into v_claim;
  insert into wnph.date_adjudications(result,manifestation_id,canonical_year_start,canonical_year_end,conclusion_text,rationale,confidence,recorded_by)
  values('CONFIRMED',v_randolph_manifest,1824,1824,'Publication year 1824.','LOC catalog directly records Washington publication in 1824.','high','wnph:foundational-cookbooks-intake-v1') returning id into v_adj;
  insert into wnph.date_adjudication_claims(adjudication_id,date_claim_id,claim_role) values(v_adj,v_claim,'supporting');

  insert into wnph.identifiers(scheme,value,source_id,item_id,status,notes) values('LCCN','44031282',v_forme_src,v_forme_item,'attested','LOC catalog identifier for the selected 1780 exemplar.');
  insert into wnph.identifiers(scheme,value,source_id,manifestation_id,status,notes) values('STC','3367',v_proper_catalog_src,v_proper_manifest,'attested','STC (2nd ed.) identifier for the 1575 edition.');
  insert into wnph.identifiers(scheme,value,source_id,surrogate_id,status,notes) values('Internet Archive','bim_early-english-books-1475-1640_a-proper-new-booke-of-co_1575',v_proper_src,v_proper_surrogate,'attested','IA identifier exposed by Commons for the 1575 scan.');
  insert into wnph.identifiers(scheme,value,source_id,manifestation_id,status,notes) values('LCCN','08013208',v_rundell_src,v_rundell_manifest,'attested','Open Library edition identifier metadata.');
  insert into wnph.identifiers(scheme,value,source_id,manifestation_id,status,notes) values('Open Library','OL6996342M',v_rundell_src,v_rundell_manifest,'attested','Open Library edition identifier.');
  insert into wnph.identifiers(scheme,value,source_id,surrogate_id,status,notes) values('Internet Archive','newsystemofdomes01rund',v_rundell_src,v_rundell_surrogate,'attested','Internet Archive identifier on Open Library record.');
  insert into wnph.identifiers(scheme,value,source_id,item_id,status,notes) values('LCCN','73217897',v_randolph_src,v_randolph_item,'attested','LOC catalog identifier for the selected 1824 exemplar.');

  insert into wnph.recovery_cases(canonical_key,work_id,initial_scope,created_by) values
  ('forme-of-cury:foundational-cookbook-recovery-1',v_forme_work,'Evaluate a source-faithful recovery of the medieval cookery Work from the governed 1780 Pegge/LOC source lineage, preserving the distinction between medieval text and later editorial apparatus before any recipe normalization.','wnph:foundational-cookbooks-intake-v1'),
  ('proper-new-booke-of-cookery:foundational-cookbook-recovery-1',v_proper_work,'Evaluate a source-faithful recovery of the 1575 witness while preserving early printed language, seasonality, service order, and source structure before any recipe normalization.','wnph:foundational-cookbooks-intake-v1'),
  ('new-system-of-domestic-cookery:foundational-cookbook-recovery-1',v_rundell_work,'Evaluate a source-faithful recovery using the 1807 Boston witness and public-domain access derivatives, with source-image custody preceding recipe extraction.','wnph:foundational-cookbooks-intake-v1'),
  ('virginia-house-wife:foundational-cookbook-recovery-1',v_randolph_work,'Evaluate a source-faithful recovery from the 1824 LOC first-edition witness, preserving household-management and recipe structure before any downstream cookbook normalization.','wnph:foundational-cookbooks-intake-v1')
  on conflict (canonical_key) do nothing;

  select id into strict v_case_forme from wnph.recovery_cases where canonical_key='forme-of-cury:foundational-cookbook-recovery-1';
  select id into strict v_case_proper from wnph.recovery_cases where canonical_key='proper-new-booke-of-cookery:foundational-cookbook-recovery-1';
  select id into strict v_case_rundell from wnph.recovery_cases where canonical_key='new-system-of-domestic-cookery:foundational-cookbook-recovery-1';
  select id into strict v_case_randolph from wnph.recovery_cases where canonical_key='virginia-house-wife:foundational-cookbook-recovery-1';

  insert into wnph.recovery_case_briefs(recovery_case_id,scope_note,why_recover,proposed_expression_type,priority) values
  (v_case_forme,'Bibliographic/source intake only. Expression reconstruction and recipe parsing are downstream.','Foundational medieval cookery witness for a governed historical cookbook corpus.','source_faithful_cookery_recovery','high'),
  (v_case_proper,'Bibliographic/source intake only. Expression reconstruction and recipe parsing are downstream.','Foundational early printed household cookery witness with explicit seasonality and table-service structure.','source_faithful_cookery_recovery','high'),
  (v_case_rundell,'Bibliographic/source intake only. Expression reconstruction and recipe parsing are downstream.','Foundational domestic-economy/private-family cookery corpus and Mary Randall-circle research member.','source_faithful_cookery_recovery','high'),
  (v_case_randolph,'Bibliographic/source intake only. Expression reconstruction and recipe parsing are downstream.','Foundational American household/garden cookery corpus and Mary Randall-circle research member.','source_faithful_cookery_recovery','high');

  insert into wnph.recovery_case_modes(recovery_case_id,recovery_mode,intent_status,rationale) values
  (v_case_forme,'text','proposed','Recover source-governed historical text before normalization.'),(v_case_forme,'transcription','proposed','Collate public transcription against page-image source.'),(v_case_forme,'witness','proposed','Preserve witness/editorial lineage.'),
  (v_case_proper,'text','proposed','Recover source-governed historical text before normalization.'),(v_case_proper,'transcription','proposed','Create/verify a source-linked transcription from the 1575 scan.'),(v_case_proper,'witness','proposed','Preserve 1575 witness structure.'),
  (v_case_rundell,'text','proposed','Recover source-governed historical text before normalization.'),(v_case_rundell,'transcription','proposed','Collate public transcription derivatives against selected source images.'),(v_case_rundell,'witness','proposed','Preserve 1807 witness identity.'),
  (v_case_randolph,'text','proposed','Recover source-governed historical text before normalization.'),(v_case_randolph,'transcription','proposed','Collate public transcription against the 1824 LOC page images.'),(v_case_randolph,'witness','proposed','Preserve first-edition witness identity.');

  insert into wnph.recovery_case_targets(recovery_case_id,target_role,manifestation_id,rationale) values
  (v_case_forme,'publication_model',v_forme_manifest,'Current historical publication model for source recovery; not a claim of medieval-original manifestation.'),
  (v_case_proper,'publication_model',v_proper_manifest,'1575 edition selected as current source witness.'),
  (v_case_rundell,'publication_model',v_rundell_manifest,'1807 Boston edition selected as current source witness.'),
  (v_case_randolph,'publication_model',v_randolph_manifest,'1824 Washington edition selected as current source witness.');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,item_id,rationale) values
  (v_case_forme,'reference',v_forme_item,'Specific LOC exemplar anchors copy-level provenance.'),
  (v_case_proper,'reference',v_proper_item,'British Library original is identified by the cataloged reproduction lineage; copy-level call number remains unresolved.'),
  (v_case_rundell,'reference',v_rundell_item,'Specific IA-digitized 1807 exemplar anchors current source identity; physical holding institution remains unresolved.'),
  (v_case_randolph,'reference',v_randolph_item,'Specific LOC exemplar anchors copy-level provenance.');
  insert into wnph.recovery_case_targets(recovery_case_id,target_role,surrogate_id,rationale) values
  (v_case_forme,'primary_source',v_forme_surrogate,'LOC page-image/PDF surrogate is the current primary recovery-research source, not yet a preferred production source.'),
  (v_case_proper,'primary_source',v_proper_surrogate,'Commons/IA 1575 scan is the current primary recovery-research source, pending WNPH page verification.'),
  (v_case_rundell,'primary_source',v_rundell_surrogate,'IA/Open Library 1807 surrogate is the current primary recovery-research source, pending direct derivative/source-object adjudication.'),
  (v_case_randolph,'primary_source',v_randolph_surrogate,'LOC 1824 page-image/PDF surrogate is the current primary recovery-research source.');

  insert into wnph.recovery_clusters(canonical_key,label,rationale,status)
  values('foundational-public-domain-cookbooks:v1','Foundational Public-Domain Cookbooks','Joint recovery cohort selected to seed a source-governed historical cookbook corpus. Clustering is for coordinated recovery only; it does not collapse Works, Expressions, authorship, or cultural context.','active')
  on conflict (canonical_key) do nothing;
  select id into strict v_cluster from wnph.recovery_clusters where canonical_key='foundational-public-domain-cookbooks:v1';
  if not exists(select 1 from wnph.recovery_cluster_members where cluster_id=v_cluster and recovery_case_id=v_case_forme and supersedes_membership_id is null) then insert into wnph.recovery_cluster_members(cluster_id,recovery_case_id,membership_role,notes) values(v_cluster,v_case_forme,'member','Medieval cookery anchor.'); end if;
  if not exists(select 1 from wnph.recovery_cluster_members where cluster_id=v_cluster and recovery_case_id=v_case_proper and supersedes_membership_id is null) then insert into wnph.recovery_cluster_members(cluster_id,recovery_case_id,membership_role,notes) values(v_cluster,v_case_proper,'member','Early printed household cookery witness.'); end if;
  if not exists(select 1 from wnph.recovery_cluster_members where cluster_id=v_cluster and recovery_case_id=v_case_rundell and supersedes_membership_id is null) then insert into wnph.recovery_cluster_members(cluster_id,recovery_case_id,membership_role,notes) values(v_cluster,v_case_rundell,'member','Domestic economy/private-family cookery witness.'); end if;
  if not exists(select 1 from wnph.recovery_cluster_members where cluster_id=v_cluster and recovery_case_id=v_case_randolph and supersedes_membership_id is null) then insert into wnph.recovery_cluster_members(cluster_id,recovery_case_id,membership_role,notes) values(v_cluster,v_case_randolph,'member','Early American household cookery witness.'); end if;

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_forme,null,'IDENTITY_ESTABLISHED','state_transition','Historical Work identity and a specific 1780 source manifestation/item/surrogate are now governed in WNPH.','wnph:foundational-cookbooks-intake-v1') returning id into v_event;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_forme,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Begin source sufficiency and source-lineage evaluation; do not yet promote a recipe corpus.','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_proper,null,'IDENTITY_ESTABLISHED','state_transition','Historical Work identity and a specific 1575 source manifestation/item/surrogate are now governed in WNPH.','wnph:foundational-cookbooks-intake-v1') returning id into v_event;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_proper,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Begin source sufficiency and page-sequence evaluation; do not yet promote a recipe corpus.','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_rundell,null,'IDENTITY_ESTABLISHED','state_transition','Historical Work identity and a specific 1807 source manifestation/item/surrogate are now governed in WNPH.','wnph:foundational-cookbooks-intake-v1') returning id into v_event;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_rundell,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Begin source sufficiency and derivative-lineage evaluation; do not yet promote a recipe corpus.','wnph:foundational-cookbooks-intake-v1');

  insert into wnph.recovery_case_events(recovery_case_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_randolph,null,'IDENTITY_ESTABLISHED','state_transition','Historical Work identity and a specific 1824 source manifestation/item/surrogate are now governed in WNPH.','wnph:foundational-cookbooks-intake-v1') returning id into v_event;
  insert into wnph.recovery_case_events(recovery_case_id,prior_event_id,from_state,to_state,event_kind,rationale,recorded_by)
  values(v_case_randolph,v_event,'IDENTITY_ESTABLISHED','SOURCE_RESEARCH','state_transition','Begin source sufficiency and first-edition page verification; do not yet promote a recipe corpus.','wnph:foundational-cookbooks-intake-v1');
end $$;