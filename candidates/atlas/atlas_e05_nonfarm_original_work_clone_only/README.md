# E05 — one source-established nonfarm original Work (TEST ONLY)

**Owning request:** [Noel #2764](https://github.com/optical-lift/noel-core-db/issues/2764).  
**Consumer:** Atlas draft [#571](https://github.com/optical-lift/atlas/pull/571), script `scripts/atlas-riversong-e05-signed-acceptance.py`.  
**State:** fixture **source prepared; live RiverSong rollback-only attempts HELD against stale local schema; not committed as valid fixture and no signed run**. No release authority.

## Existing source reused

This SQL intentionally reuses the first canonical C1 identity/authority graph
from `candidates/atlas/atlas_universal_original_work_integrated_v1/fixture.sql`,
Git blob `e877d93323ddc67d8778be8bea1dfa34319cc85c`, stopping **before**
its later Work and Farm inserts. The C1-only `ledger.actions` sensitive-action row is intentionally omitted:
E05 neither reads nor writes that unrelated history surface, and the
preserved RiverSong schema-only source does not contain that relation.
It includes actual source-shaped
`auth.users`, `reality.entities`, `reality.auth_person_bindings`,
`atlas.people`, `atlas.person_auth_credentials`, the owner Principal,
Ledger onboarding, two native Ledgers, active native seats, Organization,
organization-unit and native root governor. E05 adds a *single* existing
open original Work under the first Ledger and an independently recorded
owner-attested current Ledger relevance witness, with the ordinary
worker-attestation Result contract. It creates **no Farm record**, no farm
membership, no employee membership or fake connected-worker grant.

The three local GoTrue users are separate canonical identities: governor
(C1 owner), recipient (C1 worker) and outsider (C1 other-Ledger Person).
Their email/password credentials must be supplied freshly in the **job
environment** with `ATLAS_E05_{GOVERNOR,RECIPIENT,OUTSIDER}_{EMAIL,PASSWORD}`.
Emails must be different fictional `e05-<actor>-...@example.invalid`
addresses; passwords must be different. They are hashed only inside the
temporary database, never recorded in Git or the fixture manifest.

## Preconditions, not an inferred runnable workflow

A trusted, separately reviewed owner-gated test launcher must establish:
1. A brand-new local PostgreSQL **cluster** whose PGDATA is inside
   `RUNNER_TEMP`, not the preserved `noel_schema_clone`; an **empty**
   schema-and-roles-only fresh database named `atlas_e05_<8–24 hex>`.
2. Local `127.0.0.1` PostgreSQL access and separately configured
   real GoTrue/PostgREST connected to that same database, with the admitted
   public native Work RPCs already restored. The unchanged production
   database may be used only for the governed **read-only schema/roles
   snapshot** by the separately approved launcher. No production rows.
3. The fresh environment credentials above, plus the job-only
   `ATLAS_E05_LOCAL_ANON_KEY` used by the Atlas runner. Never place bearer,
   credentials, schema/role dump or private SQL in artifacts or issue/PR
   comments.

## Required fresh-source preflight (source-only)

The previous local `noel_schema_clone` is **stale**: actual RiverSong
[#43449919818](https://github.com/optical-lift/atlas/actions/runs/43449919818)
reported the native exact-source helper, `ledger.booking_requests` and
`ledger.booking_offerings` missing. It is not a permissible substitute for a
**current** schema-and-roles-only snapshot. RiverSong copied that stopped source
into job temp; the real SQL rollback probe refused, leaving no valid committed
fixture or genuine signed acceptance.

After an independently owner-approved, **read-only** Noel current schema/roles
snapshot is restored directly into a brand-new `atlas_e05_<nonce>` database
with PGDATA under RUNNER_TEMP, run the new no-mutation eligibility gate:

```sh
# PGPASSWORD stays in the private job environment; never put it in URLs/logs.
python3 scripts/check-atlas-e05-current-source.py \
  --db-url "postgresql://postgres@127.0.0.1:<port>/atlas_e05_<nonce>" \
  --output "$RUNNER_TEMP/e05-current-source.json"
```

This checks a clean local starting state, exact source function and both booking
tables, 7 public Work RPCs, actual authenticated EXECUTE and anonymous denial,
and native authenticator roles. Receipt is private, inside the job only, with
**FULL PRODUCTION PARITY NOT PROVEN** and **SIGNED NOT RUN**. It never accesses
Production or changes a table, grant, role, user or schema. It cannot attest
where a schema dump originated: a separately owner-approved protected snapshot
workflow must prove that chain of custody, and must not publish the dumps as
GitHub artifacts or move them to an untrusted runner. The current draft does
**not** create or authorize such a privileged workflow.

Once this gate truly passes, use the existing fixture preparer and genuinely
signed Atlas consumer below. Do not bypass source preflight merely to turn a
previously red fixture run green.

After these are independently true, the fixture-only preparer is:

```sh
python3 scripts/prepare-atlas-e05-nonfarm-clone-fixture.py \
  --db-url "postgresql://<local-user>:<local-password>@127.0.0.1:<local-port>/atlas_e05_<nonce>" \
  --output "$RUNNER_TEMP/e05-fixture.json"
```

That command loads the synthetic fixture + actual local GoTrue email
identities in one SQL transaction, verifies source conditions and writes
only UUIDs/title/contract in a private `0600` JSON manifest. It neither
starts the database nor signs actors. Any SQL error is deliberately redacted.

After preparing the matching local Auth/REST endpoint, run the **existing
Atlas** three-person acceptance runner with its exact source SHA, and
inspect its *real* resulting receipt. It must verify the distinct genuine
`auth.sessions` and independent recipient consent, same-original
assignment, outsider/cross-Ledger/anonymous denial, seat revoke/restore,
completion, identical accepted Result readback and unchanged Work count.
Unit tests **cannot** supply this acceptance evidence.

## RiverSong execution entry point (no new CI workflow)

Once RiverSong has independently established the **fresh** job-local PostgreSQL
cluster `atlas_e05_<nonce>`, restored the current Noel schema/roles **without
production data**, and bound real local GoTrue + PostgREST to that exact
database, use the source-owned bounded bridge:

```sh
python3 scripts/run-atlas-e05-isolated-riversong.py \
  --db-url "$ATLAS_E05_LOCAL_DB_URL" \
  --api-url "$ATLAS_E05_LOCAL_API_ORIGIN" \
  --atlas-runner "$ATLAS_E05_PINNED_ATLAS_RUNNER"
```

The Atlas runner file must have git blob
`87401240aa913d57e8bc276af1f221ff5ddc9765` from Atlas
[PR #571](https://github.com/optical-lift/atlas/pull/571). The bridge
accepts the separately provided three fictional local credentials, local
anonymous API key and `RUNNER_TEMP`; verifies the live database is really
job-local, fresh and empty; executes the fixture preparer and then the
unchanged Atlas runner; and accepts only its genuine bounded signed receipt.
It does not provision the clone, start/route API services, access production,
forge sessions, change GitHub Actions workflows, or count mocks as acceptance.

The only success line is
`E05_SIGNED_SOURCE_ACCEPTANCE=PASS; BROWSER=NOT_RUN; RECIPIENT_HISTORY=HELD`.
It is emitted by the live executor only after a **real** signed runner receipt;
source unit tests capture mocked output privately. All subprocess output is
withheld from workflow logs, and sensitive logs/credentials are never uploaded.
If any precondition fails, the real signed gate stays **HELD**.

## Newly authorized owner-gated workflow — DRAFT ONLY

The owner authorized writing the **test-only protected workflow**, not a
Production release or automatic merge. Its reviewed source is
`.github/workflows/atlas-e05-owner-protected-current-schema-signed.yml`,
and its source-only PR CI can execute now. The **owner issue** trigger will NOT
be available until that workflow passes normal source review and is merged to
Noel's default `main` through a separate owner decision.

The protected job does not use the old `noel_schema_clone`. It requires the
owner's **RiverSong** Intel/macOS `atlas-verifier` self-hosted runner to be
**available to the Noel repository** as well as Atlas (this association has
not been independently verified). That machine must have its existing native
Postgres.app 17 binaries and a working local Docker runtime for the exactly
SHA256-verified **Supabase CLI v2.116.0** schema/roles-only snapshot. If either
prerequisite is unavailable, the protected job refuses before requesting the
Production database secret.

Protected GitHub Actions environment `production` must provide:

- `NOEL_CORE_DATABASE_URL`: the existing approved read-only-use Production
  snapshot connection. It is passed **only** to two `supabase db dump`
  commands: `--role-only` and schema-only/default, never to the E05 test
  controller. Both private dumps remain in the same RiverSong job's
  `RUNNER_TEMP`, are **not uploaded as artifacts**, and are deleted.
- `ATLAS_E05_SOURCE_READ_TOKEN`: a separate least-privileged, read-only
  GitHub token with `Contents: Read` access to the **private**
  `optical-lift/atlas` repository. This is not the database secret. A
  Noel-scoped default `GITHUB_TOKEN` cannot be presumed to read private Atlas;
  the job refuses if the protected credential has not been configured.

After the workflow is reviewed and merged, the owner may create an issue
in Noel with **exact title**:

`Atlas E05: OWNER approved current-schema signed nonfarm disposable test`

Its **complete body** must consist of the following fields, using actual
immutable 40-character revision hashes instead of the placeholders:

```text
diagnostic_scope: atlas_e05_nonfarm_original_work_genuine_signed_v1
production_target: zirqkouammpwxlqfbsvf
noel_main_sha: <40-hex current reviewed Noel main HEAD>
noel_test_sha: <40-hex exact reviewed Noel E05 source HEAD>
atlas_test_sha: <40-hex exact reviewed Atlas E05 source HEAD>
release_intent: none
test_only: true
data_scope: schema_and_roles_only
```

The issue must be created or edited by the actual repository **OWNER**, must
remain open, must name the precise scope, and its main SHA must match the
GitHub issue event's default-branch SHA. Even then, the protected GitHub
`production` environment retains its ordinary approval control. No other
issue title, PR, branch push, pull-request-only CI or automated rerun can
activate the protected database snapshot.

The owner-signed job pins the Atlas signed runner, transport, browser-preflight
dependencies **and** the five Noel controller/fixture blobs to reviewed Git
blob hashes **before** accessing the Production URL. It creates a NEW
`atlas_e05_*` PostgreSQL 17 database whose cluster PGDATA lives within the
current job's RUNNER_TEMP, restores the schema+roles-only snapshot there,
checks the exact source/ACL/empty-state gate, and then starts **actual**
locally built GoTrue plus PostgREST. A bounded localhost proxy routes calls
to these real services, never to a mock backend. Only the unchanged Atlas
signed runner can claim a three-independent-session source PASS. A missing
extension, failed schema restore, unavailable local source tool, missing
private read token, absent Noel runner association, or GoTrue migration error
is a **HELD** result, not permission to weaken RLS or manufacture SQL.

**Status as of source authoring:** the unprivileged PR-only workflow source
checks passed; the protected issue-triggered step has NOT executed. A source
green result is not a live signed E05 PASS. Existing production data, roles,
grants, API and outsider invitations are unchanged.

## Gates still held

- Local source-only/refusal tests: `python3 -m unittest tests/test_atlas_e05_nonfarm_fixture_source.py`.
- RiverSong executed a real disposable PostgreSQL clone and rollback-only
  E05 SQL diagnostic, but **not** a valid fixture on a current-source clone.
  No independent GoTrue/Auth REST signed actor acceptance has run.
- The Atlas runner itself is in an **unmerged draft** branch and must be
  pinned to an exact source SHA before the protected run.
- Distinct recipient durable Work history remains [Noel #2765](https://github.com/optical-lift/noel-core-db/issues/2765).
- Browser acceptance, Stripe global build repair, Atlas E05 merge and any
  release or outsider invite remain independently held.

No production DDL/DML, migration, grant/RLS change, source promotion,
application deployment or real account/Work operation is authorized here.
