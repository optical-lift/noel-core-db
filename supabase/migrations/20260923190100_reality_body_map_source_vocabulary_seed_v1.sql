begin;

-- Source-native vocabulary seed for the first body-map proving packet:
-- head + pressure + dizziness / right knee + ache + intermittent.
--
-- These rows capture vocabulary used by source traditions.
-- They do not assert that traditions are equivalent, equally evidenced,
-- diagnostically correct, clinically appropriate, or causally true.

insert into draft.reality_framework_concepts
(concept_key,framework_key,native_id,preferred_label,normalized_label,concept_kind,source_language,native_definition,parent_concept_key,concept_status,notes,metadata)
values
('biomed_dizziness_term','conventional_biomedicine',null,'Dizziness','dizziness','reported_symptom_term','en',
 'An imprecise patient-reported symptom term that clinical literature may further distinguish as vertigo, disequilibrium, presyncope, or lightheadedness.',
 null,'supported','Vocabulary capture only; does not establish cause.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/","https://pubmed.ncbi.nlm.nih.gov/21250167/"],"does_not_establish":["diagnosis","etiology"]}'::jsonb),

('biomed_vertigo_term','conventional_biomedicine',null,'Vertigo','vertigo','symptom_classification','en',
 'A dizziness subtype characterized by an illusory or false sense of motion or spinning.',
 null,'supported','Clinical subdivision of dizziness; not inferred without further description.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/","https://pubmed.ncbi.nlm.nih.gov/21250167/"],"requires":["motion_or_spinning_description"]}'::jsonb),

('biomed_disequilibrium_term','conventional_biomedicine',null,'Disequilibrium','disequilibrium','symptom_classification','en',
 'A dizziness subtype describing imbalance or gait instability.',
 null,'supported','Clinical subdivision of dizziness.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/","https://pubmed.ncbi.nlm.nih.gov/21250167/"]}'::jsonb),

