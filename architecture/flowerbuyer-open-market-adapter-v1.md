# Flowerbuyer Open Market Adapter v1

**Status:** candidate-only provider adapter  
**Date:** 2026-09-24  
**Parent:** architecture/atlas-supplier-source-ingestion-v1.md  
**Downstream:** External Supply Offer -> Feast Guild Flower Candidate Gathering  
**Transport boundary:** retrieval method intentionally unresolved pending Flowerbuyer authorization

## 1. Purpose

The authenticated Flowerbuyer Open Market currently exposes structured `productdetails` data containing `ProductsDetail.OpenMarketData`.

This is sufficient to define a provider interpretation contract without assuming how Atlas will retrieve that data in production.

V1 therefore separates:

~~~text
transport
  official API / feed
  authorized portal endpoint
  authorized browser capture
  email fallback

from

provider semantics
  OpenMarketData record
  -> raw Connected Source Observation
  -> Flowerbuyer interpretation draft
  -> External Supply Offering / Observation admission
~~~

If Flowerbuyer later requires a different transport, only the transport adapter changes.

## 2. What has been observed

Two authenticated Open Market records establish a repeatable relationship between the structured payload and the customer-facing table.

Observed Acacia record:

~~~text
CustomerPrice        907
Pack                 20
StemOrBunch          BU
BoxesForSale         2
displayed unit price $9.07 / BU
displayed box price  $181.40
delivery date        09/26/2026
~~~

Observed Rose record:

~~~text
CustomerPrice        118
Pack                 125
StemOrBunch          ST
BoxesForSale         2
displayed unit price $1.18 / ST
derived box price    $147.50
delivery date        09/26/2026
~~~

Therefore V1 establishes the provider rule:

~~~text
displayed account unit price
=
CustomerPrice / 100

box cost
=
displayed account unit price * Pack
~~~

This rule is provider-specific and may be versioned if Flowerbuyer changes its payload.

## 3. Stable identities

### Catalog/product identity

Use:

`FBProductCode`

as the strongest observed Flowerbuyer product identity.

Provider stable key:

~~~text
flowerbuyer:product:<FBProductCode>
~~~

### Volatile market-listing identity

Use:

- `AuctionProductCode`;
- auction date;
- delivery date.

Raw provider object key:

~~~text
flowerbuyer:open_market:
<AuctionProductCode>:
<auction-date>:
<delivery-date>
~~~

Price or box availability changes under the same market-listing identity produce a new Connected Source Observation payload hash rather than rewriting history.

## 4. Raw source custody

Raw Open Market records are stored unchanged inside:

`atlas.connected_source_observations`

with:

~~~text
provider_key        = flowerbuyer
provider_object_kind= market_listing
provider_object_key = Flowerbuyer market-listing key
payload             = exact OpenMarketData record
~~~

Provenance may add:

- capture method;
- authenticated/account-scoped flag;
- source surface = open_market;
- request/capture time;
- transport version.

Reusable cookies, passwords, bearer tokens, session IDs, JWTs, and other authentication material must never enter raw payload/provenance.

## 5. Transport modes

V1 defines no required retrieval method.

Permitted architecture modes are:

### official_api

Use if Flowerbuyer supplies a supported API/feed.

### authorized_portal_endpoint

Use the structured portal endpoint only if Flowerbuyer permits automated account retrieval.

### authorized_browser_capture

Use an authenticated browser/computer workflow if that is the supported/authorized account-access method.

### email_fallback

Use recurring Flowerbuyer market/availability email as a lower-fidelity source.

All modes converge on the same raw observation and interpretation contracts.

Atlas must not bypass access controls, simulate authorization it does not possess, or assume undocumented automation rights.

## 6. Commercial price semantics

### Authoritative account-visible price

`CustomerPrice` is interpreted as integer/sub-dollar hundredths:

~~~text
CustomerPrice 907 -> USD 9.07
CustomerPrice 118 -> USD 1.18
~~~

The customer-facing Open Market table confirms those values.

V1 treats this as the Flowerbuyer account acquisition unit price.

### Pricing unit

Map:

~~~text
StemOrBunch = ST -> stem
StemOrBunch = BU -> bunch
~~~

Unknown codes remain unresolved.

### Price quantity

The displayed price is per one pricing unit:

~~~text
priceQuantity = 1
priceUnit     = stem | bunch
~~~

### Box pack

`Pack` is the count of pricing units per box.

Therefore:

~~~text
packQuantity = Pack
packUnit     = priceUnit
boxCost      = accountUnitPrice * Pack
~~~

### Internal price components

`UnitPrice` and `DirectShippingCharge` are preserved as raw Flowerbuyer component fields.

They are **not** used to reconstruct the acquisition price.

Across the two observed records:

~~~text
UnitPrice + DirectShippingCharge != CustomerPrice
~~~

so an additional provider component/rounding/fee may exist.

Atlas must not invent the residual's meaning.

