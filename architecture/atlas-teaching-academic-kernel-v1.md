# Atlas Teaching Academic Kernel v1

**Status:** Gate B architecture contract; no migration yet  
**Date:** 2026-09-13  
**Base:** canonical `main` after production release of `20260913223824_atlas_ledger_capability_activation_v1`  
**Required capability:** `teaching` v1

## 1. Purpose

Gate B establishes the smallest genuinely academic truth Atlas needs after Gate A:

```text
Ledger
  -> active Teaching capability
      -> Course
          -> immutable Course Version
              -> Course Offering
                  -> Enrollment -> existing Atlas Person
```

This tranche proves that Atlas can become teaching software without creating a Titus-local identity system, organization membership model, permission system, file system, calendar, work engine, communication system, or payment system.

Gate B is deliberately narrower than an LMS. It does not introduce assignments, submissions, grading, credentials, faculty appointments, tuition, academic terms, departments, public catalogues, course files, or student scheduling.

## 2. Audit result: what does not already exist

Current production has no canonical academic Course, Course Version, Course Offering, or Enrollment contract.

Superficially similar current relations are not reusable academic truth:

- `atlas.commercial_offerings` is commerce/product truth and remains separate from an academic course delivery;
- `atlas.object_contents` / `object_content_resolutions` are farm/planting content truth and are not a general document/content substrate;
- `atlas.notebook_spread_composition_revisions` is composed-spread compiler/projection history, not instructional publication history;
- `atlas.work_result_submissions` is organization/farm task execution evidence, not learner submission truth;
- `atlas.goal_evaluations` is farm goal state, not academic evaluation.

Therefore Gate B may add real academic nouns. It must still reuse Atlas Core identity, Ledger authority, and Gate A capability activation.

## 3. Existing contracts reused unchanged

Gate B reuses:

- `atlas.people`
- `atlas.person_auth_credentials`
- `atlas.principals`
- `atlas.ledgers`
- `atlas.principal_ledger_authorities`
- `atlas.current_person_id_v1()`
- `atlas.current_principal_id_v1()`
- `atlas.capability_definitions`
- `atlas.capability_activations`
- `atlas.capability_root_authority_context_self_v1(uuid)`
- `atlas.capability_active_for_subject_v1(...)`

No Gate B relation may manufacture a Principal, Ledger authority, Organization membership, auth account, or commercial entitlement.

## 4. Naming

The database contract uses the `teaching_` prefix rather than `titus_`.

Titus is a packaged/presented education experience. Teaching is the governed Atlas capability. The canonical database truth must remain usable by any Atlas that activates Teaching.

Gate B introduces exactly four domain relations:

1. `atlas.teaching_courses`
2. `atlas.teaching_course_versions`
3. `atlas.teaching_course_offerings`
4. `atlas.teaching_enrollments`

No generic `academic_objects`, EAV field store, or product-local user table is permitted.

## 5. Course

`atlas.teaching_courses` is durable academic identity.

Minimum columns:

```text
id uuid primary key
ledger_id uuid not null -> atlas.ledgers(id)
capability_activation_id uuid not null -> atlas.capability_activations(id)
course_key text not null
name text not null
status text not null
created_by_person_id uuid not null -> atlas.people(id)
created_by_principal_id uuid not null -> atlas.principals(id)
created_at timestamptz not null
updated_at timestamptz not null
retired_at timestamptz nullable
```

Initial states:

- `active`
- `retired`

Identity rules:

- `course_key` is unique within a Ledger;
- the referenced capability activation must be `teaching` version 1;
- activation Ledger, subject Ledger, and course Ledger must be the same Ledger for v1;
- course creation requires the Teaching activation to be `active`;
- pausing or retiring Teaching never deletes the Course;
- course retirement is terminal for that Course identity.

`name` identifies the durable Course. Released instructional wording belongs to Course Version.

## 6. Course Version

`atlas.teaching_course_versions` is an immutable published academic definition of one Course.

Minimum columns:

