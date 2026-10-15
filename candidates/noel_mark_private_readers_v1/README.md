# Noel private mark-first readers — governed structural candidate

**Scope:** two new versioned, server-side, security-invoker reader functions. No data mutation, no public access grants, no change to existing `intelligence.begin_noel_research_v1`, `draft.get_noel_reality_context_v1`, Atlas, or Titus.

## Interface

- `draft.get_noel_mark_occurrence_context_v1(p_source_token_id text, p_form_limit integer DEFAULT 12)`: requires a real attested MT Hebrew R2 source-token ID. Returns original witnessed Unicode form, exact NMF ID, projected NMI, original source coordinates and historical labels (including NULL Strong's), other exact forms sharing the mechanical NMI, and separately tagged proposed/ratified links to legacy pools. An unknown token returns `found:false`; it never fabricates an identity.
- `draft.get_noel_mark_collision_review_queue_v1(p_limit integer DEFAULT 25, p_offset integer DEFAULT 0)`: reads **only** explicitly proposed private `candidate_legacy_pool` links with multiple distinct lexical pools for the same NMI. Pagination is stable by NMI. Returns evidence locators and original lexical-pool names/authority states, never automatic equivalence, a winning primary pool, or steward decision.

Both readers operate on the live **306,785 attested MT source-token bindings**, **112,067 NMF** and **39,956 NMI** identities without creating or copying research text. The **132 reviewed-scope candidate collisions** and **273 historical-label candidate links** were established as `proposed` rows through separate, source-backed private data writes. This source proposal does not modify those rows.

## Separation of authority

NMI is a declared Hebrew MT R2 consonantal comparison address, **not** an R0/R1 manuscript identity, shared semantic function, or inherited Strong's dictionary identity. `candidate_legacy_pool` is never primary or steward-ratified. Historical aliases are shown only as annotations from the original witnessed source. Only a recorded, appropriately scoped stewardship decision can establish a primary lexical pool.

Do not use these functions from public client roles. Their EXECUTE rights are revoked from PUBLIC, anon and authenticated; all underlying mark-registry tables remain private with RLS.

## Controlled migration path

1. Approve the structural candidate in the public repository (no private research bodies in source), merge the review-only files into main.
2. Generate a versioned `noel_mark_private_readers_v1` migration through the owner-requested `Governed Migration Source Generation` GitHub workflow; `fixture_path: none`, `validation_path: candidates/noel_mark_private_readers_v1/postconditions.sql`.
3. Run `Production Schema Clone Validation` against the generated immutable migration on the isolated GitHub Actions PostgreSQL clone. Do not create a paid Supabase branch or apply trial DDL to production.
4. Review/merge validated migration separately. A protected **manual** Noel production release remains a separate owner action.
5. Following that release, use the private readers from authorized research workflows. Consumer code changes, if needed, require separate evidence of their actual access contracts and must not expand public permissions.

No automatic legacy pool merge, no new `draft.noel_reality_decisions` rows, no re-seeding of source evidence or migration ledger in this candidate.
