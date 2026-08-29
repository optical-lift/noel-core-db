create table if not exists atlas.reference_company_scenarios (
  id uuid primary key default gen_random_uuid(),
  stable_key text not null unique,
  domain text not null,
  title text not null,
  purpose text not null,
  run_mode text not null default 'transactional' check (run_mode in ('transactional','committed_probe')),
  fixture_version integer not null default 1 check (fixture_version > 0),
  preconditions jsonb not null default '{}'::jsonb,
  expected_invariants jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists atlas.reference_company_runs (
  id uuid primary key default gen_random_uuid(),
  scenario_id uuid not null references atlas.reference_company_scenarios(id) on delete cascade,
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  run_token text not null unique,
  run_mode text not null check (run_mode in ('transactional','committed_probe')),
  status text not null default 'running' check (status in ('running','passed','failed','aborted')),
  source_revision text,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  result jsonb not null default '{}'::jsonb,
  error_text text,
  metadata jsonb not null default '{}'::jsonb
);

create table if not exists atlas.reference_company_assertions (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references atlas.reference_company_runs(id) on delete cascade,
  assertion_key text not null,
  passed boolean not null,
  expected jsonb not null default '{}'::jsonb,
  actual jsonb not null default '{}'::jsonb,
  detail text,
  created_at timestamptz not null default now(),
  unique(run_id,assertion_key)
);

create table if not exists atlas.reference_company_fixture_registry (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references atlas.farms(id) on delete cascade,
  fixture_key text not null,
  entity_kind text not null,
  entity_id uuid,
  entity_stable_key text,
  role text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(farm_id,fixture_key)
);

create index if not exists reference_company_runs_scenario_started_idx on atlas.reference_company_runs(scenario_id,started_at desc);
create index if not exists reference_company_assertions_run_passed_idx on atlas.reference_company_assertions(run_id,passed);
create index if not exists reference_company_fixture_registry_entity_idx on atlas.reference_company_fixture_registry(farm_id,entity_kind,entity_stable_key);

alter table atlas.reference_company_scenarios enable row level security;
alter table atlas.reference_company_runs enable row level security;
alter table atlas.reference_company_assertions enable row level security;
alter table atlas.reference_company_fixture_registry enable row level security;

revoke all on atlas.reference_company_scenarios from public, anon, authenticated;
revoke all on atlas.reference_company_runs from public, anon, authenticated;
revoke all on atlas.reference_company_assertions from public, anon, authenticated;
revoke all on atlas.reference_company_fixture_registry from public, anon, authenticated;
grant select,insert,update,delete on atlas.reference_company_scenarios to service_role;
grant select,insert,update,delete on atlas.reference_company_runs to service_role;
grant select,insert,update,delete on atlas.reference_company_assertions to service_role;
grant select,insert,update,delete on atlas.reference_company_fixture_registry to service_role;

create or replace function atlas.is_system_fixture_farm_v1(p_farm_id uuid)
returns boolean
language sql
stable
security definer
set search_path='pg_catalog','atlas'
as $function$
  select coalesce((f.metadata->>'system_fixture')::boolean,false)
  from atlas.farms f
  where f.id=p_farm_id;
$function$;
revoke all on function atlas.is_system_fixture_farm_v1(uuid) from public,anon,authenticated;
grant execute on function atlas.is_system_fixture_farm_v1(uuid) to service_role;

create or replace function atlas.guard_reference_company_membership_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
begin
  if atlas.is_system_fixture_farm_v1(new.farm_id)
     and coalesce((new.permissions->>'reference_fixture_membership')::boolean,false) is not true then
    raise exception 'System fixture farms reject ordinary human memberships.' using errcode='23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists guard_reference_company_membership_v1 on atlas.farm_memberships;
create trigger guard_reference_company_membership_v1
before insert or update of farm_id,permissions on atlas.farm_memberships
for each row execute function atlas.guard_reference_company_membership_v1();

create or replace function atlas.suppress_system_fixture_notification_plan_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
begin
  if atlas.is_system_fixture_farm_v1(new.farm_id) then
    new.active:=false;
    new.metadata:=coalesce(new.metadata,'{}'::jsonb)||jsonb_build_object(
      'suppressed_by','system_fixture_isolation_v1',
      'suppressed_at',now()
    );
  end if;
  return new;
end;
$function$;

drop trigger if exists suppress_system_fixture_notification_plan_v1 on atlas.task_notification_plans;
create trigger suppress_system_fixture_notification_plan_v1
before insert or update of farm_id,active on atlas.task_notification_plans
for each row execute function atlas.suppress_system_fixture_notification_plan_v1();

insert into atlas.organizations(stable_key,name,status,metadata)
values(
  'atlas_reference_company',
  'Atlas Reference Company',
  'active',
  jsonb_build_object(
    'system_fixture',true,
    'customer_visible',false,
    'analytics_excluded',true,
    'purpose','Executable reference specification for Atlas tenant behavior',
    'fixture_version',1
  )
)
on conflict(stable_key) do update set
  name=excluded.name,
  status='active',
  metadata=atlas.organizations.metadata||excluded.metadata,
  updated_at=now();

insert into atlas.farms(stable_key,name,status,organization_id,notes,north_star_text,metadata)
select
  'atlas_reference_farm',
  'Atlas Reference Farm',
  'active',
  o.id,
  'SYSTEM FIXTURE — synthetic operating world used for Atlas conformance testing. Not a customer farm.',
  'Given known operating truth, Atlas derives exactly the lawful next obligations and never loses or invents work.',
  jsonb_build_object(
    'system_fixture',true,
    'reference_company',true,
    'customer_visible',false,
    'analytics_excluded',true,
    'notifications_suppressed',true,
    'allow_real_world_side_effects',false,
    'fixture_version',1,
    'timezone','America/Chicago'
  )
from atlas.organizations o
where o.stable_key='atlas_reference_company'
on conflict(stable_key) do update set
  name=excluded.name,
  status='active',
  organization_id=excluded.organization_id,
  notes=excluded.notes,
  north_star_text=excluded.north_star_text,
  metadata=atlas.farms.metadata||excluded.metadata,
  updated_at=now();

insert into atlas.farm_task_release_settings(farm_id,active,metadata)
select f.id,true,jsonb_build_object('system_fixture',true,'notifications_suppressed',true,'reference_company_version',1)
from atlas.farms f where f.stable_key='atlas_reference_farm'
on conflict(farm_id) do update set
  active=true,
  metadata=atlas.farm_task_release_settings.metadata||excluded.metadata,
  updated_at=now();

insert into atlas.zones(farm_id,stable_key,label,zone_type,goal_text,current_state,visible_to_guests,sort_order,metadata)
select f.id,x.stable_key,x.label,'growing_zone',x.goal_text,'active',false,x.sort_order,
       jsonb_build_object('system_fixture',true,'reference_company_version',1,'synthetic_truth',true)
from atlas.farms f
cross join (values
  ('reference_propagation_room','Reference Propagation Room','Exercise propagation and transplant-start lifecycle behavior.',10),
  ('reference_production_field','Reference Production Field','Exercise bed assignment, transplant, field care, harvest, and turnover behavior.',20),
  ('reference_service_yard','Reference Service Yard','Exercise maintenance, inventory, delivery, and service workflows.',30),
  ('reference_venue','Reference Venue','Exercise event, setup, guest-readiness, and reset workflows.',40)
) as x(stable_key,label,goal_text,sort_order)
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,stable_key) do update set
  label=excluded.label,goal_text=excluded.goal_text,current_state='active',metadata=atlas.zones.metadata||excluded.metadata,updated_at=now();

