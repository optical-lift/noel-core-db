# Feast Guild Whole-Order Quote Adapter v1

**Status:** candidate-only implementation contract  
**Date:** 2026-09-24  
**Branch:** `architecture/feast-guild-whole-order-quote-v1`  
**Parent checkpoint:** `architecture/atlas-external-supply-offer-v1` @ `78f705484ba0302395eae784ee5861e0da80d597`  
**Production boundary:** not released; do not promote while private GitHub Actions are unavailable  
**First proof:** one multi-line florist basket prepared from explicit qualified fulfillment plans

## 1. Purpose

The fulfillment-economics tranche already provides the source-side and universal calculation machinery required beneath Feast Guild:

- External Supply Offering / Supply Offer Observation;
- requirement-set evaluation;
- Candidate -> Requirement Qualification;
- neutral fulfillment composition;
- cost-based commercial price evaluation;
- pooled price protection;
- Commercial Order -> Company Work requirements;
- external acquisition commitment;
- external acquisition fulfillment intake.

The missing layer is deliberately thin and flower-specific:

> Given one florist basket and one explicitly selected source/fulfillment plan per requested flower line, can Atlas verify every line, calculate protected customer terms, preserve unresolved lines, aggregate a whole-order result, and produce an exact Commercial Offer Snapshot packet without creating an Order, purchase, Spend, inventory, payment, or customer fulfillment?

This adapter answers that question.

It does **not** choose a wholesaler autonomously. Source choice remains a separate planning/decision responsibility until a governed Feast Guild source-ranking policy is established.

## 2. Governing movement

~~~text
Florist basket
→ explicit flower requirements
→ selected candidate plan per line
→ source-backed directional qualification
→ neutral fulfillment composition
→ deterministic protected line price
→ whole-order aggregation
→ Commercial Offer Snapshot-ready packet
~~~

The adapter is read-only.

If any required line is not qualified or cannot be priced from complete known economics:

~~~text
whole order = incomplete_evidence
wholeOrderTotal = null
blocked line remains explicit
~~~

Unknown freight, unknown currency, unknown price denominator, unresolved specification, or unresolved availability may not become zero or “probably fine.”

## 3. Basket contract

Contract version:

`feast_guild_flower_basket_v1`

Required basket fields:

- `basketKey`;
- `requestedForDate`;
- `lines[]`.

Each line requires:

- `lineKey`;
- `description`;
- positive `quantity`;
- `unit`;
- `requirements[]`.

A requirement definition requires:

- `requirementKey`;
- `required` boolean, defaulting to true;
- optional `expected` structured value;
- optional `customerFacingLabel`;
- optional `evidenceRequired`, defaulting to true for required nodes.

The basket preserves what the florist requested. It does not identify a supplier SKU.

## 4. Selected line-plan contract

The adapter accepts exactly one selected plan per basket line.

Each selected plan requires:

- `lineKey`;
- `candidateRef` with `sourceDomain` and `sourceRef`;
- `qualificationNodes[]`;
- `fulfillmentPacket` using `neutral_fulfillment_composition_v1`;
- optional `customerFacingSourceFacts`;
- optional `selectionBasis`.

The adapter verifies that:

1. every basket line has exactly one selected plan;
2. every required basket requirement key has an explicit qualification node;
3. satisfied evidence-required nodes carry non-empty evidence;
4. universal qualification returns `qualified`;
5. the fulfillment packet requirement reference belongs to that basket line;
6. fulfillment packet quantity/unit exactly match the requested basket line;
7. universal commercial price evaluation returns `priced`.

The adapter does not infer equivalence from labels.

## 5. Pricing policy

The adapter receives the existing explicit universal pricing-policy input.

For the first proof:

~~~json
{
  "contractVersion": "commercial_price_policy_input_v1",
  "method": "gross_margin",
  "rate": 0.30,
  "currency": "USD",
  "rounding": {
    "mode": "ceil",
    "increment": 0.01
  }
}
~~~

This is a fixture policy, not a newly persisted Feast Guild policy.

No cross-domain pricing-policy table is created by this tranche.

## 6. Quote result

The result contract is:

`feast_guild_flower_quote_preparation_v1`

It returns:

- basket identity/date;
- `state = complete | incomplete`;
- line results in original basket order;
- priced line count;
- blocked line count;
- single order currency when all priced lines agree;
- `pricedSubtotal`;
- `wholeOrderTotal` only when the whole basket is complete;
- blocking reasons;
- customer-facing source facts supplied by the selected plan;
- Commercial Offer Snapshot-ready draft.

