begin;

insert into instrument.feature_registry(
  feature_key, prior_load_level, feature_family, feature_name, description,
  source_relation, source_column, interpretation_class, allowed_in_strict_blind
)
values
  ('mark_capture_pixels', 0, 'mark_physical', 'Mark capture pixels', 'Verified source image byte identity and pixel dimensions.', 'mark.captures', 'sha256', 'observed', true),
  ('mark_source_coordinate', 0, 'mark_physical', 'Mark source coordinate', 'Physical region coordinates in a registered capture/surface.', 'mark.regions', 'geometry_payload', 'observed', true),
  ('mark_physical_channel', 0, 'mark_physical', 'Physical mark channel', 'Observed pigment, incision, damage, or unresolved physical channel without semantic naming.', 'mark.components', 'channel_key', 'observed', true),
  ('mark_component_geometry', 0, 'mark_physical', 'Mark component geometry', 'Observed component geometry through its source region.', 'mark.components', 'region_id', 'observed', true),
  ('mark_damage_state', 0, 'mark_physical', 'Mark damage state', 'Observed visibility, damage, uncertainty, or occlusion state.', 'mark.components', 'observation_status', 'observed', true),
  ('mark_junction_relation', 1, 'mark_mechanical_topology', 'Mark junction relation', 'Topology such as touch, cross, contain, above, below, terminate, or adjacency.', 'mark.component_relations', 'relation_key', 'derived_mechanical', true),
  ('mark_sequence_position', 1, 'mark_mechanical_topology', 'Anonymous physical sequence position', 'Physical order inside an anonymous row/zone without word or character identity.', 'mark.sequence_members', 'ordinal_position', 'derived_mechanical', true),
  ('mark_capture_equivalence', 1, 'mark_source_control', 'Capture duplicate/derivative relation', 'Adjudicated capture identity relation used to prevent duplicate evidence.', 'mark.capture_equivalences', 'equivalence_kind', 'derived_mechanical', true),
  ('mark_unicode_identity', 3, 'mark_conventional_semantics', 'Unicode/conventional sign identity', 'Conventional character identity or normalized encoded sign.', null, null, 'conventional_semantic', false),
  ('mark_lexical_reading', 3, 'mark_conventional_semantics', 'Lexical/phonetic reading', 'Conventional lexical or phonetic reading assigned to a mark.', null, null, 'conventional_semantic', false),
  ('mark_translation', 3, 'mark_conventional_semantics', 'Translation', 'Translated language attached to a mark or sequence.', null, null, 'conventional_semantic', false),
  ('mark_culture_label', 3, 'mark_conventional_semantics', 'Culture/script label', 'Cultural, script, civilization, or named-writing-system identity when used as discovery evidence.', null, null, 'conventional_semantic', false),
  ('mark_scholarly_interpretation', 4, 'mark_interpretive_prior', 'Scholarly mark interpretation', 'Inherited scholarly function or meaning claims; benchmark-only after blind discovery freeze.', null, null, 'conventional_semantic', false)
on conflict (feature_key) do nothing;

insert into instrument.engine_registry(
  engine_key, engine_family, engine_name, description, implementation_ref,
  maximum_prior_load_level, uses_pretrained_semantic_model, independence_group, status
)
values
  ('mark_sequence_miner_v0', 'sequence_mining', 'Mark Sequence Miner v0', 'Anonymous physical recurrence/sequence engine over mark geometry, channels, junctions, and sequence position. Conventional mark identity is prohibited in strict-blind runs.', 'architecture/MARK_STATE_RECOVERY_CALIBRATION_V1.md', 1, false, 'mark_physical_topology_sequence', 'experimental'),
  ('mark_state_recovery_v0', 'state_recovery', 'Mark State Recovery v0', 'Masked-state recovery benchmark engine. Predicts held-out physical state from permitted non-target recurrence context under explicit leakage exclusions.', 'architecture/MARK_STATE_RECOVERY_CALIBRATION_V1.md', 1, false, 'mark_physical_state_recovery', 'experimental')
on conflict (engine_key) do nothing;

-- Constitutional assertions: strict-blind engines may not load conventional semantic mark features.
do $$
declare
  bad_feature text;
begin
  select feature_key into bad_feature
  from instrument.feature_registry
  where feature_key like 'mark_%'
    and allowed_in_strict_blind
    and prior_load_level > 2
  limit 1;

  if bad_feature is not null then
    raise exception 'MARK_STRICT_BLIND_PRIOR_VIOLATION: %', bad_feature;
  end if;

  select feature_key into bad_feature
  from instrument.feature_registry
  where feature_key in ('mark_unicode_identity','mark_lexical_reading','mark_translation','mark_culture_label','mark_scholarly_interpretation')
    and allowed_in_strict_blind
  limit 1;

  if bad_feature is not null then
    raise exception 'MARK_SEMANTIC_FEATURE_EXPOSED_TO_BLIND_DISCOVERY: %', bad_feature;
  end if;
end
$$;

commit;
