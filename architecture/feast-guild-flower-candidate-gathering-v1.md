# Feast Guild Flower Candidate Gathering v1

**Status:** candidate-only read layer  
**Date:** 2026-09-24  
**Parent:** architecture/feast-guild-flower-source-selection-policy-v1.md  
**Source owners reused:** Flower Ready Inventory; External Supply Offer  
**Production boundary:** no migration, reservation, procurement, or customer offer

## Purpose

Feast Guild source selection now knows how to choose among lawful candidate plans. The missing upstream seam is: given one florist basket line, what source-owned facts currently exist that could become candidate fulfillment plans?

V1 gathers from two source classes:

1. Elm actual Ready flower inventory.
2. Admitted External Supply Offer observations, including local growers and wholesalers.

It projects each source fact into the candidate-plan contract already consumed by the Feast Guild source-selection policy. The gatherer does not choose the winner.

## Governing movement

~~~text
Florist basket line
-> source-owned current facts
-> flower-specific requirement matching
-> candidate qualification nodes
-> neutral fulfillment packet
-> candidate set
-> Feast Guild source-selection policy
-> selected plan
-> protected quote
~~~

## Elm Ready inventory source

Owned/current Elm candidates come from atlas.flower_ready_inventory_identity_v1 and atlas.flower_ready_inventory_position_v1.

Candidate quantity uses available_quantity, not birth quantity. The live position already subtracts active sale claims, open demand allocations, prospect-route custody, and disposition events.

V1 gathers a Ready lot only when farm matches the configured Elm source farm, available quantity is positive, quantity exactness is exact, Ready date is on or before the florist requested date, and unit equals the requested line unit.

Because cut flowers are perishable, mathematical availability is not enough. Automatic qualification additionally requires explicit usable-through/freshness evidence covering the florist requested date. A Ready lot with remaining ledger quantity but no usable-through evidence remains physically unresolved for a new florist quote.

Source preference tier is elm_owned_or_grown with evidence referencing the Ready lot and Elm farm.

## Critical Elm economic boundary

Current Ready inventory carries retail valuation. It does not currently carry an authoritative production/transfer economic cost suitable for comparison against external landed acquisition cost.

Therefore:

~~~text
retail_unit_value
!= owned-inventory economic cost
~~~

V1 must not use Retail Flower Product Price Book valuation, sale price, or historical customer price as Elm cost.

Until a governed Elm-to-Feast-Guild owned-inventory cost basis exists, an Elm Ready candidate carries a required unresolved cost component named owned_inventory_economic_cost.

That makes the candidate physically real and highly preferred, but not automatically economically selectable. This is an explicit remaining business-policy/data boundary.

## External source candidates

External candidates come from active atlas.external_supply_offerings and the latest effective atlas.external_supply_offer_observations as of quote date.

The gatherer preserves source identity and current observation lineage. A source listing does not qualify merely because it exists.

## External source quantity and pack math

For requested quantity Q in the requested unit, if pack quantity is explicit in the same unit:

~~~text
source quantity = ceil(Q / pack quantity) * pack quantity
~~~

If a same-unit minimum order exceeds that quantity, the minimum is rounded upward to the pack multiple when a pack exists.

If price basis is explicit or confirmed in the same unit:

~~~text
merchandise cost = price amount * source quantity / price quantity
~~~

If price denominator or unit is unknown, economic cost remains unresolved. No unit conversion is invented.

## Landed-cost completeness

Supplier sticker price is not landed economic cost.

External candidate components may include merchandise, freight, handling, and provider/service fee.

Freight is known only when the source explicitly says freight is included or an explicit freight amount/currency is present. Otherwise freight is a required unresolved cost component.

Additional fees are complete only when source terms explicitly establish fee completeness or every required fee is represented under the admitted source contract. Otherwise an additional_fees component remains unresolved.

A plain price list is useful market evidence but insufficient for a protected florist quote.

## Availability and requested date

V1 distinguishes listing existence, availability state, quantity capacity, and requested-date feasibility.

External qualification adds required nodes:

- source_availability
- source_quantity_capacity
- source_requested_date

available may satisfy basic source availability. unavailable is unsatisfied. limited or unknown is unresolved unless stronger evidence resolves it.

Quantity capacity is satisfied only by explicit source-backed available quantity/capacity sufficient for the computed source purchase quantity.

Requested date is satisfied only by explicit source delivery/available-by evidence or another separately governed source-backed date rule. A price effective date is not a delivery promise.

## Flower requirement matching

V1 recognizes normalized flower requirement keys:

- flower_family
- product_family
- product_label
- variety
- cultivar
- color
- grade
- product_form
- stem_length_cm