insert into atlas.growing_objects(farm_id,zone_id,stable_key,label,object_type,object_mode,length_ft,width_ft,area_sqft,guest_visible,sort_order,metadata)
select f.id,z.id,x.stable_key,x.label,'bed','production',20,3,60,false,x.sort_order,
       jsonb_build_object('system_fixture',true,'synthetic_truth',true,'fixture_measurement','20 ft x 3 ft','reference_company_version',1)
from atlas.farms f
join atlas.zones z on z.farm_id=f.id and z.stable_key='reference_production_field'
cross join (values
  ('reference_bed_1','Reference Bed 1',10),
  ('reference_bed_2','Reference Bed 2',20),
  ('reference_bed_3','Reference Bed 3',30)
) as x(stable_key,label,sort_order)
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,stable_key) do update set
  zone_id=excluded.zone_id,label=excluded.label,object_type='bed',object_mode='production',length_ft=20,width_ft=3,area_sqft=60,metadata=atlas.growing_objects.metadata||excluded.metadata,updated_at=now();

insert into atlas.capacity_measurements(farm_id,stable_key,label,measurement_kind,value,unit,confidence,note,metadata)
select f.id,x.stable_key,x.label,x.measurement_kind,x.value,x.unit,'confirmed',
       'Synthetic reference-company measurement. This is test truth only and is not agronomic guidance for any customer.',
       jsonb_build_object('system_fixture',true,'synthetic_truth',true,'reference_company_version',1)