## 7. Freight semantics

The observed rows contain:

~~~text
Comment = "FedEx shipping cost of $xx.xx included in price."
~~~

When that source text explicitly states shipping is included, V1 may set:

~~~json
{
  "freightIncluded": true,
  "freightBasis": "flowerbuyer_source_comment"
}
~~~

No second freight charge is added.

`DirectShippingCharge` is preserved for audit but is not separately added when the displayed CustomerPrice is the authoritative account price and the source says freight is included.

If the source comment does not establish shipping inclusion, freight remains unresolved.

## 8. Fee-completeness boundary

Nothing observed so far establishes that Flowerbuyer `CustomerPrice` includes every possible account/order fee beyond the explicitly included shipping statement.

Therefore V1 sets:

~~~text
additionalFeesComplete = false
~~~

unless a later source/account rule explicitly establishes completeness.

This means the current adapter can produce a highly informative source offer but will still fail closed for protected automatic quoting when unknown mandatory fees remain.

That is intentional.

## 9. Availability

V1 interprets account-visible purchasability using:

- `BoxesForSale`;
- `SoldOut`;
- `AllowPurchasing`;
- `ACAllowPurchasing`.

A listing is account-available only when:

~~~text
BoxesForSale > 0
AND SoldOut = N
AND AllowPurchasing = Y
AND ACAllowPurchasing = Y
~~~

Observable quantity capacity:

~~~text
availableQuantity
=
BoxesForSale * Pack

availableUnit
=
pricing unit
~~~

Examples:

~~~text
Acacia:
2 boxes * 20 bunches = 40 bunches observable capacity

Rose:
2 boxes * 125 stems = 250 stems observable capacity
~~~

No broader grower inventory is implied.

## 10. Dates

Preserve separately:

- `AuctionDate`;
- `StrAuctionDate`;
- `DeliverDate`;
- `StrDeliveryDate`;
- `OrderByDate`.

`StrDeliveryDate` is admitted as the source-stated delivery/arrival date for the listing.

`OrderByDate` is preserved as source cutoff text.

V1 must not infer a cutoff time when only a date/text is supplied.

The price/auction date is not itself a delivery promise.

## 11. Product/specification fields

Safe provider facts include:

- `ProductName`;
- `ProductFilter`;
- `ColorFilter`;
- `ColorDescription`;
- `BudSize`;
- `FBProductCode`;
- `ProductKeyId`;
- `GrowerNumber`;
- `GrowerRating`.

V1 may parse exact structural tokens from `ProductName` where the token is explicit:

- single metric stem length such as `40cm`;
- explicit bunch configuration such as `25st/bu`.

A range or imperial dimension may be preserved raw until a separate governed conversion/normalization rule is established.

The adapter does not fuzzy-match flower identity.

## 12. Grower and origin boundary

Observed logistics fields include:

- `CountryCode`;
- `Location`;
- `OriginatingCity`;
- `PointOfEntry`.

The Rose record demonstrates that these cannot safely be treated as biological grow-origin evidence.

For example:

~~~text
CountryCode     = US
Location        = USA
OriginatingCity = Miami3
PointOfEntry    = MI
~~~

does **not** establish that the rose was U.S.-grown.

V1 therefore stores those fields under logistics/source context only.

They do not create:

- `elm_owned_or_grown`;
- `regional_us`;
- `us_grown`;
- `imported`.

Until Flowerbuyer provides an explicit grow-origin fact or a separately admitted grower-origin mapping, the Feast Guild source-preference tier remains unresolved.

`GrowerNumber` is a provider grower reference, not an origin classification.

## 13. Direct shipping fields

Preserve without over-interpretation:

- `DirectShipping`;
- `DirectShippingCharge`;
- `FedExOnly`;
- `FedExGround`;
- `FedExDisplay`;
- `HundredPercentShipper`;
- `RepackedBox`;
- `ProductSource`.

These may later support provider-specific logistics rules.

V1 does not infer their undocumented meanings beyond literal source values.

## 14. Interpretation draft

The pure provider interpreter returns:

~~~text
rawRecordIdentity
offeringDraft
observationDraft
providerFacts
unresolvedSemantics
truthBoundary
~~~

### Offering draft

~~~json
{
  "stableKey": "flowerbuyer:product:30220",
  "sourceItemKey": "30220",
  "sourceLabel": "Rose Assorted 40cm 25st/bu",
  "offeringKind": "cut_flower",
  "sourceUnit": "stem",
  "specification": {
    "productLabel": "Rose Assorted 40cm 25st/bu",
    "providerProductFilter": "Rose Assorted",
    "color": "Assorted",
    "stemLengthCm": 40,
    "stemsPerBunch": 25
  }
}
~~~

### Observation draft