A priced line preserves:

- requested description/quantity/unit;
- selected candidate reference;
- qualification result;
- fulfillment plan key;
- true known fulfillment cost;
- cost per requested unit;
- proposed unit price;
- line total;
- source facts;
- selection basis.

A blocked line preserves the exact boundary that blocked it.

## 7. Commercial Offer Snapshot bridge

The adapter does not call the snapshot writer.

It returns a `snapshotDraft` shaped for:

`atlas.record_commercial_offer_snapshot_service_v1(...)`

The draft contains:

- Organization / optional Organization Unit;
- snapshot key/title;
- `complete` or `incomplete_evidence`;
- validity window;
- one snapshot line per requested basket line;
- source references;
- explicit terms and quote-preparation provenance;
- no assets in v1.

A later reviewed command may freeze a complete result through the existing immutable Commercial Offer Snapshot authority.

An incomplete result may be preserved as incomplete evidence, but must not be treated as a provider-observed/action-result offer.

## 8. Source selection boundary

V1 intentionally does not encode a Feast Guild rule such as:

~~~text
Elm
→ Missouri
→ U.S.
→ imported
~~~

or a maximum premium Feast Guild will pay for a preferred source.

Those are real policy questions and must be supplied explicitly when established.

The selected line plan may preserve:

~~~json
{
  "selectionBasis": {
    "decisionKind": "fixture_selected",
    "reason": "first whole-order proof"
  }
}
~~~

but the quote adapter does not claim the selection was optimal.

## 9. Whole-pack economics

A florist may request 90 stems while the selected supplier requires purchase of 100.

The neutral fulfillment packet must preserve:

- requested/output quantity = 90 stems;
- source quantity = 100 stems;
- full required source cost;
- explicit 10-stem excess/disposition state.

Line pricing therefore burdens the quoted 90 stems with the full currently required cost unless another governed recovery fact is present.

The adapter does not assume future excess recovery.

## 10. First validation set

The candidate validation must prove:

1. a three-line florist basket becomes one complete prepared quote;
2. pack excess is carried into the line economics;
3. all three line totals aggregate exactly;
4. customer-facing source facts pass through without becoming qualification authority;
5. snapshot draft is `complete` only when every required line is priced;
6. one unresolved required cost blocks the whole-order total;
7. an incomplete result emits `incomplete_evidence`;
8. missing selected line plan blocks rather than disappears;
9. missing required qualification node blocks;
10. satisfied evidence-required qualification without evidence blocks;
11. mismatched quantity/unit blocks;
12. no Orders, Payments, Spend, inventory, Work Requirements, supplier commitments, or fulfillment events are created by quote preparation.

## 11. Initial fixture arithmetic

The first complete basket uses explicit test-only source economics:

### Carnations

~~~text
florist request = 90 stems
supplier buy = 100 stems
known landed source cost = $38
excess = 10 stems, recovery unresolved
30% gross-margin rule, upward cent rounding

$38 / 90 = $0.422222...
protected quote = $0.61 / stem
line total = $54.90
~~~

### White roses 60 cm

~~~text
request = 50 stems
known landed cost = $55
protected quote = $1.58 / stem
line total = $79.00
~~~

### Eucalyptus

~~~text
request = 5 bunches
known landed cost = $25
protected quote = $7.15 / bunch
line total = $35.75
~~~

Whole-order prepared total:

~~~text
$54.90 + $79.00 + $35.75 = $169.65
~~~

These are validation fixtures, not live Feast Guild prices.

## 12. Production boundary

This branch must not:

- create a Supabase migration;
- create a production release request;
- create a clone-validation issue while Actions are unavailable;
- merge the parent fulfillment-economics candidate tranche;
- connect live wholesaler credentials;
- insert fixture terms into production.

It may be committed, reviewed, extended, and fixture-tested as candidate source.

When private Actions return, the parent fulfillment-economics tranche must cross its governed validation/release boundary first. This adapter can then be validated against that released authority and promoted separately.

## 13. Completion condition

This candidate is checkpoint-clean when:

- architecture contract exists;
- read-only adapter SQL exists;
- realistic complete and incomplete basket fixtures exist;
- rollback validation covers the required boundaries;
- the adapter depends only on the frozen parent candidate contracts and existing production Commercial Offer Snapshot contract;
- no automated Actions run was required to create the checkpoint.
