# Atlas Identity Resolution Engine v1

## Purpose

Atlas now has Ledger-scoped source connections, source party records, canonical Shared Intelligence entities, and the Evidence + Disclosure membrane. This kernel supplies the missing resolver between them.

The resolver must answer:

```text
Does this new source record describe a canonical party Atlas already knows?
```

without turning private identifiers into a cross-Ledger directory.

## Two match channels

### Shared-evidence lookup

A Ledger-private source record may contribute a normalized identifier such as an email, phone, website, government registration number, social URL, or address. The normalized value stays in that Ledger's source-signal table.

The resolver may compare it only against Shared Intelligence evidence claims whose permitted uses include `identity_resolution`.

It does not compare cleartext private identifiers directly against other Ledgers.

### Private blind match

For identifiers that should support identity continuity without becoming shared/displayable, the connector or secret layer computes an opaque keyed token before writing to Postgres.

Required pattern:

```text
normalize(identifier)
        ↓
HMAC-SHA-256(versioned server secret, normalized value)
        ↓
opaque blind token
```

A plain SHA/hash of an email or phone is not sufficient because low-entropy identifiers can be dictionary-attacked.

The HMAC secret is not stored in Atlas tables, source payloads, client code, or ordinary application configuration exposed to users. Tokens are versioned so keys may rotate.

`local_intel.entity_private_match_tokens` maps an opaque token to a canonical entity. It is resolver-only state, not directory evidence.

The resolver may answer **same canonical party** from that token. It must not reveal:

- the original private identifier;
- which other Ledger supplied it;
- how many Ledgers know it;
- another Ledger's source record or notes.

## Source signals

`atlas.ledger_source_party_identity_signals` contains the identity signals extracted from one Ledger-private source record.

Each signal is either:

- `shared_evidence_lookup` — stores a Ledger-private normalized value that may only be matched against Shared Intelligence evidence;
- `private_blind_match` — stores only the opaque blind token.

Signal kinds are evaluated only when enabled by `atlas.identity_resolution_signal_policies`. Adapters do not get to invent their own confidence by writing arbitrary scores.

## Configurable resolver policy

`atlas.identity_resolution_policies` controls:

- automatic-resolution threshold;
- human-review threshold;
- ambiguity margin.

`atlas.identity_resolution_signal_policies` controls signal weights by identifier kind and match channel.

These are explicit tuning data rather than hard-coded assumptions in each connector.

## Resolution case

Evaluation creates a Ledger-private `atlas.ledger_source_party_resolution_cases` row and zero or more ranked `..._candidates`.

Case states:

- `already_resolved`
- `auto_resolvable`
- `needs_review`
- `new_candidate`
- `resolved`
- `rejected`
- `superseded`

Automatic resolution is allowed only when the top candidate exceeds the auto threshold and is separated from the next candidate by the configured ambiguity margin.

Otherwise Atlas preserves the ambiguity rather than creating a convenience duplicate or silently choosing a person.

## Human confirmation teaches the resolver

`atlas.commit_ledger_source_party_resolution_case_service_v1` commits a selected candidate through the existing source-party resolution service.

When a confirmed/resolved source record carries private blind signals, Atlas attempts to associate those tokens with the selected canonical entity.

If a token is already associated with another canonical entity, Atlas does not move the token or expose the other Ledger. It creates a resolver-level token conflict between the two canonical identities for later identity/merge review.

Thus:

```text
human says: yes, this is Bob
        ↓
source record resolves to canonical Bob
        ↓
private blind identifier can recognize Bob next time
```

without promoting the identifier into public Shared Intelligence.

## Candidate scoring

v1 combines distinct matched signals with a probabilistic-union score:

```text
score = 1 - product(1 - configured_signal_weight)
```

This rewards independent corroboration while capping the result at 1.0.

The result is resolution evidence, not a claim that identity is mathematically certain.

## Privacy rule

Candidate/read services return canonical identity candidates and safe match categories such as `shared_evidence_lookup` or `private_blind_match`.

They do not return the blind token, another Ledger's source record, or hidden Shared Intelligence evidence values.

## Core law

```text
match widely
disclose narrowly
preserve ambiguity
remember confirmed identity
never turn private identifiers into a directory
```
