# Noel Reality Pools — everyday research writing
Status: operational instructions for existing private `draft` tables (no schema change).

## Principle
Research evidence belongs in the database as **rows**. Migrations version **table/function/security definitions**, not founder conclusions, examples, Bible dictionary definitions, or a batch of Strong's records.

A research session can add/update many pools in one or more ordinary ACID transactions without issuing a migration or committing private research to public Git. The six already-live tables are:
- `draft.noel_reality_nodes` (founder node identity and governed definitions);
- `draft.noel_reality_aliases` (lexical labels / identifier links);
- `draft.noel_reality_edges` (scoped relations; `propagates_realm=false` by default);
- `draft.noel_reality_token_anchors` (witness-bound attested source tokens);
- `draft.noel_reality_verse_compositions` (text-specific compositions);
- `draft.noel_reality_decisions` (append-only decision history).

## Default mark-first research lookup (MT Hebrew R2 only)

The population of the mechanical registry is complete for the currently verified MT source spine (as of 2026-10-15): **306,785 unique occurrences**, **112,067 exact written forms (NMF)**, and **39,956 versioned consonantal comparison identities (NMI)**. These are *derived lookup addresses*, not evidence of identical operation, lexical meaning or physical R0/R1 manuscripts. The source corpus and founder lexical definitions remain their own preserved authorities.

For each token-driven inquiry, resolve the mark address *before* inherited lexical labels:
- **draft.noel_mark_occurrence_bindings** identifies the witnessed source occurrence and its exact form ID.
- **draft.noel_mark_identity_forms** identifies the versioned consonantal identity ID for the exact form.
- **draft.noel_mark_identities** provides the normalized comparison address; multiple NMF forms may share one NMI while exhibiting different canonical operations.
- **intelligence.v_noel_mark_identity_historic_labels_v1** reads the original Strong's and governance annotations **through attested source occurrences**, not through guessed dictionary equivalence.
- **draft.noel_mark_pool_identity_links** and **intelligence.v_noel_mark_primary_pool_v1** show only recorded proposals or steward-ratified primary relationships. **No primary links were automatically created** by the mechanical population.

Identity does not establish function. If multiple legacy pools correspond to one NMI, keep every original pool and present competing evidence to the steward. Only a decision explicitly scoped to that identity and pool can ratify a primary lexical pool. Do not manufacture decisions, collapse Strong's IDs, merge founder nodes, or treat 132 candidate collision cases as adjudicated truths.

These are **server-side, private** research instructions. The new registry is not a browser-facing data source and does not grant Atlas or Titus new access. Updating this workflow does not imply that every existing application consumer has been switched over; code consumers require separate reviewed integration.

## Actual writer workflow
1. Authenticate as an independently authorized server-side research operator through the connected Supabase tool or approved private server writer. Do not grant `anon`, browser clients or generic `authenticated` direct access. Never embed `service_role` in public Titus or Atlas code.
2. **Begin with the versioned Noel Mark Identity (NMI)**: resolve the observed Hebrew MT R2 `source_token_id` through `draft.noel_mark_occurrence_bindings` → `draft.noel_mark_identity_forms` → `draft.noel_mark_identities`, preserving its exact NMF written form. Check all current mark-to-pool links, then inspect any associated historical Reality Pool `node_id`, `authority_state`, `original_definition`, `operative_definition` and decisions. Strong's aliases are historical annotations, not admission or routing authority. Never create a parallel lexical pool from a guessed spelling.
3. Query the actual canonical source-token spine and verify **witness, source-token occurrence ID, canonical reference, exact written surface, source provenance, and admitted representation contract**. Examine Strong's, morphology and inherited governance labels *when present*, without requiring them to admit or divide the NMI. Preserve separate family-anchor vs token-headword identities. For a witness or language outside the admitted MT Hebrew R2 contract, use an explicitly labeled legacy compatibility lookup until its independent profile has been reviewed.
4. Within an ordinary database **transaction**, insert/update evidence rows by stable keys. Idempotency must be tested by re-reading targeted keys and handling existing rows without overwriting stronger or conflicting source/authority evidence. Use `ON CONFLICT DO NOTHING` only where the duplicate truly represents the same assertion; conflicting evidence requires a separate decision or review.
5. Record exact source or testimony and review status. An unreviewed proposed edge cannot be silently promoted to founder authority. Preserve founder-authored original/operative definitions verbatim; changes require the existing explicit steward-ratification process.
6. Append a decision to `draft.noel_reality_decisions` for substantive interpretations, status changes or conflict resolution. Never edit old decisions as a substitute for new history.
7. Verify the inserted anchors against the source spine, edge endpoints and scope, `propagates_realm`, node definition equality, counts, and private read projections; commit only after checks. If a check fails, rollback.
8. Return a concise count and evidence/decision IDs. **Do not create a migration record, Git source file, or public issue containing research bodies for routine updates.**

## Transaction pattern (illustrative; never paste unverified research literals here)
```sql
BEGIN;
-- 1. Verify the existing node and its founder-protected definition.
SELECT node_id, authority_state, original_definition, operative_definition
FROM draft.noel_reality_nodes
WHERE node_id = :existing_node_id FOR SHARE;

-- 2. Verify token ID against the appropriate live witness source, then
--    insert a source-backed anchor using actual values selected from it.
-- 3. Insert only supported, scoped relationships (propagates_realm=false);
--    append a decision if a substantive interpretation/authority change
--    is being recorded.
-- 4. Assert idempotency and protection checks, then COMMIT or ROLLBACK.
ROLLBACK; -- Replace with COMMIT only after checks pass.
```
Parameters are pseudocode, not SQL values to be copied. Use verified parameter binding or a controlled prepared statement and local transaction. Never infer a missing witness, equivalence, authority, Strong's identity or approval.

## Protection
- `draft` tables are RLS-enabled and do not receive new public/anon/authenticated grants in this protocol.
- Preserve original founder seed rows and all existing token/manuscript data.
- The admitted Hebrew v1 registry is MT R2 only. An NMI groups a prescribed consonantal projection, **not semantic equivalence**; manuscript ranks R0/R1, Aramaic and Greek must not inherit the rule automatically.
- Use mark identities as the default private research address; legacy Strong's and governance lookups are compatibility annotations, never identity creation rules.
- Store private study notes in Noel's private database or approved protected evidence store, **not** public migration, fixture, issue, PR or test snapshots.
- Record research and code as separate outputs. A new resolver algorithm or schema field requires a reviewed `noel_` migration; merely using an existing resolver or inserting rows does not.
- When an operator lacks verified authority to alter founder definitions, write a proposal/evidence row and request steward review; do not grant oneself higher authority.
- Git and public app deployments are not part of a normal dictionary session.

## Small proof
On any future research session: read production migration ledger latest version/count before and after a multiword row write, then confirm unchanged. Confirm transaction rows and source provenance changed as intended. Verify no Atlas or Titus data/access contract changed.
