# HELD test-only Farm → ONE Company signed acceptance gate

**Status:** Source implementation of a *local-only signed-session test harness*, NOT an executed signed result. This test-only branch starts at exact held Company source commit `fceab782cb87fc8fcd1d595fc8cc51c48e16a31e`, leaving the published passing nine-source schema cohort untouched. No private source SQL changed.

## Scope / owning source

- **Source:** Noel held universal Company #2567 + corrected P3 #2565 sources 14/15, and canonical native Farm custody, excluding P3 files 16/17. One Company decision history only.
- **Bounded result:** independently signed local GoTrue owner/worker/outsider/no-seat sessions; real trusted fixture Harvest-or-Seed evidence; separately authorized `identity` + `condition` grants; one Farm source link + one immutable Company decision chain; replay/CAS race/current disclosure denials; zero new Work, consent, Result, Done, Clock, Principal floor or campaign.
- **Protected:** production database/release/CI/provider; public grants; real farm records; fake source revisions; universal Company case source hashes; historical farm governor events; non-mowing issuer; Subject-private content outside scratch. No changes to Atlas UI.

## Prerequisites before executing the Python probe

1. Reuse the **reviewed owner-gated read-only production-schema export** and **disposable PG17 + actual GoTrue/PostgREST** harness. Require a fresh clone. The already-passing protected nine-source scratch build [#42316816656](https://github.com/optical-lift/noel-core-db/actions/runs/42316816656) is structural/unsigned and **is not** itself this source fixture or signed proof.
2. Independently assemble, source-review and execute a **fictional but production-shaped** Farm fixture, using current native `ledger.ledgers`, `atlas.ledgers`, `atlas.ledger_organization_participations`, exact verified `atlas.farm_crop_ledger_custody_v1` and current native `atlas.farms`. Provision canonical fictional C1 auth identities, the Company root Person and a real active current governing authority consistent with `scripts/validate-atlas-work-prerequisite-signed-http.py`. Do not substitute guessed role fields or create a false owner relationship.
3. Source an actual one-to-one fictional `atlas.flower_harvest_bucket_observations` + `atlas.journal_event_index` nonweekly owner event, or current `atlas.seed_inventory_events` + trusted position + genuinely uncovered commitments. Source table, event key, timestamps, native Subject and journal provenance **must match**, and no existing preparation directive may exist. No direct insertion of a fabricated `uni_ops_governed_source_cases_v1` case or Subject grants in the fixture. Those must be established in the test by the signed owner.
4. Start local GoTrue and REST through the canonical clone launcher. The script uses genuine local GoTrue password sign-in and verifies its `auth.sessions` rows. Because the new Company SQL methods are **PRIVATE/REVOKED**, current positive source invocations deliberately use the privileged *disposable* clone SQL test helper with the already-verified signed JWT claims. This is **not** a proof that signed principals can call the methods via browser/PostgREST. Public transport must be separately reviewed and explicitly authorized before a live use claim.
5. Pin exact source/SHA and fixture fingerprint in a distinct reviewed test-only workflow (separate CI authority). The test must run only after canonical postconditions, with strictly local DB endpoint, no source changes and no production release. No workflow added or merged by this commit.

## Local fixture manifest shape

The fictitious source fixture provides a UTF-8 JSON manifest **in runner-owned scratch only**, never containing passwords or bearer tokens:

```json
{
  "kind": "uni_ops_farm_company_source_test_only_v1",
  "organizationId": "<actual-fixture-org-uuid>",
  "governingLedgerId": "<actual-fixture-company-and-native-ledger-uuid>",
  "farmId": "<actual-fixture-farm-uuid>",
  "attentionJournalId": "<actual-fixture-native-owner-attention-journal-uuid>",
  "nativeSubjectId": "<actual-fixture-harvest-batch-or-seed-lot-uuid>",
  "governorPersonId": "e5200000-0000-4000-8000-000000000101"
}
```

**All placeholders must be replaced using IDs that were really inserted and independently verified within this same disposable clone**. Do not write guessed fake IDs to make the test run. The `governorPersonId` must resolve from the current genuine signed C1 owner relationship, not merely match the string above. Preserve a separate source receipt for each row admitted.

After exact fixture review, invoke in that clone only:

```sh
python3 -m py_compile candidates/uni_ops_universal_company_decision_v1/tests/validate_farm_company_signed_source_clone.py
python3 candidates/uni_ops_universal_company_decision_v1/tests/validate_farm_company_signed_source_clone.py \
  --db-url 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' \
  --fixture-manifest "$RUNNER_TEMP/farm-company-fixture.json" \
  --output "$RUNNER_TEMP/farm-company-signed-summary.txt"
```

The arguments describe a local test harness, not production connectivity. It must **fail closed** if any precondition/source row is missing; a failed fixture is not automatically a SQL defect.

## Verified fictional Harvest fixture and actual native custody

A read-only production catalog inspection (columns, non-null constraints, FKs and bucket-band checks; **no user records**) established the current native shape. The existing C1 fictional Work fixture already provides the authentic test-owned Organization/Company Ledger/native Ledger, real source-shaped Root, Farm, Worker membership and growing object. The separate file `farm_company_harvest_disposable_fixture.sql` adds **only** one nonweekly historical Farm task, crop cycle, original harvest batch and observation. The *original P3 14 trigger* must create exactly one first-party owner-attention Journal event itself. No SQL fixture inserts a Company case, Subject disclosure, Company decision or farm-crop Ledger custody.

The Python harness now calls the **existing genuinely signed** `public.establish_farm_crop_ledger_custody_self_api_v1` with a GoTrue root session, proves worker/outsider/no-seat denial and independently rereads the native custody source. It then checks separate private-source Subject grants and the one Company decision chain. The Company method remains ungranted over REST. This is a local SQL test using genuine identities and still **does not** establish signed public API access to the Company decision.

After an independently authorized disposable test controller has installed the exact nine-source package and original C1 fixture in a fresh local PG17 clone, the same controller may apply this **fictional** fixture only under its trusted local clone session:

```sh
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' \
  -X -v ON_ERROR_STOP=1 \
  -c "SET uni_ops.disposable_clone = 'true'" \
  -f candidates/uni_ops_universal_company_decision_v1/tests/farm_company_harvest_disposable_fixture.sql
```

**The following is a manifest-generation query, not a source insertion or authorization.** The journal UUID must be read from the trigger's actual single record, never chosen for convenience. The protected controller writes that returned one-line JSON to a scratch manifest, checks exactly one match, and stops on zero/multiple rows:

```sql
SELECT jsonb_build_object(
 'kind','uni_ops_farm_company_source_test_only_v1',
 'organizationId','e5200000-0000-4000-8000-000000000801',
 'governingLedgerId','e5200000-0000-4000-8000-000000000401',
 'farmId','e5200000-0000-4000-8000-000000000b01',
 'attentionJournalId',j.id,
 'nativeSubjectId',j.source_id,
 'governorPersonId','e5200000-0000-4000-8000-000000000101'
)
FROM atlas.journal_event_index j
WHERE j.event_key='harvest-preparation-needs-owner-direction:fa510000-0000-4000-8000-000000000003'
 AND j.provenance->>'sourceObservationId'='fa510000-0000-4000-8000-000000000004';
```

The shell command, generated fixture and signed probe **have not been executed** here. Never publish credentials, genuine JWTs, protected schema dump, underlying private source, or output manifest outside test custody. A literal guessed JSON object is not source proof.

## Acceptance matrix

| Case | Required result |
|---|---|
| Four genuine GoTrue signers and `auth.sessions` | True local JWT subjects and independent sessions; no spoofed claims accepted as an identity |
| Owner/worker/outsider/anonymous direct REST access to *private* methods | Unavailable; no invented public grant, and 404 alone **not** a business-policy denial |
| Root before exact Subject disclosures | 42501, zero case |
| Worker/outsider/no-seat attempt disclosure or admission | 42501; no private case/roster data |
| Owner identity then condition grant | Two independently attributed append-only disclosures; identity alone still denies |
| Root source admission/replay | One immutable case and one exact native source link |
| Root current-source decision/replay | One immutable Company decision and same replay event |
| Same action changed meaning | 23505, no extra event |
| Two genuine root sessions same previous event | Exactly one atomic append; other rejected under compare-and-set |
| Root after condition withholding | 42501; old case/decisions preserved |
| Result and side-effect boundary | Same original Work count, no P3 17 governor, no automatic Work/Clock |
| Separate future tests | Native root/session revocation, actual current source replacement, cross-Ledger and forged source, public signed REST admission, end-user notebook, other Company domain |

**The test script is not evidence of execution.** The fixture, protected runner integration, signed runtime output, postconditions and any live release are still **OPEN**. Do not broaden CI or grant authorizations as a troubleshooting workaround.