```text
id uuid primary key
course_id uuid not null -> atlas.teaching_courses(id)
version_no integer not null
title text not null
summary text nullable
learning_outcomes text[] not null
published_by_person_id uuid not null -> atlas.people(id)
published_by_principal_id uuid not null -> atlas.principals(id)
published_at timestamptz not null
created_at timestamptz not null
```

Rules:

- unique `(course_id, version_no)`;
- version numbers are assigned canonically under row lock, not trusted from a caller;
- a Version row is published truth at creation, not a mutable draft;
- Version rows are append-only: no update/delete API and database mutation guard;
- publishing a new version never rewrites an earlier version;
- publishing requires active Teaching and an active Course;
- Gate B freezes only academic definition fields above. General file/document custody is still a separate Atlas-core prerequisite and must not be faked with JSON blobs.

This gives Atlas a stable answer to: **Which exact course definition was this Offering teaching?**

## 7. Course Offering

`atlas.teaching_course_offerings` is one actual delivery of one exact Course Version.

Minimum columns:

```text
id uuid primary key
ledger_id uuid not null -> atlas.ledgers(id)
course_id uuid not null -> atlas.teaching_courses(id)
course_version_id uuid not null -> atlas.teaching_course_versions(id)
state text not null
delivery_mode text not null
starts_at timestamptz nullable
ends_at timestamptz nullable
created_by_person_id uuid not null -> atlas.people(id)
created_by_principal_id uuid not null -> atlas.principals(id)
created_at timestamptz not null
updated_at timestamptz not null
opened_at timestamptz nullable
closed_at timestamptz nullable
retired_at timestamptz nullable
```

Initial states:

- `draft`
- `open`
- `closed`
- `retired`

Initial delivery modes:

- `self_paced`
- `cohort`
- `scheduled`
- `live_hybrid`

Rules:

- Course and Course Version must belong together;
- Offering Ledger must equal Course Ledger;
- exact Course Version is immutable after Offering creation;
- `draft -> open -> closed -> retired` is the normal lifecycle;
- `draft -> retired` and `open -> retired` are permitted cancellation/retirement paths;
- retired is terminal;
- opening an Offering requires active Teaching;
- pausing Teaching blocks new instructional transitions but does not erase an already existing Offering or its history;
- this relation must never reuse or write `atlas.commercial_offerings`.

## 8. Enrollment

`atlas.teaching_enrollments` is the academic relationship between an existing Atlas Person and a Course Offering.

Minimum columns:

```text
id uuid primary key
ledger_id uuid not null -> atlas.ledgers(id)
offering_id uuid not null -> atlas.teaching_course_offerings(id)
person_id uuid not null -> atlas.people(id)
state text not null
enrolled_by_person_id uuid not null -> atlas.people(id)
enrolled_by_principal_id uuid not null -> atlas.principals(id)
enrolled_at timestamptz not null
withdrawn_at timestamptz nullable
withdrawal_reason text nullable
created_at timestamptz not null
```

Initial states:

- `active`
- `withdrawn`

Rules:

- enrollment points directly to canonical `atlas.people`;
- enrollment never creates Organization membership, Principal identity, Ledger authority, or auth credentials;
- new enrollment requires Offering state `open` and active Teaching capability;
- one active Enrollment per `(offering_id, person_id)`;
- exact enrollment retry is idempotent and returns the existing active relation;
- withdrawal is terminal for that Enrollment row;
- later re-enrollment creates a new Enrollment row, preserving the withdrawn historical relation;
- historical enrollment remains readable after Course/Offering/capability retirement according to the viewer's existing identity/jurisdiction.

Enrollment is academic participation, not institutional employment or tenant membership.

## 9. Authority for Gate B

Gate B adds no professor/faculty permission system.

For v1, all Course creation, Course Version publication, Offering creation/transition, enrollment, and withdrawal administration requires the same existing root Ledger authority used by Gate A:

```text
Person
  -> Principal
      -> active root_governing Principal/Ledger authority
```

This is intentionally conservative. Faculty delegation is a later contract and must reuse Atlas relationship/jurisdiction law rather than becoming a global `role = professor` flag.

A student gets no administrative authority merely by Enrollment.

## 10. Capability gate

Every administrative mutation must prove both:

1. existing root Ledger authority; and
2. active `teaching` v1 capability on that Ledger subject.

Gate B must reuse the Gate A active-capability predicate rather than duplicating activation state.

When Teaching is `paused` or `retired`:

- existing academic truth remains durable;
- historical/self reads remain possible where otherwise authorized;
- creation, publication, offering opening, and new enrollment fail closed.

## 11. Browser/API membrane

All four academic relations have RLS enabled as defense in depth and direct `anon`/`authenticated` table privileges revoked.

Initial authenticated self/admin APIs should be narrowly bounded:

```text
create_teaching_course_self_api_v1
publish_teaching_course_version_self_api_v1
create_teaching_course_offering_self_api_v1
transition_teaching_course_offering_self_api_v1
enroll_person_in_teaching_offering_self_api_v1
withdraw_teaching_enrollment_self_api_v1
teaching_courses_admin_self_api_v1
teaching_offering_roster_admin_self_api_v1
teaching_enrollments_for_current_person_self_api_v1
```

Administrative functions resolve the current Person/Principal and root authority server-side. They never accept caller-supplied Principal authority as proof.

The learner self-read resolves `auth.uid() -> canonical Person` and may return only Enrollment rows for that Person.

## 12. Explicit non-goals

Gate B does **not** create:

- `TitusUser`
- `StudentUser`
- `ProfessorUser`
- academic Organization memberships
- faculty appointments
- assignments or assessments
- submissions or evaluations
- grades
- credentials/transcripts
- tuition/payment records
- course messages
- course calendars
- course tasks
- course files/document store
- public catalog/domain presentation
- academic terms/departments

Those are later contracts only when the underlying reality is needed.

## 13. First executable proof

The migration proof should demonstrate this complete transaction:

```text
existing Ledger
  -> active Teaching v1 capability
  -> root Principal creates Course
  -> publishes Course Version 1
  -> creates Offering bound to Version 1
  -> opens Offering
  -> enrolls an existing Atlas Person
  -> enrolled Person reads that Enrollment through own identity
```

The same proof must establish that no Organization membership, Principal, or Ledger authority is created for the learner.

## 14. Required production-clone postconditions

The Gate B candidate must prove at least:

1. Gate A Teaching v1 is required and recognized.
2. Unknown/inactive capability cannot support Course creation.
3. Root-authorized Course creation succeeds.
4. Organization ownership without root Ledger authority cannot create a Course.
5. Course is bound to the exact Teaching activation and Ledger.
6. Course Version 1 publishes successfully.
7. Published Course Version is immutable.
8. Course Version 2 does not rewrite Version 1.
9. Offering is bound to one exact Course Version.
10. A Version from another Course cannot be attached to the Offering.
11. Only root-authorized administration can open/close/retire an Offering in v1.
12. New Enrollment requires an open Offering and active Teaching.
13. Enrollment attaches to existing `atlas.people` directly.
14. Enrollment creates no Organization membership.
15. Enrollment creates no Principal or Principal/Ledger authority.
16. Exact active enrollment retry is idempotent.
17. Learner self-read returns that learner's Enrollment and not another learner's.
18. Withdrawal preserves historical Enrollment and blocks mutation back to active.
19. Later re-enrollment can create a new row without deleting the withdrawn row.
20. Pausing Teaching blocks new Course/version/offering/enrollment mutations but does not destroy historical reads.
21. Academic Offering does not create or mutate `atlas.commercial_offerings`.
22. Browser roles have no direct table access.
23. Anonymous callers cannot execute academic mutation/read APIs.
24. Candidate introduces zero new Atlas lint errors relative to production baseline.

## 15. Gate B completion condition

Gate B is complete only when a production-shaped validation proves:

> An existing Atlas Ledger with active Teaching can establish a Course, freeze a published Course Version, deliver that exact version through an Offering, and enroll an existing Atlas Person without manufacturing any parallel Atlas identity, membership, authority, commerce, communication, calendar, work, or file truth.

Only after this proof should Gate C introduce the instructional transaction loop: Learning Activity -> Assessment -> Submission -> Evaluation -> Completion.
