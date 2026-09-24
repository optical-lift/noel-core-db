# Atlas Supplier Source Ingestion v1

**Status:** implementation-preparation contract  
**Date:** 2026-09-23  
**Parent:** `architecture/atlas-external-supply-offer-v1.md`  
**Initial providers:** DVFlora, Mellano, Flowerbuyer  
**First operating organization:** Elm Farm

## 1. Purpose

Marshall is creating wholesale accounts with three supply channels:

- DVFlora;
- Mellano;
- Flowerbuyer.

Atlas must be ready to ingest what those accounts reveal without:

- putting credentials in ordinary metadata;
- treating a provider page as canonical commercial truth merely because it was scraped/read;
- losing the exact source payload;
- confusing a marketplace/provider with the actual supplier/vendor of record;
- inventing price units, availability, freight, or pack semantics;
- rewriting historical observations when a supplier changes price;
- allowing a source listing to create a purchase, Spend, owned inventory, or customer-facing price.

The ingestion path is therefore:

~~~text
organization account
→ Connected Source
→ Vault-backed credential(s)
→ raw Connected Source Observation
→ explicit interpretation/admission
→ resolved supplier External Relationship
→ External Supply Offering
→ Supply Offer Observation
→ later fulfillment-economics calculation
~~~

The raw source layer and interpreted commercial-truth layer remain distinct.

## 2. Existing Atlas authority reused

Atlas already has:

### Connected Source identity

`atlas.connected_sources`

This owns an Organization's connection to an external provider/account.

For Elm, each of the three accounts should become a separate organization-connected source. If the account is truly Elm-unit-specific, bind it to the Elm organization unit after registration. If it is intentionally organization-wide, the supplier-observation bridge may consume it across fitting units while preserving the source's organization custody.

### Secret custody

`atlas.store_connected_source_secret_service_v1`

Reusable credentials belong in Vault-backed secret custody.

Passwords, API keys, access tokens, refresh tokens, client secrets, and similar reusable credentials must never be stored in:

- connected-source metadata;
- supplier metadata;
- Evidence JSON;
- supply-offer metadata;
- GitHub fixtures;
- screenshots or exported source artifacts committed to source control.

### Raw provider observations

`atlas.connected_source_observations`

Atlas already stores append-only provider observations with:

- connected source;
- provider object kind;
- provider object key;
- provider-created time if supplied;
- Atlas observed time;
- exact JSON payload;
- SHA-256 payload hash;
- provenance.

`atlas.record_connected_source_observation_batch_service_v1` already gives us idempotent raw batch ingestion with a maximum of 500 records per call.

That means the new supplier-economics system does not need a second raw-import staging table.

## 3. Provider registration profile

When Marshall finishes each account, capture only the facts needed to register it.

### DVFlora

Proposed provider key:

`dvflora`

Display label:

`DVFlora Wholesale`

Desired capability probes:

- account catalog access;
- account-specific price visibility;
- availability visibility;
- pack/bunch/case information;
- grower/origin information;
- American-grown designation where supplied;
- shipping/freight quote visibility;
- order minimum/cutoff visibility;
- export/download/API capability, if any.

Do not mark a capability true until the live account proves it.

### Mellano

Proposed provider key:

`mellano`

Display label:

`Mellano & Company`

Desired capability probes:

- current wholesale catalog;
- account pricing;
- farm-direct origin/grower identity;
- quantity/pack basis;
- availability;
- shipment method/cost;
- minimums/cutoffs;
- export/download/API capability, if any.

### Flowerbuyer

Proposed provider key:

`flowerbuyer`

Display label:

`Flowerbuyer`

Desired capability probes:

- live auction/listing prices;
- pack quantity;
- FOB/hub location;
- farm/grower/origin;
- availability/quantity offered;
- delivery/tender/shipping terms;
- account-specific fees;
- historical/market report access;
- export/download/API capability, if any.

Flowerbuyer may expose a marketplace lot whose economic source/grower differs from Flowerbuyer itself. Provider identity and supplier identity must therefore remain separate.

## 4. Account facts Marshall should return

For each provider, we need:

- account/provider customer ID if visible;
- login email/username;
- account status;
- resale/tax-exemption status if displayed;
- ship-to location(s);
- whether pricing is account-specific;
- whether the provider supports exports/downloads;
- whether an API/token exists;
- whether pricing/availability can be filtered by origin;
- whether American-grown is explicitly labeled;
- whether freight/shipping is shown before checkout;
- whether minimums/cutoffs are visible;
- screenshots or exports of one representative product page/listing and one cart/shipping screen, if allowed by the provider.

