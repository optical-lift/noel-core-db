# Atlas Organization Expense Evidence Intake v1

**Status:** Candidate architecture  
**Scope:** Private organization receipt/document custody, intake, extraction suggestions, and handoff into canonical Spend  
**Pilot:** Camps International / Los Domos expense reporting  
**Database authority:** `noel-core-db`

## 1. Purpose

Expense reporting cannot begin with a form if the practical human behavior is taking a picture of a receipt while living the month.

This seam lets Atlas capture documentary evidence **before** it knows every expense fact.

The governing sequence is:

`private file capture -> organization evidence custody -> evidence inbox -> extraction suggestion -> human/context completion -> Spend admission -> reporting interpretation`

A receipt image is evidence. A model reading of the receipt is a suggestion. Neither becomes canonical Spend truth until the required facts are accepted through the Spend authority.

## 2. Desired human interaction

The ordinary David workflow should be capable of being this small:

1. Tap **Receipt** in Atlas.
2. Take a photo or choose a file.
3. Optionally add one short note such as `lumber for Los Domos`.
4. Leave.

Atlas may then extract merchant, date, gross amount, currency, document/factura indicators, and other visible fields. If the receipt plus David's note establish enough information to create a proposed Spend occurrence/allocation, Atlas should ask only for the unresolved facts or a concise confirmation.

The system must not force David to retype information clearly present on the document.

## 3. Existing evidence authority is reused

Live schema inspection on 2026-09-10 confirmed `atlas.evidence_records` is already a generic evidence primitive. Its schema permits arbitrary scope kinds and carries:

- scope;
- subject identity;
- evidence/source kind and stable source key;
- actor;
- JSON value;
- confidence and observed/effective times;
- provenance/metadata.

Its current authenticated read policy, however, exposes only person-scoped evidence back to that person. Organization-scoped financial evidence therefore needs a governed organization access membrane; Atlas must not casually broaden the raw table to every organization member.

The existing evidence primitive remains canonical. This tranche adds intake/process state around it rather than inventing a second receipt ontology.

## 4. Storage custody

Live storage inspection found the existing private `atlas-implementation-artifacts` bucket is audio-only. Expense documents must **not** be stored there.

The candidate storage contract is a separate private bucket:

`atlas-organization-evidence`

Expected v1 document MIME types:

- `image/jpeg`
- `image/png`
- `image/webp`
- `image/heic`
- `image/heif`
- `application/pdf`

Candidate maximum object size: 20 MB per document.

Storage paths should be organization/capture scoped, for example:

`organizations/<organization_id>/expense-evidence/<capture_id>/<object_name>`

The durable evidence record stores a private object locator plus immutable integrity metadata; it must **not** store a public URL or long-lived signed URL.

At minimum preserve:

- bucket;
- object path;
- MIME type;
- byte size;
- SHA-256;
- original filename when available.

A short-lived signed URL may be issued by an authorized server route when a permitted user needs to view the document. Signed URLs are access tokens, not evidence identity, and must not become canonical database values.

## 5. Organization evidence record shape

For a captured expense document, reuse `atlas.evidence_records` with:

- `scope_kind = organization`
- `scope_id = <organization_id>`
- `subject_domain = organization_finance`
- `subject_kind = expense_document_capture`
- `subject_id = <capture_id>`
- `evidence_kind = receipt | factura | invoice | supporting_document`
- `source_kind = atlas_storage_object`
- `source_key = <stable client/server capture key>`
- `actor_user_id = uploader`
- `value = immutable private file descriptor`

The evidence record establishes that the organization has custody of the submitted document. It does **not** establish the expense amount, merchant, purpose, reimbursement eligibility, CI category, or accounting treatment by itself.

## 6. Evidence inbox

`atlas.organization_evidence_inbox_items` owns processing state for organization evidence that has arrived but may not yet be tied to a canonical domain fact.

An inbox item carries:

- organization and optional organization unit;
- evidence record;
- capture kind;
- capturing membership;
- optional human context note;
- intake state;
- eventual admitted source authority/reference when a domain fact is created or linked.

Suggested states:

- `received` — file is safely in custody;
- `extracted` — one or more machine/parser suggestions exist;
- `needs_review` — evidence is not sufficient for safe domain admission;
- `ready_to_admit` — candidate facts are complete enough for human acceptance;
- `admitted` — evidence has been linked to canonical domain truth;
- `ignored` — authorized human says this item should not continue through expense intake.

The inbox is workflow state, not money truth.

## 7. Extraction suggestions

`atlas.organization_evidence_extraction_candidates` stores immutable extraction attempts.

An attempt may suggest fields such as:

- merchant/payee label;
- transaction/document date;
- gross amount;
- currency;
- invoice/factura/document number;
- tax or receipt markers;
- visible line items;
- likely document type.

Each attempt records extractor kind/key/version, the input document hash, candidate JSON, field-level confidence, overall confidence, and creation time.

Extraction attempts are append-only. Reprocessing with a newer model/parser creates another attempt; it does not overwrite what a prior extractor observed.

`model_suggestion != organization fact`

A low-confidence field remains unresolved. A high-confidence field can reduce human typing, but database admission into Spend still occurs under the Spend command's authority.

## 8. Context is complementary evidence

A human note such as `lumber for Los Domos` is often information the receipt itself cannot contain.

The intake item therefore preserves `context_note` separately from machine extraction. The Spend proposal can combine:

- document-observed fields;
- human-supplied context;
- known organization/unit context;
- known payer membership.

It must preserve provenance so a reviewer can tell which field came from which source.

## 9. Proposed Spend packet

The intake layer may derive a **proposal packet** for the existing `record_organization_spend_api_v1` contract. A proposed packet may contain:

- `occurredOn` from receipt extraction;
- `grossAmount` from receipt extraction;
- `currency` from receipt extraction;
- `payeeLabel` from receipt extraction;
- `fundingKind` from user/organization context;
- `payerMembershipId` from the signed-in user or explicit authorized choice;
- `organizationUnitId` from capture context;
- `operationalPurpose` from the user's note or later question;
- evidence/capture provenance.

The proposal itself does not create Spend.

If one gross receipt has multiple purposes, Spend admission creates one occurrence and multiple allocations; the evidence remains one document linked to the occurrence and, where appropriate, its allocations.

## 10. Missing-field behavior

Atlas should ask only questions that remain materially unresolved.

Examples:

- Receipt clearly shows `Home Depot`, `1,840 MXN`, and date; David wrote `lumber for Los Domos` -> no need to ask merchant, amount, currency, date, or purpose again.
- Receipt clearly shows amount/date/merchant but David gave no purpose -> ask only `What was this for?`
- Receipt is blurry and amount has two plausible readings -> ask only for the amount.
- Receipt contains mixed personal/business or mixed-purpose items -> ask for the relevant split, not the entire receipt again.

A captured document must remain safely in the inbox even when no safe Spend fact can yet be created.

## 11. Access boundary

Financial evidence can contain card fragments, tax identifiers, addresses, and sensitive purchase details. Ordinary organization membership must not automatically imply raw receipt access.

For v1:

- no public storage objects;
- no direct authenticated storage-object listing;
- no broad organization SELECT policy added to `atlas.evidence_records`;
- inbox reads go through governed APIs;
- raw file access goes through a server authorization membrane that can later honor finance/treasurer-specific permissions;
- the database returns stable evidence/capture IDs and safe metadata, not reusable storage URLs.

The exact finance permission vocabulary should bind to Atlas's organization authorization architecture before release rather than being invented here.

## 12. Registration command

`register_organization_expense_document_api_v1(...)` should:

1. require authenticated active organization membership;
2. verify optional organization unit belongs to the organization;
3. validate capture kind and private-file descriptor shape;
4. validate SHA-256, MIME type, and file size contract;
5. register one organization-scoped `atlas.evidence_records` row;
6. register one inbox item;
7. make retries idempotent by organization + stable source key;
8. reject a retry whose file descriptor does not match the already-custodied object;
9. return capture/evidence IDs without exposing a public or long-lived file URL.

The function assumes the server/storage layer has already placed the bytes at the supplied private object locator. File upload and database registration must be coordinated so failed registrations do not leave uncontrolled orphaned objects indefinitely.

## 13. Extraction command

`record_organization_evidence_extraction_internal_v1(...)` is an internal/service operation. It should:

- require the evidence/inbox scope to agree;
- require candidate JSON to be an object;
- preserve extractor identity/version and input SHA;
- be idempotent for an exact extractor attempt;
- reject same-attempt replay with different candidate content;
- remain append-only;
- never create Spend, reimbursement, CI category, or accounting truth.

## 14. Read projection

An authenticated organization member may use a governed inbox projection to see safe intake status such as:

- capture ID;
- capture/document kind;
- original filename;
- MIME type;
- capture time;
- context note;
- process state;
- latest extraction suggestion summary/confidence;
- whether a canonical source has been admitted.

The projection should omit the private object path. Viewing bytes requires a separately authorized signed-URL/server response.

## 15. Camps International relationship

Once a receipt-backed Spend allocation exists, the existing Expense Report Admission layer decides whether it belongs in the CI report, what CI category applies, reimbursement treatment, factura field, exchange rate, and report amount.

The evidence intake layer does not know that `Facilities` is a CI category and does not know what Kirk will post into QuickBooks.

The full chain becomes:

`receipt photo -> organization evidence -> extraction suggestion + David context -> Spend occurrence/allocation -> CI report admission -> CI category -> USD line -> category subtotal -> Kirk accounting handoff`

## 16. Deliberately not included yet

- no production storage bucket creation;
- no broad evidence RLS change;
- no OCR/model provider hard-coding;
- no automatic acceptance threshold that turns model output into money truth;
- no QuickBooks attachment upload;
- no reimbursement payment lifecycle;
- no exact workbook renderer;
- no production migration or deployment.

## 17. Acceptance proof

The proof must establish:

1. one private document can be registered before any Spend fact exists;
2. exact source-key replay is idempotent;
3. conflicting replay under the same source key is rejected;
4. evidence scope, organization unit, and capturing membership cannot cross organizations;
5. extraction is immutable suggestion state, not Spend truth;
6. an extraction can suggest merchant/date/amount/currency while a human note supplies purpose;
7. missing purpose produces a narrow unresolved question rather than discarding the receipt;
8. one evidence item can later support one gross Spend occurrence with multiple allocations;
9. safe inbox reads do not expose private storage paths or signed URLs;
10. proof objects leave no production state after rollback.

## 18. Migration custody

This remains candidate/proof work on `feature/atlas-organization-expense-reporting-v1`. Canonical migration identity, private storage bucket creation, RLS/permission release, application upload route, and deployment must occur only after reconciliation with current `main` and the governed database release process.
