
create index bookings_occurrence_fk_idx on ledger.bookings(occurrence_id);
create index bookings_created_by_seat_fk_idx on ledger.bookings(created_by_seat_id)
  where created_by_seat_id is not null;
create index booking_events_performed_by_entity_fk_idx on ledger.booking_events(performed_by_entity_id)
  where performed_by_entity_id is not null;
create index occurrence_resource_claims_occurrence_fk_idx on ledger.occurrence_resource_claims(occurrence_id);
