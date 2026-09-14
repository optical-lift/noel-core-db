-- Atlas Farm 3 portfolio cleanup v1.
-- Farm 3 is historical/test portfolio scope. Preserve the row for history,
-- but remove it from active Principal portfolio projections by setting archived_at.
-- Elm and all other institutional/runtime state remain untouched.

BEGIN;

DO $function$
DECLARE
  v_row atlas.portfolio_units%rowtype;
  v_count integer;
  v_dependents bigint;
BEGIN
  select count(*)
  into v_count
  from atlas.portfolio_units
  where stable_key = 'farm_3'
    and archived_at is null;

  -- The Principal foundation seed may be absent on a clean schema replay.
  -- If so, there is nothing to archive.
  if v_count = 0 then
    return;
  end if;

  if v_count <> 1 then
    raise exception 'Expected exactly one active Farm 3 portfolio row; found %.', v_count
      using errcode = '55000';
  end if;

  select *
  into v_row
  from atlas.portfolio_units
  where stable_key = 'farm_3'
    and archived_at is null;

  if v_row.name <> 'Farm 3'
     or v_row.unit_kind <> 'strategic_option'
     or v_row.lifecycle_state <> 'option'
     or v_row.portfolio_role <> 'future_option'
     or v_row.horizon <> 'H3'
     or v_row.linked_farm_id is not null
     or v_row.organization_unit_id is not null
     or v_row.accountable_operator_id is not null
     or coalesce(v_row.metadata->>'source','') <> 'principal_foundation_seed_v1' then
    raise exception 'Farm 3 portfolio row changed from the audited historical/test seed semantics; refusing cleanup.'
      using errcode = '55000';
  end if;

  select
      (select count(*) from atlas.attention_subjects where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.capital_requests where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.great_game_scorecards where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.house_position_line_items where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.investment_opportunities where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.operating_functions where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.operational_escalations where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.owner_obligations where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.portfolio_theses where portfolio_unit_id = v_row.id)
    + (select count(*) from atlas.principal_authority_allocations where portfolio_unit_id = v_row.id)
  into v_dependents;

  if v_dependents <> 0 then
    raise exception 'Farm 3 has % dependent Principal-domain rows; refusing cleanup.', v_dependents
      using errcode = '55000';
  end if;

  update atlas.portfolio_units
  set archived_at = now(),
      updated_at = now()
  where id = v_row.id
    and archived_at is null;

  if not found then
    raise exception 'Farm 3 archive update did not affect the audited active row.'
      using errcode = '55000';
  end if;
END;
$function$;

COMMIT;
