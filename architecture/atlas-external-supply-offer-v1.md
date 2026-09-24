# Atlas External Supply Offer v1

**Status:** architecture contract / first-proof schema target  
**Date:** 2026-09-23  
**Parent architecture:** optical-lift/atlas/docs/architecture/ATLAS_FULFILLMENT_ECONOMICS_KERNEL_V0_1.md  
**First proof:** Elm wholesale flower sourcing for Wickman's and Flowerama sample baskets  
**Promotion boundary:** external supply only; does not yet establish a universal Fulfillment Economics kernel

## 1. Purpose

Atlas already has durable authority for External Relationships and the supplier relationship role; Organization-owned Commercial Offerings and effective-dated sell-side prices; Commercial Orders, recurring commitments, fulfillment, payments, and financial consequences; exact Commercial Offer Snapshots prepared for presentation; and Evidence / Claim custody.

What is missing is the opposite commercial direction:

> **What has an external supplier actually offered this Organization, under what specifications, quantity basis, price, timing, and conditions?**

This tranche establishes the minimum durable source-side commercial meaning required before Atlas can calculate a truthful fulfillment path.

The first proof is bought-in wholesale flowers. This object must also be capable of representing a supplier's material, rental, or subcontracted-service offer without changing its semantic meaning, but that cross-domain behavior is a qualification target rather than an assumption.

## 2. Governing distinctions

~~~text
Supplier identity
!= External Supply Offering
!= Supply Offer Observation
!= procurement decision
!= purchase authorization
!= Organization Spend
!= owned inventory
!= Organization Commercial Offering
!= customer-facing price
!= Commercial Offer Snapshot
~~~

And:

~~~text
supplier says "100 stems for $92"
!= Elm purchased 100 stems
!= Elm owns 100 stems
!= Elm should sell at $0.92/stem
~~~

The source observation may participate in later calculation. It creates none of those downstream truths by itself.

## 3. Reuse existing identity authority

A supplier is not a new domain identity.

The supplier must be an existing/resolved atlas.external_relationships row carrying atlas.external_relationship_roles(role_key = 'supplier').

If source identity is unresolved, Atlas must stop at the identity boundary rather than creating a convenience supplier record inside this kernel.

This tranche therefore creates no supplier directory.

## 4. Why Evidence / Claim alone is insufficient

atlas.evidence_records and atlas.claim_records are appropriate custody for exact testimony/source evidence and may back this domain.

They do not by themselves provide the deterministic relational identity needed to answer:

- which supplier item is this?
- which later observation belongs to the same supplier-side item?
- what quantity/pack basis does this price apply to?
- what current candidate source offers can satisfy a requirement?
- which observations belong to the same supplier-side item across time?

The new relations therefore organize source-side commercial meaning while retaining evidence provenance.

The economic facts must not be hidden only in untyped JSON metadata when Atlas needs to compare them deterministically.

## 5. External Supply Offering

Candidate canonical relation:

atlas.external_supply_offerings

One row identifies one durable supplier-side thing/service that may be acquired by the Organization.

Minimum V1 meaning:

- id uuid
- organization_id uuid
- optional organization_unit_id uuid
- supplier_relationship_id uuid
- stable_key text
- source_item_key text null
- source_label text
- offering_kind text
- source_unit text null
- status text
- specification jsonb
- metadata jsonb
- creation/update timestamps

### Required invariants

1. Supplier relationship belongs to the same Organization.
2. Supplier relationship currently carries or historically carried an appropriate supplier role.
3. Stable identity is unique within Organization/unit + supplier.
4. Source label is not treated as canonical product equivalence.
5. specification may preserve source-described grade, length, color, size, quality, form, or other attributes, but V1 does not declare one universal specification vocabulary.
6. This row does not assert current price or availability.
7. This row does not become Elm's commercial_offerings identity.

### First flower example

