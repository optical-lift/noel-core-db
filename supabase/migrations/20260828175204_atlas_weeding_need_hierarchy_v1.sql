-- Atlas weeding need hierarchy v1
-- Bed/area need is canonical; released weed tasks are projections of that need.
-- Manual owner ranking must survive ordinary priority recalculation, and planting
-- blockers must enter recovery work instead of being misclassified as light maintenance.

create or replace function atlas.recalculate_weeding_priorities(
  p_farm_key text default 'elm_farm'::text,
  p_as_of date default current_date
)
returns integer
language plpgsql
security definer
set search_path to 'atlas', 'public'
as $function$
declare
  v_farm_id uuid;
  v_updated integer := 0;
begin
  select id into v_farm_id from atlas.farms where stable_key = p_farm_key;
  if v_farm_id is null then raise exception 'Unknown farm key: %', p_farm_key; end if;

  update atlas.maintenance_objects mo
  set next_eligible_date = case
        when mo.next_eligible_date is null or mo.next_eligible_date < p_as_of then p_as_of
        else mo.next_eligible_date end,
      priority_score = greatest(0, p_as_of - coalesce(mo.last_completed_at::date, date '1900-01-01')),
      owner_priority = case
        when lower(coalesce(mo.metadata->>'manual_owner_priority_locked','false')) in ('true','yes','1')
          then mo.owner_priority
        when z.stable_key = 'field_rows' then case go.stable_key
          when 'fr_18' then 1000 when 'fr_2' then 990 when 'fr_3' then 980
          when 'fr_11' then 970 when 'fr_12' then 960 when 'fr_13' then 950
          when 'fr_14' then 940 when 'fr_15' then 930 when 'fr_4' then 920
          when 'fr_5' then 910 when 'fr_6' then 900 when 'fr_9' then 890
          when 'fr_10' then 880 when 'fr_1' then 870 when 'fr_7' then 860
          when 'fr_8' then 850 when 'fr_16' then 840 when 'fr_17' then 830 else 820 end
        when z.stable_key = 'main_garden' then 800
        when z.stable_key = 'berry_walk_flower_rows' then 700
        when go.stable_key = 'berry_walk_crescent_moon' then 600
        when z.stable_key = 'entry_billboard' then 500
        when z.stable_key = 'barn_beds' then 300
        when z.stable_key = 'u_pick' then 200
        when z.stable_key = 'lilac_haven' then 100
        else 400 end,
      metadata = coalesce(mo.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'base_owner_hierarchy_rank', case
            when z.stable_key = 'field_rows' then 1
            when z.stable_key = 'main_garden' then 2
            when z.stable_key = 'berry_walk_flower_rows' then 3
            when go.stable_key = 'berry_walk_crescent_moon' then 4
            when z.stable_key = 'entry_billboard' then 5
            when z.stable_key = 'barn_beds' then 7
            when z.stable_key = 'u_pick' then 8
            when z.stable_key = 'lilac_haven' then 9
            else 6 end,
          'base_priority_reason', case
            when z.stable_key = 'field_rows' then 'Owner hierarchy 1: Field Rows'
            when z.stable_key = 'main_garden' then 'Owner hierarchy 2: Main Garden'
            when z.stable_key = 'berry_walk_flower_rows' then 'Owner hierarchy 3: Berry Walk'
            when go.stable_key = 'berry_walk_crescent_moon' then 'Owner hierarchy 4: Berry Walk Crescent Moon'
            when z.stable_key = 'entry_billboard' then 'Owner hierarchy 5: Entry Billboard'
            when z.stable_key = 'barn_beds' then 'Owner hierarchy 7: Barn Beds'
            when z.stable_key = 'u_pick' then 'Owner hierarchy 8: U-Pick'
            when z.stable_key = 'lilac_haven' then 'Owner hierarchy 9: Lilac Haven'
            else 'Owner hierarchy 6: perennial beds and landscaping' end,
          'priority_recalculated_at', now()
        )
        || case
          when lower(coalesce(mo.metadata->>'manual_owner_priority_locked','false')) in ('true','yes','1') then '{}'::jsonb
          else jsonb_build_object(
            'owner_hierarchy_rank', case
              when z.stable_key = 'field_rows' then 1
              when z.stable_key = 'main_garden' then 2
              when z.stable_key = 'berry_walk_flower_rows' then 3
              when go.stable_key = 'berry_walk_crescent_moon' then 4
              when z.stable_key = 'entry_billboard' then 5
              when z.stable_key = 'barn_beds' then 7
              when z.stable_key = 'u_pick' then 8
              when z.stable_key = 'lilac_haven' then 9
              else 6 end,
            'priority_reason', case
              when z.stable_key = 'field_rows' then 'Owner hierarchy 1: Field Rows'
              when z.stable_key = 'main_garden' then 'Owner hierarchy 2: Main Garden'
              when z.stable_key = 'berry_walk_flower_rows' then 'Owner hierarchy 3: Berry Walk'
              when go.stable_key = 'berry_walk_crescent_moon' then 'Owner hierarchy 4: Berry Walk Crescent Moon'
              when z.stable_key = 'entry_billboard' then 'Owner hierarchy 5: Entry Billboard'
              when z.stable_key = 'barn_beds' then 'Owner hierarchy 7: Barn Beds'
              when z.stable_key = 'u_pick' then 'Owner hierarchy 8: U-Pick'
              when z.stable_key = 'lilac_haven' then 'Owner hierarchy 9: Lilac Haven'
              else 'Owner hierarchy 6: perennial beds and landscaping' end
          ) end,
      updated_at = now()
  from atlas.zones z, atlas.growing_objects go
  where z.id = mo.zone_id and go.id = mo.object_id
    and mo.farm_id = v_farm_id and mo.maintenance_type = 'weed';

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$function$;

