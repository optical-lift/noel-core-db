-- Reality Witness object/coordinate projections v2

create or replace view intelligence.v_reality_witness_objects_v1
with (security_invoker=true)
as
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    COALESCE(NULLIF(bo.raw_language, ''::text), bo.normalized_state, bo.observation_type) AS object_label,
    bo.observation_type AS object_kind,
    bo.status AS source_status,
    'practice_person'::text AS subject_ref_type,
    p.person_key AS subject_ref,
    COALESCE(bo.observed_at, s.started_at, bo.created_at) AS occurred_at,
    COALESCE(NULLIF(bo.raw_language, ''::text), bo.normalized_state) AS native_definition,
    jsonb_build_object('sessionId', bo.session_id, 'regionKey', bo.region_key, 'side', bo.side, 'reportedBy', bo.reported_by, 'intensityValue', bo.intensity_value, 'intensityScale', bo.intensity_scale, 'onsetText', bo.onset_text, 'researchObservationId', bo.research_observation_id) AS metadata
   FROM practice.body_observations bo
     JOIN practice.sessions s USING (session_id)
     JOIN practice.people p USING (person_id)
UNION ALL
 SELECT 'practice_context_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_context_observation'::text AS object_type,
    co.context_observation_id::text AS object_id,
    COALESCE(NULLIF(co.raw_language, ''::text), co.normalized_context, co.context_type) AS object_label,
    co.context_type AS object_kind,
    'recorded'::text AS source_status,
    'practice_person'::text AS subject_ref_type,
    p.person_key AS subject_ref,
    COALESCE(co.observed_at, s.started_at, co.created_at) AS occurred_at,
    COALESCE(NULLIF(co.raw_language, ''::text), co.normalized_context) AS native_definition,
    jsonb_build_object('sessionId', co.session_id, 'contextType', co.context_type, 'contextSubject', co.context_subject, 'valence', co.valence, 'intensityValue', co.intensity_value, 'intensityScale', co.intensity_scale, 'reportedBy', co.reported_by) AS metadata
   FROM practice.context_observations co
     JOIN practice.sessions s USING (session_id)
     JOIN practice.people p USING (person_id)
UNION ALL
 SELECT 'practice_intervention'::text AS adapter_key,
    'practice:intervention'::text AS witness_key,
    'practice_intervention'::text AS object_type,
    i.intervention_id::text AS object_id,
    COALESCE(NULLIF(i.practice_label, ''::text), NULLIF(i.exact_words, ''::text), i.intervention_type) AS object_label,
    i.intervention_type AS object_kind,
    'recorded'::text AS source_status,
    'practice_person'::text AS subject_ref_type,
    p.person_key AS subject_ref,
    COALESCE(s.started_at, i.created_at) AS occurred_at,
    COALESCE(NULLIF(i.exact_words, ''::text), NULLIF(i.practice_label, ''::text), i.intervention_type) AS native_definition,
    jsonb_build_object('sessionId', i.session_id, 'sequenceNo', i.sequence_no, 'targetRegionKey', i.target_region_key, 'targetSide', i.target_side, 'materialOrInput', i.material_or_input, 'durationText', i.duration_text, 'operatorIntent', i.operator_intent) AS metadata
   FROM practice.interventions i
     JOIN practice.sessions s USING (session_id)
     JOIN practice.people p USING (person_id)
UNION ALL
 SELECT 'practice_outcome'::text AS adapter_key,
    'practice:outcome'::text AS witness_key,
    'practice_outcome'::text AS object_type,
    o.outcome_id::text AS object_id,
    o.outcome_text AS object_label,
    o.outcome_type AS object_kind,
    'recorded'::text AS source_status,
    'practice_person'::text AS subject_ref_type,
    p.person_key AS subject_ref,
    COALESCE(o.observed_at, s.started_at, o.created_at) AS occurred_at,
    o.outcome_text AS native_definition,
    jsonb_build_object('sessionId', o.session_id, 'interventionId', o.intervention_id, 'bodyObservationId', o.body_observation_id, 'direction', o.direction, 'magnitudeValue', o.magnitude_value, 'magnitudeScale', o.magnitude_scale, 'durability', o.durability, 'reportedBy', o.reported_by) AS metadata
   FROM practice.outcomes o
     JOIN practice.sessions s USING (session_id)
     JOIN practice.people p USING (person_id)
