# Atlas Institutional Conversation Visibility v1

## Problem

Endpoint capability alone is too coarse for institutional communications.

A member may legitimately be allowed to see an organization's general Facebook, email, or social endpoint while a particular conversation on that endpoint is legal, HR, Principal-private, financial, or otherwise intentionally restricted.

Hiding a conversation only in the inbox UI would not be authority. The same membership could still act on a known conversation id through claim, handoff, attention, or outbound APIs.

## Model

Conversation visibility is Atlas-owned institutional authority.

`institutional_conversation_visibility_policies` stores the conversation policy:

- `endpoint` — ordinary endpoint view capability governs.
- `restricted` — an active non-owner membership requires both endpoint view capability and an explicit conversation view grant.

No policy row is equivalent to `endpoint`, preserving existing behavior.

Active organization owners remain able to see restricted conversations. This prevents a member from using a privacy setting to hide institutional evidence from the organization's owner.

`institutional_conversation_view_grants` stores explicit membership grants for restricted conversations. A grant does not create endpoint access and does not create responsibility.

## Authority to restrict

The v1 setter is owner-only. It may restrict a conversation and name allowed active organization memberships, or restore ordinary endpoint visibility.

This is intentionally narrower than allowing every endpoint admin to create hidden sub-inboxes. Broader delegation can be added later as an explicit governed capability.

## Enforcement

Visibility is enforced at more than presentation:

- shared inbox reads filter conversations through the conversation visibility helper;
- conversation detail reads fail closed without conversation view authority;
- attention events cannot be written for a hidden conversation;
- outbound operations cannot be initiated by a membership that cannot view the conversation;
- response events reject actors or handoff targets that cannot view the conversation;
- active responsibility cannot be allocated to a membership that cannot view the conversation.

Tightening visibility also fails closed if it would hide an active responsible assignment. Endpoint view-capability revocation/deletion likewise cannot strand an active responsible membership on restricted work.

## Truth boundaries

Visibility is not sensitivity inference.

Atlas v1 does not inspect content and declare a conversation "legal," "HR," "private," or "financial." It provides the durable authority model needed for an owner, governed routing rule, or later reviewed classifier to restrict a conversation without confusing inference with institutional truth.

Visibility does not:

- delete provider evidence;
- change provider custody;
- mark anything read;
- claim responsibility;
- hand off responsibility;
- classify message importance;
- grant endpoint access;
- imply that non-granted members are untrusted.

## Deployment boundary

Source candidate only. No production mutation, provider deployment, real account connection, Atlas application change, or Vercel deployment is performed by this candidate.