from atlas.farms f
cross join (values
  ('snapdragon_rows_per_three_foot_bed','Reference rows per 3-ft bed','rows_per_bed',4::numeric,'rows'),
  ('snapdragon_in_row_spacing_inches','Reference in-row spacing','spacing_inches',4::numeric,'inches')
) as x(stable_key,label,measurement_kind,value,unit)
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,stable_key) do update set
  label=excluded.label,measurement_kind=excluded.measurement_kind,value=excluded.value,unit=excluded.unit,confidence='confirmed',note=excluded.note,metadata=atlas.capacity_measurements.metadata||excluded.metadata,updated_at=now();

insert into atlas.crop_profiles(
  stable_key,crop_label,variety,crop_family,life_cycle,default_planting_method,
  days_to_germination_min,days_to_germination_max,rows_per_3ft_bed,in_row_spacing_in,
  revenue_model,metadata,harvest_pattern,productive_days_min,productive_days_max,clear_offset_days,frost_behavior,decline_signal
)
select
  'atlas_reference_snapdragon_golden_v1',
  'Reference Snapdragon',
  'Golden Path',
  cp.crop_family,
  cp.life_cycle,
  'grow_room_seed_start',
  7,14,4,4,
  'none',
  jsonb_build_object(
    'system_fixture',true,
    'synthetic_truth',true,
    'reference_company_version',1,
    'workflow_kind','transplant_start',
    'container_kind','3/4-inch soil blocks',
    'grow_out_container_kind','3/4-inch soil blocks',
    'container_persists_through_transplant',true,
    'pot_up_required',false,
    'pot_up_disposition','not_applicable',
    'hardening_duration_days_min',10,
    'hardening_duration_days_max',14,
    'transplant_readiness_cue','Synthetic fixture cohort is compact, rooted, hardened, and ready for field conditions.',
    'seedling_observation_interval_days',7,
    'fixture_density_contract',jsonb_build_object('seedlings',720,'rows_per_3ft_bed',4,'spacing_inches',4,'expected_bed_feet',60),
    'warning','Synthetic acceptance profile. Never use as customer agronomy.'
  ),
  cp.harvest_pattern,cp.productive_days_min,cp.productive_days_max,cp.clear_offset_days,cp.frost_behavior,cp.decline_signal
from atlas.crop_profiles cp
where cp.stable_key='snapdragon_rocket_overwinter_2026'
on conflict(stable_key) do update set
  crop_label=excluded.crop_label,variety=excluded.variety,crop_family=excluded.crop_family,life_cycle=excluded.life_cycle,
  default_planting_method=excluded.default_planting_method,days_to_germination_min=excluded.days_to_germination_min,
  days_to_germination_max=excluded.days_to_germination_max,rows_per_3ft_bed=excluded.rows_per_3ft_bed,
  in_row_spacing_in=excluded.in_row_spacing_in,revenue_model='none',metadata=atlas.crop_profiles.metadata||excluded.metadata,updated_at=now();

