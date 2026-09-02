begin;

-- Mark Global Topology Kernel v1.
-- Extends the physical evidence kernel from raster-only glyph comparison toward
-- medium-agnostic physical state systems: drawn marks, incisions, impressions,
-- cord/fiber structures, knots/interlacings, tokens, tallies, and bounded gaps.
--
-- Governing separation:
--   mark         = blind physical evidence + topology + computed structural motifs
--   mark_context = historical/cultural/system identity used only after blind analysis
--
-- No conventional reading, phonetic value, word meaning, deity/person identity,
-- or culture label is admitted into the blind Mark tables by this migration.

comment on schema mark is
  'Noel blind physical mark evidence custody. Stores source objects, captures, geometry, components, topology, measurable physical features, and structural operator candidates across drawn, incised, impressed, corded, token, tally, and negative-space systems without linguistic or semantic authority.';

-- ---------------------------------------------------------------------------
-- Broaden observable physical channels beyond deposited pigment.
-- ---------------------------------------------------------------------------

insert into mark.channel_registry(
  channel_key, channel_family, channel_name, physical_basis, strict_blind_allowed
)
values
  ('fiber_or_cord', 'material', 'Fiber or cord material',
   'Observed elongated fibrous, thread-like, string-like, or cordage material.', true),
  ('solid_object', 'material', 'Discrete solid object',
   'Observed discrete physical body such as a token, bead, pellet, or other bounded solid element; no cultural function is asserted.', true),
  ('impression', 'surface_deformation', 'Impressed deformation',
   'Observed indentation, wedge, stamp, pressure mark, or other non-cut deformation of a support.', true),
  ('void_interval', 'spatial_absence', 'Bounded void or interval',
   'Observed bounded spatial absence between or within physical elements. The interval itself is recorded because spacing can carry structural state.', true)
on conflict (channel_key) do nothing;

comment on table mark.channel_registry is
  'Blind physical observation channels. Entries may describe deposited material, cord/fiber, solid bodies, surface deformation, damage, or bounded negative space; never linguistic function.';

-- Relations required for graph comparison across 2-D marks and material networks.
insert into mark.relation_registry(
  relation_key, relation_family, relation_name, directed,
  physical_definition, inverse_relation_key, strict_blind_allowed
)
values
  ('attached_to', 'connectivity', 'Attached to', true,
   'The subject has an observed physical attachment locus on the object.', null, true),
  ('has_attachment', 'connectivity', 'Has attachment', true,
   'The subject bears an observed attached object at one or more loci.', null, true),
  ('branches_from', 'connectivity', 'Branches from', true,
   'The subject diverges from or originates at an observed shared physical locus on the object.', null, true),
  ('has_branch', 'connectivity', 'Has branch', true,
   'The subject bears a diverging physical continuation or attached branch.', null, true),
  ('wraps_around', 'interlacing', 'Wraps around', true,
   'The subject curves around the object through an observed partial or complete turn.', null, true),
  ('wrapped_by', 'interlacing', 'Wrapped by', true,
   'The subject is physically encircled or partially encircled by the object.', null, true),
  ('interlocks_with', 'interlacing', 'Interlocks with', false,
   'The subject and object are mutually engaged through alternating over/under, linked-loop, or equivalent observable physical interlacing.', null, true),
  ('parallel_to', 'orientation', 'Parallel to', false,
   'The subject and object maintain approximately parallel principal trajectories under the stated measurement method.', null, true),
  ('pierces', 'penetration', 'Pierces', true,
   'The subject passes physically through the body, opening, or bounded thickness of the object.', null, true),
  ('pierced_by', 'penetration', 'Pierced by', true,
   'The subject is physically penetrated by the object.', null, true),
  ('separated_from', 'spacing', 'Separated from', false,
   'The subject and object are physically distinct with a measured non-zero interval between their relevant boundaries.', null, true)
on conflict (relation_key) do nothing;

update mark.relation_registry r
set inverse_relation_key = v.inverse_key
from (values
  ('attached_to','has_attachment'), ('has_attachment','attached_to'),
  ('branches_from','has_branch'), ('has_branch','branches_from'),
  ('wraps_around','wrapped_by'), ('wrapped_by','wraps_around'),
  ('pierces','pierced_by'), ('pierced_by','pierces')
) as v(relation_key,inverse_key)
where r.relation_key=v.relation_key
  and r.inverse_relation_key is distinct from v.inverse_key;

-- ---------------------------------------------------------------------------
-- Morphology: non-exclusive observable form descriptors for components.
-- A component may legitimately carry several descriptors (for example,
-- elongated + curved + closed_loop is different from forcing one glyph class).
-- ---------------------------------------------------------------------------

