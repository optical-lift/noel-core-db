# Feast Guild Flower Source Selection Policy v1

**Status:** candidate-only institutional policy adapter  
**Date:** 2026-09-24  
**Parent:** architecture/feast-guild-whole-order-quote-v1.md  
**Universal dependencies:** Candidate -> Requirement Qualification; Neutral Fulfillment Composition  
**Production boundary:** read-only candidate; no purchase, reservation, Spend, inventory, Order, or supplier commitment

## 1. Decision established

Feast Guild will not leave source choice undefined for every florist quote.

For a flower line, Atlas may automatically select among qualified fulfillment candidates under this Feast Guild-specific institutional policy:

~~~text
1. elm_owned_or_grown
2. regional_us
3. us_grown
4. imported
~~~

Qualification comes before preference.

Among candidates that satisfy the florist's required specification, required quantity/date/availability evidence, exact quantified fulfillment coverage, complete known landed economic cost in the policy currency, and explicit evidence for their source-preference tier, Feast Guild permits the more-preferred source when its landed economic cost is no more than **10% above the cheapest qualified known-cost candidate**.

The comparison basis is **landed economic cost**, not supplier sticker price.

## 2. V1 policy contract

Contract version: feast_guild_flower_source_selection_policy_v1.

~~~json
{
  "contractVersion": "feast_guild_flower_source_selection_policy_v1",
  "comparisonBasis": "landed_economic_cost",
  "currency": "USD",
  "maximumPreferencePremiumRate": 0.10,
  "preferenceTiers": [
    {"tier": "elm_owned_or_grown", "rank": 1},
    {"tier": "regional_us", "rank": 2},
    {"tier": "us_grown", "rank": 3},
    {"tier": "imported", "rank": 4}
  ]
}
~~~

This is Feast Guild policy. It is not universal Atlas law and does not create a generic sourcing-policy table.

A future Feast Guild policy change should produce a new policy version rather than silently changing the meaning of historical V1 decisions.

## 3. Qualification comes first

Source preference never turns an unqualified candidate into a lawful candidate.

A candidate may enter automatic source selection only when Candidate -> Requirement Qualification is qualified and its Neutral Fulfillment Composition has accepted validation, exact coverage, known economics, one currency, and that currency equals the policy currency.

Examples that cannot enter automatic selection include a 50 cm rose against a required 60 cm rose, unresolved availability when availability is required, unknown freight, unknown price denominator, mixed currency without governed conversion, or a source preference tier asserted without evidence.

Unknown does not become inexpensive.

## 4. Landed economic cost

The candidate comparison value is the complete known cost of the exact fulfillment composition.

It may include merchandise, freight, handling, marketplace/provider fees, required pack/case/bunch purchase, explicit loss/yield burden, and other required cost components where source-backed.

If a florist needs 90 stems and the only lawful source purchase is a 100-stem pack, the comparison cost is the cost required to obtain that 100-stem pack while the composition allocates 90 output stems and preserves 10 as excess.

Future recovery of excess may not reduce the candidate cost unless Atlas has source-owned recovery truth.

## 5. Preference-band algorithm

For one requested line:

1. construct the set of qualified, exact, known-landed-cost candidates;
2. find the lowest landed cost in that set;
3. calculate preference ceiling = cheapest qualified landed cost × 1.10;
4. preserve candidates above the ceiling for review;
5. among candidates at or below the ceiling, choose the best preference rank;
6. within that preference rank, choose the lowest landed cost;
7. if still tied, use candidate source reference as a deterministic tie-break only.

The source reference tie-break has no business meaning. It exists only so repeated evaluation returns the same result.

## 6. Examples

### Elm inside the preference band

~~~text
Imported qualified landed cost = $100
U.S.-grown = $105
Elm-grown = $108

ceiling = $110
selected = Elm-grown at $108
~~~

### Most-preferred source outside the band

~~~text
Imported = $100
U.S.-grown = $105
Regional U.S. = $109
Elm-grown = $120

ceiling = $110
selected = Regional U.S. at $109
~~~

Elm remains visible as the more-preferred available tier, but automatic selection does not use it. Using Elm at $120 requires an explicit operator-approved exception outside this V1 automatic selector.

### Preferred tier unavailable

~~~text
Imported = $100
U.S.-grown = $107
no Elm or Regional candidate qualifies

ceiling = $110
selected = U.S.-grown at $107
~~~

The policy does not wait for a nonexistent preferred candidate.

## 7. Source-tier evidence

The selector does not infer origin from wholesaler identity, warehouse/hub, seller address, provider brand, source URL, or product name alone.

Every candidate presented for automatic selection must carry a sourcePreference object containing a tier and a non-empty evidence array.

For elm_owned_or_grown, evidence must establish Elm ownership/growing source.