UNION ALL
 SELECT 'practice_discernment_signal'::text AS adapter_key,
    'practice:discernment'::text AS witness_key,
    'practice_discernment_signal'::text AS object_type,
    d.discernment_signal_id::text AS object_id,
    d.question_or_statement AS object_label,
    d.signal_type AS object_kind,
    COALESCE(d.practice_truth_status, 'recorded'::text) AS source_status,
    'practice_person'::text AS subject_ref_type,
    p.person_key AS subject_ref,
    COALESCE(d.observed_at, s.started_at, d.created_at) AS occurred_at,
    COALESCE(NULLIF(d.raw_response, ''::text), d.normalized_response) AS native_definition,
    jsonb_build_object('sessionId', d.session_id, 'interventionId', d.intervention_id, 'bodyObservationId', d.body_observation_id, 'normalizedResponse', d.normalized_response, 'responseDirection', d.response_direction, 'interpretedAnswer', d.interpreted_answer, 'operatorInterpretation', d.operator_interpretation, 'confidence', d.confidence, 'functionKey', d.function_key, 'songObjectId', d.song_object_id, 'cleanAnswer', d.clean_answer, 'clearingRequired', d.clearing_required, 'clearingFormulaUsed', d.clearing_formula_used, 'postClearing', d.post_clearing) AS metadata
   FROM practice.discernment_signals d
     JOIN practice.sessions s USING (session_id)
     JOIN practice.people p USING (person_id)
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    bs.body_key AS object_label,
    'measured_body_state'::text AS object_kind,
    cs.computation_status AS source_status,
        CASE
            WHEN ci.subject_ref IS NULL THEN NULL::text
            ELSE 'celestial_subject'::text
        END AS subject_ref_type,
    ci.subject_ref,
    bs.sample_time_utc AS occurred_at,
    bs.body_key AS native_definition,
    jsonb_build_object('snapshotId', bs.snapshot_id, 'chartInputId', ci.chart_input_id, 'chartKey', ci.chart_key, 'chartKind', ci.chart_kind, 'eclipticLongitudeDeg', bs.ecliptic_longitude_deg, 'eclipticLatitudeDeg', bs.ecliptic_latitude_deg, 'rightAscensionDeg', bs.right_ascension_deg, 'declinationDeg', bs.declination_deg, 'altitudeDeg', bs.altitude_deg, 'azimuthDeg', bs.azimuth_deg, 'distanceAu', bs.distance_au, 'apparentMagnitude', bs.apparent_magnitude, 'longitudeSpeedDegDay', bs.longitude_speed_deg_day, 'retrograde', bs.retrograde, 'visibilityState', bs.visibility_state, 'horizonState', bs.horizon_state, 'observationalState', bs.observational_state, 'uncertainty', bs.uncertainty, 'provenance', bs.provenance) AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
     JOIN draft.celestial_chart_inputs ci USING (chart_input_id)
UNION ALL
 SELECT 'celestial_chart_event'::text AS adapter_key,
    'celestial:event_recognition'::text AS witness_key,
    'celestial_chart_event'::text AS object_type,
    ce.chart_event_id::text AS object_id,
    ce.event_key AS object_label,
    ce.raw_event_family AS object_kind,
    ce.recognition_status AS source_status,
        CASE
            WHEN ci.subject_ref IS NULL THEN NULL::text
            ELSE 'celestial_subject'::text
        END AS subject_ref_type,
    ci.subject_ref,
    COALESCE(ce.event_exact_utc, ce.event_start_utc, cs.computed_for_utc) AS occurred_at,
    ce.raw_event_family AS native_definition,
    jsonb_build_object('snapshotId', ce.snapshot_id, 'chartInputId', ci.chart_input_id, 'chartKey', ci.chart_key, 'chartKind', ci.chart_kind, 'grammarKey', ce.grammar_key, 'primaryBodyKey', ce.primary_body_key, 'secondaryBodyKey', ce.secondary_body_key, 'eventStartUtc', ce.event_start_utc, 'eventExactUtc', ce.event_exact_utc, 'eventEndUtc', ce.event_end_utc, 'eventParameters', ce.event_parameters, 'computationConfidence', ce.computation_confidence, 'uncertainty', ce.uncertainty, 'provenance', ce.provenance) AS metadata
   FROM draft.celestial_chart_events ce
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
     JOIN draft.celestial_chart_inputs ci USING (chart_input_id)
