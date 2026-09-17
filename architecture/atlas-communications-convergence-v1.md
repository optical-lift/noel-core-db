# Atlas Communications Convergence v1

**Status:** Governing structural-convergence architecture  
**Audit date:** 2026-09-17  
**Pinned database source:** `optical-lift/noel-core-db@d7ee698c92341f21533bcb246f6e2115af99ebee`  
**App source observed:** `optical-lift/atlas@3fa5588bf8911e1a6481e062127e825cba7d6808`  
**Production database:** `noel-core` read-only audit only; no production mutation is authorized by this document.

## 1. Purpose

Atlas Communications has accumulated several individually reasonable generations of architecture without completing the cutover between them.

The result is not primarily a Correspondence UI defect. It is a structural convergence defect:

- immutable Communication Event custody exists;
- provider-independent Communication Conversation identity exists;
- Correspondence Identity exists;
- actionability evidence exists;
- Institutional Conversation / Response Case machinery exists;
- personal communication evidence exists;
- the application still consumes an endpoint-selected Institutional Mailroom read path.

The newer abstractions were added, but the mature institutional writer/read path continued to create and expose reality through the older branch.

This document establishes the correction:

> **All communication enters one provider-independent Communication reality first. Institutional response, Company Work, relationship meaning, commercial meaning, and other consequences attach to that reality; they do not define communication identity.**

The convergence is structural. It is not a request to redesign `/communications` in place.

---

## 2. Governing reality artery

The canonical communications artery is:

```text
Principal / Organization custody
→ Communication Endpoint
→ Connected Source
→ transport / synchronization
→ immutable Communication Event evidence
→ source-local Communication Thread
→ durable Communication Conversation
→ participant / identity / relationship resolution
→ attention / actionability
→ optional governed consequence
→ Correspondence notebook projection
```

Possible consequences include:

```text
Communication Conversation
  ├─→ institutional response case, when warranted
  ├─→ Company Work, when warranted
  ├─→ external-relationship evidence
  ├─→ Demand / Sale / payment / other domain evidence through that domain's membrane
  ├─→ Principal or institutional attention through its own admission rule
  └─→ no consequential state at all when the communication is merely informational
```

No consequence is permitted to become the durable identity of the communication itself.

---

## 3. Canonical nouns and authority

### Canonical / preserve

- **Communication Endpoint** — durable addressable communication identity; endpoint is not Person/Organization identity.
- **Connected Source** — externally authorized provider/account custody; source is not endpoint.
- **Communication Event** — immutable source-observed communication evidence.
- **Communication Thread** — source/provider-local continuity evidence.
- **Communication Conversation** — durable provider-independent Atlas conversation identity.
- **Correspondence Identity** — recognizable persona/endeavor used to present and route correspondence; does not replace endpoint or entity identity.
- **participant / identity / relationship reconciliation** — evidence-backed resolution around the event/conversation.
- **communication attention history** — evidence of what a human has opened/noticed; visibility is not responsibility.
- **communication actionability** — whether communication warrants human/institutional consequence; receipt alone is not obligation.
- **outbound operation / transport attempt evidence** — Atlas-owned send intent/authority with provider transport evidence beneath it.

### Consequence domains / preserve but subordinate to Communication Conversation

- Institutional Response Case;
- Company Work and Work Evidence links;
- buyer/external relationship evidence;
- domain-specific uptake such as Demand, Sale, payment, calendar, or another governed state.

These remain authoritative only for their own consequence. They do not own the underlying conversation identity.

### Transitional / compatibility

- `atlas.institutional_conversations`;
- `atlas.institutional_conversation_source_threads`;
- `atlas.institutional_conversation_endpoints`;
- `atlas.institutional_conversation_messages`;
- `atlas.institutional_conversation_roots`;
- Institutional Conversation IDs used by current response/send/work APIs;
- endpoint-scoped shared-inbox/detail APIs;
- endpoint-first Mailroom product state.

They may remain while cutover is incomplete, but new architecture must not treat them as the conceptual root.

---

## 4. Audit snapshot: production is split

Read-only production inspection on 2026-09-17 showed:

