create or replace function local_intel.stamp_single_active_local_context_v1()
returns trigger
language plpgsql
set search_path = pg_catalog, public, atlas, local_intel
as $$
declare
  v_context_id uuid;
  v_context_count integer;
begin
  if new.local_context_id is not null then
    return new;
  end if;

  select count(*), min(id::text)::uuid
    into v_context_count, v_context_id
  from local_intel.local_contexts
  where status = 'active';

  if v_context_count <> 1 or v_context_id is null then
    raise exception 'local_context_id is required when Atlas Local has % active contexts', v_context_count;
  end if;

  new.local_context_id := v_context_id;
  return new;
end;
$$;

comment on function local_intel.stamp_single_active_local_context_v1() is
  'Transitional V1 writer compatibility. While exactly one Local Context is active, legacy writers that omit local_context_id are stamped into it. The moment multiple contexts exist, callers must provide explicit context.';

create trigger entities_single_context_stamp
before insert on local_intel.entities
for each row execute function local_intel.stamp_single_active_local_context_v1();

create trigger search_queries_single_context_stamp
before insert on local_intel.search_queries
for each row execute function local_intel.stamp_single_active_local_context_v1();

create trigger entity_ingestion_candidates_single_context_stamp
before insert on local_intel.entity_ingestion_candidates
for each row execute function local_intel.stamp_single_active_local_context_v1();
