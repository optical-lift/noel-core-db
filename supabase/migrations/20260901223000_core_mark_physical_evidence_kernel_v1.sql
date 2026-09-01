begin;

create schema if not exists mark authorization postgres;

comment on schema mark is
  'Noel physical mark evidence custody. Stores source objects, immutable captures, geometry, components, junctions, and anonymous sequence position without linguistic or semantic authority.';

revoke all on schema mark from public, anon, authenticated, service_role;
alter default privileges in schema mark revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema mark revoke all on sequences from public, anon, authenticated, service_role;
alter default privileges in schema mark revoke all on functions from public, anon, authenticated, service_role;

create table mark.channel_registry (
  channel_key text primary key,
  channel_family text not null,
  channel_name text not null,
  physical_basis text not null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(channel_key) <> ''),
  check (btrim(channel_family) <> ''),
  check (btrim(channel_name) <> '')
);

comment on table mark.channel_registry is
  'Physical rendering channels only. Entries describe observable media or damage classes, never linguistic function.';

insert into mark.channel_registry(channel_key, channel_family, channel_name, physical_basis, strict_blind_allowed)
values
  ('ink_dark', 'pigment', 'Dark ink/pigment', 'Observed low-luminance deposited material.', true),
  ('pigment_red', 'pigment', 'Red pigment', 'Observed red-hued deposited material.', true),
  ('pigment_orange_yellow', 'pigment', 'Orange/yellow pigment', 'Observed orange/yellow-hued deposited material.', true),
  ('incision', 'subtractive', 'Incised mark', 'Observed groove, cut, or impressed channel in the support.', true),
  ('damage', 'surface_condition', 'Damage/loss', 'Observed physical loss, abrasion, tear, occlusion, or unreadable surface state.', true),
  ('unknown_physical', 'unknown', 'Unknown physical channel', 'Visible distinction whose material/channel class is not yet resolved.', true)
on conflict (channel_key) do nothing;

create table mark.relation_registry (
  relation_key text primary key,
  relation_family text not null,
  relation_name text not null,
  directed boolean not null default true,
  physical_definition text not null,
  inverse_relation_key text null,
  strict_blind_allowed boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(relation_key) <> ''),
  check (btrim(relation_family) <> ''),
  check (btrim(relation_name) <> '')
);

alter table mark.relation_registry
  add constraint relation_registry_inverse_relation_key_fkey
  foreign key (inverse_relation_key) references mark.relation_registry(relation_key);

insert into mark.relation_registry(relation_key, relation_family, relation_name, directed, physical_definition, inverse_relation_key)
values
  ('touches', 'junction', 'Touches', false, 'Two observed components meet at one or more physical boundary points.', null),
  ('crosses', 'junction', 'Crosses', false, 'One observed component passes across the trajectory of another.', null),
  ('overlaps', 'junction', 'Overlaps', false, 'Observed component regions share physical image area.', null),
  ('inside', 'containment', 'Inside', true, 'The subject is spatially contained by the object region.', 'contains'),
  ('contains', 'containment', 'Contains', true, 'The subject spatially contains the object region.', 'inside'),
  ('above', 'orientation', 'Above', true, 'The subject centroid/extent is physically above the object in the registered surface orientation.', 'below'),
  ('below', 'orientation', 'Below', true, 'The subject centroid/extent is physically below the object in the registered surface orientation.', 'above'),
  ('left_of', 'orientation', 'Left of', true, 'The subject lies physically left of the object in registered surface orientation.', 'right_of'),
  ('right_of', 'orientation', 'Right of', true, 'The subject lies physically right of the object in registered surface orientation.', 'left_of'),
  ('extends_through', 'junction', 'Extends through', true, 'The subject continues through the object boundary/trajectory.', null),
  ('terminates_on', 'junction', 'Terminates on', true, 'The subject ends at an observed contact with the object.', null),
  ('adjacent_to', 'proximity', 'Adjacent to', false, 'The subject and object are immediate physical neighbors under the stated proximity method.', null),
  ('aligned_with', 'orientation', 'Aligned with', false, 'The subject and object share a measured alignment axis within tolerance.', null),
  ('connected_to', 'connectivity', 'Connected to', false, 'The subject and object belong to one observed connected stroke/material network.', null)
on conflict (relation_key) do nothing;

update mark.relation_registry r
set inverse_relation_key = v.inverse_key
from (values
  ('inside','contains'), ('contains','inside'),
  ('above','below'), ('below','above'),
  ('left_of','right_of'), ('right_of','left_of')
) as v(relation_key,inverse_key)
where r.relation_key=v.relation_key
  and r.inverse_relation_key is distinct from v.inverse_key;

