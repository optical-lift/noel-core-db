-- Disposable clone-only DML. C1 source fixture deliberately has no
-- Organization-owner membership: source-governed original text editing
-- requires both native root and effective owner Organization membership.
-- This membership belongs to the already seeded synthetic owner, never to
-- a real Elm Person or legacy employee account.
INSERT INTO atlas.organization_memberships(
    id,organization_id,user_id,role,active,person_id,permissions)
SELECT 'e5200000-0000-4000-8000-000000000a10'::uuid,
       'e5200000-0000-4000-8000-000000000801'::uuid,
       'e5200000-0000-4000-8000-000000000001'::uuid,
       'owner',true,
       'e5200000-0000-4000-8000-000000000101'::uuid,
       '{}'::jsonb
WHERE NOT EXISTS (
    SELECT 1 FROM atlas.organization_memberships m
    WHERE m.organization_id='e5200000-0000-4000-8000-000000000801'::uuid
      AND m.person_id='e5200000-0000-4000-8000-000000000101'::uuid
      AND m.role='owner' AND m.active);
