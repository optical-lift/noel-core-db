begin;

-- Mark Operational Grammar Kernel v1.
--
-- Purpose: compare physical states by their minimal structural differences rather
-- than by sign identity or appearance. A contrast pair is not assumed to be a
-- historical before/after sequence. Direction is explicit and may be purely
-- canonical for comparison.
--
-- mark remains blind: no culture, reading, sign name, language, or conventional
-- meaning is admitted here.

create table mark.delta_registry (
  delta_key text primary key,
  delta_family text not null,
  delta_name text not null,
  value_kind text not null,
  structural_definition text not null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(delta_key) <> ''),
  check (btrim(delta_family) <> ''),
  check (btrim(delta_name) <> ''),
  check (value_kind in ('integer','numeric','presence','categorical'))
);

insert into mark.delta_registry(delta_key,delta_family,delta_name,value_kind,structural_definition)
values
  ('D_COMPONENT_COUNT','composition','Component-count delta','integer','Signed difference in count of physical components between two candidate states.'),
  ('D_TOPOLOGY_DEGREE','topology','Topology-degree delta','integer','Signed difference in incident physical-relation count between two candidate states.'),
  ('D_REPETITION_COUNT','multiplicity','Repetition-count delta','integer','Signed difference in local homologous repetition count.'),
  ('D_LOOP_COUNT','topology','Loop-count delta','integer','Signed difference in observed closed-loop count.'),
  ('D_TERMINAL_COUNT','topology','Terminal-count delta','integer','Signed difference in observed terminal count.'),
  ('D_CLOSURE_SCORE','closure','Closure-score delta','numeric','Signed change in normalized closure score.'),
  ('D_ORIENTATION_DEGREES','orientation','Orientation delta','numeric','Signed angular change in principal orientation under a declared normalization.'),
  ('D_ATTACHMENT_PRESENCE','connectivity','Attachment presence','presence','Presence or absence change of a localized attachment relation.'),
  ('D_BRANCH_PRESENCE','connectivity','Branch presence','presence','Presence or absence change of branching topology.'),
  ('D_CROSSING_PRESENCE','intersection','Crossing presence','presence','Presence or absence change of a trajectory crossing.'),
  ('D_ENCLOSURE_PRESENCE','containment','Enclosure presence','presence','Presence or absence change of physical containment or enclosure.'),
  ('D_GAP_PRESENCE','spacing','Gap presence','presence','Presence or absence change of a bounded negative-space interval.'),
  ('D_WRAP_PRESENCE','interlacing','Wrap presence','presence','Presence or absence change of a wraps-around relation.'),
  ('D_INTERLOCK_PRESENCE','interlacing','Interlock presence','presence','Presence or absence change of interlocking topology.'),
  ('D_STACK_PRESENCE','orientation','Stack presence','presence','Presence or absence change of an ordered above/below relation.'),
  ('D_ALIGNMENT_PRESENCE','orientation','Alignment presence','presence','Presence or absence change of measured alignment.'),
  ('D_MORPHOLOGY_STATE','morphology','Morphology-state transition','categorical','Change from one blind physical morphology class to another.'),
  ('D_RELATIVE_POSITION_STATE','position','Relative-position transition','categorical','Change between blind relative-position states such as above, below, inside, or outside.')
on conflict (delta_key) do nothing;

create table mark.transformation_registry (
  transformation_key text primary key,
  transformation_family text not null,
  transformation_name text not null,
  operator_key text null,
  direction_mode text not null,
  structural_definition text not null,
  evidence_requirements jsonb not null default '{}'::jsonb,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(transformation_key) <> ''),
  check (direction_mode in ('directed','symmetric'))
);