UNION ALL
 SELECT 'framework_concept'::text AS adapter_key,
    'framework:'::text || fc.framework_key AS witness_key,
    'framework_concept'::text AS object_type,
    fc.concept_key AS object_id,
    fc.preferred_label AS object_label,
    fc.concept_kind AS object_kind,
    fc.concept_status AS source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    fc.created_at AS occurred_at,
    fc.native_definition,
    fc.metadata || jsonb_build_object('frameworkKey', fc.framework_key, 'nativeId', fc.native_id, 'normalizedLabel', fc.normalized_label, 'sourceLanguage', fc.source_language, 'parentConceptKey', fc.parent_concept_key) AS metadata
   FROM draft.reality_framework_concepts fc
UNION ALL
 SELECT 'canon_organic_term'::text AS adapter_key,
    'jurisdiction:canon_vocabulary'::text AS witness_key,
    'canon_organic_term'::text AS object_type,
    c.term_key AS object_id,
    COALESCE(NULLIF(c.transliteration, ''::text), c.lemma, c.neutral_gloss) AS object_label,
    c.term_kind AS object_kind,
    c.source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    c.created_at AS occurred_at,
    c.neutral_gloss AS native_definition,
    jsonb_build_object('languageCode', c.language_code, 'lemma', c.lemma, 'transliteration', c.transliteration, 'strongId', c.strong_id, 'notes', c.notes) AS metadata
   FROM draft.canon_organic_terms c
UNION ALL
 SELECT 'function_registry'::text AS adapter_key,
    'jurisdiction:noel_function'::text AS witness_key,
    'function'::text AS object_type,
    f.function_key AS object_id,
    f.function_name AS object_label,
    'function'::text AS object_kind,
    f.status AS source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    f.created_at AS occurred_at,
    f.working_definition AS native_definition,
    jsonb_build_object('beforeState', f.before_state, 'operation', f.operation, 'afterState', f.after_state, 'lawfulSource', f.lawful_source, 'intendedFruit', f.intended_fruit, 'failureMode', f.failure_mode, 'clarityState', f.clarity_state) AS metadata
   FROM draft.function_registry f
UNION ALL
 SELECT 'song_object'::text AS adapter_key,
    'jurisdiction:song'::text AS witness_key,
    'song_object'::text AS object_type,
    s.song_object_id::text AS object_id,
    s.object_name AS object_label,
    s.object_type AS object_kind,
    s.object_status AS source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    s.created_at AS occurred_at,
    s.one_sentence_claim AS native_definition,
    jsonb_build_object('provisionalFunctionLane', s.provisional_function_lane, 'mainstreamRivalReading', s.mainstream_rival_reading, 'notes', s.notes) AS metadata
   FROM draft.song_objects s
UNION ALL
 SELECT 'research_claim'::text AS adapter_key,
    'jurisdiction:research_claim'::text AS witness_key,
    'research_claim'::text AS object_type,
    r.claim_id::text AS object_id,
    r.claim_title AS object_label,
    r.claim_kind AS object_kind,
    r.claim_status AS source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    r.created_at AS occurred_at,
    r.short_claim AS native_definition,
    jsonb_build_object('claimKey', r.claim_key, 'currentCategory', r.current_category, 'liveTest', r.live_test, 'evidenceNeeded', r.evidence_needed, 'strengthensIf', r.strengthens_if, 'weakensIf', r.weakens_if, 'confidence', r.confidence) AS metadata
   FROM draft.research_claims r;;

