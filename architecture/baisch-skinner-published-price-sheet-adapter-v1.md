# Baisch & Skinner Published Cut Flower Price Sheet Adapter v1

**Status:** candidate-only provider adapter  
**Date:** 2026-09-24  
**Observed source:** Baisch & Skinner Wholesale Floral Distributor, Cut Flower Price List, September 19-25, 2026  
**Parent:** architecture/atlas-supplier-source-ingestion-v1.md  
**Downstream:** External Supply Offer -> Feast Guild Flower Candidate Gathering  
**Input boundary:** normalized source document; PDF/layout extraction is upstream and replaceable

## 1. Purpose

Baisch & Skinner publishes a dense periodic Cut Flower Price List.

Unlike Flowerbuyer Open Market, the observed sheet does not expose a clean live inventory quantity, explicit currency, globally stated price denominator, complete freight, or complete fee semantics.

That does not make the source unusable.

Atlas should model it for what it is:

~~~text
published source document
-> exact normalized document custody
-> row-level source interpretation
-> External Supply Offer observations
-> unresolved facts stay unresolved
-> candidate gathering
-> protected quote only when enough evidence exists
~~~

The adapter must not turn a price sheet into inventory.

## 2. Source facts established by the observed sheet

Document-level source facts:

~~~text
title             = Cut Flower Price List
validFrom         = 2026-09-19
validUntil        = 2026-09-25
priceSubjectToChange = true
highlightMeaning  = new item OR price change
~~~

The sheet contains sections headed CUT FLOWERS and GREENS, plus source-defined subheadings such as ROSES NOVELTY, BRANCHES, and LOCAL.

Rows contain a source label and displayed numeric price.

Some rows explicitly contain quantity/unit language, for example:

~~~text
Delphinium S.A. / Hybrid-10 Stem -> 20.95
Delphinium S.A. / Hybrid-5 Stem  -> 18.95
~~~

Other rows contain count-like notation without a stated unit:

~~~text
Sunflowers x5     -> 10.95
Mini x10          -> 12.95
Hellebores x10    -> 32.95
~~~

Those two forms are not equivalent.

## 3. Normalization boundary

V1 does not parse PDF pixels.

It accepts a normalized representation of the published source while preserving source structure.

Canonical normalized document:

~~~json
{
  "contractVersion": "baisch_skinner_cut_flower_price_sheet_normalized_v1",
  "documentTitle": "Cut Flower Price List",
  "validFrom": "2026-09-19",
  "validUntil": "2026-09-25",
  "priceSubjectToChange": true,
  "highlightMeaning": "new_item_or_price_change",
  "rows": [
    {
      "rowKey": "cut_flowers|carnations",
      "rowKind": "item",
      "section": "CUT FLOWERS",
      "sourcePath": ["Carnations"],
      "rawLabel": "Carnations",
      "displayPriceText": "0.65",
      "displayPrice": 0.65,
      "highlighted": false,
      "identityState": "resolved"
    }
  ]
}
~~~

The normalizer may come from:

- a future Baisch machine-readable export;
- an authorized browser/file workflow;
- a deterministic document/table parser;
- operator-assisted normalization.

The downstream provider semantics do not change.

## 4. Lossless source structure

The normalizer must preserve enough structure to distinguish:

- top-level rows;
- indented child rows;
- source subsection headings;
- ambiguous continuation rows;
- composite cells containing more than one label/price pair;
- highlighted rows.

Required row fields:

~~~text
rowKey
rowKind
section
sourcePath
rawLabel
displayPriceText
displayPrice
highlighted
identityState
~~~

Optional layout/source fields may include:

~~~text
columnIndex
sourceOrdinal
parentRowKey
subsection
indentLevel
rawQuantityNotation
normalizationNotes
~~~

The normalized form is evidence packaging, not commercial interpretation.

## 5. Row kinds

V1 supports:

### item

One source-identifiable price row.

### subsection_header

A printed source heading such as ROSES NOVELTY, BRANCHES, or LOCAL.

It is not itself an offer.

### context_ambiguous

A priced row whose commercial identity cannot be determined from the published source structure with sufficient confidence.

Example: a continuation row whose parent product is not printed or otherwise source-resolved.

It remains source evidence but is not automatically admitted as an External Supply Offering.

### composite_unresolved

A source cell that visibly contains multiple label/price pairs but cannot be separated losslessly by the normalizer.

It remains raw source evidence until resolved.

## 6. Source identity

Baisch does not expose a provider SKU on the observed sheet.

Therefore V1 uses the normalized source path as a provisional provider identity.

Stable source identity:

~~~text
baisch_skinner:price_sheet_item:<rowKey>
~~~

The rowKey must be deterministic from source structure, not row number alone.

Examples:

~~~text
cut_flowers|carnations
cut_flowers|carnations|tinted
cut_flowers|delphinium_sa|hybrid_10_stem
cut_flowers|roses_novelty|playa_aspen
greens|acacia_feather
~~~

A material source-label/path change may create a new provisional item identity until a future Baisch SKU/crosswalk establishes continuity.

