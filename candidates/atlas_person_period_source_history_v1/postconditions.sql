-- Clone-only, read-only catalog checks after protected candidate application.
select n.nspname,p.proname,pg_get_function_identity_arguments(p.oid) as args,
  p.prosecdef, p.provolatile
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where p.proname='person_period_source_history_self_api_v1'
and n.nspname in ('atlas','public');
-- Signed-user end-to-end and cross-person negative cases require real sessions.
-- No public test inserts, no owner identity spoofing, no fabricated production records.