insert into atlas.crop_lifecycle_stage_rules(
  crop_profile_id,stage_key,disposition,timing_min_days,timing_max_days,trigger_spec,rule_payload,confidence,source,note,active
)
select dst.id,r.stage_key,r.disposition,r.timing_min_days,r.timing_max_days,r.trigger_spec,r.rule_payload,
       'explicit','atlas_reference_company_foundation_v1',
       'Frozen synthetic lifecycle rule copied from the governed overwinter snapdragon contract for conformance testing only.',true
from atlas.crop_profiles src
join atlas.crop_lifecycle_stage_rules r on r.crop_profile_id=src.id and r.active
join atlas.crop_profiles dst on dst.stable_key='atlas_reference_snapdragon_golden_v1'
where src.stable_key='snapdragon_rocket_overwinter_2026'
on conflict(crop_profile_id,stage_key) do update set
  disposition=excluded.disposition,timing_min_days=excluded.timing_min_days,timing_max_days=excluded.timing_max_days,
  trigger_spec=excluded.trigger_spec,rule_payload=excluded.rule_payload,confidence='explicit',source=excluded.source,note=excluded.note,active=true,updated_at=now();

insert into atlas.reference_company_scenarios(stable_key,domain,title,purpose,run_mode,fixture_version,preconditions,expected_invariants,metadata)
values
('propagation_golden_path_v1','production','Propagation golden path','Prove a transplant-start cohort advances from propagation through field establishment without invented stages or lost obligations.','transactional',1,
 jsonb_build_object('fixtureProfile','atlas_reference_snapdragon_golden_v1','seedlings',720,'container','3/4-inch soil blocks','beds',jsonb_build_array('reference_bed_1','reference_bed_2','reference_bed_3')),
 jsonb_build_array('hardening derives from state','no pot-up is created','readiness persists even when downstream gates block','60 bed-ft are required from synthetic density truth','three bed-preparation obligations derive from three assignments','transplant appears only after preparation','establishment derives after transplant','reconciliation is idempotent'),
 jsonb_build_object('system_fixture',true,'implementation_state','foundation_ready')),
('direct_sow_golden_path_v1','production','Direct-sow golden path','Prove a direct-sown crop skips transplant machinery and advances through germination, care, harvest, and turnover.','transactional',1,'{}'::jsonb,
 jsonb_build_array('no transplant stage','germination observation derives lawful care','harvest derives only from physical readiness','turnover follows terminal disposition'),
 jsonb_build_object('system_fixture',true,'implementation_state','cataloged')),
('propagation_failure_recovery_v1','production','Propagation failure and recovery','Prove biological failure creates a governed recovery decision without fabricating surviving inventory.','transactional',1,'{}'::jsonb,
 jsonb_build_array('zero survivors are preserved as zero','failed cohort cannot advance','exactly one recovery decision exists','reconciliation creates no duplicates'),
 jsonb_build_object('system_fixture',true,'implementation_state','cataloged')),
('transplant_dependency_block_v1','production','Blocked transplant dependency','Prove transplant-ready biology remains true while missing bed math, assignment, or preparation blocks only execution downstream.','transactional',1,'{}'::jsonb,
 jsonb_build_array('biology is not rolled back','unknown bed math hard-blocks transplant','partial assignment remains visible','unprepared assigned beds prevent transplant','resolved dependencies self-heal'),
 jsonb_build_object('system_fixture',true,'implementation_state','cataloged')),
('completed_history_immutability_v1','platform','Completed history immutability','Prove later reconciliation never rewrites completed historical work when plans or profiles change.','transactional',1,'{}'::jsonb,
 jsonb_build_array('completed work remains completed','historical result payload is unchanged','only future obligations are recomputed'),
 jsonb_build_object('system_fixture',true,'implementation_state','cataloged')),
('reconciler_idempotency_v1','platform','Reconciler idempotency','Prove repeated reconciliation over identical truth produces exactly the same active obligation set.','transactional',1,'{}'::jsonb,
 jsonb_build_array('no duplicate occurrences','no duplicate tasks','stable occurrence keys','stable downstream gates'),
 jsonb_build_object('system_fixture',true,'implementation_state','cataloged'))
