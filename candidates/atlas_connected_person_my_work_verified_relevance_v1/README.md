# ACCESS-02 — Connected Person My Work, native-relevance disclosure gate

**Status: HELD SOURCE CANDIDATE. NOT INSTALLED. Not a valid production migration.**

## One bounded outcome
The *live* `atlas.connected_person_my_work_self_api_v1(integer,uuid)` is
`SECURITY DEFINER` and returns assigned Work **title/instructions** after
canonical Person, active native Ledger connection, and original Subject
disclosure. It computes `relevance.has_relevance`, requiring an active
source-verified/owner- or participant-attested native-Ledger relevance,
but presently uses that boolean only in the output
`workRelevanceVerified`. An ended/withdrawn relevance can therefore leave
the title/instructions readable as long as allocation and Seat persist.

The candidate adds **one** `AND coalesce(relevance.has_relevance,false)`
inside the existing eligible reader, before source-authorized original Work
details or page aggregation. No new database table, permission,
allocation, grant, assignment, caller argument, response field or frontend
behavior. Existing positive eligible Work remains unchanged.

## Verified live baseline, 2026-11-11
- Native source definition md5: `d6003af17ab97d3ee21188f35454332c`.
- Public wrapper definition md5: `c47a7961a04f6b834b65a851253990da`.
- Both wrapper and native source are production-installed; public
  wrapper authenticated EXECUTE, no anon or PUBLIC EXECUTE.
- Read-only enumeration of all **34 currently active, directly assigned,
  open connected-Person originals**: 34 had verified native relevance,
  **zero lacked it**. This counts the exact evidence-family predicate,
  not merely `attribution_state='active'`; no titles or Person IDs needed.
- The 47 inventory-listed full-farm alternate readers **all directly
  call** `atlas.require_governed_farm_full_disclosure_self_v1` in live
  source. This is structural evidence, **not 47 independent signed calls**.
- Current `owner_effective_subject_disclosure_review_self_api_v1` is
  already installed and explicitly returns
  `signedAlternativeReaderCoverageComplete:false`.

## Source custody
- `candidate.sql` explicitly stops if the current native definition
  fingerprint changed, and preserves the function body byte-for-byte
  except for one WHERE gate/comment. No direct public wrapper change.
- `postconditions.sql` verifies the new gate *and* the original actor,
  Subject, native Ledger, source verification, pagination, JSONB
  projection, wrapper identity and anonymous-denial conditions.
- `tests/test_atlas_access02_native_work_relevance_source.py` is
  source-only and cannot claim live permission proof.

## Required protected actor matrix before migration/release
Use a **disposable clone**, with real separate signed GoTrue sessions,
a genuine PostgREST request and fictional People/Work:
1. Current connected Person with accepted, active Work and **verified**
   native relevance receives the same title, instructions, dates and
   original Work ID; pagination is unchanged.
2. Same otherwise accepted Work after independent source **relevance
   withdrawal** must be absent (including title, instructions, counts,
   page cursor, and alternate list hints), not merely marked
   `workRelevanceVerified:false`.
3. Formerly assigned Person after ended native Seat, another Ledger's
   Person/root, outsider, anonymous and forged self/subject are denied.
4. Re-establish a legitimate verified relevance (on disposable fixtures
   only), confirm same Work reappears with the same ID and author.
5. Cross-check Today, My Work, Work Focus and Ledger source readers,
   including authorized sibling Work and no copied tasks/ghost Done.

**Do not modify real People, allocation, relevance, grant, Work or Result
rows for tests.** A source-only pass is not signed acceptance. A later
owner-originated protected test and distinct migration/production release
must be independently authorized.

Canonical source and blockers: Atlas
[disclosure audit](https://github.com/optical-lift/atlas/blob/main/docs/release/CONNECTED_PERSON_DISCLOSURE_CROSS_SURFACE_GATE_20261026.md),
[Atlas #445](https://github.com/optical-lift/atlas/issues/445) and
[human #556](https://github.com/optical-lift/atlas/issues/556).
