-- Candidate clone validation; NEVER execute against production as a migration.
DO $validation$
DECLARE n bigint;
BEGIN
  SELECT count(*) INTO n FROM atlas.company_work_native_ledger_relevance;
  IF n <> 0 THEN
    RAISE EXCEPTION 'Candidate silently backfilled % rows',n;
  END IF;
  IF has_table_privilege('authenticated','atlas.company_work_native_ledger_relevance','SELECT')
    OR has_table_privilege('authenticated','atlas.company_work_native_ledger_relevance','INSERT') THEN
    RAISE EXCEPTION 'Direct authenticated table access is forbidden';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Scope read grant missing';
  END IF;
  IF NOT has_function_privilege('authenticated',
      'atlas.establish_company_work_native_ledger_relevance_self_api_v1(uuid,uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'Attribution command grant missing';
  END IF;
  RAISE NOTICE 'PASS: empty first release; RPC surface; table denied';
END;
$validation$;

-- ADDITIONAL REQUIRED AUTHENTICATED CLONE FIXTURES (not executed by this file):
-- [ ] anonymous denied on all commands and reads
-- [ ] seat-only member denied without both root Principal grants
-- [ ] Elm authorized owner can attach one work ID to both native Flower and Venue
-- [ ] cross-organization Optical Lift / Elm linking denied
-- [ ] Optical Lift owner cannot list Elm Work/unknown pool
-- [ ] later exact duplicate is idempotent without evidence overwrite
-- [ ] mistaken attribution can be withdrawn, keeping evidence/history
-- [ ] work without a link is unknown, not inferred from title/unit
-- [ ] inactive native Ledger / expired native seat / revoked session denied
