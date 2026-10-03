insert into atlas.public_commitment_surfaces(
  surface_key,organization_id,organization_unit_id,title,description,surface_state,adapter_kind,
  ledger_id,booking_offering_id,commercial_offering_id,public_config,adapter_config,metadata,provenance
)
select
  'elm_private_venue_booking_v1',
  org.id,unit.id,
  'Book Elm Farm',
  'Public request surface for private use of Elm Farm venue resources. Atlas evaluates current resources, policy, price, and commitment requirements before a request can become a booking.',
  'active','ledger_booking',l.id,bo.id,co.id,
  jsonb_build_object(
    'brand','Elm Farm',
    'timezoneName','America/Chicago',
    'requestKind','private_venue_rental',
    'standardGuestCountMax',30,
    'standardDurationHoursMax',8,
    'publicTruthBoundary',jsonb_build_object(
      'requestIsNotBooking',true,
      'availabilityIsNotCommitment',true,
      'paymentIsNotApproval',true,
      'agreementIsNotApproval',true
    )
  ),
  jsonb_build_object(
    'businessModelKey','private_venue_rental_v1',
    'pricingPolicyKey','elm_venue_private_rental_pricing_v1',
    'publicResourceKeys',jsonb_build_array('event_center','grounds'),
    'publicPriceBasisKeys',jsonb_build_array(
      'indoor_house_base_2_hours','indoor_house_additional_hour','indoor_house_8_hours',
      'outdoor_property_add_on','bridal_lounge_add_on','stocked_coffee_refreshments_add_on',
      'wedding_planner_coordinator_add_on','full_elm_wedding_8_hours_up_to_30_guests'
    ),
    'durationPricing',jsonb_build_object(
      'resourceKey','event_center',
      'basePriceBasis','indoor_house_base_2_hours',
      'baseIncludedMinutes',120,
      'additionalPriceBasis','indoor_house_additional_hour',
      'incrementMinutes',60
    ),
    'resourcePriceBasis',jsonb_build_object('grounds','outdoor_property_add_on'),
    'addOnPriceBasis',jsonb_build_object(
      'bridal_lounge','bridal_lounge_add_on',
      'stocked_coffee_refreshments','stocked_coffee_refreshments_add_on',
      'wedding_planner_coordinator','wedding_planner_coordinator_add_on'
    ),
    'selfServiceMaxMinutes',480,
    'selfServiceGuestCountMax',30,
    'requireGuestCount',true,
    'nestedResourceRule',jsonb_build_object(
      'bridal_lounge','Commercial/event-plan designation inside an exclusive Event Center reservation; do not create a second overlapping Lounge resource claim.'
    )
  ),
  jsonb_build_object('firstAdopter','Elm Farm Venue','universalArchitecture','public_commitment_membrane_v1'),
  jsonb_build_object('sourceAuthority','user_directed_atlas_build','sourceConversationDate','2026-09-27')
from atlas.organizations org
join atlas.organization_units unit on unit.organization_id=org.id and unit.stable_key='elm'
join ledger.ledgers l on l.stable_key='elm-farm:venue' and l.ledger_state='active'
join ledger.booking_offerings bo on bo.ledger_id=l.id and bo.stable_key='elm_private_venue_rental_v1'
join atlas.commercial_offerings co on co.organization_id=org.id and co.organization_unit_id=unit.id and co.stable_key='elm_venue_private_rental'
where org.stable_key='elm_farm'
on conflict(surface_key) do update
set organization_id=excluded.organization_id,
    organization_unit_id=excluded.organization_unit_id,
    title=excluded.title,
    description=excluded.description,
    surface_state=excluded.surface_state,
    adapter_kind=excluded.adapter_kind,
    ledger_id=excluded.ledger_id,
    booking_offering_id=excluded.booking_offering_id,
    commercial_offering_id=excluded.commercial_offering_id,
    public_config=excluded.public_config,
    adapter_config=excluded.adapter_config,
    metadata=atlas.public_commitment_surfaces.metadata||excluded.metadata,
    provenance=atlas.public_commitment_surfaces.provenance||excluded.provenance;