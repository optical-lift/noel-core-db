# Atlas Claims, Evidence, and Effective Institutional Reality v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing correction

Atlas must not treat a Person's authority, role, responsibility, visibility, or confidence as a mechanism that makes a proposition true.

The governing rule is:

> **Claims are recordable propositions. Authority does not manufacture reality.**

A Person, system, sensor, import, model, or process may make a claim that is incomplete, mistaken, disputed, or false. The existence of the claim is real. The proposition asserted by the claim is not thereby established as reality.

Atlas must therefore distinguish at least:

```text
claim
  -> evidence
  -> conflict / corroboration / correction
  -> adjudication or domain resolution where required
  -> effective institutional treatment
```

The final line is what Atlas may currently act upon as institutional reality. It is not a declaration of metaphysical certainty.

## 2. Claim

A claim answers:

> What proposition has some source asserted, observed, inferred, planned, estimated, forecast, or otherwise presented for consideration?

Recording a claim must preserve provenance, modality, timing, subject, predicate, value, and source sufficient to explain what was asserted and by whom/what.

A claim may be:

- correct;
- incorrect;
- incomplete;
- stale;
- mutually compatible with another claim;
- contradicted by another claim or evidence;
- superseded by a later claim;
- accepted for institutional use;
- rejected for institutional use;
- unresolved.

The truth of the proposition is not inferred from the status, title, responsibility, or action authority of the claimant.

## 3. Evidence

Evidence answers:

> What observed or recorded material bears on this claim?

Evidence is distinct from the claim it supports or contradicts.

The existing `atlas.evidence_records` + `atlas.claim_evidence_links` substrate already expresses useful semantics:

- evidence has its own provenance and timing;
- evidence may support, contradict, correct, or contextualize a claim;
- multiple evidence records may bear on one claim;
- evidence confidence does not itself convert a claim into truth.

Evidence may itself later be shown to be incomplete or unreliable. Atlas should preserve that history rather than silently replacing the original record.

## 4. Claim relationships

Claims may conflict without either one automatically winning.

The existing `atlas.claim_adjudication_relations` relations such as `contradicts`, `corrects`, and `supersedes` are useful precedents for preserving the relationship between propositions rather than flattening them into one mutable value.

A later claim being newer does not inherently make it true. A claim being more specific does not inherently make it true. A claim being made by a Person with broad action authority does not inherently make it true.

## 5. Effective institutional treatment

Atlas still needs a current operational answer in many domains.

The concept required is not "the authorized Person said it, therefore it is true." It is:

> Given the currently admissible claims, evidence, domain rules, custody, and adjudications, what disposition may Atlas presently rely upon for institutional action?

Conceptually, effective treatment may include states such as:

```text
established_for_use
unresolved
rejected_for_use
superseded
not_established
```

These names are architectural examples, not an executable enum.

An effective institutional disposition is itself provenance-bearing and revisable. New evidence may cause Atlas to change what it currently relies upon without rewriting the prior history.

## 6. Adjudication

Adjudication answers:

> Given ambiguity or competing claims, what institutional disposition should govern now, and on what basis?

An adjudication is not truth magic.

An adjudicator may be wrong. The institutional decision may later be superseded. The underlying claims and evidence remain available so Atlas can explain:

- what was claimed;
- what evidence existed;
- what conflict existed;
- what decision was made;
- why Atlas relied on that decision at the time;
- what later changed.

Adjudication therefore establishes **effective institutional treatment**, not objective truth by fiat.

## 7. Action authority is downstream from truth formation

For this architecture, **authority means governed action authority**.

It answers questions such as:

- may this Person commit the institution to this purchase?
- may this Person change a work plan?
- may this Person move responsibility from one Person to another?
- may this Person approve, reject, or retire an institutional construct?
- may this Person record an adjudication that determines current institutional treatment where the domain requires such a decision?

Authority does **not** answer:

- is this claim true?
- does this observation become reality because this Person reported it?
- does this Scope membership become real because this Person asserted it?

The action may be authorized while the factual proposition motivating it is false. Atlas must preserve those as separate dimensions.

## 8. Claim recording capability is not truth authority

A product surface may restrict who or what is permitted to submit a claim, observation, or report. That is an ingestion/capability rule.