```text
communication_events                         4,208
  Principal-custodied events                 4,183
  Organization-custodied events                 25

communication_threads                           32
institutional_conversations                      23
institutional_conversation_response_cases        23
communication_conversations                       7
communication_actionability_assessments            0
```

The common Communication Conversation root currently contains:

```text
Principal conversations       0
Organization conversations    7
Total                         7
```

The provider-independence migration backfilled the seven Institutional Conversations that existed when it ran into `communication_conversations` and `institutional_conversation_roots`.

Production now contains:

```text
Institutional Conversations bridged to common root      7
Institutional Conversations not bridged                16
```

The date boundary is diagnostic:

```text
2026-09-11 institutional conversations    7 total / 7 bridged
2026-09-12 institutional conversations    8 total / 0 bridged
2026-09-13 institutional conversations    3 total / 0 bridged
2026-09-14 institutional conversations    5 total / 0 bridged
```

This proves the provider-independent Conversation migration performed a one-time compatibility backfill but the live institutional admission writer was never cut over to maintain that invariant for new traffic.

This is not merely historical debt. The active writer continues to create new Institutional Conversation identity without creating the common durable root.

---

## 5. Current writer divergence

### Organization ingest v2

Current production `ingest_organization_communication_events_service_v2(...)` performs:

```text
ingest organization communication evidence
→ for each admitted Communication Event
→ ensure_institutional_conversation_for_communication_event_service_v1(event)
```

The institutional admission function creates/reuses:

- `institutional_conversations`;
- `institutional_conversation_endpoints`;
- `institutional_conversation_source_threads`;
- `institutional_conversation_messages`.

It does not create or bind `communication_conversations`.

### Organization ingest v3

Current production `ingest_organization_communication_events_service_v3(...)` performs:

```text
v2 institutional conversation admission
→ for each event
→ ensure_institutional_response_case_for_event_service_v1(event)
```

The current response-case writer opens an `unclaimed` case for incoming institutional communication with an external participant unless another narrow condition blocks it.

Production currently has 23 response cases for 23 Institutional Conversations:

```text
unclaimed       22
informational    1
```

The newer actionability substrate exists but has zero accepted/proposed rows in production and is not on this writer path.

### Governing correction

The future writer must be ordered as:

```text
Communication Event admitted
→ source-local Thread established/reused
→ common Communication Conversation established/reused
→ event membership / endpoint / source-thread continuity recorded
→ identity/relationship reconciliation
→ actionability considered
→ Response Case only if the governing actionability/admission rule warrants one
```

It is forbidden for Institutional Conversation admission to continue creating a parallel durable identity after the common root becomes governing.

---

## 6. Current read divergence

The mature institutional inbox is still rooted in Institutional Conversation and Response Case state.

`atlas.v_institutional_shared_inbox_v1` composes roughly:

```text
institutional_conversation
+ endpoint
+ latest response case
+ response-work binding
+ work allocation
+ latest institutional message/event
+ attention/open state
```

Current browser APIs remain endpoint-first:

- `institutional_communications_home_self_api_v2()`;
- `institutional_shared_inbox_self_v3(endpoint_id, limit)`;
- `institutional_conversation_detail_self_v4(institutional_conversation_id)` with compatibility fallback;
- `institutional_correspondence_search_self_api_v1(...)`.

The Atlas app hook `useCorrespondenceJournal` therefore:

1. loads authorized endpoints;
2. selects one endpoint;
3. loads that endpoint's institutional shared inbox;
4. identifies rows by `institutional_conversation_id`;
5. loads institutional detail by that ID.

This is the opposite of the newer Correspondence Identity architecture, which requires one governed aggregate read across authorized communication reality and explicitly forbids the browser from assembling authority across arbitrary endpoint calls.

### Governing correction

Correspondence must read from the common Conversation root first.

A future aggregate projection should be conceptually:

```text
authorized custody
→ readable Communication Conversations
→ source-thread + event continuity
→ endpoint + Correspondence Identity + channel information
→ participant / Contact / relationship resolution
→ attention / actionability
→ optional consequence summaries
→ one governed Correspondence projection
```

Response Case and Company Work state may decorate a Conversation. They may not determine whether the Conversation exists in the primary read.

---

## 7. Missing common-conversation event membership in production