The login password itself should be handed to secure credential storage, not written into the workbench notes.

## 5. Raw observation kinds

Use the existing connected-source observation layer. Initial provider object kinds:

### `catalog_listing`

Stable identity and descriptive facts about an item/listing.

Preserve:

- provider SKU/item/lot key;
- provider label;
- source category;
- grower/brand if displayed;
- origin country/state if displayed;
- grade/length/color/variety;
- raw unit/pack text;
- source URL/path/locator when appropriate;
- flags such as American Grown only when explicitly source-backed.

### `price_listing`

A price observation.

Preserve:

- raw numeric price;
- displayed currency, if explicit;
- raw price-basis text;
- quantity denominator, if explicit;
- pack/bunch/case size, if explicit;
- tier/volume threshold;
- sale/promotional status;
- effective/expiry information if supplied.

### `availability_listing`

A real availability observation only when the provider actually exposes availability.

Preserve:

- available/unavailable/limited;
- quantity available if shown;
- expected/restock date if shown;
- hub/location;
- observed timestamp.

Presence in a catalog or price list alone is not availability.

### `shipping_quote`

A source-backed freight/logistics observation.

Preserve:

- origin/hub;
- destination;
- shipping method;
- box count/weight if supplied;
- freight amount;
- tender/handling fees;
- delivery date/window;
- quote expiry;
- whether cold-chain/refrigerated service is stated.

### `account_terms`

Supplier/account-wide terms.

Preserve:

- order minimum;
- cutoff;
- payment terms;
- account-level freight rules;
- pickup rules;
- service fees;
- tax/resale treatment;
- any provider-stated validity/effective date.

### `market_listing`

Use when a marketplace listing combines product, source, price, quantity, and availability in one volatile object and decomposing the raw provider record would lose source meaning.

Flowerbuyer auction lots are the likely first example.

Interpretation may later produce multiple normalized truths from one raw market listing.

## 6. Raw payload rule

Raw provider payloads should remain as close as practical to what the provider exposed.

The ingestion layer may add wrapper metadata such as:

~~~json
{
  "providerKey": "flowerbuyer",
  "captureMethod": "manual_export",
  "sourceSurface": "auction",
  "accountScoped": true,
  "capturedAt": "..."
}
~~~

It must not silently replace provider text with Atlas interpretations.

For example:

Provider source:

~~~text
Carn Std Assorted 45cm
300 stems
0.30
Miami
~~~

Raw observation should preserve those source facts.

It should not be rewritten in-place as:

~~~text
standard carnation, USD 0.30/stem, available in Missouri
~~~

unless every added meaning is separately supported.

## 7. Stable provider keys

Every raw provider observation requires a `provider_object_key`.

Preferred key order:

1. provider-issued immutable SKU/listing/lot ID;
2. provider-issued SKU plus tier/effective context;
3. source document ID + row key;
4. deterministic Atlas source key derived from exact source identity fields.

Never use display name alone when the provider exposes a stronger key.

Price changes should generally produce a new payload hash under the same stable provider object key, preserving observation history.

Volatile auction lots may instead have one provider object key per lot/listing.

## 8. Provider identity versus supplier identity

The account being connected is not automatically the economic supplier represented by every listing.

Examples:

~~~text
Connected Source = Flowerbuyer account
marketplace listing grower = Farm X, Colombia
vendor of record = may be Flowerbuyer or another source depending on transaction terms
~~~

~~~text
Connected Source = DVFlora account
listing origin = Mellano / California
vendor of record = DVFlora unless source/transaction evidence establishes otherwise
~~~

Atlas therefore requires an explicit resolved `supplier_relationship_id` when promoting a raw provider observation into External Supply Offering truth.

Origin/grower may be recorded separately in source context until its legal/economic role is known.

## 9. Admission bridge

The External Supply Offer candidate must support a direct link:

`external_supply_offer_observations.connected_source_observation_id`

This preserves the movement:

~~~text
raw source observation
→ interpreted supplier commercial observation
~~~

The interpreted observation may normalize fields only where source evidence or explicit authorized confirmation supports the normalization.

Examples:

### Safe

