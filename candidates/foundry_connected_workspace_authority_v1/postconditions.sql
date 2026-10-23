-- Gate 1 candidate validation ONLY after applying candidate.sql to a
-- disposable production-schema clone. No writes. Not a production script.
DO $assert$
DECLARE
  v_oid oid;
BEGIN
  SELECT c.oid INTO v_oid FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='foundry' AND c.relname='workspace_authority_registry_v1'
    AND c.relkind='r';
  IF v_oid IS NULL THEN RAISE EXCEPTION 'missing private Foundry authority registry'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=v_oid) THEN
    RAISE EXCEPTION 'Foundry registry RLS disabled';
  END IF;
  IF has_table_privilege('anon',v_oid,'SELECT') OR
     has_table_privilege('anon',v_oid,'INSERT') OR
     has_table_privilege('authenticated',v_oid,'SELECT') OR
     has_table_privilege('authenticated',v_oid,'INSERT') OR
     has_table_privilege('service_role',v_oid,'SELECT') OR
     has_table_privilege('service_role',v_oid,'INSERT') THEN
    RAISE EXCEPTION 'unexpected direct client/service_role access';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policy WHERE polrelid=v_oid) THEN
    RAISE EXCEPTION 'a direct table policy was added without authorization review';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid=v_oid AND contype='f'
      AND pg_get_constraintdef(oid) LIKE '%atlas.principals%'
  ) THEN
    RAISE EXCEPTION 'missing canonical Principal custody FK';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid=v_oid AND contype='u'
      AND pg_get_constraintdef(oid) LIKE '%owner_principal_id%'
      AND pg_get_constraintdef(oid) LIKE '%creation_request_id%'
  ) THEN
    RAISE EXCEPTION 'missing owner-scoped idempotent creation uniqueness';
  END IF;
  IF (SELECT count(*) FROM foundry.workspace_authority_registry_v1)<>0 THEN
    RAISE EXCEPTION 'candidate created/backfilled registry rows unexpectedly';
  END IF;
  IF to_regclass('foundry.events') IS NULL OR to_regclass('foundry.snapshots') IS NULL THEN
    RAISE EXCEPTION 'historical Foundry persistence missing';
  END IF;
END
$assert$;
