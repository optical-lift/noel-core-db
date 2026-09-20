-- Production Bed Assignment -> canonical crop destination claim projection v1.
-- Unifies Production spatial planning with the crop destination authority model.

begin;

create or replace function atlas.production_bed_assignment_destination_claim_key_v1(
  p_assignment_id uuid
)
returns text
language sql
immutable
set search_path='pg_catalog'
as $function$
  select case
    when p_assignment_id is null then null
    else left('production-bed-assignment:'||p_assignment_id::text||':destination-claim',240)
  end;
$function$;

revoke all on function atlas.production_bed_assignment_destination_claim_key_v1(uuid)
from public,anon,authenticated;
grant execute on function atlas.production_bed_assignment_destination_claim_key_v1(uuid)
to service_role;

create or replace function atlas.sync_production_bed_assignment_destination_claim_v1(
  p_assignment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_assignment atlas.production_bed_assignments%rowtype;
  v_claim atlas.crop_destination_claims%rowtype;
  v_claim_id uuid;
  v_cycle_id uuid;
  v_primary_count integer:=0;
  v_key text;
  v_planned_seedlings numeric:=null;
  v_window_end date:=null;
  v_claim_strength text;
  v_displacement_authority text;
  v_principal_source boolean:=false;
  v_evidence jsonb;
  v_write jsonb;
begin
  if p_assignment_id is null then
    raise exception 'Production Bed Assignment is required.' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('atlas.production-bed-assignment-destination-claim:'||p_assignment_id::text,0)
  );

  select * into v_assignment
  from atlas.production_bed_assignments
  where id=p_assignment_id
  for update;

  if v_assignment.id is null then
    raise exception 'Production Bed Assignment was not found.' using errcode='P0002';
  end if;

  v_key:=atlas.production_bed_assignment_destination_claim_key_v1(v_assignment.id);

  select * into v_claim
  from atlas.crop_destination_claims
  where farm_id=v_assignment.farm_id
    and idempotency_key=v_key
  for update;

  -- Terminal source state must terminalize any exact projected claim even if
  -- current lot lineage later becomes ambiguous. This prevents orphaned claims.
  if v_assignment.assignment_status in ('released','cancelled') then
    if v_claim.id is null then
      return jsonb_build_object(
        'state','terminal_source_without_projected_claim',
        'assignmentId',v_assignment.id,
        'assignmentStatus',v_assignment.assignment_status,
        'claimKey',v_key
      );
    end if;

    update atlas.crop_destination_claims
    set status=case
          when v_assignment.assignment_status='released' then 'released'
          else 'cancelled'
        end,
        source_evidence=coalesce(source_evidence,'{}'::jsonb)
          || jsonb_build_object(
            'productionBedAssignmentId',v_assignment.id,
            'productionLotId',v_assignment.production_lot_id,
            'assignmentStatus',v_assignment.assignment_status,
            'assignmentSource',v_assignment.source,
            'projectionContract','production_bed_assignment_destination_claim_v1',
            'projectionTerminalizedAt',now()
          ),
        metadata=coalesce(metadata,'{}'::jsonb)
          || jsonb_build_object(
            'production_bed_assignment_id',v_assignment.id,
            'projection_contract','production_bed_assignment_destination_claim_v1'
          ),
        updated_at=now()
    where id=v_claim.id
    returning * into v_claim;

    return jsonb_build_object(
      'state','projected_claim_terminal',
      'assignmentId',v_assignment.id,
      'assignmentStatus',v_assignment.assignment_status,
      'claimId',v_claim.id,
      'claimStatus',v_claim.status,
      'claimKey',v_key
    );
  end if;

  if v_assignment.assignment_status<>'assigned' then
    raise exception 'Unsupported Production Bed Assignment status: %',v_assignment.assignment_status
      using errcode='22023';
  end if;

  select count(*)::integer,
         (array_agg(plc.crop_cycle_id order by plc.crop_cycle_id))[1]
  into v_primary_count,v_cycle_id
  from atlas.production_lot_crop_cycles plc
  where plc.production_lot_id=v_assignment.production_lot_id
    and plc.relation_role='primary'
    and plc.confidence='confirmed';

  if v_primary_count<>1 or v_cycle_id is null then
    raise exception
      'Active Production Bed Assignment requires exactly one confirmed primary crop-cycle lineage; found %.',
      v_primary_count
      using errcode='23514';
  end if;

  if v_claim.id is not null then
    if v_claim.crop_cycle_id is distinct from v_cycle_id then
      raise exception
        'Projected destination claim may not move to a different crop cycle; create a new Production Bed Assignment.'
        using errcode='23514';
    end if;

    if v_claim.status<>'active' then
      raise exception
        'A terminal projected destination claim may not be silently reactivated; create a new Production Bed Assignment.'
        using errcode='23514';
    end if;
  end if;

  begin
    v_planned_seedlings:=nullif(v_assignment.metadata->>'planned_seedlings','')::numeric;
  exception when others then
    v_planned_seedlings:=null;
  end;
  if v_planned_seedlings is not null and v_planned_seedlings<=0 then
    v_planned_seedlings:=null;
  end if;

  begin
    v_window_end:=nullif(v_assignment.metadata->>'window_end','')::date;
  exception when others then
    v_window_end:=null;
  end;
  v_window_end:=coalesce(v_window_end,v_assignment.expected_release_date);

  v_principal_source:=
       lower(coalesce(v_assignment.source,'')) like 'owner_checkpoint_%'
    or lower(coalesce(v_assignment.source,'')) like 'owner_instruction_%'
    or lower(coalesce(v_assignment.source,'')) like 'owner_reconciliation_%';

  v_claim_strength:=case when v_principal_source then 'committed' else 'planned' end;
  v_displacement_authority:=case when v_principal_source then 'principal' else 'farm_operations' end;

  v_evidence:=jsonb_strip_nulls(jsonb_build_object(
    'productionBedAssignmentId',v_assignment.id,
    'productionLotId',v_assignment.production_lot_id,
    'productionCapacityRequirementId',v_assignment.requirement_id,
    'assignmentSource',v_assignment.source,
    'assignmentStatus',v_assignment.assignment_status,
    'destinationObjectId',v_assignment.object_id,
    'bedQuantity',v_assignment.quantity_assigned,
    'bedUnit',v_assignment.unit,
    'plannedSeedlings',v_planned_seedlings,
    'plannedTransplantDate',v_assignment.planned_transplant_date,
    'expectedReleaseDate',v_assignment.expected_release_date,
    'windowEnd',v_window_end,
    'sourcePath',v_assignment.metadata->>'source_path',
    'projectionContract','production_bed_assignment_destination_claim_v1',
    'projectedAt',now(),
    'bedFeetAreNotPlantQuantity',true
  ));

  if v_claim.id is null then
    v_write:=atlas.record_crop_destination_claim_v1(
      v_cycle_id,
      v_assignment.object_id,
      v_planned_seedlings,
      case when v_planned_seedlings is null then null else 'seedlings' end,
      v_assignment.planned_transplant_date,
      v_claim_strength,
      v_displacement_authority,
      case
        when v_principal_source then 'Owner-authoritative Production Bed Assignment.'
        else 'Production Bed Assignment projection.'
      end,
      null,
      'production_bed_assignment_projection',
      v_evidence,
      v_key
    );
    v_claim_id:=nullif(v_write->>'claimId','')::uuid;

    select * into v_claim
    from atlas.crop_destination_claims
    where id=v_claim_id
    for update;
  end if;

  update atlas.crop_destination_claims
  set destination_object_id=v_assignment.object_id,
      claimed_quantity=v_planned_seedlings,
      unit=case when v_planned_seedlings is null then null else 'seedlings' end,
      required_by=v_assignment.planned_transplant_date,
      window_start=v_assignment.planned_transplant_date,
      window_end=v_window_end,
      claim_strength=v_claim_strength,
      displacement_authority=v_displacement_authority,
      protection_reason=case
        when v_principal_source then 'Owner-authoritative Production Bed Assignment.'
        else 'Production Bed Assignment projection.'
      end,
      claim_source='production_bed_assignment_projection',
      source_evidence=coalesce(source_evidence,'{}'::jsonb)||v_evidence,
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
        'production_bed_assignment_id',v_assignment.id,
        'production_lot_id',v_assignment.production_lot_id,
        'production_capacity_requirement_id',v_assignment.requirement_id,
        'projection_contract','production_bed_assignment_destination_claim_v1'
      ),
      updated_at=now()
  where id=v_claim.id
  returning * into v_claim;

  return jsonb_build_object(
    'state','projected_claim_active',
    'assignmentId',v_assignment.id,
    'claimId',v_claim.id,
    'claimKey',v_key,
    'cropCycleId',v_claim.crop_cycle_id,
    'destinationObjectId',v_claim.destination_object_id,
    'claimedQuantity',v_claim.claimed_quantity,
    'unit',v_claim.unit,
    'claimStrength',v_claim.claim_strength,
    'displacementAuthority',v_claim.displacement_authority,
    'coverage',atlas.crop_destination_claim_coverage_v1(v_claim.crop_cycle_id)
  );
