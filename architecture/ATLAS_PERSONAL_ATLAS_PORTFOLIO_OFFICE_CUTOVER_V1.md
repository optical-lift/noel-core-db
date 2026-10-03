# Atlas Personal Atlas Portfolio Office Cutover v1

Status: governing implementation architecture  
Date: 2026-09-25

## Classification

The legacy Principal Office authoring tables are not registered as canonical institutional truth authorities.

They currently function as the signed-in human's portfolio-governance and planning model:

- owner obligations;
- portfolio theses;
- attention policies;
- modeled operating functions;
- modeled Great Game scorecards;
- capital requests;
- investment opportunities.

The canonical identity path for authoring them is therefore:

```text
Auth
→ Reality Person
→ native Personal Atlas
→ Personal Atlas portfolio-office projection
```

not:

```text
Organization owner role
→ Principal
→ institution truth
```

## Projection boundary

A Personal Atlas portfolio-office record may guide:

- the Person's attention;
- Principal/Personal clock arbitration;
- portfolio review;
- strategic planning;
- identification of a capital need or opportunity.

It does **not**, by itself:

- establish a canonical Reality relationship;
- establish an institutional responsibility;
- establish a durable canonical operating function;
- assign Company Work;
- spend or transfer money;
- approve a capital request;
- allocate capital;
- make a scorecard canonical for an institution;
- grant the Person authority over the referenced business.

Canonical promotion requires a separate governed operation with explicit jurisdiction.

## Compatibility storage

The existing tables retain their Principal-era names and columns during migration. The Personal Atlas API resolves exactly one legacy Principal storage carrier only after establishing the canonical Reality Person and active native Personal Atlas.

The following old browser APIs are compatibility aliases to the Personal Atlas membrane:

- `principal_upsert_owner_obligation_api_v1`;
- `principal_upsert_portfolio_thesis_api_v1`;
- `principal_upsert_attention_policy_api_v1`;
- `principal_upsert_operating_function_api_v1`;
- `principal_upsert_great_game_scorecard_api_v1`;
- `principal_upsert_capital_request_api_v1`;
- `principal_upsert_investment_opportunity_api_v1`.

This prevents stale callers from recreating Principal-as-identity.

## Existing data

At cutover, Lex had two existing owner-obligation rows and no rows in the other six authoring classes.

Those two rows are preserved unchanged. They remain Personal Atlas planning/obligation projections associated with the existing Elm portfolio unit. They are not converted into Reality authority or institutional ownership claims.

## Unified membrane

`atlas.personal_portfolio_office_author_self_api_v1(text,jsonb)` is the canonical authenticated authoring membrane for these projection classes.

The operation kind is explicit and limited to:

- `owner_obligation`;
- `portfolio_thesis`;
- `attention_policy`;
- `operating_function`;
- `great_game_scorecard`;
- `capital_request`;
- `investment_opportunity`.

Every stored row receives provenance that identifies the Reality Person, Personal Atlas, legacy-storage boundary, and non-canonical projection status.

## Acceptance

This cutover is accepted only when:

1. the active application authoring route requires Reality Person + Personal Atlas, not Organization owner membership;
2. it calls the unified Personal Atlas authoring membrane;
3. the new membrane contains no `current_principal_id_v1`, Organization Membership, or farm-owner identity gate;
4. all seven legacy Principal-named authoring APIs are compatibility aliases;
5. the seven write classes succeed in a rolled-back production proof;
6. proof rows do not persist;
7. no existing owner-obligation row is rewritten merely by introducing the new membrane.

## Promotion rule

Personal Atlas projection is not Reality establishment.

If Atlas later needs a modeled operating function, thesis, capital claim, or other projection to become canonical institutional truth, promotion must name:

- the source projection;
- the Reality Entity or domain jurisdiction;
- the responsibility relation authorizing promotion;
- the exact operation being performed;
- the evidence/provenance preserved;
- the resulting canonical relation or record.

No projection promotes itself.
