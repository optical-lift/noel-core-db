-- Atlas Waiting Room portfolio cleanup v1.
-- Waiting Room is historical/test scope. Preserve the portfolio row for history,
-- but remove it from active Principal portfolio projections by setting archived_at.
-- Farm 3 and all underlying historical Organization/Farm/Unit records remain untouched.
--
-- The Principal projection UUID is mutable seed data, so this cleanup binds instead
-- to the immutable Waiting Room historical anchors already adjudicated as
-- waiting_room_test_scope by institutional custody reconstruction.

BEGIN;

DO $function$
DECLARE
  v_row atlas.portfolio_units%rowtype;
  v_active_count integer;
  v_updated integer;
BEGIN
  select count(*)::integer
  into v_active_count
  from atlas.portfolio_units
  where stable_key = 'waiting_room'
    and archived_at is null;

  -- A clean schema replay may legitimately contain no production-authored Principal
  -- seed row. In that case there is nothing to archive.
  if v_active_count = 0 then
    return;
  end if;

  if v_active_count <> 1 then
    raise exception 'Expected exactly one active Waiting Room portfolio projection; found %.', v_active_count
      using errcode = '55000';
  end if;

  select *
  into strict v_row
  from atlas.portfolio_units
  where stable_key = 'waiting_room'
    and archived_at is null;

  if v_row.name <> 'Waiting Room'
     or v_row.unit_kind <> 'farm'
     or v_row.lifecycle_state <> 'building'
     or v_row.portfolio_role <> 'emerging_engine'
     or v_row.horizon <> 'H2'
     or v_row.organization_id <> '818b9a23-65e9-4198-b86c-9496ba548642'::uuid
     or v_row.linked_farm_id <> 'f6592422-cf2b-4375-ba8f-f00828a05c18'::uuid
     or v_row.organization_unit_id <> '999569f3-8ae5-4bd0-b74d-f586b6b39d8d'::uuid
     or coalesce(v_row.metadata->>'source','') <> 'principal_foundation_seed_v1' then
    raise exception 'Active Waiting Room projection no longer matches the governed historical test-scope anchors; refusing cleanup.'
      using errcode = '55000';
  end if;

  if not exists (
    select 1
    from atlas.institutional_custody_adjudications a
    where a.subject_schema = 'atlas'
      and a.subject_table = 'farms'
      and a.subject_key = v_row.linked_farm_id::text
      and a.disposition = 'archived'
      and a.historical_organization_id = v_row.organization_id
      and a.evidence_basis = 'waiting_room_test_scope'
      and a.evidence->>'physicalRowPreserved' = 'true'
  ) or not exists (
    select 1
    from atlas.institutional_custody_adjudications a
    where a.subject_schema = 'atlas'
      and a.subject_table = 'organization_units'
      and a.subject_key = v_row.organization_unit_id::text
      and a.disposition = 'archived'
      and a.historical_organization_id = v_row.organization_id
      and a.evidence_basis = 'waiting_room_test_scope'
      and a.evidence->>'physicalRowPreserved' = 'true'
  ) then
    raise exception 'Waiting Room historical anchors are not both immutably adjudicated as archived test scope; refusing cleanup.'
      using errcode = '55000';
  end if;

  if exists (select 1 from atlas.attention_subjects where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.capital_requests where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.great_game_scorecards where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.house_position_line_items where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.investment_opportunities where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.operating_functions where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.operational_escalations where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.owner_obligations where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.portfolio_theses where portfolio_unit_id = v_row.id)
     or exists (select 1 from atlas.principal_authority_allocations where portfolio_unit_id = v_row.id) then
    raise exception 'Waiting Room acquired active Principal-domain dependents after audit; refusing cleanup.'
      using errcode = '55000';
  end if;

  update atlas.portfolio_units
  set archived_at = now()
  where id = v_row.id
    and archived_at is null;

  get diagnostics v_updated = row_count;
  if v_updated <> 1 then
    raise exception 'Waiting Room portfolio cleanup did not archive exactly one row.'
      using errcode = '55000';
  end if;
END;
$function$;

COMMIT;