create or replace function atlas.sync_weeding_planting_dependencies(
  p_farm_key text default 'elm_farm'::text,
  p_as_of date default current_date
)
returns integer
language plpgsql
set search_path to 'atlas', 'public'
as $function$
declare
  v_farm_id uuid;
  v_count integer := 0;
begin
  select id into v_farm_id from atlas.farms where stable_key = p_farm_key;
  if v_farm_id is null then raise exception 'Unknown farm key: %', p_farm_key; end if;

  update atlas.maintenance_dependencies md
  set active = false,
      metadata = coalesce(md.metadata,'{}'::jsonb) || jsonb_build_object('deactivated_reason','dependent task no longer active','deactivated_at',now()),
      updated_at = now()
  where md.farm_id = v_farm_id
    and md.metadata->>'source' = 'automatic_bed_readiness'
    and not exists (
      select 1 from atlas.tasks t
      where t.id = md.dependent_task_id
        and t.status in ('open','blocked')
    );

  insert into atlas.maintenance_dependencies(
    farm_id, maintenance_object_id, dependent_task_id, dependency_type, active, metadata
  )
  select distinct
    v_farm_id,
    mo.id,
    t.id,
    'blocks_task',
    true,
    jsonb_build_object(
      'source','automatic_bed_readiness',
      'ready_by_date',t.due_date - 1,
      'dependent_due_date',t.due_date,
      'dependent_action',coalesce(t.action_key,t.metadata->>'work_route',t.task_type),
      'synced_at',now()
    )
  from atlas.maintenance_objects mo
  join atlas.task_objects mt on mt.object_id = mo.object_id
  join atlas.tasks t on t.id = mt.task_id
  where mo.farm_id = v_farm_id
    and mo.maintenance_type = 'weed'
    and t.status in ('open','blocked')
    and t.due_date is not null
    and (
      lower(coalesce(t.action_key,'')) in ('sow','seed','plant','planting','transplant','prep')
      or lower(coalesce(t.task_type,'')) ~ '(sow|seed|plant|transplant|succession)'
      or lower(coalesce(t.metadata->>'work_route','')) ~ '(sow|seed|plant|transplant|prep)'
    )
    and not (
      lower(coalesce(t.metadata->>'maintenance_method','')) = 'spray'
      or lower(coalesce(t.metadata->>'work_route','')) = 'weed_and_sow'
    )
  on conflict (maintenance_object_id, dependent_task_id) do update
    set active = true,
        satisfied_at = null,
        dependency_type = excluded.dependency_type,
        metadata = atlas.maintenance_dependencies.metadata || excluded.metadata,
        updated_at = now();

  get diagnostics v_count = row_count;

  update atlas.maintenance_objects mo
  set active = case
        when exists(
          select 1 from atlas.maintenance_dependencies md
          where md.maintenance_object_id = mo.id and md.active and md.satisfied_at is null
        ) and not exists(
          select 1 from atlas.tasks t
          where t.farm_id = mo.farm_id and t.status in ('open','blocked') and t.action_key='weed'
            and (
              t.generated_from_id = mo.id
              or t.metadata->>'maintenance_object_id' = mo.id::text
            )
        ) then true
        else mo.active end,
      must_precede_task = exists(
        select 1 from atlas.maintenance_dependencies md
        where md.maintenance_object_id = mo.id and md.active and md.satisfied_at is null
      ),
      planting_block_score = case
        when exists(
          select 1 from atlas.maintenance_dependencies md
          join atlas.tasks t on t.id = md.dependent_task_id
          where md.maintenance_object_id = mo.id
            and md.active and md.satisfied_at is null
            and t.due_date <= p_as_of + 2
        ) then 100
        when exists(
          select 1 from atlas.maintenance_dependencies md
          join atlas.tasks t on t.id = md.dependent_task_id
          where md.maintenance_object_id = mo.id
            and md.active and md.satisfied_at is null
            and t.due_date <= p_as_of + 7
        ) then 75
        when exists(
          select 1 from atlas.maintenance_dependencies md
          join atlas.tasks t on t.id = md.dependent_task_id
          where md.maintenance_object_id = mo.id
            and md.active and md.satisfied_at is null
        ) then 45
        else 0 end,
      metadata = coalesce(mo.metadata,'{}'::jsonb) || jsonb_build_object(
        'bed_readiness_synced_at',now(),
        'next_planting_due_date',(
          select min(t.due_date)
          from atlas.maintenance_dependencies md
          join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        ),
        'weed_ready_by_date',(
          select min(t.due_date - 1)
          from atlas.maintenance_dependencies md
          join atlas.tasks t on t.id=md.dependent_task_id
          where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null
        )
      ),
      updated_at = now()
  where mo.farm_id=v_farm_id and mo.maintenance_type='weed';

  return v_count;
