-- Bed maps own visible physical truth; inline crop entry records only observed presence.

update atlas.growing_object_relationships r
set metadata = coalesce(r.metadata, '{}'::jsonb) || jsonb_build_object(
  'mapSide', case
    when parent.metadata->>'side' = 'left' then 'right'
    when parent.metadata->>'side' = 'right' then 'left'
    else null
  end,
  'mapGeometrySource', 'owner_report_20260826'
)
from atlas.growing_objects parent,
     atlas.growing_objects child
where r.parent_object_id = parent.id
  and r.child_object_id = child.id
  and r.relationship_type = 'contains'
  and child.object_type = 'component'
  and child.metadata->>'component_kind' = 'arch'
  and parent.stable_key ~ '^curve_arch_0[12]_(left|right)_bed$';

create or replace function atlas.bed_components_state_v1(p_bed_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_bed atlas.growing_objects%rowtype;
  v_role text;
  v_result jsonb;
begin
  select * into v_bed from atlas.growing_objects where id=p_bed_id;
  if v_bed.id is null then raise exception 'Growing object not found.' using errcode='P0002'; end if;

  v_role:=atlas.current_farm_role(v_bed.farm_id);
  if not atlas.is_farm_owner(v_bed.farm_id) and coalesce(v_role,'') not in ('farm_hand','manager') then
    raise exception 'Bed components are not available to the signed-in farm member.' using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'componentId',c.id,
    'componentKey',c.stable_key,
    'componentLabel',c.label,
    'componentKind',coalesce(c.metadata->>'component_kind','component'),
    'positionLabel',r.position_label,
    'mapSide',nullif(r.metadata->>'mapSide',''),
    'relationshipMetadata',r.metadata,
    'occupancyState',coalesce(o.occ->>'occupancyState','empty'),
    'availableForPlanting',coalesce((o.occ->>'availableForPlanting')::boolean,true),
    'occupancyGroups',coalesce(o.occ->'groups','[]'::jsonb)
  ) order by r.sort_order,c.label),'[]'::jsonb)
  into v_result
  from atlas.growing_object_relationships r
  join atlas.growing_objects c on c.id=r.child_object_id
  left join lateral (select atlas.object_crop_occupancy_v1(c.id) as occ) o on true
  where r.parent_object_id=v_bed.id
    and r.relationship_type='contains'
    and c.object_type='component';

  return jsonb_build_object(
    'bedId',v_bed.id,
    'bedKey',v_bed.stable_key,
    'bedLabel',v_bed.label,
    'components',coalesce(v_result,'[]'::jsonb)
  );
end;
$function$;

