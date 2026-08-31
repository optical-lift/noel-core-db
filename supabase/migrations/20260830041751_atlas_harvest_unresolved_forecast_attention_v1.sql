do $$
declare
  v_before text;
  v_after text;
begin
  v_before := pg_get_viewdef('atlas.crop_cycle_yield_forecast'::regclass, true);
  v_after := replace(
    v_before,
    E'    forecast_state,\n    known_removed_stems,',
    E'    CASE\n        WHEN unresolved_harvest_depletion_events > 0 THEN ''assessment_required''::text\n        ELSE forecast_state\n    END AS forecast_state,\n    known_removed_stems,'
  );

  if v_after = v_before then
    raise exception 'crop_cycle_yield_forecast final forecast_state marker not found';
  end if;

  execute 'create or replace view atlas.crop_cycle_yield_forecast as ' || v_after;
end
$$;

comment on view atlas.crop_cycle_yield_forecast is
  'Canonical active crop-cycle yield forecast. Known harvest removals deplete expected stems; unresolved harvest quantity forces forecast_state=assessment_required so every client surfaces uncertainty instead of presenting unresolved supply as confident.';