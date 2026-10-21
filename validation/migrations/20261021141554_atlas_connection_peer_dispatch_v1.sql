-- Structural and permission postconditions against disposable schema clone.
do $check$
declare v_guard text;v_respond text;
begin
 if to_regclass('atlas.ledger_person_dispatches') is null then
  raise exception 'Connected Ledger dispatch source missing';end if;
 if not exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='atlas' and c.relname='ledger_person_dispatches' and c.relrowsecurity)
  then raise exception 'Dispatch source must enforce RLS';end if;
 if has_table_privilege('authenticated','atlas.ledger_person_dispatches','SELECT')
   or has_table_privilege('authenticated','atlas.ledger_person_dispatches','INSERT')
   or has_table_privilege('anon','atlas.ledger_person_dispatches','SELECT')
  then raise exception 'Direct dispatch table exposure is prohibited';end if;
 if to_regprocedure('atlas.connected_ledger_person_choices_self_api_v1(uuid,integer,uuid)') is null
  or to_regprocedure('atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)') is null
  or to_regprocedure('atlas.connected_ledger_inbox_self_api_v1(integer)') is null
  or to_regprocedure('atlas.connected_ledger_respond_self_api_v1(uuid,text)') is null
  then raise exception 'Universal Ledger sender/inbox/receiver API incomplete';end if;
 if has_function_privilege('anon','atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)','EXECUTE')
  or has_function_privilege('anon','atlas.connected_ledger_respond_self_api_v1(uuid,text)','EXECUTE')
  or not has_function_privilege('authenticated','atlas.connected_ledger_send_self_api_v1(uuid,uuid,text,text,text)','EXECUTE')
  then raise exception 'Connection API caller grants not correctly restricted';end if;
 select pg_get_functiondef('atlas.guard_work_allocation_responsibility_establishment_v2()'::regprocedure)
 into v_guard;
 if position('o.offered_by_membership_id is not distinct from new.assigned_by_membership_id' in v_guard)=0
  then raise exception 'Person offer guard still requires invented organization membership';end if;
 select pg_get_functiondef('atlas.connected_ledger_respond_self_api_v1(uuid,text)'::regprocedure)
 into v_respond;
 if position('atlas.establish_connected_person_company_work_from_offer_v1' in v_respond)=0
  or position('recipient_self_accepted' in v_respond)=0
  then raise exception 'Recipient acceptance does not establish the canonical Work carrier';end if;
 if (select is_nullable from information_schema.columns
   where table_schema='atlas' and table_name='company_work_initial_responsibility_offers'
    and column_name='offered_by_membership_id') <> 'YES'
  then raise exception 'Legacy sender membership still mandatory';end if;
 if not exists(select 1 from pg_constraint
   where conrelid='atlas.company_work_native_ledger_relevance'::regclass
    and conname='company_work_native_ledger_relevance_evidence_kind_check'
    and pg_get_constraintdef(oid) like '%participant_attested%')
  then raise exception 'Connected Person source evidence must remain distinct from owner attestation';end if;

 if position('participant_attested' in pg_get_functiondef(
   'atlas.company_work_accountability_native_ledger_self_api_v1(uuid,uuid,text,integer,uuid)'::regprocedure))=0
   or position('participant_attested' in pg_get_functiondef(
   'atlas.company_work_native_ledger_scope_self_api_v1(uuid,uuid,integer,uuid)'::regprocedure))=0
   or position('participant_attested' in pg_get_functiondef(
   'atlas.owner_set_connected_person_work_day_self_api_v1(uuid,uuid,date,text)'::regprocedure))=0
   or position('participant_attested' in pg_get_functiondef(
   'atlas.owner_native_ledger_blocker_detail_self_api_v1(uuid,uuid)'::regprocedure))=0
 then raise exception 'Accepted peer Work must appear in exact native Ledger projections';end if;
 if position('participant_authored_receiver_accepted' in pg_get_functiondef(
  'atlas.establish_connected_person_company_work_from_offer_v1(uuid,text,text,uuid)'::regprocedure))=0
 then raise exception 'Peer consent evidence must not be mislabeled owner attestation';end if;
end$check$;
