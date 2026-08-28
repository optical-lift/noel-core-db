-- Atlas Weekly Harvest generated availability write fix v1
--
-- flower_harvest_bucket_observations.more_availability is generated from
-- more_available. Weekly Harvest v2 still attempted to supply the generated
-- column explicitly, which makes harvest_amount writes fail before custody is
-- recorded. Remove only that obsolete generated-column write.

do $migration$
declare
  v_def text;
  v_next text;
begin
  select pg_get_functiondef(
    'atlas.record_weekly_harvest_row_core_v2(uuid,uuid,uuid,text,text,integer,text,boolean)'::regprocedure
  ) into v_def;

  v_next := replace(
    v_def,
    'created_by_user_id,metadata,more_availability',
    'created_by_user_id,metadata'
  );

  v_next := replace(
    v_next,
    $old$      ),'unsure'
    ) returning * into v_observation;$old$,
    $new$      )
    ) returning * into v_observation;$new$
  );

  if v_next = v_def
     or strpos(v_next, 'created_by_user_id,metadata,more_availability') > 0
     or strpos(v_next, $needle$      ),'unsure'
    ) returning * into v_observation;$needle$) > 0 then
    raise exception 'Weekly Harvest generated-column repair did not match the expected v2 function body.';
  end if;

  execute v_next;
end;
$migration$;

comment on function atlas.record_weekly_harvest_row_core_v2(uuid,uuid,uuid,text,text,integer,text,boolean) is
  'Weekly Harvest v2 recorder. flower_harvest_bucket_observations.more_availability is generated from more_available and is never written directly.';