end;
$function$;

create or replace function atlas.preview_intelligent_weeding_schedule(
  p_farm_key text default 'elm_farm'::text,
  p_start_date date default current_date,
  p_days integer default 14
)
returns table(
  schedule_date date, window_key text, window_minutes integer, window_used_minutes integer,
  window_remaining_minutes integer, sequence_in_window integer, maintenance_object_id uuid,
  object_id uuid, object_key text, object_label text, zone_key text, zone_label text,
  condition text, estimated_minutes integer, priority_score numeric, effective_priority_score numeric,
  owner_priority integer, next_eligible_date date, must_precede_task boolean,
  dependent_task_ids uuid[], dependent_task_labels text[], guest_facing boolean,
  crop_protective boolean, revenue_linked boolean, significant_day_work boolean,
  estimate_source text, priority_reasons text[]
)
language plpgsql
set search_path to 'atlas', 'public'
as $function$
declare
  v_farm_id uuid;
  v_light_minutes integer := 20;
  v_recovery_minutes integer := 120;
  v_date date;
  v_day integer;
  v_rec record;
begin
  if p_days < 1 or p_days > 31 then raise exception 'p_days must be between 1 and 31'; end if;
  select id into v_farm_id from atlas.farms where stable_key=p_farm_key;
  if v_farm_id is null then raise exception 'Unknown farm key: %',p_farm_key; end if;

  perform atlas.sync_weeding_planting_dependencies(p_farm_key,p_start_date);

  select coalesce((metadata->>'daily_light_pass_minutes')::integer,20), morning_minutes
  into v_light_minutes,v_recovery_minutes
  from atlas.maintenance_scheduler_settings
  where farm_id=v_farm_id and maintenance_type='weed' and active
  limit 1;

  create temporary table if not exists pg_temp.atlas_intelligent_weeding_reserved(
    maintenance_object_id uuid primary key
  ) on commit drop;
  truncate pg_temp.atlas_intelligent_weeding_reserved;

  for v_day in 0..p_days-1 loop
    v_date := p_start_date + v_day;
    if extract(dow from v_date)=0 then continue; end if;

    -- Light maintenance never consumes a bed that is blocking planting.
    select q.* into v_rec
    from (
      select mo.*,go.stable_key go_key,go.label go_label,z.stable_key z_key,z.label z_label,
        coalesce((select min(t.due_date-1) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),date '9999-12-31') ready_by,
        coalesce((select array_agg(md.dependent_task_id order by t.due_date,t.title) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),'{}'::uuid[]) dep_ids,
        coalesce((select array_agg(t.title order by t.due_date,t.title) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),'{}'::text[]) dep_labels
      from atlas.maintenance_objects mo
      join atlas.growing_objects go on go.id=mo.object_id
      left join atlas.zones z on z.id=mo.zone_id
      left join atlas.object_state os on os.object_id=mo.object_id
      where mo.farm_id=v_farm_id and mo.maintenance_type='weed' and mo.active
        and mo.condition in ('maintained','moderate')
        and not mo.must_precede_task
        and mo.next_eligible_date<=v_date
        and mo.remaining_effort_minutes>0
        and coalesce(os.life_status,'active') not in ('germinating','planted_no_emergence','emerging')
        and not exists(select 1 from pg_temp.atlas_intelligent_weeding_reserved r where r.maintenance_object_id=mo.id)
    ) q
    order by
      case coalesce(q.metadata->>'owner_need_class','')
        when 'crop_protection' then 1 when 'guest_readiness' then 2 when 'revenue' then 3
        when 'ordinary' then 4 when 'reclamation_later' then 9 else 5 end,
      case when coalesce(q.metadata->>'owner_need_rank','') ~ '^\d+$' then (q.metadata->>'owner_need_rank')::integer else 999999 end,
      q.owner_priority desc,
      q.last_completed_at asc nulls first,
      q.priority_score desc,
      q.go_label
    limit 1;

    if found then
      insert into pg_temp.atlas_intelligent_weeding_reserved values(v_rec.id) on conflict do nothing;
      schedule_date:=v_date; window_key:='evening'; window_minutes:=v_light_minutes;
      window_used_minutes:=least(v_light_minutes,greatest(5,v_rec.maintenance_effort_minutes)); window_remaining_minutes:=greatest(0,v_light_minutes-window_used_minutes); sequence_in_window:=1;
      maintenance_object_id:=v_rec.id; object_id:=v_rec.object_id; object_key:=v_rec.go_key; object_label:=v_rec.go_label; zone_key:=v_rec.z_key; zone_label:=v_rec.z_label;
      condition:='light'; estimated_minutes:=window_used_minutes; priority_score:=v_rec.priority_score;
      effective_priority_score:=v_rec.priority_score+v_rec.planting_block_score;
      owner_priority:=v_rec.owner_priority; next_eligible_date:=v_rec.next_eligible_date; must_precede_task:=v_rec.must_precede_task;
      dependent_task_ids:=v_rec.dep_ids; dependent_task_labels:=v_rec.dep_labels; guest_facing:=v_rec.guest_facing; crop_protective:=v_rec.crop_protective; revenue_linked:=v_rec.revenue_linked;
      significant_day_work:=false; estimate_source:='daily_light_timebox';
      priority_reasons:=array_remove(array['protect a previously weeded bed',nullif(v_rec.metadata->>'owner_priority_reason','')],null);
      return next;
    end if;

    -- Recovery work is ordered by biological/dependency pressure first, then explicit
    -- owner need class/rank, then physical condition and age.
    select q.* into v_rec
    from (
      select mo.*,go.stable_key go_key,go.label go_label,z.stable_key z_key,z.label z_label,
        coalesce((select min(t.due_date-1) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),date '9999-12-31') ready_by,
        coalesce((select array_agg(md.dependent_task_id order by t.due_date,t.title) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),'{}'::uuid[]) dep_ids,
        coalesce((select array_agg(t.title order by t.due_date,t.title) from atlas.maintenance_dependencies md join atlas.tasks t on t.id=md.dependent_task_id where md.maintenance_object_id=mo.id and md.active and md.satisfied_at is null),'{}'::text[]) dep_labels
      from atlas.maintenance_objects mo
      join atlas.growing_objects go on go.id=mo.object_id
      left join atlas.zones z on z.id=mo.zone_id
      where mo.farm_id=v_farm_id and mo.maintenance_type='weed' and mo.active
        and mo.condition in ('heavy','reset','moderate')
        and mo.remaining_effort_minutes>0
        and not exists(select 1 from pg_temp.atlas_intelligent_weeding_reserved r where r.maintenance_object_id=mo.id)
    ) q
    order by
      case when q.ready_by<=v_date+2 then 0 when q.ready_by<date '9999-12-31' then 1 else 2 end,
      case coalesce(q.metadata->>'owner_need_class','')
        when 'planting_blocker' then 0 when 'crop_protection' then 1 when 'guest_readiness' then 2
        when 'revenue' then 3 when 'ordinary' then 4 when 'reclamation_later' then 9 else 5 end,
      case when coalesce(q.metadata->>'owner_need_rank','') ~ '^\d+$' then (q.metadata->>'owner_need_rank')::integer else 999999 end,
      q.owner_priority desc,
      case q.condition when 'reset' then 0 when 'heavy' then 1 else 2 end,
      q.ready_by,
      q.last_completed_at asc nulls first,
      q.priority_score desc,
      q.go_label
    limit 1;

    if found then
      insert into pg_temp.atlas_intelligent_weeding_reserved values(v_rec.id) on conflict do nothing;
      schedule_date:=v_date; window_key:='morning'; window_minutes:=v_recovery_minutes;
      window_used_minutes:=least(v_recovery_minutes,v_rec.remaining_effort_minutes); window_remaining_minutes:=greatest(0,v_recovery_minutes-window_used_minutes); sequence_in_window:=1;
      maintenance_object_id:=v_rec.id; object_id:=v_rec.object_id; object_key:=v_rec.go_key; object_label:=v_rec.go_label; zone_key:=v_rec.z_key; zone_label:=v_rec.z_label;
      condition:=v_rec.condition; estimated_minutes:=v_rec.remaining_effort_minutes; priority_score:=v_rec.priority_score;
      effective_priority_score:=v_rec.priority_score+v_rec.planting_block_score+case when v_rec.ready_by<=v_date then 500 when v_rec.ready_by<=v_date+2 then 300 when v_rec.ready_by<date '9999-12-31' then 150 else 0 end;
      owner_priority:=v_rec.owner_priority; next_eligible_date:=v_rec.next_eligible_date; must_precede_task:=v_rec.must_precede_task;
      dependent_task_ids:=v_rec.dep_ids; dependent_task_labels:=v_rec.dep_labels; guest_facing:=v_rec.guest_facing; crop_protective:=v_rec.crop_protective; revenue_linked:=v_rec.revenue_linked;
      significant_day_work:=true; estimate_source:=v_rec.estimate_source;
      priority_reasons:=array_remove(array[
        case when v_rec.must_precede_task then 'opens bed for planting' else 'win back one bed' end,
        v_rec.condition||' condition',
        nullif(v_rec.metadata->>'owner_priority_reason',''),
        case when v_rec.ready_by<date '9999-12-31' then 'must be weeded by '||v_rec.ready_by::text end,
        case when cardinality(v_rec.dep_labels)>0 then 'prepares for '||array_to_string(v_rec.dep_labels,' · ') end
      ],null);
      return next;
    end if;
  end loop;