The merged personal-provider source architecture defines `communication_conversation_events` as the direct event-membership seam for common conversations.

The audited production database does not currently contain `atlas.communication_conversation_events`.

Therefore common Conversation is presently incomplete as the governing read root even before the application cutover: production can bridge a common Conversation to source threads/endpoints, but it lacks the released direct event-membership/read seam expected by the personal-provider architecture.

The convergence tranche must not make the app infer event membership ad hoc from source-thread joins if a governed direct seam is needed. The missing common event-membership capability must be replayed from current canon and validated/released deliberately.

---

## 8. Actionability must become a real boundary

`20260911172800_atlas_communication_provider_independence_v1` already established the governing law:

```text
receipt ≠ response obligation
```

and the intended ordering:

```text
incoming evidence
→ actionability
→ response case only when actionable
```

The live system has not completed that cutover.

### Required behavior

- An incoming event always remains Communication evidence.
- `unknown` actionability is lawful and must not be rewritten into certainty.
- Informational, automated, junk, public interaction, acknowledgement, or notification evidence can remain visible Correspondence without manufacturing a Response Case.
- Actionability does not itself establish who is responsible.
- An actionable communication may create/admit a Response Case only through the institutional consequence rule.
- Responsibility/allocation remains distinct from actionability.
- Company Work remains distinct from both.

### Cutover constraint

Do not switch the Response Case opener to fail-closed actionability until the primary Correspondence read no longer depends on Response Case existence to keep communication visible.

Otherwise a correct actionability cutover would appear to "lose mail" from the Product layer.

The safe sequence is therefore:

```text
common Conversation completeness
→ unified Correspondence read independent of Response Case
→ actionability adjudication/admission capability
→ Response Case opener cutover
```

---

## 9. Institutional response becomes consequence, not identity

Institutional response machinery is still useful. Its placement changes.

Target relationship:

```text
Communication Conversation
   ↓ optional institutional interpretation
Institutional Response Case
   ↓ optional responsibility establishment
Company Work / allocation / execution
```

The Response Case may preserve its own case number, lifecycle, response events, work binding, handoff, waiting-external state, and completion semantics.

What it must lose is its role as the durable communication root.

### Transitional binding

During cutover, `institutional_conversation_roots` may continue to translate existing Institutional Conversation IDs to common Communication Conversation IDs.

New writers should increasingly accept or derive the common `communication_conversation_id` and use the old institutional ID only behind a compatibility membrane where legacy tables still require it.

Do not drop historical Institutional Conversation rows while response/send/work history still references them.

---

## 10. Outbound communication boundary

Current institutional email/social send logic is also keyed partly by Institutional Conversation.

The existing send invariants remain valid:

- provider credentials do not authorize Atlas to speak;
- send intent/authority is Atlas authority;
- transport acceptance, delivery, and read remain distinct evidence;
- ambiguous transport cannot be blindly retried;
- reply routing defaults to the exact governed endpoint/channel evidence rather than silently switching channels.

Convergence does not require rewriting the transport engine first.

The safe evolution is:

```text
common Communication Conversation
+ exact reply/source Communication Event when applicable
+ authorized Correspondence Identity / Endpoint
→ governed outbound operation
→ provider transport
→ provider evidence
→ admitted outbound Communication Event
→ same common Conversation continuity
```

A later send API may accept the common Conversation ID. Existing Institutional Conversation send APIs may remain compatibility wrappers until all consumers cut over.

---

## 11. Correspondence Identity placement

Correspondence Identity remains correct and survives convergence.

It answers:

> Through which recognizable persona/endeavor is this communication being encountered or sent?

It does not answer:

- who the human/entity canonically is;
- which provider owns the account;
- what the durable conversation is;
- whether a response is required;
- who is responsible;
- what business fact the message establishes.

The target governed Correspondence projection should carry at minimum, where applicable:

```text
communicationConversationId
communicationEndpointId
correspondenceIdentityId
channelKind
lastActivityAt
participant/contact presentation
attention state
actionability state
optional response consequence summary
optional Work consequence summary
```

Provider/source IDs remain available as provenance and transport context, not as the primary human grouping.

---

