
create or replace view intelligence.v_reality_witness_objects_v1
with (security_invoker=true)
as
select
  'practice_body_observation'::text adapter_key,
  'practice:observation'::text witness_key,
  'practice_body_observation'::text object_type,
  bo.body_observation_id::text object_id,
  coalesce(nullif(bo.raw_language,''),bo.normalized_state,bo.observation_type) object_label,
  bo.observation_type object_kind,
  bo.status source_status,
  'practice_person'::text subject_ref_type,
  p.person_key::text subject_ref,
  coalesce(bo.observed_at,s.started_at,bo.created_at) occurred_at,
  coalesce(nullif(bo.raw_language,''),bo.normalized_state) native_definition,
  jsonb_build_object(
    'sessionId',bo.session_id,
    'regionKey',bo.region_key,
    'side',bo.side,
    'reportedBy',bo.reported_by,
    'intensityValue',bo.intensity_value,
    'intensityScale',bo.intensity_scale,
    'onsetText',bo.onset_text,
    'researchObservationId',bo.research_observation_id
  ) metadata
from practice.body_observations bo
join practice.sessions s using(session_id)
join practice.people p using(person_id)

union all
select
  'practice_context_observation',
  'practice:observation',
  'practice_context_observation',
  co.context_observation_id::text,
  coalesce(nullif(co.raw_language,''),co.normalized_context,co.context_type),
  co.context_type,
  'recorded',
  'practice_person',
  p.person_key,
  coalesce(co.observed_at,s.started_at,co.created_at),
  coalesce(nullif(co.raw_language,''),co.normalized_context),
  jsonb_build_object(
    'sessionId',co.session_id,
    'contextType',co.context_type,
    'contextSubject',co.context_subject,
    'valence',co.valence,
    'intensityValue',co.intensity_value,
    'intensityScale',co.intensity_scale,
    'reportedBy',co.reported_by
  )
from practice.context_observations co
join practice.sessions s using(session_id)
join practice.people p using(person_id)

union all
select
  'practice_intervention',
  'practice:intervention',
  'practice_intervention',
  i.intervention_id::text,
  coalesce(nullif(i.practice_label,''),nullif(i.exact_words,''),i.intervention_type),
  i.intervention_type,
  'recorded',
  'practice_person',
  p.person_key,
  coalesce(s.started_at,i.created_at),
  coalesce(nullif(i.exact_words,''),nullif(i.practice_label,''),i.intervention_type),
  jsonb_build_object(
    'sessionId',i.session_id,
    'sequenceNo',i.sequence_no,
    'targetRegionKey',i.target_region_key,
    'targetSide',i.target_side,
    'materialOrInput',i.material_or_input,
    'durationText',i.duration_text,
    'operatorIntent',i.operator_intent
  )
from practice.interventions i
join practice.sessions s using(session_id)
join practice.people p using(person_id)

union all
select
  'practice_outcome',
  'practice:outcome',
  'practice_outcome',
  o.outcome_id::text,
  o.outcome_text,
  o.outcome_type,
  'recorded',
  'practice_person',
  p.person_key,
  coalesce(o.observed_at,s.started_at,o.created_at),
  o.outcome_text,
  jsonb_build_object(
    'sessionId',o.session_id,
    'interventionId',o.intervention_id,
    'bodyObservationId',o.body_observation_id,
    'direction',o.direction,
    'magnitudeValue',o.magnitude_value,
    'magnitudeScale',o.magnitude_scale,
    'durability',o.durability,
    'reportedBy',o.reported_by
  )
from practice.outcomes o
join practice.sessions s using(session_id)
join practice.people p using(person_id)

union all
select
  'practice_discernment_signal',
  'practice:discernment',
  'practice_discernment_signal',
  d.discernment_signal_id::text,
  d.question_or_statement,
  d.signal_type,
  coalesce(d.practice_truth_status,'recorded'),
  'practice_person',
  p.person_key,
  coalesce(d.observed_at,s.started_at,d.created_at),
  coalesce(nullif(d.raw_response,''),d.normalized_response),
  jsonb_build_object(
    'sessionId',d.session_id,
    'interventionId',d.intervention_id,
    'bodyObservationId',d.body_observation_id,
    'normalizedResponse',d.normalized_response,
    'responseDirection',d.response_direction,
    'interpretedAnswer',d.interpreted_answer,
    'operatorInterpretation',d.operator_interpretation,
    'confidence',d.confidence,
    'functionKey',d.function_key,
    'songObjectId',d.song_object_id,
    'cleanAnswer',d.clean_answer,
    'clearingRequired',d.clearing_required,
    'clearingFormulaUsed',d.clearing_formula_used,
    'postClearing',d.post_clearing
  )
