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

A genuine bearer-only harness is staged as `signed_self_read_test.py`. It reads environment-supplied credentials without writing or logging them, rejects anonymous access, and verifies the actual self-response. It has not been executed because the source RPC is not yet installed. Its single-Person proof is insufficient without the separate real two-Person negative/positive tests.\n\nThe signed, two-Person test must use existing real authorized sessions or independently authorized ephemeral test identities—never a service-role impersonation:
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

## Atlas Universal Program Participation reconciliation

The existing October 26 Atlas **Universal Program Participation** handoff was inspected before introducing any private Titus Program membership. It directs that an authored Program alone is *not* a participating Person relationship; explicit consent/acceptance, shared canonical Person identity, original program, approved version, governed facilitator disclosure and source-backed participation are required. Its earlier implementation plan is **not evidence a usable participation entitlement has been released**. The current live Atlas table inventory still has authored personal Programs but no matching generic Program participation/teacher enrollment records for Titus.

Accordingly, **do not introduce a competing generic participant/coach store in Titus just for this login**. Future authorized private Titus Formation access should reuse the universally established Atlas relationship substrate if it can legitimately express that relationship, with any Titus-specific teaching/learner-state semantics remaining Titus custody. At this first slice the institutional Teaching enrollment source is real and empty; private program rights remain held.

## 2026-11-01 identity seam correction
The live Titus resolver returns a canonical Reality entity UUID, whereas Atlas Teaching enrollment points to `atlas.people(id)`. The existing Atlas Teaching enrollment reader compares a Reality Person UUID directly to that Atlas FK. This candidate instead requires an **active, nonretired Atlas Person credential** matching both the signed-in Auth user and verified canonical Reality Person and an active Atlas Person. UUID equality alone is never authorization. If the IDs legitimately diverge in the future, this first slice denies until a governed mapping exists.

Read-only aggregate inspection verified 4 such active canonical mappings, including the principal-selected test account. The existing institutional Teaching enrollment count is 0, so **no private courses are currently entitled by this slice**. The SQL source has not been applied or tested in a schema clone; the signed bearer test remains pending.

## 2026-11-01 source-check receipt

GitHub Database Custody CI passed for draft candidate commit `d857f79c3af8a093a4a0d72dc699114c1f233af6` (Actions run `41370406879`). This checks repository custody at that revision, **not** the proposed Postgres function's execution, proof of source access, a local schema clone, or authorization for production release. The related Titus client branch has no automated verification workflow receipt as of this check.


## 2026-11-01 — Principal-approved Discovery University and Universal Titus decision packet (32/32)

This section transcribes the **exact question and selected option text**; letters alone are not authority. The second questionnaire is later and more specific. Its decisions govern the universal login, role, course visibility, disclosure, participation and release behavior; the first questionnaire still governs the Discovery University reader, content and experience. The principal's verified real browser Atlas → Titus login is evidence of **identity connection only**, not entitlement to private education or approval to release code, data or infrastructure.

**Discovery University selections:** 1D, 2D, 3D, 4C, 5C, 6D, 7D, 8D, 9D, 10D, 11D, 12D.

| # | Full question | Selected | Full selected choice |
| --- | --- | --- | --- |
| 1 | Where should Marlene enter her university? | D | Titus recognizes her login and automatically opens her personal university, while others retain normal Titus experience. |
| 2 | How freely should Marlene move through the nine modules? | D | Browse everything, with personalized pathways suggested from encountered Song patterns. |
| 3 | What about the 120 class slots not yet recorded in Modules 2–9? | D | Create all 120 with provisional titles, research status, and a few chosen deeper discovery classes. |
| 4 | Main experience inside class? | C | Reading desk with movable views for sources, Song, Scripture and questions. |
| 5 | How much existing writing to show? | C | Selected excerpts with expandable longer originals and full links where permitted. |
| 6 | How display unreviewed Song connections? | D | Reviewed main reading, candidate hypotheses optional Discovery Lab. |
| 7 | How discover connections across classes? | D | All three, contextual links first and network later. |
| 8 | What can Marlene contribute first? | D | Notes/questions/comments/reflections all separately preserved with statuses. |
| 9 | How teacher-student conversation works? | D | Inline discussions + unified inbox without duplicating original conversations. |
| 10 | Noel/Song new discovery relevant to multiple classes? | D | Titus identifies classes, prepares proposed additions, teacher approves exactly what student sees. |
| 11 | How record progress and changing understanding? | D | Add optional teacher-reviewed teach-back and transfer evidence separate from activity. |
| 12 | Enough for first Marlene link? | D | Nine modules/135 slots, curated cross-module Song discoveries, and working private questions/comments. |

**Universal Titus remaining selections:** 1D, 2C, 3D, 4D, 5C, 6D, 7C, 8D, 9C, 10A, 11D, 12D, 13D, 14D, 15D, 16C, 17D, 18D, 19D, 20D.