on conflict(stable_key) do update set
  domain=excluded.domain,title=excluded.title,purpose=excluded.purpose,run_mode=excluded.run_mode,fixture_version=excluded.fixture_version,
  preconditions=excluded.preconditions,expected_invariants=excluded.expected_invariants,active=true,
  metadata=atlas.reference_company_scenarios.metadata||excluded.metadata,updated_at=now();

insert into atlas.reference_company_fixture_registry(farm_id,fixture_key,entity_kind,entity_id,entity_stable_key,role,metadata)
select f.id,'reference_farm','farm',f.id,f.stable_key,'tenant_root',jsonb_build_object('system_fixture',true)
from atlas.farms f where f.stable_key='atlas_reference_farm'
on conflict(farm_id,fixture_key) do update set entity_id=excluded.entity_id,entity_stable_key=excluded.entity_stable_key,role=excluded.role,metadata=atlas.reference_company_fixture_registry.metadata||excluded.metadata,updated_at=now();

insert into atlas.reference_company_fixture_registry(farm_id,fixture_key,entity_kind,entity_id,entity_stable_key,role,metadata)
select f.id,'bed:'||go.stable_key,'growing_object',go.id,go.stable_key,'production_destination',jsonb_build_object('system_fixture',true,'length_ft',go.length_ft)
from atlas.farms f join atlas.growing_objects go on go.farm_id=f.id and go.stable_key in ('reference_bed_1','reference_bed_2','reference_bed_3')
where f.stable_key='atlas_reference_farm'
on conflict(farm_id,fixture_key) do update set entity_id=excluded.entity_id,entity_stable_key=excluded.entity_stable_key,role=excluded.role,metadata=atlas.reference_company_fixture_registry.metadata||excluded.metadata,updated_at=now();

create or replace function atlas.reference_company_health_v1()
returns jsonb
language sql
stable
security definer
set search_path='pg_catalog','atlas'
as $function$
with rf as (
  select f.* from atlas.farms f where f.stable_key='atlas_reference_farm'
), counts as (
  select
    (select count(*) from atlas.farm_memberships fm join rf on rf.id=fm.farm_id) as memberships,
    (select count(*) from atlas.reference_company_scenarios where active) as active_scenarios,
    (select count(*) from atlas.reference_company_fixture_registry r join rf on rf.id=r.farm_id) as fixture_objects,
    (select count(*) from atlas.task_notification_plans np join rf on rf.id=np.farm_id where np.active) as active_notification_plans,
    (select count(*) from atlas.reference_company_runs r join rf on rf.id=r.farm_id where r.status='failed' and r.started_at>=now()-interval '30 days') as failed_runs_30d
) 
select jsonb_build_object(
  'contractVersion','reference_company_health_v1',
  'farmId',rf.id,
  'farmStableKey',rf.stable_key,
  'systemFixture',coalesce((rf.metadata->>'system_fixture')::boolean,false),
  'customerVisible',coalesce((rf.metadata->>'customer_visible')::boolean,true),
  'humanMembershipCount',counts.memberships,
  'activeScenarioCount',counts.active_scenarios,
  'fixtureRegistryCount',counts.fixture_objects,
  'activeNotificationPlanCount',counts.active_notification_plans,
  'failedRuns30d',counts.failed_runs_30d,
  'isolationHealthy',coalesce((rf.metadata->>'system_fixture')::boolean,false)
      and not coalesce((rf.metadata->>'customer_visible')::boolean,true)
      and counts.memberships=0
      and counts.active_notification_plans=0
)
from rf cross join counts;
$function$;
revoke all on function atlas.reference_company_health_v1() from public,anon,authenticated;
grant execute on function atlas.reference_company_health_v1() to service_role;

comment on table atlas.reference_company_scenarios is 'Executable scenario specification for the synthetic Atlas Reference Company. Scenario truth is intentionally artificial and must never be treated as customer agronomy or business data.';
comment on function atlas.reference_company_health_v1() is 'Reports tenant-isolation and conformance-harness health for the Atlas Reference Company.';