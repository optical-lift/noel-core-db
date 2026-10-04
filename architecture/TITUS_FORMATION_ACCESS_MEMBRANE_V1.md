# Titus Formation Access Membrane v1

**Status:** Governing access architecture for the first private Formation Workspace slice  
**Established:** October 3, 2026  
**Scope:** Dr. Marlene self-access to her own Formation Units and learner-authored responses/transfer attempts

## 1. Governing distinction

Titus must not convert authentication, a service-role credential, or a teacher record into authority to read or mutate private formation state.

The identity chain is:

```text
auth session
→ reality.auth_person_bindings
→ canonical reality Person
→ titus.teacher_person_bindings
→ Titus Teacher profile
→ Formation Unit owned by that Teacher profile
→ bounded self operations
```

Therefore:

```text
auth user
!= canonical Person
!= Teacher profile
!= formation authority
```

Each crossing must be explicit.

## 2. Reuse the shared Person identity kernel

Titus does **not** create its own `auth_user_id` identity table.

The physical project already contains the shared Reality identity seam:

- `reality.entities` — canonical Person identity;
- `reality.auth_person_bindings` — active auth-user ↔ canonical-Person binding.

Titus adds only the domain-specific relationship still missing:

> **Which canonical Person is the real person represented by one Titus Teacher profile?**

That relation is `titus.teacher_person_bindings`.

## 3. Teacher profile remains distinct from Person

A Titus `teacher` is a corpus/formation role and durable teaching profile. It is not the universal identity of the human being.

`teacher_person_bindings` therefore preserves:

```text
canonical Person
↔ Teacher profile
```

rather than adding `auth_user_id` directly to `titus.teachers`.

The binding carries provenance (`binding_basis`) and may be retired without destroying either identity.

V1 permits one active Person binding per Teacher profile. The architecture does not assume a Person can never hold another Teacher profile later.

## 4. Self-access and delegated builder access remain different

V1 proves **self-access only**.

A Person bound to a Teacher profile may read and author the learner-side consequences of Formation Units belonging to that Teacher profile.

This does not grant Builder/Researcher authority to edit canon claims, source adjudications, assessment results, or Formation Unit review state.

Builder/Researcher authority remains service-side/administrative during the first proof. A later governed tranche should use an explicit responsibility/jurisdiction relation rather than reusing the self-teacher binding as delegated research authority.

Candidate reusable shared relation for that later work:

- `reality.responsibility_relations`

No builder grant table is introduced in v1.

## 5. Public RPC membrane, private canonical tables

The Supabase project already exposes `public` as a compatibility/API surface. New Titus formation tables remain private inside `titus`.

V1 therefore exposes only explicit `SECURITY DEFINER` RPCs in `public`:

- `public.titus_formation_access_self_api_v1()`
- `public.titus_formation_unit_self_api_v1(uuid)`
- `public.titus_submit_formation_response_self_api_v1(...)`
- `public.titus_submit_formation_transfer_attempt_self_api_v1(...)`

The RPCs receive no client-supplied `teacher_id` or Person identity. They resolve identity from the authenticated session and current bindings.

Direct table grants to `authenticated` remain closed.

## 6. Session validity

Self RPCs must fail closed unless:

1. `auth.uid()` exists;
2. the JWT supplies a valid live `session_id`;
3. that session belongs to the same auth user and has not expired;
4. the auth account still exists and is not deleted/banned;
5. there is one active `reality.auth_person_bindings` row to a canonical Person;
6. the Person has an active `titus.teacher_person_bindings` row for the relevant Teacher profile.

This follows the same identity/session separation already proved elsewhere in the physical project without creating a Titus-specific login ontology.

## 7. Read authority

`formation_unit_self_api_v1` may return a Formation Unit only when:

- the authenticated Person is actively bound to that unit's `teacher_id`;
- the unit is not `candidate`, `researching`, `adjudication_ready`, `drafted`, `reviewed`, `superseded`, or `retired` for learner-facing purposes;
- the current review state is not `blocked` or `needs_review`.

Before learner readiness, the function returns a truthful `unit_not_ready` state rather than leaking draft formation content.

The self projection may expose:

- learner-ready Formation Unit metadata;
- reviewed/approved learner-facing sections;
- selected historical source evidence and provenance;
- reviewed canon controls/structures;
- reviewed Song/function handles;
- open learner-relevant questions;
- learner-ready transfer case only when the Formation State Machine permits it;
- the learner's own submitted responses;
- current matured articulation once one exists.

It may not expose private builder-only notes simply because the server can read them.

## 8. Response authority

A self-bound Teacher may author only their own learner response.

The client does not choose `teacher_id`.

Allowed response kinds are the existing Formation Kernel response kinds.

A response submission may establish the truthful event state `teachback_received` when the submitted response is a teach-back and the unit is currently in a phase where teach-back is fitting.

It may **not**:

- mark the response reviewed;
- mark transfer passed;
- mark the unit integrated;
- change canon/adjudication truth;
- change upstream source evidence;
- create a matured articulation automatically.

Those are separate judgments/consequences.

## 9. Transfer-attempt authority

A self-bound Teacher may submit an attempt only against a learner-ready Transfer Case belonging to their Formation Unit and only after teach-back has been reviewed enough to make transfer testing phase-fit.

The learner submission creates an attempt with assessment state `pending`.

It may not self-mark `pass`.

Assessment remains a separate review authority.

## 10. No automatic identity fabrication

This migration does not create a canonical Reality Person for Dr. Marlene and does not bind an auth account by guess.

The membrane remains fail-closed until real identity/auth evidence is available.

The eventual setup path must establish:

```text
real Marlene Person
→ verified auth binding
→ verified Teacher profile binding
```

without inferring identity from display name alone.

## 11. Security posture

- `titus.teacher_person_bindings` is RLS-enabled and private by default.
- `anon` receives no direct table access and no execute permission on authenticated self RPCs.
- `authenticated` receives execute permission only on the bounded self RPCs.
- `service_role` remains available for server-side Builder/research work but is not treated as end-user authorization.
- RPCs use fixed `search_path` and do not trust client-supplied identity.
- inherited Titus RLS exposure remains outside this tranche.

## 12. Human/product consequence

Once a real auth Person↔Teacher binding exists, Titus can build the first browser Formation Workspace surface without pretending that service-role access proves Marlene may see it.

The product sequence becomes:

```text
authenticated Marlene
→ self access contract
→ learner-ready Formation Unit read
→ learner response / teach-back
→ reviewed consequence
→ transfer attempt
→ reviewed transfer consequence
→ matured articulation
```

## 13. Governing test

Before adding another private Formation Workspace operation, ask:

1. Which real Person is acting?
2. What relation makes this Formation Unit belong to that Person as learner/Teacher?
3. What exact operation may the Person perform?
4. What nearby judgment remains outside their authority?
5. What formation phase makes the operation fitting now?
6. What durable consequence should the operation establish?
7. What history/provenance must survive?

If those answers are not clear, the operation remains unavailable rather than being implemented as generic CRUD.