create table mark.source_objects (
  source_object_id bigint generated always as identity primary key,
  object_key text not null unique,
  object_kind text not null,
  object_label text null,
  parent_source_object_id bigint null references mark.source_objects(source_object_id),
  institution_name text null,
  collection_name text null,
  collection_identifier text null,
  shelfmark text null,
  material text null,
  date_min_year integer null,
  date_max_year integer null,
  authority_status text not null default 'registered',
  provenance jsonb not null default '{}'::jsonb,
  rights jsonb not null default '{}'::jsonb,
  source_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(object_key) <> ''),
  check (btrim(object_kind) <> ''),
  check (parent_source_object_id is null or parent_source_object_id <> source_object_id),
  check (date_min_year is null or date_max_year is null or date_min_year <= date_max_year),
  check (authority_status in ('registered','source_verified','physical_verified','unavailable')),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.surfaces (
  surface_id bigint generated always as identity primary key,
  surface_key text not null unique,
  source_object_id bigint not null references mark.source_objects(source_object_id),
  surface_label text null,
  surface_role text not null default 'unspecified',
  physical_order numeric null,
  width_value numeric null,
  height_value numeric null,
  dimension_unit text null,
  orientation_payload jsonb not null default '{}'::jsonb,
  surface_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(surface_key) <> ''),
  check (btrim(surface_role) <> ''),
  check (width_value is null or width_value > 0),
  check (height_value is null or height_value > 0),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.captures (
  capture_id bigint generated always as identity primary key,
  capture_key text not null unique,
  capture_kind text not null,
  source_uri text null,
  original_filename text null,
  mime_type text null,
  width_px integer null,
  height_px integer null,
  sha256 text null,
  perceptual_hash text null,
  storage_bucket text null,
  storage_object_path text null,
  capture_status text not null default 'registered_remote',
  derivative_of_capture_id bigint null references mark.captures(capture_id),
  derivative_kind text null,
  acquisition_metadata jsonb not null default '{}'::jsonb,
  rights jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  acquired_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(capture_key) <> ''),
  check (btrim(capture_kind) <> ''),
  check (width_px is null or width_px > 0),
  check (height_px is null or height_px > 0),
  check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  check ((storage_bucket is null) = (storage_object_path is null)),
  check (capture_status in ('registered_remote','bytes_verified','derived','unavailable')),
  check (capture_status <> 'bytes_verified' or (sha256 is not null and width_px is not null and height_px is not null)),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create unique index captures_sha256_unique_when_known
  on mark.captures(sha256) where sha256 is not null;