~~~text
source: "$0.40 / stem"
→ price_amount = 0.40
→ price_quantity = 1
→ price_unit = stem
→ price_basis_state = source_explicit
~~~

### Not safe

~~~text
source: "Carnations 0.65"
→ price_amount = 0.65
→ price_basis_state = unknown
~~~

unless another provider rule/source establishes the denominator.

## 10. American-grown sourcing facts

The three sources are being opened partly so Atlas can enforce a domestic-first sourcing preference.

Do not derive domestic origin from provider name, warehouse location, or seller location.

A line may be marked American-grown only from source-backed origin/grower evidence.

The normalized source context should be able to preserve:

- country of origin;
- U.S. state of origin;
- grower;
- certification/label if supplied;
- whether the origin is source-explicit versus human-confirmed.

Later fulfillment policy may prefer:

~~~text
Elm / Missouri
→ regional U.S.
→ other American-grown
→ imported
~~~

but ingestion owns only the source facts, not the sourcing decision.

## 11. Credential handling

When Marshall returns with an account:

1. register the organization connected source;
2. use an account identifier as `provider_account_key`;
3. store login/API secret through Vault-backed secret custody;
4. keep a non-secret account hint such as the login email only where appropriate;
5. record actual capabilities after inspecting the account;
6. never paste reusable credentials into GitHub, supplier-source fixtures, source observations, or chat-generated architecture docs.

If a provider offers API credentials, store those separately from browser-login credentials by credential kind.

## 12. Initial ingestion modes

We should support these in this order:

### Mode A — file/export ingest

Preferred when provider can export CSV/XLSX/PDF/catalog data.

Advantages:

- inspectable;
- repeatable;
- deterministic;
- easy to hash and re-run;
- independent of brittle page layout.

### Mode B — structured browser/account capture

Use when pricing exists only behind the account portal and no export exists.

Capture source rows into the raw connected-source observation contract before normalization.

### Mode C — manual operator admission

For one-off quotes, emails, phone-confirmed terms, or source pages that cannot be systematically exported.

The Reality Sentence / Implementation Workbench may eventually create the typed interpretation, but the evidence/source must still be preserved.

### Mode D — API/automated sync

Use only if a provider exposes a supported API or stable machine-readable endpoint and Elm is authorized to use it.

Do not assume scraping rights or bypass provider access controls.

## 13. First synchronization target

The first useful dataset does not need every flower.

For each of the three accounts, ingest enough current rows to answer the Wickman's/Flowerama test across common commodity categories:

- carnations / mini carnations;
- roses;
- alstroemeria;
- chrysanthemums/pomps;
- snapdragons;
- lisianthus;
- hydrangea;
- sunflowers;
- eucalyptus/greens;
- one or two specialty/local-American items.

For every line we want, where the provider supplies it:

- price;
- price basis;
- pack quantity;
- source/origin;
- availability;
- order minimum;
- freight/shipping basis;
- effective/observed time.

This gives Atlas enough breadth to test the business model without prematurely ingesting an entire global catalog.

## 14. Snapshot cadence

Supplier pricing and availability are volatile.

Initial operating cadence:

- capture when Marshall first opens the account;
- capture again when Wickman's/Flowerama sample baskets arrive;
- capture at order-decision time;
- later establish a scheduled cadence only after we know how frequently each source changes and what the provider permits.

Do not overwrite previous observations.

The connected-source payload hash already lets repeated identical observations deduplicate while preserving changed snapshots.

## 15. Failure states

Atlas should distinguish:

- source account not connected;
- credentials invalid/reauthorization required;
- source accessible but pricing hidden;
- source row present but price basis unknown;
- source price known but availability unknown;
- availability known but freight unknown;
- source eligible but supplier identity unresolved;
- supplier resolved but item compatibility unresolved;
- stale observation;
- provider unavailable.

None of those should collapse to zero cost, available, or equivalent.

## 16. What we should be ready to do the moment accounts exist

For each provider:

1. register the Connected Source;
2. secure credentials;
3. inspect the live account's data surfaces;
4. record the actual capabilities;
5. capture one raw representative batch;
6. prove idempotent re-ingestion;
7. interpret three sample listings into External Supply Offering + Supply Offer Observation;
8. verify raw-observation lineage survives;
9. verify no purchase/Spend/inventory/sell-price truth is created;
10. expand to the commodity test basket.

At that point the supplier side of the Fulfillment Economics Kernel has real data rather than architecture placeholders.
