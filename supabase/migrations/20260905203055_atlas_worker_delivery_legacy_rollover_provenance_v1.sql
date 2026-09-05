begin;

update atlas.worker_week_projection
set rollover_policy = 're_evaluate',
    updated_at = clock_timestamp()
where farm_id = '6a503d9f-4008-4ddb-b3f0-cc6ab825dc9f'
  and membership_id = '23e98e5e-16ca-40d8-872c-c77e06baa167'
  and delivery_key is null
  and rollover_policy = 'carry';

comment on column atlas.worker_week_projection.rollover_policy is
  'Worker delivery rollover decision. Legacy pre-membrane placements without a delivery_key are not evidence of an explicit carry decision and are normalized to re_evaluate rather than being auto-delivered indefinitely.';

commit;