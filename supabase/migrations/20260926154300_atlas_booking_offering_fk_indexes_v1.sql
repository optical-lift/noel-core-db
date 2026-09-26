create index if not exists booking_offerings_created_by_seat_idx
  on ledger.booking_offerings(created_by_seat_id)
  where created_by_seat_id is not null;

create index if not exists booking_offering_routing_candidates_resource_idx
  on ledger.booking_offering_routing_candidates(resource_id)
  where resource_id is not null;

create index if not exists booking_offering_routing_candidates_seat_idx
  on ledger.booking_offering_routing_candidates(seat_id)
  where seat_id is not null;
