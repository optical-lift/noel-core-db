# Solo-owner structural release review — governing decision (2026-10-24)

**Effective immediately for owner-controlled Noel/Atlas release work.** This
decision supersedes any earlier release note, candidate README, PR checklist,
or agent handoff that requires a second GitHub human reviewer, independent
developer, or separate code-review approval as a universal prerequisite for
source merge, versioned migration generation, or an authorized production
release. It does **not** waive tests, rights, security, or release authority.

## Who may review

The repository OWNER may inspect, correct, and approve source for this
single-owner project. An independently submitted GitHub `APPROVED` review
from someone other than the author is **not mandatory**. The owner may
record a self-review/authorization decision in the pull request or protected
release request without impersonating another reviewer or recording a
fabricated approval. Automated lint, custody, schema-clone and signed tests
are verification evidence, **not** human approval.

If GitHub actually enforces branch protection requiring another approving
reviewer, stop and report that technical setting; this document does not
silently bypass provider-enforced rules or authorize changing branch
protection solely to make a PR merge.

## Owner review and release evidence

For source involving authentication, People, Ledger rights, source custody
or Company Work, require the following before the owner promotes it:

1. Exact source identity and comparison to the successfully tested SQL /
   application code, plus current source contract CI.
2. Disposable full-schema migration/postcondition test; genuine signed
   GoTrue/PostgREST owner/worker/outsider/anonymous denials and revocation
   tests for changed access pathways. Preserve known limits explicitly.
3. Verify scoped grants, negative privacy tests, separation of Person
   identity / native Ledger participation / permission, idempotence,
   historical event custody, and no fabricated employee/member account.
4. Record unchanged inherited lint findings separately from new failures;
   new unexpected defects remain blockers. Inspect migration receipt and
   available rollback/repair path.
5. Explicit owner authorization for each specific production release
   version/target, using the governed `main` source and separately
   protected GitHub production workflow. Source merge alone never deploys.
6. After deployment, verify the live receipt and conduct a real signed
   application smoke test with relevant independently authenticated test
   users where the workflow requires separate persons.

The owner may conduct the code/security/custody checklist; no outside
reviewer account must be created. Changes to another person's private
source, actual source-provider permissions, legal consent, financial
obligation, or independent Foundry *human source-custody decision* still
require their own real authority and must not be simulated by the owner
reviewing code.

## Boundaries

- Do not merge or deploy validation-only synthetic branches/PRs.
- Do not remove custody checks, weaken RLS/grants, use service-role
  shortcuts, disable identity guards, or turn a Ledger seat into broad data
  access to avoid review.
- Preserve original historical evidence and legacy FKs until individual
  consumers are safely retired. No `DROP ... CASCADE` cleanup.
- No production SQL through ordinary `execute_sql` or unprotected actions.
- No paid preview infrastructure merely to satisfy this decision.
- Do not claim that a clone test is a live production browser test.
- Keep application and database releases distinct and explicitly authorized.

**Terminology:** In older documents, read “independent code review,”
“external security/custody approval,” and “second reviewer” as **owner
source/security/custody review with verified tests** for this project's
release process. This terminology override does not apply to Foundry's
product feature where one signed human reviews another human's actual
source-custody claim.