Supported expected operators are equals, minimum, and maximum.

Text equality is case-insensitive after trim only. V1 does not singularize, stem, fuzzy-match, infer synonyms, or decide that a cultivar name implies a color.

Unsupported requirement keys or missing source facts become unresolved, not satisfied.

## Source facts

External Supply Offering specification is the normalized product-fact owner for admitted supplier items. Expected normalized keys include flowerFamily, productFamily, productLabel, variety, cultivar, color, grade, productForm, and stemLengthCm.

Elm Ready candidates use exact Ready/crop identity facts available from crop profile, product label, variety, inventory kind, and explicit normalized Ready-lot metadata. Missing facts remain missing.

## Source preference evidence

External source tier comes only from an admitted sourcePreference evidence object in current source observation context. Warehouse location alone is ignored.

Elm Ready inventory establishes elm_owned_or_grown from the Elm farm and Ready-lot custody chain.

## Candidate result

Every gathered source produces the plan shape consumed by atlas.feast_guild_flower_source_plan_select_v1(jsonb,jsonb):

- candidateRef
- qualificationNodes
- neutral fulfillmentPacket
- sourcePreference
- customerFacingSourceFacts
- gatheringBasis

Unresolved candidates remain visible. The selector determines whether they are economically selectable.

## Gathering service

atlas.feast_guild_flower_candidate_sets_gather_service_v1(jsonb,uuid,uuid,date)

Inputs:

1. Feast Guild flower basket.
2. Source organization ID.
3. Elm farm ID.
4. Quote/source-observation date.

The source organization owns the supplier relationships and source observations being consumed. The Elm farm must belong to that source organization.

The function is read-only but source-reading, service-only, and SECURITY DEFINER with fixed search_path. Browser roles do not gain supplier-economics read access through it.

## Scope of V1

Included: actual Elm Ready inventory, admitted external supplier offers, pack/minimum arithmetic, source availability evidence, requested-date evidence, landed-cost completeness, normalized flower requirement matching, and source-tier evidence.

Not included: expected future Elm harvest, crop forecasts, supplier reservation, quote acceptance, purchase authorization, inventory reservation, cross-supplier shared freight optimization, supplier minimum optimization across multiple florist lines, generic catalog search, or fuzzy flower-name matching.

## Whole-order economics caveat

V1 constructs line-local source plans.

If a supplier charges one freight amount across several flower lines, V1 may not independently charge or omit that freight on every line unless source truth supplies a lawful allocation.

Unknown shared freight remains unresolved, not zero.

## Validation

V1 must prove:

1. Ready inventory uses available quantity, not birth quantity.
2. Insufficient Elm available quantity cannot satisfy a larger florist request.
3. Elm Ready date after requested date is not usable current coverage.
4. Elm Ready quantity without usable-through/freshness evidence remains unresolved.
5. Elm retail valuation is never used as owned cost.
6. Elm cost remains unresolved without governed economic basis.
7. External 90-stem demand from a 100-stem pack produces 100 source stems and explicit 10-stem excess.
8. A $38 / 100-stem price basis produces $38 merchandise cost for that pack.
9. Unknown freight remains unresolved.
10. Explicit included freight does not create a second freight charge.
11. Missing fee completeness remains unresolved.
12. Explicit quantity capacity must cover source purchase quantity.
13. Unavailable source is incompatible.
14. Unknown/limited availability remains unresolved unless stronger evidence resolves it.
15. Price effective date is not treated as delivery date.
16. Unsupported flower requirement remains unresolved.
17. Source tier without evidence cannot pass automatic selection.
18. A gathered external candidate can flow through source selection and quote preparation when all required evidence is complete.
19. Gathering creates no reservation, purchase, Spend, inventory, Work, Offer Snapshot, Order, payment, or fulfillment truth.

## Production boundary

This remains candidate-only while the private Actions lane is unavailable.

Validation order when the lane returns:

~~~text
Fulfillment Economics parent
-> Whole-Order Quote adapter
-> Feast Guild Source Selection Policy
-> Feast Guild Candidate Gathering
-> disposable production-schema clone proof
-> advisors
-> governed migration decision
~~~

## Governing result

After V1:

~~~text
florist asks for flowers
-> Atlas finds actual available Elm Ready lots
-> Atlas finds current admitted supplier offers
-> Atlas preserves missing/unknown evidence
-> Atlas constructs comparable candidate plans
-> Feast Guild policy selects among economically lawful candidates
-> protected quote is prepared
~~~

The remaining Elm-specific gap is an authoritative owned-inventory economic cost basis, not candidate discovery.
