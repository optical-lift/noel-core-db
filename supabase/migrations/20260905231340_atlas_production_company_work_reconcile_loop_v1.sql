create or replace function atlas.reconcile_production_company_work_v1(
  p_production_lot_id uuid,
  p_as_of_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','atlas'
as $function$
declare
  v_lot atlas.production_lots%rowtype;
  v_assignment record;
  v_result jsonb;
  v_work jsonb:='[]'::jsonb;
  v_closed jsonb:='[]'::jsonb;
  v_stale record;
  v_requirement_id uuid;
  v_ledger jsonb;
  v_ledger_id uuid;
begin
  if p_production_lot_id is null then
    raise exception 'Production lot is required.' using errcode='22023';
  end if;

  select * into v_lot from atlas.production_lots where id=p_production_lot_id;
  if v_lot.id is null then
    raise exception 'Production lot was not found.' using errcode='P0002';
  end if;

  -- Admit each active assignment exactly once. Capacity eligibility belongs to the
  -- assignment materializer, which can resolve a direct or lot-level requirement
  -- and return capacity_not_resolved without creating Work.
  for v_assignment in
    select a.id
    from atlas.production_bed_assignments a
    where a.production_lot_id=v_lot.id
      and a.assignment_status='assigned'
    order by a.created_at,a.id
  loop
    v_result:=atlas.materialize_production_bed_preparation_company_work_v1(v_assignment.id,p_as_of_date);
    v_work:=v_work||jsonb_build_array(v_result);
  end loop;

  for v_stale in
    select wi.id as work_item_id,wi.organization_id,wi.organization_unit_id,wi.source_object_id,
           wi.title,wi.metadata
    from atlas.work_items wi
    where wi.source_object_type='production_bed_assignment'
      and wi.work_state='open'
      and wi.metadata->>'productionLotId'=v_lot.id::text
      and not exists(
        select 1
        from atlas.production_bed_assignments a
        where a.id=wi.source_object_id
          and a.production_lot_id=v_lot.id
          and a.assignment_status='assigned'
      )
  loop
    update atlas.work_items
    set work_state='cancelled',cancelled_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1','sourceRequirementActive',false)
    where id=v_stale.work_item_id and work_state='open';

    update atlas.work_requirements r
    set state='cancelled',cancelled_at=now(),updated_at=now(),
        metadata=r.metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1','sourceRequirementActive',false)
    from atlas.work_requirement_links l
    where l.work_item_id=v_stale.work_item_id
      and l.requirement_id=r.id
      and l.active
      and r.state='active';

    update atlas.work_time_contracts
    set contract_state='cancelled',updated_at=now(),
        metadata=metadata||jsonb_build_object('cancelledBy','reconcile_production_company_work_v1')
    where work_item_id=v_stale.work_item_id and contract_state='active';

    update atlas.work_execution_adapters
    set state='retired',retired_at=now(),updated_at=now(),
        metadata=metadata||jsonb_build_object('retirementReason','production_source_requirement_closed')
    where work_item_id=v_stale.work_item_id and state='active';

    select l.requirement_id into v_requirement_id
    from atlas.work_requirement_links l
    where l.work_item_id=v_stale.work_item_id and l.active
    order by l.created_at
    limit 1;

    v_ledger:=atlas.project_organization_ledger_event_internal_v1(
      v_stale.organization_id,
      v_stale.organization_unit_id,
      'production:bed-preparation-closed:'||v_stale.source_object_id::text,
      'production',
      'bed_preparation_requirement_closed',
      'production_bed_assignment:'||v_stale.source_object_id::text||':bed_preparation_closed',
      now(),
      v_stale.title,
      'Production no longer establishes this bed-preparation requirement.',
      'established','closed',
      jsonb_build_object(
        'productionLotId',v_lot.id,
        'productionBedAssignmentId',v_stale.source_object_id,
        'workRequirementId',v_requirement_id,
        'workItemId',v_stale.work_item_id,
        'workState','cancelled'
      ),
      jsonb_build_object(
        'sourceDomainAuthority','production',
        'projectedBy','reconcile_production_company_work_v1'
      ),
      jsonb_build_object('companyWorkItemId',v_stale.work_item_id),
      now()
    );
    v_ledger_id:=nullif(v_ledger->>'entryId','')::uuid;
    if v_ledger_id is not null then
      perform atlas.link_organization_ledger_subject_internal_v1(
        v_ledger_id,'production','production_bed_assignment',v_stale.source_object_id::text,'source',
        jsonb_build_object('sourceDomainAuthority','production'),'{}'::jsonb
      );
      perform atlas.link_organization_ledger_subject_internal_v1(
        v_ledger_id,'work','work_item',v_stale.work_item_id::text,'closed_work',
        jsonb_build_object('authority','company_work'),'{}'::jsonb
      );
    end if;

    v_closed:=v_closed||jsonb_build_array(jsonb_build_object(
      'workItemId',v_stale.work_item_id,
      'sourceAssignmentId',v_stale.source_object_id,
      'ledgerEntryId',v_ledger_id
    ));
  end loop;

  return jsonb_build_object(
    'contractVersion','reconcile_production_company_work_v1',
    'productionLotId',v_lot.id,
    'work',v_work,
    'closed',v_closed
  );
end;
$function$;

revoke all on function atlas.reconcile_production_company_work_v1(uuid,date)
  from public,anon,authenticated;
grant execute on function atlas.reconcile_production_company_work_v1(uuid,date)
  to postgres,service_role;

comment on function atlas.reconcile_production_company_work_v1(uuid,date) is
  'Converges active Production bed assignments into Company Work and Organization Ledger projection; capacity eligibility is adjudicated by the assignment materializer; closes stale source-owned work.';