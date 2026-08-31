do $$
declare
  v_page1 jsonb;
  v_page3 jsonb;
begin
  if exists (
    select 1
    from wnph.publication_source_surface_readings r
    join wnph.publication_source_assets a on a.id=r.source_asset_id
    join wnph.publication_source_packages p on p.id=r.source_package_id
    where p.canonical_key='proper-new-booke-of-cookery:1575-canonical-publication-source:v1'
      and a.asset_key in ('proper-new-booke:1575:source-surface:0001','proper-new-booke:1575:source-surface:0003')
  ) then
    raise exception 'Proper New Booke surface-reading bridge expected no pre-existing reading lineage for pages 1 or 3';
  end if;

  v_page1 := public.wnph_record_source_surface_reading_v1(
    'proper-new-booke-of-cookery:1575-canonical-publication-source:v1',
    'proper-new-booke:1575:source-surface:0001',
    'proper-new-booke:1575:surface-reading:page1:needs-adjudication:v1',
    'text',
    'needs_adjudication',
    E'A proper new\nBooke of Cookery.\n\nDeclaring what maner\nof meates be best in season for\nal times of the yeere, and how\nthey ought to be dressed, &\nserued at the Table, both\nfor fleshe dayes and\nfish daies.\n\nwith a new addition,\nvery necessary for al\nthem that delight\nin Cookery.\n\n1575.\n\nImprinted at London in Fleet\nstreete, by William How\nfor Abraham Veale.',
    'cde67c10950da61757a216f53ab2b1c6ca055b4ce603cc207e1fa131f9e7e07f',
    'current_governed_1575_page_image_requires_fresh_literal_pixel_inspection',
    'legacy_visual_reading_reprojected_to_superseding_render_pending_reinspection',
    0.97,
    jsonb_build_object(
      'pixel_inspected',false,
      'scan_page',1,
      'source_image_byte_length',154596,
      'source_image_fetch_http_status',200,
      'source_image_magic','ffd8ffdb',
      'image_hash_method','pgsql_http_text_to_bytea_then_sha256',
      'exact_current_source_image_bytes_pinned',true,
      'current_render_is_superseding_asset',true,
      'legacy_visual_observation_asset_id','717fc497-5668-478e-aff0-a0b22b97abcf',
      'legacy_visual_observation_keys',jsonb_build_array(
        'proper-new-booke:1575:page1:visual:title-reading',
        'proper-new-booke:1575:page1:visual:remaining-title-page-reading'
      ),
      'legacy_visual_conflict_resolved',jsonb_build_object('wikisource','William Dow','legacy_source_image_reading','William How'),
      'fresh_pixel_inspection_required_before_verified_surface_reading',true,
      'canonical_title_blocks_preexist_this_surface_reading_kernel_bridge',true,
      'promotion_allowed',false,
      'normalization_performed',false
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal',1,
        'span_kind','region',
        'text_content',E'A proper new\nBooke of Cookery.',
        'evidence',jsonb_build_object('pixel_verified',false,'scan_page',1,'legacy_visual_evidence_only',true)
      ),
      jsonb_build_object(
        'ordinal',2,
        'span_kind','region',
        'text_content',E'Declaring what maner\nof meates be best in season for\nal times of the yeere, and how\nthey ought to be dressed, &\nserued at the Table, both\nfor fleshe dayes and\nfish daies.\n\nwith a new addition,\nvery necessary for al\nthem that delight\nin Cookery.\n\n1575.\n\nImprinted at London in Fleet\nstreete, by William How\nfor Abraham Veale.',
        'evidence',jsonb_build_object('pixel_verified',false,'scan_page',1,'legacy_visual_evidence_only',true)
      )
    )
  );

  v_page3 := public.wnph_record_source_surface_reading_v1(
    'proper-new-booke-of-cookery:1575-canonical-publication-source:v1',
    'proper-new-booke:1575:source-surface:0003',
    'proper-new-booke:1575:surface-reading:page3:proposed:v1',
    'text',
    'proposed',
    E'The Booke of\ncookery.\n\nBrawne is beſt from a fo ꝛ te-night befo ꝛ e Mighelmas till Lent. Beife and Bakon is good all times the yere. Mutton is good at all times, but from Eaſter to midſommer it is woo ꝛ ſt. A fat Pigge is ever in ſeaſon. A goſe is woo ꝛ ſt in midſommer moone, and beſt in ſtubble time, but whē they be yonge Greene Geeſe, than they be beſt. Veale is beſt in January and Feb ꝛ uarye and all other times good.',
    '6750e144a1acc3879f314f4a559583c4a3a12a59d631209272451a5895ddac67',
    'current_governed_1575_page_image_required_for_final_verification',
    'external_wikisource_transcription_alignment_pending_literal_pixel_inspection',
    0.90,
    jsonb_build_object(
      'pixel_inspected',false,
      'scan_page',3,
      'source_image_byte_length',123099,
      'source_image_fetch_http_status',200,
      'source_image_magic','ffd8ffdb',
      'image_hash_method','pgsql_http_text_to_bytea_then_sha256',
      'exact_current_source_image_bytes_pinned',true,
      'current_runtime_remote_image_render_available',false,
      'wikisource_is_comparison_only',true,
      'fresh_pixel_inspection_required_before_verified_surface_reading',true,
      'promotion_allowed',false,
      'normalization_performed',false
    ),
    jsonb_build_array(
      jsonb_build_object(
        'ordinal',1,
        'span_kind','region',
        'text_content',E'The Booke of\ncookery.\n\nBrawne is beſt from a fo ꝛ te-night befo ꝛ e Mighelmas till Lent. Beife and Bakon is good all times the yere. Mutton is good at all times, but from Eaſter to midſommer it is woo ꝛ ſt. A fat Pigge is ever in ſeaſon. A goſe is woo ꝛ ſt in midſommer moone, and beſt in ſtubble time, but whē they be yonge Greene Geeſe, than they be beſt. Veale is beſt in January and Feb ꝛ uarye and all other times good.',
        'source_observation_keys',jsonb_build_array('proper-new-booke:1575:page3:wikisource:first-region-candidate'),
        'evidence',jsonb_build_object('pixel_verified',false,'scan_page',3,'coverage','heading_and_first_seasonal_paragraph_candidate')
      )
    )
  );

  if coalesce(v_page1->>'reading_state','') <> 'needs_adjudication' then
    raise exception 'Proper New Booke surface-reading bridge failed to preserve page 1 as needs-adjudication';
  end if;
  if coalesce(v_page3->>'reading_state','') <> 'proposed' then
    raise exception 'Proper New Booke surface-reading bridge failed to preserve page 3 as proposed-only';
  end if;
end $$;