~~~text
supplier = External Relationship: Supplier A
source item key = WHR-60-WHT
source label = White Rose 60cm
offering kind = cut_flower
source unit = stem
specification = {
  family: "rose",
  color: "white",
  stemLengthCm: 60,
  grade: <source-backed if known>
}
~~~

## 6. Supply Offer Observation

Candidate canonical relation:

atlas.external_supply_offer_observations

One row preserves one source-backed observation of commercial terms for one External Supply Offering.

Minimum V1 fields:

- id uuid
- organization_id uuid
- optional organization_unit_id uuid
- external_supply_offering_id uuid
- observed_at timestamptz
- optional effective_from timestamptz
- optional effective_until timestamptz
- currency text
- price_amount numeric
- price_quantity numeric
- price_unit text
- optional pack_quantity numeric
- optional pack_unit text
- optional minimum_order_quantity numeric
- optional minimum_order_unit text
- optional lead_time_value numeric
- optional lead_time_unit text
- order-cutoff field only after real-source qualification
- terms jsonb
- source_kind text
- source_ref text null
- optional evidence_record_id uuid
- observation_state text
- metadata jsonb
- created_at timestamptz

### Price-basis rule

Price must retain its denominator.

Examples:

~~~text
$92 / 100 stems
$18.50 / bunch of 10
$250 / equipment day
$1,400 / subcontracted scope
~~~

Atlas must not normalize the source observation destructively.

Derived unit cost may be calculated downstream while the original price basis remains intact.

### Pack rule

price_quantity and pack_quantity are distinct.

For example:

~~~text
supplier quote = $92 / 100 stems
order increment = case of 100
~~~

or:

~~~text
supplier quote = $1.10 / stem
order increment = bunch of 10
case = 100 stems
~~~

V1 must preserve enough source truth to calculate required buy quantity without pretending every quoted unit is an orderable unit.

## 7. Freight and landed-cost terms

V1 should not flatten freight into the source unit price.

Supplier terms may include included freight, flat shipment fee, per-box fee, threshold-based free freight, destination-dependent freight, fuel/import/handling surcharges, or unknown freight.

The first implementation may retain these in typed terms JSON if the actual Elm source sheets do not justify a stable relational model yet.

However, the calculation contract must distinguish:

~~~text
source merchandise cost
+
source freight/handling terms
=
candidate landed source cost
~~~

Unknown freight must remain unknown rather than being silently treated as zero.

If real supplier evidence shows recurring structured freight rules are required for deterministic calculation, promote those rules into an explicit child relation in a later tranche.

## 8. Availability and freshness

A Supply Offer Observation is not perpetual truth.

V1 must preserve when Atlas observed it; when the supplier says it becomes effective, if known; when it expires, if known; and whether current availability is known, unknown, or explicitly unavailable.

Candidate observation_state values:

~~~text
observed
quoted
available
unavailable
expired
superseded
unknown_availability
~~~

The exact final state vocabulary must be qualified against real supplier evidence before migration promotion.

A price sheet with no availability signal is not proof of supply.

## 9. Evidence / provenance

Every source observation must be traceable to what Atlas actually received.

Acceptable source families include supplier price sheet; supplier portal/export; supplier email; supplier text/message; supplier-issued quote; explicit authorized human report of supplier terms; and imported historical record.

The durable source observation should link to Evidence where the Evidence kernel can truthfully custody the source.

A human report of a supplier quote must remain distinguishable from provider/supplier-authored evidence.

No model-generated or inferred price may be admitted as a source observation.

## 10. No product-equivalence claim

This tranche deliberately does not create a universal Product identity or assert that:

~~~text
Supplier A "White Rose 60cm"
=
Supplier B "Freedom White 60cm"
=
Elm customer requirement "white roses"
~~~

Compatibility belongs to the later Fulfillment Candidate evaluation.

A source offering supplies attributes. A requirement supplies required attributes. A deterministic or governed compatibility rule later determines whether the source offering qualifies for that specific request.