## 12. Product consequence: Mailroom is an encounter, not a domain root

The current Atlas application treats `/communications` as a mini-application with its own mailbox ontology, endpoint selector, inbox filters, detail navigation, compose state, sent/draft state, response-work state, and page-pair construction.

That product shape grew naturally from the endpoint-first Institutional Conversation API, but it must not become future architecture.

The durable product subject is **Correspondence**, projected into the universal Atlas notebook.

Mailroom may survive as a descriptive encounter/lens where useful. It is not allowed to own:

- durable Conversation identity;
- mailbox-specific canonical truth merely for presentation;
- its own notebook geometry;
- a special parallel page runtime;
- browser-side aggregation of endpoint authority.

The Atlas app should eventually move from:

```text
Index → Correspondence → redirect to /communications mini-app
```

to:

```text
Index → Correspondence notebook address
→ normal composed-spread runtime
→ governed unified Correspondence projection
→ universal notebook composition/pagination
```

The visual correction follows the architecture correction; it must not precede it by inventing a prettier endpoint-scoped mail client.

---

## 13. Existing unreleased Communications PRs

Several open Sept. 11–12 candidates contain useful work but were built before this convergence was recognized.

They must not be merged/released merely because their local validation passed.

### PR #525 — Separate communication evidence from response obligations

**Semantic judgment:** correct problem, incomplete placement.

It introduces `communication_response_admission_policy_v1(event)` to reduce automatic Response Case creation for public/informational interactions.

Preserve the semantic distinction. Do not treat the current patch as the final cutover because it still patches the old Institutional Response Case artery while leaving Institutional Conversation as the primary conversation root and direct messages/email on conservative auto-case behavior.

**Disposition:** replay/supersede through common actionability + consequence admission after unified Correspondence visibility is available.

### PR #527 — Enforceable institutional conversation visibility

**Semantic judgment:** privacy requirement is valid; object placement is transitional.

Conversation-level privacy/visibility belongs on the durable common Communication Conversation (or an authority object directly bound to it), not permanently on a soon-to-be transitional Institutional Conversation identity.

The responsibility-stranding guard idea remains valuable and should be replayed against the common root.

**Disposition:** do not merge as-is; replay privacy authority during common Conversation read cutover.

### PR #523 and provider-specific descendants

The provider/transport stack contains many valid lower-level invariants: provider evidence normalization, replay protection, credential custody, endpoint/source setup authority, outbound uncertainty, temporary provider authorization retirement, and source attribution.

Those concerns live below or beside durable Conversation identity and can be preserved.

Any code in those candidates that:

- creates/depends on Institutional Conversation as durable identity;
- routes response responsibility directly from receipt;
- binds outbound continuity only through Institutional Conversation;

must be replayed against this convergence before release.

**Disposition:** source archaeology/replay, not direct stack release.

### PR #535 / #536 style evidence candidates

Attachment evidence and append-only provider edit/delete/unsend observations are conceptually below durable Conversation identity and remain compatible with convergence.

Because they are stacked on older provider branches, they should still be replayed from current canonical `main` rather than merging the stale stack wholesale.

---

## 14. Required tranche declaration

### `reality_artery`

```text
source communication observation
→ immutable Communication Event
→ source-local Thread
→ one durable Communication Conversation
→ identity/relationship resolution
→ attention/actionability
→ optional governed consequence
→ unified Correspondence encounter
```

### `canonical_nouns`

Communication Endpoint; Connected Source; Communication Event; Communication Thread; Communication Conversation; Correspondence Identity; communication participants/resolutions; actionability; attention; outbound operation; Company Work; Institutional Response Case as consequence.

### `authority_owner`

- source/provider custody owns provider observations only;
- Communication Event custody owns immutable admitted communication evidence;
- Communication Conversation owns durable conversation continuity;
- actionability authority owns accepted actionability interpretation;
- Institutional Response owns response-case lifecycle only;
- Company Work owns work identity/responsibility through its established membranes;
- source business domains own any business truth inferred from communication evidence.

### `kernel_dependencies`

Connected Sources; Endpoint custody; Communication Event ledger; provider-independent Conversation substrate; identity/relationship reconciliation; Correspondence Identity; Company Work; effective institutional custody where compatibility rows remain physical.