comment on view intelligence.v_reality_witness_objects_v1 is
'Universal thin envelope over native witness objects. Source records remain authoritative in their native tables; this view exposes only identity, witness, subject/time where available, source-native label/definition, status, and metadata needed for alignment.';

create or replace view intelligence.v_reality_witness_object_coordinates_v1
with (security_invoker=true)
as
 SELECT
        CASE
            WHEN d.object_type = 'framework_concept'::text THEN 'framework_concept'::text
            WHEN d.object_type = 'canon_organic_term'::text THEN 'canon_organic_term'::text
            WHEN d.object_type = 'function'::text THEN 'function_registry'::text
            WHEN d.object_type = 'song_object'::text THEN 'song_object'::text
            WHEN d.object_type = 'research_claim'::text THEN 'research_claim'::text
            ELSE 'descriptor'::text
        END AS adapter_key,
    o.witness_key,
    d.object_type,
    d.object_id,
    d.dimension_key,
    d.dimension_value,
    d.normalized_value,
        CASE
            WHEN d.dimension_key = ANY (ARRAY['body_region'::text, 'body_region_side'::text, 'laterality'::text]) THEN 'location'::text
            ELSE 'feature'::text
        END AS coordinate_role,
    d.relation_type AS source_relation,
    d.source_basis,
    d.confidence,
    d.status AS coordinate_status,
    d.scope_region_key,
    d.scope_side,
    jsonb_build_object('evidenceRef', d.evidence_ref) AS metadata
   FROM draft.reality_object_query_descriptors d
     JOIN intelligence.v_reality_witness_objects_v1 o ON o.object_type = d.object_type AND o.object_id = d.object_id
  WHERE d.status <> 'retired'::text
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'body_region'::text AS dimension_key,
    bo.region_key AS dimension_value,
    lower(bo.region_key) AS normalized_value,
    'location'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.region_key'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
  WHERE bo.region_key IS NOT NULL
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'laterality'::text AS dimension_key,
    bo.side AS dimension_value,
    lower(bo.side) AS normalized_value,
    'laterality'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.side'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
    bo.side AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
  WHERE bo.side IS NOT NULL AND bo.side <> 'unspecified'::text
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'body_region_side'::text AS dimension_key,
    (bo.region_key || ':'::text) || bo.side AS dimension_value,
    lower((bo.region_key || ':'::text) || bo.side) AS normalized_value,
    'location'::text AS coordinate_role,
    'native_compound'::text AS source_relation,
    'practice.body_observations.region_key+side'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
    bo.side AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
  WHERE bo.region_key IS NOT NULL AND bo.side IS NOT NULL AND bo.side <> 'unspecified'::text
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'state'::text AS dimension_key,
    bo.normalized_state AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bo.normalized_state), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'state'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.normalized_state'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'process'::text AS dimension_key,
    bo.observation_type AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bo.observation_type), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'process'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.observation_type'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'intensity'::text AS dimension_key,
    bo.intensity_value::text AS dimension_value,
    bo.intensity_value::text AS normalized_value,
    'measurement'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.intensity_value'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    jsonb_build_object('scale', bo.intensity_scale) AS metadata
   FROM practice.body_observations bo
  WHERE bo.intensity_value IS NOT NULL
UNION ALL
 SELECT 'practice_body_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_body_observation'::text AS object_type,
    bo.body_observation_id::text AS object_id,
    'onset'::text AS dimension_key,
    bo.onset_text AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bo.onset_text), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'time'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.body_observations.onset_text'::text AS source_basis,
    NULL::text AS confidence,
    bo.status AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.body_observations bo
  WHERE NULLIF(TRIM(BOTH FROM bo.onset_text), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_context_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_context_observation'::text AS object_type,
    co.context_observation_id::text AS object_id,
    'context_domain'::text AS dimension_key,
    co.context_type AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM co.context_type), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'context'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.context_observations.context_type'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.context_observations co
