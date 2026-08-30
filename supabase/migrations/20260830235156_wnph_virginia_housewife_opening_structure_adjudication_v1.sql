do $$
declare
  v_pkg uuid;
  v_root uuid;
  v_old_section wnph.publication_source_blocks%rowtype;
  v_old_block wnph.publication_source_blocks%rowtype;
  v_old_proposal wnph.publication_source_reconstruction_proposals%rowtype;
  v_old_unit wnph.publication_semantic_units%rowtype;
  v_opening uuid;
  v_new_proposal uuid;
  v_new_block uuid;
  v_new_unit uuid;
begin
  select id into v_pkg
  from wnph.publication_source_packages
  where canonical_key='virginia-house-wife:1824-functional-semantic-source:v1';

  if v_pkg is null then
    return;
  end if;

  select id into v_root
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_key='virginia-house-wife:1824:root'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;

  select * into v_old_section
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_key='virginia-house-wife:1824:section:beef'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;

  select * into v_old_block
  from wnph.publication_source_blocks b
  where b.source_package_id=v_pkg
    and b.block_key='virginia-house-wife:1824:beef:directions-for-curing-beef'
    and not exists(select 1 from wnph.publication_source_blocks n where n.supersedes_block_id=b.id)
  order by b.created_at desc limit 1;

  select * into v_old_proposal
  from wnph.publication_source_reconstruction_proposals r
  where r.source_package_id=v_pkg
    and r.proposal_key='virginia-house-wife:1824:curing-beef:reconstruction:v1'
    and not exists(select 1 from wnph.publication_source_reconstruction_proposals n where n.supersedes_proposal_id=r.id)
  order by r.created_at desc limit 1;

  select * into v_old_unit
  from wnph.publication_semantic_units u
  where u.source_package_id=v_pkg
    and u.unit_key='virginia-house-wife:1824:semantic:curing-beef'
    and not exists(select 1 from wnph.publication_semantic_units n where n.supersedes_unit_id=u.id)
  order by u.created_at desc limit 1;

  if v_root is null or v_old_section.id is null or v_old_block.id is null or v_old_proposal.id is null or v_old_unit.id is null then
    return;
  end if;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,properties,source_provenance
  ) values (
    v_pkg,
    'virginia-house-wife:1824:sequence:opening-preservation',
    v_root,
    1,
    'editorial_container',
    'unsectioned_opening_instruction_sequence',
    jsonb_build_object(
      'printed_heading_absent',true,
      'editorial_container',true,
      'first_printed_page',13,
      'historical_structure_status','adjudicated_from_exact_1824_sequence'
    ),
    jsonb_build_object(
      'controlling_witness','Library of Congress 1824 first edition',
      'structure_basis','exact 1824 opening sequence; later stereotype section headings are excluded',
      'cross_edition_blend_allowed',false
    )
  ) returning id into v_opening;

  insert into wnph.publication_source_reconstruction_proposals(
    source_package_id,proposal_key,target_parent_block_id,proposed_block_key,proposed_ordinal,
    proposed_block_type,proposed_semantic_role,proposed_text_content,proposed_reading_state,
    source_observation_ids,confidence,disposition,review_reasons,proposed_properties,
    proposed_source_provenance,algorithm,supersedes_proposal_id
  ) values (
    v_old_proposal.source_package_id,
    v_old_proposal.proposal_key,
    v_opening,
    v_old_proposal.proposed_block_key,
    v_old_proposal.proposed_ordinal,
    v_old_proposal.proposed_block_type,
    v_old_proposal.proposed_semantic_role,
    v_old_proposal.proposed_text_content,
    v_old_proposal.proposed_reading_state,
    v_old_proposal.source_observation_ids,
    v_old_proposal.confidence,
    v_old_proposal.disposition,
    v_old_proposal.review_reasons || jsonb_build_array('1824 opening structure corrected: no printed BEEF section governs this unit'),
    v_old_proposal.proposed_properties || jsonb_build_object(
      'historical_container','unsectioned opening instruction sequence',
      'later_edition_section_heading_excluded',true
    ),
    v_old_proposal.proposed_source_provenance || jsonb_build_object(
      'structure_adjudication','exact 1824 sequence controls; later stereotype BEEF/SOUPS structure not imported'
    ),
    v_old_proposal.algorithm,
    v_old_proposal.id
  ) returning id into v_new_proposal;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,text_content,
    properties,source_provenance,reading_state,supersedes_block_id
  ) values (
    v_old_block.source_package_id,
    v_old_block.block_key,
    v_opening,
    v_old_block.ordinal,
    v_old_block.block_type,
    v_old_block.semantic_role,
    v_old_block.text_content,
    (v_old_block.properties - 'historical_section') || jsonb_build_object(
      'historical_container','unsectioned opening instruction sequence',
      'reconstruction_proposal_id',v_new_proposal::text,
      'later_edition_section_heading_excluded',true
    ),
    v_old_block.source_provenance || jsonb_build_object(
      'structure_adjudication','exact 1824 sequence controls; unit is not governed by a printed BEEF section heading'
    ),
    v_old_block.reading_state,
    v_old_block.id
  ) returning id into v_new_block;

  insert into wnph.publication_source_blocks(
    source_package_id,block_key,parent_block_id,ordinal,block_type,semantic_role,
    properties,source_provenance,supersedes_block_id
  ) values (
    v_old_section.source_package_id,
    v_old_section.block_key,
    v_root,
    v_old_section.ordinal,
    'editorial_note',
    'retracted_structure_assumption',
    jsonb_build_object(
      'retracted',true,
      'excluded_from_historical_structure',true,
      'prior_assumption','BEEF. printed section beginning at page 13',
      'correction','The exact 1824 opening is an unsectioned instruction sequence; the BEEF section parent was imported from later-edition expectations.'
    ),
    jsonb_build_object(
      'controlling_witness','Library of Congress 1824 first edition',
      'adjudication_basis','exact 1824 sequence and independent exact-1824 comparison transcription',
      'cross_edition_blend_prevented',true
    ),
    v_old_section.id
  );

  insert into wnph.publication_semantic_units(
    expression_id,source_package_id,unit_key,parent_unit_id,ordinal,unit_type,source_title,
    semantic_status,confidence,derivation_method,properties,source_provenance,supersedes_unit_id
  ) values (
    v_old_unit.expression_id,
    v_old_unit.source_package_id,
    v_old_unit.unit_key,
    v_old_unit.parent_unit_id,
    v_old_unit.ordinal,
    v_old_unit.unit_type,
    v_old_unit.source_title,
    v_old_unit.semantic_status,
    v_old_unit.confidence,
    v_old_unit.derivation_method,
    (v_old_unit.properties - 'historical_section') || jsonb_build_object(
      'historical_container','unsectioned opening instruction sequence',
      'later_edition_section_heading_excluded',true
    ),
    (v_old_unit.source_provenance - 'source_block_id') || jsonb_build_object(
      'source_block_id',v_new_block::text,
      'structure_adjudication','exact 1824 sequence controls; no printed BEEF parent admitted'
    ),
    v_old_unit.id
  ) returning id into v_new_unit;

  insert into wnph.publication_semantic_claims(
    semantic_unit_id,source_block_id,claim_key,ordinal,claim_kind,subject_key,predicate,object_text,
    quantity_value,quantity_unit,quantity_text,temporal_text,condition_text,claim_status,confidence,
    derivation_method,properties,source_provenance,supersedes_claim_id
  )
  select
    v_new_unit,
    v_new_block,
    c.claim_key,c.ordinal,c.claim_kind,c.subject_key,c.predicate,c.object_text,
    c.quantity_value,c.quantity_unit,c.quantity_text,c.temporal_text,c.condition_text,
    c.claim_status,c.confidence,c.derivation_method,c.properties,
    c.source_provenance || jsonb_build_object(
      'structure_adjudication','claim carried into direct superseding semantic unit after exact-1824 structure correction'
    ),
    c.id
  from wnph.publication_semantic_claims c
  where c.semantic_unit_id=v_old_unit.id
    and not exists(select 1 from wnph.publication_semantic_claims n where n.supersedes_claim_id=c.id)
  order by c.ordinal;
end $$;