from practice.discernment_signals d
join practice.sessions s using(session_id)
join practice.people p using(person_id)

union all
select
  'celestial_body_state',
  'celestial:measurement',
  'celestial_body_state',
  bs.body_state_id::text,
  bs.body_key,
  'measured_body_state',
  cs.computation_status,
  case when ci.subject_ref is null then null else 'celestial_subject' end,
  ci.subject_ref,
  bs.sample_time_utc,
  bs.body_key,
  jsonb_build_object(
    'snapshotId',bs.snapshot_id,
    'chartInputId',ci.chart_input_id,
    'chartKey',ci.chart_key,
    'chartKind',ci.chart_kind,
    'eclipticLongitudeDeg',bs.ecliptic_longitude_deg,
    'eclipticLatitudeDeg',bs.ecliptic_latitude_deg,
    'rightAscensionDeg',bs.right_ascension_deg,
    'declinationDeg',bs.declination_deg,
    'altitudeDeg',bs.altitude_deg,
    'azimuthDeg',bs.azimuth_deg,
    'distanceAu',bs.distance_au,
    'apparentMagnitude',bs.apparent_magnitude,
    'longitudeSpeedDegDay',bs.longitude_speed_deg_day,
    'retrograde',bs.retrograde,
    'visibilityState',bs.visibility_state,
    'horizonState',bs.horizon_state,
    'observationalState',bs.observational_state,
    'uncertainty',bs.uncertainty,
    'provenance',bs.provenance
  )
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)
join draft.celestial_chart_inputs ci using(chart_input_id)

union all
select
  'celestial_chart_event',
  'celestial:event_recognition',
  'celestial_chart_event',
  ce.chart_event_id::text,
  ce.event_key,
  ce.raw_event_family,
  ce.recognition_status,
  case when ci.subject_ref is null then null else 'celestial_subject' end,
  ci.subject_ref,
  coalesce(ce.event_exact_utc,ce.event_start_utc,cs.computed_for_utc),
  ce.raw_event_family,
  jsonb_build_object(
    'snapshotId',ce.snapshot_id,
    'chartInputId',ci.chart_input_id,
    'chartKey',ci.chart_key,
    'chartKind',ci.chart_kind,
    'grammarKey',ce.grammar_key,
    'primaryBodyKey',ce.primary_body_key,
    'secondaryBodyKey',ce.secondary_body_key,
    'eventStartUtc',ce.event_start_utc,
    'eventExactUtc',ce.event_exact_utc,
    'eventEndUtc',ce.event_end_utc,
    'eventParameters',ce.event_parameters,
    'computationConfidence',ce.computation_confidence,
    'uncertainty',ce.uncertainty,
    'provenance',ce.provenance
  )
from draft.celestial_chart_events ce
join draft.celestial_chart_snapshots cs using(snapshot_id)
join draft.celestial_chart_inputs ci using(chart_input_id)

union all
select
  'framework_concept',
  'framework:'||fc.framework_key,
  'framework_concept',
  fc.concept_key,
  fc.preferred_label,
  fc.concept_kind,
  fc.concept_status,
  null,null,
  fc.created_at,
  fc.native_definition,
  fc.metadata || jsonb_build_object(
    'frameworkKey',fc.framework_key,
    'nativeId',fc.native_id,
    'normalizedLabel',fc.normalized_label,
    'sourceLanguage',fc.source_language,
    'parentConceptKey',fc.parent_concept_key
  )
from draft.reality_framework_concepts fc

union all
select
  'canon_organic_term',
  'jurisdiction:canon_vocabulary',
  'canon_organic_term',
  c.term_key,
  coalesce(nullif(c.transliteration,''),c.lemma,c.neutral_gloss),
  c.term_kind,
  c.source_status,
  null,null,
  c.created_at,
  c.neutral_gloss,
  jsonb_build_object(
    'languageCode',c.language_code,
    'lemma',c.lemma,
    'transliteration',c.transliteration,
    'strongId',c.strong_id,
    'notes',c.notes
  )
from draft.canon_organic_terms c

union all
select
  'function_registry',
  'jurisdiction:noel_function',
  'function',
  f.function_key,
  f.function_name,
  'function',
  f.status,
  null,null,
  f.created_at,
  f.working_definition,
  jsonb_build_object(
    'beforeState',f.before_state,
    'operation',f.operation,
    'afterState',f.after_state,
    'lawfulSource',f.lawful_source,
    'intendedFruit',f.intended_fruit,
    'failureMode',f.failure_mode,
    'clarityState',f.clarity_state
  )
