# Deterministic Person measurement — weight grammar v1

**Candidate ONLY:** source code in canonical `noel-core-db`; no SQL applied, no production claim, no automated interpretation live.

## User choice and boundary
- Decisions C/C/C: first occurrence approval; established rule reusable; targeted optional clarification for uncertainty; smallest complete measurement journey first.
- One versioned, exact first-person body-weight sentence grammar, no AI, no external service.
- First-party personal note saved **first** by existing governed capture/re-read.
- Server verifies ownership, exact source kind and deterministic match before human can approve/revoke the rule.
- Approval is persisted under the signed-in Person only. Future matching entries can be *projected* as weight readings automatically, without per-note prompt.
- Parsing derives numeric unit-safe information from preserved original text; it does not create independent medical facts, health claims, work or clock effects.
- Only the first approved source and later authored notes are projected. Earlier notes are not retroactively classified; approval time remains visible.
- Existing symptom reader and future activity reader remain independent source adapters, not special notebook writers.

## Supported pattern v1
`I weighed 172 pounds this morning.`
Also limited first-person weight variants with explicit lb/kg; explicit integer/decimal quantity; ending `today` or `this morning`. No inferred time of measurement from page timestamp. Unknown or ambiguous phrasing leaves a normal original note and no derived measurement. This is deliberately conservative.

## Required gates
1. Validate on disposable clone for SQL regex syntax, table FK references, anonymous/foreign user denial, RLS, grants, and release registration requirements.
2. Versioned rule acceptance: first note shows approval; subsequent note of same pattern yields `approved_rule`; revoke drops all derived readings but does not erase testimony.
3. Unit conversion exactness (172 lb becomes 78.01788764 kg); unknown unit, negatives, out-of-range quantities, third-party weights and ambiguous sentences unmatched.
4. Idempotent retries, no duplicate measurement truth, readable originating capture/evidence IDs, date context not silently promoted to observed-at.
5. 30-day history bounded at 100 with truncated flag; 365-day option and readable source coverage; no falsely empty history when rule absent.
6. Screen reader and mobile/desktop proofs; failure to read recognition does not block original note capture; no default new visible controls on blank right leaf.
7. Release through protected `noel-core-db` Atlas lane, not direct Supabase SQL. Follow relevant authenticated RPC registry requirements.
