alter table local_intel.entities
  alter column local_context_id set not null,
  add constraint entities_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

alter table local_intel.search_queries
  alter column local_context_id set not null,
  add constraint search_queries_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

alter table local_intel.entity_ingestion_candidates
  alter column local_context_id set not null,
  add constraint entity_ingestion_candidates_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

alter table local_intel.research_attempts
  add constraint research_attempts_local_context_fk
  foreign key (local_context_id) references local_intel.local_contexts(id) on delete restrict;

create or replace function local_intel.stamp_research_attempt_local_context()
returns trigger
language plpgsql
set search_path = pg_catalog, public, atlas, local_intel
as $$
declare
  v_entity_context uuid;
begin
  if new.entity_id is not null then
    select e.local_context_id into v_entity_context
    from local_intel.entities e
    where e.id = new.entity_id;

    if v_entity_context is null then
      raise exception 'research_attempt entity_id % has no resolvable Local Context', new.entity_id;
    end if;

    if new.local_context_id is null then
      new.local_context_id := v_entity_context;
    elsif new.local_context_id <> v_entity_context then
      raise exception 'research_attempt local_context_id does not match entity Local Context';
    end if;
  elsif new.local_context_id is null then
    raise exception 'new entity-null research_attempt requires local_context_id';
  end if;

  return new;
end;
$$;

create trigger research_attempt_local_context_stamp
before insert on local_intel.research_attempts
for each row execute function local_intel.stamp_research_attempt_local_context();

create or replace view local_intel.v_research_attempts_scoped_v1 as
select
  ra.*,
  coalesce(ra.local_context_id, e.local_context_id) as effective_local_context_id
from local_intel.research_attempts ra
left join local_intel.entities e on e.id = ra.entity_id;

comment on view local_intel.v_research_attempts_scoped_v1 is 'Context-aware projection preserving append-only historical research_attempt rows. New attempts carry local_context_id; historical attempts inherit through entity_id.';

create index entities_local_context_idx on local_intel.entities (local_context_id);
create index entities_local_context_type_city_idx on local_intel.entities (local_context_id, entity_type, city);
create index search_queries_local_context_status_idx on local_intel.search_queries (local_context_id, status, started_at desc);
create index research_attempts_local_context_attempted_idx on local_intel.research_attempts (local_context_id, attempted_at desc) where local_context_id is not null;
create index entity_ingestion_candidates_local_context_review_idx on local_intel.entity_ingestion_candidates (local_context_id, review_state, created_at);
