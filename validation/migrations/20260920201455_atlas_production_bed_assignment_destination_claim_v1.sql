-- Behavioral postconditions for Production Bed Assignment -> destination claim projection v1.

do $proof$
declare
  v_prior text:=current_setting('atlas.production_reconciler_active',true);
  v_claim_id uuid;
  v_claim_count integer;
  v_coverage jsonb;
  v_failed boolean:=false;
begin
  -- Keep this proof focused on destination projection. Existing zz_ Production
  -- work reconciliation is independently governed and is suppressed for fixture writes.
  perform set_config('atlas.production_reconciler_active','on',true);

  -- 1. Owner-checkpoint Bed Assignment creates one quantified Principal claim.
  insert into atlas.production_bed_assignments(
    id,farm_id,production_lot_id,requirement_id,object_id,
    quantity_assigned,unit,planned_transplant_date,expected_release_date,
    assignment_status,source,metadata
  ) values(
    'f1a00000-0000-4000-8000-000000000001'::uuid,
    'f1200000-0000-4000-8000-000000000001'::uuid,
    'f1700000-0000-4000-8000-000000000001'::uuid,
    'f1900000-0000-4000-8000-000000000001'::uuid,
    'f1300000-0000-4000-8000-000000000002'::uuid,
    4,
    'bed_ft',
    current_date+5,
    current_date+30,
    'assigned',
    'owner_checkpoint_20260829',
    jsonb_build_object(
      'validation_fixture',true,
      'planned_seedlings',100,
      'window_end',(current_date+10)::text,
      'source_path','/fixture/owner-checkpoint.md'
    )
  );

  select id into v_claim_id
  from atlas.crop_destination_claims
  where farm_id='f1200000-0000-4000-8000-000000000001'::uuid
    and idempotency_key=
      'production-bed-assignment:f1a00000-0000-4000-8000-000000000001:destination-claim';

  if v_claim_id is null then
    raise exception 'Assigned Production Bed Assignment did not create canonical destination claim.';
  end if;

  if not exists(
    select 1
    from atlas.crop_destination_claims c
    where c.id=v_claim_id
      and c.crop_cycle_id='f1500000-0000-4000-8000-000000000001'::uuid
      and c.destination_object_id='f1300000-0000-4000-8000-000000000002'::uuid
      and c.status='active'
      and c.claimed_quantity=100
      and c.unit='seedlings'
      and c.claim_strength='committed'
      and c.displacement_authority='principal'
      and c.required_by=current_date+5
      and c.window_start=current_date+5
      and c.window_end=current_date+10
      and c.source_evidence->>'productionBedAssignmentId'
        ='f1a00000-0000-4000-8000-000000000001'
      and c.source_evidence->>'bedUnit'='bed_ft'
      and coalesce((c.source_evidence->>'bedFeetAreNotPlantQuantity')::boolean,false)
  ) then
    raise exception 'Owner-authoritative Production Bed Assignment claim projection is incomplete.';
  end if;

  v_coverage:=atlas.crop_destination_claim_coverage_v1(
    'f1500000-0000-4000-8000-000000000001'::uuid
  );
  if v_coverage->>'coverageState'<>'complete'
     or (v_coverage->>'claimedMoveQuantity')::numeric<>100 then
    raise exception 'Projected destination claim did not satisfy quantified crop coverage.';
  end if;

  -- 2. Source update mutates the same claim, not a duplicate.
  update atlas.production_bed_assignments
  set metadata=metadata||jsonb_build_object('planned_seedlings',80)
  where id='f1a00000-0000-4000-8000-000000000001'::uuid;

  select count(*)::integer into v_claim_count
  from atlas.crop_destination_claims
  where farm_id='f1200000-0000-4000-8000-000000000001'::uuid
    and idempotency_key=
      'production-bed-assignment:f1a00000-0000-4000-8000-000000000001:destination-claim';

  if v_claim_count<>1
     or not exists(
       select 1 from atlas.crop_destination_claims
       where id=v_claim_id
         and claimed_quantity=80
         and unit='seedlings'
     ) then
    raise exception 'Bed Assignment update duplicated or failed to update its exact projected claim.';
  end if;

  v_coverage:=atlas.crop_destination_claim_coverage_v1(
    'f1500000-0000-4000-8000-000000000001'::uuid
  );
  if v_coverage->>'coverageState'<>'partial' then
    raise exception 'Updated 80-seedling allocation did not become partial against 100-seedling cohort.';
  end if;

  -- 3. Released source terminalizes exact claim and removes active coverage.
  update atlas.production_bed_assignments
  set assignment_status='released'
  where id='f1a00000-0000-4000-8000-000000000001'::uuid;

  if not exists(
    select 1 from atlas.crop_destination_claims
    where id=v_claim_id
      and status='released'
      and released_at is not null
  ) then
    raise exception 'Released Bed Assignment did not release its exact canonical claim.';
  end if;

  v_coverage:=atlas.crop_destination_claim_coverage_v1(
    'f1500000-0000-4000-8000-000000000001'::uuid
  );
  if v_coverage->>'coverageState'<>'missing' then
    raise exception 'Released projected claim still counts as active destination coverage.';
  end if;

  -- 4. Terminal claims may not be silently resurrected.
  begin
    update atlas.production_bed_assignments
    set assignment_status='assigned'
    where id='f1a00000-0000-4000-8000-000000000001'::uuid;
  exception when sqlstate '23514' then
    v_failed:=true;
  end;

  if not v_failed
     or (select assignment_status
         from atlas.production_bed_assignments
         where id='f1a00000-0000-4000-8000-000000000001'::uuid)<>'released' then
    raise exception 'Terminal projected claim was silently resurrected.';
  end if;

  -- 5. Non-owner source receives no Principal authority.
  insert into atlas.production_bed_assignments(
    id,farm_id,production_lot_id,requirement_id,object_id,
    quantity_assigned,unit,planned_transplant_date,
    assignment_status,source,metadata
  ) values(
    'f1a00000-0000-4000-8000-000000000002'::uuid,
    'f1200000-0000-4000-8000-000000000001'::uuid,
    'f1700000-0000-4000-8000-000000000001'::uuid,
    'f1900000-0000-4000-8000-000000000001'::uuid,
    'f1300000-0000-4000-8000-000000000003'::uuid,
    2,
    'bed_ft',
    current_date+5,
    'assigned',
    'capacity_planner',
    '{"validation_fixture":true,"planned_seedlings":10}'::jsonb
  );

  if not exists(
    select 1
    from atlas.crop_destination_claims c
    where c.idempotency_key=
      'production-bed-assignment:f1a00000-0000-4000-8000-000000000002:destination-claim'
      and c.status='active'
      and c.claimed_quantity=10
      and c.unit='seedlings'
      and c.claim_strength='planned'
      and c.displacement_authority='farm_operations'
  ) then
    raise exception 'Non-owner Production assignment inherited excessive claim authority.';
  end if;

  -- 6. Deleting an assignment cannot orphan an active projected claim.
  delete from atlas.production_bed_assignments
  where id='f1a00000-0000-4000-8000-000000000002'::uuid;

  if not exists(
    select 1
    from atlas.crop_destination_claims c
    where c.idempotency_key=
      'production-bed-assignment:f1a00000-0000-4000-8000-000000000002:destination-claim'
      and c.status='cancelled'
      and c.released_at is not null
      and coalesce((c.source_evidence->>'sourceAssignmentDeleted')::boolean,false)
  ) then
    raise exception 'Deleted Bed Assignment orphaned an active destination claim.';
  end if;

  -- 7. Ambiguous primary lineage fails closed before a claim can be invented.
  insert into atlas.crop_cycles(
    id,farm_id,object_id,crop_profile_id,crop_cycle_key,crop_label,variety,
    cycle_state,lifecycle_status,coverage_kind,coverage_amount,coverage_unit,metadata
  ) values(
    'f1500000-0000-4000-8000-000000000002'::uuid,
    'f1200000-0000-4000-8000-000000000001'::uuid,
    'f1300000-0000-4000-8000-000000000001'::uuid,
    'f1400000-0000-4000-8000-000000000001'::uuid,
    'destination_projection_fixture_cycle_ambiguous',
    'Snapdragon',
    'Ambiguous Fixture',
    'seedling_care',
    'active',
    'viable_seedlings',
    25,
    'seedlings',
    '{"validation_fixture":true}'::jsonb
  );

  insert into atlas.production_lot_crop_cycles(
    id,production_lot_id,crop_cycle_id,relation_role,confidence,source,metadata
  ) values(
    'f1800000-0000-4000-8000-000000000002'::uuid,
    'f1700000-0000-4000-8000-000000000001'::uuid,
    'f1500000-0000-4000-8000-000000000002'::uuid,
    'primary',
    'confirmed',
    'validation_fixture',
    '{"validation_fixture":true}'::jsonb
  );

  v_failed:=false;
  begin
    insert into atlas.production_bed_assignments(
      id,farm_id,production_lot_id,requirement_id,object_id,
      quantity_assigned,unit,planned_transplant_date,
      assignment_status,source,metadata
    ) values(
      'f1a00000-0000-4000-8000-000000000003'::uuid,
      'f1200000-0000-4000-8000-000000000001'::uuid,
      'f1700000-0000-4000-8000-000000000001'::uuid,
      'f1900000-0000-4000-8000-000000000001'::uuid,
      'f1300000-0000-4000-8000-000000000003'::uuid,
      1,
      'bed_ft',
      current_date+5,
      'assigned',
      'capacity_planner',
      '{"validation_fixture":true,"planned_seedlings":5}'::jsonb
    );
  exception when sqlstate '23514' then
    v_failed:=true;
  end;

  if not v_failed
     or exists(
       select 1 from atlas.production_bed_assignments
       where id='f1a00000-0000-4000-8000-000000000003'::uuid
     )
     or exists(
       select 1 from atlas.crop_destination_claims
       where idempotency_key=
         'production-bed-assignment:f1a00000-0000-4000-8000-000000000003:destination-claim'
     ) then
    raise exception 'Ambiguous Production Lot lineage did not fail destination projection closed.';
  end if;

  -- 8. Audit / privilege / trigger-order contract.
  if exists(
    select 1
    from atlas.production_bed_assignment_destination_claim_audit_v1
    where assignment_id='f1a00000-0000-4000-8000-000000000001'::uuid
      and projection_state='terminal_assignment_active_claim'
  ) then
    raise exception 'Terminal assignment audit still sees an active claim.';
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
    raise exception 'Internal destination projection leaked to authenticated.';
  end if;

  if not exists(
    select 1
    from pg_trigger
    where tgrelid='atlas.production_bed_assignments'::regclass
      and tgname='p1_sync_production_bed_assignment_destination_claim_v1'
      and not tgisinternal
  ) then
    raise exception 'Destination projection trigger is absent.';
  end if;

  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
exception when others then
  perform set_config('atlas.production_reconciler_active',coalesce(v_prior,''),true);
  raise;
end;
$proof$;