end;
$function$;

create or replace function atlas.set_weeding_need_rank_v1(
  p_farm_id uuid,
  p_object_id uuid,
  p_owner_rank integer,
  p_need_class text,
  p_reason text,
  p_reactivate boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas','auth'
as $function$
declare
  v_actor atlas.farm_memberships%rowtype;
  v_object atlas.growing_objects%rowtype;
  v_mo atlas.maintenance_objects%rowtype;
  v_card_id uuid;
  v_priority integer;
  v_class text:=lower(nullif(btrim(coalesce(p_need_class,'')),''));
begin
  if auth.uid() is null then raise exception 'Authenticated user required.' using errcode='42501'; end if;
  select * into v_actor from atlas.farm_memberships
  where farm_id=p_farm_id and user_id=auth.uid() and active=true and role in ('owner','manager')
  order by case role when 'owner' then 0 else 1 end,created_at limit 1;
  if v_actor.id is null then raise exception 'Owner or manager farm membership required.' using errcode='42501'; end if;
  if p_owner_rank is null or p_owner_rank<1 or p_owner_rank>999 then raise exception 'Owner need rank must be between 1 and 999.' using errcode='22023'; end if;
  if v_class not in ('planting_blocker','crop_protection','guest_readiness','revenue','ordinary','reclamation_later') then
    raise exception 'Unsupported weeding need class.' using errcode='22023';
  end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null or length(btrim(p_reason))>600 then raise exception 'Need reason is required and must be 600 characters or fewer.' using errcode='22023'; end if;

  select * into v_object from atlas.growing_objects where id=p_object_id and farm_id=p_farm_id;
  if v_object.id is null then raise exception 'Growing object not found in this farm.' using errcode='P0002'; end if;

  v_card_id:=atlas.ensure_weed_card_for_object_v1(v_object.id,null);
  select * into v_mo from atlas.maintenance_objects where object_id=v_object.id and maintenance_type='weed' order by created_at limit 1 for update;
  if v_mo.id is null then raise exception 'Weed maintenance object could not be resolved.' using errcode='55000'; end if;

  v_priority:=case v_class
    when 'planting_blocker' then greatest(4001,5001-p_owner_rank)
    when 'crop_protection' then greatest(3001,4001-p_owner_rank)
    when 'guest_readiness' then greatest(2501,3501-p_owner_rank)
    when 'revenue' then greatest(2001,3001-p_owner_rank)
    when 'ordinary' then greatest(1001,2001-p_owner_rank)
    when 'reclamation_later' then greatest(1,101-p_owner_rank)
    else 1 end;

  update atlas.maintenance_objects
  set owner_priority=v_priority,
      active=case when p_reactivate and v_class<>'reclamation_later' then true else active end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'manual_owner_priority_locked',true,
        'owner_need_class',v_class,
        'owner_need_rank',p_owner_rank,
        'owner_priority_reason',btrim(p_reason),
        'owner_need_set_at',now(),
        'owner_need_set_by_membership_id',v_actor.id,
        'owner_need_source','set_weeding_need_rank_v1'
      ),
      updated_at=now()
  where id=v_mo.id
  returning * into v_mo;

  update atlas.weed_cards
  set next_review_on=case when p_reactivate and v_class<>'reclamation_later' then least(coalesce(next_review_on,current_date),current_date) else next_review_on end,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'owner_need_class',v_class,
        'owner_need_rank',p_owner_rank,
        'owner_priority_reason',btrim(p_reason),
        'owner_need_set_at',now(),
        'owner_need_set_by_membership_id',v_actor.id
      ),
      updated_at=now()
  where id=v_card_id;

  return jsonb_build_object(
    'contractVersion','weeding_need_rank_v1',
    'farmId',p_farm_id,
    'objectId',v_object.id,
    'objectLabel',v_object.label,
    'maintenanceObjectId',v_mo.id,
    'weedCardId',v_card_id,
    'ownerNeedClass',v_class,
    'ownerNeedRank',p_owner_rank,
    'ownerPriority',v_mo.owner_priority,
    'active',v_mo.active,
    'reason',btrim(p_reason)
  );
end;
$function$;

grant execute on function atlas.set_weeding_need_rank_v1(uuid,uuid,integer,text,text,boolean) to authenticated;
