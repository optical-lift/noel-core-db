# Atlas Organization Occurrence–Relationship Links v1

## Purpose

Atlas needs a first-class way to say:

> This Organization's relationship to this canonical person/business/place is relevant to this canonical occurrence in one or more roles.

Examples include:

- vendor
- sponsor
- instructor
- host partner
- recommended nearby business
- participating merchant
- resource provider
- photographer
- caterer
- outreach candidate

The link is Organization-private. It must not duplicate either side.

## Identity boundaries

The two identity sides already exist:

```text
Shared Intelligence canonical entity
        ↓
Atlas external_relationship

Shared Intelligence canonical occurrence
        ↓
Atlas organization_occurrence_binding
```

The new link is:

```text
atlas.organization_occurrence_relationship_links
```

It joins the existing Organization-scoped relationship and occurrence binding.

Therefore:

- the business/person/place is not copied into an event table;
- the occurrence is not copied into a business table;
- event-specific role/state belongs to the Organization link.

## Role and workflow state

One link can carry multiple normalized `role_keys`.

Examples:

```text
vendor
sponsor
instructor
participating_merchant
recommended_nearby
resource_provider
```

`engagement_state` is Organization-owned workflow state. It is an open normalized key rather than a closed global vocabulary so different Organizations can use lawful workflow terms such as:

```text
candidate
invited
interested
confirmed
declined
completed
```

This workflow state does not become Shared Intelligence truth.

## Calendar display state

The link has explicit `calendar_display_state`:

- `hidden`
- `eligible`
- `published`

A discovered or invited business is therefore not accidentally published merely because it is linked to the occurrence.

Only `published` links appear in the combined calendar temporal projection.

Public presentation fields are separate from private workflow:

- `public_label`
- `public_note`
- `display_order`

## Interaction history

`atlas.external_relationship_interactions` gains an optional `occurrence_relationship_link_id`.

That allows an email/call/text to remain ordinary append-only Elm relationship history while also saying which event-specific relationship it concerned.

Example:

```text
canonical business
    ↓
Elm external_relationship
    ↓
Oct. 30 Trunk or Treat link
      role: vendor
      engagement: invited
      calendar display: hidden
    ↓
interaction:
      kind: event_outreach
      channel: email
      occurred_at: ...
      occurrence_relationship_link_id: ...
```

If the business later confirms, the same link may become:

```text
engagement_state = confirmed
calendar_display_state = published
```

No new business identity or event identity is created.

## Read paths

Atlas exposes:

- an occurrence relationship detail service for internal planning/workflow;
- published linked entities inside the combined temporal projection for calendar rendering.

The combined calendar projection only exposes canonical public entity fields plus Organization-approved public label/note/roles. It does not expose private contact history.

## Core rule

```text
one canonical entity
        +
one canonical occurrence
        ↓
one Organization-private occurrence↔relationship link
        ↓
roles + workflow + display policy + interaction history
```

This is the governed path for event vendors, sponsors, partners, instructors, participating businesses, and similar event-specific relationships.
