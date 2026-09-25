
create index booking_policies_resource_fk_idx
  on ledger.booking_policies(resource_id)
  where resource_id is not null;
create index recurrence_series_created_by_seat_fk_idx
  on ledger.recurrence_series(created_by_seat_id)
  where created_by_seat_id is not null;
create index recurrence_exceptions_created_by_seat_fk_idx
  on ledger.recurrence_exceptions(created_by_seat_id)
  where created_by_seat_id is not null;
create index recurrence_instances_exception_fk_idx
  on ledger.recurrence_instances(exception_id)
  where exception_id is not null;
