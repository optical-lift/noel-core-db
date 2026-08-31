begin;

-- WNPH Vājasaneyi Saṁhitā I.29 candidate reading v1.
--
-- Stages the six Mādhyandina I.29 clauses as candidate readings beneath the
-- qualified Weber-1852 source package. The candidate wording is copied from the
-- scholarly TITUS electronic text, which identifies Weber as its edition basis.
-- It is NOT represented as a diplomatic transcription of Weber's 1852 pixels.
--
-- Every text block remains reading_state='candidate'. Exact source-image mapping,
-- direct visual verification, accent adjudication, and governed canonical-text
-- admission remain mandatory before any block can become verified/adjudicated.

do $$
declare
  v_package uuid;
  v_stream uuid;
  v_compare_source uuid;
  v_expression uuid;
  r record;
begin
  select p.id,p.expression_id into strict v_package,v_expression
  from wnph.publication_source_packages p
  where p.canonical_key='vajasaneyi-samhita:weber-1852-i-29-canonical-source:v1'
    and not exists(
      select 1 from wnph.publication_source_packages n
      where n.supersedes_package_id=p.id
    );

  select b.id into strict v_stream
  from wnph.publication_source_blocks b
  where b.source_package_id=v_package
    and b.block_key='vajasaneyi-weber1852:i-29:reading-stream'
    and not exists(
      select 1 from wnph.publication_source_blocks n
      where n.supersedes_block_id=b.id
    );

  select id into strict v_compare_source
  from wnph.evidence_sources
  where canonical_key='titus:vajasaneyi-samhita-madhyandina-weber';

  for r in
    select * from (values
      (1,'a','protection_removal_clause',
       'प्रत्यु॑ष्टँ॒ रक्षः॒ प्रत्यु॑ष्टा॒ अरा॑तयः ।'),
      (2,'b','protection_removal_clause',
       'निष्ट॑प्तँ॒ रक्षो॒ निष्ट॑प्ता॒ अरा॑तयः ।'),
      (3,'c','masculine_cleansing_formula',
       'अनि॑शितो सि सपत्न॒क्षिद्वा॒जिनं॑ त्वा वाजे॒ध्यायै॒ सं मा॑र्ज्मि ।'),
      (4,'d','protection_removal_clause_repeated',
       'प्रत्यु॑ष्टँ॒ रक्षः॒ प्रत्यु॑ष्टा॒ अरा॑तयः ।'),
      (5,'e','protection_removal_clause_repeated',
       'निष्ट॑प्तँ॒ रक्षो॒ निष्ट॑प्ता॒ अरा॑तयः ।'),
      (6,'f','feminine_cleansing_formula',
       'अनि॑शितासि सपत्न॒क्षिद्वा॒जिनीं॑ त्वा वाजे॒ध्यायै॒ सं मा॑र्ज्मि ।।')
    ) as x(ordinal,clause_key,semantic_role,text_content)
  loop
    if not exists(
      select 1
      from wnph.publication_source_blocks b
      where b.source_package_id=v_package
        and b.block_key='vajasaneyi-weber1852:i-29:clause-' || r.clause_key
        and not exists(
          select 1 from wnph.publication_source_blocks n
          where n.supersedes_block_id=b.id
        )
    ) then
      insert into wnph.publication_source_blocks(
        source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
        text_content,reading_state,properties,source_provenance
      ) values(
        v_package,
        'vajasaneyi-weber1852:i-29:clause-' || r.clause_key,
        v_stream,
        r.ordinal,
        'formula_clause',
        r.semantic_role,
        r.text_content,
        'candidate',
        jsonb_build_object(
          'canonical_locator','Vājasaneyi Saṁhitā I.29.' || r.clause_key,
          'recension','Mādhyandina',
          'script','Devanagari',
          'vedic_accent_marks_present',true,
          'clause_ordinal',r.ordinal,
          'source_image_verification_required',true,
          'weber_1852_diplomatic_claim',false,
          'candidate_only',true,
          'paired_formula_role',case
            when r.clause_key='c' then 'masculine'
            when r.clause_key='f' then 'feminine'
            else 'shared_repeated_clause'
          end
        ),
        jsonb_build_object(
          'text_authority','TITUS scholarly electronic Mādhyandina text, Weber edition basis; comparison authority only',
          'derivation_method','direct candidate capture from TITUS verse I.29 with no silent normalization beyond preserving the displayed Devanagari text supplied by that witness',
          'source_locators',jsonb_build_array(
            jsonb_build_object(
              'source_key','titus:vajasaneyi-samhita-madhyandina-weber',
              'canonical_locator','I.29.' || r.clause_key,
              'role','comparison_electronic_text',
              'source_image_authority',false
            ),
            jsonb_build_object(
              'source_surrogate_key','vajasaneyi-samhita:weber1852:dli-486971-surrogate',
              'canonical_locator','I.29',
              'role','governed_historical_source_pending_exact_page_mapping',
              'source_image_verification_complete',false
            )
          ),
          'verification_status','not_source_verified',
          'source_image_verification_required',true,
          'accent_verification_required',true,
          'electronic_collation_may_not_promote_text',true,
          'notes','Candidate preserves the TITUS displayed reading only. Sandhi segmentation, accent placement, glyph form and punctuation must be checked against Weber 1852 before promotion.'
        )
      );
    end if;
  end loop;

  if (
    select count(*)
    from wnph.publication_source_blocks b
    where b.source_package_id=v_package
      and b.parent_block_id=v_stream
      and b.block_key like 'vajasaneyi-weber1852:i-29:clause-%'
      and b.reading_state='candidate'
      and not exists(
        select 1 from wnph.publication_source_blocks n
        where n.supersedes_block_id=b.id
      )
  ) <> 6 then
    raise exception 'Expected exactly six active Vājasaneyi I.29 candidate clauses';
  end if;

  if exists(
    select 1
    from wnph.publication_source_blocks b
    where b.source_package_id=v_package
      and b.block_key like 'vajasaneyi-weber1852:i-29:clause-%'
      and b.reading_state in ('verified','adjudicated')
      and not exists(
        select 1 from wnph.publication_source_blocks n
        where n.supersedes_block_id=b.id
      )
  ) then
    raise exception 'Vājasaneyi I.29 candidate staging may not create verified/adjudicated text';
  end if;

  insert into wnph.evidence_links(
    source_id,expression_id,support_role,confidence,note
  )
  select v_compare_source,v_expression,'context','high',
    'TITUS supplies the electronic comparison reading used to stage I.29 candidates; this evidence does not verify Weber 1852 source-image text.'
  where not exists(
    select 1 from wnph.evidence_links e
    where e.source_id=v_compare_source
      and e.expression_id=v_expression
      and e.note='TITUS supplies the electronic comparison reading used to stage I.29 candidates; this evidence does not verify Weber 1852 source-image text.'
      and e.supersedes_evidence_link_id is null
  );
end $$;

commit;
