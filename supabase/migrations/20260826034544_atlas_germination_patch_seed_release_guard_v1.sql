create or replace function atlas.guard_germination_patch_seed_release_v1()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_binding text;
  v_seed_lot_id uuid;
  v_state atlas.seed_inventory_state%rowtype;
  v_required numeric;
  v_explicit numeric;
  v_rows numeric;
  v_spacing numeric;
  v_quantity numeric;
  v_object_count integer := 0;
  v_ready boolean := false;
  v_state_label text;
begin
  if new.generated_from is distinct from 'germination_patch' then
    return new;
  end if;

  if coalesce(new.metadata->>'seed_governance_required','false') <> 'true' then
    return new;
  end if;

  v_binding := coalesce(nullif(new.metadata->>'seed_source_binding_state',''),'seed_source_unbound');
  begin
    v_seed_lot_id := nullif(new.metadata->>'seed_lot_id','')::uuid;
  exception when others then
    v_seed_lot_id := null;
  end;

  if v_binding <> 'seed_source_bound' or v_seed_lot_id is null then
    v_state_label := v_binding;
  else
    select * into v_state
    from atlas.seed_inventory_state
    where seed_lot_id = v_seed_lot_id;

    if v_state.seed_lot_id is null then
      v_state_label := 'seed_state_missing';
    else
      begin
        v_explicit := nullif(new.metadata->>'seed_requirement_quantity','')::numeric;
      exception when others then
        v_explicit := null;
      end;

      if v_explicit is not null and v_explicit > 0 then
        v_required := v_explicit;
      else
        begin
          v_rows := nullif(new.metadata->>'rows_per_3ft_bed','')::numeric;
        exception when others then
          v_rows := null;
        end;
        begin
          v_spacing := nullif(new.metadata->>'in_row_spacing_in','')::numeric;
        exception when others then
          v_spacing := null;
        end;

        if v_rows is not null and v_rows > 0 and v_spacing is not null and v_spacing > 0 then
          with raw_ids as (
            select value as raw
            from jsonb_array_elements_text(
              case when jsonb_typeof(new.metadata->'target_object_ids')='array'
                then new.metadata->'target_object_ids'
                else '[]'::jsonb end
            )
            union all
            select new.metadata->>'target_object_id'
            where nullif(new.metadata->>'target_object_id','') is not null
          ), ids as (
            select distinct raw::uuid as id
            from raw_ids
            where raw ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          )
          select count(*)::integer,
                 coalesce(sum(ceil((go.length_ft * 12) / v_spacing) * v_rows),0)
          into v_object_count, v_quantity
          from ids
          join atlas.growing_objects go
            on go.id = ids.id
           and go.farm_id = new.farm_id
          where go.length_ft is not null
            and go.length_ft > 0;

          if v_object_count > 0 and v_quantity > 0 then
            v_required := v_quantity;
          end if;
        end if;
      end if;

      if v_required is null or v_required <= 0 then
        v_state_label := 'seed_requirement_unknown';
      elsif v_state.quantity_knowledge_kind = 'exact' then
        v_ready := coalesce(v_state.verified_on_hand_quantity,0) >= v_required
          and v_state.status not in ('depleted','problem','retired','uncertain');
        v_state_label := case
          when v_ready then 'ready_exact'
          when v_state.status='depleted' or coalesce(v_state.verified_on_hand_quantity,0)=0 then 'depleted'
          else 'insufficient_exact'
        end;
      elsif v_state.quantity_knowledge_kind = 'lower_bound' then
        v_ready := coalesce(v_state.known_lower_bound_quantity,0) >= v_required
          and v_state.status='bounded';
        v_state_label := case when v_ready then 'ready_lower_bound' else 'lower_bound_insufficient' end;
      elsif v_state.quantity_knowledge_kind = 'positive_unknown' then
        v_state_label := 'positive_quantity_unmeasured';
      else
        v_state_label := 'quantity_unknown';
      end if;
    end if;
  end if;

  if not v_ready then
    new.status := 'archived';
    new.due_date := null;
    new.assigned_membership_id := null;
    new.visibility_scope := 'system_internal';
    new.metadata := coalesce(new.metadata,'{}'::jsonb)
      || jsonb_build_object(
        'sowing_suppressed', true,
        'patching_suppressed', true,
        'seed_release_guard', 'germination_patch_seed_release_guard_v1',
        'seed_release_guard_state', coalesce(v_state_label,'seed_not_ready'),
        'archived_reason', 'Seed requirement is not execution-ready; patch need preserved without worker release.'
      );
  end if;

  return new;
end;
$function$;

revoke all on function atlas.guard_germination_patch_seed_release_v1() from public;
revoke all on function atlas.guard_germination_patch_seed_release_v1() from anon;
revoke all on function atlas.guard_germination_patch_seed_release_v1() from authenticated;

create trigger zzzzzzzz_guard_germination_patch_seed_release_v1
before insert or update of generated_from, generated_from_id, metadata, status, due_date, assigned_membership_id, visibility_scope
on atlas.tasks
for each row
execute function atlas.guard_germination_patch_seed_release_v1();

with suppressed as (
  select t.id,
         atlas.task_seed_readiness_v1(t.id) as readiness
  from atlas.tasks t
  where t.generated_from='germination_patch'
    and t.status in ('open','blocked')
), retired as (
  update atlas.tasks t
  set status='archived',
      due_date=null,
      assigned_membership_id=null,
      visibility_scope='system_internal',
      metadata=coalesce(t.metadata,'{}'::jsonb) || jsonb_build_object(
        'sowing_suppressed', true,
        'patching_suppressed', true,
        'seed_release_guard', 'germination_patch_seed_release_guard_v1',
        'seed_release_guard_state', coalesce(s.readiness->>'state','seed_not_ready'),
        'archived_reason', 'Seed requirement is not execution-ready; patch need preserved without worker release.'
      )
  from suppressed s
  where t.id=s.id
    and coalesce((s.readiness->>'ready')::boolean,false)=false
  returning t.id
)
update atlas.planned_work_occurrences pwo
set state='cancelled',
    metadata=coalesce(pwo.metadata,'{}'::jsonb) || jsonb_build_object(
      'cancelled_by','germination_patch_seed_release_guard_v1',
      'cancelled_reason','Released patch task was not seed-execution-ready.'
    ),
    updated_at=now()
where pwo.state='released'
  and pwo.released_task_id in (select id from retired);