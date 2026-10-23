-- Read-only postconditions after the candidate is applied to a disposable clone.
do $check$
declare a integer; h integer; f text;
begin
 select count(*) into a from atlas.principals where status='active' and user_id is not null;
 select count(*) into h from atlas.notebook_spread_instances s join atlas.principals p on p.id=s.principal_id
 where p.status='active' and p.user_id is not null and s.spread_key='personal.health'
 and s.scope_kind='person' and s.scope_id=p.user_id::text and s.subject_domain='health'
 and s.subject_kind='person_body' and s.subject_id=p.id::text and s.purpose_key='collection'
 and s.horizon_key='permanent' and s.spread_state='open';
 if a<>h then raise exception 'Health Collection seeding incomplete'; end if;
 if not (select relrowsecurity from pg_class where oid='atlas.person_collection_filing_events_v1'::regclass)
 then raise exception 'Event table missing RLS'; end if;
 if has_table_privilege('authenticated','atlas.person_collection_filing_events_v1','SELECT')
 or has_table_privilege('anon','atlas.person_collection_filing_events_v1','SELECT')
 then raise exception 'Private event table exposed'; end if;
 foreach f in array array['person_collections_self_api_v1()',
 'person_file_capture_self_api_v1(uuid,uuid)',
 'person_collection_sources_self_api_v1(uuid,integer)',
 'person_today_filing_receipts_self_api_v1(date)'] loop
 if not has_function_privilege('authenticated',('public.'||f)::regprocedure,'EXECUTE')
 then raise exception 'Authenticated wrapper EXECUTE missing for %',f; end if;
 if has_function_privilege('anon',('public.'||f)::regprocedure,'EXECUTE')
 then raise exception 'Anonymous EXECUTE exposed for %',f; end if;
 if has_function_privilege('authenticated',('atlas.'||f)::regprocedure,'EXECUTE')
 then raise exception 'Private inner function executable for %',f; end if;
 end loop;
 if not exists(select 1 from pg_trigger where tgrelid='atlas.principals'::regclass
 and tgname='person_health_collection_on_principal_v1' and not tgisinternal)
 then raise exception 'New-principal seed trigger absent'; end if;
 if not exists(select 1 from pg_trigger where tgrelid='atlas.person_collection_filing_events_v1'::regclass
 and tgname='person_collection_events_immutable_v1' and not tgisinternal)
 then raise exception 'Immutable event trigger absent'; end if;
end;
$check$;
select 'atlas_person_health_collections_filing_v1' as candidate, 'metadata_postconditions_passed' as standing;