create table mark.capture_surfaces (
  capture_id bigint not null references mark.captures(capture_id),
  surface_id bigint not null references mark.surfaces(surface_id),
  surface_role_in_capture text not null default 'depicted',
  bbox_x integer null,
  bbox_y integer null,
  bbox_width integer null,
  bbox_height integer null,
  polygon jsonb null,
  confidence numeric not null default 1.0,
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (capture_id, surface_id),
  check (confidence >= 0 and confidence <= 1),
  check (bbox_x is null or bbox_x >= 0),
  check (bbox_y is null or bbox_y >= 0),
  check (bbox_width is null or bbox_width > 0),
  check (bbox_height is null or bbox_height > 0),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.capture_equivalences (
  capture_equivalence_id bigint generated always as identity primary key,
  capture_a_id bigint not null references mark.captures(capture_id),
  capture_b_id bigint not null references mark.captures(capture_id),
  equivalence_kind text not null,
  method_key text not null,
  similarity_score numeric null,
  adjudication_status text not null default 'candidate',
  evidence_payload jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(capture_a_id, capture_b_id, equivalence_kind),
  check (capture_a_id < capture_b_id),
  check (equivalence_kind in ('exact_duplicate','viewer_duplicate','same_physical_capture','derivative','non_equivalent_control')),
  check (similarity_score is null or (similarity_score >= 0 and similarity_score <= 1)),
  check (adjudication_status in ('candidate','confirmed','rejected')),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.regions (
  region_id bigint generated always as identity primary key,
  region_key text not null unique,
  capture_id bigint not null,
  surface_id bigint not null,
  parent_region_id bigint null references mark.regions(region_id),
  region_kind text not null,
  bbox_x integer not null,
  bbox_y integer not null,
  bbox_width integer not null,
  bbox_height integer not null,
  polygon jsonb null,
  coordinate_space text not null default 'capture_pixels',
  geometry_payload jsonb not null default '{}'::jsonb,
  observation_status text not null default 'observed_visible',
  segmentation_origin text not null default 'human',
  created_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (capture_id, surface_id) references mark.capture_surfaces(capture_id, surface_id),
  check (btrim(region_key) <> ''),
  check (btrim(region_kind) <> ''),
  check (parent_region_id is null or parent_region_id <> region_id),
  check (bbox_x >= 0 and bbox_y >= 0 and bbox_width > 0 and bbox_height > 0),
  check (coordinate_space in ('capture_pixels','normalized_surface','other_declared')),
  check (observation_status in ('observed_visible','observed_damaged','observed_uncertain','occluded','not_visible')),
  check (segmentation_origin in ('human','vision_proposal','deterministic_geometry','imported_annotation')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.instances (
  instance_id bigint generated always as identity primary key,
  instance_key text not null unique,
  region_id bigint not null references mark.regions(region_id),
  instance_kind text not null default 'candidate_physical_unit',
  observation_status text not null default 'observed_visible',
  segmentation_origin text not null default 'human',
  created_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  physical_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(instance_key) <> ''),
  check (btrim(instance_kind) <> ''),
  check (observation_status in ('observed_visible','observed_damaged','observed_uncertain','occluded','not_visible')),
  check (segmentation_origin in ('human','vision_proposal','deterministic_geometry','imported_annotation')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.components (
  component_id bigint generated always as identity primary key,
  component_key text not null unique,
  instance_id bigint not null references mark.instances(instance_id),
  region_id bigint not null references mark.regions(region_id),
  channel_key text not null references mark.channel_registry(channel_key),
  component_order integer null,
  observation_status text not null default 'observed_visible',
  confidence numeric not null default 1.0,
  physical_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(component_key) <> ''),
  check (component_order is null or component_order >= 0),
  check (observation_status in ('observed_visible','observed_damaged','observed_uncertain','occluded','not_visible')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.component_relations (
  component_relation_id bigint generated always as identity primary key,
  relation_instance_key text not null unique,
  subject_component_id bigint not null references mark.components(component_id),
  object_component_id bigint not null references mark.components(component_id),
  relation_key text not null references mark.relation_registry(relation_key),
  evidence_region_id bigint null references mark.regions(region_id),
  distance_px numeric null,
  angle_degrees numeric null,
  relation_payload jsonb not null default '{}'::jsonb,
  observation_status text not null default 'observed_visible',
  derived_by_run_id bigint null references instrument.runs(instrument_run_id),
  confidence numeric not null default 1.0,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(relation_instance_key) <> ''),
  check (subject_component_id <> object_component_id),
  check (distance_px is null or distance_px >= 0),
  check (angle_degrees is null or (angle_degrees >= -360 and angle_degrees <= 360)),
  check (observation_status in ('observed_visible','observed_damaged','observed_uncertain')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.sequence_zones (
  sequence_zone_id bigint generated always as identity primary key,
  zone_key text not null unique,
  region_id bigint not null references mark.regions(region_id),
  zone_kind text not null,
  flow_direction text not null default 'undetermined',
  physical_order numeric null,
  confidence numeric not null default 1.0,
  zone_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(zone_key) <> ''),
  check (btrim(zone_kind) <> ''),
  check (flow_direction in ('left_to_right','right_to_left','top_to_bottom','bottom_to_top','radial','network','undetermined')),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.sequence_members (
  sequence_zone_id bigint not null references mark.sequence_zones(sequence_zone_id),
  instance_id bigint not null references mark.instances(instance_id),
  ordinal_position integer not null,
  membership_role text not null default 'member',
  confidence numeric not null default 1.0,
  membership_metadata jsonb not null default '{}'::jsonb,
  record_status text not null default 'draft',
  frozen_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (sequence_zone_id, instance_id),
  unique (sequence_zone_id, ordinal_position),
  check (ordinal_position >= 0),
  check (confidence >= 0 and confidence <= 1),
  check (record_status in ('draft','reviewed','frozen')),
  check ((record_status='frozen') = (frozen_at is not null))
);

create table mark.record_supersessions (
  supersession_id bigint generated always as identity primary key,
  object_type text not null,
  old_object_key text not null,
  new_object_key text not null,
  reason text not null,
  evidence_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(object_type, old_object_key, new_object_key),
  check (old_object_key <> new_object_key),
  check (object_type in ('source_object','surface','capture','capture_surface','capture_equivalence','region','instance','component','component_relation','sequence_zone','sequence_member'))
);

comment on table mark.record_supersessions is
  'Append-only correction lineage. Frozen physical records are never overwritten; corrected observations receive new keys and explicit supersession lineage.';

create or replace function mark.guard_frozen_row_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
begin
  if old.record_status = 'frozen' then
    raise exception 'MARK_FROZEN_RECORD_IMMUTABLE: %.% cannot be % after freeze', tg_table_schema, tg_table_name, lower(tg_op);
  end if;

  if tg_op = 'UPDATE' and new.record_status = 'frozen' and new.frozen_at is null then
    new.frozen_at := now();
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end
$$;

create or replace function mark.touch_updated_at_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, mark
as $$
begin
  new.updated_at := now();
  return new;
end
$$;

do $$
declare
  rel text;
begin
  foreach rel in array array[
    'source_objects','surfaces','captures','capture_surfaces','capture_equivalences',
    'regions','instances','components','component_relations','sequence_zones','sequence_members'
  ] loop
    execute format('create trigger %I before update or delete on mark.%I for each row execute function mark.guard_frozen_row_v1()', 'guard_frozen_' || rel || '_v1', rel);
    execute format('create trigger %I before update on mark.%I for each row execute function mark.touch_updated_at_v1()', 'touch_updated_' || rel || '_v1', rel);
  end loop;
end
$$;

create index surfaces_source_object_idx on mark.surfaces(source_object_id);
create index capture_surfaces_surface_idx on mark.capture_surfaces(surface_id);
create index capture_equivalences_a_idx on mark.capture_equivalences(capture_a_id);
create index capture_equivalences_b_idx on mark.capture_equivalences(capture_b_id);
create index regions_capture_surface_idx on mark.regions(capture_id, surface_id);
create index regions_parent_idx on mark.regions(parent_region_id);
create index instances_region_idx on mark.instances(region_id);
create index components_instance_idx on mark.components(instance_id);
create index components_region_idx on mark.components(region_id);
create index components_channel_idx on mark.components(channel_key);
create index component_relations_subject_idx on mark.component_relations(subject_component_id);
create index component_relations_object_idx on mark.component_relations(object_component_id);
create index component_relations_relation_idx on mark.component_relations(relation_key);
create index sequence_zones_region_idx on mark.sequence_zones(region_id);
create index sequence_members_instance_idx on mark.sequence_members(instance_id);

alter table mark.channel_registry enable row level security;
alter table mark.relation_registry enable row level security;
alter table mark.source_objects enable row level security;
alter table mark.surfaces enable row level security;
alter table mark.captures enable row level security;
alter table mark.capture_surfaces enable row level security;
alter table mark.capture_equivalences enable row level security;
alter table mark.regions enable row level security;
alter table mark.instances enable row level security;
alter table mark.components enable row level security;
alter table mark.component_relations enable row level security;
alter table mark.sequence_zones enable row level security;
alter table mark.sequence_members enable row level security;
alter table mark.record_supersessions enable row level security;

comment on table mark.source_objects is 'Culture-agnostic physical object registry: manuscripts, leaves, tablets, bones, seals, textiles, tallies, and future durable sign-bearing objects.';
comment on table mark.surfaces is 'Physical sign-bearing surfaces belonging to source objects; a surface is not a linguistic text unit.';
comment on table mark.captures is 'Immutable image/capture custody. One capture may depict multiple physical surfaces; byte hashes and derivative lineage are first-class.';
comment on table mark.capture_surfaces is 'Many-to-many mapping between captures and physical surfaces, including the surface bounding region inside multi-surface images.';
comment on table mark.capture_equivalences is 'Duplicate/derivative adjudication used to prevent the same physical pixels from masquerading as independent recurrence evidence.';
comment on table mark.regions is 'Geometry-bearing physical regions in captured pixels. Regions may be rows, zones, components, damage areas, or candidate structures without semantic naming.';
comment on table mark.instances is 'Candidate physical mark units. Unit boundaries are provisional and may be proposed by recurrence; this table does not assert conventional character identity.';
comment on table mark.components is 'Observable components within candidate mark instances, assigned only to physical channels.';
comment on table mark.component_relations is 'First-class junction/topology observations between physical components.';
comment on table mark.sequence_zones is 'Physical ordering zones such as rows, columns, margins, bands, or undetermined flows; does not encode linguistic word/verse segmentation.';
comment on table mark.sequence_members is 'Anonymous physical order of candidate mark instances inside a sequence zone.';

do $$
declare
  role_name text;
begin
  foreach role_name in array array['anon','authenticated','service_role'] loop
    if has_schema_privilege(role_name, 'mark', 'USAGE') or has_schema_privilege(role_name, 'mark', 'CREATE') then
      raise exception 'MARK_MEMBRANE_VIOLATION: role % has direct privilege on mark schema', role_name;
    end if;
  end loop;
end
$$;

commit;
