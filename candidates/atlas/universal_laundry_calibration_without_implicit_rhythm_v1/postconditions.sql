-- Run after candidate in an isolated Atlas schema clone, NOT as a live mutation.
DO $proof$
DECLARE v_sql text;
BEGIN
 SELECT pg_get_functiondef('atlas.calibrate_personal_laundry_kernel_self_api_v1(jsonb)'::regprocedure) INTO v_sql;
 IF v_sql IS NULL THEN RAISE EXCEPTION 'Laundry calibration function absent'; END IF;
 IF strpos(v_sql,'principal_upsert_household_rhythm_api_v1')<>0 THEN
   RAISE EXCEPTION 'Calibration must never write a Household Rhythm';
 END IF;
 IF strpos(v_sql,'insert into atlas.household_kernel_instances')=0 THEN
   RAISE EXCEPTION 'Arrangement calibration no longer writes its legitimate instance';
 END IF;
 IF strpos(v_sql,'''contractVersion'', ''household_laundry_calibration_v1''')=0 THEN
   RAISE EXCEPTION 'Existing signed client calibration receipt changed without contract review';
 END IF;
END
$proof$;
