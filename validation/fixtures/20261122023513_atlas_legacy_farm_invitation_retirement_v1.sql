-- HELD CANDIDATE: additional synthetic data setup is unnecessary.
-- The exact live source table must be EMPTY. The protected original C1
-- fixture and all-Atlas row-fingerprint verification are separate gates.
SELECT 1/(CASE WHEN
  to_regclass('atlas.farm_membership_invites') IS NOT NULL
  AND (SELECT count(*) FROM atlas.farm_membership_invites)=0
  AND to_regprocedure('atlas.owner_list_farm_members_v1(uuid)') IS NOT NULL
  AND to_regprocedure('atlas.accept_membership_invite_v1(uuid)') IS NOT NULL
  AND to_regclass('atlas.organization_memberships') IS NOT NULL
  THEN 1 ELSE 0 END) AS original_invitation_retirement_fixture;