end;
$function$;

revoke all on function atlas.sync_production_bed_assignment_destination_claim_v1(uuid)
from public,anon,authenticated;
grant execute on function atlas.sync_production_bed_assignment_destination_claim_v1(uuid)
to service_role;

comment on function atlas.sync_production_bed_assignment_destination_claim_v1(uuid) is
'Internal projection from a Production Bed Assignment into the canonical crop destination claim model. Active projection requires exactly one confirmed primary crop-cycle lineage. Bed-feet remain spatial evidence and are never converted to plant quantity. Terminal source states terminalize the exact projected claim without erasing history.';

create or replace function atlas.sync_production_bed_assignment_destination_claim_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path='pg_catalog','atlas'
as $function$
declare
  v_key text;
  v_terminal_status text;
begin
  if tg_op='DELETE' then
    v_key:=atlas.production_bed_assignment_destination_claim_key_v1(old.id);
    v_terminal_status:=case
      when old.assignment_status='released' then 'released'
      else 'cancelled'
    end;

    update atlas.crop_destination_claims
    set status=v_terminal_status,
        source_evidence=coalesce(source_evidence,'{}'::jsonb)
          || jsonb_build_object(
            'productionBedAssignmentId',old.id,
            'productionLotId',old.production_lot_id,
            'sourceAssignmentDeleted',true,
            'sourceAssignmentDeletedAt',now(),
            'projectionContract','production_bed_assignment_destination_claim_v1'
          ),
        metadata=coalesce(metadata,'{}'::jsonb)
          || jsonb_build_object(
            'production_bed_assignment_id',old.id,
            'projection_contract','production_bed_assignment_destination_claim_v1'
          ),
        updated_at=now()
    where farm_id=old.farm_id
      and idempotency_key=v_key
      and status='active';

    return old;
  end if;

  if tg_op='UPDATE'
     and old.production_lot_id is distinct from new.production_lot_id then
    raise exception
      'A projected Production Bed Assignment may not move between Production Lots; create a new assignment.'
      using errcode='23514';
  end if;

  perform atlas.sync_production_bed_assignment_destination_claim_v1(new.id);
  return new;