from draft.function_registry f

union all
select
  'song_object',
  'jurisdiction:song',
  'song_object',
  s.song_object_id::text,
  s.object_name,
  s.object_type,
  s.object_status,
  null,null,
  s.created_at,
  s.one_sentence_claim,
  jsonb_build_object(
    'provisionalFunctionLane',s.provisional_function_lane,
    'mainstreamRivalReading',s.mainstream_rival_reading,
    'notes',s.notes
  )
from draft.song_objects s

union all
select
  'research_claim',
  'jurisdiction:research_claim',
  'research_claim',
  r.claim_id::text,
  r.claim_title,
  r.claim_kind,
  r.claim_status,
  null,null,
  r.created_at,
  r.short_claim,
  jsonb_build_object(
    'claimKey',r.claim_key,
    'currentCategory',r.current_category,
    'liveTest',r.live_test,
    'evidenceNeeded',r.evidence_needed,
    'strengthensIf',r.strengthens_if,
    'weakensIf',r.weakens_if,
    'confidence',r.confidence
  )
from draft.research_claims r;

comment on view intelligence.v_reality_witness_objects_v1 is
'Universal thin envelope over native witness objects. Source records remain authoritative in their native tables; this view exposes only identity, witness, subject/time where available, source-native label/definition, status, and metadata needed for alignment.';

create or replace view intelligence.v_reality_witness_object_coordinates_v1
with (security_invoker=true)
as
-- Evidence-custodied descriptors already created for framework/canon/function/Song/research objects.
select
  case
    when d.object_type='framework_concept' then 'framework_concept'
    when d.object_type='canon_organic_term' then 'canon_organic_term'
    when d.object_type='function' then 'function_registry'
    when d.object_type='song_object' then 'song_object'
    when d.object_type='research_claim' then 'research_claim'
    else 'descriptor'
  end adapter_key,
  o.witness_key,
  d.object_type,
  d.object_id,
  d.dimension_key,
  d.dimension_value,
  d.normalized_value,
  case
    when d.dimension_key in ('body_region','body_region_side','laterality') then 'location'
    else 'feature'
  end coordinate_role,
  d.relation_type source_relation,
  d.source_basis,
  d.confidence,
  d.status coordinate_status,
  d.scope_region_key,
  d.scope_side,
  jsonb_build_object('evidenceRef',d.evidence_ref) metadata
from draft.reality_object_query_descriptors d
join intelligence.v_reality_witness_objects_v1 o
  on o.object_type=d.object_type
 and o.object_id=d.object_id
where d.status<>'retired'

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'body_region',bo.region_key,lower(bo.region_key),'location','native_field','practice.body_observations.region_key',null,bo.status,
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.body_observations bo
where bo.region_key is not null

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'laterality',bo.side,lower(bo.side),'laterality','native_field','practice.body_observations.side',null,bo.status,
  bo.region_key,bo.side,'{}'::jsonb
from practice.body_observations bo
where bo.side is not null and bo.side<>'unspecified'

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'body_region_side',bo.region_key||':'||bo.side,lower(bo.region_key||':'||bo.side),'location','native_compound','practice.body_observations.region_key+side',null,bo.status,
  bo.region_key,bo.side,'{}'::jsonb
from practice.body_observations bo
where bo.region_key is not null and bo.side is not null and bo.side<>'unspecified'

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'state',bo.normalized_state,lower(regexp_replace(trim(bo.normalized_state),'\s+','_','g')),'state','native_field','practice.body_observations.normalized_state',null,bo.status,
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.body_observations bo

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'process',bo.observation_type,lower(regexp_replace(trim(bo.observation_type),'\s+','_','g')),'process','native_field','practice.body_observations.observation_type',null,bo.status,
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.body_observations bo

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'intensity',bo.intensity_value::text,bo.intensity_value::text,'measurement','native_field','practice.body_observations.intensity_value',null,bo.status,
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,
  jsonb_build_object('scale',bo.intensity_scale)
from practice.body_observations bo
where bo.intensity_value is not null

union all
select
  'practice_body_observation','practice:observation','practice_body_observation',bo.body_observation_id::text,
  'onset',bo.onset_text,lower(regexp_replace(trim(bo.onset_text),'\s+','_','g')),'time','native_field','practice.body_observations.onset_text',null,bo.status,
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.body_observations bo
where nullif(trim(bo.onset_text),'') is not null

