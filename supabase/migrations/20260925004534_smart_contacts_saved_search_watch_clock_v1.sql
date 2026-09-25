create or replace function atlas.run_due_smart_contact_saved_searches_service_v1(
  p_as_of timestamptz default now(),
  p_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_lock_ok boolean;
  v_search record;
  v_result jsonb;
  v_results jsonb:='[]'::jsonb;
  v_run_count integer:=0;
  v_failed_count integer:=0;
begin
  v_lock_ok:=pg_try_advisory_xact_lock(771243001::bigint);

  if not v_lock_ok then
    return jsonb_build_object(
      'ok',true,
      'skipped',true,
      'reason','watch_worker_already_running',
      'runCount',0,
      'failedCount',0,
      'results','[]'::jsonb
    );
  end if;

  for v_search in
    select
      s.id,
      s.organization_id,
      s.name,
      s.stable_key,
      s.watch_cadence,
      s.last_run_at,
      case s.watch_cadence
        when 'hourly' then coalesce(s.last_run_at,s.created_at)+interval '1 hour'
        when 'daily' then coalesce(s.last_run_at,s.created_at)+interval '1 day'
        when 'weekly' then coalesce(s.last_run_at,s.created_at)+interval '7 days'
        else null
      end as due_at
    from atlas.smart_contact_saved_searches s
    where s.search_state='active'
      and s.watch_enabled
      and s.watch_cadence<>'manual'
      and case s.watch_cadence
        when 'hourly' then coalesce(s.last_run_at,s.created_at)+interval '1 hour' <= p_as_of
        when 'daily' then coalesce(s.last_run_at,s.created_at)+interval '1 day' <= p_as_of
        when 'weekly' then coalesce(s.last_run_at,s.created_at)+interval '7 days' <= p_as_of
        else false
      end
    order by due_at,s.organization_id,s.name
    limit greatest(1,least(coalesce(p_limit,20),100))
  loop
    begin
      v_result:=atlas.run_smart_contact_saved_search_service_v1(v_search.id);
      v_run_count:=v_run_count+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'savedSearchId',v_search.id,
        'stableKey',v_search.stable_key,
        'name',v_search.name,
        'dueAt',v_search.due_at,
        'status','completed',
        'result',v_result
      ));
    exception when others then
      v_failed_count:=v_failed_count+1;
      v_results:=v_results||jsonb_build_array(jsonb_build_object(
        'savedSearchId',v_search.id,
        'stableKey',v_search.stable_key,
        'name',v_search.name,
        'dueAt',v_search.due_at,
        'status','failed',
        'sqlstate',sqlstate,
        'error',sqlerrm
      ));
    end;
  end loop;

  return jsonb_build_object(
    'ok',v_failed_count=0,
    'skipped',false,
    'asOf',p_as_of,
    'runCount',v_run_count,
    'failedCount',v_failed_count,
    'results',v_results
  );
end
$function$;

revoke all on function atlas.run_due_smart_contact_saved_searches_service_v1(timestamptz,integer)
  from public,anon,authenticated;
grant execute on function atlas.run_due_smart_contact_saved_searches_service_v1(timestamptz,integer)
  to service_role;

select cron.schedule(
  'atlas-smart-contacts-watch-v1',
  '53 * * * *',
  $$select atlas.run_due_smart_contact_saved_searches_service_v1(now(),20);$$
);
