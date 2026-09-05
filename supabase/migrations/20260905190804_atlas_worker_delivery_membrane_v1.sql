begin;

alter table atlas.worker_week_projection
  add column if not exists organization_id uuid references atlas.organizations(id) on delete restrict,
  add column if not exists organization_membership_id uuid references atlas.organization_memberships(id) on delete restrict,
  add column if not exists original_planned_date date,
  add column if not exists rollover_policy text not null default 'carry',
  add column if not exists delivery_key text,
  add column if not exists delivery_payload jsonb not null default '{}'::jsonb;

update atlas.worker_week_projection
set original_planned_date = planned_date
where original_planned_date is null;

alter table atlas.worker_week_projection
  drop constraint if exists worker_week_projection_rollover_policy_check;

alter table atlas.worker_week_projection
  add constraint worker_week_projection_rollover_policy_check
  check (rollover_policy = any (array['carry'::text, 'expire'::text, 're_evaluate'::text]));

alter table atlas.worker_week_projection
  drop constraint if exists worker_week_projection_source_kind_check;

alter table atlas.worker_week_projection
  add constraint worker_week_projection_source_kind_check
  check (source_kind = any (array[
    'task'::text,
    'floating_task'::text,
    'project_pull'::text,
    'queue'::text,
    'rhythm'::text,
    'work_item'::text
  ]));

create unique index if not exists worker_week_projection_delivery_key_uq
  on atlas.worker_week_projection (farm_id, membership_id, delivery_key)
  where delivery_key is not null;

create index if not exists worker_week_projection_delivery_read_idx
  on atlas.worker_week_projection (farm_id, membership_id, planned_date, rollover_policy, plan_order);

create table if not exists atlas.worker_week_projection_sources (
  projection_id uuid not null references atlas.worker_week_projection(id) on delete cascade,
  work_item_id uuid not null references atlas.work_items(id) on delete restrict,
  source_role text not null default 'required',
  created_at timestamptz not null default now(),
  primary key (projection_id, work_item_id),
  constraint worker_week_projection_sources_role_check
    check (source_role = any (array['required'::text, 'context'::text, 'evidence'::text]))
);

create index if not exists worker_week_projection_sources_work_item_idx
  on atlas.worker_week_projection_sources (work_item_id, projection_id);

alter table atlas.worker_week_projection_sources enable row level security;

comment on table atlas.worker_week_projection is
  'Canonical Worker scheduling projection. The institution owns source work; this table only governs worker delivery placement. planned_date is the manager-selected day. original_planned_date preserves first placement. carry/expire/re_evaluate governs unfinished work crossing a day boundary.';

comment on column atlas.worker_week_projection.delivery_key is
  'Stable identity for one worker-facing delivery instruction. It is not work ownership.';

comment on column atlas.worker_week_projection.delivery_payload is
  'Delivery-only phrasing/details and source-effect context. Must not become responsibility authority.';

comment on table atlas.worker_week_projection_sources is
  'Relationship from one quiet worker-facing delivery instruction to one or more institution-owned work_items. One delivery line may carry several responsibilities without copying them.';

commit;