create or replace function atlas.record_observed_crop_presence_for_member_v1(
  p_farm_id uuid,
  p_object_key text,
  p_crop_label text,
  p_observed_date date default current_date,
  p_note text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'atlas'
as $function$
declare
  v_object atlas.growing_objects%rowtype;
  v_content atlas.object_contents%rowtype;
  v_cycle atlas.crop_cycles%rowtype;
  v_profile atlas.crop_profiles%rowtype;
  v_placement atlas.crop_placements%rowtype;
  v_observation atlas.crop_observations%rowtype;
  v_role text;
  v_membership_id uuid;
  v_crop_label text := nullif(btrim(p_crop_label),'');
  v_identity text;
  v_idempotency text := nullif(btrim(p_idempotency_key),'');
  v_created_cycle boolean := false;
begin
  if p_farm_id is null then raise exception 'Farm is required.' using errcode='22023'; end if;
  if nullif(btrim(p_object_key),'') is null then raise exception 'Bed is required.' using errcode='22023'; end if;
  if v_crop_label is null or length(v_crop_label) > 120 then raise exception 'Crop name must be between 1 and 120 characters.' using errcode='22023'; end if;
  if p_observed_date is null or p_observed_date > current_date then raise exception 'Observed date must be today or earlier.' using errcode='22023'; end if;
  if p_note is not null and length(p_note) > 2000 then raise exception 'Crop presence note is too long.' using errcode='22023'; end if;
  if v_idempotency is null or length(v_idempotency) > 160 then raise exception 'A valid save key is required.' using errcode='22023'; end if;

  v_role := atlas.current_farm_role(p_farm_id);
  v_membership_id := atlas.current_membership_id(p_farm_id);
  if not atlas.is_farm_owner(p_farm_id)
     and not (coalesce(v_role,'') in ('farm_hand','manager') and v_membership_id is not null)
  then
    raise exception 'Active farm membership is required to record crop presence.' using errcode='42501';
  end if;

  select go.* into v_object
  from atlas.growing_objects go
  where go.farm_id=p_farm_id and go.stable_key=btrim(p_object_key)
  limit 1;
  if v_object.id is null then raise exception 'Growing object not found.' using errcode='P0002'; end if;
  if v_object.object_type not in ('bed','arch_bed') and coalesce(v_object.metadata->>'planting_surface','') <> 'bed' then
    raise exception 'Inline crop presence may only be recorded on a bed.' using errcode='22023';
  end if;

  select o.* into v_observation
  from atlas.crop_observations o
  where o.farm_id=p_farm_id and o.idempotency_key=v_idempotency
  limit 1;
  if v_observation.id is not null then
    select cc.* into v_cycle from atlas.crop_cycles cc where cc.id=v_observation.crop_cycle_id;
    return jsonb_build_object(
      'objectId',v_object.id,'objectKey',v_object.stable_key,'objectLabel',v_object.label,
      'cropCycleId',v_cycle.id,'cropLabel',v_cycle.crop_label,
      'observedDate',v_observation.observed_date,'createdCycle',false,'replayed',true
    );
  end if;

  v_identity := atlas.normalize_crop_identity_v1(v_crop_label,null);

  select cc.* into v_cycle
  from atlas.crop_cycles cc
  where cc.object_id=v_object.id
    and cc.lifecycle_status='active'
    and atlas.normalize_crop_identity_v1(cc.crop_label,cc.variety)=v_identity
  order by cc.updated_at desc
  limit 1;

  if v_cycle.id is null then
    select cp.* into v_profile
    from atlas.crop_profiles cp
    where lower(btrim(cp.crop_label))=lower(v_crop_label)
      and cp.variety is null
    order by cp.updated_at desc
    limit 1;

    insert into atlas.object_contents(
      farm_id,object_id,crop_profile_id,content_label,content_type,status,confidence,note,metadata
    ) values (
      v_object.farm_id,v_object.id,v_profile.id,v_crop_label,'crop','observed','medium',nullif(btrim(p_note),''),
      jsonb_strip_nulls(jsonb_build_object(
        'source','inline_bed_crop_presence_v1',
        'observed_date',p_observed_date,
        'actor_membership_id',v_membership_id,
        'actor_role',v_role
      ))
    ) returning * into v_content;

    perform atlas.ensure_crop_cycle_for_content_v1(v_content.id);
    select cc.* into v_cycle
    from atlas.crop_cycles cc
    where cc.object_content_id=v_content.id
       or (cc.object_id=v_object.id and cc.lifecycle_status='active' and atlas.normalize_crop_identity_v1(cc.crop_label,cc.variety)=v_identity)
    order by (cc.object_content_id=v_content.id) desc,cc.updated_at desc
    limit 1;

    if v_cycle.id is null then raise exception 'Atlas could not establish crop presence.' using errcode='P0002'; end if;
    v_created_cycle := true;
  end if;

  select p.* into v_placement
  from atlas.crop_placements p
  where p.crop_cycle_id=v_cycle.id and p.object_id=v_object.id
  order by (p.position_confidence='high') desc,p.created_at
  limit 1;

  if v_placement.id is null then
    insert into atlas.crop_placements(
      farm_id,object_id,crop_cycle_id,object_content_id,placement_key,placement_mode,
      confidence,position_confidence,metadata
    ) values (
      v_object.farm_id,v_object.id,v_cycle.id,v_cycle.object_content_id,'observed_presence','unknown',
      'medium','unknown',jsonb_build_object('source','inline_bed_crop_presence_v1')
    )
    on conflict (crop_cycle_id,placement_key) do update
      set updated_at=now()
    returning * into v_placement;
  end if;

  insert into atlas.crop_observations(
    farm_id,object_id,crop_cycle_id,placement_id,object_content_id,observed_date,stage,
    confidence,source_kind,source_id,note,idempotency_key,metadata
  ) values (
    v_object.farm_id,v_object.id,v_cycle.id,v_placement.id,v_cycle.object_content_id,p_observed_date,null,
    'medium','field_presence',coalesce(v_membership_id::text,auth.uid()::text),nullif(btrim(p_note),''),v_idempotency,
    jsonb_strip_nulls(jsonb_build_object(
      'source','inline_bed_crop_presence_v1',
      'actor_user_id',auth.uid(),
      'actor_membership_id',v_membership_id,
      'actor_role',v_role
    ))
  ) returning * into v_observation;

  return jsonb_build_object(
    'objectId',v_object.id,'objectKey',v_object.stable_key,'objectLabel',v_object.label,
    'cropCycleId',v_cycle.id,'cropLabel',v_cycle.crop_label,
    'observedDate',v_observation.observed_date,'createdCycle',v_created_cycle,'replayed',false
  );
end;
$function$;

revoke all on function atlas.record_observed_crop_presence_for_member_v1(uuid,text,text,date,text,text) from public;
revoke all on function atlas.record_observed_crop_presence_for_member_v1(uuid,text,text,date,text,text) from anon;
grant execute on function atlas.record_observed_crop_presence_for_member_v1(uuid,text,text,date,text,text) to authenticated;
grant execute on function atlas.record_observed_crop_presence_for_member_v1(uuid,text,text,date,text,text) to service_role;

revoke all on function atlas.bed_components_state_v1(uuid) from public;
revoke all on function atlas.bed_components_state_v1(uuid) from anon;
grant execute on function atlas.bed_components_state_v1(uuid) to authenticated;
grant execute on function atlas.bed_components_state_v1(uuid) to service_role;
