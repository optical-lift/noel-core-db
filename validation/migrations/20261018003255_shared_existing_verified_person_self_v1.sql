-- Disposable clone postconditions only: permissions and callable surface.
DO $assert$
BEGIN
  IF to_regprocedure('atlas.admit_existing_verified_person_self_api_v1()') IS NULL
     OR to_regprocedure('public.admit_existing_verified_person_self_api_v1()') IS NULL THEN
    RAISE EXCEPTION 'Verified-person admission functions missing';
  END IF;
  IF NOT (
    SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='atlas'
      AND p.proname='admit_existing_verified_person_self_api_v1'
      AND p.pronargs=0
  ) THEN
    RAISE EXCEPTION 'Internal self-only admission must enforce Auth inside governed boundary';
  END IF;
  IF (
    SELECT p.prosecdef FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='admit_existing_verified_person_self_api_v1'
      AND p.pronargs=0
  ) THEN
    RAISE EXCEPTION 'Public transport cannot be security definer';
  END IF;
  IF has_function_privilege('anon',
      'public.admit_existing_verified_person_self_api_v1()','EXECUTE')
    OR has_function_privilege('anon',
      'atlas.admit_existing_verified_person_self_api_v1()','EXECUTE') THEN
    RAISE EXCEPTION 'Anonymous Person admission execution allowed';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'public.admit_existing_verified_person_self_api_v1()','EXECUTE')
    OR NOT has_function_privilege('authenticated',
      'atlas.admit_existing_verified_person_self_api_v1()','EXECUTE') THEN
    RAISE EXCEPTION 'Authenticated self-only Person admission transport unavailable';
  END IF;
END
$assert$;