## 7. Displayed price

The source clearly supplies a numeric displayed price.

V1 therefore preserves:

~~~text
displayedPriceAmount = source numeric value
~~~

But the observed sheet does not state a currency.

Therefore:

~~~text
currency = unresolved
~~~

Do not infer USD merely because the wholesaler operates in the United States.

A later confirmed Baisch account/provider rule may establish currency for this source family.

## 8. Price denominator / unit

The sheet does not state one global price denominator.

V1 applies a narrow evidence rule.

### Explicit quantity + unit

When the source label explicitly contains a count and unit, such as:

~~~text
Hybrid-10 Stem
Hybrid-5 Stem
~~~

the adapter may establish:

~~~text
priceQuantity = 10 or 5
priceUnit     = stem
packQuantity  = same explicit quantity
packUnit      = stem
priceBasisState = source_explicit
~~~

### Count notation without unit

For:

~~~text
x5
x10
x1
~~~

the adapter may preserve:

~~~text
sourceQuantityHint = 5 / 10 / 1
rawQuantityNotation = source text
~~~

but may not invent the unit.

Therefore price denominator remains unresolved.

### Unit word without explicit denominator

Labels such as:

~~~text
Hydrangea - Stem
Thai Leaves-stem
~~~

may preserve:

~~~text
sourceUnitHint = stem
~~~

but V1 does not automatically claim that the displayed price is per one stem unless a Baisch source/account rule establishes that convention.

### Provider shorthand

Shorthand such as:

~~~text
-cs
~~~

is preserved raw.

V1 does not assume it means a case until Baisch confirms the code.

## 9. Availability

Presence on the observed price sheet does not establish available quantity.

The document calls itself a Cut Flower Price List.

Therefore every row begins as:

~~~text
availabilityState = unknown
availableQuantity = unresolved
~~~

A future Baisch rule may establish stronger semantics if the wholesaler confirms that publication on the current list means orderable availability.

Even then, no quantity capacity may be invented unless the source provides quantity or a separately confirmed purchasing rule supports it.

## 10. Publication period and volatility

The source publishes a list period.

V1 may map:

~~~text
effectiveFrom  = document validFrom
effectiveUntil = document validUntil
~~~

while also preserving:

~~~text
priceSubjectToChange = true
~~~

This means the period is a source publication window, not a guarantee that the price cannot change during the period.

If Atlas receives another copy during the same period with changed terms:

- same document/source identity may remain;
- raw payload hash changes;
- the new observation is appended;
- the newest observation may become current;
- history is not overwritten.

## 11. Highlight signal

The observed sheet states that highlighted items are:

~~~text
new items OR price changes
~~~

Therefore a highlighted row may preserve:

~~~json
{
  "sourceChangeSignal": "new_item_or_price_change"
}
~~~

It may not be normalized to only "price_changed" or only "new_item".

## 12. Source categories and sourcing preference

Source headings are preserved as provider facts.

In particular:

~~~text
LOCAL
~~~

does not automatically mean:

~~~text
regional_us
us_grown
Elm-local
~~~

"Local" is relative to Baisch's own source terminology and is not yet mapped to Feast Guild's institutional sourcing geography.

Likewise a product label containing a place name, such as Oregon, does not automatically establish biological origin unless Baisch explicitly says that is what the label means.

All Baisch source-preference tiers remain unresolved until source-backed origin evidence or a governed Baisch classification rule exists.

## 13. Freight, fees, minimums, and delivery

The observed sheet does not establish:

- freight to Elm / Feast Guild;
- handling fees;
- service fees;
- full fee completeness;
- minimum order;
- order cutoff;
- requested delivery date;
- delivery promise.

Those remain unresolved.

The source price must never be treated as landed economic cost merely because it is numeric.

## 14. Raw source custody

The normalized whole document is stored as one raw Connected Source Observation:

~~~text
providerKey         = baisch_skinner
providerObjectKind  = published_price_sheet
providerObjectKey   = baisch_skinner:cut_flower_price_list:<validFrom>:<validUntil>
payload              = exact normalized document
~~~

If a revised copy is received within the same source period, the stable provider object key remains the same while the payload hash changes.

That preserves source history.

## 15. Interpretation result

For one normalized item row, the pure interpreter returns:

~~~text
rawDocumentIdentity
rowIdentity
offeringDraft
observationDraft
providerFacts
unresolvedSemantics
sourcePreference
truthBoundary
~~~

Example Carnations:

~~~json
{
  "offeringDraft": {
    "stableKey": "baisch_skinner:price_sheet_item:cut_flowers|carnations",
    "sourceLabel": "Carnations"
  },
  "observationDraft": {
    "priceAmount": 0.65,
    "currency": null,
    "priceBasisState": "unknown",
    "priceQuantity": null,
    "priceUnit": null,
    "availabilityState": "unknown"
  }
}
~~~

Example Hybrid-10 Stem:

