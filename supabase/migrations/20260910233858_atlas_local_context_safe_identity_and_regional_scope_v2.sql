-- Atlas Local Model B: make core identity/dedupe and regional execution context-safe.

alter table local_intel.market_origins
  add column if not exists local_context_id uuid;

update local_intel.market_origins mo
set local_context_id = coalesce(
  (select e.local_context_id from local_intel.entities e where e.id = mo.entity_id),
  (select min(lc.id::text)::uuid from local_intel.local_contexts lc where lc.status='active')
)
where local_context_id is null;

alter table local_intel.market_origins
  alter column local_context_id set not null;

alter table local_intel.market_origins
  drop constraint if exists market_origins_local_context_fk;
alter table local_intel.market_origins
  add constraint market_origins_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

create index if not exists market_origins_local_context_idx
  on local_intel.market_origins(local_context_id, status);

alter table local_intel.regional_ingestion_targets
  add column if not exists local_context_id uuid;

update local_intel.regional_ingestion_targets rit
set local_context_id = (
  select lc.id from local_intel.local_contexts lc where lc.stable_key='elm_local'
)
where local_context_id is null;

alter table local_intel.regional_ingestion_targets
  alter column local_context_id set not null;

alter table local_intel.regional_ingestion_targets
  drop constraint if exists regional_ingestion_targets_local_context_fk;
alter table local_intel.regional_ingestion_targets
  add constraint regional_ingestion_targets_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

alter table local_intel.regional_ingestion_targets
  drop constraint if exists regional_ingestion_targets_geographic_area_id_key;
alter table local_intel.regional_ingestion_targets
  add constraint regional_ingestion_targets_local_context_geography_key
  unique (local_context_id, geographic_area_id);

create index if not exists regional_ingestion_targets_context_queue_idx
  on local_intel.regional_ingestion_targets(local_context_id, status, wave, priority desc);

alter table local_intel.entities
  drop constraint if exists entities_stable_key_key;
alter table local_intel.entities
  add constraint entities_local_context_stable_key_key
  unique (local_context_id, stable_key);

alter table local_intel.entity_ingestion_candidates
  drop constraint if exists entity_ingestion_candidates_ingestion_source_id_source_reco_key;
alter table local_intel.entity_ingestion_candidates
  add constraint entity_ingestion_candidates_context_source_record_key
  unique (local_context_id, ingestion_source_id, source_record_key);

drop index if exists local_intel.research_attempts_attempt_key_uidx;
create unique index if not exists research_attempts_context_attempt_key_uidx
  on local_intel.research_attempts(local_context_id, attempt_key)
  where local_context_id is not null and attempt_key is not null;
create unique index if not exists research_attempts_legacy_attempt_key_uidx
  on local_intel.research_attempts(attempt_key)
  where local_context_id is null and attempt_key is not null;

create or replace function local_intel.enforce_ingestion_candidate_local_context_v1()
returns trigger
language plpgsql
set search_path to 'local_intel','pg_catalog'
as $$
begin
  if new.matched_entity_id is not null and not exists (
    select 1 from local_intel.entities e
    where e.id=new.matched_entity_id and e.local_context_id=new.local_context_id
  ) then
    raise exception 'matched_entity_id must belong to candidate local_context_id';
  end if;
  if new.resolver_recommended_entity_id is not null and not exists (
    select 1 from local_intel.entities e
    where e.id=new.resolver_recommended_entity_id and e.local_context_id=new.local_context_id
  ) then
    raise exception 'resolver_recommended_entity_id must belong to candidate local_context_id';
  end if;
  return new;
end;
$$;

drop trigger if exists entity_ingestion_candidate_local_context_guard_v1 on local_intel.entity_ingestion_candidates;
create trigger entity_ingestion_candidate_local_context_guard_v1
before insert or update of local_context_id, matched_entity_id, resolver_recommended_entity_id
on local_intel.entity_ingestion_candidates
for each row execute function local_intel.enforce_ingestion_candidate_local_context_v1();

create or replace view local_intel.v_regional_ingestion_queue_v1 as
select
  rit.id as ingestion_target_id,
  rit.wave,
  rit.priority,
  rit.status,
  rit.target_scope,
  ga.id as geographic_area_id,
  ga.name as locality,
  ga.state,
  ga.primary_postal_code,
  ga.centroid_latitude,
  ga.centroid_longitude,
  ga.centroid_precision,
  rit.organization_goal,
  rit.person_goal,
  rit.contactable_person_goal,
  rit.rationale,
  count(distinct e.id) filter (
    where e.status='active' and e.entity_type <> 'person'
  ) as current_organizations,
  count(distinct er.subject_entity_id) filter (
    where p.status='active'
  ) as current_people_via_relationship,
  count(distinct cp.entity_id) filter (
    where cp.contact_type='email'
      and cp.visibility='public'
      and cp.marketing_status <> all(array['suppressed'::text,'unsubscribed'::text])
  ) as current_public_email_entities,
  rit.local_context_id
from local_intel.regional_ingestion_targets rit
join local_intel.geographic_areas ga on ga.id=rit.geographic_area_id
left join local_intel.entity_geographic_areas ega on ega.geographic_area_id=ga.id
left join local_intel.entities e on e.id=ega.entity_id and e.local_context_id=rit.local_context_id
left join local_intel.entity_relationships er on er.object_entity_id=e.id and er.is_current
left join local_intel.entities pe on pe.id=er.subject_entity_id and pe.local_context_id=rit.local_context_id
left join local_intel.people p on p.entity_id=pe.id
left join local_intel.contact_points cp on cp.entity_id=pe.id
group by rit.id, ga.id;
