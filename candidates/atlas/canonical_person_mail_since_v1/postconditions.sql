-- Run AFTER candidate installation in disposable production-shaped clone.
DO $test$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='atlas'
 AND indexname='communication_mail_person_current_v1')
 THEN RAISE EXCEPTION 'Missing exact endpoint + Person current-decision index'; END IF;
 IF has_table_privilege('authenticated','atlas.communication_person_mail_read_decisions_v1','SELECT')
 OR has_function_privilege('anon','public.person_mail_events_self_v1(uuid,integer,timestamptz)','EXECUTE')
 OR has_function_privilege('anon','public.set_person_mail_read_self_v1(uuid,uuid,uuid,date,text,boolean,uuid,text)','EXECUTE')
 THEN RAISE EXCEPTION 'Mailbox decision/public reader exposed'; END IF;
 IF EXISTS(SELECT 1 FROM atlas.communication_person_mail_read_decisions_v1)
 THEN RAISE EXCEPTION 'Candidate must not provision Person grants implicitly'; END IF;
END $test$;
-- Signed validation is REQUIRED: owner grant/revoke, Katie positive, Marshall
-- negative, absent sign-in, cross-organization denial; date cutoff at
-- 2026-08-28T05:00:00Z and mixed-date thread negative without leaking headers,
-- search, old reader, attachment, origin, preview or cache.
-- Do not release until all source readers/alternate paths are audited.