~~~json
{
  "priceAmount": 1.18,
  "currency": "USD",
  "priceBasisState": "source_explicit",
  "priceQuantity": 1,
  "priceUnit": "stem",
  "packQuantity": 125,
  "packUnit": "stem",
  "availabilityState": "available",
  "terms": {
    "freightIncluded": true,
    "additionalFeesComplete": false
  },
  "sourceContext": {
    "availableQuantity": 250,
    "availableQuantityUnit": "stem",
    "deliveryDate": "2026-09-26",
    "providerGrowerRef": "4088",
    "providerCountryCode": "US",
    "providerLocation": "USA",
    "providerOriginatingCity": "Miami3",
    "providerPointOfEntry": "MI"
  }
}
~~~

No supplier relationship ID is invented by the interpreter.

## 15. Provider versus supplier

Connected Source identity:

~~~text
Flowerbuyer account
~~~

does not automatically answer:

~~~text
Who is the legal/economic supplier of record for this listing?
~~~

The observed `GrowerNumber` likewise does not establish vendor-of-record status.

Admission into `atlas.external_supply_offerings` therefore still requires an explicit resolved supplier External Relationship.

The adapter may prepare the commercial observation before that resolution but must not fabricate it.

## 16. Current automatic-quote consequence

With the observed Flowerbuyer payload, Atlas can already establish:

- product identity;
- account-visible price;
- pricing unit;
- box pack;
- finite box quantity;
- finite available unit quantity;
- purchase-state flags;
- delivery date;
- grower reference;
- shipping-included evidence when stated.

It cannot yet establish:

- actual grow country/state for Feast Guild preference;
- full account/order fee completeness;
- provider-authorized automated retrieval mode.

Therefore a Flowerbuyer record can become a strong candidate source observation, but protected automatic quoting remains fail-closed until required fee completeness and any necessary source-preference evidence are established.

## 17. Refresh and staleness

Open Market inventory is volatile.

V1 stores every changed raw payload as a new append-only observation.

No permanent freshness TTL is invented yet.

Once Flowerbuyer specifies the supported retrieval mechanism and practical refresh limits, Atlas can add a provider synchronization policy governing:

- scheduled refresh cadence;
- quote-time refresh;
- pre-purchase revalidation;
- stale-observation threshold.

Until then, the observation timestamp is preserved and consumers may treat stale age as unresolved according to their own governed policy.

## 18. Email relationship

The recurring Flowerbuyer email remains useful as:

- discovery;
- fallback pricing evidence;
- outage fallback;
- cross-check against Open Market.

It is not assumed to contain the same availability, delivery, grower, or shipping completeness as Open Market.

Email and Open Market observations should share Flowerbuyer product identity where safely resolvable but retain distinct raw source observations.

## 19. Candidate functions

### atlas.flowerbuyer_open_market_provider_contract_v1()

Returns the immutable V1 semantics established from observed Open Market data.

### atlas.flowerbuyer_open_market_record_key_v1(jsonb)

Builds the deterministic raw Connected Source provider object key.

### atlas.flowerbuyer_open_market_record_interpret_v1(jsonb,timestamptz)

Pure, read-only interpretation of one raw OpenMarketData record into an admission draft.

### atlas.flowerbuyer_open_market_batch_interpret_v1(jsonb,timestamptz)

Interprets an array without writing source or commercial truth.

## 20. Validation

V1 must prove:

1. `CustomerPrice=907` becomes USD 9.07/bunch.
2. `Pack=20` means 20 bunches/box for that record.
3. two boxes produce 40 bunches observable capacity.
4. box cost derives to USD 181.40.
5. `CustomerPrice=118` becomes USD 1.18/stem.
6. `Pack=125` means 125 stems/box.
7. two boxes produce 250 stems observable capacity.
8. box cost derives to USD 147.50.
9. `25st/bu` is preserved as 25 stems/bunch.
10. `40cm` is preserved as 40 cm.
11. shipping-included source comment sets freightIncluded=true.
12. DirectShippingCharge is not added again.
13. UnitPrice is not substituted for CustomerPrice.
14. additionalFeesComplete remains false absent explicit provider rule.
15. sold-out or non-purchasable listings do not become available.
16. `CountryCode=US` does not create `us_grown`.
17. `Location=USA` does not create `us_grown`.
18. `OriginatingCity=Miami3` does not create grow-origin truth.
19. unknown StemOrBunch code remains unresolved.
20. malformed price fields remain unresolved rather than zero.
21. raw provider identity remains deterministic.
22. batch interpretation creates no Connected Source Observation, External Supply Offer, purchase, Spend, inventory, Order, payment, or fulfillment truth.

## 21. Production boundary

This is architecture + candidate interpretation only.

It does not:

- call the undocumented Flowerbuyer endpoint;
- authenticate to Flowerbuyer;
- create a scheduled poller;
- assert automation permission;
- create production migrations;
- admit supplier truth automatically;
- purchase flowers.

When Flowerbuyer tells us its supported integration method, Atlas should plug that transport into this adapter rather than redesigning provider semantics.
