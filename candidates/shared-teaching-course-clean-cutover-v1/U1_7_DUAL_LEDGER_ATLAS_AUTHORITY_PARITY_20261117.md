# U1.7 — Actual Atlas two-Ledger governing authority contract

**State:** HELD source/testing increment; no release, production schema restore or institutional-root approval.

## Source discovery (read-only live)

The existing production `atlas.company_work_native_ledger_owner_self_v1(uuid,uuid)` returns the signed canonical Person only after separately checking:

1. A current authenticated Atlas-ready Person/Principal with existing Reality authorization.
2. The selected **native Ledger**, active native Ledger membership in the organization (governing **or operating**), and the Person's current active native Ledger Seat.
3. The same Principal's current `root_governing` authority on the selected native Ledger.
4. Exactly one current **organizational primary governing Ledger**, which may differ from the selected native Ledger.
5. That same Principal's independent `root_governing` authority on the organizational primary governing Ledger.

The function uses the already-live `atlas.current_person_id_v1`, `atlas.current_principal_id_v1`, `atlas.current_active_ledger_seat_v1` and `atlas.capability_root_authority_context_self_v1` source chain. Checking only one Ledger, one Seat or an `owner` label is not equivalent. The production definition was inspected read-only, **not copied as a migration or exported with protected schema records**.

## Bounded change completed in held source

- [Fictional local GoTrue fixture](./titus_u1_local_gotrue_fixture.sql) now models a **distinct operating native Ledger (8888) and primary governing institutional Ledger (7777)** with a single Person/Principal. The existing unrelated Atlas-only Ledger with no native counterpart remains present as a denial fixture.
- The explicitly named `public.titus_u1_fixture_native_owner_probe_v1` is a **disposable local-only testing adapter**, not a U1 product API. It exposes only a boolean permission result to the genuine locally signed test client; the existing `atlas.company_work_native_ledger_owner_self_v1` implementation in the fixture is still a **test double**, not a restored production function.
- [Signed GoTrue/PostgREST test](../../scripts/validate-titus-u1-gotrue-local-signed.py) exercises all of: native operating root missing while primary root exists; both distinct roots present for one Person/Principal; another signed Person cannot borrow roots; loss of organizational primary root denies despite still-current native root; two roots do not replace an active Seat; restoring both original roots and Seat recovers the modeled Atlas authorization. It also denies **Titus institutional root bootstrap for the operating Ledger**, because Titus's candidate intentionally requires the independently verified unique **primary governing institution Ledger**, even when Atlas can govern other operating Ledgers. No institutional root is created by these failed operations.
- [Static fixture/source regression](../../tests/test_titus_u1_local_signed_safety.py) requires both separate Ledger checks, active native Seat, distinct signer denials and the fixture-only transport boundary.

## Passing evidence

[Local genuine GoTrue/PostgREST U1 #44247514204](https://github.com/optical-lift/noel-core-db/actions/runs/44247514204), [isolated PG17 #44247521516](https://github.com/optical-lift/noel-core-db/actions/runs/44247521516), and [database custody #44247521529](https://github.com/optical-lift/noel-core-db/actions/runs/44247521529) all **passed** at held source test commit `a06fc611ea72f4c3e348d7f9260c7989dbb32b95`. The signed test used distinct actual local GoTrue users and sessions to exercise the held issuer/recipient/root chain and fixture-only dual-Ledger permission probe. Those outcomes do not prove that the real production Atlas function has been restored or authorized for customers.

## Protected release gate remains

The actual `atlas.company_work_native_ledger_owner_self_v1` was **not** executed in a restored production-schema clone with fictional true signed users. The synthetic fixture is more faithful but is *not schema parity*. Complete U1 requires an independently owner-authorized protected schema/roles restore, exact cross-domain `SECURITY DEFINER`/guard review, real institutional root eligibility policy, and source-owned reconciliation for the one governing pair that has neither native Ledger nor canonical Reality mapping. No production migration, Atlas grant, extra Auth/Person, customer admission, Course or license, merge, deployment or feature flag.

The distinct U1, U2, and outsider-beta completion statuses remain HELD. Proof applies only to tested behaviors, not to untested product rights.
