create table if not exists atlas.route_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  stable_key text not null,
  route_label text not null,
  route_kind text not null,
  state text not null default 'active',
  default_custodian_organization_membership_id uuid null references atlas.organization_memberships(id) on delete set null,
  external_custodian_label text null,
  territory_label text null,
  start_label text null,
  end_label text null,
  source_authority text not null default 'atlas',
  source_system_key text null,
  source_record_key text null,
  source_observed_at timestamptz null,
  metadata jsonb not null default '{}'::jsonb,
  created_by_user_id uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint route_templates_stable_key_unique unique (organization_id, stable_key),
  constraint route_templates_kind_check check (route_kind = any (array['delivery'::text,'pickup'::text,'service'::text,'mixed'::text,'handoff'::text])),
  constraint route_templates_state_check check (state = any (array['active'::text,'inactive'::text,'archived'::text])),
  constraint route_templates_assignment_check check (((default_custodian_organization_membership_id is not null)::integer + (nullif(btrim(external_custodian_label),'') is not null)::integer) <= 1),
  constraint route_templates_source_authority_check check (source_authority = any (array['atlas'::text,'external'::text])),
  constraint route_templates_external_source_check check ((source_authority <> 'external'::text) or (nullif(btrim(source_system_key),'') is not null and nullif(btrim(source_record_key),'') is not null))
);

create index if not exists route_templates_org_state_idx
  on atlas.route_templates (organization_id, state, route_label);

create table if not exists atlas.route_template_stops (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  route_template_id uuid not null references atlas.route_templates(id) on delete cascade,
  stable_key text not null,
  sequence_number integer not null,
  stop_kind text not null,
  destination_label text not null,
  address_text text null,
  contact_name text null,
  contact_detail text null,
  worker_instruction text null,
  buyer_relationship_id uuid null references atlas.buyer_relationship_reconstruction(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint route_template_stops_route_key_unique unique (route_template_id, stable_key),
  constraint route_template_stops_route_sequence_unique unique (route_template_id, sequence_number),
  constraint route_template_stops_sequence_positive check (sequence_number > 0),
  constraint route_template_stops_kind_check check (stop_kind = any (array['product_delivery'::text,'product_pickup'::text,'service_visit'::text,'handoff'::text,'mixed'::text]))
);

create index if not exists route_template_stops_template_sequence_idx
  on atlas.route_template_stops (route_template_id, sequence_number);

create index if not exists route_template_stops_buyer_relationship_idx
  on atlas.route_template_stops (buyer_relationship_id)
  where buyer_relationship_id is not null;

create table if not exists atlas.route_template_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references atlas.organizations(id) on delete cascade,
  route_template_id uuid not null references atlas.route_templates(id) on delete restrict,
  operational_route_id uuid not null references atlas.operational_routes(id) on delete cascade,
  materialized_at timestamptz not null default now(),
  materialized_by_user_id uuid null default auth.uid() references auth.users(id) on delete set null,
  metadata jsonb not null default '{}'::jsonb,
  constraint route_template_runs_operational_route_unique unique (operational_route_id)
);

create index if not exists route_template_runs_template_idx
  on atlas.route_template_runs (route_template_id, materialized_at desc);

comment on table atlas.route_templates is 'Reusable route definitions. These are not dated executions; materialize into atlas.operational_routes when actually run.';
comment on table atlas.route_template_stops is 'Ordered reusable stops for a route template. Relationship context stays linked to underlying Atlas records rather than copied as authority.';
comment on table atlas.route_template_runs is 'Links a reusable route template to a dated operational route created from it.';
