-- Post-migration, SELECT-only SQL contract assertions.
-- Execute after migration 20261026040500 has been applied in an approved
-- environment. No user records, tasks, notes, grants or sessions are created.
-- This does NOT substitute for signed two-Person behavioral acceptance.
begin;
do $assert$
declare
 v_atlas_writer oid:=to_regprocedure('atlas.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)');
 v_atlas_reader oid:=to_regprocedure('atlas.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)');
 v_public_writer oid:=to_regprocedure('public.record_ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,text,text)');
 v_public_reader oid:=to_regprocedure('public.ledger_event_progress_self_api_v1(uuid,uuid,uuid,uuid,timestamptz,uuid,uuid)');
 v_table oid:=to_regclass('atlas.ledger_event_progress_notes_v1');
 v_rls boolean;
 v_priv record;
begin
 if v_table is null or v_atlas_writer is null or v_atlas_reader is null
    or v_public_writer is null or v_public_reader is null then
   raise exception 'Original Event progress source not fully installed';
 end if;
 select relrowsecurity into v_rls from pg_catalog.pg_class where oid=v_table;
 if v_rls is distinct from true then
   raise exception 'Progress note table does not have RLS enabled';
 end if;
 if pg_catalog.has_table_privilege('anon',v_table,'SELECT') or
    pg_catalog.has_table_privilege('anon',v_table,'INSERT') or
    pg_catalog.has_table_privilege('authenticated',v_table,'SELECT') or
    pg_catalog.has_table_privilege('authenticated',v_table,'INSERT') or
    pg_catalog.has_table_privilege('authenticated',v_table,'UPDATE') or
    pg_catalog.has_table_privilege('authenticated',v_table,'DELETE') then
   raise exception 'Raw Event note table must not be accessible from browsers';
 end if;
 for v_priv in select * from (
   values ('internal writer'::text,v_atlas_writer,true),
          ('internal reader',v_atlas_reader,true),
          ('public writer',v_public_writer,false),
          ('public reader',v_public_reader,false)
 ) checks(label,oid,should_be_definer) loop
    if (select prosecdef from pg_catalog.pg_proc where oid=v_priv.oid)
       is distinct from v_priv.should_be_definer then
      raise exception 'Function privilege boundary mismatch: %',v_priv.label;
    end if;
    if pg_catalog.has_function_privilege('anon',v_priv.oid,'EXECUTE') then
      raise exception 'Anonymous caller can access Event progress function: %',v_priv.label;
    end if;
    if not pg_catalog.has_function_privilege('authenticated',v_priv.oid,'EXECUTE') then
      raise exception 'Authenticated forwarding chain blocked: %',v_priv.label;
    end if;
 end loop;
 if (select count(*) from pg_catalog.pg_constraint
     where conrelid=v_table and contype='u' and
     pg_catalog.pg_get_constraintdef(oid) like
       '%(ledger_id, occurrence_id, source_action_id)%')<>1 then
   raise exception 'Stable original Event note identity constraint missing';
 end if;
 if (select count(*) from pg_catalog.pg_constraint
     where conrelid=v_table and contype='c' and
     pg_catalog.pg_get_constraintdef(oid) like '%body%')<1 then
   raise exception 'Bounded progress text constraint missing';
 end if;
end
$assert$;
rollback;