~~~json
{
  "offeringDraft": {
    "stableKey": "baisch_skinner:price_sheet_item:cut_flowers|delphinium_sa|hybrid_10_stem",
    "sourceLabel": "Delphinium S.A. / Hybrid-10 Stem",
    "sourceUnit": "stem"
  },
  "observationDraft": {
    "priceAmount": 20.95,
    "currency": null,
    "priceBasisState": "source_explicit",
    "priceQuantity": 10,
    "priceUnit": "stem",
    "packQuantity": 10,
    "packUnit": "stem",
    "availabilityState": "unknown"
  }
}
~~~

Currency remains unresolved even when denominator is explicit.

## 16. Admission to External Supply Offer

A normalized raw sheet may be admitted row-by-row.

Admission requires:

- Connected Source provider = baisch_skinner;
- raw provider object kind = published_price_sheet;
- active supplier External Relationship supplied explicitly;
- rowKind = item;
- identityState = resolved;
- nonblank source label;
- numeric displayed price.

Rows may be admitted even when currency, availability, or denominator remain unresolved.

That is useful because External Supply Offer is a source-observation authority, not a promise that every source is immediately quotable.

The downstream candidate selector will fail closed until required economics and qualification evidence are sufficient.

## 17. Quote-time operating flow

If Baisch publishes a current sheet whenever Feast Guild needs a quote:

~~~text
florist request arrives
        ↓
retrieve current Baisch published sheet
        ↓
normalize it losslessly
        ↓
record one raw Connected Source Observation
        ↓
interpret/admit resolvable rows
        ↓
candidate gathering matches relevant flower rows
        ↓
Baisch candidates remain partially unresolved where:
  currency
  price denominator
  availability/capacity
  delivery
  freight/fees
  grow origin
  are not established
        ↓
operator/source confirmation fills only missing facts
        ↓
source policy + protected quote
~~~

This is preferable to typing the entire Baisch list into Atlas manually.

## 18. What can become static provider rules later

We should ask Baisch once, not on every quote, whether the following are stable account/source conventions:

1. currency of the published list;
2. meaning of unqualified prices by product family;
3. whether list presence means currently orderable;
4. whether a listed item implies any standard pack/bunch quantity;
5. meaning of x5/x10/x1 notation;
6. meaning of "-stem";
7. meaning of "-cs";
8. meaning of the LOCAL section;
9. freight/delivery method to our account;
10. minimum order / cutoff rules;
11. whether prices include any fees;
12. whether a same-day refreshed sheet is sufficient availability confirmation.

Those confirmations should become a versioned Baisch provider/account-semantics contract.

They should not be hardcoded from industry convention.

## 19. Candidate functions

### atlas.baisch_skinner_price_sheet_provider_contract_v1()

Returns immutable V1 source semantics.

### atlas.baisch_skinner_price_sheet_document_key_v1(jsonb)

Builds the deterministic raw Connected Source document key.

### atlas.baisch_skinner_price_sheet_connected_source_record_v1(jsonb)

Packages one normalized document for the generic Connected Source Observation writer.

### atlas.baisch_skinner_price_sheet_row_interpret_v1(jsonb,text,timestamptz)

Interprets one normalized row by rowKey.

### atlas.baisch_skinner_price_sheet_batch_interpret_v1(jsonb,timestamptz)

Interprets every item/ambiguous row without writing truth.

### atlas.baisch_skinner_price_sheet_admit_row_service_v1(uuid,text,uuid,uuid)

Admits one resolved item row from a stored raw normalized sheet into External Supply Offer truth using an explicit supplier relationship.

## 20. Validation

V1 must prove:

1. document dates and price-subject-to-change flag survive;
2. Carnations 0.65 remains currency unresolved;
3. Carnations remains price-denominator unresolved;
4. presence on the sheet does not become availability;
5. MiniCarnations 6.25 remains denominator unresolved;
6. Sunflowers x5 preserves quantity hint 5 but not a unit;
7. Mini x10 preserves quantity hint 10 but not a unit;
8. Hellebores x10 preserves quantity hint 10 but not a unit;
9. Hybrid-10 Stem yields price quantity 10, unit stem;
10. Hybrid-5 Stem yields price quantity 5, unit stem;
11. LOCAL subsection does not create regional_us or us_grown;
12. highlighted row becomes new_item_or_price_change only;
13. context_ambiguous rows do not admit automatically;
14. composite_unresolved rows do not admit automatically;
15. revised same-period source document remains append-only under the same document key;
16. one admitted Baisch row retains raw Connected Source lineage;
17. admission creates no purchase, Spend, inventory, customer offer, Order, or payment;
18. downstream protected quote remains blocked while required currency/freight/availability evidence is unresolved.

## 21. Production boundary

This is candidate architecture only.

It does not:

- define how Baisch distributes the non-PDF/normalized source;
- assume a public/private API;
- infer source units from florist industry custom;
- infer USD;
- infer availability from list presence;
- infer LOCAL as Feast Guild regional origin;
- create production migrations;
- purchase flowers.

If Baisch later gives us stronger account rules or a machine-readable source, those facts plug into this adapter rather than replacing Atlas's source-truth model.