UNION ALL
 SELECT 'practice_context_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_context_observation'::text AS object_type,
    co.context_observation_id::text AS object_id,
    'state'::text AS dimension_key,
    co.normalized_context AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM co.normalized_context), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'state'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.context_observations.normalized_context'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.context_observations co
UNION ALL
 SELECT 'practice_context_observation'::text AS adapter_key,
    'practice:observation'::text AS witness_key,
    'practice_context_observation'::text AS object_type,
    co.context_observation_id::text AS object_id,
    'affect'::text AS dimension_key,
    co.valence AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM co.valence), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'affect'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.context_observations.valence'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.context_observations co
  WHERE NULLIF(TRIM(BOTH FROM co.valence), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_intervention'::text AS adapter_key,
    'practice:intervention'::text AS witness_key,
    'practice_intervention'::text AS object_type,
    i.intervention_id::text AS object_id,
    'body_region'::text AS dimension_key,
    i.target_region_key AS dimension_value,
    lower(i.target_region_key) AS normalized_value,
    'location'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.interventions.target_region_key'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    i.target_region_key AS scope_region_key,
        CASE
            WHEN i.target_side = 'unspecified'::text THEN NULL::text
            ELSE i.target_side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.interventions i
  WHERE i.target_region_key IS NOT NULL
UNION ALL
 SELECT 'practice_intervention'::text AS adapter_key,
    'practice:intervention'::text AS witness_key,
    'practice_intervention'::text AS object_type,
    i.intervention_id::text AS object_id,
    'action'::text AS dimension_key,
    i.intervention_type AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM i.intervention_type), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'action'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.interventions.intervention_type'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    i.target_region_key AS scope_region_key,
        CASE
            WHEN i.target_side = 'unspecified'::text THEN NULL::text
            ELSE i.target_side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.interventions i
UNION ALL
 SELECT 'practice_intervention'::text AS adapter_key,
    'practice:intervention'::text AS witness_key,
    'practice_intervention'::text AS object_type,
    i.intervention_id::text AS object_id,
    'source_term'::text AS dimension_key,
    i.practice_label AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM i.practice_label), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'source_term'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.interventions.practice_label'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    i.target_region_key AS scope_region_key,
        CASE
            WHEN i.target_side = 'unspecified'::text THEN NULL::text
            ELSE i.target_side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.interventions i
  WHERE NULLIF(TRIM(BOTH FROM i.practice_label), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_intervention'::text AS adapter_key,
    'practice:intervention'::text AS witness_key,
    'practice_intervention'::text AS object_type,
    i.intervention_id::text AS object_id,
    'input'::text AS dimension_key,
    i.material_or_input AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM i.material_or_input), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'input'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.interventions.material_or_input'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    i.target_region_key AS scope_region_key,
        CASE
            WHEN i.target_side = 'unspecified'::text THEN NULL::text
            ELSE i.target_side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.interventions i
  WHERE NULLIF(TRIM(BOTH FROM i.material_or_input), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_outcome'::text AS adapter_key,
    'practice:outcome'::text AS witness_key,
    'practice_outcome'::text AS object_type,
    o.outcome_id::text AS object_id,
    'response'::text AS dimension_key,
    o.outcome_text AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM o.outcome_text), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'response'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.outcomes.outcome_text'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.outcomes o
     LEFT JOIN practice.body_observations bo ON bo.body_observation_id = o.body_observation_id
UNION ALL
 SELECT 'practice_outcome'::text AS adapter_key,
    'practice:outcome'::text AS witness_key,
    'practice_outcome'::text AS object_type,
    o.outcome_id::text AS object_id,
    'direction'::text AS dimension_key,
    o.direction AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM o.direction), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'direction'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.outcomes.direction'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.outcomes o
     LEFT JOIN practice.body_observations bo ON bo.body_observation_id = o.body_observation_id
  WHERE NULLIF(TRIM(BOTH FROM o.direction), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_outcome'::text AS adapter_key,
    'practice:outcome'::text AS witness_key,
    'practice_outcome'::text AS object_type,
    o.outcome_id::text AS object_id,
    'temporal_pattern'::text AS dimension_key,
    o.durability AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM o.durability), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'time'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.outcomes.durability'::text AS source_basis,
    NULL::text AS confidence,
    'recorded'::text AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.outcomes o
     LEFT JOIN practice.body_observations bo ON bo.body_observation_id = o.body_observation_id
  WHERE NULLIF(TRIM(BOTH FROM o.durability), ''::text) IS NOT NULL