end;
$function$;

revoke all on function atlas.sync_production_bed_assignment_destination_claim_trigger_v1()
from public,anon,authenticated;

drop trigger if exists p1_sync_production_bed_assignment_destination_claim_v1
on atlas.production_bed_assignments;

create trigger p1_sync_production_bed_assignment_destination_claim_v1
after insert or delete or update of
  production_lot_id,
  requirement_id,
  object_id,
  quantity_assigned,
  unit,
  planned_transplant_date,
  expected_release_date,
  assignment_status,
  source,
  metadata
on atlas.production_bed_assignments
for each row
execute function atlas.sync_production_bed_assignment_destination_claim_trigger_v1();

comment on trigger p1_sync_production_bed_assignment_destination_claim_v1
on atlas.production_bed_assignments is
'Projects Production Bed Assignment destination truth into canonical crop_destination_claims before the zz_ Production work reconciler observes the changed assignment.';

create or replace view atlas.production_bed_assignment_destination_claim_audit_v1 as
select
  pba.id as assignment_id,
  pba.farm_id,
  pba.production_lot_id,
  pba.requirement_id,
  pba.object_id as assigned_object_id,
  pba.assignment_status,
  pba.quantity_assigned as assigned_bed_quantity,
  pba.unit as assigned_bed_unit,
  parsed.planned_seedlings,
  lineage.primary_count,
  lineage.primary_crop_cycle_id,
  cdc.id as projected_claim_id,
  cdc.crop_cycle_id as claim_crop_cycle_id,
  cdc.destination_object_id as claim_destination_object_id,
  cdc.status as claim_status,
  cdc.claimed_quantity,
  cdc.unit as claim_unit,
  cdc.claim_strength,
  cdc.displacement_authority,
  case
    when pba.assignment_status='assigned' and lineage.primary_count<>1
      then 'primary_lineage_unresolved'
    when pba.assignment_status='assigned' and cdc.id is null
      then 'projected_claim_missing'
    when pba.assignment_status='assigned' and cdc.status<>'active'
      then 'active_assignment_terminal_claim'
    when pba.assignment_status='assigned'
      and cdc.crop_cycle_id is distinct from lineage.primary_crop_cycle_id
      then 'claim_lineage_mismatch'
    when pba.assignment_status='assigned'
      and cdc.destination_object_id is distinct from pba.object_id
      then 'claim_destination_mismatch'
    when pba.assignment_status='assigned'
      and parsed.planned_seedlings is not null
      and (
        cdc.claimed_quantity is distinct from parsed.planned_seedlings
        or cdc.unit is distinct from 'seedlings'
      )
      then 'claim_quantity_mismatch'
    when pba.assignment_status in ('released','cancelled') and cdc.status='active'
      then 'terminal_assignment_active_claim'
    else 'aligned'
  end as projection_state