It must not be interpreted as:

```text
allowed to submit claim
  -> claim is true
```

Likewise, Atlas may accept claims from sources that do not possess institutional action authority. A worker observation, imported record, sensor reading, customer message, or external source may be highly relevant evidence without granting that source any power to govern the institution.

## 9. Existing `claim_records.authority_kind` compatibility note

`atlas.claim_records` currently contains an `authority_kind` field. Under this architecture that field must **not** be interpreted as proof that the proposition is true or as generic Person action authority.

Where retained, it is compatibility/provenance metadata describing the asserted source/claim basis unless and until a more precise migration gives it a narrower semantic meaning.

No future aperture or Scope resolver may treat `claim_records.authority_kind` alone as evidence that a claim is accepted, true, visible, or action-authorized.

## 10. Existing claim substrate audit

The generic claim/evidence substrate already contains strong pieces for this model:

- `claim_records` separates lifecycle from source, value, modality, confidence, and adjudication state;
- `claim_records` supports v2 modality including observed, authoritative assertion, derived, planned, forecast, estimated, and unknown;
- `claim_records` supports adjudication states including current, accepted, disputed, rejected, superseded, and expired;
- `claim_evidence_links` preserves supporting, contradicting, correcting, and contextual evidence;
- `claim_adjudication_relations` preserves contradiction, correction, and supersession among claims;
- `evidence_records` preserves provenance, actor, observed/learned/effective time, and confidence.

This is a suitable substrate to build on conceptually, but it is not yet declared the executable universal Scope-membership contract.

The older farm-shaped `truth_assertions` substrate is domain-specific compatibility machinery and must not be promoted into the generic reality ontology merely because of its name.

## 11. Scope membership consequence

A Governed Scope must follow this law.

Statements such as:

```text
Subject X belongs in Scope S
Subject X does not belong in Scope S
Scope A is a child of Scope B
Predicate P should select this class of reality into Scope S
```

are propositions/rules with provenance. Their existence does not automatically settle effective membership.

Conceptually:

```text
membership claims / rules
        +
evidence / predicate evaluation / child-Scope evidence
        +
conflicts / corrections / supersession
        +
current adjudication where required
        ->
effective Scope membership disposition
```

A direct inclusion is therefore not "truth by edit." It is an explicit positive membership claim. A direct exclusion is an explicit negative membership claim. Predicate matches and child-Scope resolution contribute governed membership evidence according to their contracts.

Where the evidence conflicts and no current institutional disposition resolves it, membership remains unresolved and aperture paths depending on it fail closed.

## 12. Aperture consequence

Visibility, responsibility, and action authority should consume **effective governed reality**, not merely raw claims.

Aperture resolution must not say:

```text
Person P claimed X
therefore X is real
therefore P's aperture changes
```

Instead, any claim-dependent aperture fact must pass through the domain's effective-reality resolution law before it can participate in visibility, responsibility, or action-authority projection.

This keeps a false report from automatically widening visibility, moving responsibility, or granting action capability.

## 13. Correction to prior aperture wording

Where earlier documents in this architecture tranche describe authority as the ability to "establish institutional truth," that wording is superseded by this document.

The corrected definition is:

> **Action authority is the governed capability to take or commit specified institutional actions over specified reality. It does not determine whether a factual proposition is true.**

An adjudication may be one authorized institutional action. Its product is a current governed disposition for institutional use, with provenance and supersession, not truth by fiat.

## 14. Explicit non-scope

This document does **not**:

- create a new claim table;
- alter `claim_records`;
- alter `evidence_records`;
- reinterpret existing production claim rows;
- create a Scope table;
- create Scope membership claims;
- create Scope adjudication schema;
- create a generic effective-reality resolver;
- change any production permissions;
- change Worker Day behavior.

## 15. Next boundary

Before executable Scope schema is created, Atlas must decide how a Governed Scope definition itself relates to claims and institutional constructs:

- which parts of a Scope are definition/specification rather than factual proposition;
- which changes merely propose a new Scope revision;
- how a proposed revision becomes the current institutional Scope definition;
- and which action-authority rules govern adopting/retiring that institutional construct without confusing adoption with factual truth.
