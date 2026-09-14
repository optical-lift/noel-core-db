-- Atlas Waiting Room portfolio cleanup v1.
-- Waiting Room is historical/test scope. Preserve the portfolio row for history,
-- but remove it from active Principal portfolio projections by setting archived_at.
-- Farm 3 and all underlying historical Organization/Farm/Unit records remain untouched.

BEGIN;

DO $function$
DECLARE
  v_waiting_room_id constant uuid := '47f8e248-d8fb-408d-a20d-74cf37433945'::uuid;
  v_row atlas.portfolio_units%rowtype;
BEGIN
  select *
  into v_row
  from atlas.portfolio_units
  where id = v_waiting_room_id;

  -- This row is production data rather than schema-seed data, so a clean schema replay
  -- may legitimately not contain it. In that case there is nothing to archive.
  if v_row.id is null then
    if exists (
      select 1
      from atlas.portfolio_units
      where stable_key = 'waiting_room'
        and archived_at is null
    ) then
      raise exception 'An unexpected active Waiting Room portfolio row exists under a different identity.'
        using errcode = '55000';
    end if;
    return;
  end if;

  if v_row.stable_key <> 'waiting_room'
     or v_row.name <> 'Waiting Room'
     or v_row.unit_kind <> 'farm'
     or v_row.lifecycle_state <> 'building'
     or v_row.horizon <> 'H2' then
    raise exception 'Waiting Room portfolio row changed from the audited test-scope identity; refusing cleanup.'
      using errcode = '55000';
  end if;

  update atlas.portfolio_units
  set archived_at = coalesce(archived_at, now()),
      updated_at = now()
  where id = v_waiting_room_id;
END;
$function$;

COMMIT;