create table mark.morphology_registry (
  morphology_key text primary key,
  morphology_family text not null,
  morphology_name text not null,
  physical_definition text not null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(morphology_key) <> ''),
  check (btrim(morphology_family) <> ''),
  check (btrim(morphology_name) <> '')
);

insert into mark.morphology_registry(
  morphology_key, morphology_family, morphology_name, physical_definition
)
values
  ('unknown_morphology','uncertain','Unknown morphology',
   'A physical component is observed but its morphology has not yet been resolved.'),
  ('point_like','extent','Point-like',
   'Observed component extent is compact relative to the active comparison scale.'),
  ('elongated','extent','Elongated',
   'Observed component has a dominant long axis substantially greater than its transverse extent.'),
  ('linear_open','trajectory','Open linear trajectory',
   'Observed component follows an approximately straight open trajectory with distinct terminals.'),
  ('curvilinear_open','trajectory','Open curved trajectory',
   'Observed component follows a curved open trajectory with distinct terminals.'),
  ('angular_open','trajectory','Open angular trajectory',
   'Observed component contains one or more abrupt direction changes while remaining topologically open.'),
  ('closed_loop','closure','Closed loop',
   'Observed component trajectory returns to form a closed loop.'),
  ('enclosure_boundary','closure','Enclosure boundary',
   'Observed component forms or participates in a boundary surrounding a bounded interior region.'),
  ('compact_body','body','Compact body',
   'Observed component is a bounded body whose extent is not primarily represented as a trajectory.'),
  ('branched_body','connectivity','Branched body',
   'Observed component has a physical branching topology with three or more local continuations.'),
  ('bundled_body','grouping','Bundled body',
   'Observed component comprises multiple elongated physical elements held or traveling together as a local bundle.'),
  ('coiled_body','interlacing','Coiled body',
   'Observed component turns repeatedly around a local center or axis.'),
  ('localized_interlacing','interlacing','Localized interlacing',
   'Observed component region contains repeated local over/under, wrapping, or self-engaging trajectory structure without assigning a cultural knot type.'),
  ('void_interval','spacing','Void interval',
   'Observed component is a deliberately segmented bounded interval of negative space rather than deposited or solid material.')
on conflict (morphology_key) do nothing;