union all
select
  'practice_context_observation','practice:observation','practice_context_observation',co.context_observation_id::text,
  'context_domain',co.context_type,lower(regexp_replace(trim(co.context_type),'\s+','_','g')),'context','native_field','practice.context_observations.context_type',null,'recorded',
  null,null,'{}'::jsonb
from practice.context_observations co

union all
select
  'practice_context_observation','practice:observation','practice_context_observation',co.context_observation_id::text,
  'state',co.normalized_context,lower(regexp_replace(trim(co.normalized_context),'\s+','_','g')),'state','native_field','practice.context_observations.normalized_context',null,'recorded',
  null,null,'{}'::jsonb
from practice.context_observations co

union all
select
  'practice_context_observation','practice:observation','practice_context_observation',co.context_observation_id::text,
  'affect',co.valence,lower(regexp_replace(trim(co.valence),'\s+','_','g')),'affect','native_field','practice.context_observations.valence',null,'recorded',
  null,null,'{}'::jsonb
from practice.context_observations co
where nullif(trim(co.valence),'') is not null

union all
select
  'practice_intervention','practice:intervention','practice_intervention',i.intervention_id::text,
  'body_region',i.target_region_key,lower(i.target_region_key),'location','native_field','practice.interventions.target_region_key',null,'recorded',
  i.target_region_key,case when i.target_side='unspecified' then null else i.target_side end,'{}'::jsonb
from practice.interventions i
where i.target_region_key is not null

union all
select
  'practice_intervention','practice:intervention','practice_intervention',i.intervention_id::text,
  'action',i.intervention_type,lower(regexp_replace(trim(i.intervention_type),'\s+','_','g')),'action','native_field','practice.interventions.intervention_type',null,'recorded',
  i.target_region_key,case when i.target_side='unspecified' then null else i.target_side end,'{}'::jsonb
from practice.interventions i

union all
select
  'practice_intervention','practice:intervention','practice_intervention',i.intervention_id::text,
  'source_term',i.practice_label,lower(regexp_replace(trim(i.practice_label),'\s+','_','g')),'source_term','native_field','practice.interventions.practice_label',null,'recorded',
  i.target_region_key,case when i.target_side='unspecified' then null else i.target_side end,'{}'::jsonb
from practice.interventions i
where nullif(trim(i.practice_label),'') is not null

union all
select
  'practice_intervention','practice:intervention','practice_intervention',i.intervention_id::text,
  'input',i.material_or_input,lower(regexp_replace(trim(i.material_or_input),'\s+','_','g')),'input','native_field','practice.interventions.material_or_input',null,'recorded',
  i.target_region_key,case when i.target_side='unspecified' then null else i.target_side end,'{}'::jsonb
from practice.interventions i
where nullif(trim(i.material_or_input),'') is not null

union all
select
  'practice_outcome','practice:outcome','practice_outcome',o.outcome_id::text,
  'response',o.outcome_text,lower(regexp_replace(trim(o.outcome_text),'\s+','_','g')),'response','native_field','practice.outcomes.outcome_text',null,'recorded',
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.outcomes o
left join practice.body_observations bo on bo.body_observation_id=o.body_observation_id

union all
select
  'practice_outcome','practice:outcome','practice_outcome',o.outcome_id::text,
  'direction',o.direction,lower(regexp_replace(trim(o.direction),'\s+','_','g')),'direction','native_field','practice.outcomes.direction',null,'recorded',
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.outcomes o
left join practice.body_observations bo on bo.body_observation_id=o.body_observation_id
where nullif(trim(o.direction),'') is not null

union all
select
  'practice_outcome','practice:outcome','practice_outcome',o.outcome_id::text,
  'temporal_pattern',o.durability,lower(regexp_replace(trim(o.durability),'\s+','_','g')),'time','native_field','practice.outcomes.durability',null,'recorded',
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.outcomes o
left join practice.body_observations bo on bo.body_observation_id=o.body_observation_id
where nullif(trim(o.durability),'') is not null

union all
select
  'practice_discernment_signal','practice:discernment','practice_discernment_signal',d.discernment_signal_id::text,
  'question',d.question_or_statement,lower(regexp_replace(trim(d.question_or_statement),'\s+','_','g')),'question','native_field','practice.discernment_signals.question_or_statement',null,coalesce(d.practice_truth_status,'recorded'),
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.discernment_signals d
left join practice.body_observations bo on bo.body_observation_id=d.body_observation_id

union all
select
  'practice_discernment_signal','practice:discernment','practice_discernment_signal',d.discernment_signal_id::text,
  'response',d.normalized_response,lower(regexp_replace(trim(d.normalized_response),'\s+','_','g')),'response','native_field','practice.discernment_signals.normalized_response',null,coalesce(d.practice_truth_status,'recorded'),
  bo.region_key,case when bo.side='unspecified' then null else bo.side end,'{}'::jsonb
