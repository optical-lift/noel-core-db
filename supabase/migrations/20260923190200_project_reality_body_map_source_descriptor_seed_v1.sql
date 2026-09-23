begin;

-- Evidence-custodied query edges for the first cross-domain body-map proving packet.
-- Relation names are intentionally specific. A returned object may be:
--   a direct term,
--   a framework-native category,
--   a condition vocabulary that may include a feature,
--   an intervention vocabulary used in a matching context,
--   a correspondence-map object,
--   or structurally adjacent canon vocabulary.
-- None of those relation types is silently upgraded to diagnosis, truth parity,
-- causal identity, treatment recommendation, or cross-framework equivalence.

insert into draft.reality_object_query_descriptors
(object_type,object_id,dimension_key,dimension_value,normalized_value,relation_type,source_basis,framework_key,evidence_ref,confidence,rationale,status,metadata,scope_region_key,scope_side)
values
-- Conventional biomedicine: dizziness vocabulary.
('framework_concept','biomed_dizziness_term','reported_symptom','dizziness','dizziness','direct_clinical_term',
 'ACR dizziness terminology + Clinical Methods','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/","https://pubmed.ncbi.nlm.nih.gov/21250167/"]}'::jsonb,
 'high','Direct clinical vocabulary for the user-reported term; no cause inferred.','active','{}'::jsonb,null,null),

('framework_concept','biomed_vertigo_term','reported_symptom','dizziness','dizziness','clinical_subclassification_of_dizziness',
 'ACR dizziness terminology','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb,
 'high','Vertigo is one clinically distinguished meaning patients may intend by dizziness; further description is required.','active',
 '{"requires":["motion_or_spinning_description"]}'::jsonb,null,null),

('framework_concept','biomed_disequilibrium_term','reported_symptom','dizziness','dizziness','clinical_subclassification_of_dizziness',
 'ACR dizziness terminology','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb,
 'high','Disequilibrium is one clinically distinguished meaning patients may intend by dizziness.','active','{}'::jsonb,null,null),

('framework_concept','biomed_presyncope_term','reported_symptom','dizziness','dizziness','clinical_subclassification_of_dizziness',
 'ACR dizziness terminology','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb,
 'high','Presyncope is one clinically distinguished meaning patients may intend by dizziness.','active','{}'::jsonb,null,null),

('framework_concept','biomed_lightheadedness_term','reported_symptom','dizziness','dizziness','clinical_subclassification_of_dizziness',
 'ACR dizziness terminology','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb,
 'high','Lightheadedness is one clinically distinguished meaning patients may intend by dizziness.','active','{}'::jsonb,null,null),

('framework_concept','biomed_vestibular_migraine','reported_symptom','dizziness','dizziness','condition_vocabulary_may_include_feature',
 'NLM MeSH Vestibular Migraine','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/2108908"]}'::jsonb,
 'medium','MeSH defines vestibular migraine using vertigo or major dizziness with migraine context; dizziness alone is insufficient.','active',
 '{"requires":["migraine_context","diagnostic_evaluation"]}'::jsonb,null,null),

-- Head pressure / headache vocabulary.
('framework_concept','biomed_headache_term','body_region','head','head','localized_to_region',
 'NLM MeSH Headache','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68006261"]}'::jsonb,
 'high','Headache is pain in the cranial region.','active','{}'::jsonb,'head',null),

('framework_concept','biomed_pressing_tightening_headache_quality','body_region','head','head','localized_to_region',
 'ICHD-3 terminology','conventional_biomedicine',
 '{"sources":["https://ichd-3.org/definition-of-terms/"]}'::jsonb,
 'high','The source term is specifically a head-pain quality.','active','{}'::jsonb,'head',null),

('framework_concept','biomed_pressing_tightening_headache_quality','sensation','pressure','pressure','clinical_quality_matches_user_description',
 'ICHD-3 terminology','conventional_biomedicine',
 '{"sources":["https://ichd-3.org/definition-of-terms/"]}'::jsonb,
 'high','Pressing/tightening is an established headache-quality term; it does not by itself establish a headache disorder.','active',
 '{"does_not_establish":["tension_type_headache"]}'::jsonb,'head',null),

('framework_concept','biomed_tension_type_headache','body_region','head','head','condition_anatomic_scope',
 'NLM MeSH Tension-Type Headache','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68018781"]}'::jsonb,
 'high','The condition is defined in the head/scalp/neck domain.','active','{}'::jsonb,'head',null),