UNION ALL
 SELECT 'practice_discernment_signal'::text AS adapter_key,
    'practice:discernment'::text AS witness_key,
    'practice_discernment_signal'::text AS object_type,
    d.discernment_signal_id::text AS object_id,
    'question'::text AS dimension_key,
    d.question_or_statement AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM d.question_or_statement), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'question'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.discernment_signals.question_or_statement'::text AS source_basis,
    NULL::text AS confidence,
    COALESCE(d.practice_truth_status, 'recorded'::text) AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.discernment_signals d
     LEFT JOIN practice.body_observations bo ON bo.body_observation_id = d.body_observation_id
UNION ALL
 SELECT 'practice_discernment_signal'::text AS adapter_key,
    'practice:discernment'::text AS witness_key,
    'practice_discernment_signal'::text AS object_type,
    d.discernment_signal_id::text AS object_id,
    'response'::text AS dimension_key,
    d.normalized_response AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM d.normalized_response), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'response'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'practice.discernment_signals.normalized_response'::text AS source_basis,
    NULL::text AS confidence,
    COALESCE(d.practice_truth_status, 'recorded'::text) AS coordinate_status,
    bo.region_key AS scope_region_key,
        CASE
            WHEN bo.side = 'unspecified'::text THEN NULL::text
            ELSE bo.side
        END AS scope_side,
    '{}'::jsonb AS metadata
   FROM practice.discernment_signals d
     LEFT JOIN practice.body_observations bo ON bo.body_observation_id = d.body_observation_id
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    'source_term'::text AS dimension_key,
    bs.body_key AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bs.body_key), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'source_term'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_body_states.body_key'::text AS source_basis,
    NULL::text AS confidence,
    cs.computation_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{}'::jsonb AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    'state'::text AS dimension_key,
    bs.visibility_state AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bs.visibility_state), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'state'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_body_states.visibility_state'::text AS source_basis,
    NULL::text AS confidence,
    cs.computation_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{"state_family": "visibility"}'::jsonb AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
  WHERE NULLIF(TRIM(BOTH FROM bs.visibility_state), ''::text) IS NOT NULL
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    'state'::text AS dimension_key,
    bs.horizon_state AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM bs.horizon_state), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'state'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_body_states.horizon_state'::text AS source_basis,
    NULL::text AS confidence,
    cs.computation_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{"state_family": "horizon"}'::jsonb AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
  WHERE NULLIF(TRIM(BOTH FROM bs.horizon_state), ''::text) IS NOT NULL
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    'process'::text AS dimension_key,
    'retrograde'::text AS dimension_value,
    'retrograde'::text AS normalized_value,
    'process'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_body_states.retrograde'::text AS source_basis,
    NULL::text AS confidence,
    cs.computation_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{}'::jsonb AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
  WHERE bs.retrograde IS TRUE
UNION ALL
 SELECT 'celestial_body_state'::text AS adapter_key,
    'celestial:measurement'::text AS witness_key,
    'celestial_body_state'::text AS object_type,
    bs.body_state_id::text AS object_id,
    'measurement'::text AS dimension_key,
    'ecliptic_longitude='::text || bs.ecliptic_longitude_deg::text AS dimension_value,
    lower('ecliptic_longitude='::text || bs.ecliptic_longitude_deg::text) AS normalized_value,
    'measurement'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_body_states.ecliptic_longitude_deg'::text AS source_basis,
    NULL::text AS confidence,
    cs.computation_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    jsonb_build_object('measure', 'ecliptic_longitude_deg', 'value', bs.ecliptic_longitude_deg) AS metadata
   FROM draft.celestial_chart_body_states bs
     JOIN draft.celestial_chart_snapshots cs USING (snapshot_id)
  WHERE bs.ecliptic_longitude_deg IS NOT NULL
