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

## Actual writer workflow
1. Authenticate as an independently authorized server-side research operator through the connected Supabase tool or approved private server writer. Do not grant `anon`, browser clients or generic `authenticated` direct access. Never embed `service_role` in public Titus or Atlas code.
2. Identify the existing founder pool and confirm `node_id`, Strong's alias, `authority_state`, `original_definition`, `operative_definition` and current decisions. Do not create a parallel lexical identity on a guessed spelling.
3. Query the relevant canonical source token spine and verify **witness, token ID, canonical reference, surface, and Strong's lexical identity**. Preserve separate family-anchor vs token-headword identities.
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
- Store private study notes in Noel's private database or approved protected evidence store, **not** public migration, fixture, issue, PR or test snapshots.
- Record research and code as separate outputs. A new resolver algorithm or schema field requires a reviewed `noel_` migration; merely using an existing resolver or inserting rows does not.
- When an operator lacks verified authority to alter founder definitions, write a proposal/evidence row and request steward review; do not grant oneself higher authority.
- Git and public app deployments are not part of a normal dictionary session.

## Small proof
On any future research session: read production migration ledger latest version/count before and after a multiword row write, then confirm unchanged. Confirm transaction rows and source provenance changed as intended. Verify no Atlas or Titus data/access contract changed.
