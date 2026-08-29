create or replace function atlas.validate_flower_ready_inventory_lot_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_preparation atlas.flower_preparation_batches%rowtype;
  v_shared_batch_input boolean;
begin
  select * into v_preparation from atlas.flower_preparation_batches where id=new.preparation_batch_id;
  if v_preparation.id is null or v_preparation.farm_id is distinct from new.farm_id then
    raise exception 'Ready inventory preparation does not belong to this farm.' using errcode='22023';
  end if;
  if v_preparation.result_kind<>'ready' then
    raise exception 'A no-saleable-output preparation cannot create Ready inventory.' using errcode='22023';
  end if;

  v_shared_batch_input := coalesce(v_preparation.metadata->>'inputAllocation','')='unquantified_existing_harvest_custody';

  if not exists (select 1 from atlas.flower_preparation_inputs where preparation_batch_id=v_preparation.id) then
    if not v_shared_batch_input
       or v_preparation.harvest_batch_id is null
       or not exists (
         select 1
         from atlas.flower_harvest_batches hb
         where hb.id=v_preparation.harvest_batch_id and hb.farm_id=v_preparation.farm_id
           and (
             exists (select 1 from atlas.flower_harvest_bucket_observations h where h.batch_id=hb.id)
             or exists (
               select 1 from atlas.flower_external_intakes i
               join atlas.flower_external_intake_lines l on l.intake_id=i.id
               where i.harvest_batch_id=hb.id
             )
           )
       ) then
      raise exception 'Ready inventory requires harvested preparation input.' using errcode='22023';
    end if;
  end if;

  if new.ready_date < v_preparation.prepared_date then
    raise exception 'Ready inventory cannot predate its preparation.' using errcode='22023';
  end if;

  if new.crop_profile_id is not null and not (
    exists (
      select 1
      from atlas.flower_preparation_inputs i
      join atlas.flower_harvest_bucket_observations h on h.id=i.harvest_observation_id
      join atlas.crop_cycles c on c.id=h.crop_cycle_id
      where i.preparation_batch_id=v_preparation.id and c.crop_profile_id=new.crop_profile_id
    )
    or (
      v_shared_batch_input and exists (
        select 1
        from atlas.flower_harvest_bucket_observations h
        join atlas.crop_cycles c on c.id=h.crop_cycle_id
        where h.batch_id=v_preparation.harvest_batch_id and c.crop_profile_id=new.crop_profile_id
      )
    )
  ) then
    raise exception 'Ready inventory crop identity is not present in its harvested preparation inputs.' using errcode='22023';
  end if;
  return new;
end;
$function$;