| # | Full question | Selected | Full selected choice |
| --- | --- | --- | --- |
| 1 | Which kinds of educational subjects should a Person's Titus home be able to show? | D | Both, plus other source-authorized Atlas Programs when they genuinely operate as education or training. |
| 2 | Where should the relationship between a Person and a private Titus curriculum live? | C | In the existing universal Atlas Program participation mechanism once its authorization contracts are released. |
| 3 | Who may authorize someone to participate in a private curriculum? | D | The currently authorized governor or delegate for that exact subject, with the granting operation and source recorded. |
| 4 | How can a learner legitimately enter a course or program? | D | Support all three, but each program governs which entry methods are permitted and what consent is required. |
| 5 | What should your existing Atlas Person be authorized to do in Marlene's private university for the initial real test? | C | Author and review its teaching material, without automatically becoming a teacher or learner. |
| 6 | What relationship should Marlene initially have to this university when she receives her link? | D | Learner and historical-source reviewer: she can review how her original writings are represented, without acquiring general teacher authority. |
| 7 | At what level can a teacher be assigned responsibility? | C | For complete modules, including the classes they contain. |
| 8 | How should teaching, writing and approving curriculum relate to each other? | D | Studying, teaching, authoring, reviewing and releasing are independent operations; one Person may possess several through separately established authority. |
| 9 | How discoverable should private universities be to someone without enrollment? | C | Visible only when someone has a specific invitation, even before accepting. |
| 10 | How should the 135 class destinations behave when their research is incomplete? | A | Only researched classes open; unfinished classes are listed but inactive. |
| 11 | What authorizes Titus to show passages from Marlene's historical writing? | D | Source-specific use and disclosure authority, plus the appropriate curriculum release decision; selections and expandable originals retain their provenance. |
| 12 | What additional authorization should apply when candidate Song connections enter the Discovery Lab? | D | Research visibility and curriculum-sharing permission are separate; candidates must remain labeled and enter the learner's Discovery Lab only when authorized for that subject. |
| 13 | What happens to a learner's personal notes? | D | Private by default; the learner may explicitly share selected notes without exposing the rest of their notebook. |
| 14 | Who can read a question, comment or reflection submitted inside a class? | D | Its own disclosure scope governs access: private teacher exchange, approved class discussion or other authorized recipients, all attached to one original conversation. |
| 15 | How should teachers understand a student's progress? | D | Separate browsing, reading, submitted work, demonstrated understanding and teacher review; visibility is bounded by the actual teaching relationship. |
| 16 | What happens when the teacher or learner changes an earlier statement? | C | Keep each revision in a history visible to the participants. |
| 17 | What happens if someone loses permission to a private course? | D | Recheck access immediately on every protected operation; retain historical records under their own governed custody and disclosure permissions. |
| 18 | How should Titus handle an authenticated session expiring while someone is studying? | D | Release first with the existing secure reauthentication behavior, then add separately reviewed longer-session support without blocking university use. |
| 19 | What level of real-Person testing is required before the universal Titus home can be released? | D | First prove synthetic signed access and denials in an isolated database, then prove your real account and a second authorized Person with differing responsibilities. |
| 20 | What should be the first actual private Titus release milestone? | D | Release the full nine-module university and all question/discovery capabilities simultaneously, after every gate passes. |

### Binding reconciliations and boundaries
- **Universal Person home:** Earlier 1D speaks of "Marlene's login" and "normal Titus"; later governing clarification means **EVERY Person** has their own source-authorized Titus home. Marlene and Marshall are illustrative, not special-case accounts. Do not implement name/email routing.
- **Membership:** Universal 2C chooses the existing **Atlas universal Program participation** relationship when governed contracts are released. Its October 26 handoff describes needed participation but does not prove that a valid record currently exists. Do not invent a competing Titus enrollment engine or turn Atlas institutional Teaching into a fictitious universal program.
- **Delegated authority:** Universal 3D and 8D require real subject-bound governor/delegate operation, not role-title inference. The principal's test account (5C) is intended for **authoring and review**, *not automatic learner, teacher, release, or universal administrator access*. The choice authorizes a target design, not a present grant.
- **Marlene relationship:** 6D gives *learner plus source-representation reviewer* only once an actual invitation and acceptance/review authority exist; not general teacher status. 7C limits teaching assignments to an **entire module** including its classes; do not silently implement broad program-wide teaching delegation from earlier examples. Study/author/review/release are distinct.
- **Invitation privacy:** 9C means an otherwise unauthorized Person may discover only a specifically invited curriculum **before acceptance**, without any automatic study right. 4D allows self-start, request-and-approve or invite-and-accept *only where that program's rules permit*. No full catalog of private universities.
- **Classes:** Discovery 3D calls for 135 durable named/provisional slots. Later Universal 10A governs interactions: **only researched classes may open; unfinished slots remain listed but inactive**. A placeholder destination is not an open learning reader. Discovery 12D and Universal 20D require a **full nine-module University plus working private discussion and discovery features** before the first real private release. A minimal empty home is not permission to deploy as the first private launch.
- **Evidence/disclosure:** Original Marlene text requires source use license + class release (11D); Song candidate research permission and curriculum-sharing approval are different (12D). Reviewed/candidate labels are never conflated.
- **Learner state:** Private notes unless individually shared (13D); conversations governed by their own disclosure scopes and one original record (14D); progress dimensions separately interpreted (15D). Choice 16C commits to **preserving each revision visible to the existing participants**; it does *not* additionally select 16D's correction/withdrawal workflow. Historical records survive revocation under separately governed retention/disclosure, but protected reads reauthorize on every operation (17D).
- **Sessions and release:** Existing secure reauthentication remains initial behavior (18D). 19D requires isolated real signed positive/negative tests, then the principal-selected real account and **another independently authorized Person** exhibiting differentiated rights. 20D requires coordinated first private release after the nine-module Discovery University, actual discussion and discovery, denial tests, release review and explicit deployment authority. All prior public Titus access remains untouched while staging.
- **Open technical facts, not unanswered choices:** Which actual source owns issuing the future private Titus curriculum participation and delegated module rights; which exact lawful author/reviewer role grant exists for the principal-selected Person; source-use permissions for Marlene corpus; signed cloned source execution, negative access proofs, provider config and browser acceptance. Do not infer these from selections or claim a license already exists.
- **Protected scope:** No new live grant, Auth user, Course/Offering/Enrollment, private Titus author membership, Supabase DDL, live RLS changes, Vercel Preview/Production or merge from this decision packet.
