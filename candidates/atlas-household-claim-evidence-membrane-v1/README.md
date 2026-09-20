# Atlas Household Claim / Evidence Membrane v1

Status: **source-complete candidate; inert, not migration-identified, not clone-validated, not released**.

## Why this exists

Laundry exposed a missing authority membrane, not a missing data model.

The universal Claim/Evidence envelope already stores:
- scope;
- subject;
- raw Evidence;
- Claim lifecycle and authority;
- validity time;
- supersession;
- provenance;
- many-to-many Evidence relations.

Its original migration deliberately exposed authenticated **person** scope first and left other scopes private until a separate authority membrane existed.

Personal Laundry needs household-specific truths that must not collapse into one `household_kernel_instances.configuration` blob:

- where Laundry happens;
- who carries which part;
- what normally creates the next need;
- material topology/path variants;
- deadline-producing relationships;
- later observations and corrections.

Creating a parallel Laundry fact table would duplicate the universal envelope. This candidate instead opens the existing envelope to exactly the signed-in Principal's current active Household.

## Authority envelope

The write API derives:
- actor from `auth.uid()`;
- Household from `atlas.principal_current_household_id_v1()`;
- scope as `household`.

The caller cannot choose another Household.

Subjects are restricted to:
- `household`; or
- domains beginning `household.`.

The membrane permits first-party lifecycle states:
- reported;
- observed;
- proposed;
- accepted;
- rejected;
- unknown.

It does not permit a first-party caller to author:
- inferred;
- superseded;
- expired.

Corrections use explicit same-Household, same-subject supersession and retain prior Evidence/Claim history.

## Deliberately not granted

This membrane creates no authority for:
- task creation;
- carrier selection;
- responsibility assignment by inference;
- causation;
- Person Life Consequence creation;
- Household Rhythm;
- Principal capacity;
- Clock placement;
- cross-Household access;
- direct authenticated table writes.

Those remain separate downstream authorities.

## Laundry use

After this membrane exists, Laundry calibration can stop treating all household-specific truth as one settings object.

A Laundry instance can be the resolved subject root, while separate Household Claims carry facets such as:

```text
subject.domain = household.laundry
subject.kind   = kernel_instance
subject.id     = <Laundry household_kernel_instance UUID>

claimType = location
value = "home"
```

```text
claimType = ordinary_responsibility
value = {"kind":"self"}
```

```text
claimType = need_generation
value = {"kind":"accumulation_threshold"}
```

```text
claimType = process_variant
value = {"class":"ordinary_clothing","drying":"hang","readying":"hang"}
```

Each statement has its own Evidence, lifecycle, validity, provenance, and correction history.

The exact Laundry claim vocabulary belongs to the Laundry domain tranche, not this shared membrane.

## No direct RLS expansion

The candidate does not add a general Household RLS policy to the universal tables and does not grant authenticated write access to them.

Reads/writes occur through the Security Definer APIs only. Existing table RLS remains in force for direct access.

## Validation target

Before promotion:
1. caller without auth fails;
2. caller without an active Principal Household fails;
3. caller cannot supply another Household id;
4. non-Household subject domains fail;
5. Evidence and Claim are created atomically in the derived Household scope;
6. retries with identical sourceKey and bytes replay safely;
7. conflicting sourceKey retry fails;
8. correction can supersede only same-Household/same-subject Claim;
9. old Evidence and superseded Claim remain readable through the Household read membrane;
10. another Principal cannot read or correct the Household history;
11. no task/Rhythm/consequence/Clock row is created;
12. this tranche introduces no authenticated RPC custody drift for the endpoints it registers;
13. zero candidate-introduced Atlas lint errors.

## Promotion rule

Do not copy this candidate directly into `supabase/migrations/`.

Generate a legitimate migration identity with the repository-pinned Supabase CLI, freeze the migration/fixture/postcondition bytes, and run Production Schema Clone Validation. Production release remains a later separate authority.
