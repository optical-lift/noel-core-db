-- HELD Us Carry v3 increment A: DB privilege floor only.
-- Apply ONLY after original Us finance + Carry v1 + dated-event v2 in a disposable DB.
-- NOT a release migration. This deliberately makes the existing Python adoption
-- writer unable to seal until the separate server-derived v3 writer is complete.
-- No owner/stream identity is accepted here, and no financial data is changed.
BEGIN;

DO $gate$
BEGIN
  IF pg_catalog.to_regclass('us.financial_expectation_revisions') IS NULL
    OR pg_catalog.to_regclass('us.financial_expectation_lines') IS NULL
    OR pg_catalog.to_regclass('us.carry_case_events_v1') IS NULL
    OR pg_catalog.to_regprocedure(
      'us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)'
    ) IS NULL
    OR NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_trigger
       WHERE tgname='carry_forecast_line_event_scope_guard_v2'
         AND tgrelid='us.carry_case_events_v1'::pg_catalog.regclass
         AND NOT tgisinternal
    )
  THEN
    RAISE EXCEPTION 'Us Carry v3 privilege floor requires intact finance + v1 + v2'
      USING ERRCODE='55000';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='service_role')
  THEN
    RAISE EXCEPTION 'service_role absent from the disposable fixture'
      USING ERRCODE='55000';
  END IF;
END;
$gate$;

-- No direct caller-populated revision or financial lines, including the
-- service_role that may bypass RLS. Privilege grants, not RLS alone, are
-- the security boundary for these two operations.
REVOKE INSERT ON TABLE us.financial_expectation_revisions,
                       us.financial_expectation_lines
  FROM service_role;

-- This v1 SECURITY DEFINER appender permits REVISION_SEALED. A server may no
-- longer call it directly; the eventual v3 adoption writer will retain its
-- own privileged internal ability to append after deriving lines under lock.
REVOKE EXECUTE ON FUNCTION
  us.carry_append_event_v1(uuid,text,text,date,text,text,jsonb,bigint)
  FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
