# Signed worker discovery of ongoing care (HELD)

This source-only slice is stacked on Noel #2362 and does NOT modify
production or put a farm task on Today.

The held and already signed-tested continuing-care source accepts a
single rhythm-state ID. It cannot safely enumerate worker-visible rhythms.
The new source is paginated, per-native-Ledger, signed, and only returns
the latest governor-approved standing policy and independently
identity+condition-disclosed Subject rows for the exact accepted
connected Person. Withdrawn scope, Person connection or either disclosure
removes the row. Only mower/weed care is admitted in this initial domain
adapter; the source interface is not an Elm-specific task engine.

One row is a standing expectation, not completed/open Work or a fabricated
work-on date. A separate signed eligibility + fresh physical observation +
current governor policy must still admit an original Work item. That Work
then uses the existing native allocation, Today and signed Result model.

Before merge/release: compile full disposable production-schema clone,
prove signed governor/worker/outsider/withdrawn-grant pagination and source
isolation, and connect the authorized notebook UI. New tests here are
source-only negative invariants, not signed authorization proof.
