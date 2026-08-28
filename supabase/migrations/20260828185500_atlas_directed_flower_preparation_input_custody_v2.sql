begin;

create or replace function atlas.attach_directed_flower_preparation_inputs_v2()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_input_count integer;
begin
  if coalesce(new.metadata->>'source', '') <> 'flower_preparation_directive_result_v2' then
    return new;
  end if;

  insert into atlas.flower_preparation_inputs(
    farm_id,
    preparation_batch_id,
    harvest_observation_id,
    source_bucket_band,
    source_bucket_equivalent_floor,
    source_lower_bound
  )
  select
    h.farm_id,
    new.id,
    h.id,
    h.bucket_band,
    h.bucket_equivalent_floor,
    (h.bucket_band = 'more_than_one' and h.bucket_halves is null)
  from atlas.flower_harvest_bucket_observations h
  where h.batch_id = new.harvest_batch_id
    and not exists (
      select 1
      from atlas.flower_preparation_inputs i
      where i.harvest_observation_id = h.id
    )
  order by h.created_at;

  get diagnostics v_input_count = row_count;
  if v_input_count < 1 then
    raise exception 'There is no unprepared harvest output in this batch.' using errcode = '22023';
  end if;

  return new;
end;
$function$;

revoke all on function atlas.attach_directed_flower_preparation_inputs_v2() from public;

drop trigger if exists trg_attach_directed_flower_preparation_inputs_v2 on atlas.flower_preparation_batches;
create trigger trg_attach_directed_flower_preparation_inputs_v2
after insert on atlas.flower_preparation_batches
for each row
execute function atlas.attach_directed_flower_preparation_inputs_v2();

commit;
