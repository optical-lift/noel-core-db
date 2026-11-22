-- Protected current-schema signed clone after exact source-only migration.
-- Does NOT establish external farm-atlas deployed route discontinuation; that
-- is a separate blocking approval gate before any live release.
DO $verify_legacy_farm_invite_retirement$
BEGIN
  IF to_regclass('atlas.farm_membership_invites') IS NOT NULL
    OR to_regprocedure('atlas.accept_membership_invite_v1(uuid)') IS NOT NULL
    OR to_regprocedure('atlas.owner_prepare_membership_invite_v1(uuid,text,text,text,text)') IS NOT NULL
    OR to_regprocedure('atlas.owner_get_membership_invite_v1(uuid,uuid)') IS NOT NULL
    OR to_regprocedure('atlas.owner_mark_membership_invite_error_v1(uuid,uuid,text)') IS NOT NULL
    OR to_regprocedure('atlas.owner_mark_membership_invite_sent_v1(uuid,uuid,uuid)') IS NOT NULL
    OR to_regprocedure('atlas.owner_revoke_membership_invite_v1(uuid,uuid)') IS NOT NULL
    OR to_regprocedure('atlas.pending_membership_invite_for_current_user_v1(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'Legacy farm-invitation SQL authority remains';
  END IF;
  IF to_regprocedure('atlas.owner_list_farm_members_v1(uuid)') IS NULL
    OR to_regclass('atlas.farm_memberships') IS NULL
    OR to_regclass('atlas.organization_access_invitations') IS NULL
    OR to_regclass('atlas.organization_memberships') IS NULL
    OR to_regclass('atlas.work_items') IS NULL
    OR to_regclass('atlas.tasks') IS NULL THEN
    RAISE EXCEPTION 'Original member-list or unrelated canonical data removed';
  END IF;
END $verify_legacy_farm_invite_retirement$;