This prevents the supply catalog from becoming an unreviewed product-ontology engine.

## 11. Relationship to Organization Commercial Offerings

atlas.commercial_offerings answers:

> What does this Organization offer commercially?

atlas.external_supply_offerings answers:

> What does this external supplier offer this Organization as an acquirable source?

They are intentionally opposite directions.

Do not place supplier catalog items into Elm's Commercial Offering catalog merely to reuse pricing tables.

A later fulfillment path may connect an External Supply Offering to an Organization Commercial Offering for one calculation or qualified compatibility relation, but neither identity owns the other.

## 12. Relationship to actual Spend

atlas.organization_spend_occurrences may later prove:

> What did the Organization actually spend?

This tranche answers:

> What source terms were available/quoted before purchase?

Therefore:

~~~text
Supply Offer Observation
→ possible later procurement
→ actual economic occurrence / Spend
~~~

Actual Spend can later pressure-test estimated landed costs.

It must not be backfilled as if it had been the supplier's standing pre-purchase quote unless evidence supports that claim.

## 13. Relationship to fulfillment economics

This tranche provides only one missing input family:

~~~text
resolved supplier
→ External Supply Offering
→ current/source-backed Supply Offer Observation
~~~

A later candidate-evaluation tranche may combine it with requested requirement, owned Ready inventory, pack conversion, yield/loss, freight, timing, and mixed-source allocation to produce one or more Fulfillment Paths.

This tranche does not yet persist Fulfillment Paths or cost compositions.

That sequencing is deliberate: source truth must exist before Atlas can build a trustworthy optimizer/calculator over it.

## 14. First acceptance fixture

When the first wholesale flower supplier sheet/quote is available, V1 must be able to represent at least:

~~~text
Supplier relationship
Item: White Rose 60cm
Source item/SKU if supplied
Price: $92 / 100 stems
Order pack: 100 stems
Observed: <timestamp>
Effective/expiry: <if supplied>
Freight: <included / rule / unknown>
Lead time: <if supplied>
Availability: <if supplied>
Source evidence: <exact supplier source>
~~~

Then a later read must be able to retrieve the current non-expired observations for that supplier/item without parsing prose.

## 15. Qualification cases

Before promotion, production-shaped validation should prove:

1. supplier relationship must belong to the same Organization;
2. Organization Unit, when present, belongs to the same Organization;
3. source offering key is idempotent within supplier scope;
4. an offering may exist with no current price;
5. multiple dated observations may exist for one offering;
6. original price denominator is preserved;
7. currency is explicit;
8. negative price/quantity/pack/minimum values are rejected;
9. invalid effective windows are rejected;
10. expired observations are not returned as current without explicit historical request;
11. unknown freight is not normalized to zero;
12. unknown availability is not normalized to available;
13. one supplier observation creates no Commercial Order;
14. one supplier observation creates no Organization Spend;
15. one supplier observation creates no owned/Ready inventory;
16. one supplier observation creates no customer-facing Commercial Offering price;
17. browser roles cannot write supplier commercial truth directly;
18. source/evidence provenance survives round-trip read;
19. later observation does not mutate historical observation;
20. source item identity can survive a price change.

## 16. Browser / service boundary

V1 should be written through a governed service/internal command.

The browser must not receive generic write access to the source tables.

A later Implementation Workbench / Reality Sentence adapter may translate an authorized human statement such as:

~~~text
Supplier A offers White Rose 60cm at $92 per 100 stems,
case of 100, observed Sept. 23.
~~~

into a proposed typed operation.

That interpretation does not bypass identity resolution, evidence custody, or command authorization.

## 17. Promotion boundary

This architecture contract does not yet authorize a migration, procurement commands, supplier outreach, automated purchasing, generic inventory, Fulfillment Path persistence, cost composition persistence, pricing-policy persistence, customer quote generation, or model-chosen product equivalence.

