# Atlas durable position definitions v1

Source-first candidate for reviewed Atlas-lane migration generation. Not a live migration and not authorization to release.

Reuses `atlas.organization_positions` and its current appointments. A definition is owned by an organization, bounded to one exact native Ledger, and independently survives vacancy. Revisions are append-only, carry the author and effective time, and never create a native Ledger seat or a standing assignment acceptance.

The general kernel catalog provides adoption **provenance and suggestions**, not automatic responsibilities or permission grants. The `requestedAccess` definition field is non-authoritative until separate, checked permission machinery is released.

Do not activate Anna's native seat through this candidate. The current Ledger history reader must first be remediated and direct-access-tested.

## Contracts and release order

- The SQL candidate creates the immutable kernel catalog, exact-Ledger Position definition, immutable revision ledger and three authenticated RPCs (catalog, owner read, owner save). The postconditions check schema/authorization invariants in a disposable clone.
- Owner save requires the existing exact native-Ledger owner proof, canonical Position identity, an expected revision, a reason, a monotonic effective time and a complete structured document. It records the then-affected appointment IDs and returns explicit false values for all authority and Work mutations.
- The requestedAccess field is only a proposal displayed in an editor. No worker may derive actual authority from this field. No direct authenticated table grants or worker reader is introduced in this slice.
- Kernel publication is append-only by version. The institution's selected kernel ID/version persists as provenance, while each local revision contains a self-contained document snapshot.
- The existing Elm Farm Steward Position ID is reused when the owner first saves its definition. No production Elm row is inserted automatically; the owner must review and establish its actual wording.

Required follow-on slices before production worker participation:

1. A source-backed server authority mechanism that resolves separately confirmed information/action scopes (never the template/description), with expiry, acceptance and revocation.
2. An owner/worker read matrix and direct-API tests proving no financial or unrelated Ledger action history is visible.
3. The necessary-work register and canonical recurring Work allocation adapter.
4. Notebook-native owner/worker editors, with authoritative rereads and reviewable confirmation of any proposed expansion.

The source-generated migration, disposable clone test, review, merge and guarded production release are separate events. Do not invoke the migration generator from a candidate branch.
