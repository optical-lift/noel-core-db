-- Postconditions for Atlas Personal Laundry Authority Split v1.
-- These assertions are intentionally identity-free and schema-clone-safe.
-- Live world-kernel row presence is an operational data precondition, not a schema postcondition.

do $$
declare
  v_def text;
  v_comment text;
begin
  select pg_get_functiondef(
    'atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure
  ) into v_def;

  if v_def is null then
    raise exception 'Laundry calibration function is missing.';
  end if;

  if position('principal_upsert_household_rhythm_api_v1' in v_def) > 0 then
    raise exception 'Laundry calibration still carries Household Rhythm write authority.';
  end if;

  if position('rhythmMutation' in v_def) = 0
     or position('calibrationDoesNotCreateRhythm' in v_def) = 0
     or position('calibrationDoesNotAssignPrincipalResponsibility' in v_def) = 0 then
    raise exception 'Laundry calibration authority-boundary return contract is incomplete.';
  end if;

  select obj_description(
    'atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure,
    'pg_proc'
  ) into v_comment;

  if v_comment is null
     or position('creates, modifies, and deletes no Household Rhythm' in v_comment) = 0 then
    raise exception 'Laundry calibration function comment does not preserve the authority split.';
  end if;

end
$$;