insert into mark.transformation_registry(
  transformation_key,transformation_family,transformation_name,operator_key,direction_mode,structural_definition,evidence_requirements
)
values
  ('TX_ADD_COMPONENT','composition','Add component',null,'directed','One state contains one or more additional distinguishable physical components relative to the paired state.','{"delta_key":"D_COMPONENT_COUNT","sign":"positive"}'::jsonb),
  ('TX_REMOVE_COMPONENT','composition','Remove component',null,'directed','One state contains one or more fewer distinguishable physical components relative to the paired state.','{"delta_key":"D_COMPONENT_COUNT","sign":"negative"}'::jsonb),
  ('TX_ADD_ATTACHMENT','connectivity','Add attachment','OP_ATTACH','directed','A localized attachment relation is present in the variant state and absent in the paired base state.','{"delta_key":"D_ATTACHMENT_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_REMOVE_ATTACHMENT','connectivity','Remove attachment','OP_ATTACH','directed','A localized attachment relation is absent in the variant state and present in the paired base state.','{"delta_key":"D_ATTACHMENT_PRESENCE","presence_delta":-1}'::jsonb),
  ('TX_ADD_BRANCH','connectivity','Add branch','OP_BRANCH','directed','Branching topology is introduced relative to the paired state.','{"delta_key":"D_BRANCH_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_CROSSING','intersection','Add crossing','OP_CROSS','directed','A crossing relation is introduced relative to the paired state.','{"delta_key":"D_CROSSING_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_ENCLOSURE','containment','Add enclosure','OP_ENCLOSE','directed','A containment or enclosure relation is introduced relative to the paired state.','{"delta_key":"D_ENCLOSURE_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_OPEN_BOUNDARY','closure','Open boundary',null,'directed','A previously more closed physical boundary becomes measurably more open.','{"delta_key":"D_CLOSURE_SCORE","sign":"negative"}'::jsonb),
  ('TX_CLOSE_BOUNDARY','closure','Close boundary',null,'directed','A previously more open physical boundary becomes measurably more closed.','{"delta_key":"D_CLOSURE_SCORE","sign":"positive"}'::jsonb),
  ('TX_ADD_GAP','spacing','Add gap','OP_GAP','directed','A bounded interval of negative space is introduced relative to the paired state.','{"delta_key":"D_GAP_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_WRAP','interlacing','Add wrap','OP_WRAP','directed','A wraps-around relation is introduced relative to the paired state.','{"delta_key":"D_WRAP_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_INTERLOCK','interlacing','Add interlock','OP_INTERLOCK','directed','An interlocking relation is introduced relative to the paired state.','{"delta_key":"D_INTERLOCK_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_REPEAT','multiplicity','Increase repetition','OP_REPEAT','directed','The count of locally homologous repeated elements increases.','{"delta_key":"D_REPETITION_COUNT","sign":"positive"}'::jsonb),
  ('TX_ADD_STACK','orientation','Add stack relation','OP_STACK','directed','An ordered above/below relationship is introduced relative to the paired state.','{"delta_key":"D_STACK_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ADD_ALIGNMENT','orientation','Add alignment','OP_ALIGN','directed','A measured alignment relation is introduced relative to the paired state.','{"delta_key":"D_ALIGNMENT_PRESENCE","presence_delta":1}'::jsonb),
  ('TX_ROTATE','orientation','Rotate',null,'directed','The principal orientation changes while other declared topology is held invariant.','{"delta_key":"D_ORIENTATION_DEGREES"}'::jsonb),
  ('TX_CHANGE_MORPHOLOGY','morphology','Change morphology',null,'directed','A homologous physical component changes blind morphology class.','{"delta_key":"D_MORPHOLOGY_STATE"}'::jsonb),
  ('TX_MOVE_RELATIVE','position','Move relative position',null,'directed','A homologous element changes its relative physical position with respect to a carrier or comparison frame.','{"delta_key":"D_RELATIVE_POSITION_STATE"}'::jsonb),
  ('TX_GEOMETRIC_VARIANT','invariance','Geometric variant',null,'symmetric','Paired states preserve declared topology and morphology while differing only in continuous geometry such as scale or aspect.','{"requires_topology_invariance":true,"requires_morphology_invariance":true}'::jsonb)
on conflict (transformation_key) do nothing;

-- The production-schema clone intentionally contains registry schema but not
-- seeded registry rows. Create the cross-registry FK without scanning existing
-- seed rows, then validate it when the parent operator registry is populated.
alter table mark.transformation_registry
  add constraint transformation_registry_operator_key_fkey
  foreign key (operator_key) references mark.operator_registry(operator_key)
  not valid;

do $$
begin
  if not exists (
    select 1
    from mark.transformation_registry t
    left join mark.operator_registry o on o.operator_key=t.operator_key
    where t.operator_key is not null and o.operator_key is null
  ) then
    alter table mark.transformation_registry
      validate constraint transformation_registry_operator_key_fkey;
  end if;
end
$$;

