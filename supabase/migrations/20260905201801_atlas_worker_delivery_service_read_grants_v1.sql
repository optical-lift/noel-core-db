begin;

grant select on table atlas.worker_week_projection_sources to service_role;
grant select on table atlas.worker_delivery_pilot_events to service_role;
grant select on table atlas.worker_delivery_pilot_active_attention to service_role;

comment on table atlas.worker_week_projection_sources is
  'Institution-owned work relationships for worker delivery projections. Direct server-side read is granted only to service_role for Worker Day projection consumers; mutation remains governed separately.';
comment on table atlas.worker_delivery_pilot_events is
  'Append-only Worker Day pilot interaction ledger. service_role may read for server-rendered delivery state; writes remain RPC-governed.';
comment on table atlas.worker_delivery_pilot_active_attention is
  'Mutable Worker Day pilot attention coordination state. service_role may read for server-rendered delivery state; writes remain RPC-governed.';

commit;