('biomed_presyncope_term','conventional_biomedicine',null,'Presyncope','presyncope','symptom_classification','en',
 'A dizziness subtype describing a feeling of nearly fainting or blacking out.',
 null,'supported','Clinical subdivision of dizziness.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb),

('biomed_lightheadedness_term','conventional_biomedicine',null,'Lightheadedness','lightheadedness','symptom_classification','en',
 'A nonspecific lightheaded sensation used as one clinical subdivision of dizziness.',
 null,'supported','Clinical subdivision of dizziness.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/38823940/"]}'::jsonb),

('biomed_headache_term','conventional_biomedicine','D006261','Headache / cephalgia','headache','symptom_classification','en',
 'Pain in the cranial region; MeSH also indexes cephalalgia, cephalgia, cephalodynia, cranial pain, and head pain as entry terms.',
 null,'supported','MeSH vocabulary.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68006261"],"mesh_id":"D006261","does_not_establish":["headache_disorder","etiology"]}'::jsonb),

('biomed_pressing_tightening_headache_quality','conventional_biomedicine',null,'Pressing / tightening head-pain quality','pressing tightening head pain','symptom_quality','en',
 'Head pain described as pressing or tightening, often compared with a tight band around the head.',
 null,'supported','ICHD vocabulary quality; does not establish tension-type headache.',
 '{"sources":["https://ichd-3.org/definition-of-terms/"],"does_not_establish":["tension_type_headache","etiology"]}'::jsonb),

('biomed_tension_type_headache','conventional_biomedicine','D018781','Tension-type headache','tension type headache','diagnostic_concept','en',
 'A primary headache disorder characterized in MeSH by dull, non-pulsatile, diffuse, band-like or vice-like head pain.',
 null,'supported','Condition vocabulary only; pressure language alone does not establish this diagnosis.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68018781"],"requires":["full_diagnostic_criteria"]}'::jsonb),

('biomed_vestibular_migraine','conventional_biomedicine','D000099099','Vestibular migraine','vestibular migraine','diagnostic_concept','en',
 'A MeSH diagnostic concept for vertigo or major dizziness associated with migraine affecting the vestibular system.',
 null,'supported','Condition vocabulary only; dizziness alone does not establish it.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/2108908"],"mesh_id":"D000099099","requires":["migraine_context","diagnostic_evaluation"]}'::jsonb),

('biomed_concussion_mild_tbi','conventional_biomedicine',null,'Concussion / mild traumatic brain injury','concussion mild traumatic brain injury','diagnostic_concept','en',
 'A mild traumatic brain injury concept for which headache and dizziness or balance problems can occur among symptoms.',
 null,'supported','Requires an injury context; this query does not establish concussion.',
 '{"sources":["https://www.cdc.gov/traumatic-brain-injury/signs-symptoms/index.html"],"requires":["head_or_body_impact_context","clinical_assessment"]}'::jsonb),

('biomed_pain_ache','conventional_biomedicine','D010146','Pain / ache','pain ache','symptom_term','en',
 'Pain is a MeSH concept whose entry terms include ache and aches.',
 null,'supported','Vocabulary relation from NLM MeSH.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68010146"],"mesh_id":"D010146"}'::jsonb),

('biomed_arthralgia','conventional_biomedicine','D018771','Arthralgia / joint pain','arthralgia joint pain','symptom_classification','en',
 'Pain in a joint; MeSH includes joint pain as an entry term.',
 null,'supported','Applicable vocabulary for pain located at a joint such as the knee; not equivalent to inflammatory arthritis.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/D018771"],"mesh_id":"D018771","does_not_establish":["arthritis"]}'::jsonb),

('biomed_patellofemoral_pain','conventional_biomedicine','D046788','Patellofemoral pain / anterior knee pain','patellofemoral pain','diagnostic_concept','en',
 'A syndrome characterized by retropatellar or peripatellar pain and indexed with anterior knee pain terminology.',
 null,'supported','Specific knee-pain vocabulary; generic knee ache does not establish the syndrome.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/D046788"],"mesh_id":"D046788","requires":["patellofemoral_localization_or_clinical_criteria"]}'::jsonb),

('biomed_intermittent_knee_pain','conventional_biomedicine',null,'Intermittent knee pain','intermittent knee pain','symptom_pattern','en',
 'A knee-pain temporal pattern distinguished from constant pain in osteoarthritis research and measured using instruments such as ICOAP.',
 null,'supported','Descriptive research vocabulary; does not imply osteoarthritis.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://pubmed.ncbi.nlm.nih.gov/32198833/"],"does_not_establish":["osteoarthritis"]}'::jsonb),

('biomed_knee_osteoarthritis','conventional_biomedicine',null,'Knee osteoarthritis','knee osteoarthritis','diagnostic_concept','en',
 'A joint disease in which research distinguishes intermittent and constant knee-pain patterns.',
 null,'supported','Condition vocabulary surfaced because literature explicitly studies this pattern; this query does not diagnose OA.',
 '{"sources":["https://pubmed.ncbi.nlm.nih.gov/25376465/","https://pubmed.ncbi.nlm.nih.gov/32198833/"],"requires":["clinical_and_or_radiographic_assessment"]}'::jsonb),

('biomed_aspirin','conventional_biomedicine','D001241','Aspirin','aspirin','drug_intervention','en',
 'A prototypical analgesic used for mild to moderate pain, with anti-inflammatory, antipyretic, and platelet-inhibiting properties.',
 null,'supported','Intervention vocabulary only; retrieval is not a treatment recommendation.',
 '{"sources":["https://www.ncbi.nlm.nih.gov/mesh/68001241"],"mesh_id":"D001241","does_not_establish":["appropriateness_for_this_person","dose","safety"]}'::jsonb),

('tcm_vertigo_dizziness_category','classical_tcm',null,'眩晕 — vertigo / dizziness category','tcm vertigo dizziness','symptom_category','zh',
 'A traditional Chinese medicine symptom/category vocabulary used in literature discussing vertigo or dizziness.',
 null,'working','Framework-native terminology; does not assert a biomedical mechanism.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC5474245/"],"jurisdiction":"classical_tcm"}'::jsonb),

('tcm_wind_phlegm_dizziness_pattern','classical_tcm',null,'Wind-phlegm / phlegm-stasis dizziness pattern','wind phlegm dizziness','pattern_context','en',
 'A TCM pattern vocabulary used in cervicogenic-dizziness literature.',
 null,'working','Not inferred as present from dizziness alone.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"],"requires":["tcm_pattern_differentiation"]}'::jsonb),

('tcm_liver_yang_dizziness_pattern','classical_tcm',null,'Hyperactivity / ascendance of liver yang','liver yang dizziness','pattern_context','en',
 'A TCM pattern vocabulary used in dizziness or vertigo literature.',
 null,'working','Not inferred as present from dizziness alone.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"],"requires":["tcm_pattern_differentiation"]}'::jsonb),

('tcm_qi_blood_deficiency_dizziness_pattern','classical_tcm',null,'Qi and blood deficiency pattern','qi blood deficiency dizziness','pattern_context','en',
 'A TCM pattern vocabulary used in dizziness or vertigo literature.',
 null,'working','Not inferred as present from dizziness alone.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC9110151/"],"requires":["tcm_pattern_differentiation"]}'::jsonb),

('tcm_bone_impediment_knee','classical_tcm',null,'骨痹 — bone impediment','bone impediment','diagnostic_category','zh',
 'A TCM category used in integrative clinical literature to classify knee osteoarthritis.',
 null,'working','A knee ache does not establish this category.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC10617515/"]}'::jsonb),

('tcm_bi_syndrome_knee','classical_tcm',null,'痹病 / 痹证 — bi syndrome / impediment disease','bi syndrome','diagnostic_category','zh',
 'A TCM impediment-disease category used for painful or obstructive joint presentations including knee osteoarthritis in cited literature.',
 null,'working','Does not establish a biomedical diagnosis or TCM subtype.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624358/","https://pmc.ncbi.nlm.nih.gov/articles/PMC10617515/"]}'::jsonb),

('homeopathy_dizziness_rubric','classical_homeopathy',null,'Dizziness','homeopathy dizziness','repertory_rubric','en',
 'A repertory heading under Sensorium in Hering/Knerr, alongside giddiness, reeling, staggering, swaying, and vertigo.',
 null,'working','Historical framework-native vocabulary; retrieval does not establish remedy selection or efficacy.',
 '{"sources":["https://www.homeoint.org/hering/dizziness.htm"],"does_not_establish":["remedy_indication","efficacy"]}'::jsonb),

('homeopathy_vertigo_rubric','classical_homeopathy',null,'Vertigo','homeopathy vertigo','repertory_rubric','en',
 'A classical homeopathic repertory/symptom term adjacent to dizziness.',
 null,'working','Historical framework-native vocabulary.',
 '{"sources":["https://www.homeoint.org/hering/dizziness.htm"],"does_not_establish":["remedy_indication","efficacy"]}'::jsonb),

('homeopathy_head_pressure_fullness_rubric','classical_homeopathy',null,'Head — pressure / fullness / pressive pain','homeopathy head pressure fullness','repertory_rubric','en',
 'Classical materia medica language describing head pressure, fullness, heaviness, or pressive pain.',
 null,'working','Historical framework-native vocabulary.',
 '{"sources":["https://www.homeoint.org/hering/a/aesc-1.htm","https://www.homeoint.org/hering/b/bism.htm"],"does_not_establish":["remedy_indication","efficacy"]}'::jsonb),

('homeopathy_right_knee_pain_rubric','classical_homeopathy',null,'Right knee pain','homeopathy right knee pain','repertory_rubric','en',
 'Classical materia medica language recording pain localized to the right knee.',
 null,'working','Historical framework-native vocabulary.',
 '{"sources":["https://www.homeoint.org/hering/c/cinnb-3.htm","https://www.homeoint.org/hering/a/aesc-3.htm"],"does_not_establish":["remedy_indication","efficacy"]}'::jsonb),

('homeopathy_intermit_right_knee_pain','classical_homeopathy',null,'Intermitting pain — right knee','homeopathy intermitting right knee pain','repertory_rubric','en',
 'A source-attested classical homeopathic symptom phrase recording slight intermitting pains in the right knee joint.',
 null,'working','Historical framework-native vocabulary.',
 '{"sources":["https://homeoint.org/hering/t/trom.htm"],"does_not_establish":["remedy_indication","efficacy"]}'::jsonb),

('reflexology_head_brain_reflex_area','reflexology_zone_therapy',null,'Head / brain reflex area','reflexology head brain reflex area','correspondence_map','en',
 'Reflexology-map vocabulary assigning hand or foot reflex areas to the head, brain, or related head structures.',
 null,'working','Framework-native correspondence map, not an anatomical or physiological equivalence.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624523/","https://pmc.ncbi.nlm.nih.gov/articles/PMC12303304/"],"does_not_establish":["anatomical_connection","clinical_effect"]}'::jsonb),

('reflexology_knee_reflex_area','reflexology_zone_therapy',null,'Knee reflex area','reflexology knee reflex area','correspondence_map','en',
 'Reflexology-map vocabulary assigning hand or foot reflex areas or body zones to the knee.',
 null,'working','Framework-native correspondence map; maps vary across schools.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4624523/"],"does_not_establish":["anatomical_connection","clinical_effect"]}'::jsonb),

('biofield_energy_medicine_term','biofield_energy_healing',null,'Energy medicine','energy medicine','framework_term','en',
 'A broad term used for practices and explanatory models involving energy or informational fields in health and healing.',
 null,'working','Source-native umbrella terminology; mechanisms and evidence vary across modalities.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4654789/"],"does_not_establish":["single_mechanism","efficacy"]}'::jsonb),

('biofield_therapy_term','biofield_energy_healing',null,'Biofield therapy','biofield therapy','therapeutic_modality_family','en',
 'A term used for practitioner-based approaches such as Reiki, Healing Touch, and Therapeutic Touch that explicitly work with a proposed biofield.',
 null,'working','Framework/research vocabulary; evidence and mechanisms remain contested and modality-specific.',
 '{"sources":["https://pmc.ncbi.nlm.nih.gov/articles/PMC4654788/","https://pmc.ncbi.nlm.nih.gov/articles/PMC13490130/"],"does_not_establish":["efficacy","biofield_mechanism"]}'::jsonb)
on conflict (concept_key) do update set
  framework_key=excluded.framework_key,
  native_id=excluded.native_id,
  preferred_label=excluded.preferred_label,
  normalized_label=excluded.normalized_label,
  concept_kind=excluded.concept_kind,
  source_language=excluded.source_language,
  native_definition=excluded.native_definition,
  parent_concept_key=excluded.parent_concept_key,
  concept_status=excluded.concept_status,
  notes=excluded.notes,
  metadata=excluded.metadata,
  updated_at=now();

-- Canon vocabulary enters only after checking Noel's underlying token/Strong's corpus.
-- These are lexical/body or adjacent-motion terms, not symptom-to-spiritual-meaning mappings.

insert into draft.canon_organic_terms
(term_key,language_code,lemma,transliteration,strong_id,term_kind,neutral_gloss,source_status,definition_ceiling,notes)
values
('heb_rosh_head','he','ראש','rosh','H7218','part','head / top / chief','measured',
 'Do not assume a physical human head from the lexeme alone; the corpus also uses the token for top, chief, beginning and other relations. Body-map retrieval exposes a lexical body sense, not a theological diagnosis.',
 'Recovered from Noel public.strongs plus token occurrences; numerous direct physical-head attestations.'),

('heb_berek_knee','he','ברך','berek','H1290','part','knee','measured',
 'Do not infer posture, submission, weakness, fear, or spiritual meaning from knee alone; adjudicate each clause.',
 'Recovered from Noel public.strongs and canonical token occurrences.'),

('gr_kephale_head','gr','κεφαλή','kephale','G2776','part','head','measured',
 'Do not collapse bodily head, metaphorical headship, top/relational uses, or theological interpretation. Body-map retrieval exposes the bodily lexical sense only.',
 'Recovered from Noel Greek token occurrences and Strong''s registry.'),

('gr_gony_knee','gr','γόνυ','gony','G1119','part','knee','measured',
 'Do not infer kneeling, worship, submission, weakness, or function merely from the knee lexeme; inspect syntax and action.',
 'Recovered from Noel Greek token occurrences and Strong''s registry.'),

('heb_nuwa_reel_stagger','he','נוע','nuwa','H5128','process','quiver / totter / shake / reel / stagger / wander','candidate',
 'This motion vocabulary is not a synonym for subjective dizziness. It may be retrieved only as structurally adjacent bodily-instability language where source context supports staggering or reeling.',
 'Noel token occurrences include Psalm 107:27 stagger and Isaiah 24:20 reel; other occurrences mean move, shake, wander, sift, etc.'),

('heb_taah_wander_stagger','he','תעה','taah','H8582','process','err / wander / go astray / stagger','candidate',
 'Do not collapse physical wandering or staggering with mental, moral, or theological error. Retrieval beside dizziness is adjacency only, not synonymy.',
 'Noel token occurrences include Job 12:25 and Isaiah 19:14 with stagger language, alongside many non-bodily uses.')
on conflict (term_key) do update set
  language_code=excluded.language_code,
  lemma=excluded.lemma,
  transliteration=excluded.transliteration,
  strong_id=excluded.strong_id,
  term_kind=excluded.term_kind,
  neutral_gloss=excluded.neutral_gloss,
  source_status=excluded.source_status,
  definition_ceiling=excluded.definition_ceiling,
  notes=excluded.notes,
  updated_at=now();

commit;