create table mark.contrast_pairs (
  contrast_pair_id bigint generated always as identity primary key,
  pair_key text not null unique,
  left_instance_id bigint not null references mark.instances(instance_id),
  right_instance_id bigint not null references mark.instances(instance_id),
  comparison_scope text not null,
  direction_basis text not null default 'unordered',
  contrast_class text not null default 'unknown',
  admissibility text not null default 'candidate',
  distance_score numeric null,
  observation_basis text not null default 'deterministic_derived',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(pair_key) <> ''),
  check (left_instance_id <> right_instance_id),
  check (comparison_scope in ('same_sequence','same_surface','same_source_object','cross_object_blind')),
  check (direction_basis in ('unordered','canonical_complexity','sequence_position','physical_superposition')),
  check (contrast_class in ('unknown','minimal_delta','invariance','compound_delta')),
  check (admissibility in ('candidate','admissible','rejected')),
  check (observation_basis in ('observed','deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index contrast_pairs_left_idx on mark.contrast_pairs(left_instance_id);
create index contrast_pairs_right_idx on mark.contrast_pairs(right_instance_id);
create index contrast_pairs_scope_idx on mark.contrast_pairs(comparison_scope);

create or replace function mark.validate_contrast_pair_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  l_surface bigint;
  r_surface bigint;
  l_source bigint;
  r_source bigint;
begin
  select r.surface_id,s.source_object_id into l_surface,l_source
  from mark.instances i
  join mark.regions r on r.region_id=i.region_id
  join mark.surfaces s on s.surface_id=r.surface_id
  where i.instance_id=new.left_instance_id;

  select r.surface_id,s.source_object_id into r_surface,r_source
  from mark.instances i
  join mark.regions r on r.region_id=i.region_id
  join mark.surfaces s on s.surface_id=r.surface_id
  where i.instance_id=new.right_instance_id;

  if new.comparison_scope='same_surface' and l_surface is distinct from r_surface then
    raise exception 'MARK_CONTRAST_SCOPE_MISMATCH: same_surface pair crosses surfaces';
  elsif new.comparison_scope='same_source_object' and l_source is distinct from r_source then
    raise exception 'MARK_CONTRAST_SCOPE_MISMATCH: same_source_object pair crosses objects';
  elsif new.comparison_scope='cross_object_blind' and l_source is not distinct from r_source then
    raise exception 'MARK_CONTRAST_SCOPE_MISMATCH: cross_object_blind pair is within one object';
  elsif new.comparison_scope='same_sequence' and not exists (
    select 1
    from mark.sequence_members a
    join mark.sequence_members b on b.sequence_zone_id=a.sequence_zone_id
    where a.instance_id=new.left_instance_id and b.instance_id=new.right_instance_id
  ) then
    raise exception 'MARK_CONTRAST_SCOPE_MISMATCH: same_sequence pair has no shared physical sequence zone';
  end if;

  if new.direction_basis='sequence_position' and new.comparison_scope <> 'same_sequence' then
    raise exception 'MARK_CONTRAST_DIRECTION_MISMATCH: sequence_position requires same_sequence scope';
  end if;

  return new;
end
$$;

create trigger validate_contrast_pair_v1
before insert or update on mark.contrast_pairs
for each row execute function mark.validate_contrast_pair_v1();

create table mark.contrast_deltas (
  contrast_delta_id bigint generated always as identity primary key,
  contrast_pair_id bigint not null references mark.contrast_pairs(contrast_pair_id),
  delta_key text not null references mark.delta_registry(delta_key),
  numeric_delta numeric null,
  integer_delta bigint null,
  presence_delta smallint null,
  from_state text null,
  to_state text null,
  observation_basis text not null default 'deterministic_derived',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(contrast_pair_id,delta_key),
  check (presence_delta is null or presence_delta in (-1,1)),
  check (observation_basis in ('observed','deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index contrast_deltas_delta_idx on mark.contrast_deltas(delta_key);

create or replace function mark.validate_contrast_delta_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
declare
  k text;
begin
  select value_kind into k from mark.delta_registry
  where delta_key=new.delta_key and strict_blind_allowed;
  if k is null then
    raise exception 'MARK_CONTRAST_DELTA_REJECTED: unknown or non-blind delta %',new.delta_key;
  end if;

  if k='integer' and (new.integer_delta is null or num_nonnulls(new.numeric_delta,new.presence_delta,new.from_state,new.to_state) <> 0) then
    raise exception 'MARK_CONTRAST_DELTA_VALUE_MISMATCH: % requires integer_delta',new.delta_key;
  elsif k='numeric' and (new.numeric_delta is null or num_nonnulls(new.integer_delta,new.presence_delta,new.from_state,new.to_state) <> 0) then
    raise exception 'MARK_CONTRAST_DELTA_VALUE_MISMATCH: % requires numeric_delta',new.delta_key;
  elsif k='presence' and (new.presence_delta is null or num_nonnulls(new.integer_delta,new.numeric_delta,new.from_state,new.to_state) <> 0) then
    raise exception 'MARK_CONTRAST_DELTA_VALUE_MISMATCH: % requires presence_delta',new.delta_key;
  elsif k='categorical' and (
      new.from_state is null or new.to_state is null or new.from_state=new.to_state
      or num_nonnulls(new.integer_delta,new.numeric_delta,new.presence_delta) <> 0
    ) then
    raise exception 'MARK_CONTRAST_DELTA_VALUE_MISMATCH: % requires distinct from_state/to_state',new.delta_key;
  end if;
  return new;
end
$$;

create trigger validate_contrast_delta_v1
before insert or update on mark.contrast_deltas
for each row execute function mark.validate_contrast_delta_v1();

create table mark.contrast_transformations (
  contrast_transformation_id bigint generated always as identity primary key,
  contrast_pair_id bigint not null references mark.contrast_pairs(contrast_pair_id),
  transformation_key text not null references mark.transformation_registry(transformation_key),
  observation_basis text not null default 'model_proposal',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(contrast_pair_id,transformation_key),
  check (observation_basis in ('deterministic_derived','model_proposal','human_proposal')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create index contrast_transformations_key_idx on mark.contrast_transformations(transformation_key);

create view mark.blind_contrast_pairs_v1
with (security_invoker = true)
as
select contrast_pair_id,left_instance_id,right_instance_id,comparison_scope,direction_basis,
       contrast_class,admissibility,distance_score,confidence
from mark.contrast_pairs;

create view mark.blind_contrast_deltas_v1
with (security_invoker = true)
as
select contrast_delta_id,contrast_pair_id,delta_key,numeric_delta,integer_delta,
       presence_delta,from_state,to_state,confidence
from mark.contrast_deltas;

create view mark.blind_contrast_transformations_v1
with (security_invoker = true)
as
select contrast_transformation_id,contrast_pair_id,transformation_key,confidence
from mark.contrast_transformations;

create view mark.blind_transformation_recurrence_v1
with (security_invoker = true)
as
select
  ct.transformation_key,
  count(distinct ct.contrast_pair_id)::bigint as pair_count,
  count(distinct src.source_object_id)::bigint as distinct_source_object_count,
  min(ct.confidence) as minimum_confidence,
  avg(ct.confidence) as mean_confidence
from mark.contrast_transformations ct
join mark.contrast_pairs cp on cp.contrast_pair_id=ct.contrast_pair_id
join lateral (
  select s.source_object_id
  from mark.instances i
  join mark.regions r on r.region_id=i.region_id
  join mark.surfaces s on s.surface_id=r.surface_id
  where i.instance_id=cp.left_instance_id
  union
  select s.source_object_id
  from mark.instances i
  join mark.regions r on r.region_id=i.region_id
  join mark.surfaces s on s.surface_id=r.surface_id
  where i.instance_id=cp.right_instance_id
) src on true
where cp.admissibility='admissible'
group by ct.transformation_key;

comment on table mark.contrast_pairs is
  'Blind physical-state contrasts. A pair does not imply historical chronology or semantic derivation.';
comment on table mark.contrast_deltas is
  'Typed physical differences between paired states, prior to cultural or linguistic interpretation.';
comment on table mark.contrast_transformations is
  'Blind transformation candidates inferred from one or more physical deltas.';
comment on view mark.blind_transformation_recurrence_v1 is
  'Counts recurrence of blind physical transformations across distinct source objects without exposing historical system identity.';

-- Freeze/correction behavior.
do $$
declare rel text;
begin
  foreach rel in array array['contrast_pairs','contrast_deltas','contrast_transformations'] loop
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

alter table mark.record_supersessions
  drop constraint if exists record_supersessions_object_type_check;
alter table mark.record_supersessions
  add constraint record_supersessions_object_type_check
  check (object_type in (
    'source_object','surface','capture','capture_surface','capture_equivalence','region',
    'instance','component','component_relation','sequence_zone','sequence_member',
    'component_morphology','feature_observation','operator_observation',
    'contrast_pair','contrast_delta','contrast_transformation'
  ));

alter table mark.delta_registry enable row level security;
alter table mark.transformation_registry enable row level security;
alter table mark.contrast_pairs enable row level security;
alter table mark.contrast_deltas enable row level security;
alter table mark.contrast_transformations enable row level security;

revoke all on table
  mark.delta_registry,
  mark.transformation_registry,
  mark.contrast_pairs,
  mark.contrast_deltas,
  mark.contrast_transformations,
  mark.blind_contrast_pairs_v1,
  mark.blind_contrast_deltas_v1,
  mark.blind_contrast_transformations_v1,
  mark.blind_transformation_recurrence_v1
from public, anon, authenticated, service_role;

revoke all on function mark.validate_contrast_pair_v1() from public, anon, authenticated, service_role;
revoke all on function mark.validate_contrast_delta_v1() from public, anon, authenticated, service_role;

-- Runtime roles must remain outside both blind evidence and context authority.
do $$
declare role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name,'mark','USAGE')
       or has_schema_privilege(role_name,'mark_context','USAGE')
       or has_table_privilege(role_name,'mark.contrast_pairs','SELECT')
       or has_table_privilege(role_name,'mark.blind_contrast_pairs_v1','SELECT') then
      raise exception 'MARK_OPERATIONAL_GRAMMAR_MEMBRANE_VIOLATION: runtime role % can reach contrast authority',role_name;
    end if;
  end loop;
end
$$;

commit;