### `candidate_abstractions`

- common Communication Conversation as the sole durable conversation identity;
- unified Correspondence aggregate read;
- common conversation-level visibility/privacy authority;
- actionability-driven consequence admission.

### `proof_domains`

Communication Conversation is already independently required by both Principal/personal communication and Organization/institutional communication. The cross-custody proof exists conceptually; the production institutional writer cutover remains incomplete.

### `read_membrane`

Pending new governed unified Correspondence projection rooted in `communication_conversations`. Existing institutional endpoint-scoped APIs remain transitional until cutover.

### `command_membrane`

Existing source ingest, response, Company Work, and outbound command seams remain bounded. New conversation admission/actionability/cross-root commands must be introduced only through governed database functions. Browser-side reconstruction is forbidden.

### `product_surface`

Correspondence as an Atlas notebook subject/spread. `/communications` Mailroom is transitional Product UI until the unified read and normal composed-spread runtime can replace it.

### `principal_admission`

No communication reaches Principal decision/Clock merely because it exists. Any Principal consequence uses the existing fitting admission authority.

### `transitional_carriers`

Institutional Conversation identity/tables; Institutional Conversation IDs in response/send/work APIs; endpoint-scoped shared inbox; Mailroom endpoint selection; effective institutional-custody compatibility wrappers where still required.

### `retirement_target`

- dual durable Conversation identity;
- new Institutional Conversations without common roots;
- receipt-first Response Case creation;
- endpoint-scoped inbox as the primary Correspondence read;
- browser-side endpoint aggregation;
- `letters:*` / Correspondence redirect into a parallel mini-app;
- Mailroom-owned physical page-pair composition;
- stale communications PR stacks that bypass current canon.

### `collision_scope`

Do not independently redefine while this convergence is active:

- Communication Conversation identity/continuity;
- event-to-conversation admission;
- actionability vs response obligation;
- conversation visibility/privacy;
- Correspondence aggregate read authority;
- reply/send conversation continuity;
- institutional communication → Company Work consequence boundary.

Provider-specific transport/evidence work may proceed only when it does not redefine these invariants and is replayable onto the common root.

---

## 15. Safe implementation sequence

### Stage 0 — freeze architectural drift

Before new UI or provider work merges:

- treat this contract as the governing target;
- do not add another inbox/conversation identity;
- do not make Institutional Conversation more canonical;
- do not add another endpoint-specific product aggregation layer;
- do not production-release stale Communications stacks without replay against current main and this contract.

No runtime change occurs in Stage 0.

### Stage 1 — make common Conversation complete for institutional traffic

Build from current canonical main.

For every new Organization Communication Event:

1. preserve current source evidence admission;
2. establish/reuse source-local Thread;
3. establish/reuse common Communication Conversation;
4. bind source thread and exact endpoint;
5. bind the event to the common Conversation through a governed event-membership seam;
6. only then maintain a compatibility Institutional Conversation if current response/send/work machinery still requires it.

Backfill the 16 currently unbridged Institutional Conversations without rewriting Communication Events, source refs, timestamps, response history, or Work history.

Acceptance invariant:

```text
Every active institutional conversation used by product/consequence machinery
has exactly one common Communication Conversation root.
```

### Stage 2 — establish unified common read

Add one authenticated governed Correspondence read rooted in common Conversation.

It must:

- span all authorized readable endpoints within the caller's custody/authority;
- include Correspondence Identity/channel/endpoint context;
- include event/message continuity;
- include attention and actionability independently;
- include Response Case/Work only as optional consequence summaries;
- enforce conversation-level visibility/privacy at the common root;
- fail closed on ambiguous custody;
- avoid raw browser joins across endpoints/tables.

Keep old endpoint-scoped reads as compatibility wrappers until Product cutover is complete.

### Stage 3 — actionability cutover

Once a Conversation remains visible without a Response Case:

- establish the accepted actionability writer/adjudication path;
- use accepted actionability / governed admission policy before opening a Response Case;
- preserve `unknown` rather than manufacturing certainty;
- ensure informational/automated/junk/public evidence can remain visible with no response case;
- preserve existing historical cases as history; do not retroactively delete them simply because a later classifier would differ.