For regional_us, the source adapter must establish that the product is U.S.-grown and qualifies under Feast Guild's regional classification. V1 does not infer that classification from mileage or warehouse location.

For us_grown, origin evidence must establish U.S. growing origin.

For imported, origin evidence must establish non-U.S. growing origin or an explicit source classification sufficient for the adapter.

If the tier cannot be supported, the candidate remains visible but cannot be automatically ranked under this policy.

## 8. Regional classification boundary

V1 deliberately does not encode a universal geographic radius.

Regional U.S. is a Feast Guild operating classification, not an Atlas geography primitive.

The flower/source adapter must supply evidence that a candidate belongs to the Feast Guild regional class.

A later operational rule may define that class by approved states, mileage, grower network, delivery lane, or another explicit Feast Guild rule. Until then, automatic selection may use regional_us only when the source/admission layer has already explicitly established it.

## 9. Operator exception

When a more-preferred available tier exists above the 10% ceiling:

- automatic selection proceeds with the best in-band candidate;
- the result preserves the out-of-band preferred candidate(s);
- the result states that using one requires explicit operator approval;
- no automatic function may silently widen the 10% band.

V1 does not create the durable operator-approval authority. That approval should later be represented through the governing decision/authority membrane rather than a boolean supplied by a browser.

## 10. Selection result

The selector returns policy version, requirement reference, cheapest qualified known landed cost, preference ceiling, selected candidate, selected tier/rank, selected landed cost, premium amount and premium rate versus cheapest, all candidate evaluations, excluded/unresolved reasons, whether a more-preferred candidate exists outside the band, and whether operator approval would be required to use that candidate.

The selected candidate remains a plan. It is not reserved, purchased, secured, inventory, Spend, a Commercial Order, a customer offer, or a supplier commitment.

## 11. Whole-order composition

Source selection occurs line by line.

A single florist basket may therefore become:

~~~text
Line 1 -> Elm
Line 2 -> regional U.S. grower
Line 3 -> DVFlora source item
Line 4 -> imported Flowerbuyer lot
~~~

Feast Guild then presents one customer order/quote.

V1 does not impose a one-wholesaler-per-basket rule.

Later whole-order optimization may consider shared freight or supplier minimums when those economics are represented as real cross-line constraints. V1 must not fake such savings by summing line-local costs that omit them.

## 12. Candidate functions

### atlas.feast_guild_flower_source_selection_policy_v1()

Returns the immutable V1 institutional policy.

### atlas.feast_guild_flower_source_plan_select_v1(jsonb,jsonb)

Inputs are a basket-line requirement packet and a candidate plan array. The function always uses the immutable V1 Feast Guild policy; the preference band is not caller-supplied.

The function is read-only. It returns a selected plan when automatic selection is lawful, or a blocked state when no candidate can be selected safely, plus full evaluation evidence.

### atlas.feast_guild_flower_quote_prepare_from_candidates_v1(jsonb,jsonb,jsonb,jsonb)

Whole-basket orchestration:

~~~text
basket
+ candidate set per line
-> policy selection per line
-> selected line plans
-> existing feast_guild_flower_quote_prepare_v1
-> quote + selection evidence
~~~

This orchestration does not write the Commercial Offer Snapshot.

## 13. Required validation

V1 must prove:

1. Elm within +10% of cheapest is selected;
2. Elm above +10% is not automatically selected;
3. next-best preference tier inside the band wins over a cheaper lower-preference tier;
4. exactly 10% premium is allowed;
5. greater than 10% premium is outside the band;
6. within one tier, lower landed cost wins;
7. unknown freight cannot enter automatic selection;
8. unresolved qualification cannot enter automatic selection;
9. missing source-tier evidence cannot enter automatic selection;
10. supplier/warehouse identity does not establish source tier;
11. pack excess remains in landed economics;
12. the cheapest lawful candidate remains selectable;
13. a whole basket may select different source tiers per line;
14. whole-order quote receives selected plans and preserves selection basis;
15. no Order, payment, Spend, Work Requirement, inventory, supplier commitment, offer snapshot, or fulfillment event is created.

## 14. Production boundary

Until the parent Fulfillment Economics candidate tranche is released:

- this policy remains candidate-only;
- no migration is created;
- no production source feed may depend on it;
- no quote should be represented as production-governed by this candidate;
- no GitHub Actions validation/release issue is opened while private Actions are locked.

## 15. Governing result

~~~text
qualification
-> exact known landed economics
-> cheapest lawful cost baseline
-> +10% preference ceiling
-> best source tier inside ceiling
-> deterministic selected plan
-> protected customer pricing
~~~

Feast Guild prefers Elm/local/domestic in a measurable way without allowing preference to erase specification truth or economic protection.