('framework_concept','biomed_tension_type_headache','sensation','pressure','pressure','condition_vocabulary_may_include_quality',
 'NLM MeSH + ICHD-3','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68018781","https://ichd-3.org/definition-of-terms/"]}'::jsonb,
 'medium','Band-like or pressing/tightening quality belongs to the vocabulary of tension-type headache, but full criteria are required.','active',
 '{"requires":["full_diagnostic_criteria"]}'::jsonb,'head',null),

('framework_concept','biomed_concussion_mild_tbi','body_region','head','head','condition_relevant_to_region_with_required_context',
 'CDC mild TBI/concussion','conventional_biomedicine',
 '{"sources":["https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html"]}'::jsonb,
 'medium','Concussion is relevant to a head-focused search only when an injury context exists.','active',
 '{"requires":["head_or_body_impact_context"]}'::jsonb,'head',null),

('framework_concept','biomed_concussion_mild_tbi','reported_symptom','dizziness','dizziness','condition_may_include_feature',
 'CDC mild TBI/concussion','conventional_biomedicine',
 '{"sources":["https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html"]}'::jsonb,
 'high','CDC lists dizziness or balance problems among possible concussion symptoms; this does not establish concussion.','active',
 '{"requires":["injury_context","clinical_assessment"]}'::jsonb,'head',null),