### Stage 4 — rebind institutional consequence commands

Move response/handoff/work/send APIs toward common Conversation IDs or resolve common Conversation first behind compatibility wrappers.

Response Case remains its own lifecycle; Company Work remains its own identity; outbound transport remains its own operation/evidence chain.

No command may require the browser to reconstruct Institutional Conversation identity from source data.

### Stage 5 — Product cutover

In `optical-lift/atlas`:

- make Correspondence a normal NotebookAddress/composed spread;
- consume the unified governed read;
- route all pages through the universal notebook renderer and spread aesthetic contract;
- remove endpoint selection as the root of communication identity;
- retain endpoint/channel controls only where the human is intentionally filtering or choosing a send route;
- use semantic pagination rather than Mailroom-owned page pairs;
- preserve drafts/sent/search/actions only through governed seams that attach to common communication reality.

### Stage 6 — retirement

After production + human proof:

- stop new writes that create independent Institutional Conversation identity;
- retire old shared-inbox/detail APIs when no consumers remain;
- retire obsolete Institutional Conversation compatibility writers/wrappers;
- retire Mailroom redirect/parallel renderer;
- close/supersede stale PRs and branches with successor pointers;
- only then consider physical retirement of Institutional Conversation identity tables after all historical FKs/provenance needs are satisfied.

---

## 16. Acceptance tests

A convergence release is not complete until all of the following hold.

### Identity / continuity

- A provider/source thread is not the durable conversation identity.
- Every newly admitted institutional event belongs to exactly one appropriate common Conversation.
- Provider/account replacement can preserve common Conversation continuity through explicit evidence.
- Personal and institutional conversations use the same durable Conversation concept under different custody roots.

### Evidence / consequence

- An incoming message can exist in Correspondence with no Response Case.
- An informational or automated event remains visible without creating responsibility.
- An actionable event can admit a Response Case without assigning a Person automatically.
- Company Work created from communication preserves exact Communication evidence and does not make the message itself Work truth.
- A communication claim about Sale/payment/Demand/etc. cannot mutate that domain without the owning membrane.

### Read authority

- The browser can load authorized Correspondence without iterating arbitrary endpoints and reconstructing authority.
- Conversation privacy/visibility is enforced server-side against the common root.
- Response Case absence does not remove a Conversation from the primary read.
- Source/provider details remain available as provenance but do not drive top-level grouping.

### Product

- Correspondence can render through the same universal notebook chassis as unrelated Atlas subjects.
- No domain-specific notebook geometry is introduced for email/social traffic.
- Mobile is a single Atlas leaf, not a compressed Mailroom application.
- High message volume is handled by interpretation/grouping/pagination, not a special dense visual mode.

### Retirement

- no new Institutional Conversation exists without a common root;
- no production application consumer depends exclusively on endpoint-scoped shared inbox/detail;
- no stale unreleased Communications PR can be merged without explicit replay/supersession review.

---

## 17. Non-goals

This convergence does not by itself:

- connect Gmail, Microsoft, Facebook, Instagram, SMS, or another new provider;
- deploy a provider gateway;
- send a message;
- classify historical communications in bulk;
- infer Contact identity without evidence;
- create a CRM pipeline;
- create a generic Task sink;
- change business-domain truth;
- redesign the notebook aesthetic;
- authorize production release.

Its job is narrower and more important:

> **Make one Communication reality artery govern all providers, people, institutions, consequences, and future Correspondence encounters before more product or provider surface area is added.**

---

## 18. Supersession / interpretation rule

This document does not erase the valid laws in:

- `atlas-communication-ledger-v1.md`;
- `atlas-communication-provider-independence-v1.md`;
- `atlas-personal-communication-provider-v1.md`;
- `atlas-contacts-correspondence-identity-audience-v1.md`;
- Work Sentence / Company Work evidence contracts.

It resolves the unfinished transition among them.

Where earlier documents say existing Institutional Conversation authority is retained **until a later explicit cutover**, this document is that governing cutover direction.

Until executable migrations complete each stage, current production remains current authority. This architecture forbids new work from mistaking transitional production shape for the intended durable ontology.