create table mark.component_morphologies (
  component_morphology_id bigint generated always as identity primary key,
  component_id bigint not null references mark.components(component_id),
  morphology_key text not null references mark.morphology_registry(morphology_key),
  observation_basis text not null default 'observed',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(component_id, morphology_key),
  check (observation_basis in ('observed','deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index component_morphologies_morphology_idx
  on mark.component_morphologies(morphology_key);
create index component_morphologies_derived_by_run_idx
  on mark.component_morphologies(derived_by_run_id);

comment on table mark.component_morphologies is
  'Non-exclusive blind morphology observations. These describe visible physical form, not conventional sign identity.';

-- ---------------------------------------------------------------------------
-- Typed blind features. This is where a line, knot-like interlacing, tally cut,
-- token, or glyph can be converted into comparable measurements without first
-- translating the object.
-- ---------------------------------------------------------------------------

create table mark.feature_registry (
  feature_key text primary key,
  feature_family text not null,
  feature_name text not null,
  target_kind text not null,
  value_kind text not null,
  unit_key text null,
  allowed_values text[] null,
  physical_definition text not null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(feature_key) <> ''),
  check (btrim(feature_family) <> ''),
  check (btrim(feature_name) <> ''),
  check (target_kind in ('component','relation','instance','region')),
  check (value_kind in ('numeric','integer','boolean','categorical')),
  check (allowed_values is null or cardinality(allowed_values) > 0)
);

insert into mark.feature_registry(
  feature_key, feature_family, feature_name, target_kind, value_kind,
  unit_key, allowed_values, physical_definition
)
values
  ('aspect_ratio','geometry','Aspect ratio','component','numeric','ratio',null,
   'Major physical extent divided by minor physical extent under the declared geometry method.'),
  ('orientation_degrees','geometry','Principal orientation','component','numeric','degrees',null,
   'Principal observed component-axis orientation in the registered coordinate frame.'),
  ('curvature_score','geometry','Curvature score','component','numeric','unit_interval',null,
   'Normalized measure of departure from a straight principal trajectory.'),
  ('closure_score','geometry','Closure score','component','numeric','unit_interval',null,
   'Normalized measure of how completely a component trajectory forms a closed boundary.'),
  ('branch_count','topology','Branch count','component','integer','count',null,
   'Count of observed local branch loci under the declared extraction method.'),
  ('terminal_count','topology','Terminal count','component','integer','count',null,
   'Count of observed component terminals under the declared extraction method.'),
  ('crossing_count','topology','Crossing count','component','integer','count',null,
   'Count of observed trajectory crossings local to the component.'),
  ('loop_count','topology','Loop count','component','integer','count',null,
   'Count of observed closed-loop structures local to the component.'),
  ('observed_twist_slant','material_topology','Observed twist slant','component','categorical',null,
   array['s_like','z_like','mixed','undetermined']::text[],
   'Viewer-frame slant of repeated visible twist structure. This records observed geometry only and does not assign manufacture or semantic meaning.'),
  ('attachment_position_normalized','connectivity','Normalized attachment position','relation','numeric','unit_interval',null,
   'Attachment locus projected onto the object principal extent and normalized from 0 to 1 under the declared orientation.'),
  ('wrap_turn_count','interlacing','Wrap turn count','relation','numeric','turns',null,
   'Observed number of turns made by the subject around the object in a wraps-around relation.'),
  ('separation_normalized','spacing','Normalized separation','relation','numeric','ratio',null,
   'Observed boundary-to-boundary separation normalized to the declared local scale.'),
  ('component_count','composition','Component count','instance','integer','count',null,
   'Count of physical components assigned to the candidate unit under the frozen segmentation.'),
  ('symmetry_score','composition','Reflection symmetry score','instance','numeric','unit_interval',null,
   'Normalized geometric reflection-similarity score under the declared axis search method.'),
  ('repetition_count','composition','Local repetition count','instance','integer','count',null,
   'Count of recurrent homologous physical elements detected within the candidate unit.'),
  ('occupied_area_ratio','composition','Occupied area ratio','instance','numeric','unit_interval',null,
   'Fraction of candidate-unit region occupied by observed non-void physical components under the declared segmentation.')
on conflict (feature_key) do nothing;

create table mark.feature_observations (
  feature_observation_id bigint generated always as identity primary key,
  observation_key text not null unique,
  feature_key text not null references mark.feature_registry(feature_key),
  component_id bigint null references mark.components(component_id),
  component_relation_id bigint null references mark.component_relations(component_relation_id),
  instance_id bigint null references mark.instances(instance_id),
  region_id bigint null references mark.regions(region_id),
  numeric_value numeric null,
  integer_value bigint null,
  boolean_value boolean null,
  categorical_value text null,
  observation_basis text not null default 'observed',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(observation_key) <> ''),
  check (observation_basis in ('observed','deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null)),
  check (num_nonnulls(component_id,component_relation_id,instance_id,region_id)=1),
  check (num_nonnulls(numeric_value,integer_value,boolean_value,categorical_value)=1)
);

create index feature_observations_feature_idx on mark.feature_observations(feature_key);
create index feature_observations_component_idx on mark.feature_observations(component_id);
create index feature_observations_relation_idx on mark.feature_observations(component_relation_id);
create index feature_observations_instance_idx on mark.feature_observations(instance_id);
create index feature_observations_region_idx on mark.feature_observations(region_id);
create index feature_observations_derived_by_run_idx on mark.feature_observations(derived_by_run_id);

create or replace function mark.validate_feature_observation_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  v_feature mark.feature_registry%rowtype;
  v_target_kind text;
begin
  select * into v_feature
  from mark.feature_registry
  where feature_key = new.feature_key;

  if not found then
    raise exception 'MARK_FEATURE_UNKNOWN: %', new.feature_key;
  end if;

  v_target_kind := case
    when new.component_id is not null then 'component'
    when new.component_relation_id is not null then 'relation'
    when new.instance_id is not null then 'instance'
    when new.region_id is not null then 'region'
    else null
  end;

  if v_target_kind is distinct from v_feature.target_kind then
    raise exception 'MARK_FEATURE_TARGET_MISMATCH: feature % targets %, received %',
      new.feature_key, v_feature.target_kind, coalesce(v_target_kind,'none');
  end if;

  if v_feature.value_kind='numeric' and
     (new.numeric_value is null or num_nonnulls(new.integer_value,new.boolean_value,new.categorical_value) <> 0) then
    raise exception 'MARK_FEATURE_VALUE_MISMATCH: feature % requires numeric_value', new.feature_key;
  elsif v_feature.value_kind='integer' and
     (new.integer_value is null or num_nonnulls(new.numeric_value,new.boolean_value,new.categorical_value) <> 0) then
    raise exception 'MARK_FEATURE_VALUE_MISMATCH: feature % requires integer_value', new.feature_key;
  elsif v_feature.value_kind='boolean' and
     (new.boolean_value is null or num_nonnulls(new.numeric_value,new.integer_value,new.categorical_value) <> 0) then
    raise exception 'MARK_FEATURE_VALUE_MISMATCH: feature % requires boolean_value', new.feature_key;
  elsif v_feature.value_kind='categorical' and
     (new.categorical_value is null or num_nonnulls(new.numeric_value,new.integer_value,new.boolean_value) <> 0) then
    raise exception 'MARK_FEATURE_VALUE_MISMATCH: feature % requires categorical_value', new.feature_key;
  end if;

  if v_feature.value_kind='categorical'
     and v_feature.allowed_values is not null
     and not (new.categorical_value = any(v_feature.allowed_values)) then
    raise exception 'MARK_FEATURE_CATEGORY_REJECTED: % is not allowed for feature %',
      new.categorical_value, new.feature_key;
  end if;

  if new.numeric_value is not null and v_feature.unit_key='unit_interval'
     and (new.numeric_value < 0 or new.numeric_value > 1) then
    raise exception 'MARK_FEATURE_RANGE_REJECTED: feature % requires 0..1', new.feature_key;
  end if;

  if new.integer_value is not null and v_feature.unit_key='count' and new.integer_value < 0 then
    raise exception 'MARK_FEATURE_RANGE_REJECTED: feature % count cannot be negative', new.feature_key;
  end if;

  return new;
end
$$;

create trigger validate_feature_observation_v1
before insert or update on mark.feature_observations
for each row execute function mark.validate_feature_observation_v1();

comment on table mark.feature_observations is
  'Typed blind physical measurements on components, relations, instances, or regions. Feature definitions are physical and clustering-safe.';

-- ---------------------------------------------------------------------------
-- Structural operators: graph motifs, not dictionary meanings.
-- These are derived/testable physical configurations and remain blind.
-- ---------------------------------------------------------------------------

create table mark.operator_registry (
  operator_key text primary key,
  operator_family text not null,
  operator_name text not null,
  structural_definition text not null,
  evidence_requirements jsonb not null default '{}'::jsonb,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(operator_key) <> ''),
  check (btrim(operator_family) <> ''),
  check (btrim(operator_name) <> '')
);

insert into mark.operator_registry(
  operator_key, operator_family, operator_name, structural_definition, evidence_requirements
)
values
  ('OP_REPEAT','multiplicity','Repeat',
   'Two or more locally homologous physical elements recur within a declared comparison scope.',
   '{"minimum_recurrent_elements":2}'::jsonb),
  ('OP_ATTACH','connectivity','Attach',
   'A physical element is connected to another at a localized attachment locus while remaining distinguishable as an element.',
   '{"relation_keys":["attached_to","has_attachment"]}'::jsonb),
  ('OP_BRANCH','connectivity','Branch',
   'One physical trajectory or body has multiple continuations or attached divergences from a shared locus.',
   '{"relation_keys":["branches_from","has_branch"]}'::jsonb),
  ('OP_ENCLOSE','containment','Enclose',
   'A boundary physically surrounds another element or bounded region.',
   '{"relation_keys":["contains","inside"]}'::jsonb),
  ('OP_CROSS','intersection','Cross',
   'Two physical trajectories intersect or pass across one another.',
   '{"relation_keys":["crosses"]}'::jsonb),
  ('OP_TERMINATE','connectivity','Terminate',
   'A physical trajectory ends at contact with another component or boundary.',
   '{"relation_keys":["terminates_on"]}'::jsonb),
  ('OP_ALIGN','orientation','Align',
   'Two or more physical elements share a measured alignment axis within declared tolerance.',
   '{"relation_keys":["aligned_with"]}'::jsonb),
  ('OP_PARALLEL','orientation','Parallel',
   'Two or more elongated physical elements maintain approximately parallel trajectories.',
   '{"relation_keys":["parallel_to"]}'::jsonb),
  ('OP_NEST','containment','Nest',
   'Containment occurs recursively across two or more bounded physical levels.',
   '{"minimum_containment_depth":2}'::jsonb),
  ('OP_STACK','orientation','Stack',
   'Multiple distinguishable physical elements occupy an ordered above/below arrangement without requiring contact.',
   '{"relation_keys":["above","below"]}'::jsonb),
  ('OP_BUNDLE','grouping','Bundle',
   'Multiple elongated physical elements occupy a locally grouped or jointly traveling configuration.',
   '{"morphology_keys":["bundled_body"]}'::jsonb),
  ('OP_WRAP','interlacing','Wrap',
   'One physical element turns around another through a measurable partial or complete revolution.',
   '{"relation_keys":["wraps_around","wrapped_by"]}'::jsonb),
  ('OP_INTERLOCK','interlacing','Interlock',
   'Two physical elements are mutually engaged through observable linked or alternating interlacing.',
   '{"relation_keys":["interlocks_with"]}'::jsonb),
  ('OP_GAP','spacing','Gap',
   'A bounded interval of negative space separates or structures neighboring physical elements.',
   '{"channel_keys":["void_interval"]}'::jsonb),
  ('OP_MIRROR','symmetry','Mirror',
   'A physical configuration approximately repeats under reflection about a measured axis.',
   '{"feature_keys":["symmetry_score"]}'::jsonb),
  ('OP_ALTERNATE','sequence','Alternate',
   'A physical sequence recurrently switches between two or more distinguishable structural states.',
   '{"minimum_states":2,"minimum_transitions":2}'::jsonb),
  ('OP_ROTATE_EQUIVALENT','recurrence','Rotation-equivalent recurrence',
   'Two physical configurations retain topology under a declared rotation transform.',
   '{"requires_transform_test":true}'::jsonb)
on conflict (operator_key) do nothing;

create table mark.operator_observations (
  operator_observation_id bigint generated always as identity primary key,
  observation_key text not null unique,
  operator_key text not null references mark.operator_registry(operator_key),
  region_id bigint not null references mark.regions(region_id),
  instance_id bigint null references mark.instances(instance_id),
  sequence_zone_id bigint null references mark.sequence_zones(sequence_zone_id),
  observation_basis text not null default 'deterministic_derived',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(observation_key) <> ''),
  check (observation_basis in ('observed','deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index operator_observations_operator_idx on mark.operator_observations(operator_key);
create index operator_observations_region_idx on mark.operator_observations(region_id);
create index operator_observations_instance_idx on mark.operator_observations(instance_id);
create index operator_observations_zone_idx on mark.operator_observations(sequence_zone_id);
create index operator_observations_derived_by_run_idx on mark.operator_observations(derived_by_run_id);

comment on table mark.operator_registry is
  'Blind structural operator vocabulary. Operators name recurrent physical graph configurations, not conventional meanings.';
comment on table mark.operator_observations is
  'Observed or computed instances of blind structural operators anchored to physical evidence regions.';

-- ---------------------------------------------------------------------------
-- Cross-instance topology intake.
-- Existing physical-sequence intake intentionally prevents cross-instance edges.
-- Material systems such as cord networks require them, so this separate narrow
-- intake adds only physical edges between already-custodied components.
-- ---------------------------------------------------------------------------

create or replace function mark.ingest_physical_topology_edges_v1(p_payload jsonb)
returns jsonb
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  v_relation jsonb;
  v_existing mark.component_relations%rowtype;
  v_subject mark.components%rowtype;
  v_object mark.components%rowtype;
  v_registry mark.relation_registry%rowtype;
  v_evidence_region_id bigint;
  v_subject_source_id bigint;
  v_object_source_id bigint;
  v_evidence_source_id bigint;
  v_key text;
  v_count integer := 0;
  v_observation_status text;
  v_confidence numeric;
  v_distance numeric;
  v_angle numeric;
begin
  perform mark.assert_json_keys_v1(p_payload, array['relations'], 'topology_payload');

  if jsonb_typeof(p_payload->'relations') <> 'array'
     or jsonb_array_length(p_payload->'relations') = 0 then
    raise exception 'MARK_TOPOLOGY_REQUIRED_FIELD: relations must be a non-empty JSON array';
  end if;

  for v_relation in select value from jsonb_array_elements(p_payload->'relations')
  loop
    perform mark.assert_json_keys_v1(
      v_relation,
      array[
        'relation_instance_key','subject_component_key','object_component_key',
        'relation_key','evidence_region_key','distance_px','angle_degrees',
        'observation_status','confidence'
      ],
      'topology_relation'
    );

    v_key := nullif(btrim(v_relation->>'relation_instance_key'),'');
    if v_key is null then
      raise exception 'MARK_TOPOLOGY_REQUIRED_FIELD: relation_instance_key';
    end if;

    select * into v_subject
    from mark.components
    where component_key = v_relation->>'subject_component_key';
    if not found then
      raise exception 'MARK_TOPOLOGY_UNKNOWN_COMPONENT: %', v_relation->>'subject_component_key';
    end if;

    select * into v_object
    from mark.components
    where component_key = v_relation->>'object_component_key';
    if not found then
      raise exception 'MARK_TOPOLOGY_UNKNOWN_COMPONENT: %', v_relation->>'object_component_key';
    end if;

    if v_subject.component_id = v_object.component_id then
      raise exception 'MARK_TOPOLOGY_SELF_RELATION: %', v_key;
    end if;

    select * into v_registry
    from mark.relation_registry
    where relation_key = v_relation->>'relation_key';
    if not found or not v_registry.strict_blind_allowed then
      raise exception 'MARK_TOPOLOGY_RELATION_REJECTED: % is not an approved blind physical relation', v_relation->>'relation_key';
    end if;

    select s.source_object_id into v_subject_source_id
    from mark.components c
    join mark.regions r on r.region_id=c.region_id
    join mark.surfaces s on s.surface_id=r.surface_id
    where c.component_id=v_subject.component_id;

    select s.source_object_id into v_object_source_id
    from mark.components c
    join mark.regions r on r.region_id=c.region_id
    join mark.surfaces s on s.surface_id=r.surface_id
    where c.component_id=v_object.component_id;

    if v_subject_source_id is distinct from v_object_source_id then
      raise exception 'MARK_TOPOLOGY_CROSS_OBJECT_RELATION: components % and % do not belong to the same physical source object',
        v_relation->>'subject_component_key', v_relation->>'object_component_key';
    end if;

    v_evidence_region_id := null;
    if nullif(btrim(v_relation->>'evidence_region_key'),'') is not null then
      select r.region_id, s.source_object_id
        into v_evidence_region_id, v_evidence_source_id
      from mark.regions r
      join mark.surfaces s on s.surface_id=r.surface_id
      where r.region_key=v_relation->>'evidence_region_key';

      if v_evidence_region_id is null then
        raise exception 'MARK_TOPOLOGY_UNKNOWN_REGION: %', v_relation->>'evidence_region_key';
      end if;
      if v_evidence_source_id is distinct from v_subject_source_id then
        raise exception 'MARK_TOPOLOGY_EVIDENCE_OBJECT_MISMATCH: evidence region belongs to a different physical source object';
      end if;
    end if;

    v_observation_status := coalesce(nullif(v_relation->>'observation_status',''),'observed_visible');
    if v_observation_status not in ('observed_visible','observed_damaged','observed_uncertain') then
      raise exception 'MARK_TOPOLOGY_OBSERVATION_STATUS_REJECTED: %', v_observation_status;
    end if;

    v_confidence := coalesce(nullif(v_relation->>'confidence','')::numeric,1.0);
    if v_confidence < 0 or v_confidence > 1 then
      raise exception 'MARK_TOPOLOGY_CONFIDENCE_REJECTED: confidence must be 0..1';
    end if;

    v_distance := nullif(v_relation->>'distance_px','')::numeric;
    v_angle := nullif(v_relation->>'angle_degrees','')::numeric;

    select * into v_existing
    from mark.component_relations
    where relation_instance_key=v_key;

    if found then
      if v_existing.subject_component_id <> v_subject.component_id
         or v_existing.object_component_id <> v_object.component_id
         or v_existing.relation_key <> v_registry.relation_key
         or v_existing.evidence_region_id is distinct from v_evidence_region_id
         or v_existing.distance_px is distinct from v_distance
         or v_existing.angle_degrees is distinct from v_angle
         or v_existing.observation_status <> v_observation_status
         or v_existing.confidence <> v_confidence then
        raise exception 'MARK_TOPOLOGY_KEY_CONFLICT: relation_instance_key % already names different physical evidence', v_key;
      end if;
    else
      insert into mark.component_relations(
        relation_instance_key, subject_component_id, object_component_id, relation_key,
        evidence_region_id, distance_px, angle_degrees, observation_status, confidence
      ) values (
        v_key, v_subject.component_id, v_object.component_id, v_registry.relation_key,
        v_evidence_region_id, v_distance, v_angle, v_observation_status, v_confidence
      );
    end if;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('relation_count',v_count);
end
$$;

revoke all on function mark.validate_feature_observation_v1() from public, anon, authenticated, service_role;
revoke all on function mark.ingest_physical_topology_edges_v1(jsonb) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Blind machine surfaces: numeric IDs + physical observations only.
-- Historical system identity is deliberately absent.
-- ---------------------------------------------------------------------------

create view mark.blind_component_graph_v1
with (security_invoker = true)
as
select
  c.component_id,
  c.instance_id,
  c.channel_key,
  c.component_order,
  cm.morphology_key,
  cm.confidence as morphology_confidence,
  c.confidence as component_confidence
from mark.components c
left join mark.component_morphologies cm on cm.component_id=c.component_id;

create view mark.blind_topology_edges_v1
with (security_invoker = true)
as
select
  cr.component_relation_id,
  cr.subject_component_id,
  cr.object_component_id,
  cr.relation_key,
  cr.distance_px,
  cr.angle_degrees,
  cr.confidence
from mark.component_relations cr;

create view mark.blind_feature_observations_v1
with (security_invoker = true)
as
select
  fo.feature_observation_id,
  fo.feature_key,
  fo.component_id,
  fo.component_relation_id,
  fo.instance_id,
  fo.region_id,
  fo.numeric_value,
  fo.integer_value,
  fo.boolean_value,
  fo.categorical_value,
  fo.confidence
from mark.feature_observations fo;

comment on view mark.blind_component_graph_v1 is
  'Clustering surface containing physical component IDs, channels, morphology, order, and confidence only. No historical system identity.';
comment on view mark.blind_topology_edges_v1 is
  'Clustering surface containing physical graph edges only. No source labels, culture, language, readings, or historical-system identity.';
comment on view mark.blind_feature_observations_v1 is
  'Clustering surface containing typed physical features only. No historical-system identity.';

-- ---------------------------------------------------------------------------
-- Context membrane. This is the deliberate rejoin layer.
-- ---------------------------------------------------------------------------

create schema if not exists mark_context authorization postgres;
comment on schema mark_context is
  'Historical and comparative context for Mark evidence. This schema may name writing/sign/record systems, but blind clustering must operate without joining it.';

revoke all on schema mark_context from public, anon, authenticated, service_role;
alter default privileges in schema mark_context revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema mark_context revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema mark_context revoke all on functions from public, anon, authenticated, service_role;

create table mark_context.system_registry (
  system_key text primary key,
  blind_code text not null unique,
  canonical_label text not null,
  context_class text not null,
  comparison_role text not null,
  parent_system_key text null references mark_context.system_registry(system_key),
  context_notes text null,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(system_key) <> ''),
  check (blind_code ~ '^SYS[0-9]{3}$'),
  check (btrim(canonical_label) <> ''),
  check (context_class in ('graphic_sign_system','cord_record_system','tally_record_system','token_record_system','formal_notation_system')),
  check (comparison_role in ('primary_origin_sample','historical_lineage_sample','undeciphered_sample','cross_medium_foundation','modern_notation_control')),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

insert into mark_context.system_registry(
  system_key, blind_code, canonical_label, context_class, comparison_role, parent_system_key
)
values
  ('proto_cuneiform','SYS001','Proto-cuneiform','graphic_sign_system','primary_origin_sample',null),
  ('cuneiform','SYS002','Cuneiform','graphic_sign_system','historical_lineage_sample','proto_cuneiform'),
  ('egyptian_hieroglyphic','SYS003','Egyptian hieroglyphic','graphic_sign_system','primary_origin_sample',null),
  ('hieratic','SYS004','Hieratic','graphic_sign_system','historical_lineage_sample','egyptian_hieroglyphic'),
  ('oracle_bone_chinese','SYS005','Oracle-bone Chinese inscriptions','graphic_sign_system','primary_origin_sample',null),
  ('chinese_bronze_inscriptions','SYS006','Chinese bronze inscriptions','graphic_sign_system','historical_lineage_sample',null),
  ('maya','SYS007','Maya glyphic writing','graphic_sign_system','primary_origin_sample',null),
  ('indus','SYS008','Indus signs','graphic_sign_system','undeciphered_sample',null),
  ('linear_a','SYS009','Linear A','graphic_sign_system','undeciphered_sample',null),
  ('linear_b','SYS010','Linear B','graphic_sign_system','historical_lineage_sample',null),
  ('proto_sinaitic_canaanite','SYS011','Proto-Sinaitic / early Canaanite','graphic_sign_system','historical_lineage_sample',null),
  ('phoenician','SYS012','Phoenician','graphic_sign_system','historical_lineage_sample','proto_sinaitic_canaanite'),
  ('archaic_greek','SYS013','Archaic Greek alphabets','graphic_sign_system','historical_lineage_sample','phoenician'),
  ('brahmi','SYS014','Brahmi','graphic_sign_system','historical_lineage_sample',null),
  ('elder_futhark','SYS015','Elder Futhark','graphic_sign_system','historical_lineage_sample',null),
  ('ogham','SYS016','Ogham','graphic_sign_system','historical_lineage_sample',null),
  ('khipu','SYS017','Khipu','cord_record_system','cross_medium_foundation',null),
  ('tally_marks','SYS018','Tally marks','tally_record_system','cross_medium_foundation',null),
  ('clay_accounting_tokens','SYS019','Clay accounting tokens','token_record_system','cross_medium_foundation',null),
  ('mathematical_notation','SYS020','Mathematical notation','formal_notation_system','modern_notation_control',null)
on conflict (system_key) do nothing;

create table mark_context.corpus_batches (
  batch_key text primary key,
  batch_label text not null,
  target_total integer not null,
  status text not null default 'planned',
  blind_contract text not null,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(batch_key) <> ''),
  check (target_total > 0),
  check (status in ('planned','active','frozen','retired')),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

insert into mark_context.corpus_batches(
  batch_key, batch_label, target_total, blind_contract
)
values (
  'global_topology_pilot_v1',
  'Global Topology Pilot v1',
  1500,
  'Balanced pilot of candidate physical units. Culture/system labels, conventional sign names, readings, and meanings are excluded from clustering inputs; mark_context is rejoined only after blind clusters are frozen.'
)
on conflict (batch_key) do nothing;

create table mark_context.corpus_batch_targets (
  batch_key text not null references mark_context.corpus_batches(batch_key),
  system_key text not null references mark_context.system_registry(system_key),
  target_units integer not null,
  priority_order integer not null,
  sampling_role text not null default 'balanced_representative',
  notes text null,
  primary key (batch_key, system_key),
  unique(batch_key, priority_order),
  check (target_units > 0),
  check (priority_order >= 0),
  check (sampling_role in ('balanced_representative','control','lineage_bridge','undeciphered_probe'))
);

insert into mark_context.corpus_batch_targets(
  batch_key, system_key, target_units, priority_order, sampling_role
)
select
  'global_topology_pilot_v1',
  s.system_key,
  75,
  substring(s.blind_code from 4 for 3)::integer,
  case
    when s.comparison_role='cross_medium_foundation' then 'control'
    when s.comparison_role='undeciphered_sample' then 'undeciphered_probe'
    when s.comparison_role='historical_lineage_sample' then 'lineage_bridge'
    else 'balanced_representative'
  end
from mark_context.system_registry s
where s.blind_code between 'SYS001' and 'SYS020'
on conflict (batch_key,system_key) do nothing;

create table mark_context.source_system_assignments (
  source_object_id bigint not null references mark.source_objects(source_object_id),
  system_key text not null references mark_context.system_registry(system_key),
  assignment_basis text not null,
  confidence numeric not null default 1.0,
  context_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (source_object_id, system_key),
  check (assignment_basis in ('catalogue','scholarly_consensus','project_control','provisional')), 
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index source_system_assignments_system_idx
  on mark_context.source_system_assignments(system_key);
create index corpus_batch_targets_system_idx
  on mark_context.corpus_batch_targets(system_key);

comment on table mark_context.system_registry is
  'Unblinding registry for historical/sign/record-system identity. It is intentionally separated from blind Mark evidence.';
comment on table mark_context.source_system_assignments is
  'Deliberate rejoin mapping from physically custodied Mark source objects to historical system context.';
comment on table mark_context.corpus_batch_targets is
  'Balanced sampling plan. Target counts structure corpus acquisition but are never clustering features.';

-- ---------------------------------------------------------------------------
-- Freeze behavior, RLS, privilege membrane, and correction lineage.
-- ---------------------------------------------------------------------------

do $$
declare rel text;
begin
  foreach rel in array array[
    'component_morphologies','feature_observations','operator_observations'
  ] loop
    execute format(
      'create trigger %I before update or delete on mark.%I for each row execute function mark.guard_frozen_row_v1()',
      'guard_frozen_' || rel || '_v1', rel
    );
    execute format(
      'create trigger %I before update on mark.%I for each row execute function mark.touch_updated_at_v1()',
      'touch_updated_' || rel || '_v1', rel
    );
  end loop;
end
$$;

do $$
declare rel text;
begin
  foreach rel in array array[
    'system_registry','corpus_batches','source_system_assignments'
  ] loop
    execute format(
      'create trigger %I before update or delete on mark_context.%I for each row execute function mark.guard_frozen_row_v1()',
      'guard_frozen_' || rel || '_v1', rel
    );
    execute format(
      'create trigger %I before update on mark_context.%I for each row execute function mark.touch_updated_at_v1()',
      'touch_updated_' || rel || '_v1', rel
    );
  end loop;
end
$$;

alter table mark.record_supersessions
  drop constraint if exists record_supersessions_object_type_check;
alter table mark.record_supersessions
  add constraint record_supersessions_object_type_check
  check (object_type in (
    'source_object','surface','capture','capture_surface','capture_equivalence','region',
    'instance','component','component_relation','sequence_zone','sequence_member',
    'component_morphology','feature_observation','operator_observation'
  ));

alter table mark.morphology_registry enable row level security;
alter table mark.component_morphologies enable row level security;
alter table mark.feature_registry enable row level security;
alter table mark.feature_observations enable row level security;
alter table mark.operator_registry enable row level security;
alter table mark.operator_observations enable row level security;

alter table mark_context.system_registry enable row level security;
alter table mark_context.corpus_batches enable row level security;
alter table mark_context.corpus_batch_targets enable row level security;
alter table mark_context.source_system_assignments enable row level security;

revoke all on table
  mark.morphology_registry,
  mark.component_morphologies,
  mark.feature_registry,
  mark.feature_observations,
  mark.operator_registry,
  mark.operator_observations,
  mark.blind_component_graph_v1,
  mark.blind_topology_edges_v1,
  mark.blind_feature_observations_v1
from public, anon, authenticated, service_role;

revoke all on all tables in schema mark_context from public, anon, authenticated, service_role;
revoke all on all sequences in schema mark_context from public, anon, authenticated, service_role;

-- Final membrane assertions.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark_context','USAGE')
       or has_function_privilege(role_name,'mark.ingest_physical_topology_edges_v1(jsonb)','EXECUTE') then
      raise exception 'MARK_GLOBAL_TOPOLOGY_MEMBRANE_VIOLATION: runtime role % can reach blind/context topology authority', role_name;
    end if;
  end loop;
end
$$;

commit;
