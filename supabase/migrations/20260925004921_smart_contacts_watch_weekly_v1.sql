update atlas.smart_contact_saved_searches
set watch_cadence='weekly',
    updated_at=now()
where organization_id=(select id from atlas.organizations where stable_key='feast_guild')
  and stable_key in ('local-flower-buyers','wholesale-flower-suppliers')
  and search_state='active';

select cron.alter_job(
  (select jobid from cron.job where jobname='atlas-smart-contacts-watch-v1'),
  schedule := '53 11 * * 1'
);
