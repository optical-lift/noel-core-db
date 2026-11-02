# Shared Atlas Person → Titus Authorized Home (bounded candidate)

**Date:** 2026-11-01  
**Source:** `optical-lift/noel-core-db` (the only canonical schema/migration repository)  
**Tracker:** [#2437](https://github.com/optical-lift/noel-core-db/issues/2437)  
**Titus client:** [optical-lift/titus#19](https://github.com/optical-lift/titus/pull/19)  
**Disposition:** **SOURCE-STAGED, NOT VERIFIED OR RELEASED**. No database application or permission changes were made.

## Intended user outcome

A Person signs in to the same Titus application using existing Atlas OAuth. Their private homepage displays *only* educational subjects that the current canonical Person is authorized to discover, with separate learner, teacher and author responsibilities. The source may lawfully return an empty collection. Titus must not infer education permission from historical `titus.teachers`, profile name, sign-in email, a Constellation research grant, an Atlas organization membership or the public site.

## Verified fixture baseline

A principal-designated existing Atlas sign-in was checked privately on 2026-11-01 and resolved to exactly one active canonical Reality Person. The email, Auth user UUID, Person UUID and access tokens are deliberately excluded from this source, comments, tests and PR. Current `atlas.teaching_courses`, `atlas.teaching_course_offerings`, and `atlas.teaching_enrollments` each contain zero rows; there are zero current active `titus.teacher_person_bindings`. The subject's existing historical research grant is not an educational relationship and may not be repurposed.

The positive *current real-human educational entitlement test* is **not possible** from this fixture without an independently established actual course/program relationship. This is a real authorization gate, not a code failure.

## Bounded first source implementation

`candidate.sql` proposes `public.titus_authorized_home_self_api_v1()`, an **authenticated user-bearer self read**, not a generic teacher-browse query or bulk list. It depends only on current live structural objects:

- `auth.uid()` and exact registered Titus OAuth client ID (not general Atlas JWTs).
- `titus.current_authenticated_person_entity_id_v1()` for active `auth.sessions`, current `auth.users`, and active canonical `reality.auth_person_bindings`.
- Existing `atlas.teaching_enrollments` (current Person, active/unwithdrawn), `atlas.teaching_course_offerings` (open), `atlas.teaching_courses` (active) and `atlas.teaching_course_versions` (actually published).
- **No other entitlement source is assumed**. The only emitted kind is `institutional_course`, and the only emitted role is `learner`. This is intentionally narrower than the final universal model.
- No source texts, student submissions, faculty rosters, program hidden names, raw source links or token data in the result.
- Explicit `EXECUTE` ACL: authenticated self only; revoke default PUBLIC, anon and service_role access. Reviewed definer transport is needed to cross the private owning schema; never use it to evade current-Person checks.

Reply: `{contractVersion:"titus_authorized_home_self_v1",state:"ready",personId:<canonical Person UUID>,subjects:[{id:<Course UUID>,kind:"institutional_course",title:<bounded>,subtitle:<bounded>,roles:["learner"]}]}`. For a missing/mismatched session or OAuth client: `{contractVersion:"titus_authorized_home_self_v1",state:"identity_not_ready",subjects:[]}`.

## Tests and proof still required

`structural_postconditions.sql` is a structural-only assertion for a disposable production-schema clone **after applying** the SQL candidate; it checks scoped ACL, search path and key source dependencies. It is neither an executable deployment permission nor signed HTTP proof.

The signed, two-Person test must use existing real authorized sessions or independently authorized ephemeral test identities—never a service-role impersonation:
1. Principal-designated existing Person signed into Titus + no educational membership → `ready` with `subjects:[]`, **no private program titles**.
2. Distinct enrolled Person in an active offering for published version → one `institutional_course` with `roles:["learner"]` (only if independently authorized actual enrollment exists).
3. Withdrawn enrollment, closed/retired offering, unpublished version, inactive Course → corresponding Course absent without total count or identity disclosure.
4. Wrong OAuth `client_id`, signed-out/expired/revoked session, unbound/noncanonical Person, anonymous request → appropriate empty/denied result; no title leak.
5. Duplicate actual offerings for one eligible Course → one card; changing teaching/authoring role **does not** appear from the enrollment itself.
6. SQL role permission probes: anon, PUBLIC and service_role cannot EXECUTE; authenticated bearer may invoke self RPC only.
7. Titus `/my` and exact subject route reread source on fresh requests; private body sources remain unavailable until their separate authorization read is implemented.

Record exact clone migration checksum, signed user receipts (redacted), positive/negative results and current release SHA before graduating this source. No real browser or DB test has yet passed.

## Unfinished gates (DO NOT fake)

**A.** Source-approved private Titus Program participation and permission issuance, with separate *study*, *teach*, *author*, *review* and source/learner-data disclosure boundaries. No existing Titus private-program permission table currently demonstrates this; do not substitute historical Teacher Person binding or a new universal boolean grant.

**B.** Lawful subject-specific rights for the principal-designated Person; genuine source provenance and issuer.

**C.** Precise cross-domain producer ownership and migration lane review. This proposal queries Atlas institutional source from a shared self-read and uses Titus's existing real-Person resolver. Use the `shared_` custody lane only after review, and do **not** move it into Titus app migrations.

**D.** Actual signed, isolated production-shaped clone testing, Supabase security advisor review, exact source generation, and separately authorized protected release. Then configure the Titus bearer publishable key and opt-in `TITUS_PERSONAL_HOME_ENABLED` only as a separate approved application release. Public Titus homepage must remain unchanged until then.

**E.** A safe teacher-specific discovery projection must read actual teaching relationships, not `created_by_person_id` or `published_by_person_id` as blanket rights. Nothing here creates a teacher registry or upgrades historic Marlene profile.

## Deployment prohibition

No production DDL, RLS/grant changes, entitlement creation, OAuth client modification, Atlas UI change, research release, Tutor-role creation, Vercel Preview or Production. This proposal does not alter the existing Atlas/Titus authorization release policy.
