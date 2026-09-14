# Atlas Scope Triage Destination v1

**Status:** Architecture contract only  
**Date:** 2026-09-14  
**Executable scope:** None

## 1. Governing decision

A broader Person may reroute, split, consolidate, clarify, or supersede a narrower living-Scope addition only into destination reality that is itself within the triager's independently resolved visibility **and** responsibility aperture.

Seeing the destination is not enough. Carrying responsibility for the destination without visibility is not enough. Both dimensions must independently admit the destination at the effective time of the triage event.

The destination must also be semantically valid for the affected addition under the destination Scope's own living definition and membership-resolution rules. Atlas must not treat "the triager can see and carry both places" as sufficient proof that the addition belongs in the destination.

## 2. Rerouting is coordination, not truth creation

A triage event changes the institution's current organization of a living Scope contribution. It does not, by itself:

- prove the underlying factual claim;
- reject or disprove the original contributor's factual claim;
- transfer Ledger custody;
- create visibility;
- create responsibility;
- reassign responsibility for underlying Company Work or another governed subject;
- create action authority outside the already established local triage law.

Claims, evidence, adjudication, custody, responsibility allocation, and Scope-definition coordination remain separate semantic systems.

## 3. Required destination proofs

For an addition `E` concerning affected reality `X`, a reroute by Person `T` from source Scope `S1` to destination Scope `S2` is valid only when Atlas can establish all of the following for the relevant context and effective time:

1. `T` has independently admitted visibility to the portion of `X` affected by the reroute.
2. `T` independently carries responsibility for that same affected portion of `X`.
3. `T` has independently admitted visibility to the destination boundary relevant to `S2`.
4. `T` independently carries responsibility over that destination boundary to the degree required to coordinate the addition there.
5. `S2` is a currently usable living Scope at that effective time.
6. The destination definition can legitimately address `X` through explicit inclusion, child-Scope composition, governed predicates, or another admissible membership path.
7. Any required membership, custody, or predicate resolution needed to justify the destination is not unresolved.
8. For cross-Ledger destinations, the required proofs hold separately for every affected Ledger-custody intersection.

If any required proof is absent or unresolved, Atlas fails closed for that reroute.

## 4. Destination validity is not destination membership by assertion

The triager cannot make a destination valid merely by choosing it.

If the destination Scope does not currently contain or validly address the affected reality, the triager must first make whatever Scope-definition contribution is locally permitted by the same visibility-and-responsibility law. That definition event is separately recorded and may itself be visible/triageable under the comparative-aperture rules.

Only after the destination can validly address the affected reality may the coordination event place the addition there.

This prevents triage from becoming an ungoverned shortcut around Scope membership.

## 5. Source and destination provenance

A reroute must preserve the complete coordination chain.

Conceptually:

```text
Person A added E in Scope S1
Person T later rerouted E from S1 to S2
```

The durable record must preserve at least:

- original addition identity;
- original contributor/source;
- original Scope and event position;
- triager identity/source;
- destination Scope;
- affected reality;
- comparison/breadth basis used for triage standing;
- destination-validity evidence or proof references;
- effective time;
- recorded time;
- reason or routing note where supplied;
- any later superseding triage event.

Triage never rewrites the original event in place.

## 6. Split and consolidation behavior

A broader Person may split one lower-scope addition across multiple destinations only when every destination independently satisfies the full destination law.

One valid destination cannot make another invalid destination acceptable.

Likewise, consolidation of several additions into one destination requires that the destination validly address the affected reality represented by every consolidated addition.

The original contributions remain individually traceable even when the current coordination surface presents a consolidated result.

## 7. Rerouting to a narrower Scope

A broader Person may return or reroute an addition into a narrower contained Scope when:

- that narrower destination is within the triager's own visibility and responsibility aperture;
- the destination legitimately addresses the affected reality;
- the event preserves the original broader/narrower coordination history.

This allows broader responsibility to distribute work or specification back down without creating a permanent supervisor relation.

The recipient or narrower participant is not automatically assigned responsibility merely because the event is visible in that narrower Scope. Any responsibility transfer or assignment remains a separate governed action.

## 8. Rerouting to a peer Scope

A broader Person may reroute an addition laterally into another Scope within their own admitted visibility/responsibility aperture only when the destination-validity proof succeeds.

The fact that the target Scope is a peer of the source Scope does not matter by itself. Semantic fit, aperture fit, and custody resolution govern the move.

## 9. Cross-Ledger consequence

A cross-Ledger Scope may be a valid destination, but the triager must satisfy the destination law at every affected Ledger intersection.

Example:

```text
Flower Fulfillment Scope
  Elm production intersection
  Feast Guild order intersection
```

If an addition touches both intersections, the triager must have independently sufficient visibility and responsibility for both. Broad Elm standing cannot compensate for missing Feast Guild standing.

The reroute itself does not transfer custody between the two Ledgers.

## 10. No hidden authority substitution

Action-authority substrates, titles, root Principal status, organization roles, seats, credentials, or UI routes do not substitute for the visibility-and-responsibility destination proof established by this local Scope-triage law.

This does not mean action authority is globally irrelevant. It means this specific Scope-coordination behavior is governed by the already-settled local rule: visible + responsible participants may contribute locally, and strictly broader visible + responsible participants may triage narrower contributions.

Other institutional actions may still require independent action-authority contracts.

## 11. Fail-closed conditions

Atlas must refuse or leave unapplied a reroute when:

- the destination Scope cannot be resolved;
- the destination is retired/suspended in a way that disallows ordinary additions;
- the triager lacks visibility to the affected destination reality;
- the triager lacks responsibility for the affected destination reality;
- destination membership is unresolved;
- destination custody is unresolved;
- the move depends on a stale compatibility role or title;
- a cross-Ledger intersection is missing required proof;
- the only justification is that the triager can see both source and destination;
- the move would silently reassign responsibility or transfer custody without the separate governed action required for those changes.

## 12. Relationship to factual disagreement

A reroute may occur even when a factual claim underlying the addition is disputed, provided the destination is a valid place for that disputed matter to be coordinated and the visibility/responsibility requirements are met.

The reroute does not resolve the dispute.

Likewise, an adjudication about the factual claim does not automatically decide where the resulting coordination item belongs. Truth treatment and coordination placement remain separate.

## 13. Historical reconstruction

Historical reconstruction must use the destination Scope definition, visibility admissions, responsibility relationships, custody state, and comparative breadth that were effective when the triage event occurred.

Atlas must not justify an old reroute using today's broader aperture or today's changed destination definition.

## 14. Explicit non-scope

This document does **not**:

- create a Scope table;
- create a Scope event table;
- create a reroute/triage table;
- create a triage RPC;
- create a responsibility-assignment API;
- define generic action authority;
- create a Person hierarchy;
- create a manager/supervisor relation;
- create a numeric breadth score;
- change Worker Day or production permissions.

## 15. Next unresolved boundary

The destination law now establishes where a broader participant may coordinate a narrower addition.

The next architectural boundary is **responsibility handoff versus coordination reroute**:

> When a broader participant moves an addition into another Scope that is carried by a different Person, when is that merely a visible coordination move, and when does Atlas establish or change actual responsibility for the underlying work/reality?

This distinction must remain explicit so Scope triage cannot silently become task assignment.