-- Knee ache / intermittency.
('framework_concept','biomed_pain_ache','sensation','ache','ache','entry_term_equivalence',
 'NLM MeSH Pain','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'high','MeSH lists ache as an entry term under Pain.','active','{}'::jsonb,null,null),

('framework_concept','biomed_arthralgia','body_region','knee','knee','joint_pain_term_applicable_to_region',
 'NLM MeSH Arthralgia','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/D018771"]}'::jsonb,
 'high','Arthralgia means joint pain; knee is a joint region.','active','{"does_not_establish":["arthritis"]}'::jsonb,'knee',null),

('framework_concept','biomed_arthralgia','sensation','ache','ache','joint_pain_term_matches_ache',
 'NLM MeSH Pain + Arthralgia','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68010146","https://www.ncbi.nlm.nih.gov/mesh/D018771"]}'::jsonb,
 'high','Ache is a Pain entry term and arthralgia is joint pain.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_patellofemoral_pain','body_region','knee','knee','condition_localized_to_region',
 'NLM MeSH Patellofemoral Pain Syndrome','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/D046788"]}'::jsonb,
 'high','Patellofemoral pain is localized around the knee.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_patellofemoral_pain','sensation','ache','ache','condition_vocabulary_may_include_pain',
 'NLM MeSH Patellofemoral Pain Syndrome + Pain','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/D046788","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','Generic knee ache reaches this term through the broader pain vocabulary; localization/criteria remain unresolved.','active',
 '{"requires":["patellofemoral_localization_or_clinical_criteria"]}'::jsonb,'knee',null),

('framework_concept','biomed_intermittent_knee_pain','body_region','knee','knee','pattern_localized_to_region',
 'Osteoarthritis Initiative pain-pattern research','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://pubmed.ncbi.nlm.nih.gov/32198833/"]}'::jsonb,
 'high','The research term is explicitly knee pain.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_intermittent_knee_pain','sensation','ache','ache','pain_pattern_matches_ache',
 'NLM MeSH Pain + knee pain-pattern research','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68010146","https://pubmed.ncbi.nlm.nih.gov/25376465/"]}'::jsonb,
 'high','Ache expands to pain; this object is specifically a knee-pain pattern.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_intermittent_knee_pain','temporal_pattern','intermittent','intermittent','direct_temporal_pattern',
 'Osteoarthritis Initiative pain-pattern research','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://pubmed.ncbi.nlm.nih.gov/32198833/"]}'::jsonb,
 'high','Intermittent versus constant knee pain is directly distinguished in the source literature.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_knee_osteoarthritis','body_region','knee','knee','condition_localized_to_region',
 'Knee osteoarthritis pain-pattern literature','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/"]}'::jsonb,
 'high','The condition is knee osteoarthritis.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_knee_osteoarthritis','sensation','ache','ache','condition_may_include_pain',
 'Knee osteoarthritis literature + MeSH Pain','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','Knee pain is studied in OA; ache is a pain term. This is not a diagnosis.','active','{}'::jsonb,'knee',null),

('framework_concept','biomed_knee_osteoarthritis','temporal_pattern','intermittent','intermittent','condition_studied_with_temporal_pain_pattern',
 'Osteoarthritis Initiative pain-pattern research','conventional_biomedicine',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://pubmed.ncbi.nlm.nih.gov/32198833/"]}'::jsonb,
 'medium','Intermittent knee pain is explicitly studied in cohorts with or at risk for knee OA; this does not establish OA.','active',
 '{"does_not_establish":["osteoarthritis"]}'::jsonb,'knee',null),

('framework_concept','biomed_aspirin','sensation','ache','ache','analgesic_vocabulary_used_for_pain',
 'NLM MeSH Aspirin + Pain','conventional_biomedicine',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68001241","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'high','Aspirin is indexed as an analgesic used for mild to moderate pain; retrieval is not a recommendation.','active',
 '{"not_a_recommendation":true,"requires":["individual_safety_and_context"]}'::jsonb,null,null),

-- Traditional Chinese medicine.
('framework_concept','tcm_vertigo_dizziness_category','reported_symptom','dizziness','dizziness','framework_native_category_for_feature',
 'TCM cervical-vertigo literature','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC5474245/"]}'::jsonb,
 'high','TCM literature places cervical vertigo/dizziness within a vertigo category.','active',
 '{"framework_native":true}'::jsonb,null,null),

('framework_concept','tcm_wind_phlegm_dizziness_pattern','reported_symptom','dizziness','dizziness','framework_pattern_used_for_feature',
 'TCM cervicogenic-dizziness systematic review','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"]}'::jsonb,
 'high','Wind-phlegm and phlegm-stasis are source-attested TCM pattern types in cervicogenic-dizziness literature.','active',
 '{"requires":["tcm_pattern_differentiation"]}'::jsonb,null,null),

('framework_concept','tcm_liver_yang_dizziness_pattern','reported_symptom','dizziness','dizziness','framework_pattern_used_for_feature',
 'TCM cervicogenic-dizziness systematic review','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"]}'::jsonb,
 'high','Hyperactivity of liver yang is a source-attested pattern type in the cited dizziness literature.','active',
 '{"requires":["tcm_pattern_differentiation"]}'::jsonb,null,null),

('framework_concept','tcm_qi_blood_deficiency_dizziness_pattern','reported_symptom','dizziness','dizziness','framework_pattern_used_for_feature',
 'TCM cervicogenic-dizziness systematic review','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"]}'::jsonb,
 'high','Qi and blood deficiency is a source-attested pattern type in the cited dizziness literature.','active',
 '{"requires":["tcm_pattern_differentiation"]}'::jsonb,null,null),

('framework_concept','tcm_bone_impediment_knee','body_region','knee','knee','framework_category_applied_to_region_condition',
 'TCM integrative knee-OA guideline','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC10617515/"]}'::jsonb,
 'high','The guideline classifies knee OA in the bone-impediment category.','active',
 '{"does_not_establish":["knee_osteoarthritis"]}'::jsonb,'knee',null),

('framework_concept','tcm_bone_impediment_knee','sensation','ache','ache','framework_category_associated_with_knee_pain',
 'TCM integrative knee-OA guideline + neutral pain expansion','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC10617515/","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','The guideline describes knee pain in the condition it calls bone impediment; generic ache does not establish the category.','active',
 '{}'::jsonb,'knee',null),

('framework_concept','tcm_bi_syndrome_knee','body_region','knee','knee','framework_category_applied_to_region_condition',
 'TCM knee-OA literature','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624358/","https://pmc.ncbi.nlm.nih.gov/articles/PMC10617515/"]}'::jsonb,
 'high','Bi/impediment disease is used as TCM vocabulary for knee OA/joint obstruction-pain contexts.','active',
 '{}'::jsonb,'knee',null),

('framework_concept','tcm_bi_syndrome_knee','sensation','ache','ache','framework_category_associated_with_knee_pain',
 'TCM knee-OA literature + neutral pain expansion','classical_tcm',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624358/","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','Knee pain belongs to the cited presentation; the user term ache reaches pain without establishing the syndrome.','active',
 '{}'::jsonb,'knee',null),

-- Classical homeopathy / repertory language.
('framework_concept','homeopathy_dizziness_rubric','reported_symptom','dizziness','dizziness','direct_repertory_heading',
 'Knerr repertory of Hering','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/dizziness.htm"]}'::jsonb,
 'high','Dizziness is a direct repertory heading.','active','{"historical_framework":true}'::jsonb,null,null),

('framework_concept','homeopathy_vertigo_rubric','reported_symptom','dizziness','dizziness','adjacent_repertory_heading',
 'Knerr repertory of Hering','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/dizziness.htm"]}'::jsonb,
 'high','Vertigo appears as a neighboring repertory category; it is not assumed identical to dizziness.','active',
 '{"historical_framework":true}'::jsonb,null,null),

('framework_concept','homeopathy_head_pressure_fullness_rubric','body_region','head','head','repertory_region',
 'Hering materia medica','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/a/aesc-1.htm","https://www.homeoint.org/hering/b/bism.htm"]}'::jsonb,
 'high','The source language explicitly concerns the head.','active','{"historical_framework":true}'::jsonb,'head',null),

('framework_concept','homeopathy_head_pressure_fullness_rubric','sensation','pressure','pressure','direct_source_language',
 'Hering materia medica','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/a/aesc-1.htm","https://www.homeoint.org/hering/b/bism.htm"]}'::jsonb,
 'high','The source entries use pressure/fullness/pressive language in the head.','active',
 '{"historical_framework":true}'::jsonb,'head',null),

('framework_concept','homeopathy_right_knee_pain_rubric','body_region','knee','knee','repertory_region',
 'Hering materia medica','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/c/cinnb-3.htm","https://www.homeoint.org/hering/a/aesc-3.htm"]}'::jsonb,
 'high','The source entries explicitly localize pain to the knee.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_right_knee_pain_rubric','body_region_side','knee:right','knee:right','direct_laterality_phrase',
 'Hering materia medica','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/c/cinnb-3.htm"]}'::jsonb,
 'high','Right knee is explicit source language.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_right_knee_pain_rubric','sensation','ache','ache','pain_vocabulary_matches_ache',
 'Hering materia medica + NLM pain entry term','classical_homeopathy',
 '{"sources":["https://www.homeoint.org/hering/a/aesc-3.htm","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','Source uses pain/aching language; ache is a Pain entry term.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_intermit_right_knee_pain','body_region','knee','knee','direct_source_region',
 'Hering Trombidium entry','classical_homeopathy',
 '{"sources":["https://homeoint.org/hering/t/trom.htm"]}'::jsonb,
 'high','Source explicitly says right knee joint.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_intermit_right_knee_pain','body_region_side','knee:right','knee:right','direct_source_laterality',
 'Hering Trombidium entry','classical_homeopathy',
 '{"sources":["https://homeoint.org/hering/t/trom.htm"]}'::jsonb,
 'high','Source explicitly says right knee joint.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_intermit_right_knee_pain','sensation','ache','ache','pain_vocabulary_matches_ache',
 'Hering Trombidium entry + NLM pain entry term','classical_homeopathy',
 '{"sources":["https://homeoint.org/hering/t/trom.htm","https://www.ncbi.nlm.nih.gov/mesh/68010146"]}'::jsonb,
 'medium','Source says pain; user term ache is normalized to pain vocabulary.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

('framework_concept','homeopathy_intermit_right_knee_pain','temporal_pattern','intermittent','intermittent','direct_source_temporal_phrase',
 'Hering Trombidium entry','classical_homeopathy',
 '{"sources":["https://homeoint.org/hering/t/trom.htm"]}'::jsonb,
 'high','Source explicitly records intermitting pains in the right knee joint.','active',
 '{"historical_framework":true}'::jsonb,'knee','right'),

-- Reflexology.
('framework_concept','reflexology_head_brain_reflex_area','body_region','head','head','framework_correspondence_map',
 'Reflexology map review','reflexology_zone_therapy',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624523/","https://pmc.ncbi.nlm.nih.gov/articles/PMC12303304/"]}'::jsonb,
 'high','Reflexology sources label hand/foot areas as corresponding to head/brain structures.','active',
 '{"does_not_establish":["anatomical_connection","physiological_mechanism"]}'::jsonb,'head',null),

('framework_concept','reflexology_knee_reflex_area','body_region','knee','knee','framework_correspondence_map',
 'Reflexology map review','reflexology_zone_therapy',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624523/"]}'::jsonb,
 'medium','Reflexology literature describes body-zone mappings extending through knee-level body areas; map conventions vary.','active',
 '{"does_not_establish":["anatomical_connection","physiological_mechanism"]}'::jsonb,'knee',null),

-- Energy medicine / biofield.
('framework_concept','biofield_energy_medicine_term','sensation','ache','ache','framework_vocabulary_studied_in_pain_context',
 'Biofield terminology + pain research','biofield_energy_healing',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4654789/","https://pmc.ncbi.nlm.nih.gov/articles/PMC13490130/"]}'::jsonb,
 'medium','Energy medicine is an umbrella term and biofield modalities have been studied in pain contexts; retrieval does not establish efficacy.','active',
 '{"does_not_establish":["efficacy","mechanism"]}'::jsonb,null,null),

('framework_concept','biofield_therapy_term','sensation','ache','ache','modality_family_studied_in_pain_context',
 'Biofield clinical literature','biofield_energy_healing',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4654788/","https://pmc.ncbi.nlm.nih.gov/articles/PMC13490130/"]}'::jsonb,
 'medium','Biofield therapies are a modality family studied in pain populations; evidence quality and findings vary.','active',
 '{"does_not_establish":["efficacy","mechanism"]}'::jsonb,null,null),

-- Canon: direct body vocabulary and explicitly bounded adjacent motion vocabulary.
('canon_organic_term','heb_rosh_head','body_region','head','head','lexical_body_sense',
 'Noel Strong''s registry + canonical token occurrences',null,
 '{"strong_id":"H7218","sample_physical_attestations":["1Sa 1:11","1Sa 17:5","2Sa 13:19"]}'::jsonb,
 'high','Hebrew rosh has a direct bodily head sense while also having non-bodily senses.','active',
 '{"definition_ceiling":"do_not_make_headship_or_theological_claim_from_body_selection"}'::jsonb,'head',null),

('canon_organic_term','gr_kephale_head','body_region','head','head','lexical_body_sense',
 'Noel Greek token corpus + Strong''s registry',null,
 '{"strong_id":"G2776","sample_physical_attestations":["Mat 5:36","Mat 6:17","Jhn 20:12"]}'::jsonb,
 'high','Greek kephale has direct bodily head attestations alongside relational/metaphorical uses.','active',
 '{"definition_ceiling":"do_not_infer_headship_function"}'::jsonb,'head',null),

('canon_organic_term','heb_berek_knee','body_region','knee','knee','lexical_body_sense',
 'Noel Strong''s registry + canonical token occurrences',null,
 '{"strong_id":"H1290"}'::jsonb,
 'high','Hebrew berek is canonical knee vocabulary; posture/function requires clause-level study.','active',
 '{"definition_ceiling":"do_not_infer_submission_or_weakness_from_knee_alone"}'::jsonb,'knee',null),

('canon_organic_term','gr_gony_knee','body_region','knee','knee','lexical_body_sense',
 'Noel Greek token corpus + Strong''s registry',null,
 '{"strong_id":"G1119","sample_attestations":["Luk 5:8","Eph 3:14","Heb 12:12"]}'::jsonb,
 'high','Greek gony is canonical knee vocabulary; kneeling or other action remains separate.','active',
 '{"definition_ceiling":"do_not_infer_worship_or_submission_from_knee_alone"}'::jsonb,'knee',null),

('canon_organic_term','heb_nuwa_reel_stagger','reported_symptom','dizziness','dizziness','structurally_adjacent_motion_vocabulary',
 'Noel Strong''s registry + token occurrences',null,
 '{"strong_id":"H5128","physical_motion_attestations":["Psa 107:27","Isa 24:20","Isa 29:9"]}'::jsonb,
 'medium','Hebrew nuwa includes reel/stagger/totter motion in some passages. This is adjacent to instability language, not a synonym for subjective dizziness.','active',
 '{"not_equivalent_to":"dizziness","polysemy":["move","shake","wander","sift"]}'::jsonb,null,null),

('canon_organic_term','heb_taah_wander_stagger','reported_symptom','dizziness','dizziness','structurally_adjacent_motion_vocabulary',
 'Noel Strong''s registry + token occurrences',null,
 '{"strong_id":"H8582","stagger_attestations":["Job 12:25","Isa 19:14"]}'::jsonb,
 'medium','Hebrew taah is used for wandering/erring and in some clauses staggering; retrieval is structural adjacency only.','active',
 '{"not_equivalent_to":"dizziness","definition_ceiling":"separate physical staggering from mental_moral error"}'::jsonb,null,null)

on conflict
(object_type,object_id,dimension_key,normalized_value,relation_type,coalesce(framework_key,''),coalesce(scope_region_key,''),coalesce(scope_side,''))
do update set
  dimension_value=excluded.dimension_value,
  source_basis=excluded.source_basis,
  evidence_ref=excluded.evidence_ref,
  confidence=excluded.confidence,
  rationale=excluded.rationale,
  status=excluded.status,
  metadata=excluded.metadata,
  updated_at=now();

-- Replay-time acceptance checks.
do $validation$
declare
  v_query jsonb := '{
    "selections":[
      {"region_key":"head","features":[
        {"dimension_key":"sensation","value":"pressure"},
        {"dimension_key":"reported_symptom","value":"dizziness"}
      ]},
      {"region_key":"knee","side":"right","features":[
        {"dimension_key":"sensation","value":"ache"},
        {"dimension_key":"temporal_pattern","value":"intermittent"}
      ]}
    ]
  }'::jsonb;
  v_count integer;
begin
  select count(*) into v_count
  from intelligence.search_body_map_vocabulary_v2(v_query,500);

  if v_count < 50 then
    raise exception 'Body-map proving query returned only % vocabulary objects; expected at least 50.',v_count;
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label='Aspirin'
  ) then
    raise exception 'Body-map proving query did not recover Aspirin vocabulary.';
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label='Energy medicine'
  ) then
    raise exception 'Body-map proving query did not recover energy-medicine vocabulary.';
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label='Concussion / mild traumatic brain injury'
  ) then
    raise exception 'Body-map proving query did not recover concussion vocabulary.';
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label='Intermitting pain — right knee'
      and matched_feature_count>=2
  ) then
    raise exception 'Body-map proving query did not preserve the source-attested right-knee intermittent homeopathy vocabulary.';
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label='骨痹 — bone impediment'
  ) then
    raise exception 'Body-map proving query did not recover TCM bone-impediment vocabulary.';
  end if;

  if not exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(v_query,500)
    where display_label in ('rosh','kephale','berek','gony')
      and source_jurisdiction='canon_vocabulary'
  ) then
    raise exception 'Body-map proving query did not recover bounded canon body vocabulary.';
  end if;

  -- Critical anti-cross-talk proof:
  -- intermittency attached to HEAD may not retrieve knee-scoped intermittent objects.
  if exists(
    select 1
    from intelligence.search_body_map_vocabulary_v2(
      '{"selections":[{"region_key":"head","features":[{"dimension_key":"temporal_pattern","value":"intermittent"}]}]}'::jsonb,
      500
    )
    where object_id in (
      'biomed_intermittent_knee_pain',
      'homeopathy_intermit_right_knee_pain',
      'biomed_knee_osteoarthritis'
    )
  ) then
    raise exception 'Region scope failure: head intermittency reached knee-scoped vocabulary.';
  end if;

  if coalesce((
    select retrieval_lane_count
    from intelligence.v_body_map_query_value_gap_queue_v2
    where dimension_key='reported_symptom' and value_key='dizziness'
  ),0) < 4 then
    raise exception 'Dizziness proving vocabulary did not retain at least four independent retrieval lanes.';
  end if;

  if coalesce((
    select retrieval_lane_count
    from intelligence.v_body_map_query_value_gap_queue_v2
    where dimension_key='sensation' and value_key='ache'
  ),0) < 4 then
    raise exception 'Ache proving vocabulary did not retain at least four independent retrieval lanes.';
  end if;

  if has_function_privilege(
       'anon',
       'intelligence.search_body_map_vocabulary_v2(jsonb,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'intelligence.search_body_map_vocabulary_v2(jsonb,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'service_role',
       'intelligence.search_body_map_vocabulary_v2(jsonb,integer)',
       'EXECUTE'
     ) then
    raise exception 'Body-map search execution boundary is not service-only.';
  end if;

  if to_regprocedure('intelligence.search_body_map_vocabulary_v1(jsonb,integer)') is not null then
    raise exception 'Superseded pre-scope body-map search v1 is still present.';
  end if;
end;
$validation$;

commit;