The next step is to obtain/inspect at least one real supplier source artifact and qualify these fields against it before generating executable migration SQL.

## 18. Resulting architecture

~~~text
External Relationship (supplier)
→ External Supply Offering
→ Supply Offer Observation + Evidence
→ later Fulfillment Candidate evaluation
→ later true-cost composition
→ existing Organization sell-side commercial authority
→ existing Commercial Offer Snapshot
~~~

The object earns its place only because current Atlas has no source-owned durable meaning that answers the supplier-side commercial question without corrupting sell-side pricing, Spend, inventory, or generic Evidence into substitute authority.


## 19. First real-source qualification: Baisch & Skinner cut-flower price list

A user-supplied Baisch & Skinner Wholesale Floral Distributor price list dated September 19-25, 2026 was reviewed as the first real supplier artifact.

The artifact materially corrects the pre-source schema assumptions.

### 19.1 What the source actually establishes

The page establishes:

- supplier identity from the document masthead;
- one dated source document titled "Cut Flower Price List";
- a stated source window of September 19-25, 2026;
- source row labels and numeric price amounts;
- source grouping such as CUT FLOWERS, GREENS, BRANCHES, and LOCAL;
- some labels that explicitly carry quantity-like notation, including "Sunflowers x5", "Mini x10", "Hellebores x10", "Hybrid-10 Stem", "Hybrid-5 Stem", and "Phael Spray x 1";
- a source warning that prices are subject to change;
- visual highlighting whose legend says highlighted rows are new items or price changes.

The source therefore proves that raw source presentation/context has economic meaning and should survive ingestion.

### 19.2 What the source does not establish

The page does not, by itself, establish:

- currency;
- a price denominator/unit for most rows;
- whether most numeric prices are per stem, bunch, pack, or another unit;
- freight;
- handling;
- minimum order;
- lead time;
- order cutoff;
- available quantity;
- a positive availability assertion for each listed line.

The uploaded filename includes "Availability", but the document itself is headed "Cut Flower Price List" and contains no quantity-available column. Atlas must not turn presence on this sheet into inventory/availability truth.

### 19.3 Required schema corrections

The first draft incorrectly required currency, price_quantity, and price_unit on every observation.

That is not source-faithful.

V1 must instead allow:

- currency = null when the source does not state currency;
- price_quantity = null and price_unit = null when the price denominator is not source-explicit or human-confirmed;
- an explicit price_basis_state such as source_explicit | confirmed | unknown;
- source_context JSON preserving source section/path, raw row label, parent/variant context when needed, and visual emphasis/change marking;
- availability_state defaulting to unknown unless the source actually states availability;
- effective_from/effective_until from the document window while separately preserving the term that prices are subject to change.

A row may therefore truthfully mean:

~~~text
source label = Carnations
price amount = 0.65
currency = unknown
price basis = unknown
availability = unknown
effective window = 2026-09-19 through 2026-09-25
terms.priceSubjectToChange = true
~~~

That is more useful than guessing "0.65 USD per stem."

### 19.4 Hierarchy and variant handling

The source frequently expresses commercial identity through a parent/variant visual hierarchy rather than one globally unique row label.

Examples include parent families with subordinate sizes/colors/grades, and labels whose meaning depends on the source column/section.

V1 should not create a universal flower taxonomy from this layout.

For first ingestion, the durable source offering may use a fully-qualified source label plus source_context. A later deterministic normalization/adjudication step may map source-described attributes into requirement-compatible specifications.

### 19.5 Migration gate cleared, with narrower scope

This source is sufficient to draft executable schema for:

- External Supply Offering identity;
- append-only Supply Offer Observation;
- unknown/explicit price-basis state;
- source validity/freshness;
- source context/provenance;
- unknown availability;
- service-only write/read membranes.

It is not sufficient to design freight, minimum-order, or procurement-authority subsystems.

Those remain deferred until source evidence actually requires them.