from practice.discernment_signals d
left join practice.body_observations bo on bo.body_observation_id=d.body_observation_id

union all
select
  'celestial_body_state','celestial:measurement','celestial_body_state',bs.body_state_id::text,
  'source_term',bs.body_key,lower(regexp_replace(trim(bs.body_key),'\s+','_','g')),'source_term','native_field','draft.celestial_chart_body_states.body_key',null,cs.computation_status,
  null,null,'{}'::jsonb
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)

union all
select
  'celestial_body_state','celestial:measurement','celestial_body_state',bs.body_state_id::text,
  'state',bs.visibility_state,lower(regexp_replace(trim(bs.visibility_state),'\s+','_','g')),'state','native_field','draft.celestial_chart_body_states.visibility_state',null,cs.computation_status,
  null,null,'{"state_family":"visibility"}'::jsonb
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)
where nullif(trim(bs.visibility_state),'') is not null

union all
select
  'celestial_body_state','celestial:measurement','celestial_body_state',bs.body_state_id::text,
  'state',bs.horizon_state,lower(regexp_replace(trim(bs.horizon_state),'\s+','_','g')),'state','native_field','draft.celestial_chart_body_states.horizon_state',null,cs.computation_status,
  null,null,'{"state_family":"horizon"}'::jsonb
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)
where nullif(trim(bs.horizon_state),'') is not null

union all
select
  'celestial_body_state','celestial:measurement','celestial_body_state',bs.body_state_id::text,
  'process','retrograde','retrograde','process','native_field','draft.celestial_chart_body_states.retrograde',null,cs.computation_status,
  null,null,'{}'::jsonb
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)
where bs.retrograde is true

union all
select
  'celestial_body_state','celestial:measurement','celestial_body_state',bs.body_state_id::text,
  'measurement','ecliptic_longitude='||bs.ecliptic_longitude_deg::text,
  lower('ecliptic_longitude='||bs.ecliptic_longitude_deg::text),'measurement','native_field','draft.celestial_chart_body_states.ecliptic_longitude_deg',null,cs.computation_status,
  null,null,jsonb_build_object('measure','ecliptic_longitude_deg','value',bs.ecliptic_longitude_deg)
from draft.celestial_chart_body_states bs
join draft.celestial_chart_snapshots cs using(snapshot_id)
where bs.ecliptic_longitude_deg is not null

union all
select
  'celestial_chart_event','celestial:event_recognition','celestial_chart_event',ce.chart_event_id::text,
  'process',ce.raw_event_family,lower(regexp_replace(trim(ce.raw_event_family),'\s+','_','g')),'process','native_field','draft.celestial_chart_events.raw_event_family',ce.computation_confidence,ce.recognition_status,
  null,null,jsonb_build_object('grammarKey',ce.grammar_key)
from draft.celestial_chart_events ce

union all
select
  'celestial_chart_event','celestial:event_recognition','celestial_chart_event',ce.chart_event_id::text,
  'source_term',ce.primary_body_key,lower(regexp_replace(trim(ce.primary_body_key),'\s+','_','g')),'source_term','native_field','draft.celestial_chart_events.primary_body_key',ce.computation_confidence,ce.recognition_status,
  null,null,'{"participant_role":"primary"}'::jsonb
from draft.celestial_chart_events ce

union all
select
  'celestial_chart_event','celestial:event_recognition','celestial_chart_event',ce.chart_event_id::text,
  'source_term',ce.secondary_body_key,lower(regexp_replace(trim(ce.secondary_body_key),'\s+','_','g')),'source_term','native_field','draft.celestial_chart_events.secondary_body_key',ce.computation_confidence,ce.recognition_status,
  null,null,'{"participant_role":"secondary"}'::jsonb
from draft.celestial_chart_events ce
where ce.secondary_body_key is not null;

comment on view intelligence.v_reality_witness_object_coordinates_v1 is
'Candidate Reality Coordinates emitted by native-source adapters. Rows retain witness and source basis. Exact coordinate agreement is a discoverable contact surface, not an assertion that the source objects are equivalent.';

revoke all on intelligence.v_reality_witness_objects_v1 from anon,authenticated;
revoke all on intelligence.v_reality_witness_object_coordinates_v1 from anon,authenticated;
grant select on intelligence.v_reality_witness_objects_v1 to service_role;
grant select on intelligence.v_reality_witness_object_coordinates_v1 to service_role;