UNION ALL
 SELECT 'celestial_chart_event'::text AS adapter_key,
    'celestial:event_recognition'::text AS witness_key,
    'celestial_chart_event'::text AS object_type,
    ce.chart_event_id::text AS object_id,
    'process'::text AS dimension_key,
    ce.raw_event_family AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM ce.raw_event_family), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'process'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_events.raw_event_family'::text AS source_basis,
    ce.computation_confidence AS confidence,
    ce.recognition_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    jsonb_build_object('grammarKey', ce.grammar_key) AS metadata
   FROM draft.celestial_chart_events ce
UNION ALL
 SELECT 'celestial_chart_event'::text AS adapter_key,
    'celestial:event_recognition'::text AS witness_key,
    'celestial_chart_event'::text AS object_type,
    ce.chart_event_id::text AS object_id,
    'source_term'::text AS dimension_key,
    ce.primary_body_key AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM ce.primary_body_key), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'source_term'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_events.primary_body_key'::text AS source_basis,
    ce.computation_confidence AS confidence,
    ce.recognition_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{"participant_role": "primary"}'::jsonb AS metadata
   FROM draft.celestial_chart_events ce
UNION ALL
 SELECT 'celestial_chart_event'::text AS adapter_key,
    'celestial:event_recognition'::text AS witness_key,
    'celestial_chart_event'::text AS object_type,
    ce.chart_event_id::text AS object_id,
    'source_term'::text AS dimension_key,
    ce.secondary_body_key AS dimension_value,
    lower(regexp_replace(TRIM(BOTH FROM ce.secondary_body_key), '\s+'::text, '_'::text, 'g'::text)) AS normalized_value,
    'source_term'::text AS coordinate_role,
    'native_field'::text AS source_relation,
    'draft.celestial_chart_events.secondary_body_key'::text AS source_basis,
    ce.computation_confidence AS confidence,
    ce.recognition_status AS coordinate_status,
    NULL::text AS scope_region_key,
    NULL::text AS scope_side,
    '{"participant_role": "secondary"}'::jsonb AS metadata
   FROM draft.celestial_chart_events ce
  WHERE ce.secondary_body_key IS NOT NULL;;

comment on view intelligence.v_reality_witness_object_coordinates_v1 is
'Candidate Reality Coordinates emitted by native-source adapters. Rows retain witness and source basis. Exact coordinate agreement is a discoverable contact surface, not an assertion that source objects are equivalent.';

create or replace view intelligence.v_reality_witness_objects_v2
with (security_invoker=true)
as
 SELECT v_reality_witness_objects_v1.adapter_key,
    v_reality_witness_objects_v1.witness_key,
    v_reality_witness_objects_v1.object_type,
    v_reality_witness_objects_v1.object_id,
    v_reality_witness_objects_v1.object_label,
    v_reality_witness_objects_v1.object_kind,
    v_reality_witness_objects_v1.source_status,
    v_reality_witness_objects_v1.subject_ref_type,
    v_reality_witness_objects_v1.subject_ref,
    v_reality_witness_objects_v1.occurred_at,
    v_reality_witness_objects_v1.native_definition,
    v_reality_witness_objects_v1.metadata
   FROM intelligence.v_reality_witness_objects_v1
UNION ALL
 SELECT 'universal_vocabulary'::text AS adapter_key,
        CASE
            WHEN v.framework_key IS NOT NULL THEN 'framework:'::text || v.framework_key
            ELSE 'jurisdiction:'::text || v.source_jurisdiction
        END AS witness_key,
    v.object_type,
    v.object_id,
    v.display_label AS object_label,
    v.object_kind,
    v.source_status,
    NULL::text AS subject_ref_type,
    NULL::text AS subject_ref,
    NULL::timestamp with time zone AS occurred_at,
    v.definition_text AS native_definition,
    v.metadata || jsonb_build_object('sourceDomain', v.source_domain, 'sourceJurisdiction', v.source_jurisdiction, 'frameworkKey', v.framework_key, 'frameworkName', v.framework_name) AS metadata
   FROM intelligence.v_universal_vocabulary_index_v1 v
  WHERE NOT (EXISTS ( SELECT 1
           FROM intelligence.v_reality_witness_objects_v1 x
          WHERE x.object_type = v.object_type AND x.object_id = v.object_id));;