from atlas.production_bed_assignments pba
left join lateral (
  select case
    when nullif(btrim(coalesce(pba.metadata->>'planned_seedlings','')),'')
         ~ '^[0-9]+([.][0-9]+)?
  on cdc.farm_id=pba.farm_id
 and cdc.idempotency_key=
   atlas.production_bed_assignment_destination_claim_key_v1(pba.id);

revoke all on atlas.production_bed_assignment_destination_claim_audit_v1
from public,anon,authenticated;
grant select on atlas.production_bed_assignment_destination_claim_audit_v1
to service_role;

comment on view atlas.production_bed_assignment_destination_claim_audit_v1 is
'Internal audit of Production Bed Assignment -> canonical crop destination claim projection, including exact primary lineage, destination identity, quantity, authority, and lifecycle alignment.';

-- Backfill current source truth through the same projection seam.
do $backfill$
declare
  r record;
begin
  for r in
    select id
    from atlas.production_bed_assignments
    where assignment_status='assigned'
    order by id
  loop
    perform atlas.sync_production_bed_assignment_destination_claim_v1(r.id);
  end loop;
end;
$backfill$;

do $verification$
begin
  if exists(
    select 1
    from atlas.production_bed_assignment_destination_claim_audit_v1
    where assignment_status='assigned'
      and projection_state<>'aligned'
  ) then
    raise exception 'Active Production Bed Assignment destination projection remains unresolved after backfill.'
      using errcode='55000';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.sync_production_bed_assignment_destination_claim_v1(uuid)',
       'EXECUTE'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.production_bed_assignment_destination_claim_audit_v1',
       'SELECT'
     ) then
    raise exception 'Internal Production destination projection leaked to authenticated.';
  end if;

  if not has_function_privilege(
       'service_role',
       'atlas.sync_production_bed_assignment_destination_claim_v1(uuid)',
       'EXECUTE'
     )
     or not has_table_privilege(
       'service_role',
       'atlas.production_bed_assignment_destination_claim_audit_v1',
       'SELECT'
     ) then
    raise exception 'Service role cannot inspect/repair Production destination projection.';
  end if;

  if not exists(
    select 1
    from pg_trigger
    where tgrelid='atlas.production_bed_assignments'::regclass
      and tgname='p1_sync_production_bed_assignment_destination_claim_v1'
      and not tgisinternal
  ) then
    raise exception 'Production Bed Assignment destination projection trigger is absent.';
  end if;
