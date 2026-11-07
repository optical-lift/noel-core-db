# HELD — existing Venue Event Work ordinary Result/Done source-authority review

**Status:** 2026-11-07 source audit and test-only denial regression. **NO positive Event Person Result/Done verified.** Original Flower Person Result/Done signed success is separate: protected local clone [#42423006780](https://github.com/optical-lift/noel-core-db/actions/runs/42423006780). Venue/Event linkage separately proved in the same earlier held matrix. Do not merge or deploy.

## Requested bounded result

A genuine connected Person must lawfully complete the *same* original Venue Work `e5200000-0000-4000-8000-000000000b20` through an ordinary Work result and acceptance after that same Work was linked to Event `e5200000-0000-4000-8000-000000000b40`. The Event checklist's distinct Done is not a substitute. Preserve Flower Work 901, Flower Bed 3, both independent Venue references, original Work/Bed counts and crop custody.

## Source audit — exact current contracts, no data change

Read-only PostgreSQL `pg_proc` function-source inspection on 2026-11-07 found:

1. `atlas.company_work_native_ledger_owner_self_v1` insists the authenticated actor's principal be **both** the native target Ledger root and the Organization's sole compatibility-primary governing Ledger root. In the signed fixture, Flower primary root Person 101 and Venue native root Person 103 are deliberately **different**. Thus the Venue-only root cannot currently offer a Person-native responsibility for its Event Work through `public.offer_connected_person_company_work_owner_self_api_v1`, nor the current `public.event_work_owner_assign_connected_self_api_v1` or standing-scope route. The Flower institutional root cannot simply operate the Venue native Ledger. Adding a fabricated principal, changing the compatibility-primary root, or impersonating either actor to make a test pass would not prove the intended law.
2. `atlas.person_has_native_ledger_connection_v1` requires an **active native Ledger Seat** for the *specific target canonical Person and target Ledger*. The existing Flower worker/Person 102's acceptance of Flower Work is NOT by itself evidence of a Venue Ledger connection. A genuine source-authorized Venue recipient connection must be proved separately; neither an employee seat nor Organization membership alone substitutes.
3. The fictional existing Venue Work has `source_object_type` and `result_contract_key` absent. `atlas.establish_connected_person_company_work_from_offer_v1` auto-binds `ordinary_company_work_worker_attestation_v1` only for eligible `personal_dated_task` or `legacy_task` Work with a missing contract; an Event association does not itself bind one. Event-specific direct assignment requires that exact worker-attestation contract **already exist**. The separately released `bind_ordinary_company_work_result_contract_self_api_v1` binds a distinct **manager-acceptance** contract and requires the same dual-root authority. Do not silently edit the Work row, invent a fixture policy binding, or substitute manager completion.
4. `atlas.person_original_work_identity_disclosed_self_v1`, used by ordinary `own_work` Result/Done, currently checks **spatial growing_object** context and its identity/condition disclosure. It does not check a temporal Event context. `atlas.governor_set_subject_disclosure_self_api_v1` does support exact `event/occurrence` **identity** grant/withhold, but a successful Event-only Result is not presently proof of that Event disclosure. Audit original Event information, recipient access, alternate readers and source-specific privacy before treating Event completion as an accepted positive test.

All findings are **function-source inspection**, not an independently signed Event Result/Done execution. No live Work, People, Ledger, assignment, result, privacy grant or other operational rows were selected or changed.

## Bounded test change

Test-only script `scripts/validate-atlas-venue-bed-signed-http.py` now tests both *released* source routes with the four existing genuine signed actors (Venue-only root, Flower primary root, worker, unseated), requiring SQL-origin `42501` denials and **zero Venue offers, allocations or results**, unchanged original Venue Work state and absent fictional result contract. It does **not** create a new worker, Ledger Seat, institutional root, result policy, Event Work or completion.

The previously passing Flower positive sequence remains in place and unchanged. The new Event denial test has **NOT YET** been run in the approved full-schema protected PG17+GoTrue+PostgREST clone. Database Custody CI is not a substitute for that signed runtime.

## Next source-owner decision / required proof

- Decide and source-review **who can legitimately govern original Venue Work responsibility** when an Organization has distinct primary and operating native-Ledger governors. Either an exact reviewed dual-root operating contract or a genuine correctly owned separate Venue institution is necessary; do not assume the test fixture decides business architecture.
- Establish a **real accepted native Venue connection** for the intended recipient, not legacy employee credentials or inferred membership.
- Prove the original Venue Work's authentic **ordinary result contract** from its legitimate Work source; no result-policy substitution or reclassification merely for the test.
- Review and test Event Subject disclosure as an independent information gate and prove no unauthorized Event title/location/condition disclosure.
- Only then compose the **genuine signed** exact existing original Event Work acceptance → Result → Done/replay/denial test, with Flower and Venue/Bed/Event context unchanged.
- Separate owner-gated protected test request, CI, source-owner/security review, approved migration and production release. Keep all draft PRs unmerged.

**Stop rule:** A passing Flower work result or an Event Work link cannot authorize a positive Event result claim. If lawful issuance or source privacy is missing, leave the original Event Work **open** and record the exact blocker.