comment on view intelligence.v_reality_witness_objects_v2 is
'Universal Reality Witness Object envelope: native practice/celestial records plus all indexed Noel vocabulary/research objects not already represented by a native adapter.';

create or replace view intelligence.v_reality_witness_object_coordinates_v2
with (security_invoker=true)
as
 SELECT v_reality_witness_object_coordinates_v1.adapter_key,
    v_reality_witness_object_coordinates_v1.witness_key,
    v_reality_witness_object_coordinates_v1.object_type,
    v_reality_witness_object_coordinates_v1.object_id,
    v_reality_witness_object_coordinates_v1.dimension_key,
    v_reality_witness_object_coordinates_v1.dimension_value,
    v_reality_witness_object_coordinates_v1.normalized_value,
    v_reality_witness_object_coordinates_v1.coordinate_role,
    v_reality_witness_object_coordinates_v1.source_relation,
    v_reality_witness_object_coordinates_v1.source_basis,
    v_reality_witness_object_coordinates_v1.confidence,
    v_reality_witness_object_coordinates_v1.coordinate_status,
    v_reality_witness_object_coordinates_v1.scope_region_key,
    v_reality_witness_object_coordinates_v1.scope_side,
    v_reality_witness_object_coordinates_v1.metadata
   FROM intelligence.v_reality_witness_object_coordinates_v1
UNION ALL
 SELECT 'universal_vocabulary'::text AS adapter_key,
        CASE
            WHEN vi.framework_key IS NOT NULL THEN 'framework:'::text || vi.framework_key
            ELSE 'jurisdiction:'::text || vi.source_jurisdiction
        END AS witness_key,
    dm.object_type,
    dm.object_id,
    dm.dimension_key,
    dm.dimension_value,
    dm.normalized_value,
        CASE
            WHEN dm.dimension_key = 'laterality'::text THEN 'laterality'::text
            WHEN dm.dimension_key = ANY (ARRAY['body_region'::text, 'body_region_side'::text]) THEN 'location'::text
            ELSE 'feature'::text
        END AS coordinate_role,
    dm.relation_type AS source_relation,
    dm.source_basis,
    dm.confidence,
    dm.status AS coordinate_status,
    dm.scope_region_key,
    dm.scope_side,
    dm.metadata
   FROM intelligence.v_universal_vocabulary_dimension_map_v2 dm
     JOIN intelligence.v_universal_vocabulary_index_v1 vi ON vi.object_type = dm.object_type AND vi.object_id = dm.object_id
  WHERE NOT (EXISTS ( SELECT 1
           FROM intelligence.v_reality_witness_object_coordinates_v1 x
          WHERE x.object_type = dm.object_type AND x.object_id = dm.object_id AND x.dimension_key = dm.dimension_key AND x.normalized_value = dm.normalized_value AND COALESCE(x.source_relation, ''::text) = COALESCE(dm.relation_type, ''::text)));;

comment on view intelligence.v_reality_witness_object_coordinates_v2 is
'Complete candidate coordinate membrane for Reality Alignment. It combines native adapter coordinates with existing governed Noel vocabulary mappings while preserving witness identity and source basis.';

revoke all on intelligence.v_reality_witness_objects_v1 from anon,authenticated;
revoke all on intelligence.v_reality_witness_object_coordinates_v1 from anon,authenticated;
revoke all on intelligence.v_reality_witness_objects_v2 from anon,authenticated;
revoke all on intelligence.v_reality_witness_object_coordinates_v2 from anon,authenticated;
grant select on intelligence.v_reality_witness_objects_v1 to service_role;
grant select on intelligence.v_reality_witness_object_coordinates_v1 to service_role;
grant select on intelligence.v_reality_witness_objects_v2 to service_role;
grant select on intelligence.v_reality_witness_object_coordinates_v2 to service_role;