end;
$verification$;

commit;

      then (pba.metadata->>'planned_seedlings')::numeric
    else null
  end as planned_seedlings
) parsed on true
left join lateral (
  select
    count(*)::integer as primary_count,
    (array_agg(plc.crop_cycle_id order by plc.crop_cycle_id))[1]
      as primary_crop_cycle_id
  from atlas.production_lot_crop_cycles plc
  where plc.production_lot_id=pba.production_lot_id
    and plc.relation_role='primary'
    and plc.confidence='confirmed'
) lineage on true
left join atlas.crop_destination_claims cdc
  on cdc.farm_id=pba.farm_id
 and cdc.idempotency_key=
   atlas.production_bed_assignment_destination_claim_key_v1(pba.id);

revoke all on atlas.production_bed_assignment_destination_claim_audit_v1
from public,anon,authenticated;
grant select on atlas.production_bed_assignment_destination_claim_audit_v1
to service_role;

comment on view atlas.production_bed_assignment_destination_claim_audit_v1 is
'Internal audit of Production Bed Assignment -> canonical crop destination claim projection, including exact primary lineage, destination identity, quantity, authority, and lifecycle alignment.';

-- Backfill current source truth through the same projection seam.
do $backfill$
declare
  r record;
begin
  for r in
    select id
    from atlas.production_bed_assignments
    where assignment_status='assigned'
    order by id
  loop
    perform atlas.sync_production_bed_assignment_destination_claim_v1(r.id);
  end loop;
end;
$backfill$;

do $verification$
begin
  if exists(
    select 1
    from atlas.production_bed_assignment_destination_claim_audit_v1
    where assignment_status='assigned'
      and projection_state<>'aligned'
  ) then
    raise exception 'Active Production Bed Assignment destination projection remains unresolved after backfill.'
      using errcode='55000';
  end if;

  if has_function_privilege(
       'authenticated',
       'atlas.sync_production_bed_assignment_destination_claim_v1(uuid)',
       'EXECUTE'
     )
     or has_table_privilege(
       'authenticated',
       'atlas.production_bed_assignment_destination_claim_audit_v1',
       'SELECT'
     ) then
    raise exception 'Internal Production destination projection leaked to authenticated.';
  end if;

  if not has_function_privilege(
       'service_role',
       'atlas.sync_production_bed_assignment_destination_claim_v1(uuid)',
       'EXECUTE'
     )
     or not has_table_privilege(
       'service_role',
       'atlas.production_bed_assignment_destination_claim_audit_v1',
       'SELECT'
     ) then
    raise exception 'Service role cannot inspect/repair Production destination projection.';
  end if;

  if not exists(
    select 1
    from pg_trigger
    where tgrelid='atlas.production_bed_assignments'::regclass
      and tgname='p1_sync_production_bed_assignment_destination_claim_v1'
      and not tgisinternal
  ) then
    raise exception 'Production Bed Assignment destination projection trigger is absent.';
  end if;
end;
$verification$;

commit;
