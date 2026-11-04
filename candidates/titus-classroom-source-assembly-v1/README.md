# Titus classroom source assembly — one governed release candidate

**Date:** November 4, 2026. **Status:** verified **source-only candidate**, not a migration, not merged or applied.  
**Owner:** the Noel migration repository, serving Titus product custody across the Atlas Teaching authority boundary.  
**Release lane:** **`shared_`** — this SQL references `titus`, `atlas`, `reality`, `auth` and `public` and must not be submitted as a Titus-only lane (which forbids Atlas cross-schema dependencies).

## Exact bounded result

The preexisting source candidates were scattered across Titus and three stacked Noel PRs. `candidate.sql` is now a single **BEGIN/COMMIT** transaction with unchanged ordered source segments:

1. Titus draft event carrier from `optical-lift/titus`, `candidates/titus-classroom-event-core-build1/candidate.sql`, blob `8dc575b53d824a8204f12a1eb6ebaf98b1c1592b`.
2. Noel Build 1C signed participation, blob `40de318414b4440eb19ae643f0c347691275ee37`.
3. Noel Build 1E read/append, blob `cf370c8091e17f08b2653a7ef3f89c8a150eb51f`.
4. Noel Build 1F source issuance, teacher appointment and learner explicit acceptance, blob `bd436a4c0f76c11e387c4517088a579d1218a8f3`.

All four exact byte-provenance segment paths and blob hashes are recorded inside the candidate source header. This **does not** claim the contents were reviewed/approved for production, or that passing fictional tests creates real end-user authorization.

## Source verification

**PASS:** [Titus RiverSong carrier #41913689179](https://github.com/optical-lift/titus/actions/runs/41913689179), carrier commit `b2b3a4be2408159a7804d034ff78f91ce7a6688c`, pinned Noel source commit `fe16dccbc27426174fac11e3c42edd06d713bb89`.

The runner built one **new disposable PostgreSQL 17 cluster** on a private Unix socket at port **55445** (not Atlas protected clone 55432), installed the assembled SQL in one transaction, and reused existing source-shaped synthetic GoTrue/session/Person, governor, classroom acceptance, outsider and withdrawal postconditions. The candidate's independent source writer function returned **false** after testing. No production connection, real Auth account, Atlas activation or private research document was used. Cleanup passed.

**Scope of proof:** synthetic request claims are *unverified* GUC values provided only to the scratch PostgreSQL session. The tests exercise SQL authorization behavior but do not prove GoTrue signature verification or two real people consenting.

## Live source facts (read-only SELECT, November 4)

| Reality in the physical Supabase project | Current count |
| --- | ---: |
| Teaching capability definitions marked active (v1) | 1 |
| Teaching capability activations marked active | **0** |
| Teaching Courses | **0** |
| Open Teaching Offerings | **0** |
| Active Teaching enrollments | **0** |
| Classroom public source RPCs deployed | **0** |
| Active Atlas root-governing authority records | 6 |

**Implication:** even if this DDL packet were released tomorrow, the current 1F issuer could not offer anyone a real classroom seat. There is no governed Offering, enrolled learner or activated Teaching context to bind. The existing owner-only Titus client [PR #42](https://github.com/optical-lift/titus/pull/42) is only an entry point, not source membership.

## Correct Atlas Teaching source setup — not direct SQL

Already-live Atlas **signed self-service** APIs provide the real governed sequence, with per-call principal authority and input validation. The owner must intentionally choose the correct authorized Ledger and Teaching source; no default Ledger or Person identifier is inferred.

1. An authorized principal uses `atlas.create_capability_activation_self_api_v1` to request a `teaching` v1 capability scoped to their governed source, and `atlas.transition_capability_activation_self_api_v1` for its allowed activation transition.
2. Once the Teaching activation is genuinely active, create the Course through `atlas.create_teaching_course_self_api_v1` or the source-activation-specific `atlas.create_teaching_course_from_activation_self_api_v1`.
3. Publish a version through `atlas.publish_teaching_course_version_self_api_v1`.
4. Create a draft `self_paced` Offering through `atlas.create_teaching_course_offering_self_api_v1`, then explicitly open it with `atlas.transition_teaching_course_offering_self_api_v1`.
5. Enroll **only a consenting real Person** under `atlas.enroll_person_in_teaching_offering_self_api_v1`, using the exact active Atlas Person and verified underlying canonical identity; do not enroll Dr. Marlene or anyone else merely for a fiction/pilot.
6. A separately governed Titus source-root operation must create one **fixture-only** thread and its allowed parts. The current core `titus.classroom_authority_gate_v1()` deliberately prevents root creation and original append: it is still `false` and has **no approved real writer operation**.
7. Finally the principal offers the actual teacher/learner seats and they each accept with their own active signed session. Teacher access requires the learner to consent to that *exact teacher*. This two-party consent is not required for a distinct **solo private workspace**, but that would need its own source contract rather than borrowing a fictitious second Person.

**Do not:** use privileged SQL to fabricate an Auth account, Teaching activation, Course, enrollment, classroom invitation, or learner consent; use a test GUC as authentication; seed real user IDs in public Git; or quietly enable the writer gate to `true`.

## Remaining distinct release gates

- **Source reviewer / classification:** review the cross-domain SQL as a `shared_` candidate with actual source-custody evidence and a production-shaped schema clone. The four segment prerequisites must match the current live schema, not only the invented PG17 fixture.
- **Migration identity and merge:** the governed generator requires the reviewed candidate to be on Noel canonical `main`, a precise owner-triggered `Migration generation request: Shared ...` issue, and a generated candidate migration PR. This draft PR does *not* create a migration identity.
- **Writer and room issuance:** separately source-authorize creation of a sample root and append of a new original; define an owner-only case explicitly if the goal is solo use. Current false writer is not an overlooked feature flag.
- **Actual owner teaching setup:** independently activate the right Ledger via the existing signed Atlas APIs. Zero active activations today; neither the UI nor code can silently select a Ledger.
- **Real smoke gate:** check the actual signed owner permission and a genuinely unrelated Person denial. For another real learner, check their independent acceptance before disclosure. The current source fixture is not proof of human consent.
- **Protected release:** only after source review and exact migration version, use the Noel protected manual release with explicit authorization for its target. Titus Vercel deployment is separately approved and currently disabled.

**Next bounded engineering choice:** for fastest personal use, a **solo owner workspace** with no learner disclosure may be a smaller product than the full Atlas Teaching school, but must have a separately reviewed source-authorized contract; it cannot bypass the shared classroom's explicit consent. This release assembly alone cannot implement either product.
