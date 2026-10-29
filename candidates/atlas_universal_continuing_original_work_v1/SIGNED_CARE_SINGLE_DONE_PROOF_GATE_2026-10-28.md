# Atlas continuing physical care — signed One-Done proof gate

Status: **source-ready; runtime HOLD**. Draft Noel PR #2362 depends on held #2368.
No production installation, authentic browser care writer grant, real Person mutation,
new farm Work engine, or production release is authorized by this test package.

## Verified so far

- RiverSong's existing `noel_schema_clone:55432` accepted the exact coordinated
  sources, checked the single private Done path, and returned `ROLLBACK`.
  It is not a signed GoTrue proof and must not be repurposed for data-bearing
  cross-HTTP tests.
- Existing canonical Noel tests previously established genuine local GoTrue
  identity/session, Person/Work/Subject disclosure, Bed 3 vs Bed 4, and
  cross-person signed REST denials in separate, older candidates.
- Database Custody CI parses the new Python acceptance scripts, checks that
  only fictional Bed 3 is seeded, and retains the restricted-source execution
  and local-only boundaries. CI **does not** run the signed proof itself.

## Source-exact new gated test files

1. `signed_care_single_done_fictional_fixture_v1.sql`: DML-only fictional
   rule, subject-specific binding, Rhythm state, weed card, on the existing
   C1 original-Work fixture's Bed 3. Requires the combined private source
   and the canonical held original Work fixture.
2. `validate_signed_care_single_done_clone_v1.py`: separate authentic local
   GoTrue owner/worker/outsider/no-seat identities; source Ledger scope,
   worker consent, exact Bed 3 identity+condition grants, withheld Bed 4,
   signed governor source observation, partial Result, invalid full refusal,
   full physical Result -> qualifying satisfaction -> one immutable Done,
   same-action retry and no duplicated original Work.
3. `run_signed_care_on_fresh_protected_clone_v1.py`: composes the exact
   held original-Work candidate/fixture and BOTH existing draft packages
   inside a newly disposable, fully provisioned local Supabase clone.
   No local server startup or production read occurs in this script.

## How to run through the protected clone lane

The protected existing production-schema validation workflow must first
supply a FRESH disposable Supabase Auth+REST+Postgres instance at
`127.0.0.1:54322/postgres` containing the full user-schema and custom-role
read-only snapshots. **Do not run this on the retained RiverSong 55432 clone.**

The canonical-main validation controller must accept a separately reviewed
test-only care candidate and call the staged runner with three exact checkouts:
canonical Noel `main` (holding original-Work source/fixture), the immutable
#2368 checkout SHA `dc793c94365f2f1f68185aa4446f61e17fb10ce6`,
and this held #2362 checkout.

Example for the already-provisioned *ephemeral test runner* (not RiverSong):

```bash
python3 candidates/atlas_universal_continuing_original_work_v1/run_signed_care_on_fresh_protected_clone_v1.py \
  --db-url 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' \
  --main-checkout /path/to/reviewed/noel-main \
  --done-checkout /path/to/immutable/pr2368 \
  --output /path/to/ephemeral/artifacts/signed-care-one-done.txt
```

The ephemeral database must be destroyed with no retained backup after the
signed tests. This command must never be wired into production release.

## What passing this test DOES and DOES NOT prove

Proves only when runtime-green: separate genuine GoTrue signed identities and
current auth.sessions; physical care internal source refuses outsider and
wrong performer; current disclosure governs Bed 3 but not Bed 4; full/partial
differentiate actual evidence; no standalone farm Done or recurrence; one
immutable Work lifecycle completion and one physical satisfaction; replay
does not duplicate the original evidence or Work.

The private methods deliberately retain `REVOKE ALL` for client roles.
Their source is invoked using the *genuine signed claims* in privileged
disposable SQL. This is **not a successful end-user PostgREST care RPC**.

Still required before release: an approved bounded client entrypoint with
real signed positive/negative bearer HTTP calls; a complete legacy-reader
sweep; source-observed corrective Need vs approved standing stewardship
policy; bounded daily Work allocation/Today exposure and source-grounded
successor admission, including zero Work when eligibility is absent;
separate nonfarm universal Work regression; no false 404-denial pass.

Keep both PRs draft, no `authenticated` grants, no merge or production
release based on this document or the structural rollback PASS.
